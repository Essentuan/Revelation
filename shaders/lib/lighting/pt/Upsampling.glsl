#include "/photonics/samplers.glsl"

#if RENDER_SCALE >= 1.0

#include "/photonics/uniforms.glsl"
#include "/photonics/rendering/frag/frag_data.glsl"

vec3 UpscaleDiffuse(vec2 coord, vec3 worldPos, vec3 worldNormal, vec3 geoNormal, bool handMask) {
    vec3 sum = vec3(0.0);
    float sumWeight = 0.0;

    ivec2 texelEnd = ivec2(scaledHalfViewSize);
    coord = coord * scaledViewSize * 0.5 - 0.5;

    ivec2 floorTexel = ivec2(floor(coord));
    vec2 fractTexel = coord - vec2(floorTexel);

    vec4 bilinearWeight = bilinear(fractTexel);

    for (uint i = 0u; i < 4u; ++i) {
        ivec2 sampleTexel = clamp(floorTexel + offset2x2[i], ivec2(1), texelEnd);

        FragData sampleFrag;
        frag_data_load(sampleFrag, sampleTexel);

        #define plane_dist dot(worldPos - frag_data_player_pos(sampleFrag), geoNormal)

        float weight = handMask ? float(frag_data_is_hand(sampleFrag)) : step(abs(plane_dist), 0.25f);
        weight *= pow4(saturate(dot(frag_data_tex_normal(sampleFrag), worldNormal)));
        weight *= bilinearWeight[i];

        vec3 sampleLight = uintBitsToFloat(texelFetch(denoise_result, sampleTexel, 0).rgb);

        sum += sampleLight * weight;
        sumWeight += weight;
    }

    if (sumWeight < EPS) return vec3(0.0);

    return sum * rcp(sumWeight);
}

#else
vec3 UpscaleDiffuse(vec2 coord, vec3 worldPos, vec3 worldNormal, vec3 geoNormal, bool handMask) {
    return sample_photonics_direct(coord);
}

#endif
