# AFC-09 candidate C5d: C5c dynamic gate with the fixed final-join throttle offset removed.
# Command generator for research only; never changes the flight model or session trims.
# The 100 m lateral lane leaves about 45 m from the measured crown location at 160 m.
# C3 reached first gear contact 87.46 m beyond its 94 m final gate, leaving the complete
# gear/hull footprint 7.384 m beyond the near runway end. C4 moves that gate to 84 m
# before the loaded runway end and raises final-join power bias by 0.04 to retain the 12 m/s
# entry condition. The E3c1a landing law and all flight physics remain unchanged. C5 reads the
# accepted FlightSession air-data/wind snapshot; its crab feed-forward is a pilot command only.
# All circuit gains, route distances, bank limits and speed/altitude targets are estimated test-pilot choices,
# tuned on the current model's traces. They are not measured aircraft properties or real-world technique.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const LandingPilot = preload("res://sim/landing_maneuver.gd")

const APPROACH_SPEED: float = 12.0 # m/s; E3c1a bounded Stik landing entry
const FINAL_JOIN_POWER_BIAS: float = 0.0 # no fixed offset; closed-loop airspeed feedback handles variable time to the predicted gate
const CIRCUIT_SPEED: float = 15.0 # m/s; estimated pilot target above the 12 m/s approach condition
const CIRCUIT_POWER_BIAS: float = 0.18 # command units; estimated feedforward over the 12 m/s trim throttle
const CIRCUIT_HEIGHT: float = 24.0 # m CG; estimated test altitude
const INITIAL_UPWIND_GATE_ALONG: float = 52.0 # m from runway center; estimated departure leg length
const DOWNWIND_TURN_START_ALONG: float = -190.0 # m from runway center; turn geometry gate
const DOWNWIND_END_HEIGHT: float = 10.0 # m CG; original E3c2a descent profile
const BASE_HEIGHT: float = 10.0 # m CG; descent begins only after the base turn clears the trees
const FINAL_START_ALONG: float = -210.0 # m; nominal final-turn exit, leaves 66 m to the E3c1a approach gate
const FINAL_GATE_BEFORE_THRESHOLD_M: float = 84.0 # m; calm reference used if wind prediction is unavailable
const FINAL_GATE_HEIGHT: float = 6.0 # m CG; E3c1a approach condition
const TARGET_TOUCHDOWN_MARGIN_M: float = 5.0 # m inside the near runway threshold
const APPROACH_TARGET_SINK_MPS: float = 0.8 # existing bounded landing law's saturated approach sink target
const TURN_RADIUS: float = 60.0 # m; estimated at 15 m/s and the selected bank limit
const MAX_BANK: float = 0.35 # rad; estimated turn limit for route following
const CROSSWIND_GATE_LATERAL: float = 100.0 # m; leaves a nominal 60 m second quarter-turn
const DOWNWIND_LATERAL: float = 100.0 # m; candidate lane clear of the measured treeline crown
const FINAL_TURN_RADIUS: float = 40.0 # m; estimated turn radius after slowing to 12 m/s
const BASE_X_ALONG: float = FINAL_START_ALONG - FINAL_TURN_RADIUS # m; base line, following both nominal turn radii
const BASE_GATE_LATERAL: float = FINAL_TURN_RADIUS # m; estimated quarter-turn completion line
const ROTATION_SPEED: float = 12.0 # m/s; estimated Stik rotation cue for this pilot
const CLIMB_PITCH: float = deg_to_rad(10.0) # estimated pilot target, follows existing scenario cue

var direction: float = 1.0
var side: float = 1.0
var center_north: float = 0.0
var center_east: float = 0.0
var base_throttle: float = 0.0
var cruise_throttle: float = 0.0
var pitch_trim: float = 0.0
var cruise_throttle_available: bool = false
var phase: String = "takeoff_roll"
var landing_pilot: RefCounted = null
var _first_turn_along: float = INITIAL_UPWIND_GATE_ALONG
var final_gate_along: float = 0.0
var runway_half_length: float = 0.0
var approach_ground_speed_estimate_mps: float = 0.0
var approach_crab_angle_rad: float = 0.0
var approach_gate_prediction_valid: bool = false


