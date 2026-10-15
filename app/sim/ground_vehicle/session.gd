## Fixed-tick owner for the experimental RC ground vehicle. This stays separate from
## FlightSession and owns no aircraft data, controls, state layout, or renderer objects.
extends Node
class_name GroundVehicleSession

const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const VehicleData := preload("res://physics/ground_vehicle/vehicle_data.gd")
const Course := preload("res://physics/ground_vehicle/course.gd")
const AirfieldCourse := preload("res://physics/ground_vehicle/airfield_course.gd")
const Damage := preload("res://physics/ground_vehicle/vehicle_damage.gd")
const Math3D := preload("res://physics/math3d.gd")
const WetPhysics := preload("res://physics/ground_vehicle/vehicle_environment.gd")
const NitroDynamics := preload("res://physics/ground_vehicle/nitro_dynamics.gd")

const FORMAT := "openrc-ground-vehicle-checkpoint v3"
const RECORDING_FORMAT := "openrc-ground-vehicle-recording v4"
const FIXED_HZ := 240
const DT := 1.0 / float(FIXED_HZ)
const STATE_SIZE := 31
const MAX_FRAME_DT_S := 2.0
const MAX_RECORDING_DURATION_TICKS := FIXED_HZ * 60 * 10
const MAX_RECORDING_SAMPLES := MAX_RECORDING_DURATION_TICKS + 1024
const CONTROL_LAYOUT := ["throttle", "steering", "brake", "reverse_flag"]
const RECORD_CONTROLS_OFFSET := 1
const RECORD_STATE_OFFSET := RECORD_CONTROLS_OFFSET + 4
const RECORD_TELEMETRY_OFFSET := RECORD_STATE_OFFSET + STATE_SIZE
const RECORD_TELEMETRY_BASE_WIDTH := 73
const ENVIRONMENT_SCALARS := ["body_submersion", "water_depth_m", "buoyancy_n", "drag_power_w", "power_w"]
const ENVIRONMENT_ARRAYS := ["wheel_submersion", "wheel_water_height_m", "wheel_depth_m", "wheel_mud"]
const DAMAGE_CHANNELS := ["body_damage", "suspension_damage", "drive_scale", "last_impact_energy_j"]
const NITRO_TELEMETRY_FIELDS := ["engine_rpm", "fuel_kg", "fuel_fraction", "clutch_engaged", "clutch_engagement"]
const RECORD_TELEMETRY_SPEED_OFFSET := 0
const RECORD_TELEMETRY_FORWARD_SPEED_OFFSET := 1
const RECORD_TELEMETRY_LOAD_OFFSET := 2
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
const CHECKPOINT_DISPLAY_MIRROR_TOLERANCE := 1.0e-12
const SHA256_EMPTY_HEX := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

signal tick_advanced(tick: int, time_s: float, state: PackedFloat64Array, telemetry: Dictionary)
signal event_added(event: Dictionary)
signal pause_changed(paused: bool)
signal faulted(reason: String)
signal recording_limit_reached(sample_count: int, elapsed_seconds: float)
signal recording_interrupted(reason: String, sample_count: int)

var prepared := false
var paused := true
var tick := 0
var _state := PackedFloat64Array()
var state: PackedFloat64Array:
	get:
		return _state.duplicate()
var _last_telemetry: Dictionary = {}
var last_telemetry: Dictionary:
	get:
		return _last_telemetry.duplicate(true)
var _last_controls: Dictionary = {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false}
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
var _vehicle_id := ""
var _course_identity: Dictionary = {}
var _prepared_backend_identity: Dictionary = {}
var _road: Callable
var _initial_state := PackedFloat64Array()
var _spawn_up_delta_m := 0.0
var spawn_id := ""
var _pause_holds: Dictionary = {}
var _last_sample_is_neutral_armed := false
var _braking_run: Dictionary = {}
## A sample stores only exported channels in one packed float64 buffer. Boolean flags are 0/1.
var _record_samples := PackedFloat64Array()
var _record_sample_width := 0
var _record_hull_contact_count := 0
var _recording_ticks := 0
var _recording_start_tick := 0
var _recording_end_tick := 0
var _recording_events: Array[Dictionary] = []
var _recording_run_valid := true
var _recording_limit_hit := false
var _recorded_controls_sha256 := ""
var _recording_exported := false
var _suppress_signals := false
var _damage = Damage.new()
var _last_effective_controls: Dictionary = _neutral_controls()
var _recording_damage_start := PackedFloat64Array()
var _recording_damage_end := PackedFloat64Array()


func prepare_default(experiment: Dictionary = {}, vehicle_id: String = "mt8-bisonte") -> bool:
	var base_vehicle_result: Dictionary = _load_vehicle(vehicle_id)
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
	base_vehicle_result["vehicle_id"] = vehicle_id
	vehicle_result["vehicle_id"] = vehicle_id
	return prepare(vehicle_result, course_result, base_vehicle_result, pose_up_delta_m)


## Prepare the selected ground vehicle on the validated airplane field, sampling the same ground
## model as aircraft. The selected kernel computes model-specific static support at that spawn.
func prepare_airfield(field_result: Dictionary, experiment: Dictionary = {}, lake: Dictionary = {},
		vehicle_id: String = "mt8-bisonte") -> bool:
	var base_vehicle_result: Dictionary = _load_vehicle(vehicle_id)
	if not bool(base_vehicle_result.get("ok", false)):
		load_error = "; ".join(_result_errors(base_vehicle_result, "vehicle data did not load"))
		return false
	var vehicle_result: Dictionary = base_vehicle_result
	if not experiment.is_empty():
		vehicle_result = VehicleData.with_experiment(base_vehicle_result, experiment)
		if not bool(vehicle_result.get("ok", false)):
			load_error = "; ".join(_result_errors(vehicle_result, "vehicle experiment was rejected"))
			return false
	base_vehicle_result["vehicle_id"] = vehicle_id
	vehicle_result["vehicle_id"] = vehicle_id
	var course_result: Dictionary = AirfieldCourse.build(field_result, {}, lake)
	if not bool(course_result.get("ok", false)):
		load_error = "; ".join(_result_errors(course_result, "airfield course could not be built"))
		return false
	return prepare(vehicle_result, course_result, base_vehicle_result, 0.0)


