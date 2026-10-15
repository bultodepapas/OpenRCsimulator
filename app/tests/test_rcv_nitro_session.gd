extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const VehicleData := preload("res://physics/ground_vehicle/vehicle_data.gd")
const NitroDynamics := preload("res://physics/ground_vehicle/nitro_dynamics.gd")
const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const AirfieldCourse := preload("res://physics/ground_vehicle/airfield_course.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_bisonte_compatibility()
	_test_nitro_checkpoint_recording_and_replay()
	_test_nitro_zero_gravity_experiment_reset()
	_test_nitro_airfield_prepare()
	print("RCV Nitro session: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("FAIL: " + label)


func _neutral() -> Dictionary:
	return {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false,
		"source": "keyboard", "armed": true}


func _test_bisonte_compatibility() -> void:
	var bisonte = Session.new()
	var prepared: bool = bisonte.prepare_default()
	_check("existing no-argument prepare_default still selects Bisonte", prepared
		and str(bisonte.identities_snapshot().get("vehicle_id", "")) == "mt8-bisonte"
		and str(bisonte.model_snapshot().get("drive_configuration", "")) == "electric_4wd")
	if prepared:
		var state: PackedFloat64Array = bisonte.state_snapshot()
		var checkpoint: Dictionary = bisonte.checkpoint()
		_check("Bisonte remains a 31-value state with its original layout",
			state.size() == 31 and checkpoint.get("state_layout", []).size() == 31)
		_check("Bisonte checkpoint restores through its original session path",
			bisonte.can_restore_checkpoint(checkpoint) and bisonte.restore_checkpoint(checkpoint)
			and state.to_byte_array() == bisonte.state_snapshot().to_byte_array())
	var unknown = Session.new()
	_check("unknown vehicle IDs fail instead of falling back to Bisonte",
		not unknown.prepare_default({}, "free-download-car") and not unknown.prepared)
	unknown.free()
	bisonte.free()


func _test_nitro_checkpoint_recording_and_replay() -> void:
	var session = Session.new()
	var prepared: bool = session.prepare_default({}, "monster-car-2")
	if not prepared:
		print("Nitro default preparation error: ", session.load_error)
	_check("Monster Car 2 loads as a separate nitro session", prepared
		and str(session.identities_snapshot().get("vehicle_id", "")) == "monster-car-2"
		and str(session.model_snapshot().get("drive_configuration", "")) == "nitro_4wd")
	if not prepared:
		session.free()
		return
	var initial_state: PackedFloat64Array = session.state_snapshot()
	var model: Dictionary = session.model_snapshot()
	_check("Nitro state appends idle engine speed and full fuel at float64 precision",
		initial_state.size() == NitroDynamics.STATE_SIZE
		and initial_state[31] == float(model.powertrain.engine_idle_speed_rad_s)
		and initial_state[32] == float(model.powertrain.initial_fuel_mass_kg))
	var identity: Dictionary = session._solver_identity()
	_check("solver identity names the Nitro composite adapter and pins its implementation",
		str(identity.get("solver_version", "")).begins_with(NitroDynamics.SOLVER_VERSION)
		and str(identity.get("backend_identity", {}).get("backend_version", "")).begins_with(
			NitroDynamics.BACKEND_VERSION + "+")
		and str(identity.get("integration_artifact", {}).get("sha256", "")).length() == 64)

	var initial_checkpoint: Dictionary = session.checkpoint()
	var json_checkpoint: Variant = JSON.parse_string(JSON.stringify(initial_checkpoint, "", true, true))
	_check("Nitro checkpoint records the model ID and all 33 state fields",
		initial_checkpoint.get("vehicle_id") == "monster-car-2"
		and initial_checkpoint.get("state_layout") == NitroDynamics.STATE_LAYOUT
		and initial_checkpoint.get("state", []).size() == NitroDynamics.STATE_SIZE
		and session.can_restore_checkpoint(json_checkpoint))
	_check("Nitro checkpoint roundtrip preserves engine and fuel bytes",
		session.restore_checkpoint(json_checkpoint)
		and initial_state.to_byte_array() == session.state_snapshot().to_byte_array())

	var bisonte = Session.new()
	var bisonte_prepared: bool = bisonte.prepare_default()
	var bisonte_state: PackedFloat64Array = bisonte.state_snapshot()
	_check("Nitro checkpoints cannot restore into Bisonte", bisonte_prepared
		and not bisonte.can_restore_checkpoint(initial_checkpoint)
		and not bisonte.restore_checkpoint(initial_checkpoint)
		and bisonte_state.to_byte_array() == bisonte.state_snapshot().to_byte_array())
	bisonte.free()

	var misidentified: Dictionary = initial_checkpoint.duplicate(true)
	misidentified["vehicle_id"] = "mt8-bisonte"
	misidentified["checkpoint_sha256"] = session._checkpoint_hash(misidentified)
	_check("self-hashed cross-vehicle ID edits remain invalid",
		not session.can_restore_checkpoint(misidentified)
		and initial_state.to_byte_array() == session.state_snapshot().to_byte_array())

	var invalid_fuel: Dictionary = initial_checkpoint.duplicate(true)
	var invalid_state: PackedFloat64Array = session._decode_float64_blob(
		invalid_fuel.get("state_f64_base64", ""), NitroDynamics.STATE_SIZE)
	invalid_state[32] = -0.01
	var invalid_bytes := invalid_state.to_byte_array()
	invalid_fuel["state_f64_base64"] = Marshalls.raw_to_base64(invalid_bytes)
	invalid_fuel["state_sha256"] = session._hash_bytes(invalid_bytes)
	invalid_fuel["state"] = _float_array(invalid_state)
	invalid_fuel["checkpoint_sha256"] = session._checkpoint_hash(invalid_fuel)
	_check("invalid negative fuel is rejected even after all checkpoint hashes are recomputed",
		not session.can_restore_checkpoint(invalid_fuel)
		and initial_state.to_byte_array() == session.state_snapshot().to_byte_array())

	_check("Nitro recording starts with a complete engine and fuel sample", session.start_recording()
		and session._recording_sample_count() == 1)
	var controls := PackedFloat64Array()
	var neutral := _neutral()
	var neutral_accepted: bool = session.tick_once(neutral)
	var resumed: bool = neutral_accepted and session.resume()
	_check("Nitro recording arms and resumes on the neutral 240 Hz tick", resumed)
	var run_ok := resumed
	var throttle := _neutral()
	throttle["throttle"] = 1.0
	throttle["steering"] = 0.125
	for _index in 480:
		if not session.tick_once(throttle):
			run_ok = false
			break
		controls.append_array(PackedFloat64Array([1.0, 0.125, 0.0, 0.0]))
	var final_state: PackedFloat64Array = session.state_snapshot()
	_check("Nitro engine state and fuel advance during one recorded second",
		run_ok and session.tick == 480 and final_state.size() == 33
		and final_state[31] != initial_state[31]
		and final_state[32] < initial_state[32] and final_state[32] >= 0.0)
	_check("Nitro recording buffer stores the complete dynamic state in every sample",
		session._recording_sample_count() == controls.size() / 4 + 1
		and session._record_sample_width == Session.RECORD_STATE_OFFSET + NitroDynamics.STATE_SIZE
			+ Session.RECORD_TELEMETRY_BASE_WIDTH + session._record_hull_contact_count
			+ Session.NITRO_TELEMETRY_FIELDS.size())
	var final_sample_state_offset: int = (session._recording_sample_count() - 1) * session._record_sample_width \
		+ Session.RECORD_STATE_OFFSET
	_check("recording samples retain engine-speed and fuel float64 values at both ends",
		session._record_samples[Session.RECORD_STATE_OFFSET + 31] == initial_state[31]
		and session._record_samples[Session.RECORD_STATE_OFFSET + 32] == initial_state[32]
		and session._record_samples[final_sample_state_offset + 31] == final_state[31]
		and session._record_samples[final_sample_state_offset + 32] == final_state[32])
	_check("recorded Nitro telemetry retains RPM and fuel channels",
		_nitro_telemetry_record_is_valid(
			session._recorded_telemetry(session._record_telemetry_offset()).get("nitro", {})))
	_check("Nitro recording stops cleanly", session.stop_recording())
	var recording_name := "rcv_nitro_session_%d" % Time.get_ticks_usec()
	var exported: Dictionary = session.export_recording(recording_name)
	_check("Nitro recording exports", exported.get("ok", false))
	if exported.get("ok", false):
		var csv_file := FileAccess.open(str(exported.csv_path), FileAccess.READ)
		var csv_text := csv_file.get_as_text() if csv_file != null else ""
		if csv_file != null:
			csv_file.close()
		var metadata_file := FileAccess.open(str(exported.metadata_path), FileAccess.READ)
		var metadata: Dictionary = JSON.parse_string(metadata_file.get_as_text()) if metadata_file != null else {}
		if metadata_file != null:
			metadata_file.close()
		_check("Nitro recording metadata pins model, dynamic state layout and engine channels",
			metadata.get("vehicle_id") == "monster-car-2"
			and metadata.get("state_layout") == NitroDynamics.STATE_LAYOUT
			and metadata.get("sample_layout", {}).get("telemetry_offset")
				== Session.RECORD_STATE_OFFSET + NitroDynamics.STATE_SIZE
			and metadata.get("sample_layout", {}).get("telemetry_fields", []).has("nitro.engine_rpm")
			and metadata.get("sample_layout", {}).get("telemetry_fields", []).has("nitro.fuel_kg"))
		_check("Nitro CSV includes engine and fuel telemetry", csv_text.contains("engine_rpm")
			and csv_text.contains("fuel_kg"))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(exported.csv_path)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(exported.metadata_path)))

	var checkpoint: Dictionary = session.checkpoint()
	_check("final Nitro checkpoint restores exact full-state bytes", session.restore_checkpoint(checkpoint)
		and final_state.to_byte_array() == session.state_snapshot().to_byte_array())
	_check("recorded control tape replays to exact engine, fuel and body state",
		session.replay(controls) and session.tick == controls.size() / 4
		and final_state.to_byte_array() == session.state_snapshot().to_byte_array())
	session.free()


