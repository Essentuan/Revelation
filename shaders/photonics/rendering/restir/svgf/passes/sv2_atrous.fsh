#version 430

uniform int atrous_iteration;

uniform usampler2D temporal_history_frame_count;
uniform usampler2D denoise_data;
uniform usampler2D prev_denoise_result;

#include "/photonics/rendering/frag/world_interface.glsl"
#include "/photonics/utility/normal_encoding.glsl"

#include "/photonics/rendering/restir/common.glsl"
#include "/photonics/rendering/restir/svgf/common.glsl"

#include "/photonics/utility/color.glsl"

bool fetch_svgf_data(
        ivec2 texel,
        out float depth,
        out vec3 normal,
        out float di_shadow, out float gi_shadow,
        out uvec2 center_data
) {
    uvec4 packed_data = texelFetch(denoise_data, texel, 0);

    depth = uintBitsToFloat(packed_data.x);
    svgf_unpack_shadow_normal(packed_data.y, di_shadow, gi_shadow, normal);
    center_data = packed_data.zw;

    return !isinf(depth);
}

struct AtrousState {
    float L0;
    float phi_luminance;

    vec3 C_sum;
    float W_sum;
};

AtrousState atrous_state(uint center_result) {
    vec2 smple = unpackHalf2x16(center_result);

    return AtrousState(
            smple.x,
            3.0f * sqrt(max(1e-10, smple.y)),
            vec3(0.0f),
            0.0f
    );
}

void atrous_state_filter_neighbor(
        int i,
        inout AtrousState state,
        float D0, float Di,
        vec3  N0, vec3  Ni,
        float S0, float Si,
        uint sample_data,
        uvec2 color_result
) {
    const float phi_depth = 0.5f;
    const float phi_shadow = 0.1f;
    #define phi_luminance state.phi_luminance

    #define Ci svgf_unpack_color(color_result)
    #define L0 state.L0
    #define Li unpackHalf2x16(sample_data).x

    float weight  = kernel[i];
          weight *= svgf_normal_edge_stopping_weight(N0, Ni); // Normal weight
          weight *= svgf_depth_edge_stopping_weight(D0, Di, phi_depth); // Position weight
          weight *= svgf_luma_edge_stopping_weight(L0, Li, phi_luminance); // Color (luminance) weight
          weight *= svgf_shadow_stopping_weight(S0, Si, phi_shadow);

    state.C_sum += Ci * weight;
    state.W_sum += weight;
}

void atrous_state_finalize(AtrousState state, float pass_weight, uvec2 prev_result, out uvec2 result) {
    result = svgf_pack_color(mix(
            svgf_unpack_color(prev_result),
            state.C_sum / max(0.0001f, state.W_sum),
            pass_weight
    ));
}

float get_pass_weight(uint frame_count) {
    const float pass_cutoff = PH_RESTIR_ACCUMULATION_FRAMES * 0.5f;
    if (atrous_iteration < PH_RESTIR_DENOISER_PASSES) return 1.0f;

    return clamp(1.0f - (float(frame_count) / pass_cutoff), 0.0f, 1.0f);
}

layout(location = SVGF_RESULT_OUT) out uvec4 denoise_out;

void main() {
    denoise_out = uvec4(0);
    ivec2 texel = ivec2(gl_FragCoord.xy);

    uint frame_count = texelFetch(temporal_history_frame_count, texel, 0).r;
    uvec4 prev_result = texelFetch(prev_denoise_result, texel, 0);

    float D0; vec3 N0; float DS0; float GS0; uvec2 center_data;
    if (!fetch_svgf_data(texel, D0, N0, DS0, GS0, center_data)) discard;

    float pass_weight = get_pass_weight(frame_count);
    if (pass_weight > 0.0f) {
        AtrousState di_state = atrous_state(center_data.x);
        AtrousState gi_state = atrous_state(center_data.y);

        int step_width = 1 << atrous_iteration;
        for (int i = 0; i < 9; ++i) {
            ivec2 p = texel + step_width * offset[i];

            uvec4 color_data = texelFetch(prev_denoise_result, p, 0);
            float Di; vec3 Ni; float DSi; float GSi; uvec2 sample_data;
            fetch_svgf_data(p, Di, Ni, DSi, GSi, sample_data);

            atrous_state_filter_neighbor(i, di_state, D0, Di, N0, Ni, DS0, DSi, sample_data.x, color_data.xy);
            atrous_state_filter_neighbor(i, gi_state, D0, Di, N0, Ni, GS0, GSi, sample_data.y, color_data.zw);
        }

        atrous_state_finalize(di_state, pass_weight, prev_result.xy, denoise_out.xy);
        atrous_state_finalize(gi_state, pass_weight, prev_result.zw, denoise_out.zw);
    } else denoise_out = prev_result;
}
