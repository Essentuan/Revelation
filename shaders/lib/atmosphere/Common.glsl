/*
--------------------------------------------------------------------------------

	References:
		Sébastien Hillaire. "A Scalable and Production Ready Sky and Atmosphere Rendering Technique". EGSR 2020.
            https://sebh.github.io/publications/egsr2020.pdf
		Epic Games, Inc. "Unreal Engine Sky Atmosphere Rendering Technique". 2020.
            https://github.com/sebh/UnrealEngineSkyAtmosphere

--------------------------------------------------------------------------------
*/

//================================================================================================//

// #define PLANET_GROUND

#define VIEWER_BASE_ALTITUDE 384.0 // [64.0 128.0 256.0 384.0 512.0 1024.0 2048.0 4096.0 8192.0 16384.0 32768.0 65536.0 131072.0 262144.0 524288.0 1048576.0 2097152.0 4194304.0 8388608.0 16777216.0 33554432.0 67108864.0 134217728.0 268435456.0 536870912.0 1073741824.0]
#define ATMOSPHERE_THICKNESS 100000.0 // [0.0 5000.0 10000.0 20000.0 30000.0 40000.0 50000.0 60000.0 70000.0 80000.0 90000.0 100000.0 110000.0 120000.0 130000.0 140000.0 150000.0 160000.0]

#define ProjectSky      OctEncodeUnorm
#define UnprojectSky    OctDecodeUnorm

//================================================================================================//

struct AtmosphereParameters {
    vec3 solarIrradiance;
    float sunAngularRadius;
    float bottomRadius;
    float topRadius;
    vec3 rayleighScattering;
    vec3 mieScattering;
    vec3 mieExtinction;
    vec3 ozoneExtinction;
    vec3 groundAlbedo;
};

//================================================================================================//

const float planetRadius = 6371e3; // The average radius of the Earth: 6,371 kilometers
const float aerosol_g = 0.8; // Asymmetry factor for mie phase function
const float aerosol_d = 1.6; // Mean diameter in µm

const AtmosphereParameters atmosphere = AtmosphereParameters(
	vec3(1.0),
	0.004675 * SUN_RADIUS_MULT,
    planetRadius,
    planetRadius + ATMOSPHERE_THICKNESS,
    vec3(0.005802, 0.013558, 0.033100) * 1e-3,
    vec3(0.003996, 0.003996, 0.003996) * 1e-3,
    vec3(0.004440, 0.004440, 0.004440) * 1e-3,
    vec3(0.000650, 0.001881, 0.000085) * 1e-3,
    vec3(0.05, 0.06, 0.1)
);

float atmosphereViewHeight = planetRadius + VIEWER_BASE_ALTITUDE + eyeAltitude;
vec3 atmosphereViewPos = vec3(0.0, atmosphereViewHeight, 0.0);

//================================================================================================//

vec2 RaySphereIntersection(in vec3 pos, in vec3 dir, in float rad) {
	float PdotD = dot(pos, dir);
	float delta = sqr(PdotD) - sdot(pos) + sqr(rad);

	if (delta >= 0.0) {
		delta *= inversesqrt(delta);
		return vec2(-delta, delta) - PdotD;
	} else {
		return vec2(-1.0);
	}
}

vec2 RaySphereIntersection(in float r, in float mu, in float rad) {
	float delta = sqr(r) * (sqr(mu) - 1.0) + sqr(rad);

	if (delta >= 0.0) {
		delta *= inversesqrt(delta);
		return vec2(-delta, delta) - r * mu;
	} else {
		return vec2(-1.0);
	}
}

vec2 RaySphericalShellIntersection(in vec3 pos, in vec3 dir, in float bottomRad, in float topRad) {
    vec2 bottomIntersection = RaySphereIntersection(pos, dir, bottomRad);
    vec2 topIntersection = RaySphereIntersection(pos, dir, topRad);

    if (topIntersection.y >= 0.0) {
		vec2 intersection;
		if (bottomIntersection.y < 0.0) {
			intersection.x = max0(topIntersection.x);
			intersection.y = topIntersection.y;
		} else if (bottomIntersection.x < 0.0) {
			intersection.x = bottomIntersection.y;
			intersection.y = topIntersection.y;
		} else {
			intersection.x = max0(topIntersection.x);
			intersection.y = bottomIntersection.x;
		}

		return intersection;
	} else {
		return vec2(-1.0);
	}
}

vec2 RaySphericalShellIntersection(in float r, in float mu, in float bottomRad, in float topRad) {
    vec2 bottomIntersection = RaySphereIntersection(r, mu, bottomRad);
    vec2 topIntersection = RaySphereIntersection(r, mu, topRad);

    if (topIntersection.y >= 0.0) {
		vec2 intersection;
		if (bottomIntersection.y < 0.0) {
			intersection.x = max0(topIntersection.x);
			intersection.y = topIntersection.y;
		} else if (bottomIntersection.x < 0.0) {
			intersection.x = bottomIntersection.y;
			intersection.y = topIntersection.y;
		} else {
			intersection.x = max0(topIntersection.x);
			intersection.y = bottomIntersection.x;
		}

		return intersection;
	} else {
		return vec2(-1.0);
	}
}