func _test_nitro_airfield_prepare() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	var session = Session.new()
	var prepared := bool(field_result.get("ok", false)) \
		and session.prepare_airfield(field_result, {}, {}, "monster-car-2")
	if not prepared:
		print("Nitro airfield preparation error: ", session.load_error)
		var vehicle_result: Dictionary = VehicleData.load_vehicle("monster-car-2")
		var course_result: Dictionary = AirfieldCourse.build(field_result, {}, {})
		if vehicle_result.get("ok", false) and course_result.get("ok", false):
			var course: Dictionary = course_result.course
			var spawn: Dictionary = course.spawns[0]
			var road: Callable = session._make_road(course)
			var body_state: PackedFloat64Array = VehicleDynamics.make_terrain_state(
				vehicle_result.model, spawn, road)
			var state: PackedFloat64Array = NitroDynamics.make_terrain_state(
				vehicle_result.model, spawn, road)
			print("Nitro terrain diagnostic: model_valid=", NitroDynamics._valid_model(vehicle_result.model),
				" body_state_size=", body_state.size(), " nitro_state_size=", state.size())
	_check("Nitro prepares on the airplane airfield through the optional last vehicle ID",
		prepared and str(session.identities_snapshot().get("vehicle_id", "")) == "monster-car-2"
		and session.state_snapshot().size() == NitroDynamics.STATE_SIZE)
	if prepared:
		var checkpoint: Dictionary = session.checkpoint()
		_check("airfield Nitro checkpoint keeps model and terrain-kernel identities",
			checkpoint.get("vehicle_id") == "monster-car-2"
			and checkpoint.get("state_layout", []).size() == NitroDynamics.STATE_SIZE
			and session.can_restore_checkpoint(checkpoint))
	session.free()


