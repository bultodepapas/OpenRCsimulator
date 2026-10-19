shader_type particles;
render_mode disable_velocity;

// Presentation only. DELTA at birth is Godot's fractional age within this request.
uniform vec3 segment_begin;
uniform vec3 segment_end;
uniform vec3 direction_begin;
uniform vec3 direction_end;
uniform vec3 carrier_velocity;
uniform vec3 wind_velocity;
uniform float interval_s = 0.0166667;
uniform float jet_speed = 2.0;
uniform vec3 wash_velocity;
uniform float density = 1.0;
uniform float opacity = 0.1;
uniform float size_start = 0.04;
uniform float size_growth = 0.6;
uniform float buoyancy = 0.25;
uniform vec3 tint = vec3(0.84, 0.88, 0.94);

float random_value(uint n) {
	n = (n ^ (n >> 16u)) * 73244475u;
	n = (n ^ (n >> 16u)) * 73244475u;
	return float(n ^ (n >> 16u)) / 4294967295.0;
}

void start() {
	float r = random_value(NUMBER + RANDOM_SEED);
	if (random_value(NUMBER + RANDOM_SEED + 103u) > density) {
		ACTIVE = false;
	}
	float fraction = clamp(1.0 - DELTA / max(interval_s, 0.000001), 0.0, 1.0);
	vec3 direction = normalize(mix(direction_begin, direction_end, fraction));
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = mix(segment_begin, segment_end, fraction);
	VELOCITY = carrier_velocity + direction * jet_speed + wash_velocity;
	CUSTOM = vec4(r * TAU, 0.0, r, opacity);
	COLOR = vec4(tint * mix(0.94, 1.0, r), 0.0);
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	float age = CUSTOM.y * LIFETIME;
	// Rapid entrainment removes aircraft/jet momentum; aged puffs share the live M5 wind.
	// Seeded eddies are a small visual diffusion term, not a second weather field.
	vec3 eddy = vec3(sin(age * 2.3 + CUSTOM.x), sin(age * 1.7 + CUSTOM.x * 1.3),
		cos(age * 2.1 + CUSTOM.x)) * 0.22;
	vec3 target = wind_velocity + vec3(0.0, buoyancy, 0.0) + eddy;
	float tau = mix(0.12, 0.65, smoothstep(0.0, 0.7, age));
	float decay = exp(-DELTA / tau);
	TRANSFORM[3].xyz += target * DELTA + (VELOCITY - target) * tau * (1.0 - decay);
	VELOCITY = target + (VELOCITY - target) * decay;
	float size = (size_start + size_growth * sqrt(max(age, 0.0))) * mix(0.82, 1.18, CUSTOM.z);
	TRANSFORM[0].xyz = vec3(size, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, size, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, size);
	float fade = 1.0 - smoothstep(0.12, 1.0, CUSTOM.y);
	// Growing area dilutes the puff. Smooth onset avoids bright dots at the mouth.
	COLOR.a = CUSTOM.w * smoothstep(0.0, 0.035, age) * fade * fade / (1.0 + age * 0.65);
	if (CUSTOM.y >= 1.0) { ACTIVE = false; }
}
