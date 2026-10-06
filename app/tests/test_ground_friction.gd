# E2: tyre friction and nose-wheel steering. Hand-computed tyre loads and signs; friction never produces power;
# a coast-down decelerates at C_rr·g; a slow steered turn follows the kinematic radius wheelbase / tan δ; the same
# turn agrees at h and h/2; a parked airplane stays put; the real session (aero, engine) taxis a figure-eight.
# Run: godot --headless --path . --script res://tests/test_ground_friction.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const Ground := preload("res://physics/ground_contact.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const FlightSession := preload("res://sim/flight_session.gd")

const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const G := 9.80665
## Stick speed of the test pilot's thumb (full throw per second) in the session taxi.
const STICK_RATE := 1.0

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _state(alt: float, vel_body: PackedFloat64Array, yaw := 0.0, pitch := 0.0, roll := 0.0, rate := M.v3(0, 0, 0)) -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, -alt), vel_body, M.q_from_euler(yaw, pitch, roll), rate)


## One contact 0.3 m ahead of and 0.2 m below the CG, k 1000 N/m, no damping, steerable ±20°, μ 0.8, C_rr 0.04, 6°.
func _one_contact(mu := 0.8) -> Dictionary:
	return { contacts = [{ name = "test", position = M.v3(0.3, 0.0, 0.2), stiffness = 1000.0, damping = 0.0,
		max_compression = 0.5, max_steering = deg_to_rad(20.0) }], reach = 0.5,
		rolling_resistance = 0.04, side_friction = mu, tan_peak_slip = tan(deg_to_rad(6.0)) }


## A bare rigid body (no air, no engine) on the Stik's gear; `push` (s -> body force along x, N) at the CG.
func _bare(model: Dictionary, steer: float, push: Callable) -> Node:
	var gear: Dictionary = model.landing_gear
	var sim: Node = Sim.new()
	sim.mass = model.mass_kg
	sim.inertia = model.inertia.duplicate()
	sim.loads = func(s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		var out := PackedFloat64Array([push.call(s), 0.0, 0.0, 0.0, 0.0, 0.0])
		var g := Ground.loads(s, gear, steer)
		for i in g.size():
			out[i] += g[i]
		return out
	return sim


## The Stik settled on its wheels (bare body), at rest, at the origin, heading north.
func _parked(model: Dictionary) -> PackedFloat64Array:
	var sim := _bare(model, 0.0, func(_s): return 0.0)
	sim.reset(_state(0.27, M.v3(0, 0, 0)))
	for i in roundi(6.0 / sim.dt()):
		sim.step()
	var s: PackedFloat64Array = sim.state.duplicate()
	sim.free()
	s[RB.POS] = 0.0
	s[RB.POS + 1] = 0.0
	return s


## Slow steered turn of the bare body: speed held at `speed` by a stiff throttle on u; after `settle` seconds
## measures for `seconds`. Returns { radius (m, ground speed of the main-axle midpoint / yaw rate), slip (deg, at
## the main axle), state, fault }.
func _turn(model: Dictionary, parked: PackedFloat64Array, steer: float, speed: float, settle: float, seconds: float) -> Dictionary:
	var sim := _bare(model, steer, func(s): return 20.0 * (speed - s[RB.VEL]))
	var s0 := parked.duplicate()
	s0[RB.VEL] = speed
	sim.reset(s0)
	for i in roundi(settle / sim.dt()):
		sim.step()
	var x_main: float = model.landing_gear.contacts[0].position[0]
	var radii := PackedFloat64Array()
	var slips := PackedFloat64Array()
	for i in roundi(seconds / sim.dt()):
		sim.step()
		var s: PackedFloat64Array = sim.state
		var r := s[RB.RATE + 2]
		var u := s[RB.VEL]
		var v := s[RB.VEL + 1] + r * x_main # lateral velocity of the main-axle midpoint
		radii.append(sqrt(u * u + v * v) / absf(r))
		slips.append(rad_to_deg(atan2(v, u)))
	var out := { radius = _mean(radii), slip = _mean(slips), state = sim.state.duplicate(), fault = sim.fault_reason }
	sim.free()
	return out


## Full right steer, speed raised slowly (0.1 m/s per s from 1 m/s, quasi-static) until the inside (right) main wheel
## leaves the ground. Returns { a_lat (V·r, m/s²), speed, radius } at that moment, or {} if it never does in 30 s.
func _tip_ramp(model: Dictionary, parked: PackedFloat64Array) -> Dictionary:
	var gear: Dictionary = model.landing_gear
	var t := [0.0]
	var sim := _bare(model, 1.0, func(s): return 20.0 * (1.0 + 0.1 * t[0] - s[RB.VEL]))
	var s0 := parked.duplicate()
	s0[RB.VEL] = 1.0
	sim.reset(s0)
	var out := {}
	for i in roundi(30.0 / sim.dt()):
		sim.step()
		t[0] = sim.time()
		var s: PackedFloat64Array = sim.state
		if t[0] > 2.0 and Ground.compressions(s, gear)[1] <= 0.0:
			var v := sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2)
			out = { a_lat = v * s[RB.RATE + 2], speed = v, radius = v / s[RB.RATE + 2] }
			break
	sim.free()
	return out


