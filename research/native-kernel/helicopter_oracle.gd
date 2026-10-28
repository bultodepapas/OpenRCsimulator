## NK-3 experimental X-Cell session-stage comparison. The source of truth is
## HelicopterFlightSession._stage, with the real Flight.prepare context, skid
## terrain, trainer/direct controls and lifecycle. Component evidence only;
## native Simulation installation, stop events and replay remain separate gates.
extends "oracle.gd"

const HelicopterSession := preload("res://sim/helicopter_flight_session.gd")
const RotorcraftData := preload("res://physics/rotorcraft_data.gd")
const HeliSkids := preload("res://physics/rotorcraft/skid_contact.gd")
const HeliMain := preload("res://physics/rotorcraft/main_rotor.gd")
const HeliWindConfig := preload("res://physics/wind_config.gd")

const HELICOPTER_ID := "xcell-60-research"
const HELICOPTER_PATH := "res://data/aircraft/xcell_60_research.json"


func _source_hashes() -> Dictionary:
	var out: Dictionary = super._source_hashes()
	for path: String in ["res://sim/helicopter_flight_session.gd", "res://physics/rotorcraft_data.gd",
			"res://physics/rotorcraft/flight_dynamics.gd", "res://physics/rotorcraft/aerodynamic_stage.gd",
			"res://physics/rotorcraft/performance_context.gd", "res://physics/rotorcraft/main_rotor.gd",
			"res://physics/rotorcraft/main_rotor_stage.gd", "res://physics/rotorcraft/tail_rotor.gd",
			"res://physics/rotorcraft/inflow.gd", "res://physics/rotorcraft/dynamic_inflow.gd",
			"res://physics/rotorcraft/airframe.gd", "res://physics/rotorcraft/electronics.gd",
			"res://physics/rotorcraft/swash.gd", "res://physics/rotorcraft/drive.gd",
			"res://physics/rotorcraft/geared_coupling.gd", "res://physics/rotorcraft/skid_contact.gd",
			"res://physics/rotorcraft/lifecycle.gd", "res://physics/rotorcraft/trim.gd",
			"res://physics/rotorcraft/ground_start.gd", "res://data/aircraft/xcell_60_research.json",
			"res://data/aircraft/hx700_electric_3d_experimental.json", "res://data/fields/default.json"]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _checks() -> void:
	_report.format = "openrc-nk3-helicopter-oracle v1"
	if not _native.has_method("prepare_helicopter") or not _native.has_method("heli_component"):
		_failures.append("native helicopter methods are missing")
		return
	if _states <= 0:
		_failures.append("helicopter states must be positive")
		return
	var loaded_field: Dictionary = FieldLoader.load_from()
	if not loaded_field.ok:
		_failures.append("default field failed to load")
		return
	var weather_ids := ["calm", "steady", "crosswind", "gusty", "updraft", "hot-high", "cool-dense"]
	_report.reference_start_refusals = []
	for start: String in ["airborne", "ground"]:
		for weather_id: String in weather_ids:
			var session := _make_session(loaded_field.field, start, weather_id)
			if session == null:
				continue
			var snapshot := _snapshot(session)
			var prepared: Dictionary = _native.prepare_helicopter(snapshot)
			if not prepared.ok:
				_failures.append("helicopter prepare %s/%s: %s" % [start, weather_id, str(prepared.error)])
				session.free()
				continue
			_check_session(session, start, weather_id, maxi(1, int(ceil(float(_states) / float(2 * weather_ids.size())))))
			if weather_id == "calm":
				_check_malformed_stages(session, start)
				_check_heli_refusals(session, snapshot, start)
			session.free()


