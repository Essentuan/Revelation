#include "/photonics/tracing.glsl"
#include "/lib/lighting/pt/DiffuseState.glsl"

bool shouldPassThrough(RayResult hit, vec4 albedo, inout uint rndState) {
    return ray_result_is_transparent(hit) && (ph_rand_next_float(rndState) > albedo.a);
}

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

    const float infinity = intBitsToFloat(0x7f800000);
    firstHit = vec3(infinity);
    firstNormal = -itr.direction;

    DiffuseState diffuseState = DiffuseStateEmpty();

    bool hitSky = false;

    #define MAX_BOUNCES 1
    for (int i = -1; i < MAX_BOUNCES; i++) {
        ray_iter_offset_position(itr, itr.direction * 0.01f);
        RayResult hit = ray_iter_next(itr);

        if (itr.iterations <= 0) return;
        if (!ray_result_is_hit(hit)) {
            hitSky = true;
            break;
        }

        rtPos = ray_result_position(hit);
        normal = ray_result_normal(hit);

        VoxelData voxelData = ray_result_voxel_data(hit);
        vec4 albedo = voxel_data_albedo(voxelData);

        if (shouldPassThrough(hit, albedo, rndState)) {
            DiffuseStateApplyTranslucency(diffuseState, albedo);
            ray_iter_offset_position(itr, itr.direction);

            i--;
            continue;
        } else if (i == -1) {
            firstHit = rtPos;
            firstNormal = normal;
        }

        vec3 directSample = DiffuseStateCalculateRadiance(diffuseState, albedo, voxel_data_specular(voxelData));

        if (i == -1) {
            directColor += directSample;
        } else {
            indirectColor += directSample;
        }

        DiffuseStateApplySurface(diffuseState, albedo);
        indirectColor += DiffuseStateCalculateSunLight(diffuseState, rtPos, normal, ray_result_skylight(hit) / 15.0f, rndState);

        ray_iter_set_position(itr, rtPos);
        ray_iter_set_direction(itr, processNextDirection(diffuseState, rndState, normal));
    }

    if (hitSky) {
        indirectColor += DiffuseStateCalculateSkyLight(diffuseState, rtPos, itr.direction);
    }
}
