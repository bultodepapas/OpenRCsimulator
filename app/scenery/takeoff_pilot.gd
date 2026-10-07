## The runway scenario's scripted pilot (app/scenery/runway_scenario.gd, test_scenery_scenario.gd): 2 s at idle, then
## the throttle advanced over 2 s, heading held with the rudder, wings held level, rotation at VR and a pitch hold for
## the climb. Pure function of (time, state): the same tick always gets the same commands. Gains tuned on the Stik
## (2026-10-07: lifts off ≈ 5.5 s, climbs ≈ 14° nose-up, heading within ~1°); estimates, not a pilot model.
extends RefCounted

const M = preload("res://physics/math3d.gd")

const IDLE_S := 2.0
const THROTTLE_RAMP_S := 2.0
const VR_MS := 12.0 # rotation speed, estimated for the Stik (trimmed level flight at 15 m/s, ROADMAP D5)
const CLIMB_PITCH_DEG := 10.0


## {commands: {roll, pitch, yaw, throttle}, phase: idle | roll | rotate | climb} for state `s` (13 floats) at time t.
static func step(t: float, s: PackedFloat64Array, heading_target: float) -> Dictionary:
	var e := M.q_to_euler(s.slice(6, 10)) # [yaw, pitch, roll]
	var speed := sqrt(s[3] * s[3] + s[4] * s[4] + s[5] * s[5])
	var c := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	var phase := "idle"
	if t >= IDLE_S:
		c.throttle = clampf((t - IDLE_S) / THROTTLE_RAMP_S, 0.0, 1.0)
		var heading_err := wrapf(heading_target - e[0], -PI, PI)
		c.yaw = clampf(2.5 * heading_err - 0.4 * s[12], -1.0, 1.0) # right rudder for a heading left of target
		c.roll = clampf(-1.5 * e[2] - 0.2 * s[10], -1.0, 1.0)
		phase = "roll"
		if speed >= VR_MS:
			c.pitch = clampf(3.0 * (deg_to_rad(CLIMB_PITCH_DEG) - e[1]) - 0.6 * s[11], -1.0, 1.0)
			phase = "rotate" if s[2] > -1.0 else "climb"
	return {commands = c, phase = phase}
