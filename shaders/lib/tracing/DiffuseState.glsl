#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Common.glsl"
#include "/lib/atmosphere/Celestial.glsl"
#include "/lib/atmosphere/clouds/Common.glsl"

#include "/lib/lighting/shadow/Render.glsl"

struct DiffuseState {
    vec3 runningColor;
};

DiffuseState DiffuseStateEmpty() {
    return DiffuseState(vec3(1.0f));
}

void DiffuseStateApplyWeight(inout DiffuseState state, float weight) {
    state.runningColor *= weight;
}

void DiffuseStateApplySurface(inout DiffuseState state, vec4 surface) {
    state.runningColor *= surface.rgb;
}

void DiffuseStateApplyTranslucency(inout DiffuseState state, vec4 surface) {
    state.runningColor *= surface.rgb;
}

vec3 DiffuseStateCalculateRadiance(DiffuseState state, vec4 surface, vec4 specular) {
    if (specular.a == 1.0f) return vec3(0.0f);

    return surface.rgb * specular.a * 10.0f * state.runningColor;
}

vec3 DiffuseStateCalculateSunLight(DiffuseState state, vec3 rtPos, vec3 normal, float skylight, inout uint rndState) {
    float NdotL = dot(normal, shadowDirWorld);
    if (NdotL <= 0.0f) return vec3(0.0f);

    rtPos -= rt_camera_position;

    vec3 shadow = vec3(NdotL);
    float dither = ph_rand_next_float(rndState);

    // Cloud shadows
    #ifdef CLOUD_SHADOWS
        // float cloudShadow = CalculateCloudShadows(worldPos);
        vec2 cloudShadowCoord = WorldToCloudShadowScreenPos(rtPos).xy + (dither - 0.5) / textureSize(cloudShadowTex, 0);
        shadow *= textureBicubic(cloudShadowTex, saturate(cloudShadowCoord)).x;
    #else
        shadow *= 1.0 - wetness * 0.96;
    #endif

    float ignored;
    shadow *= CalculatePCSS(rtPos, normal * 0.01f, dither, ignored);

    return global.directIlluminance * shadow * state.runningColor;
}

vec3 DiffuseStateCalculateSkyLight(DiffuseState state, vec3 rtPos, vec3 rayDir) {
    return textureBicubic(skyEnvMapTex, saturate(ProjectCubemap(rayDir, 96.0))).rgb * state.runningColor;
}
