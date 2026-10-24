// SC-BIRD-04/05/08 (docs/plans/birds-sky-life.md): one MultiMesh of birds. Ours, MIT. No TIME: position, attitude,
// wingbeat and arrivals/departures are functions of sim_clock (track periods and frequencies divide 1024 s), so the
// same simulation time draws the same birds. bird_tracks.gd compiles the arc-line circuits into seg_a/seg_b and
// mirrors track_pos() in float64; birds.gd mirrors the departure share. Per instance (INSTANCE_CUSTOM): x time offset
// (s), y track + 8 * species, z state (1500 flying, 2000 away, 0..1023.5 leaving since that clock, -1024..-0.5 arriving
// since -z - 0.5; all exact in the half floats Compatibility stores custom data in), w hash in [0, 1) (flap phase). The species' shape is CUSTOM0..3 (bird_planform.gd: xyz and the rig
// weights packed as tail + 2 * hand). Mesh frame: nose +Z, wings +-X, up +Y.
shader_type spatial;
render_mode cull_disabled;

global uniform float sim_clock;

const int MAX_SEGMENTS = 48;
const float GRAVITY = 9.81;
const float HEADING_STEP_S = 0.05;
const float BANK_STEP_S = 0.8; // the bank follows the turn with ~1 s of roll-in and roll-out
const float PITCH_SHARE = 0.3; // birds climb in thermals nearly level
const float STEADY = 1500.0;
const float HIDDEN = 2000.0;

uniform vec4 seg_a[48];       // x, y (m), heading (rad), start time (s)
uniform vec4 seg_b[48];       // curvature (1/m), speed (m/s), start height (m), climb rate (m/s)
uniform vec4 track_info[8];   // first segment, segment count, period (s)
uniform vec4 gait_a[4];       // flap frequency (Hz), amplitude (rad), burst period (s), burst duty
uniform vec4 gait_b[4];       // dihedral (rad), hand lag (rad), tip curl (rad), upstroke fold
uniform vec4 gait_c[4];       // tail twist per bank (1), tail wobble (rad), departure time (s)
uniform vec4 rig[4];          // shoulder x, wrist x, tail root z, half span (m)
uniform vec4 color_top[4];
uniform vec4 color_under[4];
uniform vec4 color_tip[4];
uniform vec4 depart[4];       // departure displacement (m, world axes)

varying vec3 v_up;
varying vec3 v_top;
varying vec3 v_under;
varying vec3 v_tip;
varying float v_shade;

vec3 track_pos(int track, float t) {
	vec4 info = track_info[track];
	int first = int(info.x + 0.5);
	int count = int(info.y + 0.5);
	float tt = mod(t, info.z);
	int index = first;
	for (int i = 1; i < MAX_SEGMENTS; i++) {
		if (i >= count || seg_a[first + i].w > tt) {
			break;
		}
		index = first + i;
	}
	vec4 a = seg_a[index];
	vec4 b = seg_b[index];
	float d = tt - a.w;
	float s = b.y * d;
	vec2 p;
	if (abs(b.x) < 1e-7) {
		p = a.xy + s * vec2(cos(a.z), sin(a.z));
	} else {
		float h = a.z + b.x * s;
		p = a.xy + vec2(sin(h) - sin(a.z), cos(a.z) - cos(h)) / b.x;
	}
	return vec3(p, b.z + b.w * d);
}

// Share of the departure displacement (0 on the circuit, 1 away); > 1 means not drawn (birds.gd departure_share()).
float departure_share(float state, float duration) {
	if (state > HIDDEN - 0.5) {
		return 2.0;
	}
	if (state > STEADY - 0.5) {
		return 0.0;
	}
	float start = state >= 0.0 ? state : -state - 0.5;
	float p = clamp(mod(sim_clock - start, 1024.0) / duration, 0.0, 1.0);
	float eased = smoothstep(0.0, 1.0, p);
	return state >= 0.0 ? (p >= 1.0 ? 2.0 : eased) : 1.0 - eased;
}

vec2 rotate2(vec2 v, float a) {
	return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
}

