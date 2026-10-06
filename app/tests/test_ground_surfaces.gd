# E3a: field surfaces scale the tyre forces. The surface table loads and refuses bad data; each wheel finds its
# surface in the field's rectangles (runway over mown over rough, rough beyond); hand-computed scaled loads; friction
# still never produces power across surface edges; coast-downs decelerate at C_rr·factor·g; on the real field the
# idling Stik holds on the mown runway and on the rough, while on pavement it rolls away (the E2 finding).
# Run: godot --headless --path . --script res://tests/test_ground_surfaces.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const Ground := preload("res://physics/ground_contact.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const AD := preload("res://physics/aircraft_data.gd")
const FieldLoader := preload("res://data/field_loader.gd")
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


func _state(north: float, east: float, alt: float, vel_body: PackedFloat64Array, yaw := 0.0) -> PackedFloat64Array:
	return RB.make_state(M.v3(north, east, -alt), vel_body, M.q_from_euler(yaw, 0.0, 0.0), M.v3(0, 0, 0))


## One contact at the CG's ground point (0.2 m below it), k 1000 N/m: level at 0.1 m → N = 100 N.
func _one_contact() -> Dictionary:
	return { contacts = [{ name = "test", position = M.v3(0.0, 0.0, 0.2), stiffness = 1000.0, damping = 0.0,
		max_compression = 0.5, max_steering = 0.0 }], reach = 0.5,
		rolling_resistance = 0.04, side_friction = 0.8, tan_peak_slip = tan(deg_to_rad(6.0)) }


func _rejects(label: String, mutate: Callable, needle: String) -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GroundSurfaces.DEFAULT_PATH))
	mutate.call(raw)
	var r := GroundSurfaces.validate(raw)
	var hit := false
	for e in r.errors:
		hit = hit or needle in e
	_check("refuses: " + label, not r.ok and hit, str(r.errors))


