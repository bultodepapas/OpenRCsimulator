# E3c2a: bounded experimental full-circuit test pilot for the wash-off Stik.
# Command generator for research only; never changes the flight model or session trims.
# All circuit gains, route distances, bank limits and speed/altitude targets are estimated test-pilot choices,
# tuned on the current model's traces. They are not measured aircraft properties or real-world technique.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const LandingPilot = preload("res://sim/landing_maneuver.gd")

const APPROACH_SPEED: float = 12.0 # m/s; E3c1a bounded Stik landing entry
const CIRCUIT_SPEED: float = 15.0 # m/s; estimated pilot target above the 12 m/s approach condition
const CIRCUIT_POWER_BIAS: float = 0.18 # command units; estimated feedforward over the 12 m/s trim throttle
const CIRCUIT_HEIGHT: float = 24.0 # m CG; estimated test altitude
const INITIAL_UPWIND_GATE_ALONG: float = 52.0 # m from runway center; estimated departure leg length
const DOWNWIND_TURN_START_ALONG: float = -190.0 # m from runway center; turn geometry gate
const DOWNWIND_END_HEIGHT: float = 10.0 # m CG; estimated height at base leg entry
const FINAL_START_ALONG: float = -210.0 # m; nominal final-turn exit, leaves 66 m to the E3c1a approach gate
const FINAL_GATE_ALONG: float = -144.0 # m from runway center, 94 m before the physical threshold
const FINAL_GATE_HEIGHT: float = 6.0 # m CG; E3c1a approach condition
const TURN_RADIUS: float = 60.0 # m; estimated at 15 m/s and the selected bank limit
const MAX_BANK: float = 0.35 # rad; estimated turn limit for route following
const CROSSWIND_GATE_LATERAL: float = 100.0 # m; leaves a nominal 60 m second quarter-turn
const DOWNWIND_LATERAL: float = 160.0 # m; circuit lane, estimated route geometry
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


func _init(runway: Dictionary, eastbound: bool, approach_trim: Dictionary) -> void:
	direction = 1.0 if eastbound else -1.0
	side = direction
	center_north = float(runway.get("center_north", 0.0))
	center_east = float(runway.get("center_east", 0.0))
	base_throttle = float(approach_trim.get("throttle", 0.0))
	pitch_trim = float(approach_trim.get("pitch_command", 0.0))
	cruise_throttle_available = approach_trim.has("cruise_throttle")
	cruise_throttle = float(approach_trim.get("cruise_throttle", base_throttle + CIRCUIT_POWER_BIAS))


