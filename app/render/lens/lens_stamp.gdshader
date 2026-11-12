// LENS-04/10/11 (docs/plans/lens-screen-effects.md §5.2, §7.2). Ours, MIT. Things stuck on the lens, one instance of a
// unit quad each in a MultiMeshInstance2D: procedural shapes, so no texture memory and nothing to license.
// Custom data: x kind (0 blood splat, 1 mud splat, 2 grass blade, 3 cracked lens), y seed, z opacity, w radius (px).
// Liquids absorb and refract the live image; mud is mostly opaque; grass is out of focus; a crack splits the image
// chromatically along its line. No TIME: the CPU ages every stamp.
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec3 blood_sigma = vec3(0.55, 7.5, 8.5);
uniform vec3 blood_albedo = vec3(0.30, 0.012, 0.010);
uniform float blood_dry = 0.0;

varying vec4 stamp;
varying vec2 local;
varying vec2 axis_x;

uint lowbias32(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float hash01(int a, int b) {
	return float(lowbias32(uint(a) * 1597334677u ^ uint(b) * 3812015801u) >> 8u) / 16777215.0;
}

// A splat: a noisy disc with spikes thrown outward and satellite droplets. Distance in quad half-sizes.
float splat_sdf(vec2 q, int salt) {
	float angle = atan(q.y, q.x);
	float radius = 0.42;
	for (int k = 0; k < 5; k++) {
		float freq = float(k + 2);
		radius += 0.05 / freq * sin(angle * freq + hash01(salt, k) * 6.2831);
	}
	for (int k = 0; k < 7; k++) {
		float at = hash01(salt, 20 + k) * 6.2831;
		float delta = abs(mod(angle - at + 3.14159, 6.28318) - 3.14159);
		radius += (0.12 + 0.3 * hash01(salt, 40 + k)) * exp(-pow(delta / (0.06 + 0.08 * hash01(salt, 60 + k)), 2.0));
	}
	float d = length(q) - radius;
	for (int k = 0; k < 6; k++) {
		float at = hash01(salt, 80 + k) * 6.2831;
		float far = 0.6 + 0.32 * hash01(salt, 100 + k);
		float r = 0.025 + 0.06 * hash01(salt, 120 + k);
		d = min(d, length(q - far * vec2(cos(at), sin(at))) - r);
	}
	return d;
}

// Distance to segment ab.
float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
	return length(pa - ba * h);
}

// A radial crack network from an impact point: kinked rays and a few concentric arcs. Distance in half-sizes.
float crack_sdf(vec2 q, int salt, out vec2 along) {
	float best = 1e3;
	along = vec2(1.0, 0.0);
	for (int k = 0; k < 9; k++) {
		float at = (float(k) + hash01(salt, k)) * 6.2831 / 9.0;
		float len1 = 0.18 + 0.25 * hash01(salt, 30 + k);
		float len2 = len1 + 0.2 + 0.45 * hash01(salt, 60 + k);
		float bend = (hash01(salt, 90 + k) - 0.5) * 0.7;
		vec2 a = vec2(0.0);
		vec2 b = len1 * vec2(cos(at), sin(at));
		vec2 c = len2 * vec2(cos(at + bend), sin(at + bend));
		float d1 = segment(q, a, b);
		float d2 = segment(q, b, c);
		if (d1 < best) { best = d1; along = normalize(b - a); }
		if (d2 < best) { best = d2; along = normalize(c - b); }
	}
	for (int k = 0; k < 3; k++) {
		float ring = 0.16 + 0.22 * float(k) + 0.06 * hash01(salt, 150 + k);
		float start = hash01(salt, 170 + k) * 6.2831;
		float span = 0.8 + 1.4 * hash01(salt, 190 + k);
		float angle = atan(q.y, q.x);
		float delta = mod(angle - start, 6.28318);
		if (delta < span) {
			float d = abs(length(q) - ring);
			if (d < best) { best = d; along = normalize(vec2(-q.y, q.x)); }
		}
	}
	return best;
}

void vertex() {
	stamp = INSTANCE_CUSTOM;
	local = VERTEX;
	axis_x = normalize(MODEL_MATRIX[0].xy);
}

