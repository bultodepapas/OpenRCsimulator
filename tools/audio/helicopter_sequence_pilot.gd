## Research-only adapter of HELI-20's X-Cell ground-cycle pilot.
## Source law: research/helicopter/ground_start/cycles.gd::run_cycle, documented in
## docs/research/helicopter/HELI-20/README.md. This helper does not reset or step a
## session and does not alter physics. Call before_accepted_tick() from Simulation.before_step.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const Skids := preload("res://physics/rotorcraft/skid_contact.gd")

const AIRCRAFT_ID := "xcell-60-research"
const TARGET_NORTH_M := 6.0
const TARGET_EAST_M := 0.0
const G := 9.80665
const MAX_CYCLE_SECONDS := 120.0
const GOVERNED_AFTER_SPOOL_S := 14.0
const MAX_FLIGHT_SECONDS := 65.0
const MAX_HEIGHT_DURING_SPOOL_M := 0.16
const FLIGHT_COMPLETION_HEIGHT_M := 0.14
const TOUCHDOWN_HOLD_SECONDS := 2.0
const ROTOR_STOP_DWELL_S := 1.0

## spool | flight | lower_collective | coast | complete | failed
var phase := "unconfigured"
var complete := false
var failure_reason := ""

var _session: Node
var _begin_attempted := false
var _started := false
var _has_prepared_tick := false
var _last_prepared_tick := -1
var _last_confirmed_tick := -1
var _expected_tick := -1
var _accepted_ticks := 0
var _start_time_s := 0.0
var _phase_start_s := 0.0
var _initial_state := PackedFloat64Array()
var _initial_yaw_rad := 0.0
var _trainer_max_tilt_rad := 0.0
var _landing_collective := 0.0
var _iz := 0.0
var _inorth := 0.0
var _ieast := 0.0
var _peak_height_m := 0.0
var _peak_radius_m := 0.0
var _spool_displacement_m := 0.0
var _spool_yaw_rad := 0.0
var _touchdown_down_speed_m_s := 0.0
var _hover_error_m := 0.0
var _left_ground := false
var _grounded_previous := true
var _shutdown_on_ground := false
var _rotor_stop_time_s := -1.0
var _last_commands: Dictionary = {}


## Start one cycle on an already configured, ground-reset X-Cell session.
## The caller owns setup, field/weather selection, and the single reset before this call.
## This method intentionally never calls reset().
func begin_cycle(session: Node) -> bool:
	if _begin_attempted:
		return _refuse("begin_cycle may only be called once")
	_begin_attempted = true
	_session = session
	if _session == null:
		return _refuse("session is null")
	var aircraft: Dictionary = _session.aircraft
	if str(aircraft.get("id", "")) != AIRCRAFT_ID:
		return _refuse("pilot is qualified only for " + AIRCRAFT_ID)
	if str(_session.start_choice) != "ground":
		return _refuse("pilot requires the already selected ground start")
	if not _session.is_flyable():
		return _refuse("session is not flyable: " + str(_session.pause_reason))
	if bool(_session.sim.paused):
		return _refuse("session must be resumed before the cycle starts")
	if _session.sim.state.size() != 13 or _session.sim.continuous.size() != 14:
		return _refuse("expected the X-Cell ground-start body and 14 continuous states")
	if bool(_session.power.armed) or not bool(_session.zero_drive_hold):
		return _refuse("cycle must start disarmed with drive hold engaged")
	var electronics: Dictionary = _session.aircraft.context.electronics_model
	_trainer_max_tilt_rad = float(electronics.get("trainer_max_tilt_rad", NAN))
	if not is_finite(_trainer_max_tilt_rad) or _trainer_max_tilt_rad <= 0.0:
		return _refuse("X-Cell trainer tilt reference is invalid")
	var dt_s: float = float(_session.sim.dt())
	if not is_finite(dt_s) or dt_s <= 0.0:
		return _refuse("session simulation step is invalid")

	_start_time_s = float(_session.sim.time())
	_phase_start_s = _start_time_s
	_expected_tick = int(_session.sim.tick)
	_initial_state = _session.sim.state.duplicate()
	_initial_yaw_rad = M.q_to_euler(_initial_state.slice(6, 10))[0]
	_last_commands = {"roll": 0.0, "pitch": 0.0, "yaw": 0.0,
		"throttle": float(_session.startup_collective)}
	_set_commands(_last_commands)
	phase = "spool"
	var arm_accepted: bool = _session.toggle_motor_arm()
	if not arm_accepted or not bool(_session.power.armed):
		return _refuse("arm/hold refused: " + str(_session.pause_reason))
	if not _session.set_drive_hold(false):
		return _refuse("arm/hold refused: " + str(_session.pause_reason))
	_started = true
	return true


