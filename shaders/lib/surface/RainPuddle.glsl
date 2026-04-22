
void CalculateRainPuddles(inout vec3 albedo, inout vec3 specTex, vec3 worldPos, vec3 geoNormal, float skylight) {
    vec3 minecraftPos = worldPos + cameraPosition;
    vec2 puddlePos = minecraftPos.xz - minecraftPos.y;
	puddlePos -= worldTimeCounter * vec2(0.016, 0.01);
	puddlePos *= RAIN_PUDDLE_SCALE;

    // Puddle noise
	float noise = texture(noisetex, puddlePos).z;
	noise += texture(noisetex, puddlePos * 0.7).z;
	noise += texture(noisetex, puddlePos * 0.3).z * 2.0;
	noise = saturate(noise * 0.2) * wetnessCustom;

    float puddles = smoothstep(0.45, 0.55, noise);
    if (puddles < EPS) return;

    // Normal falloff
    puddles *= saturate(geoNormal.y * 0.5 + 0.5);
    // Skylight falloff
    puddles *= saturate(skylight * 5.0 - 4.0);

    #if defined MC_SPECULAR_MAP && TEXTURE_FORMAT == 0
        // https://shaderlabs.org/wiki/LabPBR_Material_Standard
        float porosity = saturate(specTex.b * (255.0 / 64.0) - step(64.5, specTex.b * 255.0));
    #else
        const float porosity = 0.25;
    #endif
    puddles *= saturate(1.5 - porosity);

    // Apply wetness to albedo
    vec3 wetAlbedo = desaturate(albedo, 0.25);
    wetAlbedo *= 1.0 - porosity * 0.75;
    albedo = mix(albedo, wetAlbedo, puddles);

    // Apply wetness to normal
    // TODO: Add ripple normal
    // normal = normalize(mix(normal, rippleNormal, puddles));

    // Apply wetness to specular
    specTex.r = mix(specTex.r, RAIN_PUDDLE_SMOOTHNESS, puddles);
    specTex.g = max(specTex.g, DEFAULT_DIELECTRIC_F0 * puddles);
}