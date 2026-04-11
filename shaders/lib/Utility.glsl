/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/


#include "/settings.glsl"

#if defined VOXY || defined DISTANT_HORIZONS
	#define LOD_MOD
#endif

#include "/lib/utility/Compat.glsl"
#include "/lib/utility/Math.glsl"
#include "/lib/utility/Matrix.glsl"
#include "/lib/utility/Pack.glsl"
#include "/lib/utility/Color.glsl"
#include "/lib/utility/Interpolate.glsl"
#include "/lib/utility/Phase.glsl"
#include "/lib/utility/SH.glsl"
#include "/lib/utility/Offset.glsl"
#include "/lib/utility/Load.glsl"

//================================================================================================//

#define ApplyFog(scene, fog) ((scene) * fog[1] + fog[0])

// Remap thread index to 2D index following Z-order curve.
uvec2 RemapThread8x8(uint idx) {
    return uvec2((((idx >> 2) & 0x7) & 0xFFFE) | (idx & 0x1), ((idx >> 1) & 0x3) | (((idx >> 3) & 0x7) & 0xFFFC));
}

uvec2 RemapThread16x16(uint idx) {
    return RemapThread8x8(idx & 63) + (uvec2((idx >> 6) & 1, idx >> 7) << 3);
}
