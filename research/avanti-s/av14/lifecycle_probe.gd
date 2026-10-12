# AV-17: Avanti S lifecycle and renderer-adapter contracts on the frozen application baseline.
# These are software/model checks; they do not establish landing, restart, or handling acceptance.
extends "../../extra-300/ex06/envelope_probe.gd"

const AVANTI_ID := "sebart-avanti-s-a200-p100rx"
const AVANTI_DATA := "res://data/aircraft/sebart_avanti_s_a200.json"
const Sim := preload("res://sim/simulation.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Commands := preload("res://input/commands.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const AvantiModel := preload("res://aircraft/avanti_s_model.gd")

const REPLAY_TICKS := 240
const GLIDE_SPEED_MPS := 21.0
const TEST_SPEED_MPS := 29.0
const TEST_ALTITUDE_M := 300.0

var _requested_output_path := ""
var _requested_hz := 240


func _initialize() -> void:
	var output_path := ""
	var hz := 240
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_path = arg.trim_prefix("--output=")
		elif arg.begins_with("--hz=") and arg.trim_prefix("--hz=").is_valid_int():
			hz = int(arg.trim_prefix("--hz="))
	if output_path.is_empty() or hz not in [240, 480]:
		printerr("AV-17 lifecycle probe requires --output=<json-path> and --hz=240 or 480")
		quit(2)
		return
	_requested_output_path = output_path
	_requested_hz = hz
	Engine.physics_ticks_per_second = hz
	Callable(self, "_run").call_deferred()


func _run() -> void:
	var output_path := _requested_output_path
	var hz := _requested_hz
	var session := _new_lifecycle_session()
	var report := {
		"schema": "openrc-avanti-lifecycle-probe-v1",
		"probe": "AV-17 FlightSession lifecycle and rendered control-adapter contracts",
		"aircraft_id": AVANTI_ID,
		"tick_hz": hz,
		"dt_s": 1.0 / float(hz),
		"evidence_kind": "software and experimental-model prediction",
		"physical_validation": false,
		"scope": "Native Variant checkpoint restore/replay with separate JSON diagnostics, glide engine-off reset, terminal hull crash hold/restart, unsupported runway/gear/flaps observations, and actual rendered hinges; no ground fixture or landing claim",
		"errors": [],
		"cases": [],
	}
	var setup_error := str(session.get_meta("av17_setup_error", ""))
	if not setup_error.is_empty() or not session.is_flyable() or not session.sim.fault_reason.is_empty():
		report.errors.append(setup_error if not setup_error.is_empty() else
			str(session.pause_reason if not session.pause_reason.is_empty() else session.sim.fault_reason))
		report["completed"] = false
		_write_json(output_path, report)
		session.free()
		quit(1)
		return
	var model: Dictionary = session.aircraft.model
	report["setup"] = {
		"field_id": session.ground_field_id,
		"trim": _trim_snapshot(session.start),
		"gear_capability": str(model.get("capabilities", {}).get("gear", "unspecified")),
		"flap_capability": str(model.get("capabilities", {}).get("flaps", "unspecified")),
		"landing_gear_section_empty": model.get("landing_gear", {}).is_empty(),
		"wheel_count": session.wheel_count(),
		"anchor_count": session.anchor_count(),
	}

	var cases: Array = report["cases"]
	cases.append(_engine_off_glide_reset(session))
	cases.append(_checkpoint_native_replay(session))
	cases.append(_crash_hold_restart(session))
	cases.append(_unsupported_ground_contract(session))
	var render_case := _rendered_adapter_contract(session)
	cases.append(render_case)
	for case: Dictionary in cases:
		if not case.get("ok", false):
			report.errors.append("lifecycle case failed: %s: %s" % [
				str(case.get("id", "?")), str(case.get("error", "one or more recorded assertions failed"))])
	report["completed"] = report.errors.is_empty() and cases.size() == 5
	_write_json(output_path, report)
	print("AV-17 Avanti lifecycle: %d cases, %d errors at %d Hz" % [cases.size(), report.errors.size(), hz])
	session.free()
	quit(0 if report.completed else 1)


func _new_lifecycle_session() -> Node:
	var session := Session.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.setup(AVANTI_DATA, AVANTI_ID)
	root.add_child(session)
	session.start_choice = "airborne"
	var loaded_field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not loaded_field.get("ok", false):
		session.set_meta("av17_setup_error", "default field failed to load")
	elif not session.set_field(loaded_field.get("field", {})):
		session.set_meta("av17_setup_error", "default field surfaces failed: " + str(session.surface_error))
	session.reset()
	return session


func _engine_off_glide_reset(session: Node) -> Dictionary:
	var trim: Dictionary = session.trim_at(GLIDE_SPEED_MPS, "glide")
	if not trim.get("ok", false):
		return _failed_case("engine_off_glide_reset", "glide trim unavailable: " + str(trim.get("message", "")))
	session.set_start_altitude(TEST_ALTITUDE_M)
	session.commands = { "roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0 }
	# Deliberately change the old engine mode; reset must derive the new mode from the selected glide start.
	session.engine_running = true
	session.reset()
	var mode := str(session.start.get("mode", ""))
	var reset_tick: int = session.sim.tick
	var reset_valid: bool = session.is_flyable() and session.sim.fault_reason.is_empty() \
		and Sim.state_is_valid(session.sim.state)
	var engine_off_at_reset: bool = not session.engine_running and int(session.sim.modes[0]) == 0
	var reset_rpm: float = float(session.sim.aux[0]) if session.sim.aux.size() > 0 else NAN
	var state_before_tick: PackedFloat64Array = session.sim.state.duplicate()
	var advanced := _advance_ticks(session, 1, { "roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0 })
	var engine_off_after_tick: bool = not session.engine_running and int(session.sim.modes[0]) == 0
	var rpm_after_tick: float = float(session.sim.aux[0]) if session.sim.aux.size() > 0 else NAN
	var state_moved: bool = _max_state_delta(state_before_tick, session.sim.state) > 0.0
	var ok: bool = reset_valid and reset_tick == 0 and mode == "glide" and engine_off_at_reset \
		and is_finite(reset_rpm) and reset_rpm == 0.0 and advanced.get("ok", false) \
		and engine_off_after_tick and is_finite(rpm_after_tick) and rpm_after_tick == 0.0 \
		and state_moved and Sim.state_is_valid(session.sim.state)
	return {
		"id": "engine_off_glide_reset",
		"available": trim.get("ok", false),
		"complete": advanced.get("ticks", 0) == 1,
		"ok": ok,
		"mode": mode,
		"speed_mps": GLIDE_SPEED_MPS,
		"start_throttle": float(session.start.get("throttle", NAN)),
		"reset_tick": reset_tick,
		"engine_was_forced_on_before_reset": true,
		"engine_off_at_reset": engine_off_at_reset,
		"engine_off_after_tick": engine_off_after_tick,
		"rpm_at_reset": _finite_or_null(reset_rpm),
		"rpm_after_one_tick": _finite_or_null(rpm_after_tick),
		"one_tick_state_changed": state_moved,
		"simulation_fault": str(session.sim.fault_reason),
		"error": "reset did not preserve a finite, engine-off glide start" if not ok else "",
	}


func _checkpoint_native_replay(session: Node) -> Dictionary:
	var trim: Dictionary = session.trim_at(TEST_SPEED_MPS, "level")
	if not trim.get("ok", false):
		return _failed_case("checkpoint_native_replay_240", "level trim unavailable: " + str(trim.get("message", "")))
	session.set_start_altitude(TEST_ALTITUDE_M)
	session.reset()
	if not session.is_flyable() or not session.sim.fault_reason.is_empty():
		return _failed_case("checkpoint_native_replay_240", "session reset failed before checkpoint")
	session.commands = _replay_commands(session)
	session.sim.inputs = session._inputs()
	session.sim.set_paused(false)
	var checkpoint: Dictionary = session.checkpoint()
	if checkpoint.is_empty():
		return _failed_case("checkpoint_native_replay_240", "session refused the reset-boundary checkpoint")
	# app/sim/simulation.gd documents var_to_bytes/bytes_to_var as the float64-preserving checkpoint contract; JSON/CSV are diagnostics.
	var checkpoint_bytes: PackedByteArray = var_to_bytes(checkpoint)
	var native_restored_value: Variant = bytes_to_var(checkpoint_bytes)
	if not native_restored_value is Dictionary:
		return _failed_case("checkpoint_native_replay_240", "native Variant checkpoint bytes did not decode into an object")
	var native_checkpoint: Dictionary = native_restored_value
	var native_roundtrip_bytes: PackedByteArray = var_to_bytes(native_checkpoint)
	var native_roundtrip_exact: bool = native_roundtrip_bytes == checkpoint_bytes
	if not native_roundtrip_exact:
		return _failed_case("checkpoint_native_replay_240", "typed Variant checkpoint bytes changed during native round-trip")
	var checkpoint_json: String = JSON.stringify(checkpoint, "", true, true)
	var json_diagnostic: Dictionary = _checkpoint_json_diagnostic(checkpoint, checkpoint_json)
	var dt: float = session.sim.dt()
	var first_branch := _advance_ticks(session, REPLAY_TICKS, _replay_commands(session))
	if not first_branch.get("ok", false):
		return _failed_case("checkpoint_native_replay_240", "first 240-tick session branch failed: " + str(first_branch.get("error", "")))
	var expected_checkpoint: Dictionary = session.checkpoint()
	if expected_checkpoint.is_empty():
		return _failed_case("checkpoint_native_replay_240", "session refused the first branch's final checkpoint")
	var expected_bytes: PackedByteArray = var_to_bytes(expected_checkpoint)
	var expected_state: PackedFloat64Array = session.sim.state.duplicate()
	if not session.restore_checkpoint(native_checkpoint):
		return _failed_case("checkpoint_native_replay_240", "session refused its native-byte-round-tripped checkpoint")
	session.commands = _replay_commands(session)
	session.sim.set_paused(false)
	var replay_branch := _advance_ticks(session, REPLAY_TICKS, _replay_commands(session))
	if not replay_branch.get("ok", false):
		return _failed_case("checkpoint_native_replay_240", "replayed 240-tick session branch failed: " + str(replay_branch.get("error", "")))
	var actual_checkpoint: Dictionary = session.checkpoint()
	var actual_bytes: PackedByteArray = var_to_bytes(actual_checkpoint) if not actual_checkpoint.is_empty() else PackedByteArray()
	var replay_exact: bool = actual_bytes == expected_bytes
	var state_delta: float = _max_state_delta(expected_state, session.sim.state)
	var ok: bool = native_roundtrip_exact and replay_exact and state_delta == 0.0 \
		and session.sim.tick == REPLAY_TICKS and session.sim.fault_reason.is_empty() and session.crash.is_empty()
	return {
		"id": "checkpoint_native_replay_240",
		"available": true,
		"complete": first_branch.get("ticks", 0) == REPLAY_TICKS and replay_branch.get("ticks", 0) == REPLAY_TICKS,
		"ok": ok,
		"checkpoint_format": str(checkpoint.get("format", "")),
		"checkpoint_transport": "var_to_bytes/bytes_to_var; app/sim/simulation.gd documents JSON/CSV as diagnostics because native Variant bytes preserve float64 bits",
		"native_checkpoint_byte_roundtrip_exact": native_roundtrip_exact,
		"native_checkpoint_replay_exact": replay_exact,
		"native_checkpoint_bytes_sha256": _sha256_bytes(checkpoint_bytes),
		"checkpoint_json_diagnostic_sha256": _sha256(checkpoint_json),
		"checkpoint_json_diagnostic": json_diagnostic,
		"checkpoint_replay_ticks": REPLAY_TICKS,
		"checkpoint_replay_s": REPLAY_TICKS * dt,
		"final_checkpoint_sha256_first_branch": _sha256_bytes(expected_bytes),
		"final_checkpoint_sha256_replay": _sha256_bytes(actual_bytes),
		"final_state_max_abs_delta": state_delta,
		"simulation_tick": session.sim.tick,
		"simulation_fault": str(session.sim.fault_reason),
		"error": "native checkpoint round-trip did not reproduce the exact 240-tick session boundary" if not ok else "",
	}


func _checkpoint_json_diagnostic(checkpoint: Dictionary, serialized: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(serialized)
	if not parsed is Dictionary:
		return { "available": false, "exact_numeric_values": false, "error": "diagnostic JSON did not parse into an object" }
	var source_simulation_value: Variant = checkpoint.get("simulation", null)
	var parsed_simulation_value: Variant = parsed.get("simulation", null)
	if not source_simulation_value is Dictionary or not parsed_simulation_value is Dictionary:
		return { "available": false, "exact_numeric_values": false, "error": "diagnostic JSON is missing the simulation object" }
	var source_simulation: Dictionary = source_simulation_value
	var parsed_simulation: Dictionary = parsed_simulation_value
	var field_max_abs_delta: Dictionary = {}
	var field_exact: Dictionary = {}
	var type_mismatches: Array[String] = []
	var all_numeric_exact := true
	var maximum_abs_delta := 0.0
	for key: String in ["dt", "mass", "gravity", "tick", "stop_at_tick"]:
		var source_value: Variant = source_simulation.get(key, null)
		var parsed_value: Variant = parsed_simulation.get(key, null)
		if typeof(source_value) not in [TYPE_INT, TYPE_FLOAT] or typeof(parsed_value) not in [TYPE_INT, TYPE_FLOAT]:
			return { "available": false, "exact_numeric_values": false, "error": "diagnostic numeric scalar '%s' is missing or nonnumeric" % key }
		var delta := absf(float(source_value) - float(parsed_value))
		field_max_abs_delta[key] = delta
		maximum_abs_delta = maxf(maximum_abs_delta, delta)
		var value_exact := float(source_value) == float(parsed_value)
		if typeof(source_value) == TYPE_FLOAT and typeof(parsed_value) == TYPE_FLOAT:
			value_exact = _float64_bits(float(source_value)) == _float64_bits(float(parsed_value))
		field_exact[key] = value_exact
		all_numeric_exact = all_numeric_exact and value_exact
		if typeof(source_value) != typeof(parsed_value):
			type_mismatches.append("simulation.%s: %s -> %s" % [key, type_string(typeof(source_value)), type_string(typeof(parsed_value))])
	var float_array_fields: Array[String] = ["state", "previous", "aux", "inputs", "last_loads", "inertia"]
	if source_simulation.has("continuous"):
		float_array_fields.append("continuous")
	for key: String in float_array_fields:
		var source_value: Variant = source_simulation.get(key, null)
		var parsed_value: Variant = parsed_simulation.get(key, null)
		if not source_value is PackedFloat64Array or not parsed_value is Array or source_value.size() != parsed_value.size():
			return { "available": false, "exact_numeric_values": false, "error": "diagnostic array '%s' changed shape or type unexpectedly" % key }
		if typeof(source_value) != typeof(parsed_value):
			type_mismatches.append("simulation.%s: %s -> %s" % [key, type_string(typeof(source_value)), type_string(typeof(parsed_value))])
		var field_delta := 0.0
		var field_is_exact := true
		for i in source_value.size():
			var parsed_item: Variant = parsed_value[i]
			if typeof(parsed_item) not in [TYPE_INT, TYPE_FLOAT]:
				return { "available": false, "exact_numeric_values": false, "error": "diagnostic array '%s' item %d is nonnumeric" % [key, i] }
			var item_delta := absf(source_value[i] - float(parsed_item))
			field_delta = maxf(field_delta, item_delta)
			var item_exact := _float64_bits(source_value[i]) == _float64_bits(float(parsed_item))
			field_is_exact = field_is_exact and item_exact
			all_numeric_exact = all_numeric_exact and item_exact
		field_max_abs_delta[key] = field_delta
		field_exact[key] = field_is_exact
		maximum_abs_delta = maxf(maximum_abs_delta, field_delta)
	var source_modes: Variant = source_simulation.get("modes", null)
	var parsed_modes: Variant = parsed_simulation.get("modes", null)
	if not source_modes is PackedInt64Array or not parsed_modes is Array or source_modes.size() != parsed_modes.size():
		return { "available": false, "exact_numeric_values": false, "error": "diagnostic mode array changed shape or type unexpectedly" }
	if typeof(source_modes) != typeof(parsed_modes):
		type_mismatches.append("simulation.modes: %s -> %s" % [type_string(typeof(source_modes)), type_string(typeof(parsed_modes))])
	var modes_delta := 0.0
	var modes_exact := true
	for i in source_modes.size():
		var parsed_mode: Variant = parsed_modes[i]
		if typeof(parsed_mode) not in [TYPE_INT, TYPE_FLOAT]:
			return { "available": false, "exact_numeric_values": false, "error": "diagnostic mode item %d is nonnumeric" % i }
		var item_delta := absf(float(source_modes[i]) - float(parsed_mode))
		modes_delta = maxf(modes_delta, item_delta)
		var item_exact := float(source_modes[i]) == float(parsed_mode)
		modes_exact = modes_exact and item_exact
		all_numeric_exact = all_numeric_exact and item_exact
	field_max_abs_delta["modes"] = modes_delta
	field_exact["modes"] = modes_exact
	maximum_abs_delta = maxf(maximum_abs_delta, modes_delta)
	var mode_type_exact := typeof(source_modes) == typeof(parsed_modes)
	return {
		"available": true,
		"authoritative_format": false,
		"contract": "Simulation.checkpoint() documents var_to_bytes/bytes_to_var as the float64-preserving format; JSON/CSV are diagnostics.",
		"canonical_json_text_roundtrip_exact": JSON.stringify(parsed, "", true, true) == serialized,
		"numeric_values_exact": all_numeric_exact,
		"typed_numeric_checkpoint_exact": all_numeric_exact and type_mismatches.is_empty() and mode_type_exact,
		"type_mismatches": type_mismatches,
		"max_abs_numeric_delta": maximum_abs_delta,
		"max_abs_numeric_delta_by_field": field_max_abs_delta,
		"numeric_exact_by_field": field_exact,
	}


func _float64_bits(value: float) -> String:
	return PackedFloat64Array([value]).to_byte_array().hex_encode()


func _crash_hold_restart(session: Node) -> Dictionary:
	var trim: Dictionary = session.trim_at(TEST_SPEED_MPS, "level")
	if not trim.get("ok", false):
		return _failed_case("crash_hold_restart", "level trim unavailable: " + str(trim.get("message", "")))
	session.set_start_altitude(TEST_ALTITUDE_M)
	session.reset()
	if not session.is_flyable() or not session.sim.fault_reason.is_empty():
		return _failed_case("crash_hold_restart", "session reset failed before hull-contact fixture")
	var restart_checkpoint: Dictionary = session.sim.checkpoint()
	var restart_bytes: PackedByteArray = var_to_bytes(restart_checkpoint)
	var impact_state: PackedFloat64Array = session.sim.state.duplicate()
	var contact_depth := NAN
	for depth: float in [0.0, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0]:
		impact_state[RB.POS + 2] = depth
		if session.touches_ground(impact_state):
			contact_depth = depth
			break
	if not is_finite(contact_depth):
		return _failed_case("crash_hold_restart", "could not construct a documented Avanti hull-contact crash state")
	session.sim.continuous = session._settled_continuous(impact_state, session.sim.aux)
	if not session.sim.reset(impact_state):
		return _failed_case("crash_hold_restart", "hull-contact state reset failed: " + str(session.sim.fault_reason))
	session.sim.set_paused(false)
	session.crash_auto_restart = true
	var dt: float = session.sim.dt()
	session._physics_process(dt)
	var detected: bool = not session.crash.is_empty()
	var reason := str(session.pause_reason)
	var expected_ticks := roundi(Session.CRASH_HOLD_S / dt)
	var countdown_at_detection: int = int(session.crash.get("ticks_left", 0)) if detected else 0
	var ticks_waited := 0
	while not session.crash.is_empty() and ticks_waited < expected_ticks:
		session._physics_process(dt)
		ticks_waited += 1
	var restarted: bool = session.crash.is_empty() and session.is_flyable() and session.sim.fault_reason.is_empty()
	var restart_bytes_after: PackedByteArray = var_to_bytes(session.sim.checkpoint()) if restarted else PackedByteArray()
	var restart_exact: bool = restarted and restart_bytes_after == restart_bytes
	var state_delta: float = _max_state_delta(session.start.state, session.sim.state) if restarted else INF
	var held_s: float = ticks_waited * dt
	var ok: bool = detected and countdown_at_detection == expected_ticks and ticks_waited == expected_ticks \
		and is_equal_approx(held_s, Session.CRASH_HOLD_S) and restarted and session.sim.tick == 0 \
		and restart_exact and state_delta == 0.0
	session.crash_auto_restart = false
	return {
		"id": "crash_hold_restart",
		"available": true,
		"complete": detected and (ticks_waited == expected_ticks or restarted),
		"ok": ok,
		"fixture": "valid trimmed start repositioned only in NED down until FlightSession.touches_ground() accepted the gear-up crash_hull; no landing gear or runway fixture",
		"hull_contact_depth_m": contact_depth,
		"crash_detected": detected,
		"crash_reason": reason,
		"countdown_ticks_at_detection": countdown_at_detection,
		"countdown_ticks_expected": expected_ticks,
		"countdown_ticks_waited": ticks_waited,
		"countdown_s": held_s,
		"restart_tick": session.sim.tick,
		"restart_state_max_abs_delta": _finite_or_null(state_delta),
		"restart_full_simulation_checkpoint_exact": restart_exact,
		"simulation_fault": str(session.sim.fault_reason),
		"error": "hull crash did not hold for exactly 1.5 s of callbacks and restart at the exact trimmed boundary" if not ok else "",
	}


func _unsupported_ground_contract(session: Node) -> Dictionary:
	var trim: Dictionary = session.trim_at(TEST_SPEED_MPS, "level")
	if not trim.get("ok", false):
		return _failed_case("unsupported_ground_contract", "level trim unavailable: " + str(trim.get("message", "")))
	session.set_start_altitude(TEST_ALTITUDE_M)
	session.start_choice = "airborne"
	session.reset()
	var model: Dictionary = session.aircraft.model
	var gear_data: Dictionary = model.get("landing_gear", {})
	var state_valid: bool = Sim.state_is_valid(session.sim.state)
	var compressions: PackedFloat64Array = session.gear_compressions(session.sim.state)
	var no_gear: bool = gear_data.is_empty() and session.wheel_count() == 0 and session.anchor_count() == 0 \
		and compressions.is_empty() and not session.gear_collapsed(session.sim.state)
	var capabilities: Dictionary = model.get("capabilities", {})
	var flap_mode := str(capabilities.get("flaps", "unspecified"))
	var simulated_surfaces: Dictionary = session.surfaces()
	var surfaced_channels: Dictionary = Commands.surface_deflections_deg(simulated_surfaces, session.throws_deg())
	var no_flight_flap_channel: bool = not simulated_surfaces.has("flap") and not surfaced_channels.has("flap") \
		and flap_mode == "not_simulated"
	var expected_state: PackedFloat64Array = session.start.state.duplicate()
	var helper_result: bool = session.reset_on_runway(0.0, 0.0, 0.0)
	var helper_fallback_delta: float = _max_state_delta(expected_state, session.sim.state)
	var helper_refused: bool = not helper_result and session.start_choice == "airborne" \
		and session.is_flyable() and session.sim.fault_reason.is_empty() and helper_fallback_delta == 0.0
	session.start_choice = "runway"
	session.reset()
	var refusal_reason := str(session.start_error if not session.start_error.is_empty() else session.sim.fault_reason)
	var selected_runway_refused: bool = not session.is_flyable() and session.sim.paused \
		and not session.sim.fault_reason.is_empty() and refusal_reason.contains("runway start is supported only")
	session.start_choice = "airborne"
	session.reset()
	var airborne_recovered: bool = session.is_flyable() and session.sim.fault_reason.is_empty() \
		and Sim.state_is_valid(session.sim.state) and session.sim.tick == 0
	var ok: bool = state_valid and no_gear and no_flight_flap_channel and helper_refused \
		and selected_runway_refused and airborne_recovered
	return {
		"id": "unsupported_ground_contract",
		"available": true,
		"complete": true,
		"ok": ok,
		"gear_capability": str(capabilities.get("gear", "unspecified")),
		"landing_gear_section_empty": gear_data.is_empty(),
		"wheel_count": session.wheel_count(),
		"anchor_count": session.anchor_count(),
		"gear_compressions_count": compressions.size(),
		"gear_collapsed": session.gear_collapsed(session.sim.state),
		"gear_claim": "No Avanti runway, taxi, takeoff, or landing mechanics are exercised; zero wheel contacts/anchors are confirmed from the loaded model and session API.",
		"flap_capability": flap_mode,
		"session_surface_channels": simulated_surfaces.keys(),
		"command_deflection_channels": surfaced_channels.keys(),
		"flap_claim": "FlightSession exposes no flap command and the loaded aircraft declares flaps not_simulated; visual flap hinges/setter are not evidence of simulated flap behavior.",
		"runway_helper_returned_true": helper_result,
		"runway_helper_refused_and_restored_airborne_start": helper_refused,
		"runway_helper_fallback_state_max_abs_delta": helper_fallback_delta,
		"persistent_runway_refusal_reason": refusal_reason,
		"persistent_runway_selection_refused": selected_runway_refused,
		"airborne_reset_recovered": airborne_recovered,
		"error": "unsupported runway/gear/flap behavior did not match the explicit Avanti contract" if not ok else "",
	}


func _rendered_adapter_contract(session: Node) -> Dictionary:
	var trim: Dictionary = session.trim_at(TEST_SPEED_MPS, "level")
	if not trim.get("ok", false):
		return _failed_case("rendered_adapter_differential_hinges", "level trim unavailable: " + str(trim.get("message", "")))
	session.set_start_altitude(TEST_ALTITUDE_M)
	session.start_choice = "airborne"
	session.reset()
	if not session.is_flyable() or not session.sim.fault_reason.is_empty():
		return _failed_case("rendered_adapter_differential_hinges", "session reset failed before rendered controls")
	var airplane: Dictionary = AirplaneBuilder.build(AVANTI_ID)
	if airplane.is_empty() or str(airplane.get("aircraft_id", "")) != AVANTI_ID:
		return _failed_case("rendered_adapter_differential_hinges", "AirplaneBuilder did not return the Avanti adapter")
	root.add_child(airplane.root)
	var hinge_names := ["aileron_right", "aileron_left", "elevator_left", "elevator_right", "rudder", "flap_left", "flap_right"]
	var missing_hinges: Array[String] = []
	for name: String in hinge_names:
		if not airplane.hinges.has(name):
			missing_hinges.append(name)
	if not missing_hinges.is_empty():
		airplane.root.free()
		return _failed_case("rendered_adapter_differential_hinges", "renderer adapter lacks hinges: " + str(missing_hinges))
	var baseline_surfaces: Dictionary = session.surfaces().duplicate(true)
	var baseline_positions: Dictionary = _hinge_positions(airplane, hinge_names)
	AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations(baseline_surfaces, session.throws_deg()))
	baseline_positions = _hinge_positions(airplane, hinge_names)
	var pulse_ticks := maxi(1, roundi(0.24 / session.sim.dt()))
	var positive_advance := _advance_ticks(session, pulse_ticks,
		{ "roll": 1.0, "pitch": 0.5, "yaw": 0.5, "throttle": float(session.start.throttle) })
	var positive_surfaces: Dictionary = session.surfaces().duplicate(true)
	var positive_deflections: Dictionary = Commands.surface_deflections_deg(positive_surfaces, session.throws_deg())
	AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations(positive_surfaces, session.throws_deg()))
	var positive_positions: Dictionary = _hinge_positions(airplane, hinge_names)
	var positive_right_up: bool = float(positive_deflections.get("aileron_right", 0.0)) > 0.0 \
		and _point_delta(positive_positions, baseline_positions, "aileron_right").y > 0.0
	var positive_left_down: bool = float(positive_deflections.get("aileron_left", 0.0)) < 0.0 \
		and _point_delta(positive_positions, baseline_positions, "aileron_left").y < 0.0
	var positive_differential: bool = absf(float(positive_deflections.get("aileron_right", 0.0))) \
		> absf(float(positive_deflections.get("aileron_left", 0.0)))
	var positive_elevator: bool = float(positive_deflections.get("elevator", 0.0)) > 0.0 \
		and _point_delta(positive_positions, baseline_positions, "elevator_left").y > 0.0 \
		and _point_delta(positive_positions, baseline_positions, "elevator_right").y > 0.0
	var positive_rudder: bool = float(positive_deflections.get("rudder", 0.0)) > 0.0 \
		and _point_delta(positive_positions, baseline_positions, "rudder").x > 0.0
	var positive_flaps_rest: bool = _max_point_delta(positive_positions, baseline_positions, ["flap_left", "flap_right"]) <= 1e-7
	var positive_return := _neutral_return(session, baseline_surfaces, 0.5)
	AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations(session.surfaces(), session.throws_deg()))
	var positive_neutral_position_delta := _max_point_delta(_hinge_positions(airplane, hinge_names), baseline_positions, hinge_names)
	var negative_advance := _advance_ticks(session, pulse_ticks,
		{ "roll": -1.0, "pitch": 0.0, "yaw": 0.0, "throttle": float(session.start.throttle) })
	var negative_surfaces: Dictionary = session.surfaces().duplicate(true)
	var negative_deflections: Dictionary = Commands.surface_deflections_deg(negative_surfaces, session.throws_deg())
	AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations(negative_surfaces, session.throws_deg()))
	var negative_positions: Dictionary = _hinge_positions(airplane, hinge_names)
	var negative_left_up: bool = float(negative_deflections.get("aileron_left", 0.0)) > 0.0 \
		and _point_delta(negative_positions, baseline_positions, "aileron_left").y > 0.0
	var negative_right_down: bool = float(negative_deflections.get("aileron_right", 0.0)) < 0.0 \
		and _point_delta(negative_positions, baseline_positions, "aileron_right").y < 0.0
	var negative_differential: bool = absf(float(negative_deflections.get("aileron_left", 0.0))) \
		> absf(float(negative_deflections.get("aileron_right", 0.0)))
	var negative_flaps_rest: bool = _max_point_delta(negative_positions, baseline_positions, ["flap_left", "flap_right"]) <= 1e-7
	var negative_return := _neutral_return(session, baseline_surfaces, 0.5)
	AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations(session.surfaces(), session.throws_deg()))
	var final_neutral_positions: Dictionary = _hinge_positions(airplane, hinge_names)
	var final_neutral_position_delta: float = _max_point_delta(final_neutral_positions, baseline_positions, hinge_names)
	var no_crash_or_fault: bool = session.crash.is_empty() and session.sim.fault_reason.is_empty()
	var ok: bool = positive_advance.get("ok", false) and negative_advance.get("ok", false) \
		and positive_right_up and positive_left_down and positive_differential and positive_elevator and positive_rudder \
		and positive_flaps_rest and positive_return.get("ok", false) and positive_neutral_position_delta <= 1e-6 \
		and negative_left_up and negative_right_down and negative_differential and negative_flaps_rest \
		and negative_return.get("ok", false) and final_neutral_position_delta <= 1e-6 and no_crash_or_fault
	var summary := {
		"id": "rendered_adapter_differential_hinges",
		"available": true,
		"complete": positive_advance.get("ticks", 0) == pulse_ticks and negative_advance.get("ticks", 0) == pulse_ticks,
		"ok": ok,
		"adapter": "res://render/airplane.gd AirplaneBuilder.build/apply_surfaces with FlightSession servo outputs and Commands.hinge_rotations",
		"aircraft_id": str(airplane.get("aircraft_id", "")),
		"positive_actual_servo_surfaces": positive_surfaces,
		"positive_surface_deflections_deg": positive_deflections,
		"positive_roll_right_up": positive_right_up,
		"positive_roll_left_down": positive_left_down,
		"positive_roll_differential_up_exceeds_down": positive_differential,
		"positive_elevator_both_halves_up": positive_elevator,
		"positive_rudder_trailing_edge_right": positive_rudder,
		"positive_pulse_flaps_remained_at_rest": positive_flaps_rest,
		"positive_neutral_return": positive_return,
		"positive_neutral_witness_max_delta_m": positive_neutral_position_delta,
		"negative_actual_servo_surfaces": negative_surfaces,
		"negative_surface_deflections_deg": negative_deflections,
		"negative_roll_left_up": negative_left_up,
		"negative_roll_right_down": negative_right_down,
		"negative_roll_differential_up_exceeds_down": negative_differential,
		"negative_pulse_flaps_remained_at_rest": negative_flaps_rest,
		"negative_neutral_return": negative_return,
		"final_neutral_witness_max_delta_m": final_neutral_position_delta,
		"no_crash_or_fault": no_crash_or_fault,
		"error": "rendered hinge signs/differential, flap isolation, or neutral return did not match actual Avanti adapter outputs" if not ok else "",
	}
	airplane.root.free()
	return summary


