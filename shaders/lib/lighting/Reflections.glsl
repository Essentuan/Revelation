#include "/lib/lighting/SSRT.glsl"
#include "/lib/universal/MonteCarlo.glsl"

#include "/lib/lighting/pt/IrCache.glsl"
#include "/lib/lighting/pt/Tracing.glsl"
#include "/lib/lighting/pt/State.glsl"

bool TraceScreenSpaceReflection(
    float roughness,

    vec3 viewPos,
    vec3 rayDir,
    float dither,

    out vec4 reflection,
    inout vec3 skyTint
) {
    uint stepCount = uint(SSRT_MAX_SAMPLES * oms(roughness * 0.75));
    vec3 hitPos;
    if (!ScreenSpaceRaytrace(viewPos, mat3(gbufferModelView) * rayDir, dither, stepCount, hitPos)) return false;

    ivec2 texel = uvToTexelScaled(hitPos.xy);
    float hitDepth = loadDepth0(texel);
    if (hitDepth < 0.56f) return false;

    reflection.rgb = texture(colortex4, scaleScreenUv(hitPos.xy)).rgb;

    vec3 reflectViewPos = ScreenToViewPos(vec3(hitPos.xy, hitDepth));
    reflection.a = distance(reflectViewPos, viewPos);

    return true;
}

