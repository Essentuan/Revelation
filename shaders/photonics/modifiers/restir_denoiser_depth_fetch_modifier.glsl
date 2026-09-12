ivec2 modify_denoiser_depth_fetch(ivec2 texel) {
#if RENDER_SCALE >= 1.0
    vec2 uv = texelToUv(texel) / RENDER_SCALE_HALF;
    return uvToTexel(uv);
#else
    return texel;
#endif
}
