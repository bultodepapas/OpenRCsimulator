# E1: landing gear as spring-damper contacts. Hand-computed loads and signs; a drop test that never gains energy
# and settles on its wheels; the same drop at h and h/2 agrees; the Stik lands from a low drop and breaks its gear
# from a high one; nothing changes in the air.
# Run: godot --headless --path . --script res://tests/test_ground_contact.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const Ground := preload("res://physics/ground_contact.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const FlightSession := preload("res://sim/flight_session.gd")

const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const G := 9.80665

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _level(alt: float, vel_down := 0.0, pitch := 0.0, roll := 0.0) -> PackedFloat64Array:
	var q := M.q_from_euler(0.0, pitch, roll)
	return RB.make_state(M.v3(0, 0, -alt), M.q_rotate(M.q_conj(q), M.v3(0, 0, vel_down)), q, M.v3(0, 0, 0))


func _one_contact(k: float, c: float) -> Dictionary:
	return { contacts = [{ name = "test", position = M.v3(0.3, 0.0, 0.2), stiffness = k, damping = c, max_compression = 0.5 }], reach = 0.5 }


## Mechanical energy of a bare rigid body on the gear: kinetic + m·g·h + springs.
func _energy(s: PackedFloat64Array, mass: float, j: PackedFloat64Array, gear: Dictionary) -> float:
	var v := M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2])
	var w := M.v3(s[RB.RATE], s[RB.RATE + 1], s[RB.RATE + 2])
	return 0.5 * mass * M.dot(v, v) + 0.5 * M.dot(w, RB.inertia_mul(j, w)) - mass * G * s[RB.POS + 2] + Ground.spring_energy(s, gear)


