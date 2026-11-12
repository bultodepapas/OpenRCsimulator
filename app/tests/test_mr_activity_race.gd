# DR-32/36b: the local practice race from the FPV quad activity. On the default field the activity prepares a race
# session, draws the gate frames from the course's solid boxes, shows the race line on the OSD, starts a countdown on
# request, highlights the next gate, reaches GO with the motors armed, cancels on a second request and writes the
# aborted record to the (isolated) results folder. Headless: no rendering, pacing or latency claim.
extends SceneTree

const Scene := preload("res://vehicles/multirotor/multirotor_scene.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const RaceModel := preload("res://sim/race/race_model.gd")
const CourseVisual = preload("res://vehicles/multirotor/race_course_visual.gd")
const Director := preload("res://sim/race/race_director.gd")
const RaceRecords := preload("res://vehicles/multirotor/race_records.gd")

const DIR := "user://test_mr_activity_race"

var _count := 0
var _failures := 0
var _scene: Node3D


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _clean() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for file: String in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(file))
		DirAccess.remove_absolute(DIR)


## Angle mode on the pad: arm switch OFF for the first ticks, then ON with the throttle low.
func _pilot(tick: int) -> PackedFloat64Array:
	return Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0 if tick < 4 else 1, 1)


func _phase() -> int:
	return int(_scene.session.sim.modes[RaceModel.MODE_PHASE])


## The OSD and the gate highlight are drawn from a later rendered frame's telemetry: let a few frames pass.
func _settle() -> void:
	for _i in 4:
		await process_frame


func _until(done: Callable, limit: int) -> bool:
	for _i in limit:
		if done.call():
			return true
		await physics_frame
	return done.call()


