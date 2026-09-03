#version 430

#include "/photonics/rendering/frag/common.glsl"
#include "/photonics/rendering/restir/direct/pbr/reservoir.glsl"

uniform sampler2D hit_data;
uniform sampler2D initial_direct;

layout(location = DIRECT_RESERVOIR_0) out vec4 di_reservoir_0;
layout(location = DIRECT_RESERVOIR_1) out uvec3 di_reservoir_1;

void main() {
    setup_frag_data(1);

    float direct_weight = 0.0f;
    DirectReservoir direct_result = direct_reservoir_empty();

    if (frag_is_in_world) {
        vec4 initial_hit = texelFetch(hit_data, frag_tex_coord, 0);
        vec3 initial_color = texelFetch(initial_direct, frag_tex_coord, 0).rgb;

        direct_sample_set_hit_point(direct_result.smple, initial_hit.xyz);
        direct_sample_set_hit_normal(direct_result.smple, ph_unpack_normal(floatBitsToUint(initial_hit.w)));

        direct_sample_set_color(direct_result.smple, initial_color);
        direct_weight = direct_sample_weight(direct_result.smple);

        direct_result.weight = direct_weight;
        direct_result.total_samples = 1.0f;

        vec2 uv = ph_reproject_player_pos(frag_player_pos, frag_is_hand, get_taa_jitter()).xy;
        if (clamp(uv, 0, 1) == uv) {
            ivec2 prev_texel = ivec2(uv * PH_VIEW_SIZE);

            FragData prev_frag;
            frag_data_load_previous(prev_frag, prev_texel);

            if (is_same_plane(prev_frag) && is_same_normal(prev_frag)) {
                DirectReservoir reuse_direct = direct_reservoir_empty();
                if (direct_reservoir_load_previous(reuse_direct, prev_texel, true)) {
                    direct_reservoir_reuse(
                            direct_result,
                            reuse_direct,
                            prev_frag,
                            150.0f,
                            direct_weight
                    );
                }
            }
        }
    }

    direct_reservoir_finalize_weight(direct_result, direct_weight);
    direct_reservoir_encode(direct_result, di_reservoir_0, di_reservoir_1);
}
