# E0a2b/R02: the tail's downwash lag (FlightSession aux, advanced in _pre_step) holds a dimensional wing lift-velocity
# proxy in m/s. Layout and settled start; the lag input equals the loads' own wake source (byte-exact quasi-static identity);
# exact first-order step response; Cmα̇ measured by a
# forced plunge oscillation through the real _pre_step and local loads against the delay theory from the model's
# geometry; tick refinement; checkpoint replay. D11g: the oracle (attached-flow) regime carries the same lag, so its
# Cmα̇ equals the local one; reports the effective pitch damping Cmq + Cmα̇ in both regimes.
# Run: godot --headless --path . --script res://tests/test_downwash_lag.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const RB := preload("res://physics/rigid_body.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Ground := preload("res://physics/ground_contact.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

const V := 15.0
const RHO := 1.225
const K_REDUCED := 0.02 # ω·c/(2V): quasi-steady; the lag's exact 1/(1 + (ωτ)²) factor is kept in the theory
const AMPLITUDE := 0.0174533 # 1° plunge

var _failures := 0
var _count := 0
var _session: Node


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	_session = FlightSession.new()
	_session.setup()
	root.add_child(_session)
	_session.input_enabled = false
	var model: Dictionary = _session.aircraft.model
	var lag: int = _session.downwash_index()
	_check("Stik: one lagged wing lift-velocity source (m/s) after the anchors", lag == FlightSession.AUX_ANCHORS + 9 and _session.sim.aux.size() == lag + 1)
	# The lag is an explicit local-model capability. The Avanti oracle path does not receive an unused lag entry.

	for id in ["gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx"]:
		var other := FlightSession.new()
		other.setup(Catalog.entry(id).data)
		root.add_child(other)
		var other_model: Dictionary = other.aircraft.model
		var declares_lag: bool = not other_model.get("envelope", {}).is_empty() \
			and other_model.get("surfaces", {}).get("horizontal", {}).has("downwash_lag_length")
		var other_lag: int = other.downwash_index()
		var expected_lag: int = FlightSession.AUX_ANCHORS + other.anchor_count() * Ground.ANCHOR_STRIDE if declares_lag else -1
		_check("%s lag allocation follows its derived local-model capability" % id,
			other_lag == expected_lag and (not declares_lag or other.sim.aux.size() > other_lag))
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.entry(id).data))
		raw.aero.surfaces.horizontal.erase("downwash_gradient")
		var gradient_free := AD.validate_and_derive(raw.duplicate(true))
		var stripped := FlightSession.new()
		stripped.setup(Catalog.entry(id).data)
		root.add_child(stripped)
		stripped.expected_aircraft_id = ""
		if raw.aero.has("ground_effect"):
			var ground_effect_error := "aero.ground_effect: requires aero.surfaces.horizontal.downwash_gradient (the free tail law whose downwash it reduces)"
			_check("%s rejects ground effect without its free-tail gradient" % id,
				not gradient_free.ok and gradient_free.errors.has(ground_effect_error), str(gradient_free.errors))
			var invalid_apply: bool = stripped._apply(gradient_free)
			_check("%s rejected candidate leaves the active lag allocation unchanged" % id,
				not invalid_apply and stripped.downwash_index() == other_lag,
				"apply=%s, active_lag=%d, expected=%d" % [str(invalid_apply), stripped.downwash_index(), other_lag])
			# This candidate exercises a valid no-gradient/no-lag model. The P-51 ground-effect closure depends on the
			# gradient-derived free tail law, so remove that optional law from the synthetic in-memory candidate too.
			raw.aero.erase("ground_effect")
		var no_gradient := AD.validate_and_derive(raw)
		var applied: bool = stripped._apply(no_gradient)
		_check("%s without gradient-dependent laws (in memory): applies and has no lag entry" % id,
			no_gradient.ok and applied and stripped.downwash_index() == -1,
			"valid=%s, apply=%s, errors=%s" % [str(no_gradient.ok), str(applied), str(no_gradient.get("errors", PackedStringArray()))])
		stripped.queue_free()
		other.queue_free()
	var start: PackedFloat64Array = _session.sim.state
	_check("reset starts the lag settled at the start state's wing lift-velocity source (m/s)", _session.sim.aux[lag] == _session._wing_cl(start, _session.sim.aux))
	_identity(model)
	_selector_uses_lagged_tail()
	_session_path(model, lag)
	_step_response(lag)
	var at_240 := _plunge(model, lag, 1.0 / 240.0)
	var at_480 := _plunge(model, lag, 1.0 / 480.0)
	# A first-order lag of time constant τ = l/V responds in quadrature with Cmα̇/(1 + (ωτ)²) at frequency ω.
	var tau: float = float(model.surfaces.horizontal.downwash_lag_length) / V
	var omega_tau := K_REDUCED * 2.0 * V / float(model.reference.c) * tau
	var theory := _theory(model) / (1.0 + omega_tau * omega_tau)
	print("info Cmα̇: quasi-steady theory %.3f, at k %.2f %.3f; measured %.3f (240 Hz), %.3f (480 Hz)" % [_theory(model), K_REDUCED, theory, at_240, at_480])
	_check("Cmα̇ from the plunge oscillation %.3f within 5 %% of the lag theory %.3f" % [at_240, theory], absf(at_240 / theory - 1.0) < 0.05)
	var e240 := absf(at_240 - theory)
	var e480 := absf(at_480 - theory)
	_check("tick refinement: the error to theory halves at 480 Hz (held lag input, first order)", e480 < 0.65 * e240 and e480 > 0.35 * e240,
		"%.4f → %.4f" % [e240, e480])
	var oracle := _plunge(model, lag, 1.0 / 240.0, true)
	_check("D11g: the oracle regime's Cmα̇ %.3f within 3 %% of the local regime's %.3f (one lag, one tail)" % [oracle, at_240],
		absf(oracle / at_240 - 1.0) < 0.03)
	var cmq := _cmq_local(model, lag)
	var effective: float = cmq + at_240 * (1.0 + omega_tau * omega_tau) # measured, back to the quasi-steady limit
	print("info effective pitch damping: local Cmq %.2f + Cmα̇ %.2f = %.2f; oracle Cmq %.2f + Cmα̇ %.2f = %.2f"
		% [cmq, at_240, effective, model.aero.Cmq, oracle, float(model.aero.Cmq) + oracle * (1.0 + omega_tau * omega_tau)])
	_check("effective pitch damping Cmq + Cmα̇ %.2f within 10 %% of the geometry estimate −2·a_t·η·V_H·(l_t/c)·(1 + lag) + wing (%.2f)"
		% [effective, _geometry_estimate(model, cmq)], absf(effective / _geometry_estimate(model, cmq) - 1.0) < 0.10)
	_checkpoint()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## A descending α ramp leaves the tail outside the attached limit while the steady selector remains attached.
