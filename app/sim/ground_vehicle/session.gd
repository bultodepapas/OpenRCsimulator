## Fixed-tick owner for the experimental RC ground vehicle. This stays separate from
## FlightSession and owns no aircraft data, controls, state layout, or renderer objects.
extends Node
class_name GroundVehicleSession

const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const VehicleData := preload("res://physics/ground_vehicle/vehicle_data.gd")
const Course := preload("res://physics/ground_vehicle/course.gd")
const Math3D := preload("res://physics/math3d.gd")

const FORMAT := "openrc-ground-vehicle-checkpoint v1"
const RECORDING_FORMAT := "openrc-ground-vehicle-recording v1"
const FIXED_HZ := 240
const DT := 1.0 / float(FIXED_HZ)
const STATE_SIZE := 31
const MAX_FRAME_DT_S := 2.0
const CONTROL_LAYOUT := ["throttle", "steering", "brake", "reverse_flag"]
const STATE_LAYOUT := [
	"north_m", "east_m", "down_m", "u_m_per_s", "v_m_per_s", "w_m_per_s",
	"qw", "qx", "qy", "qz", "p_rad_per_s", "q_rad_per_s", "r_rad_per_s",
	"travel_fl_m", "travel_fr_m", "travel_rl_m", "travel_rr_m",
	"travel_rate_fl_m_per_s", "travel_rate_fr_m_per_s", "travel_rate_rl_m_per_s", "travel_rate_rr_m_per_s",
	"wheel_spin_fl_rad_per_s", "wheel_spin_fr_rad_per_s", "wheel_spin_rl_rad_per_s", "wheel_spin_rr_rad_per_s",
	"wheel_angle_fl_rad", "wheel_angle_fr_rad", "wheel_angle_rl_rad", "wheel_angle_rr_rad",
	"steer_angle_rad", "steer_rate_rad_per_s",
]
const CORNERS := ["FL", "FR", "RL", "RR"]
const NEUTRAL_EPSILON := 1.0e-12

signal tick_advanced(tick: int, time_s: float, state: PackedFloat64Array, telemetry: Dictionary)
signal event_added(event: Dictionary)
signal pause_changed(paused: bool)
signal faulted(reason: String)

var prepared := false
var paused := true
var tick := 0
var _state := PackedFloat64Array()
var state: PackedFloat64Array:
	get:
		return _state.duplicate()
	set(value):
		_state = value.duplicate()
var _last_telemetry: Dictionary = {}
var last_telemetry: Dictionary:
	get:
		return _last_telemetry.duplicate(true)
	set(value):
		_last_telemetry = value.duplicate(true)
var _event_tape: Array[Dictionary] = []
## Four float64 values per tick keep complete replay history compact: throttle, steering,
## brake, and reverse-as-0/1. This is about 27.6 MB per simulated hour.
var _control_tape := PackedFloat64Array()
var _recovery_actions: Array[Dictionary] = []
var load_error := ""
var fault_reason := ""
var pause_reason := "prepared"
var run_valid := true
var recording := false
var frame_backlog_s := 0.0
var slowdown_detected := false

var _model: Dictionary = {}
var _course: Dictionary = {}
var _vehicle_result: Dictionary = {}
var _base_vehicle_result: Dictionary = {}
var _course_result: Dictionary = {}
var _model_identity: Dictionary = {}
var _course_identity: Dictionary = {}
var _road: Callable
var _initial_state := PackedFloat64Array()
var _spawn_up_delta_m := 0.0
var spawn_id := ""
var _pause_holds: Dictionary = {}
var _last_sample_is_neutral_armed := false
var _braking_run: Dictionary = {}
var _record_samples: Array[Dictionary] = []
var _recording_start_tick := 0
var _suppress_signals := false


func prepare_default(experiment: Dictionary = {}) -> bool:
	var base_vehicle_result: Dictionary = VehicleData.load_default()
	var vehicle_result := base_vehicle_result
	var course_result: Dictionary = Course.load_default()
	var pose_up_delta_m := 0.0
	if vehicle_result.get("ok", false) and not experiment.is_empty():
		vehicle_result = VehicleData.with_experiment(base_vehicle_result, experiment)
		if vehicle_result.get("ok", false):
			var support_delta := _support_altitude_delta(vehicle_result, base_vehicle_result, course_result)
			if not support_delta.ok:
				load_error = str(support_delta.error)
				return false
			pose_up_delta_m = float(support_delta.delta_m)
	return prepare(vehicle_result, course_result, base_vehicle_result, pose_up_delta_m)


## Build every derived object before replacing a running session. A malformed model/course or
## failed kernel initialization leaves the previous state, identities, tape, and pause untouched.
func prepare(vehicle_result: Dictionary, course_result: Dictionary,
		baseline_vehicle_result: Dictionary = {}, pose_up_delta_m: float = 0.0) -> bool:
	if recording:
		load_error = "stop and export the current recording before preparing another session"
		return false
	var baseline := vehicle_result if baseline_vehicle_result.is_empty() else baseline_vehicle_result
	var staged := _stage_session(vehicle_result, course_result, "", baseline, pose_up_delta_m)
	if not staged.ok:
		load_error = "; ".join(staged.errors)
		return false
	_commit_prepared(staged)
	load_error = ""
	return true


