#include "/lib/Utility.glsl"

layout(location = 0) out vec4 albedoOut;
layout(location = 1) out uvec4 materialOut;
layout(location = 2) out vec4 normalOut;

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
	return 1u;
}

void voxy_emitFragment(in VoxyFragmentParameters parameters) {
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
