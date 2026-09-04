uniform sampler3D irCacheMainTex;
uniform sampler3D irCacheAltTex;

layout (rgba32f) restrict uniform image3D irCacheMainImg;
layout (rgba32f) restrict uniform image3D irCacheAltImg;

#define irCache ((frameCounter & 1) == 0 ? irCacheMainImg : irCacheAltImg)
#define irCachePrev ((frameCounter & 1) != 0 ? irCacheMainImg : irCacheAltImg)

#define irCacheTex ((frameCounter & 1) == 0 ? irCacheMainTex : irCacheAltTex)
#define irCachePrevTex ((frameCounter & 1) != 0 ? irCacheMainTex : irCacheAltTex)

vec3 WorldPosToIrcPos(vec3 worldPos) {
    return floor(worldPos + cameraPositionFract);
}

vec3 WorldPosToIrcCoord(vec3 worldPos) {
    return WorldPosToIrcPos(worldPos) + ircSizeHalf;
}

ivec3 WorldPosToIrcTexel(vec3 worldPos) {
    return ivec3(WorldPosToIrcPos(worldPos)) + ircSizeHalfInt;
}

vec3 IrcTexelToWorldPos(ivec3 ircTexel) {
    return vec3(ircTexel - ircSizeHalfInt) - cameraPositionFract + 0.5f;
}

vec4 IrcLoad(ivec3 texel) {
    return texelFetch(irCacheTex, texel, 0);
}

vec4 IrcReproject(ivec3 texel) {
    return texelFetch(irCachePrevTex, texel + (cameraPositionInt - previousCameraPositionInt), 0);
}

void IrcStore(ivec3 texel, vec4 value) {
    imageStore(irCache, texel, value);
}
