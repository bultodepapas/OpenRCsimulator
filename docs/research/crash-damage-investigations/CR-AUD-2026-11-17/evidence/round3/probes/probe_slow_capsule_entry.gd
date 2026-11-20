# DRAFT ONLY: the caller owns inspection, execution, and classification.
# A single datum probe approaches the isolated production field-tree trunk. Gear,
# propeller, aero, gravity, and unrelated scenery are suppressed. A prescribed body
# force is switched on AFTER the first accepted tick; no state is teleported.
# Scope: a submicron first-tick crossing at 0.1 mm/s, not a stock flight or a
# statement about physical tree geometry or an established collision tolerance.
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")

const HULL := [0.0, 0.0, 0.0]
const SLOW_SPEED_MPS := 0.0001
const FAST_SPEED_MPS := 0.01
const SLOW_CLEARANCE_M := 1.0e-7
const FAST_CLEARANCE_M := 1.0e-5
const ACCELERATION_MPS2 := 4.0
const SLOW_TICKS := 120

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
	var out: Array = []
	for value: float in values:
		out.append(value)
	return out


func _plain_modes(values: PackedInt64Array) -> Array:
	var out: Array = []
	for value: int in values:
		out.append(value)
	return out


func _state(north: float, east: float, down: float, speed: float) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([north, east, down]),
		PackedFloat64Array([speed, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))


func _tree_world() -> Dictionary:
	# Stock tree builder supplies the capsule dimensions and hard-terminal policy;
	# retain only its trunk so the foliage proxy cannot mask the question.
	var parts: Array[Dictionary] = []
	CollisionWorld._add_field_tree_proxies(parts, "round3", 0.0, 0.0, 0.0, 7.0, 0, 0.0)
	var proxies: Array[Dictionary] = []
	for part: Dictionary in parts:
		if str(part.get("part", "")) == "trunk":
			proxies.append(part)
	CollisionWorld._assign_damage_profiles(proxies)
	return {"format": CollisionWorld.FORMAT, "identity": "round3-isolated-field-trunk-v1",
		"cell_size_m": CollisionWorld.CELL_SIZE_M, "proxies": proxies,
		"bins": CollisionWorld._build_bins(proxies)}


# Signed distance to the actual or uniformly padded capsule; negative is inside.
func _gap(body: PackedFloat64Array, proxy: Dictionary, padding: float = 0.0) -> float:
	var dn: float = body[RB.POS] - float(proxy.north)
	var de: float = body[RB.POS + 1] - float(proxy.east)
	var dz: float = body[RB.POS + 2] - float(proxy.down)
	var clamped_z: float = clampf(dz, -float(proxy.half_length), float(proxy.half_length))
	return sqrt(dn * dn + de * de + (dz - clamped_z) * (dz - clamped_z)) \
		- float(proxy.radius) - padding


func _event_summary(event: SceneryCollision.Event) -> Dictionary:
	if event == null:
		return {"hit": false}
	return {"hit": true, "terminal": event.terminal, "trigger": event.trigger,
		"response_class": event.response_class, "fraction": event.time_fraction,
		"normal_speed_mps": event.normal_speed_mps, "point_index": event.point_index,
		"obstacle_id": event.obstacle_id, "point_ned": _plain(event.point_ned)}


func _segment_summary(a: PackedFloat64Array, b: PackedFloat64Array, proxy: Dictionary) -> Dictionary:
	var result: Dictionary = SceneryCollision._segment_capsule(a.slice(RB.POS, RB.POS + 3),
		b.slice(RB.POS, RB.POS + 3), proxy, SceneryCollision.ROTATION_PADDING_EPSILON_M)
	if result.has("normal") and result.normal is PackedFloat64Array:
		result.normal = _plain(result.normal)
	return result