void vertex() {
	float packed = INSTANCE_CUSTOM.y + 0.5;
	int species = int(packed / 8.0);
	int track = int(packed) - species * 8;
	float hash = INSTANCE_CUSTOM.w;
	vec4 shape = species == 0 ? CUSTOM0 : (species == 1 ? CUSTOM1 : (species == 2 ? CUSTOM2 : CUSTOM3));
	float hand = shape.w > 1.5 ? 1.0 : 0.0;
	float tail = shape.w - 2.0 * hand;
	v_shade = UV.y;
	v_up = vec3(0.0, 1.0, 0.0);
	v_top = color_top[species].rgb;
	v_under = color_under[species].rgb;
	v_tip = color_tip[species].rgb;
	vec4 gc = gait_c[species];
	float away = departure_share(INSTANCE_CUSTOM.z, gc.z);
	if (away > 1.5) {
		VERTEX = vec3(0.0); // gone: birds.gd stops drawing it at the next settle
	} else {
		float t = sim_clock + INSTANCE_CUSTOM.x;
		vec3 p = track_pos(track, t);
		vec3 v = (track_pos(track, t + HEADING_STEP_S) - track_pos(track, t - HEADING_STEP_S)) / (2.0 * HEADING_STEP_S);
		vec2 acc = (track_pos(track, t + BANK_STEP_S).xy - 2.0 * p.xy + track_pos(track, t - BANK_STEP_S).xy)
			/ (BANK_STEP_S * BANK_STEP_S);
		float vh = max(length(v.xy), 1e-4);
		vec2 dir = v.xy / vh;
		float bank = atan(dir.x * acc.y - dir.y * acc.x, GRAVITY); // > 0 turning left
		float pitch = atan(v.z, vh) * PITCH_SHARE;
		// Track (x east, y north, z up) to mesh-instance axes (x east, y up, z south).
		vec3 fwd = vec3(dir.x * cos(pitch), sin(pitch), -dir.y * cos(pitch));
		vec3 left = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
		vec3 up = cross(fwd, left);
		vec3 bank_left = cos(bank) * left - sin(bank) * up;
		vec3 bank_up = cos(bank) * up + sin(bank) * left;

		vec4 ga = gait_a[species];
		vec4 gb = gait_b[species];
		vec4 r = rig[species];
		float cycle = sim_clock * ga.x + hash; // flap frequencies are multiples of 1/1024 Hz
		float window = fract(t / ga.z + hash * 7.0);
		float edge = max(min(0.08, ga.w * 0.5), 1e-3);
		float envelope = ga.w >= 0.999 ? 1.0 : smoothstep(0.0, edge, window) * (1.0 - smoothstep(ga.w - edge, ga.w, window));
		float sway = 0.03 * sin(TAU * (t * 0.125 + hash));
		float arm = gb.x + envelope * ga.y * sin(TAU * cycle) + sway;
		float hand_angle = gb.z + envelope * ga.y * 0.6 * sin(TAU * cycle - gb.y);
		float fold = gb.w * envelope * max(0.0, -cos(TAU * cycle));

		vec3 q = shape.xyz;
		float ax = abs(q.x);
		if (ax > r.x + 1e-5 && tail == 0.0) { // wings only: a spread tail can be wider than the shoulders
			float side = sign(q.x);
			vec2 w = vec2(ax - r.x, q.y);
			if (hand > 0.5) {
				float wrist = r.y - r.x;
				w = vec2(wrist, 0.0) + rotate2(vec2((w.x - wrist) * (1.0 - fold), w.y), hand_angle);
			}
			w = rotate2(w, arm);
			q.x = side * (r.x + w.x);
			q.y = w.y;
		}
		if (tail > 0.0) {
			// Steering tail: twisted against the body's bank (toward level) in proportion to it, plus a small wobble.
			float twist = clamp(gc.x * bank + gc.y * sin(TAU * (t * 0.25 + hash)), -0.7, 0.7) * tail;
			q.xy = rotate2(q.xy, twist);
		}
		// The departure is a world direction; rotated or mirrored birds take it back into their own axes.
		vec3 shift = inverse(mat3(MODEL_MATRIX)) * depart[species].xyz;
		VERTEX = bank_left * q.x + bank_up * q.y + fwd * q.z + vec3(p.x, p.z, -p.y) + shift * away;
		NORMAL = bank_up;
		v_up = bank_up;
	}
	v_up = (MODELVIEW_MATRIX * vec4(v_up, 0.0)).xyz;
}

const float UNDERSIDE_TRANSMISSION = 0.6; // thin feathers pass sunlight; sky and ground light the belly [est]

void fragment() {
	vec3 up = normalize(v_up);
	bool under = dot(up, VIEW) < 0.0;
	// Both sides take the sun on the wing's upper surface: seen from below, a white stork reads white with black
	// flight feathers, as it does in the field, rather than as an unlit shadow.
	ALBEDO = mix(under ? v_under * UNDERSIDE_TRANSMISSION : v_top, v_tip, smoothstep(0.5, 1.0, v_shade));
	NORMAL = up;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
