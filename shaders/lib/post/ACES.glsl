// https://github.com/aces-aswf/aces-core

/*
The following are the license terms for ACES 1
--------------------------------------------------------------------------------
	# License Terms for Academy Color Encoding System Components #

	Academy Color Encoding System (ACES) software and tools are provided by the
	Academy under the following terms and conditions: A worldwide, royalty-free,
	non-exclusive right to copy, modify, create derivatives, and use, in source and
	binary forms, is hereby granted, subject to acceptance of this license.

	Copyright © 2015 Academy of Motion Picture Arts and Sciences (A.M.P.A.S.).
	Portions contributed by others as indicated. All rights reserved.

	Performance of any of the aforementioned acts indicates acceptance to be bound
	by the following terms and conditions:

	* Copies of source code, in whole or in part, must retain the above copyright
	notice, this list of conditions and the Disclaimer of Warranty.

	* Use in binary form must retain the above copyright notice, this list of
	conditions and the Disclaimer of Warranty in the documentation and/or other
	materials provided with the distribution.

	* Nothing in this license shall be deemed to grant any rights to trademarks,
	copyrights, patents, trade secrets or any other intellectual property of
	A.M.P.A.S. or any contributors, except as expressly stated herein.

	* Neither the name "A.M.P.A.S." nor the name of any other contributors to this
	software may be used to endorse or promote products derivative of or based on
	this software without express prior written permission of A.M.P.A.S. or the
	contributors, as appropriate.

	This license shall be construed pursuant to the laws of the State of
	California, and any disputes related thereto shall be subject to the
	jurisdiction of the courts therein.

	Disclaimer of Warranty: THIS SOFTWARE IS PROVIDED BY A.M.P.A.S. AND CONTRIBUTORS
	"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
	THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND
	NON-INFRINGEMENT ARE DISCLAIMED. IN NO EVENT SHALL A.M.P.A.S., OR ANY
	CONTRIBUTORS OR DISTRIBUTORS, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
	SPECIAL, EXEMPLARY, RESITUTIONARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
	LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
	PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
	LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
	OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
	ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

	WITHOUT LIMITING THE GENERALITY OF THE FOREGOING, THE ACADEMY SPECIFICALLY
	DISCLAIMS ANY REPRESENTATIONS OR WARRANTIES WHATSOEVER RELATED TO PATENT OR
	OTHER INTELLECTUAL PROPERTY RIGHTS IN THE ACADEMY COLOR ENCODING SYSTEM, OR
	APPLICATIONS THEREOF, HELD BY PARTIES OTHER THAN A.M.P.A.S.,WHETHER DISCLOSED OR
	UNDISCLOSED.
--------------------------------------------------------------------------------
*/

float rgbToSaturation(vec3 rgb) {
	float minC = min(min(rgb.r, rgb.g), rgb.b);
	float maxC = max(max(rgb.r, rgb.g), rgb.b);

	return (max(maxC, 1e-10) - max(minC, 1e-10)) / max(maxC, 1e-2);
}

// Returns a geometric hue angle in degrees (0-360) based on RGB values
// For neutral colors, hue is undefined and the function will return zero (The reference
// implementation returns NaN but I think that's silly)
float rgbToHue(vec3 rgb) {
	if (rgb.r == rgb.g && rgb.g == rgb.b) return 0.0;

	float hue = (360.0 / TAU) * atan(2.0 * rgb.r - rgb.g - rgb.b, sqrt(3.0) * (rgb.g - rgb.b));

	if (hue < 0.0) hue += 360.0;

	return hue;
}

// Converts RGB to a luminance proxy, here called YC
// YC is ~ Y + K * Chroma
float rgbToYc(vec3 rgb) {
	const float yc_radius_weight = 1.75;

	float chroma = sqrt(rgb.b * (rgb.b - rgb.g) + rgb.g * (rgb.g - rgb.r) + rgb.r * (rgb.r - rgb.b));

	return (rgb.r + rgb.g + rgb.b + yc_radius_weight * chroma) * rcp(3.0);
}

const mat3 Rec2020_2_AP0 = mat3(
     0.6790856347, 0.1577009146, 0.1632134507,
     0.0460020031, 0.8590546730, 0.0949433240,
    -0.0005739432, 0.0284677684, 0.9721061748
);

