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
    uvec2 xy = uvec2(idx, idx >> 1) & 0x55u;
    xy = (xy | (xy >> 1)) & 0x33u;
    xy = (xy | (xy >> 2)) & 0x0fu;
    return xy;
}

uvec2 RemapThread16x16(uint idx) {
    uvec2 xy = uvec2(idx, idx >> 1) & 0x5555u;
    xy = (xy | (xy >> 1)) & 0x3333u;
    xy = (xy | (xy >> 2)) & 0x0f0fu;
    xy = (xy | (xy >> 4)) & 0x00ffu;
    return xy;
}

uvec2 RemapThread32x32(uint idx) {
    uvec2 xy = uvec2(idx, idx >> 1) & 0x55555555u;
    xy = (xy | (xy >> 1)) & 0x33333333u;
    xy = (xy | (xy >> 2)) & 0x0f0f0f0fu;
    xy = (xy | (xy >> 4)) & 0x00ff00ffu;
    xy = (xy | (xy >> 8)) & 0x0000ffffu;
    return xy;
}
