# Independent representation/invariance checks, not a flight-model validation.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Air := preload("res://physics/air_data.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

func error(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var out := 0.0
	for i in a.size():
		if not is_finite(a[i]) or not is_finite(b[i]):
			return INF
		out = maxf(out, absf(a[i] - b[i]) / maxf(1.0, maxf(absf(a[i]), absf(b[i]))))
	return out

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026101303
	var results: Array = []
	var failed := 0
	for id: String in Catalog.flyable_ids():
		var flight := Flight.new()
		flight.setup(Catalog.entry(id).data)
		root.add_child(flight)
		if not flight.aircraft.get("ok", false):
			failed += 1
			flight.free()
			continue
		var model: Dictionary = flight.aircraft.model
		var maxima := {quaternion_sign = 0.0, heading_rotation = 0.0, wind_boost = 0.0, stage_air = 0.0}
		for sample in 400:
			var s: PackedFloat64Array = flight.sim.state.duplicate()
			var q := M.q_from_euler(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI))
			for i in 4:
				s[RB.ATT + i] = q[i]
			for i in 3:
				s[RB.VEL + i] = rng.randf_range(-35.0, 35.0)
				s[RB.RATE + i] = rng.randf_range(-3.0, 3.0)
			var wind := M.v3(rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0), rng.randf_range(-3.0, 3.0))
			var d := {elevator = rng.randf_range(-0.3, 0.3), aileron_right = rng.randf_range(-0.3, 0.3), aileron_left = rng.randf_range(-0.3, 0.3), rudder = rng.randf_range(-0.3, 0.3)}
			var rpm: float = flight.start.rpm * rng.randf_range(0.2, 1.2)
			var rho := rng.randf_range(0.8, 1.3)
			var lag: float = rng.randf_range(-0.9, 1.2) if sample % 2 == 0 else NAN
			var ground: float = 0.0 if sample % 4 == 0 else NAN
			if not is_nan(ground):
				s[RB.POS + 2] = rng.randf_range(-3.0, -0.3)
			var base := Dynamics.loads(s, model, d, rpm, rho, wind, lag, PackedFloat64Array(), ground)
			var opposite := s.duplicate()
			for i in 4:
				opposite[RB.ATT + i] = -q[i]
			maxima.quaternion_sign = maxf(maxima.quaternion_sign, error(base, Dynamics.loads(opposite, model, d, rpm, rho, wind, lag, PackedFloat64Array(), ground)))
			var heading := M.q_from_euler(rng.randf_range(-PI, PI), 0.0, 0.0)
			var rotated := s.duplicate()
			var rotated_q := M.q_mul(heading, q)
			for i in 4:
				rotated[RB.ATT + i] = rotated_q[i]
			maxima.heading_rotation = maxf(maxima.heading_rotation, error(base, Dynamics.loads(rotated, model, d, rpm, rho, M.q_rotate(heading, wind), lag, PackedFloat64Array(), ground)))
			var boost := M.v3(11.0, -7.0, 2.0)
			var body_boost := M.q_rotate(M.q_conj(q), boost)
			var boosted := s.duplicate()
			for i in 3:
				boosted[RB.VEL + i] += body_boost[i]
			maxima.wind_boost = maxf(maxima.wind_boost, error(base, Dynamics.loads(boosted, model, d, rpm, rho, M.add(wind, boost), lag, PackedFloat64Array(), ground)))
			maxima.stage_air = maxf(maxima.stage_air, error(base, Dynamics.loads_from_air(s, model, d, rpm, rho, Air.compute(s, wind, rho), lag, PackedFloat64Array(), ground)))
		for value in maxima.values():
			if value > 1e-10:
				failed += 1
		results.append({aircraft = id, samples = 400, explicit_lag_samples = 200, ground_query_samples = 100, maximum_scaled_error = maxima})
		flight.free()
	var report := {schema = "openrc-shared-code-invariants-v1", seed = 2026101303, failures = failed, results = results}
	print(JSON.stringify(report))
	quit(1 if failed else 0)
