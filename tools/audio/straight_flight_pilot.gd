extends RefCounted

## AUD-15 draft: straight, continuous fixed-wing audio route.
## Reuses FT-card-v5 pilot laws and never reads or writes FlightSession state.

const Pilot := preload("res://../research/flight-test/pilot.gd")
const G := 9.80665
const RHO := 1.225
const PILOT_DT := 1.0 / 240.0
const APPROACH_GAMMA := PI / 45.0 # 4 degrees, matching FT-card-v5.
const TAKEOFF_RAMP_S := 2.0
const LEVEL_FLIGHT_S := 2.0
const AIM_PAST_FINAL_M := 10.0

## takeoff | flight | approach | flare | rollout | invalid
var phase: String = "unconfigured"
var finished := false

var _configured := false
var _v_start_mps := 0.0
var _stall_speed_mps := 0.0
var _approach_speed_mps := 0.0
var _flight_speed_mps := 0.0
var _start_throttle := 0.0
var _stall_start_alpha_rad := 0.0
var _rotation_pitch_rad := 0.0
var _cruise_clearance_m := 30.0
var _level_flight_s := LEVEL_FLIGHT_S
var _heading_rad := NAN
var _target_altitude_m := NAN
var _aim_north_m := NAN
var _aim_east_m := NAN
var _phase_started_s := 0.0
var _flight_mode := "climb"
var _touchdown_pitch_rad := NAN
var _airborne_dwell_s := 0.0
var _context: Dictionary = {}


## Configure from the accepted session model and its actual solved start trim.
## Pass session.aircraft.model and session.start.throttle after runway reset.
func configure(model: Dictionary, start_throttle: float, cruise_clearance_m := 30.0,
		level_flight_s := LEVEL_FLIGHT_S) -> bool:
	_configured = false
	phase = "invalid"
	var reference: Dictionary = model.get("reference", {})
	var envelope: Dictionary = model.get("envelope", {})
	var mass_kg := float(model.get("mass_kg", NAN))
	var area_m2 := float(reference.get("S", NAN))
	var cl_max := float(envelope.get("CL_max", NAN))
	_v_start_mps = float(model.get("start_speed", NAN))
	_stall_start_alpha_rad = float(envelope.get("a1", deg_to_rad(12.0)))
	if not is_finite(mass_kg) or mass_kg <= 0.0 or not is_finite(area_m2) or area_m2 <= 0.0 \
			or not is_finite(cl_max) or cl_max <= 0.0 or not is_finite(_v_start_mps) or _v_start_mps <= 0.0 \
			or not is_finite(start_throttle) or start_throttle < 0.0 or start_throttle > 1.0 \
			or not is_finite(cruise_clearance_m) or cruise_clearance_m <= 3.0 \
			or not is_finite(level_flight_s) or level_flight_s < 0.0:
		return false

	# Same reference-density CLmax estimate and speed multiples used by FT-card-v5.
	_stall_speed_mps = sqrt(2.0 * mass_kg * G / (RHO * area_m2 * cl_max))
	_approach_speed_mps = 1.3 * _stall_speed_mps
	_flight_speed_mps = maxf(_v_start_mps, 1.4 * _stall_speed_mps)
	_rotation_pitch_rad = minf(deg_to_rad(8.0), _stall_start_alpha_rad - deg_to_rad(3.0))
	if not is_finite(_stall_speed_mps) or _stall_speed_mps <= 0.0 or _rotation_pitch_rad <= 0.0:
		return false

	_start_throttle = start_throttle
	_cruise_clearance_m = cruise_clearance_m
	_level_flight_s = level_flight_s
	_heading_rad = NAN # Captured from the accepted runway-start state on the first call.
	_target_altitude_m = NAN
	_aim_north_m = NAN
	_aim_east_m = NAN
	_phase_started_s = 0.0
	_flight_mode = "climb"
	_touchdown_pitch_rad = NAN
	_airborne_dwell_s = 0.0
	_context = {"start_throttle": _start_throttle}
	phase = "takeoff"
	finished = false
	_configured = true
	return true


