float SampleHeight(vec2 localCoord) {
    #ifdef SMOOTH_PARALLAX
        vec2 quadPixelSize = rcp(tileScale * vec2(atlasSize));
        vec2 atlasCoord = localToAtlas(localCoord) * vec2(atlasSize);

        vec2 f = fract(atlasCoord);

        ivec2 atlasTexel00 = ivec2(atlasCoord);
	    ivec2 atlasTexel11 = ivec2(localToAtlas(localCoord + quadPixelSize) * vec2(atlasSize));

        float a = texelFetch(normals, atlasTexel00, 0).a;
        float b = texelFetch(normals, ivec2(atlasTexel11.x, atlasTexel00.y), 0).a;
        float c = texelFetch(normals, ivec2(atlasTexel00.x, atlasTexel11.y), 0).a;
        float d = texelFetch(normals, atlasTexel11, 0).a;

        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    #else
        return texelFetch(normals, ivec2(localToAtlas(localCoord) * vec2(atlasSize)), 0).a;
    #endif
}

vec3 HeightBasedNormal(vec2 localCoord) {
    vec2 quadSize = tileScale * vec2(atlasSize);
    vec2 quadPixelSize = rcp(quadSize);

	#ifdef SMOOTH_PARALLAX
        vec2 atlasCoord = localToAtlas(localCoord) * vec2(atlasSize);
	    vec2 f = fract(atlasCoord);

        ivec2 atlasTexel00 = ivec2(atlasCoord);
        ivec2 atlasTexel11 = ivec2(localToAtlas(localCoord + quadPixelSize) * vec2(atlasSize));

        float a = texelFetch(normals, atlasTexel00, 0).a;
        float b = texelFetch(normals, ivec2(atlasTexel11.x, atlasTexel00.y), 0).a;
        float c = texelFetch(normals, ivec2(atlasTexel00.x, atlasTexel11.y), 0).a;
        float d = texelFetch(normals, atlasTexel11, 0).a;

		vec3 normal = vec3(((b + c - a - d) * f.yx + vec2(a, d) - vec2(b, c)) * quadSize, 4.0 / PARALLAX_DEPTH);
	#else
        vec2 bias = 1e-2 * quadPixelSize;

        float heightR = textureLod(normals, localToAtlas(localCoord + vec2(bias.x, 0.0)), 0.0).a;
        float heightL = textureLod(normals, localToAtlas(localCoord - vec2(bias.x, 0.0)), 0.0).a;
        float heightU = textureLod(normals, localToAtlas(localCoord + vec2(0.0, bias.y)), 0.0).a;
        float heightD = textureLod(normals, localToAtlas(localCoord - vec2(0.0, bias.y)), 0.0).a;

        float deltaX = heightL - heightR;
        float deltaY = heightD - heightU;

		vec3 normal = vec3(deltaX, deltaY, step(abs(deltaX) + abs(deltaY), 1e-3));
	#endif

    return normalize(normal);
}

const float rSteps = 1.0 / float(PARALLAX_SAMPLES);

vec3 CalculateParallax(vec3 tangentDir, float dither, float parallaxFade) {
	vec3 rayStep = vec3(tangentDir.xy, 1.0) * -rSteps;
	rayStep.xy *= PARALLAX_DEPTH * parallaxFade / tangentDir.z;

	vec3 rayPos = vec3(atlasToLocal(texCoord), 1.0) + rayStep * dither;

	for (uint i = 0u; i < PARALLAX_SAMPLES; ++i) {
		rayPos += rayStep;
		float sampleHeight = SampleHeight(rayPos.xy);
        if (sampleHeight > rayPos.z) break;
	}

	// Refine the parallax mapping (binary search)
	#ifdef PARALLAX_REFINEMENT
		rayPos -= rayStep;
		rayStep *= 0.5;

		for (uint i = 0u; i < PARALLAX_REFINEMENT_STEPS; ++i) {
			float sampleHeight = SampleHeight(rayPos.xy);

			rayPos += rayStep * signI(rayPos.z - sampleHeight);
			rayStep *= 0.5;
		}

		rayPos += rayStep * 2.0;
	#endif

	return rayPos;
}

float CalculateParallaxShadow(vec3 tangentDir, vec3 rayPos, float dither, float parallaxFade) {
	vec3 rayStep = vec3(tangentDir.xy, 1.0) * rayPos.z * rSteps;
	rayStep.xy *= PARALLAX_DEPTH * parallaxFade / tangentDir.z;
	rayPos += rayStep * dither;

	for (uint i = 0u; i < PARALLAX_SAMPLES; ++i) {
		float sampleHeight = SampleHeight(rayPos.xy);

		if (sampleHeight > rayPos.z) return 1.0;
		rayPos += rayStep;
	}

	return 0.0;
}
