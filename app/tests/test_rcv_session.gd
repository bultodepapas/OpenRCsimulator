extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const InputSampler := preload("res://input/ground_vehicle_input.gd")
const VehicleData := preload("res://physics/ground_vehicle/vehicle_data.gd")
const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Course := preload("res://physics/ground_vehicle/course.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	var session = Session.new()
	_test_prepare_and_transaction(session)
	if failures == 0:
		_test_garage_reverse_checkpoint_replay(session)
	if failures == 0:
		_test_experiment_and_reset(session)
	if failures == 0:
		_test_recording_export(session)
	session.free()
	if failures == 0:
		_test_native_backend_switch_guards()
	print("RCV session: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("FAIL: " + label)


func _neutral(armed: bool = true) -> Dictionary:
	return {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false,
		"source": "keyboard", "armed": armed}


func _test_prepare_and_transaction(session) -> void:
	_check("default session prepares", session.prepare_default())
	if not session.prepared:
		return
	_check("new session starts paused at tick zero", session.paused and session.tick == 0 and session.time_s() == 0.0)
	var state: PackedFloat64Array = session.state_snapshot()
	_check("initial state is a 31-float64 vector", state.size() == 31 and typeof(session.state) == TYPE_PACKED_FLOAT64_ARRAY)
	_check("initial telemetry has four wheel loads", session.last_telemetry.get("wheel_load_n", PackedFloat64Array()).size() == 4)
	var initial_checkpoint: Dictionary = session.checkpoint()
	var initial_json: Variant = JSON.parse_string(JSON.stringify(initial_checkpoint, "", true, true))
	_check("tick-zero checkpoint represents its empty control tape without invalid base64 calls",
		not initial_checkpoint.is_empty() and int(initial_checkpoint.get("tick", -1)) == 0
		and str(initial_checkpoint.get("control_tape_f64_base64", "missing")) == ""
		and str(initial_checkpoint.get("control_tape_sha256", "")) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
		and session.can_restore_checkpoint(initial_checkpoint))
	_check("JSON roundtrip preserves a restorable initial checkpoint",
		typeof(initial_json) == TYPE_DICTIONARY and session.can_restore_checkpoint(initial_json))
	_check("initial checkpoint restores byte-exact state and remains at tick zero",
		session.restore_checkpoint(initial_json) and session.tick == 0 and session.paused
		and _arrays_equal(session.state_snapshot(), state) and session.control_tape_snapshot().is_empty())
	var exposed: PackedFloat64Array = session.state
	exposed[0] += 17.0
	_check("public state access is isolated from the simulation state", session.state_snapshot()[0] == state[0])
	var original_tick: int = session.tick
	var original_state: PackedFloat64Array = session.state_snapshot()
	var broken := {"ok": false, "errors": PackedStringArray(["deliberate load failure"])}
	_check("failed prepare is rejected", not session.prepare(broken, {}))
	_check("failed prepare preserves the prepared state", session.prepared and session.tick == original_tick
		and _arrays_equal(session.state_snapshot(), original_state))
	_check("failed load has a useful diagnostic", not session.load_error.is_empty())
	_check("pre-pause neutral sample is observed", session.tick_once(_neutral()))
	session.pause("test-pause")
	_check("pausing requires a fresh neutral sample before resume", not session.resume())
	_check("fresh neutral input allows explicit resume", session.tick_once(_neutral()) and session.resume())
	session.pause("test-complete")


func _test_garage_reverse_checkpoint_replay(session) -> void:
	var sampler = InputSampler.new()
	_check("neutral sample is armed before opening garage", session.tick_once(sampler.sample({}, {})))
	_check("garage hold is accepted", session.add_pause_hold("garage"))
	_check("garage release is explicit", session.release_pause_hold("garage") and session.paused)
	_check("stale neutral sample cannot resume after garage hold", not session.resume())
	var held_reverse: Dictionary = sampler.sample({"reverse": true}, {})
	_check("keyboard S samples reverse throttle", held_reverse.throttle == 1.0 and held_reverse.reverse)
	_check("paused garage samples input without advancing", session.tick_once(held_reverse)
		and session.paused and session.tick == 0)
	_check("held reverse cannot resume after garage release", not session.resume())
	var neutral: Dictionary = sampler.sample({}, {})
	_check("neutral sample arms the input", neutral.armed and neutral.throttle == 0.0)
	_check("paused neutral sample leaves tick unchanged", session.tick_once(neutral) and session.tick == 0)
	_check("resume requires an explicit request after neutral", session.resume() and not session.paused)

	var start_north: float = session.state_snapshot()[0]
	for _index in range(240):
		var reverse := _neutral()
		reverse.throttle = 1.0
		reverse.steering = 0.12345678901234568
		reverse.reverse = true
		if not session.tick_once(reverse):
			break
	_check("reverse controls advance one second of fixed ticks", session.tick == 240 and absf(session.time_s() - 1.0) < 1.0e-12)
	_check("reverse input produces negative forward speed", float(session.last_telemetry.get("forward_speed_m_per_s", 0.0)) < -1.0e-4)
	_check("reverse input moves the chassis backward", session.state_snapshot()[0] < start_north)
	var current_model: Dictionary = session.model_snapshot()
	var current_course: Dictionary = session.course_snapshot()
	var road := func(north_m: float, east_m: float) -> Dictionary:
		return Course.sample(current_course, north_m, east_m)
	var reverse_controls := {"throttle": 1.0, "steering": 0.12345678901234568, "brake": 0.0, "reverse": true}
	var expected_telemetry: Dictionary = VehicleDynamics.telemetry(
		session.state_snapshot(), current_model, road, reverse_controls)
	_check("accepted tick telemetry uses the exact accepted controls",
		_arrays_equal(session.last_telemetry.get("wheel_longitudinal_force_n", PackedFloat64Array()),
			expected_telemetry.get("wheel_longitudinal_force_n", PackedFloat64Array())))
	var tape: PackedFloat64Array = session.control_tape_snapshot()
	_check("complete controls are compact float64 tape", tape.size() == session.tick * 4
		and tape[0] == 1.0 and tape[1] == 0.12345678901234568 and tape[3] == 1.0)

	var checkpoint_before_recovery: Dictionary = session.checkpoint()
	_check("checkpoint contains matching model/course identities and complete tape",
		not checkpoint_before_recovery.is_empty() and checkpoint_before_recovery.control_tape.size() == session.tick * 4)
	_check("checkpoint pins the prepared solver backend receipt",
		session._backend_identities_equal(
			checkpoint_before_recovery.get("solver_identity", {}).get("backend_identity", {}),
			VehicleDynamics.backend_identity()))
	_check("manual recovery succeeds and invalidates the run", session.manual_recovery()
		and session.paused and not session.run_valid)
	var checkpoint_after_recovery: Dictionary = session.checkpoint()
	_check("recovery is represented by an event and replay action",
		not session.event_tape_snapshot().is_empty() and session.recovery_actions_snapshot().size() == 1)
	var recovered_state: PackedFloat64Array = session.state_snapshot()
	_check("strict checkpoint restore succeeds", session.restore_checkpoint(checkpoint_before_recovery))
	var checkpoint_state_bytes: PackedFloat64Array = session._decode_float64_blob(
		checkpoint_before_recovery.state_f64_base64, 31)
	_check("restored checkpoint is paused and byte-for-byte same state",
		session.paused and session.tick == 240 and _arrays_equal(session.state_snapshot(), checkpoint_state_bytes))
	var json_checkpoint: Variant = JSON.parse_string(JSON.stringify(checkpoint_before_recovery, "", true, true))
	_check("JSON checkpoint roundtrip preserves authoritative float64 byte hashes",
		typeof(json_checkpoint) == TYPE_DICTIONARY and session.can_restore_checkpoint(json_checkpoint))
	_check("JSON-loaded checkpoint restores while paused", session.restore_checkpoint(json_checkpoint)
		and session.paused and _arrays_equal(session.state_snapshot(), checkpoint_state_bytes))
	_check("JSON restore uses authoritative control bytes instead of rounded display values",
		_arrays_equal(session.control_tape_snapshot(), tape))
	var bad_state_checkpoint: Dictionary = checkpoint_before_recovery.duplicate(true)
	bad_state_checkpoint.state_f64_base64 = "A" + str(bad_state_checkpoint.state_f64_base64).substr(1)
	_check("state-byte corruption is rejected atomically", not session.restore_checkpoint(bad_state_checkpoint)
		and session.tick == 240 and _arrays_equal(session.state_snapshot(), checkpoint_state_bytes))
	var foreign_checkpoint: Dictionary = checkpoint_before_recovery.duplicate(true)
	var foreign_identity: Dictionary = foreign_checkpoint.model_identity
	foreign_identity.id = "different-vehicle"
	foreign_checkpoint.model_identity = foreign_identity
	_check("foreign model identity is rejected", not session.restore_checkpoint(foreign_checkpoint))
	_check("failed restore leaves current state unchanged", _arrays_equal(session.state_snapshot(), checkpoint_state_bytes))
	var foreign_solver_checkpoint: Dictionary = checkpoint_before_recovery.duplicate(true)
	var foreign_solver: Dictionary = foreign_solver_checkpoint.solver_identity
	foreign_solver.solver_version = "different-equations"
	foreign_solver_checkpoint.solver_identity = foreign_solver
	foreign_solver_checkpoint.checkpoint_sha256 = session._checkpoint_hash(foreign_solver_checkpoint)
	_check("checkpoint from a different dynamics solver is rejected",
		not session.restore_checkpoint(foreign_solver_checkpoint))
	var foreign_backend_checkpoint: Dictionary = checkpoint_before_recovery.duplicate(true)
	var foreign_backend_solver: Dictionary = foreign_backend_checkpoint.solver_identity
	var foreign_backend: Dictionary = foreign_backend_solver.backend_identity.duplicate(true)
	foreign_backend.backend = "different-backend"
	foreign_backend.backend_version = "fixture-native-v1"
	foreign_backend.toolchain_sha256 = "f".repeat(64)
	foreign_backend.binary_sha256 = "e".repeat(64)
	foreign_backend_solver.backend_identity = foreign_backend
	foreign_backend_checkpoint.solver_identity = foreign_backend_solver
	foreign_backend_checkpoint.checkpoint_sha256 = session._checkpoint_hash(foreign_backend_checkpoint)
	_check("checkpoint from a different dynamics backend is rejected after integrity verification",
		not session.restore_checkpoint(foreign_backend_checkpoint))
	var legacy_checkpoint: Dictionary = checkpoint_before_recovery.duplicate(true)
	var legacy_solver: Dictionary = legacy_checkpoint.solver_identity.duplicate(true)
	legacy_solver.erase("backend_identity")
	legacy_checkpoint.solver_identity = legacy_solver
	legacy_checkpoint.checkpoint_sha256 = session._checkpoint_hash(legacy_checkpoint)
	var active_backend := str(VehicleDynamics.backend_identity().get("backend", ""))
	var legacy_accepted: bool = session.can_restore_checkpoint(legacy_checkpoint)
	_check("legacy v2 checkpoint is accepted only by its original reference backend",
		(active_backend == VehicleDynamics.BACKEND_GDSCRIPT_REFERENCE and legacy_accepted)
		or (active_backend == VehicleDynamics.BACKEND_NATIVE and not legacy_accepted))
	var controls_for_replay: PackedFloat64Array = tape
	var actions_for_replay: Array = checkpoint_after_recovery.recovery_actions
	_check("packed controls and recovery actions replay transactionally",
		session.replay(controls_for_replay, actions_for_replay))
	_check("replay reproduces recovered state and invalid-run marker",
		session.tick == 240 and not session.run_valid and _arrays_equal(session.state_snapshot(), recovered_state))


func _test_experiment_and_reset(session) -> void:
	var base_checkpoint: Dictionary = session.checkpoint()
	var old_identity: Dictionary = session.identities_snapshot().model
	var old_state: PackedFloat64Array = session.state_snapshot()
	_check("invalid experiment is rejected", not session.set_experiment({"spring_scale": -1.0}))
	_check("invalid experiment is transactional", session.paused and session.tick == 240
		and _arrays_equal(session.state_snapshot(), old_state)
		and session.identities_snapshot().model == old_identity)
	var experiment_ok: bool = session.set_experiment({
		"gravity_scale": 1.0, "grip_scale": 1.0, "spring_scale": 1.05,
		"damper_scale": 1.0, "ballast_kg": 0.0, "ballast_height_m": 0.03,
	})
	_check("spring experiment loads from the immutable base recipe", experiment_ok)
	_check("experiment changes identity and clears old-run history", session.tick == 0
		and session.control_tape_snapshot().is_empty()
		and session.identities_snapshot().model != old_identity)
	_check("old checkpoint cannot cross an experiment identity", not session.restore_checkpoint(base_checkpoint))
	_check("reset to named course spawn starts paused with clean history", session.reset("start")
		and session.paused and session.tick == 0 and session.state_snapshot().size() == 31)
	var experiment_spawn_state: PackedFloat64Array = session.state_snapshot()
	_check("experiment recovery preserves the adjusted static spawn pose",
		session.manual_recovery() and _arrays_equal(session.state_snapshot(), experiment_spawn_state))
	_check("unknown spawn reset is rejected without mutating state", not session.reset("missing-spawn")
		and session.tick == 0 and session.paused)


func _test_recording_export(session) -> void:
	_check("recording starts", session.start_recording())
	var before_reset: PackedFloat64Array = session.state_snapshot()
	_check("reset cannot discard an active unexported recording", not session.reset()
		and session.recording and _arrays_equal(session.state_snapshot(), before_reset))
	var sampler = InputSampler.new()
	var neutral: Dictionary = sampler.sample({}, {})
	session.tick_once(neutral)
	_check("recording can explicitly resume after neutral arming", session.resume())
	var forward: Dictionary = sampler.sample({"accelerate": true}, {})
	_check("recording tick advances", session.tick_once(forward) and session.tick == 1)
	_check("recovery during recording stays explicit and marks the run invalid",
		session.manual_recovery() and session.recording and session.paused and not session.run_valid
		and not session.event_tape_snapshot().is_empty())
	_check("recording stops", session.stop_recording() and not session.recording)
	var unique_name := "rcv_session_test_%d" % Time.get_ticks_usec()
	var exported: Dictionary = session.export_recording(unique_name)
	_check("versioned CSV and JSON metadata export successfully", exported.get("ok", false)
		and FileAccess.file_exists(str(exported.get("csv_path", "")))
		and FileAccess.file_exists(str(exported.get("metadata_path", ""))))
	if exported.get("ok", false):
		var csv := FileAccess.open(str(exported.csv_path), FileAccess.READ)
		var csv_text := csv.get_as_text()
		csv.close()
		var json := FileAccess.open(str(exported.metadata_path), FileAccess.READ)
		var metadata: Dictionary = JSON.parse_string(json.get_as_text())
		json.close()
		_check("CSV declares recording version and state schema", csv_text.begins_with("# openrc-ground-vehicle-recording v3\n")
			and metadata.get("format") == "openrc-ground-vehicle-recording v3"
			and metadata.get("version") == 3 and metadata.get("fixed_hz") == 240
			and metadata.get("state_layout", []).size() == 31
			and metadata.get("sample_width", 0) > 80)
		_check("recording metadata includes strict identities and integrity hashes",
			metadata.get("model_identity", {}).has("sha256") and metadata.get("course_identity", {}).has("sha256")
			and metadata.get("solver_identity", {}).get("solver_version") == VehicleDynamics.SOLVER_VERSION
			and metadata.get("solver_identity", {}).get("substeps_per_tick") == VehicleDynamics.SUBSTEPS_PER_TICK
			and session._backend_identities_equal(
				metadata.get("solver_identity", {}).get("backend_identity", {}), VehicleDynamics.backend_identity())
			and str(metadata.get("control_tape_sha256", "")).length() == 64
			and str(metadata.get("recorded_samples_sha256", "")).length() == 64
			and metadata.get("run_valid") == false
			and metadata.get("events", []).any(func(event: Dictionary) -> bool:
				return str(event.get("type", "")) == "manual_recovery"))
		_check("recording storage is packed and preserves dynamic telemetry channels",
			typeof(session._record_samples) == TYPE_PACKED_FLOAT64_ARRAY
			and session._record_samples.size() == metadata.sample_count * session._record_sample_width
			and csv_text.contains("wheel_longitudinal_force_n"))
		var collision: Dictionary = session.export_recording(unique_name)
		_check("export refuses overwrite of existing pair", not collision.get("ok", false))
		var csv_abs := ProjectSettings.globalize_path(str(exported.csv_path))
		var json_abs := ProjectSettings.globalize_path(str(exported.metadata_path))
		DirAccess.remove_absolute(csv_abs)
		DirAccess.remove_absolute(json_abs)
	_check("export rejects traversal-like names", not session.export_recording("../bad").get("ok", false))
	_test_recording_limit(session)


func _test_recording_limit(session) -> void:
	var limit_notifications: Array = []
	var on_limit := func(sample_count: int, elapsed_seconds: float) -> void:
		limit_notifications.append([sample_count, elapsed_seconds])
	session.recording_limit_reached.connect(on_limit)
	_check("a saved recording allows a new bounded recording", session.start_recording())
	_check("recording buffer stores packed float64 rows", typeof(session._record_samples) == TYPE_PACKED_FLOAT64_ARRAY
		and session._recording_sample_count() == 1)
	session._recording_ticks = Session.MAX_RECORDING_DURATION_TICKS - 1
	_check("paused neutral input arms the duration-boundary resume", session.tick_once(_neutral()))
	_check("duration-boundary recording resumes explicitly", session.resume())
	var neutral_tick := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
	_check("duration cap stops without dropping the final accepted sample",
		session.tick_once(neutral_tick) and not session.recording and session._recording_sample_count() == 2)
	_check("duration cap notifies the scene with exportable sample count and duration",
		limit_notifications.size() == 1 and limit_notifications[0][0] == 2
		and limit_notifications[0][1] == 600.0 and session._recording_limit_hit)
	session.recording_limit_reached.disconnect(on_limit)
	var capped_name := "rcv_limit_test_%d" % Time.get_ticks_usec()
	var capped_export: Dictionary = session.export_recording(capped_name)
	_check("duration-capped samples remain exportable", capped_export.get("ok", false))
	if capped_export.get("ok", false):
		var metadata_file := FileAccess.open(str(capped_export.metadata_path), FileAccess.READ)
		var metadata: Dictionary = JSON.parse_string(metadata_file.get_as_text())
		metadata_file.close()
		_check("limit metadata retains the solver and capped duration", metadata.get("recording_limit_hit", false)
			and metadata.get("recorded_tick_count") == Session.MAX_RECORDING_DURATION_TICKS
			and metadata.get("solver_identity", {}).get("solver_version") == VehicleDynamics.SOLVER_VERSION)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(capped_export.csv_path)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(capped_export.metadata_path)))
	_test_recording_interruption(session)


