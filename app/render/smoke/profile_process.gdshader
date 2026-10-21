shader_type particles;
render_mode disable_velocity;

const int MAX_BIRTH_EVENTS = 32;

uniform vec3 segment_begin;
uniform vec3 segment_end;
uniform vec3 direction_begin;
uniform vec3 direction_end;
uniform vec3 carrier_velocity;
uniform vec3 wind_velocity;
uniform float interval_s = 0.0166667;
uniform float amount = 1.0;
uniform float lod = 1.0;
uniform float opacity = 0.58;
uniform float width_m = 0.22;
uniform int shape_mode = 0;
uniform float size_growth = 0.55;
uniform float buoyancy = 0.24;
uniform float jet_speed = 0.65;
uniform bool legacy_motion = false;
uniform float presentation_time_s = 0.0;
uniform float field_seed = 0.0;
uniform float density = 1.0;
uniform float rate_fraction = 1.0;
uniform float bore_radius_m = 0.005;
uniform float jet_speed_mps = 0.65;
uniform float dispersion_m2_s = 0.1;
uniform float buoyancy_mps = 0.27;
uniform float turbulence_mps = 0.22;
uniform float drag_s = 0.4;
uniform float velocity_inheritance = 1.0;
uniform vec4 birth_event_next_states[MAX_BIRTH_EVENTS];
uniform float birth_event_transitions[MAX_BIRTH_EVENTS];
uniform vec3 birth_event_wash[MAX_BIRTH_EVENTS];
uniform int birth_event_count = 0;
uniform float birth_event_times[MAX_BIRTH_EVENTS];
uniform vec4 birth_event_states[MAX_BIRTH_EVENTS];
uniform float birth_event_levels[MAX_BIRTH_EVENTS];

float random_value(uint n) {
	n = (n ^ (n >> 16u)) * 73244475u;
	n = (n ^ (n >> 16u)) * 73244475u;
	return float(n ^ (n >> 16u)) / 4294967295.0;
}

vec3 finite_direction(vec3 a, vec3 b, float fraction) {
	// Great-circle interpolation has an explicit deterministic antipodal arc.
	// Linear blending of opposite outlet directions would normalize zero.
	a = length(a) > 0.00001 ? normalize(a) : vec3(0.0, 0.0, -1.0);
	b = length(b) > 0.00001 ? normalize(b) : a;
	float alignment = clamp(dot(a, b), -1.0, 1.0);
	if (alignment > 0.9995) { return normalize(mix(a, b, fraction)); }
	vec3 orthogonal = b - a * alignment;
	if (length(orthogonal) < 0.0001) {
		orthogonal = cross(a, abs(a.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0));
	}
	float angle = acos(alignment) * fraction;
	return normalize(a * cos(angle) + normalize(orthogonal) * sin(angle));
}

vec3 coherent_curl(vec3 p, float time_s) {
	// Analytic curl of three sinusoidal vector potentials. Each term is
	// divergence-free; division by the sum of mode magnitudes bounds speed.
	vec3 k0 = vec3(0.73, 0.31, -0.47);
	vec3 k1 = vec3(-0.28, 0.67, 0.41);
	vec3 k2 = vec3(0.37, -0.43, 0.59);
	vec3 c0 = cross(k0, vec3(0.0, 0.8, 0.6));
	vec3 c1 = cross(k1, vec3(0.7, 0.0, -0.7));
	vec3 c2 = cross(k2, vec3(0.6, 0.8, 0.0));
	return (c0 * cos(dot(k0, p) + time_s * 0.41 + field_seed)
		+ c1 * cos(dot(k1, p) - time_s * 0.29 + field_seed * 1.37)
		+ c2 * cos(dot(k2, p) + time_s * 0.19 + field_seed * 0.73))
		/ (length(c0) + length(c1) + length(c2));
}

vec3 srgb_to_linear(vec3 color) {
	return mix(color / 12.92, pow((color + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), color));
}
vec3 linear_to_srgb(vec3 color) {
	return mix(color * 12.92, 1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), color));
}

