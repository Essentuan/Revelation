#version 430

#include "/photonics/rendering/frag/common.glsl"
#include "/photonics/rendering/restir/common.glsl"
#include "/photonics/rendering/indirect_lighting.glsl"

layout(location = 0) out vec4 hit_data;
layout(location = 1) out vec3 initial_direct;
layout(location = 2) out vec3 initial_indirect;

void main() {
    setup_frag_data(0);
    if (!frag_is_in_world) discard;

    initial_direct = vec3(0.0f);
    initial_indirect = vec3(0.0f);

    vec3 hit_normal;

    // Needs this for compatability
    uint rnd_state = frag_rnd_state;
    sample_indirect(
        initial_direct,
        initial_indirect,

        frag_rt_pos,
        frag_tex_normal,
        rnd_state,

        hit_data.xyz,
        hit_normal
    );

    if (isinf(hit_data.x)) {
        vec3 direction = ph_rand_direction(frag_rnd_state, frag_tex_normal);
        hit_data.xyz = frag_rt_pos + (direction * restir_sky_distance);
    }

    hit_data.w = uintBitsToFloat(ph_pack_normal(hit_normal));

    float exposure = get_exposure();
    initial_direct *= exposure;
    initial_indirect *= exposure;

    initial_direct = clamp(initial_direct, 0.0f, FP16_MAX);
    initial_indirect = clamp(initial_indirect, 0.0f, FP16_MAX);
}