func _initialize() -> void:
	var t := GroundSurfaces.load_table()
	_check("surface table loads", t.ok, str(t.errors))
	if not t.ok:
		quit(1)
		return
	var table: Dictionary = t.table
	_check("runway (mown strip) 0.8 / 2.5, mown 0.7 / 5, rough 0.7 / 7.5", table.runway.friction_factor == 0.8 and table.runway.rolling_factor == 2.5
		and table.mown.friction_factor == 0.7 and table.mown.rolling_factor == 5.0 and table.rough.friction_factor == 0.7 and table.rough.rolling_factor == 7.5, str(table))
	_rejects("wrong format", func(d): d.format = "openrc-surfaces v0", "format")
	_rejects("a missing surface type", func(d): d.surfaces.erase("mown"), "surfaces.mown: missing")
	_rejects("friction factor above 1 (would break the side-force bound)", func(d): d.surfaces.runway.friction_factor.value = 1.2, "outside")
	_rejects("rolling factor in percent", func(d): d.surfaces.rough.rolling_factor.unit = "%", "unit '%'")
	_rejects("an unknown surface type", func(d): d.surfaces["ice"] = d.surfaces.rough, "unknown surface type")
	_rejects("an empty source", func(d): d.surfaces.rough.rolling_factor.source = " ", "empty source")

	# Lookup on the real field, from the field's own rectangles (whatever the landscape track sets them to).
	var f := FieldLoader.load_from()
	_check("default field loads", f.ok, str(f.get("errors", [])))
	var field: Dictionary = f.field
	var built := GroundSurfaces.build(table, field)
	_check("surface lookup table builds from the field", built.ok, str(built.errors))
	var rects: PackedFloat64Array = built.rects
	var runway: Dictionary = {}
	for s in field.surfaces:
		if s.type == "runway":
			runway = s
	var rn: float = runway.center_north
	var re: float = runway.center_east
	var half_e: float = runway.length_east_west / 2.0
	var half_n: float = runway.width_north_south / 2.0
	var at := func(n: float, e: float) -> PackedFloat64Array:
		var i := Ground.surface_at(rects, n, e)
		return PackedFloat64Array([rects[i + 4], rects[i + 5]])
	var on_runway := PackedFloat64Array([0.8, 2.5])
	var on_rough := PackedFloat64Array([0.7, 7.5])
	_check("runway centre, threshold and edge are runway", at.call(rn, re) == on_runway and at.call(rn, re + half_e - 0.01) == on_runway and at.call(rn + half_n, re) == on_runway)
	_check("just past the runway's end and side is rough", at.call(rn, re + half_e + 0.01) == on_rough and at.call(rn + half_n + 0.01, re) == on_rough)
	_check("the pilot station and 30 km away are rough (beyond every rectangle: rough)", at.call(field.pilot.north, field.pilot.east) == on_rough and at.call(30000.0, 0.0) == on_rough)
	# Precedence: a runway inside a mown area inside the rough, listed in the worst order.
	var nested := { surfaces = [
		{ id = "r", type = "rough", center_north = 0.0, center_east = 0.0, length_east_west = 1000.0, width_north_south = 1000.0 },
		{ id = "m", type = "mown", center_north = 0.0, center_east = 0.0, length_east_west = 200.0, width_north_south = 60.0 },
		{ id = "w", type = "runway", center_north = 0.0, center_east = 0.0, length_east_west = 100.0, width_north_south = 12.0 }] }
	var nr: PackedFloat64Array = GroundSurfaces.build(table, nested).rects
	var fac := func(n: float, e: float) -> float: return nr[Ground.surface_at(nr, n, e) + 5]
	_check("precedence: runway over mown over rough, whatever the field's order", fac.call(0, 0) == 2.5 and fac.call(20, 0) == 5.0 and fac.call(100, 0) == 7.5 and fac.call(900, 0) == 7.5,
		"%s %s %s %s" % [fac.call(0, 0), fac.call(20, 0), fac.call(100, 0), fac.call(900, 0)])

	# Hand-computed: N = 100 N, C_rr 0.04, μ 0.8.
	var one := _one_contact()
	var l := Ground.loads(_state(rn, re, 0.1, M.v3(2.0, 0, 0)), one, 0.0, rects)
	_check("on the runway: rolling drag −0.04·2.5·100 = −10 N", absf(l[0] + 10.0) < 1e-12, str(l))
	l = Ground.loads(_state(rn, re, 0.1, M.v3(0.0, 2.0, 0)), one, 0.0, rects)
	_check("on the runway: sideways skid saturates at −0.8·0.8·100 = −64 N", absf(l[1] + 64.0) < 1e-12, str(l))
	l = Ground.loads(_state(0.0, 0.0, 0.1, M.v3(2.0, 0, 0)), one, 0.0, rects)
	_check("on the rough: rolling drag −0.04·7.5·100 = −30 N", absf(l[0] + 30.0) < 1e-12, str(l))
	l = Ground.loads(_state(0.0, 0.0, 0.1, M.v3(0.015, 0, 0)), one, 0.0, rects)
	_check("on the rough at 1.5 cm/s: half the drag (creep speed 0.1·C_rr = 3 cm/s)", absf(l[0] + 15.0) < 1e-9, str(l))
	# The surface is looked up under each wheel, not the CG: a wheel 0.3 m ahead, heading east, CG 0.1 m before the
	# runway's end → the wheel is 0.2 m past it, on the rough.
	var ahead := _one_contact()
	ahead.contacts[0].position = M.v3(0.3, 0.0, 0.2)
	l = Ground.loads(_state(rn, re + half_e - 0.1, 0.1, M.v3(2.0, 0, 0), PI / 2.0), ahead, 0.0, rects)
	_check("the wheel's own surface counts: CG on the runway, wheel past its end → rough drag −30 N", absf(l[0] + 30.0) < 1e-9, str(l))
	l = Ground.loads(_state(rn, re, 0.1, M.v3(2.0, 0, 0)), one)
	_check("without a surface table: the gear's pavement values (−4 N), as in E2", absf(l[0] + 4.0) < 1e-12, str(l))

	# Friction never produces power, also with the wheel crossing surface edges.
	var bare := one.duplicate()
	bare.side_friction = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var worst := -INF
	for i in 2000:
		var vel := M.v3(rng.randf_range(-5, 5), rng.randf_range(-5, 5), rng.randf_range(-1, 1))
		var s := _state(rn + rng.randf_range(-1.5, 1.5) * half_n, re + rng.randf_range(-1.2, 1.2) * half_e, rng.randf_range(0.0, 0.19), vel, rng.randf_range(-PI, PI))
		var a := Ground.loads(s, one, 0.0, rects)
		var b := Ground.loads(s, bare, 0.0, rects)
		if not a.is_empty():
			worst = maxf(worst, (a[0] - b[0]) * vel[0] + (a[1] - b[1]) * vel[1] + (a[2] - b[2]) * vel[2])
	_check("friction never produces power across surface edges (2000 random states)", worst <= 1e-12, "max P %s W" % worst)

	var r := AD.load_file(PATH)
	var model: Dictionary = r.model
	var parked := _parked(model)
	for case in [["runway", rn, re - half_e + 30.0, 0.04 * 2.5], ["rough", rn - 40.0, 0.0, 0.04 * 7.5]]:
		var d := _coast(model, parked, rects, case[1], case[2])
		var expect: float = case[3] * G
		_check("coast-down on the %s from 3 m/s: %.3f m/s² (C_rr·factor·g) within 1 %%" % [case[0], expect], absf(d - expect) < 0.01 * expect, "%.4f m/s²" % d)

	_session_checks(model, field, parked, rn, re - half_e + 10.0)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## A bare rigid body (no air, no engine) on the Stik's gear and the given surfaces.
