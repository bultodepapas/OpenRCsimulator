extends SceneTree
## Import closeout: a converted ClearView helicopter test flies its appearance on the X-Cell .60 donor
## helicopter physics. The offer exists only for modelType 0, the donor route is unchanged without a
## Creator visual, the donor physics is the same with one, and AppRoot runs the trial lifecycle.
const AppRoot := preload("res://app_root.gd")
const Creator := preload("res://ui/aircraft_creator.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const FlightMain := preload("res://helicopter_main.gd")
const HeliDonor := preload("res://workshop/creator/clearview/heli_donor.gd")
const Setup := preload("res://workshop/creator/clearview/setup.gd")
const Package := preload("res://workshop/creator/clearview/package.gd")
const Converter := preload("res://workshop/creator/clearview/converter.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const VisualBuilder := preload("res://workshop/creator/visual_builder.gd")
const ChoicePanel := preload("res://ui/aircraft_creator_installation.gd")
const CvFixture := preload("res://tests/test_creator_clearview_readers.gd")
const Fixture := preload("res://tests/creator_fixtures.gd")
const Driver := preload("res://tests/ui_driver.gd")
const Preferences := preload("res://app_state/preferences.gd")
const Frames := preload("res://render/frames.gd")

const HELI_PARAMS := "verNumber 3\nmodelType 0\n"
const PLANE_PARAMS := "verNumber 5\nmodelType 1\nmodelName body.ac\n"
const TICKS := 240

var checks := 0
var failures := 0
var _directory := "user://clearview-heli-%d" % Time.get_ticks_usec()


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, good: bool, detail := "") -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ", label, " ", detail)


func _run() -> void:
	var heli := _converted(_heli_ac(0.3), HELI_PARAMS)
	var sized := _converted(_heli_ac(0.6), HELI_PARAMS)
	var plane := _converted(CvFixture._ac_fixture(), PLANE_PARAMS)
	check("fixtures convert", heli.ok and sized.ok and plane.ok)
	if not (heli.ok and sized.ok and plane.ok):
		_finish()
		return
	_offer(heli.value.source, plane.value.source)
	_placement(heli.value.source, sized.value.source)
	await _panel()
	await _wizard()
	_flights(heli.value.source, plane.value.source)
	await _app_trial(heli.value.source, plane.value.source)
	_finish()


## A body whose nose is at -X, a ClearView main-rotor disc and blade of `radius`, and a tail disc.
static func _heli_ac(radius: float) -> String:
	var objects := [
		["body", [[-0.4, -0.15, 0.0], [0.3, -0.1, 0.0], [0.0, 0.05, 0.05]]],
		["rotorDisk_movabledisk", [[-radius, 0.2, -radius], [radius, 0.2, -radius], [radius, 0.2, radius], [-radius, 0.2, radius]]],
		["rotorBlades_mainblade1", [[-0.02, 0.21, -radius], [0.02, 0.21, -radius], [0.02, 0.21, radius], [-0.02, 0.21, radius]]],
		["tailDisk_taildisk", [[0.3, 0.0, 0.02], [0.4, 0.0, 0.02], [0.4, 0.1, 0.02]]],
	]
	var text := "AC3Db\nMATERIAL \"m\" rgb 1 1 1 amb 0.2 0.2 0.2 emis 0 0 0 spec 0.5 0.5 0.5 shi 10 trans 0\nOBJECT world\nkids %d\n" % objects.size()
	for item: Array in objects:
		var points: Array = item[1]
		text += "OBJECT poly\nname \"%s\"\nnumvert %d\n" % [item[0], points.size()]
		for point: Array in points:
			text += "%s %s %s\n" % [point[0], point[1], point[2]]
		text += "numsurf 1\nSURF 0x30\nmat 0\nrefs %d\n" % points.size()
		for index: int in points.size():
			text += "%d 0 0\n" % index
		text += "kids 0\n"
	return text


static func _zip(ac: String, params: String) -> PackedByteArray:
	return CvFixture._zip_bytes([["Heli/params.txt", params.to_ascii_buffer()], ["Heli/data/body.ac", ac.to_ascii_buffer()]])


static func _converted(ac: String, params: String) -> Dictionary:
	var package := Package.inspect_bytes(_zip(ac, params))
	return Converter.convert(package.value, "Heli") if package.ok else package


func _offer(heli: RefCounted, plane: RefCounted) -> void:
	var ordinary := Importer.inspect_bytes(Fixture.airplane_glb(), "ordinary.glb")
	check("the donor offer is for a converted modelType 0 only", HeliDonor.is_helicopter(heli)
		and not HeliDonor.is_helicopter(plane) and ordinary.ok and not HeliDonor.is_helicopter(ordinary.value)
		and not HeliDonor.is_helicopter(null))
	var refused := Setup.propose(heli)
	check("the aeroplane setup still refuses a helicopter and names the offer", not refused.ok
		and refused.diagnostics[0].message == Setup.HELICOPTER and Setup.HELICOPTER.contains("Fly as a helicopter"))
	check("a modelType 1 model is not refused as a helicopter", Setup.propose(plane).ok
		or Setup.propose(plane).diagnostics[0].message != Setup.HELICOPTER)


func _placement(heli: RefCounted, sized: RefCounted) -> void:
	var donor_radius := 0.775
	var skid := 0.108
	var built := HeliDonor.build(heli, donor_radius, skid)
	check("the fixture helicopter builds", built.ok)
	if built.ok:
		var visual: Dictionary = built.value
		var scale := donor_radius / 0.3
		check("a rotor far from the donor's is shown at the donor rotor size", absf(float(visual.creator_scale) - scale) < 1e-6
			and absf(float(visual.model_rotor_radius_m) - donor_radius) < 1e-6)
		check("the lowest point sits on the donor skid plane", absf(visual.cg_model_m.y - (-0.15 * scale + skid)) < 1e-5
			and visual.cg_model_m.x == 0.0 and visual.cg_model_m.z == 0.0)
		var model_root: Node3D = visual.root
		var body := model_root.find_child("body", true, false) as MeshInstance3D
		var box: AABB = VisualBuilder.relative(model_root, body) * body.get_aabb() if body != null else AABB()
		check("ClearView -X nose maps to the render nose (-Z), metres, origin kept", body != null
			and absf(box.position.z + 0.4 * scale) < 1e-4 and absf(box.end.z - 0.3 * scale) < 1e-4
			and absf(box.position.y + 0.15 * scale) < 1e-4 and absf(box.end.y - 0.05 * scale) < 1e-4)
		var parts: Dictionary = visual.rotor_parts
		check("ClearView rotor parts are found by name", parts.main[0].size() == 1 and parts.main[1].size() == 1
			and parts.tail[0].size() == 1 and parts.tail[1].is_empty())
		HeliDonor.show_rotors(parts, 0.0, 0.0)
		var tail_disc: Node3D = parts.tail[0][0]
		check("a slow rotor shows its blades, not its disc", not (parts.main[0][0] as Node3D).visible and (parts.main[1][0] as Node3D).visible)
		HeliDonor.show_rotors(parts, 167.0, 778.0)
		check("a governed rotor shows its disc, not its blades", (parts.main[0][0] as Node3D).visible and not (parts.main[1][0] as Node3D).visible)
		check("a rotor without blade parts keeps its source look", tail_disc.visible)
		model_root.free()
	var near := HeliDonor.build(sized, donor_radius, skid)
	check("a rotor within 1.5 times the donor's keeps the model's size", near.ok and float(near.value.creator_scale) == 1.0
		and absf(near.value.cg_model_m.y - (-0.15 + skid)) < 1e-6)
	if near.ok:
		(near.value.root as Node3D).free()
	check("an invalid donor size is refused", not HeliDonor.build(sized, 0.0, skid).ok and not HeliDonor.build(sized, donor_radius, NAN).ok)
	# Audit 2026-11-17: a degenerate rotor (here 2 cm, shown 39 times larger) is refused, never shown absurdly.
	var tiny := _converted(_heli_ac(0.0001), HELI_PARAMS)
	check("a degenerate rotor is refused rather than scaled without bound", tiny.ok and not HeliDonor.build(tiny.value.source, donor_radius, skid).ok)
	# Without a named rotor, the model length stands in for its rotor diameter (body 0.7 m -> radius 0.35 m).
	var bare := _converted(_heli_ac(0.3).get_slice("OBJECT poly\nname \"rotorDisk", 0).replace("kids 4", "kids 1"), HELI_PARAMS)
	var bare_built := HeliDonor.build(bare.value.source, donor_radius, skid) if bare.ok else {ok = false}
	check("a helicopter without rotor parts is sized by its length", bare_built.ok
		and absf(float(bare_built.value.creator_scale) - donor_radius / 0.35) < 1e-4)
	if bare_built.ok:
		(bare_built.value.root as Node3D).free()
	check("an untyped flight payload source is not a helicopter", not HeliDonor.is_helicopter({}) and not HeliDonor.is_helicopter("x")
		and not HeliDonor.is_helicopter(heli.get_script()))


func _panel() -> void:
	var panel := ChoicePanel.new()
	root.add_child(panel)
	var setups := []
	var helis := []
	panel.setup_requested.connect(func(revision: int) -> void: setups.append(revision))
	panel.helicopter_requested.connect(func(revision: int) -> void: helis.append(revision))
	var proposal := {format = "clearview"}
	panel.show_state(1, 4, proposal, false, false, true)
	check("a helicopter offers the donor flight first", panel.focus_target() == panel._setup and panel._setup.visible
		and panel._setup.text == HeliDonor.OFFER and not panel._review.visible and not panel._choose.visible
		and not panel._qualification.visible)
	panel._setup.pressed.emit()
	check("the helicopter offer requests the donor flight, not the aeroplane setup", helis == [4] and setups.is_empty())
	panel.show_state(1, 4, proposal, false, true, true)
	panel._setup.pressed.emit()
	check("a busy import cannot start the donor flight", panel._setup.disabled and helis == [4])
	panel.show_state(1, 5, proposal, false, false)
	panel._setup.pressed.emit()
	check("an aeroplane keeps the automatic setup", panel._setup.text == ChoicePanel.SETUP and setups == [5] and helis == [4])
	panel.queue_free()
	await process_frame


func _wizard() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	var path := _directory + "/heli.zip"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(_zip(_heli_ac(0.3), HELI_PARAMS))
	file.close()
	var wizard := Creator.new()
	wizard.store_root = _directory + "/library"
	wizard.theme = UiTheme.build()
	root.add_child(wizard)
	await process_frame
	wizard.request_import(path)
	var deadline := Time.get_ticks_msec() + 30000
	while (wizard.import_state().state == "inspecting" or wizard.save_state().opening) and Time.get_ticks_msec() < deadline:
		await process_frame
	for index: int in 3:
		await process_frame
	var requests := []
	wizard.test_fly_requested.connect(func(payload: Dictionary) -> void: requests.append(payload))
	var offer := wizard.find_child("SetupClearView", true, false) as Button
	check("the imported helicopter shows the donor offer", wizard.import_state().state == "imported" and offer != null
		and offer.is_visible_in_tree() and offer.text == HeliDonor.OFFER)
	if offer != null:
		# A reopened draft is adopted without a source change: the helicopter offer must survive it.
		var reopened: RefCounted = wizard.document()
		wizard.set("_shown_helicopter", false)
		wizard.call("_adopt_document", reopened, "")
		for index: int in 2:
			await process_frame
		check("a reopened helicopter draft still shows the donor offer", offer.is_visible_in_tree() and offer.text == HeliDonor.OFFER)
		offer.pressed.emit()
		var dialog: ConfirmationDialog = wizard.get("_confirm")
		var text: Label = wizard.get("_confirm_text")
		check("the confirmation states the donor physics and that it is not the ClearView flight model",
			dialog.visible and dialog.ok_button_text == HeliDonor.ACCEPT and text.text.contains(HeliDonor.CONFIRM)
			and text.text.contains(HeliDonor.CONFIRM_PLACEMENT))
		dialog.hide()
		wizard.call("_on_confirmed")
	check("confirming requests a donor flight of the admitted appearance", requests.size() == 1
		and requests[0].has("creator_helicopter") and not requests[0].has("creator_candidate")
		and requests[0].creator_helicopter.source == wizard.document().source()
		and requests[0].start_choice in ["airborne", "ground"])
	wizard.queue_free()
	await process_frame


func _start(args: PackedStringArray, visual: Dictionary, start := "airborne") -> Node:
	var flight: Node = FlightMain.new()
	flight.interactive_start = true
	flight.start_choice = start
	flight.creator_visual = visual
	flight.set_user_args(args)
	root.add_child(flight)
	return flight


func _flights(heli: RefCounted, plane: RefCounted) -> void:
	var args := PackedStringArray(["--soundscape=off", "--physics-backend=gdscript_reference", "--lens=off"])
	var stock := _start(args, {})
	check("the stock route starts unchanged", stock.startup_error.is_empty() and stock._rotors != null
		and stock._night_kit != null and stock._creator_label.is_empty() and stock._airplane.has("main_rotor_pivot"))
	var donor := _start(args, {source = heli, name = "Fixture heli"})
	check("a ClearView helicopter starts on the donor route", donor.startup_error.is_empty() and donor.session != null
		and donor._rotors == null and donor._night_kit == null and donor._crash_presentation != null, donor.startup_error)
	check("the flight is labelled as donor physics with this appearance and its scale", donor._creator_label.contains("X-Cell .60")
		and donor._creator_label.contains("Fixture heli") and donor._creator_label.contains("258 %"), donor._creator_label)
	if stock.startup_error.is_empty() and donor.startup_error.is_empty():
		for tick: int in TICKS:
			stock.session.sim.step()
			donor.session.sim.step()
			donor._present(1.0 / 60.0, 1.0)
		check("donor physics is the stock X-Cell physics, tick for tick", donor.session.sim.tick == stock.session.sim.tick
			and donor.session.sim.state == stock.session.sim.state and donor.session.sim.continuous == stock.session.sim.continuous)
		check("the donor flight stays flyable without a crash", donor.session.is_flyable() and donor.session.crash.is_empty())
		var parts: Dictionary = donor._airplane.rotor_parts
		check("a governed donor rotor shows the model's disc", (parts.main[0][0] as Node3D).visible and not (parts.main[1][0] as Node3D).visible)
		var expected: Transform3D = Frames.root_transform(Frames.quat_to_render(donor.session.sim.state.slice(6, 10)),
			Frames.ned_to_render(donor.session.sim.state.slice(0, 3)), donor._airplane.cg_model_m)
		check("the model follows the donor body pose", (donor._airplane.root as Node3D).transform.is_equal_approx(expected))
	for flight: Node in [stock, donor]:
		root.remove_child(flight)
		flight.free()
	var grounded := _start(args, {source = heli, name = "Fixture heli"}, "ground")
	if grounded.startup_error.is_empty():
		grounded._present(1.0 / 60.0, 1.0)
		var lowest := INF
		for node: Node in (grounded._airplane.root as Node3D).find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.is_visible_in_tree():
				lowest = minf(lowest, (mesh.global_transform * mesh.get_aabb()).position.y)
		var at: Vector3 = (grounded._airplane.root as Node3D).position
		var ground: float = grounded._ground_height(at.x, at.z)
		var parts: Dictionary = grounded._airplane.rotor_parts
		check("a ground start rests the model on the ground with its blades shown", absf(lowest - ground) < 0.02
			and not (parts.main[0][0] as Node3D).visible and (parts.main[1][0] as Node3D).visible, "%s %s" % [lowest, ground])
	check("a ground start succeeds", grounded.startup_error.is_empty(), grounded.startup_error)
	root.remove_child(grounded)
	grounded.free()
	var wrong := _start(args, {source = plane, name = "Plane"})
	check("an aeroplane source cannot fly on the donor route", wrong.startup_error == HeliDonor.UNAVAILABLE)
	root.remove_child(wrong)
	wrong.free()


func _app_trial(heli: RefCounted, plane: RefCounted) -> void:
	var host := AppRoot.new()
	host.user_args = PackedStringArray()
	host.preferences_path = _directory + "/prefs.cfg"
	check("prepare preferences", Preferences.save_to(host.preferences_path, Preferences.DEFAULTS.duplicate(true)) == OK)
	root.add_child(host)
	var ui := Driver.new(self)
	await ui.settle()
	host.open_workshop()
	await ui.settle()
	var editor: Node = host.screens.top()
	check("Workshop opens from Home", host.screens.is_top("workshop"))
	host._start_workshop_trial({creator_helicopter = {source = plane, name = "Plane"}, start_choice = "airborne"})
	check("a non-helicopter request is refused in the Workshop", host.flight == null and host.screens.top() == editor)
	host._start_workshop_trial({creator_helicopter = {source = heli, name = "Fixture heli"}, start_choice = "airborne"})
	var flight: Node = host.flight
	check("the helicopter trial starts on the donor route", flight != null and flight.get_script() == FlightMain
		and flight.startup_error.is_empty() and not flight.creator_visual.is_empty() and host.screens.top() == null)
	if flight != null and flight.get_script() == FlightMain:
		host.open_pause()
		check("Pause names the Workshop trial build", host.pause_menu != null
			and host.pause_menu.identity_label.text.contains("Fixture heli"))
		host.end_flight()
		await ui.settle()
		check("ending the trial returns to the Workshop", host.flight == null and host.screens.top() == editor
			and (not is_instance_valid(flight) or flight.get_parent() == null))
	# AC-CV: an airship request flies the stock RC blimp with the imported appearance; a helicopter cannot use it.
	host._start_workshop_trial({creator_airship = {source = heli, name = "Fixture heli"}, start_choice = "airborne"})
	check("a helicopter cannot take the blimp route", host.ground_vehicle == null and host.screens.top() == editor)
	host._start_workshop_trial({creator_airship = {source = plane, name = "Fixture airship"}, start_choice = "airborne"})
	await ui.settle()
	var blimp: Node = host.ground_vehicle
	check("the airship trial starts the blimp activity with the imported model", blimp != null and blimp.name == "AirshipActivity"
		and str(blimp.startup_error).is_empty() and not blimp.creator_visual.is_empty()
		and blimp.visual.root.get_node_or_null("CreatorModel") != null and host.screens.top() == null)
	if blimp != null:
		host._return_to_workshop()
		await ui.settle()
		check("the blimp trial returns to the Workshop", host.ground_vehicle == null and host.screens.top() == editor)
	await ui.close_app(host)


func _finish() -> void:
	_remove_tree(ProjectSettings.globalize_path(_directory))
	print("ClearView helicopter donor: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _remove_tree(path: String) -> void:
	# Only this test's freshly allocated user:// directory is removed.
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child: String in directory.get_directories():
		_remove_tree(path.path_join(child))
	for child: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)