func _stage_session(vehicle_result: Dictionary, course_result: Dictionary, requested_spawn: String,
		baseline_vehicle_result: Dictionary, pose_up_delta_m: float) -> Dictionary:
	var errors := PackedStringArray()
	if not vehicle_result.get("ok", false):
		return {"ok": false, "errors": _result_errors(vehicle_result, "vehicle data did not load")}
	if not course_result.get("ok", false):
		return {"ok": false, "errors": _result_errors(course_result, "course data did not load")}
	var model_value: Variant = vehicle_result.get("model")
	var course_value: Variant = course_result.get("course")
	var model_id_value: Variant = vehicle_result.get("identity")
	var course_id_value: Variant = course_result.get("identity")
	if typeof(model_value) != TYPE_DICTIONARY or typeof(course_value) != TYPE_DICTIONARY:
		errors.append("vehicle and course results must contain normalized dictionaries")
	if typeof(model_id_value) != TYPE_DICTIONARY or not _identity_is_valid(model_id_value):
		errors.append("vehicle identity is malformed")
	if typeof(course_id_value) != TYPE_DICTIONARY or not _identity_is_valid(course_id_value):
		errors.append("course identity is malformed")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}

	var model_copy: Dictionary = model_value.duplicate(true)
	var course_copy: Dictionary = course_value.duplicate(true)
	var vehicle_copy: Dictionary = vehicle_result.duplicate(true)
	var base_vehicle_copy: Dictionary = baseline_vehicle_result.duplicate(true)
	var course_result_copy: Dictionary = course_result.duplicate(true)
	var staged_spawn := _find_spawn(course_copy, requested_spawn)
	if not staged_spawn.ok:
		return {"ok": false, "errors": PackedStringArray([str(staged_spawn.error)])}
	if not is_finite(pose_up_delta_m):
		return {"ok": false, "errors": PackedStringArray(["spawn CG-height adjustment must be finite"])}
	var spawn_pose: Dictionary = staged_spawn.pose.duplicate(true)
	spawn_pose.vehicle_up_m = float(spawn_pose.vehicle_up_m) + pose_up_delta_m
	var road := _make_road(course_copy)
	var initial: Variant = VehicleDynamics.make_state(model_copy, spawn_pose, road)
	if not _state_is_valid(initial):
		return {"ok": false, "errors": PackedStringArray(["vehicle kernel could not initialize the selected course spawn"])}
	var telemetry: Dictionary = VehicleDynamics.telemetry(initial, model_copy, road)
	if not _telemetry_is_valid(telemetry):
		return {"ok": false, "errors": PackedStringArray([str(telemetry.get("error", "initial vehicle telemetry is invalid"))])}
	return {
		"ok": true,
		"vehicle_result": vehicle_copy,
		"base_vehicle_result": base_vehicle_copy,
		"course_result": course_result_copy,
		"model": model_copy,
		"course": course_copy,
		"model_identity": model_id_value.duplicate(true),
		"course_identity": course_id_value.duplicate(true),
		"road": road,
		"initial_state": initial.duplicate(),
		"telemetry": telemetry.duplicate(true),
		"spawn_id": str(spawn_pose.id),
		"spawn_up_delta_m": pose_up_delta_m,
	}


func _commit_prepared(staged: Dictionary) -> void:
	_model = staged.model
	_course = staged.course
	_vehicle_result = staged.vehicle_result
	_base_vehicle_result = staged.base_vehicle_result
	_course_result = staged.course_result
	_model_identity = staged.model_identity
	_course_identity = staged.course_identity
	_road = staged.road
	_initial_state = staged.initial_state
	_spawn_up_delta_m = float(staged.spawn_up_delta_m)
	_state = _initial_state.duplicate()
	_last_telemetry = staged.telemetry
	spawn_id = staged.spawn_id
	prepared = true
	tick = 0
	pause_reason = "prepared"
	_event_tape.clear()
	_control_tape.clear()
	_recovery_actions.clear()
	_record_samples.clear()
	recording = false
	run_valid = true
	fault_reason = ""
	_braking_run.clear()
	frame_backlog_s = 0.0
	slowdown_detected = false
	_last_sample_is_neutral_armed = false
	_set_paused(true)


func reset(selected_spawn_id: String = "") -> bool:
	if recording:
		load_error = "stop and export the current recording before resetting"
		return false
	if not prepared:
		load_error = "session is not prepared"
		return false
	var staged := _stage_session(_vehicle_result, _course_result, selected_spawn_id,
		_base_vehicle_result, _spawn_up_delta_m)
	if not staged.ok:
		load_error = "; ".join(staged.errors)
		return false
	var holds := _pause_holds.duplicate(true)
	_commit_prepared(staged)
	_pause_holds = holds
	_set_paused(true)
	load_error = ""
	return true


func set_experiment(parameters: Dictionary) -> bool:
	if not prepared or not paused or recording:
		load_error = "vehicle experiments require a prepared, paused session with recording stopped"
		return false
	var changed: Dictionary = VehicleData.with_experiment(_base_vehicle_result, parameters)
	if not changed.get("ok", false):
		load_error = "; ".join(_result_errors(changed, "experiment parameters were rejected"))
		return false
	var support_delta := _support_altitude_delta(changed, _base_vehicle_result, _course_result)
	if not support_delta.ok:
		load_error = str(support_delta.error)
		return false
	var pose_up_delta_m := float(support_delta.delta_m)
	return prepare(changed, _course_result, _base_vehicle_result, pose_up_delta_m)


func fixed_dt() -> float:
	return DT


func time_s() -> float:
	return float(tick) * DT


