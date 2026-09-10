#version 430

#include "/photonics/rendering/frag/common.glsl"
#include "/photonics/rendering/restir/direct/pbr/reservoir.glsl"
#include "/photonics/rendering/restir/svgf/channel.glsl"

uniform usampler2D di_temporal_history;
uniform usampler2D prev_di_temporal_history;
uniform usampler2D prev_di_shadow_history;

layout(location = DIRECT_CHANNEL_OUT) out uvec4 di_temporal_out;
layout(location = DIRECT_SHADOW_OUT) out float di_shadow_out;

void main() {
    di_temporal_out = uvec4(0);
    di_shadow_out = 0.0f;

    setup_frag_data(0);
    if (!frag_is_in_world) return;

    diffuse_channel_accumulate(
        prev_di_temporal_history,
        prev_di_shadow_history,
        uintBitsToFloat(texelFetch(di_temporal_history, frag_tex_coord, 0)),

        di_temporal_out,
        di_shadow_out
    );
}
