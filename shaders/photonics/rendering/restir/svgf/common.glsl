#include "/photonics/utility/normal_encoding.glsl"

#define TEMPORAL_FRAME_OUT 0
#define TEMPORAL_WEIGHTS_OUT 1

#if PH_RESTIR_DENOISER_PASSES > 0
#define SVGF_DATA_OUT 0
#define SVGF_RESULT_OUT 1
#else
#define SVGF_RESULT_OUT 0
#endif

//ph_required: uniform usampler2D prev_denoise_result;

// 3×3 Gaussian Kernel & Offsets
const float kernel[9] = float[](
        1.0 / 6., 2.0 / 3., 1.0 / 6.,
        2.0 / 3., 1.0, 2.0 / 3.,
        1.0 / 6., 2.0 / 3., 1.0 / 6.
);

const ivec2 offset[9] = ivec2[](
        ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1),
        ivec2(-1, 0), ivec2(0, 0), ivec2(1, 0),
        ivec2(-1, 1), ivec2(0, 1), ivec2(1, 1)
);

#define SVGF_CENTER_INDEX 4

float svgf_normal_edge_stopping_weight(vec3 center_normal, vec3 sample_normal)
{
    const float power = 64.0f;

    return pow(clamp(dot(center_normal, sample_normal), 0.0f, 1.0f), power);
}

float svgf_depth_edge_stopping_weight(float center_depth, float sample_depth, float phi)
{
    return exp(-abs(center_depth - sample_depth) / phi);
}

float svgf_luma_edge_stopping_weight(float center_luma, float sample_luma, float phi)
{
    return exp(-abs(center_luma - sample_luma) / phi);
}

float svgf_shadow_stopping_weight(float center_vis, float sample_vis, float phi)
{
    return exp(-abs(center_vis - sample_vis) / phi);
}

uint svgf_pack_shadow_normal(float di_shadow, float gi_shadow, uint packed_normal) {
    return packUnorm4x8(vec4(unpackUnorm2x16(packed_normal), vec2(di_shadow, gi_shadow)));
}

void svgf_unpack_shadow_normal(uint packed_value, out float di_shadow, out float gi_shadow, out vec3 normal) {
    vec4 unpacked = unpackUnorm4x8(packed_value);

    di_shadow = unpacked.z;
    gi_shadow = unpacked.w;
    normal = ph_decode_normal(unpacked.xy);
}

uvec2 svgf_pack_color(vec3 color) {
    return uvec2(
        packHalf2x16(color.rb),
        floatBitsToUint(color.g)
    );
}

vec3 svgf_unpack_color(uvec2 packed_color) {
    vec3 result;
    result.rb = unpackHalf2x16(packed_color.x);
    result.g = uintBitsToFloat(packed_color.g);

    return result;
}
