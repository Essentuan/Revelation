#version 430

#define USE_FRAG_RT_POS
#define USE_FRAG_GEO_NORMAL
#define USE_FRAG_TEX_NORMAL

#include "/photonics/rendering/frag/common.glsl"
#include "/photonics/rendering/restir/direct/pbr/reservoir.glsl"
#include "/photonics/rendering/restir/neighbor/reservoir.glsl"

layout(location = DIRECT_RESERVOIR_0) out vec4 di_reservoir_0;
layout(location = DIRECT_RESERVOIR_1) out uvec3 di_reservoir_1;

void main() {
    setup_frag_data(2);
    if (!frag_is_in_world) discard;

//    float reservoir_data = texelFetch(prev_di_reservoirs0, frag_tex_coord, 0).a;

    uvec4 samples;
    neighbor_load_samples(frag_tex_coord, samples);

    float direct_sample_weight = 0.0f;
    DirectReservoir direct_result = direct_reservoir_empty();
    DirectReservoir reuse_direct = direct_reservoir_empty();

//    int max_samples = direct_reservoir_is_disoccluded(reservoir_data) ? PH_RESTIR_SPATIAL_REUSE_SAMPLES : 1;
    for (int i = 0; i < PH_RESTIR_SPATIAL_REUSE_SAMPLES; i++) {
        if (samples[i] != 0) {
            ivec2 sample_texel = neighbor_next_sample(samples[i]);
            if (!direct_reservoir_load_previous(reuse_direct, sample_texel, false)) continue;

            FragData sample_frag;
            frag_data_load(sample_frag, sample_texel);

            direct_reservoir_reuse(
                direct_result,
                reuse_direct,
                sample_frag,
                50.0f,
                direct_sample_weight
            );
        }
    }

    direct_reservoir_finalize_weight(direct_result, direct_sample_weight);
    direct_reservoir_encode(direct_result, di_reservoir_0, di_reservoir_1);
}
