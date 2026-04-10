//======// Constants //===========================================================================//

const float min_ev = -7.5;
const float max_ev = 5.5;
const float middle_grey = 0.18;

const float slope = 2.0;
const float toe_power = 3.0;
const float shoulder_power = 3.25;

const vec3 compression = vec3(0.1, 0.1, 0.15);
const vec3 rotation = vec3(2.0, -1.0, -3.0);

//======// AgX Minimal //=========================================================================//

// From https://iolite-engine.com/blog_posts/minimal_agx_implementation

// MIT License
//
// Copyright (c) 2024 Missing Deadlines (Benjamin Wrensch)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// All values used to derive this implementation are sourced from Troy’s initial AgX implementation/OCIO config file available here:
//   https://github.com/sobotka/AgX

// 0: Default, 1: Golden, 2: Punchy
#define AGX_LOOK 0 // [0 1 2]

// Mean error^2: 3.6705141e-06
vec3 agxDefaultContrastApprox_6th(vec3 x) {
    vec3 x2 = x * x;
    vec3 x4 = x2 * x2;

    return  + 15.5     * x4 * x2
            - 40.14    * x4 * x
            + 31.96    * x4
            - 6.868    * x2 * x
            + 0.4298   * x2
            + 0.1191   * x
            - 0.00232;
}

// Mean error^2: 1.85907662e-06
vec3 agxDefaultContrastApprox_7th(vec3 x) {
    vec3 x2 = x * x;
    vec3 x4 = x2 * x2;

    return - 17.86     * x4 * x2 * x
           + 78.01     * x4 * x2
           - 126.7     * x4 * x
           + 92.06     * x4
           - 28.72     * x2 * x
           + 4.361     * x2
           - 0.1718    * x
           + 0.002857;
}

vec3 agx(vec3 val) {
    const mat3 agx_mat = mat3(
    0.842479062253094, 0.0423282422610123, 0.0423756549057051,
    0.0784335999999992,  0.878468636469772,  0.0784336,
    0.0792237451477643, 0.0791661274605434, 0.879142973793104);

    // const float min_ev = -12.47393f;
    // const float max_ev = 4.026069f;

    // Input transform (inset)
    val = agx_mat * val;

    // Log2 space encoding
    val = clamp(log2(val * rcp(middle_grey)), min_ev, max_ev);
    val = (val - min_ev) * rcp(max_ev - min_ev);

    // Apply sigmoid function approximation
    val = agxDefaultContrastApprox_7th(val);

    return val;
}

vec3 agxEotf(vec3 val) {
    const mat3 agx_mat_inv = mat3(
    1.19687900512017, -0.0528968517574562, -0.0529716355144438,
    -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
    -0.0990297440797205, -0.0989611768448433, 1.15107367264116);

    // Inverse input transform (outset)
    val = agx_mat_inv * val;

    // sRGB IEC 61966-2-1 2.2 Exponent Reference EOTF Display
    // NOTE: We're linearizing the output here. Comment/adjust when
    // *not* using a sRGB render target
    val = pow(val, vec3(2.2));

    return val;
}

vec3 agxLook(vec3 val) {
    const vec3 lw = vec3(0.2126, 0.7152, 0.0722);
    float luma = dot(val, lw);

    #if AGX_LOOK == 0
        // Default
        const vec3 slope = vec3(1.0);
        const vec3 power = vec3(1.0);
        const float sat = 1.0;
    #elif AGX_LOOK == 1
        // Golden
        const vec3 slope = vec3(1.0, 0.9, 0.5);
        const vec3 power = vec3(0.8);
        const float sat = 0.8;
    #elif AGX_LOOK == 2
        // Punchy
        const vec3 slope = vec3(1.0);
        const vec3 power = vec3(1.35);
        const float sat = 1.4;
    #else
        // Custom
        const vec3 slope = vec3(1.0);
        const vec3 power = vec3(1.2);
        const float sat = 1.2;
    #endif

    // ASC CDL
    val = pow(val * slope, power);
    return luma + sat * (val - luma);
}

vec3 AgX_Minimal(vec3 value) {
    value = agx(value);
    value = agxLook(value); // Optional
    return agxEotf(value);
}

//======// AgX Full //============================================================================//

vec3 unproject(vec2 xy) {
    if (xy.y == 0.0) return vec3(0.0);

    float Y = 1.0;
    float X = xy.x / xy.y;
    float Z = (1.0 - xy.x - xy.y) / xy.y;

    return vec3(X, Y, Z);
}

mat3 primaries_to_matrix(vec2 xy_red, vec2 xy_green, vec2 xy_blue, vec2 xy_white) {
    vec3 XYZ_red = unproject(xy_red);
    vec3 XYZ_green = unproject(xy_green);
    vec3 XYZ_blue = unproject(xy_blue);

    vec3 XYZ_white = unproject(xy_white);

    mat3 temp = mat3(
                XYZ_red.x,	XYZ_green.x,	XYZ_blue.x,
                1.0,        1.0,            1.0,
                XYZ_red.z,	XYZ_green.z,	XYZ_blue.z);

    mat3 inv = inverse(temp);
    vec3 scale = XYZ_white * inv;

    return mat3(
        scale.x * XYZ_red.x, scale.y * XYZ_green.x,	scale.z * XYZ_blue.x,
        scale.x * XYZ_red.y, scale.y * XYZ_green.y,	scale.z * XYZ_blue.y,
        scale.x * XYZ_red.z, scale.y * XYZ_green.z,	scale.z * XYZ_blue.z);
}