func _make_session(field: Dictionary, start: String, weather_id: String) -> Node:
	var session: Node = HelicopterSession.new()
	session.input_enabled = false
	if not session.setup(HELICOPTER_PATH, HELICOPTER_ID) or not session.set_field(field):
		_failures.append("helicopter setup %s/%s: %s" % [start, weather_id, str(session.start_error)])
		session.free()
		return null
	if not session.set_start_choice(start):
		_failures.append("helicopter start choice refused: " + start)
		session.free()
		return null
	# At stock hot-high density, reference reset currently cannot solve trim.
	# Keep a real calm reset as a clearly labeled component seed, then prepare the
	# actual hot-high context. This never claims an available hot-high flight start.
	if weather_id == "hot-high" and not session.reset():
		_failures.append("calm seed for hot-high component failed: " + start)
		session.free()
		return null
	if not session.setup_weather(HeliWindConfig.preset(weather_id)):
		_failures.append("helicopter weather %s/%s: %s" % [start, weather_id, str(session.weather_error)])
		session.free()
		return null
	var reset_ok: bool = session.reset()
	if not reset_ok and weather_id == "hot-high" and str(session.start_error).contains("hover trim line search could not reduce the full-force residual"):
		_report.reference_start_refusals.append({start = start, weather = weather_id, reason = session.start_error,
			component_seed = "calm reference reset; no hot-high flight start"})
	elif not reset_ok:
		_failures.append("helicopter reset %s/%s: %s / %s" % [start, weather_id, str(session.start_error), str(session.weather_error)])
		session.free()
		return null
	if session.sim.continuous.size() != (14 if start == "ground" else 6):
		_failures.append("helicopter continuous layout mismatch: " + start)
		session.free()
		return null
	return session


func _snapshot(session: Node) -> Dictionary:
	return {format = "openrc-nk3-helicopter-snapshot-v1", context = session.aircraft.context,
		skids = session.aircraft.skids, surfaces = session.ground_surfaces.duplicate()}


func _tick(session: Node) -> Dictionary:
	return {inputs = session.sim.inputs.duplicate(), mode = session.flight_mode, trainer = session.trainer_enabled,
		hold = session.zero_drive_hold, armed = session.power.armed, ground_start = session.start_choice == "ground",
		spool_start_s = float(session.power.spool_start_s), trim = session._trim.duplicate(true)}


func _compare_stage(session: Node, body: PackedFloat64Array, continuous: PackedFloat64Array,
		time: float, label: Variant) -> bool:
	session._stage_failure = ""
	var reference: Dictionary = session._stage(body, continuous, time)
	var tick := _tick(session)
	var wind: PackedFloat64Array = session.wind_at(time, body)
	var native: Dictionary = _native.heli_component(body, continuous, time, tick, wind)
	var reference_ok := not reference.is_empty()
	var native_ok: bool = native.get("ok", false)
	var inputs := [label, body, continuous, time, tick, wind, session._stage_failure, native.get("error", "")]
	_compare("helicopter_stage_validity", PackedFloat64Array([1.0 if reference_ok else 0.0]),
		PackedFloat64Array([1.0 if native_ok else 0.0]), inputs)
	if not reference_ok or not native_ok:
		if native_ok != reference_ok: _tally("helicopter", "validity_mismatches")
		if not reference_ok and not native_ok:
			_compare("helicopter_failure_message", str(session._stage_failure), str(native.get("error", "")), inputs)
		return false
	for key: String in ["loads", "body_derivative", "derivative", "rotor_momentum"]:
		_compare("helicopter_" + key, reference[key], native.get(key), inputs)
	_tally("helicopter", "accepted")
	return true