func _selector_uses_lagged_tail() -> void:
	var model: Dictionary = AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json").model
	var tail: Dictionary = model.surfaces.horizontal
	var start_alpha := deg_to_rad(7.8)
	var rate := -3.0 # rad/s, 46 ms at 15 m/s
	var dt := 1.0 / 240.0
	var d := { elevator = -deg_to_rad(12.605), aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	var ticks := ceili(start_alpha / (-rate * dt))
	var alpha := start_alpha
	var s := RB.make_state(M.v3(0.0, 0.0, -20.0), M.v3(V * cos(alpha), 0.0, V * sin(alpha)), M.q_identity(), M.v3(0.0, 0.0, 0.0))
	var air := Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), RHO)
	var lag: float = Aero.wing_wake_velocity(s, air, d, model)
	for k in range(1, ticks + 1):
		alpha = maxf(0.0, start_alpha + rate * k * dt)
		s = RB.make_state(M.v3(0.0, 0.0, -20.0), M.v3(V * cos(alpha), 0.0, V * sin(alpha)), M.q_identity(), M.v3(0.0, 0.0, 0.0))
		air = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), RHO)
		var wake_now: float = Aero.wing_wake_velocity(s, air, d, model)
		lag = wake_now + (lag - wake_now) * exp(-dt * V / float(tail.downwash_lag_length))
	var tail_plane_speed: float = sqrt(air.v_air[0] * air.v_air[0] + air.v_air[2] * air.v_air[2])
	var actual_tail: float = atan2(air.v_air[2], air.v_air[0]) - Aero.downwash_angle(lag, float(tail.downwash_per_cl), tail_plane_speed) \
		+ float(tail.elevator_tau) * d.elevator + float(tail.free_incidence)
	var x := clampf((absf(actual_tail) - float(model.surfaces.attached_limit))
		/ (float(model.surfaces.tail_local_limit) - float(model.surfaces.attached_limit)), 0.0, 1.0)
	var expected_blend := x * x * (3.0 - 2.0 * x)
	var static_blend: float = Aero.local_flow_weight(s, air, d, model)
	var actual_blend: float = Aero.local_flow_weight(s, air, d, model, lag)
	_check("descending α ramp moves actual tail beyond the attached limit", absf(actual_tail) > float(model.surfaces.attached_limit),
		"tail %.3f° after %d ticks" % [rad_to_deg(actual_tail), ticks])
	_check("selector uses lagged m/s source while the static call remains unchanged",
		static_blend == 0.0 and expected_blend > 0.0 and absf(actual_blend - expected_blend) < 1e-12,
		"static %.6f, actual %.6f, expected %.6f" % [static_blend, actual_blend, expected_blend])
	var global_loads: PackedFloat64Array = Aero._global_loads(s, air, d, model, RHO, lag)
	var local_loads: PackedFloat64Array = Aero._local_loads(s, air, d, model, RHO, lag)
	var expected_loads := global_loads.duplicate()
	for i in 6:
		expected_loads[i] = lerpf(global_loads[i], local_loads[i], expected_blend)
	var actual_loads: PackedFloat64Array = Aero.loads(s, air, d, model, RHO, lag)
	var static_loads: PackedFloat64Array = Aero.loads(s, air, d, model, RHO)
	_check("Aero.loads applies the lag-aware blend and passes the lag to both load laws",
		actual_loads.to_byte_array() == expected_loads.to_byte_array()
			and actual_loads.to_byte_array() != static_loads.to_byte_array(),
		"actual pitch %.6f, lag-weighted %.6f, static %.6f N·m" % [actual_loads[4], expected_loads[4], static_loads[4]])


