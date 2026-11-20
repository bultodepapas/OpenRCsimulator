# Accepted Simulation.step characterization at main d736ee8a.
# Adapted from the isolated body-only setup in test_landscape_collision_session.gd.
# This is a synthetic single-point body with zero gravity, zero loads and zero rotation;
# it is NOT an ordinary airplane flight, a stock-aircraft trajectory, or material validation.
# The separately calculated continuation includes the implementation's 0.01 m separation.
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const Collision := preload("res://sim/scenery_collision.gd")
const RB := preload("res://physics/rigid_body.gd")
const SPEED: float = 250.0 / 3.0
const DOWN_SPEED: float = 0.24
const TOP_DOWN: float = -10.0
const INITIAL_CLEARANCE: float = 0.0004
var checks: int = 0
var failures: int = 0

func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		failures += 1

func world() -> Dictionary:
	# Box top D=-10, bottom D=-8; north/east are each [-5,+5].
	var proxies: Array[Dictionary] = []
	CollisionWorld._add_box_at_down(proxies, "remainder:soft-box", "test_obstacle", "body",
		"soft_foliage_impulse", 0.0, 0.0, -9.0, 10.0, 2.0, 10.0, 0.0)
	return {format = CollisionWorld.FORMAT, identity = "remainder-soft-box-v1",
		cell_size_m = CollisionWorld.CELL_SIZE_M, proxies = proxies,
		bins = CollisionWorld._build_bins(proxies)}

