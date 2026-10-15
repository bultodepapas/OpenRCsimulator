## R06 Slice A: AircraftData, control-authority and same-input checks for the isolated candidate.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Flight := preload("res://sim/flight_session.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Slipstream := preload("res://physics/slipstream.gd")

const BASELINE_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const CANDIDATE_RELATIVE := "res://../research/physics-audit-2026-10-14/remediation/stik_wash_candidate/aircraft_v2.json"
const RHO := 1.225
const CONTROL_DELTA_RAD := 0.01
const SCENARIO_TICKS := 240

var _checks := 0
var _failures := 0
var _candidate_path := ""


func _initialize() -> void:
	_candidate_path = ProjectSettings.globalize_path(CANDIDATE_RELATIVE)
	call_deferred("_run")


func _run() -> void:
	var baseline: Dictionary = AD.load_file(BASELINE_PATH)
	var candidate: Dictionary = AD.load_file(_candidate_path)
	_check("baseline aircraft loads", baseline.get("ok", false), str(baseline.get("errors", [])))
	_check("candidate AircraftData.load_file accepts v2", candidate.get("ok", false), str(candidate.get("errors", [])))
	if not baseline.get("ok", false) or not candidate.get("ok", false):
		_quit()
		return
	var base_model: Dictionary = baseline.model
	var candidate_model: Dictionary = candidate.model
	var slipstream: Dictionary = candidate_model.propulsion.get("slipstream", {})
	_check("catalog Stik remains unconfigured", base_model.propulsion.get("slipstream", {}).is_empty())
	_check("candidate has three generated stateless pieces", slipstream.get("pieces", []).size() == 3
		and not slipstream.has("transport_speed_floor"))
	_check("candidate preserves baseline physical ID and wheel profile", candidate_model.id == base_model.id
		and candidate_model.wheel_profile.get("status", "") == base_model.wheel_profile.get("status", ""))
	print(JSON.stringify({record="identity", baseline_id=base_model.id, candidate_id=candidate_model.id,
		baseline_sha256=baseline.get("input_identity", {}).get("sha256", ""),
		candidate_sha256=candidate.get("input_identity", {}).get("sha256", ""),
		candidate_wheel_profile=candidate_model.wheel_profile.get("status", ""),
		candidate_piece_count=slipstream.get("pieces", []).size(), stateless=true}))
	_authority_sweep(base_model, candidate_model)
	_stopped_transport_edge(candidate_model)
	_same_input_scenario()
	print("R06 Slice A probe: %d checks, %d failed" % [_checks, _failures])
	_quit()


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	print("%s %s%s" % ["ok" if ok else "FAIL", label, " — " + detail if not detail.is_empty() else ""])
	if not ok:
		_failures += 1


