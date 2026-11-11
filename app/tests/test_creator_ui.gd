extends SceneTree
## AC-10: the Aircraft Creator wizard and its isolated preview, driven through their controls.
const Creator := preload("res://ui/aircraft_creator.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const AcceptedCandidate := preload("res://workshop/creator/accepted_candidate.gd")
const Definition := preload("res://workshop/creator/definition.gd")

const CAPTION := "Visual preview · no flight simulation"
const PAYLOAD_KEYS: PackedStringArray = ["creator_candidate", "creator_source", "creator_placement", "creator_name", "start_choice"]
const WORKER_TIMEOUT_MS := 20000

var failures := 0
var checks := 0
var payloads: Array = []
var closes := 0
# Fixture landmarks in source millimetres, from the starting template.
var _nose_y := 0.0
var _tail_y := 0.0
var _half_span := 0.0
var _nose_x_m := 0.0
var _length_m := 0.0
var _span_m := 0.0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL: %s %s" % [label, detail])


func _settle(frames := 2) -> void:
	for _index: int in frames:
		await process_frame


## A flat "airplane" drawn in millimetres with the nose along +y and up along +z, in the proportions
## of the Creator's own starting template, so that its starting values describe this model: wing
## leading edge on the centreline at y = 200, wing tips at x = +-half span.
func _plane_stl() -> PackedByteArray:
	var triangles: Array = [
		[[0, _nose_y, 0], [-40, _tail_y, 0], [40, _tail_y, 0]],                # fuselage
		[[-_half_span, 100, 0], [_half_span, 100, 0], [0, 200, 0]],            # wing
		[[0, _tail_y, 0], [0, _tail_y + 80.0, 0], [0, _tail_y, 120]],          # fin, in the plane of symmetry
	]
	var bytes := PackedByteArray()
	bytes.resize(84 + 50 * triangles.size())
	bytes.encode_u32(80, triangles.size())
	var offset := 84
	for triangle: Array in triangles:
		offset += 12
		for vertex: Array in triangle:
			for component: int in 3:
				bytes.encode_float(offset, float(vertex[component]))
				offset += 4
		offset += 2
	return bytes


func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _find(wizard: Node, node_name: String) -> Node:
	return wizard.find_child(node_name, true, false)


func _new_wizard() -> Control:
	var wizard := Creator.new() as Control
	wizard.theme = UiTheme.build()
	wizard.test_fly_requested.connect(func(payload: Dictionary) -> void: payloads.append(payload))
	wizard.close_requested.connect(func() -> void: closes += 1)
	root.add_child(wizard)
	return wizard


## Types into a field without committing: the text changes as it would under the keyboard.
func _type(edit: LineEdit, text: String) -> void:
	edit.grab_focus()
	edit.text = text
	edit.text_changed.emit(text)


func _enter(edit: LineEdit, text: String) -> void:
	_type(edit, text)
	edit.text_submitted.emit(text)
	await _settle()


func _choose(picker: OptionButton, value: String) -> void:
	for index: int in picker.item_count:
		if str(picker.get_item_metadata(index)) == value:
			picker.select(index)
			picker.item_selected.emit(index)
			await _settle()
			return
	check("option %s offers %s" % [picker.name, value], false)


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func _mouse(button: MouseButton, at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = at
		event.global_position = at
		root.push_input(event)
		await process_frame


## Left button down at `at`, one move by `by`, button up.
func _drag(at: Vector2, by: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	down.global_position = at
	root.push_input(down)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = at + by
	motion.global_position = at + by
	motion.relative = by
	root.push_input(motion)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at + by
	up.global_position = at + by
	root.push_input(up)
	await process_frame


## Visible buttons and fields that keyboard or controller focus cannot reach.
func _unreachable(wizard: Control) -> PackedStringArray:
	var found := PackedStringArray()
	for node: Node in wizard.find_children("*", "Control", true, false):
		var control := node as Control
		if (control is BaseButton or control is LineEdit) and control.is_visible_in_tree() \
				and control.focus_mode != Control.FOCUS_ALL:
			found.append(str(control.name))
	return found


## Waits for the worker by wall time: headless frames are too short to count.
func _await_import(wizard: Control) -> void:
	var deadline := Time.get_ticks_msec() + WORKER_TIMEOUT_MS
	while str(wizard.import_state().state) == "inspecting" and Time.get_ticks_msec() < deadline:
		await process_frame
	await _settle()


## Controls outside the viewport and content wider than its scroll area. Empty when the layout fits.
func _layout_problems(wizard: Control) -> PackedStringArray:
	var problems := PackedStringArray()
	var area := root.get_visible_rect().grow(0.5)
	var pending: Array = [[wizard, null]]
	while not pending.is_empty():
		var entry: Array = pending.pop_back()
		var node: Node = entry[0]
		var scroll: ScrollContainer = entry[1]
		if node is Window:
			continue
		var control := node as Control
		if control != null:
			if not control.is_visible_in_tree():
				continue
			var rect := control.get_global_rect()
			if scroll == null:
				if not area.encloses(rect):
					problems.append("%s is outside the viewport: %s" % [wizard.get_path_to(control), rect])
			else:
				var clip := scroll.get_global_rect()
				if rect.position.x < clip.position.x - 0.5 or rect.end.x > clip.end.x + 0.5:
					problems.append("%s needs horizontal scrolling: %s in %s" % [wizard.get_path_to(control), rect, clip])
			if control is ScrollContainer:
				scroll = control as ScrollContainer
				if scroll.get_h_scroll_bar().visible:
					problems.append("%s shows a horizontal scroll bar" % wizard.get_path_to(control))
		for child: Node in node.get_children():
			pending.append([child, scroll])
	return problems


func _check_all_steps(wizard: Control, label: String) -> void:
	var heading := _find(wizard, "StepHeading") as Label
	for step: String in Authoring.STEPS:
		wizard.go_to_step(step)
		await _settle(3)
		var page := _find(wizard, "Page" + step.to_pascal_case()) as Control
		check("%s: step %s is shown with its heading" % [label, step], wizard.current_step() == step
			and page != null and page.visible and heading.text == str(Authoring.STEP_TITLES[step]), heading.text)
		var problems := _layout_problems(wizard)
		check("%s: step %s fits without horizontal scrolling" % [label, step], problems.is_empty(), "\n".join(problems))
		var unreachable := _unreachable(wizard)
		check("%s: step %s is reachable by focus" % [label, step], unreachable.is_empty(), ", ".join(unreachable))


func _run() -> void:
	var orphans_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var stamp := Time.get_ticks_usec()
	var plane_path := "user://creator-ui-test-%d.stl" % stamp
	var broken_path := "user://creator-ui-test-%d-broken.stl" % stamp
	var template: Dictionary = Definition.template()
	_nose_x_m = float(template.fuselage.nose_x)
	_length_m = float(template.fuselage.tail_x) - _nose_x_m
	_span_m = float(template.wing.span)
	_nose_y = 200.0 - _nose_x_m * 1000.0
	_tail_y = 200.0 - float(template.fuselage.tail_x) * 1000.0
	_half_span = _span_m * 500.0
	_write(plane_path, _plane_stl())
	_write(broken_path, PackedByteArray([1, 2, 3, 4, 5]))

	root.size = Vector2i(1920, 1080)
	var wizard := _new_wizard()
	await _settle(4)
	var doc: Authoring = wizard.document()
	var preview: Control = wizard.preview()

	await _layout(wizard)
	await _import(wizard, doc, preview, plane_path, broken_path)
	await _orient(wizard, doc, preview)
	await _preview_input(wizard, preview)
	await _fields(wizard, doc)
	await _complete(wizard, doc, preview)
	await _review(wizard, doc)
	await _back_and_modals(wizard, doc, plane_path)
	await _closing(plane_path)

	wizard.free()
	await _settle(3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(plane_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(broken_path))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check("no orphan nodes are left", orphans == orphans_before, "%d before, %d after" % [orphans_before, orphans])
	if orphans != orphans_before:
		Node.print_orphan_nodes()
	print("Creator UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _layout(wizard: Control) -> void:
	for node_name: String in ["BackToWorkshop", "AircraftName", "ExperimentalBadge", "ChooseModel", "StepBack",
			"StepContinue", "TestFly", "CreatorPreview", "Inspector", "ViewFront", "ViewSide", "ViewTop", "ZoomIn",
			"ZoomOut", "ResetView"]:
		check("control %s exists" % node_name, _find(wizard, node_name) is Control)
	for step: String in Authoring.STEPS:
		var entry := _find(wizard, "Step" + step.to_pascal_case()) as Button
		check("rail entry for %s shows its title and status" % step, entry != null
			and entry.text.contains(str(Authoring.STEP_TITLES[step])) and entry.text.contains(Authoring.STATUS_NOT_STARTED),
			entry.text if entry != null else "missing")
	check("the wizard fills the viewport", wizard.get_global_rect().is_equal_approx(root.get_visible_rect()))
	check("1080p shows the step rail, not the selector", (_find(wizard, "StepRail") as Control).is_visible_in_tree()
		and not (_find(wizard, "StepSelect") as Control).is_visible_in_tree())
	var caption := _find(wizard, "PreviewCaption") as Label
	check("the preview caption is always shown", caption != null and caption.is_visible_in_tree() and caption.text == CAPTION)
	check("a new wizard has no unsaved changes", not wizard.has_unsaved_changes())
	await _check_all_steps(wizard, "1920x1080")
	check("the caption stays on the last step", caption.is_visible_in_tree())

	UiTheme.compact_layout = true
	wizard.theme = UiTheme.build()
	root.size = Vector2i(1280, 720)
	await _settle(4)
	check("720p swaps the rail for a step selector", not (_find(wizard, "StepRail") as Control).is_visible_in_tree()
		and (_find(wizard, "StepSelect") as Control).is_visible_in_tree()
		and (_find(wizard, "CreatorPreview") as Control).is_visible_in_tree())
	await _check_all_steps(wizard, "1280x720")
	var selector := _find(wizard, "StepSelect") as OptionButton
	selector.select(2)
	selector.item_selected.emit(2)
	await _settle()
	check("the step selector changes the step", wizard.current_step() == Authoring.STEPS[2])

	root.size = Vector2i(900, 600)
	await _settle(4)
	var toggle := _find(wizard, "TogglePreview") as Button
	check("a narrow window shows the inspector and a preview toggle", toggle.is_visible_in_tree()
		and (_find(wizard, "Inspector") as Control).is_visible_in_tree()
		and not (_find(wizard, "CreatorPreview") as Control).is_visible_in_tree())
	check("narrow layout fits", _layout_problems(wizard).is_empty(), "\n".join(_layout_problems(wizard)))
	toggle.pressed.emit()
	await _settle(3)
	check("the toggle shows the preview instead", (_find(wizard, "CreatorPreview") as Control).is_visible_in_tree()
		and not (_find(wizard, "Inspector") as Control).is_visible_in_tree())
	check("narrow preview fits", _layout_problems(wizard).is_empty(), "\n".join(_layout_problems(wizard)))
	toggle.pressed.emit()

	UiTheme.compact_layout = false
	wizard.theme = UiTheme.build()
	root.size = Vector2i(1920, 1080)
	await _settle(4)
	check("back at 1080p the rail returns", (_find(wizard, "StepRail") as Control).is_visible_in_tree())


func _import(wizard: Control, doc: Authoring, preview: Control, plane_path: String, broken_path: String) -> void:
	wizard.go_to_step("orient_size")
	await _settle()
	var missing := _find(wizard, "OrientNoModel") as Control
	check("Orient and size asks for a model first", missing.is_visible_in_tree()
		and not (_find(wizard, "OrientControls") as Control).is_visible_in_tree())
	(_find(wizard, "GoToImport") as Button).pressed.emit()
	await _settle()
	check("its button goes to Import", wizard.current_step() == "import")
	check("no preview root before an import", preview.find_child("airplane", true, false) == null)

	# A second selection while the first is inspected: the first result must be dropped, although
	# it is the valid one.
	var status := _find(wizard, "ImportStatus") as Label
	wizard.request_import(plane_path)
	check("an import shows that it is inspecting", str(wizard.import_state().state) == "inspecting"
		and status.text.contains("Inspecting model…") and status.text.contains(plane_path.get_file()), status.text)
	check("an import in progress counts as unsaved work", wizard.has_unsaved_changes())
	wizard.request_import(broken_path)
	await _await_import(wizard)
	check("the stale result is discarded", doc.source() == null and str(wizard.import_state().state) == "failed"
		and int(wizard.import_state().discarded) == 1, str(wizard.import_state()))
	check("a refused file shows its diagnostics", (_find(wizard, "ImportErrors") as Control).get_child_count() > 0
		and status.text.contains("The model could not be imported"), status.text)
	check("a refused file leaves the model unchanged", doc.source() == null and doc.revision == 0)

	wizard.request_import(plane_path)
	await _await_import(wizard)
	var details := _find(wizard, "ImportDetails") as Label
	check("the fixture is imported", doc.source() != null and str(wizard.import_state().state) == "imported"
		and status.text == "Model imported", status.text)
	check("the import lists file, format, triangles and size", details.text.contains(plane_path.get_file())
		and details.text.contains("STL (binary)") and details.text.contains("Triangles: 3")
		and details.text.contains(String.num(_half_span * 2.0, 3)), details.text)
	check("the errors of the earlier attempt are gone", (_find(wizard, "ImportErrors") as Control).get_child_count() == 0)
	var shown := preview.find_child("airplane", true, false) as Node3D
	check("the preview shows a root named airplane", shown != null and shown.get_node_or_null("model") is Node3D)
	check("the import step is complete", (_find(wizard, "StepImport") as Button).text.contains(Authoring.STATUS_COMPLETE))
	check("an imported model is unsaved work", wizard.has_unsaved_changes())
	check("Choose model becomes Replace model", (_find(wizard, "ChooseModel") as Button).text == "Replace model…")


func _orient(wizard: Control, doc: Authoring, preview: Control) -> void:
	wizard.go_to_step("orient_size")
	await _settle()
	var nose := _find(wizard, "NoseAxis") as OptionButton
	var up := _find(wizard, "UpAxis") as OptionButton
	var units := _find(wizard, "Units") as OptionButton
	var wingspan := _find(wizard, "KnownWingspan") as LineEdit
	var datum: Array[LineEdit] = [_find(wizard, "DatumX") as LineEdit, _find(wizard, "DatumY") as LineEdit,
		_find(wizard, "DatumZ") as LineEdit]
	var real_size := _find(wizard, "RealSize") as Label
	check("nothing is preselected", nose.selected == 0 and up.selected == 0 and units.selected == 0
		and nose.get_item_text(0) == "Choose…" and units.get_item_text(0) == "Choose units"
		and wingspan.text.is_empty() and datum[0].text.is_empty() and datum[1].text.is_empty() and datum[2].text.is_empty())
	check("the placement starts unresolved", not doc.placement_result().ok and not real_size.text.contains("Span"))
	check("the open decisions are listed as text", (_find(wizard, "OrientTodo") as Label).text.contains("nose"))

	await _choose(nose, "+y")
	await _choose(up, "+z")
	check("a wingspan needs no unit", doc.units().is_empty())
	await _enter(wingspan, "3")
	check("a known wingspan sets the scale", is_equal_approx(float(doc.placement().unit_scale), 3.0 / (_half_span * 2.0)),
		str(doc.placement()))
	await _enter(wingspan, "abc")
	check("an invalid wingspan stays visible and is flagged", wingspan.text == "abc"
		and (_find(wizard, "KnownWingspanError") as Control).visible)
	await _choose(units, "mm")
	check("choosing units replaces the wingspan", wingspan.text.is_empty() and doc.units() == "mm"
		and not (_find(wizard, "KnownWingspanError") as Control).visible)
	check("the status reports progress", (_find(wizard, "StepOrientSize") as Button).text.contains(Authoring.STATUS_IN_PROGRESS))

	await _enter(datum[0], "0")
	await _enter(datum[1], "x")
	check("an invalid datum stays visible and is flagged", datum[1].text == "x" and (_find(wizard, "DatumError") as Control).visible
		and not doc.placement_result().ok)
	await _enter(datum[1], "200")
	await _enter(datum[2], "0")
	check("axes, units and datum resolve the placement", doc.placement_result().ok
		and not (_find(wizard, "DatumError") as Control).visible, str(doc.placement()))
	check("the real size is shown", real_size.text == "Span %.2f m · Length %.2f m · Height 0.12 m" % [_span_m, _length_m],
		real_size.text)
	check("Orient and size is complete", (_find(wizard, "StepOrientSize") as Button).text.contains(Authoring.STATUS_COMPLETE))
	var shown := preview.find_child("airplane", true, false) as Node3D
	var model := shown.get_node("model") as Node3D
	check("the preview is rebuilt in the model frame", (model.transform * Vector3(0, _nose_y, 0)).is_equal_approx(Vector3(0, 0, _nose_x_m)),
		str(model.transform))

	# A ray straight down onto a known point of the wing triangle, in the preview's world space.
	var expected := Vector3(200.0, 130.0, 0.0)
	var above: Vector3 = model.transform * expected + Vector3(0.0, 1.0, 0.0)
	var hit: Dictionary = preview.pick_ray(above, Vector3.DOWN)
	check("a ray hits the wing in source coordinates", not hit.is_empty()
		and (hit.source_point as Vector3).distance_to(expected) < 0.05, str(hit))
	check("a ray beside the model hits nothing", preview.pick_ray(Vector3(5.0, 1.0, 5.0), Vector3.DOWN).is_empty())

	# The same pick through the click path: the picked point becomes the datum.
	var pick := _find(wizard, "PickDatum") as Button
	var picked: Array = []
	var collect := func(point: Vector3) -> void: picked.append(point)
	preview.point_picked.connect(collect)
	pick.button_pressed = true
	await _settle()
	check("PickDatum arms the preview", preview.is_pick_mode() and (_find(wizard, "PickHint") as Control).visible)
	preview.set_standard_view("top")
	await _settle()
	var camera := preview.find_child("PreviewCamera", true, false) as Camera3D
	var surface := _find(wizard, "PreviewSurface") as Control
	var viewport := preview.find_child("PreviewViewport", true, false) as SubViewport
	var at: Vector2 = camera.unproject_position(model.transform * expected) * surface.size / Vector2(viewport.size)
	check("a click on the model picks", preview.pick_at(at) and picked.size() == 1)
	await _settle()
	var picked_datum: Array = doc.placement().datum
	check("the pick is a source-space point on the wing", picked.size() == 1
		and (picked[0] as Vector3).distance_to(expected) < 0.5, str(picked))
	check("the picked point becomes the datum", picked_datum.size() == 3
		and Vector3(picked_datum[0], picked_datum[1], picked_datum[2]).distance_to(expected) < 0.5, str(picked_datum))
	check("a pick ends pick mode and fills the fields", not pick.button_pressed and not preview.is_pick_mode()
		and is_equal_approx(datum[1].text.to_float(), float(picked_datum[1])), datum[1].text)
	preview.point_picked.disconnect(collect)
	check("a pick outside pick mode changes nothing", preview.pick_at(at) and doc.placement().datum == picked_datum)
	await _enter(datum[0], "0")
	await _enter(datum[1], "200")
	await _enter(datum[2], "0")
	check("the datum can be corrected by typing", doc.placement().datum == [0.0, 200.0, 0.0], str(doc.placement().datum))


func _preview_input(wizard: Control, preview: Control) -> void:
	var viewport := preview.find_child("PreviewViewport", true, false) as SubViewport
	var surface := _find(wizard, "PreviewSurface") as Control
	check("the preview world is isolated", viewport.own_world_3d and preview.find_child("PreviewKeyLight", true, false) is DirectionalLight3D
		and preview.find_child("PreviewFillLight", true, false) is DirectionalLight3D)
	check("the preview renders on demand", viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS)
	preview.reset_view()
	var start: Dictionary = preview.view_state()
	(_find(wizard, "ViewSide") as Button).pressed.emit()
	check("a view button turns the camera", not is_equal_approx(float(preview.view_state().yaw_deg), float(start.yaw_deg)))
	(_find(wizard, "ZoomIn") as Button).pressed.emit()
	check("Zoom + moves closer", float(preview.view_state().distance) < float(start.distance))
	preview.orbit_by(10.0, 400.0)
	check("orbit is bounded in pitch", float(preview.view_state().pitch_deg) <= 89.0)
	(_find(wizard, "ResetView") as Button).pressed.emit()
	check("Reset view fits the model again", is_equal_approx(float(preview.view_state().distance), float(start.distance))
		and is_equal_approx(float(preview.view_state().yaw_deg), float(start.yaw_deg)))

	var centre := surface.get_global_rect().get_center()
	await _mouse(MOUSE_BUTTON_WHEEL_UP, centre)
	var zoomed := float(preview.view_state().distance)
	check("the wheel zooms over the preview", zoomed < float(start.distance), "%s -> %s" % [start.distance, zoomed])
	var yaw := float(preview.view_state().yaw_deg)
	await _drag(centre, Vector2(60.0, 0.0))
	check("a drag over the preview orbits", not is_equal_approx(float(preview.view_state().yaw_deg), yaw))
	yaw = float(preview.view_state().yaw_deg)
	await _mouse(MOUSE_BUTTON_WHEEL_UP, (_find(wizard, "Inspector") as Control).get_global_rect().get_center())
	check("the wheel beside the preview leaves the view alone", is_equal_approx(float(preview.view_state().distance), zoomed))
	wizard.set_active(false)
	await _mouse(MOUSE_BUTTON_WHEEL_UP, centre)
	await _drag(centre, Vector2(60.0, 0.0))
	check("an inactive wizard ignores the wheel and the drag", is_equal_approx(float(preview.view_state().distance), zoomed)
		and is_equal_approx(float(preview.view_state().yaw_deg), yaw))
	wizard.set_active(true)
	wizard.visible = false
	await _settle()
	await _mouse(MOUSE_BUTTON_WHEEL_UP, centre)
	check("a hidden wizard ignores the wheel", is_equal_approx(float(preview.view_state().distance), zoomed))
	preview.orbit_by(5.0, 0.0)
	check("a hidden preview does not render", viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	wizard.visible = true
	await _settle()
	check("a shown preview asks for one image", viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS
		and int(preview.view_state().render_requests) > 0, "%s %s" % [viewport.render_target_update_mode, preview.view_state()])


func _fields(wizard: Control, doc: Authoring) -> void:
	wizard.go_to_step("aircraft_layout")
	await _settle()
	var span := _find(wizard, "FieldWingSpan") as LineEdit
	var root_chord := _find(wizard, "FieldWingRootChord") as LineEdit
	var tip_chord := _find(wizard, "FieldWingTipChord") as LineEdit
	var error := _find(wizard, "FieldWingSpanError") as Label
	check("an unresolved field is empty with a placeholder", span.text.is_empty() and span.placeholder_text == "Not set"
		and doc.value("wing/span") == null)
	check("the model note appears once the model is placed", (_find(wizard, "LayoutModelNote") as Control).visible)

	await _enter(span, "abc")
	check("invalid text stays visible and is flagged", span.text == "abc" and doc.is_invalid("wing/span")
		and error.visible and error.text == "Enter a number.")
	check("the step needs attention", (_find(wizard, "StepAircraftLayout") as Button).text.contains(Authoring.STATUS_NEEDS_ATTENTION))
	wizard.go_to_step("review_test")
	await _settle()
	var test_fly := _find(wizard, "TestFly") as Button
	var reason := _find(wizard, "TestFlyReason") as Label
	check("invalid text blocks Test fly with a visible reason", test_fly.is_visible_in_tree() and test_fly.disabled
		and reason.is_visible_in_tree() and not reason.text.is_empty())
	test_fly.pressed.emit()
	check("a blocked Test fly emits nothing", payloads.is_empty())
	var jump: Button
	for row: Node in (_find(wizard, "IssueList") as Control).get_children():
		if row is Button and (row as Button).text.contains("\"Wingspan\" is not a number."):
			jump = row
	check("the invalid field is listed as an issue", jump != null)
	if jump != null:
		jump.pressed.emit()
		await _settle(3)
		check("an issue jumps to its step and focuses its field", wizard.current_step() == "aircraft_layout"
			and root.gui_get_focus_owner() == span, str(root.gui_get_focus_owner()))

	wizard.go_to_step("aircraft_layout")
	await _enter(span, "1.5")
	check("a corrected field is accepted", not doc.is_invalid("wing/span") and doc.value("wing/span") == 1.5 and not error.visible)
	await _enter(root_chord, "0.3")

	# Escape through the field itself.
	_type(root_chord, "0.9zz")
	await _key(KEY_ESCAPE)
	check("Escape restores the text from before the edit", root_chord.text == "0.3" and doc.raw("wing/root_chord") == "0.3",
		root_chord.text)
	# Escape routed by the host.
	_type(root_chord, "7")
	check("handle_back cancels an edit first", wizard.handle_back() and root_chord.text == "0.3"
		and wizard.current_step() == "aircraft_layout")

	# Focus loss commits; a refresh leaves the field being typed in alone.
	_type(root_chord, "0.31")
	doc.set_value("wing/tip_chord", 0.25)
	await _settle()
	check("a refresh does not rewrite the field being typed in or steal focus", root_chord.text == "0.31"
		and root.gui_get_focus_owner() == root_chord and tip_chord.text == Authoring.format_number(0.25), tip_chord.text)
	span.grab_focus()
	await _settle()
	check("leaving a field commits it", doc.raw("wing/root_chord") == "0.31" and doc.value("wing/root_chord") == 0.31)
	await _enter(span, "")
	check("clearing a field returns it to unresolved", doc.value("wing/span") == null and not doc.is_invalid("wing/span"))


func _complete(wizard: Control, doc: Authoring, preview: Control) -> void:
	wizard.go_to_step("aircraft_layout")
	await _settle()
	var confirm := _find(wizard, "CreatorConfirm") as ConfirmationDialog
	(_find(wizard, "UseStartingValues") as Button).pressed.emit()
	await _settle()
	var listed := (_find(wizard, "ConfirmText") as Label).text
	check("starting values are listed before they are applied", confirm.visible and listed.contains("Wingspan: ")
		and listed.contains("Aileron travel: ") and doc.value("wing/span") == null, listed)
	check("a dialog pauses the preview", not preview.is_active())
	confirm.get_ok_button().pressed.emit()
	await _settle()
	check("confirming applies the starting values", not confirm.visible and is_equal_approx(float(doc.value("wing/span")), _span_m)
		and doc.value("controls/servo_time_s") != null and (_find(wizard, "FieldWingSpan") as LineEdit).text == doc.raw("wing/span"))
	check("the preview is active again", preview.is_active())

	wizard.go_to_step("weight_balance")
	await _settle()
	check("the power hardware note is shown", (_find(wizard, "PowerHardwareNotice") as Control).is_visible_in_tree())
	(_find(wizard, "ProposeAirframe") as Button).pressed.emit()
	await _settle()
	var items: Array = doc.inventory()
	check("Propose airframe fills the inventory", not items.is_empty()
		and (_find(wizard, "InventoryList") as Control).get_child_count() == items.size())
	var issues: Array = doc.issues()
	var texts := PackedStringArray()
	for entry: Dictionary in issues:
		texts.append("%s %s %s" % [entry.field, entry.message, entry.arguments])
	check("starting values and the proposed airframe leave no issue", issues.is_empty(), "\n".join(texts))
	check("the read-out shows the estimates", (_find(_find(wizard, "WeightReadout"), "ReadoutMass") as Label).text.ends_with(" kg")
		and (_find(_find(wizard, "WeightReadout"), "ReadoutStaticMargin") as Label).text.ends_with(" %"))
	for step: String in Authoring.STEPS:
		check("step %s is complete" % step, (_find(wizard, "Step" + step.to_pascal_case()) as Button).text.contains(Authoring.STATUS_COMPLETE),
			(_find(wizard, "Step" + step.to_pascal_case()) as Button).text)
	check("the preview marks datum, CG, neutral point, hub and tail", preview.find_child("PreviewMarkers", true, false).get_child_count() == 6,
		str(preview.find_child("PreviewMarkers", true, false).get_child_count()))

	# Inventory rows: an added item, invalid text and removal.
	var revision := doc.revision
	(_find(wizard, "AddItem") as Button).pressed.emit()
	await _settle()
	var added: Dictionary = doc.inventory().back()
	var suffix := str(added.id).to_pascal_case()
	var mass := _find(wizard, "ItemMass" + suffix) as LineEdit
	check("Add item adds a row", doc.revision > revision and mass != null and doc.inventory().size() == items.size() + 1)
	await _enter(mass, "heavy")
	check("invalid inventory text stays visible and is flagged", mass.text == "heavy"
		and (_find(wizard, "ItemError" + suffix) as Control).visible and float(doc.inventory().back().mass) == 0.0)
	wizard.go_to_step("review_test")
	await _settle()
	check("invalid inventory text blocks Test fly", (_find(wizard, "TestFly") as Button).disabled)
	wizard.go_to_step("weight_balance")
	await _enter(mass, "0.05")
	check("a corrected inventory value is stored", is_equal_approx(float(doc.inventory().back().mass), 0.05)
		and not (_find(wizard, "ItemError" + suffix) as Control).visible)
	(_find(wizard, "ItemRemove" + suffix) as Button).pressed.emit()
	await _settle(3)
	check("Remove deletes the row", doc.inventory().size() == items.size() and _find(wizard, "ItemMass" + suffix) == null)
	check("the document is flyable again", doc.issues().is_empty())


func _review(wizard: Control, doc: Authoring) -> void:
	wizard.go_to_step("review_test")
	await _settle(3)
	var test_fly := _find(wizard, "TestFly") as Button
	var scroll := _find(wizard, "InspectorScroll") as ScrollContainer
	var airborne := _find(wizard, "StartAirborne") as Button
	var hand := _find(wizard, "StartHandLaunch") as Button
	var runway := _find(wizard, "StartRunway") as Button
	check("with no issue Test fly is enabled", not test_fly.disabled and not (_find(wizard, "TestFlyReason") as Control).visible
		and (_find(wizard, "IssueList") as Control).get_child_count() == 1)
	check("the review states that the aircraft is estimated", (_find(wizard, "EstimateNotice") as Control).is_visible_in_tree())
	check("Airborne is the default start", airborne.button_pressed and airborne.text.contains("Selected") and not hand.button_pressed)
	check("unavailable cards say why", runway.disabled and runway.text.contains("Needs landing gear")
		and (_find(wizard, "LayoutFlyingWing") as Button).disabled
		and (_find(wizard, "LayoutFlyingWing") as Button).text.contains("Not available yet")
		and (_find(wizard, "PowerGasoline") as Button).disabled and (_find(wizard, "GearRetractable") as Button).disabled
		and (_find(wizard, "PaintGenerate") as Button).disabled)

	scroll.ensure_control_visible(runway)
	await _settle()
	await _mouse(MOUSE_BUTTON_LEFT, runway.get_global_rect().get_center())
	check("a disabled card cannot be selected", not runway.button_pressed and airborne.button_pressed)
	scroll.ensure_control_visible(hand)
	await _settle()
	await _mouse(MOUSE_BUTTON_LEFT, hand.get_global_rect().get_center())
	check("an enabled card is selected by a click", hand.button_pressed and not airborne.button_pressed
		and hand.text.contains("Selected") and not airborne.text.contains("Selected"))

	var note := _find(wizard, "CreatorNote") as Label
	wizard.set_note("The field is closed today.")
	check("set_note is displayed", note.text == "The field is closed today." and note.is_visible_in_tree())
	var name_edit := _find(wizard, "AircraftName") as LineEdit
	name_edit.text = "Test plane"
	name_edit.text_changed.emit("Test plane")
	test_fly.pressed.emit()
	check("Test fly emits exactly one payload", payloads.size() == 1)
	if payloads.size() == 1:
		var payload: Dictionary = payloads[0]
		var keys := PackedStringArray()
		for key: Variant in payload:
			keys.append(str(key))
		keys.sort()
		var expected := PAYLOAD_KEYS.duplicate()
		expected.sort()
		check("the payload has the fixed keys", keys == expected, str(keys))
		check("the candidate is an accepted object", typeof(payload.creator_candidate) == TYPE_OBJECT
			and AcceptedCandidate.is_accepted(payload.creator_candidate) and payload.creator_candidate == doc.compile().value)
		check("the payload carries source, placement, name and start", payload.creator_source == doc.source()
			and payload.creator_placement == doc.placement() and payload.creator_name == "Test plane"
			and payload.start_choice == "hand_launch", str(payload.start_choice))
	check("a new request clears the old note", not note.is_visible_in_tree())
	wizard.set_note("Refused: the start is not available.")
	check("the host's refusal is displayed", note.text == "Refused: the start is not available." and note.is_visible_in_tree())
	wizard.set_note("")
	(_find(wizard, "BackToWorkshop") as Button).pressed.emit()
	check("Back to Workshop asks the host to close", closes == 1)


func _back_and_modals(wizard: Control, doc: Authoring, plane_path: String) -> void:
	var dialog := _find(wizard, "ModelFileDialog") as FileDialog
	var confirm := _find(wizard, "CreatorConfirm") as ConfirmationDialog
	wizard.go_to_step("review_test")
	check("handle_back goes to the previous step", wizard.handle_back() and wizard.current_step() == "paint_skins")
	wizard.go_to_step("import")
	await _settle()
	check("handle_back on the first step with nothing open is left to the host", not wizard.handle_back()
		and wizard.current_step() == "import")
	wizard.focus_default()
	check("focus_default focuses the step's first control", root.gui_get_focus_owner() == _find(wizard, "ChooseModel"))

	(_find(wizard, "ChooseModel") as Button).pressed.emit()
	await _settle()
	check("Choose model opens the file dialog", dialog.visible and dialog.access == FileDialog.ACCESS_FILESYSTEM
		and not dialog.use_native_dialog and dialog.filters.size() >= 2)
	check("handle_back closes the dialog first", wizard.handle_back() and not dialog.visible and wizard.current_step() == "import")
	(_find(wizard, "ChooseModel") as Button).pressed.emit()
	await _settle()
	check("dismiss_modal_for_exit hides the dialog", dialog.visible and wizard.dismiss_modal_for_exit() and not dialog.visible)
	check("dismiss_modal_for_exit reports nothing left", not wizard.dismiss_modal_for_exit())

	# Replacing a model resets its placement, so it asks first.
	var source := doc.source()
	wizard.request_import(plane_path)
	await _settle()
	check("replacing a model asks first", confirm.visible and doc.source() == source
		and str(wizard.import_state().state) != "inspecting")
	check("dismissing the question keeps the model", wizard.dismiss_modal_for_exit() and not confirm.visible)
	await _settle()
	check("nothing was replaced", doc.source() == source and doc.placement_result().ok
		and str(wizard.import_state().state) != "inspecting")
	wizard.request_import(plane_path)
	await _settle()
	confirm.get_ok_button().pressed.emit()
	await _await_import(wizard)
	check("a confirmed replacement resets the placement and keeps the values", doc.source() != null and doc.source() != source
		and not doc.placement_result().ok and str(doc.placement().nose_axis).is_empty() and is_equal_approx(float(doc.value("wing/span")), _span_m))
	wizard.go_to_step("orient_size")
	await _settle()
	check("the replaced model shows nothing preselected", (_find(wizard, "NoseAxis") as OptionButton).selected == 0
		and (_find(wizard, "DatumY") as LineEdit).text.is_empty())


## Closing the screen while a model is inspected must neither crash nor adopt the result.
func _closing(plane_path: String) -> void:
	var second := _new_wizard()
	await _settle()
	second.request_import(plane_path)
	check("the second wizard is inspecting", str(second.import_state().state) == "inspecting")
	# A document change leaves a refresh queued: freeing the screen must drop it too.
	second.document().set_value("wing/span", 1.2)
	second.free()
	var deadline := Time.get_ticks_msec() + WORKER_TIMEOUT_MS
	var running: int = Creator.reap_abandoned_imports()
	while running > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
		running = Creator.reap_abandoned_imports()
	check("an abandoned inspection finishes and is released", running == 0)
	await _settle()
