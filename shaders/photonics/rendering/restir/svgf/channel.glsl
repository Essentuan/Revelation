#include "/photonics/utility/color.glsl"

uniform usampler2D temporal_history_frame_count;
uniform sampler2D  temporal_reprojection_weights;

struct DiffuseChannel {
    vec3 color;
    vec3 fast_color;

    vec2 moments;
    float shadow;
};

DiffuseChannel diffuse_channel_empty() {
    return DiffuseChannel(
        vec3(0.0f),
        vec3(0.0f),
        vec2(0.0f),
        0.0f
    );
}

void diffuse_channel_add_sample(inout DiffuseChannel channel, vec4 smple, uint frame_count) {
    const float fast_history_samples = clamp(floor(PH_RESTIR_ACCUMULATION_FRAMES * 0.25f), 1.0f, 8.0f);
    const float min_fast_mix_factor = 1.0f / fast_history_samples;

    float mix_factor = 1.0f / max(float(frame_count), 1.0f);
    channel.color = mix(channel.color, smple.rgb, mix_factor);
    channel.fast_color = mix(channel.fast_color, smple.rgb, max(mix_factor, min_fast_mix_factor));

    float luminance = ph_luminance(smple.rgb);
    channel.moments = mix(channel.moments, vec2(luminance, luminance * luminance), mix_factor);
    channel.moments.y = max(channel.moments.y, frame_count <= 1 ? 100.0f : 0.0f);

    channel.shadow = frame_count < 4 ? 1.0f : mix(channel.shadow, smple.a, mix_factor);

    const float fast_shadow_weight = 1.5f;
    const float fast_light_weight = 1.0f / 1.5f;

    channel.color = clamp(
        channel.color,
        channel.fast_color * fast_light_weight,
        channel.fast_color * fast_shadow_weight
    );
}

void diffuse_channel_encode(DiffuseChannel channel, out uvec4 result) {
    result.x = packHalf2x16(channel.color.xy);
    result.y = packHalf2x16(channel.fast_color.xy);
    result.z = packHalf2x16(vec2(channel.color.z, channel.fast_color.z));
    result.w = packHalf2x16(channel.moments);
}

void diffuse_channel_decode(inout DiffuseChannel channel, uvec4 result) {
    channel.color.xy = unpackHalf2x16(result.x);
    channel.fast_color.xy = unpackHalf2x16(result.y);

    vec2 unpacked = unpackHalf2x16(result.z);
    channel.color.z = unpacked.x;
    channel.fast_color.z = unpacked.y;

    channel.moments = unpackHalf2x16(result.w);
}

ivec2 diffuse_channel_previous_texel() {
    vec2 center = ph_reproject_player_pos(frag_player_pos, frag_is_hand, get_taa_jitter()).xy;
    center.xy *= PH_VIEW_SIZE;
    center.xy -= 0.5f;

    return ivec2(center);
}

void diffuse_channel_accumulate(
        usampler2D prev_channel,
        sampler2D prev_shadow,
        vec4 smple,

        out uvec4 channel_out,
        out float shadow_out
) {
    DiffuseChannel channel = diffuse_channel_empty();

    const ivec2[4] offsets = ivec2[](ivec2(0, 0), ivec2(1, 0), ivec2(0, 1), ivec2(1, 1));
    vec4 offset_weights = texelFetch(temporal_reprojection_weights, frag_tex_coord, 0);
    uint frame_count = texelFetch(temporal_history_frame_count, frag_tex_coord, 0).r;

    ivec2 prev_texel = diffuse_channel_previous_texel();

    float weight_sum = 0.0f;
    for (int i = 0; i < offsets.length(); i++) {
        if (offset_weights[i] == 0.0f) continue;

        ivec2 sample_texel = prev_texel + offsets[i];
        uvec4 sample_data = texelFetch(prev_channel, sample_texel, 0);
        float sample_shadow = texelFetch(prev_shadow, sample_texel, 0).r;

        DiffuseChannel sample_channel;
        diffuse_channel_decode(sample_channel, sample_data);

        channel.color += sample_channel.color * offset_weights[i];
        channel.fast_color += sample_channel.fast_color * offset_weights[i];
        channel.moments += sample_channel.moments * offset_weights[i];
        channel.shadow += sample_shadow * offset_weights[i];

        weight_sum += offset_weights[i];
    }

    weight_sum = 1.0f / max(0.0001f, weight_sum);
    weight_sum *= get_exposure() / get_previous_exposure();

    channel.color *= weight_sum;
    channel.fast_color *= weight_sum;
    channel.moments *= weight_sum;
    channel.shadow *= weight_sum;

    diffuse_channel_add_sample(channel, smple, frame_count);

    diffuse_channel_encode(channel, channel_out);
    shadow_out = channel.shadow;
}

