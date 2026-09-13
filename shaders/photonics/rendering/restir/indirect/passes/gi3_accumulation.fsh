#version 430

#include "/photonics/rendering/frag/common.glsl"
#include "/photonics/rendering/restir/indirect/reservoir.glsl"
#include "/photonics/rendering/restir/svgf/common.glsl"
#include "/photonics/rendering/restir/svgf/channel.glsl"

uniform usampler2D gi_temporal_history;
uniform sampler2D gi_shadow_history;

layout(location = INDIRECT_CHANNEL_OUT) out uvec4 gi_temporal_out;

void main() {
    uint frame_count = texelFetch(temporal_history_frame_count, frag_tex_coord, 0).r;

    setup_frag_data(0);
    if (!frag_is_in_world) discard;
    if (frame_count < 8) discard;

    DiffuseChannel channel;
    float maxConfidence = 0.0f;

    float shadow = texelFetch(gi_shadow_history, frag_tex_coord, 0).r;

    for (int i = 0; i < 9; i++) {
        ivec2 sample_texel = frag_tex_coord + offset[i];
        uvec4 sample_data = texelFetch(gi_temporal_history, sample_texel, 0);

        DiffuseChannel sample_channel;
        diffuse_channel_decode(sample_channel, sample_data);

        if (i == SVGF_CENTER_INDEX) channel = sample_channel;

        float confidence = diffuse_channel_calculate_confidence(sample_channel, shadow * 0.5f);
        maxConfidence = max(confidence, maxConfidence);
    }

    channel.color = mix(channel.fast_color, channel.color, maxConfidence);
    diffuse_channel_encode(channel, gi_temporal_out);
}
