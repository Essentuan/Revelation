#define VOXEL_COLOR_MODIFIER_SIMPLE

#include "/lib/Utility.glsl"

void voxel_color_modifier(inout vec4 color) {
    color.rgb = sRGBToLinear(color.rgb);
}
