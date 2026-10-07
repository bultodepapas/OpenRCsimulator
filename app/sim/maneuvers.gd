# Scripted maneuvers (D8a), flown through the real session loop (commands → servos → aero/propulsion → RK4).
# The handling checks measure them; golden flights record and replay them. 64-bit floats only (guarded).
extends RefCounted

const Recorder := preload("res://sim/recorder.gd")
const M := preload("res://physics/math3d.gd")

## Slow flight (D9a): idle throttle, elevator holding the start altitude (PD on altitude error and climb rate, plus
## the pilot's own pitch-rate damping kq), so the airplane slows down at constant height until the wing can no longer
## hold it. D11g added kq: with the Stik's own (lower) static pitch damping the PD loop alone over-controlled, α
## overshot 2° and the wing stalled dynamically at 9.99 m/s; with kq the pre- and post-D11g physics both stall at
## 9.68 m/s (and the linear oracle holds to 8.21/8.19), so the measurement is of the wing, not of the loop.
## Flown from 150 m (E1): after the stall the airplane falls for the rest of the 10 s and used to sink below the
## ground, where nothing acted on it; with gear contacts the ground is real, so the maneuver starts high enough.
const SLOW_FLIGHT := { altitude = 150.0, kp = 1.5, kd = 1.5, kq = 0.5 } # m; stick per m; stick per m/s (tuned on traces, 2026-10-05); stick per rad/s (D11g)

## Rudder gain of the "coordinated" maneuvers: yaw command per radian of sideslip (holds β ≈ 0, like a pilot's feet).
const COORDINATION_GAIN := 10.0

## name → { mode: "level"/"glide", speed (m/s), duration (s), sticks(t, state) -> { roll, pitch, yaw, throttle_delta } },
## plus an optional altitude (m above ground, default the trimmed start's 30 m).
## Sticks are pilot inputs added to the trims; throttle_delta is added to the trimmed throttle. glide = engine stopped.
static func all() -> Dictionary:
	return {
		hold_15 = { mode = "level", speed = 15.0, duration = 5.0, sticks = func(_t: float, _s: PackedFloat64Array) -> Dictionary: return _hands_off() },
		roll_15 = { mode = "level", speed = 15.0, duration = 2.5, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary: return _pulse(t, 0.25, 1.25, { roll = 1.0 }) },
		roll_20 = { mode = "level", speed = 20.0, duration = 2.5, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary: return _pulse(t, 0.25, 1.25, { roll = 1.0 }) },
		roll_15_coordinated = { mode = "level", speed = 15.0, duration = 2.5, sticks = func(t: float, s: PackedFloat64Array) -> Dictionary: return _coordinated(_pulse(t, 0.25, 1.25, { roll = 1.0 }), s) },
		roll_20_coordinated = { mode = "level", speed = 20.0, duration = 2.5, sticks = func(t: float, s: PackedFloat64Array) -> Dictionary: return _coordinated(_pulse(t, 0.25, 1.25, { roll = 1.0 }), s) },
		glide_15 = { mode = "glide", speed = 15.0, duration = 5.0, sticks = func(_t: float, _s: PackedFloat64Array) -> Dictionary: return _hands_off() },
		pull_throttle = { mode = "level", speed = 15.0, duration = 3.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary: return _pulse(t, 0.25, 1.75, { pitch = 0.5, throttle_delta = 0.7 }) },
		slow_flight = { mode = "level", speed = 12.0, altitude = SLOW_FLIGHT.altitude, duration = 10.0, sticks = func(_t: float, s: PackedFloat64Array) -> Dictionary: return _altitude_hold(s) },
		symmetric_stall = { mode = "glide", speed = 12.0, duration = 4.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary: return _pulse(t, 0.25, 4.0, { pitch = 1.0 }) },
		# Power-off spin entry (full up elevator + full right rudder), then the standard recovery (opposite rudder,
		# stick forward) held until the rotation stops (0.9 s), then neutral. From 150 m: the spin loses ~80 m in 8 s
		# and used to continue below the ground (E1 made the ground real).
		spin_right = { mode = "level", speed = 12.0, altitude = 150.0, duration = 8.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
			var c := _pulse(t, 0.25, 4.0, { pitch = 1.0, yaw = 1.0 })
			if t >= 4.0 and t < 4.9:
				c = { roll = 0.0, pitch = -0.5, yaw = -1.0, throttle_delta = 0.0 }
			c.throttle_delta = -1.0
			return c },
		rudder_doublet = { mode = "level", speed = 15.0, duration = 3.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
			return _pulse(t, 0.5, 1.0, { yaw = 1.0 }) if t < 1.0 else _pulse(t, 1.0, 1.5, { yaw = -1.0 }) },
	}


static func _altitude_hold(s: PackedFloat64Array, gains := SLOW_FLIGHT) -> Dictionary:
	var down_rate := M.q_rotate(M.quat(s[6], s[7], s[8], s[9]), M.v3(s[3], s[4], s[5]))[2]
	var error: float = gains.altitude + s[2] # altitude lost (state[2] = down, start at −30)
	var out := _hands_off()
	out.pitch = clampf(gains.kp * error + gains.kd * down_rate - gains.kq * s[11], -1.0, 1.0) # s[11] = pitch rate q
	out.throttle_delta = -1.0 # idle
	return out


## Adds rudder against sideslip: β > 0 (wind from the right) → right rudder.
static func _coordinated(sticks: Dictionary, s: PackedFloat64Array) -> Dictionary:
	var beta := M.atan2_(s[4], M.sqrt_(s[3] * s[3] + s[5] * s[5])) # body velocity [u, v, w] at state[3..5]
	sticks.yaw = clampf(sticks.yaw + COORDINATION_GAIN * beta, -1.0, 1.0)
	return sticks


static func _hands_off() -> Dictionary:
	return { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle_delta = 0.0 }


static func _pulse(t: float, t0: float, t1: float, sticks: Dictionary) -> Dictionary:
	var out := _hands_off()
	if t >= t0 and t < t1:
		out.merge(sticks, true)
	return out


## Trims the session for the maneuver, flies it tick by tick and returns the recorded Trace (row 0 = the start).
## The session must be set up and inside the tree; its own input sampling is switched off.
static func fly(session: Node, m: Dictionary) -> RefCounted:
	session.input_enabled = false
	var t: Dictionary = session.trim_at(m.speed, m.mode)
	assert(t.ok, "maneuver trim failed: %s" % t.message)
	if m.has("altitude"):
		session.set_start_altitude(m.altitude) # optional start height (m): room for loops and spins
	session.reset()
	var sim: Node = session.sim
	var rec := Recorder.new(sim)
	rec.start({ maneuver = m })
	for i in roundi(m.duration / sim.dt()):
		var s: Dictionary = m.sticks.call(sim.time(), sim.state)
		session.commands = { roll = s.roll, pitch = s.pitch, yaw = s.yaw, throttle = clampf(session.start.throttle + s.throttle_delta, 0.0, 1.0) }
		sim.inputs = session._inputs()
		sim.step()
	rec.detach()
	return rec.trace
