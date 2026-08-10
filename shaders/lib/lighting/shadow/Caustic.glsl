
vec2 WaterRefractionOffset(vec2 encodedNormal, float waterDepth) {
	vec3 waveNormal = OctDecodeUnorm(encodedNormal);
	vec3 refractDir = refract(vec3(0.0, -1.0, 0.0), waveNormal, 1.0 / WATER_IOR);

	return refractDir.xz * (waterDepth / maxEps(abs(refractDir.y)));
}

float EvaluateWaterMapping(
	vec3 sourceWorldPos, float projectionDepth, float footprint,
	out vec2 offsetCenter, out vec2 jacobianX, out vec2 jacobianZ
) {
	vec2 shadowCoord = WorldToShadowScreenSpace(sourceWorldPos).xy;
	vec2 shadowTexel = clamp(
		shadowCoord * realShadowMapRes - 0.5,
		vec2(0.0), vec2(realShadowMapRes - 1.001)
	);
	ivec2 texel00 = ivec2(floor(shadowTexel));
	vec2 texelFract = shadowTexel - vec2(texel00);

	// Reconstruct a continuous refraction field from one shadow texel quad.
	vec4 sample00 = texelFetch(shadowcolor1, texel00, 0);
	vec4 sample10 = texelFetch(shadowcolor1, texel00 + ivec2(1, 0), 0);
	vec4 sample01 = texelFetch(shadowcolor1, texel00 + ivec2(0, 1), 0);
	vec4 sample11 = texelFetch(shadowcolor1, texel00 + ivec2(1, 1), 0);
	vec2 offset00 = WaterRefractionOffset(sample00.xy, projectionDepth);
	vec2 offset10 = WaterRefractionOffset(sample10.xy, projectionDepth);
	vec2 offset01 = WaterRefractionOffset(sample01.xy, projectionDepth);
	vec2 offset11 = WaterRefractionOffset(sample11.xy, projectionDepth);

	vec2 offset0 = mix(offset00, offset10, texelFract.x);
	vec2 offset1 = mix(offset01, offset11, texelFract.x);
	offsetCenter = mix(offset0, offset1, texelFract.y);
	vec2 offsetTexelX = mix(offset10 - offset00, offset11 - offset01, texelFract.y);
	vec2 offsetTexelY = mix(offset01 - offset00, offset11 - offset10, texelFract.x);

	float texelScale = realShadowMapRes / footprint;
	vec2 shadowGradX = (
		WorldToShadowScreenSpace(sourceWorldPos + vec3(footprint, 0.0, 0.0)).xy
		- shadowCoord
	) * texelScale;
	vec2 shadowGradZ = (
		WorldToShadowScreenSpace(sourceWorldPos + vec3(0.0, 0.0, footprint)).xy
		- shadowCoord
	) * texelScale;
	jacobianX = vec2(1.0, 0.0)
		+ offsetTexelX * shadowGradX.x + offsetTexelY * shadowGradX.y;
	jacobianZ = vec2(0.0, 1.0)
		+ offsetTexelX * shadowGradZ.x + offsetTexelY * shadowGradZ.y;

	return min(min(sample00.w, sample10.w), min(sample01.w, sample11.w));
}

vec3 CalculateWaterCaustics(vec3 worldPos, float waterDepth, vec2 encodedNormal) {
	float projectionDepth = clamp(waterDepth, 4.0, 48.0);
	float shadowFootprint = 2.0 * abs(shadowProjectionInverse[0].x) / realShadowMapRes;
	float footprint = max(shadowFootprint, 0.05 * approxSqrt(projectionDepth));

	vec2 targetPos = worldPos.xz;
	vec2 sourcePos = targetPos - WaterRefractionOffset(encodedNormal, projectionDepth);
	vec3 sourceWorldPos = worldPos;
	sourceWorldPos.xz = sourcePos;

	vec2 offsetCenter, jacobianX, jacobianZ;
	float validMask = EvaluateWaterMapping(
		sourceWorldPos, projectionDepth, footprint,
		offsetCenter, jacobianX, jacobianZ
	);

	float jacobianDet = jacobianX.x * jacobianZ.y - jacobianZ.x * jacobianX.y;
	vec2 mappingError = sourcePos + offsetCenter - targetPos;
	vec2 correction = vec2(
		jacobianZ.y * mappingError.x - jacobianZ.x * mappingError.y,
		jacobianX.x * mappingError.y - jacobianX.y * mappingError.x
	) * (signI(jacobianDet) / maxEps(abs(jacobianDet)));
	correction *= saturate(4.0 * footprint * inversesqrt(maxEps(sdot(correction))));

	sourcePos -= correction;
	sourceWorldPos.xz = sourcePos;
	validMask *= EvaluateWaterMapping(
		sourceWorldPos, projectionDepth, footprint,
		offsetCenter, jacobianX, jacobianZ
	);

	jacobianDet = jacobianX.x * jacobianZ.y - jacobianZ.x * jacobianX.y;
	mappingError = sourcePos + offsetCenter - targetPos;

	float mappingValidity = exp2(-sdot(mappingError) / (32.0 * footprint * footprint));
	float compression = rcp(max(abs(jacobianDet), 0.1));
	float focus = mix(1.0, compression, validMask * mappingValidity);

	return focus * saturate(exp2(-rLOG2 * waterExtinction * waterDepth));
}
