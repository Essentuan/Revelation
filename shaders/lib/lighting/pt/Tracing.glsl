#include "/photonics/tracing.glsl"

#define VoxelDataEmpty() voxel_data_empty()

uint VoxelDataMaterialId(VoxelData voxelData) {
    return uint(max(voxel_data_block_id(voxelData) - 10000, 1));
}

#define VoxelDataBlockId(voxelData)

vec4 VoxelDataAlbedo(VoxelData voxelData) {
    vec4 result = voxel_data_albedo(voxelData);
    result.rgb = sRGBToLinear(result.rgb) * sRGB_2_Rec2020;

    return result;
}

vec4 VoxelDataNormal(VoxelData voxelData, vec3 geoNormal) {
    vec4 normal = voxel_data_normal(voxelData).xyzz;
    normal.z = sqrt(1.0 - dot(normal.xy, normal.xy));

    vec3 tang = geoNormal.y != 0 ? vec3(-1.,0.,0.) : geoNormal.z != 0 ? vec3(-1.,0.,0.) : vec3(0.,0.,-1.);
    vec3 bitan = geoNormal.y != 0 ? vec3(0.,0.,-1.) : geoNormal.z != 0 ? vec3(0.,-1.,0.) : vec3(0.,-1.,0.);

    mat3 tbn = mat3(tang.xyz, bitan.xyz, geoNormal.xyz);
    normal.xyz = normalize(tbn * normal.xyz);

    return normal;
}

vec4 VoxelDataSpecular(VoxelData voxelData) {
    vec4 specular = voxel_data_specular(voxelData);
    specular.a = specular.a >= 0.999 ? 0.0f : specular.a;

    return specular;
}

#define RayResultEmpty() missed_ray_result()

#define RayResultIsHit(hit) ray_result_is_hit(hit)
#define RayResultPosition(hit) ray_result_position(hit)
#define RayResultNormal(hit) ray_result_normal(hit)
#define RayResultIsTransparent(hit) ray_result_is_transparent(hit)
#define RayResultVoxelData(hit) ray_result_voxel_data(hit)

float RayResultSkylight(RayResult hit) {
    return float(ray_result_skylight(hit)) / 15.0f;
}

#define Ray RayIterator

Ray CreateRay(vec3 pos, vec3 dir) {
    Ray result;
    ray_iter_begin(result, pos, dir);

    return result;
}

#define RaySetPosition(ray, pos) ray_iter_set_position(ray, pos)
#define RayOffsetPosition(ray, offset) ray_iter_offset_position(ray, offset)
#define RaySetDirection(ray, dir) ray.direction = ph_signed_nudge(dir)

#define RayHasNext(ray) ray_iter_has_next(ray)
#define RayNext(ray) ray_iter_next(ray)

#define RaySkipBlock(ray) ray_iter_skip_block(ray)
#define RaySkipVoxel(ray) ray_iter_skip_voxel(ray)

bool IsSubChunkOccupied(vec3 voxelPos) {
    vec3 normPos = ph_to_norm_pos(voxelPos, vec3(0.0f, 0.0f, 0.0f));

    int scale_exp = 21;
    uint node_index = 0;

    for (; scale_exp > world_block_scale_exp; scale_exp-= 2) {
        uint child_index = ph_get_node_cell_index(normPos, scale_exp);
        RtNode node = load_rt_node(node_index);

        if (!rt_node_has_child(node, child_index)) return false;

        node_index = rt_node_get_child(node, child_index, scale_exp);
    }

    return true;
}

bool IsBlockSolid(vec3 voxelPos) {
    vec3 normPos = ph_to_norm_pos(voxelPos, vec3(0.0f, 0.0f, 0.0f));

    int scale_exp = 21;
    uint node_index = 0;

    for (; scale_exp > 0; scale_exp-= 2) {
        uint child_index = ph_get_node_cell_index(normPos, scale_exp);
        RtNode node = load_rt_node(node_index);

        if (rt_node_is_solid(node)) return true;
        if (!rt_node_has_child(node, child_index)) return false;

        node_index = rt_node_get_child(node, child_index, scale_exp);
    }

    return false;
}
