# UI-05 / EX-11 / AV-03: choosing the aircraft on Home with real key events (tests/ui_driver.gd). The card and the
# backdrop follow the choice, the choice is remembered, Fly starts exactly that airplane (model and physics), and a
# stale or broken preference falls back to the default. Since AV-07 the catalog has no preview entry: the Avanti flies
# (experimental), so the "a preview cannot be flown" path has no real entry to drive here.
# Run: godot --headless --path . --script res://tests/test_ui_aircraft.gd
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS := "user://test_ui_aircraft_settings.cfg"
const STIK := "jensen-das-ugly-stik-60"
const EXTRA := "gp-extra-300s-60"
const AVANTI := "sebart-avanti-s-a200-p100rx"
const P51 := "p51d-mustang-120"

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
	_run()


func _app() -> Node:
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS # never the player's own settings
	root.add_child(app)
	await ui.settle()
	return app


func _close(app: Node) -> void:
	root.remove_child(app)
	app.free()
	await ui.settle()


func _run() -> void:
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Node = await _app()
	var home: Control = app.home
	_check("default: the Ugly Stik on the card and in the backdrop", home.aircraft_id == STIK and home.aircraft_name_label.text == Catalog.entry(STIK).name
		and app.home_scene.airplane.aircraft_id == STIK)
	_check("default: Fly enabled and focused, counter 1 of 4", not home.fly_button.disabled and ui.focus_name() == "Fly" and home.aircraft_count_label.text == "Aircraft 1 of 4",
		home.aircraft_count_label.text)

	# Right from Fly reaches the next arrow; Enter there shows the Extra.
	await ui.tap(KEY_RIGHT)
	_check("Right from Fly -> next aircraft arrow", ui.focus_name() == "NextAircraft", ui.focus_name())
	await ui.tap(KEY_ENTER)
	_check("Enter on the arrow: the Extra on the card, in the backdrop and saved", home.aircraft_id == EXTRA and home.aircraft_name_label.text == Catalog.entry(EXTRA).name
		and app.home_scene.airplane.aircraft_id == EXTRA and Preferences.load_from(PREFS).aircraft == EXTRA)
	_check("Extra: Fly enabled, its status says experimental", not home.fly_button.disabled and home.aircraft_status_label.text.begins_with("Experimental"))
	_check("choosing never starts a flight", app.flight == null)

	# Next again: the P-51 (experimental, flyable); then the Avanti (experimental since AV-07, flyable).
	await ui.tap(KEY_ENTER)
	_check("P-51: shown, experimental, Fly enabled", home.aircraft_id == P51 and not home.fly_button.disabled
		and home.aircraft_status_label.text.begins_with("Experimental") and app.home_scene.airplane.aircraft_id == P51, home.aircraft_id)
	await ui.tap(KEY_ENTER)
	_check("Avanti: shown, experimental, Fly enabled", home.aircraft_id == AVANTI and not home.fly_button.disabled
		and home.aircraft_status_label.text.begins_with("Experimental"), home.aircraft_status_label.text)
	_check("Avanti: the backdrop shows it, focus stays on the arrow", app.home_scene.airplane.aircraft_id == AVANTI and ui.focus_name() == "NextAircraft", ui.focus_name())
	_check("choosing the Avanti never starts a flight", app.flight == null)

	# Wraps to the Stik; Left goes back to the Avanti. Spanish texts follow the language.
	await ui.tap(KEY_ENTER)
	_check("next wraps around to the Ugly Stik", home.aircraft_id == STIK)
	await ui.tap(KEY_LEFT)
	await ui.tap(KEY_ENTER)
	_check("previous arrow goes back to the Avanti", home.aircraft_id == AVANTI, home.aircraft_id)
	app.set_language("es")
	await ui.settle()
	# Labels keep the English source and translate when drawn (auto-translate), so read them the way they are drawn.
	var status: Label = home.aircraft_status_label
	_check("Spanish: counter and status translated", home.aircraft_count_label.text == "Avión 4 de 4" and status.can_auto_translate()
		and status.atr(status.text).begins_with("Experimental: primera estimación física (turbina") and home.aircraft_summary_label.atr(home.aircraft_summary_label.text).begins_with("Reactor deportivo"),
		"%s / %s" % [home.aircraft_count_label.text, status.atr(status.text)])
	app.set_language("en")
	await _close(app)

	# A new start remembers the Avanti (Fly enabled) ...
	app = await _app()
	home = app.home
	_check("restart: the saved Avanti comes back, Fly enabled", home.aircraft_id == AVANTI and not home.fly_button.disabled, ui.focus_name())
	# ... and Fly with the Extra starts the Extra: its model with its physics.
	app.set_aircraft(EXTRA)
	await ui.settle()
	home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Fly with the Extra: one flight, Extra model and Extra physics", app.flight != null and app.flight._airplane.aircraft_id == EXTRA
		and app.flight.session.aircraft.model.id == EXTRA and app.home == null)
	await _close(app)

	# A preference naming an aircraft that no longer exists (or the wrong type) falls back to the default.
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", 1)
	cfg.set_value("flight", "aircraft", "removed-aircraft")
	cfg.save(PREFS)
	_check("unknown saved aircraft -> default", Preferences.load_from(PREFS).aircraft == Catalog.DEFAULT_ID)
	cfg.set_value("flight", "aircraft", 3)
	cfg.save(PREFS)
	_check("saved aircraft of the wrong type -> default", Preferences.load_from(PREFS).aircraft == Catalog.DEFAULT_ID)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))

	print("all UI aircraft checks passed" if _failures == 0 else "%d UI aircraft checks failed" % _failures)
	quit(1 if _failures > 0 else 0)
