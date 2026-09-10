#version 430

#include "/photonics/tracing.glsl"
#include "/photonics/rendering/frag/common.glsl"
#include "/photonics/rendering/restir/direct/pbr/reservoir.glsl"

#include "/photonics/modifiers/restir_gi_modifier.glsl"

layout(location = DIRECT_RESERVOIR_0) out vec4 di_reservoir_0;
layout(location = DIRECT_RESERVOIR_1) out uvec3 di_reservoir_1;
layout(location = DIRECT_CHANNEL_OUT) out uvec4 di_output;

void main() {
    di_output = uvec4(0u);

    setup_frag_data(3);
    if (!frag_is_in_world) return;

    float direct_sample_weight = 0.0f;
    DirectReservoir direct_result = direct_reservoir_empty();
    DirectReservoir reused_reservoir = direct_reservoir_empty();

    float rng;
    direct_reservoir_load(reused_reservoir, frag_tex_coord);
    direct_reservoir_merge(direct_result, reused_reservoir, 1.0f, rng, direct_sample_weight);

#if PH_RESTIR_SPATIAL_REUSE_SAMPLES > 0
    if (direct_reservoir_load_previous(reused_reservoir, frag_tex_coord, false)) {
        direct_reservoir_validate_visiblity(reused_reservoir, frag_rt_pos);
        direct_reservoir_merge(direct_result, reused_reservoir, 1.0f, rng, direct_sample_weight);

        di_output.w = floatBitsToUint(direct_sample_weight == 0.0f ? 1.0f : rng);
    }
#endif

    direct_reservoir_clamp_samples(direct_result);
    direct_reservoir_finalize_weight(direct_result, direct_sample_weight);
    direct_reservoir_encode(direct_result, di_reservoir_0, di_reservoir_1);

    di_output.xyz = floatBitsToUint(direct_reservoir_get_final_color(direct_result));
}
