## AUD-03. Presentation estimates, never aerodynamic forces or calibrated acoustics.
extends RefCounted


static func doppler(source: Vector3, listener: Vector3, source_velocity: Vector3,
		listener_velocity: Vector3, sound_speed: float = 343.0) -> float:
	var ray: Vector3 = (source - listener).normalized()
	var c: float = clampf(sound_speed, 300.0, 380.0)
	return clampf((c + listener_velocity.dot(ray)) / maxf(c + source_velocity.dot(ray), c * 0.5), 0.65, 1.5)


static func targets(snapshot: Dictionary) -> Dictionary:
	var rpm: float = maxf(float(snapshot.get("rpm", 0.0)), 0.0)
	var ratio: float = clampf(rpm / maxf(float(snapshot.get("max_rpm", 12000.0)), 1.0), 0.0, 1.4)
	var load_amount: float = clampf(float(snapshot.get("load", 0.0)), 0.0, 1.0)
	var throttle: float = clampf(float(snapshot.get("throttle", load_amount)), 0.0, 1.0)
	var speed: float = clampf(float(snapshot.get("airspeed", 0.0)), 0.0, 150.0)
	var wind: float = clampf(float(snapshot.get("wind_speed", 0.0)), 0.0, 35.0)
	var running: bool = bool(snapshot.get("running", true)) and rpm > 30.0
	var kind: String = str(snapshot.get("kind", "glow_prop"))
	var spin: float = smoothstep(30.0, 1200.0, rpm)
	var result: Dictionary = {
		motor_gain = (0.16 + 0.38 * sqrt(ratio)) * (0.3 + 0.35 * load_amount + 0.35 * throttle) if running else 0.0,
		prop_gain = spin * (0.07 + 0.32 * ratio) * (0.55 + 0.45 * load_amount),
		motor_pitch = clampf(rpm / 6000.0, 0.12, 3.5),
		prop_pitch = clampf(rpm / 6000.0 * float(snapshot.get("blades", 2)) / 2.0, 0.12, 3.5),
		air_gain = 0.18 * pow(clampf(speed / 55.0, 0.0, 1.5), 2.0),
		wind_low = 0.012 + 0.20 * pow(wind / 18.0, 1.1),
		wind_high = 0.10 * pow(wind / 20.0, 1.7),
		foliage = 0.008 + 0.23 * smoothstep(0.0, 14.0, wind),
		bird_activity = smoothstep(-6.0, 3.0, float(snapshot.get("sun_elevation", 45.0))) * (1.0 - smoothstep(6.0, 18.0, wind)),
	}
	if kind == "electric_prop":
		result.motor_gain *= 0.4
	elif kind == "turbine":
		var turbine: Dictionary = turbine_targets(snapshot, running)
		result.merge(turbine, true)
	return result


## AUD-10: a turbojet as two layers. Voice 0 is the intake/compressor whine on the true shaft order; voice 1 (the
## propeller slot, unused by a turbine) is the jet mixing roar. Laws follow published trends; levels are authored
## against the AUD-06 bench (D4), not calibrated acoustics.
const TURBINE_WHINE_REFERENCE_RPM: float = 82320.0 # turbine_whine.wav plays its 1,372 Hz shaft order at pitch 1
const TURBINE_ROAR_PITCH_AT_MAX_JET: float = 1.40 # roar peak ~1.5 kHz x 1.40 ~ St 0.2 x V_j,max / D_nozzle (~2 kHz)
const TURBINE_WHINE_GAIN: float = 0.60
const TURBINE_ROAR_GAIN: float = 1.20
## Exhaust-axis angle (deg, 0 = listener in the plume behind) -> dB. Mixing noise peaks 15-45 deg off the jet
## axis with a refraction dip on it; the intake whine radiates forward and is shielded aft.
const ROAR_DIRECTIVITY: Array[float] = [0.0, -4.0, 30.0, 0.0, 60.0, -3.0, 90.0, -7.0, 120.0, -10.0, 180.0, -12.0]
const WHINE_DIRECTIVITY: Array[float] = [0.0, -8.0, 30.0, -6.0, 90.0, -2.0, 150.0, 0.0, 180.0, 0.0]


static func turbine_targets(snapshot: Dictionary, running: bool) -> Dictionary:
	var rpm: float = maxf(float(snapshot.get("rpm", 0.0)), 0.0)
	var n_ratio: float = clampf(rpm / maxf(float(snapshot.get("max_rpm", 1.0)), 1.0), 0.0, 1.2)
	var jet_ratio: float = clampf(float(snapshot.get("jet_velocity", 0.0)) / maxf(float(snapshot.get("jet_velocity_max", 1.0)), 1.0), 0.0, 1.5)
	var theta: float = exhaust_angle_deg(snapshot)
	# Lighthill: mixing-noise power ~ V_j^8, so amplitude ~ V_j^4. A small core-noise term keeps idle combustion audible.
	var roar: float = pow(jet_ratio, 4.0) + 0.05 * n_ratio
	# Authored so the whine falls 5 dB from full to idle (D4: idle about 10 dB under full power).
	var whine: float = pow(n_ratio, 0.46)
	return {
		motor_pitch = rpm / TURBINE_WHINE_REFERENCE_RPM,
		motor_gain = TURBINE_WHINE_GAIN * whine * db_to_linear(table_db(WHINE_DIRECTIVITY, theta)) if running else 0.0,
		prop_pitch = TURBINE_ROAR_PITCH_AT_MAX_JET * jet_ratio, # Strouhal: the spectral peak scales with V_j
		prop_gain = TURBINE_ROAR_GAIN * roar * db_to_linear(table_db(ROAR_DIRECTIVITY, theta)) if running else 0.0,
		exhaust_angle_deg = theta,
	}


## Angle between the jet (exhaust flow direction) and the source-to-listener ray; 90 when either is undefined.
static func exhaust_angle_deg(snapshot: Dictionary) -> float:
	var exhaust: Vector3 = snapshot.get("exhaust_direction", Vector3.ZERO)
	var ray: Vector3 = Vector3(snapshot.get("listener", Vector3.ZERO)) - Vector3(snapshot.get("source", Vector3.ZERO))
	if exhaust.length_squared() < 1e-6 or ray.length_squared() < 1e-6:
		return 90.0
	return rad_to_deg(exhaust.angle_to(ray))


## Piecewise-linear lookup in [x0, y0, x1, y1, ...], clamped at the ends.
static func table_db(table: Array[float], x: float) -> float:
	if x <= table[0]:
		return table[1]
	for i: int in range(2, table.size(), 2):
		if x <= table[i]:
			return lerpf(table[i - 1], table[i + 1], (x - table[i - 2]) / (table[i] - table[i - 2]))
	return table[table.size() - 1]


## A ray through authored canopy boxes screens highs. Visual vegetation is not a collider.
static func screening(source: Vector3, listener: Vector3, canopies: Array[AABB]) -> float:
	var hits: int = 0
	for canopy: AABB in canopies:
		if canopy.intersects_segment(listener, source) != null:
			hits += 1
			if hits == 3:
				break
	return minf(float(hits) / 3.0, 1.0)