func _init(runway: Dictionary, eastbound: bool, approach_trim: Dictionary) -> void:
	direction = 1.0 if eastbound else -1.0
	side = direction
	center_north = float(runway.get("center_north", 0.0))
	center_east = float(runway.get("center_east", 0.0))
	runway_half_length = 0.5 * float(runway.get("length_east_west", 0.0))
	final_gate_along = -runway_half_length - FINAL_GATE_BEFORE_THRESHOLD_M
	base_throttle = float(approach_trim.get("throttle", 0.0))
	pitch_trim = float(approach_trim.get("pitch_command", 0.0))
	cruise_throttle_available = approach_trim.has("cruise_throttle")
	cruise_throttle = float(approach_trim.get("cruise_throttle", base_throttle + CIRCUIT_POWER_BIAS))


# One call per tick. `time` is elapsed since the harness's one-second idle hold and drives the takeoff ramp.
# Returns stick deltas from unchanged FlightSession trims, except absolute throttle [0, 1].
func commands(s: PackedFloat64Array, clearance: float, time: float) -> Dictionary:
	return commands_with_weather(s, clearance, time, {}, PackedFloat64Array())


func commands_with_weather(s: PackedFloat64Array, clearance: float, time: float,
		air_data: Dictionary, wind_ned: PackedFloat64Array) -> Dictionary:
	var attitude: PackedFloat64Array = M.quat(s[6], s[7], s[8], s[9])
	var euler: PackedFloat64Array = M.q_to_euler(attitude)
	var world_velocity: PackedFloat64Array = M.q_rotate(attitude, M.v3(s[3], s[4], s[5]))
	var ground_speed: float = M.norm(M.v3(s[3], s[4], s[5]))
	var body_air_velocity: PackedFloat64Array = air_data.get("v_air", M.v3(s[3], s[4], s[5]))
	var airspeed: float = float(air_data.get("V", M.norm(body_air_velocity)))
	if not is_finite(airspeed) or airspeed < 0.0:
		airspeed = M.norm(body_air_velocity)
	var along: float = direction * (s[1] - center_east)
	var lateral: float = side * (s[0] - center_north)
	var height: float = -s[2]
	var runway_heading: float = direction * PI / 2.0
	var crosswind_heading: float = 0.0 if side > 0.0 else PI
	var downwind_heading: float = -direction * PI / 2.0
	var base_heading: float = PI if side > 0.0 else 0.0
	var phase_heading: float = runway_heading
	var target_height: float = CIRCUIT_HEIGHT
	var throttle: float = _speed_throttle(airspeed, CIRCUIT_SPEED)

	if phase == "takeoff_roll":
		phase_heading = runway_heading
		throttle = clampf(time / 2.0, 0.0, 1.0)
		if airspeed >= ROTATION_SPEED:
			phase = "initial_climb"
	elif phase == "initial_climb":
		phase_heading = runway_heading
		target_height = CIRCUIT_HEIGHT
		throttle = _circuit_throttle(airspeed, height < CIRCUIT_HEIGHT - 1.0)
		if along >= INITIAL_UPWIND_GATE_ALONG and height >= CIRCUIT_HEIGHT - 1.0:
			_first_turn_along = along
			phase = "crosswind_turn"
	elif phase == "crosswind_turn":
		phase_heading = crosswind_heading
		if _heading_error(phase_heading, euler[0]) < deg_to_rad(5.0):
			phase = "crosswind"
	elif phase == "crosswind":
		phase_heading = crosswind_heading
		if lateral >= CROSSWIND_GATE_LATERAL - 3.0:
			phase = "downwind_turn"
	elif phase == "downwind_turn":
		phase_heading = downwind_heading
		target_height = CIRCUIT_HEIGHT
		if _heading_error(phase_heading, euler[0]) < deg_to_rad(5.0):
			phase = "downwind"
	elif phase == "downwind":
		phase_heading = downwind_heading
		var downwind_span: float = maxf(1.0, _first_turn_along - DOWNWIND_TURN_START_ALONG)
		var downwind_progress: float = clampf((_first_turn_along - along) / downwind_span, 0.0, 1.0)
		target_height = lerpf(CIRCUIT_HEIGHT, DOWNWIND_END_HEIGHT, downwind_progress)
		if along <= DOWNWIND_TURN_START_ALONG + 3.0:
			phase = "base_turn"
	elif phase == "base_turn":
		phase_heading = base_heading
		target_height = DOWNWIND_END_HEIGHT
		throttle = _approach_speed_throttle(airspeed)
		if _heading_error(phase_heading, euler[0]) < deg_to_rad(5.0):
			phase = "base"
	elif phase == "base":
		phase_heading = base_heading
		target_height = BASE_HEIGHT
		throttle = _approach_speed_throttle(airspeed)
		if lateral <= BASE_GATE_LATERAL + 3.0:
			phase = "final_turn"
	elif phase == "final_turn":
		phase_heading = runway_heading
		target_height = BASE_HEIGHT
		throttle = _approach_speed_throttle(airspeed)
		if _heading_error(phase_heading, euler[0]) < deg_to_rad(5.0) and lateral <= 8.0:
			var gate: Dictionary = approach_gate_for_weather(runway_half_length, direction, wind_ned)
			if gate.get("ok", false):
				final_gate_along = float(gate.gate_along_m)
				approach_ground_speed_estimate_mps = float(gate.ground_speed_mps)
				approach_crab_angle_rad = float(gate.crab_angle_rad)
				approach_gate_prediction_valid = true
			phase = "final_join"
	elif phase == "final_join":
		phase_heading = runway_heading
		throttle = clampf(_speed_throttle(airspeed, APPROACH_SPEED) + FINAL_JOIN_POWER_BIAS, 0.0, 1.0)
		if along >= final_gate_along:
			landing_pilot = LandingPilot.new(center_north, direction > 0.0, base_throttle, pitch_trim)
			phase = "approach"
			var landing_commands: Dictionary = landing_pilot.commands(s, clearance)
			phase = str(landing_pilot.phase)
			return _landing_weather_commands(landing_commands, phase, clearance, airspeed, wind_ned)
	elif phase == "approach" or phase == "flare" or phase == "rollout":
		if landing_pilot == null:
			landing_pilot = LandingPilot.new(center_north, direction > 0.0, base_throttle, pitch_trim)
		var landing_commands: Dictionary = landing_pilot.commands(s, clearance)
		phase = str(landing_pilot.phase)
		return _landing_weather_commands(landing_commands, phase, clearance, airspeed, wind_ned)

	if phase == "crosswind_turn" or phase == "downwind_turn" or phase == "base_turn" or phase == "final_turn":
		if phase == "base_turn" or phase == "final_turn":
			throttle = _approach_speed_throttle(airspeed)
		else:
			throttle = _circuit_throttle(airspeed)
	elif phase == "crosswind" or phase == "downwind":
		throttle = _circuit_throttle(airspeed)
	var cross_track: float = _cross_track_error(phase, along, lateral)
	var lookahead: float = maxf(20.0, ground_speed * 3.0)
	var track_heading: float = wrapf(phase_heading - atan(cross_track / lookahead), -PI, PI)
	var commanded_heading: float = track_heading
	if airspeed >= 6.0:
		var correction: Dictionary = wind_correction(track_heading, wind_ned, airspeed)
		if correction.get("ok", false):
			commanded_heading = float(correction.heading_rad)
	var heading_error: float = wrapf(commanded_heading - euler[0], -PI, PI)
	var bank_target: float = clampf(1.4 * heading_error, -MAX_BANK, MAX_BANK)
	var roll_command: float = 1.8 * (bank_target - euler[2]) - 0.35 * s[10]
	var beta: float = M.atan2_(body_air_velocity[1], M.sqrt_(body_air_velocity[0] * body_air_velocity[0] + body_air_velocity[2] * body_air_velocity[2]))
	var coordinated_rate: float = 9.80665 * tan(euler[2]) / maxf(airspeed, 3.0)
	var yaw_command: float = 4.0 * beta + 0.5 * (coordinated_rate - s[12])
	if phase == "takeoff_roll":
		yaw_command = 2.5 * heading_error - 0.4 * s[12]
	elif phase == "initial_climb":
		yaw_command = 4.0 * beta + 0.25 * heading_error + 0.3 * (coordinated_rate - s[12])
	var vertical_down: float = world_velocity[2]
	var target_down: float = clampf((height - target_height) * 0.12, -1.5, 1.5)
	if phase == "final_join":
		var ground_speed_along: float = direction * world_velocity[1]
		var seconds_to_gate: float = maxf((final_gate_along - along) / maxf(ground_speed_along, 8.0), 0.25)
		target_down = clampf((height - FINAL_GATE_HEIGHT) / seconds_to_gate, -0.2, 0.9)
	var pitch_command: float = vertical_down - target_down - 0.5 * s[11]
	if phase == "takeoff_roll":
		pitch_command = 0.0
	elif phase == "initial_climb" and airspeed >= ROTATION_SPEED:
		pitch_command = clampf(3.0 * (CLIMB_PITCH - euler[1]) - 0.6 * s[11], -1.0, 1.0)
	elif phase == "initial_climb" and airspeed < ROTATION_SPEED:
		pitch_command = 0.0
	if phase == "final_join":
		pitch_command = vertical_down - target_down - 0.5 * s[11]
	return {
		roll = clampf(roll_command, -1.0, 1.0),
		pitch = clampf(pitch_command, -1.0, 1.0),
		yaw = clampf(yaw_command, -1.0, 1.0),
		throttle = clampf(throttle, 0.0, 1.0),
	}