func state_snapshot() -> PackedFloat64Array:
	return _state.duplicate()


func telemetry_snapshot() -> Dictionary:
	return _last_telemetry.duplicate(true)


func event_tape_snapshot() -> Array[Dictionary]:
	return _event_tape.duplicate(true)


func control_tape_snapshot() -> PackedFloat64Array:
	return _control_tape.duplicate()


func recovery_actions_snapshot() -> Array[Dictionary]:
	return _recovery_actions.duplicate(true)


func identities_snapshot() -> Dictionary:
	return {"model": _model_identity.duplicate(true), "course": _course_identity.duplicate(true)}


func model_snapshot() -> Dictionary:
	return _model.duplicate(true)


func course_snapshot() -> Dictionary:
	return _course.duplicate(true)


func is_paused() -> bool:
	return paused


func pause(reason: String = "user") -> void:
	pause_reason = reason if not reason.strip_edges().is_empty() else "user"
	load_error = ""
	_set_paused(true)


func add_pause_hold(reason: String) -> bool:
	if reason.strip_edges().is_empty():
		return false
	_pause_holds[reason] = true
	pause_reason = reason
	_set_paused(true)
	return true


func hold(reason: String) -> bool:
	return add_pause_hold(reason)


## Releasing a modal/focus hold never resumes. The caller must make a separate resume request.
func release_pause_hold(reason: String) -> bool:
	if not _pause_holds.has(reason):
		return false
	_pause_holds.erase(reason)
	return true


func pause_holds() -> PackedStringArray:
	var names := PackedStringArray()
	for key in _pause_holds.keys():
		names.append(str(key))
	names.sort()
	return names


func resume() -> bool:
	if not prepared or not fault_reason.is_empty() or not _pause_holds.is_empty() \
			or not _last_sample_is_neutral_armed:
		return false
	_set_paused(false)
	pause_reason = ""
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		add_pause_hold("focus")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		release_pause_hold("focus")


## Called exactly once by the scene's 240 Hz physics tick. The last neutral+armed sample is
## observed while paused so an explicit resume cannot reuse a held key or controller trigger.
func tick_once(sample: Dictionary) -> bool:
	if not prepared:
		return false
	var parsed := _parse_controls(sample, true)
	if not parsed.ok:
		_fail_safe(str(parsed.error))
		return false
	_last_sample_is_neutral_armed = parsed.neutral and parsed.armed
	if paused:
		return true
	if not _state_is_valid(_state):
		_fail_safe("ground-vehicle state became invalid before tick")
		return false
	var next_state: PackedFloat64Array = VehicleDynamics.step(_state, _model, parsed.controls, DT, _road)
	if not _state_is_valid(next_state):
		_fail_safe("ground-vehicle kernel rejected the tick or returned nonfinite state")
		return false
	var next_telemetry: Dictionary = VehicleDynamics.telemetry(next_state, _model, _road)
	if not _telemetry_is_valid(next_telemetry):
		_fail_safe(str(next_telemetry.get("error", "ground-vehicle telemetry failed")))
		return false
	var next_tick := tick + 1
	var new_events: Array[Dictionary] = []
	var next_braking := _braking_run.duplicate(true)
	_observe_events(_state, next_state, _last_telemetry, next_telemetry, parsed.controls, next_tick, new_events, next_braking)
	_state = next_state
	tick = next_tick
	_last_telemetry = next_telemetry
	_braking_run = next_braking
	_append_control(parsed.controls)
	for event in new_events:
		_event_tape.append(event)
	if recording:
		_capture_record_sample(parsed.controls)
	if not _suppress_signals:
		tick_advanced.emit(tick, time_s(), _state.duplicate(), _last_telemetry.duplicate(true))
		for event in new_events:
			event_added.emit(event.duplicate(true))
	return true


## Render-frame adapter is available to harnesses that do not own the engine physics callback.
## It caps work but preserves accumulated time and reports backlog; it never drops simulation ticks.
func advance(frame_dt: float, sample: Dictionary, max_ticks: int = 8) -> int:
	if not is_finite(frame_dt) or frame_dt < 0.0 or frame_dt > MAX_FRAME_DT_S or max_ticks <= 0:
		load_error = "frame delta or tick cap is invalid"
		return 0
	if paused:
		frame_backlog_s = 0.0
		slowdown_detected = false
		tick_once(sample)
		return 0
	frame_backlog_s += frame_dt
	var available := int(floor((frame_backlog_s + DT * 1.0e-9) / DT))
	var count := mini(available, max_ticks)
	for _index in count:
		if not tick_once(sample):
			return _index
		frame_backlog_s -= DT
	frame_backlog_s = maxf(frame_backlog_s, 0.0)
	slowdown_detected = available > count
	return count


func manual_recovery() -> bool:
	if not prepared:
		return false
	var pose := _find_spawn(_course, spawn_id)
	if not pose.ok:
		load_error = str(pose.error)
		return false
	var recovered: Variant = VehicleDynamics.make_state(_model, pose.pose, _road)
	if not _state_is_valid(recovered):
		load_error = "manual recovery pose was rejected"
		return false
	var telemetry: Dictionary = VehicleDynamics.telemetry(recovered, _model, _road)
	if not _telemetry_is_valid(telemetry):
		load_error = str(telemetry.get("error", "manual recovery telemetry failed"))
		return false
	_state = recovered
	_last_telemetry = telemetry
	run_valid = false
	fault_reason = ""
	_braking_run.clear()
	var event := {"type": "manual_recovery", "tick": tick, "time_s": time_s(), "spawn_id": spawn_id}
	_event_tape.append(event)
	_recovery_actions.append({"type": "manual_recovery", "tick": tick, "spawn_id": spawn_id})
	if recording:
		_capture_record_sample(_neutral_controls())
	if not _suppress_signals:
		event_added.emit(event.duplicate(true))
	load_error = ""
	_last_sample_is_neutral_armed = false
	pause_reason = "manual recovery"
	_set_paused(true)
	return true


