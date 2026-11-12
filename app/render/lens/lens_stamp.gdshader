// LENS-04/10/11 (docs/plans/lens-screen-effects.md §5.2, §7.2). Things stuck on the lens, one instance of a unit quad
// each in a MultiMeshInstance2D. Custom data: x kind (0 blood splat, 1 mud splat, 2 grass blade, 3 cracked lens, 4 blood runner) + dryness,
// y seed, z opacity, w radius in pixels. No TIME: the CPU ages every stamp.
//
// Splat shapes are real photographed ink splatters (app/assets/lens/splats.png, CC0, Dino0040 via OpenGameArt; built by
// tools/lens/build_splat_atlas.py): the top row liquid splats for blood, the bottom row clumpy splats for mud. The
// atlas's blurred mips give each splat a dome of thickness, so blood absorbs and refracts the live image by its depth.
// The cracked lens follows the radial Voronoi technique of "Impact Glass Shader" by Lord0Sanz (MIT, see
// IMPACT_GLASS_LICENSE.txt): feature points scattered around the impact at growing radii; the difference between the
// nearest and second-nearest distances draws the cracks, and each shard refracts the image away from its point.
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D splat_atlas : filter_linear_mipmap, repeat_disable;
uniform vec3 blood_sigma = vec3(1.8, 9.0, 10.0);
uniform vec3 blood_albedo = vec3(0.19, 0.009, 0.008);
uniform float blood_dry = 0.0;
const float RUNNER_ASPECT = 0.12; // runner quad height / length (lens_stack.gd RUNNER_ASPECT)
uniform vec2 crack_points[32];
uniform int crack_point_count = 0;
// Physical pixels per canvas pixel: the UI may stretch the canvas (content scale) on 1440p and 4K screens.
uniform float canvas_scale = 1.0;

varying vec4 stamp;
varying vec2 local;
varying vec2 axis_x;
varying float phase; // a per-instance phase from the instance's position (runners meander differently)

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

float value_noise(vec2 p, int salt) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 s = f * f * (3.0 - 2.0 * f);
	int x = int(i.x) + salt * 131;
	int y = int(i.y);
	return mix(mix(hash01(x, y), hash01(x + 1, y), s.x), mix(hash01(x, y + 1), hash01(x + 1, y + 1), s.x), s.y);
}

// Atlas coverage of cell (column, row) at local q in [-1, 1]², with a blur level (mip).
float atlas(vec2 q, int column, int row, float lod) {
	vec2 uv = (clamp(q * 0.5 + 0.5, vec2(0.0), vec2(1.0)) + vec2(float(column), float(row))) / vec2(4.0, 2.0);
	return textureLod(splat_atlas, uv, lod).r;
}

// Radial Voronoi crack field around the impact at the origin (after Impact Glass Shader, MIT). The feature points are
// computed once per crack on the CPU (lens_stack.gd _crack_points): the loop is plain distances. Lengths in half-sizes.
float crack_field(vec2 q, out float nearest_distance, out vec2 nearest_point) {
	float first = 1e3;
	float second = 1e3;
	nearest_point = q;
	for (int i = 0; i < 32; i++) {
		if (i >= crack_point_count) {
			break;
		}
		vec2 point = crack_points[i];
		float d = distance(q, point);
		if (d < first) {
			second = first;
			first = d;
			nearest_point = point;
		} else if (d < second) {
			second = d;
		}
	}
	nearest_distance = first;
	return second - first;
}

// Shrinkage cracks of drying mud: distance to the nearest Voronoi edge, thresholded to thin dark lines.
float crackle(vec2 p, int salt) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float first = 8.0;
	float second = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			int cx = int(cell.x) + i;
			int cy = int(cell.y) + j;
			vec2 point = o + vec2(hash01(cx + salt * 31, cy), hash01(cy + salt * 17, cx + 5)) - f;
			float d = dot(point, point);
			if (d < first) {
				second = first;
				first = d;
			} else if (d < second) {
				second = d;
			}
		}
	}
	return 1.0 - smoothstep(0.0, 0.06, sqrt(second) - sqrt(first));
}

void vertex() {
	stamp = INSTANCE_CUSTOM;
	local = VERTEX;
	axis_x = normalize(MODEL_MATRIX[0].xy);
	phase = MODEL_MATRIX[2].x * 0.0131 + MODEL_MATRIX[2].y * 0.0077;
}

