// LU-25: dry turf, damp soil and submerged bed on the physically sampled basin.
shader_type spatial;
render_mode cull_back, diffuse_burley;
uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
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
 vec3 turf = texture(grass, world_pos.xz / 6.0).rgb;
 float earth = smoothstep(-5.0, -0.7, UV.x);
 float wet = smoothstep(-1.8, 0.6, UV.x);
 vec3 soil = mix(vec3(0.22,0.16,0.08), vec3(0.095,0.10,0.06), wet);
 soil *= 0.85 + 0.25 * clamp(turf.g * 3.0, 0.0, 1.0);
 ALBEDO = mix(turf, soil, earth);
 ROUGHNESS = mix(1.0, 0.85, wet);
 SPECULAR = 0.1 * wet;
 vec3 ray = world_pos - CAMERA_POSITION_WORLD;
 float d = length(ray);
 vec3 v = ray / max(d, 1e-3);
 float h = max(length(v.xz), 1e-4);
 float az = max(dot(v.xz / h, normalize(lobe_dir.xz + vec2(1e-6,0.0))), 0.0);
 vec3 haze = haze_lin + sun_lin * pow(max(dot(v,sun_dir),0.0),8.0)*sun_scatter
  + lobe_lin*pow(az,lobe_k)*exp(-max(asin(clamp(v.y,-1.0,1.0)),0.0)/lobe_height);
 FOG = vec4(haze, 1.0-exp(-beta*d));
 if (!inside_bank(world_pos.xz)) discard;
}
