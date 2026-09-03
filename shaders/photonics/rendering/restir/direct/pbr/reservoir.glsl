#include "/photonics/rendering/restir/common.glsl"
#include "/photonics/rendering/restir/direct/pbr/sample.glsl"
#include "/photonics/utility/normal_encoding.glsl"

#define DIRECT_RESERVOIR_0 0
#define DIRECT_RESERVOIR_1 1
#define DIRECT_CHANNEL_OUT 2
#define DIRECT_SHADOW_OUT  3

uniform sampler2D di_reservoirs0;
uniform usampler2D di_reservoirs1;

uniform sampler2D prev_di_reservoirs0;
uniform usampler2D prev_di_reservoirs1;

const float max_direct_reservoir_samples = 20.0f;

struct DirectReservoir {
    DirectSample smple;

    float weight;
    float total_samples;
};

DirectReservoir direct_reservoir_empty() {
    return DirectReservoir(
            direct_sample_empty(),
            0.0f,
            0.0f
    );
}

bool direct_reservoir_update(
        inout DirectReservoir reservoir,
        DirectSample smple,
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

bool direct_reservoir_merge(
        inout DirectReservoir reservoir,
        DirectReservoir source,
        float jacobian,

        out float rng,
        inout float sample_weight
) {
    float source_sample_weight = direct_sample_weight(source.smple);

    float souce_weight = source_sample_weight * source.weight * source.total_samples * jacobian;
    if (direct_reservoir_update(reservoir, source.smple, souce_weight, source.total_samples, rng)) {
        sample_weight = source_sample_weight;
        return true;
    }

    return false;
}

void direct_reservoir_reuse(
        inout DirectReservoir reservoir,
        DirectReservoir source,
        FragData source_frag,
        float weight_limit,
        inout float sample_weight
) {
    const float min_weight = 1.0f / weight_limit;
    const float max_weight = weight_limit;

    float jacobian = direct_sample_compute_jacobian(source.smple, source_frag);
    if (isnan(jacobian) || isinf(jacobian) || jacobian < min_weight || jacobian > max_weight) return;

    source.total_samples = min(max_direct_reservoir_samples, source.total_samples);

    float ignored;

    float source_sample_weight = direct_sample_weight(source.smple);
    float source_weight = source_sample_weight * jacobian * source.weight * source.total_samples;
    if (!direct_reservoir_update(reservoir, source.smple, source_weight, source.total_samples, ignored)) return;

    sample_weight = source_sample_weight;
}


void direct_reservoir_clamp_samples(inout DirectReservoir reservoir) {
    if (reservoir.total_samples <= max_direct_reservoir_samples) return;

    reservoir.weight *= max_direct_reservoir_samples / reservoir.total_samples;
    reservoir.total_samples = max_direct_reservoir_samples;
}

#if defined PH_TRACING_INCLUDE
void direct_reservoir_validate_visiblity(inout DirectReservoir reservoir, vec3 rt_pos) {
    vec3 hit_point = direct_sample_get_hit_point(reservoir.smple);

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

void direct_reservoir_finalize_weight(
        inout DirectReservoir reservoir,
        float sample_weight
) {
    if (sample_weight <= 0.0f) {
        reservoir.weight = 0.0f;
        return;
    }

    reservoir.weight = (1.0f / sample_weight) * (reservoir.weight / reservoir.total_samples);
}

vec3 direct_reservoir_get_final_color(inout DirectReservoir reservoir) {
    return direct_sample_get_color(reservoir.smple) * reservoir.weight;
}

void direct_reservoir_encode(DirectReservoir reservoir, out vec4 data0, out uvec3 data1) {
    data0.xyz = reservoir.smple.hit_point;
    data0.w = uintBitsToFloat(packHalf2x16(vec2(max(reservoir.weight, MINIMUM_RESERVOIR_WEIGHT), reservoir.total_samples)));

    data1.x = reservoir.smple.packed_hit_normal;
    data1.yz = reservoir.smple.packed_color;
}

void direct_reservoir_decode(out DirectReservoir reservoir, vec4 data0, uvec3 data1) {
    reservoir.smple.hit_point = data0.xyz;
    reservoir.smple.packed_hit_normal = data1.x;
    reservoir.smple.packed_color = data1.yz;

    vec2 unpacked = unpackHalf2x16(floatBitsToUint(data0.w));
    reservoir.weight = unpacked.x;
    reservoir.total_samples = unpacked.y;
}

bool direct_reservoir_is_disoccluded(float data) {
    return unpackHalf2x16(floatBitsToUint(data)).y < max_direct_reservoir_samples;
}

bool direct_reservoir_is_nan(DirectReservoir reservoir) {
    return isnan(reservoir.weight) || isnan(reservoir.total_samples);
}

bool direct_reservoir_load(out DirectReservoir reservoir, ivec2 tex_coord) {
    direct_reservoir_decode(
            reservoir,
            texelFetch(di_reservoirs0, tex_coord, 0),
            texelFetch(di_reservoirs1, tex_coord, 0).rgb
    );

    return !direct_reservoir_is_nan(reservoir);
}

bool direct_reservoir_load_previous(out DirectReservoir reservoir, ivec2 tex_coord, bool reprojected) {
    direct_reservoir_decode(
            reservoir,
            texelFetch(prev_di_reservoirs0, tex_coord, 0),
            texelFetch(prev_di_reservoirs1, tex_coord, 0).rgb
    );

    if (reprojected) {
        reservoir.smple.hit_point += previousCameraPosition - cameraPosition;
        direct_sample_multiply_color(reservoir.smple, get_exposure() / get_previous_exposure());
    }

    return !direct_reservoir_is_nan(reservoir);
}