func _mean(a: PackedFloat64Array) -> float:
	var t := 0.0
	for x in a:
		t += x
	return t / a.size()


func _initialize() -> void:
	var r := AD.load_file(PATH)
	_check("Stik data loads with tyre friction and a steerable nose wheel", r.ok and r.model.landing_gear.get("side_friction", 0.0) > 0.0, str(r.errors))
	if not r.ok:
		quit(1)
		return
	var model: Dictionary = r.model
	var gear: Dictionary = model.landing_gear
	var steer_max: float = gear.contacts[2].max_steering
	_check("only the nose wheel steers (20°)", gear.contacts[0].max_steering == 0.0 and gear.contacts[1].max_steering == 0.0 and absf(steer_max - deg_to_rad(20.0)) < 1e-12)

	_hand_computed()
	_never_adds_energy()

	# Coast-down, bare body (no air, no engine): from 3 m/s straight ahead the wheels decelerate it at C_rr·g while
	# rolling faster than ROLL_CREEP (ΣN = m·g; the nose-down moment of the wheel drag only shifts load).
	var parked := _parked(model)
	var coast := _bare(model, 0.0, func(_s): return 0.0)
	var s0 := parked.duplicate()
	s0[RB.VEL] = 3.0
	coast.reset(s0)
	for i in roundi(0.5 / coast.dt()):
		coast.step()
	var u0: float = coast.state[RB.VEL]
	for i in roundi(2.0 / coast.dt()):
		coast.step()
	var decel: float = (u0 - coast.state[RB.VEL]) / 2.0
	var expect: float = gear.rolling_resistance * G
	_check("coast-down decelerates at C_rr·g = %.4f m/s² within 1 %%" % expect, absf(decel - expect) < 0.01 * expect, "%.5f m/s²" % decel)
	for i in roundi(10.0 / coast.dt()):
		coast.step()
	var stopped: PackedFloat64Array = coast.state
	_check("then stops and stays stopped (no creep, no chatter)", absf(stopped[RB.VEL]) < 1e-3 and absf(stopped[RB.VEL + 1]) < 1e-3 and coast.fault_reason == "",
		"u %s, v %s m/s, rolled %.2f m (v²/2a = %.2f)" % [stopped[RB.VEL], stopped[RB.VEL + 1], stopped[RB.POS], 9.0 / (2.0 * expect)])
	coast.free()

	# Kinematic oracle: at walking speed the tyres barely slip, so the main-axle midpoint circles with
	# R = wheelbase / tan δ (bicycle model). Faster, the slip angles grow and the radius opens (understeer).
	var wheelbase: float = gear.contacts[2].position[0] - gear.contacts[0].position[0]
	var r_kin := wheelbase / tan(steer_max)
	var slow := _turn(model, parked, 1.0, 1.0, 4.0, 2.0)
	_check("full right steer at 1 m/s: radius = wheelbase / tan 20° = %.3f m within 3 %%" % r_kin, absf(slow.radius - r_kin) < 0.03 * r_kin and slow.fault == "",
		"%.4f m (main-axle slip %.2f°)" % [slow.radius, slow.slip])
	_check("right steer turns right (yaw rate > 0), left steer turns left", slow.state[RB.RATE + 2] > 0.0 and _turn(model, parked, -1.0, 1.0, 2.0, 0.5).state[RB.RATE + 2] < 0.0)
	var fast := _turn(model, parked, 1.0, 3.0, 4.0, 2.0)
	_check("at 3 m/s the turn opens (understeer from tyre slip), still on three wheels", fast.radius > slow.radius and fast.fault == "" and _on_wheels(fast.state, gear),
		"radius %.3f m, main-axle slip %.2f°" % [fast.radius, fast.slip])

	# Quasi-static tip-over: in a right turn the airplane rolls out (left) about the nose–left-main line. It lifts a
	# wheel when the lateral acceleration v²/R exceeds g·d/h (d: the CG's ground distance to that line, h: CG height).
	# μ = 0.8 > d/h, so the tyres grip and it tips before it slides: the high-wing Stik's real failure mode.
	var nose: PackedFloat64Array = gear.contacts[2].position
	var left: PackedFloat64Array = gear.contacts[0].position
	var lx := left[0] - nose[0]
	var ly := left[1] - nose[1]
	var d := absf(nose[0] * ly - nose[1] * lx) / sqrt(lx * lx + ly * ly)
	# Rigid limit: the gear 64× stiffer (damping 8×, same ζ) at 960 Hz sags 1 mm instead of 18, so the quasi-static
	# rigid-triangle oracle must hold. The real gear rolls out on its springs first and unloads earlier.
	var stiff := model.duplicate()
	stiff.landing_gear = gear.duplicate(true)
	for c in stiff.landing_gear.contacts:
		c.stiffness *= 64.0
		c.damping *= 8.0
	var saved_hz := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 960
	var stiff_parked := _parked(stiff)
	var rigid := _tip_ramp(stiff, stiff_parked)
	Engine.physics_ticks_per_second = saved_hz
	var h_rigid := -stiff_parked[RB.POS + 2]
	var a_oracle := G * d / h_rigid
	_check("tip-over, rigid limit: speeding up slowly in a full-steer turn, the inside wheel unloads at a_lat = g·d/h = %.2f m/s² within 3 %% (d %.3f m, h %.3f m; d/h %.2f < μ: it tips before it slides)" % [a_oracle, d, h_rigid, d / h_rigid],
		not rigid.is_empty() and absf(rigid.a_lat - a_oracle) < 0.03 * a_oracle,
		"a_lat %.3f m/s² at %.2f m/s" % [rigid.get("a_lat", NAN), rigid.get("speed", NAN)])
	var tip := _tip_ramp(model, parked)
	_check("tip-over, real gear: unloads earlier (roll on 18 mm-sag springs moves the CG out) but above 0.6× rigid",
		not tip.is_empty() and tip.a_lat < rigid.get("a_lat", 0.0) and tip.a_lat > 0.6 * a_oracle,
		"a_lat %.2f m/s² (%.0f %% of rigid) at %.2f m/s, radius %.2f m" % [tip.get("a_lat", NAN), 100.0 * tip.get("a_lat", NAN) / a_oracle, tip.get("speed", NAN), tip.get("radius", NAN)])

	# The same 3 s turn at h and h/2 (480 Hz), well below the tip speed: the tick resolves the tyre forces. (Near
	# v_tip a wheel bounces on and off the ground and the error falls to first order.)
	var h := _turn(model, parked, 1.0, 1.5, 0.0, 3.0)
	var saved := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 480
	var h2 := _turn(model, parked, 1.0, 1.5, 0.0, 3.0)
	Engine.physics_ticks_per_second = saved
	var dp := sqrt((h.state[RB.POS] - h2.state[RB.POS]) ** 2 + (h.state[RB.POS + 1] - h2.state[RB.POS + 1]) ** 2)
	var dr: float = absf(h.state[RB.RATE + 2] - h2.state[RB.RATE + 2])
	_check("h vs h/2 after a 3 s turn at 1.5 m/s: position within 0.1 mm, yaw rate within 1e-4 rad/s", dp < 1e-4 and dr < 1e-4, "Δpos %s m, Δr %s rad/s" % [dp, dr])

	_session_checks(model, parked)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _hand_computed() -> void:
	# Level at 0.1 m altitude → compression 0.1 m, N = 100 N; μ·N = 80 N, C_rr·N = 4 N.
	var one := _one_contact()
	var l := Ground.loads(_state(0.1, M.v3(2.0, 0, 0)), one)
	_check("rolling ahead at 2 m/s: F_x = −C_rr·N = −4 N, no side force", l.size() == 6 and absf(l[0] + 4.0) < 1e-12 and absf(l[1]) < 1e-12 and absf(l[2] + 100.0) < 1e-12, str(l))
	_check("  and its moment: M_y = 0.2·(−4) + 0.3·100 = 29.2 N·m", absf(l[4] - 29.2) < 1e-12, str(l))
	# Slipping: v_lat 0.1 at v_long 2 → tan(slip) 0.05 → F_side = −80·0.05 / tan 6° = −38.06 N (below μ·N, linear).
	l = Ground.loads(_state(0.1, M.v3(2.0, 0.1, 0)), one)
	var f_side := -80.0 * 0.05 / tan(deg_to_rad(6.0))
	_check("slip angle below the peak: F_y = −μ·N·tan(slip)/tan 6° = %.3f N" % f_side, absf(l[1] - f_side) < 1e-9 and absf(l[0] + 4.0) < 1e-12, str(l))
	l = Ground.loads(_state(0.1, M.v3(-2.0, 0.1, 0)), one)
	_check("rolling backwards at the same slip: same side force, rolling drag forward (+4 N)", absf(l[1] - f_side) < 1e-9 and absf(l[0] - 4.0) < 1e-12, str(l))
	l = Ground.loads(_state(0.1, M.v3(0.0, 2.0, 0)), one)
	_check("sliding sideways: saturated at −μ·N = −80 N, no rolling drag", absf(l[1] + 80.0) < 1e-12 and absf(l[0]) < 1e-12, str(l))
	l = Ground.loads(_state(0.1, M.v3(0.0, 0.0, 0)), one)
	_check("at rest: normal force only (no friction without motion)", absf(l[0]) < 1e-15 and absf(l[1]) < 1e-15 and absf(l[2] + 100.0) < 1e-12, str(l))
	# Heading north-east (yaw 45°) changes nothing in body axes: the law is frame-independent.
	var turned := Ground.loads(_state(0.1, M.v3(2.0, 0.1, 0), PI / 4.0), one)
	var same := true
	var flat := Ground.loads(_state(0.1, M.v3(2.0, 0.1, 0)), one)
	for i in 6:
		same = same and absf(turned[i] - flat[i]) < 1e-9
	_check("heading does not matter (yaw 45° gives the same body loads)", same, "%s vs %s" % [turned, flat])
	# Steered right 20° while rolling straight: the wheel sees −20° slip (saturated) and pushes the nose right.
	l = Ground.loads(_state(0.1, M.v3(2.0, 0, 0)), one, 1.0)
	var t := sqrt(l[0] * l[0] + l[1] * l[1])
	_check("steered right: side force to the right (F_y > 0), nose-right yaw moment (M_z > 0)", l[1] > 0.0 and l[5] > 0.0, str(l))
	_check("  inside the friction circle: |F_tangential| ≤ μ·N", t <= 80.0 + 1e-9, "%.6f N" % t)
	l = Ground.loads(_state(0.1, M.v3(2.0, 0, 0)), one, -1.0)
	_check("steered left: side force to the left, nose-left yaw moment", l[1] < 0.0 and l[5] < 0.0, str(l))
	# Without friction keys (an E1 gear) the forces stay normal-only, exactly.
	var e1 := { contacts = one.contacts, reach = 0.5 }
	l = Ground.loads(_state(0.1, M.v3(2.0, 0.5, 0)), e1, 1.0)
	_check("a gear without friction data stays normal-only (E1 behaviour)", l[0] == 0.0 and l[1] == 0.0, str(l))