func _check_session(session: Node, start: String, weather_id: String, count: int) -> void:
	var initial_body: PackedFloat64Array = session.sim.state.duplicate()
	var initial_continuous: PackedFloat64Array = session.sim.continuous.duplicate()
	var nominal: float = session.aircraft.context.main_model.omega_nominal_rad_s
	var zero_bristles := PackedFloat64Array()
	zero_bristles.resize(8)
	# The live reset state must compare before any manufactured perturbations.
	# Hot-high is explicitly a calm-derived seed after the recorded refusal above.
	if not _compare_stage(session, initial_body, initial_continuous, 0.0, [start, weather_id, "reset_or_labeled_seed"]) and weather_id != "hot-high":
		_failures.append("native helicopter reset stage refused: " + start + "/" + weather_id)
	for i in count:
		var body := initial_body.duplicate()
		var continuous := initial_continuous.duplicate()
		var mode := i % 2
		session.flight_mode = "idle_up" if mode else "normal"
		session.trainer_enabled = i % 3 != 0
		session.zero_drive_hold = i % 11 == 0
		var time: float = [0.0, 1.0, 5.0, 12.0, 18.0][i % 5]
		session.power = {armed = i % 13 != 0, spool_start_s = -12.0 if start == "airborne" else 0.0}
		session.sim.inputs = PackedFloat64Array([_rng.randf_range(-0.7, 0.7), _rng.randf_range(-0.7, 0.7),
			_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.05, 0.95)])
		if i % 7 == 0:
			session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.5])
		for axis in 3:
			body[3 + axis] += _rng.randf_range(-0.5, 0.5)
			body[10 + axis] = _rng.randf_range(-0.3, 0.3)
		if start == "ground":
			body[2] += _rng.randf_range(-0.008, 0.008)
			if i % 5 == 0: body[2] = -3.0 # unloaded bristle decay
			if i % 7 == 0: body[0] = 100.0 # rough terrain, non-pad friction
			for axis in 8: continuous[6 + axis] = _rng.randf_range(-0.0002, 0.0002)
		else:
			body[2] = -_rng.randf_range(1.0, 30.0)
			if i % 5 == 0: body[2] = initial_body[2] * 0.15 # near-ground effect
		# Explicit stopped/low/blended/normal shaft speeds and signed inflow.
		var factors := [0.0, 0.01, 0.04, 0.06, 0.08, 0.12, 0.20, 1.0]
		continuous[0] = nominal * factors[i % factors.size()]
		continuous[1] = _rng.randf_range(-0.035, 0.035)
		continuous[2] = _rng.randf_range(-0.035, 0.035)
		continuous[3] = _rng.randf_range(-1.5, 5.5)
		continuous[4] = _rng.randf_range(-0.2, 0.2)
		continuous[5] = _rng.randf_range(-0.1, 0.1)
		if i % 9 == 0:
			# RK stages are not forcibly unit-normalized by the caller.
			for axis in 4: body[6 + axis] *= 1.00001
		var contact: Dictionary = HeliSkids.evaluate(body, session.aircraft.skids, session.ground_surfaces,
			false, continuous.slice(6) if continuous.size() == 14 else PackedFloat64Array())
		var accepted := _compare_stage(session, body, continuous, time, [start, weather_id, i])
		var group := "helicopter_" + start + "_" + weather_id
		_tally(group, "states")
		_tally(group, "accepted" if accepted else "refused")
		if accepted:
			_tally(group, "trainer" if session.trainer_enabled else "direct")
			_tally(group, "idle_up" if mode else "normal")
			_tally(group, "stopped" if continuous[0] == 0.0 else ("near_stop" if factors[i % factors.size()] < 0.20 else "running"))
			if start == "ground":
				_tally(group, "contact" if contact.get("max_depth_m", 0.0) > 0.0 else "unloaded")


