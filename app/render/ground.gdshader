// Ground (L2; LANDSCAPE-PLAN, investigation 02). Ours, MIT. The grass texture in world space (one tile every tile_m
// metres), matte, and the haze written as custom FOG: the same colour formula as the engine's fog and the sky's
// horizon, exponential amount 1 − e^(−βd), plus a rim fade to full haze between rim_start and rim_end so the 6 km
// edge of the ground can never show (realistic haze leaves 36 % contrast there).
shader_type spatial;
render_mode cull_back;

uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 6.0;
uniform vec3 haze_lin = vec3(0.584, 0.768, 0.846);
uniform vec3 sun_dir = vec3(0.0, 0.707, 0.707);
uniform vec3 sun_lin = vec3(3.14159);
uniform float sun_scatter = 0.0;
uniform float beta = 0.00017;
uniform float rim_start = 4800.0;
uniform float rim_end = 6000.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = texture(grass, world_pos.xz / tile_m).rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	vec3 to_frag = world_pos - CAMERA_POSITION_WORLD;
	float d = length(to_frag);
	vec3 v = to_frag / max(d, 1e-3);
	vec3 haze = haze_lin + sun_lin * pow(max(dot(v, sun_dir), 0.0), 8.0) * sun_scatter;
	FOG = vec4(haze, max(1.0 - exp(-beta * d), smoothstep(rim_start, rim_end, d)));
}