## Build every derived object before replacing a running session. A malformed model/course or
## failed kernel initialization leaves the previous state, identities, tape, and pause untouched.
func prepare(vehicle_result: Dictionary, course_result: Dictionary,
		baseline_vehicle_result: Dictionary = {}, pose_up_delta_m: float = 0.0) -> bool:
	if recording or _has_unexported_recording():
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
	var backend_identity := _backend_identity_for_model(model_copy)
	if not _backend_identity_is_valid(backend_identity):
		return {"ok": false, "errors": PackedStringArray(["vehicle dynamics backend identity is malformed"])}
	var staged_spawn := _find_spawn(course_copy, requested_spawn)
	if not staged_spawn.ok:
		return {"ok": false, "errors": PackedStringArray([str(staged_spawn.error)])}
	if not is_finite(pose_up_delta_m):
		return {"ok": false, "errors": PackedStringArray(["spawn CG-height adjustment must be finite"])}
	var spawn_pose: Dictionary = staged_spawn.pose.duplicate(true)
	var road := _make_road(course_copy)
	var initial: Variant = _make_spawn_state(model_copy, course_copy, spawn_pose, road, pose_up_delta_m)
	if not _state_is_valid_for_model(initial, model_copy):
		return {"ok": false, "errors": PackedStringArray(["vehicle kernel could not initialize the selected course spawn"])}
	var telemetry: Dictionary = _telemetry_for_model(initial, model_copy, road, _neutral_controls())
	if not _telemetry_is_valid_for_model(telemetry, model_copy):
		return {"ok": false, "errors": PackedStringArray([str(telemetry.get("error", "initial vehicle telemetry is invalid"))])}
	if not _backend_identities_equal(backend_identity, _backend_identity_for_model(model_copy)):
		return {"ok": false, "errors": PackedStringArray(["vehicle dynamics backend changed during session preparation"])}
	return {
		"ok": true,
		"vehicle_result": vehicle_copy,
		"base_vehicle_result": base_vehicle_copy,
		"course_result": course_result_copy,
		"model": model_copy,
		"course": course_copy,
		"model_identity": model_id_value.duplicate(true),
		"course_identity": course_id_value.duplicate(true),
		"backend_identity": backend_identity.duplicate(true),
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
	_vehicle_id = str(staged.base_vehicle_result.get("vehicle_id", ""))
	if _vehicle_id.is_empty():
		var base_identity: Variant = staged.base_vehicle_result.get("identity", {})
		_vehicle_id = str(staged.model_identity.get("id", ""))
		if typeof(base_identity) == TYPE_DICTIONARY:
			_vehicle_id = str(base_identity.get("id", _vehicle_id))
	_course_identity = staged.course_identity
	_prepared_backend_identity = staged.backend_identity
	_road = staged.road
	_initial_state = staged.initial_state
	_spawn_up_delta_m = float(staged.spawn_up_delta_m)
	_state = _initial_state.duplicate()
	_damage.reset()
	_last_telemetry = staged.telemetry
	_last_telemetry["damage"] = _damage.visual_state()
	_recording_damage_start.clear()
	_recording_damage_end.clear()
	_last_controls = _neutral_controls()
	_last_effective_controls = _neutral_controls()
	spawn_id = staged.spawn_id
	prepared = true
	tick = 0
	pause_reason = "prepared"
	_event_tape.clear()
	_control_tape.clear()
	_recovery_actions.clear()
	_record_samples.clear()
	_record_sample_width = 0
	_record_hull_contact_count = 0
	_recording_ticks = 0
	_recording_start_tick = 0
	_recording_end_tick = 0
	_recording_events.clear()
	_recording_run_valid = true
	_recording_limit_hit = false
	_recorded_controls_sha256 = ""
	_recording_exported = false
	recording = false
	run_valid = true
	fault_reason = ""
	_braking_run.clear()
	frame_backlog_s = 0.0
	slowdown_detected = false
	_last_sample_is_neutral_armed = false
	_set_paused(true)


func reset(selected_spawn_id: String = "") -> bool:
	if recording or _has_unexported_recording():
		load_error = "stop and export the current recording before resetting"
		return false
	if not prepared:
		load_error = "session is not prepared"
		return false
	if not _active_backend_matches_prepared():
		load_error = "vehicle dynamics backend changed during this session"
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


func damage_snapshot() -> PackedFloat64Array:
	return _damage.snapshot()


func damage_visual_state() -> Dictionary:
	return _damage.visual_state()


func event_tape_snapshot() -> Array[Dictionary]:
	return _event_tape.duplicate(true)


func control_tape_snapshot() -> PackedFloat64Array:
	return _control_tape.duplicate()


func recovery_actions_snapshot() -> Array[Dictionary]:
	return _recovery_actions.duplicate(true)


func identities_snapshot() -> Dictionary:
	return {"model": _model_identity.duplicate(true), "course": _course_identity.duplicate(true),
		"vehicle_id": _vehicle_id}


func model_snapshot() -> Dictionary:
	return _model.duplicate(true)


func course_snapshot() -> Dictionary:
	return _course.duplicate(true)


func is_paused() -> bool:
	return paused


func pause(reason: String = "user") -> void:
	pause_reason = reason if not reason.strip_edges().is_empty() else "user"
	load_error = ""
	_last_sample_is_neutral_armed = false
	_set_paused(true)


func add_pause_hold(reason: String) -> bool:
	if reason.strip_edges().is_empty():
		return false
	_pause_holds[reason] = true
	pause_reason = reason
	_last_sample_is_neutral_armed = false
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
			or not _last_sample_is_neutral_armed or not _active_backend_matches_prepared():
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
	if not _active_backend_matches_prepared():
		_fail_safe("vehicle dynamics backend changed during this session")
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
	# Record the requested controls; damage only reduces propulsion authority.
	var effective_controls: Dictionary = _damage.effective_controls(parsed.controls)
	var next_state: PackedFloat64Array = _step_model(_state, _model, effective_controls, DT, _road)
	if not _state_is_valid(next_state):
		_fail_safe("ground-vehicle kernel rejected the tick or returned nonfinite state")
		return false
	var next_telemetry: Dictionary = _telemetry_for_model(next_state, _model, _road, effective_controls)
	if not _telemetry_is_valid(next_telemetry):
		_fail_safe(str(next_telemetry.get("error", "ground-vehicle telemetry failed")))
		return false
	var previous_damage: Dictionary = _damage.visual_state()
	if not _damage.advance(_damage_observer_state(_state), _damage_observer_state(next_state),
			_last_telemetry, next_telemetry, _model, DT):
		_fail_safe("ground-vehicle damage observer rejected the tick")
		return false
	var next_damage: Dictionary = _damage.visual_state()
	next_telemetry["damage"] = next_damage
	var next_tick := tick + 1
	var new_events: Array[Dictionary] = []
	if next_damage.stage != previous_damage.stage:
		new_events.append({"type": "damage", "tick": next_tick, "time_s": float(next_tick) * DT,
			"stage": next_damage.stage, "body_damage": next_damage.body_damage,
			"suspension_damage": next_damage.suspension_damage, "drive_scale": next_damage.drive_scale})
	var next_braking := _braking_run.duplicate(true)
	_observe_events(_state, next_state, _last_telemetry, next_telemetry, parsed.controls, next_tick, new_events, next_braking)
	_state = next_state
	tick = next_tick
	_last_telemetry = next_telemetry
	_last_controls = parsed.controls.duplicate(true)
	_last_effective_controls = effective_controls.duplicate(true)
	_braking_run = next_braking
	_append_control(parsed.controls)
	for event in new_events:
		_event_tape.append(event)
		if recording:
			_recording_events.append(event.duplicate(true))
	if recording:
		if not _capture_record_sample(parsed.controls):
			_interrupt_recording("accepted simulation sample did not match the recording schema")
		else:
			_recording_ticks += 1
			_recording_end_tick = tick
			_recording_run_valid = run_valid
			if _recording_ticks >= MAX_RECORDING_DURATION_TICKS \
					or _recording_sample_count() >= MAX_RECORDING_SAMPLES:
				_stop_recording_at_limit()
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
	if not _active_backend_matches_prepared():
		load_error = "vehicle dynamics backend changed during this session"
		return false
	var pose := _find_spawn(_course, spawn_id)
	if not pose.ok:
		load_error = str(pose.error)
		return false
	var recovery_pose: Dictionary = pose.pose.duplicate(true)
	var recovered: Variant = _make_spawn_state(_model, _course, recovery_pose, _road, _spawn_up_delta_m)
	if not _state_is_valid(recovered):
		load_error = "manual recovery pose was rejected"
		return false
	var telemetry: Dictionary = _telemetry_for_model(recovered, _model, _road, _neutral_controls())
	if not _telemetry_is_valid(telemetry):
		load_error = str(telemetry.get("error", "manual recovery telemetry failed"))
		return false
	_state = recovered
	_damage.reset() # Recovery is an explicit repair and already invalidates the run.
	telemetry["damage"] = _damage.visual_state()
	_last_telemetry = telemetry
	_last_controls = _neutral_controls()
	_last_effective_controls = _neutral_controls()
	run_valid = false
	fault_reason = ""
	_braking_run.clear()
	var event := {"type": "manual_recovery", "tick": tick, "time_s": time_s(), "spawn_id": spawn_id}
	_event_tape.append(event)
	_recovery_actions.append({"type": "manual_recovery", "tick": tick, "spawn_id": spawn_id})
	if recording:
		_recording_events.append(event.duplicate(true))
		if not _capture_record_sample(_neutral_controls()):
			_interrupt_recording("recovery sample did not match the recording schema")
		else:
			_recording_end_tick = tick
			_recording_run_valid = run_valid
			if _recording_sample_count() >= MAX_RECORDING_SAMPLES:
				_stop_recording_at_limit()
	if not _suppress_signals:
		event_added.emit(event.duplicate(true))
	load_error = ""
	_last_sample_is_neutral_armed = false
	pause_reason = "manual recovery"
	_set_paused(true)
	return true


func replay(controls: Variant, actions: Array = []) -> bool:
	if not prepared or recording or _has_unexported_recording() or not _active_backend_matches_prepared():
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
				or not _integer_value_is_valid(item.get("tick")) or int(item.tick) < previous_action_tick \
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
	if not prepared or not _active_backend_matches_prepared() \
			or not _state_is_valid(_state) or _control_tape.size() != tick * 4:
		return {}
	var damage_state: PackedFloat64Array = _damage.snapshot()
	if not _damage.valid_snapshot(damage_state): return {}
	var damage_bytes := damage_state.to_byte_array()
	var state_bytes := _state.to_byte_array()
	var control_bytes := _control_tape.to_byte_array()
	var last_control_bytes := _controls_to_packed(_last_controls).to_byte_array()
	var applied_control_bytes := _controls_to_packed(_last_effective_controls).to_byte_array()
	# Normalize event values for JSON storage. Their digest is computed from the
	# final canonical checkpoint below, after every nested value has normalized.
	var canonical_events: Variant = _json_canonical_variant(_json_value(_event_tape))
	var canonical_braking: Variant = _json_value(_braking_run)
	var candidate := {
		"format": FORMAT,
		"fixed_hz": FIXED_HZ,
		"dt": DT,
		"tick": tick,
		"time_s": time_s(),
		"model_identity": _model_identity.duplicate(true),
		"vehicle_id": _vehicle_id,
		"course_identity": _course_identity.duplicate(true),
		"solver_identity": _solver_identity(),
		"spawn_id": spawn_id,
		"control_layout": CONTROL_LAYOUT.duplicate(),
		"state_layout": _state_layout_for_model(_model),
		"state": _json_canonical_variant(_json_value(_state)),
		"state_f64_base64": _base64_bytes(state_bytes),
		"state_sha256": _hash_bytes(state_bytes),
		"damage_state": _json_canonical_variant(_json_value(damage_state)),
		"damage_state_f64_base64": _base64_bytes(damage_bytes),
		"damage_state_sha256": _hash_bytes(damage_bytes),
		"control_tape": _json_canonical_variant(_json_value(_control_tape)),
		"control_tape_f64_base64": _base64_bytes(control_bytes),
		"control_tape_sha256": _hash_bytes(control_bytes),
		"last_controls": _json_canonical_variant(_json_value(_last_controls)),
		"last_controls_f64_base64": _base64_bytes(last_control_bytes),
		"last_controls_sha256": _hash_bytes(last_control_bytes),
		"applied_controls_f64_base64": _base64_bytes(applied_control_bytes),
		"recovery_actions": _recovery_actions.duplicate(true),
		"event_tape": canonical_events,
		"event_tape_sha256": "",
		"braking_run": canonical_braking,
		"run_valid": run_valid,
	}
	var canonical_candidate: Variant = _json_canonical_variant(candidate)
	if typeof(canonical_candidate) != TYPE_DICTIONARY:
		return {}
	canonical_candidate["event_tape_sha256"] = _hash_variant(canonical_candidate.get("event_tape", []))
	canonical_candidate["checkpoint_sha256"] = _checkpoint_hash(canonical_candidate)
	return canonical_candidate


func can_restore_checkpoint(candidate: Variant) -> bool:
	if not prepared or not _active_backend_matches_prepared() \
			or recording or _has_unexported_recording() or typeof(candidate) != TYPE_DICTIONARY:
		return false
	if candidate.get("format") != FORMAT or candidate.get("fixed_hz") != FIXED_HZ \
			or candidate.get("control_layout") != CONTROL_LAYOUT \
			or typeof(candidate.get("dt")) not in [TYPE_FLOAT, TYPE_INT] \
			or absf(float(candidate.dt) - DT) > 1.0e-15:
		return false
	if not _identity_equal(candidate.get("model_identity", {}), _model_identity) \
			or not _identity_equal(candidate.get("course_identity", {}), _course_identity):
		return false
	if candidate.has("vehicle_id"):
		if typeof(candidate.get("vehicle_id")) != TYPE_STRING or str(candidate.vehicle_id) != _vehicle_id:
			return false
	elif _vehicle_id != "mt8-bisonte":
		return false
	if candidate.has("state_layout"):
		if candidate.get("state_layout") != _state_layout_for_model(_model):
			return false
	elif _vehicle_id != "mt8-bisonte":
		return false
	if not _solver_identity_matches(candidate.get("solver_identity", {})):
		return false
	if typeof(candidate.get("spawn_id")) != TYPE_STRING or not _find_spawn(_course, str(candidate.spawn_id)).ok:
		return false
	if not _integer_value_is_valid(candidate.get("tick")) or int(candidate.tick) < 0 \
			or typeof(candidate.get("time_s")) not in [TYPE_FLOAT, TYPE_INT] \
			or absf(float(candidate.time_s) - float(candidate.tick) * DT) > 1.0e-12:
		return false
	var candidate_damage := _decode_float64_blob(candidate.get("damage_state_f64_base64"), Damage.SNAPSHOT_SIZE)
	if not _damage.valid_snapshot(candidate_damage) \
			or _hash_bytes(candidate_damage.to_byte_array()) != str(candidate.get("damage_state_sha256", "")):
		return false
	if not _checkpoint_float_array_mirror_matches(candidate.get("damage_state"), candidate_damage):
		return false
	var candidate_state := _decode_float64_blob(candidate.get("state_f64_base64"), _state_size_for_model(_model))
	if not _state_is_valid(candidate_state) \
			or _hash_bytes(candidate_state.to_byte_array()) != str(candidate.get("state_sha256", "")):
		return false
	if not _checkpoint_float_array_mirror_matches(candidate.get("state"), candidate_state):
		return false
	var controls_value: Variant = candidate.get("control_tape")
	var actions_value: Variant = candidate.get("recovery_actions")
	var events_value: Variant = candidate.get("event_tape")
	var packed_controls := _decode_float64_blob(candidate.get("control_tape_f64_base64"), int(candidate.tick) * 4)
	if int(candidate.tick) == 0 and str(candidate.get("control_tape_f64_base64", "")) != "":
		return false
	if (packed_controls.is_empty() and int(candidate.tick) > 0) \
			or packed_controls.size() != int(candidate.tick) * 4 \
			or typeof(actions_value) != TYPE_ARRAY or typeof(events_value) != TYPE_ARRAY:
		return false
	if not _checkpoint_float_array_mirror_matches(controls_value, packed_controls):
		return false
	if not _expand_control_tape(packed_controls).ok:
		return false
	var last_control_tape := _decode_float64_blob(candidate.get("last_controls_f64_base64"), 4)
	if last_control_tape.size() != 4 \
			or _hash_bytes(last_control_tape.to_byte_array()) != str(candidate.get("last_controls_sha256", "")):
		return false
	var parsed_last_controls := _controls_from_packed(last_control_tape)
	if parsed_last_controls.is_empty() \
			or not _checkpoint_controls_mirror_matches(candidate.get("last_controls"), parsed_last_controls) \
			or not _last_controls_match_tape(parsed_last_controls, packed_controls, actions_value, int(candidate.tick)):
		return false
	if not _actions_are_valid(actions_value, int(candidate.tick), str(candidate.spawn_id)) \
			or not _events_are_valid(events_value, int(candidate.tick)) \
			or not _recovery_history_is_consistent(actions_value, events_value):
		return false
	if _hash_bytes(packed_controls.to_byte_array()) != str(candidate.get("control_tape_sha256", "")) \
			or _hash_variant(events_value) != str(candidate.get("event_tape_sha256", "")):
		return false
	if typeof(candidate.get("run_valid")) != TYPE_BOOL or typeof(candidate.get("braking_run")) != TYPE_DICTIONARY:
		return false
	if bool(candidate.run_valid) and not actions_value.is_empty():
		return false
	if not _braking_state_is_valid(candidate.braking_run, int(candidate.tick)):
		return false
	if _checkpoint_hash(candidate) != str(candidate.get("checkpoint_sha256", "")):
		return false
	var applied_controls := _controls_from_packed(_decode_float64_blob(candidate.get("applied_controls_f64_base64"), 4))
	var damage_candidate = Damage.new()
	if not damage_candidate.restore_snapshot(candidate_damage): return false
	var post_tick_drive_scale := float(damage_candidate.visual_state().drive_scale)
	if not _applied_controls_are_valid(applied_controls, parsed_last_controls, post_tick_drive_scale): return false
	var telemetry: Dictionary = _telemetry_for_model(candidate_state, _model, _road, applied_controls)
	return _telemetry_is_valid(telemetry)


func restore_checkpoint(candidate: Variant) -> bool:
	if not can_restore_checkpoint(candidate):
		return false
	var next_state := _decode_float64_blob(candidate.state_f64_base64, _state_size_for_model(_model))
	var restored_controls := _controls_from_packed(_decode_float64_blob(candidate.last_controls_f64_base64, 4))
	var restored_effective_controls := _controls_from_packed(_decode_float64_blob(candidate.applied_controls_f64_base64, 4))
	var next_damage = Damage.new()
	if not next_damage.restore_snapshot(_decode_float64_blob(candidate.damage_state_f64_base64, Damage.SNAPSHOT_SIZE)):
		return false
	var next_telemetry: Dictionary = _telemetry_for_model(next_state, _model, _road, restored_effective_controls)
	next_telemetry["damage"] = next_damage.visual_state()
	if not _telemetry_is_valid(next_telemetry):
		return false
	_state = next_state
	_damage = next_damage
	tick = int(candidate.tick)
	spawn_id = str(candidate.spawn_id)
	_control_tape = _decode_float64_blob(candidate.control_tape_f64_base64, int(candidate.tick) * 4)
	_last_controls = restored_controls
	_last_effective_controls = restored_effective_controls
	_recovery_actions = _dictionary_array(candidate.recovery_actions)
	_event_tape = _event_array(candidate.event_tape)
	_braking_run = candidate.braking_run.duplicate(true)
	_last_telemetry = next_telemetry
	run_valid = bool(candidate.run_valid)
	fault_reason = ""
	pause_reason = "checkpoint restored"
	_record_samples.clear()
	_record_sample_width = 0
	_record_hull_contact_count = 0
	_recording_ticks = 0
	_recording_start_tick = tick
	_recording_end_tick = tick
	_recording_events.clear()
	_recording_run_valid = run_valid
	_recording_limit_hit = false
	_recorded_controls_sha256 = ""
	_recording_exported = false
	recording = false
	_last_sample_is_neutral_armed = false
	_set_paused(true)
	return true


func _record_telemetry_offset() -> int:
	return RECORD_STATE_OFFSET + _state_size_for_model(_model)


func _record_nitro_telemetry_count() -> int:
	return NITRO_TELEMETRY_FIELDS.size() if _uses_nitro(_model) else 0


func start_recording() -> bool:
	if not prepared or not _active_backend_matches_prepared() or not fault_reason.is_empty() \
			or recording or _has_unexported_recording():
		return false
	var hull_radii: Variant = _model.get("hull_probe_radii_m", PackedFloat64Array())
	if typeof(hull_radii) != TYPE_PACKED_FLOAT64_ARRAY:
		return false
	_record_hull_contact_count = hull_radii.size()
	_record_sample_width = _record_telemetry_offset() + RECORD_TELEMETRY_BASE_WIDTH \
		+ _record_hull_contact_count + _record_nitro_telemetry_count()
	if not _recording_sample_is_valid(_last_telemetry, _last_controls):
		_record_sample_width = 0
		_record_hull_contact_count = 0
		return false
	_record_samples.clear()
	_recording_start_tick = tick
	_recording_end_tick = tick
	_recording_damage_start = _damage.snapshot()
	_recording_damage_end = _recording_damage_start.duplicate()
	_recording_ticks = 0
	_recording_events.clear()
	_recording_run_valid = run_valid
	_recording_limit_hit = false
	_recorded_controls_sha256 = ""
	_recording_exported = false
	recording = true
	if not _capture_record_sample(_last_controls):
		recording = false
		_record_samples.clear()
		_record_sample_width = 0
		_record_hull_contact_count = 0
		return false
	return true


func stop_recording() -> bool:
	if not recording:
		return false
	_finish_recording()
	return true


## Export only to user://rcv/. `name` is a basename, never a path. Existing files are preserved.
func export_recording(name: String) -> Dictionary:
	var sample_count := _recording_sample_count()
	if recording or sample_count <= 0:
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
	var metadata := _recording_metadata()
	var json_text := JSON.stringify(metadata, "\t", true, true) + "\n"
	var csv_error := _write_recording_csv(csv_temp)
	if not csv_error.is_empty():
		DirAccess.remove_absolute(csv_temp)
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
	_recording_exported = true
	return {"ok": true, "csv_path": "user://rcv/" + safe_name + ".csv",
		"metadata_path": "user://rcv/" + safe_name + ".json", "samples": sample_count}


func _capture_record_sample(controls: Dictionary) -> bool:
	if _record_sample_width <= 0 or not _state_is_valid(_state) \
			or not _recording_sample_is_valid(_last_telemetry, controls):
		return false
	var initial_size := _record_samples.size()
	_record_samples.append(float(tick))
	_record_samples.append_array(_controls_to_packed(controls))
	_record_samples.append_array(_state)
	var telemetry: Dictionary = _last_telemetry
	_record_samples.append(float(telemetry.speed_m_per_s))
	_record_samples.append(float(telemetry.forward_speed_m_per_s))
	for key in ["wheel_load_n", "wheel_longitudinal_force_n", "wheel_lateral_force_n",
			"wheel_brake_torque_n_m", "wheel_slip_ratio", "wheel_slip_angle_rad", "wheel_slip_speed_m_per_s"]:
		_record_samples.append_array(telemetry[key])
	for item in telemetry.wheel_in_contact:
		_record_samples.append(float(item))
	for item in telemetry.hull_in_contact:
		_record_samples.append(float(item))
	_record_samples.append(1.0 if bool(telemetry.airborne) else 0.0)
	_record_samples.append_array(telemetry.suspension_travel_m)
	_record_samples.append_array(telemetry.suspension_force_n)
	_record_samples.append(float(telemetry.total_energy_j))
	for channel in DAMAGE_CHANNELS:
		_record_samples.append(float(telemetry.damage[channel]))
	_record_samples.append_array(_controls_to_packed(_last_effective_controls))
	for key in ENVIRONMENT_SCALARS: _record_samples.append(float(telemetry.environment[key]))
	for key in ENVIRONMENT_ARRAYS: _record_samples.append_array(telemetry.environment[key])
	if _uses_nitro(_model):
		var nitro: Dictionary = telemetry.nitro
		for field in NITRO_TELEMETRY_FIELDS:
			var item: Variant = nitro[field]
			if typeof(item) == TYPE_BOOL:
				_record_samples.append(1.0 if bool(item) else 0.0)
			else:
				_record_samples.append(float(item))
	return _record_samples.size() - initial_size == _record_sample_width


func _write_recording_csv(path: String) -> String:
	if _record_sample_width <= 0 or _record_samples.size() % _record_sample_width != 0:
		return "recording sample buffer is malformed"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "could not open recording CSV (%s)" % error_string(FileAccess.get_open_error())
	file.store_line("# " + RECORDING_FORMAT)
	file.store_line("tick,time_s,throttle,steering,brake,reverse,state_json,telemetry_json")
	var count := _recording_sample_count()
	for sample_index in count:
		var base := sample_index * _record_sample_width
		var record_tick := int(_record_samples[base])
		var controls_offset := base + RECORD_CONTROLS_OFFSET
		var state_offset := base + RECORD_STATE_OFFSET
		var telemetry_offset := base + _record_telemetry_offset()
		var state_json := JSON.stringify(_recorded_float_array(state_offset, _state_size_for_model(_model)), "", false, true)
		var telemetry_json := JSON.stringify(_recorded_telemetry(telemetry_offset), "", true, true)
		file.store_line(",".join(PackedStringArray([
			str(record_tick), _json_number(float(record_tick) * DT),
			_json_number(_record_samples[controls_offset]), _json_number(_record_samples[controls_offset + 1]),
			_json_number(_record_samples[controls_offset + 2]),
			("true" if _record_samples[controls_offset + 3] == 1.0 else "false"),
			_csv_quote(state_json), _csv_quote(telemetry_json),
		])))
		if sample_index % 1024 == 0 and file.get_error() != OK:
			var write_error := file.get_error()
			file.close()
			return "could not write recording CSV (%s)" % error_string(write_error)
	file.flush()
	var status := file.get_error()
	file.close()
	return "could not write recording CSV (%s)" % error_string(status) if status != OK else ""


func _recorded_float_array(offset: int, count: int) -> Array[float]:
	var values: Array[float] = []
	for index in count:
		values.append(_record_samples[offset + index])
	return values


func _recorded_byte_array(offset: int, count: int) -> Array[int]:
	var values: Array[int] = []
	for index in count:
		values.append(int(_record_samples[offset + index]))
	return values


func _recorded_telemetry(offset: int) -> Dictionary:
	var cursor := offset
	var telemetry := {
		"ok": true,
		"error": "",
		"speed_m_per_s": _record_samples[cursor],
		"forward_speed_m_per_s": _record_samples[cursor + 1],
	}
	cursor += 2
	for key in ["wheel_load_n", "wheel_longitudinal_force_n", "wheel_lateral_force_n",
			"wheel_brake_torque_n_m", "wheel_slip_ratio", "wheel_slip_angle_rad", "wheel_slip_speed_m_per_s"]:
		telemetry[key] = _recorded_float_array(cursor, 4)
		cursor += 4
	telemetry["wheel_in_contact"] = _recorded_byte_array(cursor, 4)
	cursor += 4
	telemetry["hull_in_contact"] = _recorded_byte_array(cursor, _record_hull_contact_count)
	cursor += _record_hull_contact_count
	telemetry["airborne"] = _record_samples[cursor] != 0.0
	cursor += 1
	telemetry["suspension_travel_m"] = _recorded_float_array(cursor, 4)
	cursor += 4
	telemetry["suspension_force_n"] = _recorded_float_array(cursor, 4)
	cursor += 4
	telemetry["total_energy_j"] = _record_samples[cursor]
	cursor += 1
	var damage := {}
	for channel in DAMAGE_CHANNELS:
		damage[channel] = _record_samples[cursor]
		cursor += 1
	telemetry["damage"] = damage
	telemetry["applied_controls"] = _recorded_float_array(cursor, 4)
	cursor += 4
	var environment := {"ok": true}
	for key in ENVIRONMENT_SCALARS:
		environment[key] = _record_samples[cursor]
		cursor += 1
	for key in ENVIRONMENT_ARRAYS:
		environment[key] = _recorded_float_array(cursor, 4)
		cursor += 4
	telemetry["environment"] = environment
	if _uses_nitro(_model):
		var nitro := {}
		for field in NITRO_TELEMETRY_FIELDS:
			nitro[field] = _record_samples[cursor]
			cursor += 1
		nitro["clutch_engaged"] = bool(nitro.clutch_engaged)
		telemetry["nitro"] = nitro
	return telemetry


func _recording_sample_count() -> int:
	if _record_sample_width <= 0 or _record_samples.size() % _record_sample_width != 0:
		return 0
	return _record_samples.size() / _record_sample_width


func _recording_sample_is_valid(telemetry: Dictionary, controls: Dictionary) -> bool:
	if not WetPhysics.telemetry_is_valid(telemetry.get("environment")): return false
	if _controls_to_packed(controls).size() != 4 or typeof(telemetry.get("ok")) != TYPE_BOOL \
			or not bool(telemetry.get("ok")):
		return false
	var damage: Variant = telemetry.get("damage")
	if typeof(damage) != TYPE_DICTIONARY: return false
	for channel in DAMAGE_CHANNELS:
		var item: Variant = damage.get(channel)
		if typeof(item) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(item)): return false
	for key in ["speed_m_per_s", "forward_speed_m_per_s", "total_energy_j"]:
		var value: Variant = telemetry.get(key, NAN)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
	for key in ["wheel_load_n", "wheel_longitudinal_force_n", "wheel_lateral_force_n",
			"wheel_brake_torque_n_m", "wheel_slip_ratio", "wheel_slip_angle_rad", "wheel_slip_speed_m_per_s",
			"suspension_travel_m", "suspension_force_n"]:
		var values: Variant = telemetry.get(key)
		if typeof(values) != TYPE_PACKED_FLOAT64_ARRAY or values.size() != 4:
			return false
		for value in values:
			if not is_finite(float(value)):
				return false
	var wheel_contact: Variant = telemetry.get("wheel_in_contact")
	var hull_contact: Variant = telemetry.get("hull_in_contact")
	return typeof(wheel_contact) == TYPE_PACKED_BYTE_ARRAY and wheel_contact.size() == 4 \
		and typeof(hull_contact) == TYPE_PACKED_BYTE_ARRAY and hull_contact.size() == _record_hull_contact_count \
		and typeof(telemetry.get("airborne")) == TYPE_BOOL \
		and (not _uses_nitro(_model) or _nitro_telemetry_is_valid(telemetry.get("nitro")))


