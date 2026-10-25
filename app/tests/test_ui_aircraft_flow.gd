# UI-34b–d (UI-30 audit AS-2, AS-5, AS-6, AS-8, AS-9, AS-11, HN-7, SP-1, SP-7): choosing an aircraft shows what it is,
# the preview never contradicts the selection, and the helicopter no longer closes unrelated activities.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_aircraft_flow.gd
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const PREFS := "user://test_ui_aircraft_flow.cfg"
const HELICOPTER := "xcell-60-research"

var _failures := 0
var ui: RefCounted


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ui = UiDriver.new(self)
	await _run()
	print("UI aircraft flow: %d failed" % _failures)
	quit(1 if _failures else 0)


func _run() -> void:
	TranslationServer.set_locale("en")
	for suffix in ["", ".display", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))

	# --- AS-9 / AS-8: the catalog owns short names and answers capability questions consistently.
	var names_ok := true
	var capability_ok := true
	for id: String in Catalog.ids():
		names_ok = names_ok and not Catalog.short_name(id).is_empty()
		capability_ok = capability_ok and Catalog.runway_supported(id) == FlightSession.runway_aircraft_supported(id) \
			and Catalog.runway_supported(id) == FlightSession.runway_aircraft_supported(id) # second answer is cached
	_check("every catalog entry has a short name", names_ok)
	_check("cached runway capability matches the session's validation", capability_ok)

	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	root.size = Vector2i(1920, 1080) # after startup: the shell's resize handler applies the desktop canvas
	for frame in 4: await process_frame
	var home: Control = app.home
	_check("the test runs on a desktop canvas", home.get_viewport_rect().size == Vector2(1920, 1080), str(home.get_viewport_rect().size))

	# --- AS-9 / SP-7: the helicopter card uses its short name, so the default Flight page never scrolls.
	app.set_aircraft(HELICOPTER)
	var preview_deadline := Time.get_ticks_msec() + 15000
	while app.home_scene.preview_pending and Time.get_ticks_msec() < preview_deadline:
		await process_frame # the asynchronous model load shows a temporary "Loading…" line
	for frame in 4: await process_frame
	var scroll: ScrollContainer = home.get_node("HomeRail/HomeContentScroll")
	_check("helicopter card shows the catalog short name", home.aircraft_name_label.text == Catalog.short_name(HELICOPTER),
		home.aircraft_name_label.text)
	_check("helicopter Flight page fits without scrolling at 1080p", not scroll.get_v_scroll_bar().visible,
		"scroll=%s page=%s viewport=%s" % [scroll.size, home._pages[0].get_combined_minimum_size(), home.get_viewport_rect().size])

	# --- AS-6: the helicopter selection does not close Workshop or Natural Random.
	_check("Workshop stays available with the helicopter selected", not home.workshop_button.disabled)
	_check("Natural Random stays available with the helicopter selected", not home.natural_random_button.disabled)

	# --- AS-11: the Natural Random briefing previews the airplane it describes, and Back restores Home's selection.
	app.open_natural_random(home.natural_random_button)
	await ui.settle()
	var drawn := ""
	if app.screens.is_top("natural_random"):
		drawn = str(app.natural_random_screen.get("_scenario").get("aircraft_id", ""))
	_check("Natural Random opens with the helicopter selected", app.screens.is_top("natural_random") and not drawn.is_empty())
	_check("the briefing previews the drawn airplane", app.home_scene.requested_aircraft == drawn,
		"%s vs %s" % [app.home_scene.requested_aircraft, drawn])
	app.close_natural_random()
	await ui.settle()
	_check("Back restores Home's aircraft preview", app.home_scene.requested_aircraft == HELICOPTER)

	# --- AS-6: Workshop opens on an airplane when the helicopter is selected.
	app.open_workshop(home.workshop_button)
	await ui.settle()
	var editor: Node = app.screens.top()
	_check("Workshop opens from a helicopter selection on the default airplane", app.screens.is_top("workshop")
		and str(editor.get("initial_aircraft_id")) == Catalog.DEFAULT_ID)
	app.close_workshop()
	await ui.settle()

	# --- SP-1 / AS-2: beside the catalog, the selected aircraft's full name, capability, summary and limits.
	app.set_aircraft("stik-glow-61fx-2t")
	home._select_page(1)
	for frame in 4: await process_frame
	var details: Control = home.find_child("AircraftDetails", true, false)
	var entry: Dictionary = Catalog.entry("stik-glow-61fx-2t")
	var details_text := ""
	if details != null:
		for label: Label in details.find_children("*", "Label", true, false):
			details_text += label.text + "\n"
	_check("the selected aircraft's details are shown beside the catalog", details != null and details.visible
		and details_text.contains(entry.name) and details_text.contains(entry.summary) and details_text.contains(entry.status_note),
		"visible=%s text=%s" % [details.visible if details != null else "none", details_text.replace("\n", " | ")])
	_check("the details card sits right of the rail", details != null
		and details.get_global_rect().position.x >= home.get_node("HomeRail").get_global_rect().end.x)

	# --- AS-5: loading and failure states are visible on the Aircraft page too.
	home.set_preview_state("loading")
	var catalog_state: Label = home.find_child("CatalogPreviewState", true, false)
	_check("the Aircraft page shows a loading preview", catalog_state != null and catalog_state.is_visible_in_tree()
		and catalog_state.text == tr("Loading aircraft preview…"))
	home.set_preview_state("ready")
	_check("a ready preview hides the state", catalog_state != null and not catalog_state.visible)
	home._select_page(0)
	for frame in 2: await process_frame
	_check("the details card belongs to the Aircraft page only", details != null and not details.visible)

	# --- HN-7: exercise the interactive loading route even under headless Godot.
	app.flight_loading_enabled = true
	home.fly_button.pressed.emit()
	_check("Fly shows Preparing flight before building", app.flight == null and home.fly_button.disabled
		and home.fly_button.text == tr("Preparing flight…") and app.screens.is_top("loading"), home.fly_button.text)
	var flight_deadline := Time.get_ticks_msec() + 15000
	while app._loading_active and Time.get_ticks_msec() < flight_deadline:
		await process_frame
	_check("the flight starts after the loading checkpoints", app.flight != null and app.flight.startup_complete
		and app.last_flight_loading.get("status", "") == "ready" and app.screens.get_screen("loading") == null)
	app.queue_free()
	await ui.settle()

	# --- compact layouts keep the list in the rail and no details card.
	var compact_app: Node = load("res://app_root.tscn").instantiate()
	compact_app.user_args = PackedStringArray()
	compact_app.preferences_path = PREFS
	root.add_child(compact_app)
	await ui.settle()
	root.size = Vector2i(1280, 720)
	for frame in 4: await process_frame
	compact_app.home._select_page(1)
	for frame in 4: await process_frame
	var compact_details: Control = compact_app.home.find_child("AircraftDetails", true, false)
	_check("compact Home keeps the catalog in the rail without a details card", compact_details == null or not compact_details.visible)
	compact_app.queue_free()
	await ui.settle()
	for suffix in ["", ".display", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
