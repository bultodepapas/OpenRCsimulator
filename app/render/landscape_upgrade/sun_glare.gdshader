// SUN-02/03/04 (docs/plans/sun.md; was LU-04's bounded approximation). Ours, MIT. One full-screen pass over the frame,
// no screen-colour copy. Numbers and sources: render/sun/sun_optics.gd, docs/research/sun/SUN-00/README.md.
// Eye (pilot view): the eye's straylight. CIE 146:2002's disability-glare equation gives the veil θ from the sun per
// unit illuminance at the eye; with r = veil / the luminance behind the target (sky plus aureole) its contrast falls to
// 1/(1 + r), which this mix toward the sun's own displayed colour reproduces with alpha q/(1 + q), q = κ·r. Plus the
// ciliary corona's needles. What loses a model that crosses the sun, the bleached retina, is a canvas overlay
// (render/sun/sun_afterimage.gdshader).
// Lens (chase, orbit, close-up): a camera's smaller veil, a six-blade aperture starburst and ghosts.
// The sun's position is projected here with each camera's own matrices (no frame lag, any FOV or aspect). Its disc is
// occluded by opaque depth on screen (the flown aircraft included; transparent canopies do not write depth) and by the
// skyline prior off screen; clouds come from the CPU mirror of the sky's deck (render/sun/sky_mirror.gd).
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

global uniform float sim_clock;
uniform sampler2D depth_buffer : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 source_dir = vec3(0.0, 1.0, 0.0);     // world, toward the apparent disc
uniform float source_radius = 0.0046251;          // rad
uniform vec3 source_lin = vec3(1.0);              // the disc's mean radiance (pre-exposure): the colour a full veil reaches
uniform float source_scale = 0.0;                 // E/B: sun illuminance / sky luminance around it, sr · clouds · strength (0 = off)
uniform float horizon_prior = 1.0;                // disc visibility assumed while it is off screen
uniform float far_distance = 21000.0;
uniform float exposure = 0.6;
uniform float kappa = 0.75;                       // SunOptics.KAPPA
uniform float age_factor = 1.1678;                // 1 + (A/62.5)⁴
uniform float pigment = 0.5;
uniform float veil_cut = 0.005541;                // the spread at SunOptics.VEIL_CUT_DEG (subtracted)
uniform float veil_cut_deg = 45.0;
uniform float aureole_coeff = 0.0;                // SunOptics.aureole_background_coeff (0 = sky only)
uniform float aureole_core = 0.27;                // deg
uniform int optics = 0;                           // 0 eye, 1 lens
uniform int pass_kind = 0;                        // 0 veil, 1 ghosts (lens), drawn on top
uniform float lens_veil = 0.2;

varying flat vec3 sun_view;
varying flat vec2 sun_uv;
varying flat float sun_valid;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
	sun_view = normalize((VIEW_MATRIX * vec4(source_dir, 0.0)).xyz);
	// A point one unit along the direction projects where the sun does. Orthographic views have no sun position.
	vec4 clip = PROJECTION_MATRIX * vec4(sun_view, 1.0);
	bool perspective = abs(PROJECTION_MATRIX[3][3]) < 0.5;
	sun_valid = perspective && sun_view.z < -1e-4 && clip.w > 1e-6 ? 1.0 : 0.0;
	sun_uv = clip.xy / max(clip.w, 1e-6) * 0.5 + 0.5;
}

float sky_at(vec2 uv, mat4 inverse_projection) {
	float depth = textureLod(depth_buffer, clamp(uv, vec2(0.0), vec2(1.0)), 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 point = inverse_projection * vec4(ndc, 1.0);
	float distance_to_surface = abs(point.z / max(abs(point.w), 1e-8));
	return step(far_distance * 0.98, distance_to_surface);
}

vec3 view_ray(vec2 uv, mat4 inverse_projection) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 p = inverse_projection * vec4(uv * 2.0 - 1.0, 0.0, 1.0);
#else
	vec4 p = inverse_projection * vec4(uv * 2.0 - 1.0, 0.5, 1.0);
#endif
	return normalize(p.xyz / p.w);
}

// CIE 146:2002 straylight above its value at the cut angle (SunOptics.glare_excess).
float glare_excess(float theta_deg) {
	if (theta_deg >= veil_cut_deg) {
		return 0.0;
	}
	float t = clamp(theta_deg, 0.1, 100.0);
	return 10.0 / (t * t * t) + (5.0 / (t * t) + 0.1 * pigment / t) * age_factor + 0.0025 * pigment - veil_cut;
}

float hash11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

// Periodic value noise around the circle: `cells` cells per turn.
float ring_noise(float turns, float cells, float seed) {
	float x = fract(turns) * cells;
	float i = floor(x);
	float f = x - i;
	float a = hash11(mod(i, cells) + seed);
	float b = hash11(mod(i + 1.0, cells) + seed);
	return mix(a, b, f * f * (3.0 - 2.0 * f));
}

// The disc's visibility: opaque depth while it is on screen, the skyline prior off it, blended at the frame edge.
float disc_visibility(mat4 projection, mat4 inverse_projection) {
	float visible = horizon_prior;
	if (sun_valid > 0.0) {
		float radius_uv = tan(source_radius) * 0.5 * abs(projection[1][1]);
		float aspect = abs(projection[1][1] / projection[0][0]);
		vec2 inside = min(sun_uv, 1.0 - sun_uv);
		float on_screen = smoothstep(0.0, 0.02, min(inside.x, inside.y) - radius_uv);
		if (on_screen > 0.0) {
			float clear_disc = sky_at(sun_uv, inverse_projection);
			for (int i = 0; i < 8; i++) {
				float a = float(i) * TAU / 8.0;
				vec2 offset = vec2(cos(a) / aspect, sin(a)) * radius_uv * 0.76;
				clear_disc += sky_at(sun_uv + offset, inverse_projection);
			}
			visible = mix(horizon_prior, clear_disc / 9.0, on_screen);
		}
	}
	return visible;
}

