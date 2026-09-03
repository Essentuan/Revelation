ivec2 modify_denoiser_depth_fetch(ivec2 texel) {
    vec2 uv = texelToUv(texel) / RENDER_SCALE_HALF;
    return uvToTexel(uv);
}
