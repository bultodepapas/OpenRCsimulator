## Profile the production Monster Car 2 Session without rendering or recording.
## Run only after a baseline/profile window has been scheduled by the owning track.
extends SceneTree

const Session := preload("res://../research/rc-monster-truck/monster-car-2/rcv41/profiled_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const NitroDynamics := preload("res://physics/ground_vehicle/nitro_dynamics.gd")
const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")

const WARMUP_TICKS := 60
const MEASURED_TICKS := 960
const PAUSED_GUARD_SAMPLES := 120
const IDENTITY_WARMUP_CALLS := 8
const IDENTITY_MEASURED_CALLS := 120
const VEHICLE_ID := "monster-car-2"
const VEHICLE_DATA_PATH := "res://data/vehicles/ground/monster_car_2.json"
const SPAWN_ID := "track_start"
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0,
	"reverse": false, "armed": true}

const MEASURED_PHASES := [
	{"id": "launch", "ticks": 200, "throttle": 0.50, "steering": 0.0, "brake": 0.0},
	{"id": "right_sweep", "ticks": 140, "throttle": 0.35, "steering": 0.30, "brake": 0.0},
	{"id": "left_sweep", "ticks": 140, "throttle": 0.35, "steering": -0.30, "brake": 0.0},
	{"id": "braking", "ticks": 140, "throttle": 0.0, "steering": 0.0, "brake": 0.55},
	{"id": "relaunch", "ticks": 160, "throttle": 0.48, "steering": 0.10, "brake": 0.0},
	{"id": "combined", "ticks": 120, "throttle": 0.22, "steering": -0.15, "brake": 0.12},
	{"id": "coast", "ticks": 60, "throttle": 0.0, "steering": 0.0, "brake": 0.0},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			if not output_path.is_empty():
				_fail("--output may be supplied only once")
				return
			output_path = argument.trim_prefix("--output=")
	if output_path.is_empty():
		_fail("--output=<absolute-json-path> is required")
		return

	var field_result: Dictionary = FieldLoader.load_from()
	if not bool(field_result.get("ok", false)):
		_fail("default production airfield did not load: " + str(field_result.get("errors", [])))
		return
	var session = Session.new()
	if not session.prepare_airfield(field_result, {}, {}, VEHICLE_ID):
		_fail("Monster Car 2 did not prepare on the production airfield: " + str(session.load_error))
		session.free()
		return
	if not session.reset(SPAWN_ID):
		_fail("authored %s spawn was not accepted: %s" % [SPAWN_ID, str(session.load_error)])
		session.free()
		return

	# Measure the guard-only path while paused. These calls must leave the accepted
	# state and tape untouched, and the final neutral sample arms the later resume.
	var initial_state: PackedFloat64Array = session.state_snapshot()
	var initial_state_bytes := initial_state.to_byte_array()
	var paused_guard_durations := PackedFloat64Array()
	for _index in PAUSED_GUARD_SAMPLES:
		var started := Time.get_ticks_usec()
		var ok: bool = session.tick_once(NEUTRAL)
		var elapsed_us := float(Time.get_ticks_usec() - started)
		if not ok:
			_fail("paused identity-guard probe failed: " + str(session.fault_reason))
			session.free()
			return
		paused_guard_durations.append(elapsed_us)
	if not session.paused or session.tick != 0 or not session.control_tape_snapshot().is_empty() \
			or session.state_snapshot().to_byte_array() != initial_state_bytes:
		_fail("paused guard probe changed simulation state or accepted controls")
		session.free()
		return

	# Attribute the adapter identity-generation cost separately from the whole
	# paused tick guard. The result is also checked against the prepared identity.
	for _index in IDENTITY_WARMUP_CALLS:
		NitroDynamics.backend_identity()
	var identity_call_durations := PackedFloat64Array()
	var identity_probe: Dictionary = {}
	for _index in IDENTITY_MEASURED_CALLS:
		var started := Time.get_ticks_usec()
		identity_probe = NitroDynamics.backend_identity()
		identity_call_durations.append(float(Time.get_ticks_usec() - started))
	var prepared_identity := NitroDynamics.backend_identity()
	if not session.tick_once(NEUTRAL) or not session.resume():
		_fail("session did not arm and resume: " + str(session.fault_reason))
		session.free()
		return

	var expected_tape := _scheduled_control_tape()
	session.wrap_road()
	var trajectory_hash := HashingContext.new()
	if trajectory_hash.start(HashingContext.HASH_SHA256) != OK:
		_fail("could not start trajectory digest")
		session.free()
		return
	var tick_durations := PackedFloat64Array()
	var measured_durations := PackedFloat64Array()
	var friction_sweep_counts := {}
	var friction_sweep_cap_hits := 0
	var maximum_friction_sweeps := 0
	for tick_index in WARMUP_TICKS + MEASURED_TICKS:
		session.profiling = tick_index >= WARMUP_TICKS
		var controls := _scheduled_controls(tick_index)
		var started := Time.get_ticks_usec()
		var ok: bool = session.tick_once(controls)
		var elapsed_us := float(Time.get_ticks_usec() - started)
		if not ok:
			_fail("vehicle session faulted at tick %d: %s" % [tick_index, str(session.fault_reason)])
			session.free()
			return
		tick_durations.append(elapsed_us)
		if tick_index >= WARMUP_TICKS:
			measured_durations.append(elapsed_us)
			var sweeps := int(session.last_telemetry.get("friction_sweeps_used", 0))
			var sweep_key := str(sweeps)
			friction_sweep_counts[sweep_key] = int(friction_sweep_counts.get(sweep_key, 0)) + 1
			maximum_friction_sweeps = maxi(maximum_friction_sweeps, sweeps)
			if sweeps >= VehicleDynamics.FRICTION_SWEEPS:
				friction_sweep_cap_hits += 1
		var state_after_tick: PackedFloat64Array = session.state_snapshot()
		trajectory_hash.update(state_after_tick.to_byte_array())

	session.profiling = false
	var original_trajectory_sha256 := trajectory_hash.finish().hex_encode()
	var accepted_tape: PackedFloat64Array = session.control_tape_snapshot()
	var final_state: PackedFloat64Array = session.state_snapshot()
	var final_state_bytes := final_state.to_byte_array()
	var original_checkpoint: Dictionary = session.checkpoint()
	if session.tick != WARMUP_TICKS + MEASURED_TICKS \
			or accepted_tape.size() != (WARMUP_TICKS + MEASURED_TICKS) * 4 \
			or accepted_tape.to_byte_array() != expected_tape.to_byte_array() \
			or original_checkpoint.is_empty():
		_fail("measured run was incomplete or its accepted tape/checkpoint was invalid")
		session.free()
		return

	var checkpoint_restore_ok: bool = session.restore_checkpoint(original_checkpoint)
	var restored_checkpoint: Dictionary = session.checkpoint() if checkpoint_restore_ok else {}
	var checkpoint_restore_exact: bool = checkpoint_restore_ok \
		and session.state_snapshot().to_byte_array() == final_state_bytes \
		and session.control_tape_snapshot().to_byte_array() == accepted_tape.to_byte_array() \
		and str(restored_checkpoint.get("checkpoint_sha256", "")) \
			== str(original_checkpoint.get("checkpoint_sha256", ""))
	if not checkpoint_restore_exact:
		_fail("checkpoint restore differed from the accepted measured state")
		session.free()
		return

	# Exercise the production checkpoint/replay path and demand byte-exact endpoint,
	# checkpoint, and control-tape equality. Session.replay suppresses tick signals,
	# so a second unmeasured tape pass below captures every replay trajectory state.
	var official_replay_ok: bool = session.replay(accepted_tape)
	if not official_replay_ok:
		_fail("Session.replay did not complete: " + str(session.load_error))
		session.free()
		return
	var official_replay_state: PackedFloat64Array = session.state_snapshot()
	var official_replay_tape: PackedFloat64Array = session.control_tape_snapshot()
	var official_replay_checkpoint: Dictionary = session.checkpoint()
	var official_replay_exact: bool = session.tick == WARMUP_TICKS + MEASURED_TICKS \
		and official_replay_state.to_byte_array() == final_state_bytes \
		and official_replay_tape.to_byte_array() == accepted_tape.to_byte_array() \
		and str(official_replay_checkpoint.get("checkpoint_sha256", "")) \
			== str(original_checkpoint.get("checkpoint_sha256", ""))
	if not official_replay_exact:
		_fail("official replay differed from the measured checkpoint or accepted tape")
		session.free()
		return

	if not session.reset(SPAWN_ID) or not session.tick_once(NEUTRAL) or not session.resume():
		_fail("could not prepare the trace-capturing tape replay")
		session.free()
		return
	var replay_trajectory_hash := HashingContext.new()
	if replay_trajectory_hash.start(HashingContext.HASH_SHA256) != OK:
		_fail("could not start replay trajectory digest")
		session.free()
		return
	for offset in range(0, accepted_tape.size(), 4):
		var controls := {
			"throttle": accepted_tape[offset],
			"steering": accepted_tape[offset + 1],
			"brake": accepted_tape[offset + 2],
			"reverse": float(accepted_tape[offset + 3]) == 1.0,
			"armed": true,
		}
		if not session.tick_once(controls):
			_fail("trace-capturing tape replay faulted at tick %d: %s" % [session.tick, str(session.fault_reason)])
			session.free()
			return
		var state_after_tick: PackedFloat64Array = session.state_snapshot()
		replay_trajectory_hash.update(state_after_tick.to_byte_array())
	var replay_trajectory_sha256 := replay_trajectory_hash.finish().hex_encode()
	var trace_replay_state: PackedFloat64Array = session.state_snapshot()
	var trace_replay_tape: PackedFloat64Array = session.control_tape_snapshot()
	var trace_replay_exact: bool = session.tick == WARMUP_TICKS + MEASURED_TICKS \
		and replay_trajectory_sha256 == original_trajectory_sha256 \
		and trace_replay_state.to_byte_array() == final_state_bytes \
		and trace_replay_tape.to_byte_array() == accepted_tape.to_byte_array()
	if not trace_replay_exact:
		_fail("trace-capturing replay did not match the full trajectory and accepted tape")
		session.free()
		return

	var identities: Dictionary = session.identities_snapshot()
	var course: Dictionary = session.course_snapshot()
	var field_value: Dictionary = field_result.get("field", {})
	var track: Dictionary = course.get("track", {})
	var solver_identity: Dictionary = original_checkpoint.get("solver_identity", {})
	var backend_identity: Dictionary = solver_identity.get("backend_identity", {})
	var body_backend_identity: Dictionary = VehicleDynamics.backend_identity()
	var identity_probe_matches: bool = _identity_signature(identity_probe) == _identity_signature(prepared_identity) \
		and _identity_signature(prepared_identity) == _identity_signature(backend_identity)
	if not identity_probe_matches:
		_fail("Backend identity differs from prepared/checkpoint identity")
		session.free()
		return
	var source_identities := {
		"field_loader_script_sha256": FileAccess.get_sha256("res://data/field_loader.gd"),
		"field_data_sha256": FileAccess.get_sha256(FieldLoader.DEFAULT_PATH),
		"vehicle_data_sha256": FileAccess.get_sha256(VEHICLE_DATA_PATH),
		"vehicle_data_script_sha256": FileAccess.get_sha256("res://physics/ground_vehicle/vehicle_data.gd"),
		"session_script_sha256": FileAccess.get_sha256("res://sim/ground_vehicle/session.gd"),
		"nitro_dynamics_script_sha256": FileAccess.get_sha256("res://physics/ground_vehicle/nitro_dynamics.gd"),
		"vehicle_dynamics_script_sha256": FileAccess.get_sha256("res://physics/ground_vehicle/vehicle_dynamics.gd"),
		"vehicle_environment_script_sha256": FileAccess.get_sha256("res://physics/ground_vehicle/vehicle_environment.gd"),
		"damage_observer_script_sha256": FileAccess.get_sha256("res://physics/ground_vehicle/vehicle_damage.gd"),
		"airfield_course_script_sha256": FileAccess.get_sha256("res://physics/ground_vehicle/airfield_course.gd"),
		"airfield_track_script_sha256": FileAccess.get_sha256("res://physics/ground_vehicle/airfield_track.gd"),
		"native_kernel_source_sha256": FileAccess.get_sha256("res://../research/rc-monster-truck/native/src/ground_vehicle_kernel.hpp"),
		"native_wrapper_source_sha256": FileAccess.get_sha256("res://../research/rc-monster-truck/native/src/ground_vehicle_native.cpp"),
		"profile_script_sha256": FileAccess.get_sha256(get_script().resource_path),
		"profile_wrapper_sha256": FileAccess.get_sha256("res://../research/rc-monster-truck/monster-car-2/rcv41/profiled_session.gd"),
	}
	var measured_summary := _summary(measured_durations)
	var report := {
		"format": "openrc-rcv41-monster-car-2-session-profile-v1",
		"profile": session.profile_summary(),
		"complete": session.tick == WARMUP_TICKS + MEASURED_TICKS,
		"exact_replay": official_replay_exact and trace_replay_exact,
		"engine": Engine.get_version_info().string,
		"debug_build": OS.is_debug_build(),
		"processor": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"scope": "Bare production Session on the production airfield, track_start, Monster Car 2; 60 neutral warmup and 960 measured fixed-tape ticks. No rendering or recording. Replay/checkpoint validation occurs outside timing.",
		"vehicle_id": VEHICLE_ID,
		"vehicle_data_path": VEHICLE_DATA_PATH,
		"vehicle_identity": identities.get("model", {}),
		"field_id": str(field_value.get("id", "")),
		"course_identity": identities.get("course", {}),
		"track_id": str(track.get("id", "")),
		"spawn_id": SPAWN_ID,
		"control_phases": _phase_report(),
		"warmup_ticks": WARMUP_TICKS,
		"measured_ticks": MEASURED_TICKS,
		"tick_cost": measured_summary,
		"warmup_tick_cost": _summary(tick_durations.slice(0, WARMUP_TICKS)),
		"measured_tick_durations_us": measured_durations,
		"paused_guard_probe": {
			"samples": PAUSED_GUARD_SAMPLES,
			"scope": "paused Session.tick_once: active backend identity guard, control parse, and paused early-return; state/tick/tape verified unchanged",
			"cost": _summary(paused_guard_durations),
		},
		"backend_identity_probe": {
			"warmup_calls": IDENTITY_WARMUP_CALLS,
			"measured_calls": IDENTITY_MEASURED_CALLS,
			"scope": "NitroDynamics.backend_identity only; per-call composition and artifact hash cost, outside simulation timing",
			"cost": _summary(identity_call_durations),
			"matches_prepared_and_checkpoint_identity": identity_probe_matches,
		},
		"backend_identity": backend_identity,
		"body_backend_identity": body_backend_identity,
		"source_identities": source_identities,
		"accepted_control_tape_sha256": _sha256_bytes(accepted_tape.to_byte_array()),
		"accepted_control_tape_f64_count": accepted_tape.size(),
		"checkpoint_sha256": str(original_checkpoint.get("checkpoint_sha256", "")),
		"checkpoint_restore_exact": checkpoint_restore_exact,
		"official_replay_checkpoint_sha256": str(official_replay_checkpoint.get("checkpoint_sha256", "")),
		"official_replay_exact": official_replay_exact,
		"trace_replay_exact": trace_replay_exact,
		"trajectory_sha256": original_trajectory_sha256,
		"replay_trajectory_sha256": replay_trajectory_sha256,
		"maximum_friction_sweeps": VehicleDynamics.FRICTION_SWEEPS,
		"observed_maximum_friction_sweeps": maximum_friction_sweeps,
		"friction_sweep_count_by_sweeps_used": friction_sweep_counts,
		"friction_sweep_cap_hits": friction_sweep_cap_hits,
		"initial_position_north_east_m": [float(initial_state[0]), float(initial_state[1])],
		"final_position_north_east_m": [float(final_state[0]), float(final_state[1])],
		"final_speed_m_per_s": sqrt(final_state[3] * final_state[3] + final_state[4] * final_state[4] + final_state[5] * final_state[5]),
		"final_state_sha256": _sha256_bytes(final_state_bytes),
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail("cannot open profile output (error %d)" % FileAccess.get_open_error())
		session.free()
		return
	file.store_string(JSON.stringify(report, "  ", true, true) + "\n")
	file.close()
	session.free()
	print(JSON.stringify({
		"ok": true,
		"output": output_path,
		"tick_cost": measured_summary,
		"paused_guard_cost": report.paused_guard_probe.cost,
		"backend_identity_cost": report.backend_identity_probe.cost,
		"accepted_control_tape_sha256": report.accepted_control_tape_sha256,
		"trajectory_sha256": report.trajectory_sha256,
		"exact_replay": report.exact_replay,
	}, "  ", true, true))
	quit(0)


func _scheduled_controls(absolute_tick: int) -> Dictionary:
	if absolute_tick < WARMUP_TICKS:
		return NEUTRAL.duplicate()
	var measured_tick := absolute_tick - WARMUP_TICKS
	var phase_start := 0
	for phase: Dictionary in MEASURED_PHASES:
		var phase_end := phase_start + int(phase.ticks)
		if measured_tick < phase_end:
			return {
				"throttle": float(phase.throttle),
				"steering": float(phase.steering),
				"brake": float(phase.brake),
				"reverse": false,
				"armed": true,
			}
		phase_start = phase_end
	return NEUTRAL.duplicate()


func _scheduled_control_tape() -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for tick_index in WARMUP_TICKS + MEASURED_TICKS:
		var controls := _scheduled_controls(tick_index)
		result.append(float(controls.throttle))
		result.append(float(controls.steering))
		result.append(float(controls.brake))
		result.append(1.0 if bool(controls.reverse) else 0.0)
	return result


func _phase_report() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start_tick := 0
	for phase: Dictionary in MEASURED_PHASES:
		var tick_count := int(phase.ticks)
		result.append({
			"id": str(phase.id),
			"start_tick": start_tick,
			"end_tick_exclusive": start_tick + tick_count,
			"throttle": float(phase.throttle),
			"steering": float(phase.steering),
			"brake": float(phase.brake),
			"reverse": false,
		})
		start_tick += tick_count
	return result


func _identity_signature(value: Dictionary) -> String:
	var keys := ["backend", "backend_version", "abi_version", "solver_version", "source_sha256",
		"toolchain_sha256", "binary_sha256", "implementation_artifact_kind"]
	var fields: Array[String] = []
	for key in keys:
		# JSON checkpoint numbers decode as float; ABI is an integer contract.
		fields.append(str(int(value.get(key, -1))) if key == "abi_version" else str(value.get(key, "")))
	return "|".join(fields)


func _sha256_bytes(value: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(value)
	return hashing.finish().hex_encode()


func _summary(values: PackedFloat64Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	var p95_index := int(ceil(float(sorted.size() - 1) * 0.95))
	return {
		"samples": sorted.size(),
		"mean_us": total / float(sorted.size()),
		"median_us": sorted[sorted.size() / 2],
		"p95_us": sorted[p95_index],
		"maximum_us": sorted[-1],
		"minimum_us": sorted[0],
	}


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
