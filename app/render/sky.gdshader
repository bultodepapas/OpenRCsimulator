// Sky background (L1a, L2; LANDSCAPE-PLAN, investigations 01 and 02). Ours, MIT.
// Gradient from the horizon haze to the zenith with weight 1 − (1 − y)^2.6 (Hosek-Wilkie fit at a 45° sun). The
// horizon is EXACTLY the colour the engine fogs distant objects toward (GLES3 fog_process: fog light colour + the
// sun's ×π scatter term), so far terrain melts into the sky with no seam. Below the horizon: pure haze. A 0.53° sun
// disc and halo. A flat cloud deck (L4). Godot's debanding. Never TIME (captures repeat; the radiance renders once).
//
// Colour space (read from the 4.7.2 GLES3 sky.glsl, line 250): Compatibility treats a sky shader's COLOR as sRGB
// and converts it with a cubic srgb_to_linear right after our code. So all maths here is linear (uniforms are linear,
// computed on the CPU) and the result is encoded with the exact inverse of that cubic: the engine gets our linear
// value back, the same number the ground's fog and the engine's object fog use.
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith_lin = vec3(0.076, 0.138, 0.287);
uniform vec3 haze_lin = vec3(0.584, 0.768, 0.846); // fog_light_color.srgb_to_linear() * fog_light_energy
uniform vec3 sun_dir = vec3(0.0, 0.707, 0.707);    // toward the sun == the light's basis.z
uniform vec3 sun_lin = vec3(3.14159);              // light_color.srgb_to_linear() * light_energy * PI
uniform float sun_scatter = 0.0;                   // == Environment.fog_sun_scatter
uniform float gradient_curve = 2.6;
uniform float sun_radius = 0.0046251;              // rad: half of 0.53° (LIGHT0_SIZE defaults to 0)

// L4 clouds: one flat fair-weather deck from periodic value noise over an integer hash (no textures, no TIME).
uniform vec3 cloud_lin = vec3(0.9);         // lit cloud colour, linear
uniform float cloud_coverage = 0.35;        // 0 clear … 1 overcast
uniform float cloud_scale = 6.0;            // noise cells per unit of deck coordinate (dir.xz / dir.y)
uniform vec2 cloud_offset = vec2(0.0);      // drift in cells, wrapped to [0, CLOUD_PERIOD) on the CPU from SIM time
uniform uint cloud_seed = 1u;
const int CLOUD_PERIOD = 64;                // lattice period of the base octave: drift wraps without a jump

// Integer hash (Hoskins-style constants, MIT): uniform in [0, 1).
float hash2(ivec2 c, uint seed) {
	uvec2 q = uvec2(c) * uvec2(1597334677u, 3812015801u);
	uint n = (q.x ^ q.y ^ (seed * 2654435761u)) * 1597334677u;
	return float(n >> 8u) * (1.0 / 16777216.0);
}

// Value noise on a lattice of `period` cells, quintic fade: exactly periodic.
float value_noise(vec2 p, int period, uint seed) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	ivec2 c = ivec2(i);
	float a = hash2(ivec2(c.x % period, c.y % period), seed);
	float b = hash2(ivec2((c.x + 1) % period, c.y % period), seed);
	float d = hash2(ivec2(c.x % period, (c.y + 1) % period), seed);
	float e = hash2(ivec2((c.x + 1) % period, (c.y + 1) % period), seed);
	return mix(mix(a, b, u.x), mix(d, e, u.x), u.y);
}

// 5 octaves at exactly ×2 frequency (so every octave shares the base period), per-octave seeds.
float cloud_fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	int period = CLOUD_PERIOD;
	for (int o = 0; o < 5; o++) {
		vec2 q = mod(p, float(period));
		sum += amp * value_noise(q, period, cloud_seed + uint(o) * 7919u);
		p *= 2.0;
		period *= 2;
		amp *= 0.5;
	}
	return sum / 0.96875;
}

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
	if (EYEDIR.y > 0.0 && cloud_coverage > 0.0) {
		vec2 deck = EYEDIR.xz / max(EYEDIR.y, 0.02);                    // flat layer
		float n = cloud_fbm(deck * cloud_scale + cloud_offset);
		float density = smoothstep(1.0 - cloud_coverage, 1.25 - cloud_coverage, n)
			* smoothstep(0.03, 0.25, EYEDIR.y);                         // thin out into the horizon haze
		col = mix(col, cloud_lin * mix(1.0, 0.82, density), density);   // darker cores
	}
	float ang = acos(clamp(dot(EYEDIR, sun_dir), -1.0, 1.0));
	col += (sun_lin / PI) * (exp(-ang * 18.0) * 0.35 + 4.0 * (1.0 - smoothstep(0.9 * sun_radius, 1.1 * sun_radius, ang)));
	COLOR = encode_for_engine(col);
}
