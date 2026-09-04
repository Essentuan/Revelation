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

vec3 rtTexNormal(VoxelData voxelData, vec3 geoNormal) {
    vec3 tang = geoNormal.y != 0 ? vec3(-1.,0.,0.) : geoNormal.z != 0 ? vec3(-1.,0.,0.) : vec3(0.,0.,-1.);
    vec3 bitan = geoNormal.y != 0 ? vec3(0.,0.,-1.) : geoNormal.z != 0 ? vec3(0.,-1.,0.) : vec3(0.,-1.,0.);

    mat3 tbn = mat3(tang.xyz, bitan.xyz, geoNormal.xyz);
    return normalize(tbn * voxel_data_normal(voxelData).xyz);
}
