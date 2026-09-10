#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Common.glsl"
#include "/lib/atmosphere/Celestial.glsl"
#include "/lib/atmosphere/clouds/Common.glsl"

#include "/lib/lighting/shadow/Render.glsl"

#include "/lib/lighting/pt/Tracing.glsl"

struct PathState {
    vec3 runningColor;
    uint lastColor;
};

PathState PathStateEmpty()  {
    return PathState(vec3(1.0f), 0u);
}

void PathStateAcceptWeight(inout PathState path, float weight) {
    path.runningColor *= weight;
}

void PathStateAcceptSurface(inout PathState path, vec4 surface) {
    path.runningColor *= pow(surface.rgb, vec3(2.2f));
}

bool PathStateAcceptTranslucent(
    inout PathState path,
    inout Ray ray,

    RayResult hit,
    vec3 geoNormal,

    VoxelData voxelData,
    vec4 albedo,
    vec4 specular,
    inout uint rndState
) {
    const uint ALPHA_MASK = 0xffffffu;

    if (!RayResultIsTransparent(hit)) return false;
    if (path.lastColor == (voxelData.y & ALPHA_MASK)) return true;

    if (specular.a < 1.0f && specular.a > 0.0001f && ph_rand_next_float(rndState) > albedo.a) {
        PathStateAcceptWeight(path, 1.0f / albedo.a);
        return false;
    }

    albedo.rgb = sRGBToLinear(albedo.rgb) * sRGB_2_Rec2020;
    path.runningColor *= exp2(log2(albedo.rgb * oms(0.125 * albedo.a)) * approxSqrt(albedo.a + 0.25));
    path.lastColor = voxelData.y & ALPHA_MASK;

    // Refraction
    ray.direction = refract(ray.direction, VoxelDataNormal(voxelData, geoNormal).xyz, 1.0f / GLASS_IOR);

    return true;
}


vec3 PathStateApplyTo(PathState path, vec3 radiance) {
    return path.runningColor * radiance;
}

vec3 PathStateCalculateBlockRadiance(PathState state, vec4 albedo, vec4 specular) {
    specular.a = pow(specular.a, EMISSIVE_CURVE) * EMISSIVE_BRIGHTNESS;
    specular.a *= luminance(albedo.rgb) * 4.0;
    albedo.rgb = pow(albedo.rgb, vec3(2.2f));

    return PathStateApplyTo(state, albedo.rgb * specular.a);
}

vec3 PathStateCalculateSunRadiance(PathState path, vec3 rtPos, vec3 normal, float skylight, inout uint rndState) {
    float NdotL = dot(normal, shadowDirWorld);
    if (NdotL <= 0.0f) return vec3(0.0f);

    rtPos -= rt_camera_position;

    vec3 shadow = vec3(NdotL);
    shadow *= saturate(skylight * 1e6 + float(isEyeInWater));

    float dither = ph_rand_next_float(rndState);

    // Cloud shadows
    #ifdef CLOUD_SHADOWS
        vec2 cloudShadowCoord = WorldToCloudShadowScreenPos(rtPos).xy + (dither - 0.5) / textureSize(cloudShadowTex, 0);
        shadow *= textureBicubic(cloudShadowTex, saturate(cloudShadowCoord)).x;
    #else
        shadow *= 1.0 - wetness * 0.96;
    #endif

    float ignored;
    shadow *= CalculatePCSS(rtPos, normal * 0.01f, dither, ignored);

    return PathStateApplyTo(path, global.directIlluminance * shadow);
}

vec3 PathStateCalculateSkyRadiance(PathState path, vec3 rayDir) {
    return PathStateApplyTo(path, textureBicubic(skyEnvMapTex, saturate(ProjectCubemap(rayDir, 96.0))).rgb);
}
