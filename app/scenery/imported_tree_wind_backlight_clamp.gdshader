// L8a-R4: double-sided, clamped source materials with backlight.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
#define TREE_WIND_CLAMP
#define TREE_WIND_BACKLIGHT
#include "res://scenery/imported_tree_wind.gdshaderinc"
