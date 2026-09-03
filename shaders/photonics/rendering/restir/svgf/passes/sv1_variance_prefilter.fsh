#version 430

#include "/photonics/rendering/frag/common.glsl"
#include "/photonics/rendering/restir/common.glsl"
#include "/photonics/rendering/restir/svgf/common.glsl"
#include "/photonics/rendering/restir/svgf/channel.glsl"

struct SvgfSample {
    vec3 center;
    vec3 maxNeighbor;

    float variance;
};

void svgf_sample_filter_neighbor(inout SvgfSample smple, uvec4 packed_channel, int index) {
    DiffuseChannel channel;
    diffuse_channel_decode(channel, packed_channel);

    if (index == SVGF_CENTER_INDEX) {
        smple.center = channel.color;
    } else {
        smple.maxNeighbor = max(smple.maxNeighbor, channel.color);
    }

     smple.variance += channel.moments.y - (channel.moments.x * channel.moments.x);
}

void svgf_sample_finalize(inout SvgfSample smple) {
    smple.center = min(min(smple.center, smple.maxNeighbor), 65504.0);
    smple.variance = frag_is_hand ? 100.0f : min(smple.variance / 9.0f, 65504.0);
}

uniform usampler2D di_temporal_history;
uniform usampler2D gi_temporal_history;

uniform sampler2D di_shadow_history;
uniform sampler2D gi_shadow_history;

layout(location = SVGF_RESULT_OUT) out uvec4 denoise_out;
layout(location = SVGF_DATA_OUT) out uvec4 denoise_data_out;

void main() {
    denoise_out = uvec4(0);
    denoise_data_out = uvec4(floatBitsToUint(0x7f800000));
    float depth = load_depth();

    setup_frag_data(0);
    if (!frag_is_in_world) return;

    float di_shadow = texelFetch(di_shadow_history, frag_tex_coord, 0).r;
    float gi_shadow =   texelFetch(gi_shadow_history, frag_tex_coord, 0).r;

    SvgfSample direct = SvgfSample(vec3(0.0f), vec3(0.0f), 0.0f);
    SvgfSample indirect = SvgfSample(vec3(0.0f), vec3(0.0f), 0.0f);

    for (int i = 0; i < 9; i++) {
        ivec2 p = frag_tex_coord + offset[i];

        uvec4 di_channel = texelFetch(di_temporal_history, p, 0);
        uvec4 gi_channel = texelFetch(gi_temporal_history, p, 0);

        svgf_sample_filter_neighbor(direct, di_channel, i);
        svgf_sample_filter_neighbor(indirect, gi_channel, i);
    }

    svgf_sample_finalize(direct);
    svgf_sample_finalize(indirect);

    denoise_data_out.x = floatBitsToUint(ph_linearize_depth(depth));
    denoise_data_out.y = svgf_pack_shadow_normal(di_shadow, gi_shadow, frag_is_hand ? _frag_data.data1.y : _frag_data.data1.z);

    denoise_data_out.z = packHalf2x16(vec2(ph_luminance(direct.center), direct.variance));
    denoise_out.xy = svgf_pack_color(direct.center);

    denoise_data_out.w = packHalf2x16(vec2(ph_luminance(indirect.center), indirect.variance));
    denoise_out.zw = svgf_pack_color(indirect.center);
}
