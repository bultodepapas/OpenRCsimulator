extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const NitroDynamics := preload("res://physics/ground_vehicle/nitro_dynamics.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const VEHICLE_ID := "monster-car-2"
const RUN_TICKS := 480

var errors := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var report := {
		"format": "openrc-nitro-session-replay-evidence v1",
		"vehicle_id": VEHICLE_ID,
		"fixed_hz": Session.FIXED_HZ,
		"requested_run_ticks": RUN_TICKS,
		"complete": false,
		"errors": [],
	}
	var session = Session.new()
	if not session.prepare_default({}, VEHICLE_ID):
		_fail("prepare_default: " + str(session.load_error))
		_finish(report, session)
		return

	var initial_state: PackedFloat64Array = session.state_snapshot()
	var initial_checkpoint: Dictionary = session.checkpoint()
	var checkpoint_json: Variant = JSON.parse_string(JSON.stringify(initial_checkpoint, "", true, true))
	var initial_checkpoint_ok: bool = initial_state.size() == NitroDynamics.STATE_SIZE \
		and initial_checkpoint.get("vehicle_id") == VEHICLE_ID \
		and initial_checkpoint.get("state_layout") == NitroDynamics.STATE_LAYOUT \
		and session.can_restore_checkpoint(checkpoint_json)
	if not initial_checkpoint_ok:
		_fail("tick-zero checkpoint did not validate with the full Nitro state layout")

	var recording_started := session.start_recording()
	var armed := recording_started and session.tick_once(_neutral()) and session.resume()
	var tape := PackedFloat64Array()
	if not armed:
		_fail("recording could not arm on the neutral session tick: " + str(session.load_error))
	else:
		for tick_index in RUN_TICKS:
			var throttle := 0.72 if tick_index < RUN_TICKS / 2 else 0.9
			var steering := 0.08 if tick_index < RUN_TICKS / 2 else -0.08
			var controls := {"throttle": throttle, "steering": steering, "brake": 0.0,
				"reverse": false, "armed": true, "source": "nitro-replay-evidence"}
			if not session.tick_once(controls):
				_fail("simulation stopped at tick %d: %s" % [tick_index, session.load_error])
				break
			tape.append_array(PackedFloat64Array([throttle, steering, 0.0, 0.0]))

	var final_state: PackedFloat64Array = session.state_snapshot()
	var simulation_complete: bool = session.tick == RUN_TICKS and tape.size() == RUN_TICKS * 4 \
		and final_state.size() == NitroDynamics.STATE_SIZE
	if not simulation_complete:
		_fail("recorded run did not complete all fixed 240 Hz ticks")
	if final_state.size() == NitroDynamics.STATE_SIZE:
		if final_state[31] == initial_state[31] or final_state[32] >= initial_state[32] \
				or final_state[32] < 0.0:
			_fail("engine speed or fuel did not evolve within physical state bounds")

	var recording_stopped: bool = session.recording and session.stop_recording()
	var recording_metadata: Dictionary = session._recording_metadata()
	var recording_complete: bool = recording_stopped and session._recording_sample_count() == RUN_TICKS + 1 \
		and int(recording_metadata.get("sample_count", -1)) == RUN_TICKS + 1 \
		and recording_metadata.get("vehicle_id") == VEHICLE_ID \
		and recording_metadata.get("state_layout") == NitroDynamics.STATE_LAYOUT \
		and recording_metadata.get("sample_layout", {}).get("telemetry_offset") \
			== Session.RECORD_STATE_OFFSET + NitroDynamics.STATE_SIZE \
		and recording_metadata.get("sample_layout", {}).get("telemetry_fields", []).has("nitro.engine_rpm") \
		and recording_metadata.get("sample_layout", {}).get("telemetry_fields", []).has("nitro.fuel_kg")
	if not recording_complete:
		_fail("recording did not preserve full state, identity and Nitro telemetry")

	var export_name := "nitro_session_evidence_%d" % Time.get_ticks_usec()
	var exported: Dictionary = session.export_recording(export_name) if recording_stopped else {"ok": false}
	var export_files_valid := false
	var csv_sha256 := ""
	var metadata_sha256 := ""
	if bool(exported.get("ok", false)):
		var csv_path := ProjectSettings.globalize_path(str(exported.csv_path))
		var metadata_path := ProjectSettings.globalize_path(str(exported.metadata_path))
		csv_sha256 = FileAccess.get_sha256(csv_path)
		metadata_sha256 = FileAccess.get_sha256(metadata_path)
		var metadata_file := FileAccess.open(metadata_path, FileAccess.READ)
		var exported_metadata: Variant = JSON.parse_string(metadata_file.get_as_text()) \
			if metadata_file != null else null
		if metadata_file != null:
			metadata_file.close()
		export_files_valid = not csv_sha256.is_empty() and not metadata_sha256.is_empty() \
			and typeof(exported_metadata) == TYPE_DICTIONARY \
			and exported_metadata.get("vehicle_id") == VEHICLE_ID \
			and exported_metadata.get("state_layout") == NitroDynamics.STATE_LAYOUT
	if not export_files_valid:
		_fail("recording export or exported metadata verification failed: " + str(exported.get("error", "")))

	var final_checkpoint: Dictionary = session.checkpoint()
	var checkpoint_restored := session.restore_checkpoint(final_checkpoint) \
		and final_state.to_byte_array() == session.state_snapshot().to_byte_array()
	if not checkpoint_restored:
		_fail("final checkpoint restore changed one or more of the 33 state values")
	var replayed := checkpoint_restored and session.replay(tape)
	var replay_state: PackedFloat64Array = session.state_snapshot()
	var replay_exact: bool = replayed and session.tick == RUN_TICKS \
		and final_state.to_byte_array() == replay_state.to_byte_array()
	if not replay_exact:
		_fail("control tape replay did not reproduce exact full-state bytes: " + str(session.load_error))

	var field_result: Dictionary = FieldLoader.load_from()
	var airfield_session = Session.new()
	var airfield_prepared: bool = bool(field_result.get("ok", false)) \
		and airfield_session.prepare_airfield(field_result, {}, {}, VEHICLE_ID)
	var airfield_checkpoint_ok := false
	var airfield_state_sha256 := ""
	if airfield_prepared:
		var airfield_state: PackedFloat64Array = airfield_session.state_snapshot()
		var airfield_checkpoint: Dictionary = airfield_session.checkpoint()
		var airfield_json: Variant = JSON.parse_string(JSON.stringify(airfield_checkpoint, "", true, true))
		airfield_checkpoint_ok = airfield_state.size() == NitroDynamics.STATE_SIZE \
			and airfield_checkpoint.get("vehicle_id") == VEHICLE_ID \
			and airfield_checkpoint.get("state_layout") == NitroDynamics.STATE_LAYOUT \
			and airfield_session.can_restore_checkpoint(airfield_json) \
			and airfield_session.restore_checkpoint(airfield_json) \
			and airfield_state.to_byte_array() == airfield_session.state_snapshot().to_byte_array()
		airfield_state_sha256 = airfield_session._hash_bytes(airfield_state.to_byte_array())
	if not airfield_prepared or not airfield_checkpoint_ok:
		_fail("airfield preparation or its full-state checkpoint roundtrip failed: "
			+ str(airfield_session.load_error))

	var telemetry: Dictionary = session.telemetry_snapshot()
	var nitro_telemetry: Dictionary = telemetry.get("nitro", {})
	var identities: Dictionary = session.identities_snapshot()
	report.merge({
		"complete": errors.is_empty() and simulation_complete and recording_complete and export_files_valid \
			and checkpoint_restored and replay_exact and airfield_prepared and airfield_checkpoint_ok,
		"tick_count": session.tick,
		"model_identity": identities.get("model", {}),
		"course_identity": identities.get("course", {}),
		"state_size": replay_state.size(),
		"state_layout": NitroDynamics.STATE_LAYOUT,
		"initial_state_sha256": session._hash_bytes(initial_state.to_byte_array()),
		"final_state_sha256": session._hash_bytes(final_state.to_byte_array()),
		"replay_state_sha256": session._hash_bytes(replay_state.to_byte_array()),
		"control_tape_sha256": session._hash_bytes(tape.to_byte_array()),
		"checkpoint_json_roundtrip": initial_checkpoint_ok,
		"final_checkpoint_restore_exact": checkpoint_restored,
		"control_replay_exact": replay_exact,
		"airfield_prepared": airfield_prepared,
		"airfield_checkpoint_json_roundtrip_exact": airfield_checkpoint_ok,
		"airfield_initial_state_sha256": airfield_state_sha256,
		"engine_rpm": float(nitro_telemetry.get("engine_rpm", -1.0)),
		"fuel_kg": float(nitro_telemetry.get("fuel_kg", -1.0)),
		"recording_sample_count": recording_metadata.get("sample_count", 0),
		"recording_run_valid": recording_metadata.get("run_valid", false),
		"recorded_state_sample_width": recording_metadata.get("sample_width", 0),
		"recorded_samples_sha256": recording_metadata.get("recorded_samples_sha256", ""),
		"recording_export": {"csv_path": exported.get("csv_path", ""),
			"metadata_path": exported.get("metadata_path", ""),
			"csv_sha256": csv_sha256, "metadata_sha256": metadata_sha256},
		"solver_identity": session._solver_identity(),
		"errors": Array(errors),
	}, true)
	print("NITRO_SESSION_EVIDENCE=" + JSON.stringify(report, "", true, true))
	airfield_session.free()
	session.free()
	quit(0 if bool(report.complete) else 1)


func _neutral() -> Dictionary:
	return {"throttle": 0.0, "steering": 0.0, "brake": 0.0,
		"reverse": false, "armed": true, "source": "nitro-replay-evidence"}


func _fail(message: String) -> void:
	errors.append(message)


func _finish(report: Dictionary, session: Object) -> void:
	report["errors"] = Array(errors)
	print("NITRO_SESSION_EVIDENCE=" + JSON.stringify(report, "", true, true))
	session.free()
	quit(1)