func replay(controls: Variant, actions: Array = []) -> bool:
	if not prepared or recording:
		load_error = "replay requires a prepared session with recording stopped"
		return false
	var controls_result := _expand_control_tape(controls)
	if not controls_result.ok:
		load_error = str(controls_result.error)
		return false
	var staged_controls: Array[Dictionary] = controls_result.controls
	var staged_actions: Array[Dictionary] = []
	var previous_action_tick := -1
	for item in actions:
		if typeof(item) != TYPE_DICTIONARY or item.get("type") != "manual_recovery" \
				or typeof(item.get("tick")) != TYPE_INT or int(item.tick) < previous_action_tick \
				or int(item.tick) < 0 or int(item.tick) > staged_controls.size() \
				or str(item.get("spawn_id", "")) != spawn_id:
			load_error = "replay actions are malformed or refer to another spawn"
			return false
		previous_action_tick = int(item.tick)
		staged_actions.append(item.duplicate(true))
	var before := checkpoint()
	if before.is_empty():
		load_error = "current session cannot produce a replay rollback checkpoint"
		return false
	var ok := _replay_validated(staged_controls, staged_actions)
	if ok:
		load_error = ""
		return true
	var replay_error := load_error
	restore_checkpoint(before)
	load_error = replay_error
	return false


func _replay_validated(controls: Array[Dictionary], actions: Array[Dictionary]) -> bool:
	_suppress_signals = true
	if not reset(spawn_id):
		_suppress_signals = false
		return false
	tick_once({"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false,
		"armed": true})
	if not resume():
		_suppress_signals = false
		load_error = "replay could not arm its neutral start"
		return false
	var action_index := 0
	for index in range(controls.size() + 1):
		while action_index < actions.size() and int(actions[action_index].tick) == tick:
			if not manual_recovery():
				_suppress_signals = false
				return false
			action_index += 1
		if index < controls.size():
			if not tick_once(controls[index]):
				_suppress_signals = false
				return false
	if action_index != actions.size():
		_suppress_signals = false
		load_error = "replay actions could not be applied at their tick"
		return false
	_suppress_signals = false
	_set_paused(true)
	return true


func checkpoint() -> Dictionary:
	if not prepared or not _state_is_valid(_state) or _control_tape.size() != tick * 4:
		return {}
	var candidate := {
		"format": FORMAT,
		"fixed_hz": FIXED_HZ,
		"dt": DT,
		"tick": tick,
		"time_s": time_s(),
		"model_identity": _model_identity.duplicate(true),
		"course_identity": _course_identity.duplicate(true),
		"spawn_id": spawn_id,
		"control_layout": CONTROL_LAYOUT.duplicate(),
		"state": _state.duplicate(),
		"state_sha256": _hash_bytes(_state.to_byte_array()),
		"control_tape": _control_tape.duplicate(),
		"control_tape_sha256": _hash_bytes(_control_tape.to_byte_array()),
		"recovery_actions": _recovery_actions.duplicate(true),
		"event_tape": _event_tape.duplicate(true),
		"event_tape_sha256": _hash_variant(_event_tape),
		"braking_run": _braking_run.duplicate(true),
		"run_valid": run_valid,
	}
	candidate["checkpoint_sha256"] = _checkpoint_hash(candidate)
	return candidate


func can_restore_checkpoint(candidate: Variant) -> bool:
	if not prepared or recording or typeof(candidate) != TYPE_DICTIONARY:
		return false
	if candidate.get("format") != FORMAT or candidate.get("fixed_hz") != FIXED_HZ \
			or candidate.get("control_layout") != CONTROL_LAYOUT \
			or typeof(candidate.get("dt")) not in [TYPE_FLOAT, TYPE_INT] \
			or absf(float(candidate.dt) - DT) > 1.0e-15:
		return false
	if not _identity_equal(candidate.get("model_identity", {}), _model_identity) \
			or not _identity_equal(candidate.get("course_identity", {}), _course_identity):
		return false
	if typeof(candidate.get("spawn_id")) != TYPE_STRING or not _find_spawn(_course, str(candidate.spawn_id)).ok:
		return false
	if typeof(candidate.get("tick")) != TYPE_INT or int(candidate.tick) < 0 \
			or typeof(candidate.get("time_s")) not in [TYPE_FLOAT, TYPE_INT] \
			or absf(float(candidate.time_s) - float(candidate.tick) * DT) > 1.0e-12:
		return false
	var candidate_state := _as_float64_array(candidate.get("state"), STATE_SIZE)
	if not _state_is_valid(candidate_state) \
			or _hash_bytes(candidate_state.to_byte_array()) != str(candidate.get("state_sha256", "")):
		return false
	var controls_value: Variant = candidate.get("control_tape")
	var actions_value: Variant = candidate.get("recovery_actions")
	var events_value: Variant = candidate.get("event_tape")
	var packed_controls := _as_control_tape(controls_value)
	if typeof(controls_value) not in [TYPE_PACKED_FLOAT64_ARRAY, TYPE_ARRAY] \
			or packed_controls.size() != controls_value.size() \
			or (packed_controls.is_empty() and int(candidate.tick) > 0) \
			or packed_controls.size() != int(candidate.tick) * 4 \
			or typeof(actions_value) != TYPE_ARRAY or typeof(events_value) != TYPE_ARRAY:
		return false
	if not _expand_control_tape(packed_controls).ok:
		return false
	if not _actions_are_valid(actions_value, int(candidate.tick), str(candidate.spawn_id)) \
			or not _events_are_valid(events_value, int(candidate.tick)):
		return false
	if _hash_bytes(packed_controls.to_byte_array()) != str(candidate.get("control_tape_sha256", "")) \
			or _hash_variant(events_value) != str(candidate.get("event_tape_sha256", "")):
		return false
	if typeof(candidate.get("run_valid")) != TYPE_BOOL or typeof(candidate.get("braking_run")) != TYPE_DICTIONARY:
		return false
	if not _braking_state_is_valid(candidate.braking_run, int(candidate.tick)):
		return false
	if _checkpoint_hash(candidate) != str(candidate.get("checkpoint_sha256", "")):
		return false
	var telemetry: Dictionary = VehicleDynamics.telemetry(candidate_state, _model, _road)
	return _telemetry_is_valid(telemetry)


