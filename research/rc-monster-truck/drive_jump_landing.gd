extends SceneTree

const Activity = preload("res://vehicles/ground/ground_scene.gd")
const VehicleDynamics = preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const TICK_RATE := 240.0
const DT := 1.0 / TICK_RATE
const MAX_TICKS := 2400
const POST_LANDING_SETTLE_TICKS := 120
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}

var activity: Node3D
var throttle_ticks := 0
var gravity_scale := 1.0
var output_path := ""
var _cli_error := ""
var _saw_gravity_scale := false
var samples: Array[Dictionary] = []
var events: Array[Dictionary] = []
var control_state_audit: Array[Dictionary] = []
var _last_airborne := false
var _events_seen := 0
var _airborne_hud_seen := false
var _ground_hud_after_landing := false
var _landing_contact_count := 0
var _landing_upright_dot := -1.0
var _post_landing_until_tick := -1
var _drive_torque_per_wheel_nm := 0.0
var _drive_torque_fade_rad_s := 0.0
var _fade_window_ticks := 0
var _fade_window_all_wheels_at_or_above := 0
var _fade_window_min_abs_wheel_spin := INF
var _fade_window_max_endpoint_torque_nm := 0.0


func _initialize() -> void:
	var saw_throttle_ticks := false
	var saw_output_path := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--throttle-ticks="):
			if saw_throttle_ticks:
				_cli_error = "--throttle-ticks may be supplied only once"
				break
			saw_throttle_ticks = true
			var tick_text := argument.trim_prefix("--throttle-ticks=")
			if not _is_unsigned_integer(tick_text):
				_cli_error = "--throttle-ticks must be an integer in [1, 1200]"
				break
			throttle_ticks = int(tick_text)
			if throttle_ticks < 1 or throttle_ticks > 1200:
				_cli_error = "--throttle-ticks must be an integer in [1, 1200]"
				break
		elif argument.begins_with("--output="):
			if saw_output_path:
				_cli_error = "--output may be supplied only once"
				break
			saw_output_path = true
			output_path = argument.trim_prefix("--output=").replace("\\", "/")
			if not _is_absolute_path(output_path) or not output_path.to_lower().ends_with(".json"):
				_cli_error = "--output must be an absolute .json path"
				break
		elif argument.begins_with("--gravity-scale="):
			if _saw_gravity_scale:
				_cli_error = "--gravity-scale may be supplied only once"
				break
			_saw_gravity_scale = true
			var gravity_text := argument.trim_prefix("--gravity-scale=")
			if not gravity_text.is_valid_float():
				_cli_error = "--gravity-scale must be a finite number in [0, 2]"
				break
			gravity_scale = gravity_text.to_float()
			if not is_finite(gravity_scale) or gravity_scale < 0.0 or gravity_scale > 2.0:
				_cli_error = "--gravity-scale must be a finite number in [0, 2]"
				break
		else:
			_cli_error = "unsupported argument: " + argument
			break
	if _cli_error.is_empty() and not saw_throttle_ticks:
		_cli_error = "required argument missing: --throttle-ticks=1..1200"
	if _cli_error.is_empty() and not saw_output_path:
		_cli_error = "required argument missing: --output=<fresh.json>"
	if _cli_error.is_empty() and not DirAccess.dir_exists_absolute(output_path.get_base_dir()):
		_cli_error = "output directory does not exist: " + output_path.get_base_dir()
	if _cli_error.is_empty() and FileAccess.file_exists(output_path):
		_cli_error = "refusing to overwrite existing output: " + output_path
	_run.call_deferred()