const mat3 Rec2020_2_AP1 = mat3(
    0.9748949779, 0.0195991086, 0.0055059134,
    0.0021795628, 0.9955354689, 0.0022849683,
    0.0047972397, 0.0245320166, 0.9706707437
);

const mat3 AP0_2_Rec2020 = mat3(
     1.4904095205, -0.2661709193, -0.2242386013,
    -0.0801674998,  1.1821671211, -0.1019996212,
     0.0032276312, -0.0347764757,  1.0315488446
);

const mat3 AP1_2_Rec2020 = mat3(
     1.0258247477, -0.0200531908, -0.0057715568,
    -0.0022343695,  1.0045865019, -0.0023521324,
    -0.0050133515, -0.0252900718,  1.0303034233
);

const mat3 AP0_2_XYZ = mat3(
	 0.9525523959,  0.0000000000,  0.0000936786,
	 0.3439664498,  0.7281660966, -0.0721325464,
	 0.0000000000,  0.0000000000,  1.0088251844
);
const mat3 XYZ_2_AP0 = mat3(
	 1.0498110175,  0.0000000000, -0.0000974845,
	-0.4959030231,  1.3733130458,  0.0982400361,
	 0.0000000000,  0.0000000000,  0.9912520182
);

const mat3 AP1_2_XYZ = mat3(
	 0.6624541811,  0.1340042065,  0.1561876870,
	 0.2722287168,  0.6740817658,  0.0536895174,
	-0.0055746495,  0.0040607335,  1.0103391003
);
const mat3 XYZ_2_AP1 = mat3(
	 1.6410233797, -0.3248032942, -0.2364246952,
	-0.6636628587,  1.6153315917,  0.0167563477,
	 0.0117218943, -0.0082844420,  0.9883948585
);

const mat3 AP0_2_AP1 = AP0_2_XYZ * XYZ_2_AP1;
const mat3 AP1_2_AP0 = AP1_2_XYZ * XYZ_2_AP0;

const mat3 sRGB_2_AP0 = sRGB_2_XYZ * XYZ_2_AP0;
const mat3 AP0_2_sRGB = AP0_2_XYZ * XYZ_2_sRGB;

const mat3 sRGB_2_AP1 = sRGB_2_XYZ * XYZ_2_AP1;
const mat3 AP1_2_sRGB = AP1_2_XYZ * XYZ_2_sRGB;

const mat3 D60ToD65_CAT = mat3(
     0.98722400, -0.00611327, 0.01595330,
    -0.00759836,  1.00186000, 0.00533002,
     0.00307257, -0.00509595, 1.08168000
);

const vec3 AP1_RGB2Y = vec3(0.2722287168, 0.6740817658, 0.0536895174);

//======// ACES 1 Fit //============================================================================//
// "Glow" module constants
const float rrtGlowGain  = 0.05;   	// Default: 0.05
const float rrtGlowMid   = 0.08;   	// Default: 0.08

// Red modifier constants
const float rrtRedScale  = 0.82;  	// Default: 0.82
const float rrtRedPivot  = 0.03;    // Default: 0.03
const float rrtRedHue    = 0.0;     // Default: 0.0
const float rrtRedWidth  = 135.0; 	// Default: 135.0

// Desaturation contants
const float rrtSatFactor = 0.96; 	// Default: 0.96
const float odtSatFactor = 0.93; 	// Default: 0.93

// ------- Glow module functions
float GlowFwd(float yc_in, float glow_gain_in, const float glow_mid) {
	float glow_gain_out;

	if (yc_in <= 2.0 / 3.0 * glow_mid) {
		glow_gain_out = glow_gain_in;
	} else if (yc_in >= 2.0 * glow_mid) {
		glow_gain_out = 0.0;
	} else {
		glow_gain_out = glow_gain_in * (glow_mid / yc_in - 0.5);
	}

	return glow_gain_out;
}

float SigmoidShaper(float x) {
	// Sigmoid function in the range 0 to 1 spanning -2 to +2
	float t = max0(1.0 - abs(0.5 * x));
	float y = 1.0 + signMul(oms(t * t), x);

	return 0.5 * y;
}

