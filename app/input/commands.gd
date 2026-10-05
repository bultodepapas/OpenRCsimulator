# Raw input -> rate-limited commands -> surface hinge angles. Pure functions: no input, no clock, no nodes.
extends RefCounted

const Spec := preload("res://spec.gd")


static func neutral_raw() -> Dictionary:
	return { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0 }


static func neutral_commands() -> Dictionary:
	return { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = Spec.CONTROLS.throttle_start }


## Move `value` toward `target` by at most `rate * dt`, never overshooting.
static func rate_limit(value: float, target: float, rate: float, dt: float) -> float:
	var max_step := rate * dt
	return value + clampf(target - value, -max_step, max_step)


static func step_commands(c: Dictionary, raw: Dictionary, dt: float) -> Dictionary:
	var rate: float = Spec.CONTROLS.rate
	return {
		roll = rate_limit(c.roll, raw.roll, rate, dt),
		pitch = rate_limit(c.pitch, raw.pitch, rate, dt),
		yaw = rate_limit(c.yaw, raw.yaw, rate, dt),
		throttle = clampf(c.throttle + raw.throttle * Spec.CONTROLS.throttle_rate * dt, 0.0, 1.0),
	}


## Trailing-edge deflections in degrees: positive = up (ailerons, elevator) or right (rudder).
static func surface_deflections_deg(c: Dictionary) -> Dictionary:
	var t: Dictionary = Spec.CONTROLS.max_throw_deg
	return {
		aileron_right = c.roll * t.aileron,
		aileron_left = -c.roll * t.aileron,
		elevator = c.pitch * t.elevator,
		rudder = c.yaw * t.rudder,
	}


## Hinge rotations in model axes (radians). Surfaces extend aft (+z) from the hinge.
## About +x, the trailing edge goes up for a negative angle; about +y, it goes right (+x) for a positive angle.
static func hinge_rotations(c: Dictionary) -> Dictionary:
	var d := surface_deflections_deg(c)
	return {
		aileron_right = { x = -deg_to_rad(d.aileron_right), y = 0.0 },
		aileron_left = { x = -deg_to_rad(d.aileron_left), y = 0.0 },
		elevator = { x = -deg_to_rad(d.elevator), y = 0.0 },
		rudder = { x = 0.0, y = deg_to_rad(d.rudder) },
	}


## Propeller speed, rev/s: 10 at the starting throttle (visual only).
static func prop_rev_per_sec(c: Dictionary) -> float:
	return Spec.CIRCLE.prop_rev_per_sec * c.throttle * 2.0