func _nitro_telemetry_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	for key in ["engine_rpm", "fuel_kg", "fuel_fraction", "clutch_engagement"]:
		var item: Variant = value.get(key, NAN)
		if typeof(item) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(item)):
			return false
	return float(value.fuel_kg) >= 0.0 and typeof(value.get("clutch_engaged")) == TYPE_BOOL


func _finish_recording() -> void:
	recording = false
	_recording_end_tick = tick
	_recording_run_valid = run_valid
	_recorded_controls_sha256 = _hash_bytes(_recorded_control_channels().to_byte_array())
	_recording_damage_end = _damage.snapshot()


func _recorded_control_channels() -> PackedFloat64Array:
	var values := PackedFloat64Array()
	var count := _recording_sample_count()
	for sample_index in count:
		var offset := sample_index * _record_sample_width + RECORD_CONTROLS_OFFSET
		values.append_array(_record_samples.slice(offset, offset + 4))
	return values


func _stop_recording_at_limit() -> void:
	_recording_limit_hit = true
	_finish_recording()
	recording_limit_reached.emit(_recording_sample_count(), float(_recording_ticks) * DT)


func _interrupt_recording(reason: String) -> void:
	if not recording:
		return
	_recording_events.append({"type": "recording_interrupted", "tick": tick,
		"time_s": time_s(), "reason": reason})
	_recording_run_valid = false
	_finish_recording()
	_recording_run_valid = false
	load_error = reason
	recording_interrupted.emit(reason, _recording_sample_count())


