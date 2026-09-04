#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Common.glsl"
#include "/lib/atmosphere/Celestial.glsl"
#include "/lib/atmosphere/clouds/Common.glsl"

#include "/lib/lighting/shadow/Render.glsl"

struct DiffuseState {
    vec3 runningColor;
    uint lastColor;
};

DiffuseState DiffuseStateEmpty() {
    return DiffuseState(vec3(1.0f), 0u);
}

void DiffuseStateApplyWeight(inout DiffuseState state, float weight) {
    state.runningColor *= weight;
}

void DiffuseStateApplySurface(inout DiffuseState state, vec4 surface) {
    state.runningColor *= surface.rgb;
}

bool DiffuseStateApplyTranslucency(
    inout DiffuseState state,
    inout RayIterator itr,

    RayResult hit,
    vec3 geoNormal,

    VoxelData voxelData,
    vec4 albedo,
    vec4 specular,
    inout uint rndState
) {
    const uint ALPHA_MASK = 0xffffffu;

    if (!ray_result_is_transparent(hit)) return false;
    if (state.lastColor == (voxelData.y & ALPHA_MASK)) return true;

    if (specular.a < 1.0f && specular.a > 0.0001f && ph_rand_next_float(rndState) > albedo.a) {
        DiffuseStateApplyWeight(state, 1.0f / albedo.a);
        return false;
    }

    albedo.rgb = sRGBToLinear(albedo.rgb) * sRGB_2_Rec2020;
    state.runningColor *= exp2(log2(albedo.rgb * oms(0.125 * albedo.a)) * approxSqrt(albedo.a + 0.25));
    state.lastColor = voxelData.y & ALPHA_MASK;

    // Refraction
    vec3 tang = geoNormal.y != 0 ? vec3(-1.,0.,0.) : geoNormal.z != 0 ? vec3(-1.,0.,0.) : vec3(0.,0.,-1.);
    vec3 bitan = geoNormal.y != 0 ? vec3(0.,0.,-1.) : geoNormal.z != 0 ? vec3(0.,-1.,0.) : vec3(0.,-1.,0.);

    mat3 tbn = mat3(tang.xyz, bitan.xyz, geoNormal.xyz);
    vec3 normal = normalize(tbn * voxel_data_normal(voxelData).xyz);

    itr.direction = refract(itr.direction, normal, 1.0f / GLASS_IOR);

    return true;
}

vec3 DiffuseStateCalculateRadiance(DiffuseState state, vec4 surface, vec4 specular) {
    if (specular.a == 1.0f || specular.a < 0.0001f) return vec3(0.0f);

    specular.a = pow(specular.a, EMISSIVE_CURVE) * EMISSIVE_BRIGHTNESS;
    specular.a *= luminance(surface.rgb) * 4.0;

    return sRGBToLinearApprox(surface.rgb) * specular.a * state.runningColor;
}

vec3 DiffuseStateCalculateSunLight(DiffuseState state, vec3 rtPos, vec3 normal, float skylight, inout uint rndState) {
    const float skylight_cutoff = 4.0f / 15.0f;
    if (skylight < skylight_cutoff) return vec3(0.0f);

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