// ------- Red modifier functions
float CubicBasisShaper(float x, float w) {
    const mat4 M = mat4(
        -1.0 / 6.0,  3.0 / 6.0, -3.0 / 6.0,  1.0 / 6.0,
         3.0 / 6.0, -6.0 / 6.0,  3.0 / 6.0,  0.0 / 6.0,
        -3.0 / 6.0,  0.0 / 6.0,  3.0 / 6.0,  0.0 / 6.0,
         1.0 / 6.0,  4.0 / 6.0,  1.0 / 6.0,  0.0 / 6.0
    );

    float knots[5] = float[5](
        w * -0.5,
        w * -0.25,
        0.0,
        w *  0.25,
        w *  0.5
    );

    float y = 0;
    if ((x > knots[0]) && (x < knots[4])) {
        float knot_coord = (x - knots[0]) * 4.0 / w;
        int j = int(knot_coord);
        float t = knot_coord - j;

        vec4 monomials = vec4(cube(t), sqr(t), t, 1.0);

        switch(j) {
            case 3:  y = monomials[0] * M[0][0] + monomials[1] * M[1][0] + monomials[2] * M[2][0] + monomials[3] * M[3][0]; break;
            case 2:  y = monomials[0] * M[0][1] + monomials[1] * M[1][1] + monomials[2] * M[2][1] + monomials[3] * M[3][1]; break;
            case 1:  y = monomials[0] * M[0][2] + monomials[1] * M[1][2] + monomials[2] * M[2][2] + monomials[3] * M[3][2]; break;
            case 0:  y = monomials[0] * M[0][3] + monomials[1] * M[1][3] + monomials[2] * M[2][3] + monomials[3] * M[3][3]; break;
            default: y = 0.0; break;
        }
    }

    return y * 1.5;
}

// https://github.com/sixthsurge/photon/blob/main/shaders/include/aces/aces.glsl
float CubicBasisShaperFit(float x, const float width) {
	float radius = 0.5 * width;
	return abs(x) < radius ? sqr(curve(1.0 - abs(x) / radius)) : 0.0;
}

float CenterHue(float hue, float centerH) {
	float hueCentered = hue - centerH;
	if (hueCentered < -180.0) hueCentered += 360.0;
	else if (hueCentered > 180.0) hueCentered -= 360.0;
	return hueCentered;
}

#define log10(x) (log2(x) * rcp(log2(10.0)))

// Textbook monomial to basis-function conversion matrix
const mat3 M = mat3(
	 0.5, -1.0,  0.5,
	-1.0,  1.0,  0.5,
	 0.5,  0.0,  0.0
);

vec3 RRTSweeteners(vec3 aces) {
	// --- Glow module --- //
	float saturation = rgbToSaturation(aces);
	float ycIn = rgbToYc(aces);
	float s = SigmoidShaper(saturation * 5.0 - 2.0);
	float addedGlow = 1.0 + GlowFwd(ycIn, rrtGlowGain * s, rrtGlowMid);

	aces *= addedGlow;

	// --- Red modifier --- //
	float hue = rgbToHue(aces);
	float centeredHue = CenterHue(hue, rrtRedHue);
	float hueWeight = CubicBasisShaperFit(centeredHue, rrtRedWidth);

	aces.r += hueWeight * saturation * (rrtRedPivot - aces.r) * oms(rrtRedScale);

    // --- ACES to RGB rendering space --- //
	vec3 rgbPre = max0(aces * AP0_2_AP1);

	// --- Global desaturation --- //
	rgbPre = mix(vec3(dot(rgbPre, AP1_RGB2Y)), rgbPre, rrtSatFactor);

	return rgbPre;
}

// https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl
vec3 RRTAndODTFit(vec3 rgb) {
	vec3 a = rgb * (rgb + 0.0245786) - 0.000090537;
	vec3 b = rgb * (0.983729 * rgb + 0.4329510) + 0.238081;

	return a / b;
}

vec3 AcademyFit(vec3 rgb) {
	rgb *= Rec2020_2_AP0;

	// Apply RRT sweeteners
	rgb = RRTSweeteners(rgb);

	// Apply RRT and ODT
	rgb = RRTAndODTFit(rgb);

	// Global desaturation
	rgb = mix(vec3(dot(rgb, AP1_RGB2Y)), rgb, odtSatFactor);

	return rgb * AP1_2_Rec2020;
}

