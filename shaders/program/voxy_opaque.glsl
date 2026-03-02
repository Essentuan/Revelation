#include "/lib/Utility.glsl"

layout(location = 0) out vec4 albedoOut;
layout(location = 1) out uvec4 materialOut;
layout(location = 2) out vec4 normalOut;

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
		return materialId == 0u ? 1u : materialId;
	}
	return 1u;
}

void voxy_emitFragment(VoxyFragmentParameters parameters) {
	vec4 baseColor = parameters.sampledColour * parameters.tinting;
	vec3 flatNormal = VoxyFaceNormal(parameters.face);
	vec2 lightmap = saturate((parameters.lightMap - 0.03125) * 1.06667);

	albedoOut = vec4(baseColor.rgb, 1.0);

	#ifdef WHITE_WORLD
		albedoOut = vec4(1.0);
	#endif

	materialOut.x = Packup2x8U(lightmap);
	materialOut.y = VoxyMaterialId(parameters.customId);
	materialOut.zw = uvec2(0u);

	normalOut.xy = OctEncodeUnorm(flatNormal);
	normalOut.zw = normalOut.xy;
}