## With the lag equal to the instantaneous wing lift-velocity source the local loads are quasi-static, byte for byte.
func _identity(model: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51616
	var same := 0
	var same_oracle := 0
	for i in 2000:
		var alpha := rng.randf_range(-0.3, 0.5)
		var speed := rng.randf_range(6.0, 35.0)
		var s := PackedFloat64Array([0, 0, -100, speed * cos(alpha), rng.randf_range(-3, 3), speed * sin(alpha), 1, 0, 0, 0,
			rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3)])
		var d := { elevator = rng.randf_range(-0.4, 0.4), aileron_right = rng.randf_range(-0.4, 0.4), aileron_left = rng.randf_range(-0.4, 0.4), rudder = 0.0 }
		var air := Air.compute(s, PackedFloat64Array([0, 0, 0]), RHO)
		var wake := Aero.wing_wake_velocity(s, air, d, model)
		if Aero._local_loads(s, air, d, model, RHO, wake).to_byte_array() == Aero._local_loads(s, air, d, model, RHO).to_byte_array():
			same += 1
		if Aero._global_loads(s, air, d, model, RHO, wake).to_byte_array() == Aero._global_loads(s, air, d, model, RHO).to_byte_array():
			same_oracle += 1
	_check("lag = instantaneous wake source reproduces quasi-static local loads byte for byte (2000 stalled/rate/control states)", same == 2000, "%d/2000" % same)
	_check("D11g: and the quasi-static oracle loads byte for byte (settled lag adds nothing)", same_oracle == 2000, "%d/2000" % same_oracle)