func _run_case(name: String, world: Dictionary, proxy: Dictionary, north: float, east: float,
		speed: float, tick_limit: int, accelerate: bool) -> Dictionary:
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
	var bindings: Array = session._contact_bindings.get("hull_probes", [])
	if bindings.is_empty():
		result.failure = "no existing hull contact binding"
		session.free()
		return result
	bindings[0]["position"] = hull.duplicate()

	var prepared: Dictionary = session._hull_contact
	var forcing: Dictionary = {"north_n": 0.0, "calls": 0, "forced_calls": 0, "max_hull_load": 0.0}
	var stage_loads := func(body: PackedFloat64Array, _stage_time_s: float) -> PackedFloat64Array:
		var loads: PackedFloat64Array = HullContact.loads(body, prepared)
		if loads.is_empty():
			loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		for load: float in loads:
			forcing.max_hull_load = maxf(float(forcing.max_hull_load), absf(load))
		forcing.calls = int(forcing.calls) + 1
		if float(forcing.north_n) > 0.0:
			forcing.forced_calls = int(forcing.forced_calls) + 1
		loads[0] += float(forcing.north_n)
		return loads

	# Same body-only reference route used by the earlier accepted-tick audit draft.
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
	var initial: PackedFloat64Array = _state(north, east, float(proxy.down), speed)
	if not session.sim.reset(initial):
		result.failure = "simulation reset refused: " + str(session.sim.fault_reason)
		session.free()
		return result
	if not world.is_empty() and not session.set_collision_world(world):
		result.failure = "session refused isolated trunk world"
		session.free()
		return result
	forcing.calls = 0
	forcing.forced_calls = 0
	forcing.max_hull_load = 0.0
	session.sim.set_paused(false)
	result.setup_ok = true
	result["initial_guard_ready"] = session._session_after_input()
	result["_initial"] = initial.duplicate()
	result["_first_state"] = PackedFloat64Array()
	result["initial_body"] = _plain(initial)
	result["initial_modes"] = _plain_modes(session.sim.modes)
	result["mass_kg"] = float(session.sim.mass)
	result["_inertia"] = session.sim.inertia.duplicate()
	result["dt_s"] = float(session.sim.dt())
	var history: Array[Dictionary] = []
	if bool(result.initial_guard_ready):
		for iteration: int in tick_limit:
			if not session.crash.is_empty() or not session.sim.fault_reason.is_empty() or session.sim.paused:
				break
			# The first accepted sweep remains at the slow approach speed. The next
			# tick starts with a finite, constant force in the real RK load callback.
			forcing.north_n = float(session.sim.mass) * ACCELERATION_MPS2 if accelerate and iteration > 0 else 0.0
			var before_tick: int = int(session.sim.tick)
			session.sim.step()
			if int(session.sim.tick) != before_tick + 1:
				break
			if iteration == 0:
				result._first_state = session.sim.state.duplicate()
			if session.crash.is_empty() and session.sim.fault_reason.is_empty() and not session.sim.paused:
				session._session_after_input()
			var impact: Variant = session.crash.get("impact")
			var trigger: String = str(impact.trigger) if impact != null else ""
			var event: SceneryCollision.Event = session.last_scenery_event()
			history.append({"tick": int(session.sim.tick), "time_s": float(session.sim.time()),
				"body": _plain(session.sim.state), "modes": _plain_modes(session.sim.modes),
				"gap_m": _gap(session.sim.state, proxy), "force_n": float(forcing.north_n),
				"paused": bool(session.sim.paused), "fault": str(session.sim.fault_reason),
				"crash_trigger": trigger, "scenery_event": _event_summary(event)})
	result["history"] = history
	result["tick"] = int(session.sim.tick)
	result["fault"] = str(session.sim.fault_reason)
	result["forcing"] = forcing.duplicate(true)
	result["paused"] = bool(session.sim.paused)
	result["crash_trigger"] = ""
	var final_impact: Variant = session.crash.get("impact")
	if final_impact != null:
		result.crash_trigger = str(final_impact.trigger)
	result["last_scenery_event"] = _event_summary(session.last_scenery_event())
	session.free()
	return result


func _public_case(input: Dictionary) -> Dictionary:
	var out: Dictionary = input.duplicate(true)
	out.erase("_initial")
	out.erase("_first_state")
	out.erase("_inertia")
	return out