float RotationToSlide(vec2 primary, vec2 neighborA, vec2 neighborB, float angle) {
	vec2 neighbor = angle >= 0.0 ? neighborA : neighborB;

	float distance_to_neighbor = distance(primary, neighbor);
	float distance_to_center = length(primary);

	float side = sin(angle / 180.0 * PI) * distance_to_center;

	return side / distance_to_neighbor;
}

vec2 SlidePrimary(vec2 primary, vec2 neighborA, vec2 neighborB, float amount) {
	return mix(primary, amount >= 0.0 ? neighborA : neighborB, saturate(abs(amount)));
}

mat3 ComputeCompressionMatrix(vec2 xyR, vec2 xyG, vec2 xyB, vec2 xyW) {
	vec2 offsetR = xyR - xyW;
	vec2 offsetG = xyG - xyW;
	vec2 offsetB = xyB - xyW;

	vec3 slide = vec3(0.0);
	slide.r = RotationToSlide(offsetR, offsetB, offsetG, rotation.r);
	slide.g = RotationToSlide(offsetG, offsetR, offsetB, rotation.g);
	slide.b = RotationToSlide(offsetB, offsetG, offsetR, rotation.b);

	vec3 scale_factor = 1.0 / (1.0 - compression);

	vec2 R = (SlidePrimary(offsetR, offsetB, offsetG, slide.r) * scale_factor.r) + xyW;
	vec2 G = (SlidePrimary(offsetG, offsetR, offsetB, slide.g) * scale_factor.g) + xyW;
	vec2 B = (SlidePrimary(offsetB, offsetG, offsetR, slide.b) * scale_factor.b) + xyW;
	vec2 W = xyW;

	return primaries_to_matrix(R, G, B, W);
}

vec3 open_domain_to_normalized_log2(vec3 in_od, float minimum_ev, float maximum_ev) {
    float total_exposure = maximum_ev - minimum_ev;

    vec3 output_log = clamp(log2(in_od * rcp(middle_grey)), minimum_ev, maximum_ev);

    return (output_log - minimum_ev) * rcp(total_exposure);
}

float equation_scale(float x_pivot, float y_pivot, float slope_pivot, float power) {
    return pow(pow((slope_pivot * x_pivot), -power) * (pow((slope_pivot * (x_pivot / y_pivot)), power) - 1.0), -1.0 / power);
}

float equation_hyperbolic(float x, float power) {
    return x * pow(1.0 + pow(x, power), -1.0 / power);
}

float equation_term(float x, float x_pivot, float slope_pivot, float scale) {
    return (slope_pivot * (x - x_pivot)) / scale;
}

float equation_curve(float x, float x_pivot, float y_pivot, float slope_pivot, float toe_power, float shoulder_power, float scale) {
    if (scale < 0.0) {
        return scale * equation_hyperbolic(equation_term(x, x_pivot, slope_pivot, scale), toe_power) + y_pivot;
    } else {
        return scale * equation_hyperbolic(equation_term(x,x_pivot,slope_pivot,scale), shoulder_power) + y_pivot;
    }
}

float equation_full_curve(float x, float x_pivot, float y_pivot, float slope_pivot, float toe_power, float shoulder_power) {
    bool bpivot = x >= x_pivot;
    float scale_x_pivot = mix(x_pivot, 1.0 - x_pivot, bpivot);
    float scale_y_pivot = mix(y_pivot, 1.0 - y_pivot, bpivot);

    float toe_scale = equation_scale(scale_x_pivot, scale_y_pivot, slope_pivot, toe_power);
    float shoulder_scale = equation_scale(scale_x_pivot, scale_y_pivot, slope_pivot, shoulder_power);

    float scale = mix(-toe_scale, shoulder_scale, bpivot);

    return equation_curve(x, x_pivot, y_pivot, slope_pivot, toe_power, shoulder_power, scale);
}

vec3 AgXConfigurable(vec3 rgb) {
    const float x_pivot = abs(min_ev) / (max_ev - min_ev);
    const float y_pivot = 0.5;

    vec3 logRGB = open_domain_to_normalized_log2(rgb, min_ev, max_ev);

    float outputR = equation_full_curve(logRGB.r, x_pivot, y_pivot, slope, toe_power, shoulder_power);
    float outputG = equation_full_curve(logRGB.g, x_pivot, y_pivot, slope, toe_power, shoulder_power);
    float outputB = equation_full_curve(logRGB.b, x_pivot, y_pivot, slope, toe_power, shoulder_power);

    return saturate(vec3(outputR, outputG, outputB));
}

vec3 AgX_Full(vec3 rgb) {
    return sRGBToLinear(AgXConfigurable(rgb));
}

