// LENS-07 (docs/plans/lens-screen-effects.md §6.6). Ours, MIT. Falling rain near the camera: one thin quad per drop in a
// MultiMeshInstance3D. Each drop has a fixed world-anchored trajectory (its hash and the fall velocity), wrapped into a
// box that follows the camera, so streaks never swim with the view. A streak is the drop's motion relative to the
// camera during a short exposure: its length and angle come from the camera's own speed through the rain.
// Each streak is a brighter blurred copy of what lies behind it (a drop refracts its surroundings), so day, dusk and
// night agree; lightning adds a cool flash. The CPU integrates the fall (wind and rate changes stay continuous): no TIME.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 travel = vec3(0.0);                      // accumulated fall (render metres), integrated on the CPU
uniform vec3 box_centre = vec3(0.0);
uniform vec3 box_size = vec3(36.0, 24.0, 36.0);
uniform vec3 fall_velocity = vec3(0.0, -6.5, 0.0);     // rain over the ground (wind and fall speed), render axes
uniform vec3 camera_velocity = vec3(0.0);
uniform float exposure_s = 0.05;
uniform float width_m = 0.009;
uniform float opacity = 0.6;
uniform float near_fade_m = 0.5;
uniform float far_fade_m = 16.0;
uniform float flash = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;

varying float fade;
varying vec2 streak_uv;

uint lowbias32(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float hash01(uint x) {
	return float(lowbias32(x) >> 8u) / 16777215.0;
}

void vertex() {
	uint id = uint(INSTANCE_ID);
	vec3 h = vec3(hash01(id * 4u), hash01(id * 4u + 1u), hash01(id * 4u + 2u));
	float jitter = 0.75 + 0.5 * hash01(id * 4u + 3u);
	vec3 velocity = fall_velocity * jitter;
	vec3 origin = box_centre - box_size * 0.5;
	vec3 travelled = h * box_size + travel * jitter;
	vec3 p = origin + mod(travelled - origin, box_size);
	vec3 relative = velocity - camera_velocity;
	float rel_speed = length(relative);
	vec3 axis = rel_speed > 1e-3 ? relative / rel_speed : vec3(0.0, -1.0, 0.0);
	float len = clamp(rel_speed * exposure_s, 0.06, 2.5);
	vec3 to_camera = CAMERA_POSITION_WORLD - p;
	float distance_m = length(to_camera);
	to_camera /= max(distance_m, 1e-4);
	vec3 side = cross(axis, to_camera);
	if (length(side) < 1e-3) {
		side = INV_VIEW_MATRIX[0].xyz;
	}
	side = normalize(side);
	// Keep far streaks at least about a pixel wide without fattening near ones.
	float metres_per_pixel = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float width = max(width_m, distance_m * metres_per_pixel * 1.6);
	vec3 world = p + side * VERTEX.x * width + axis * VERTEX.y * len;
	fade = smoothstep(near_fade_m, near_fade_m * 4.0, distance_m) * (1.0 - smoothstep(far_fade_m * 0.65, far_fade_m, distance_m));
	streak_uv = VERTEX.xy + vec2(0.5);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float across = sqrt(max(1.0 - abs(streak_uv.x * 2.0 - 1.0), 0.0));
	float along = smoothstep(0.0, 0.25, streak_uv.y) * (1.0 - smoothstep(0.75, 1.0, streak_uv.y));
	// A falling drop refracts and reflects its surroundings: a streak is a brighter, blurred copy of what lies behind.
	vec3 behind = textureLod(screen_texture, SCREEN_UV, 2.0).rgb;
	ALBEDO = behind * 1.5 + vec3(0.035) + vec3(0.7, 0.8, 1.0) * flash * 0.6;
	ALPHA = opacity * fade * across * along;
}