func restore_checkpoint(candidate: Variant) -> bool:
	if not can_restore_checkpoint(candidate):
		return false
	var next_state := _as_float64_array(candidate.state, STATE_SIZE)
	var next_telemetry: Dictionary = VehicleDynamics.telemetry(next_state, _model, _road)
	if not _telemetry_is_valid(next_telemetry):
		return false
	_state = next_state
	tick = int(candidate.tick)
	spawn_id = str(candidate.spawn_id)
	_control_tape = _as_control_tape(candidate.control_tape)
	_recovery_actions = candidate.recovery_actions.duplicate(true)
	_event_tape = candidate.event_tape.duplicate(true)
	_braking_run = candidate.braking_run.duplicate(true)
	_last_telemetry = next_telemetry
	run_valid = bool(candidate.run_valid)
	fault_reason = ""
	pause_reason = "checkpoint restored"
	_record_samples.clear()
	recording = false
	_last_sample_is_neutral_armed = false
	_set_paused(true)
	return true


func start_recording() -> bool:
	if not prepared or recording:
		return false
	_record_samples.clear()
	_recording_start_tick = tick
	recording = true
	_capture_record_sample(_neutral_controls())
	return true


func stop_recording() -> bool:
	if not recording:
		return false
	recording = false
	return true


## Export only to user://rcv/. `name` is a basename, never a path. Existing files are preserved.
func export_recording(name: String) -> Dictionary:
	if recording or _record_samples.is_empty():
		return {"ok": false, "error": "stop a non-empty recording before export"}
	var safe_name := _safe_recording_name(name)
	if safe_name.is_empty():
		return {"ok": false, "error": "recording name must be a simple 1-64 character filename stem"}
	var directory := ProjectSettings.globalize_path("user://rcv")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(directory)
	if mkdir_error != OK and not DirAccess.dir_exists_absolute(directory):
		return {"ok": false, "error": "could not create user://rcv/ (%s)" % error_string(mkdir_error)}
	var csv_path := directory.path_join(safe_name + ".csv")
	var json_path := directory.path_join(safe_name + ".json")
	var csv_temp := csv_path + ".tmp"
	var json_temp := json_path + ".tmp"
	if FileAccess.file_exists(csv_path) or FileAccess.file_exists(json_path) \
			or FileAccess.file_exists(csv_temp) or FileAccess.file_exists(json_temp):
		return {"ok": false, "error": "recording output already exists; choose a new name"}
	var csv_text := _recording_csv()
	var metadata := _recording_metadata()
	var json_text := JSON.stringify(metadata, "\t", true, true) + "\n"
	var csv_error := _write_new_file(csv_temp, csv_text)
	if not csv_error.is_empty():
		return {"ok": false, "error": csv_error}
	var json_error := _write_new_file(json_temp, json_text)
	if not json_error.is_empty():
		DirAccess.remove_absolute(csv_temp)
		return {"ok": false, "error": json_error}
	var rename_error := DirAccess.rename_absolute(csv_temp, csv_path)
	if rename_error != OK:
		DirAccess.remove_absolute(csv_temp)
		DirAccess.remove_absolute(json_temp)
		return {"ok": false, "error": "could not commit CSV recording (%s)" % error_string(rename_error)}
	rename_error = DirAccess.rename_absolute(json_temp, json_path)
	if rename_error != OK:
		DirAccess.remove_absolute(csv_path)
		DirAccess.remove_absolute(json_temp)
		return {"ok": false, "error": "could not commit JSON metadata (%s)" % error_string(rename_error)}
	return {"ok": true, "csv_path": "user://rcv/" + safe_name + ".csv",
		"metadata_path": "user://rcv/" + safe_name + ".json", "samples": _record_samples.size()}


func _capture_record_sample(controls: Dictionary) -> void:
	_record_samples.append({"tick": tick, "time_s": time_s(), "controls": controls.duplicate(true),
		"state": _state.duplicate(), "telemetry": _last_telemetry.duplicate(true)})


