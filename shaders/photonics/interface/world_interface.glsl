#include "/lib/Utility.glsl"
#include "/lib/universal/Uniform.glsl"
#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/SSBO.glsl"

ivec2 texel = ivec2(gl_FragCoord.xy);
vec2 uv = texelToUv(texel) / RENDER_SCALE_HALF;
ivec2 scaledTexel = uvToTexel(uv);

vec3 load_player_position() {
    vec3 screenPos = vec3(uv, loadDepth0(scaledTexel));
    vec3 viewPos = ScreenToViewPos(screenPos);

    return transMAD(gbufferModelViewInverse, viewPos);
}

void load_fragment_data(out vec3 geometry_normal, out vec3 texture_normal) {
    FetchNormalData(scaledTexel, geometry_normal, texture_normal);
}

bool is_in_world() {
    return loadDepth0(scaledTexel) < 1.0f;
}

bool is_hand_at() {
    return loadDepth0(scaledTexel) < 0.56;
}

vec2 get_taa_jitter() {
    #ifdef SHOULD_APPLY_JITTER
        return taaJitter;
    #else
        return vec2(0.0f);
    #endif
}

#define PH_EXPOSURE_ADJUSTMENT
float get_exposure() {
    #if EXPOSURE_MODE == MANUAL
        return exp2(-MANUAL_EV);
    #else
        return exposure.value;
    #endif
}