func _run() -> void:
	_clean()
	_scene = Scene.new()
	_scene.enable_audio = false
	_scene.enable_world = false
	_scene.departure_managed = true
	_scene.scripted_pilot = _pilot
	_scene.results_directory = DIR
	root.add_child(_scene)
	await process_frame
	await process_frame
	var s: Node = _scene.session
	_check("the activity prepares a race session on the default field", _scene.startup_error.is_empty() and s != null and s.prepared
		and s.race != null and str(s.options.race_track) == Scene.RACE_TRACK, _scene.startup_error)
	if s == null or not s.prepared or s.race == null:
		_finish()
		return
	# DR-32: each gate is one merged mesh drawing its four collision boxes; every drawn box is its collision box, and
	# the mesh's bounds are exactly the union of the boxes (nothing drawn outside a solid, no solid undrawn).
	var cv0: RefCounted = _scene.course_visual
	var exact: bool = _scene._gate_views.size() == s.course.gates.size()
	var detail := ""
	for g in s.course.gates.size():
		var frames: Array = s.course.gates[g].frames
		var drawn: Array = cv0.gate_boxes[g]
		exact = exact and drawn.size() == 4 and frames.size() == 4
		var view: MeshInstance3D = _scene._gate_views[g][0]
		var union := AABB()
		for k in mini(drawn.size(), frames.size()):
			var box: Dictionary = frames[k]
			var size := Vector3(2.0 * float(box.half_z), 2.0 * float(box.half_down), 2.0 * float(box.half_x))
			var at := Vector3(float(box.east), -float(box.down), -float(box.north))
			exact = exact and (drawn[k].position as Vector3).is_equal_approx(at) and (drawn[k].size as Vector3).is_equal_approx(size)
			var local := view.transform.affine_inverse() * at
			var part := AABB(local - 0.5 * size, size)
			union = part if k == 0 else union.merge(part)
		var bounds: AABB = view.mesh.get_aabb()
		if not (bounds.position.is_equal_approx(union.position) and bounds.size.is_equal_approx(union.size)):
			exact = false
			detail = "gate %d mesh %s against boxes %s" % [g, bounds, union]
	_check("every gate is drawn as exactly its four solid frame boxes (one merged mesh per gate)", exact, detail)
	_scene.handle_action("resume")
	await _until(func() -> bool: return int(s.sim.tick) >= 8, 240)
	await _settle()
	_check("DR-37 on the pad, armed, the OSD says how to start (G, throttle low until GO)", _phase() == Director.PHASE_IDLE
		and _scene.hud.race_label.visible and _scene.hud.race_label.text == "Race: press G to start, throttle low until GO",
		_scene.hud.race_label.text)
	_check("DR-40 the pause menu shows the course's first medal target before any finish", _scene.hud.race_note.visible
		and _scene.hud.race_note.text.begins_with("No finish yet. Bronze target "), _scene.hud.race_note.text)
	_scene.request_race()
	await _until(func() -> bool: return _phase() == Director.PHASE_COUNTDOWN, 240)
	await _settle()
	_check("a race request starts the countdown: the OSD counts seconds and the first gate is highlighted",
		_phase() == Director.PHASE_COUNTDOWN and _scene.hud.countdown_label.visible
		and _scene.hud.countdown_label.text in ["3", "2", "1"] and _scene.hud.race_label.text == "THROTTLE LOW UNTIL GO"
		and _scene._gate_next == 0
		and _scene.course_visual.gate_states[0] == CourseVisual.GateState.NEXT
		and _scene.course_visual.gate_states[1] == CourseVisual.GateState.AFTER
		and _scene.course_visual.gate_states[2] == CourseVisual.GateState.CALM, _scene.hud.countdown_label.text)
	var cv: RefCounted = _scene.course_visual
	var red: Color = cv.lamp_color(0)
	_check("DR-32 the countdown shows the guidance: chevron at gate 1 (its light only from dusk), a dotted path from the pad, red start lamps",
		cv.chevron.visible and cv.gate_light.visible == (cv.night >= cv.GATE_LIGHT_NIGHT) and cv.path.visible and cv.path.multimesh.visible_instance_count > 2
		and cv.chevron.position.distance_to((cv.gate_frames[0].top as Vector3) + (cv.gate_frames[0].up as Vector3) * cv.CHEVRON_LIFT_M) < 1.0e-4
		and red.r > 4.0 * red.g, "lamp %s, %d dots" % [red, cv.path.multimesh.visible_instance_count])
	_check("DR-28 the pause menu offers the field's other course", _scene.hud.course_button.visible
		and _scene.hud.course_button.text == "Course: Practice oval 1", _scene.hud.course_button.text)
	cv.gate_passed(3)
	cv.update(0.1, {})
	_check("DR-32 a scored gate flashes white, then fades", float(cv.gate_materials[3][0].get_shader_parameter("flash")) > 0.5)
	cv.update(1.0, {})
	_check("DR-32 the flash is over after its time", float(cv.gate_materials[3][0].get_shader_parameter("flash")) == 0.0)
	var racing: bool = await _until(func() -> bool: return _phase() == Director.PHASE_RACING, 1500)
	await _settle()
	_check("GO after the countdown with the motors armed: RACING and the lap line on the OSD", racing
		and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED and _scene.hud.race_label.text.begins_with("Lap 1/3   Gate 1/6"),
		_scene.hud.race_label.text)
	_scene.request_race()
	await _until(func() -> bool: return _phase() == Director.PHASE_ABORTED, 240)
	await _settle()
	var files := PackedStringArray()
	if DirAccess.dir_exists_absolute(DIR):
		for file: String in DirAccess.get_files_at(DIR):
			if file.begins_with("race-"):
				files.append(file)
	_check("a second request cancels the race: ABORTED on the OSD, the record written once to the results folder",
		_phase() == Director.PHASE_ABORTED and _scene.hud.race_label.text == "Race aborted" and files.size() == 1
		and s.results.is_empty() and _scene._gate_next == -1, "%s, %d files" % [_scene.hud.race_label.text, files.size()])
	if files.size() == 1:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(files[0])))
		_check("the saved record is the aborted attempt of this course", typeof(parsed) == TYPE_DICTIONARY and parsed.get("valid") == false
			and parsed.get("phase") == "ABORTED" and parsed.get("course_identity") == str(s.course.identity) and parsed.get("saved") == true)
	var book: Dictionary = RaceRecords.load_file(_scene.records_path())
	var entry: Dictionary = book.records.get(str(s.course.identity), {})
	_check("DR-40 a cancelled race enters the record book as no attempt (the pilot left it), no finish, no best total",
		book.ok and not entry.is_empty() and int(entry.get("attempts", -1)) == 0 and int(entry.get("finishes", -1)) == 0
		and float(entry.get("best_total_s", -1.0)) == 0.0, str(entry))
	_check("DR-37 the results card shows why the attempt ended and how to race again", _scene.hud.race_card.visible
		and _scene.hud.race_card_title.text == "ATTEMPT OVER" and _scene.hud.race_card_body.text.contains("Race cancelled (G).")
		and _scene.hud.race_card_body.text.contains("G: race again"), _scene.hud.race_card_body.text)
	_check("DR-37 every start refusal names what the pilot must do", _scene.race_refusal_text("go_refused_not_armed").begins_with("False start")
		and _scene.race_refusal_text("go_refused_throttle").begins_with("Jump start")
		and _scene.race_refusal_text("start_refused_moving").begins_with("Hold still"))
	# DR-37 one-key retry: off the pad, G returns the quad to the pad, flies on and stages the start.
	s.sim.state[0] += 6.0
	_scene._invalidate_telemetry()
	var off_pad: bool = not _scene._on_race_pad()
	_scene.request_race()
	var retried: bool = await _until(func() -> bool: return _phase() == Director.PHASE_COUNTDOWN, 240)
	_check("DR-37 G off the pad returns to the pad and starts the countdown at once", off_pad and retried and not s.paused
		and _scene._on_race_pad() and not _scene.hud.race_card.visible, "phase %d paused %s" % [_phase(), s.paused])
	_scene.request_race()
	await _until(func() -> bool: return _phase() == Director.PHASE_IDLE, 240)
	# DR-28/32: T switches to the next course of this field; the quad is back on the pad and the new gates are drawn.
	var oval: String = str(s.course.identity)
	_scene.cycle_course()
	await _settle()
	await process_frame
	var tower: bool = str(s.course.track_id) == "openrc-tower-sprint-1" and str(s.course.identity) != oval
	_check("T switches to the tower sprint: prepared on the pad, its seven gates drawn at their collision boxes", tower
		and int(s.sim.tick) == 0 and s.paused and _phase() == Director.PHASE_IDLE
		and _scene.course_visual.course_identity == str(s.course.identity) and _scene._gate_views.size() == 7
		and (_scene.course_visual.gate_boxes[2][0].position as Vector3).is_equal_approx(Vector3(float(s.course.gates[2].frames[0].east),
			-float(s.course.gates[2].frames[0].down), -float(s.course.gates[2].frames[0].north)))
		and _scene.find_children("RaceCourse", "Node3D", false, false).size() == 1,
		"%s, %d gates, tick %d paused %s phase %d visual %s roots %d" % [s.course.track_id, _scene._gate_views.size(), s.sim.tick,
			s.paused, _phase(), _scene.course_visual.course_identity == str(s.course.identity),
			_scene.find_children("RaceCourse", "Node3D", false, false).size()])
	_scene.cycle_course()
	await _settle()
	await process_frame
	_check("T again returns to the practice oval", str(s.course.track_id) == "openrc-practice-oval-1" and _scene._gate_views.size() == 6
		and _scene.find_children("RaceCourse", "Node3D", false, false).size() == 1)
	_scene.race_track = ""
	_check("without a course the activity falls back to plain free flight", _scene._load_field() and _scene._race_option.is_empty())
	_finish()


func _finish() -> void:
	if _scene != null:
		_scene.queue_free()
	_clean()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