func _recording_csv() -> String:
	var lines := PackedStringArray()
	lines.append("# " + RECORDING_FORMAT)
	lines.append("tick,time_s,throttle,steering,brake,reverse,state_json,telemetry_json")
	for row in _record_samples:
		var controls: Dictionary = row.controls
		var state_json := JSON.stringify(row.state, "", false, true)
		var telemetry_json := JSON.stringify(row.telemetry, "", true, true)
		lines.append("%d,%.17g,%.17g,%.17g,%.17g,%s,%s,%s" % [
			int(row.tick), float(row.time_s), float(controls.throttle), float(controls.steering),
			float(controls.brake), str(bool(controls.reverse)).to_lower(), _csv_quote(state_json), _csv_quote(telemetry_json)])
	return "\n".join(lines) + "\n"


func _recording_metadata() -> Dictionary:
	return {
		"format": RECORDING_FORMAT,
		"version": 1,
		"fixed_hz": FIXED_HZ,
		"dt_s": DT,
		"state_layout": STATE_LAYOUT.duplicate(),
		"control_layout": CONTROL_LAYOUT.duplicate(),
		"corner_order": CORNERS.duplicate(),
		"model_identity": _model_identity.duplicate(true),
		"course_identity": _course_identity.duplicate(true),
		"spawn_id": spawn_id,
		"start_tick": _recording_start_tick,
		"end_tick": tick,
		"sample_count": _record_samples.size(),
		"run_valid": run_valid,
		"events": _event_tape.duplicate(true),
		"control_tape_sha256": _hash_bytes(_control_tape.to_byte_array()),
		"recorded_samples_sha256": _hash_variant(_record_samples),
	}


