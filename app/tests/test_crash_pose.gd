# CR-01c: real flight scene, detector and render consumers; no simulation writes from presentation.
extends SceneTree
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
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

func _observation(sim: Node) -> Array:
	return [sim.state.duplicate(),sim.previous.duplicate(),sim.aux.duplicate(),sim.continuous.duplicate(),sim.inputs.duplicate(),sim.tick,sim.paused]

func _run() -> void:
	for entry: Dictionary in Catalog.ENTRIES:
		var flight: Node = load("res://main.tscn").instantiate()
		flight.aircraft_id = entry.id
		root.add_child(flight)
		flight.set_process(false)
		var session: Node = flight.session
		session.set_physics_process(false)
		session.sim.set_physics_process(false)
		session.input_enabled = false
		var start: PackedFloat64Array = session.sim.state.duplicate()
		var checkpoint: Dictionary = session.checkpoint()
		# A manufactured descending interval goes through the production detector.
		session.sim.previous = _state(-5)
		session.sim.state = _state(.4)
		session.sim.tick = 7
		session.sim.set_paused(false)
		session._physics_process(session.sim.dt())
		_check(entry.id+" actual hull crash has an available crossing", not session.crash.is_empty() and session.crash.impact.crossing != null and session.crash.impact.crossing.available)
		if session.crash.is_empty() or session.crash.impact.crossing == null or not session.crash.impact.crossing.available:
			flight.free()
			continue
		var crossing: RefCounted = session.crash.impact.crossing
		var before: Array = _observation(session.sim)
		flight._process(1.0/60.0)
		var pose: Dictionary = flight._last_render_pose
		var expected_pos: Vector3 = Frames.ned_to_render(Array(crossing.position_ned))
		var expected_basis: Basis = Frames.quat_to_render(crossing.attitude)
		_check(entry.id+" rendered CG and attitude use crossing", pose.pos == expected_pos and pose.basis == expected_basis)
		var cg: Vector3 = flight._airplane.root.transform * flight._cg_model
		_check(entry.id+" model origin preserves crossing CG", cg.distance_to(expected_pos) < 2e-6)
		var r: PackedFloat64Array = session.aircraft.model.crash_hull.slice(3*crossing.point_index,3*crossing.point_index+3)
		var contact: Vector3 = flight._airplane.root.transform * (flight._cg_model+Vector3(r[1],-r[2],-r[0]))
		_check(entry.id+" rendered hull point lies on ground plane", absf(contact.y) < 2e-6 and contact.distance_to(Frames.ned_to_render(Array(crossing.point_ned))) < 2e-6)
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
		_check(entry.id+" automatic restart clears crossing pose", session.crash.is_empty() and session.sim.state == start and _pose_equal(flight._last_render_pose,flight._pose_of(start)))
		# A pre-existing contact has an unavailable estimate and must use observed pose.
		session.sim.previous = _state(.1)
		session.sim.state = _state(.4)
		session._physics_process(session.sim.dt())
		_check(entry.id+" unavailable crossing uses detected pose", not session.crash.impact.crossing.available and _pose_equal(flight._current_pose(),flight._pose_of(session.crash.impact.detected_state)))
		session.crash.impact.crossing = null
		_check(entry.id+" absent crossing uses detected pose", _pose_equal(flight._current_pose(),flight._pose_of(session.crash.impact.detected_state)))
		# Legacy/missing snapshot has only the detected simulation state to display.
		session.crash.erase("impact")
		_check(entry.id+" missing snapshot uses current tick pose", _pose_equal(flight._current_pose(),flight._pose_of(session.sim.state)))
		_check(entry.id+" checkpoint restore clears crash pose", session.restore_checkpoint(checkpoint) and session.crash.is_empty() and _pose_equal(flight._current_pose(),flight._pose_of(start)))
		# Synthetic/scripted review routes keep their existing priority.
		flight._visual_pose = {pos=Vector3(1,2,3),basis=Basis.IDENTITY}
		_check(entry.id+" synthetic pose precedence unchanged", _pose_equal(flight._current_pose(),flight._visual_pose))
		flight._visual_pose = {}
		flight._scripted = true
		flight._t = .75
		var scripted: Dictionary = Scripted.pose_at(.75)
		_check(entry.id+" scripted pose precedence unchanged", flight._current_pose().pos == Frames.ned_to_render(scripted.ned))
		flight._scripted = false
		session.sim.previous = _state(-5)
		session.sim.state = _state(.4)
		session.sim.set_paused(false)
		session._physics_process(session.sim.dt())
		_check(entry.id+" manual-reset precondition is active crossing", not session.crash.is_empty() and session.crash.impact.crossing.available)
		session.reset()
		flight._process(1.0/60.0)
		_check(entry.id+" manual reset restores ordinary pose", session.crash.is_empty() and _pose_equal(flight._last_render_pose,flight._pose_of(start)))
		session.sim.previous = _state(-5)
		session.sim.state = _state(-4)
		var ordinary: Dictionary = flight._pose_of(session.sim.interpolated(Engine.get_physics_interpolation_fraction()))
		_check(entry.id+" ordinary pose retains interpolation", _pose_equal(flight._current_pose(),ordinary))
		flight.queue_free()
		await process_frame
	print("%d checks, %d failed" % [_count,_failures])
	quit(1 if _failures else 0)