void fragment() {
	int kind = int(stamp.x + 0.5);
	int salt = int(stamp.y * 65521.0);
	float radius_px = max(stamp.w, 1.0);
	vec2 q = local * 2.0;
	vec2 axis_y = vec2(-axis_x.y, axis_x.x);
	float px = 1.0 / radius_px;
	vec3 colour = vec3(0.0);
	float alpha = 0.0;
	if (kind <= 1) {
		float d = splat_sdf(q, salt);
		float coverage = 1.0 - smoothstep(-px * 1.5, px * 1.5, d);
		if (coverage <= 0.0) {
			discard;
		}
		float h = clamp(-d * 4.0, 0.0, 1.0);
		const float e = 0.02;
		vec2 g = vec2(splat_sdf(q + vec2(e, 0.0), salt) - splat_sdf(q - vec2(e, 0.0), salt),
			splat_sdf(q + vec2(0.0, e), salt) - splat_sdf(q - vec2(0.0, e), salt));
		vec2 screen_g = (axis_x * g.x + axis_y * g.y);
		vec3 behind = textureLod(screen_texture, clamp(SCREEN_UV + screen_g * SCREEN_PIXEL_SIZE * 40.0 * (1.0 - h), vec2(0.0), vec2(1.0)), 1.0 + 1.5 * h).rgb;
		vec3 ambient = textureLod(screen_texture, SCREEN_UV, 5.0).rgb;
		float lum = dot(ambient, vec3(0.2126, 0.7152, 0.0722));
		vec3 normal = normalize(vec3(-screen_g * 8.0 * (1.0 - h), 1.0));
		float spec = pow(max(dot(normal, normalize(vec3(-0.35, -0.55, 0.76))), 0.0), 30.0);
		if (kind == 0) {
			float density = 1.5 * h + 0.25;
			vec3 film_albedo = mix(blood_albedo, blood_albedo * 0.55, blood_dry);
			colour = behind * exp(-blood_sigma * density) + film_albedo * (1.0 - exp(-2.4 * density)) * (0.35 + 0.65 * lum) * 1.6;
			colour += vec3(0.5, 0.42, 0.4) * spec * (0.3 + 0.7 * lum) * (1.0 - blood_dry * 0.7);
			alpha = coverage;
		} else {
			vec3 mud = mix(vec3(0.20, 0.14, 0.085), vec3(0.32, 0.24, 0.15), hash01(salt, 7)) * (0.45 + 0.75 * lum);
			colour = mix(behind * vec3(0.55, 0.45, 0.35), mud, smoothstep(0.0, 0.35, h));
			colour += vec3(0.35) * spec * 0.6;
			alpha = coverage * mix(0.75, 1.0, h);
		}
	} else if (kind == 2) {
		// A grass blade lying across the lens, out of focus: a curved tapering strip with a paler midrib.
		float x = q.x;
		float bend = (hash01(salt, 3) - 0.5) * 0.9;
		float centre = bend * (x * x - 0.6) * 0.5;
		float half_width = 0.11 * (1.0 - x * x) + 0.01;
		float d = abs(q.y - centre) - half_width;
		float soft = 0.05;
		float coverage = (1.0 - smoothstep(-soft, soft, d)) * (1.0 - smoothstep(0.9, 1.0, abs(x)));
		if (coverage <= 0.0) {
			discard;
		}
		vec3 ambient = textureLod(screen_texture, SCREEN_UV, 5.0).rgb;
		float lum = dot(ambient, vec3(0.2126, 0.7152, 0.0722));
		vec3 green = mix(vec3(0.16, 0.30, 0.07), vec3(0.32, 0.44, 0.12), hash01(salt, 9));
		float rib = 1.0 - smoothstep(0.0, 0.25, abs(q.y - centre) / max(half_width, 1e-3));
		colour = green * (0.35 + 0.8 * lum) * (1.0 + 0.35 * rib);
		alpha = coverage * 0.92;
	} else {
		vec2 along;
		float d = crack_sdf(q, salt, along);
		float d_px = d * radius_px;
		float line = 1.0 - smoothstep(0.6, 2.2, d_px);
		float halo = 1.0 - smoothstep(2.0, 9.0, d_px);
		if (halo <= 0.0) {
			discard;
		}
		vec2 normal_local = vec2(-along.y, along.x);
		vec2 n = (axis_x * normal_local.x + axis_y * normal_local.y) * SCREEN_PIXEL_SIZE * 3.0;
		float r = textureLod(screen_texture, clamp(SCREEN_UV + n, vec2(0.0), vec2(1.0)), 0.0).r;
		float g = textureLod(screen_texture, SCREEN_UV, 0.0).g;
		float b = textureLod(screen_texture, clamp(SCREEN_UV - n, vec2(0.0), vec2(1.0)), 0.0).b;
		colour = mix(vec3(r, g, b), vec3(0.92, 0.95, 1.0), line * 0.55) * (1.0 - 0.25 * (halo - line));
		alpha = max(line, halo * 0.85);
	}
	COLOR = vec4(colour, alpha * stamp.z);
}