## Friction never produces power: for random attitudes, velocities, rates and steering, the tangential force
## (loads with friction minus loads without) dotted with the contact point's velocity is ≤ 0.
func _never_adds_energy() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261006
	var one := _one_contact()
	var bare := _one_contact(0.0)
	var r: PackedFloat64Array = one.contacts[0].position
	var worst := -INF
	var touching := 0
	for i in 2000:
		var vel := M.v3(rng.randf_range(-5, 5), rng.randf_range(-5, 5), rng.randf_range(-1, 1))
		var w := M.v3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		var s := _state(rng.randf_range(0.0, 0.25), vel, rng.randf_range(-PI, PI), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), w)
		var steer := rng.randf_range(-1, 1)
		var a := Ground.loads(s, one, steer)
		var b := Ground.loads(s, bare, steer)
		if a.is_empty():
			continue
		touching += 1
		var vc := M.add(vel, M.cross(w, r))
		var p := (a[0] - b[0]) * vc[0] + (a[1] - b[1]) * vc[1] + (a[2] - b[2]) * vc[2]
		worst = maxf(worst, p)
	_check("friction never produces power (2000 random states, %d touching): max P ≤ 1e-12 W" % touching, touching > 500 and worst <= 1e-12, "max P %s W" % worst)


func _on_wheels(s: PackedFloat64Array, gear: Dictionary) -> bool:
	var c := Ground.compressions(s, gear)
	return c[0] > 0.0 and c[1] > 0.0 and c[2] > 0.0


