#include "/lib/Utility.glsl"

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

float ScreenToViewDepthVX(in float depth) {
	return -vxProj[3].z / (vxProj[2].z + (depth * 2.0 - 1.0));
}

vec4 VoxyApplyColorState(in vec4 color) {
	// Mirror Voxy's default color path so translucent alpha is preserved.
	vec4 outColor = color * uint2vec4RGBA(interData.y);
	outColor.a += float(interData.w & 0xFFu) * r255;
	return clamp(outColor, vec4(0.0), vec4(1.0));
}

void voxy_emitFragment(VoxyFragmentParameters parameters) {
	ivec2 texelPos = ivec2(gl_FragCoord.xy);
	vec4 baseColor = VoxyApplyColorState(parameters.sampledColour * parameters.tinting);

	uint materialId = VoxyMaterialId(parameters.customId);
	bool waterMask = materialId == 3u;

	// Treat unknown translucent materials as generic glass.
	if (!waterMask && materialId != 2u) {
		materialId = 2u;
	}

	vec3 flatNormal = VoxyFaceNormal(parameters.face);
	vec2 encodedNormal = OctEncodeUnorm(flatNormal);

	materialOut.x = Packup2x8U(parameters.lightMap);
	materialOut.y = materialId;
	materialOut.zw = uvec2(0u);

	normalOut.xy = encodedNormal;
	normalOut.zw = encodedNormal;

	waterOut = vec4(0.0);

	if (waterMask) {
		float depthBehind = texelFetch(vxDepthTexOpaque, texelPos, 0).x;
		float depthFrontLinear = ScreenToViewDepthVX(gl_FragCoord.z);
		float depthBackLinear = ScreenToViewDepthVX(depthBehind);
		float waterDepth = abs(depthBackLinear - depthFrontLinear);

		waterOut = vec4(clamp(waterDepth * r255, 0.0, 1.0), Packup2x8(encodedNormal), 0.0, 1.0);
	} else {
		materialOut.z = Packup2x8U(baseColor.xy);
		materialOut.w = Packup2x8U(baseColor.zw);
	}
}