func _run() -> void:
	if not _cli_error.is_empty():
		printerr("ERROR: " + _cli_error)
		quit(2)
		return
	TranslationServer.set_locale("en")
	activity = Activity.new()
	activity.enable_audio = false
	activity.enable_course_visual = false
	activity.set_physics_process(false)
	activity.set_process(false)
	root.add_child(activity)
	if not activity.startup_error.is_empty():
		_finish({"ok": false, "error": "activity startup failed: " + activity.startup_error})
		return
	if throttle_ticks < 1 or throttle_ticks > 1200:
		_finish({"ok": false, "error": "throttle tick count is outside the supported range"})
		return
	if _saw_gravity_scale:
		activity._select_mode(2)
		activity._experiment({
			"gravity_scale": gravity_scale,
			"grip_scale": 1.0,
			"spring_scale": 1.0,
			"damper_scale": 1.0,
			"ballast_kg": 0.0,
			"ballast_height_m": 0.03,
		})
		if absf(float(activity.session.model_snapshot().gravity_m_per_s2) - 9.80665 * gravity_scale) > 1.0e-10:
			_finish({
				"ok": false,
				"error": "gravity experiment did not apply the requested scale",
				"experiment_load_error": activity.session.load_error,
				"actual_gravity_m_per_s2": float(activity.session.model_snapshot().gravity_m_per_s2),
			})
			return
	if not activity.session.reset("jump_start"):
		_finish({"ok": false, "error": "could not select the supported jump_start course spawn"})
		return
	activity._after_reset()
	activity.scripted_controls = _controls_for_tick
	var model: Dictionary = activity.session.model_snapshot()
	_drive_torque_per_wheel_nm = float(model.get("drive_torque_per_wheel_nm", 0.0))
	_drive_torque_fade_rad_s = float(model.get("drive_torque_fade_rad_s", 0.0))
	activity.session.tick_once(NEUTRAL)
	activity.handle_action("resume")
	if activity.session.paused:
		_finish({"ok": false, "error": "activity refused to resume from neutral controls"})
		return
	_last_airborne = bool(activity.session.telemetry_snapshot().airborne)
	var outcome := "timeout"
	for _step in MAX_TICKS:
		activity._physics_process(DT)
		if not activity.session.fault_reason.is_empty():
			outcome = "session_fault"
			break
		var telemetry: Dictionary = activity.session.telemetry_snapshot()
		_record_torque_fade_state()
		if activity.session.tick in [299, 300, 301, 599, 600, 601]:
			_capture_control_state_audit(telemetry)
		var airborne := bool(telemetry.airborne)
		var new_events: Array[Dictionary] = activity.session.event_tape_snapshot()
		while _events_seen < new_events.size():
			var event: Dictionary = new_events[_events_seen]
			events.append(event.duplicate(true))
			_events_seen += 1
			if str(event.get("type", "")) == "jump":
				activity._process(0.0)
				_airborne_hud_seen = activity.dashboard.telemetry.text.contains("AIR")
			elif str(event.get("type", "")) == "landing" and _post_landing_until_tick < 0:
				activity._process(0.0)
				_ground_hud_after_landing = not activity.dashboard.telemetry.text.contains("AIR")
				var landing_telemetry: Dictionary = activity.session.telemetry_snapshot()
				_landing_contact_count = _contact_count(landing_telemetry.wheel_in_contact)
				_landing_upright_dot = _upright_dot(activity.session.state_snapshot())
				_post_landing_until_tick = activity.session.tick + POST_LANDING_SETTLE_TICKS
			_capture_sample(telemetry, event)
		if activity.session.tick % 24 == 0 or airborne != _last_airborne:
			_capture_sample(telemetry)
		_last_airborne = airborne
		if _post_landing_until_tick >= 0 and activity.session.tick >= _post_landing_until_tick:
			if activity.dashboard.toast.text.begins_with("Landed!"):
				outcome = "landed_message"
			elif _upright_dot(activity.session.state_snapshot()) > 0.65 \
					and not bool(telemetry.airborne) and activity.session.run_valid:
				outcome = "upright_short_landing"
			else:
				outcome = "landing_not_upright"
			break
	var final_state: PackedFloat64Array = activity.session.state_snapshot()
	var final_telemetry: Dictionary = activity.session.telemetry_snapshot()
	var landing_event := _landing_event()
	var result := {
		"ok": outcome == "landed_message" and events.size() >= 2 and landing_event != {} \
			and _airborne_hud_seen and _ground_hud_after_landing and _landing_contact_count > 0 \
			and _landing_upright_dot > 0.65 and _contact_count(final_telemetry.wheel_in_contact) > 0,
		"outcome": outcome,
		"spawn_id": activity.session.spawn_id,
		"throttle_ticks": throttle_ticks,
		"requested_gravity_scale": gravity_scale,
		"effective_gravity_m_per_s2": float(activity.session.model_snapshot().gravity_m_per_s2),
		"tick_count": activity.session.tick,
		"run_valid": activity.session.run_valid,
		"landing_event": landing_event,
		"airtime_s": float(landing_event.get("time_s", -1.0)) - float(_jump_event().get("time_s", 0.0)),
		"airborne_hud_seen": _airborne_hud_seen,
		"ground_hud_after_landing": _ground_hud_after_landing,
		"landing_upright_dot": _landing_upright_dot,
		"landing_wheel_contact_count": _landing_contact_count,
		"post_landing_settle_ticks": POST_LANDING_SETTLE_TICKS,
		"upright_dot_at_end": _upright_dot(final_state),
		"final_airborne": bool(final_telemetry.airborne),
		"final_wheel_contact_count": _contact_count(final_telemetry.wheel_in_contact),
		"final_hull_contact_count": _contact_count(final_telemetry.hull_in_contact),
		"activity_toast": activity.dashboard.toast.text,
		"control_state_audit": control_state_audit,
		"full_throttle_fade_window": {
			"accepted_ticks_first": 301,
			"accepted_ticks_last": throttle_ticks if throttle_ticks > 300 else 300,
			"accepted_tick_count": _fade_window_ticks,
			"expected_drive_torque_per_wheel_nm": _drive_torque_per_wheel_nm,
			"drive_torque_fade_rad_s": _drive_torque_fade_rad_s,
			"minimum_abs_wheel_spin_rad_per_s": _fade_window_min_abs_wheel_spin if _fade_window_ticks > 0 else -1.0,
			"ticks_all_wheels_at_or_above_fade": _fade_window_all_wheels_at_or_above,
			"maximum_endpoint_drive_torque_nm": _fade_window_max_endpoint_torque_nm,
			"drive_torque_formula": "throttle * drive_torque_per_wheel_nm * max(0, 1 - abs(wheel_spin_rad_s) / drive_torque_fade_rad_s)",
		},
		"events": events,
		"samples": samples,
	}
	_finish(result)


