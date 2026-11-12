// DR-32 race gate panels: the solid frame boxes of one gate, merged into one mesh in the gate's frame (x across the
// aperture, y up, z along the normal) and drawn as a league gate is built: a fabric sleeve stretched between two tubes
// as thick as the panel. The tube on the aperture edge is a milky LED diffuser (single LEDs show up close, the chase
// runs along it, its light spills onto the fabric); the outer tube is white PVC; moulded corner connectors with a bolt
// join the posts to the bars; the fabric carries stripes (a checker on the start/finish gate, a solid top banner with
// eyelets), stitched seams and a woven-mesh texture that fades out before it can alias. Tubes are shaded as cylinders
// from the panel's flat faces. Per vertex, UV.x = 1 on a post (long axis y) and 0 on a bar. Presentation only; the
// mesh's boxes are the collision boxes.
shader_type spatial;
render_mode cull_back;

uniform vec4 color_a : source_color = vec4(0.95, 0.18, 0.55, 1.0);
uniform vec4 color_b : source_color = vec4(0.12, 0.12, 0.14, 1.0);
uniform vec4 led_color : source_color = vec4(0.35, 1.0, 0.95, 1.0);
uniform float stripe_period = 0.6;
// How far the LED light spills onto the fabric (m).
uniform float led_width = 0.025;
uniform float led_energy = 1.0;
uniform float panel_glow = 0.0;
uniform bool checker = false;
uniform float checker_cell = 0.09;
// LED animation: chase runs segments along the strip (the next gate); flash is a short white burst (a gate passed);
// breathe is a slow calm-state swell; weave is the fabric mesh texture strength.
uniform float chase = 0.0;
uniform float chase_speed = 1.6;
uniform float flash = 0.0;
uniform float breathe = 0.0;
uniform float weave = 0.035;
// The gate in its own frame (m): aperture half width and half height, outer half width, top of the banner; the
// underside of the bottom bar (below it are the legs); the tube diameter (the panel thickness).
uniform vec4 frame_extent = vec4(0.75, 0.5, 0.93, 0.9);
uniform float frame_bottom = -0.68;
uniform float tube_m = 0.04;
// 1 / the scene's tonemap exposure ^ gamma (race_course_visual.gd): LED emission keeps its on-screen level and hue
// under eye adaptation. One value for every gate, set once per frame.
global uniform float race_exposure_comp;

const vec3 PVC = vec3(0.9, 0.91, 0.93);
const vec3 CONNECTOR = vec3(0.09, 0.09, 0.1);
const vec3 METAL = vec3(0.72, 0.73, 0.75);
const float CONNECTOR_M = 0.075;
const float LEDS_PER_M = 60.0;

