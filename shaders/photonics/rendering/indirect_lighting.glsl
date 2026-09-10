#include "/photonics/tracing.glsl"

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

    RayResult result = ray_iter_next(itr);
    if (!ray_result_is_hit(result)) return;

    firstHit = ray_result_position(result);
    firstNormal = ray_result_normal(result);

    VoxelData voxelData = ray_result_voxel_data(result);
    vec4 albedo = voxel_data_albedo(voxelData);
    vec4 specular = voxel_data_specular(voxelData);

    if (specular.a == 1.0f) return;
    indirectColor += pow(albedo.rgb, vec3(2.2f)) * specular.a * 10.0f;
}
