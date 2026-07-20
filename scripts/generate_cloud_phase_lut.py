#!/usr/bin/env python3
"""Generate the cloud scattering phase LUT from OPAC cloud data.

The output is a little-endian 512x3 half-float texture. `--format rgb`
stores log2 of the normalized linear Rec.2020 phase function in RGB16F;
`--format r` stores its Rec.2020 luminance in R16F. Rows are:

    0: cumulus (cucc00)
    1: stratus (stco00)
    2: cirrus  (cir200)

OPAC reference: https://cds-espri.ipsl.upmc.fr/etherTypo/?id=989&L=0
"""

from __future__ import annotations

import argparse
import bisect
import csv
import heapq
import math
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


LUT_WIDTH = 512
LUT_HEIGHT = 3
PHASE_FLOOR = 2.0**-24
MAPPING_GRID_SIZE = 65537
MAPPING_NODE_COUNT = LUT_WIDTH

CIRRUS_ROUGHNESS_DEGREES = 1.5
CIRRUS_ICE_FEATURE_WEIGHT = 0.9
CIRRUS_LEGENDRE_ORDER = 256
CIRRUS_BACK_LOBE_WEIGHT = 0.04
CIRRUS_BACK_LOBE_G = -0.25

XYZ_TO_REC2020 = (
    (1.7166511880, -0.3556707838, -0.2533662814),
    (-0.6666843518, 1.6164812366, 0.0157685458),
    (0.0176398574, -0.0427706133, 0.9421031212),
)

REC2020_LUMA = (0.2627002120, 0.6779980715, 0.0593017165)

GAUSS_X = (
    -0.9602898564975363,
    -0.7966664774136267,
    -0.5255324099163290,
    -0.1834346424956498,
    0.1834346424956498,
    0.5255324099163290,
    0.7966664774136267,
    0.9602898564975363,
)

GAUSS_W = (
    0.1012285362903763,
    0.2223810344533745,
    0.3137066458778873,
    0.3626837833783620,
    0.3626837833783620,
    0.3137066458778873,
    0.2223810344533745,
    0.1012285362903763,
)


@dataclass(frozen=True)
class CIESample:
    wavelength_um: float
    x_bar: float
    y_bar: float
    z_bar: float
    illuminant: float


@dataclass(frozen=True)
class CloudSource:
    name: str
    filename: str


@dataclass(frozen=True)
class PhaseMapping:
    normalized_angles: tuple[float, ...]
    texture_coordinates: tuple[float, ...]
    reference_error: float

    def coordinate(self, normalized_angle: float) -> float:
        return self._interpolate(
            self.normalized_angles,
            self.texture_coordinates,
            min(max(normalized_angle, 0.0), 1.0),
        )

    def angle(self, texture_coordinate: float) -> float:
        return self._interpolate(
            self.texture_coordinates,
            self.normalized_angles,
            min(max(texture_coordinate, 0.0), 1.0),
        )

    @staticmethod
    def _interpolate(xs: Sequence[float], ys: Sequence[float], x: float) -> float:
        index = min(max(bisect.bisect_right(xs, x) - 1, 0), len(xs) - 2)
        fraction = (x - xs[index]) / (xs[index + 1] - xs[index])
        return ys[index] + (ys[index + 1] - ys[index]) * fraction


CLOUD_SOURCES = (
    CloudSource("cumulus", "cucc00.txt"),
    CloudSource("stratus", "stco00.txt"),
    CloudSource("cirrus", "cir200.txt"),
)


