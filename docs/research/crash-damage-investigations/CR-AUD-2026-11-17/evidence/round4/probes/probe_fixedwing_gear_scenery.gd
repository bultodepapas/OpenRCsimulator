# DRAFT ONLY: the lead owns execution, source-identity checks and classification.
# Stock Avanti, actual runway initialization and ordinary session loads. A synthetic
# finite hard box is placed across one deployed wheel's reference-point path.
# A point entering the box is not a complete wheel-solid intersection model.
# Run this script from a properly imported disposable source mirror, not in-place.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Ground := preload("res://physics/ground_contact.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const World := preload("res://scenery/collision_world.gd")
const Scenery := preload("res://sim/scenery_collision.gd")

const AIRCRAFT := "res://data/aircraft/sebart_avanti_s_a200.json"
const HZ := 240
const SPEED_MPS := 3.0
const TICK_LIMIT := 80
const BOX_FORWARD_M := 0.30
const BOX_WIDTH_M := 0.10
const BOX_LENGTH_M := 0.08
const BOX_HEIGHT_M := 0.10

var checks := 0
var failures := 0
var assertions: Array[Dictionary] = []


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	assertions.append({"label": label, "passed": passed})
	print("%s %s" % ["ok" if passed else "FAIL", label])


func _plain(a: PackedFloat64Array) -> Array:
	return Array(a)


func _world_point(s: PackedFloat64Array, p: PackedFloat64Array) -> PackedFloat64Array:
	return M.add(s.slice(RB.POS, RB.POS + 3), M.q_rotate(RB._att(s), p))


# Signed L-infinity face clearance; negative means strictly inside the box.
func _box_gap(point: PackedFloat64Array, proxy: Dictionary) -> float:
	var local: PackedFloat64Array = Scenery._world_to_box(point, proxy)
	return maxf(maxf(absf(local[0]) - float(proxy.half_x),
		absf(local[1]) - float(proxy.half_down)), absf(local[2]) - float(proxy.half_z))


func _local_along(point: PackedFloat64Array, proxy: Dictionary) -> float:
	return float(Scenery._world_to_box(point, proxy)[2])


func _make_world(name: String, start: PackedFloat64Array, forward: PackedFloat64Array) -> Dictionary:
	var n: float = start[0] + BOX_FORWARD_M * forward[0]
	var e: float = start[1] + BOX_FORWARD_M * forward[1]
	# For the gear fixture this spans the ground plane and extends a little below it,
	# so the undeformed (compressed) wheel-bottom reference can pass through it.
	var d: float = start[2] - 0.005
	var heading_deg: float = rad_to_deg(atan2(forward[1], forward[0]))
	var proxies: Array[Dictionary] = []
	World._add_box_at_down(proxies, name, "fixture", "audit_box", "hard_terminal",
		n, e, d, BOX_WIDTH_M, BOX_HEIGHT_M, BOX_LENGTH_M, heading_deg)
	World._assign_damage_profiles(proxies)
	var bins: Dictionary = World._build_bins(proxies)
	return {"format": World.FORMAT, "identity": name,
		"cell_size_m": World.CELL_SIZE_M, "proxies": proxies, "bins": bins}


func _event(e: Scenery.Event) -> Dictionary:
	if e == null:
		return {"hit": false}
	return {"hit": true, "terminal": bool(e.terminal), "trigger": str(e.trigger),
		"fraction": float(e.time_fraction), "point_index": int(e.point_index),
		"point_ned": _plain(e.point_ned), "normal_speed_mps": float(e.normal_speed_mps),
		"obstacle_id": str(e.obstacle_id), "response_status": str(e.response_status)}