func _neutral_return(session: Node, target_surfaces: Dictionary, duration: float) -> Dictionary:
	var ticks := maxi(1, roundi(duration / session.sim.dt()))
	var advance := _advance_ticks(session, ticks, {
		"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": float(session.start.throttle),	})
	var current: Dictionary = session.surfaces()
	var delta := 0.0
	for axis: String in ["roll", "pitch", "yaw"]:
		delta = maxf(delta, absf(float(current.get(axis, 0.0)) - float(target_surfaces.get(axis, 0.0))))
	return { "ok": advance.get("ok", false) and delta <= 1e-8,
		"ticks": advance.get("ticks", 0), "max_normalized_surface_delta": delta,
		"target_actual_surfaces": target_surfaces.duplicate(true), "returned_actual_surfaces": current }


func _hinge_positions(airplane: Dictionary, names: Array) -> Dictionary:
	var out := {}
	for name: String in names:
		if airplane.hinges.has(name):
			var hinge: Dictionary = airplane.hinges[name]
			out[name] = hinge.node.to_global(hinge.witness)
	return out


func _point_delta(current: Dictionary, baseline: Dictionary, name: String) -> Vector3:
	return current[name] - baseline[name] if current.has(name) and baseline.has(name) else Vector3.ZERO


func _max_point_delta(current: Dictionary, baseline: Dictionary, names: Array) -> float:
	var peak := 0.0
	for name: String in names:
		peak = maxf(peak, _point_delta(current, baseline, name).length())
	return peak