# One call per tick. `time` is elapsed since the harness's one-second idle hold and drives the takeoff ramp.
# Returns stick deltas from unchanged FlightSession trims, except absolute throttle [0, 1].
func commands(s: PackedFloat64Array, clearance: float, time: float) -> Dictionary:
	var attitude: PackedFloat64Array = M.quat(s[6], s[7], s[8], s[9])
	var euler: PackedFloat64Array = M.q_to_euler(attitude)
	var world_velocity: PackedFloat64Array = M.q_rotate(attitude, M.v3(s[3], s[4], s[5]))
	var speed: float = M.norm(M.v3(s[3], s[4], s[5]))
	var along: float = direction * (s[1] - center_east)
	var lateral: float = side * (s[0] - center_north)
	var height: float = -s[2]
	var runway_heading: float = direction * PI / 2.0
	var crosswind_heading: float = 0.0 if side > 0.0 else PI
	var downwind_heading: float = -direction * PI / 2.0
	var base_heading: float = PI if side > 0.0 else 0.0
	var phase_heading: float = runway_heading
	var target_height: float = CIRCUIT_HEIGHT
	var throttle: float = _speed_throttle(speed, CIRCUIT_SPEED)

	if phase == "takeoff_roll":
		phase_heading = runway_heading
		throttle = clampf(time / 2.0, 0.0, 1.0)
		if speed >= ROTATION_SPEED:
			phase = "initial_climb"
	elif phase == "initial_climb":
		phase_heading = runway_heading
		target_height = CIRCUIT_HEIGHT
		throttle = _circuit_throttle(speed, height < CIRCUIT_HEIGHT - 1.0)
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
		throttle = _approach_speed_throttle(speed)
		if _heading_error(phase_heading, euler[0]) < deg_to_rad(5.0):
			phase = "base"
	elif phase == "base":
		phase_heading = base_heading
		target_height = DOWNWIND_END_HEIGHT
		throttle = _approach_speed_throttle(speed)
		if lateral <= BASE_GATE_LATERAL + 3.0:
			phase = "final_turn"
	elif phase == "final_turn":
		phase_heading = runway_heading
		target_height = DOWNWIND_END_HEIGHT
		throttle = _approach_speed_throttle(speed)
		if _heading_error(phase_heading, euler[0]) < deg_to_rad(5.0) and lateral <= 8.0:
			phase = "final_join"
	elif phase == "final_join":
		phase_heading = runway_heading
		throttle = clampf(_speed_throttle(speed, APPROACH_SPEED) - 0.12, 0.0, 1.0)
		if along >= FINAL_GATE_ALONG:
			landing_pilot = LandingPilot.new(center_north, direction > 0.0, base_throttle, pitch_trim)
			phase = "approach"
			var landing_commands: Dictionary = landing_pilot.commands(s, clearance)
			phase = str(landing_pilot.phase)
			return landing_commands
	elif phase == "approach" or phase == "flare" or phase == "rollout":
		if landing_pilot == null:
			landing_pilot = LandingPilot.new(center_north, direction > 0.0, base_throttle, pitch_trim)
		var landing_commands: Dictionary = landing_pilot.commands(s, clearance)
		phase = str(landing_pilot.phase)
		return landing_commands

	if phase == "crosswind_turn" or phase == "downwind_turn" or phase == "base_turn" or phase == "final_turn":
		if phase == "base_turn" or phase == "final_turn":
			throttle = _approach_speed_throttle(speed)
		else:
			throttle = _circuit_throttle(speed)
	elif phase == "crosswind" or phase == "downwind":
		throttle = _circuit_throttle(speed)
	var heading_error: float = wrapf(phase_heading - euler[0], -PI, PI)
	var cross_track: float = _cross_track_error(phase, along, lateral)
	var lookahead: float = maxf(20.0, speed * 3.0)
	var course_error: float = heading_error - atan(cross_track / lookahead)
	var bank_target: float = clampf(1.4 * course_error, -MAX_BANK, MAX_BANK)
	var roll_command: float = 1.8 * (bank_target - euler[2]) - 0.35 * s[10]
	var beta: float = M.atan2_(s[4], M.sqrt_(s[3] * s[3] + s[5] * s[5]))
	var coordinated_rate: float = 9.80665 * tan(euler[2]) / maxf(speed, 3.0)
	var yaw_command: float = 4.0 * beta + 0.5 * (coordinated_rate - s[12])
	if phase == "takeoff_roll":
		yaw_command = 2.5 * heading_error - 0.4 * s[12]
	elif phase == "initial_climb":
		yaw_command = 4.0 * beta + 0.25 * heading_error + 0.3 * (coordinated_rate - s[12])
	var vertical_down: float = world_velocity[2]
	var target_down: float = clampf((height - target_height) * 0.12, -1.5, 1.5)
	if phase == "final_join":
		var seconds_to_gate: float = maxf((FINAL_GATE_ALONG - along) / maxf(speed, 8.0), 0.25)
		target_down = clampf((height - FINAL_GATE_HEIGHT) / seconds_to_gate, -0.2, 0.9)
	var pitch_command: float = vertical_down - target_down - 0.5 * s[11]
	if phase == "takeoff_roll":
		pitch_command = 0.0
	elif phase == "initial_climb" and speed >= ROTATION_SPEED:
		pitch_command = clampf(3.0 * (CLIMB_PITCH - euler[1]) - 0.6 * s[11], -1.0, 1.0)
	elif phase == "initial_climb" and speed < ROTATION_SPEED:
		pitch_command = 0.0
	if phase == "final_join":
		pitch_command = vertical_down - target_down - 0.5 * s[11]
	return {
		roll = clampf(roll_command, -1.0, 1.0),
		pitch = clampf(pitch_command, -1.0, 1.0),
		yaw = clampf(yaw_command, -1.0, 1.0),
		throttle = clampf(throttle, 0.0, 1.0),
	}


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
		"crosswind_turn", "downwind_turn", "base_turn", "final_turn":
			return 0.0
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