# Mirrors the repository's Avanti runway setup and stopped-engine 3 m/s test.
# No integrator, force, gravity, collision or aircraft-geometry callbacks are replaced.
func _new_session() -> Dictionary:
	var session: Node = Flight.new()
	session.soft_hull_contacts = true
	session.crash_auto_restart = false
	session.setup(AIRCRAFT)
	root.add_child(session)
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	if not session.aircraft.get("ok", false) or not session.is_flyable():
		return {"ok": false, "session": session, "reason": "stock aircraft did not load or is not flyable"}
	var loaded: Dictionary = FieldLoader.load_from()
	if not loaded.get("ok", false) or not session.set_field(loaded.field):
		return {"ok": false, "session": session, "reason": "default field refused"}
	var spot: Dictionary = GroundStart.threshold(loaded.field)
	if not spot.get("ok", false) or not session.reset_on_runway(spot.north, spot.east, spot.heading):
		return {"ok": false, "session": session, "reason": "runway reset refused: " + str(session.start_error)}
	if not session.gear_is_retractable() or float(session.gear_state().get("extension", -1.0)) != 1.0:
		return {"ok": false, "session": session, "reason": "runway gear is not downlocked"}
	session.engine_running = false
	var aux: PackedFloat64Array = session.sim.aux.duplicate()
	aux[Flight.AUX_RPM] = 0.0
	for i: int in session.anchor_count():
		aux[Flight.AUX_ANCHORS + i * Ground.ANCHOR_STRIDE + 2] = 0.0
	session.sim.aux = aux
	var continuous: PackedFloat64Array = session.sim.continuous.duplicate()
	if not continuous.is_empty():
		continuous[session._rotor_index()] = 0.0
	for i: int in session.wheel_count():
		continuous[session.wheel_index() + i] = SPEED_MPS
	session.sim.continuous = continuous
	var state: PackedFloat64Array = session.sim.state.duplicate()
	state[RB.VEL] = SPEED_MPS
	session.sim.state = state.duplicate()
	session.sim.previous = state.duplicate()
	session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0])
	session.input_enabled = false
	session.sim.set_paused(false)
	return {"ok": true, "session": session, "reason": ""}


func _finish_failed_setup(result: Dictionary) -> void:
	if result.get("session") != null:
		result.session.free()


func _hull_clearance(s: PackedFloat64Array, hull: PackedFloat64Array, proxy: Dictionary) -> float:
	var minimum: float = INF
	for at: int in range(0, hull.size(), 3):
		minimum = minf(minimum, _box_gap(_world_point(s, hull.slice(at, at + 3)), proxy))
	return minimum


func _run(name: String, session: Node, installed: Dictionary, reference: Dictionary,
		gear_point: PackedFloat64Array) -> Dictionary:
	var result: Dictionary = {"name": name, "setup_ok": false, "reason": "", "history": []}
	if not installed.is_empty() and not session.set_collision_world(installed):
		result.reason = "world installation refused"
		return result
	var proxy: Dictionary = reference.proxies[0]
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var initial: PackedFloat64Array = session.sim.state.duplicate()
	var point: PackedFloat64Array = _world_point(initial, gear_point)
	var initial_local_along: float = _local_along(point, proxy)
	var wheel_inside := false
	var wheel_exited := false
	var direct_entry := {"hit": false}
	var minimum_wheel_gap: float = _box_gap(point, proxy)
	var minimum_sampled_hull_gap: float = _hull_clearance(initial, hull, proxy)
	var min_endpoint_gear_fraction: float = 1.0
	var first_direct_tick := -1
	result["initial_state"] = _plain(initial)
	result["initial_wheel_point"] = _plain(point)
	result["initial_wheel_along"] = initial_local_along
	result["initial_wheel_gap"] = minimum_wheel_gap
	result["initial_hull_gap"] = minimum_sampled_hull_gap
	result["gear_point_body"] = _plain(gear_point)
	result["gravity_mps2"] = float(session.sim.gravity)
	result["force_callbacks"] = {"loads": session.sim.model.loads.is_valid(),
		"stage": session.sim.model.stage.is_valid(), "block_loads": session.sim.model.block_loads.is_valid(),
		"post_tick": session.sim.model.post_tick.is_valid(),
		"post_tick_joint": session.sim.model.post_tick_joint.is_valid()}
	result["setup_ok"] = true
	for _iteration: int in TICK_LIMIT:
		if session.sim.paused or not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
			break
		if not session._session_after_input():
			break
		var previous: PackedFloat64Array = session.sim.state.duplicate()
		var before_tick: int = int(session.sim.tick)
		session.sim.step()
		if int(session.sim.tick) != before_tick + 1:
			break
		var current: PackedFloat64Array = session.sim.state.duplicate()
		point = _world_point(current, gear_point)
		var gap: float = _box_gap(point, proxy)
		minimum_wheel_gap = minf(minimum_wheel_gap, gap)
		var along: float = _local_along(point, proxy)
		if gap < -0.001:
			wheel_inside = true
		if wheel_inside and along < -float(proxy.half_z) - 0.001:
			wheel_exited = true
		# Check every hull point at five interpolation fractions in each accepted
		# interval. The exact direct scenery sweep below is a separate control.
		for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var sample: PackedFloat64Array = Scenery.state_at_fraction(previous, current, fraction)
			minimum_sampled_hull_gap = minf(minimum_sampled_hull_gap, _hull_clearance(sample, hull, proxy))
		if not direct_entry.hit:
			var hit: Scenery.Event = Scenery.first_hit(previous, current, gear_point, reference,
				int(session.sim.tick), float(session.sim.mass), session.sim.inertia)
			if hit != null:
				direct_entry = _event(hit)
				first_direct_tick = int(session.sim.tick)
		var actual: Scenery.Event = session.last_scenery_event()
		var gear: Dictionary = session.gear_state()
		min_endpoint_gear_fraction = minf(min_endpoint_gear_fraction, float(gear.get("extension", -1.0)))
		var impact: Variant = session.crash.get("impact")
		var row := {"tick": int(session.sim.tick), "body": _plain(current),
			"aux": _plain(session.sim.aux), "continuous": _plain(session.sim.continuous),
			"modes": Array(session.sim.modes), "wheel_point": _plain(point),
			"wheel_gap": gap, "wheel_along": along,
			"gear_extension": float(gear.get("extension", -1.0)),
			"compressions": _plain(session.gear_compressions(current)),
			"contact_events": session.contact_events(), "scenery_event": _event(actual),
			"crash_trigger": str(impact.trigger) if impact != null else "",
			"paused": bool(session.sim.paused), "fault": str(session.sim.fault_reason)}
		result.history.append(row)
		if name == "hull_positive" and actual != null:
			break
	result["tick"] = int(session.sim.tick)
	result["fault"] = str(session.sim.fault_reason)
	result["paused"] = bool(session.sim.paused)
	result["minimum_wheel_gap"] = minimum_wheel_gap
	result["minimum_sampled_hull_gap"] = minimum_sampled_hull_gap
	result["minimum_gear_fraction"] = min_endpoint_gear_fraction
	result["wheel_inside"] = wheel_inside
	result["wheel_exited_far_face"] = wheel_exited
	result["first_direct_gear_event"] = direct_entry
	result["first_direct_gear_tick"] = first_direct_tick
	result["last_scenery_event"] = _event(session.last_scenery_event())
	var impact: Variant = session.crash.get("impact")
	result["crash_trigger"] = str(impact.trigger) if impact != null else ""
	return result