// From https://gamedev.stackexchange.com/questions/96459/fast-ray-sphere-collision-code.
// - ro: ray origin
// - rd: normalized ray direction
// - sr: sphere radius
// - Returns distance from ro to first intersecion with sphere,
//   or -1.0 if no intersection.
float RaySphereIntersectNearest(vec3 ro, vec3 rd, float sr) {
    float a = dot(rd, rd);
    float b = 2.0 * dot(rd, ro);
    float c = dot(ro, ro) - (sr * sr);
    float delta = b * b - 4.0 * a * c;
    if (delta < 0.0 || a == 0.0) {
        return -1.0;
    }
    float sol0 = (-b - sqrt(delta)) / (2.0 * a);
    float sol1 = (-b + sqrt(delta)) / (2.0 * a);
    if (sol0 < 0.0 && sol1 < 0.0) {
        return -1.0;
    }
    if (sol0 < 0.0) {
        return max0(sol1);
    } else if (sol1 < 0.0) {
        return max0(sol0);
    }
    return max0(min(sol0, sol1));
}

// https://doi.org/10.1364/JOSA.47.000176
float AirPhase(in float mu) {
	return uniformPhase * 0.7629 * (1.0 + 0.932 * mu * mu);
}

// HG-Draine for aerosols
float AerosolPhase(in float mu) {
    const float ld = log(aerosol_d);

    const float gHG = 0.0604931 * log(ld) + 0.940256;
    const float gD 	= 0.500411 - 0.081287 / (-2.0 * ld + tan(ld) + 1.27551);
    const float a 	= 7.30354 * ld + 6.31675;
    const float wD 	= 0.026914 * (ld - cos(5.68947 * (log(ld) - 0.0292149))) + 0.376475;

	return mix(HenyeyGreensteinPhase(mu, gHG), DrainePhase(mu, gD, a), wD);
}

vec3 LightningContribution(in vec3 pos) {
	if (lightningBoltPosition.w < 0.5) return vec3(0.0);

    float distSq = sdot(lightningBoltPosition.xyz - pos);
	return vec3(0.32, 0.3, 1.0) * 5e5 / (1.0 + distSq);
}

vec3 LightningContribution(in vec3 pos, in vec3 normal) {
	if (lightningBoltPosition.w < 0.5) return vec3(0.0);

    vec3 vector = lightningBoltPosition.xyz - pos;
    float distSq = sdot(vector);
    vec3 lightDir = vector * inversesqrt(distSq);

    float diffuse = saturate(dot(normal, lightDir)) * 0.75 + 0.25;
	return vec3(0.32, 0.3, 1.0) * 5e3 / (1.0 + distSq) * diffuse;
}

//================================================================================================//

vec3 AtmosphereDensityAtPoint(vec3 pos) {
    float altitudeKm = (length(pos) - atmosphere.bottomRadius) * 1e-3;
    return vec3(exp(-altitudeKm * rcp(vec2(8.0, 1.2))), saturate(1.0 - abs(altitudeKm - 25.0) * rcp(15.0)));
}

vec3 AtmosphereExtinctionFromDensity(vec3 density) {
	const mat3 atmosphereExtinction = mat3(
		atmosphere.rayleighScattering,
		atmosphere.mieScattering,
		atmosphere.ozoneExtinction
	);

    return atmosphereExtinction * density;
}

vec3 ReadAtmosphereLUT(sampler2D tex, vec3 pos, vec3 dir) {
    float height = length(pos);
    vec3 up = pos / height;

    vec2 uv = vec2(saturate(0.5 + 0.5 * dot(dir, up)), linearstep(atmosphere.bottomRadius, atmosphere.topRadius, height));
    return texture(tex, uv).rgb;
}

vec3 AtmosphereTransmittance(vec3 pos, vec3 dir) {
    return ReadAtmosphereLUT(tLutTex, pos, dir);
}

vec3 AtmosphereMultiScattering(vec3 pos, vec3 dir) {
    return ReadAtmosphereLUT(msLutTex, pos, dir);
}

vec3 AtmosphereSkyView(vec3 viewPos, vec3 rayDir, vec3 sunDir) {
    float height = length(viewPos);
    vec3 up = viewPos / height;

	float viewZenithCos = dot(rayDir, up);
	vec3 sideVector = normalize(cross(up, rayDir));
	vec3 forwardVector = normalize(cross(sideVector, up));

    vec2 lightOnPlane = vec2(dot(sunDir, sideVector), dot(sunDir, forwardVector));
	float lightViewCos = normalize(lightOnPlane).y;

	vec2 uv;
	uv.x = sqrt(-lightViewCos * 0.5 + 0.5);

	float vHorizon = sqrt(height * height - atmosphere.bottomRadius * atmosphere.bottomRadius);
	float beta = fastAcos(vHorizon / height);
	float zenithHorizon = PI - beta;

	float coord = fastAcos(viewZenithCos);
	if (RaySphereIntersectNearest(viewPos, rayDir, atmosphere.bottomRadius) >= 0.0) {
		coord = (coord - zenithHorizon) / beta;
		coord = sqrt(coord); // Non-linear mapping
		uv.y = coord * 0.5 + 0.5;
	} else {
		coord = 1.0 - coord / zenithHorizon;
		coord = sqrt(coord); // Non-linear mapping
		uv.y = (1.0 - coord) * 0.5;
	}

    return texture(skyViewTex, uv).rgb;
}
