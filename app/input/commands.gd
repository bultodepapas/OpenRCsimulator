# Raw input -> rate-limited commands -> surface hinge angles. Pure functions: no input, no clock, no nodes.
# Surface throws are aircraft data (controls.max_throw in app/data/aircraft/): the flight path passes the loaded
# model's throws; callers that only pose the visual model may omit them and get the data file's (loaded once).
extends RefCounted

const Spec := preload("res://spec.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const ControlSurfaces := preload("res://physics/control_surfaces.gd")
const ControlActuators := preload("res://physics/control_actuators.gd")
const Scenarios := preload("res://sim/scenarios.gd")

static var _data_throws_deg := {}


static func neutral_raw() -> Dictionary:
	return { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0 }


static func neutral_commands() -> Dictionary:
	return { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = Spec.CONTROLS.throttle_start }


## Move `value` toward `target` by at most `rate * dt`, never overshooting.
static func rate_limit(value: float, target: float, rate: float, dt: float) -> float:
	return ControlActuators.rate_limit(value, target, rate, dt)


static func step_commands(c: Dictionary, raw: Dictionary, dt: float) -> Dictionary:
	var rate: float = Spec.CONTROLS.rate
	return {
		roll = rate_limit(c.roll, raw.roll, rate, dt),
		pitch = rate_limit(c.pitch, raw.pitch, rate, dt),
		yaw = rate_limit(c.yaw, raw.yaw, rate, dt),
		throttle = clampf(c.throttle + raw.throttle * Spec.CONTROLS.throttle_rate * dt, 0.0, 1.0),
	}


## Transmitter expo on one stick position x (−1…1): y = (1 − e)·x + e·x³ keeps the ends and softens the centre
## (positive e in the JR/Spektrum sense, as rc_input.gd shapes gamepads).
static func expo(x: float, e: float) -> float:
	return (1.0 - e) * x + e * x * x * x


## D6e: dual rates and expo on the pilot's sticks, as a radio applies them before the servo: each axis is shaped by
## its expo and scaled by its travel fraction of the maximum throw. profile = controls.rates.normal of the aircraft
## data ({ aileron, elevator, rudder, aileron_expo, elevator_expo, rudder_expo }). with_expo = false applies the
## travel only (a gamepad already has its own expo). Trims are not sticks and are added afterwards by the session.
static func shape_sticks(c: Dictionary, profile: Dictionary, with_expo := true) -> Dictionary:
	return {
		roll = expo(c.roll, profile.aileron_expo if with_expo else 0.0) * profile.aileron,
		pitch = expo(c.pitch, profile.elevator_expo if with_expo else 0.0) * profile.elevator,
		yaw = expo(c.yaw, profile.rudder_expo if with_expo else 0.0) * profile.rudder,
		throttle = c.throttle,
	}


## Maximum throws in degrees { aileron, elevator, rudder } from the aircraft data file, loaded once.
static func data_throws_deg() -> Dictionary:
	if _data_throws_deg.is_empty():
		var a := AircraftData.load_file(Scenarios.AIRCRAFT)
		if not a.ok:
			push_error("commands: aircraft data invalid, surfaces stay neutral: %s" % a.errors[0])
			_data_throws_deg = { aileron = 0.0, elevator = 0.0, rudder = 0.0 } # reported once
		else:
			_data_throws_deg = a.model.controls.throw_deg
	return _data_throws_deg


## Trailing-edge deflections in degrees: positive = up (ailerons, elevator) or right (rudder).
## throws_deg: { aileron, elevator, rudder } maximum throws, plus an optional aileron_down (differential ailerons: the
## down-going aileron's maximum; absent = symmetric); empty = the data file's.
static func surface_deflections_deg(c: Dictionary, throws_deg := {}) -> Dictionary:
	var t: Dictionary = throws_deg if not throws_deg.is_empty() else data_throws_deg()
	return ControlSurfaces.surface_deflections_deg(c, t)


## One aileron's trailing-edge angle (degrees, + = up) for its own command x (+ = this aileron's trailing edge up).
static func _aileron(x: float, t: Dictionary) -> float:
	return ControlSurfaces._aileron(x, t)


## Hinge rotations in model axes (radians). Surfaces extend aft (+z) from the hinge.
## About +x, the trailing edge goes up for a negative angle; about +y, it goes right (+x) for a positive angle.
static func hinge_rotations(c: Dictionary, throws_deg := {}) -> Dictionary:
	var t: Dictionary = throws_deg if not throws_deg.is_empty() else data_throws_deg()
	return ControlSurfaces.hinge_rotations(c, t)


## Propeller speed, rev/s: 10 at the starting throttle (visual only).
static func prop_rev_per_sec(c: Dictionary) -> float:
	return Spec.CIRCLE.prop_rev_per_sec * c.throttle * 2.0
