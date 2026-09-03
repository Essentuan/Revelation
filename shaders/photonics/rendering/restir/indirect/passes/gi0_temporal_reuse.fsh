#version 430

#include "/photonics/rendering/frag/common.glsl"
#include "/photonics/rendering/restir/indirect/reservoir.glsl"

uniform sampler2D hit_data;
uniform sampler2D initial_indirect;

layout(location = INDIRECT_RESERVOIR_0) out vec4 gi_reservoir_0;
layout(location = INDIRECT_RESERVOIR_1) out uvec3 gi_reservoir_1;

void main() {
    setup_frag_data(1);

    float indirect_weight = 0.0f;
    IndirectReservoir indirect_result = indirect_reservoir_empty();

    if (frag_is_in_world) {
        vec4 initial_hit = texelFetch(hit_data, frag_tex_coord, 0);
        vec3 initial_color = texelFetch(initial_indirect, frag_tex_coord, 0).rgb;

        indirect_sample_set_hit_point(indirect_result.smple, initial_hit.xyz);
        indirect_sample_set_hit_normal(indirect_result.smple, ph_unpack_normal(floatBitsToUint(initial_hit.w)));

        indirect_sample_set_color(indirect_result.smple, initial_color);
        indirect_weight = indirect_sample_weight(indirect_result.smple);

        indirect_result.weight = indirect_weight;
        indirect_result.total_samples = 1.0f;

        vec2 uv = ph_reproject_player_pos(frag_player_pos, frag_is_hand, get_taa_jitter()).xy;
        if (clamp(uv, 0, 1) == uv) {
            ivec2 prev_texel = ivec2(uv * PH_VIEW_SIZE);

            FragData prev_frag;
            frag_data_load_previous(prev_frag, prev_texel);

            if (is_same_plane(prev_frag) && is_same_normal(prev_frag)) {
                IndirectReservoir reuse_indirect = indirect_reservoir_empty();
                if (indirect_reservoir_load_previous(reuse_indirect, prev_texel, true)) {
                    indirect_reservoir_reuse(
                            indirect_result,
                            reuse_indirect,
                            prev_frag,
                            150.0f,
                            indirect_weight
                    );
                }
            }
        }
    }

    indirect_reservoir_finalize_weight(indirect_result, indirect_weight);
    indirect_reservoir_encode(indirect_result, gi_reservoir_0, gi_reservoir_1);
}