class Pchip:
    def __init__(self, xs: Sequence[float], ys: Sequence[float]) -> None:
        if len(xs) != len(ys) or len(xs) < 2:
            raise ValueError("PCHIP needs equally sized arrays with at least two points")
        if any(a >= b for a, b in zip(xs, xs[1:])):
            raise ValueError("PCHIP x coordinates must be strictly increasing")

        self.xs = tuple(xs)
        self.ys = tuple(ys)
        self.ds = tuple(_pchip_slopes(xs, ys))

    def __call__(self, x: float) -> float:
        if x <= self.xs[0]:
            return self.ys[0]
        if x >= self.xs[-1]:
            return self.ys[-1]

        lo = 0
        hi = len(self.xs) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if self.xs[mid] <= x:
                lo = mid
            else:
                hi = mid

        h = self.xs[lo + 1] - self.xs[lo]
        t = (x - self.xs[lo]) / h
        t2 = t * t
        t3 = t2 * t
        h00 = 2.0 * t3 - 3.0 * t2 + 1.0
        h10 = t3 - 2.0 * t2 + t
        h01 = -2.0 * t3 + 3.0 * t2
        h11 = t3 - t2
        return (
            h00 * self.ys[lo]
            + h10 * h * self.ds[lo]
            + h01 * self.ys[lo + 1]
            + h11 * h * self.ds[lo + 1]
        )


def _pchip_slopes(xs: Sequence[float], ys: Sequence[float]) -> list[float]:
    count = len(xs)
    if count == 2:
        slope = (ys[1] - ys[0]) / (xs[1] - xs[0])
        return [slope, slope]

    hs = [xs[i + 1] - xs[i] for i in range(count - 1)]
    secants = [(ys[i + 1] - ys[i]) / hs[i] for i in range(count - 1)]
    slopes = [0.0] * count

    for i in range(1, count - 1):
        left = secants[i - 1]
        right = secants[i]
        if left == 0.0 or right == 0.0 or left * right < 0.0:
            slopes[i] = 0.0
            continue
        w1 = 2.0 * hs[i] + hs[i - 1]
        w2 = hs[i] + 2.0 * hs[i - 1]
        slopes[i] = (w1 + w2) / (w1 / left + w2 / right)

    slopes[0] = _pchip_endpoint(hs[0], hs[1], secants[0], secants[1])
    slopes[-1] = _pchip_endpoint(hs[-1], hs[-2], secants[-1], secants[-2])
    return slopes


def _pchip_endpoint(h0: float, h1: float, m0: float, m1: float) -> float:
    slope = ((2.0 * h0 + h1) * m0 - h0 * m1) / (h0 + h1)
    if slope * m0 <= 0.0:
        return 0.0
    if m0 * m1 < 0.0 and abs(slope) > abs(3.0 * m0):
        return 3.0 * m0
    return slope


def load_cie_samples(cmf_path: Path, illuminant_path: Path) -> list[CIESample]:
    cmf: dict[int, tuple[float, float, float]] = {}
    with cmf_path.open("r", encoding="utf-8-sig", newline="") as stream:
        for row in csv.reader(stream):
            if len(row) >= 4:
                cmf[int(float(row[0]))] = (float(row[1]), float(row[2]), float(row[3]))

    illuminant: dict[int, float] = {}
    with illuminant_path.open("r", encoding="utf-8-sig", newline="") as stream:
        for row in csv.reader(stream):
            if len(row) >= 2:
                illuminant[int(float(row[0]))] = float(row[1])

    wavelengths = sorted(cmf.keys() & illuminant.keys())
    if len(wavelengths) < 2:
        raise ValueError("CIE CMF and illuminant wavelength ranges do not overlap")
    return [
        CIESample(wavelength * 1e-3, *cmf[wavelength], illuminant[wavelength])
        for wavelength in wavelengths
    ]


