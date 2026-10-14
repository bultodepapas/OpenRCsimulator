# E3d1: in the production flight scene a wingtip brush continues the flight and leaves presentation feedback (a mark
# along the slide and a small puff), while the source airplane stays visible and the crash aftermath stays idle.
# US-V12: the brush also scuffs the low wing, and restart removes the scuff.
# Run: godot --headless --path . --script res://tests/test_soft_contact_feedback.gd
extends SceneTree

const MainScene = preload("res://main.tscn")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const STIK := "jensen-das-ugly-stik-60"

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Variant = MainScene.instantiate()
	main.set("aircraft_id", STIK)
	root.add_child(main)
	await process_frame
	var session: Variant = main.get("session")
	var director: Variant = main.get("_crash_director")
	_check("production flight enables soft hull contacts", session != null and session.soft_hull_contacts)
	_check("production flight has a crash director", director != null)
	if session == null or director == null:
		_finish(main)
		return
	session.input_enabled = false
	session.set_physics_process(false)
	# Bank 40°, 15 m/s, sinking 0.5 m/s, the low wingtip 1 cm above the field.
	var q := M.q_from_euler(0.0, 0.0, deg_to_rad(40.0))
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var lowest := -INF
	for i in range(0, hull.size(), 3):
		lowest = maxf(lowest, M.q_rotate(q, hull.slice(i, i + 3))[2])
	var s := RB.make_state(M.v3(0, 0, -(lowest + 0.01)), M.q_rotate(M.q_conj(q), M.v3(15, 0, 0.5)), q, M.v3(0, 0, 0))
	session.sim.reset(s)
	session.sim.set_paused(false)
	var touched := false
	var marks_seen := 0
	var puff_seen := false
	for t in 60:
		session._physics_process(session.sim.dt())
		if not session.soft_contacts.is_empty():
			touched = true
		# As main._process does: draw the pose, then let the director read it.
		main._render_pose(main._current_pose(), session.surfaces(), 0.0)
		director.update(session.sim.dt())
		marks_seen = maxi(marks_seen, _visible_marks(director.effects))
		puff_seen = puff_seen or director.effects.touch_dust.emitting
		if not session.crash.is_empty():
			break
		session.sim.step()
	_check("the wingtip touches in production", touched)
	_check("the brush does not end the flight", session.crash.is_empty())
	_check("the touch leaves a ground mark", marks_seen >= 1, "%d marks" % marks_seen)
	var scuffs: Array = director.scuffs.marks
	var on_wing := not scuffs.is_empty()
	for scuff: Node in scuffs:
		var cursor: Node = scuff
		var wing := false
		while cursor != null:
			wing = wing or String(cursor.name).begins_with("wing_frame_")
			cursor = cursor.get_parent()
		on_wing = on_wing and wing
	_check("the brush scuffs the low wing", on_wing, "%d scuffs" % scuffs.size())
	var surface: String = director.surface_at(main.get("field"), 0.0, 0.0)
	var soft_ground: bool = not director.effects.dust_profile(surface).is_empty()
	_check("the touch throws a puff only on soft ground (%s)" % surface, puff_seen == soft_ground)
	_check("the crash aftermath stays idle", not director.active and not director.wreck.stats().started)
	_check("the source airplane stays visible", main.get("_airplane").root.visible)
	_check("touch feedback stays inside the effects budget", int(director.effects.stats().particles) <= 700 and _visible_marks(director.effects) <= director.effects.MAX_MARKS)
	session.reset()
	director.update(session.sim.dt())
	_check("restart clears the touch marks", _visible_marks(director.effects) == 0 and session.soft_contacts.is_empty())
	_check("restart removes the airframe scuffs", director.scuffs.marks.is_empty())
	_finish(main)


func _visible_marks(effects: Variant) -> int:
	var n := 0
	for mark: MeshInstance3D in effects.marks:
		if mark.visible:
			n += 1
	return n


func _finish(main: Variant) -> void:
	main.queue_free()
	await process_frame
	await process_frame
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)
