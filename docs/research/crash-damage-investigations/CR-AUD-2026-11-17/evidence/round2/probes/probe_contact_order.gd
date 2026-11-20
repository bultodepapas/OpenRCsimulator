# Draft, source-read-only outside this file. The caller owns execution and classification.
# One synthetic datum point isolates ground/scenery ordering in a real FlightSession/Simulation tick.
# Airframe aerodynamics, propulsion, gear, prop disc, gravity, rotor momentum and continuous
# dynamics are explicitly disabled. Each RK stage still calls the production HullContact.loads.
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const HullCrossing := preload("res://physics/hull_crossing.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")

const HULL := [0.0, 0.0, 0.0]
const WALL_NEAR_NORTH_M := 0.025
const START_DOWN_M := -0.001
const CLEAR_DOWN_M := -1.0
const NORTH_MPS := 8.0
const DOWN_MPS := 4.0

var checks: int = 0
var failures: int = 0
var assertions: Array[Dictionary] = []


func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
	assertions.append({"label": label, "passed": condition})
	print("%s %s" % ["ok" if condition else "FAIL", label])


func _plain(values: PackedFloat64Array) -> Array:
	var result: Array = []
	for value: float in values:
		result.append(value)
	return result


func _initial(down_m: float) -> PackedFloat64Array:
	return RB.make_state(
		PackedFloat64Array([0.0, 0.0, down_m]),
		PackedFloat64Array([NORTH_MPS, 0.0, DOWN_MPS]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]))


# Uses the production box and broadphase builders. The synthetic wall extends from
# north=0.025..0.045 m, east=-1..1 m, down=-3..1 m; it is terminal at any entering speed.
func _wall_world() -> Dictionary:
	var proxies: Array[Dictionary] = []
	CollisionWorld._add_box_at_down(proxies, "round2:wall", "building", "wall",
		"hard_terminal", WALL_NEAR_NORTH_M + 0.01, 0.0, -1.0, 2.0, 4.0, 0.02, 0.0)
	CollisionWorld._assign_damage_profiles(proxies)
	return {"format": CollisionWorld.FORMAT, "identity": "round2-synthetic-wall-v1",
		"cell_size_m": CollisionWorld.CELL_SIZE_M, "proxies": proxies,
		"bins": CollisionWorld._build_bins(proxies)}