func _bare(model: Dictionary, rects: PackedFloat64Array) -> Node:
	var gear: Dictionary = model.landing_gear
	var sim: Node = Sim.new()
	sim.mass = model.mass_kg
	sim.inertia = model.inertia.duplicate()
	sim.loads = func(s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		var g := Ground.loads(s, gear, 0.0, rects)
		return g if not g.is_empty() else PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	return sim


## The Stik settled on its wheels at the origin, heading east (down the runway), at rest.
func _parked(model: Dictionary) -> PackedFloat64Array:
	var sim := _bare(model, PackedFloat64Array())
	sim.reset(_state(0.0, 0.0, 0.27, M.v3(0, 0, 0), PI / 2.0))
	for i in roundi(6.0 / sim.dt()):
		sim.step()
	var s: PackedFloat64Array = sim.state.duplicate()
	sim.free()
	return s


## Mean deceleration (m/s²) between 0.25 s and 0.75 s of a coast from 3 m/s eastward at (north, east).
func _coast(model: Dictionary, parked: PackedFloat64Array, rects: PackedFloat64Array, north: float, east: float) -> float:
	var sim := _bare(model, rects)
	var s0 := parked.duplicate()
	s0[RB.POS] = north
	s0[RB.POS + 1] = east
	s0[RB.VEL] = 3.0
	sim.reset(s0)
	for i in roundi(0.25 / sim.dt()):
		sim.step()
	var u0: float = sim.state[RB.VEL]
	for i in roundi(0.5 / sim.dt()):
		sim.step()
	var d: float = (u0 - sim.state[RB.VEL]) / 0.5
	sim.free()
	return d


## The real session (aero, engine at idle, servos) parked at (north, east) heading east, for 10 s.
## Returns { moved (m), speed (m/s), crashes }.
func _idle(session: Node, parked: PackedFloat64Array, north: float, east: float) -> Dictionary:
	session.reset()
	session.engine_running = true
	session.trims = { roll = 0.0, pitch = 0.0, yaw = 0.0 }
	var s0 := parked.duplicate()
	s0[RB.POS] = north
	s0[RB.POS + 1] = east
	session.sim.aux = PackedFloat64Array([float(session.aircraft.model.propulsion.idle_rpm), 0.0, 0.0, 0.0])
	session.sim.reset(s0)
	session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	session.sim.set_paused(false)
	var crashes := 0
	for i in roundi(10.0 / session.sim.dt()):
		session._physics_process(session.sim.dt())
		if not session.crash.is_empty():
			crashes += 1
			break
		session.sim.step()
	var s: PackedFloat64Array = session.sim.state
	return { moved = sqrt((s[RB.POS] - north) ** 2 + (s[RB.POS + 1] - east) ** 2), speed = sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2), crashes = crashes }


func _session_checks(model: Dictionary, field: Dictionary, parked: PackedFloat64Array, north: float, east: float) -> void:
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	var pavement := _idle(session, parked, north, east)
	_check("no field (pavement): idling on the runway spot rolls away (E2 finding)", pavement.moved > 5.0, "%.1f m in 10 s, %.2f m/s" % [pavement.moved, pavement.speed])
	_check("set_field builds the surfaces and keeps the flight flyable", session.set_field(field) and session.surface_error.is_empty() and session.is_flyable())
	session.reset()
	var held := _idle(session, parked, north, east)
	# A pure velocity law cannot hold a steady push: it creeps at v_creep·F/(C_rr·N), = 0.1·F/(m·g) once C_rr ≥ 0.1
	# (0.9 cm/s at idle on any grass). True stiction needs per-wheel state (E3b).
	_check("on the mown runway: idle (2.6 N) does not beat rolling resistance (2.8 N); only the regularisation's creep, ≤ 1 cm/s", held.crashes == 0 and held.speed <= 0.01 and held.moved < 0.11,
		"%.3f m in 10 s, %.4f m/s" % [held.moved, held.speed])
	var rough := _idle(session, parked, north - 40.0, 0.0)
	_check("on the rough: idle holds (creep ≤ 1 cm/s)", rough.crashes == 0 and rough.speed <= 0.01, "%.3f m in 10 s, %.4f m/s" % [rough.moved, rough.speed])
	print("info trace header: ", session.trace_meta().ground)
	var broken := FlightSession.new()
	broken.setup()
	root.add_child(broken)
	_check("invalid surface data refuses the flight (like invalid aircraft data)", not broken.set_field(field, "res://data/ground/missing.json") and not broken.is_flyable() and "ground surfaces invalid" in broken.pause_reason,
		broken.pause_reason)
	broken.queue_free()
	session.queue_free()
