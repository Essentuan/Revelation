#ifndef PH_SHARED_INCLUDE
#define PH_SHARED_INCLUDE

#define MINIMUM_RESERVOIR_WEIGHT 0.000001f

//TODO Rename restir combined gi
#if defined PH_ENABLE_GI && defined PH_RESTIR_COMBINED_GI
#define PH_ENABLE_RESTIR_GI
#endif

#include "/photonics/utility/projection.glsl"
#include "/photonics/utility/normal_encoding.glsl"
#include "/photonics/utility/color.glsl"

const float restir_sky_distance = 100000.0f;

bool restir_is_sky(vec3 player_pos) {
    return any(
            greaterThan(
                    abs(player_pos),
                    vec3(restir_sky_distance * 0.1f)
            )
    );
}

uvec2 restir_pack_color(vec3 color) {
    return uvec2(
        packHalf2x16(color.xy),
        packHalf2x16(vec2(color.z, ph_luminance(color)))
    );
}

vec4 restir_unpack_color(uvec2 packed_colors) {
    return vec4(
        unpackHalf2x16(packed_colors.x),
        unpackHalf2x16(packed_colors.y)
    );
}

#endif
