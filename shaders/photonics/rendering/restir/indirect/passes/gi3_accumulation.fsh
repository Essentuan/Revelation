#version 430

#include "/photonics/rendering/frag/common.glsl"
#include "/photonics/rendering/restir/indirect/reservoir.glsl"
#include "/photonics/rendering/restir/svgf/channel.glsl"

uniform usampler2D gi_temporal_history;
uniform usampler2D prev_gi_temporal_history;
uniform usampler2D prev_gi_shadow_history;

layout(location = INDIRECT_CHANNEL_OUT) out uvec4 gi_temporal_out;
layout(location = INDIRECT_SHADOW_OUT) out float gi_shadow_out;

void main() {
    gi_temporal_out = uvec4(0);
    gi_shadow_out = 0.0f;

    setup_frag_data(0);
    if (!frag_is_in_world) return;

    diffuse_channel_accumulate(
            prev_gi_temporal_history,
            prev_gi_shadow_history,
            uintBitsToFloat(texelFetch(gi_temporal_history, frag_tex_coord, 0)),

            gi_temporal_out,
            gi_shadow_out
    );
}
