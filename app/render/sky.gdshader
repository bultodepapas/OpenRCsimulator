// Sky background (L1a, L2; LANDSCAPE-PLAN, investigations 01 and 02). Ours, MIT.
// Gradient from the horizon haze to the zenith with weight 1 − (1 − y)^2.6 (Hosek-Wilkie fit at a 45° sun). The
// horizon is EXACTLY the colour the engine fogs distant objects toward (GLES3 fog_process: fog light colour + the
// sun's ×π scatter term), so far terrain melts into the sky with no seam. Below the horizon: pure haze. A 0.53° sun
// disc and halo. Clouds are periodic and deterministic; their drift is supplied from simulation time on the CPU.
// Godot's debanding. Never TIME (captures repeat; the radiance renders once).
//
// Colour space (read from the 4.7.2 GLES3 sky.glsl, line 250): Compatibility treats a sky shader's COLOR as sRGB
// and converts it with a cubic srgb_to_linear right after our code. So all maths here is linear (uniforms are linear,
// computed on the CPU) and the result is encoded with the exact inverse of that cubic: the engine gets our linear
// value back, the same number the ground's fog and the engine's object fog use.
shader_type sky;
render_mode use_debanding;
#include "res://render/cloud_field.gdshaderinc"

uniform vec3 zenith_lin = vec3(0.076, 0.138, 0.287);
uniform vec3 haze_lin = vec3(0.584, 0.768, 0.846); // fog_light_color.srgb_to_linear() * fog_light_energy
uniform vec3 sun_dir = vec3(0.0, 0.707, 0.707);    // toward the sun == the light's basis.z
uniform vec3 sun_lin = vec3(3.14159);              // light_color.srgb_to_linear() * light_energy * PI
uniform float sun_scatter = 0.0;                   // == Environment.fog_sun_scatter
uniform float gradient_curve = 2.6;
uniform float sun_radius = 0.0046251;              // rad: half of 0.53° (LIGHT0_SIZE defaults to 0)

// L4 fair-weather deck, now able to group into larger patches while keeping the old setting at zero strength.
uniform vec3 cloud_lin = vec3(0.9);         // lit cloud colour, linear
uniform float cloud_coverage = 0.35;        // 0 clear … 1 overcast
uniform float cloud_scale = 6.0;            // noise cells per unit of deck coordinate (dir.xz / dir.y)
uniform vec2 cloud_offset = vec2(0.0);      // drift in cells, wrapped to [0, CLOUD_FIELD_PERIOD) on the CPU from SIM time
uniform uint cloud_seed = 1u;
uniform float cluster_strength : hint_range(0.0, 1.0) = 0.0;
uniform float cirrus_strength : hint_range(0.0, 0.12) = 0.0; // maximum sky blend for the thin layer
uniform float cirrus_coverage : hint_range(0.0, 1.0) = 0.34;
uniform float silver_strength : hint_range(0.0, 1.0) = 0.0;

vec3 haze(vec3 d) {
	return haze_lin + sun_lin * pow(max(dot(d, sun_dir), 0.0), 8.0) * sun_scatter;
}

// Exact inverse of the engine's srgb_to_linear(s) = s·(s·(0.305306011·s + 0.682171111) + 0.012522878):
// Newton's method from the engine's own linear_to_srgb approximation; 3 steps reach float precision.
vec3 encode_for_engine(vec3 x) {
	vec3 s = max(vec3(1.055) * pow(max(x, vec3(0.0)), vec3(0.416666667)) - vec3(0.055), vec3(0.0));
	for (int i = 0; i < 3; i++) {
		vec3 f = s * (s * (s * 0.305306011 + 0.682171111) + 0.012522878) - x;
		vec3 df = s * (s * 0.915918033 + 1.364342222) + 0.012522878;
		s -= f / df;
	}
	return s;
}

void sky() {
	float y = max(EYEDIR.y, 0.0);
	vec3 col = mix(haze(EYEDIR), zenith_lin, 1.0 - pow(1.0 - y, gradient_curve));
	float density = 0.0;
	if (EYEDIR.y > 0.0 && cloud_coverage > 0.0) {
		vec2 deck = EYEDIR.xz / max(EYEDIR.y, 0.02);                    // flat layer
		vec2 cells = mod(deck * cloud_scale + cloud_offset, float(CLOUD_FIELD_PERIOD));
		density = cloud_density(cells, cloud_seed, cloud_coverage, cluster_strength)
			* smoothstep(0.03, 0.25, EYEDIR.y);                           // thin out into the horizon haze
		col = mix(col, cloud_lin * mix(1.0, 0.82, density), density);   // darker cores

		// A higher, very thin deck: noise stretched along the horizon, with an exact 64-cell period.
		if (cirrus_strength > 0.0) {
			float cirrus = cloud_stretched_density(cells, cloud_seed + 15485863u, cirrus_coverage, vec2(3.0, 51.0) / 64.0)
				* smoothstep(0.02, 0.18, EYEDIR.y);
			float cirrus_amount = clamp(cirrus * clamp(cirrus_strength, 0.0, 0.12), 0.0, 0.12);
			col = mix(col, cloud_lin * 1.04, cirrus_amount);
		}

		// A bounded forward-scatter edge on clouds close to the sun direction; never raises the deck by > 0.08.
		if (silver_strength > 0.0) {
			float cloud_edge = 4.0 * density * (1.0 - density);
			float forward_scatter = pow(max(dot(EYEDIR, sun_dir), 0.0), 24.0);
			float silver = 0.08 * clamp(silver_strength, 0.0, 1.0) * cloud_edge * forward_scatter;
			col += cloud_lin * silver;
		}
	}
	float ang = acos(clamp(dot(EYEDIR, sun_dir), -1.0, 1.0));
	col += (sun_lin / PI) * (exp(-ang * 18.0) * 0.35 + 4.0 * (1.0 - smoothstep(0.9 * sun_radius, 1.1 * sun_radius, ang)));
	COLOR = encode_for_engine(col);
}
