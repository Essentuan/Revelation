#include "/lib/Utility.glsl"
#include "/lib/water/WaterWave.glsl"

layout(location = 0) out uvec4 materialOut;
layout(location = 1) out vec4 normalOut;
layout(location = 2) out vec4 waterOut;

vec3 VoxyFaceNormal(in uint face) {
	return vec3(
		uint((face >> 1u) == 2u),
		uint((face >> 1u) == 0u),
		uint((face >> 1u) == 1u)
	) * uintBitsToFloat((face << 31u) ^ 0xBF800000u);
}

uint VoxyMaterialId(in uint customId) {
	if (customId > 10000u) {
		return customId - 10000u;
	}
	return 2u;
}

vec3 ScreenToViewSpace(in vec3 screenPos) {
	vec3 ndcPos = screenPos * 2.0 - 1.0;
	return ProjectDivide(ndcPos, vxProjInv);
}

vec4 ApplyColorState(in vec4 color) {
	// Mirror Voxy's default color path so translucent alpha is preserved.
	vec4 outColor = color * uint2vec4RGBA(interData.y);
	outColor.a += float(interData.w & 0xFFu) * rcp255;
	return saturate(outColor);
}

float BlueNoise(in ivec2 texel, in int frame) {
	float base = texelFetch(noisetex, texel & 255, 0).a;
	#ifdef TAA_ENABLED
		return fract(base + float(frame) * PHI);
	#else
		return base;
	#endif
}

void voxy_emitFragment(in VoxyFragmentParameters parameters) {
	ivec2 texelPos = ivec2(gl_FragCoord.xy);
	vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

	vec4 baseColor = ApplyColorState(parameters.sampledColour * parameters.tinting);
	vec2 lightmap = vec2(0.0, saturate((parameters.lightMap.y - 0.03125) * 1.06667));

	uint materialId = VoxyMaterialId(parameters.customId);
	bool waterMask = materialId == 3u;

	// Treat unknown translucent materials as generic glass.
	if (!waterMask && materialId != 2u) {
		materialId = 2u;
	}

	vec3 flatNormal = VoxyFaceNormal(parameters.face);
	vec2 encodedNormal = OctEncodeUnorm(flatNormal);

	materialOut.x = Packup2x8U(lightmap);
	materialOut.y = materialId;
	materialOut.zw = uvec2(0u);

	normalOut.xy = normalOut.zw = encodedNormal;

	waterOut = vec4(0.0);

	if (waterMask) {
		vec3 viewPos = ScreenToViewSpace(vec3(screenCoord, gl_FragCoord.z));
		vec3 worldPos = transMAD(gbufferModelViewInverse, viewPos);

		float alpha = smoothstep(sqr(far - 32.0), sqr(far - 16.0), sdot(worldPos));
		float dither = BlueNoise(texelPos, frameCounter);
    	if (alpha < dither || loadDepth0(texelPos) < 1.0) {
			discard;
			return;
		}

		vec3 worldDir = normalize(worldPos - gbufferModelViewInverse[3].xyz);

		mat3 tbnMatrix = BuildOrthonormalBasis(flatNormal);

		vec3 minecraftPos = worldPos + cameraPosition;
		#ifdef WATER_PARALLAX
			vec3 worldNormal = CalculateWaterNormal(minecraftPos, worldDir * tbnMatrix);
		#else
			vec3 worldNormal = CalculateWaterNormal(minecraftPos);
		#endif

		worldNormal = tbnMatrix * worldNormal;

		vec2 encodedWaterNormal = OctEncodeUnorm(worldNormal);
		normalOut.zw = encodedWaterNormal;

		float depthBack = texelFetch(vxDepthTexOpaque, texelPos, 0).x;
		vec3 viewPosBack = ScreenToViewSpace(vec3(screenCoord, depthBack));
		vec3 worldPosBack = transMAD(gbufferModelViewInverse, viewPosBack);
		float waterDepth = distance(worldPos, worldPosBack);

		waterOut = vec4(waterDepth * rcp255, Packup2x8(encodedWaterNormal), 0.0, 1.0);
	} else {
		materialOut.z = Packup2x8U(baseColor.xy);
		materialOut.w = Packup2x8U(baseColor.zw);
	}
}