func _controls_for_tick(tick: int) -> Dictionary:
	var controls: Dictionary = NEUTRAL.duplicate(true)
	if tick < throttle_ticks:
		controls.throttle = 1.0
	return controls


func _capture_sample(telemetry: Dictionary, event: Dictionary = {}) -> void:
	var state: PackedFloat64Array = activity.session.state_snapshot()
	var sample := {
		"tick": activity.session.tick,
		"time_s": activity.session.time_s(),
		"north_m": state[VehicleDynamics.POS],
		"east_m": state[VehicleDynamics.POS + 1],
		"up_m": -state[VehicleDynamics.POS + 2],
		"forward_speed_m_per_s": float(telemetry.forward_speed_m_per_s),
		"speed_m_per_s": float(telemetry.speed_m_per_s),
		"airborne": bool(telemetry.airborne),
		"wheel_contact_count": _contact_count(telemetry.wheel_in_contact),
		"hull_contact_count": _contact_count(telemetry.hull_in_contact),
		"upright_dot": _upright_dot(state),
		"accepted_controls": _last_accepted_controls(),
		"wheel_spin_rad_per_s": _wheel_spin(state),
	}
	if not event.is_empty():
		sample["event"] = event.duplicate(true)
	samples.append(sample)


func _capture_control_state_audit(telemetry: Dictionary) -> void:
	var state: PackedFloat64Array = activity.session.state_snapshot()
	var controls := _last_accepted_controls()
	if controls.is_empty():
		return
	var wheel_spin := _wheel_spin(state)
	control_state_audit.append({
		"accepted_tick": activity.session.tick,
		"callback_tick": activity.session.tick - 1,
		"accepted_controls": controls,
		"forward_speed_m_per_s": float(telemetry.forward_speed_m_per_s),
		"wheel_spin_rad_per_s": wheel_spin,
	})