def parse_opac(path: Path) -> tuple[list[float], list[list[float]], list[float]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    optical_index = lines.index("# optical parameters:")
    phase_index = lines.index("# volume phase function [1/km]:")
    optical_rows: list[list[float]] = []
    for line in lines[optical_index + 6 : phase_index]:
        values = _float_fields(line.lstrip("# "))
        if len(values) >= 6:
            optical_rows.append(values)

    phase_wavelengths = _float_fields(lines[phase_index + 5].split("|", 1)[1])
    phase_angles: list[float] = []
    volume_phase_rows: list[list[float]] = []
    for line in lines[phase_index + 7 :]:
        values = _float_fields(line)
        if not values:
            continue
        phase_angles.append(math.radians(values[0]))
        volume_phase_rows.append(values[1:])

    if not optical_rows or not phase_angles:
        raise ValueError(f"Incomplete OPAC data in {path}")
    if any(len(row) != len(phase_wavelengths) for row in volume_phase_rows):
        raise ValueError(f"Phase wavelength count mismatch in {path}")

    optical_wavelengths = [row[0] for row in optical_rows]
    optical_scattering = [max(row[2], 1e-30) for row in optical_rows]
    scattering_curve = Pchip(optical_wavelengths, [math.log(v) for v in optical_scattering])
    scattering = [math.exp(scattering_curve(wavelength)) for wavelength in phase_wavelengths]

    normalized_spectra = [
        [max(value / scattering[i], 1e-30) for i, value in enumerate(row)]
        for row in volume_phase_rows
    ]
    return phase_angles, normalized_spectra, phase_wavelengths


def _float_fields(text: str) -> list[float]:
    fields: list[float] = []
    for token in text.replace("|", " ").split():
        try:
            fields.append(float(token))
        except ValueError:
            pass
    return fields


def color_match_phase(
    spectra: Sequence[Sequence[float]],
    wavelengths: Sequence[float],
    cie: Sequence[CIESample],
) -> list[tuple[float, float, float]]:
    min_wavelength = wavelengths[0]
    max_wavelength = wavelengths[-1]
    visible = [s for s in cie if min_wavelength <= s.wavelength_um <= max_wavelength]
    if len(visible) < 2:
        raise ValueError("OPAC and CIE wavelength ranges do not overlap")

    integration_weights = _trapezoid_point_weights([s.wavelength_um for s in visible])
    white_y = sum(
        sample.y_bar * sample.illuminant * weight
        for sample, weight in zip(visible, integration_weights)
    )

    result: list[tuple[float, float, float]] = []
    for spectrum in spectra:
        spectral_curve = Pchip(wavelengths, [math.log(max(v, 1e-30)) for v in spectrum])
        xyz = [0.0, 0.0, 0.0]
        for sample, weight in zip(visible, integration_weights):
            phase = math.exp(spectral_curve(sample.wavelength_um))
            scale = phase * sample.illuminant * weight / white_y
            xyz[0] += scale * sample.x_bar
            xyz[1] += scale * sample.y_bar
            xyz[2] += scale * sample.z_bar

        rgb = tuple(
            max(sum(row[i] * xyz[i] for i in range(3)), PHASE_FLOOR)
            for row in XYZ_TO_REC2020
        )
        result.append(rgb)
    return result


def _trapezoid_point_weights(xs: Sequence[float]) -> list[float]:
    weights = [0.0] * len(xs)
    weights[0] = 0.5 * (xs[1] - xs[0])
    weights[-1] = 0.5 * (xs[-1] - xs[-2])
    for i in range(1, len(xs) - 1):
        weights[i] = 0.5 * (xs[i + 1] - xs[i - 1])
    return weights


def build_phase_curves(
    angles: Sequence[float], rgb_rows: Sequence[Sequence[float]]
) -> tuple[Pchip, Pchip, Pchip]:
    curves: list[Pchip] = []
    for channel in range(3):
        logs = [math.log(max(rgb[channel], PHASE_FLOOR)) for rgb in rgb_rows]
        raw_curve = Pchip(angles, logs)
        integral = integrate_sphere(raw_curve, angles)
        curves.append(Pchip(angles, [value - math.log(integral) for value in logs]))
    return curves[0], curves[1], curves[2]


def integrate_sphere(log_curve: Pchip, knots: Sequence[float]) -> float:
    integral = 0.0
    for left, right in zip(knots, knots[1:]):
        center = 0.5 * (left + right)
        radius = 0.5 * (right - left)
        for x, weight in zip(GAUSS_X, GAUSS_W):
            theta = center + radius * x
            integral += radius * weight * math.exp(log_curve(theta)) * math.sin(theta)
    return 2.0 * math.pi * integral


def legendre_moments(
    log_curve: Pchip, knots: Sequence[float], order: int
) -> list[float]:
    moments = [0.0] * (order + 1)
    for left, right in zip(knots, knots[1:]):
        center = 0.5 * (left + right)
        radius = 0.5 * (right - left)
        for x, gaussian_weight in zip(GAUSS_X, GAUSS_W):
            theta = center + radius * x
            mu = math.cos(theta)
            weight = (
                2.0
                * math.pi
                * radius
                * gaussian_weight
                * math.sin(theta)
                * math.exp(log_curve(theta))
            )
            p0 = 1.0
            moments[0] += weight
            if order == 0:
                continue
            p1 = mu
            moments[1] += weight * p1
            for degree in range(2, order + 1):
                p2 = (
                    (2.0 * degree - 1.0) * mu * p1 - (degree - 1.0) * p0
                ) / degree
                moments[degree] += weight * p2
                p0, p1 = p1, p2
    return moments


def reconstruct_legendre_phase(moments: Sequence[float], mu: float) -> float:
    result = moments[0]
    if len(moments) == 1:
        return result * (0.25 / math.pi)
    p0 = 1.0
    p1 = mu
    result += 3.0 * moments[1] * p1
    for degree in range(2, len(moments)):
        p2 = ((2.0 * degree - 1.0) * mu * p1 - (degree - 1.0) * p0) / degree
        result += (2.0 * degree + 1.0) * moments[degree] * p2
        p0, p1 = p1, p2
    return result * (0.25 / math.pi)


def henyey_greenstein_phase(mu: float, asymmetry: float) -> float:
    denominator = 1.0 + asymmetry * asymmetry - 2.0 * asymmetry * mu
    return (
        (0.25 / math.pi)
        * (1.0 - asymmetry * asymmetry)
        / (denominator * math.sqrt(denominator))
    )


def build_typical_cirrus_curves(
    base_curves: Sequence[Pchip], knots: Sequence[float]
) -> tuple[Pchip, Pchip, Pchip]:
    sigma = math.radians(CIRRUS_ROUGHNESS_DEGREES)
    output: list[Pchip] = []

    for base_curve in base_curves:
        moments = legendre_moments(base_curve, knots, CIRRUS_LEGENDRE_ORDER)
        target_g = moments[1] / moments[0]

        # Keep normalization and g unchanged while damping the higher moments
        # that encode pristine-crystal halos and very narrow angular peaks.
        rough_moments = moments.copy()
        for degree in range(2, len(rough_moments)):
            exponent = -0.5 * (degree * (degree + 1.0) - 2.0) * sigma * sigma
            rough_moments[degree] *= math.exp(exponent)

        forward_g = (
            target_g - CIRRUS_BACK_LOBE_WEIGHT * CIRRUS_BACK_LOBE_G
        ) / (1.0 - CIRRUS_BACK_LOBE_WEIGHT)
        forward_g = min(max(forward_g, -0.98), 0.98)

        values: list[float] = []
        for theta in knots:
            mu = math.cos(theta)
            rough_phase = max(
                reconstruct_legendre_phase(rough_moments, mu),
                PHASE_FLOOR,
            )
            smooth_phase = (
                (1.0 - CIRRUS_BACK_LOBE_WEIGHT)
                * henyey_greenstein_phase(mu, forward_g)
                + CIRRUS_BACK_LOBE_WEIGHT
                * henyey_greenstein_phase(mu, CIRRUS_BACK_LOBE_G)
            )
            values.append(
                CIRRUS_ICE_FEATURE_WEIGHT * rough_phase
                + (1.0 - CIRRUS_ICE_FEATURE_WEIGHT) * smooth_phase
            )

        curve = Pchip(knots, [math.log(max(value, PHASE_FLOOR)) for value in values])
        integral = integrate_sphere(curve, knots)
        output.append(Pchip(knots, [value - math.log(integral) for value in curve.ys]))

    return output[0], output[1], output[2]


def build_phase_mapping(phase_sets: Sequence[Sequence[Pchip]]) -> PhaseMapping:
    # Greedily split the interval with the largest log-domain interpolation
    # error across every cloud type, RGB channel, and Rec.2020 luminance.
    normalized_angles = [i / (MAPPING_GRID_SIZE - 1) for i in range(MAPPING_GRID_SIZE)]
    log2e = 1.0 / math.log(2.0)
    reference_curves: list[list[float]] = []

    for curves in phase_sets:
        rgb_logs = [
            [curve(math.pi * angle) * log2e for angle in normalized_angles]
            for curve in curves
        ]
        reference_curves.extend(rgb_logs)
        reference_curves.append(
            [
                math.log2(
                    phase_luma(tuple(2.0 ** rgb_logs[channel][i] for channel in range(3)))
                )
                for i in range(MAPPING_GRID_SIZE)
            ]
        )

    def interval_error(start: int, end: int) -> tuple[float, int]:
        if end - start <= 1:
            return 0.0, start
        max_error = 0.0
        split = (start + end) // 2
        inverse_span = 1.0 / (end - start)
        for sample in range(start + 1, end):
            fraction = (sample - start) * inverse_span
            for curve in reference_curves:
                interpolated = curve[start] + (curve[end] - curve[start]) * fraction
                error = abs(interpolated - curve[sample])
                if error > max_error:
                    max_error = error
                    split = sample
        return max_error, split

    error, split = interval_error(0, MAPPING_GRID_SIZE - 1)
    intervals = [(-error, 0, MAPPING_GRID_SIZE - 1, split)]
    node_indices = {0, MAPPING_GRID_SIZE - 1}

    for _ in range(MAPPING_NODE_COUNT - 2):
        _, start, end, split = heapq.heappop(intervals)
        node_indices.add(split)
        for child_start, child_end in ((start, split), (split, end)):
            if child_end - child_start <= 1:
                continue
            error, child_split = interval_error(child_start, child_end)
            heapq.heappush(
                intervals,
                (-error, child_start, child_end, child_split),
            )

    sorted_indices = sorted(node_indices)
    angles = tuple(normalized_angles[index] for index in sorted_indices)
    coordinates = tuple(i / (MAPPING_NODE_COUNT - 1) for i in range(MAPPING_NODE_COUNT))
    return PhaseMapping(angles, coordinates, -intervals[0][0])


def _glsl_float(value: float) -> str:
    result = f"{value:.10g}"
    if "." not in result and "e" not in result:
        result += ".0"
    return result


def write_mapping_glsl(path: Path, mapping: PhaseMapping) -> None:
    search_steps = math.ceil(math.log2(len(mapping.normalized_angles)))
    lines = [
        "#if !defined INCLUDE_CLOUDS_PHASE_LUT_MAPPING",
        "#define INCLUDE_CLOUDS_PHASE_LUT_MAPPING",
        "",
        f"const int cloudPhaseWarpKnotCount = {len(mapping.normalized_angles)};",
        f"const uint cloudPhaseWarpSearchSteps = {search_steps}u;",
        "const vec2 cloudPhaseWarpKnots[cloudPhaseWarpKnotCount] = vec2[](",
    ]
    for index, (angle, coordinate) in enumerate(
        zip(mapping.normalized_angles, mapping.texture_coordinates)
    ):
        suffix = "," if index + 1 < len(mapping.normalized_angles) else ""
        lines.append(
            f"\tvec2({_glsl_float(angle)}, {_glsl_float(coordinate)}){suffix}"
        )
    lines.extend((");", "", "#endif", ""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="ascii", newline="\n")


def phase_rgb(curves: Sequence[Pchip], theta: float) -> tuple[float, float, float]:
    return tuple(math.exp(curve(theta)) for curve in curves)


def phase_luma(rgb: Sequence[float]) -> float:
    return sum(value * weight for value, weight in zip(rgb, REC2020_LUMA))


def phase_luma_asymmetry(curves: Sequence[Pchip], knots: Sequence[float]) -> float:
    integral = 0.0
    first_moment = 0.0
    for left, right in zip(knots, knots[1:]):
        center = 0.5 * (left + right)
        radius = 0.5 * (right - left)
        for x, gaussian_weight in zip(GAUSS_X, GAUSS_W):
            theta = center + radius * x
            phase = phase_luma(phase_rgb(curves, theta))
            weight = 2.0 * math.pi * radius * gaussian_weight * math.sin(theta)
            integral += phase * weight
            first_moment += phase * math.cos(theta) * weight
    return first_moment / integral


def write_lut(
    path: Path,
    phase_sets: Sequence[Sequence[Pchip]],
    mapping: PhaseMapping,
    texture_format: str,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    format_string = "<3e" if texture_format == "rgb" else "<e"
    with path.open("wb") as stream:
        for curves in phase_sets:
            for pixel in range(LUT_WIDTH):
                u = pixel / (LUT_WIDTH - 1)
                theta = math.pi * mapping.angle(u)
                rgb = phase_rgb(curves, theta)
                encoded = (
                    tuple(math.log2(max(value, PHASE_FLOOR)) for value in rgb)
                    if texture_format == "rgb"
                    else (math.log2(max(phase_luma(rgb), PHASE_FLOOR)),)
                )
                stream.write(struct.pack(format_string, *encoded))


def validate_lut(
    path: Path,
    phase_sets: Sequence[Sequence[Pchip]],
    mapping: PhaseMapping,
    texture_format: str,
) -> None:
    channel_count = 3 if texture_format == "rgb" else 1
    expected_size = LUT_WIDTH * LUT_HEIGHT * channel_count * 2
    data = path.read_bytes()
    if len(data) != expected_size:
        raise ValueError(f"Expected {expected_size} bytes, got {len(data)}")

    format_string = "<3e" if channel_count == 3 else "<e"
    values = list(struct.iter_unpack(format_string, data))
    max_log_error = 0.0
    weighted_error_sum = 0.0
    weighted_sample_sum = 0.0
    integral_errors: list[float] = []

    for row, curves in enumerate(phase_sets):
        reconstructed_integrals = [0.0] * channel_count
        sample_count = MAPPING_GRID_SIZE
        step = math.pi / (sample_count - 1)
        previous_sample: tuple[float, ...] | None = None
        for sample in range(sample_count):
            theta = sample * step
            u = mapping.coordinate(theta / math.pi)
            x = u * (LUT_WIDTH - 1)
            x0 = min(int(x), LUT_WIDTH - 1)
            x1 = min(x0 + 1, LUT_WIDTH - 1)
            fraction = x - x0
            a = values[row * LUT_WIDTH + x0]
            b = values[row * LUT_WIDTH + x1]
            decoded = tuple(
                2.0 ** (a[c] + (b[c] - a[c]) * fraction) for c in range(channel_count)
            )
            reference_rgb = phase_rgb(curves, theta)
            reference = reference_rgb if channel_count == 3 else (phase_luma(reference_rgb),)
            sin_theta = math.sin(theta)
            for channel in range(channel_count):
                log_error = abs(math.log2(decoded[channel] / reference[channel]))
                max_log_error = max(max_log_error, log_error)
                weighted_error_sum += log_error * log_error * sin_theta
                weighted_sample_sum += sin_theta
            if previous_sample is not None:
                for channel in range(channel_count):
                    reconstructed_integrals[channel] += (
                        0.5
                        * step
                        * (
                            previous_sample[channel] * math.sin(theta - step)
                            + decoded[channel] * sin_theta
                        )
                    )
            previous_sample = decoded
        integral_errors.extend(abs(2.0 * math.pi * value - 1.0) for value in reconstructed_integrals)

    rms_log_error = math.sqrt(weighted_error_sum / weighted_sample_sum)
    format_name = "RGB16F" if channel_count == 3 else "R16F"
    print(f"size: {len(data)} bytes ({LUT_WIDTH}x{LUT_HEIGHT} {format_name})")
    print(f"weighted RMS log2 error: {rms_log_error:.6f} stops")
    print(f"maximum log2 error: {max_log_error:.6f} stops")
    print(f"maximum reconstructed integral error: {max(integral_errors):.6%}")


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    data_dir = Path(__file__).resolve().parent / "cloud_phase_data"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--opac-dir",
        type=Path,
        default=data_dir,
        help="Directory containing cir200.txt, cucc00.txt and stco00.txt",
    )
    parser.add_argument(
        "--cmf",
        type=Path,
        default=data_dir / "CIE_xyz_1931_2deg.csv",
        help="CIE XYZ 1931 2-degree color matching functions CSV",
    )
    parser.add_argument(
        "--illuminant",
        type=Path,
        default=data_dir / "CIE_std_illum_D65.csv",
        help="CIE standard illuminant spectral power distribution CSV",
    )
    parser.add_argument(
        "--format",
        dest="texture_format",
        choices=("r", "rgb"),
        default="r",
        help="LUT channels: r (R16F luminance) or rgb (RGB16F color)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=repo_root / "shaders" / "texture" / "cloud" / "CloudPhaseLut.bin",
    )
    parser.add_argument(
        "--mapping-output",
        type=Path,
        default=repo_root
        / "shaders"
        / "lib"
        / "atmosphere"
        / "clouds"
        / "PhaseLutMapping.glsl",
        help="Generated GLSL include containing the adaptive angle mapping",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    cie = load_cie_samples(args.cmf, args.illuminant)
    phase_sets: list[tuple[Pchip, Pchip, Pchip]] = []

    for source in CLOUD_SOURCES:
        angles, spectra, wavelengths = parse_opac(args.opac_dir / source.filename)
        rgb_rows = color_match_phase(spectra, wavelengths, cie)
        curves = build_phase_curves(angles, rgb_rows)
        if source.name == "cirrus":
            base_curves = curves
            curves = build_typical_cirrus_curves(base_curves, angles)
            base_g = phase_luma_asymmetry(base_curves, angles)
            filtered_g = phase_luma_asymmetry(curves, angles)
            print(
                f"cirrus filter: roughness={CIRRUS_ROUGHNESS_DEGREES:.2f} deg, "
                f"ice features={CIRRUS_ICE_FEATURE_WEIGHT:.0%}, "
                f"g={base_g:.6f}->{filtered_g:.6f}"
            )
            forward_before = phase_luma(phase_rgb(base_curves, 0.0))
            forward_after = phase_luma(phase_rgb(curves, 0.0))
            print(f"cirrus 0 deg phase: {forward_before:.6g}->{forward_after:.6g}")
            for feature_angle, side_angles in ((22.0, (18.0, 26.0)), (46.0, (42.0, 50.0))):
                center = math.radians(feature_angle)
                sides = tuple(math.radians(angle) for angle in side_angles)
                before_center = phase_luma(phase_rgb(base_curves, center))
                after_center = phase_luma(phase_rgb(curves, center))
                before_background = sum(
                    phase_luma(phase_rgb(base_curves, angle)) for angle in sides
                ) * 0.5
                after_background = sum(
                    phase_luma(phase_rgb(curves, angle)) for angle in sides
                ) * 0.5
                print(
                    f"cirrus {feature_angle:.0f} deg local contrast: "
                    f"{before_center / before_background:.3f}x->"
                    f"{after_center / after_background:.3f}x"
                )
        phase_sets.append(curves)
        maxima = tuple(max(math.exp(curve(angle)) for angle in angles) for curve in curves)
        print(f"{source.name}: peak Rec.2020 phase = {maxima}")

    mapping = build_phase_mapping(phase_sets)
    write_mapping_glsl(args.mapping_output, mapping)
    write_lut(args.output, phase_sets, mapping, args.texture_format)
    validate_lut(args.output, phase_sets, mapping, args.texture_format)
    print(
        f"mapping: {len(mapping.normalized_angles)} knots, "
        f"reference max error {mapping.reference_error:.6f} stops"
    )
    shader_mode = 1 if args.texture_format == "rgb" else 0
    print(f"shader setting: CLOUD_PHASE_LUT_COLORED {shader_mode}")
    print(f"wrote: {args.output}")


if __name__ == "__main__":
    main()
