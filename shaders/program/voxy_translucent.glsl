#include "/lib/Utility.glsl"
#include "/lib/water/WaterWave.glsl"

layout(location = 0) out uvec4 materialOut;
layout(location = 1) out vec4 normalOut;
layout(location = 2) out vec4 waterOut;

vec3 VoxyFaceNormal(uint face) {
	return vec3(
		uint((face >> 1u) == 2u),
		uint((face >> 1u) == 0u),
		uint((face >> 1u) == 1u)
	) * (float(int(face & 1u)) * 2.0 - 1.0);
}

uint VoxyMaterialId(uint customId) {
	if (customId >= 10000u) {
		uint materialId = customId - 10000u;
		return materialId == 0u ? 2u : materialId;
	}
	return 2u;
}

vec3 ProjectDivideVX(in vec3 v, in mat4 m) {
	return projMAD(m, v) * rcp(m[2].w * v.z + m[3].w);
}

vec3 ScreenToViewSpaceVX(in vec3 screenPos) {
	vec3 ndcPos = screenPos * 2.0 - 1.0;
	return ProjectDivideVX(ndcPos, vxProjInv);
}

vec4 VoxyApplyColorState(in vec4 color) {
	// Mirror Voxy's default color path so translucent alpha is preserved.
	vec4 outColor = color * uint2vec4RGBA(interData.y);
	outColor.a += float(interData.w & 0xFFu) * r255;
	return clamp(outColor, vec4(0.0), vec4(1.0));
}

float VoxyBlueNoise(in ivec2 texel, in int frame) {
	float base = texelFetch(noisetex, texel & 255, 0).a;
	#ifdef TAA_ENABLED
		return fract(base + float(frame) * 0.61803398875);
	#else
		return base;
	#endif
}

void voxy_emitFragment(VoxyFragmentParameters parameters) {
	ivec2 texelPos = ivec2(gl_FragCoord.xy);
	vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;
	vec4 baseColor = VoxyApplyColorState(parameters.sampledColour * parameters.tinting);
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

	normalOut.xy = encodedNormal;
	normalOut.zw = encodedNormal;

	waterOut = vec4(0.0);

	if (waterMask) {
		vec3 viewPos = ScreenToViewSpaceVX(vec3(screenCoord, gl_FragCoord.z));
		vec3 worldPos = transMAD(gbufferModelViewInverse, viewPos);

		float alpha = smoothstep(sqr(far - 32.0), sqr(far - 16.0), dot(worldPos, worldPos));
		float dither = VoxyBlueNoise(texelPos, frameCounter);
		if (alpha < dither || texelFetch(depthtex0, texelPos, 0).x < 1.0) {
			discard;
			return;
		}

		vec3 worldDir = normalize(worldPos - gbufferModelViewInverse[3].xyz);

		const mat3 tbnMatrix = mat3(
			vec3(1.0, 0.0, 0.0),
			vec3(0.0, 0.0, 1.0),
			vec3(0.0, 1.0, 0.0)
		);

		vec3 minecraftPos = worldPos + cameraPosition;
		#ifdef WATER_PARALLAX
			vec3 worldNormal = CalculateWaterNormal(minecraftPos, worldDir * tbnMatrix);
		#else
			vec3 worldNormal = CalculateWaterNormal(minecraftPos);
		#endif

		worldNormal = tbnMatrix * worldNormal;

		vec2 encodedWaterNormal = OctEncodeUnorm(worldNormal);
		normalOut.zw = encodedWaterNormal;

		float depthBehind = texelFetch(vxDepthTexOpaque, texelPos, 0).x;
		vec3 viewPos1 = ScreenToViewSpaceVX(vec3(screenCoord, depthBehind));
		vec3 worldPos1 = transMAD(gbufferModelViewInverse, viewPos1);
		float waterDepth = distance(worldPos, worldPos1);

		waterOut = vec4(waterDepth * r255, Packup2x8(encodedWaterNormal), 0.0, 1.0);
	} else {
		materialOut.z = Packup2x8U(baseColor.xy);
		materialOut.w = Packup2x8U(baseColor.zw);
	}
}
