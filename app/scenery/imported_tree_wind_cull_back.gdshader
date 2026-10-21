// L15b-R2 close-tree wind: back-face-culled surfaces (opaque bark) with repeating textures.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://scenery/imported_tree_wind.gdshaderinc"