## The simulator's own loads callback must feed the lag to the tail: with the held m/s source displaced from the instantaneous source
## in the blend regime (α 11°), FlightSession._loads equals Dynamics with that lag and differs from the quasi-static one.
func _session_path(model: Dictionary, lag: int) -> void:
	const Dynamics := preload("res://physics/dynamics.gd")
	var alpha := deg_to_rad(11.0)
	var s := PackedFloat64Array([0, 0, -100, V * cos(alpha), 0, V * sin(alpha), 1, 0, 0, 0, 0, 0, 0])
	var aux: PackedFloat64Array = _session.sim.aux.duplicate()
	aux[lag] = _session._wing_cl(s, aux) - 3.0 # m/s, corresponding to a 0.2 CL offset at this 15 m/s condition
	_session.sim.aux = aux
	var through_session: PackedFloat64Array = _session._loads(s, 0.0)
	var d: Dictionary = _session._deflections(aux)
	var with_lag := Dynamics.loads(s, model, d, aux[0], RHO, PackedFloat64Array([0, 0, 0]), aux[lag])
	var quasi := Dynamics.loads(s, model, d, aux[0], RHO, PackedFloat64Array([0, 0, 0]))
	_check("FlightSession._loads feeds the held m/s source to the tail (equals Dynamics with it, differs from instantaneous)",
		through_session == with_lag and through_session != quasi, "pitch %.4f vs quasi-static %.4f N·m" % [through_session[4], quasi[4]])
	_session.reset()


## Fixed state, lag displaced: after n ticks it is U_L + (x0 − U_L)·exp(−n·dt·V/l).
func _step_response(lag: int) -> void:
	var s: PackedFloat64Array = _session.sim.state.duplicate()
	var aux: PackedFloat64Array = _session.sim.aux.duplicate()
	var wake: float = _session._wing_cl(s, aux)
	var x0 := wake + 0.3
	aux[lag] = x0
	var dt := 1.0 / 240.0
	var speed: float = Air.compute(s, PackedFloat64Array([0, 0, 0]), RHO).V
	var length: float = _session.aircraft.model.surfaces.horizontal.downwash_lag_length
	var worst := 0.0
	for n in range(1, 25):
		aux = _session._pre_step(aux, _session.sim.inputs, dt)
		var expected := wake + (x0 - wake) * exp(-n * dt * speed / length)
		worst = maxf(worst, absf(aux[lag] - expected))
	_check("step response: exact first-order lag over 24 ticks (τ = l/V = %.1f ms)" % (1000.0 * length / speed), worst < 1e-12,
		String.num_scientific(worst))


## Forced plunge α = α0 + A·sin(ωt), q = 0, through the session's _pre_step and the local loads (or the oracle's, at
## the same α 4° where the blend is 0); Cmα̇ is the moment in phase with α̇, nondimensionalised by α̇·c/(2V).
func _plunge(model: Dictionary, lag: int, dt: float, oracle := false) -> float:
	var c: float = model.reference.c
	# A whole number of ticks per period, so the projection window holds exact periods and the large in-phase Cmα·α
	# term cannot leak into the α̇ (quadrature) term.
	var steps := roundi(TAU / (K_REDUCED * 2.0 * V / c) / dt)
	var period := steps * dt
	var omega := TAU / period
	var alpha0 := deg_to_rad(4.0)
	var aux: PackedFloat64Array = _session.sim.aux.duplicate()
	var d := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	var qs: float = 0.5 * RHO * V * V * float(model.reference.S) * c
	var projection := 0.0
	for k in 6 * steps:
		var t := k * dt
		var alpha := alpha0 + AMPLITUDE * sin(omega * t)
		var s := PackedFloat64Array([0, 0, -100, V * cos(alpha), 0, V * sin(alpha), 1, 0, 0, 0, 0, 0, 0])
		_session.sim.state = s
		aux = _session._pre_step(aux, _session.sim.inputs, dt)
		if k >= 3 * steps:
			var air := Air.compute(s, PackedFloat64Array([0, 0, 0]), RHO)
			var loads: PackedFloat64Array = Aero._global_loads(s, air, d, model, RHO, aux[lag]) if oracle \
				else Aero._local_loads(s, air, d, model, RHO, aux[lag])
			var cm: float = loads[4] / qs
			projection += cm * cos(omega * t) * dt
	var in_quadrature := projection * 2.0 / (3.0 * period)
	return in_quadrature / (AMPLITUDE * omega * c / (2.0 * V))


