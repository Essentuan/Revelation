#include "/lib/lighting/SSRT.glsl"
#include "/lib/universal/MonteCarlo.glsl"

vec4 CalculateSpecularReflections(
#if !defined PASS_TRANSLUCENT
    Material material,
#endif
    vec3 worldNormal,
    vec3 screenPos,
    vec3 worldDir,
    vec3 viewPos,
    float skylight,
    float dither,
    uint stepCount
) {
	viewPos += mat3(gbufferModelView) * worldNormal * saturate(length(viewPos) * 3e-4);

	vec3 halfway = worldNormal;
#ifdef ROUGH_REFLECTIONS
	if (!material.mirrorMask) {
		mat3 tbnMatrix = BuildOrthonormalBasis(worldNormal);

		vec2 noise = SampleStbnVec2(ivec2(gl_FragCoord.xy), frameCounter + 3);
		halfway = tbnMatrix * SampleVisibleGGX(-worldDir * tbnMatrix, material.roughness, noise);
	}
#endif

#if !defined PASS_TRANSLUCENT
	vec3 lightDir = reflect(worldDir, halfway);
#else
    float NdotV = abs(dot(worldNormal, worldDir));
    vec3 lightDir = worldDir + worldNormal * NdotV * 2.0;
#endif

	float NdotL = dot(worldNormal, lightDir);
	if (NdotL < EPS) return vec4(0.0);

    if (ScreenSpaceRaytrace(viewPos, mat3(gbufferModelView) * lightDir, dither, stepCount, screenPos)) {
        vec3 reflection = texture(colortex4, scaleScreenUv(screenPos.xy)).rgb;

        ivec2 texel = uvToTexelScaled(screenPos.xy);
        vec3 reflectViewPos = ScreenToViewPos(vec3(screenPos.xy, loadDepth0(texel)));

        return vec4(
            reflection,
            distance(reflectViewPos, viewPos)
        );
    }

    vec3 rtPos = transMAD(gbufferModelViewInverse, viewPos) + rt_camera_position;

    RayIterator itr;
    ray_iter_begin(itr, rtPos, lightDir);

    VoxelData voxelData = voxel_data_empty();
    RayResult lastHit = missed_ray_result();

    DiffuseState diffuseState = DiffuseStateEmpty();
    uint rndState = floatBitsToUint(dither) * 7;

    #define MAX_INTERACTIONS 8
    for (int interactions = 0; interactions < MAX_INTERACTIONS; interactions++) {
        ray_iter_offset_position(itr, itr.direction * 0.03f);
        lastHit = ray_iter_next(itr);

        if (!ray_result_is_hit(lastHit)) {
            lastHit = missed_ray_result();

            break;
        }

        vec3 hitNormal = ray_result_normal(lastHit);

        voxelData = ray_result_voxel_data(lastHit);
        vec4 albedo = voxel_data_albedo(voxelData);
        vec4 specular = voxel_data_specular(voxelData);

        if (!DiffuseStateApplyTranslucency(diffuseState, itr, lastHit, hitNormal, voxelData, albedo, specular, rndState))
            break;

        ray_iter_set_direction(itr, itr.direction);

        ray_iter_skip_block(itr);
        ray_iter_offset_position(itr, itr.direction * 0.1f);
    }

    if (itr.iterations > 0 && ray_result_is_hit(lastHit)) {
        vec3 hitPos = ray_result_position(lastHit);
        vec3 hitDir = normalize(hitPos - rtPos);
        float hitDistance = distance(rtPos, hitPos);

        hitPos -= rt_camera_position;

        vec3 hitGeoNormal = ray_result_normal(lastHit);
        vec3 hitTexNormal = rtTexNormal(voxelData, hitGeoNormal);

        vec3 albedo = voxel_data_albedo(voxelData).rgb;
        vec4 specular = voxel_data_specular(voxelData);

        uint materialID = uint(voxel_data_block_id(voxelData) - 10000);
        Material hitMaterial = GetMaterialData(specular, albedo);

        vec2 lightmap = vec2(0.0f, ray_result_skylight(lastHit)) / 15.0f;

        float sssAmount = 0.0;
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
        sssAmount = max(sssAmount, specular.b * step(64.5 * rcp255, specular.b));
        #endif

        // Remap sss amount to [0, 1] range
        sssAmount = linearstep(64.0 * rcp255, 1.0, sssAmount) * eyeSkylightSmooth * SUBSURFACE_SCATTERING_STRENGTH;

        vec3 diffuseRadiance = IrcLoad(WorldPosToIrcTexel(hitPos + hitGeoNormal * 0.03f)).rgb;

        // Cloud shadows
        #ifdef CLOUD_SHADOWS
            // float cloudShadow = CalculateCloudShadows(worldPos);
            vec2 cloudShadowCoord = WorldToCloudShadowScreenPos(hitPos).xy + (dither - 0.5) / textureSize(cloudShadowTex, 0);
            float cloudShadow = textureBicubic(cloudShadowTex, saturate(cloudShadowCoord)).x;
        #else
            float cloudShadow = 1.0 - wetness * 0.96;
        #endif

        vec3 sunlightBase = cloudShadow * saturate(lightmap.y * 1e6 + float(isEyeInWater)) * global.directIlluminance;

        float NdotV = dot(hitTexNormal, -hitDir);
        float NdotL = dot(hitTexNormal, shadowDirWorld);
        float LdotV = dot(shadowDirWorld, -hitDir);

        // Must use unclamped NdotL & NdotV
        float invLenH = inversesqrt(2.0 + 2.0 * LdotV);
        float NdotH = saturate((NdotL + NdotV) * invLenH);
        float VdotH = saturate(LdotV * invLenH + invLenH);
        NdotL = saturate(NdotL);
        NdotV = saturate(NdotV);

        // Shadows and SSS
        if (NdotL + sssAmount > EPS) {
            vec3 shadow = vec3(saturate(NdotL * FLT_MAX));
            float surfaceDepth = 0.0;

            const float normalOffsetBase = 0.03f;

            // PCSS
            shadow *= CalculatePCSS(hitPos, hitGeoNormal * normalOffsetBase, dither, surfaceDepth), vec3(1.0);

            const float contactShadow = 1.0;

            // Subsurface scattering
            if (sssAmount > EPS) {
                vec3 beta = approxSqrt(saturate(normalize(albedo)));
                vec3 sigmaA = oms(beta) * 8.0 / (sssAmount * SUBSURFACE_SCATTERING_STRENGTH);
                vec3 sigmaS = 2.0 * beta * sssAmount;

                float phase = HenyeyGreensteinPhase(-LdotV, 0.7) * 0.25 + uniformPhase * 0.75;
                vec3 sss = sigmaS * phase * exp2(-rLOG2 * surfaceDepth * (sigmaS + sigmaA));

                diffuseRadiance += sunlightBase * sss * SUBSURFACE_SCATTERING_BRIGHTNESS;
            }

            if (dot(shadow, vec3(1.0)) > EPS) {
                shadow *= sunlightBase;

                diffuseRadiance += shadow * DiffuseHammon(NdotV, NdotL, VdotH, NdotH, hitMaterial.roughness, albedo) * NdotL;
            }
        }

        // Minimal ambient light
        diffuseRadiance += saturate((hitTexNormal.y * 0.4 + 0.6)) * max(MINIMUM_AMBIENT_BRIGHTNESS, 5e-3 * nightVision);
        diffuseRadiance *= albedo;

        // Emissive
        #if EMISSIVE_MODE > 0 && defined MC_SPECULAR_MAP
            diffuseRadiance += hitMaterial.emissive * albedo;
        #endif
        #if EMISSIVE_MODE < 2
            // Hard-coded emissive
            diffuseRadiance += HardCodeEmissive(materialID, albedo, hitPos) * EMISSIVE_BRIGHTNESS * albedo;
        #endif

        return vec4(
            DiffuseStateApplyToRadiance(diffuseState, diffuseRadiance),
            hitDistance
        );
    }

    if (skylight > EPS && isEyeInWater == 0) {
        vec3 skyRadiance = textureBicubic(skyEnvMapTex, saturate(ProjectCubemap(lightDir, 96.0))).rgb;
        return vec4(skyRadiance, FP16_MAX);
    }

	return vec4(0.0, 0.0, 0.0, FP16_MAX);
}