func _initialize() -> void:
	var old_hz: int = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = HZ
	var a: Dictionary = _new_session()
	var b: Dictionary = _new_session()
	var c: Dictionary = _new_session()
	_check("all stock Avanti runway sessions initialize", a.ok and b.ok and c.ok)
	if not a.ok or not b.ok or not c.ok:
		print("SETUP_DETAIL ", JSON.stringify([a.get("reason", ""), b.get("reason", ""), c.get("reason", "")]))
		_finish_failed_setup(a)
		_finish_failed_setup(b)
		_finish_failed_setup(c)
		Engine.physics_ticks_per_second = old_hz
		quit(1)
		return
	var base: Node = a.session
	var initial: PackedFloat64Array = base.sim.state.duplicate()
	var gear: Dictionary = base.current_landing_gear()
	var gear_index := -1
	for i: int in gear.contacts.size():
		if str(gear.contacts[i].get("name", "")) == "nose":
			gear_index = i
			break
	_check("stock nose wheel contact exists", gear_index >= 0)
	if gear_index < 0:
		_finish_failed_setup(a)
		_finish_failed_setup(b)
		_finish_failed_setup(c)
		Engine.physics_ticks_per_second = old_hz
		quit(1)
		return
	var gear_point: PackedFloat64Array = gear.contacts[gear_index].position.duplicate()
	var nose: PackedFloat64Array = _world_point(initial, gear_point)
	var forward: PackedFloat64Array = M.q_rotate(RB._att(initial), PackedFloat64Array([1.0, 0.0, 0.0]))
	var horizontal: float = sqrt(forward[0] * forward[0] + forward[1] * forward[1])
	if horizontal <= 0.0:
		_check("runway heading has horizontal forward direction", false)
		_finish_failed_setup(a)
		_finish_failed_setup(b)
		_finish_failed_setup(c)
		Engine.physics_ticks_per_second = old_hz
		quit(1)
		return
	forward = PackedFloat64Array([forward[0] / horizontal, forward[1] / horizontal, 0.0])
	var gear_world: Dictionary = _make_world("round4-wheel-box", nose, forward)
	var hull: PackedFloat64Array = base.aircraft.model.crash_hull
	var lowest_index := -1
	var lowest_down := -INF
	for at: int in range(0, hull.size(), 3):
		var p: PackedFloat64Array = _world_point(initial, hull.slice(at, at + 3))
		if p[2] > lowest_down:
			lowest_down = p[2]
			lowest_index = at / 3
	var positive_point: PackedFloat64Array = _world_point(initial, hull.slice(3 * lowest_index, 3 * lowest_index + 3))
	var positive_world: Dictionary = _make_world("round4-hull-box", positive_point, forward)
	_check("both synthetic boxes have bounded production bins", not gear_world.bins.is_empty() and not positive_world.bins.is_empty())
	_check("control sessions have identical injected starting frames", var_to_bytes(base.sim.state) == var_to_bytes(b.session.sim.state)
		and var_to_bytes(base.sim.state) == var_to_bytes(c.session.sim.state)
		and var_to_bytes(base.sim.aux) == var_to_bytes(b.session.sim.aux)
		and var_to_bytes(base.sim.aux) == var_to_bytes(c.session.sim.aux)
		and var_to_bytes(base.sim.continuous) == var_to_bytes(b.session.sim.continuous)
		and var_to_bytes(base.sim.continuous) == var_to_bytes(c.session.sim.continuous))
	var clear: Dictionary = _run("no_box", a.session, {}, gear_world, gear_point)
	var wheel: Dictionary = _run("gear_box", b.session, gear_world, gear_world, gear_point)
	var positive: Dictionary = _run("hull_positive", c.session, positive_world, positive_world, gear_point)
	_check("all three runs install their intended context", clear.setup_ok and wheel.setup_ok and positive.setup_ok)
	if not clear.setup_ok or not wheel.setup_ok or not positive.setup_ok:
		print("RUN_SETUP_DETAIL ", JSON.stringify([clear.reason, wheel.reason, positive.reason]))
		_finish_failed_setup(a)
		_finish_failed_setup(b)
		_finish_failed_setup(c)
		Engine.physics_ticks_per_second = old_hz
		quit(1)
		return
	_check("nose starts outside before the obstacle's near face", float(wheel.initial_wheel_along) > float(gear_world.proxies[0].half_z) + 0.01)
	_check("all hull probes start clear of the positive-control box", float(positive.initial_hull_gap) > 0.001)
	_check("gear point enters, penetrates and exits the finite unpadded box", wheel.wheel_inside and wheel.wheel_exited_far_face and float(wheel.minimum_wheel_gap) < -0.001)
	_check("independent production sweep sees the true gear-point entry", bool(wheel.first_direct_gear_event.hit)
		and bool(wheel.first_direct_gear_event.get("terminal", false)))
	_check("sampled full-hull points stay clear of the wheel box", float(wheel.minimum_sampled_hull_gap) > 0.001)
	_check("downlock remains engaged throughout the tested accepted trajectory", float(wheel.minimum_gear_fraction) == 1.0)
	_check("box and no-box accepted histories are byte-identical and do not crash", var_to_bytes(clear.history) == var_to_bytes(wheel.history)
		and wheel.fault.is_empty() and wheel.crash_trigger.is_empty() and not wheel.last_scenery_event.hit)
	_check("the hull-path positive control produces an accepted terminal scenery event", positive.last_scenery_event.hit
		and positive.last_scenery_event.terminal and positive.crash_trigger == "scenery")
	var conclusive: bool = wheel.wheel_inside and wheel.wheel_exited_far_face \
		and bool(wheel.first_direct_gear_event.hit) and float(wheel.minimum_sampled_hull_gap) > 0.001 \
		and float(wheel.minimum_gear_fraction) == 1.0 and wheel.fault.is_empty() \
		and positive.last_scenery_event.hit and positive.crash_trigger == "scenery"
	if conclusive:
		_check("gear-only obstacle entry reaches a session contact or response", \
			wheel.last_scenery_event.hit or not wheel.crash_trigger.is_empty() \
			or var_to_bytes(clear.history) != var_to_bytes(wheel.history))
	else:
		_check("fixture establishes a gear-only obstacle comparison", false)
	var summary := {"fixture": "stock Avanti, ordinary 240 Hz runway session, stopped engine and 3 m/s injected start",
		"limits": "synthetic box and prescribed initial taxi state; wheel-bottom reference point is not a complete finite wheel solid",
		"gear_contact_index": gear_index, "hull_positive_index": lowest_index,
		"gear_box": gear_world.proxies[0], "hull_box": positive_world.proxies[0],
		"checks": checks, "failures": failures, "assertions": assertions,
		"cases": [clear, wheel, positive]}
	print("ROUND4_GEAR_SCENERY_JSON " + JSON.stringify(summary, "", true, true))
	print("ROUND4_GEAR_SCENERY_COMPLETE %d checks, %d failures" % [checks, failures])
	_finish_failed_setup(a)
	_finish_failed_setup(b)
	_finish_failed_setup(c)
	Engine.physics_ticks_per_second = old_hz
	quit(1 if failures > 0 else 0)