func _has_unexported_recording() -> bool:
	return not _recording_exported and not _record_samples.is_empty()


func _json_number(value: float) -> String:
	return JSON.stringify(value, "", true, true)


func _recording_metadata() -> Dictionary:
	var telemetry_fields := ["speed_m_per_s", "forward_speed_m_per_s", "wheel_load_n[4]",
		"wheel_longitudinal_force_n[4]", "wheel_lateral_force_n[4]", "wheel_brake_torque_n_m[4]",
		"wheel_slip_ratio[4]", "wheel_slip_angle_rad[4]", "wheel_slip_speed_m_per_s[4]",
	"wheel_in_contact[4]", "hull_in_contact[N]", "airborne", "suspension_travel_m[4]",
		"suspension_force_n[4]", "total_energy_j", "damage.body_damage",
		"damage.suspension_damage", "damage.drive_scale", "damage.last_impact_energy_j", "applied_controls[4]",
		"environment.body_submersion", "environment.water_depth_m", "environment.buoyancy_n",
		"environment.drag_power_w", "environment.power_w", "environment.wheel_submersion[4]",
		"environment.wheel_water_height_m[4]", "environment.wheel_depth_m[4]", "environment.wheel_mud[4]"]
	if _uses_nitro(_model):
		for field in NITRO_TELEMETRY_FIELDS:
			telemetry_fields.append("nitro." + field)
	return {
		"format": RECORDING_FORMAT,
		"version": 4,
		"fixed_hz": FIXED_HZ,
		"dt_s": DT,
		"state_layout": _state_layout_for_model(_model),
		"vehicle_id": _vehicle_id,
		"control_layout": CONTROL_LAYOUT.duplicate(),
		"sample_layout": {
			"tick_offset": 0,
			"controls_offset": RECORD_CONTROLS_OFFSET,
			"state_offset": RECORD_STATE_OFFSET,
			"telemetry_offset": _record_telemetry_offset(),
			"telemetry_fields": telemetry_fields,
		},
		"sample_width": _record_sample_width,
		"damage_state_layout": Damage.STATE_LAYOUT.duplicate(),
		"initial_damage_f64_base64": _base64_bytes(_recording_damage_start.to_byte_array()),
		"final_damage_f64_base64": _base64_bytes(_recording_damage_end.to_byte_array()),
		"hull_probe_count": _record_hull_contact_count,
		"corner_order": CORNERS.duplicate(),
		"model_identity": _model_identity.duplicate(true),
		"course_identity": _course_identity.duplicate(true),
		"solver_identity": _solver_identity(),
		"spawn_id": spawn_id,
		"start_tick": _recording_start_tick,
		"end_tick": _recording_end_tick,
		"recorded_tick_count": _recording_ticks,
		"sample_count": _recording_sample_count(),
		"run_valid": _recording_run_valid,
		"recording_limit_hit": _recording_limit_hit,
		"recording_limit_seconds": float(MAX_RECORDING_DURATION_TICKS) * DT,
		"events": _recording_events.duplicate(true),
		"control_tape_sha256": _recorded_controls_sha256,
		"recorded_samples_sha256": _hash_bytes(_record_samples.to_byte_array()),
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


func _decode_float64_blob(encoded: Variant, expected_count: int) -> PackedFloat64Array:
	if typeof(encoded) != TYPE_STRING or expected_count < 0:
		return PackedFloat64Array()
	if expected_count == 0:
		return PackedFloat64Array() if str(encoded).is_empty() else PackedFloat64Array([NAN])
	var bytes := Marshalls.base64_to_raw(str(encoded))
	if bytes.size() != expected_count * 8 or Marshalls.raw_to_base64(bytes) != str(encoded):
		return PackedFloat64Array()
	var values := bytes.to_float64_array()
	if values.size() != expected_count:
		return PackedFloat64Array()
	for value in values:
		if not is_finite(float(value)):
			return PackedFloat64Array()
	return values


func _controls_to_packed(value: Variant) -> PackedFloat64Array:
	if typeof(value) != TYPE_DICTIONARY:
		return PackedFloat64Array()
	var parsed := _parse_controls(value, false)
	if not parsed.ok:
		return PackedFloat64Array()
	var controls: Dictionary = parsed.controls
	return PackedFloat64Array([
		float(controls.throttle), float(controls.steering), float(controls.brake),
		1.0 if bool(controls.reverse) else 0.0,
	])


func _controls_from_packed(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != 4:
		return {}
	if float(value[3]) != 0.0 and float(value[3]) != 1.0:
		return {}
	var parsed := _parse_controls({
		"throttle": value[0], "steering": value[1], "brake": value[2], "reverse": value[3] == 1.0,
	}, false)
	return parsed.controls if parsed.ok else {}


func _last_controls_match_tape(controls: Dictionary, packed_tape: PackedFloat64Array,
		actions: Array, at_tick: int) -> bool:
	var expected := _neutral_controls()
	var recovered_at_current_tick := false
	for action in actions:
		if typeof(action) == TYPE_DICTIONARY and int(action.get("tick", -1)) == at_tick:
			recovered_at_current_tick = true
	if at_tick > 0 and not recovered_at_current_tick:
		var offset := (at_tick - 1) * 4
		if offset + 3 >= packed_tape.size():
			return false
		expected = {
			"throttle": float(packed_tape[offset]),
			"steering": float(packed_tape[offset + 1]),
			"brake": float(packed_tape[offset + 2]),
			"reverse": float(packed_tape[offset + 3]) == 1.0,
		}
	return float(controls.get("throttle", NAN)) == float(expected.throttle) \
		and float(controls.get("steering", NAN)) == float(expected.steering) \
		and float(controls.get("brake", NAN)) == float(expected.brake) \
		and bool(controls.get("reverse", not expected.reverse)) == bool(expected.reverse)


func _json_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_PACKED_FLOAT64_ARRAY:
		var result: Array[float] = []
		for item in value:
			result.append(float(item))
		return result
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item in value:
			result.append(_json_value(item))
		return result
	if typeof(value) == TYPE_DICTIONARY:
		var result: Dictionary = {}
		for key in value:
			result[key] = _json_value(value[key])
		return result
	return value


func _dictionary_array(value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in value:
		if typeof(item) == TYPE_DICTIONARY:
			result.append(item.duplicate(true))
	return result


func _event_array(value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in value:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = item.duplicate(true)
		if event.has("tick"):
			event["tick"] = int(event.tick)
		if event.has("start_tick"):
			event["start_tick"] = int(event.start_tick)
		if event.has("end_tick"):
			event["end_tick"] = int(event.end_tick)
		result.append(event)
	return result


func _json_canonical_variant(value: Variant) -> Variant:
	var encoded := JSON.stringify(_json_value(value), "", true, true)
	return JSON.parse_string(encoded)


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
	if str(course_value.get("sampler", "")) == AirfieldCourse.FORMAT:
		return func(north_m: float, east_m: float) -> Dictionary:
			return AirfieldCourse.sample(course_value, north_m, east_m)
	return func(north_m: float, east_m: float) -> Dictionary:
		return Course.sample(course_value, north_m, east_m)


func _load_vehicle(vehicle_id: String) -> Dictionary:
	if vehicle_id == "mt8-bisonte":
		return VehicleData.load_default()
	return VehicleData.load_vehicle(vehicle_id)


func _uses_nitro(model: Dictionary) -> bool:
	return str(model.get("drive_configuration", "")) == "nitro_4wd"


func _state_size_for_model(model: Dictionary) -> int:
	return int(NitroDynamics.STATE_SIZE) if _uses_nitro(model) else int(VehicleDynamics.STATE_SIZE)


func _state_layout_for_model(model: Dictionary) -> Array:
	return NitroDynamics.STATE_LAYOUT.duplicate() if _uses_nitro(model) else STATE_LAYOUT.duplicate()


func _backend_identity_for_model(model: Dictionary) -> Dictionary:
	return NitroDynamics.backend_identity() if _uses_nitro(model) else VehicleDynamics.backend_identity()


func _substeps_for_model(model: Dictionary) -> int:
	return int(NitroDynamics.SUBSTEPS_PER_TICK) if _uses_nitro(model) else int(VehicleDynamics.SUBSTEPS_PER_TICK)


func _initialize_model(model: Dictionary, road: Callable, north_m: float = 0.0, east_m: float = 0.0) -> Dictionary:
	if _uses_nitro(model):
		return NitroDynamics.initialize(model, road, north_m, east_m)
	return VehicleDynamics.initialize(model, road, north_m, east_m)


func _step_model(state_value: PackedFloat64Array, model: Dictionary, controls: Dictionary,
		dt: float, road: Callable) -> PackedFloat64Array:
	if _uses_nitro(model):
		return NitroDynamics.step(state_value, model, controls, dt, road)
	return VehicleDynamics.step(state_value, model, controls, dt, road)


func _damage_observer_state(state_value: PackedFloat64Array) -> PackedFloat64Array:
	return state_value.slice(0, VehicleDynamics.STATE_SIZE) if _uses_nitro(_model) else state_value


func _telemetry_for_model(state_value: PackedFloat64Array, model: Dictionary, road: Callable,
		controls: Dictionary) -> Dictionary:
	if _uses_nitro(model):
		return NitroDynamics.telemetry(state_value, model, road, controls)
	return VehicleDynamics.telemetry(state_value, model, road, controls)


func _make_spawn_state(model: Dictionary, course_value: Dictionary, pose: Dictionary,
		road: Callable, pose_up_delta_m: float) -> PackedFloat64Array:
	if _uses_nitro(model):
		if str(course_value.get("sampler", "")) == AirfieldCourse.FORMAT:
			return NitroDynamics.make_terrain_state(model, pose, road)
		var nitro_practice_pose := pose.duplicate(true)
		nitro_practice_pose.vehicle_up_m = float(nitro_practice_pose.vehicle_up_m) + pose_up_delta_m
		return NitroDynamics.make_state(model, nitro_practice_pose, road)
	if str(course_value.get("sampler", "")) == AirfieldCourse.FORMAT:
		return VehicleDynamics.make_terrain_state(model, pose, road)
	var practice_pose := pose.duplicate(true)
	practice_pose.vehicle_up_m = float(practice_pose.vehicle_up_m) + pose_up_delta_m
	return VehicleDynamics.make_state(model, practice_pose, road)


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
	if str(course_value.get("sampler", "")) == AirfieldCourse.FORMAT:
		# make_terrain_state solves support from the current model and real wheel patches each prepare/reset.
		return {"ok": true, "delta_m": 0.0}
	var road := _make_road(course_value.duplicate(true))
	var experiment_support: Dictionary = _initialize_model(experiment_model, road, 0.0, 0.0)
	var baseline_support: Dictionary = _initialize_model(baseline_model, road, 0.0, 0.0)
	if not experiment_support.get("ok", false) or not baseline_support.get("ok", false):
		return {"ok": false, "error": "kernel could not compute baseline and experiment support altitudes"}
	var experiment_state: Variant = experiment_support.get("state")
	var baseline_state: Variant = baseline_support.get("state")
	if not _state_is_valid_for_model(experiment_state, experiment_model) \
			or not _state_is_valid_for_model(baseline_state, baseline_model):
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


## A damage modifier may reduce requested throttle only. Braking and steering stay driver-owned.
func _applied_controls_are_valid(applied: Dictionary, requested: Dictionary, minimum_drive_scale: float) -> bool:
	if _controls_to_packed(applied).size() != 4: return false
	if not is_finite(minimum_drive_scale) or minimum_drive_scale < 0.0 or minimum_drive_scale > 1.0:
		return false
	# Drive damage is monotone during a run. The pre-tick scale may be higher than
	# this post-tick scale, so this lower bound checks internal consistency only.
	var throttle_floor := float(requested.throttle) * minimum_drive_scale
	return float(applied.throttle) <= float(requested.throttle) \
		and float(applied.throttle) + 1.0e-12 >= throttle_floor \
		and applied.steering == requested.steering and applied.brake == requested.brake \
		and applied.reverse == requested.reverse


func _solver_identity() -> Dictionary:
	var engine_version: Dictionary = Engine.get_version_info()
	var backend_identity := _prepared_backend_identity if prepared and not _prepared_backend_identity.is_empty() \
		else _backend_identity_for_model(_model)
	var implementation_path := "res://physics/ground_vehicle/nitro_dynamics.gd" \
		if _uses_nitro(_model) else "res://physics/ground_vehicle/vehicle_dynamics.gd"
	return {
		"solver_version": str(backend_identity.get("solver_version", VehicleDynamics.SOLVER_VERSION)),
		"environment_version": WetPhysics.VERSION,
		"environment_artifact": VehicleDynamics._reference_implementation_artifact("res://physics/ground_vehicle/vehicle_environment.gd"),
		"integration_artifact": VehicleDynamics._reference_implementation_artifact(implementation_path),
		"damage_version": Damage.SNAPSHOT_VERSION,
		"engine_version": str(engine_version.get("string", "")),
		"fixed_hz": FIXED_HZ,
		"substeps_per_tick": _substeps_for_model(_model),
		"backend_identity": backend_identity.duplicate(true),
	}


func _solver_identity_matches(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var current := _solver_identity()
	var old_solver_fields_match: bool = value.get("solver_version") == current.solver_version \
		and value.get("environment_version") == current.environment_version \
		and value.get("environment_artifact") == current.environment_artifact \
		and _implementation_artifact_matches(value.get("integration_artifact"), current.integration_artifact) \
		and value.get("damage_version") == current.damage_version \
		and value.get("engine_version") == current.engine_version \
		and _integer_value_is_valid(value.get("fixed_hz")) \
		and int(value.fixed_hz) == FIXED_HZ \
		and _integer_value_is_valid(value.get("substeps_per_tick")) \
		and int(value.substeps_per_tick) == _substeps_for_model(_model)
	if not old_solver_fields_match:
		return false
	var backend_value: Variant = value.get("backend_identity")
	if backend_value == null:
		# v2 checkpoints written before backend pinning came only from this reference
		# implementation. Keep their authoritative float64 byte path available while
		# refusing them under any native backend.
		return str(current.backend_identity.get("backend", "")) == VehicleDynamics.BACKEND_GDSCRIPT_REFERENCE
	return _backend_identity_is_valid(backend_value) \
		and _backend_identities_equal(backend_value, current.backend_identity)


func _implementation_artifact_matches(value: Variant, current: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or typeof(current) != TYPE_DICTIONARY \
			or value.size() != 2 or current.size() != 2:
		return false
	for artifact in [value, current]:
		if typeof(artifact.get("sha256")) != TYPE_STRING \
				or not _sha256_field_is_valid(artifact.get("sha256"), false) \
				or typeof(artifact.get("kind")) != TYPE_STRING \
				or str(artifact.kind) not in ["gdscript_source", "gdscript_remapped_bytecode"]:
			return false
	return value.sha256 == current.sha256 and value.kind == current.kind


func _active_backend_matches_prepared() -> bool:
	return prepared and not _prepared_backend_identity.is_empty() \
		and _backend_identities_equal(_prepared_backend_identity, _backend_identity_for_model(_model))


func _backend_identity_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	for key in ["backend", "backend_version", "solver_version"]:
		if typeof(value.get(key)) != TYPE_STRING or str(value[key]).is_empty():
			return false
	if not _integer_value_is_valid(value.get("abi_version")) \
			or int(value.abi_version) != VehicleDynamics.BACKEND_ABI_VERSION:
		return false
	if not _sha256_field_is_valid(value.get("source_sha256"), false) \
			or not _sha256_field_is_valid(value.get("toolchain_sha256"), true) \
			or not _sha256_field_is_valid(value.get("binary_sha256"), true):
		return false
	var backend := str(value.backend)
	if backend == VehicleDynamics.BACKEND_GDSCRIPT_REFERENCE:
		var artifact_kind: Variant = value.get("implementation_artifact_kind", "gdscript_source")
		if typeof(artifact_kind) != TYPE_STRING \
				or str(artifact_kind) not in ["gdscript_source", "gdscript_remapped_bytecode"]:
			return false
	elif value.has("implementation_artifact_kind") \
			and (typeof(value.implementation_artifact_kind) != TYPE_STRING \
			or str(value.implementation_artifact_kind).is_empty()):
		return false
	if backend != VehicleDynamics.BACKEND_GDSCRIPT_REFERENCE \
			and (str(value.toolchain_sha256).is_empty() or str(value.binary_sha256).is_empty()):
		return false
	return true


func _backend_identities_equal(left: Variant, right: Variant) -> bool:
	if not _backend_identity_is_valid(left) or not _backend_identity_is_valid(right):
		return false
	for key in ["backend", "backend_version", "abi_version", "solver_version",
			"source_sha256", "toolchain_sha256", "binary_sha256", "implementation_artifact_kind"]:
		if key == "abi_version":
			if int(left.get(key)) != int(right.get(key)):
				return false
		elif key == "implementation_artifact_kind":
			var left_default := "gdscript_source" if str(left.get("backend", "")) == VehicleDynamics.BACKEND_GDSCRIPT_REFERENCE else ""
			var right_default := "gdscript_source" if str(right.get("backend", "")) == VehicleDynamics.BACKEND_GDSCRIPT_REFERENCE else ""
			if str(left.get(key, left_default)) != str(right.get(key, right_default)):
				return false
		elif str(left.get(key, "")) != str(right.get(key, "")):
			return false
	return true


func _sha256_field_is_valid(value: Variant, allow_empty: bool) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var digest := str(value)
	if digest.is_empty():
		return allow_empty
	if digest.length() != 64 or digest.to_lower() != digest:
		return false
	for character in digest:
		if not str(character) in "0123456789abcdef":
			return false
	return true


func _state_is_valid(value: Variant) -> bool:
	return _state_is_valid_for_model(value, _model)


func _state_is_valid_for_model(value: Variant, model: Dictionary) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != _state_size_for_model(model):
		return false
	if _uses_nitro(model) and not NitroDynamics._valid_state(value, model):
		return false
	for item in value:
		if not is_finite(float(item)):
			return false
	return true


func _telemetry_is_valid(value: Variant) -> bool:
	return _telemetry_is_valid_for_model(value, _model)


func _telemetry_is_valid_for_model(value: Variant, model: Dictionary) -> bool:
	if typeof(value) != TYPE_DICTIONARY or not value.get("ok", false):
		return false
	if not WetPhysics.telemetry_is_valid(value.get("environment")): return false
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
	return typeof(value.get("airborne")) == TYPE_BOOL \
		and (not _uses_nitro(model) or _nitro_telemetry_is_valid(value.get("nitro")))


func _actions_are_valid(actions: Array, max_tick: int, expected_spawn: String) -> bool:
	var last_tick := -1
	for item in actions:
		if typeof(item) != TYPE_DICTIONARY or item.get("type") != "manual_recovery" \
				or not _integer_value_is_valid(item.get("tick")) or int(item.tick) < last_tick \
				or int(item.tick) < 0 or int(item.tick) > max_tick \
				or str(item.get("spawn_id", "")) != expected_spawn:
			return false
		last_tick = int(item.tick)
	return true


func _recovery_history_is_consistent(actions: Array, events: Array) -> bool:
	var counts_by_tick: Dictionary = {}
	for item in events:
		if typeof(item) != TYPE_DICTIONARY:
			return false
		if item.get("type") != "manual_recovery":
			continue
		if not _integer_value_is_valid(item.get("tick")) or typeof(item.get("spawn_id")) != TYPE_STRING:
			return false
		var event_tick := int(item.tick)
		if not counts_by_tick.has(event_tick):
			counts_by_tick[event_tick] = {}
		var spawn_counts: Dictionary = counts_by_tick[event_tick]
		var spawn_id: String = item.spawn_id
		spawn_counts[spawn_id] = int(spawn_counts.get(spawn_id, 0)) + 1
		counts_by_tick[event_tick] = spawn_counts
	for action in actions:
		if typeof(action) != TYPE_DICTIONARY or not _integer_value_is_valid(action.get("tick")) \
				or typeof(action.get("spawn_id")) != TYPE_STRING:
			return false
		var action_tick := int(action.tick)
		if not counts_by_tick.has(action_tick):
			return false
		var spawn_counts: Dictionary = counts_by_tick[action_tick]
		var spawn_id: String = action.spawn_id
		var count := int(spawn_counts.get(spawn_id, 0))
		if count <= 0:
			return false
		spawn_counts[spawn_id] = count - 1
	for tick_key in counts_by_tick:
		var spawn_counts: Dictionary = counts_by_tick[tick_key]
		for count_value in spawn_counts.values():
			if int(count_value) != 0:
				return false
	return true


func _events_are_valid(events: Array, max_tick: int) -> bool:
	var previous_event_tick := -1
	for item in events:
		if typeof(item) != TYPE_DICTIONARY or typeof(item.get("type")) != TYPE_STRING:
			return false
		var event_tick := -1
		match str(item.type):
			"damage":
				if not _event_has_exact_keys(item, ["type", "tick", "time_s", "stage",
						"body_damage", "suspension_damage", "drive_scale"]) \
						or not _event_tick_is_valid(item.get("tick"), max_tick) \
						or not _event_time_matches_tick(item.get("time_s"), int(item.tick)) \
						or typeof(item.get("stage")) != TYPE_STRING \
						or str(item.stage) not in ["scuffed", "damaged", "disabled"] \
						or not _event_number_in_range(item.get("body_damage"), 0.0, 1.0) \
						or not _event_number_in_range(item.get("suspension_damage"), 0.0, 1.0) \
						or not _event_number_in_range(item.get("drive_scale"), 0.0, 1.0):
					return false
				var expected_stage := "intact"
				var damage_fraction := maxf(float(item.body_damage), float(item.suspension_damage))
				if float(item.drive_scale) <= 0.02:
					expected_stage = "disabled"
				elif damage_fraction >= 0.28:
					expected_stage = "damaged"
				elif damage_fraction >= 0.04:
					expected_stage = "scuffed"
				if str(item.stage) != expected_stage or expected_stage == "intact":
					return false
				event_tick = int(item.tick)
			"jump", "landing":
				if not _event_has_exact_keys(item, ["type", "tick", "time_s", "speed_m_per_s"]) \
						or not _event_tick_is_valid(item.get("tick"), max_tick) \
						or not _event_time_matches_tick(item.get("time_s"), int(item.tick)) \
						or not _event_number_in_range(item.get("speed_m_per_s"), 0.0, INF):
					return false
				event_tick = int(item.tick)
			"braking_distance":
				if not _event_has_exact_keys(item, ["type", "start_tick", "end_tick", "time_s",
						"distance_m", "initial_speed_m_per_s", "end_speed_m_per_s"]) \
						or not _event_tick_is_valid(item.get("start_tick"), max_tick) \
						or not _event_tick_is_valid(item.get("end_tick"), max_tick) \
						or int(item.end_tick) <= int(item.start_tick) \
						or not _event_time_matches_tick(item.get("time_s"), int(item.end_tick)) \
						or not _event_number_in_range(item.get("distance_m"), 0.0, INF) \
						or not _event_number_in_range(item.get("initial_speed_m_per_s"), 0.5, INF, true) \
						or not _event_number_in_range(item.get("end_speed_m_per_s"), 0.0, INF):
					return false
				event_tick = int(item.end_tick)
			"manual_recovery":
				if not _event_has_exact_keys(item, ["type", "tick", "time_s", "spawn_id"]) \
						or not _event_tick_is_valid(item.get("tick"), max_tick) \
						or not _event_time_matches_tick(item.get("time_s"), int(item.tick)) \
						or typeof(item.get("spawn_id")) != TYPE_STRING or str(item.spawn_id).is_empty():
					return false
				event_tick = int(item.tick)
			_:
				return false
		if event_tick < previous_event_tick:
			return false
		previous_event_tick = event_tick
	return true


func _event_has_exact_keys(event: Dictionary, expected_keys: Array) -> bool:
	if event.size() != expected_keys.size():
		return false
	for key in expected_keys:
		if not event.has(str(key)):
			return false
	return true


func _event_tick_is_valid(value: Variant, max_tick: int) -> bool:
	return _integer_value_is_valid(value) and int(value) >= 0 and int(value) <= max_tick


func _event_time_matches_tick(value: Variant, at_tick: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) \
		and absf(float(value) - float(at_tick) * DT) <= 1.0e-12


func _event_number_in_range(value: Variant, minimum: float, maximum: float,
		strict_minimum := false) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return false
	var number := float(value)
	if strict_minimum and number <= minimum:
		return false
	if not strict_minimum and number < minimum:
		return false
	return number <= maximum


func _braking_state_is_valid(braking: Dictionary, at_tick: int) -> bool:
	if braking.is_empty():
		return true
	for key in ["start_tick", "start_speed_m_per_s", "distance_m"]:
		if not braking.has(key):
			return false
	if not _integer_value_is_valid(braking.start_tick) or int(braking.start_tick) < 0 or int(braking.start_tick) > at_tick:
		return false
	for key in ["start_speed_m_per_s", "distance_m"]:
		if typeof(braking[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(braking[key])) or float(braking[key]) < 0.0:
			return false
	return true


func _checkpoint_hash(value: Dictionary) -> String:
	var content := value.duplicate(true)
	content.erase("checkpoint_sha256")
	return _hash_variant(content)


## JSON mirrors are for inspection. Float64 blobs and their SHA-256 fields remain
## authoritative; allow only a small serialization tolerance in their mirrors.
func _checkpoint_float_array_mirror_matches(display_value: Variant, authoritative: PackedFloat64Array) -> bool:
	if typeof(display_value) != TYPE_ARRAY or display_value.size() != authoritative.size():
		return false
	for index in range(authoritative.size()):
		var displayed: Variant = display_value[index]
		if typeof(displayed) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(displayed)):
			return false
		var expected := float(authoritative[index])
		var tolerance := CHECKPOINT_DISPLAY_MIRROR_TOLERANCE * maxf(1.0, absf(expected))
		if absf(float(displayed) - expected) > tolerance:
			return false
	return true


func _checkpoint_controls_mirror_matches(display_value: Variant, authoritative: Dictionary) -> bool:
	if typeof(display_value) != TYPE_DICTIONARY or display_value.size() != authoritative.size():
		return false
	for key in ["throttle", "steering", "brake"]:
		var displayed: Variant = display_value.get(key, NAN)
		var expected: Variant = authoritative.get(key, NAN)
		if typeof(displayed) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(displayed)) \
				or typeof(expected) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(expected)):
			return false
		var tolerance := CHECKPOINT_DISPLAY_MIRROR_TOLERANCE * maxf(1.0, absf(float(expected)))
		if absf(float(displayed) - float(expected)) > tolerance:
			return false
	var displayed_reverse: Variant = display_value.get("reverse")
	return typeof(displayed_reverse) == TYPE_BOOL \
		and bool(displayed_reverse) == bool(authoritative.get("reverse", false))


func _integer_value_is_valid(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return false
	return floor(float(value)) == float(value)


func _hash_variant(value: Variant) -> String:
	return _hash_bytes(JSON.stringify(value, "", true, true).to_utf8_buffer())


func _hash_bytes(value: PackedByteArray) -> String:
	if value.is_empty():
		return SHA256_EMPTY_HEX
	var digest := HashingContext.new()
	if digest.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if digest.update(value) != OK:
		return ""
	return digest.finish().hex_encode()


func _base64_bytes(value: PackedByteArray) -> String:
	return "" if value.is_empty() else Marshalls.raw_to_base64(value)


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
	if not fault_reason.is_empty():
		return
	fault_reason = reason
	load_error = reason
	_set_paused(true)
	if recording:
		_interrupt_recording(reason)
	if not _suppress_signals:
		faulted.emit(reason)
