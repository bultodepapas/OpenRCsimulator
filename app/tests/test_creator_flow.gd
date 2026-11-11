extends SceneTree
## AC-11: an unsaved Creator candidate flies through the real root and Main, then returns to the
## same Workshop screen. Rendering is headless; this checks ownership and wiring, not appearance.
const AppRoot := preload("res://app_root.gd")
const Driver := preload("res://tests/ui_driver.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const R := preload("res://workshop/creator/result.gd")
const CreatorTrial := preload("res://workshop/creator/trial.gd")
const RB := preload("res://physics/rigid_body.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, condition: bool, detail := "") -> void:
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _plane_stl() -> PackedByteArray:
	var triangles: Array = [
		[[0, 500, 0], [-40, -700, 0], [40, -700, 0]],
		[[-750, 100, 0], [750, 100, 0], [0, 200, 0]],
		[[0, -700, 0], [0, -620, 0], [0, -700, 120]],
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


func _payload(start: String) -> Dictionary:
	var document := Authoring.new()
	var admitted: Dictionary = Importer.inspect_bytes(_plane_stl(), "plane.stl")
	if not admitted.ok:
		return {}
	document.set_source(admitted.value)
	document.set_axis("nose_axis", "+y")
	document.set_axis("up_axis", "+z")
	document.set_units("mm")
	document.set_datum([0.0, 200.0, 0.0])
	document.apply_values(document.starting_values(), true)
	document.propose_inventory()
	var compiled: Dictionary = document.compile()
	if not compiled.ok:
		printerr("\n".join(R.texts(compiled)))
		return {}
	return {creator_candidate = compiled.value, creator_source = document.source(),
		creator_placement = document.placement(), creator_name = "Flow test", start_choice = start}


func _run() -> void:
	var host := AppRoot.new()
	host.user_args = PackedStringArray()
	host.preferences_path = "user://test_creator_flow.cfg"
	if FileAccess.file_exists(host.preferences_path):
		DirAccess.remove_absolute(host.preferences_path)
	root.add_child(host)
	var ui := Driver.new(self)
	await ui.settle()
	host.home.workshop_button.grab_focus()
	await ui.tap(KEY_ENTER)
	check("Workshop opens", host.screens.is_top("workshop"))
	var editor: Node = host.screens.top()
	check("Workshop offers the Creator", editor.find_child("OpenCreator", true, false) is Button)

	var payload: Dictionary = _payload("airborne")
	check("candidate prepared", not payload.is_empty())
	if payload.is_empty():
		_finish(host)
		return

	# Unsupported start: refused before anything is built, and never substituted.
	var runway: Dictionary = payload.duplicate()
	runway.start_choice = "runway"
	editor.trial_requested.emit(runway)
	check("runway start is refused for a gearless Creator aircraft", host.flight == null and host.screens.top() == editor)

	# A dictionary posing as an accepted candidate is refused.
	var forged: Dictionary = payload.duplicate()
	forged.creator_candidate = {ok = true}
	editor.trial_requested.emit(forged)
	check("a forged candidate is refused", host.flight == null and host.screens.top() == editor)

	for start: String in ["airborne", "hand_launch"]:
		payload.start_choice = start
		editor.trial_requested.emit(payload)
		check(start + ": trial starts", host.flight != null and host.flight.startup_error.is_empty(),
			"" if host.flight == null else str(host.flight.startup_error))
		if host.flight == null:
			continue
		var flight: Node = host.flight
		var session: Node = flight.session
		check(start + ": the compiled aircraft flies, not a catalog entry", str(flight.aircraft_id).begins_with("user-aircraft-")
			and not Catalog.has(flight.aircraft_id) and str(session.aircraft.model.id) == str(flight.aircraft_id))
		check(start + ": requested start kept", str(session.start_choice) == start and str(session.start_error).is_empty())
		var backend: Dictionary = session.stage_backend_status()
		check(start + ": reference evaluator pinned, native never requested", str(backend.requested) == "gdscript_reference"
			and str(backend.identity.backend) == "gdscript_reference")
		check(start + ": finite battery from the frozen record", str(session.aircraft.model.propulsion.get("battery", {}).get("kind", "")) == "ocv_resistance")
		var airplane: Dictionary = flight.get("_airplane")
		var visual: Node3D = airplane.get("root")
		check(start + ": runtime visual is in the world", visual != null and visual.is_inside_tree() and str(visual.name) == "airplane"
			and visual.find_child("stl_mesh", true, false) is MeshInstance3D and airplane.propeller is Node3D)
		check(start + ": the Workshop waits detached", not host.screens.is_top("workshop"))
		for _frame: int in 30:
			await process_frame
		var state: PackedFloat64Array = session.sim.state
		var finite := true
		for index: int in state.size():
			finite = finite and is_finite(state[index])
		check(start + ": flight state stays finite", finite and str(session.sim.fault_reason).is_empty())
		check(start + ": visual follows the simulated pose", visual.global_position.is_finite() and visual.global_position.length() > 0.0)
		host.open_pause()
		check(start + ": Pause opens over the trial", host.screens.is_top("pause"))
		check(start + ": Pause names the unsaved aircraft under test", host.pause_menu.identity_label.text.contains("Flow test"),
			host.pause_menu.identity_label.text)
		host.end_flight()
		await ui.settle()
		check(start + ": returns to the same Workshop screen", host.flight == null and host.screens.top() == editor)
	await _tampered_trial(payload)
	await _wizard_journey(host, editor, ui)
	_finish(host)


## Main verifies a Creator trial itself: a frozen dictionary edited after freezing never flies.
func _tampered_trial(payload: Dictionary) -> void:
	var trial: Dictionary = CreatorTrial.freeze(payload)
	check("tamper: trial freezes", trial.get("ok", false))
	if not trial.get("ok", false):
		return
	var edited: Dictionary = trial.duplicate(true)
	edited.data.model.mass_kg = 0.05
	var flight: Node = load("res://main.tscn").instantiate()
	flight.aircraft_id = str(trial.identity.aircraft_id)
	flight.workshop_trial = edited
	flight.start_choice = "airborne"
	flight.interactive_start = true
	root.add_child(flight)
	await process_frame
	check("tamper: Main refuses an edited frozen trial", not str(flight.startup_error).is_empty() and flight.session == null,
		str(flight.startup_error))
	flight.queue_free()
	await process_frame


## The player's own route: Workshop -> Create aircraft -> import a file -> place it -> starting
## values -> Test fly -> Pause -> back in the same wizard with the same document.
func _wizard_journey(host: Node, editor: Node, ui: RefCounted) -> void:
	var path := "user://creator-flow-test-%d.stl" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(_plane_stl())
	file.close()
	var open_button := editor.find_child("OpenCreator", true, false) as Button
	open_button.grab_focus()
	open_button.pressed.emit()
	await ui.settle()
	check("wizard: opens inside the Workshop screen", editor.creator_active() and host.screens.is_top("workshop"))
	var wizard: Control = editor.find_child("AircraftCreator", true, false) as Control
	check("wizard: the stock editor is hidden underneath", wizard != null and not (editor.find_child("WorkshopPanel", true, false) as Control).visible)
	if wizard == null:
		return
	check("wizard: a fresh Creator has nothing to lose", not editor.has_unsaved_changes() or not wizard.has_unsaved_changes())
	wizard.request_import(path)
	var deadline := Time.get_ticks_msec() + 20000
	while str(wizard.import_state().state) == "inspecting" and Time.get_ticks_msec() < deadline:
		await process_frame
	var document: RefCounted = wizard.document()
	check("wizard: model imported from a file", document.source() != null, str(wizard.import_state()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if document.source() == null:
		return
	document.set_axis("nose_axis", "+y")
	document.set_axis("up_axis", "+z")
	document.set_units("mm")
	document.set_datum([0.0, 200.0, 0.0])
	document.apply_values(document.starting_values(), true)
	document.propose_inventory()
	await ui.settle()
	check("wizard: unsaved work is reported to the host", editor.has_unsaved_changes())
	wizard.go_to_step("review_test")
	await ui.settle()
	var test_fly := wizard.find_child("TestFly", true, false) as Button
	check("wizard: Test fly is offered once nothing blocks it", test_fly != null and not test_fly.disabled and document.issues().is_empty(),
		"\n".join(R.texts({diagnostics = document.issues()})))
	if test_fly == null or test_fly.disabled:
		return
	var revision: int = document.revision
	test_fly.grab_focus()
	test_fly.pressed.emit()
	check("wizard: the trial starts from the button", host.flight != null and host.flight.startup_error.is_empty())
	if host.flight == null:
		return
	check("wizard: the imported aircraft is flying", str(host.flight.aircraft_id).begins_with("user-aircraft-"))
	for _frame: int in 10:
		await process_frame
	host.open_pause()
	host.end_flight()
	await ui.settle()
	check("wizard: return lands in the same wizard", host.flight == null and host.screens.top() == editor and editor.creator_active()
		and editor.find_child("AircraftCreator", true, false) == wizard)
	check("wizard: the document survived the flight unchanged", wizard.document() == document and document.revision == revision
		and document.source() != null and str(wizard.current_step()) == "review_test")

	# Escape walks back one step at a time; it never drops the aircraft from a later step.
	editor.call("_request_close")
	await ui.settle()
	check("wizard: Escape steps back inside the wizard", editor.creator_active() and str(wizard.current_step()) == "paint_skins"
		and editor.find_child("CreatorDiscardDialog", true, false) == null)
	# Leaving with unsaved work asks first; keeping the work keeps the wizard.
	wizard.close_requested.emit()
	await ui.settle()
	var discard := editor.find_child("CreatorDiscardDialog", true, false) as ConfirmationDialog
	check("wizard: leaving asks before discarding", discard != null and discard.visible and editor.creator_active())
	if discard != null:
		discard.canceled.emit()
		await ui.settle()
		check("wizard: Keep editing keeps the aircraft", editor.creator_active() and wizard.document().source() != null)
		editor.call("_request_creator_close")
		await ui.settle()
		discard = editor.find_child("CreatorDiscardDialog", true, false) as ConfirmationDialog
		if discard != null:
			discard.confirmed.emit()
			await ui.settle()
	check("wizard: discarding returns to the stock editor", not editor.creator_active()
		and (editor.find_child("WorkshopPanel", true, false) as Control).visible and host.screens.top() == editor)


func _finish(host: Node) -> void:
	if host.screens.is_top("workshop"):
		host.close_workshop()
	host.queue_free()
	await process_frame
	print("Creator flow: %d failures" % failures)
	quit(1 if failures else 0)
