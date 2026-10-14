## Measure production Session.tick_once cost with the current generated Bisonte and airfield course.
## Run with the pinned Godot console executable; no rendering or recording is enabled.
extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const MAX_FRICTION_SWEEPS := VehicleDynamics.FRICTION_SWEEPS

const WARMUP_TICKS := 60
const MEASURED_TICKS := 480
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
const DRIVE := {"throttle": 0.55, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
const VEHICLE_DATA_PATH := "res://data/vehicles/ground/mt8_bisonte.json"


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
		_fail("default airfield did not load: " + str(field_result.get("errors", [])))
		return
	var session = Session.new()
	if not session.prepare_airfield(field_result):
		_fail("current default vehicle and airfield did not prepare: " + str(session.load_error))
		session.free()
		return
	if not session.reset("track_start"):
		_fail("authored track_start spawn was not accepted")
		session.free()
		return
	if not session.tick_once(NEUTRAL) or not session.resume():
		_fail("session did not arm and resume: " + str(session.fault_reason))
		session.free()
		return
	var initial_state: PackedFloat64Array = session.state_snapshot()

	var tick_durations := PackedFloat64Array()
	var measured_durations := PackedFloat64Array()
	var friction_sweep_counts := {}
	var friction_sweep_cap_hits := 0
	var maximum_friction_sweeps := 0
	var trajectory_hash := HashingContext.new()
	if trajectory_hash.start(HashingContext.HASH_SHA256) != OK:
		_fail("could not start trajectory digest")
		session.free()
		return
	for tick_index in WARMUP_TICKS + MEASURED_TICKS:
		var started := Time.get_ticks_usec()
		var ok: bool = session.tick_once(DRIVE)
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
			if sweeps >= MAX_FRICTION_SWEEPS:
				friction_sweep_cap_hits += 1
		trajectory_hash.update(session.state_snapshot().to_byte_array())

	var identities: Dictionary = session.identities_snapshot()
	var course: Dictionary = session.course_snapshot()
	var final_state: PackedFloat64Array = session.state_snapshot()
	var measured_summary := _summary(measured_durations)
	var vehicle_hash := FileAccess.get_sha256(VEHICLE_DATA_PATH)
	var report := {
		"format": "openrc-rcv-active-session-profile-v1",
		"engine": Engine.get_version_info().string,
		"debug_build": OS.is_debug_build(),
		"processor": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"backend_identity": VehicleDynamics.backend_identity(),
		"scope": "Session.tick_once at 240 Hz on the production airfield course from track_start; 60 warmup and 480 measured straight-drive ticks; no rendering, recording, or sampler microbenchmark.",
		"vehicle_data_path": VEHICLE_DATA_PATH,
		"vehicle_data_sha256": vehicle_hash,
		"vehicle_identity": identities.get("model", {}),
		"course_identity": identities.get("course", {}),
		"track_id": str(course.get("track", {}).get("id", "")),
		"spawn_id": "track_start",
		"controls": DRIVE,
		"warmup_ticks": WARMUP_TICKS,
		"measured_ticks": MEASURED_TICKS,
		"tick_cost": measured_summary,
		"maximum_friction_sweeps": MAX_FRICTION_SWEEPS,
		"observed_maximum_friction_sweeps": maximum_friction_sweeps,
		"friction_sweep_count_by_sweeps_used": friction_sweep_counts,
		"friction_sweep_cap_hits": friction_sweep_cap_hits,
		"warmup_tick_cost": _summary(tick_durations.slice(0, WARMUP_TICKS)),
		"trajectory_sha256": trajectory_hash.finish().hex_encode(),
		"initial_position_north_east_m": [float(initial_state[0]), float(initial_state[1])],
		"final_position_north_east_m": [float(final_state[0]), float(final_state[1])],
		"final_speed_m_per_s": sqrt(final_state[3] * final_state[3] + final_state[4] * final_state[4] + final_state[5] * final_state[5]),
		"measured_tick_durations_us": measured_durations,
		"session_script_sha256": FileAccess.get_sha256("res://sim/ground_vehicle/session.gd"),
		"dynamics_script_sha256": FileAccess.get_sha256("res://physics/ground_vehicle/vehicle_dynamics.gd"),
		"native_kernel_source_sha256": FileAccess.get_sha256("res://../research/rc-monster-truck/native/src/ground_vehicle_kernel.hpp"),
		"native_wrapper_source_sha256": FileAccess.get_sha256("res://../research/rc-monster-truck/native/src/ground_vehicle_native.cpp"),
		"course_script_sha256": FileAccess.get_sha256("res://physics/ground_vehicle/airfield_course.gd"),
		"track_script_sha256": FileAccess.get_sha256("res://physics/ground_vehicle/airfield_track.gd"),
		"profile_script_sha256": FileAccess.get_sha256("res://../research/rc-monster-truck/performance-r2/bench_active_session.gd"),
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail("cannot open profile output (error %d)" % FileAccess.get_open_error())
		session.free()
		return
	file.store_string(JSON.stringify(report, "  ", true, true) + "\n")
	file.close()
	session.free()
	print(JSON.stringify({"ok": true, "output": output_path, "tick_cost": measured_summary,
		"vehicle_data_sha256": vehicle_hash, "trajectory_sha256": report.trajectory_sha256}, "  ", true, true))
	quit(0)


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