// KS91's aerosol aureole behind the target per unit sun illuminance, above its 45° value (SunOptics.aureole_background).
float aureole_background(float theta_deg) {
	if (theta_deg >= 45.0 || aureole_coeff <= 0.0) {
		return 0.0;
	}
	float far_shape = pow(10.0, 6.15 - theta_deg / 40.0);
	float near_shape = 6.2e7 / (theta_deg * theta_deg + aureole_core * aureole_core);
	return ((theta_deg < 30.0 ? max(near_shape, far_shape) : far_shape) - 105925.4) * aureole_coeff;
}

// The veil's alpha at a pixel: eye straylight with the ciliary corona, or the lens's veil and starburst. The veil is
// taken over the luminance behind the target, the clear sky plus the aureole (SunOptics.veil_ratio).
float veil_alpha(vec3 ray, float scale) {
	if (scale <= 0.0 || sun_view.z >= 0.5) {
		return 0.0;
	}
	float theta_deg = degrees(acos(clamp(dot(ray, sun_view), -1.0, 1.0)));
	float e = scale; // E/B times the disc's visible fraction
	float ratio = e * glare_excess(theta_deg) / (1.0 + e * aureole_background(theta_deg));
	// Around the source on the plane of the sky: the angle φ for the corona and the starburst.
	vec3 side = normalize(abs(sun_view.y) < 0.99 ? cross(sun_view, vec3(0.0, 1.0, 0.0)) : cross(sun_view, vec3(1.0, 0.0, 0.0)));
	vec3 up = cross(side, sun_view);
	float phi = atan(dot(ray, up), dot(ray, side));
	if (optics == 0) {
		// Ciliary corona: fine radial needles near the source (Simpson 1953; Spencer et al. 1995), slowly changing
		// with the pupil (Ritschel et al. 2009). Integer turns per 1024 s keep the shader clock seamless.
		float turns = phi / TAU;
		float drift = sim_clock * (3.0 / 1024.0);
		float needles = pow(ring_noise(turns, 149.0, 7.0), 6.0) + 0.6 * pow(ring_noise(turns + drift, 97.0, 19.0), 8.0);
		ratio *= 1.0 + 0.8 * needles * exp(-theta_deg / 6.0);
	} else {
		// A six-blade aperture: six thin spikes fading over ~20°.
		ratio = ratio * lens_veil + e * 0.08 * pow(abs(cos(3.0 * phi)), 400.0) * exp(-theta_deg / 9.0);
	}
	float q = kappa * max(ratio, 0.0);
	return q / (1.0 + q);
}

// Pass 1, on top of the veil, lens only: ghosts on the line through the frame centre (internal reflections,
// screen-space by nature). Display colours, so ALBEDO divides them by the exposure. The eye's bleached patches are a
// canvas overlay (render/sun/sun_afterimage.gdshader).
void secondary_pass(vec3 ray, vec2 screen_uv, float scale, float aspect, out vec3 albedo, out float alpha) {
	albedo = vec3(0.0);
	alpha = 0.0;
	if (optics == 0) {
		return;
	}
	if (scale <= 0.0 || sun_valid <= 0.0) {
		return;
	}
	vec2 axis = vec2(0.5) - sun_uv;
	float positions[5] = float[](0.45, 0.8, 1.15, 1.55, 2.1);
	float sizes[5] = float[](0.012, 0.035, 0.02, 0.06, 0.03);
	vec3 tints[5] = vec3[](vec3(1.0, 0.75, 0.4), vec3(0.4, 1.0, 0.6), vec3(0.6, 0.6, 1.0), vec3(1.0, 0.6, 0.9), vec3(0.7, 0.9, 1.0));
	float edge_fade = smoothstep(-0.1, 0.15, min(min(sun_uv.x, 1.0 - sun_uv.x), min(sun_uv.y, 1.0 - sun_uv.y)));
	vec3 color = vec3(0.0);
	for (int g = 0; g < 5; g++) {
		vec2 at = sun_uv + axis * positions[g];
		float r = length((screen_uv - at) * vec2(aspect, 1.0)) / sizes[g];
		float disc = smoothstep(1.0, 0.85, r) * (0.35 + 0.65 * smoothstep(0.3, 1.0, r));
		float a = disc * 0.05 * min(scale, 1.5) * edge_fade;
		color += tints[g] * a;
		alpha += a;
	}
	alpha = clamp(alpha, 0.0, 0.3);
	albedo = alpha > 0.0 ? color / max(alpha, 1e-6) * 0.9 / exposure : vec3(0.0);
}

void fragment() {
	vec3 ray = view_ray(SCREEN_UV, INV_PROJECTION_MATRIX);
	float scale = source_scale;
	if (scale > 0.0) {
		scale *= disc_visibility(PROJECTION_MATRIX, INV_PROJECTION_MATRIX);
	}
	vec3 albedo = source_lin;
	float alpha;
	if (pass_kind == 0) {
		alpha = veil_alpha(ray, scale);
	} else {
		secondary_pass(ray, SCREEN_UV, scale, abs(PROJECTION_MATRIX[1][1] / PROJECTION_MATRIX[0][0]), albedo, alpha);
	}
	ALBEDO = albedo;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