func _write_new_file(path: String, content: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "could not open recording output (%s)" % error_string(FileAccess.get_open_error())
	file.store_string(content)
	file.flush()
	var status := file.get_error()
	file.close()
	return "could not write recording output (%s)" % error_string(status) if status != OK else ""


func _csv_quote(value: String) -> String:
	return "\"" + value.replace("\"", "\"\"") + "\""


func _safe_recording_name(value: String) -> String:
	if value.length() < 1 or value.length() > 64:
		return ""
	var regex := RegEx.new()
	if regex.compile("^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$") != OK:
		return ""
	return value if regex.search(value) != null else ""


func _observe_events(previous_state: PackedFloat64Array, next_state: PackedFloat64Array,
		previous: Dictionary, current: Dictionary, controls: Dictionary, at_tick: int,
		events: Array[Dictionary], braking: Dictionary) -> void:
	var was_airborne := bool(previous.get("airborne", false))
	var is_airborne := bool(current.get("airborne", false))
	if is_airborne and not was_airborne:
		events.append({"type": "jump", "tick": at_tick, "time_s": float(at_tick) * DT,
			"speed_m_per_s": float(current.get("speed_m_per_s", 0.0))})
	elif was_airborne and not is_airborne:
		events.append({"type": "landing", "tick": at_tick, "time_s": float(at_tick) * DT,
			"speed_m_per_s": float(current.get("speed_m_per_s", 0.0))})

	var brake_active := float(controls.brake) > 0.05
	var forward_speed := absf(float(previous.get("forward_speed_m_per_s", previous.get("speed_m_per_s", 0.0))))
	if brake_active and braking.is_empty() and forward_speed > 0.5:
		braking.assign({"start_tick": at_tick - 1, "start_speed_m_per_s": forward_speed, "distance_m": 0.0})
	if not braking.is_empty():
		var north_delta := next_state[0] - previous_state[0]
		var east_delta := next_state[1] - previous_state[1]
		braking.distance_m = float(braking.distance_m) + Math3D.sqrt_(north_delta * north_delta + east_delta * east_delta)
		var speed := absf(float(current.get("forward_speed_m_per_s", current.get("speed_m_per_s", 0.0))))
		if not brake_active or speed <= 0.2:
			events.append({"type": "braking_distance", "start_tick": int(braking.start_tick),
				"end_tick": at_tick, "time_s": float(at_tick) * DT, "distance_m": float(braking.distance_m),
				"initial_speed_m_per_s": float(braking.start_speed_m_per_s), "end_speed_m_per_s": speed})
			braking.clear()


func _find_spawn(course_value: Dictionary, requested: String) -> Dictionary:
	var spawns: Variant = course_value.get("spawns", [])
	if typeof(spawns) != TYPE_ARRAY or spawns.is_empty():
		return {"ok": false, "error": "course declares no vehicle spawns"}
	var chosen: Dictionary = {}
	for raw_spawn in spawns:
		if typeof(raw_spawn) != TYPE_DICTIONARY:
			return {"ok": false, "error": "course spawn record is malformed"}
		if requested.is_empty() and (str(raw_spawn.get("id", "")) == "default" or chosen.is_empty()):
			chosen = raw_spawn
		elif str(raw_spawn.get("id", "")) == requested:
			chosen = raw_spawn
	if chosen.is_empty():
		return {"ok": false, "error": "course has no spawn named '%s'" % requested}
	var pose := {
		"id": str(chosen.get("id", "")),
		"north_m": chosen.get("north_m", NAN),
		"east_m": chosen.get("east_m", NAN),
		"heading_rad": chosen.get("heading_rad", NAN),
		"vehicle_up_m": chosen.get("vehicle_up_m", NAN),
	}
	if pose.id.is_empty():
		return {"ok": false, "error": "course spawn needs a non-empty id"}
	for key in ["north_m", "east_m", "heading_rad", "vehicle_up_m"]:
		if typeof(pose[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(pose[key])):
			return {"ok": false, "error": "course spawn %s is invalid" % key}
	return {"ok": true, "pose": pose}


func _parse_controls(value: Dictionary, read_arming: bool) -> Dictionary:
	var parsed := _neutral_controls()
	for key in ["throttle", "steering", "brake"]:
		var raw: Variant = value.get(key, NAN)
		if typeof(raw) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(raw)):
			return {"ok": false, "error": "control %s must be finite" % key}
		parsed[key] = float(raw)
	if typeof(value.get("reverse")) != TYPE_BOOL:
		return {"ok": false, "error": "control reverse must be boolean"}
	parsed.reverse = value.reverse
	if float(parsed.throttle) < 0.0 or float(parsed.throttle) > 1.0 \
			or float(parsed.steering) < -1.0 or float(parsed.steering) > 1.0 \
			or float(parsed.brake) < 0.0 or float(parsed.brake) > 1.0:
		return {"ok": false, "error": "control is outside its normalized range"}
	var neutral := float(parsed.throttle) <= NEUTRAL_EPSILON and absf(float(parsed.steering)) <= NEUTRAL_EPSILON \
		and float(parsed.brake) <= NEUTRAL_EPSILON and not bool(parsed.reverse)
	var armed := true
	if read_arming:
		if value.has("armed") and typeof(value.armed) != TYPE_BOOL:
			return {"ok": false, "error": "input armed flag must be boolean"}
		armed = bool(value.get("armed", false))
	return {"ok": true, "controls": parsed, "neutral": neutral, "armed": armed}


func _append_control(controls: Dictionary) -> void:
	_control_tape.append_array(PackedFloat64Array([
		float(controls.throttle), float(controls.steering), float(controls.brake),
		1.0 if bool(controls.reverse) else 0.0,
	]))


func _as_float64_array(value: Variant, expected_size: int = -1) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	if typeof(value) == TYPE_PACKED_FLOAT64_ARRAY:
		result = value.duplicate()
	elif typeof(value) == TYPE_ARRAY:
		for raw in value:
			if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or typeof(raw) == TYPE_BOOL \
					or not is_finite(float(raw)):
				return PackedFloat64Array()
			result.append(float(raw))
	else:
		return PackedFloat64Array()
	if expected_size >= 0 and result.size() != expected_size:
		return PackedFloat64Array()
	for item in result:
		if not is_finite(float(item)):
			return PackedFloat64Array()
	return result


func _as_control_tape(value: Variant) -> PackedFloat64Array:
	if typeof(value) not in [TYPE_PACKED_FLOAT64_ARRAY, TYPE_ARRAY]:
		return PackedFloat64Array()
	var result := _as_float64_array(value)
	if result.size() % 4 != 0 or result.size() != value.size():
		return PackedFloat64Array()
	return result


func _expand_control_tape(value: Variant) -> Dictionary:
	var staged: Array[Dictionary] = []
	var packed := _as_control_tape(value)
	var numeric_array: bool = typeof(value) == TYPE_ARRAY and (value.is_empty() \
		or typeof(value[0]) in [TYPE_INT, TYPE_FLOAT])
	if typeof(value) == TYPE_PACKED_FLOAT64_ARRAY or numeric_array:
		if packed.size() != value.size():
			return {"ok": false, "error": "packed replay tape must contain finite float64 groups of four"}
		for offset in range(0, packed.size(), 4):
			var reverse_value := float(packed[offset + 3])
			if reverse_value != 0.0 and reverse_value != 1.0:
				return {"ok": false, "error": "packed replay reverse flag must be 0 or 1"}
			var item := {"throttle": packed[offset], "steering": packed[offset + 1],
				"brake": packed[offset + 2], "reverse": reverse_value == 1.0}
			var parsed := _parse_controls(item, false)
			if not parsed.ok:
				return {"ok": false, "error": str(parsed.error)}
			staged.append(parsed.controls)
	elif typeof(value) == TYPE_ARRAY:
		for item in value:
			if typeof(item) != TYPE_DICTIONARY:
				return {"ok": false, "error": "replay controls contain a malformed tick"}
			var parsed := _parse_controls(item, false)
			if not parsed.ok:
				return {"ok": false, "error": str(parsed.error)}
			staged.append(parsed.controls)
	else:
		return {"ok": false, "error": "replay controls must be a packed tape or dictionary array"}
	return {"ok": true, "controls": staged}


func _make_road(course_value: Dictionary) -> Callable:
	return func(north_m: float, east_m: float) -> Dictionary:
		return Course.sample(course_value, north_m, east_m)


## Keep the chassis datum at the authored spawn when mass, CG, springs, or tire stiffness change.
## Kernel initialization computes the corresponding model-specific supported CG altitude, so this
## difference includes static suspension sag and tire compression as well as geometry.
func _support_altitude_delta(experiment: Dictionary, baseline: Dictionary,
		course_result: Dictionary) -> Dictionary:
	var experiment_model: Variant = experiment.get("model")
	var baseline_model: Variant = baseline.get("model")
	var course_value: Variant = course_result.get("course")
	if typeof(experiment_model) != TYPE_DICTIONARY or typeof(baseline_model) != TYPE_DICTIONARY \
			or typeof(course_value) != TYPE_DICTIONARY:
		return {"ok": false, "error": "cannot estimate experiment support altitude from incomplete model/course data"}
	var road := _make_road(course_value.duplicate(true))
	var experiment_support: Dictionary = VehicleDynamics.initialize(experiment_model, road, 0.0, 0.0)
	var baseline_support: Dictionary = VehicleDynamics.initialize(baseline_model, road, 0.0, 0.0)
	if not experiment_support.get("ok", false) or not baseline_support.get("ok", false):
		return {"ok": false, "error": "kernel could not compute baseline and experiment support altitudes"}
	var experiment_state: Variant = experiment_support.get("state")
	var baseline_state: Variant = baseline_support.get("state")
	if not _state_is_valid(experiment_state) or not _state_is_valid(baseline_state):
		return {"ok": false, "error": "kernel returned invalid state while estimating support altitude"}
	var delta_m := float(baseline_state[2]) - float(experiment_state[2])
	if not is_finite(delta_m):
		return {"ok": false, "error": "experiment support-altitude adjustment is nonfinite"}
	return {"ok": true, "delta_m": delta_m}


func _neutral_controls() -> Dictionary:
	return {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false}


func _identity_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	for key in ["format", "version", "id", "sha256"]:
		if typeof(value.get(key)) != TYPE_STRING or str(value[key]).is_empty():
			return false
	var digest := str(value.sha256)
	if digest.length() != 64 or digest.to_lower() != digest:
		return false
	for character in digest:
		if not str(character) in "0123456789abcdef":
			return false
	return true


func _identity_equal(left: Variant, right: Dictionary) -> bool:
	return typeof(left) == TYPE_DICTIONARY and _identity_is_valid(left) \
		and JSON.stringify(left, "", true, true) == JSON.stringify(right, "", true, true)


func _state_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != STATE_SIZE:
		return false
	for item in value:
		if not is_finite(float(item)):
			return false
	return true


func _telemetry_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or not value.get("ok", false):
		return false
	for key in ["speed_m_per_s", "forward_speed_m_per_s"]:
		var scalar: Variant = value.get(key, NAN)
		if typeof(scalar) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(scalar)):
			return false
	for key in ["wheel_load_n", "wheel_slip_ratio", "wheel_slip_angle_rad", "wheel_in_contact"]:
		var wheel_values: Variant = value.get(key)
		if typeof(wheel_values) not in [TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_BYTE_ARRAY] or wheel_values.size() != 4:
			return false
		if typeof(wheel_values) == TYPE_PACKED_FLOAT64_ARRAY:
			for item in wheel_values:
				if not is_finite(float(item)):
					return false
	return typeof(value.get("airborne")) == TYPE_BOOL