func make_session(collision_world: Dictionary) -> Node:
	var session: Node = FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	if session.sim == null or not session.aircraft.get("ok", false):
		check("session aircraft and simulation prepared", false)
		session.free()
		return null
	check("session aircraft and simulation prepared", true)
	# The normalized aircraft is retained solely to drive the real session machinery.
	# Replace its collision points with one CG point and isolate the RK body step.
	var aircraft: Dictionary = session.aircraft
	aircraft.model.crash_hull = PackedFloat64Array([0.0, 0.0, 0.0])
	session.aircraft = aircraft
	session.sim.gravity = 0.0
	session.sim.continuous = PackedFloat64Array()
	session.sim.model.block_loads = func(_body: PackedFloat64Array, _extra: PackedFloat64Array,
			_t: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	session.sim.model.block_derivative = func(_body: PackedFloat64Array, extra: PackedFloat64Array,
			_t: float) -> PackedFloat64Array:
		var rates := PackedFloat64Array()
		rates.resize(extra.size())
		return rates
	session.sim.model.stage = Callable()
	session.sim.model.stage_rotor_momentum = Callable()
	session.sim.model.block_aux = Callable()
	session.sim.model.step_policy = Callable()
	session.sim.model.substeps = Callable()
	session.sim.model.substeps_joint = Callable()
	session.sim.model.events.clear()
	session.sim.model.pre_tick = func(aux: PackedFloat64Array, _inputs: PackedFloat64Array,
			_dt: float) -> PackedFloat64Array:
		return aux
	session.sim.model.rotor_momentum = func(_aux: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array()
	session.sim.model.loads = func(_body: PackedFloat64Array, _time_s: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	if not collision_world.is_empty():
		var installed: bool = session.set_collision_world(collision_world)
		check("synthetic scenery world installs", installed)
		if not installed:
			session.free()
			return null
	var initial := RB.make_state(PackedFloat64Array([0.0, 0.0, TOP_DOWN - INITIAL_CLEARANCE]),
		PackedFloat64Array([SPEED, 0.0, DOWN_SPEED]), PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]))
	var reset_ok: bool = session.sim.reset(initial)
	check("body-only synthetic initial state resets", reset_ok, str(session.sim.fault_reason))
	if not reset_ok:
		session.free()
		return null
	check("fixture uses constant-mass scenery path", not session.finite_fuel_is_active())
	session.sim.set_paused(false)
	return session

func _initialize() -> void:
	var obstacle: Dictionary = world()
	check("synthetic box and bins prepared", obstacle.proxies.size() == 1 and not obstacle.bins.is_empty())
	var control: Node = make_session({})
	var impacted: Node = make_session(obstacle)
	if control == null or impacted == null:
		if control != null: control.free()
		if impacted != null: impacted.free()
		print("SUMMARY checks=%d failures=%d (setup incomplete)" % [checks, failures])
		quit(1)
		return
	var dt: float = impacted.sim.dt()
	check("fixture tick is 1/240 s", absf(dt - 1.0 / 240.0) < 1e-14)
	print("CASE isolated accepted step: one point at CG; zero applied loads, zero gravity, zero angular rate")
	print("PARAM speed_n=%.12f down_speed=%.12f dt=%.12f initial_down=%.12f box_top=%.12f separation=%.12f" % [SPEED, DOWN_SPEED, dt, TOP_DOWN - INITIAL_CLEARANCE, TOP_DOWN, Collision.CONTACT_SEPARATION_M])
	control.sim.step()
	impacted.sim.step()
	var nohit: PackedFloat64Array = control.sim.state.duplicate()
	var accepted: PackedFloat64Array = impacted.sim.state.duplicate()
	var event: Variant = impacted.last_scenery_event()
	print("OBS control tick=%d time_s=%.12f fault=%s state=%s scenery_event=%s" % [control.sim.tick, control.sim.time(), str(control.sim.fault_reason), str(nohit), str(control.last_scenery_event())])
	print("OBS impacted tick=%d time_s=%.12f fault=%s state=%s crash=%s" % [impacted.sim.tick, impacted.sim.time(), str(impacted.sim.fault_reason), str(accepted), str(impacted.crash)])
	check("no-world control accepts one tick", control.sim.tick == 1 and control.sim.fault_reason.is_empty())
	check("no-world control travels the full zero-force interval", absf(nohit[RB.POS] - SPEED * dt) < 1e-9 and absf(nohit[RB.POS + 2] - (TOP_DOWN - INITIAL_CLEARANCE + DOWN_SPEED * dt)) < 1e-9)
	check("world run accepts one tick without a crash", impacted.sim.tick == 1 and impacted.sim.fault_reason.is_empty() and impacted.crash.is_empty())
	check("accepted tick commits a nonterminal scenery impulse", event != null and not event.terminal and event.response_status == "dissipative_impulse")
	if event != null:
		var fraction: float = float(event.time_fraction)
		var remaining: float = dt * (1.0 - fraction)
		var post_north_velocity: float = accepted[RB.VEL]
		var post_down_velocity: float = accepted[RB.VEL + 2]
		# Independent continuation for the SAME instantaneous normal impulse and 1 cm
		# separation: after that response, hold velocity over the unconsumed interval.
		# This is a deliberately force-free ballistic comparison, not the current solver.
		var continued_north: float = float(event.point_ned[0]) + post_north_velocity * remaining
		var continued_down: float = accepted[RB.POS + 2] + post_down_velocity * remaining
		var missing_north: float = continued_north - accepted[RB.POS]
		print("OBS event fraction=%.12f time_s=%.12f point=%s normal=%s point_velocity=%s normal_speed=%.12f restitution=%.12f energy_j=%.12f dissipated_j=%.12f status=%s" % [fraction, fraction * dt, str(event.point_ned), str(event.normal_ned), str(event.velocity_ned), float(event.normal_speed_mps), float(event.restitution), float(event.impact_energy_j), float(event.dissipated_energy_j), str(event.response_status)])
		print("ORACLE remaining_s=%.12f current_north=%.12f forcefree_continued_north=%.12f difference_north_m=%.12f current_down=%.12f forcefree_continued_down=%.12f" % [remaining, accepted[RB.POS], continued_north, missing_north, accepted[RB.POS + 2], continued_down])
		check("event time matches the prescribed approach", absf(fraction - 0.4) < 2e-6)
		check("normal impact speed and direction match fixture", absf(float(event.normal_speed_mps) - DOWN_SPEED) < 1e-9 and event.normal_ned.size() == 3 and float(event.normal_ned[2]) < -0.999999)
		check("current accepted north stops at the event point", absf(accepted[RB.POS] - float(event.point_ned[0])) < 1e-9)
		check("current response includes 1 cm outward position separation", absf(accepted[RB.POS + 2] - (float(event.point_ned[2]) - Collision.CONTACT_SEPARATION_M)) < 1e-9)
		check("normal impulse reverses down velocity and preserves north velocity", absf(post_north_velocity - SPEED) < 1e-9 and absf(post_down_velocity + DOWN_SPEED * float(event.restitution)) < 1e-9)
		check("characterized remaining ballistic north travel is about 0.2083 m", absf(missing_north - (SPEED * dt * 0.6)) < 1e-5)
	control.free()
	impacted.free()
	print("SUMMARY accepted-step characterization checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