void fragment() {
	// x packs the kind (integer part) and this stamp's own dryness (fraction / 0.9); see lens_stack.gd _write_stamps.
	int kind = int(floor(stamp.x + 0.001));
	float dry = clamp(fract(stamp.x + 0.001) / 0.9, 0.0, 1.0);
	int salt = int(stamp.y * 65521.0);
	int column = int(stamp.y * 3.999);
	float radius_px = max(stamp.w, 1.0);
	vec2 px_uv = SCREEN_PIXEL_SIZE * canvas_scale; // one canvas pixel in screen uv
	vec2 q = local * 2.0;
	vec2 axis_y = vec2(-axis_x.y, axis_x.x);
	vec3 ambient = textureLod(screen_texture, SCREEN_UV, 5.0).rgb;
	float lum = dot(ambient, vec3(0.2126, 0.7152, 0.0722));
	vec3 colour = vec3(0.0);
	float alpha = 0.0;
	if (kind <= 1) {
		int row = kind;
		float coverage = atlas(q, column, row, 0.0);
		if (coverage <= 0.004) {
			discard;
		}
		// Thickness: the blurred coverage is a dome over each blob; its gradient is the liquid surface's slope.
		float h = atlas(q, column, row, 3.0);
		const float e = 0.03;
		vec2 g = vec2(atlas(q + vec2(e, 0.0), column, row, 3.0) - atlas(q - vec2(e, 0.0), column, row, 3.0),
			atlas(q + vec2(0.0, e), column, row, 3.0) - atlas(q - vec2(0.0, e), column, row, 3.0));
		vec2 screen_g = axis_x * g.x + axis_y * g.y;
		vec3 normal = normalize(vec3(-screen_g * 4.0, 1.0));
		float spec = pow(max(dot(normal, normalize(vec3(-0.35, -0.55, 0.76))), 0.0), 34.0);
		if (kind == 0) {
			// Blood dries from its thin rim inward: the edge turns dark and matte first, the thick centre stays wet.
			float set_in = clamp(dry * 1.7 - h * 0.9, 0.0, 1.0);
			vec3 behind = textureLod(screen_texture, clamp(SCREEN_UV + screen_g * px_uv * radius_px * 0.12 * (1.0 - set_in),
				vec2(0.0), vec2(1.0)), 0.8 + 1.6 * h).rgb;
			float density = 1.6 * h + 0.3 + 0.8 * set_in;
			vec3 film_albedo = mix(blood_albedo, blood_albedo * vec3(0.5, 0.75, 0.75), set_in);
			colour = behind * exp(-blood_sigma * density) + film_albedo * (1.0 - exp(-2.4 * density)) * (0.35 + 0.65 * lum) * 1.6;
			colour += vec3(0.5, 0.42, 0.4) * spec * (0.3 + 0.7 * lum) * (1.0 - set_in * 0.85);
			alpha = coverage;
		} else {
			// Mud: a wet dark body with a glint on the lumps; drying lightens it to dusty clay and opens a crackle
			// of shrinkage cracks that let the scene through.
			float grit = value_noise(q * 9.0, salt) * 0.6 + value_noise(q * 23.0, salt + 3) * 0.4;
			vec3 behind = textureLod(screen_texture, SCREEN_UV, 2.5).rgb;
			vec3 wet = mix(vec3(0.075, 0.052, 0.032), vec3(0.15, 0.108, 0.066), hash01(salt, 7)) * (0.5 + 1.1 * lum);
			vec3 clay = mix(vec3(0.36, 0.30, 0.22), vec3(0.46, 0.39, 0.29), hash01(salt, 11)) * (0.45 + 0.9 * lum);
			float set_in = smoothstep(0.0, 1.0, clamp(dry * 1.4 - h * 0.4, 0.0, 1.0));
			vec3 mud = mix(wet, wet * vec3(1.35, 1.3, 1.25), smoothstep(0.55, 0.9, grit)) * (0.75 + 0.35 * grit);
			mud = mix(mud, clay * (0.85 + 0.3 * grit), set_in);
			float crack = crackle(q * 6.5, salt) * smoothstep(0.55, 0.95, dry);
			colour = mix(behind * vec3(0.45, 0.38, 0.3), mud, smoothstep(0.15, 0.6, h))
				+ vec3(0.6, 0.58, 0.55) * spec * (1.0 - smoothstep(0.5, 0.9, grit)) * (0.25 + 0.75 * lum) * (1.0 - set_in);
			colour = mix(colour, behind * 0.7, crack * 0.85);
			alpha = coverage * mix(0.65, 1.0, smoothstep(0.1, 0.5, h)) * (1.0 - crack * 0.6);
		}
	} else if (kind == 4) {
		// A blood runner: a viscous rivulet creeping down from a splat along screen gravity, a meniscus where it
		// leaves the splat and a round bead at its tip. y = how far it has crept (0…1 of its reach); w = half reach (px).
		float reach_px = radius_px * 2.0;
		float along = (local.x + 0.5) * reach_px;
		float across = local.y * reach_px * RUNNER_ASPECT;
		float width = reach_px * RUNNER_ASPECT * 0.2;
		float tip = clamp(stamp.y, 0.0, 1.0) * reach_px;
		// A rivulet wanders as it finds its way through the glass's pinning: the meander grows along its length.
		float wander = (sin(along / reach_px * 9.0 + phase * 6.2831) * 0.7 + sin(along / reach_px * 23.0 + phase * 3.1) * 0.3)
			* width * 1.6 * (along / reach_px);
		across -= wander;
		float d = 1e3;
		if (along <= tip) {
			d = abs(across) - width * (0.75 + 0.25 * (1.0 - along / reach_px)) * (1.0 + 1.3 * exp(-along / (0.06 * reach_px)));
		}
		d = min(d, length(vec2(along - tip, across)) - width * 1.45);
		float coverage = 1.0 - smoothstep(-0.8, 0.8, d * canvas_scale);
		if (coverage <= 0.0) {
			discard;
		}
		float h = clamp(-d / max(width, 1.0), 0.0, 1.0);
		float set_in = clamp(dry * 1.7 - h * 0.9, 0.0, 1.0);
		vec3 behind = textureLod(screen_texture, SCREEN_UV, 0.8 + 1.2 * h).rgb;
		float density = 1.4 * h + 0.35 + 0.8 * set_in;
		vec3 film_albedo = mix(blood_albedo, blood_albedo * vec3(0.5, 0.75, 0.75), set_in);
		colour = behind * exp(-blood_sigma * density) + film_albedo * (1.0 - exp(-2.4 * density)) * (0.35 + 0.65 * lum) * 1.6;
		float rim = smoothstep(0.2, 0.7, h) * (1.0 - smoothstep(0.7, 1.0, h));
		colour += vec3(0.5, 0.42, 0.4) * rim * 0.25 * (0.3 + 0.7 * lum) * (1.0 - set_in);
		alpha = coverage;
	} else if (kind == 2) {
		// A grass blade lying across the lens, out of focus: a curved tapering strip with a paler midrib.
		float x = q.x;
		float bend = (hash01(salt, 3) - 0.5) * 0.9;
		float centre = bend * (x * x - 0.6) * 0.5;
		float half_width = 0.13 * (1.0 - x * x) + 0.012;
		float d = abs(q.y - centre) - half_width;
		float coverage = (1.0 - smoothstep(-0.05, 0.05, d)) * (1.0 - smoothstep(0.88, 1.0, abs(x)));
		if (coverage <= 0.0) {
			discard;
		}
		vec3 green = mix(vec3(0.10, 0.20, 0.045), vec3(0.22, 0.32, 0.08), hash01(salt, 9));
		float rib = 1.0 - smoothstep(0.0, 0.25, abs(q.y - centre) / max(half_width, 1e-3));
		colour = green * (0.35 + 0.8 * lum) * (1.0 + 0.3 * rib);
		alpha = coverage * 0.9;
	} else {
		float reach = length(q);
		float fade = 1.0 - smoothstep(0.7, 1.0, reach);
		if (fade <= 0.0) {
			discard;
		}
		float nearest_distance;
		vec2 nearest_point;
		float edge = crack_field(q, nearest_distance, nearest_point) * radius_px * canvas_scale;
		float line = (1.0 - smoothstep(0.4, 1.6, edge + value_noise(q * 40.0, salt) * 0.8)) * fade;
		// Each shard bends the image a little away from its own point; the shift grows near the impact.
		vec2 shard = normalize(q - nearest_point + vec2(1e-5));
		float strength = 1.0 - smoothstep(0.0, 0.6, reach);
		vec2 shift_local = shard * (2.0 + 6.0 * strength) + (q - nearest_point) * 2.5 * strength;
		vec2 shift = (axis_x * shift_local.x + axis_y * shift_local.y) * px_uv;
		vec2 split = (axis_x * shard.x + axis_y * shard.y) * px_uv * 1.5 * line;
		vec2 uv = clamp(SCREEN_UV + shift * fade, vec2(0.0), vec2(1.0));
		vec3 seen = vec3(textureLod(screen_texture, clamp(uv + split, vec2(0.0), vec2(1.0)), 0.0).r,
			textureLod(screen_texture, uv, 0.0).g, textureLod(screen_texture, clamp(uv - split, vec2(0.0), vec2(1.0)), 0.0).b);
		// Crack faces catch light; the crushed core at the impact is frosted.
		float core = 1.0 - smoothstep(0.0, 0.12, reach);
		vec3 frost = textureLod(screen_texture, SCREEN_UV, 3.0).rgb * 1.15 + vec3(0.08);
		colour = mix(seen, frost, core * 0.8) + vec3(0.75, 0.8, 0.85) * line * (0.35 + 0.65 * lum);
		alpha = fade;
	}
	COLOR = vec4(colour, alpha * stamp.z);
}
