#if defined PASS_DEFERRED_LIGHTING
#if defined SSILVB_ENABLED && defined SVGF_ENABLED
	vec3 UpscaleDiffuseIndirect(in ivec2 texelPos, in vec3 worldNormal, in float viewDistance, in float NdotV) {
		// ivec2 randTexel = ivec2(vec2(texelPos >> 1) + BlueNoise(texelPos, frameCounter + 3));
		texelPos >>= 1;

		vec3 sum = texelFetch(colortex3, texelPos, 0).rgb;
		float sumWeight = 1.0;

		float sigmaZ = -4.0 * NdotV;

		ivec2 tileOffset = ivec2(halfViewSize.x, 0);
        ivec2 texelEnd = ivec2(halfViewEnd) - 1;

		// float depthTolerance = saturate(0.05 + viewDistance * 0.02);

		for (uint i = 0u; i < 8u; ++i) {
			ivec2 sampleTexel = clamp(texelPos + offset3x3N[i], ivec2(1), texelEnd);

			vec3 prevData = texelFetch(colortex2, sampleTexel + tileOffset, 0).rgb;

			float weight = pow16(saturate(dot(OctDecodeSnorm(prevData.xy), worldNormal)));
			weight *= exp2(distance(prevData.z, viewDistance) * sigmaZ);

			vec3 sampleLight = texelFetch(colortex3, sampleTexel, 0).rgb;

			sum += sampleLight * weight;
			sumWeight += weight;
		}

		return sum * rcp(sumWeight);
	}
#endif
#endif

//================================================================================================//

#if defined PASS_COMPOSITE
#if defined VOLUMETRIC_FOG || defined UW_VOLUMETRIC_FOG
	mat2x3 UnpackFogData(in uvec2 data) {
		return mat2x3(DecodeRGBE8U(data.x), DecodeRGBE8U(data.y));
	}

	mat2x3 UpscaleVolumetricFog(in ivec2 texelPos, in float linearDepth) {
		ivec2 randTexel = ivec2(vec2(texelPos >> 1) + BlueNoise(texelPos, frameCounter + 7));
		float sigmaZ = -64.0 / linearDepth;

		mat2x3 sum = UnpackFogData(texelFetch(colortex11, randTexel, 0).xy);
		float sumWeight = 1.0;

		for (uint i = 0u; i < 8u; ++i) {
			ivec2 sampleTexel = randTexel + offset3x3N[i];
			uvec3 sampleFogData = texelFetch(colortex11, sampleTexel, 0).xyz;

			float sampleDepth = uintBitsToFloat(sampleFogData.z);
			float weight = exp2(abs(sampleDepth - linearDepth) * sigmaZ);

			sum += UnpackFogData(sampleFogData.xy) * weight;
			sumWeight += weight;
		}

		sum *= rcp(sumWeight);
		return sum;
	}
#endif
#endif