void start() {
	float born_at_s = clamp(interval_s - DELTA, 0.0, interval_s);
	vec4 birth_state = vec4(0.0);
	float birth_level = 0.0;
	vec3 wash = vec3(0.0);
	for (int i = 0; i < MAX_BIRTH_EVENTS; i++) {
		if (i >= birth_event_count) { break; }
		if (birth_event_times[i] <= born_at_s + 0.0000005) {
			birth_state = birth_event_states[i];
			float transition = birth_event_transitions[i];
			if (transition > 0.0) {
				float weight = clamp((born_at_s - birth_event_times[i]) / transition, 0.0, 1.0);
				vec4 next = birth_event_next_states[i];
				birth_state.rgb = linear_to_srgb(mix(srgb_to_linear(birth_state.rgb), srgb_to_linear(next.rgb), weight));
				birth_state.a = mix(birth_state.a, next.a, weight);
			}
			birth_level = birth_event_levels[i];
			wash = birth_event_wash[i];
		}
	}
	float seed = random_value(NUMBER + RANDOM_SEED);
	if (birth_level <= 0.0 || birth_state.a <= 0.0 || density <= 0.0 ||
		random_value(NUMBER + RANDOM_SEED + 103u) > birth_level * amount * lod * rate_fraction) {
		ACTIVE = false;
	}
	float fraction = clamp(1.0 - DELTA / max(interval_s, 0.000001), 0.0, 1.0);
	vec3 direction = finite_direction(direction_begin, direction_end, fraction);
	vec3 position = mix(segment_begin, segment_end, fraction);
	vec3 right = normalize(cross(direction, abs(direction.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 up = normalize(cross(right, direction));
	float disk_angle = random_value(NUMBER + RANDOM_SEED + 17u) * TAU;
	float disk_radius = sqrt(random_value(NUMBER + RANDOM_SEED + 29u)) * bore_radius_m;
	if (!legacy_motion) { position += (right * cos(disk_angle) + up * sin(disk_angle)) * disk_radius; }
	float spread = (seed * 2.0 - 1.0) * width_m * 0.35;
	if (legacy_motion && shape_mode == 1) {
		position += (right * (seed - 0.5) + up * (random_value(NUMBER + RANDOM_SEED + 17u) - 0.5)) * width_m;
	} else if (shape_mode == 2) {
		direction = normalize(direction + right * spread + up * (random_value(NUMBER + RANDOM_SEED + 29u) - 0.5) * width_m * 0.18);
	}
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = position;
	VELOCITY = carrier_velocity * velocity_inheritance + direction * (legacy_motion ? jet_speed : jet_speed_mps) + wash;
	CUSTOM = vec4(seed * TAU, 0.0, seed, opacity * birth_level * birth_state.a);
	COLOR = vec4(birth_state.rgb, 0.0);
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	float age = CUSTOM.y * LIFETIME;
	// No shader TIME: this clock is supplied only by accepted presentation ticks.
	// A midpoint sample is consistent for newborn fractional and residual steps.
	vec3 detail = legacy_motion
		? vec3(sin(age * 2.3 + CUSTOM.x), sin(age * 1.7 + CUSTOM.x * 1.3), cos(age * 2.1 + CUSTOM.x))
		: coherent_curl(TRANSFORM[3].xyz, presentation_time_s - DELTA * 0.5);
	float rise = legacy_motion ? buoyancy : buoyancy_mps * exp(-age / max(LIFETIME * 0.6, 0.1));
	float turbulence = legacy_motion ? 0.22 : turbulence_mps;
	vec3 target = wind_velocity + vec3(0.0, rise, 0.0) + detail * turbulence * (legacy_motion ? 1.0 : smoothstep(0.0, 0.3, age));
	float tau = legacy_motion ? mix(0.12, 0.65, smoothstep(0.0, 0.7, age)) : drag_s;
	float decay = exp(-DELTA / tau);
	TRANSFORM[3].xyz += target * DELTA + (VELOCITY - target) * tau * (1.0 - decay);
	VELOCITY = target + (VELOCITY - target) * decay;
	float initial_size = max(width_m * 0.025, 0.004);
	float size = legacy_motion ? initial_size + size_growth * width_m * sqrt(max(age, 0.0))
		: sqrt(width_m * width_m * 0.04 + 2.0 * dispersion_m2_s * max(age, 0.0));
	if (shape_mode == 1) { size *= 1.35; }
	TRANSFORM[0].xyz = vec3(size, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, size, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, size);
	float fade = 1.0 - smoothstep(0.12, 1.0, CUSTOM.y);
	float onset = smoothstep(0.0, 0.035, age);
	if (legacy_motion) {
		COLOR.a = CUSTOM.w * onset * fade * fade / (1.0 + age * 0.65);
	} else {
		float dilution = width_m * width_m * 0.04 / max(size * size, 0.000001);
		float optical_depth = density * CUSTOM.w * 4.0 * dilution * onset * fade * fade;
		COLOR.a = 1.0 - exp(-optical_depth);
	}
	if (CUSTOM.y >= 1.0) { ACTIVE = false; }
}