func _run_case(name: String, world: Dictionary, down_m: float, tick_limit: int) -> Dictionary:
	var result: Dictionary = {"name": name, "setup_ok": false, "failure": ""}
	var session: Node = FlightSession.new()
	session.setup()
	root.add_child(session)
	if not session.aircraft.get("ok", false) or session.finite_fuel_is_active() or not session.is_flyable():
		result.failure = "default session unavailable, non-flyable, or uses finite fuel"
		session.free()
		return result
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	session.input_enabled = false
	session.crash_auto_restart = false
	session.soft_hull_contacts = true

	# Deliberately restrict geometry to one point and suppress the distinct gear and
	# propeller guards. This is a numerical isolation fixture, not a stock-aircraft flight.
	var hull: PackedFloat64Array = PackedFloat64Array(HULL)
	session.aircraft.model.crash_hull = hull.duplicate()
	session.aircraft.model.landing_gear = {}
	session._prop_disc = {}
	session._drop_tick_facts()
	session._hull_contact = HullContact.prepare(hull, session.sim.mass, session.sim.inertia)
	if session._hull_contact.is_empty():
		result.failure = "HullContact.prepare refused fixture"
		session.free()
		return result
	# Keep the session's existing stable ID for point zero while making its bound
	# position match the synthetic point; later stock IDs cannot generate contacts.
	var binding_probes: Array = session._contact_bindings.get("hull_probes", [])
	if binding_probes.is_empty():
		result.failure = "session has no existing hull contact binding"
		session.free()
		return result
	binding_probes[0]["position"] = hull.duplicate()

	var prepared: Dictionary = session._hull_contact
	var stages: Array[Dictionary] = []
	var stage_loads := func(body: PackedFloat64Array, stage_time_s: float) -> PackedFloat64Array:
		var loads: PackedFloat64Array = HullContact.loads(body, prepared)
		if loads.is_empty():
			loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		# Diagnostic-only capture; this array is not read by the force law or kernel.
		stages.append({"time_s": stage_time_s, "body": _plain(body), "loads": _plain(loads)})
		return loads

	# Exercise the body-only RK4 route and the session's actual post-tick filter.
	session.sim.gravity = 0.0
	session.sim.continuous = PackedFloat64Array()
	session.sim.model.stage = Callable()
	session.sim.model.stage_rotor_momentum = Callable()
	session.sim.model.block_loads = Callable()
	session.sim.model.block_derivative = Callable()
	session.sim.model.block_aux = Callable()
	session.sim.model.step_policy = Callable()
	session.sim.model.substeps = Callable()
	session.sim.model.substeps_joint = Callable()
	session.sim.model.events.clear()
	session.sim.model.loads = stage_loads
	session.sim.model.pre_tick = func(aux: PackedFloat64Array, _inputs: PackedFloat64Array,
			_dt: float) -> PackedFloat64Array:
		return aux
	session.sim.model.rotor_momentum = func(_aux: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array()
	session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var initial: PackedFloat64Array = _initial(down_m)
	if not session.sim.reset(initial):
		result.failure = "simulation reset refused: " + str(session.sim.fault_reason)
		session.free()
		return result
	if not world.is_empty() and not session.set_collision_world(world):
		result.failure = "session refused synthetic scenery world"
		session.free()
		return result
	stages.clear() # exclude reset evaluation
	session.sim.set_paused(false)
	result.setup_ok = true
	result["initial"] = initial.duplicate()
	result["mass_kg"] = float(session.sim.mass)
	result["inertia"] = session.sim.inertia.duplicate()
	result["prepared"] = prepared.duplicate(true)
	result["dt_s"] = session.sim.dt()
	result["initial_guard_ready"] = session._session_after_input()
	if bool(result.initial_guard_ready):
		for _iteration: int in tick_limit:
			if not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
				break
			session.sim.step()
			if session.crash.is_empty() and session.sim.fault_reason.is_empty():
				# Same guard invoked before the next normal Simulation tick.
				session._session_after_input()
		result["tick"] = int(session.sim.tick)
	result["time_s"] = session.sim.time()
	result["fault"] = str(session.sim.fault_reason)
	result["accepted_body"] = session.sim.state.duplicate()
	result["stages"] = stages.duplicate(true)
	result["crash_trigger"] = ""
	result["crash_rule"] = ""
	result["crash_point_index"] = -1
	var impact: Variant = session.crash.get("impact")
	if impact != null:
		result.crash_trigger = str(impact.trigger)
		result.crash_rule = str(impact.soft_rule)
		result.crash_point_index = int(impact.point_index)
		result["crash_detected_state"] = impact.detected_state.duplicate()
	else:
		result["crash_detected_state"] = PackedFloat64Array()
	session.free()
	return result


func _public_case(input: Dictionary) -> Dictionary:
	var out: Dictionary = input.duplicate(true)
	out.erase("prepared")
	for key: String in ["initial", "inertia", "accepted_body", "crash_detected_state"]:
		if out.has(key) and out[key] is PackedFloat64Array:
			out[key] = _plain(out[key])
	return out


func _initialize() -> void:
	var original_hz: int = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 240
	var world: Dictionary = _wall_world()
	var no_scenery: Dictionary = _run_case("ground_only", {}, START_DOWN_M, 1)
	var combined: Dictionary = _run_case("ground_and_wall", world, START_DOWN_M, 1)
	var ground_clear: Dictionary = _run_case("wall_only_ground_clear", world, CLEAR_DOWN_M, 1)
	Engine.physics_ticks_per_second = 960
	var fine: Dictionary = _run_case("ground_and_wall_960hz", world, START_DOWN_M, 4)
	Engine.physics_ticks_per_second = original_hz

	var fixture_ok: bool = bool(no_scenery.get("setup_ok", false)) \
		and bool(combined.get("setup_ok", false)) and bool(ground_clear.get("setup_ok", false)) \
		and bool(fine.get("setup_ok", false))
	_check("all four isolated sessions prepare", fixture_ok)
	var first_three_ok: bool = fixture_ok
	for result: Dictionary in [no_scenery, combined, ground_clear]:
		first_three_ok = first_three_ok and bool(result.get("initial_guard_ready", false)) \
			and int(result.get("tick", -1)) == 1 and str(result.get("fault", "")) == "" \
			and absf(float(result.get("dt_s", 0.0)) - 1.0 / 240.0) < 1.0e-12
	_check("each 240 Hz case accepts exactly one fault-free tick", first_three_ok)

	var same_stages: bool = fixture_ok and var_to_bytes(no_scenery.get("stages", [])) \
		== var_to_bytes(combined.get("stages", []))
	_check("ground-only and combined runs use identical recorded RK stages", same_stages)
	var maximum_ground_force_n: float = 0.0
	for sample: Dictionary in no_scenery.get("stages", []):
		var loads: Array = sample.get("loads", [])
		if loads.size() == 6:
			maximum_ground_force_n = maxf(maximum_ground_force_n, -float(loads[2]))
	_check("real soft-hull loads are nonzero in an RK stage", maximum_ground_force_n > 0.0)

	var ground: Dictionary = {}
	var crossing_fraction: Variant = null
	var crossing_reason: String = "no_candidate"
	var wall_fraction: Variant = null
	var wall_terminal: bool = false
	var wall_contact: PackedFloat64Array = PackedFloat64Array()
	var ground_at_wall: Dictionary = {}
	if first_three_ok:
		var before: PackedFloat64Array = no_scenery.initial
		# This is an accepted Simulation.step endpoint of a matched no-scenery run,
		# before any scenery filter; it is not manufactured from endpoint interpolation.
		var candidate: PackedFloat64Array = no_scenery.accepted_body
		var prepared: Dictionary = no_scenery.prepared
		ground = HullContact.terminal(before, candidate, prepared)
		var crossing: HullCrossing.Result = HullCrossing.reconstruct(before, candidate,
			PackedFloat64Array(HULL))
		crossing_reason = crossing.reason
		if crossing.available:
			crossing_fraction = crossing.fraction
		var event: SceneryCollision.Event = SceneryCollision.first_hit(before, candidate,
			PackedFloat64Array(HULL), world, 1, float(no_scenery.mass_kg), no_scenery.inertia)
		if event != null:
			wall_fraction = event.time_fraction
			wall_terminal = event.terminal
			wall_contact = event.contact_state()
			ground_at_wall = HullContact.terminal(before, wall_contact, prepared)

	var ground_terminal: bool = int(ground.get("index", -1)) == 0 \
		and str(ground.get("rule", "")) == "impact" \
		and float(ground.get("specific_j_per_kg", 0.0)) >= HullContact.TERMINAL_J_PER_KG
	_check("no-scenery candidate independently meets the hull impact threshold", ground_terminal)
	var separated_order: bool = crossing_fraction != null and wall_fraction != null and wall_terminal \
		and float(crossing_fraction) + 0.1 < float(wall_fraction)
	_check("estimated ground crossing clearly precedes terminal wall crossing", separated_order)
	_check("the wall contact pose independently meets the ground terminal rule",
		int(ground_at_wall.get("index", -1)) == 0 and str(ground_at_wall.get("rule", "")) == "impact")
	_check("ground-only control reports a hull crash", str(no_scenery.get("crash_trigger", "")) == "hull_contact")
	_check("ground-clear control reports a scenery crash", str(ground_clear.get("crash_trigger", "")) == "scenery")
	var fine_ok: bool = bool(fine.get("initial_guard_ready", false)) and int(fine.get("tick", -1)) == 1 \
		and str(fine.get("fault", "")) == "" and str(fine.get("crash_trigger", "")) == "hull_contact" \
		and absf(float(fine.get("dt_s", 0.0)) - 1.0 / 960.0) < 1.0e-12
	_check("960 Hz accepted-tick control reaches terminal ground before the wall", fine_ok)
	var preconditions: bool = fixture_ok and first_three_ok and same_stages \
		and maximum_ground_force_n > 0.0 and ground_terminal and separated_order and fine_ok \
		and int(ground_at_wall.get("index", -1)) == 0 \
		and str(no_scenery.get("crash_trigger", "")) == "hull_contact" \
		and str(ground_clear.get("crash_trigger", "")) == "scenery"
	if preconditions:
		_check("earlier terminal ground wins in combined 240 Hz case",
			str(combined.get("crash_trigger", "")) == "hull_contact")
	else:
		_check("ordering fixture is conclusive", false)

	var report: Dictionary = {
		"fixture": "single datum point, production hull loads and fixed-wing session filter; synthetic wall",
		"limitations": "GDScript reference fixture, no aero/prop/gear/gravity; nlerp crossing is an estimate; not a stock flight",
		"classification": "desired_behavior_pass" if preconditions and str(combined.get("crash_trigger", "")) == "hull_contact" \
			else "desired_behavior_fail" if preconditions else "fixture_inconclusive",
		"ground_crossing_fraction_estimate": crossing_fraction,
		"ground_crossing_reason": crossing_reason,
		"wall_fraction_estimate": wall_fraction,
		"wall_terminal": wall_terminal,
		"ground_terminal_candidate": ground,
		"ground_terminal_at_wall_pose": ground_at_wall,
		"wall_contact_state": _plain(wall_contact),
		"max_rk_stage_ground_force_n": maximum_ground_force_n,
		"checks": checks,
		"failures": failures,
		"assertions": assertions,
		"cases": [_public_case(no_scenery), _public_case(combined), _public_case(ground_clear), _public_case(fine)],
	}
	print("ROUND2_CONTACT_ORDER_JSON " + JSON.stringify(report, "", true, true))
	print("ROUND2_CONTACT_ORDER_COMPLETE %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