## Return direct roll/pitch/yaw deltas and absolute throttle in [0, 1].
## clearance_m is the lowest gear reference's clearance: negative under contact,
## positive after liftoff, matching fleet_sequence.gd's contact snapshot.
func commands(state: PackedFloat64Array, clearance_m: float, elapsed_s: float) -> Dictionary:
	if not _configured or state.size() < 13 or not is_finite(clearance_m) or not is_finite(elapsed_s):
		phase = "invalid"
		return _neutral()
	if not is_finite(_heading_rad):
		_heading_rad = Pilot.euler(state)[0]
		_target_altitude_m = Pilot.altitude(state) + _cruise_clearance_m - clearance_m

	var speed_mps := Pilot.speed(state)
	match phase:
		"takeoff":
			var takeoff := _takeoff_controls(state, speed_mps, elapsed_s)
			_airborne_dwell_s = _airborne_dwell_s + PILOT_DT if clearance_m > 0.0 else 0.0
			if _airborne_dwell_s >= 0.1:
				_set_phase("flight", elapsed_s)
				_flight_mode = "climb"
				_context.erase("pitch_i")
				_context.erase("speed_i")
				return _climb_controls(state)
			return takeoff
		"flight":
			if _flight_mode == "climb":
				var climb := _climb_controls(state)
				if clearance_m >= _cruise_clearance_m:
					_target_altitude_m = Pilot.altitude(state)
					_context.erase("pitch_i")
					_context.erase("speed_i")
					_flight_mode = "level"
					_phase_started_s = elapsed_s
					return _level_controls(state)
				return climb
			if elapsed_s - _phase_started_s >= _level_flight_s:
				_begin_straight_approach(state, clearance_m, elapsed_s)
				return _approach_controls(state, clearance_m)
			return _level_controls(state)
		"approach":
			if clearance_m <= 0.0:
				return _enter_rollout(state, speed_mps, elapsed_s)
			if clearance_m <= _flare_height_m():
				_set_phase("flare", elapsed_s)
				return _flare_controls(state, clearance_m)
			return _approach_controls(state, clearance_m)
		"flare":
			if clearance_m <= 0.0:
				return _enter_rollout(state, speed_mps, elapsed_s)
			return _flare_controls(state, clearance_m)
		"rollout":
			var rollout := _rollout_controls(state, speed_mps)
			if clearance_m <= 0.0 and speed_mps < 1.0:
				finished = true
			return rollout
		_:
			phase = "invalid"
			return _neutral()


func _takeoff_controls(state: PackedFloat64Array, speed_mps: float, elapsed_s: float) -> Dictionary:
	var result := {
		"roll": Pilot.bank(state, 0.0, 1.0),
		"pitch": 0.0,
		"yaw": Pilot.ground_heading(state, _heading_rad),
		"throttle": clampf(elapsed_s / TAKEOFF_RAMP_S, 0.0, 1.0),
	}
	if speed_mps < 0.4 * _stall_speed_mps:
		result.pitch = 0.6
	elif speed_mps < 1.25 * _stall_speed_mps:
		result.pitch = Pilot.pitch(state, deg_to_rad(1.0), 1.0, _context, PILOT_DT)
	else:
		if not _context.has("rotation_t"):
			_context.rotation_t = elapsed_s
			_context.erase("pitch_i")
		result.pitch = Pilot.pitch(state, _rotation_pitch_rad, 1.0, _context, PILOT_DT)
	return result


func _climb_controls(state: PackedFloat64Array) -> Dictionary:
	var k := Pilot.schedule(state, _v_start_mps)
	return {
		"roll": Pilot.bank(state, 0.0, k),
		"pitch": Pilot.hold_speed(state, _flight_speed_mps, k, _context, PILOT_DT),
		"yaw": Pilot.ground_heading(state, _heading_rad),
		"throttle": 1.0,
	}


