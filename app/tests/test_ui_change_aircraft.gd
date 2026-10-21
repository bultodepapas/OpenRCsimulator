# UI-34a (UI-30 audit AS-1): Pause names the flight and switches aircraft without the collapsed exit group.
# Real key events on the production shell with isolated preferences.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_change_aircraft.gd
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const PREFS := "user://test_ui_change_aircraft.cfg"

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
	print("UI change aircraft: %d failed" % _failures)
	quit(1 if _failures else 0)


func _run() -> void:
	TranslationServer.set_locale("en")
	for suffix in ["", ".display", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	await ui.tap(KEY_ENTER) # Fly the default aircraft
	await create_timer(0.3).timeout
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	var pause: Node = app.pause_menu
	_check("Pause names the aircraft and the field", pause != null and pause.identity_label.visible
		and pause.identity_label.text.contains(tr(Catalog.entry(Catalog.DEFAULT_ID).name))
		and pause.identity_label.text.contains("Club field"), pause.identity_label.text if pause != null else "no Pause")
	_check("Change aircraft is a top-level action directly above Exit options", pause != null and pause.change_aircraft_button.visible
		and pause.change_aircraft_button.get_parent() == pause.exit_options_button.get_parent()
		and pause.change_aircraft_button.get_index() == pause.exit_options_button.get_index() - 1)

	# Three activations from Pause: Change aircraft, the next catalog entry, Fly.
	for i in 8: # Restart, Session options, Settings, Help, Change aircraft
		if ui.focus_name() == "ChangeAircraft":
			break
		await ui.tap(KEY_DOWN)
	_check("keyboard reaches Change aircraft", ui.focus_name() == "ChangeAircraft", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Change aircraft ends the flight and opens the catalog", app.flight == null and app.screens.is_top("home")
		and app.home._pages[1].visible)
	var current: int = app.home._catalog_ids.find(Catalog.DEFAULT_ID)
	_check("the flown aircraft has the focus", ui.focus_name() == app.home._catalog_buttons[current].name, ui.focus_name())
	await ui.tap(KEY_DOWN)
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var next_id: String = app.home._catalog_ids[current + 1]
	_check("Enter selects the next aircraft without launching", app.home.aircraft_id == next_id and app.flight == null)
	app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await create_timer(0.3).timeout
	_check("Fly starts the newly selected aircraft", app.flight != null and str(app.flight.get("aircraft_id")) == next_id)

	# A Workshop trial keeps its own return route; the direct route has no Home to return to.
	app.end_flight()
	await ui.settle()
	app.open_workshop()
	await ui.settle()
	var source: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	app._start_workshop_trial({base_id = Catalog.DEFAULT_ID, base_bytes = source, recipe = {scale = 1.0}})
	await ui.settle()
	app.open_pause()
	await ui.settle()
	_check("trial Pause offers Return to Workshop, not Change aircraft", app.pause_menu != null
		and not app.pause_menu.change_aircraft_button.visible
		and app.pause_menu.identity_label.text.begins_with(tr("Workshop trial")), app.pause_menu.identity_label.text if app.pause_menu != null else "")
	await ui.close_app(app)