func _check_malformed_stages(session: Node, start: String) -> void:
	var initial_body: PackedFloat64Array = session.sim.state.duplicate()
	var initial_values: PackedFloat64Array = session.sim.continuous.duplicate()
	var saved_trim: Dictionary = session._trim.duplicate(true)
	var saved_inputs: PackedFloat64Array = session.sim.inputs.duplicate()
	var saved_mode: String = session.flight_mode
	session.flight_mode = "normal"
	session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.5])
	# Stay clear of ground for attitude/refusal checks; contact-specific bad
	# memory is still tested individually in the 14-state case below.
	initial_body[2] = -30.0
	var bad_values := initial_values.duplicate()
	bad_values[0] = -0.001
	if _compare_stage(session, initial_body, bad_values, 0.0, [start, "negative_rotor"]):
		_failures.append("negative helicopter rotor speed was not refused")
	bad_values = initial_values.duplicate()
	bad_values[3] = NAN
	if _compare_stage(session, initial_body, bad_values, 0.0, [start, "nan_inflow"]):
		_failures.append("nonfinite helicopter inflow was not refused")
	var bad_body := initial_body.duplicate()
	bad_body[3] = NAN
	if _compare_stage(session, bad_body, initial_values, 0.0, [start, "nan_velocity"]):
		_failures.append("nonfinite helicopter body was not refused")
	bad_body = initial_body.duplicate()
	bad_body[3] = 1e150
	if _compare_stage(session, bad_body, initial_values, 0.0, [start, "overflow_flow"]):
		_failures.append("unbounded helicopter flow was not refused")
	if _compare_stage(session, initial_body, initial_values, -1.0, [start, "invalid_wind_time"]):
		_failures.append("invalid helicopter wind time was not refused")
	session.sim.inputs[0] = 2.0
	if _compare_stage(session, initial_body, initial_values, 0.0, [start, "invalid_stick"]):
		_failures.append("out-of-range helicopter stick was not refused")
	session.sim.inputs[0] = NAN
	if _compare_stage(session, initial_body, initial_values, 0.0, [start, "nan_stick"]):
		_failures.append("nonfinite helicopter stick was not refused")
	session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.5])
	for mode: String in ["", "unconfigured"]:
		session.flight_mode = mode
		if _compare_stage(session, initial_body, initial_values, 0.0, [start, "unsupported_mode", mode]):
			_failures.append("unsupported helicopter mode was not refused")
	session.flight_mode = "normal"
	session._trim = {cyclic_forward_bias_rad = 100.0}
	if _compare_stage(session, initial_body, initial_values, 0.0, [start, "invalid_trim"]):
		_failures.append("out-of-range helicopter trim was not refused")
	session._trim = {cyclic_forward_bias_rad = NAN}
	if _compare_stage(session, initial_body, initial_values, 0.0, [start, "nan_trim"]):
		_failures.append("nonfinite helicopter trim was not refused")
	session._trim = {future_unmodeled_bias = 0.0}
	if _compare_stage(session, initial_body, initial_values, 0.0, [start, "unknown_trim"]):
		_failures.append("unknown helicopter trim was not refused")
	session._trim = saved_trim
	if start == "ground":
		for axis in 8:
			bad_values = initial_values.duplicate()
			bad_values[6 + axis] = NAN
			if _compare_stage(session, initial_body, bad_values, 0.0, [start, "nan_bristle", axis]):
				_failures.append("nonfinite skid bristle was not refused: %d" % axis)
	var q0: float = _from_bits(PackedInt64Array([0x3d719799812dea11]))[0]
	var qnext: float = _from_bits(PackedInt64Array([0x3d719799812dea12]))[0]
	for probe: Dictionary in [{name = "attitude_threshold", q = q0, valid = false},
			{name = "attitude_above_threshold", q = qnext, valid = true}]:
		bad_body = initial_body.duplicate()
		for axis in 4: bad_body[6 + axis] = 0.0
		bad_body[6] = probe.q
		var accepted := _compare_stage(session, bad_body, initial_values, 0.0, [start, probe.name])
		if accepted != probe.valid: _failures.append("helicopter attitude threshold produced unexpected validity: " + str(probe.name))
	session._trim = saved_trim
	session.sim.inputs = saved_inputs
	session.flight_mode = saved_mode


func _check_heli_refusals(session: Node, snapshot: Dictionary, start: String) -> void:
	var bad := snapshot.duplicate()
	bad.unsupported_future_law = true
	if _native.prepare_helicopter(bad).ok:
		_failures.append("unknown helicopter snapshot key admitted")
	var stale: Dictionary = _native.heli_component(session.sim.state, session.sim.continuous, 0.0, _tick(session),
		session.wind_at(0.0, session.sim.state))
	if stale.get("ok", true): _failures.append("failed helicopter prepare retained a usable stale model")
	bad = snapshot.duplicate()
	bad.surfaces = PackedFloat64Array([0.0, 1.0])
	if _native.prepare_helicopter(bad).ok:
		_failures.append("invalid helicopter terrain table admitted")
	var alternate: Dictionary = RotorcraftData.load_file("res://data/aircraft/hx700_electric_3d_experimental.json")
	if alternate.ok:
		bad = snapshot.duplicate()
		bad.context = alternate.context
		bad.skids = alternate.skids
		if _native.prepare_helicopter(bad).ok:
			_failures.append("laboratory-only helicopter body-rate electronics admitted")
	else:
		_failures.append("laboratory-only helicopter fixture did not load for refusal gate")
	if not _native.prepare_helicopter(snapshot).ok:
		_failures.append("helicopter could not be re-prepared after refusal: " + start)
