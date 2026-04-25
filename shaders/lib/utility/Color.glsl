#define TONEMAPPER_AgX_Minimal 1
#define TONEMAPPER_AgX_Full 2
#define TONEMAPPER_ACES_Fit 16
#define TONEMAPPER_ACES_Full 17
#define TONEMAPPER_GT 32
#define TONEMAPPER_GT7 33
#define TONEMAPPER_Lottes 48
#define TONEMAPPER_None 0

const mat3 Rec2020_2_sRGB = mat3(
     1.6603034854, -0.5875701425, -0.0728900602,
    -0.1243755953,  1.1328344814, -0.0083597372,
    -0.0181122800, -0.1005836085,  1.1187703262
);

const mat3 sRGB_2_Rec2020 = mat3(
    0.6274413721, 0.3292974595, 0.0433514584,
    0.0690276171, 0.9195806669, 0.0113614226,
    0.0163642351, 0.0880171625, 0.8955649727
);

const mat3 sRGB_2_XYZ = mat3(
	0.4124564, 0.3575761, 0.1804375,
	0.2126729, 0.7151522, 0.0721750,
	0.0193339, 0.1191920, 0.9503041
);

const mat3 XYZ_2_sRGB = mat3(
	 3.2409699419, -1.5373831776, -0.4986107603,
	-0.9692436363,  1.8759675015,  0.0415550574,
	 0.0556300797, -0.2039769589,  1.0569715142
);

const mat3 XYZ_2_Rec2020 = mat3(
     1.716651188,  -0.3556707838, -0.2533662814,
    -0.6666843518,  1.6164812366,  0.0157685458,
     0.0176398574, -0.0427706133,  0.9421031212
);

const mat3 Rec2020_2_XYZ = mat3(
    0.6369580483, 0.1446169036, 0.1688809752,
    0.2627002120, 0.6779980715, 0.0593017165,
    0.0000000000, 0.0280726930, 1.0609850577
);

// https://en.wikipedia.org/wiki/SRGB
// https://github.com/tobspr/GLSL-Color-Spaces/blob/master/ColorSpaces.inc.glsl
vec3 linearToSRGB(vec3 color) {
	return mix(color * 12.92, 1.055 * pow(color, vec3(0.41666666)) - 0.055, step(vec3(0.0031308), color));
}

vec3 sRGBToLinear(vec3 color) {
	return mix(color * 0.07739938, pow((color + 0.055) * 0.94786729, vec3(2.4)), step(vec3(0.04045), color));
}

// https://chilliant.blogspot.com/2012/08/srgb-approximations-for-hlsl.html
vec3 linearToSRGBApprox(vec3 color) {
    vec3 S1 = color * inversesqrt(color);
    vec3 S2 = S1 * inversesqrt(S1);
    vec3 S3 = S2 * inversesqrt(S2);
    return 0.585122381 * S1 + 0.783140355 * S2 - 0.368262736 * S3;
}

vec3 sRGBToLinearApprox(vec3 color) {
    return color * (color * (color * 0.305306011 + 0.682171111) + 0.012522878);
}

// https://en.wikipedia.org/wiki/YCoCg
vec3 RGBToYCoCg(vec3 rgb) {
    return mat3(
        0.25,  0.50, -0.25,
        0.50,  0.00,  0.50,
        0.25, -0.50, -0.25
    ) * rgb;
}
vec3 YCoCgToRGB(vec3 YCoCg) {
    return mat3(
         1.0,  1.0,  1.0,
         1.0,  0.0, -1.0,
        -1.0,  1.0, -1.0
    ) * YCoCg;
}

float luminance(vec3 color) {
    return dot(color, Rec2020_2_XYZ[1]);
}

vec3 desaturate(vec3 color, float amount) {
    return mix(color, vec3(luminance(color)), amount);
}

float karisAverage(vec3 color) {
    return rcp(1.0 + luminance(color));
}

vec3 reinhard(vec3 hdr) {
    return hdr * rcp(1.0 + luminance(hdr));
}
vec3 invReinhard(vec3 sdr) {
    return sdr * rcp(1.0 - luminance(sdr));
}

// Inspired by GPU Zen 4
vec3 TonemapRadiance(vec3 v, float e) {
    return v * pow(luminance(v) + EPS, e - 1.0);
}
vec3 InverseTonemapRadiance(vec3 v, float e) {
    return v * pow(luminance(v) + EPS, rcp(e) - 1.0);
}

//======// ACES 2.0 //===========================================================================//

const float aces_limit_J_max = 100.0;
const int aces_tableSize = 360;
const int aces_baseIndex = 1;
const int aces_totalTableSize = 363;
const int aces_lowerWrapIndex = 0;
const int aces_lastNominalIndex = 360;
const int aces_upperWrapIndex = 361;
const int aces_upperWrapPlusOneIndex = 362;
const int aces_cuspCornerCount = 6;
const int aces_totalCornerCount = aces_cuspCornerCount + 2;
const float aces_hue_limit = 360.0;
const float aces_display_cusp_tolerance = 1e-7;
const float aces_smooth_cusps = 0.12;
const float aces_smooth_m = 0.27;
const float aces_gamma_minimum = 0.0;
const float aces_gamma_maximum = 5.0;
const float aces_gamma_search_step = 0.4;
const float aces_gamma_accuracy = 1e-5;
const float aces_gamma_bottom_inv = 0.877192974;
const float aces_focus_dist_scaled = 135.0;
const float aces_mid_J = 34.096539;
const float aces_focus_gain_blend = 0.3;