func _test_recording_interruption(session) -> void:
	var notifications: Array = []
	var on_interrupted := func(reason: String, sample_count: int) -> void:
		notifications.append([reason, sample_count])
	session.recording_interrupted.connect(on_interrupted)
	_check("interruption test starts a fresh recording", session.start_recording())
	var retained_sample_count: int = session._recording_sample_count()
	var retained_sample_bytes: PackedFloat64Array = session._record_samples.duplicate()
	session._interrupt_recording("test schema interruption")
	_check("interruption emits its reason and preserved sample count exactly once",
		notifications.size() == 1 and notifications[0][0] == "test schema interruption"
		and notifications[0][1] == retained_sample_count and not session.recording)
	_check("interrupted recording remains pending in memory and blocks discard paths",
		session._has_unexported_recording() and session._record_samples == retained_sample_bytes
		and not session.start_recording() and not session.reset())
	var interrupted_name := "rcv_interrupted_test_%d" % Time.get_ticks_usec()
	var interrupted_export: Dictionary = session.export_recording(interrupted_name)
	_check("interrupted partial recording remains exportable", interrupted_export.get("ok", false))
	if interrupted_export.get("ok", false):
		var metadata_file := FileAccess.open(str(interrupted_export.metadata_path), FileAccess.READ)
		var metadata: Dictionary = JSON.parse_string(metadata_file.get_as_text())
		metadata_file.close()
		var has_interruption := false
		for event: Variant in metadata.get("events", []):
			if typeof(event) == TYPE_DICTIONARY \
					and str(event.get("type", "")) == "recording_interrupted" \
					and str(event.get("reason", "")) == "test schema interruption":
				has_interruption = true
		_check("interruption metadata identifies the partial recording and reason",
			not metadata.get("run_valid", true) and has_interruption
			and metadata.get("sample_count") == retained_sample_count)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(interrupted_export.csv_path)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(interrupted_export.metadata_path)))
	session.recording_interrupted.disconnect(on_interrupted)


