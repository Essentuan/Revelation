#version 430

#define STAGE_FRAGMENT

#include "/photonics/tracing.glsl"
#include "/photonics/rendering/frag/common.glsl"
#include "/photonics/rendering/restir/indirect/reservoir.glsl"
#include "/photonics/rendering/restir/svgf/channel.glsl"

#include "/photonics/modifiers/restir_gi_modifier.glsl"

layout(location = INDIRECT_RESERVOIR_0) out vec4 gi_reservoir_0;
layout(location = INDIRECT_RESERVOIR_1) out uvec3 gi_reservoir_1;

uniform usampler2D prev_gi_temporal_history;
uniform sampler2D prev_gi_shadow_history;

layout(location = INDIRECT_CHANNEL_OUT) out uvec4 gi_temporal_out;
layout(location = INDIRECT_SHADOW_OUT) out float gi_shadow_out;

void main() {
    gi_temporal_out = uvec4(0);
    gi_shadow_out = 0.0f;

    setup_frag_data(3);
    if (!frag_is_in_world) return;

    vec4 indirect_sample = vec4(0.0f);
    float shadow_sample = 0.0f;

    IndirectReservoir indirect_result = indirect_reservoir_empty();
    IndirectReservoir reused_reservoir = indirect_reservoir_empty();

    indirect_reservoir_load(reused_reservoir, frag_tex_coord);
    if (reused_reservoir.weight < 100.0f && reused_reservoir.total_samples > 10.0f) {
        indirect_sample += vec4(indirect_reservoir_get_final_color(reused_reservoir), 1.0f);
    }

    float rng;
    float indirect_sample_weight = 0.0f;
    indirect_reservoir_merge(indirect_result, reused_reservoir, 1.0f, true, rng, indirect_sample_weight);

#if PH_RESTIR_SPATIAL_REUSE_SAMPLES > 0
    if (indirect_reservoir_load_previous(reused_reservoir, frag_tex_coord, false)) {
        bool visible = indirect_reservoir_validate_visiblity(reused_reservoir, frag_rt_pos);
        indirect_reservoir_merge(indirect_result, reused_reservoir, 1.0f, visible, rng, indirect_sample_weight);

        shadow_sample = indirect_sample_weight == 0.0f ? 1.0f : rng;
    }
#endif

    indirect_reservoir_clamp_samples(indirect_result);
    indirect_reservoir_finalize_weight(indirect_result, indirect_sample_weight);

    indirect_sample += vec4(indirect_reservoir_get_final_color(indirect_result), 1.0f);
    indirect_sample.rgb /= indirect_sample.a;

    #ifndef PH_RESTIR_GI_MODIFIER_DISABLED
        modify_restir_gi(indirect_sample.rgb);
    #endif

    indirect_reservoir_encode(indirect_result, gi_reservoir_0, gi_reservoir_1);

    diffuse_channel_accumulate(
        prev_gi_temporal_history,
        prev_gi_shadow_history,
        vec4(indirect_sample.rgb, shadow_sample),

        gi_temporal_out,
        gi_shadow_out
    );
}