//======// AgX AllenWp, for HDR/SDR use //============================================================================//
// allenwp tonemapping curve; developed for use in the Godot game engine.
// Source and details: https://allenwp.com/blog/2025/05/29/allenwp-tonemapping-curve/
// Input must be a non-negative linear scene value.
vec3 allenwp_curve(vec3 x) {
    #ifdef HDR_ENABLED
        float output_max_value = HdrGamePeakBrightness / HdrGamePaperWhiteBrightness;
    #else
        float output_max_value = 1.0;
    #endif
	// These constants must match the those in the C++ code that calculates the parameters.
	// 18% "middle gray" is perceptually 50% of the brightness of reference white.
	const float awp_crossover_point = 0.1841865;
	const float awp_shoulder_max = output_max_value - awp_crossover_point;
    float awp_high_clip = 12.0;
    awp_high_clip = max(awp_high_clip, output_max_value);
	float awp_contrast = 1.5;
	float awp_toe_a = ((1.0 / awp_crossover_point) - 1.0) * pow(awp_crossover_point, awp_contrast);
    float awp_slope_denom = pow(awp_crossover_point, awp_contrast) + awp_toe_a;
	float awp_slope = (awp_contrast * pow(awp_crossover_point, awp_contrast - 1.0) * awp_toe_a) / (awp_slope_denom * awp_slope_denom);
	float awp_w = awp_high_clip - awp_crossover_point;
	awp_w = awp_w * awp_w;
	awp_w = awp_w / awp_shoulder_max;
	awp_w = awp_w * awp_slope;

	// Reinhard-like shoulder:
	vec3 s = x - awp_crossover_point;
	vec3 slope_s = awp_slope * s;
	s = slope_s * (1.0 + s / awp_w) / (1.0 + (slope_s / awp_shoulder_max));
	s += awp_crossover_point;

	// Sigmoid power function toe:
	vec3 t = pow(x, vec3(awp_contrast));
	t = t / (t + awp_toe_a);

	return mix(s, t, lessThan(x, vec3(awp_crossover_point)));
}

// This is an approximation and simplification of EaryChow's AgX implementation that is used by Blender.
// This code is based off of the script that generates the AgX_Base_sRGB.cube LUT that Blender uses.
// Source: https://github.com/EaryChow/AgX_LUT_Gen/blob/main/AgXBasesRGB.py
// Colorspace transformation source: https://www.colour-science.org:8010/apps/rgb_colourspace_transformation_matrix
vec3 AgX_AllenWp(vec3 color) {
	// Input color should be non-negative!
	// Large negative values in one channel and large positive values in other
	// channels can result in a colour that appears darker and more saturated than
	// desired after passing it through the inset matrix. For this reason, it is
	// best to prevent negative input values.
	// This is done before the Rec. 2020 transform to allow the Rec. 2020
	// transform to be combined with the AgX inset matrix. This results in a loss
	// of color information that could be correctly interpreted within the
	// Rec. 2020 color space as positive RGB values, but is often not worth
	// the performance cost of an additional matrix multiplication.
	//
	// Additionally, this AgX configuration was created subjectively based on
	// output appearance in the Rec. 709 color gamut, so it is possible that these
	// matrices will not perform well with non-Rec. 709 output (more testing with
	// future wide-gamut displays is be needed).
	// See this comment from the author on the decisions made to create the matrices:
	// https://github.com/godotengine/godot-proposals/issues/12317#issuecomment-2835824250

	// Combined Rec. 709 to Rec. 2020 and Blender AgX inset matrices:
	const mat3 rec709_to_rec2020_agx_inset_matrix = mat3(
			0.544814746488245, 0.140416948464053, 0.0888104196149096,
			0.373787398372697, 0.754137554567394, 0.178871756420858,
			0.0813978551390581, 0.105445496968552, 0.732317823964232);

	// Combined inverse AgX outset matrix and Rec. 2020 to Rec. 709 matrices.
	const mat3 agx_outset_rec2020_to_rec709_matrix = mat3(
			1.96488741169489, -0.299313364904742, -0.164352742528393,
			-0.855988495690215, 1.32639796461980, -0.238183969428088,
			-0.108898916004672, -0.0270845997150571, 1.40253671195648);
    #ifdef HDR_ENABLED
	    float output_max_value = HdrGamePeakBrightness / HdrGamePaperWhiteBrightness;
    #else
        float output_max_value = 1.0;
    #endif

    // Apply inset matrix.
	color = rec709_to_rec2020_agx_inset_matrix * color * 2.0;

	// Use the allenwp tonemapping curve to match the Blender AgX curve while
	// providing stability across all variable dyanimc range (SDR, HDR, EDR).
	color = allenwp_curve(color);

	// Clipping to output_max_value is required to address a cyan colour that occurs
	// with very bright inputs.
	color = min(vec3(output_max_value), color);

	// Apply outset to make the result more chroma-laden and then go back to Rec. 709.
	color = agx_outset_rec2020_to_rec709_matrix * color;

	// Blender's lusRGB.compensate_low_side is too complex for this shader, so
	// simply return the color, even if it has negative components. These negative
	// components may be useful for subsequent color adjustments.
    return color;
}