func _test_nitro_zero_gravity_experiment_reset() -> void:
	var session = Session.new()
	var prepared: bool = session.prepare_default({}, "monster-car-2")
	var experiment_ok := prepared and session.set_experiment({
		"gravity_scale": 0.0, "grip_scale": 1.0, "spring_scale": 1.0,
		"damper_scale": 1.0, "ballast_kg": 0.0, "ballast_height_m": 0.10,
	})
	var experiment_state: PackedFloat64Array = session.state_snapshot()
	var experiment_model: Dictionary = session.model_snapshot()
	var telemetry: Dictionary = session.telemetry_snapshot()
	_check("Nitro session accepts a zero-gravity experiment with full state",
		experiment_ok and experiment_state.size() == NitroDynamics.STATE_SIZE
		and float(experiment_model.get("gravity_m_per_s2", -1.0)) == 0.0
		and bool(telemetry.get("ok", false)))
	var reset_ok := experiment_ok and session.reset()
	_check("Nitro reset rebuilds deterministic zero-gravity support and restores engine and fuel",
		reset_ok and session.tick == 0 and session.state_snapshot().size() == NitroDynamics.STATE_SIZE
		and experiment_state.to_byte_array() == session.state_snapshot().to_byte_array()
		and session.state_snapshot()[31] == experiment_state[31]
		and session.state_snapshot()[32] == experiment_state[32]
		and float(session.model_snapshot().get("gravity_m_per_s2", -1.0)) == 0.0)
	session.free()


func _float_array(values: PackedFloat64Array) -> Array[float]:
	var result: Array[float] = []
	for value in values:
		result.append(value)
	return result


func _nitro_telemetry_record_is_valid(value: Variant) -> bool:
	return typeof(value) == TYPE_DICTIONARY \
		and typeof(value.get("engine_rpm")) in [TYPE_INT, TYPE_FLOAT] \
		and typeof(value.get("fuel_kg")) in [TYPE_INT, TYPE_FLOAT] \
		and is_finite(float(value.get("engine_rpm", NAN))) \
		and is_finite(float(value.get("fuel_kg", NAN)))