static func wind_correction(track_heading: float, wind_ned: PackedFloat64Array, true_airspeed: float) -> Dictionary:
	if not is_finite(track_heading) or not is_finite(true_airspeed) or true_airspeed <= 0.0 \
			or wind_ned.size() != 3:
		return {ok = false, reason = "invalid wind-correction inputs"}
	for component: float in wind_ned:
		if not is_finite(component):
			return {ok = false, reason = "nonfinite wind component"}
	var right_north: float = -sin(track_heading)
	var right_east: float = cos(track_heading)
	var crosswind_mps: float = right_north * wind_ned[0] + right_east * wind_ned[1]
	if absf(crosswind_mps) >= true_airspeed:
		return {ok = false, reason = "crosswind is not trackable at current airspeed", crosswind_mps = crosswind_mps}
	var forward_airspeed: float = sqrt(true_airspeed * true_airspeed - crosswind_mps * crosswind_mps)
	var heading_offset: float = atan2(-crosswind_mps, forward_airspeed)
	return {ok = true, heading_rad = wrapf(track_heading + heading_offset, -PI, PI),
		crosswind_mps = crosswind_mps, correction_rad = heading_offset}


static func approach_gate_for_weather(half_length_m: float, runway_direction: float,
		wind_ned: PackedFloat64Array) -> Dictionary:
	if not is_finite(half_length_m) or half_length_m <= 0.0 \
			or (absf(runway_direction - 1.0) > 1.0e-9 and absf(runway_direction + 1.0) > 1.0e-9):
		return {ok = false, reason = "invalid runway geometry or direction"}
	var runway_heading: float = runway_direction * PI / 2.0
	var correction: Dictionary = wind_correction(runway_heading, wind_ned, APPROACH_SPEED)
	if not correction.get("ok", false):
		return {ok = false, reason = str(correction.get("reason", "untrackable approach wind"))}
	var forward_north: float = cos(runway_heading)
	var forward_east: float = sin(runway_heading)
	var wind_along_mps: float = forward_north * wind_ned[0] + forward_east * wind_ned[1]
	var crosswind_mps: float = float(correction.crosswind_mps)
	var airspeed_along_mps: float = sqrt(APPROACH_SPEED * APPROACH_SPEED - crosswind_mps * crosswind_mps)
	var ground_speed_mps: float = airspeed_along_mps + wind_along_mps
	if not is_finite(ground_speed_mps) or ground_speed_mps < 4.0:
		return {ok = false, reason = "approach ground speed below the research predictor floor"}
	var predicted_time_s: float = FINAL_GATE_HEIGHT / APPROACH_TARGET_SINK_MPS
	var target_touchdown_along_m: float = -half_length_m + TARGET_TOUCHDOWN_MARGIN_M
	var gate_along_m: float = target_touchdown_along_m - ground_speed_mps * predicted_time_s
	return {ok = true, gate_along_m = gate_along_m,
		gate_before_threshold_m = -half_length_m - gate_along_m,
		ground_speed_mps = ground_speed_mps, predicted_time_s = predicted_time_s,
		wind_along_mps = wind_along_mps, crosswind_mps = crosswind_mps,
		crab_angle_rad = float(correction.correction_rad),
		target_touchdown_along_m = target_touchdown_along_m}


