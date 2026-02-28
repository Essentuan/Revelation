/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

out vec3 worldPos;

out vec4 vertColor;
out vec2 texCoord;
out vec2 lightmap;

//======// Uniform //=============================================================================//

uniform mat4 gbufferModelViewInverse;

uniform vec2 taaOffset;

//======// Main //================================================================================//
void main() {
	vertColor = gl_Color;
	texCoord = mat2(gl_TextureMatrix[0]) * gl_MultiTexCoord0.xy + gl_TextureMatrix[0][3].xy;

	lightmap = saturate((gl_MultiTexCoord1.xy - 8.0) * rcp(232.0));

	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);
	gl_Position = diagonal4(gl_ProjectionMatrix) * viewPos.xyzz + gl_ProjectionMatrix[3];
	worldPos = transMAD(gbufferModelViewInverse, viewPos);

	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif
}