## The real session (aero, engine, servos, crash checks), ticked like the game does.
func _session_checks(model: Dictionary, parked: PackedFloat64Array) -> void:
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false

	# Parked, engine off: stays within 1 mm for 10 s.
	var p := _drive(session, parked, false, [[10.0, 0.0, 0.0]])
	var moved := sqrt(p.state[RB.POS] ** 2 + p.state[RB.POS + 1] ** 2)
	_check("parked with the engine off: stays within 1 mm for 10 s, no crash", p.crashes == 0 and moved < 1e-3, "moved %s m" % moved)

	# Idle: thrust at idle rpm against rolling resistance (a finding, printed: real glow airplanes creep at idle on
	# pavement and sit still on grass).
	var idle_thrust: float = Propulsion.loads(M.v3(0, 0, 0), model.propulsion.idle_rpm, model.propulsion, 1.225)[0]
	var idle := _drive(session, parked, true, [[10.0, 0.0, 0.0]])
	print("info idle: static thrust %.2f N vs rolling resistance C_rr·m·g %.2f N; after 10 s at idle %.2f m/s, %.1f m" %
		[idle_thrust, model.landing_gear.rolling_resistance * model.mass_kg * G, idle.state[RB.VEL], idle.state[RB.POS]])

	# Figure-eight at idle (on pavement idle already rolls the Stik, and there are no brakes): a straight start, then
	# 30 % right steer (6° at the wheel) for one full turn, then 30 % left for one. More steer at this speed rolls it
	# onto a wingtip (tip-over checks above; printed below).
	var eight := _drive(session, parked, true, [[1.5, 0.0, 0.0], [-1.0, 0.0, 0.3], [-1.0, 0.0, -0.3]])
	_check("figure-eight at idle: two full turns (right, then left), no crash, all three wheels on the ground throughout",
		eight.crashes == 0 and eight.turned.size() == 3 and absf(eight.turned[1] - 360.0) < 1.0 and absf(eight.turned[2] + 360.0) < 1.0 and eight.lifted == 0,
		"crashes %d, turns %s°, ticks with a wheel up %d" % [eight.crashes, eight.turned, eight.lifted])
	if eight.crashes == 0 and eight.turned.size() == 3:
		_check("figure-eight: the right loop lies east of the start line, the left loop west, each > 2 m wide", eight.max_east > 2.0 and eight.min_east < -2.0,
			"east %.2f m, west %.2f m" % [eight.max_east, eight.min_east])
		# The right loop is flown at almost constant speed and closes on itself. Idle keeps accelerating the airplane
		# (3 → 3.8 m/s), so the left loop opens (larger radius, more tyre slip): it must still pass back by the crossing.
		_check("figure-eight: the right loop closes within 0.3 m of the crossing; the left loop passes within 25 % of its width of it; below 4.5 m/s",
			eight.closest[1] < 0.3 and eight.closest[2] < 0.25 * -eight.min_east and eight.max_speed < 4.5,
			"right %.3f m, left %.3f m (width %.2f m), max speed %.2f m/s, %.1f s" % [eight.closest[1], eight.closest[2], -eight.min_east, eight.max_speed, eight.t])
	var snap := _drive(session, parked, true, [[1.5, 0.0, 0.0], [-1.0, 0.0, 1.0], [-1.0, 0.0, -1.0]])
	print("info full-steer figure-eight at idle: crashes %d after turns %s° (reversal at %.2f m/s)" % [snap.crashes, snap.turned, snap.max_speed])
	session.queue_free()