bool TracePtReflection(
    float roughness,

    vec3 viewPos,
    vec3 rayDir,
    float dither,

    out vec4 reflection,
    inout vec3 skyTint
) {
    vec3 worldPos = transMAD(gbufferModelViewInverse, viewPos);
    Ray ray = CreateRay(worldPos + rt_camera_position, rayDir);

    PathState path = PathStateEmpty();

    RayResult lastHit = RayResultEmpty();
    VoxelData lastVoxelData = VoxelDataEmpty();

    uint rndState = floatBitsToUint(dither) * 3457;

    #define MAX_INTERACTIONS 16
    for (int i = 0; i < MAX_INTERACTIONS; i++) {
        RayOffsetPosition(ray, ray.direction * 0.03f);
        lastHit = RayNext(ray);

        if (!RayResultIsHit(lastHit)) {
            skyTint = PathStateApplyTo(path, vec3(float(ray.iterations > 0)));
            return false;
        }

        vec3 hitNormal = RayResultNormal(lastHit);

        lastVoxelData = RayResultVoxelData(lastHit);
        vec4 albedo = VoxelDataAlbedo(lastVoxelData);
        vec4 specular = VoxelDataSpecular(lastVoxelData);

        if (!PathStateAcceptTranslucent(path, ray, lastHit, hitNormal, lastVoxelData, albedo, specular, rndState))
            break;

        RaySkipBlock(ray);
        RayOffsetPosition(ray, ray.direction * 0.1f);
    }

    vec3 hitWorldPos = RayResultPosition(lastHit) - rt_camera_position;
    vec3 hitNormal = RayResultNormal(lastHit);
    float hitSkylight = RayResultSkylight(lastHit);

    vec4 hitAlbedo = VoxelDataAlbedo(lastVoxelData);
    hitAlbedo.rgb = sRGBToLinear(hitAlbedo.rgb) * sRGB_2_Rec2020;

    vec4 hitSpecularTex = VoxelDataSpecular(lastVoxelData);

    vec3 hitWorldDir = normalize(hitWorldPos - worldPos);
    float ao = VoxelDataNormal(lastVoxelData, hitNormal).a;

    Material hitMaterial = GetMaterialData(hitSpecularTex, hitAlbedo.rgb);
    uint materialID = VoxelDataMaterialId(lastVoxelData);

    float sssAmount = 0.0;
    { // Subsurface Scattering
        #if SUBSURFACE_SCATTERING_MODE < 2
        // Hard-coded sss amount for certain materials
            switch (materialID) {
                case 1000u: case 1001u: case 1002u: case 1003u: case 27u: case 28u: // Plants
                    sssAmount = 0.6;
                    break;
                case 13u: // Leaves
                    sssAmount = 0.8;
                    break;
                case 37u: case 39u: // Weak SSS
                    sssAmount = 0.5;
                    break;
                case 38u: case 51u: // Strong SSS
                    sssAmount = 0.8;
                    break;
                case 40u: // Particles
                    sssAmount = 0.3;
                    break;
            }
        #endif

        #if TEXTURE_FORMAT == 0 && SUBSURFACE_SCATTERING_MODE > 0 && defined MC_SPECULAR_MAP
            sssAmount = max(sssAmount, hitSpecularTex.b * step(64.5 * rcp255, hitSpecularTex.b));
        #endif

        // Remap sss amount to [0, 1] range
        sssAmount = linearstep(64.0 * rcp255, 1.0, sssAmount) * eyeSkylightSmooth * SUBSURFACE_SCATTERING_STRENGTH;
    }

    float cloudShadow = 1.0f;
    { // Cloud shadows
        #ifdef CLOUD_SHADOWS
        // float cloudShadow = CalculateCloudShadows(worldPos);
            vec2 cloudShadowCoord = WorldToCloudShadowScreenPos(hitWorldPos).xy + (dither - 0.5) / textureSize(cloudShadowTex, 0);
            cloudShadow  = textureBicubic(cloudShadowTex, saturate(cloudShadowCoord)).x;
        #else
            cloudShadow = 1.0 - wetness * 0.96;
        #endif
    }

    vec3 diffuseRadiance = vec3(0.0f);
    vec3 specularRadiance = vec3(0.0f);

    vec3 sunlightBase = cloudShadow * saturate(hitSkylight * 1e6 + float(isEyeInWater)) * global.directIlluminance;
    vec3 shadow = vec3(0.0f);

    float NdotV = dot(hitNormal, -hitWorldDir);
    float NdotL = dot(hitNormal, shadowDirWorld);
    float LdotV = dot(shadowDirWorld, - hitWorldDir);

    // Must use unclamped NdotL & NdotV
    float invLenH = inversesqrt(2.0 + 2.0 * LdotV);
    float NdotH = saturate((NdotL + NdotV) * invLenH);
    float VdotH = saturate(LdotV * invLenH + invLenH);
    NdotL = saturate(NdotL);
    NdotV = saturate(NdotV);

    // Shadows and SSS
    if (NdotL + sssAmount > EPS) {
        shadow = vec3(saturate(NdotL * FLT_MAX));
        float surfaceDepth = 0.0;

        const float normalOffsetBase = 0.03f;

        // PCSS
        shadow *= CalculatePCSS(hitWorldPos, hitNormal * normalOffsetBase, dither, surfaceDepth);

        // Subsurface scattering
        if (sssAmount > EPS) {
            vec3 beta = approxSqrt(saturate(normalize(hitAlbedo.rgb)));
            vec3 sigmaA = oms(beta) * 8.0 / (sssAmount * SUBSURFACE_SCATTERING_STRENGTH);
            vec3 sigmaS = 2.0 * beta * sssAmount;

            float phase = HenyeyGreensteinPhase(-LdotV, 0.7) * 0.25 + uniformPhase * 0.75;
            vec3 sss = sigmaS * phase * exp2(-rLOG2 * surfaceDepth * (sigmaS + sigmaA));

            float cutout = float(clamp(materialID, 1000u, 1003u) == materialID || clamp(materialID, 27u, 28u) == materialID);
            diffuseRadiance += sunlightBase * sss * SUBSURFACE_SCATTERING_BRIGHTNESS;
        }

        if (dot(shadow, vec3(1.0)) > EPS) {
            shadow *= sunlightBase;

            diffuseRadiance += shadow * DiffuseHammon(NdotV, NdotL, VdotH, NdotH, hitMaterial.roughness, hitAlbedo.rgb) * NdotL;
            specularRadiance += shadow * SpecularGGX(VdotH, NdotV, NdotL, NdotH, hitMaterial.roughness, hitMaterial.reflectance) * NdotL;
        }
    }

    // Spherical harmonics skylight
    vec3 skyRadiance = ConvolvedReconstructSH3(global.skySH, hitNormal);
    vec3 fakeSkylight = skyRadiance * cube(hitSkylight) * ao * 0.5f;

    { // Skylight & Blocklight
        ivec3 ircTexel = WorldPosToIrcTexel(hitWorldPos + hitNormal * 0.03f);
        if (IrcContainsTexel(ircTexel)) {
            IrcEntry ircEntry = IrcLoad(ircTexel);
            diffuseRadiance += IrcEntryCalculateRadiance(
                ircEntry,
                global.directIlluminance * (saturate(shadow) * 0.2f + 0.8f),
                skyRadiance * PI
            ) * rPI;
        } else if (hitSkylight > EPS){
            diffuseRadiance += fakeSkylight;

            // Fake bounced light
            float bounce = CalculateFakeBouncedLight(hitNormal);
            diffuseRadiance += bounce * pow5(hitSkylight) * sunlightBase * ao;
        }
    }

    // Minimal ambient light
    diffuseRadiance += (hitNormal.y * 0.4 + 0.6) * max(MINIMUM_AMBIENT_BRIGHTNESS, 5e-3 * nightVision) * ao;

    // Apply diffuse color (baseColor * (1 - metallic))
    hitMaterial.metallic *= 0.2 * hitSkylight + 0.8;
    diffuseRadiance *= hitAlbedo.rgb * oms(hitMaterial.metallic);

    // Indirect specular
    if (hitMaterial.specularMask) {
        vec2 brdf = texture(envBRDFTex, vec2(hitMaterial.roughness, NdotV)).xy;

        vec3 specular = hitMaterial.reflectance * brdf.x + brdf.y;
        specularRadiance += diffuseRadiance * specular;
    }

    // Emissive
    #if EMISSIVE_MODE > 0 && defined MC_SPECULAR_MAP
        diffuseRadiance += hitMaterial.emissive * hitAlbedo.rgb;
    #endif

    #if EMISSIVE_MODE < 2
        // Hard-coded emissive
        diffuseRadiance += HardCodeEmissive(materialID, hitAlbedo.rgb, hitWorldPos) * EMISSIVE_BRIGHTNESS * hitAlbedo.rgb;
    #endif


    reflection.rgb = PathStateApplyTo(path, diffuseRadiance + specularRadiance);
    reflection.a = distance(worldPos, hitWorldPos);

    return true;
}

