extends SceneTree
## AC-13..17: the Aircraft Creator wizard saves, reopens and publishes aircraft through its library,
## backs up unsaved work, paints the model and binds its moving parts. Driven through the wizard's
## controls on an isolated library folder; the default library is never touched.
const Creator := preload("res://ui/aircraft_creator.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const Store := preload("res://workshop/creator/store.gd")
const CreatorTrial := preload("res://workshop/creator/trial.gd")
const Fixtures := preload("res://tests/creator_fixtures.gd")
const R := preload("res://workshop/creator/result.gd")

const WORKER_TIMEOUT_MS := 20000
const BACKUP_TIMEOUT_MS := 8000
const NAME := "Persist plane"

var failures := 0
var checks := 0
var payloads: Array = []
var _root_path := ""
var _glb_path := ""


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


func _find(node: Node, node_name: String) -> Node:
	return node.find_child(node_name, true, false)


func _new_wizard() -> Control:
	var wizard := Creator.new() as Control
	wizard.set("store_root", _root_path)
	wizard.theme = UiTheme.build()
	wizard.test_fly_requested.connect(func(payload: Dictionary) -> void: payloads.append(payload))
	root.add_child(wizard)
	await _settle(3)
	return wizard


## Waits by wall time for an import or an opening on the worker.
func _await_worker(wizard: Control) -> void:
	await _settle()
	var deadline := Time.get_ticks_msec() + WORKER_TIMEOUT_MS
	while (str(wizard.import_state().state) == "inspecting" or bool(wizard.save_state().opening)) \
			and Time.get_ticks_msec() < deadline:
		await process_frame
	await _settle(2)


## A fresh read-only view of the library: {drafts, aircraft, recovery}.
func _library() -> Dictionary:
	var opened: Dictionary = Store.open(_root_path, {"read_only": true})
	if not opened.ok:
		return {drafts = [], aircraft = [], recovery = [], archived_drafts = []}
	var store: RefCounted = opened.value
	return {drafts = store.list_drafts(false), archived_drafts = store.list_drafts(true), aircraft = store.list_aircraft(false),
		recovery = store.list_recovery()}


func _await_backup(draft_id: String) -> bool:
	var deadline := Time.get_ticks_msec() + BACKUP_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		for entry: Dictionary in _library().recovery:
			if str(entry.draft_id) == draft_id:
				return true
		await process_frame
	return false


func _has_backup(draft_id: String) -> bool:
	for entry: Dictionary in _library().recovery:
		if str(entry.draft_id) == draft_id:
			return true
	return false


func _type(edit: LineEdit, text: String) -> void:
	edit.grab_focus()
	edit.text = text
	edit.text_changed.emit(text)


func _enter(edit: LineEdit, text: String) -> void:
	_type(edit, text)
	edit.text_submitted.emit(text)
	await _settle()


func _choose(picker: OptionButton, value: Variant) -> void:
	for index: int in picker.item_count:
		if picker.get_item_metadata(index) == value:
			picker.select(index)
			picker.item_selected.emit(index)
			await _settle()
			return
	check("option %s offers %s" % [picker.name, value], false)


func _note(wizard: Control) -> String:
	var note := _find(wizard, "CreatorNote") as Label
	return note.text if note.is_visible_in_tree() else ""


## Sorted-key JSON: tells a whole number from a float, as the stored records do.
static func _exact(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _remove_tree(path: String) -> void:
	for directory: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(directory))
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


## Controls outside the viewport and content wider than its scroll area (as in test_creator_ui.gd).
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


func _unreachable(wizard: Control) -> PackedStringArray:
	var found := PackedStringArray()
	for node: Node in wizard.find_children("*", "Control", true, false):
		var control := node as Control
		if (control is BaseButton or control is LineEdit) and control.is_visible_in_tree() \
				and control.focus_mode != Control.FOCUS_ALL:
			found.append(str(control.name))
	return found


func _run() -> void:
	var orphans_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var stamp := Time.get_ticks_usec()
	_root_path = "user://creator-persistence-ui-%d" % stamp
	_glb_path = "user://creator-persistence-ui-%d.glb" % stamp
	var file := FileAccess.open(_glb_path, FileAccess.WRITE)
	file.store_buffer(Fixtures.airplane_glb())
	file.close()
	root.size = Vector2i(1920, 1080)

	var first := await _new_wizard()
	var saved := await _author(first)
	if not saved.is_empty():
		saved = await _save_and_publish(first, saved)
	first.free()
	await _settle(3)
	if not saved.is_empty():
		var second := await _reopen(saved)
		var third := await _recovery(second)
		var fourth := await _discard_recovery(third)
		await _open_aircraft(fourth, saved)
		await _archive(fourth)
		await _view_only(fourth)
		await _leave_guard(fourth)
		await _damaged_entry(fourth)
		fourth.free()
		await _settle(3)

	Creator.reap_abandoned_imports()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_glb_path))
	_remove_tree(ProjectSettings.globalize_path(_root_path))
	check("the test library folder is removed", not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_root_path)))
	await _settle(3)
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check("no orphan nodes are left", orphans == orphans_before, "%d before, %d after" % [orphans_before, orphans])
	if orphans != orphans_before:
		Node.print_orphan_nodes()
	print("Creator persistence UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## Import the GLB fixture, place it, fill it, bind its parts and paint it. Returns {} on a setup failure.
func _author(wizard: Control) -> Dictionary:
	var state: Dictionary = wizard.save_state()
	check("an empty library opens for writing", bool(state.writable) and str(state.state) == "saved", str(state))
	check("the header shows the save state", (_find(wizard, "SaveState") as Label).text == Creator.STATE_SAVED)
	for node_name: String in ["OpenLibrary", "SaveDraft"]:
		check("%s is offered" % node_name, (_find(wizard, node_name) as Button).is_visible_in_tree()
			and not (_find(wizard, node_name) as Button).disabled)
	wizard.request_import(_glb_path)
	await _await_worker(wizard)
	var doc: Authoring = wizard.document()
	check("the GLB fixture is imported", doc.source() != null, str(wizard.import_state()))
	if doc.source() == null:
		return {}
	check("an imported model is unsaved work", wizard.has_unsaved_changes() and (_find(wizard, "SaveState") as Label).text == Creator.STATE_UNSAVED)
	doc.set_axis("nose_axis", str(Fixtures.AIRPLANE_PLACEMENT.nose_axis))
	doc.set_axis("up_axis", str(Fixtures.AIRPLANE_PLACEMENT.up_axis))
	# The fixture's own scale of 0.5 m per unit, through the known-wingspan path (no unit names it).
	var low: PackedFloat64Array = doc.source().bounds_min()
	var high: PackedFloat64Array = doc.source().bounds_max()
	doc.set_scale_from_wingspan((high[0] - low[0]) * float(Fixtures.AIRPLANE_PLACEMENT.unit_scale))
	check("the fixture is placed at its own scale", is_equal_approx(float(doc.placement().unit_scale),
		float(Fixtures.AIRPLANE_PLACEMENT.unit_scale)), str(doc.placement()))
	doc.set_datum(Fixtures.AIRPLANE_PLACEMENT.datum)
	doc.apply_values(doc.starting_values(), true)
	# The fixture's tail sits far aft for its wing: smaller tail surfaces bring it inside the package domain.
	doc.apply_values({"horizontal_tail/chord": float(doc.value("horizontal_tail/chord")) * 0.6,
		"vertical_tail/height": float(doc.value("vertical_tail/height")) * 0.75}, true)
	doc.propose_inventory()
	# The fixture's fuselage is short: the battery moves aft until the balance is inside the package domain.
	var step := float(doc.value("wing/root_chord")) * 0.05
	for _attempt: int in 40:
		if float(doc.summary().get("static_margin", 0.0)) <= 0.2:
			break
		doc.apply_values({"equipment/battery_position/0": float(doc.value("equipment/battery_position/0")) + step}, true)
	await _settle()

	# Estimated values carry a marker until the player types their own.
	wizard.go_to_step("aircraft_layout")
	await _settle()
	var span_badge := _find(wizard, "FieldWingSpanEstimate") as Label
	var chord_badge := _find(wizard, "FieldWingRootChordEstimate") as Label
	var dihedral := _find(wizard, "FieldWingDihedralDeg") as LineEdit
	check("the dihedral field appears through the generic fields", dihedral != null and dihedral.is_visible_in_tree())
	check("estimated values show their marker", span_badge.is_visible_in_tree() and chord_badge.is_visible_in_tree()
		and span_badge.text == "Estimated value")
	await _enter(_find(wizard, "FieldWingRootChord") as LineEdit, Authoring.format_number(float(doc.value("wing/root_chord")) + 0.001))
	check("a typed value loses its marker", not chord_badge.is_visible_in_tree() and not doc.is_estimated("wing/root_chord")
		and span_badge.is_visible_in_tree())

	await _bind_parts(wizard, doc)
	await _paint(wizard, doc)
	var issues: Array = doc.issues()
	check("the placed, filled fixture has no issue", issues.is_empty(), "\n".join(R.texts({diagnostics = issues})))
	if not issues.is_empty():
		return {}

	# Test fly carries the moving parts and the paint, and the trial accepts them.
	wizard.go_to_step("review_test")
	await _settle(2)
	(_find(wizard, "TestFly") as Button).pressed.emit()
	check("Test fly emits one payload", payloads.size() == 1)
	if payloads.size() == 1:
		var payload: Dictionary = payloads[0]
		check("the payload carries the bound parts", _exact(payload.get("creator_bindings")) == _exact(Fixtures.airplane_bindings()),
			_exact(payload.get("creator_bindings")))
		check("the payload carries the paint", payload.get("creator_appearance") == {"mode": "solid", "color": "#1e4fa3"})
		var frozen: Dictionary = CreatorTrial.freeze(payload)
		check("the trial accepts the payload's parts and paint", frozen.get("ok", false), str(frozen.get("errors", [])))
	return {doc = doc}


func _bind_parts(wizard: Control, doc: Authoring) -> void:
	wizard.go_to_step("controls_ground")
	await _settle(2)
	var motion := _find(wizard, "MotionState") as Label
	check("the Controls step lists the GLB parts", (_find(wizard, "PartsList") as Control).is_visible_in_tree()
		and not (_find(wizard, "PartsStlNote") as Control).is_visible_in_tree())
	check("nothing is bound at first", doc.bindings().is_empty() and motion.text == Creator.STATIC_VISUAL, motion.text)
	var slots := {}
	for role: String in Fixtures.SURFACES:
		var listed: Array = Fixtures.SURFACES[role]
		for slot: int in listed.size():
			slots["%s%d" % [role.to_pascal_case(), slot]] = listed[slot]
	for suffix: String in slots:
		var part: Dictionary = slots[suffix]
		await _choose(_find(wizard, "BindPart" + suffix) as OptionButton, int(part.node))
		var axis := _find(wizard, "BindAxis" + suffix) as OptionButton
		var reversed := _find(wizard, "BindReversed" + suffix) as CheckButton
		check("%s: choosing a part suggests its axis and direction" % suffix, str(axis.get_item_metadata(axis.selected)) == str(part.letter)
			and reversed.button_pressed == (int(part.sign) < 0), "%s %s" % [axis.get_item_metadata(axis.selected), reversed.button_pressed])
	await _choose(_find(wizard, "BindPartPropeller0") as OptionButton, Fixtures.PROPELLER_NODE)
	check("binding every fixture part gives the fixture bindings", _exact(doc.bindings()) == _exact(Fixtures.airplane_bindings()),
		_exact(doc.bindings()))
	check("the read-out says that bound parts move", motion.text == Creator.MOVING_VISUAL, motion.text)
	check("the builder's origin advice is shown", (_find(wizard, "PartsOriginNote") as Control).is_visible_in_tree())

	# A part bound twice is an issue on this step with its field focus.
	var second := _find(wizard, "BindPartElevator1") as OptionButton
	await _choose(second, int(Fixtures.SURFACES.elevator[0].node))
	await _settle()
	var error := _find(wizard, "BindErrorElevator1") as Label
	check("a part bound twice is reported on its row", error.is_visible_in_tree() and error.text.contains("more than once"), error.text)
	wizard.go_to_step("review_test")
	await _settle(2)
	var jump: Button
	for row: Node in (_find(wizard, "IssueList") as Control).get_children():
		if row is Button and (row as Button).text.contains("more than once"):
			jump = row
	check("the binding problem blocks Test fly as an issue", jump != null and (_find(wizard, "TestFly") as Button).disabled)
	if jump != null:
		jump.pressed.emit()
		await _settle(3)
		check("the issue focuses the part's control", wizard.current_step() == "controls_ground"
			and root.gui_get_focus_owner() == second, str(root.gui_get_focus_owner()))
	await _choose(second, int(Fixtures.SURFACES.elevator[1].node))
	check("the corrected binding is the fixture's again", _exact(doc.bindings()) == _exact(Fixtures.airplane_bindings()))

	# Show movement animates the bound parts and stops on leaving the step.
	var preview: Control = wizard.preview()
	var aileron := _bound_node(preview, "aileron")
	var rest: Transform3D = aileron.transform if aileron != null else Transform3D.IDENTITY
	var show := _find(wizard, "ShowMovement") as Button
	show.button_pressed = true
	for _frame: int in 20:
		await process_frame
	await create_timer(0.2).timeout
	aileron = _bound_node(preview, "aileron")
	check("Show movement moves a bound part", aileron != null and not aileron.transform.is_equal_approx(rest),
		str(aileron.transform) if aileron != null else "missing")
	wizard.go_to_step("paint_skins")
	await _settle(2)
	check("leaving the step stops the movement", not show.button_pressed and not wizard.is_processing())
	aileron = _bound_node(preview, "aileron")
	check("the stopped part is back at rest", aileron != null and aileron.transform.is_equal_approx(rest))

	# Layout with every row shown, at the primary and the compact target.
	wizard.go_to_step("controls_ground")
	await _settle(3)
	check("1080p: the moving parts fit", _layout_problems(wizard).is_empty(), "\n".join(_layout_problems(wizard)))
	check("1080p: every part control is reachable by focus", _unreachable(wizard).is_empty(), ", ".join(_unreachable(wizard)))
	UiTheme.compact_layout = true
	wizard.theme = UiTheme.build()
	root.size = Vector2i(1280, 720)
	await _settle(4)
	check("720p: the moving parts fit", _layout_problems(wizard).is_empty(), "\n".join(_layout_problems(wizard)))
	wizard.go_to_step("paint_skins")
	await _settle(3)
	check("720p: the paint step fits", _layout_problems(wizard).is_empty(), "\n".join(_layout_problems(wizard)))
	wizard.go_to_step("review_test")
	await _settle(3)
	check("720p: the review step with Save aircraft fits", _layout_problems(wizard).is_empty(), "\n".join(_layout_problems(wizard)))
	UiTheme.compact_layout = false
	wizard.theme = UiTheme.build()
	root.size = Vector2i(1920, 1080)
	await _settle(4)


## The first mesh node under the preview whose name starts with `prefix`.
func _bound_node(preview: Control, prefix: String) -> Node3D:
	var shown := preview.find_child("airplane", true, false)
	if shown == null:
		return null
	for node: Node in shown.find_children(prefix + "*", "MeshInstance3D", true, false):
		return node as Node3D
	return null


func _paint(wizard: Control, doc: Authoring) -> void:
	wizard.go_to_step("paint_skins")
	await _settle(2)
	var original := _find(wizard, "PaintOriginal") as Button
	var solid := _find(wizard, "PaintSolid") as Button
	check("the paint starts original", original.button_pressed and not solid.button_pressed and doc.appearance() == {"mode": "original"})
	(_find(wizard, "PaintSwatchBlue") as Button).pressed.emit()
	await _settle(2)
	check("a swatch paints the whole model one colour", doc.appearance() == {"mode": "solid", "color": "#1e4fa3"}
		and solid.button_pressed and not original.button_pressed and solid.text.contains("Selected"))
	var mesh := _bound_node(wizard.preview(), "body")
	var material := mesh.mesh.surface_get_material(0) as StandardMaterial3D if mesh != null else null
	check("the preview shows the paint", material != null and material.resource_name == "creator_solid"
		and material.albedo_color.is_equal_approx(Color.html("#1e4fa3")), str(material))
	original.pressed.emit()
	await _settle(2)
	mesh = _bound_node(wizard.preview(), "body")
	material = mesh.mesh.surface_get_material(0) as StandardMaterial3D if mesh != null else null
	check("Original restores the model's own look", doc.appearance() == {"mode": "original"} and material != null
		and material.resource_name != "creator_solid")
	solid.pressed.emit()
	await _settle(2)
	check("Solid colour reuses the chosen colour", doc.appearance() == {"mode": "solid", "color": "#1e4fa3"},
		str(doc.appearance()))


## Save draft, Ctrl+S, a stale save, and two published versions. Returns what a reopen must match.
func _save_and_publish(wizard: Control, saved: Dictionary) -> Dictionary:
	var doc: Authoring = saved.doc
	var save := _find(wizard, "SaveDraft") as Button
	var name_edit := _find(wizard, "AircraftName") as LineEdit
	save.pressed.emit()
	await _settle()
	check("saving without a name asks for one", _note(wizard) == Creator.NEEDS_NAME and root.gui_get_focus_owner() == name_edit
		and _library().drafts.is_empty() and wizard.has_unsaved_changes())
	_type(name_edit, NAME)
	save.pressed.emit()
	await _settle()
	var listed: Array = _library().drafts
	check("Save draft stores one named draft", listed.size() == 1 and str(listed[0].name) == NAME
		and str(listed[0].draft_id) == doc.draft_id and str(listed[0].record_sha256) == doc.saved_record_sha256)
	check("after saving nothing is unsaved", not wizard.has_unsaved_changes() and not doc.has_unsaved_changes()
		and (_find(wizard, "SaveState") as Label).text == Creator.STATE_SAVED and _note(wizard).is_empty())

	# Ctrl+S saves the next change.
	var first_hash := doc.saved_record_sha256
	_type(name_edit, NAME + " 2")
	await _settle()
	check("a change is unsaved again", wizard.has_unsaved_changes())
	var key := InputEventKey.new()
	key.keycode = KEY_S
	key.physical_keycode = KEY_S
	key.ctrl_pressed = true
	key.pressed = true
	Input.parse_input_event(key)
	await _settle()
	var released := key.duplicate() as InputEventKey
	released.pressed = false
	Input.parse_input_event(released)
	await _settle()
	check("Ctrl+S saves the draft", not wizard.has_unsaved_changes() and doc.saved_record_sha256 != first_hash
		and str(_library().drafts[0].name) == NAME + " 2")
	var second_hash := doc.saved_record_sha256

	# A save based on a stale record is refused and changes nothing.
	_type(name_edit, NAME)
	await _settle()
	doc.saved_record_sha256 = first_hash
	save.pressed.emit()
	await _settle()
	check("a stale save is refused with the store's message", _note(wizard) == Store.M_DRAFT_CONFLICT
		and doc.saved_record_sha256 == first_hash and wizard.has_unsaved_changes()
		and str(_library().drafts[0].record_sha256) == second_hash, _note(wizard))
	doc.saved_record_sha256 = second_hash
	save.pressed.emit()
	await _settle()
	check("the current record saves again", not wizard.has_unsaved_changes() and str(_library().drafts[0].name) == NAME)

	# Publish version 1, change the paint, publish version 2.
	wizard.go_to_step("review_test")
	await _settle(2)
	var publish := _find(wizard, "SaveAircraft") as Button
	check("Save aircraft sits beside Test fly and is enabled", publish.is_visible_in_tree() and not publish.disabled
		and (_find(wizard, "TestFly") as Button).is_visible_in_tree())
	check("the review keeps its estimate notice", (_find(wizard, "EstimateNotice") as Control).is_visible_in_tree())
	publish.pressed.emit()
	await _settle()
	var aircraft: Array = _library().aircraft
	check("Save aircraft publishes version 1", doc.published_revision == 1 and aircraft.size() == 1
		and int(aircraft[0].revisions) == 1 and str(aircraft[0].aircraft_uuid) == doc.aircraft_uuid()
		and _note(wizard) == Creator.SAVED_AS_VERSION % 1, _note(wizard))
	check("publishing leaves nothing unsaved", not wizard.has_unsaved_changes()
		and str(_library().drafts[0].aircraft_uuid) == doc.aircraft_uuid())
	wizard.go_to_step("paint_skins")
	await _settle()
	(_find(wizard, "PaintSwatchGreen") as Button).pressed.emit()
	await _settle()
	wizard.go_to_step("review_test")
	await _settle(2)
	publish.pressed.emit()
	await _settle()
	aircraft = _library().aircraft
	check("Save aircraft publishes version 2", doc.published_revision == 2 and aircraft.size() == 1
		and int(aircraft[0].revisions) == 2 and _note(wizard) == Creator.SAVED_AS_VERSION % 2, _note(wizard))
	var compiled: Dictionary = doc.compile()
	check("the published document compiles", compiled.ok)
	if not compiled.ok:
		return {}
	return {fingerprint = doc.fingerprint(), raw_sha256 = compiled.value.raw_sha256(), draft_id = doc.draft_id,
		aircraft_uuid = doc.aircraft_uuid(), bindings = _exact(doc.bindings())}


## A fresh wizard opens the saved draft from the library: same content, same compiled bytes.
func _reopen(saved: Dictionary) -> Control:
	var wizard := await _new_wizard()
	check("a saved draft leaves no recovery question", not (_find(wizard, "CreatorRecoveryDialog") as Window).visible)
	(_find(wizard, "OpenLibrary") as Button).pressed.emit()
	await _settle(2)
	var library := _find(wizard, "CreatorLibrary") as Window
	var drafts := _find(library, "DraftList") as Control
	var aircraft := _find(library, "AircraftList") as Control
	check("Open… shows the library", library.visible and drafts.get_child_count() == 1 and aircraft.get_child_count() == 1)
	var aircraft_entry := _find(aircraft, "Entry") as Label
	check("a saved aircraft lists its name, date and versions", aircraft_entry != null and aircraft_entry.text.begins_with(NAME)
		and aircraft_entry.text.contains("Versions: 2"), aircraft_entry.text if aircraft_entry != null else "")
	check("the library focuses its first entry", library.gui_get_focus_owner() == _find(drafts, "Open"), str(library.gui_get_focus_owner()))
	(_find(drafts, "Open") as Button).pressed.emit()
	await _await_worker(wizard)
	var doc: Authoring = wizard.document()
	check("the draft is opened", not library.visible and doc.source() != null and doc.draft_id == str(saved.draft_id))
	check("the reopened draft has the same fingerprint", doc.fingerprint() == str(saved.fingerprint))
	var compiled: Dictionary = doc.compile()
	check("the reopened draft compiles to the same bytes", compiled.ok and compiled.value.raw_sha256() == str(saved.raw_sha256))
	check("the reopened draft is saved, linked and keeps its parts", not wizard.has_unsaved_changes()
		and doc.published_revision == 2 and doc.aircraft_uuid() == str(saved.aircraft_uuid) and _exact(doc.bindings()) == str(saved.bindings))
	check("the name box shows the reopened name", (_find(wizard, "AircraftName") as LineEdit).text == NAME)
	return wizard


## Unsaved work is backed up after a quiet moment and offered when the Creator opens again.
func _recovery(wizard: Control) -> Control:
	var doc: Authoring = wizard.document()
	wizard.go_to_step("paint_skins")
	await _settle()
	(_find(wizard, "PaintSwatchRed") as Button).pressed.emit()
	await _settle()
	check("a change is backed up after a quiet moment", await _await_backup(doc.draft_id))
	var draft_id := doc.draft_id
	wizard.free()
	await _settle(3)
	var next := await _new_wizard()
	await _settle(2)
	var dialog := _find(next, "CreatorRecoveryDialog") as ConfirmationDialog
	check("opening asks about the newer backup", dialog.visible and dialog.dialog_text.contains(NAME), dialog.dialog_text)
	dialog.get_ok_button().pressed.emit()
	await _await_worker(next)
	var recovered: Authoring = next.document()
	check("the recovered draft is open and still unsaved", recovered.draft_id == draft_id
		and recovered.appearance() == {"mode": "solid", "color": "#c62828"} and next.has_unsaved_changes())
	(_find(next, "SaveDraft") as Button).pressed.emit()
	await _settle()
	check("saving the recovered draft clears its backup", not next.has_unsaved_changes() and not _has_backup(draft_id)
		and _library().drafts.size() == 1, _note(next))
	return next


func _discard_recovery(wizard: Control) -> Control:
	var doc: Authoring = wizard.document()
	await _enter(_find(wizard, "AircraftName") as LineEdit, NAME + " backup")
	check("the renamed draft is backed up", await _await_backup(doc.draft_id))
	var draft_id := doc.draft_id
	wizard.free()
	await _settle(3)
	var next := await _new_wizard()
	await _settle(2)
	var dialog := _find(next, "CreatorRecoveryDialog") as ConfirmationDialog
	check("the backup is offered again", dialog.visible)
	dialog.custom_action.emit(&"discard")
	await _settle()
	check("Discard it removes the backup", not dialog.visible and not _has_backup(draft_id) and not next.has_unsaved_changes())
	return next


## A saved aircraft opens as a new draft linked to it: Save aircraft publishes the next version.
func _open_aircraft(wizard: Control, saved: Dictionary) -> void:
	wizard.open_library()
	await _settle(2)
	var library := _find(wizard, "CreatorLibrary") as Window
	(_find(_find(library, "AircraftList"), "Open") as Button).pressed.emit()
	await _await_worker(wizard)
	var doc: Authoring = wizard.document()
	check("the aircraft opens as a new draft of it", doc.aircraft_uuid() == str(saved.aircraft_uuid) and doc.published_revision == 2
		and doc.draft_id != str(saved.draft_id) and doc.name == NAME and doc.appearance() == {"mode": "solid", "color": "#2e7d32"})
	wizard.go_to_step("review_test")
	await _settle(2)
	(_find(wizard, "SaveAircraft") as Button).pressed.emit()
	await _settle()
	var aircraft: Array = _library().aircraft
	check("publishing it adds version 3 to the same aircraft", doc.published_revision == 3 and aircraft.size() == 1
		and int(aircraft[0].revisions) == 3 and _library().drafts.size() == 2, _note(wizard))


func _archive(wizard: Control) -> void:
	wizard.open_library()
	await _settle(2)
	var library := _find(wizard, "CreatorLibrary") as Window
	var drafts := _find(library, "DraftList") as Control
	var before: int = _library().drafts.size()
	(_find(drafts.get_child(0), "Archive") as Button).pressed.emit()
	await _settle(2)
	check("Archive hides a draft", _library().drafts.size() == before - 1 and _library().archived_drafts.size() == before
		and drafts.get_child_count() == before - 1)
	(_find(library, "ShowArchived") as CheckButton).button_pressed = true
	await _settle(2)
	var restore: Button
	for row: Node in drafts.get_children():
		var entry := _find(row, "Entry") as Label
		if entry != null and entry.text.contains("Archived"):
			restore = _find(row, "Archive") as Button
	check("Show archived lists it with Restore", drafts.get_child_count() == before and restore != null and restore.text == "Restore")
	if restore != null:
		restore.pressed.emit()
		await _settle(2)
	check("Restore shows it again", _library().drafts.size() == before)
	(_find(library, "ShowArchived") as CheckButton).button_pressed = false
	check("Back closes the library", wizard.handle_back() and not library.visible)
	await _settle(2)


## A second wizard on the same library while the first holds it is view-only and says why.
func _view_only(holder: Control) -> void:
	var other := await _new_wizard()
	var state: Dictionary = other.save_state()
	check("the second wizard is view-only", not bool(state.writable) and str(state.state) == "view_only"
		and (_find(other, "SaveState") as Label).text == Creator.STATE_VIEW_ONLY)
	check("it shows the store's reason", _note(other) == Store.M_LOCK_BUSY, _note(other))
	check("saving is disabled with the reason", (_find(other, "SaveDraft") as Button).disabled
		and (_find(other, "SaveDraft") as Button).tooltip_text == Store.M_LOCK_BUSY)
	other.open_library()
	await _settle(2)
	var library := _find(other, "CreatorLibrary") as Window
	var archive := _find(_find(library, "DraftList"), "Archive") as Button
	check("a view-only library lists entries without Archive", library.visible and archive != null and archive.disabled)
	other.dismiss_modal_for_exit()
	other.free()
	await _settle(3)
	check("the holder still writes", bool(holder.save_state().writable))


func _leave_guard(wizard: Control) -> void:
	var calls: Array[String] = []
	var proceed := func() -> void: calls.append("proceed")
	var cancel := func() -> void: calls.append("cancel")
	var dialog := _find(wizard, "CreatorLeaveDialog") as ConfirmationDialog
	wizard.confirm_leave(proceed, cancel)
	check("without changes leaving proceeds at once", calls == ["proceed"] and not dialog.visible)
	var name_edit := _find(wizard, "AircraftName") as LineEdit

	calls.clear()
	_type(name_edit, NAME + " keep")
	wizard.confirm_leave(proceed, cancel)
	await _settle()
	check("unsaved changes ask first", dialog.visible and calls.is_empty())
	dialog.get_cancel_button().pressed.emit()
	await _settle()
	check("Keep editing cancels", calls == ["cancel"] and not dialog.visible and wizard.has_unsaved_changes())

	calls.clear()
	wizard.confirm_leave(proceed, cancel)
	await _settle()
	check("Back on the question keeps editing", wizard.handle_back() and calls == ["cancel"] and not dialog.visible)

	calls.clear()
	var doc: Authoring = wizard.document()
	check("the change is backed up before discarding", await _await_backup(doc.draft_id))
	wizard.confirm_leave(proceed, cancel)
	await _settle()
	dialog.custom_action.emit(&"discard")
	await _settle()
	check("Discard changes proceeds and drops the backup", calls == ["proceed"] and not dialog.visible
		and not _has_backup(doc.draft_id))

	calls.clear()
	var saved_before := doc.saved_record_sha256
	wizard.confirm_leave(proceed, cancel)
	await _settle()
	dialog.get_ok_button().pressed.emit()
	await _settle()
	check("Save draft and leave saves, then proceeds", calls == ["proceed"] and not wizard.has_unsaved_changes()
		and doc.saved_record_sha256 != saved_before)

	calls.clear()
	_type(name_edit, "")
	wizard.confirm_leave(proceed, cancel)
	await _settle()
	dialog.get_ok_button().pressed.emit()
	await _settle()
	check("Save draft and leave without a name stays", calls == ["cancel"] and _note(wizard) == Creator.NEEDS_NAME)
	_type(name_edit, NAME)
	(_find(wizard, "SaveDraft") as Button).pressed.emit()
	await _settle()


## A damaged record costs only its own entry: the library says why and keeps listing.
func _damaged_entry(wizard: Control) -> void:
	var listed: Array = _library().drafts
	if listed.is_empty():
		check("a draft to damage", false)
		return
	var target: Dictionary = listed.back()
	var sha := str(target.record_sha256)
	var object_path := ProjectSettings.globalize_path(_root_path).path_join("objects").path_join(sha.substr(0, 2)).path_join(sha)
	var broken := FileAccess.open(object_path, FileAccess.WRITE)
	check("the record file can be damaged for the test", broken != null)
	if broken == null:
		return
	broken.store_buffer("{\"damaged\": true}\n".to_utf8_buffer())
	broken.close()
	var before: Authoring = wizard.document()
	wizard.open_library()
	await _settle(2)
	var library := _find(wizard, "CreatorLibrary") as Window
	var drafts := _find(library, "DraftList") as Control
	var row: Node
	for candidate: Node in drafts.get_children():
		if str(candidate.get_meta("id", "")) == str(target.draft_id):
			row = candidate
	if row != null:
		(_find(row, "Open") as Button).pressed.emit()
		await _settle(2)
	var message := _find(library, "LibraryMessage") as Label
	check("a damaged draft shows the store's message in the library", row != null and library.visible and message.visible
		and message.text.begins_with("Part of this saved item is damaged"), message.text)
	check("the list and the document are untouched", drafts.get_child_count() == listed.size() and wizard.document() == before)
	wizard.dismiss_modal_for_exit()
	await _settle()