func _wheel_spin(state: PackedFloat64Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for corner in VehicleDynamics.CORNER_COUNT:
		result.append(state[VehicleDynamics.WHEEL_SPIN + corner])
	return result


func _record_torque_fade_state() -> void:
	var accepted_tick: int = activity.session.tick
	if throttle_ticks <= 300 or accepted_tick <= 300 or accepted_tick > throttle_ticks:
		return
	var controls := _last_accepted_controls()
	if controls.is_empty() or float(controls.throttle) != 1.0:
		return
	var spin := _wheel_spin(activity.session.state_snapshot())
	var minimum_abs_spin := INF
	var tick_max_endpoint_torque := 0.0
	var all_above_fade := _drive_torque_fade_rad_s > 0.0
	for wheel_spin in spin:
		var absolute_spin := absf(wheel_spin)
		minimum_abs_spin = minf(minimum_abs_spin, absolute_spin)
		if absolute_spin < _drive_torque_fade_rad_s:
			all_above_fade = false
		var endpoint_torque := _drive_torque_per_wheel_nm
		if _drive_torque_fade_rad_s > 0.0:
			endpoint_torque *= maxf(0.0, 1.0 - absolute_spin / _drive_torque_fade_rad_s)
		tick_max_endpoint_torque = maxf(tick_max_endpoint_torque, endpoint_torque)
	_fade_window_ticks += 1
	_fade_window_min_abs_wheel_spin = minf(_fade_window_min_abs_wheel_spin, minimum_abs_spin)
	_fade_window_max_endpoint_torque_nm = maxf(_fade_window_max_endpoint_torque_nm, tick_max_endpoint_torque)
	if all_above_fade:
		_fade_window_all_wheels_at_or_above += 1


func _last_accepted_controls() -> Dictionary:
	var control_tape: PackedFloat64Array = activity.session.control_tape_snapshot()
	if control_tape.size() < 4:
		return {}
	var last := control_tape.size() - 4
	return {
		"throttle": control_tape[last],
		"steering": control_tape[last + 1],
		"brake": control_tape[last + 2],
		"reverse_flag": control_tape[last + 3],
	}


func _landing_event() -> Dictionary:
	for event in events:
		if str(event.get("type", "")) == "landing":
			return event
	return {}


func _jump_event() -> Dictionary:
	for event in events:
		if str(event.get("type", "")) == "jump":
			return event
	return {}


func _upright_dot(state: PackedFloat64Array) -> float:
	var x := state[VehicleDynamics.ATT + 1]
	var y := state[VehicleDynamics.ATT + 2]
	return 1.0 - 2.0 * (x * x + y * y)


func _contact_count(flags: PackedByteArray) -> int:
	var count := 0
	for flag in flags:
		if flag != 0:
			count += 1
	return count


func _is_unsigned_integer(value: String) -> bool:
	if value.is_empty():
		return false
	for character in value:
		if not str(character) in "0123456789":
			return false
	return true


func _is_absolute_path(path: String) -> bool:
	return path.begins_with("/") or (path.length() >= 3 and path.substr(1, 1) == ":" and path.substr(2, 1) == "/")


func _finish(result: Dictionary) -> void:
	if activity != null and is_instance_valid(activity) and activity.session.prepared:
		var identities: Dictionary = activity.session.identities_snapshot()
		var vehicle_identity: Dictionary = identities.get("model", {})
		var course_identity: Dictionary = identities.get("course", {})
		var backend_identity: Dictionary = activity.session._prepared_backend_identity.duplicate(true)
		result["vehicle_identity"] = vehicle_identity
		result["course_identity"] = course_identity
		result["backend_identity"] = backend_identity
		result["identity_hashes"] = {
			"vehicle_sha256": str(vehicle_identity.get("sha256", "")),
			"course_sha256": str(course_identity.get("sha256", "")),
			"backend_source_sha256": str(backend_identity.get("source_sha256", "")),
			"backend_toolchain_sha256": str(backend_identity.get("toolchain_sha256", "")),
			"backend_binary_sha256": str(backend_identity.get("binary_sha256", "")),
		}
		var accepted_control_tape: PackedFloat64Array = activity.session.control_tape_snapshot()
		var accepted_control_rows: Array[Dictionary] = []
		for offset in range(0, accepted_control_tape.size(), 4):
			accepted_control_rows.append({
				"accepted_tick": offset / 4 + 1,
				"throttle": accepted_control_tape[offset],
				"steering": accepted_control_tape[offset + 1],
				"brake": accepted_control_tape[offset + 2],
				"reverse_flag": accepted_control_tape[offset + 3],
			})
		var control_digest_context := HashingContext.new()
		var control_digest_text := JSON.stringify(accepted_control_rows, "", true, true)
		var control_digest_error := control_digest_context.start(HashingContext.HASH_SHA256)
		if control_digest_error == OK:
			control_digest_error = control_digest_context.update(control_digest_text.to_utf8_buffer())
		result["accepted_control_tape"] = {
			"layout": ["throttle", "steering", "brake", "reverse_flag"],
			"accepted_tick_count": accepted_control_rows.size(),
			"canonical_rows_sha256": control_digest_context.finish().hex_encode() if control_digest_error == OK else "",
			"rows": accepted_control_rows,
		}
	if FileAccess.file_exists(output_path):
		printerr("ERROR: refusing to overwrite existing output: " + output_path)
		if activity != null and is_instance_valid(activity):
			activity.free()
		quit(2)
		return
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t", true, true) + "\n")
		file.close()
	else:
		result["ok"] = false
		result["trace_error"] = "could not write trace to " + output_path
	var console_summary := result.duplicate(true)
	console_summary.erase("accepted_control_tape")
	console_summary.erase("samples")
	console_summary.erase("events")
	print("RCV jump/landing: " + JSON.stringify(console_summary, "", true, true))
	print("Trace: " + output_path)
	if activity != null and is_instance_valid(activity):
		activity.free()
	quit(0 if bool(result.get("ok", false)) else 1)
