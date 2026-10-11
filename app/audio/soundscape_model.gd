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
		result.motor_pitch = 0.55 + 0.75 * ratio
		result.motor_gain = (0.12 + 0.40 * ratio * ratio) if running else 0.0
		result.prop_gain = 0.0
	return result


## A ray through authored canopy boxes screens highs. Visual vegetation is not a collider.
static func screening(source: Vector3, listener: Vector3, canopies: Array[AABB]) -> float:
	var hits: int = 0
	for canopy: AABB in canopies:
		if canopy.intersects_segment(listener, source) != null:
			hits += 1
			if hits == 3:
				break
	return minf(float(hits) / 3.0, 1.0)