func _test_native_backend_switch_guards() -> void:
	if str(VehicleDynamics.backend_identity().get("backend", "")) != VehicleDynamics.BACKEND_NATIVE:
		print("SKIP native Session backend-switch guard: pinned native backend is not staged")
		return
	var session = Session.new()
	var prepared: bool = session.prepare_default()
	var armed: bool = prepared and session.tick_once(_neutral())
	var resumed: bool = armed and session.resume()
	var advanced: bool = resumed and session.tick_once(_neutral())
	_check("native backend guard fixture prepares and records one valid tick",
		advanced and session.tick == 1)
	if not advanced:
		session.free()
		return
	var checkpoint: Dictionary = session.checkpoint()
	var reference_selected := VehicleDynamics.set_backend_override_for_tests(VehicleDynamics.BACKEND_GDSCRIPT_REFERENCE)
	_check("process-local test override selects the GDScript reference", reference_selected
		and str(VehicleDynamics.backend_identity().get("backend", "")) == VehicleDynamics.BACKEND_GDSCRIPT_REFERENCE)
	_check("prepared native Session rejects its checkpoint under the reference backend",
		not session.can_restore_checkpoint(checkpoint))
	var replay_accepted: bool = session.replay(PackedFloat64Array())
	_check("prepared native Session refuses replay after a backend flip",
		not replay_accepted and session.load_error == "replay requires a prepared session with recording stopped")
	var tick_accepted: bool = session.tick_once(_neutral())
	_check("prepared native Session fail-safes a tick after a backend flip",
		not tick_accepted and session.paused
		and session.fault_reason.contains("vehicle dynamics backend changed"))
	var native_restored := VehicleDynamics.set_backend_override_for_tests("")
	_check("automatic native backend selection is restored after guard checks",
		native_restored and str(VehicleDynamics.backend_identity().get("backend", "")) == VehicleDynamics.BACKEND_NATIVE)
	session.free()


func _arrays_equal(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if left[index] != right[index]:
			return false
	return true