func _actions_are_valid(actions: Array, max_tick: int, expected_spawn: String) -> bool:
	var last_tick := -1
	for item in actions:
		if typeof(item) != TYPE_DICTIONARY or item.get("type") != "manual_recovery" \
				or typeof(item.get("tick")) != TYPE_INT or int(item.tick) < last_tick \
				or int(item.tick) < 0 or int(item.tick) > max_tick \
				or str(item.get("spawn_id", "")) != expected_spawn:
			return false
		last_tick = int(item.tick)
	return true


func _events_are_valid(events: Array, max_tick: int) -> bool:
	for item in events:
		if typeof(item) != TYPE_DICTIONARY or typeof(item.get("type")) != TYPE_STRING \
				or typeof(item.get("tick")) != TYPE_INT or int(item.tick) < 0 or int(item.tick) > max_tick:
			return false
		for raw_value in item.values():
			if typeof(raw_value) in [TYPE_FLOAT, TYPE_INT] and not is_finite(float(raw_value)):
				return false
	return true


func _braking_state_is_valid(braking: Dictionary, at_tick: int) -> bool:
	if braking.is_empty():
		return true
	for key in ["start_tick", "start_speed_m_per_s", "distance_m"]:
		if not braking.has(key):
			return false
	if typeof(braking.start_tick) != TYPE_INT or int(braking.start_tick) < 0 or int(braking.start_tick) > at_tick:
		return false
	for key in ["start_speed_m_per_s", "distance_m"]:
		if typeof(braking[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(braking[key])) or float(braking[key]) < 0.0:
			return false
	return true


func _checkpoint_hash(value: Dictionary) -> String:
	var content := value.duplicate(true)
	content.erase("checkpoint_sha256")
	return _hash_variant(content)


func _hash_variant(value: Variant) -> String:
	return _hash_bytes(JSON.stringify(value, "", true, true).to_utf8_buffer())


func _hash_bytes(value: PackedByteArray) -> String:
	var digest := HashingContext.new()
	if digest.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if digest.update(value) != OK:
		return ""
	return digest.finish().hex_encode()


func _result_errors(result: Dictionary, fallback: String) -> PackedStringArray:
	var raw: Variant = result.get("errors", [])
	if typeof(raw) == TYPE_PACKED_STRING_ARRAY and not raw.is_empty():
		return raw
	if typeof(raw) == TYPE_ARRAY and not raw.is_empty():
		var errors := PackedStringArray()
		for item in raw:
			errors.append(str(item))
		return errors
	return PackedStringArray([fallback])


func _set_paused(value: bool) -> void:
	if not value and (not _pause_holds.is_empty() or not fault_reason.is_empty()):
		return
	if paused != value:
		paused = value
		if not _suppress_signals:
			pause_changed.emit(paused)


func _fail_safe(reason: String) -> void:
	fault_reason = reason
	_set_paused(true)
	if not _suppress_signals:
		faulted.emit(reason)
