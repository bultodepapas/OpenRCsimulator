# E3c1a: bounded experimental test pilot for the wash-off Stik, calm air and an east/west strip.
# This is a pilot command generator, not an autopilot mode or part of the flight force model.
# Gains/targets are estimated test-pilot choices tuned on traces; none represents aircraft data.
# Command outputs are deltas from FlightSession's solved trims, except absolute throttle [0, 1].
extends RefCounted

const M = preload("res://physics/math3d.gd")
const APPROACH_SPEED: float = 12.0 # m/s; tested on the current Stik only
const START_ALTITUDE: float = 6.0 # CG height, m
const START_BEFORE_END: float = 94.0 # m before the physical runway end
const FLARE_HEIGHT: float = 2.0 # lowest wheel clearance, m

var direction: float = 1.0
var center_north: float = 0.0
var base_throttle: float = 0.0
var pitch_trim: float = 0.0
var phase: String = "approach"


func _init(north: float, eastbound: bool, trimmed_throttle: float, trimmed_pitch: float) -> void:
	center_north = north
	direction = 1.0 if eastbound else -1.0
	base_throttle = trimmed_throttle
	pitch_trim = trimmed_pitch


# Called once per physics tick; phase is sampled pilot state, outside the integrator.
# A fresh instance starts a new maneuver. First wheel contact latches rollout through any bounce.
func commands(s: PackedFloat64Array, clearance: float) -> Dictionary:
	var attitude: PackedFloat64Array = M.quat(s[6], s[7], s[8], s[9])
	var euler: PackedFloat64Array = M.q_to_euler(attitude)
	var velocity: PackedFloat64Array = M.q_rotate(attitude, M.v3(s[3], s[4], s[5]))
	var speed: float = M.norm(M.v3(s[3], s[4], s[5]))
	var heading_error: float = wrapf(direction * PI / 2.0 - euler[0], -PI, PI)
	var lateral_error: float = direction * (s[0] - center_north)
	# Outer heading/cross-track law (rad); inner roll PD (stick per rad, stick per rad/s).
	var bank_target: float = clampf(heading_error + 0.035 * lateral_error, -0.2, 0.2)
	var roll: float = 1.5 * (bank_target - euler[2]) - 0.35 * s[10]
	var beta: float = M.atan2_(s[4], M.sqrt_(s[3] * s[3] + s[5] * s[5]))
	var yaw: float = 5.0 * beta + 0.5 * heading_error - 0.2 * s[12]
	if phase == "approach" and clearance < FLARE_HEIGHT:
		phase = "flare"
	if clearance <= 0.0:
		phase = "rollout"
	# Sink target in m/s; elevator PD uses stick per m/s and stick per rad/s.
	var target_sink: float = minf(0.8, 0.15 + 0.35 * maxf(clearance, 0.0))
	var pitch: float = (velocity[2] - target_sink) - 0.5 * s[11]
	# Speed control in approach. Engine remains running at idle throughout flare/rollout.
	var throttle: float = clampf(base_throttle + 0.08 * (APPROACH_SPEED - speed) - 0.12, 0.0, 1.0)
	if phase == "flare":
		throttle = 0.0
	if phase == "rollout":
		throttle = 0.0
		# Release the airborne elevator trim with pilot input; retain pitch-rate damping.
		pitch = -pitch_trim - 0.5 * s[11]
		yaw = 0.8 * heading_error + 0.06 * lateral_error - 0.3 * s[12]
	return {roll = clampf(roll, -1.0, 1.0), pitch = clampf(pitch, -1.0, 1.0),
		yaw = clampf(yaw, -1.0, 1.0), throttle = throttle}
