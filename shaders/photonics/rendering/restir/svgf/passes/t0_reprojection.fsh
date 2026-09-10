#version 430

#define FRAG_USE_RT_POS
#define FRAG_USE_TEX_NORMAL

#include "/photonics/rendering/frag/common.glsl"
#include "/photonics/rendering/restir/common.glsl"
#include "/photonics/rendering/restir/svgf/common.glsl"

uniform usampler2D prev_temporal_history_frame_count;

layout(location = TEMPORAL_FRAME_OUT) out uint frame_count_out;
layout(location = TEMPORAL_WEIGHTS_OUT) out vec4 sample_weights;

void main() {
    frame_count_out = 0;
    sample_weights = vec4(0.0f);

    setup_frag_data(0);
    if (!frag_is_in_world) return;

    vec2 center = ph_reproject_player_pos(frag_player_pos, frag_is_hand, get_taa_jitter()).xy;
         center.xy *= PH_VIEW_SIZE;
         center.xy -= 0.5f;

    ivec2 texel = ivec2(center.xy);

    const ivec2[4] offsets = ivec2[](ivec2(0, 0), ivec2(1, 0), ivec2(0, 1), ivec2(1, 1));
    const vec2[4] weights = vec2[](vec2(1.0f, 1.0f), vec2(0.0f, 1.0f), vec2(1.0f, 0.0f), vec2(0.0f, 0.0f));

    float frame_count = 0.0f;
    float weight_sum = 0.0f;
    for (int i = 0; i < weights.length(); i++) {
        ivec2 sample_texel = texel + offsets[i];
        uint sample_frame_count = texelFetch(prev_temporal_history_frame_count, sample_texel, 0).r;

        FragData prev_frag;
        frag_data_load_previous(prev_frag, sample_texel);

        if (!is_same_plane(prev_frag)) continue;
        if (!is_same_normal(prev_frag)) continue;

        vec2 mix_weights = abs(weights[i] - fract(center.xy));
        sample_weights[i] = mix_weights.x * mix_weights.y;

        frame_count += float(sample_frame_count) * sample_weights[i];
        weight_sum += sample_weights[i];
    }

    frame_count *= 1.0f / max(0.0001f, weight_sum);
    frame_count = round(frame_count);
    frame_count = min(frame_count + 1, PH_RESTIR_ACCUMULATION_FRAMES);

    frame_count_out = uint(frame_count);
}
