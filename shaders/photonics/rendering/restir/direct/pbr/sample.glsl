#include "/photonics/utility/random.glsl"
#include "/photonics/utility/normal_encoding.glsl"

struct DirectSample {
    vec3 hit_point;
    uint packed_hit_normal;

    uvec2 packed_color;
};

DirectSample direct_sample_empty() {
    return DirectSample(vec3(0.0f), 0u, uvec2(0));
}

vec3 direct_sample_get_color(DirectSample smple) {
    return restir_unpack_color(smple.packed_color).rgb;
}

void direct_sample_set_color(inout DirectSample smple, vec3 color) {
    smple.packed_color = restir_pack_color(color);
}

void direct_sample_multiply_color(inout DirectSample smple, float multiplier) {
    direct_sample_set_color(
        smple,
        direct_sample_get_color(smple) * multiplier
    );
}

vec3 direct_sample_get_hit_normal(DirectSample smple) {
    return ph_decode_normal(unpackUnorm2x16(smple.packed_hit_normal));
}

void direct_sample_set_hit_normal(inout DirectSample smple, vec3 hit_normal) {
    smple.packed_hit_normal = packUnorm2x16(ph_encode_normal(hit_normal));
}

vec3 direct_sample_get_hit_point(DirectSample smple) {
    return smple.hit_point + rt_camera_position;
}

void direct_sample_set_hit_point(inout DirectSample smple, vec3 hit_position) {
    smple.hit_point = hit_position - rt_camera_position;
}

float direct_sample_weight(DirectSample smple) {
    return restir_unpack_color(smple.packed_color).a;
}

float direct_sample_compute_jacobian(DirectSample smple, FragData src_frag) {
    #define dst_pos frag_player_pos
    #define dst_geo_normal frag_geo_normal
    #define dst_tex_normal frag_tex_normal

    #define src_pos frag_data_player_pos(src_frag)
    #define src_geo_normal frag_data_geo_normal(src_frag)
    #define src_tex_normal frag_data_tex_normal(src_frag)

    #define hit_pos smple.hit_point
    #define hit_normal direct_sample_get_hit_normal(smple)

    vec3 to_dst = hit_pos - dst_pos;
    float to_dst_sq = dot(to_dst, to_dst);
    float to_dst_inv = inversesqrt(to_dst_sq);

    float jacobian     = dot(hit_normal, to_dst * to_dst_inv) / to_dst_sq;
    float normal_shift = dot(dst_tex_normal, -to_dst * to_dst_inv) / dot(dst_geo_normal, -to_dst * to_dst_inv);

    vec3 to_src = hit_pos - src_pos;
    float to_src_sq = dot(to_src, to_src);
    float to_src_inv = inversesqrt(to_src_sq);

    jacobian     /= dot(hit_normal, to_src * inversesqrt(to_src_sq)) / to_src_sq;
    normal_shift /= dot(src_tex_normal, -to_src * to_src_inv) / dot(src_geo_normal, -to_src * to_src_inv);

    return jacobian * normal_shift;

    #undef dst_pos
    #undef dst_tex_normal
    #undef src_pos
    #undef src_tex_normal
    #undef hit_pos
    #undef hit_normal
}