func _level_controls(state: PackedFloat64Array) -> Dictionary:
	var k := Pilot.schedule(state, _v_start_mps)
	return {
		"roll": Pilot.bank(state, 0.0, k),
		"pitch": Pilot.hold_altitude(state, _target_altitude_m, k, _context, PILOT_DT),
		"yaw": Pilot.ground_heading(state, _heading_rad),
		"throttle": _start_throttle,
	}


func _begin_straight_approach(state: PackedFloat64Array, clearance_m: float, elapsed_s: float) -> void:
	# Keep the runway takeoff heading and use the FT-card-v5 coupled path/speed and flare laws.
	# The target is deliberately ahead in clear terrain: a straight route cannot return to the same runway.
	var final_distance_m := maxf(clearance_m, _flare_height_m()) / tan(APPROACH_GAMMA) + AIM_PAST_FINAL_M
	var north_axis := cos(_heading_rad)
	var east_axis := sin(_heading_rad)
	_aim_north_m = state[0] + north_axis * final_distance_m
	_aim_east_m = state[1] + east_axis * final_distance_m
	_context.erase("pitch_i")
	_context.erase("speed_i")
	_context.erase("climb_i")
	_context.erase("app_pitch0")
	_set_phase("approach", elapsed_s)


func _approach_controls(state: PackedFloat64Array, clearance_m: float) -> Dictionary:
	var k := Pilot.schedule(state, _v_start_mps)
	var ahead_m := (_aim_north_m - state[0]) * cos(_heading_rad) + (_aim_east_m - state[1]) * sin(_heading_rad)
	var h_path_m := ahead_m * tan(APPROACH_GAMMA)
	return {
		"roll": Pilot.bank(state, 0.0, k),
		"pitch": Pilot.approach_pitch(state, maxf(clearance_m, 0.0), h_path_m,
			_approach_speed_mps, APPROACH_GAMMA, _stall_start_alpha_rad, k, _context),
		"yaw": Pilot.ground_heading(state, _heading_rad),
		"throttle": Pilot.approach_throttle(state, _approach_speed_mps, _start_throttle, _context),
	}


func _flare_controls(state: PackedFloat64Array, clearance_m: float) -> Dictionary:
	var k := Pilot.schedule(state, _v_start_mps)
	return {
		"roll": Pilot.bank(state, 0.0, k),
		"pitch": Pilot.flare(state, maxf(clearance_m, 0.0), _stall_start_alpha_rad, k, _context),
		"yaw": Pilot.ground_heading(state, _heading_rad),
		"throttle": 0.0,
	}


func _rollout_controls(state: PackedFloat64Array, speed_mps: float) -> Dictionary:
	var pitch_delta := Pilot.pitch(state, _touchdown_pitch_rad, 1.0, _context, PILOT_DT) \
		if speed_mps > 0.7 * _stall_speed_mps else clampf((0.7 * _stall_speed_mps - speed_mps) / 3.0, 0.0, 1.0)
	var k := Pilot.schedule(state, _v_start_mps)
	return {
		"roll": Pilot.bank(state, 0.0, k),
		"pitch": pitch_delta,
		"yaw": Pilot.ground_heading(state, _heading_rad),
		"throttle": 0.0,
	}


func _enter_rollout(state: PackedFloat64Array, speed_mps: float, elapsed_s: float) -> Dictionary:
	_touchdown_pitch_rad = Pilot.euler(state)[1]
	_set_phase("rollout", elapsed_s)
	return _rollout_controls(state, speed_mps)


func _flare_height_m() -> float:
	return clampf(_approach_speed_mps * tan(APPROACH_GAMMA), 0.5, 3.0)


func _set_phase(next_phase: String, elapsed_s: float) -> void:
	phase = next_phase
	_phase_started_s = elapsed_s


func _neutral() -> Dictionary:
	return {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0}