func research_diagnostics() -> Dictionary:
	return {candidate_id = "AFC09-C5d", approach_gate_prediction_valid = approach_gate_prediction_valid,
		approach_gate_along_m = final_gate_along,
		approach_gate_before_threshold_m = -runway_half_length - final_gate_along,
		approach_ground_speed_estimate_mps = approach_ground_speed_estimate_mps,
		approach_crab_angle_rad = approach_crab_angle_rad,
		target_touchdown_margin_m = TARGET_TOUCHDOWN_MARGIN_M}


func _landing_weather_commands(commands: Dictionary, landing_phase: String, clearance: float,
		airspeed: float, wind_ned: PackedFloat64Array) -> Dictionary:
	var output: Dictionary = commands.duplicate(true)
	var runway_heading: float = direction * PI / 2.0
	var crab_offset: float = 0.0
	if airspeed >= 6.0:
		var correction: Dictionary = wind_correction(runway_heading, wind_ned, airspeed)
		if correction.get("ok", false):
			crab_offset = wrapf(float(correction.heading_rad) - runway_heading, -PI, PI)
	var crab_weight: float = 1.0 if landing_phase == "approach" else 0.0
	if landing_phase == "flare":
		crab_weight = clampf(clearance / LandingPilot.FLARE_HEIGHT, 0.0, 1.0)
	var heading_bias: float = crab_offset * crab_weight
	output.roll = clampf(float(output.get("roll", 0.0)) + 1.5 * heading_bias, -1.0, 1.0)
	output.yaw = clampf(float(output.get("yaw", 0.0)) + 0.5 * heading_bias, -1.0, 1.0)
	if landing_phase == "approach":
		output.throttle = clampf(base_throttle + 0.08 * (APPROACH_SPEED - airspeed) - 0.12, 0.0, 1.0)
	return output