//======// ACES 2.0 //===========================================================================//
// This implementation is based on the shaders emitted by OCIO's ACES 2.0 implementation and [the reference implementation](https://github.com/aces-aswf/aces-core)
// ACES 2.0 is licensed under Apache License 2.0. You can find a copy in the root of this repository(/LICENSE).
// Copyright Contributors to the ACES Project.
/*
Copyright Contributors to the OpenColorIO Project.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

* Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.
* Neither the name of the copyright holder nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

uniform sampler1D acesReachMTableTex;
uniform sampler1D acesGamutCuspTableTex;

float aces_reach_m_table_sample(float h) {
  float i_base = floor(h);
  float i_lo = i_base + 1;
  float i_hi = i_lo + 1;
  float lo = texelFetch(acesReachMTableTex, int(i_lo), 0).r;
  float hi = texelFetch(acesReachMTableTex, int(i_hi), 0).r;
  float t = h - i_base;
  return mix(lo, hi, t);
}
float aces_tonescale_fwd0(float J) {
  float A = 0.0323680267 * pow(abs(J) * 0.00999999978, 0.879464149);
  float Y = pow(( 27.1299992 * A) / (1.0f - A), 2.3809523809523809);
  float f = 1.04710376 * pow(Y / (Y + 0.73009213709383403), 1.14999998);
  float Y_ts = max(0.0, f * f / (f + 0.0399999991));
  float F_L_Y = pow(0.79370057210326195 * Y_ts, 0.42);
  float J_ts = 100. * pow((F_L_Y / ( 27.1299992 + F_L_Y)) * 30.8946857, 1.13705599);
  return sign(J) * J_ts;
}
float aces_toe_fwd0(float x, float limit, float k1_in, float k2_in)
{
  float k2 = max(k2_in, 0.001);
  float k1 = sqrt(k1_in * k1_in + k2 * k2);
  float k3 = (limit + k1) / (limit + k2);
  return (x > limit) ? x : 0.5 * (k3 * x - k1 + sqrt((k3 * x - k1) * (k3 * x - k1) + 4.0 * k2 * k3 * x));
}
const float aces_gamut_cusp_table_hues_array[363] = float[363](-1.01858521, 0., 0.999435902, 1.9988718, 2.9983077, 3.99774361, 4.99717951, 5.99661541, 6.99605131, 7.99548721, 8.99492264, 9.99435902, 10.9937954, 11.9932308, 12.9926662, 13.9921026, 14.991539, 15.9909744, 16.9904099, 17.9898453, 18.9892826, 19.988718, 20.9881535, 21.9875908, 22.9870262, 23.9864616, 24.9858971, 26.2510033, 27.2489777, 28.2469521, 29.2449265, 30.2429008, 31.2408752, 32.2388496, 33.236824, 34.2347984, 35.2327728, 36.2307434, 37.2287216, 38.2266922, 39.2246704, 40.222641, 41.2206154, 42.2185898, 43.2165642, 44.2145386, 45.212513, 46.2104874, 47.2084618, 48.2064362, 49.2044106, 50.2023849, 51.2003593, 52.1983337, 53.1963043, 54.1942825, 55.1922531, 56.1902313, 57.1882019, 58.1861801, 59.1841507, 60.1821251, 61.1800995, 62.1780739, 63.1760483, 64.1740265, 65.1719971, 66.1699677, 67.1679459, 68.1659241, 69.1638947, 70.1618652, 71.1598434, 72.1578217, 73.1557922, 74.1537628, 75.151741, 76.1497192, 77.1476898, 78.1456604, 79.1436386, 80.1416092, 81.1395874, 82.137558, 83.1355286, 84.1335068, 85.131485, 86.1294556, 87.1274261, 88.1254044, 89.1233826, 90.1213531, 91.1193237, 92.1172943, 93.1152802, 94.1132507, 95.1112213, 96.1091919, 97.1071777, 98.1051483, 99.1031189, 100.101089, 101.099075, 102.097046, 103.095016, 104.092987, 105.090973, 106.088936, 106.548775, 107.571564, 108.594353, 109.617142, 110.639931, 111.66272, 112.685509, 113.708298, 114.731087, 115.753876, 116.776665, 117.799454, 118.822243, 119.845032, 120.867821, 121.89061, 122.913399, 123.936188, 124.958977, 125.981766, 127.004555, 128.027344, 129.05014, 130.072922, 131.095703, 132.1185, 133.141296, 134.164078, 135.186859, 136.209656, 137.232452, 138.255234, 139.278015, 140.300812, 141.287491, 142.27417, 143.260849, 144.247528, 145.234207, 146.220886, 147.207565, 148.207993, 149.20842, 150.208847, 151.209274, 152.209702, 153.210129, 154.210556, 155.210983, 156.211411, 157.211853, 158.21228, 159.212708, 160.213135, 161.213562, 162.213989, 163.214417, 164.214844, 165.215271, 166.215698, 167.216125, 168.216553, 169.21698, 170.217407, 171.217834, 172.218262, 173.218689, 174.219116, 175.219543, 176.219971, 177.220398, 178.220825, 179.221252, 180.22168, 181.222107, 182.222549, 183.222977, 184.223404, 185.223831, 186.224258, 187.224686, 188.225113, 189.22554, 190.225967, 191.226395, 192.226822, 193.12616, 194.025482, 194.92482, 195.824158, 196.830383, 197.836609, 198.842819, 199.849045, 200.85527, 201.861496, 202.867706, 203.873932, 204.880157, 205.886383, 206.892609, 207.898819, 208.905045, 209.91127, 210.917496, 211.923706, 212.929932, 213.936157, 214.942383, 215.948608, 216.954819, 217.961044, 218.96727, 219.973495, 220.979706, 221.985931, 222.992157, 223.998383, 225.004608, 226.010834, 227.017044, 228.02327, 229.029495, 230.035706, 231.041931, 232.048157, 233.054382, 234.060608, 235.066833, 236.073044, 237.079269, 238.085495, 239.091705, 240.097931, 241.104156, 242.110382, 243.116608, 244.122833, 245.129044, 246.135269, 247.141495, 248.147705, 249.153931, 250.160156, 251.166382, 252.172607, 253.178833, 254.185043, 255.191269, 256.19751, 257.203705, 258.20993, 259.216156, 260.222382, 261.228607, 262.234833, 263.241058, 264.247253, 265.253479, 266.259705, 267.26593, 268.272156, 269.270721, 270.269287, 271.267853, 272.266418, 273.264984, 274.26355, 275.262115, 276.260681, 277.249512, 278.238342, 279.227203, 280.216034, 281.204865, 282.193695, 283.182556, 284.171387, 285.160217, 286.149048, 287.137878, 288.12674, 289.11557, 290.104401, 291.093231, 292.082092, 293.070923, 294.059753, 295.048584, 296.037445, 297.026276, 298.015106, 299.003937, 299.992798, 300.981628, 301.970459, 302.95929, 303.94812, 304.936981, 305.925812, 306.914642, 307.903473, 308.892334, 309.881165, 310.869995, 311.858826, 312.847656, 313.836517, 314.825348, 315.814178, 316.803009, 317.79187, 318.780701, 319.769531, 320.758362, 321.747192, 322.736053, 323.724884, 324.713715, 325.702545, 326.691406, 327.680237, 328.669067, 329.657898, 330.646759, 331.63559, 332.62442, 333.628967, 334.633514, 335.638062, 336.642609, 337.647186, 338.651733, 339.656281, 340.660828, 341.665375, 342.68396, 343.702545, 344.72113, 345.739746, 346.758331, 347.776917, 348.795502, 349.814087, 350.832703, 351.851288, 352.869873, 353.888458, 354.907043, 355.925629, 356.944244, 357.96283, 358.981415, 360., 360.999451);
vec3 aces_gamut_cusp_table_sample(float h)
{
  int i = int(h) + 1;
  int i_lo = int(max(float(0), float(i + 0)));
  int i_hi = int(min(float(361), float(i + 2)));
  while (i_lo + 1 < i_hi) {
    float hcur = aces_gamut_cusp_table_hues_array[i];
    if (h > hcur) {
      i_lo = i;
    } else {
      i_hi = i;
    }
    i = (i_lo + i_hi) / 2;
  }
  vec3 lo = texelFetch(acesGamutCuspTableTex, i_hi - 1, 0).rgb;
  vec3 hi = texelFetch(acesGamutCuspTableTex, i_hi, 0).rgb;
  float t = (h - aces_gamut_cusp_table_hues_array[i_hi - 1]) / (aces_gamut_cusp_table_hues_array[i_hi] - aces_gamut_cusp_table_hues_array[i_hi - 1]);
  return mix(lo, hi, t);
}
float aces_get_focus_gain0(float J, float cuspJ)
{
  float thr = mix(cuspJ, aces_limit_J_max, 0.300000);
  if (J > thr) {
    float gain = (aces_limit_J_max - thr) / max(0.0001, aces_limit_J_max - J);
    gain = log(gain)/log(10.0);
    return gain * gain + 1.0;
  } else {
    return 1.0;
  }
}
float aces_solve_J_intersect0(float J, float M, float focusJ, float slope_gain)
{
  float M_scaled = M / slope_gain;
  float a = M_scaled / focusJ;
  if (J < focusJ) {
    float b = 1.0 - M_scaled;
    float c = -J;
    float det =  b * b - 4.f * a * c;
    float root =  sqrt(det);
    return -2.0 * c / (b + root);
  } else {
    float b = - (1.0 + M_scaled + aces_limit_J_max * a);
    float c = aces_limit_J_max * M_scaled + J;
    float det =  b * b - 4.f * a * c;
    float root =  sqrt(det);
    return -2.0 * c / (b - root);
  }
}
float aces_find_gamut_boundary_intersection0(vec2 JM_cusp, float gamma_top_inv, float gamma_bottom_inv, float J_intersect_source, float J_intersect_cusp, float slope)
{
  float M_boundary_lower = J_intersect_cusp * pow(J_intersect_source / J_intersect_cusp, gamma_bottom_inv) / (JM_cusp.r / JM_cusp.g - slope);
  float M_boundary_upper = JM_cusp.g * (aces_limit_J_max - J_intersect_cusp) * pow((aces_limit_J_max - J_intersect_source) / (aces_limit_J_max - J_intersect_cusp), gamma_top_inv) / (slope * JM_cusp.g + aces_limit_J_max - JM_cusp.r);
  float smin = 0.0;
  {
    float a = M_boundary_lower > 0.0 ? M_boundary_lower : 10000.0;
    float b = M_boundary_upper > 0.0 ? M_boundary_upper : 10000.0;
    float s = 0.119999997 * JM_cusp.g;
    float h = max(s - abs(a - b), 0.0) / s;
    smin = min(a, b) - h * h * h * s * 0.16666666666666666;
  }
  return smin;
}
float aces_remap_M_fwd0(float M, float gamut_boundary_M, float reach_boundary_M)
{
  float boundary_ratio = gamut_boundary_M / reach_boundary_M;
  float proportion = max(boundary_ratio, 0.75);
  float threshold = proportion * gamut_boundary_M;
  if (proportion >= 1.0f || M <= threshold) {
    return M;
  }
  float m_offset = M - threshold;
  float gamut_offset = gamut_boundary_M - threshold;
  float reach_offset = reach_boundary_M - threshold;
  float scale = reach_offset / ((reach_offset / gamut_offset) - 1.0f);
  float nd = m_offset / scale;
  return threshold + scale * nd / (1.0f + nd);
}
vec3 aces_gamut_compress0(vec3 JMh, float Jx, vec3 JMGcusp, float reachMaxM) {
  float J = JMh.r;
  float M = JMh.g;
  float h = JMh.b;
  if (J <= 0.0) {
    return vec3(0.0, 0.0, h);
  }
  if (M <= 0.0 || J > aces_limit_J_max) {
    return vec3(J, 0.0, h);
  } else {
    vec2 JMcusp = JMGcusp.rg;
    float focusJ = mix(JMcusp.r, 34.096539, min(1.0, 1.300000 - (JMcusp.r / aces_limit_J_max)));
    float slope_gain = 135. * aces_get_focus_gain0(Jx, JMcusp.r);
    float J_intersect_source = aces_solve_J_intersect0(JMh.r, JMh.g, focusJ, slope_gain);
    float gamut_slope = (J_intersect_source < focusJ) ? J_intersect_source : (aces_limit_J_max - J_intersect_source);
    gamut_slope = gamut_slope * (J_intersect_source - focusJ) / (focusJ * slope_gain);
    float gamma_top_inv = JMGcusp.b;
    float gamma_bottom_inv = 0.877192974;
    float J_intersect_cusp = aces_solve_J_intersect0(JMcusp.r, JMcusp.g, focusJ, slope_gain);
    float gamutBoundaryM = aces_find_gamut_boundary_intersection0(JMcusp, gamma_top_inv, gamma_bottom_inv, J_intersect_source, J_intersect_cusp, gamut_slope);
    if (gamutBoundaryM <= 0.0) {
      return vec3(J, 0.0, h);
    }
    float reachBoundaryM = aces_limit_J_max * pow(J_intersect_source / aces_limit_J_max,  0.879464149);
    reachBoundaryM = reachBoundaryM / ((aces_limit_J_max / reachMaxM) - gamut_slope);
    float remapped_M = aces_remap_M_fwd0(M, gamutBoundaryM, reachBoundaryM);
    float remapped_J = J_intersect_source + remapped_M * gamut_slope;
    return vec3(remapped_J, remapped_M, h);
  }
}

vec3 ACES2(vec3 inPixel) {
  inPixel *= 2.0; // Workaround to match other tonemappers' exposure
  vec3 outColor = inPixel * Rec2020_2_AP1;

  {
    outColor = RGB_to_JMh(outColor);
    float h_rad = outColor.b * 0.0174532924;
    float cos_hr = cos(h_rad);
    float sin_hr = sin(h_rad);

    // ToneScale and ChromaCompress (fwd)

    float J_ts = aces_tonescale_fwd0(outColor.r);
    // Sample tables (fwd)
    float reachMaxM = aces_reach_m_table_sample(outColor.b);

    {
      float J = outColor.r;
      float M = outColor.g;
      float h = outColor.b;
      float M_cp = M;
      if (M != 0.0) {
        float nJ = J_ts / aces_limit_J_max;
        float snJ = max(0.0, 1.0 - nJ);
        float Mnorm;
        {
          float cos_hr2 = 2.0 * cos_hr * cos_hr - 1.0;
          float sin_hr2 = 2.0 * cos_hr * sin_hr;
          float cos_hr3 = 4.0 * cos_hr * cos_hr * cos_hr - 3.0 * cos_hr;
          float sin_hr3 = 3.0 * sin_hr - 4.0 * sin_hr * sin_hr * sin_hr;
          vec3 cosines = vec3(cos_hr, cos_hr2, cos_hr3);
          vec3 cosine_weights = vec3(11.341321604032515, 16.469863649185896, 7.8842182208776475);
          vec3 sines = vec3(sin_hr, sin_hr2, sin_hr3);
          vec3 sine_weights = vec3(14.665187919584513, -6.3725780354404442, 9.1941277054452897);
          Mnorm = dot(cosines, cosine_weights) + dot(sines, sine_weights) + 77.133051547393805;
        }
        float limit = pow(nJ, 0.879464149) * reachMaxM / Mnorm;
        M_cp = M * pow(J_ts / J, 0.879464149);
        M_cp = M_cp / Mnorm;
        M_cp = limit - aces_toe_fwd0(limit - M_cp, limit - 0.001, snJ * 1.29999995, sqrt(nJ * nJ + 0.00499999989));
        M_cp = aces_toe_fwd0(M_cp, limit, nJ * 2.4000001, snJ);
        M_cp = M_cp * Mnorm;
      }
      outColor.rgb = vec3(J_ts, M_cp, h);
    }

    // GamutCompress (fwd)

    {
      vec3 JMGcusp = aces_gamut_cusp_table_sample(outColor.b);
      outColor.rgb = aces_gamut_compress0(outColor.rgb, outColor.r, JMGcusp, reachMaxM);
    }


    outColor = JMh_to_RGB(outColor);
  }

  outColor = clamp(outColor, vec3(0.0), vec3(1.0));

  outColor *= sRGB_2_Rec2020;
  return outColor;
}
