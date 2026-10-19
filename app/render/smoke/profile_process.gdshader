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
uniform int birth_event_count = 0;
uniform float birth_event_times[MAX_BIRTH_EVENTS];
uniform vec4 birth_event_states[MAX_BIRTH_EVENTS];
uniform float birth_event_levels[MAX_BIRTH_EVENTS];

float random_value(uint n) {
	n = (n ^ (n >> 16u)) * 73244475u;
	n = (n ^ (n >> 16u)) * 73244475u;
	return float(n ^ (n >> 16u)) / 4294967295.0;
}

void start() {
	float born_at_s = clamp(interval_s - DELTA, 0.0, interval_s);
	vec4 birth_state = vec4(0.0);
	for (int i = 0; i < MAX_BIRTH_EVENTS; i++) {
		if (i >= birth_event_count) { break; }
		if (birth_event_times[i] <= born_at_s + 0.0000005) {
			birth_state = birth_event_states[i];
		}
	}
	float birth_level = 0.0;
	for (int i = 0; i < MAX_BIRTH_EVENTS; i++) {
		if (i >= birth_event_count) { break; }
		if (birth_event_times[i] <= born_at_s + 0.0000005) {
			birth_level = birth_event_levels[i];
		}
	}
	if (birth_level <= 0.0) {
		ACTIVE = false;
	}
	float seed = random_value(NUMBER + RANDOM_SEED);
	if (random_value(NUMBER + RANDOM_SEED + 103u) > birth_level * amount * lod) {
		ACTIVE = false;
	}
	float fraction = clamp(1.0 - DELTA / max(interval_s, 0.000001), 0.0, 1.0);
	vec3 direction = normalize(mix(direction_begin, direction_end, fraction));
	vec3 position = mix(segment_begin, segment_end, fraction);
	vec3 right = normalize(cross(direction, abs(direction.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 up = normalize(cross(right, direction));
	float spread = (seed * 2.0 - 1.0) * width_m * 0.35;
	if (shape_mode == 1) {
		position += (right * (seed - 0.5) + up * (random_value(NUMBER + RANDOM_SEED + 17u) - 0.5)) * width_m;
	} else if (shape_mode == 2) {
		direction = normalize(direction + right * spread + up * (random_value(NUMBER + RANDOM_SEED + 29u) - 0.5) * width_m * 0.18);
	}
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = position;
	VELOCITY = carrier_velocity + direction * jet_speed;
	CUSTOM = vec4(seed * TAU, 0.0, seed, opacity * birth_level * birth_state.a);
	COLOR = vec4(birth_state.rgb, 0.0);
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	float age = CUSTOM.y * LIFETIME;
	vec3 eddy = vec3(sin(age * 2.3 + CUSTOM.x), sin(age * 1.7 + CUSTOM.x * 1.3),
		cos(age * 2.1 + CUSTOM.x)) * 0.22;
	vec3 target = wind_velocity + vec3(0.0, buoyancy, 0.0) + eddy;
	float tau = mix(0.12, 0.65, smoothstep(0.0, 0.7, age));
	float decay = exp(-DELTA / tau);
	TRANSFORM[3].xyz += target * DELTA + (VELOCITY - target) * tau * (1.0 - decay);
	VELOCITY = target + (VELOCITY - target) * decay;
	float size = max(width_m * 0.025, 0.004) + size_growth * width_m * sqrt(max(age, 0.0));
	if (shape_mode == 1) { size *= 1.35; }
	TRANSFORM[0].xyz = vec3(size, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, size, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, size);
	float fade = 1.0 - smoothstep(0.12, 1.0, CUSTOM.y);
	COLOR.a = CUSTOM.w * smoothstep(0.0, 0.035, age) * fade * fade / (1.0 + age * 0.65);
	if (CUSTOM.y >= 1.0) { ACTIVE = false; }
}
