shader_type canvas_item;
render_mode unshaded;

// HUD-13-R14. Local tank optics; no screen texture, wall clock or physics feedback.
global uniform float sim_clock;
uniform vec2 rect_size = vec2(200.0, 100.0);
uniform vec4 liquid_color : source_color = vec4(0.945, 0.792, 0.49, 1.0);
uniform float fill = -1.0;
uniform float sample_clock = 0.0;
uniform float tilt = 0.0;
uniform float tilt_velocity = 0.0;
uniform float target_tilt = 0.0;
uniform float wave_energy = 0.0;
uniform float foam_energy = 0.0;
uniform float force_g = 1.0;
uniform float wave_phase = 0.0;
uniform float bubble_phase = 0.0;

// Uniform-only work runs at the quad's vertices, not across every tank pixel.
// Four small flat varyings keep this within Compatibility's varying budget.
varying flat vec4 surface_data; // down.xy, surface offset, chord span
varying flat vec4 motion_data; // wave energy, aeration, clearance, scale
varying flat vec4 phase_data; // three modal amplitudes, bubble flow
varying flat vec4 chord_data; // chord endpoints, optical depth extent, foam phase

// Value noise adapted from PWira's MIT-licensed 2D Liquid Wave.
// See FUEL_LIQUID_LICENSE.txt. All animation uses the paused simulation clock.
float liquid_random(vec2 st) {
	return fract(sin(dot(st, vec2(12.9898, 78.233))) * 43758.5453123);
}

