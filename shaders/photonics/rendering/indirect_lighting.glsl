#include "/lib/lighting/pt/State.glsl"

void sample_indirect(
    inout vec3 directColor,
    inout vec3 indirectColor,

    vec3 rtPos,
    vec3 normal,
    inout uint rndState,

    out vec3 firstHit,
    out vec3 firstNormal
) {
    Ray ray = CreateRay(rtPos, ph_rand_direction(rndState, normal));

    firstHit = vec3(FLT_POS_INF);
    firstNormal = -ray.direction;

    PathState path = PathStateEmpty();
    bool hitSky = false;

    #define MAX_BOUNCES 1
    #define MAX_INTERACTIONS 16

    int bounces = -1;
    for (int i = 0; i < MAX_INTERACTIONS && bounces < MAX_BOUNCES; i++) {
        RayOffsetPosition(ray, ray.direction * 0.03f);
        RayResult hit = RayNext(ray);

        if (!RayResultIsHit(hit)) {
            hitSky = ray.iterations > 0;
            break;
        }

        rtPos = RayResultPosition(hit);
        normal = RayResultNormal(hit);

        if (i == 0) {
            firstHit = rtPos;
            firstNormal = normal;
        }

        VoxelData voxelData = RayResultVoxelData(hit);
        vec4 albedo = VoxelDataAlbedo(voxelData);
        vec4 specular = VoxelDataSpecular(voxelData);

        if (PathStateAcceptTranslucent(path, ray, hit, normal, voxelData, albedo, specular, rndState)) {
            RaySkipBlock(ray);
            RayOffsetPosition(ray, ray.direction * 0.1f);
        } else {
            indirectColor += PathStateCalculateBlockRadiance(
                path,
                rtPos,
                VoxelDataMaterialId(voxelData),

                albedo,
                specular
            );

            PathStateAcceptSurface(path, albedo);
            PathStateAcceptWeight(path, bounces++ < MAX_BOUNCES ? rPI : 1.0f);

            indirectColor += PathStateCalculateSunRadiance(
                path,
                rtPos,
                normal,
                RayResultSkylight(hit),
                rndState
            );

            ray.direction = ph_rand_direction(rndState, normal);
        }
    }

    if (hitSky) {
        indirectColor += PathStateCalculateSkyRadiance(path, ray.direction);
    }
}