## Apply the HELI-20 law once immediately before each accepted Simulation step.
## Connect this method to session.sim.before_step; it only assigns session commands/inputs and
## lifecycle APIs. The session's normal Simulation loop remains the sole physics stepper.
func before_accepted_tick() -> Dictionary:
	if not _started or complete or not failure_reason.is_empty():
		return status()
	_confirm_previous_tick()
	if not failure_reason.is_empty():
		return status()
	var tick: int = int(_session.sim.tick)
	if tick != _expected_tick:
		return _fail_status("tick failed: expected %d, got %d" % [_expected_tick, tick])
	_last_prepared_tick = tick
	_has_prepared_tick = true
	_expected_tick = tick + 1
	if _accepted_duration_s() >= MAX_CYCLE_SECONDS:
		return _fail_status("cycle acceptance metric failed")

	var t_s: float = _accepted_duration_s()
	var state: PackedFloat64Array = _session.sim.state
	var velocity_ned: PackedFloat64Array = M.q_rotate(state.slice(6, 10), state.slice(3, 6))
	var height_m: float = -state[2]
	var contact: Dictionary = Skids.evaluate(state, _session.aircraft.skids, _session.ground_surfaces)
	var grounded: bool = bool(contact.get("ok", false)) and float(contact.get("max_depth_m", 0.0)) > 0.0
	if not grounded and height_m > 0.2:
		_left_ground = true
	if grounded and not _grounded_previous and _left_ground:
		_touchdown_down_speed_m_s = maxf(_touchdown_down_speed_m_s, velocity_ned[2])
	_grounded_previous = grounded
	_peak_height_m = maxf(_peak_height_m, height_m)
	_peak_radius_m = maxf(_peak_radius_m,
		sqrt((state[0] - TARGET_NORTH_M) ** 2 + (state[1] - TARGET_EAST_M) ** 2))
	if phase == "spool":
		var position_delta: PackedFloat64Array = M.sub(state.slice(0, 3), _initial_state.slice(0, 3))
		_spool_displacement_m = maxf(_spool_displacement_m, M.norm(position_delta))
		var yaw_rad: float = M.q_to_euler(state.slice(6, 10))[0]
		_spool_yaw_rad = maxf(_spool_yaw_rad, absf(wrapf(yaw_rad - _initial_yaw_rad, -PI, PI)))
		if height_m > MAX_HEIGHT_DURING_SPOOL_M:
			return _fail_status("automatic liftoff during zero-pitch spool")
		if t_s >= GOVERNED_AFTER_SPOOL_S:
			if str(_session.power_phase()) != "GOVERNED":
				return _fail_status("spool never governed")
			phase = "flight"
			_phase_start_s = float(_session.sim.time())

	if phase == "flight":
		var flight_t_s: float = float(_session.sim.time()) - _phase_start_s
		var target_height_m: float = 0.11 + minf(flight_t_s * 0.18, 1.09) \
			if flight_t_s < 16.0 else maxf(0.06, 1.2 - (flight_t_s - 16.0) * 0.12)
		var down_target_m_s: float = clampf((height_m - target_height_m) * 0.8, -0.25, 0.2)
		var vertical_error_m_s: float = down_target_m_s - velocity_ned[2]
		var dt_s: float = float(_session.sim.dt())
		_iz = clampf(_iz + 0.03 * vertical_error_m_s * dt_s, -0.15, 0.3)
		var throttle: float = clampf(0.49 - 0.07 * vertical_error_m_s - _iz, 0.16, 0.7)
		_inorth = clampf(_inorth + 0.12 * (TARGET_NORTH_M - state[0]) * dt_s, -0.8, 0.8)
		_ieast = clampf(_ieast + 0.12 * (TARGET_EAST_M - state[1]) * dt_s, -0.8, 0.8)
		var acceleration_north: float = 0.7 * (TARGET_NORTH_M - state[0]) \
			- 1.4 * velocity_ned[0] + _inorth
		var acceleration_east: float = 0.7 * (TARGET_EAST_M - state[1]) \
			- 1.4 * velocity_ned[1] + _ieast
		var yaw_rad: float = M.q_to_euler(state.slice(6, 10))[0]
		var acceleration_forward: float = cos(yaw_rad) * acceleration_north \
			+ sin(yaw_rad) * acceleration_east
		var acceleration_right: float = -sin(yaw_rad) * acceleration_north \
			+ cos(yaw_rad) * acceleration_east
		var roll: float = clampf(acceleration_right / G / _trainer_max_tilt_rad, -0.4, 0.4)
		var pitch: float = clampf(-acceleration_forward / G / _trainer_max_tilt_rad, -0.4, 0.4)
		_last_commands = {"roll": roll, "pitch": pitch, "yaw": 0.0, "throttle": throttle}
		_set_commands(_last_commands)
		if flight_t_s >= 12.0 and flight_t_s <= 16.0:
			_hover_error_m = maxf(_hover_error_m, absf(height_m - 1.2))
		if flight_t_s > 26.0 and grounded and height_m < FLIGHT_COMPLETION_HEIGHT_M \
				and M.norm(velocity_ned) < 0.1:
			phase = "lower_collective"
			_phase_start_s = float(_session.sim.time())
			_landing_collective = throttle
			_shutdown_on_ground = true
		elif flight_t_s > MAX_FLIGHT_SECONDS:
			return _fail_status("test pilot did not finish landing")
	elif phase == "lower_collective":
		var ramp_fraction: float = clampf((float(_session.sim.time()) - _phase_start_s) / 2.0, 0.0, 1.0)
		var throttle: float = lerpf(_landing_collective, float(_session.startup_collective), ramp_fraction)
		_last_commands = {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": throttle}
		_set_commands(_last_commands)
		if ramp_fraction == 1.0:
			_session.set_drive_hold(true)
			phase = "coast"
			_phase_start_s = float(_session.sim.time())
	elif phase == "coast":
		if _session.sim.continuous[0] == 0.0:
			if _rotor_stop_time_s < 0.0:
				_rotor_stop_time_s = float(_session.sim.time())
			if float(_session.sim.time()) - _rotor_stop_time_s >= ROTOR_STOP_DWELL_S:
				if not _session.toggle_motor_arm():
					return _fail_status("disarm refused")
				return _finish_cycle()
	return status()


## Read the result without advancing the controller. Call after a simulation frame as needed so
## a final failed Simulation step is visible even when it prevents another before_step callback.
func status() -> Dictionary:
	if _started and not complete and failure_reason.is_empty():
		_confirm_previous_tick()
		if failure_reason.is_empty() and not _session.is_flyable():
			_fail("tick failed: " + str(_session.pause_reason))
	return _status_dictionary()


func _confirm_previous_tick() -> void:
	if not _has_prepared_tick or _last_confirmed_tick == _last_prepared_tick:
		return
	var current_tick: int = int(_session.sim.tick)
	if current_tick == _last_prepared_tick + 1:
		_accepted_ticks += 1
		_last_confirmed_tick = _last_prepared_tick
	elif current_tick != _last_prepared_tick or not _session.is_flyable():
		_fail("tick failed: " + str(_session.pause_reason))


func _set_commands(commands: Dictionary) -> void:
	_session.commands = commands.duplicate(true)
	_session.sim.inputs = PackedFloat64Array([
		float(commands.get("roll", 0.0)),
		float(commands.get("pitch", 0.0)),
		float(commands.get("yaw", 0.0)),
		float(commands.get("throttle", float(_session.startup_collective))),
	])


func _accepted_duration_s() -> float:
	return float(_session.sim.time()) - _start_time_s


func _finish_cycle() -> Dictionary:
	var final_omega_rad_s: float = float(_session.sim.continuous[0]) if _session.sim.continuous.size() > 0 else NAN
	var metrics := _metrics_dictionary()
	metrics["final_omega_rad_s"] = final_omega_rad_s
	metrics["final_body"] = Array(_session.sim.state)
	var ok: bool = _left_ground and _peak_height_m > 0.9 and _peak_height_m < 1.5 \
		and _peak_radius_m < 2.5 and _hover_error_m < 0.15 and _shutdown_on_ground \
		and _touchdown_down_speed_m_s < 0.35 and final_omega_rad_s == 0.0 \
		and not bool(_session.power.armed) and bool(_session.zero_drive_hold)
	if not ok:
		return _fail_status("cycle acceptance metric failed")
	complete = true
	phase = "complete"
	return _status_dictionary()


func _metrics_dictionary() -> Dictionary:
	return {
		"seconds": _accepted_duration_s(),
		"accepted_ticks": _accepted_ticks,
		"spool_displacement_m": _spool_displacement_m,
		"spool_yaw_deg": rad_to_deg(_spool_yaw_rad),
		"left_ground": _left_ground,
		"peak_height_m": _peak_height_m,
		"peak_radius_m": _peak_radius_m,
		"hover_height_error_m": _hover_error_m,
		"touchdown_down_speed_m_s": _touchdown_down_speed_m_s,
		"shutdown_on_ground": _shutdown_on_ground,
		"final_omega_rad_s": float(_session.sim.continuous[0]) if _session != null and _session.sim.continuous.size() > 0 else NAN,
	}


func _status_dictionary() -> Dictionary:
	return {
		"phase": phase,
		"complete": complete,
		"failed": not failure_reason.is_empty(),
		"failure": failure_reason,
		"commands": _last_commands.duplicate(true),
		"metrics": _metrics_dictionary() if _session != null else {},
	}


func _fail_status(reason: String) -> Dictionary:
	_fail(reason)
	return _status_dictionary()


func _fail(reason: String) -> void:
	if failure_reason.is_empty():
		failure_reason = reason
	phase = "failed"
	complete = false


func _refuse(reason: String) -> bool:
	_fail(reason)
	return false