float liquid_noise(vec2 st) {
	vec2 i = floor(st);
	vec2 f = fract(st);
	float a = liquid_random(i);
	float b = liquid_random(i + vec2(1.0, 0.0));
	float c = liquid_random(i + vec2(0.0, 1.0));
	float d = liquid_random(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Exact area quantile of a rectangle projected along a unit normal. Unlike a
// slope/height graph this works through both knife edges and inverted flight.
float surface_offset(vec2 down, vec2 extent, float amount) {
	vec2 spans = abs(down) * extent;
	float a = max(max(spans.x, spans.y), 0.0001);
	float b = min(spans.x, spans.y);
	float tail = min(amount, 1.0 - amount);
	float distance = tail < b / (2.0 * a)
		? a + b - sqrt(max(0.0, 8.0 * a * b * tail))
		: a * (1.0 - 2.0 * tail);
	return amount < 0.5 ? distance : -distance;
}

// Endpoints of the free-surface chord, in force-relative tangent coordinates.
vec2 surface_chord(vec2 down, vec2 tangent, vec2 extent, float surface) {
	vec2 origin = down * surface;
	vec2 limits = vec2(-100000.0, 100000.0);
	if (abs(tangent.x) > 0.0001) {
		vec2 hit = (vec2(-extent.x, extent.x) - origin.x) / tangent.x;
		limits = vec2(max(limits.x, min(hit.x, hit.y)), min(limits.y, max(hit.x, hit.y)));
	}
	if (abs(tangent.y) > 0.0001) {
		vec2 hit = (vec2(-extent.y, extent.y) - origin.y) / tangent.y;
		limits = vec2(max(limits.x, min(hit.x, hit.y)), min(limits.y, max(hit.x, hit.y)));
	}
	return limits;
}

void vertex() {
	vec2 half_size = rect_size * 0.5;
	// Match the CPU spring; clamp stale samples and handle the shared 1024 s clock wrap.
	// The render clock may trail the accepted tick by one interpolation step.
	float dt = clamp(mod(sim_clock - sample_clock + 512.0, 1024.0) - 512.0, 0.0, 2.0);
	float rate = sqrt(clamp(force_g, 0.04, 6.0));
	float damping = 4.0 * rate;
	float frequency = 9.0 * rate;
	float offset = tilt - target_tilt;
	float angle = target_tilt + exp(-damping * dt) * (offset * cos(frequency * dt)
		+ (tilt_velocity + damping * offset) / frequency * sin(frequency * dt));
	vec2 down = vec2(sin(angle), cos(angle));
	vec2 tangent = vec2(down.y, -down.x);
	float energy = wave_energy * exp(-1.8 * dt);
	// Perceptual gain keeps small, short-lived air pockets readable at HUD size.
	float aeration = sqrt(clamp(foam_energy * exp(-0.65 * dt), 0.0, 1.0));
	float clearance = clamp(min(fill, 1.0 - fill) / 0.15, 0.0, 1.0);
	float phase = wave_phase + 5.0 * rate * dt;
	float flow = bubble_phase + rate * dt;
	float surface = surface_offset(down, half_size, clamp(fill, 0.0, 1.0));
	vec2 chord = surface_chord(down, tangent, half_size, surface);
	float span = max(chord.y - chord.x, 1.0);
	float scale = clamp(min(rect_size.x, rect_size.y) / 100.0, 0.35, 2.5);
	surface_data = vec4(down, surface, span);
	motion_data = vec4(energy, aeration, clearance, scale);
	float wave_gain = clearance * (energy + sqrt(energy)) * 0.5 * scale;
	phase_data = vec4(wave_gain * vec3(7.0 * sin(phase), 2.7 * sin(2.0 * phase), 1.1 * sin(3.0 * phase)), flow);
	chord_data = vec4(chord, max(dot(abs(down), rect_size), 1.0), sin(phase) * 0.5);
}

void fragment() {
	vec2 half_size = rect_size * 0.5;
	vec2 point = (UV - 0.5) * rect_size;
	vec2 q = abs(point) - half_size + 8.0;
	float sdf = min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - 8.0;
	float aa = max(fwidth(sdf), 0.6);
	float mask = 1.0 - smoothstep(-aa, aa, sdf);
	vec2 down = surface_data.xy;
	vec2 tangent = vec2(down.y, -down.x);
	float surface = surface_data.z;
	vec2 chord = chord_data.xy;
	float energy = motion_data.x;
	float aeration = motion_data.y;
	float clearance = motion_data.z;
	float scale = motion_data.w;
	float flow = phase_data.w;
	float along = clamp((dot(point, tangent) - chord_data.x) / surface_data.w, 0.0, 1.0);
	// Three zero-mean standing modes across the actual surface, including knife edge.
	float wave = 0.0;
	if (energy > 0.0) {
		wave = dot(vec3(cos(along * PI), cos(along * TAU), cos(along * 3.0 * PI)), phase_data.xyz);
	}
	float depth = dot(point, down) - surface - wave;
	float edge = max(fwidth(depth), 0.6);
	float wet = smoothstep(-edge, edge, depth);
	if (fill <= 0.0) { wet = 0.0; }
	if (fill >= 1.0) { wet = 1.0; }
	float optical_depth = fill >= 1.0 ? 1.0 : clamp(depth / chord_data.z, 0.0, 1.0);
	// Actual alpha blending transmits the inner tank ribs. Deeper fluid absorbs
	// more light; a fine meniscus and doubled reflection suggest clear tinted liquid.
	vec3 color = liquid_color.rgb * mix(0.95, 0.58, optical_depth);
	float opacity = wet * mix(0.28, 0.57, sqrt(optical_depth));
	float crest = fill > 0.0 && fill < 1.0 ? exp(-abs(depth) / 0.4) : 0.0;
	color = mix(color, mix(liquid_color.rgb, vec3(1.0), 0.65), crest * 0.75);
	opacity = max(opacity, crest * 0.85);
	// Derivatives above stay outside divergent branches. Preserve the AA wet fringe.
	if (fill > 0.0 && fill < 1.0 && wet > 0.0 && mask > 0.0) {
		// A refracted-looking return below the moving surface, without a screen copy.
		float return_band = exp(-abs(depth - (3.5 + energy * 2.0) * scale) / (1.4 * scale));
		color += liquid_color.rgb * return_band * energy * 0.16 * wet;
		if (aeration > 0.001) {
			// Broken patches of entrained air, on the wet side of the meniscus only.
			float froth = 0.0;
			if (depth < scale * aeration * 5.2 + 0.5) {
				float froth_noise = liquid_noise(vec2(dot(point, tangent) / (9.0 * scale), chord_data.w));
				float foam_depth = scale * aeration * (1.2 + 4.0 * froth_noise);
				froth = wet * (1.0 - smoothstep(foam_depth * 0.25, foam_depth + 0.5, depth));
				froth *= aeration * smoothstep(0.18, 0.72, froth_noise);
			}
			color = mix(color, mix(liquid_color.rgb, vec3(1.0), 0.78), froth * 0.8);
			opacity = min(0.82, opacity + froth * 0.32);
			// Fixed-budget bubbles rise opposite apparent gravity and vanish at the
			// free surface. Radius is in pixels so they remain round at any aspect ratio.
			float column = max(dot(abs(down), half_size) - surface, 1.0);
			float bubbles = 0.0;
			float glints = 0.0;
			float cores = 0.0;
			if (depth > 0.5) {
				for (int i = 0; i < 16; i++) {
					float seed = liquid_random(vec2(float(i), 4.7));
					float life = fract(flow * (12.0 + float(i)) / 64.0 + seed);
					float across = mix(chord.x, chord.y, fract(seed * 7.31));
					across += sin(life * TAU + seed * TAU) * (1.0 + energy * 3.0) * scale;
					vec2 center = tangent * across + down * (surface + (1.0 - life) * column);
					vec2 delta = point - center;
					float radius = (1.2 + 2.6 * seed) * scale;
					// Conservative support of rim, core and displaced glint. Most
					// fragments miss a bubble and need neither distance calculation.
					if (any(greaterThan(abs(delta), vec2(radius + 0.9 * scale)))) { continue; }
					float distance = length(delta);
					float fade = smoothstep(0.0, 0.15, life) * (1.0 - smoothstep(0.9, 1.0, life));
					bubbles = max(bubbles, (1.0 - smoothstep(0.25 * scale, 0.9 * scale, abs(distance - radius))) * fade);
					cores = max(cores, (1.0 - smoothstep(radius * 0.45, radius, distance)) * fade);
					glints = max(glints, (1.0 - smoothstep(0.15 * scale, 0.8 * scale,
						length(delta + vec2(radius * 0.35)))) * fade);
				}
			}
			float submerged = smoothstep(0.5, 2.0 * scale, depth) * wet * aeration * clearance;
			color *= 1.0 - cores * submerged * 0.16;
			color = mix(color, mix(liquid_color.rgb, vec3(1.0), 0.7), bubbles * submerged * 0.85);
			color += vec3(glints * submerged * 0.45);
			opacity = min(0.82, opacity + (bubbles * 0.30 + glints * 0.18) * submerged);
		}
	}
	float reflection = 1.0 - smoothstep(0.0, 0.045, abs(UV.x + UV.y * 0.14 - 0.18));
	float return_reflection = 1.0 - smoothstep(0.0, 0.018, abs(UV.x + UV.y * 0.14 - 0.28));
	float rim = 1.0 - smoothstep(0.0, 1.7, -sdf);
	float glass = reflection * 0.08 + return_reflection * 0.025 + rim * 0.25;
	color = mix(color, vec3(0.65, 0.8, 0.86), glass);
	opacity = max(opacity, glass);
	if (fill < 0.0) {
		float hatch = step(0.82, fract((UV.x * rect_size.x + UV.y * rect_size.y) / 14.0));
		color = vec3(0.18);
		opacity = hatch * 0.22 + rim * 0.3;
	}
	COLOR = vec4(color, mask * opacity);
}
