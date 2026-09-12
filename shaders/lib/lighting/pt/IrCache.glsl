#define IrUseMainTex ((frameCounter & 1) == 0)

struct IrcEntry {
    vec3 radiance;
    vec3 sunColor;
    vec3 skyColor;

    float samples;
};

IrcEntry IrcEntryEmpty() {
    return IrcEntry(vec3(0.0f), vec3(0.0f), vec3(0.0f), 0.0f);
}

vec3 IrcEntryCalculateRadiance(IrcEntry entry, vec3 sunIlluminance, vec3 skyIlluminance) {
    return entry.radiance + (entry.sunColor * sunIlluminance) + (entry.skyColor * skyIlluminance);
}

void IrcEntryAddSample(inout IrcEntry history, IrcEntry smple) {
    history.samples = min(history.samples + 1.0f, frameCounter <= 5 ? 1.0f : IRC_HISTORY_LENGTH);
    float mixFactor = 1.0f / history.samples;

    history.radiance = mix(history.radiance, smple.radiance, mixFactor);
    history.sunColor = mix(history.sunColor, smple.sunColor, mixFactor);
    history.skyColor = mix(history.skyColor, smple.skyColor, mixFactor);
}

void IrcEntryEncode(IrcEntry entry, out uvec4 data0, out uvec4 data1)  {
    data0.xyz = floatBitsToUint(entry.radiance);
    data0.w = floatBitsToUint(entry.samples);

    data1.x = packUnorm2x16(saturate(entry.sunColor.xy));
    data1.y = packUnorm2x16(saturate(entry.sunColor.zz));

    data1.z = packUnorm2x16(saturate(entry.skyColor.xy));
    data1.w = packUnorm2x16(saturate(entry.skyColor.zz));
}

IrcEntry IrcEntryDecode(uvec4 data0, uvec4 data1) {
    IrcEntry result;

    result.radiance = uintBitsToFloat(data0.xyz);
    result.samples = uintBitsToFloat(data0.w);

    result.sunColor.xy = unpackUnorm2x16(data1.x);
    result.sunColor.z  = unpackUnorm2x16(data1.y).x;

    result.skyColor.xy = unpackUnorm2x16(data1.z);
    result.skyColor.z  = unpackUnorm2x16(data1.w).x;

    return result;
}

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

bool IrcContainsTexel(ivec3 ircTexel) {
    return all(greaterThanEqual(ircTexel, ivec3(0))) && all(lessThan(ircTexel, ircSizeInt));
}

IrcEntry IrcLoad(ivec3 texel) {
    texel.x <<= 1;

    if (IrUseMainTex) {
        return IrcEntryDecode(
            texelFetchOffset(irCacheMainTex, texel, 0, ivec3(0, 0, 0)),
            texelFetchOffset(irCacheMainTex, texel, 0, ivec3(1, 0, 0))
        );
    } else {
        return IrcEntryDecode(
            texelFetchOffset(irCacheAltTex, texel, 0, ivec3(0, 0, 0)),
            texelFetchOffset(irCacheAltTex, texel, 0, ivec3(1, 0, 0))
        );
    }
}

uvec4[2] IrcReprojectRaw(ivec3 texel) {
    texel += cameraPositionInt - previousCameraPositionInt;
    texel.x <<= 1;

    if (!IrUseMainTex) {
        return uvec4[](
            texelFetchOffset(irCacheMainTex, texel, 0, ivec3(0, 0, 0)),
            texelFetchOffset(irCacheMainTex, texel, 0, ivec3(1, 0, 0))
        );
    } else {
        return uvec4[](
            texelFetchOffset(irCacheAltTex, texel, 0, ivec3(0, 0, 0)),
            texelFetchOffset(irCacheAltTex, texel, 0, ivec3(1, 0, 0))
        );
    }
}

IrcEntry IrcReproject(ivec3 texel) {
    uvec4[2] data = IrcReprojectRaw(texel);
    return IrcEntryDecode(data[0], data[1]);
}

void IrcStore(ivec3 texel, IrcEntry entry) {
    texel.x <<= 1;

    uvec4 data0;
    uvec4 data1;
    IrcEntryEncode(entry, data0, data1);

    if (IrUseMainTex) {
        imageStore(irCacheMainImg, texel + ivec3(0, 0, 0), data0);
        imageStore(irCacheMainImg, texel + ivec3(1, 0, 0), data1);
    } else {
        imageStore(irCacheAltImg, texel + ivec3(0, 0, 0), data0);
        imageStore(irCacheAltImg, texel + ivec3(1, 0, 0), data1);
    }
}

#if defined IRC_COMPUTE_SHADER

#define IRC_WORKGROUPS_X 8
#define IRC_WORKGROUPS_Y 128
#define IRC_WORKGROUPS_Z 8

#define IRC_LOCALSIZE_X 16
#define IRC_LOCALSIZE_Y 1
#define IRC_LOCALSIZE_Z 16

ivec3 RemapIrcThreadImpl(uvec3 workGroupId, uvec3 workGroupSize, uint localIndex) {
    uvec3 result = workGroupId * workGroupSize;
    uvec2 localThread = RemapThread16x16(localIndex);

    return ivec3(result + uvec3(localThread.x, 0, localThread.y));
}

#define RemapIrcThread() RemapIrcThreadImpl(gl_WorkGroupID, gl_WorkGroupSize, gl_LocalInvocationIndex)

#endif