// JMh to output RGB (sRGB here)
vec3 JMh_to_RGB(vec3 JMh) {
	float h_rad = JMh.b * 0.0174532924;
    float cos_hr = cos(h_rad);
    float sin_hr = sin(h_rad);
	vec3 outColor;
    vec3 Aab;
    {
      Aab.r = pow(JMh.r * 0.00999999978, 0.879464149);
      Aab.g = JMh.g * cos_hr;
      Aab.b = JMh.g * sin_hr;
    }
    {
      vec3 rgb_a = mat3(0.0323680267, 0.0323680267, 0.0323680267, 2.07657631e-05, -4.10250432e-05, -1.01296409e-05, 1.3260621e-05, -1.20174373e-05, -0.000290076074) * Aab.rgb;
      vec3 rgb_a_lim = min( abs(rgb_a), vec3(0.99000001, 0.99000001, 0.99000001) );
      vec3 lms = sign(rgb_a) * pow( 27.1299992 * rgb_a_lim / (1.0f - rgb_a_lim), vec3(2.38095236, 2.38095236, 2.38095236));
      outColor = mat3(7.45048571, -1.4750675, 0.0106288502, -6.1301837, 3.11835742, -0.31857267, -0.0603808537, -0.383369029, 1.56786489) * lms;
    }
    return outColor;
}

// AP1 to JMh
vec3 RGB_to_JMh(vec3 RGB) {
    vec3 lms = mat3(
        0.445181042, 0.123734146, 0.0117007261,
        0.34964928, 0.613643706, 0.0280607939,
        -0.00112973212, 0.0563228019, 0.753939033
    ) * RGB;

    vec3 F_L_v = pow(abs(lms), vec3(0.419999987));
    vec3 rgb_a = (sign(lms) * F_L_v) / (27.1299992 + F_L_v);
    vec3 Aab = mat3(
        20.25881, 15480.0, 1720.0,
        10.129405, -16887.2734, 1720.0,
        0.506470263, 1407.27271, -3440.0
    ) * rgb_a;

    if (Aab.r < EPS) {
        return vec3(0.0);
    }

    float J = 100.0 * pow(Aab.r, 1.13705599);
    float M = sqrt(Aab.g * Aab.g + Aab.b * Aab.b);
    float h = atan(Aab.b, Aab.g) * 57.29577951308232;
    h = h - floor(h / 360.0) * 360.0;
    if (h < 0.0) {
        h += 360.0;
    }

    return vec3(J, M, h);
}

//================================================================================================//

// Adapted from https://github.com/zubetto/BlackBodyRadiation
// MIT License
// Copyright (c) 2021 Alexander
/*
    This function approximates luminance and chromaticity of a black body radiation emitted at the given temperature.
    Approximation errors are not provided, so this function should not be used where computational accuracy is critical!
    Instead, the primary purpose of this function is to render a black body surface in real time, which can be used in CG shaders,
    therefore the function is written in HLSL.

    The luminance and chromaticity of a black body radiation are computed independently of each other.
    The alpha-component of returned value is effective radiance in W/(sr*m2), which
    should be multiplied by 683.002 lm/W to get the corresponding luminance in cd/m2.
    The rgb-components of returned value are color components expressed in linear sRGB color space.
    Relative luminance of returned color is close to 1 for temperatures above about 1000 K.
    Note, that returned color can have negative components, which means that chromaticity of a black body
    is outside the sRGB gamut for a given temperature (g-component < 0 for temperatures below about 900 K and
    b-component < 0 for temperatures below about 1900 K).
    To get final color of a black body radiation with luminance in cd/m2
    the rgb-components should be multiplied by the alpha-component and by 683.002 lm/W.

    sRGB is defined according to ITU-R BT.709:
                             x       y
        white point   = 0.3127, 0.3290
        red primary   =   0.64,   0.33
        green primary =   0.30,   0.60
        blue primary  =   0.15,	  0.06
    More details can be found here https://www.desmos.com/calculator/qaxw5zb0zc

    T - temperature in degrees Kelvin;
    bComputeRadiance - if true, effective radiance is computed;
    bComputeChromaticity - if true, chromaticity is computed;

    returns: vec4 ChromaRadiance = {chroma_r, chroma_g, chroma_b, effRadiance}
*/
vec4 BlackBodyRadiation(float T) {
    if (T <= 0.0) return vec4(0.0);

    vec4 ChromaRadiance;

    // --- Effective radiance in W/(sr*m2) ---
    ChromaRadiance.a = 230141698.067 / (exp2(37112.1757708 / T) - 1.0);

    // luminance Lv = Km*ChromaRadiance.a in cd/m2, where Km = 683.002 lm/W

    // --- Chromaticity in linear sRGB ---
    // (i.e. color luminance Y = dot({r,g,b}, {0.2126, 0.7152, 0.0722}) = 1)
    // --- R ---
    float u = 0.000536332 * T;
    ChromaRadiance.r = 0.638749 + (u + 1.57533) / (u * u + 0.28664);

    // --- G ---
    u = 0.0019639 * T;
    ChromaRadiance.g = 0.971029 + (u - 10.8015) / (u * u + 6.59002);

    // --- B ---
    float p = 0.00668406 * T + 23.3962;
    u = 0.000941064 * T;
    float q = u * u + 0.00100641 * T + 10.9068;
    ChromaRadiance.b = 2.25398 - p / q;

    return ChromaRadiance;
}
