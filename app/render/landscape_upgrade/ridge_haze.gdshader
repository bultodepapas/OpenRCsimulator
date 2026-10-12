// LU-16. Distant terrain shares the ground/sky directional haze, not only engine uniform fog.
// Original MIT. No artificial ground-rim fade: ridge height and distance retain their depth cues.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform vec3 haze_lin = vec3(0.584, 0.768, 0.846);
uniform vec3 sun_dir = vec3(0.0, 0.707, 0.707);
uniform vec3 sun_lin = vec3(3.14159);
uniform float sun_scatter = 0.0;
uniform vec3 lobe_lin = vec3(0.0);
uniform vec3 lobe_dir = vec3(1.0, 0.0, 0.0);
uniform float lobe_k = 8.0;
uniform float lobe_height = 1.5708;
uniform float beta = 0.00017;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.12;
	vec3 to_frag = world_pos - CAMERA_POSITION_WORLD;
	float d = length(to_frag);
	vec3 v = to_frag / max(d, 1e-3);
	float h = max(length(v.xz), 1e-4);
	float az = max(dot(v.xz / h, normalize(lobe_dir.xz + vec2(1e-6, 0.0))), 0.0);
	vec3 lobe = lobe_lin * pow(az, lobe_k) * exp(-max(asin(clamp(v.y, -1.0, 1.0)), 0.0) / lobe_height);
	vec3 haze = haze_lin + sun_lin * pow(max(dot(v, sun_dir), 0.0), 8.0) * sun_scatter + lobe;
	FOG = vec4(haze, 1.0 - exp(-beta * d));
}