varying vec3 local_pos;
varying vec3 local_normal;
varying float post;
varying vec3 axis_x;
varying vec3 axis_y;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	post = UV.x;
	axis_x = (MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
	axis_y = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

// Antialiased half-duty square wave of period 1 at f (1 for fract(f) in 0.25..0.75); fw = the pixel footprint in f.
float bands(float f, float fw) {
	return clamp((0.25 - abs(fract(f) - 0.5)) / max(fw, 1.0e-5) + 0.5, 0.0, 1.0);
}

// Antialiased thin line: 1 where |d| < half_width; fw = the pixel footprint in d's units.
float line(float d, float half_width, float fw) {
	return 1.0 - smoothstep(half_width, half_width + max(fw, 1.0e-5), abs(d));
}

void fragment() {
	float w = frame_extent.x;
	float h = frame_extent.y;
	float x_out = frame_extent.z;
	float y_top = frame_extent.w;
	vec2 p = local_pos.xy;
	float ax = abs(p.x);
	bool front = abs(local_normal.z) > 0.5;
	bool leg = p.y < frame_bottom - 1.0e-3;
	bool vertical = post > 0.5;
	// Pixel footprint (m), taken once outside the branches; fine details fade out before they would speckle.
	float px = max(length(fwidth(local_pos)), 1.0e-6);
	float detail = 1.0 - smoothstep(0.004, 0.01, px);
	// Distance from the aperture (Chebyshev, so the LED corners close) and from the outer boundary; a leg is a post
	// with a white tube on both sides.
	float d_in = leg ? ax - w : max(ax - w, abs(p.y) - h);
	float d_out = leg ? x_out - ax : min(x_out - ax, min(y_top - p.y, p.y - frame_bottom));
	vec2 dir_in = ax - w > abs(p.y) - h ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
	vec2 dir_out = x_out - ax < min(y_top - p.y, p.y - frame_bottom) ? vec2(sign(p.x), 0.0)
		: (y_top - p.y < p.y - frame_bottom ? vec2(0.0, 1.0) : vec2(0.0, -1.0));
	if (leg) {
		dir_in = vec2(-sign(p.x), 0.0);
		dir_out = vec2(sign(p.x), 0.0);
	}
	// Faces: the panel's two broad faces show the tubes and the fabric; a narrow face on the aperture is the LED tube's
	// crown, every other narrow face a white tube's.
	bool led_face = !front && !leg && ax <= w + 1.0e-3 && abs(p.y) <= h + 1.0e-3;
	bool led_tube = !leg && (led_face || (front && d_in < tube_m));
	bool white_tube = !led_tube && (!front || d_out < tube_m || (leg && d_in < tube_m));
	// Moulded connectors on the outer corners and where the bottom bar meets the posts.
	float bar_mid = 0.5 * (frame_bottom - h);
	bool connector = ax > x_out - CONNECTOR_M && (p.y > y_top - CONNECTOR_M
		|| abs(p.y - bar_mid) < 0.5 * (-h - frame_bottom) + 0.03);
	// Along the strip for the LEDs and the chase; across a tube, -1..1 from its inner to its outer side.
	float along_led = abs(dir_in.x) > 0.5 ? p.y : p.x;
	float t = 0.0;
	vec2 tilt = vec2(0.0);
	if (front && led_tube) {
		t = clamp(d_in / tube_m * 2.0 - 1.0, -1.0, 1.0);
		tilt = dir_in;
	} else if (front && white_tube) {
		bool inner_leg = leg && d_in < d_out;
		t = inner_leg ? clamp(1.0 - d_in / tube_m * 2.0, -1.0, 1.0) : clamp(1.0 - d_out / tube_m * 2.0, -1.0, 1.0);
		tilt = inner_leg ? dir_in : dir_out;
	}
	vec3 led_rgb = mix(led_color.rgb, vec3(1.0), clamp(flash, 0.0, 1.0));
	float swell = 1.0 + breathe * 0.35 * sin(TIME * 1.7);
	float run = 0.45 + 0.55 * smoothstep(0.35, 0.65, fract(along_led / 0.35 - TIME * chase_speed));
	float level = led_energy * mix(1.0, run, chase) * swell + flash * 2.0;
	vec3 albedo;
	vec3 emission = vec3(0.0);
	float roughness = 0.8;
	float metallic = 0.0;
	if (connector) {
		albedo = CONNECTOR;
		roughness = 0.45;
		// A bolt in the middle of each connector's broad face.
		vec2 centre = vec2(sign(p.x) * (x_out - 0.5 * CONNECTOR_M),
			p.y > y_top - CONNECTOR_M ? y_top - 0.5 * CONNECTOR_M : bar_mid);
		float bolt = front ? (1.0 - smoothstep(0.009, 0.009 + px, length(p - centre))) * detail : 0.0;
		albedo = mix(albedo, METAL, bolt);
		metallic = 0.8 * bolt;
		tilt = vec2(0.0);
	} else if (led_tube) {
		// Milky diffuser over a strip of single LEDs: hot spots up close, an even line once they would alias.
		float e = along_led * LEDS_PER_M;
		float fade = 1.0 - smoothstep(0.25, 0.6, px * LEDS_PER_M);
		float spot = pow(1.0 - 2.0 * abs(fract(e) - 0.5), 3.0);
		float dots = mix(1.0, 0.6 + 1.6 * spot, fade);
		float core = 0.55 + 0.45 * (1.0 - t * t);
		albedo = mix(vec3(0.82), led_rgb, 0.4);
		emission = led_rgb * level * core * dots;
		roughness = 0.25;
	} else if (white_tube) {
		albedo = PVC;
		roughness = 0.32;
	} else {
		// Fabric.
		float along = vertical ? p.y : p.x;
		if (checker) {
			float cx = bands(p.x / (2.0 * checker_cell), px / (2.0 * checker_cell));
			float cy = bands(p.y / (2.0 * checker_cell), px / (2.0 * checker_cell));
			albedo = mix(vec3(0.95), vec3(0.04), cx * (1.0 - cy) + cy * (1.0 - cx));
		} else if (!vertical && p.y > h) {
			albedo = color_a.rgb;
		} else {
			float f = along / stripe_period;
			albedo = mix(color_a.rgb, color_b.rgb, bands(f, px / stripe_period));
		}
		// Woven vinyl mesh: a fine two-axis weave, faded out where it would alias (same mean either way).
		vec2 fibre = p * 55.0;
		float weave_fade = 1.0 - smoothstep(0.2, 0.5, px * 55.0);
		float pattern = cos(TAU * fibre.x) + cos(TAU * fibre.y);
		albedo *= 1.0 - weave * (1.0 + weave_fade * 0.5 * pattern);
		// The sleeve folds into the tubes: darker in the seam, a stitched line beside it.
		float from_tube = min(d_out, leg ? d_in : max(d_in, 0.0)) - tube_m;
		albedo *= mix(0.62, 1.0, smoothstep(0.0, 0.022, from_tube));
		float dash = bands(along / 0.018, px / 0.018);
		float stitch = line(from_tube - 0.009, 0.0012, px) * dash * detail;
		albedo = mix(albedo, min(albedo * 1.5 + 0.12, vec3(1.0)), stitch);
		// Eyelets along the top of the banner.
		if (!vertical && p.y > h && !checker) {
			vec2 q = vec2(mod(p.x + 0.21, 0.42) - 0.21, p.y - (y_top - tube_m - 0.03));
			float r = length(q);
			float ring = line(r - 0.010, 0.0035, px) * detail;
			albedo = mix(albedo, vec3(0.05), (1.0 - smoothstep(0.006, 0.006 + px, r)) * detail);
			albedo = mix(albedo, METAL, ring);
			metallic = 0.8 * ring;
		}
		// LED light spilling onto the fabric beside the strip (steady: a chase there reads as blocks).
		if (!leg) {
			float steady = led_energy * swell + flash * 2.0;
			emission = led_rgb * steady * 0.18 * exp(-max(d_in - tube_m, 0.0) / max(led_width, 1.0e-3));
		}
		emission += albedo * panel_glow;
	}
	if (front && (tilt.x != 0.0 || tilt.y != 0.0)) {
		vec3 side = normalize(axis_x * tilt.x + axis_y * tilt.y);
		NORMAL = normalize(NORMAL * sqrt(max(1.0 - t * t, 0.0)) + side * t);
	}
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emission * race_exposure_comp;
}