## Drives the session from `start` through `legs` [[seconds (−1 = until heading turned 360°), throttle, steer]],
## engine on or off, ticking it like the game. Returns { state, leg_starts, leg_ends (states), closest (per leg,
## the nearest approach to the crossing, where the second leg began, after turning 180°: m), crashes,
## turned (heading change per leg, deg), lifted (ticks with any wheel off the ground after the first second),
## max_east, min_east, max_speed, t }.
func _drive(session: Node, start: PackedFloat64Array, engine: bool, legs: Array) -> Dictionary:
	session.reset()
	session.engine_running = engine
	session.trims = { roll = 0.0, pitch = 0.0, yaw = 0.0 }
	session.sim.aux = PackedFloat64Array([model_idle(session) if engine else 0.0, 0.0, 0.0, 0.0])
	session.sim.reset(start)
	session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	session.sim.set_paused(false)
	var dt: float = session.sim.dt()
	var out := { crashes = 0, turned = PackedFloat64Array(), lifted = 0, max_east = -INF, min_east = INF, max_speed = 0.0, t = 0.0, leg_starts = [], leg_ends = [], closest = [] }
	var tick := 0
	for li in legs.size():
		var leg: Array = legs[li]
		out.leg_starts.append(session.sim.state.duplicate())
		var prev := _yaw(session.sim.state)
		var turned := 0.0
		var cross: PackedFloat64Array = out.leg_starts[mini(1, li)] # the figure-eight's crossing: where the first loop began
		var closest := INF
		var limit := roundi((leg[0] if leg[0] > 0.0 else 30.0) / dt)
		for i in limit:
			# The pilot's thumb: the stick moves at STICK_RATE toward the leg's steering (a full reversal takes 2 s).
			var inputs: PackedFloat64Array = session.sim.inputs
			session.sim.inputs = PackedFloat64Array([0.0, 0.0, move_toward(inputs[2], leg[2], STICK_RATE * dt), leg[1]])
			session._physics_process(dt)
			if not session.crash.is_empty():
				out.crashes += 1
				out.state = session.sim.state.duplicate()
				return out
			session.sim.step()
			tick += 1
			var s: PackedFloat64Array = session.sim.state
			var y := _yaw(s)
			turned += wrapf(y - prev, -PI, PI)
			prev = y
			if tick * dt > 1.0 and not _on_wheels(s, session.aircraft.model.landing_gear):
				out.lifted += 1
			out.max_east = maxf(out.max_east, s[RB.POS + 1])
			out.min_east = minf(out.min_east, s[RB.POS + 1])
			out.max_speed = maxf(out.max_speed, sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2))
			if absf(turned) > PI:
				closest = minf(closest, sqrt((s[RB.POS] - cross[RB.POS]) ** 2 + (s[RB.POS + 1] - cross[RB.POS + 1]) ** 2))
			if leg[0] < 0.0 and absf(turned) >= TAU:
				out.turned.append(rad_to_deg(turned))
				break
		if leg[0] > 0.0:
			out.turned.append(rad_to_deg(turned))
		out.leg_ends.append(session.sim.state.duplicate())
		out.closest.append(closest)
	out.state = session.sim.state.duplicate()
	out.t = tick * dt
	return out


func model_idle(session: Node) -> float:
	return float(session.aircraft.model.propulsion.idle_rpm)


func _yaw(s: PackedFloat64Array) -> float:
	return M.q_to_euler(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]))[0]