func _speed_throttle(speed: float, target: float) -> float:
	return clampf(base_throttle + 0.08 * (target - speed), 0.0, 1.0)


func _circuit_throttle(speed: float, climb_bias: bool = false) -> float:
	var feedforward: float = cruise_throttle if cruise_throttle_available else base_throttle + CIRCUIT_POWER_BIAS
	var climb: float = 0.08 if cruise_throttle_available else 0.12
	return clampf(feedforward + 0.08 * (CIRCUIT_SPEED - speed) + (climb if climb_bias else 0.0), 0.0, 1.0)


func _approach_speed_throttle(speed: float) -> float:
	return _speed_throttle(speed, APPROACH_SPEED)


func _heading_error(target: float, actual: float) -> float:
	return absf(wrapf(target - actual, -PI, PI))


func _cross_track_error(current_phase: String, along: float, lateral: float) -> float:
	match current_phase:
		"crosswind_turn", "downwind_turn", "base_turn":
			return 0.0
		"final_turn":
			# Keep closing toward the strip centerline while rotating onto the runway heading.
			return -lateral
		"crosswind":
			# Positive is right of the crosswind course for either mirrored circuit direction.
			return along - (_first_turn_along + TURN_RADIUS)
		"downwind":
			# The circuit's positive side is right of the downwind course in both headings.
			return lateral - DOWNWIND_LATERAL
		"base":
			# Along error is positive on the course's left; invert it for the shared right-positive correction.
			return BASE_X_ALONG - along
		"final_join":
			# The circuit-side offset is left of either mirrored final and must command a right turn.
			return -lateral
		_:
			# A runway-aligned course uses the same right-of-course sign as the final line.
			return -lateral