func _far_face_tick(result: Dictionary, proxy: Dictionary) -> int:
	for entry: Dictionary in result.get("history", []):
		var body: Array = entry.body
		if float(body[RB.POS]) > float(proxy.north) + float(proxy.radius):
			return int(entry.tick)
	return -1


func _initialize() -> void:
	var original_hz: int = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 240
	var world: Dictionary = _tree_world()
	var proxies: Array = world.proxies
	_check("tree builder supplies one binned hard-terminal capsule",
		proxies.size() == 1 and not world.bins.is_empty() and str(proxies[0].shape) == "capsule" \
		and str(proxies[0].kind) == "tree_trunk" and str(proxies[0].response_class) == "hard_terminal")
	if proxies.size() != 1:
		print("ROUND3_SLOW_CAPSULE_COMPLETE fixture_inconclusive %d checks, %d failures" % [checks, failures])
		Engine.physics_ticks_per_second = original_hz
		quit(1)
		return
	var proxy: Dictionary = proxies[0]
	var near_face: float = float(proxy.north) - float(proxy.radius)
	var slow_north: float = near_face - SLOW_CLEARANCE_M
	var fast_north: float = near_face - FAST_CLEARANCE_M
	var slow_clear: Dictionary = _run_case("slow_no_obstacle", {}, proxy, slow_north,
		float(proxy.east), SLOW_SPEED_MPS, SLOW_TICKS, true)
	var slow_world: Dictionary = _run_case("slow_trunk", world, proxy, slow_north,
		float(proxy.east), SLOW_SPEED_MPS, SLOW_TICKS, true)
	var fast_clear: Dictionary = _run_case("fast_no_obstacle", {}, proxy, fast_north,
		float(proxy.east), FAST_SPEED_MPS, 1, false)
	var fast_world: Dictionary = _run_case("fast_trunk", world, proxy, fast_north,
		float(proxy.east), FAST_SPEED_MPS, 1, false)
	var outward: Dictionary = _run_case("outward_trunk", world, proxy, fast_north,
		float(proxy.east), -FAST_SPEED_MPS, 1, false)
	var clear: Dictionary = _run_case("side_clear_trunk", world, proxy, fast_north,
		float(proxy.east) + float(proxy.radius) + 0.05, FAST_SPEED_MPS, 1, false)
	Engine.physics_ticks_per_second = original_hz

	var cases: Array[Dictionary] = [slow_clear, slow_world, fast_clear, fast_world, outward, clear]
	var setups_ok: bool = true
	for item: Dictionary in cases:
		setups_ok = setups_ok and bool(item.get("setup_ok", false)) \
			and bool(item.get("initial_guard_ready", false)) and str(item.get("fault", "")) == "" \
			and absf(float(item.get("dt_s", 0.0)) - 1.0 / 240.0) < 1.0e-12
	_check("all six isolated reference sessions prepare at 240 Hz without faults", setups_ok)
	var slow_ready: bool = setups_ok and int(slow_clear.get("tick", -1)) == SLOW_TICKS \
		and int(slow_world.get("tick", -1)) >= 1
	var first: PackedFloat64Array = slow_clear.get("_first_state", PackedFloat64Array())
	var before: PackedFloat64Array = slow_clear.get("_initial", PackedFloat64Array())
	var fast_before: PackedFloat64Array = fast_clear.get("_initial", PackedFloat64Array())
	var fast_after: PackedFloat64Array = fast_clear.get("_first_state", PackedFloat64Array())
	var states_ok: bool = before.size() == RB.SIZE and first.size() == RB.SIZE \
		and fast_before.size() == RB.SIZE and fast_after.size() == RB.SIZE
	_check("unobstructed controls accept the required initial candidate states", slow_ready and states_ok \
		and int(fast_clear.get("tick", -1)) == 1)

	var actual_before: float = 0.0
	var actual_after: float = 0.0
	var padded_before: float = 0.0
	var padded_after: float = 0.0
	var displacement_sq: float = 0.0
	var estimated_fraction: float = -1.0
	var broadphase: Array[int] = []
	var aabb_overlap: bool = false
	var slow_segment: Dictionary = {}
	var fast_segment: Dictionary = {}
	var slow_event: SceneryCollision.Event = null
	var fast_event: SceneryCollision.Event = null
	if states_ok:
		actual_before = _gap(before, proxy)
		actual_after = _gap(first, proxy)
		padded_before = _gap(before, proxy, SceneryCollision.ROTATION_PADDING_EPSILON_M)
		padded_after = _gap(first, proxy, SceneryCollision.ROTATION_PADDING_EPSILON_M)
		var dn: float = first[RB.POS] - before[RB.POS]
		var de: float = first[RB.POS + 1] - before[RB.POS + 1]
		var dd: float = first[RB.POS + 2] - before[RB.POS + 2]
		displacement_sq = dn * dn + de * de + dd * dd
		if dn > 0.0:
			estimated_fraction = padded_before / dn
		var padding: float = SceneryCollision.ROTATION_PADDING_EPSILON_M
		var min_n: float = minf(before[RB.POS], first[RB.POS])
		var max_n: float = maxf(before[RB.POS], first[RB.POS])
		broadphase = SceneryCollision._candidate_indices(world, min_n, max_n, before[RB.POS + 1],
			first[RB.POS + 1], before[RB.POS + 2], first[RB.POS + 2])
		aabb_overlap = SceneryCollision._aabb_overlap(proxy, min_n - padding, max_n + padding,
			before[RB.POS + 1] - padding, first[RB.POS + 1] + padding,
			before[RB.POS + 2] - padding, first[RB.POS + 2] + padding)
		slow_segment = _segment_summary(before, first, proxy)
		fast_segment = _segment_summary(fast_before, fast_after, proxy)
		slow_event = SceneryCollision.first_hit(before, first, PackedFloat64Array(HULL), world, 1,
			float(slow_clear.mass_kg), slow_clear._inertia)
		fast_event = SceneryCollision.first_hit(fast_before, fast_after, PackedFloat64Array(HULL), world, 1,
			float(fast_clear.mass_kg), fast_clear._inertia)

	var straddles: bool = states_ok and actual_before > 0.0 and actual_after < 0.0 \
		and padded_before > 0.0 and padded_after < 0.0 and estimated_fraction > 0.0 and estimated_fraction < 1.0
	_check("first slow candidate starts outside both capsules and crosses both", straddles)
	var under_epsilon: bool = states_ok and displacement_sq > 0.0 \
		and displacement_sq < SceneryCollision.GEOMETRY_EPSILON
	_check("first slow displacement squared is below the capsule solver threshold", under_epsilon)
	_check("the trunk passes the swept-bin and padded AABB gates", broadphase.has(0) and aabb_overlap)
	var fast_detected: bool = fast_event != null and fast_event.terminal \
		and fast_event.response_class == "hard_terminal" and fast_event.normal_speed_mps > 0.0 \
		and fast_event.normal_speed_mps < SceneryCollision.MIN_RESPONSE_NORMAL_SPEED_MPS
	var fast_session_ok: bool = str(fast_world.get("crash_trigger", "")) == "scenery" \
		and int(fast_world.get("tick", -1)) == 1 and bool(fast_world.get("paused", false))
	_check("faster external entry hits the same hard trunk in detector and accepted tick", fast_detected and fast_session_ok)
	var negative_controls_ok: bool = true
	for item: Dictionary in [outward, clear]:
		negative_controls_ok = negative_controls_ok and int(item.get("tick", -1)) == 1 \
			and str(item.get("crash_trigger", "")) == "" \
			and not bool(item.get("last_scenery_event", {}).get("hit", false))
	_check("outward and side-clear controls accept without scenery contact", negative_controls_ok)
	var clear_history: Array = slow_clear.get("history", [])
	var force_ok: bool = clear_history.size() == SLOW_TICKS and float(slow_clear.get("mass_kg", 0.0)) > 0.0
	if force_ok:
		var force_n: float = float(slow_clear.mass_kg) * ACCELERATION_MPS2
		force_ok = float(clear_history[0].force_n) == 0.0 \
			and absf(float(clear_history[1].force_n) - force_n) < 1.0e-12 \
			and int(slow_clear.forcing.forced_calls) > 0 \
			and float(slow_clear.forcing.max_hull_load) == 0.0
		var final_body: Array = clear_history.back().body
		var expected_speed: float = SLOW_SPEED_MPS + ACCELERATION_MPS2 * float(SLOW_TICKS - 1) / 240.0
		force_ok = force_ok and absf(float(final_body[RB.VEL]) - expected_speed) < 1.0e-9
	var clear_far_face: int = _far_face_tick(slow_clear, proxy)
	_check("matched no-obstacle run integrates the later force and crosses the far face", force_ok and clear_far_face > 1)
	var same_initial: bool = states_ok and var_to_bytes(before) == var_to_bytes(slow_world.get("_initial"))
	_check("slow trunk and no-obstacle runs begin with identical accepted body state", same_initial)

	var preconditions: bool = setups_ok and slow_ready and states_ok and straddles and under_epsilon \
		and broadphase.has(0) and aabb_overlap and fast_detected and fast_session_ok \
		and negative_controls_ok and force_ok and clear_far_face > 1 and same_initial
	if preconditions:
		_check("direct detector reports the slow hard-terminal entry", slow_event != null and slow_event.terminal)
		_check("accepted first tick reports the slow hard-terminal entry",
			str(slow_world.get("crash_trigger", "")) == "scenery" and int(slow_world.get("tick", -1)) == 1)
	else:
		_check("fixture establishes the hard-entry comparison", false)

	var world_far_face: int = _far_face_tick(slow_world, proxy)
	var same_trajectory: bool = var_to_bytes(slow_clear.get("history", [])) == var_to_bytes(slow_world.get("history", []))
	var report: Dictionary = {
		"fixture": "fixed-wing reference FlightSession and accepted Simulation steps; one datum point; isolated production field-tree trunk",
		"limits": "synthetic body-only load fixture, no aero/gravity/gear/prop/foliage; 0.1 mm/s entry with 0.1 micrometre initial clearance; not a stock flight or a qualified collision-tolerance requirement",
		"classification": "desired_behavior_pass" if preconditions and slow_event != null \
			and str(slow_world.get("crash_trigger", "")) == "scenery" and int(slow_world.get("tick", -1)) == 1 \
			else "desired_behavior_fail" if preconditions else "fixture_inconclusive",
		"proxy": proxy, "padding_m": SceneryCollision.ROTATION_PADDING_EPSILON_M,
		"geometry_epsilon_m2": SceneryCollision.GEOMETRY_EPSILON,
		"slow_actual_gap_before_m": actual_before, "slow_actual_gap_after_m": actual_after,
		"slow_padded_gap_before_m": padded_before, "slow_padded_gap_after_m": padded_after,
		"slow_first_displacement_sq_m2": displacement_sq, "analytic_padded_entry_fraction": estimated_fraction,
		"broadphase_indices": broadphase, "padded_aabb_overlap": aabb_overlap,
		"slow_segment": slow_segment, "fast_segment": fast_segment,
		"slow_direct_event": _event_summary(slow_event), "fast_direct_event": _event_summary(fast_event),
		"slow_no_obstacle_far_face_tick": clear_far_face, "slow_trunk_far_face_tick": world_far_face,
		"entire_accepted_histories_identical": same_trajectory,
		"checks": checks, "failures": failures, "assertions": assertions,
		"cases": [_public_case(slow_clear), _public_case(slow_world), _public_case(fast_clear),
			_public_case(fast_world), _public_case(outward), _public_case(clear)],
	}
	print("ROUND3_SLOW_CAPSULE_JSON " + JSON.stringify(report, "", true, true))
	print("ROUND3_SLOW_CAPSULE_COMPLETE %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