## Delay theory for ε = atan2(g·U_L, V_t): calculate dU_L/dα from the attached induced map, then apply the analytic
## atan2 derivative and first-order lag factor. This fixture has no optional post-stall polar at 4°.
func _theory(model: Dictionary) -> float:
	var tail: Dictionary = model.surfaces.horizontal
	var c: float = model.reference.c
	var arm: float = float(tail.position[0]) - float(model.cg_le[0])
	var dcm_dtail: float = -float(tail.free_slope) * float(tail.area) / float(model.reference.S) * arm / c
	var env: Dictionary = model.envelope
	var station_count: int = env.station_ys.size()
	var strip_slope: float = float(env.get("strip_slope", model.aero.CLa))
	var wake_slope := V * float(model.aero.CLa)
	var e_map: PackedFloat64Array = env.get("induced_map", PackedFloat64Array())
	if e_map.size() == station_count * station_count:
		wake_slope = 0.0
		for i in station_count:
			var row_sum := 0.0
			for j in station_count:
				row_sum += e_map[i * station_count + j]
			wake_slope += V * strip_slope * row_sum / station_count
	var alpha := deg_to_rad(4.0)
	var state := RB.make_state(M.v3(0.0, 0.0, -100.0), M.v3(V * cos(alpha), 0.0, V * sin(alpha)),
		M.q_identity(), M.v3(0.0, 0.0, 0.0))
	var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), RHO)
	var d := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	var wake: float = Aero.wing_wake_velocity(state, air, d, model)
	var tail_speed := V # alpha changes direction at fixed speed and there are no tail rates in this analytic state
	var d_epsilon_d_wake: float = float(tail.downwash_per_cl) * tail_speed \
		/ (tail_speed * tail_speed + pow(float(tail.downwash_per_cl) * wake, 2.0))
	var d_epsilon_d_alpha: float = d_epsilon_d_wake * wake_slope
	return dcm_dtail * d_epsilon_d_alpha * float(tail.downwash_lag_length) / V * 2.0 * V / c


## Geometry estimate of Cmq + Cmα̇: the measured local Cmq (tail and wing) plus the delay theory.
func _geometry_estimate(model: Dictionary, cmq: float) -> float:
	return cmq + _theory(model)


## Local-regime Cmq at α 4° (central difference in q, lag settled), nondimensional.
func _cmq_local(model: Dictionary, lag: int) -> float:
	var c: float = model.reference.c
	var alpha := deg_to_rad(4.0)
	var d := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	var h := 0.05
	var m := PackedFloat64Array()
	for q in [h, -h]:
		var s := PackedFloat64Array([0, 0, -100, V * cos(alpha), 0, V * sin(alpha), 1, 0, 0, 0, 0, q, 0])
		var air := Air.compute(s, PackedFloat64Array([0, 0, 0]), RHO)
		m.append(Aero._local_loads(s, air, d, model, RHO, Aero.wing_wake_velocity(s, air, d, model))[4])
	return (m[0] - m[1]) / (2.0 * h) / (0.5 * RHO * V * V * float(model.reference.S) * c * c / (2.0 * V))


func _checkpoint() -> void:
	_session.reset()
	var inputs: PackedFloat64Array = _session.sim.inputs.duplicate()
	inputs[1] = 0.6 # pull: the lag moves
	_session.sim.inputs = inputs
	for i in 300:
		_session.sim.step()
	var cp: Dictionary = _session.checkpoint()
	for i in 200:
		_session.sim.step()
	var first: PackedByteArray = _session.sim.state.to_byte_array() + _session.sim.aux.to_byte_array()
	var restored: bool = _session.restore_checkpoint(cp)
	_session.sim.set_paused(false)
	_session.sim.inputs = inputs
	for i in 200:
		_session.sim.step()
	_check("checkpoint mid-pull: restore and replay 200 ticks byte-identical, lag included", restored
		and first == _session.sim.state.to_byte_array() + _session.sim.aux.to_byte_array())