## Drops the Stik (gear only, no air) from `alt` for `seconds`; returns { state, max_gain (J per tick), ticks }.
## normal_only: drop the E2 tyre friction (μ = 0), leaving the vertical spring-dampers alone.
func _drop(model: Dictionary, alt: float, seconds: float, normal_only := false) -> Dictionary:
	var gear: Dictionary = model.landing_gear
	if normal_only:
		gear = gear.duplicate()
		gear.side_friction = 0.0
	var sim: Node = Sim.new()
	sim.mass = model.mass_kg
	sim.inertia = model.inertia.duplicate()
	sim.loads = func(s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		var g := Ground.loads(s, gear)
		return g if not g.is_empty() else PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	sim.reset(_level(alt))
	var ticks := roundi(seconds / sim.dt())
	var e_prev := _energy(sim.state, sim.mass, sim.inertia, gear)
	var max_gain := -INF
	for i in ticks:
		sim.step()
		var e := _energy(sim.state, sim.mass, sim.inertia, gear)
		max_gain = maxf(max_gain, e - e_prev)
		e_prev = e
	var out := { state = sim.state.duplicate(), max_gain = max_gain, ticks = ticks, fault = sim.fault_reason }
	sim.free()
	return out


func _initialize() -> void:
	var r := AD.load_file(PATH)
	_check("Stik data loads with landing gear", r.ok and not r.model.landing_gear.is_empty(), str(r.errors))
	if not r.ok:
		quit(1)
		return
	var model: Dictionary = r.model
	var gear: Dictionary = model.landing_gear

	# Hand-computed: one contact 0.3 m ahead and 0.2 m below the CG, k 1000 N/m, c 10 N·s/m, level at 0.1 m altitude
	# → compression 0.1 m; sinking at 1 m/s → F_up = 100 + 10 = 110 N, pitch moment = 0.3 × 110 (nose up).
	var one := _one_contact(1000.0, 10.0)
	var l := Ground.loads(_level(0.1, 1.0), one)
	_check("one contact: F_z = −110 N exactly", l.size() == 6 and l[2] == -110.0 and l[0] == 0.0 and l[1] == 0.0, str(l))
	_check("one contact: nose-up moment 33 N·m, no roll or yaw", l.size() == 6 and absf(l[4] - 33.0) < 1e-12 and l[3] == 0.0 and l[5] == 0.0, str(l))
	_check("rebounding faster than the spring pushes: no force (a damper never pulls the wheel down)", Ground.loads(_level(0.1, -20.0), one).is_empty())
	_check("in the air: nothing (an empty array, not zeros)", Ground.loads(_level(1.0), one).is_empty() and Ground.loads(_level(0.21), one).is_empty())
	_check("compression reported ≤ 0 in the air, > 0 on the ground", Ground.compressions(_level(1.0), one)[0] < 0.0 and absf(Ground.compressions(_level(0.1), one)[0] - 0.1) < 1e-12)
	_check("collapse past the travel", not Ground.collapsed(_level(0.1), one) and Ground.collapsed(_level(-0.4), one))

	# Signs with the Stik's gear: a right roll loads the right wheel more → restoring (left-rolling) moment; a
	# nose-down pitch with only the nose wheel touching → nose-up moment.
	var rolled := Ground.loads(_level(0.24, 0.0, 0.0, 0.1), gear)
	_check("rolled right on the ground: rolling moment restores (Mx < 0)", rolled.size() == 6 and rolled[3] < 0.0, str(rolled))
	var nosed := Ground.loads(_level(0.30, 0.0, -0.2), gear)
	var c := Ground.compressions(_level(0.30, 0.0, -0.2), gear)
	_check("nose-down on the nose wheel only: nose-up moment (My > 0)", c[0] < 0.0 and c[1] < 0.0 and c[2] > 0.0 and nosed.size() == 6 and nosed[4] > 0.0, str(nosed))

	# Drop test (gear only, no air): from 0.5 m, level, at rest. Energy never grows; it settles on its wheels
	# carrying its weight, sagging about the loader's static_sag.
	var d := _drop(model, 0.5, 6.0)
	_check("drop test: no simulation fault", d.fault == "", d.fault)
	_check("drop test: mechanical energy never gains more than 1e-6 J in a tick", d.max_gain < 1e-6, "max gain %s J" % d.max_gain)
	var s: PackedFloat64Array = d.state
	var speed := sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)
	var rate := sqrt(s[RB.RATE] ** 2 + s[RB.RATE + 1] ** 2 + s[RB.RATE + 2] ** 2)
	_check("drop test: at rest after 6 s", speed < 1e-4 and rate < 1e-4, "%s m/s, %s rad/s" % [speed, rate])
	var rest := Ground.loads(s, gear)
	var rest_force := sqrt(rest[0] ** 2 + rest[1] ** 2 + rest[2] ** 2) if rest.size() == 6 else 0.0
	_check("drop test: the wheels carry the weight (|F| = m·g, no net moment)", absf(rest_force - model.mass_kg * G) < 1e-3 and rest.size() == 6 and absf(rest[4]) < 1e-3 and absf(rest[3]) < 1e-3, str(rest))
	var comp := Ground.compressions(s, gear)
	var sag: float = (comp[0] + comp[1] + comp[2]) / 3.0
	_check("drop test: all three wheels compressed, mean sag within 30 %% of static_sag %.3f m" % gear.static_sag,
		comp[0] > 0.0 and comp[1] > 0.0 and comp[2] > 0.0 and absf(sag - gear.static_sag) < 0.3 * gear.static_sag, str(comp))
	var e := M.q_to_euler(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]))
	_check("drop test: rests within 1° of level (the nose leg carries its 27 % share)", absf(e[1]) < deg_to_rad(1.0) and absf(e[2]) < deg_to_rad(1.0), "pitch %.2f° roll %.2f°" % [rad_to_deg(e[1]), rad_to_deg(e[2])])

	# The same drop at h/2 (480 Hz) during the bounce phase (1 s) agrees with h: the tick resolves the gear.
	var h := _drop(model, 0.5, 1.0)
	var saved := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 480
	var h2 := _drop(model, 0.5, 1.0)
	Engine.physics_ticks_per_second = saved
	var dz: float = absf(h.state[RB.POS + 2] - h2.state[RB.POS + 2])
	var dq := 0.0
	for i in 4:
		dq = maxf(dq, absf(h.state[RB.ATT + i] - h2.state[RB.ATT + i]))
	var dv: float = absf(h.state[RB.VEL + 2] - h2.state[RB.VEL + 2])
	_check("h vs h/2 after 1 s of bouncing: altitude within 1 mm, attitude within 1e-3, sink within 1 cm/s", dz < 1e-3 and dq < 1e-3 and dv < 1e-2, "Δz %s m, Δq %s, Δw %s m/s (h2 ticks %d)" % [dz, dq, dv, h2.ticks])
	# Without tyre friction (E2) the contact force is vertical in NED, so the CG must not move horizontally. RK4 on
	# body-axis velocities leaves a truncation drift during the bounce; it is integration error, not a force, if it
	# shrinks ≥ 8× at h/2 (4th order: 16×). With friction the rocking wheels scrub and really move the CG.
	var n_h := _drop(model, 0.5, 1.0, true)
	Engine.physics_ticks_per_second = 480
	var n_h2 := _drop(model, 0.5, 1.0, true)
	Engine.physics_ticks_per_second = saved
	var drift_h: float = absf(n_h.state[RB.POS])
	var drift_h2: float = absf(n_h2.state[RB.POS])
	_check("normal force only: horizontal drift is integration error, ≤ 0.1 mm at h and ≥ 8× smaller at h/2", drift_h < 1e-4 and drift_h2 * 8.0 <= drift_h, "north %s m at h, %s m at h/2" % [drift_h, drift_h2])

	# The real session: nothing changes in the air (loads bit-identical to the air-only evaluator at the trimmed
	# start), a low drop is a landing, a high drop breaks the gear, and the hull still crashes the rest.
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	session.reset()
	var air_only: PackedFloat64Array = Dynamics.loads(session.start.state, model, _trim_deflections(session), session.start.rpm, 1.225, M.v3(0, 0, 0))
	_check("in the air the session's loads are bit-identical to the air-only evaluator", session._loads(session.start.state, 0.0) == air_only)
	_check("a trimmed start has no wheel on the ground", session.gear_compressions(session.start.state)[0] < -20.0)

	var landed := _session_drop(session, 0.35, 3.0)
	_check("dropped from 0.35 m: lands, no crash, at rest on three wheels", landed.crashes == 0 and landed.on_wheels and landed.speed < 0.02, "crashes %d, speed %.3f m/s, compressions %s" % [landed.crashes, landed.speed, landed.comp])
	var broken := _session_drop(session, 2.0, 3.0)
	_check("dropped from 2.0 m: nose gear travel limit (crash, restart)", broken.crashes >= 1 and broken.why == "landing gear travel limit (nose)", "crashes %d, why '%s', sink %.1f m/s" % [broken.crashes, broken.why, broken.sink])
	_check("inverted at 0.20 m: still a hull crash (fin)", session.touches_ground(RB.make_state(M.v3(0, 0, -0.2), M.v3(0, 0, 0), M.q_from_euler(0, 0, PI), M.v3(0, 0, 0))))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _trim_deflections(session: Node) -> Dictionary:
	var Commands := preload("res://input/commands.gd")
	var Aero := preload("res://physics/aero.gd")
	var a: PackedFloat64Array = session.sim.aux
	return Aero.deflections_from_surfaces(Commands.surface_deflections_deg({ roll = a[1], pitch = a[2], yaw = a[3] }, session.throws_deg()))


## Engine off, sticks neutral, dropped level from `alt` at rest; ticks the session like the game does.
func _session_drop(session: Node, alt: float, seconds: float) -> Dictionary:
	session.reset()
	session.engine_running = false
	var inputs: PackedFloat64Array = session.sim.inputs
	inputs[3] = 0.0
	session.sim.inputs = inputs
	session.sim.aux = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	session.sim.reset(_level(alt))
	session.sim.set_paused(false)
	var crashes := 0
	var why := ""
	var sink := 0.0
	for i in roundi(seconds / session.sim.dt()):
		session._physics_process(session.sim.dt())
		if not session.crash.is_empty() and why.is_empty():
			crashes += 1
			why = str(session.crash.why)
			sink = float(session.crash.sink)
			break
		if not session.sim.paused:
			session.sim.step()
	var s: PackedFloat64Array = session.sim.state
	var comp: PackedFloat64Array = session.gear_compressions(s)
	var on_wheels: bool = comp.size() == 3 and comp[0] > 0.0 and comp[1] > 0.0 and comp[2] > 0.0
	return { crashes = crashes, why = why, sink = sink, on_wheels = on_wheels, comp = comp,
		speed = sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2) }
