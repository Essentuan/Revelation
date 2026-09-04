#include "/photonics/tracing.glsl"
#include "/lib/lighting/pt/DiffuseState.glsl"

vec3 processNextDirection(
    inout DiffuseState diffuseState,
    inout uint rndState,
    vec3 normal
) {
    DiffuseStateApplyWeight(diffuseState, rPI);
    return ph_rand_direction(rndState, normal);
}

void sample_indirect(
    inout vec3 directColor,
    inout vec3 indirectColor,

    vec3 rtPos,
    vec3 normal,
    inout uint rndState,

    out vec3 firstHit,
    out vec3 firstNormal
) {
    RayIterator itr;
    ray_iter_begin(itr, rtPos, ph_rand_direction(rndState, normal));

    DiffuseState diffuseState = DiffuseStateEmpty();

    bool hitSky = false;
    bool setFirstHit = false;

    #define MAX_BOUNCES 1
    #define MAX_INTERACTIONS 16

    int bounces = -1;
    for (int interactions = 0; interactions < MAX_INTERACTIONS && bounces < MAX_BOUNCES; interactions++) {
        ray_iter_offset_position(itr, itr.direction * 0.03f);
        RayResult hit = ray_iter_next(itr);

        if (itr.iterations <= 0) return;
        if (!ray_result_is_hit(hit)) {
            hitSky = true;
            break;
        }

        rtPos = ray_result_position(hit);
        normal = ray_result_normal(hit);

        if (!setFirstHit) {
            firstHit = rtPos;
            firstNormal = normal;

            setFirstHit = true;
        }

        VoxelData voxelData = ray_result_voxel_data(hit);
        vec4 albedo = voxel_data_albedo(voxelData);
        vec4 specular = voxel_data_specular(voxelData);

        if (DiffuseStateApplyTranslucency(diffuseState, itr, hit, normal, voxelData, albedo, specular, rndState)) {
            ray_iter_skip_block(itr);
            ray_iter_offset_position(itr, itr.direction * 0.1f);
        } else {
            vec3 directSample = DiffuseStateCalculateRadiance(diffuseState, albedo, specular);

            if (bounces++ == -1) {
                directColor += directSample;
            } else {
                indirectColor += directSample;
            }

            DiffuseStateApplySurface(diffuseState, albedo);
            indirectColor += DiffuseStateCalculateSunLight(diffuseState, rtPos, normal, ray_result_skylight(hit) / 15.0f, rndState);

            itr.direction = processNextDirection(diffuseState, rndState, normal);
        }

        ray_iter_set_direction(itr, itr.direction);
    }

    if (hitSky) {
        indirectColor += DiffuseStateCalculateSkyLight(diffuseState, rtPos, itr.direction);

        if (!setFirstHit) {
            const float infinity = intBitsToFloat(0x7f800000);

            firstHit = vec3(infinity);
            firstNormal = -itr.direction;
        }
    }
}
