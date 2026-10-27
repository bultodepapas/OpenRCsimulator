# CR-01c: real flight scene, detector and render consumers; no simulation writes from presentation.
extends SceneTree
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const HullContact = preload("res://physics/hull_contact.gd")
const Frames = preload("res://render/frames.gd")
const Shadow = preload("res://render/shadow.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Scripted = preload("res://sim/scripted.gd")
var _count: int = 0
var _failures: int = 0

func _check(label: String, ok: bool) -> void:
	_count += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ")+label)

func _initialize() -> void:
	_run.call_deferred()

func _state(down: float) -> PackedFloat64Array:
	return RB.make_state(M.v3(0,-15,down),M.v3(8,0,3),M.q_from_euler(.4,.3,.6),M.v3(.2,.3,.4))

func _pose_equal(a: Dictionary, b: Dictionary) -> bool:
	return a.pos == b.pos and a.basis == b.basis

func _ordinary_pose_equal(a: Dictionary, b: Dictionary) -> bool:
	# Ordinary interpolation normalizes the quaternion, even when both states are equal.
	# AV-17: the corrected Vantage Jet trim exposes a 2.22e-16 basis residual near zero.
	# Retain exact position and simulation-state checks; only allow roundoff in this basis.
	if a.pos != b.pos:
		return false
	for axis in 3:
		var delta: float = (a.basis[axis] - b.basis[axis]).length()
		if not is_finite(delta) or delta > 1e-12:
			return false
	return true

func _place_hull_contact(session: Node, penetration_m: float, down_speed_mps: float) -> PackedFloat64Array:
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var attitude: PackedFloat64Array = state.slice(RB.ATT, RB.ATT + 4)
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var deepest_down := -INF
	for index in range(0, hull.size(), 3):
		var point := PackedFloat64Array([hull[index], hull[index + 1], hull[index + 2]])
		deepest_down = maxf(deepest_down, M.q_rotate(attitude, point)[2])
	state[RB.POS + 2] = -deepest_down + penetration_m
	var velocity_body := M.q_rotate(M.q_conj(attitude), PackedFloat64Array([0.0, 0.0, down_speed_mps]))
	for axis in 3:
		state[RB.VEL + axis] = velocity_body[axis]
		state[RB.RATE + axis] = 0.0
	return state

func _tick_before_contact(state: PackedFloat64Array) -> PackedFloat64Array:
	var previous := state.duplicate()
	previous[RB.POS + 2] -= 0.01
	return previous

func _accepted_contact_tick(session: Node, previous: PackedFloat64Array, aircraft_id: String) -> int:
	var tick_before: int = session.sim.tick
	session.sim.state = previous.duplicate()
	session.sim.previous = previous.duplicate()
	session.sim.set_paused(false)
	session.sim.step()
	var accepted_tick: int = session.sim.tick
	# Non-Glow terminal hull decisions are classified by FlightSession after the accepted dynamics tick.
	if session.crash.is_empty():
		session._physics_process(session.sim.dt())
	_check(aircraft_id + " contact is classified on one accepted, fault-free tick",
		accepted_tick == tick_before + 1 and session.sim.tick == accepted_tick
			and session.sim.fault_reason.is_empty() and not session.crash.is_empty()
			and session.crash.impact.trigger == "hull_contact" and session.crash.impact.tick == accepted_tick)
	return accepted_tick

func _observation(sim: Node) -> Array:
	return [sim.state.duplicate(),sim.previous.duplicate(),sim.aux.duplicate(),sim.continuous.duplicate(),sim.inputs.duplicate(),sim.tick,sim.paused]

func _run() -> void:
	_check("ordinary pose comparison rejects a real attitude change", not _ordinary_pose_equal(
		{pos = Vector3.ZERO, basis = Basis.IDENTITY},
		{pos = Vector3.ZERO, basis = Basis(Vector3.RIGHT, 1e-6)}))
	_check("ordinary pose comparison rejects a nonfinite attitude", not _ordinary_pose_equal(
		{pos = Vector3.ZERO, basis = Basis.IDENTITY},
		{pos = Vector3.ZERO, basis = Basis(Vector3(NAN, 0, 0), Vector3.UP, Vector3.BACK)}))
	for entry: Dictionary in Catalog.airplane_flyable_entries(): # TT-06: a preview refuses the flight scene (main.gd)
		var flight: Node = load("res://main.tscn").instantiate()
		flight.aircraft_id = entry.id
		flight.crash_effects_enabled = false # CR-01 diagnostic pose and legacy timer fixture
		flight.accident_reports_enabled = false # CR-30 reports intentionally disable automatic restart.
		root.add_child(flight)
		flight.set_process(false)
		var session: Node = flight.session
		session.set_physics_process(false)
		session.sim.set_physics_process(false)
		session.input_enabled = false
		var start: PackedFloat64Array = session.sim.state.duplicate()
		var checkpoint: Dictionary = session.checkpoint()
		# A one-centimetre clear state reaches a real contact through Simulation.step.
		var contact_state: PackedFloat64Array = _place_hull_contact(session, 0.001, 20.0)
		var previous_contact: PackedFloat64Array = _tick_before_contact(contact_state)
		var detected_tick: int = _accepted_contact_tick(session, previous_contact, entry.id)
		_check(entry.id+" actual hull crash has an available crossing", not session.crash.is_empty()
			and session.crash.impact.crossing != null and session.crash.impact.crossing.available)
		if session.crash.is_empty() or session.crash.impact.crossing == null or not session.crash.impact.crossing.available:
			flight.free()
			continue
		var crossing: RefCounted = session.crash.impact.crossing
		_check(entry.id+" render event records the accepted tick", session.crash.impact.tick == detected_tick)
		var before: Array = _observation(session.sim)
		flight._process(1.0/60.0)
		var pose: Dictionary = flight._last_render_pose
		var expected_pos: Vector3 = Frames.ned_to_render(Array(crossing.position_ned))
		var expected_basis: Basis = Frames.quat_to_render(crossing.attitude)
		_check(entry.id+" rendered CG and attitude use crossing", pose.pos == expected_pos and pose.basis == expected_basis)
		var detected_pos: Vector3 = Frames.ned_to_render(Array(session.crash.impact.detected_state.slice(RB.POS, RB.POS + 3)))
		var endpoint_separation: float = expected_pos.distance_to(detected_pos)
		_check(entry.id+" crossing pose is distinct from the accepted endpoint (%.6f m)" % endpoint_separation,
			endpoint_separation > 0.02)
		var cg: Vector3 = flight._airplane.root.transform * flight._cg_model
		_check(entry.id+" model origin preserves crossing CG", cg.distance_to(expected_pos) < 2e-6)
		var r: PackedFloat64Array = session.aircraft.model.crash_hull.slice(3*crossing.point_index,3*crossing.point_index+3)
		var contact: Vector3 = flight._airplane.root.transform * (flight._cg_model+Vector3(r[1],-r[2],-r[0]))
		var ground_error: float = absf(contact.y)
		var event_point_render: Vector3 = Frames.ned_to_render(Array(crossing.point_ned))
		var event_point_error: float = contact.distance_to(event_point_render)
		# Both values pass through float32 Vector3 rendering; bound two rounding ulps at world scale.
		var render_scale: float = maxf(1.0, maxf(maxf(absf(contact.x), absf(contact.y)), absf(contact.z)))
		render_scale = maxf(render_scale, maxf(maxf(absf(event_point_render.x), absf(event_point_render.y)), absf(event_point_render.z)))
		var event_point_limit: float = 2e-6 + 2.0 * 1.1920928955078125e-7 * render_scale
		_check(entry.id+" rendered hull point lies on ground plane (residual %.9f m)" % ground_error,
			ground_error < 2e-6)
		_check(entry.id+" rendered hull point matches event point (residual %.9f m, limit %.9f m)" % [event_point_error, event_point_limit],
			event_point_error <= event_point_limit)
		var shadow: Transform3D = Shadow.footprint(expected_basis,expected_pos,flight._extent.x,flight._extent.y,Atmosphere.sun_direction())
		_check(entry.id+" shadow uses crossing pose", flight._shadow.transform.is_equal_approx(shadow))
		for inspect: bool in [false,true]:
			flight._inspect = inspect
			flight._process(1.0/30.0)
			var aim: Vector3 = (expected_pos-flight._camera.global_position).normalized()
			_check(entry.id+" camera targets crossing CG inspect="+str(inspect), (-flight._camera.global_basis.z).dot(aim) > 1.0-1e-6)
		_check(entry.id+" rendering preserves simulation state", before == _observation(session.sim))
		var held_pose: Dictionary = flight._current_pose()
		var ticks: int = session.crash.ticks_left
		session.hold("cr01c-test")
		for frame in 6:
			session._physics_process(session.sim.dt())
			flight._process(1.0/144.0)
		_check(entry.id+" menu hold freezes countdown and pose", session.crash.ticks_left == ticks and _pose_equal(held_pose,flight._last_render_pose))
		session.release("cr01c-test")
		session.resume()
		_check(entry.id+" Continue cannot resume an active crash", session.sim.paused)
		for tick in 359:
			session._physics_process(session.sim.dt())
		_check(entry.id+" pose remains through final held tick", session.crash.ticks_left == 1 and _pose_equal(held_pose,flight._current_pose()))
		session._physics_process(session.sim.dt())
		flight._process(1.0/60.0)
		_check(entry.id+" automatic restart clears crossing pose", session.crash.is_empty() and session.sim.state == start and session.sim.previous == start and _ordinary_pose_equal(flight._last_render_pose,flight._pose_of(start)))
		# A tick that starts in deep contact has no new crossing estimate; render its detected endpoint.
		# X8-08: a tolerant (foam) hull crushes deeper before it is terminal; sink past the aircraft's own depth.
		var crush_m: float = 0.10 if not session.aircraft.model.has("crash_tolerance") \
			else float(session.aircraft.model.crash_tolerance.crash_depth) + 0.02
		var preexisting_contact: PackedFloat64Array = _place_hull_contact(session, crush_m, 0.0)
		_accepted_contact_tick(session, preexisting_contact, entry.id)
		_check(entry.id+" pre-existing accepted contact has unavailable crossing", not session.crash.is_empty()
			and session.crash.impact.crossing != null and not session.crash.impact.crossing.available)
		_check(entry.id+" unavailable crossing uses detected pose", not session.crash.is_empty()
			and _pose_equal(flight._current_pose(),flight._pose_of(session.crash.impact.detected_state)))
		session.crash.impact.crossing = null
		_check(entry.id+" absent crossing uses detected pose", _pose_equal(flight._current_pose(),flight._pose_of(session.crash.impact.detected_state)))
		# Legacy/missing snapshot has only the detected simulation state to display.
		session.crash.erase("impact")
		_check(entry.id+" missing snapshot uses current tick pose", _pose_equal(flight._current_pose(),flight._pose_of(session.sim.state)))
		_check(entry.id+" checkpoint restore clears crash pose", session.restore_checkpoint(checkpoint) and session.crash.is_empty() and session.sim.state == start and session.sim.previous == start and _ordinary_pose_equal(flight._current_pose(),flight._pose_of(start)))
		# Synthetic/scripted review routes keep their existing priority.
		flight._visual_pose = {pos=Vector3(1,2,3),basis=Basis.IDENTITY}
		_check(entry.id+" synthetic pose precedence unchanged", _pose_equal(flight._current_pose(),flight._visual_pose))
		flight._visual_pose = {}
		flight._scripted = true
		flight._t = .75
		var scripted: Dictionary = Scripted.pose_at(.75)
		_check(entry.id+" scripted pose precedence unchanged", flight._current_pose().pos == Frames.ned_to_render(scripted.ned))
		flight._scripted = false
		var reset_contact: PackedFloat64Array = _place_hull_contact(session, 0.001, 20.0)
		_accepted_contact_tick(session, _tick_before_contact(reset_contact), entry.id)
		_check(entry.id+" manual-reset precondition is active crossing", not session.crash.is_empty()
			and session.crash.impact.crossing != null and session.crash.impact.crossing.available)
		session.reset()
		flight._process(1.0/60.0)
		_check(entry.id+" manual reset restores ordinary pose", session.crash.is_empty() and session.sim.state == start and session.sim.previous == start and _ordinary_pose_equal(flight._last_render_pose,flight._pose_of(start)))
		session.sim.previous = _state(-5)
		session.sim.state = _state(-4)
		var ordinary: Dictionary = flight._pose_of(session.sim.interpolated(Engine.get_physics_interpolation_fraction()))
		_check(entry.id+" ordinary pose retains interpolation", _pose_equal(flight._current_pose(),ordinary))
		var untouched := var_to_bytes([session.sim.previous, session.sim.state, session.sim.tick])
		session.sim.set_paused(true)
		_check(entry.id+" paused pose uses the latest accepted tick", _pose_equal(flight._current_pose(),
			flight._pose_of(session.sim.interpolated(1.0))))
		_check(entry.id+" paused presentation leaves simulation untouched", untouched ==
			var_to_bytes([session.sim.previous, session.sim.state, session.sim.tick]))
		session.sim.set_paused(false)
		_check(entry.id+" resumed pose retains interpolation", _pose_equal(flight._current_pose(),ordinary))
		flight.queue_free()
		await process_frame
	print("%d checks, %d failed" % [_count,_failures])
	quit(1 if _failures else 0)
