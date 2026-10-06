# Physics cost per 240 Hz tick of the real flight session (ROADMAP rule 7: every aero step reports µs/tick).
# NOT a test (timing depends on the machine): run it before and after a physics change.
# Run: godot --headless --path . --script res://tests/bench_physics.gd [-- --aircraft=<catalog id>]
# H1: after the headline (trimmed flight, unchanged since D5) it prints a per-component table, in µs per call, for
# three regimes: trimmed (oracle only), stalled (α 15°: local surfaces) and on the ground (three wheels compressed),
# plus whole ticks in the stalled regime. A tick costs ≈ 5 load calls (one before RK4, four inside) + 4 derivatives.
# The HUD's perf line (F3) already shows the live tick cost (`Simulation.step_usec`), so no custom monitor is added.
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Commands := preload("res://input/commands.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Ground := preload("res://physics/ground_contact.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const TICKS := 2400 # 10 s of flight
const CALLS := 4000 # per component and regime


func _initialize() -> void:
	var session := FlightSession.new()
	session.setup(_aircraft_path())
	root.add_child(session)
	session.input_enabled = false
	session.reset()
	print("physics: %.1f µs per tick (best of 3 × %d ticks; budget 500 µs on the owner's slowest machine)" % [_ticks(session, PackedFloat64Array()), TICKS])
	var trimmed: PackedFloat64Array = session.sim.state.duplicate()
	var regimes := {
		trimmed = trimmed,
		stalled = _with_alpha(trimmed, deg_to_rad(15.0)),
		ground = _on_ground(trimmed, session.aircraft.model.landing_gear),
	}
	var rows := PackedStringArray()
	for regime in regimes:
		var s: PackedFloat64Array = regimes[regime]
		rows.append("| %s | %s |" % [regime, " | ".join(_components(session, s))])
	print("\n| regime (µs per call) | Air.compute | Aero.loads | Propulsion.loads | Ground.loads | Dynamics.loads | session loads | RB.derivative | RK4 overhead |")
	print("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for row in rows:
		print(row)
	print("\nstalled flight: %.1f µs per tick (best of 3 × %d ticks from α 15°)" % [_ticks(session, regimes.stalled), TICKS])
	quit()


func _aircraft_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--aircraft="):
			return AircraftCatalog.entry(arg.trim_prefix("--aircraft=")).get("data", FlightSession.Scenarios.AIRCRAFT)
	return FlightSession.Scenarios.AIRCRAFT


## Best of three runs of TICKS whole steps, from the reset state or from `start` when given.
func _ticks(session: Node, start: PackedFloat64Array) -> float:
	var best := 1e30
	for run in 3:
		session.reset()
		if not start.is_empty():
			session.sim.state = start.duplicate()
			session.sim.previous = start.duplicate()
		var t0 := Time.get_ticks_usec()
		for i in TICKS:
			session.sim.step()
		best = minf(best, float(Time.get_ticks_usec() - t0) / TICKS)
	return best


## The same speed and attitude, with the air-relative velocity turned to angle of attack `alpha`.
func _with_alpha(s: PackedFloat64Array, alpha: float) -> PackedFloat64Array:
	var out := s.duplicate()
	var v := sqrt(s[RB.VEL] * s[RB.VEL] + s[RB.VEL + 1] * s[RB.VEL + 1] + s[RB.VEL + 2] * s[RB.VEL + 2])
	out[RB.VEL] = v * cos(alpha)
	out[RB.VEL + 1] = 0.0
	out[RB.VEL + 2] = v * sin(alpha)
	return out


## Wings level, slow, at the height where the lowest wheel is compressed 1 cm (or unchanged without gear).
func _on_ground(s: PackedFloat64Array, gear: Dictionary) -> PackedFloat64Array:
	var out := s.duplicate()
	out[RB.VEL] = 2.0
	out[RB.VEL + 1] = 0.0
	out[RB.VEL + 2] = 0.0
	for i in 3:
		out[RB.RATE + i] = 0.0
	var q := M.q_from_euler(0.0, 0.0, 0.0)
	for i in 4:
		out[RB.ATT + i] = q[i]
	if gear.is_empty():
		return out
	out[RB.POS + 2] = 0.0
	var c := Ground.compressions(out, gear)
	var lowest := -1e30
	for x in c:
		lowest = maxf(lowest, x)
	out[RB.POS + 2] = -lowest + 0.01
	return out


## µs per call of each component at state `s`, formatted.
func _components(session: Node, s: PackedFloat64Array) -> PackedStringArray:
	var model: Dictionary = session.aircraft.model
	var a: PackedFloat64Array = session.sim.aux
	var rho := Air.RHO_SEA_LEVEL
	var wind := PackedFloat64Array([0.0, 0.0, 0.0])
	var surfaces := Commands.surface_deflections_deg({ roll = a[1], pitch = a[2], yaw = a[3] }, session.throws_deg())
	var d := Aero.deflections_from_surfaces(surfaces)
	var air := Air.compute(s, wind, rho)
	var loads: PackedFloat64Array = session._loads(s, 0.0)
	var h := Dynamics.rotor_momentum(model, a[0])
	var inv := RB.inertia_inverse(model.inertia)
	var force := M.v3(loads[0], loads[1], loads[2])
	var moment := M.v3(loads[3], loads[4], loads[5])
	var f := func(x: PackedFloat64Array) -> PackedFloat64Array: return RB.derivative(x, model.mass_kg, model.inertia, inv, force, moment, 9.80665, h)
	var zero := func(_x: PackedFloat64Array) -> PackedFloat64Array: return PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	var out := PackedStringArray()
	out.append(_us(func() -> void: Air.compute(s, wind, rho)))
	out.append(_us(func() -> void: Aero.loads(s, air, d, model, rho)))
	out.append(_us(func() -> void: Propulsion.loads(air.v_air, a[0], model.propulsion, rho)))
	out.append(_us(func() -> void: Ground.loads(s, model.landing_gear, a[3], session.ground_surfaces)))
	out.append(_us(func() -> void: Dynamics.loads(s, model, d, a[0], rho, wind)))
	out.append(_us(func() -> void: session._loads(s, 0.0)))
	out.append(_us(func() -> void: f.call(s)))
	out.append(_us(func() -> void: RK.rk4_step(s, 1.0 / 240.0, zero)))
	return out


## Best of three: µs per call of `body`, minus nothing (a bare lambda call costs well under 1 µs here).
func _us(body: Callable) -> String:
	var best := 1e30
	for run in 3:
		var t0 := Time.get_ticks_usec()
		for i in CALLS:
			body.call()
		best = minf(best, float(Time.get_ticks_usec() - t0) / CALLS)
	return "%.1f" % best
