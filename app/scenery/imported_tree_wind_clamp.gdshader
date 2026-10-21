// L15b-R2 close-tree wind: double-sided surfaces with non-repeating (clamped) textures.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
#define TREE_WIND_CLAMP
#include "res://scenery/imported_tree_wind.gdshaderinc"
