#if defined PASS_COMBINE_LIGHTING
#if defined SSILVB_ENABLED && defined SVGF_ENABLED
	vec3 UpscaleDiffuseIndirect(vec2 coord, vec3 worldNormal, float viewDistance, float NdotV) {
		vec3 sum = vec3(0.0);
		float sumWeight = 0.0;

		float sigmaZ = -4.0 * NdotV;

        ivec2 texelEnd = ivec2(halfViewEnd) - 1;
        coord = coord * viewSize * 0.5 - 0.5;

        ivec2 floorTexel = ivec2(floor(coord));
        vec2 fractTexel = coord - vec2(floorTexel);

        float bilinearWeight[4] = {
            oms(fractTexel.x) * oms(fractTexel.y),
            fractTexel.x      * oms(fractTexel.y),
            oms(fractTexel.x) * fractTexel.y,
            fractTexel.x      * fractTexel.y
        };

		for (uint i = 0u; i < 4u; ++i) {
			ivec2 sampleTexel = clamp(floorTexel + offset2x2[i], ivec2(1), texelEnd);

			vec3 sampleAux = texelFetch(colortex14, sampleTexel, 0).rgb;

			float weight = pow4(saturate(dot(OctDecodeSnorm(sampleAux.xy), worldNormal)));
			weight *= exp2(distance(sampleAux.z, viewDistance) * sigmaZ);
            weight *= bilinearWeight[i];

			vec3 sampleLight = texelFetch(colortex3, sampleTexel, 0).rgb;

			sum += sampleLight * weight;
			sumWeight += weight;
		}

        if (sumWeight < EPS) return vec3(0.0);

		return sum * rcp(sumWeight);
	}
#endif
#endif

//================================================================================================//

#if defined PASS_COMPOSITE
#if defined VOLUMETRIC_FOG || defined UW_VOLUMETRIC_FOG
	mat2x3 UnpackFogData(uvec2 data) {
		return mat2x3(DecodeRGBE8U(data.x), DecodeRGBE8U(data.y));
	}

	mat2x3 UpscaleVolumetricFog(ivec2 texelPos, float linearDepth) {
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
