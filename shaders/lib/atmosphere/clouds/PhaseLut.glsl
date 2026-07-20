#if !defined INCLUDE_CLOUDS_PHASE_LUT
#define INCLUDE_CLOUDS_PHASE_LUT

#define CLOUD_PHASE_CU 0
#define CLOUD_PHASE_ST 1
#define CLOUD_PHASE_CI 2

const ivec2 cloudPhaseLutRes = ivec2(512, 3);

#include "/lib/atmosphere/clouds/PhaseLutMapping.glsl"

float CloudPhaseLutSearch(float cosTheta) {
	float t = acos(satSnorm(cosTheta)) * rPI;
	int lower = 0;
	int upper = cloudPhaseWarpKnotCount - 1;

    // Binary search for the knot that is just greater than t.
	for (uint i = 0u; i < cloudPhaseWarpSearchSteps; ++i) {
		int middle = (lower + upper + 1) >> 1;
		if (cloudPhaseWarpKnots[middle].x <= t) lower = middle;
		else upper = middle - 1;
	}

	lower = min(lower, cloudPhaseWarpKnotCount - 2);
	vec2 knot0 = cloudPhaseWarpKnots[lower];
	vec2 knot1 = cloudPhaseWarpKnots[lower + 1];
	return remap(knot0.x, knot1.x, knot0.y, knot1.y, t);
}

vec2 CloudPhaseLutUv(float cosTheta, int cloudType) {
	int row = clamp(cloudType, CLOUD_PHASE_CU, CLOUD_PHASE_CI);
	vec2 uv = vec2(CloudPhaseLutSearch(cosTheta), float(row));
	return UnitToSubUv(uv, vec2(cloudPhaseLutRes));
}

#if CLOUD_PHASE_LUT_COLORED == 1

// The RGB LUT stores log2 of the normalized linear Rec.2020 phase function.
vec3 SampleCloudPhaseLut(float cosTheta, int cloudType) {
	vec2 uv = CloudPhaseLutUv(cosTheta, cloudType);
	return exp2(textureLod(cloudPhaseLut, uv, 0.0).rgb);
}

float SampleCloudPhaseLutScalar(float cosTheta, int cloudType) {
	return luminance(SampleCloudPhaseLut(cosTheta, cloudType));
}

#else

// The R LUT stores log2 of the normalized Rec.2020 luminance phase function.
float SampleCloudPhaseLutScalar(float cosTheta, int cloudType) {
	vec2 uv = CloudPhaseLutUv(cosTheta, cloudType);
	return exp2(textureLod(cloudPhaseLut, uv, 0.0).r);
}

#endif

#endif