func _state(speed_mps: float, alpha_deg: float = 0.0) -> PackedFloat64Array:
	var alpha := deg_to_rad(alpha_deg)
	return PackedFloat64Array([0.0, 0.0, -100.0, speed_mps * cos(alpha), 0.0, speed_mps * sin(alpha),
		1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


func _deflections(elevator: float = 0.0, rudder: float = 0.0) -> Dictionary:
	return {elevator=elevator, rudder=rudder, aileron_left=0.0, aileron_right=0.0}


func _add_loads(left: PackedFloat64Array, right: PackedFloat64Array) -> PackedFloat64Array:
	var result := left.duplicate()
	for index in 6:
		result[index] += right[index]
	return result


func _aero_loads(model: Dictionary, state: PackedFloat64Array, deflections: Dictionary, rpm: float) -> PackedFloat64Array:
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var free: PackedFloat64Array = Aero.loads(state, air, deflections, model, RHO)
	if model.propulsion.get("slipstream", {}).is_empty():
		return free
	var wash: PackedFloat64Array = Slipstream.loads(state, air, deflections, model, rpm, RHO)
	return _add_loads(free, wash)


func _moment_slope(model: Dictionary, speed_mps: float, rpm: float, control: String) -> float:
	var plus := _deflections()
	var minus := _deflections()
	plus[control] = CONTROL_DELTA_RAD
	minus[control] = -CONTROL_DELTA_RAD
	var state: PackedFloat64Array = _state(speed_mps)
	var m_plus: PackedFloat64Array = _aero_loads(model, state, plus, rpm)
	var m_minus: PackedFloat64Array = _aero_loads(model, state, minus, rpm)
	var moment_index := 4 if control == "elevator" else 5
	return (m_plus[moment_index] - m_minus[moment_index]) / (2.0 * CONTROL_DELTA_RAD)


func _authority_sweep(base_model: Dictionary, candidate_model: Dictionary) -> void:
	var rpm_values := {"engine_off": 0.0, "engine_on_rated_static": float(base_model.propulsion.max_rpm)}
	for speed_mps in [0.0, 5.0, 15.0]:
		for operating_point: String in rpm_values:
			var rpm: float = rpm_values[operating_point]
			var record := {record="authority", alpha_deg=0.0, speed_mps=speed_mps,
				operating_point=operating_point, rpm=rpm, control_delta_rad=CONTROL_DELTA_RAD,
				control_sign_convention="actual surface deflection radians; positive elevator TE-down, rudder TE-left",
				baseline={}, candidate={}, added_by_wash={}}
			for control in ["elevator", "rudder"]:
				var base_slope: float = _moment_slope(base_model, speed_mps, rpm, control)
				var candidate_slope: float = _moment_slope(candidate_model, speed_mps, rpm, control)
				var moment_name := "My" if control == "elevator" else "Mz"
				record.baseline[control + "_" + moment_name + "_Nm_per_rad"] = base_slope
				record.candidate[control + "_" + moment_name + "_Nm_per_rad"] = candidate_slope
				record.added_by_wash[control + "_" + moment_name + "_Nm_per_rad"] = candidate_slope - base_slope
				if rpm == 0.0:
					_check("engine-off free-flow response preserved: %s %s m/s" % [control, str(speed_mps)],
						candidate_slope == base_slope)
				else:
					_check("running-prop wash changes modeled authority: %s %s m/s" % [control, str(speed_mps)],
						absf(candidate_slope - base_slope) > 1e-6)
			_check("finite control moment slopes %s m/s %s" % [str(speed_mps), operating_point],
				is_finite(float(record.candidate.elevator_My_Nm_per_rad))
				and is_finite(float(record.candidate.rudder_Mz_Nm_per_rad)))
			print(JSON.stringify(record))


func _norm6(values: PackedFloat64Array) -> float:
	var sum := 0.0
	for value in values:
		sum += value * value
	return sqrt(sum)


func _stopped_transport_load(model: Dictionary, axial_speed: float, transported: PackedFloat64Array) -> PackedFloat64Array:
	var state: PackedFloat64Array = _state(absf(axial_speed))
	state[RB.VEL] = axial_speed
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	return Slipstream.loads(state, air, _deflections(), model, 0.0, RHO, 0.0, transported)


func _stopped_transport_edge(model: Dictionary) -> void:
	var transported := PackedFloat64Array([2.0, 2.0, 2.0])
	var neg: PackedFloat64Array = _stopped_transport_load(model, -1e-8, transported)
	var zero: PackedFloat64Array = _stopped_transport_load(model, 0.0, transported)
	var pos: PackedFloat64Array = _stopped_transport_load(model, 1e-8, transported)
	var jump := PackedFloat64Array()
	for index in 6:
		jump.append(pos[index] - neg[index])
	var force_jump := sqrt(jump[0] * jump[0] + jump[1] * jump[1] + jump[2] * jump[2])
	var moment_jump := sqrt(jump[3] * jump[3] + jump[4] * jump[4] + jump[5] * jump[5])
	var record := {record="stopped_transported_wake_edge", rpm=0.0, transported_dv_mps=Array(transported),
		axial_velocity_samples_mps=[-1e-8, 0.0, 1e-8],
		loads_at_minus_epsilon=Array(neg), loads_at_zero=Array(zero), loads_at_plus_epsilon=Array(pos),
		one_sided_force_jump_n=force_jump, one_sided_moment_jump_nm=moment_jump,
		code_branch="fade = 1 for v[0] >= 0; fade = 0 for v[0] < 0"}
	_check("stopped transported-wake edge diagnostic is finite", is_finite(force_jump) and is_finite(moment_jump))
	print(JSON.stringify(record))


func _make_session(path: String) -> Node:
	var session: Node = Flight.new()
	session.input_enabled = false
	session.setup(path)
	root.add_child(session)
	session.input_enabled = false
	return session


func _same_input_scenario() -> void:
	var baseline: Node = _make_session(BASELINE_PATH)
	var candidate: Node = _make_session(_candidate_path)
	var compatible: bool = baseline.is_flyable() and candidate.is_flyable()
	if not compatible:
		_check("same-input sessions load", false, "baseline=%s candidate=%s" % [baseline.pause_reason, candidate.pause_reason])
		baseline.free()
		candidate.free()
		return
	var same_layout: bool = baseline.sim.inputs.size() == candidate.sim.inputs.size() \
		and baseline.sim.aux.size() == candidate.sim.aux.size() \
		and baseline.sim.continuous.size() == candidate.sim.continuous.size()
	_check("stateless candidate retains baseline simulation layout", same_layout,
		"inputs %d/%d aux %d/%d continuous %d/%d" % [baseline.sim.inputs.size(), candidate.sim.inputs.size(),
			baseline.sim.aux.size(), candidate.sim.aux.size(), baseline.sim.continuous.size(), candidate.sim.continuous.size()])
	if not same_layout:
		baseline.free()
		candidate.free()
		return
	var initial: PackedFloat64Array = baseline.sim.state.duplicate()
	var inputs: PackedFloat64Array = baseline.sim.inputs.duplicate()
	var aux: PackedFloat64Array = baseline.sim.aux.duplicate()
	var continuous: PackedFloat64Array = baseline.sim.continuous.duplicate()
	candidate.sim.inputs = inputs.duplicate()
	candidate.sim.aux = aux.duplicate()
	candidate.sim.continuous = continuous.duplicate()
	candidate.sim.modes = baseline.sim.modes.duplicate()
	var reset_ok: bool = candidate.sim.reset(initial.duplicate())
	var exact_initial: bool = reset_ok and candidate.sim.state.to_byte_array() == initial.to_byte_array() \
		and candidate.sim.inputs.to_byte_array() == inputs.to_byte_array() \
		and candidate.sim.aux.to_byte_array() == aux.to_byte_array() \
		and candidate.sim.continuous.to_byte_array() == continuous.to_byte_array()
	_check("candidate accepts baseline's exact initial body/internal/input state", exact_initial,
		"initial airspeed %.6f m/s, baseline rpm %.6f" % [Air.compute(initial, M.v3(0.0, 0.0, 0.0), RHO).V, aux[0]])
	if not exact_initial:
		baseline.free()
		candidate.free()
		return
	baseline.sim.set_paused(false)
	candidate.sim.set_paused(false)
	var max_position_delta := 0.0
	var max_velocity_delta := 0.0
	var max_attitude_delta := 0.0
	var max_rate_delta := 0.0
	var samples: Array[Dictionary] = []
	var candidate_failed := false
	for tick in SCENARIO_TICKS:
		baseline.sim.step()
		candidate.sim.step()
		if not baseline.sim.fault_reason.is_empty() or not candidate.sim.fault_reason.is_empty():
			candidate_failed = true
			break
		var position_delta := _vector_delta(baseline.sim.state, candidate.sim.state, RB.POS)
		var velocity_delta := _vector_delta(baseline.sim.state, candidate.sim.state, RB.VEL)
		var attitude_delta := _attitude_delta(baseline.sim.state, candidate.sim.state)
		var rate_delta := _vector_delta(baseline.sim.state, candidate.sim.state, RB.RATE)
		max_position_delta = maxf(max_position_delta, position_delta)
		max_velocity_delta = maxf(max_velocity_delta, velocity_delta)
		max_attitude_delta = maxf(max_attitude_delta, attitude_delta)
		max_rate_delta = maxf(max_rate_delta, rate_delta)
		if (tick + 1) % 60 == 0:
			samples.append({tick=tick + 1, time_s=baseline.sim.time(), position_delta_m=position_delta,
				velocity_delta_mps=velocity_delta, attitude_delta_rad=attitude_delta, rate_delta_radps=rate_delta,
				baseline_state=Array(baseline.sim.state), candidate_state=Array(candidate.sim.state)})
	_check("240-tick baseline/candidate scenario remains finite", not candidate_failed,
		"baseline fault='%s', candidate fault='%s'" % [baseline.sim.fault_reason, candidate.sim.fault_reason])
	print(JSON.stringify({record="same_input_scenario", compatible_layout=same_layout, ticks=baseline.sim.tick,
		initial_state_from="baseline fresh FlightSession trim", copied_inputs=Array(inputs), initial_rpm=aux[0],
		initial_body_internal_input_state_byte_equal=exact_initial,
		max_position_delta_m=max_position_delta, max_velocity_delta_mps=max_velocity_delta,
		max_attitude_delta_rad=max_attitude_delta, max_rate_delta_radps=max_rate_delta,
		baseline_state_final=Array(baseline.sim.state), candidate_state_final=Array(candidate.sim.state), samples=samples}))
	baseline.free()
	candidate.free()


func _vector_delta(left: PackedFloat64Array, right: PackedFloat64Array, start: int) -> float:
	var delta := 0.0
	for index in 3:
		var difference: float = left[start + index] - right[start + index]
		delta += difference * difference
	return sqrt(delta)


func _attitude_delta(left: PackedFloat64Array, right: PackedFloat64Array) -> float:
	var dot := 0.0
	for index in 4:
		dot += left[RB.ATT + index] * right[RB.ATT + index]
	return 2.0 * acos(clampf(absf(dot), 0.0, 1.0))


func _quit() -> void:
	quit(1 if _failures else 0)
