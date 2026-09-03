#include "/photonics/rendering/restir/common.glsl"
#include "/photonics/rendering/restir/indirect/sample.glsl"
#include "/photonics/utility/normal_encoding.glsl"

#define INDIRECT_RESERVOIR_0 0
#define INDIRECT_RESERVOIR_1 1
#define INDIRECT_CHANNEL_OUT 2
#define INDIRECT_SHADOW_OUT  3

uniform sampler2D gi_reservoirs0;
uniform usampler2D gi_reservoirs1;

uniform sampler2D prev_gi_reservoirs0;
uniform usampler2D prev_gi_reservoirs1;

const float max_indirect_reservoir_samples = 20.0f;

struct IndirectReservoir {
    IndirectSample smple;

    float weight;
    float total_samples;
};

IndirectReservoir indirect_reservoir_empty() {
    return IndirectReservoir(
        indirect_sample_empty(),
        0.0f,
        0.0f
    );
}

bool indirect_reservoir_update(
    inout IndirectReservoir reservoir,
    IndirectSample smple,
    float weight,
    float samples,

    out float required_rng
) {
    reservoir.weight += weight;
    reservoir.total_samples += samples;

    required_rng = weight / reservoir.weight;
    if (ph_rand_next_float(frag_rnd_state) < required_rng) {
        reservoir.smple = smple;
        return true;
    }

    return false;
}

bool indirect_reservoir_merge(
    inout IndirectReservoir reservoir,
    IndirectReservoir source,
    float jacobian,

    out float rng,
    inout float sample_weight
) {
    float source_sample_weight = indirect_sample_weight(source.smple);

    float souce_weight = source_sample_weight * source.weight * source.total_samples * jacobian;
    if (indirect_reservoir_update(reservoir, source.smple, souce_weight, source.total_samples, rng)) {
        sample_weight = source_sample_weight;
        return true;
    }

    return false;
}

void indirect_reservoir_reuse(
        inout IndirectReservoir reservoir,
        IndirectReservoir source,
        FragData source_frag,
        float weight_limit,
        inout float sample_weight
) {
    const float min_weight = 1.0f / weight_limit;
    const float max_weight = weight_limit;

    float jacobian = indirect_sample_compute_jacobian(source.smple, source_frag);
    if (isnan(jacobian) || isinf(jacobian) || jacobian < min_weight || jacobian > max_weight) return;

    source.total_samples = min(max_indirect_reservoir_samples, source.total_samples);

    float ignored;

    float source_sample_weight = indirect_sample_weight(source.smple);
    float source_weight = source_sample_weight * jacobian * source.weight * source.total_samples;
    if (!indirect_reservoir_update(reservoir, source.smple, source_weight, source.total_samples, ignored)) return;

    sample_weight = source_sample_weight;
}


void indirect_reservoir_clamp_samples(inout IndirectReservoir reservoir) {
    if (reservoir.total_samples <= max_indirect_reservoir_samples) return;

    reservoir.weight *= max_indirect_reservoir_samples / reservoir.total_samples;
    reservoir.total_samples = max_indirect_reservoir_samples;
}

#if defined PH_TRACING_INCLUDE
void indirect_reservoir_validate_visiblity(inout IndirectReservoir reservoir, vec3 rt_pos) {
    vec3 hit_point = indirect_sample_get_hit_point(reservoir.smple);

    RayIterator ray;
    ray_iter_begin(ray, rt_pos, hit_point - rt_pos);

    while (true) {
        RayResult result = ray_iter_next(ray);

        if (!ray_result_is_hit(result)) {
            if (!restir_is_sky(hit_point))
                reservoir.weight = MINIMUM_RESERVOIR_WEIGHT * 0.01f;

            return;
        }

        vec3 pos_diff = ray_result_position(result) - hit_point;
        if (dot(pos_diff, pos_diff) < 0.05f) return;

        if (ray_result_is_transparent(result)) {
            ray_iter_skip_block(ray);
            ray_iter_offset_position(ray, ray.direction * 0.03f);

            continue;
        }

        break;
    }

    reservoir.weight = MINIMUM_RESERVOIR_WEIGHT * 0.01f;
}
#endif

void indirect_reservoir_finalize_weight(
    inout IndirectReservoir reservoir,
    float sample_weight
) {
    if (sample_weight <= 0.0f) {
        reservoir.weight = 0.0f;
        return;
    }

    reservoir.weight = (1.0f / sample_weight) * (reservoir.weight / reservoir.total_samples);
}

vec3 indirect_reservoir_get_final_color(inout IndirectReservoir reservoir) {
    return indirect_sample_get_color(reservoir.smple) * reservoir.weight;
}

void indirect_reservoir_encode(IndirectReservoir reservoir, out vec4 data0, out uvec3 data1) {
    data0.xyz = reservoir.smple.hit_point;
    data0.w = uintBitsToFloat(packHalf2x16(vec2(max(reservoir.weight, MINIMUM_RESERVOIR_WEIGHT), reservoir.total_samples)));

    data1.x = reservoir.smple.packed_hit_normal;
    data1.yz = reservoir.smple.packed_color;
}

void indirect_reservoir_decode(out IndirectReservoir reservoir, vec4 data0, uvec3 data1) {
    reservoir.smple.hit_point = data0.xyz;
    reservoir.smple.packed_hit_normal = data1.x;
    reservoir.smple.packed_color = data1.yz;

    vec2 unpacked = unpackHalf2x16(floatBitsToUint(data0.w));
    reservoir.weight = unpacked.x;
    reservoir.total_samples = unpacked.y;
}

bool indirect_reservoir_is_disoccluded(float data) {
    return unpackHalf2x16(floatBitsToUint(data)).y < max_indirect_reservoir_samples;
}

bool indirect_reservoir_is_nan(IndirectReservoir reservoir) {
    return isnan(reservoir.weight) || isnan(reservoir.total_samples);
}

bool indirect_reservoir_load(out IndirectReservoir reservoir, ivec2 tex_coord) {
    indirect_reservoir_decode(
        reservoir,
        texelFetch(gi_reservoirs0, tex_coord, 0),
        texelFetch(gi_reservoirs1, tex_coord, 0).rgb
    );

    return !indirect_reservoir_is_nan(reservoir);
}

bool indirect_reservoir_load_previous(out IndirectReservoir reservoir, ivec2 tex_coord, bool reprojected) {
    indirect_reservoir_decode(
        reservoir,
        texelFetch(prev_gi_reservoirs0, tex_coord, 0),
        texelFetch(prev_gi_reservoirs1, tex_coord, 0).rgb
    );

    if (reprojected) {
        vec3 camera_offset = cameraPosition - previousCameraPosition;
        reservoir.smple.hit_point -= camera_offset;
        indirect_sample_multiply_color(reservoir.smple, get_exposure() / get_previous_exposure());
    }

    return !indirect_reservoir_is_nan(reservoir);
}