bool TraceSkyReflection(
    float roughness,

    vec3 viewPos,
    vec3 rayDir,
    float dither,

    out vec4 reflection,
    inout vec3 skyTint
) {
    reflection.rgb  = textureBicubic(skyEnvMapTex, saturate(ProjectCubemap(rayDir, 96.0))).rgb;
    reflection.rgb *= skyTint;

    reflection.a = FP16_MAX;

    return true;
}


vec4 CalculateSpecularReflections(
    vec3 rayDir,
    float roughness,

    vec3 worldNormal,
    vec3 worldDir,
    vec3 viewPos,
    float skylight,
    float dither
) {
	viewPos += mat3(gbufferModelView) * worldNormal * saturate(length(viewPos) * 3e-4);

	float NdotL = dot(worldNormal, rayDir);
	if (NdotL < EPS) return vec4(0.0);

    bool hasHit = false;
    vec4 reflection = vec4(0.0f);
    vec3 skyTint = vec3(1.0f);

    if (!hasHit) hasHit = TraceScreenSpaceReflection(roughness, viewPos, rayDir, dither, reflection, skyTint);
    if (!hasHit) hasHit = TracePtReflection(roughness, viewPos, rayDir, dither, reflection, skyTint);
    if (!hasHit) hasHit = TraceSkyReflection(roughness, viewPos, rayDir, dither, reflection, skyTint);

    return reflection;
}