func _advance_ticks(session: Node, ticks: int, controls: Dictionary) -> Dictionary:
	var completed_ticks := 0
	var error_text := ""
	var throttle := clampf(float(controls.get("throttle", 0.0)), 0.0, 1.0)
	var sticks := {
		"roll": clampf(float(controls.get("roll", 0.0)), -1.0, 1.0),
		"pitch": clampf(float(controls.get("pitch", 0.0)), -1.0, 1.0),
		"yaw": clampf(float(controls.get("yaw", 0.0)), -1.0, 1.0),
		"throttle": throttle,
	}
	var dt: float = session.sim.dt()
	for _i in ticks:
		session.commands = sticks.duplicate(true)
		session.sim.inputs = session._inputs()
		session._physics_process(dt)
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
			error_text = str(session.pause_reason if not session.pause_reason.is_empty() else session.sim.fault_reason)
			break
		if session.sim.paused:
			error_text = "session paused before requested lifecycle tick"
			break
		var previous_tick: int = session.sim.tick
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			error_text = str(session.sim.fault_reason)
			break
		if session.sim.tick != previous_tick + 1 or not Sim.state_is_valid(session.sim.state):
			error_text = "lifecycle simulation did not commit one finite session tick"
			break
		completed_ticks += 1
	if error_text.is_empty() and session.crash.is_empty() and session.sim.fault_reason.is_empty() and not session.sim.paused:
		# Inspect the final committed state for contact without advancing a tick or crash-hold callback.
		session._physics_process(0.0)
		if not session.crash.is_empty():
			error_text = "final session callback detected hull contact after the requested ticks"
		elif not session.sim.fault_reason.is_empty():
			error_text = str(session.sim.fault_reason)
	return { "ok": error_text.is_empty() and completed_ticks == ticks,
		"ticks": completed_ticks, "requested_ticks": ticks, "error": error_text }


func _replay_commands(session: Node) -> Dictionary:
	return {
		"roll": 0.1,
		"pitch": -0.05,
		"yaw": 0.05,
		"throttle": minf(float(session.start.throttle) + 0.05, 1.0),
	}


func _max_state_delta(left: PackedFloat64Array, right: PackedFloat64Array) -> float:
	if left.size() != right.size():
		return INF
	var largest := 0.0
	for i in left.size():
		largest = maxf(largest, absf(left[i] - right[i]))
	return largest


func _failed_case(case_id: String, error_text: String) -> Dictionary:
	return { "id": case_id, "available": false, "complete": false, "ok": false, "error": error_text }


func _sha256(value: String) -> String:
	return _sha256_bytes(value.to_utf8_buffer())


func _sha256_bytes(value: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value)
	return context.finish().hex_encode()
