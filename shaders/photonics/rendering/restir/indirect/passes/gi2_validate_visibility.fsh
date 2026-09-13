#version 430

#define STAGE_FRAGMENT

#include "/photonics/tracing.glsl"
#include "/photonics/rendering/frag/common.glsl"
#include "/photonics/rendering/restir/indirect/reservoir.glsl"

#include "/photonics/modifiers/restir_gi_modifier.glsl"

layout(location = INDIRECT_RESERVOIR_0) out vec4 gi_reservoir_0;
layout(location = INDIRECT_RESERVOIR_1) out uvec3 gi_reservoir_1;
layout(location = INDIRECT_CHANNEL_OUT) out uvec4 gi_output;

void main() {
    gi_output = uvec4(0);

    setup_frag_data(3);
    if (!frag_is_in_world) return;

    vec4 indirect_color = vec4(0.0f);
    IndirectReservoir indirect_result = indirect_reservoir_empty();
    IndirectReservoir reused_reservoir = indirect_reservoir_empty();


    indirect_reservoir_load(reused_reservoir, frag_tex_coord);
    if (reused_reservoir.weight < 100.0f && reused_reservoir.total_samples > 10.0f) {
        indirect_color += vec4(indirect_reservoir_get_final_color(reused_reservoir), 1.0f);
    }

    float rng;
    float indirect_sample_weight = 0.0f;
    indirect_reservoir_merge(indirect_result, reused_reservoir, 1.0f, true, rng, indirect_sample_weight);

#if PH_RESTIR_SPATIAL_REUSE_SAMPLES > 0
    if (indirect_reservoir_load_previous(reused_reservoir, frag_tex_coord, false)) {
        bool visible = indirect_reservoir_validate_visiblity(reused_reservoir, frag_rt_pos);
        indirect_reservoir_merge(indirect_result, reused_reservoir, 1.0f, visible, rng, indirect_sample_weight);

        gi_output.w = floatBitsToUint(indirect_sample_weight == 0.0f ? 1.0f : rng);
    }
#endif

    indirect_reservoir_clamp_samples(indirect_result);
    indirect_reservoir_finalize_weight(indirect_result, indirect_sample_weight);

    indirect_color += vec4(indirect_reservoir_get_final_color(indirect_result), 1.0f);
    indirect_color.rgb /= indirect_color.a;

    #ifndef PH_RESTIR_GI_MODIFIER_DISABLED
        modify_restir_gi(indirect_color.rgb);
    #endif

    gi_output.xyz = floatBitsToUint(indirect_color.rgb);
    indirect_reservoir_encode(indirect_result, gi_reservoir_0, gi_reservoir_1);
}
