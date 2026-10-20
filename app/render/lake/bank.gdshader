// LU-25: dry turf, damp soil and submerged bed on the physically sampled basin.
// LU-22-R1: reuse the field's licensed dirt maps on the exposed bank, with a
// broken grass-to-soil transition away from the exact water-contact edge.
shader_type spatial;
render_mode cull_back, diffuse_burley;
#include "res://render/grass_surface.gdshaderinc"
#include "res://render/rc_ground_detail.gdshaderinc"
uniform vec3 haze_lin = vec3(0.584, 0.768, 0.846);
uniform vec3 sun_dir = vec3(0.0, 0.707, 0.707);
uniform vec3 sun_lin = vec3(3.14159);
uniform float sun_scatter = 0.0;
uniform float beta = 0.00017;
uniform vec3 lobe_lin = vec3(0.0);
uniform vec3 lobe_dir = vec3(1.0, 0.0, 0.0);
uniform float lobe_k = 8.0;
uniform float lobe_height = 1.5708;
uniform int lake_bank_count = 0;
uniform vec2 lake_bank_points[64];
uniform vec4 lake_bank_bounds = vec4(0.0);
varying vec3 world_pos;
bool inside_bank(vec2 p) {
 bool inside = false;
 int previous = lake_bank_count - 1;
 for (int i = 0; i < 64; i++) {
  if (i >= lake_bank_count) break;
  vec2 a = lake_bank_points[i];
  vec2 b = lake_bank_points[previous];
  if ((a.y > p.y) != (b.y > p.y)) {
   if (p.x < (b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) inside = !inside;
  }
  previous = i;
 }
 return inside;
}
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
 vec3 turf = rough_grass_colour(world_pos.xz);
 // UV.x is signed distance to the water polygon (positive in water). Keep
 // the material fully damp at the true shoreline; vary only the inland edge.
 float boundary_noise = (filtered_vnoise(world_pos.xz / 2.8 + 43.0) - 0.5) * 1.2;
 float earth = smoothstep(-5.0, -0.7, UV.x + boundary_noise);
 float wet = smoothstep(-1.8, 0.6, UV.x + boundary_noise * 0.28);
 vec3 soil = mix(vec3(0.48,0.39,0.245), vec3(0.32,0.335,0.225), wet);
 float sediment = 0.55 * filtered_vnoise(world_pos.xz / 3.8 + 71.0)
  + 0.45 * filtered_vnoise(world_pos.xz / 12.0 + 9.0);
 soil *= (0.85 + 0.25 * clamp(turf.g * 3.0, 0.0, 1.0)) * mix(0.82, 1.16, sediment);
 vec3 base_normal = normalize(NORMAL);
 float d = distance(world_pos, CAMERA_POSITION_WORLD);
 vec2 gx = dFdx(world_pos.xz);
 vec2 gy = dFdy(world_pos.xz);
 float photo_weight = rc_near_weight(gx, gy, d) * earth;
 vec3 photo_normal = vec3(0.5, 0.5, 1.0);
 float photo_roughness = 1.0;
 if (photo_weight > 0.001) {
  vec2 uv_a;
  vec2 uv_b;
  float blend;
  rc_uvs(world_pos.xz, 2.0, uv_a, uv_b, blend);
  vec3 photo_color;
  rc_dirt_sample(uv_a, uv_b, gx * 0.5, gy * 0.5, blend,
   photo_color, photo_normal, photo_roughness);
  vec3 mean_color = OUTPUT_IS_SRGB ? vec3(0.38622, 0.32281, 0.24576)
   : vec3(0.12699, 0.08668, 0.04947);
  soil *= mix(vec3(1.0), clamp(photo_color / mean_color, vec3(0.68), vec3(1.38)),
   photo_weight * 0.72);
 }
 ALBEDO = mix(turf, soil, earth);
 ROUGHNESS = mix(1.0, mix(0.94, 0.82, wet), earth);
 ROUGHNESS = mix(ROUGHNESS, clamp(photo_roughness, 0.75, 1.0), photo_weight * 0.55);
 SPECULAR = 0.1 * wet;
 if (photo_weight > 0.001) {
  NORMAL = rc_project_normal(base_normal, photo_normal, VIEW_MATRIX, photo_weight * 0.38);
 }
 vec3 ray = world_pos - CAMERA_POSITION_WORLD;
 vec3 v = ray / max(d, 1e-3);
 float h = max(length(v.xz), 1e-4);
 float az = max(dot(v.xz / h, normalize(lobe_dir.xz + vec2(1e-6,0.0))), 0.0);
 vec3 haze = haze_lin + sun_lin * pow(max(dot(v,sun_dir),0.0),8.0)*sun_scatter
  + lobe_lin*pow(az,lobe_k)*exp(-max(asin(clamp(v.y,-1.0,1.0)),0.0)/lobe_height);
 FOG = vec4(haze, 1.0-exp(-beta*d));
 if (!inside_bank(world_pos.xz)) discard;
}
