#version 430

#include "/photonics/rendering/frag/common.glsl"
#include "/photonics/rendering/restir/common.glsl"
#include "/photonics/rendering/restir/svgf/common.glsl"
#include "/photonics/rendering/restir/svgf/channel.glsl"

uniform usampler2D di_temporal_history;
uniform usampler2D gi_temporal_history;
uniform usampler2D denoise_result;

layout(location = SVGF_RESULT_OUT) out uvec3 denoise_out;

#define frag_tex_coord ivec2(gl_FragCoord.xy)

vec3 fetch_color(usampler2D sampler) {
    uvec4 smple = texelFetch(sampler, frag_tex_coord, 0);

    DiffuseChannel channel;
    diffuse_channel_decode(channel, smple);

    return channel.color;
}

void main() {
    denoise_out = uvec3(0u);

    setup_frag_data(0);
    if (!frag_is_in_world) return;

#if PH_RESTIR_DENOISER_PASSES > 0
    vec3 result_color = vec3(0.0f);
    uvec4 denoise_data = texelFetch(denoise_result, frag_tex_coord, 0);

    result_color += svgf_unpack_color(denoise_data.xy);
    result_color += svgf_unpack_color(denoise_data.zw);
#else
    vec3 result_color = vec3(0.0f);

#if defined PH_ENABLE_BLOCKLIGHT
    result_color += fetch_color(di_temporal_history);
#endif

#if defined PH_ENABLE_RESTIR_GI
    result_color += fetch_color(gi_temporal_history);
#endif

#endif

    denoise_out = floatBitsToUint(result_color / get_exposure());
}
