# UI-05 / EX-11 / AV-03 / TT-10: choosing the aircraft on Home with real key events (tests/ui_driver.gd). The card and
# backdrop follow the choice, the choice is remembered, Fly starts exactly that airplane (model and physics), and a
# stale or broken preference falls back to the default. Includes the three inferred glow Stik installations.
# Run: godot --headless --path . --script res://tests/test_ui_aircraft.gd
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS := "user://test_ui_aircraft_settings.cfg"
const STIK := "jensen-das-ugly-stik-60"
const EXTRA := "gp-extra-300s-60"
const AVANTI := "sebart-avanti-s-a200-p100rx"
const TIMBER := "turbo-lumber-evolution"
const P51 := "p51d-mustang-120"
const GLOW_61FX := "stik-glow-61fx-2t"
const GLOW_55AX := "stik-glow-55ax-2t"
const GLOW_FS64V := "stik-glow-fs64v-4t"
const HELI := "xcell-60-research"

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


func _aircraft_counter(id: String) -> String:
	var ids: PackedStringArray = Catalog.ids()
	return tr("Aircraft %d of %d") % [ids.find(id) + 1, ids.size()]


func _run() -> void:
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Node = await _app()
	var home: Control = app.home
	_check("catalog order keeps the Stik glow variants before the Extra",
		Catalog.step(STIK, 1) == GLOW_61FX and Catalog.step(GLOW_61FX, 1) == GLOW_55AX
		and Catalog.step(GLOW_55AX, 1) == GLOW_FS64V and Catalog.step(GLOW_FS64V, 1) == EXTRA)
	_check("default: the Ugly Stik on the card and in the backdrop", home.aircraft_id == STIK and home.aircraft_name_label.text == Catalog.entry(STIK).name
		and app.home_scene.airplane.aircraft_id == STIK)
	_check("default: Fly enabled and focused, catalog counter", not home.fly_button.disabled and ui.focus_name() == "Fly"
		and home.aircraft_count_label.text == _aircraft_counter(STIK),
		home.aircraft_count_label.text)

	# Right from Fly reaches the next arrow; Enter visits each inferred glow variant before the Extra.
	await ui.tap(KEY_RIGHT)
	_check("Right from Fly -> next aircraft arrow", ui.focus_name() == "NextAircraft", ui.focus_name())
	await ui.tap(KEY_ENTER)
	_check("MAX-61FX Stik: experimental 2-stroke on card and backdrop", home.aircraft_id == GLOW_61FX
		and home.aircraft_count_label.text == _aircraft_counter(GLOW_61FX)
		and home.aircraft_name_label.text == Catalog.entry(GLOW_61FX).name
		and app.home_scene.airplane.aircraft_id == GLOW_61FX and not home.fly_button.disabled
		and home.aircraft_status_label.text.contains("MAX-61FX") and home.aircraft_status_label.text.contains("not flight-validated"),
		home.aircraft_status_label.text)
	_check("MAX-61FX selection does not start a flight", app.flight == null)
	await ui.tap(KEY_ENTER)
	_check("55AX glow Stik: experimental 2-stroke on card and backdrop", home.aircraft_id == GLOW_55AX
		and home.aircraft_name_label.text == Catalog.entry(GLOW_55AX).name
		and app.home_scene.airplane.aircraft_id == GLOW_55AX and not home.fly_button.disabled
		and home.aircraft_status_label.text.contains("inferred") and home.aircraft_status_label.text.contains("2-stroke"),
		home.aircraft_status_label.text)
	_check("55AX selection does not start a flight", app.flight == null)
	await ui.tap(KEY_ENTER)
	_check("FS-64V glow Stik: experimental true 4-stroke on card and backdrop", home.aircraft_id == GLOW_FS64V
		and home.aircraft_name_label.text == Catalog.entry(GLOW_FS64V).name
		and app.home_scene.airplane.aircraft_id == GLOW_FS64V and not home.fly_button.disabled
		and home.aircraft_status_label.text.contains("inferred") and home.aircraft_status_label.text.contains("4-stroke"),
		home.aircraft_status_label.text)
	_check("FS-64V selection does not start a flight", app.flight == null)
	await ui.tap(KEY_ENTER)
	_check("Enter on the arrow: the Extra on the card, in the backdrop and saved", home.aircraft_id == EXTRA and home.aircraft_name_label.text == Catalog.entry(EXTRA).name
		and app.home_scene.airplane.aircraft_id == EXTRA and Preferences.load_from(PREFS).aircraft == EXTRA)
	_check("Extra: Fly enabled, its status says experimental", not home.fly_button.disabled and home.aircraft_status_label.text.begins_with("Experimental"))
	_check("choosing never starts a flight", app.flight == null)

	# Next again: the P-51 (experimental, flyable); then the Ventage Jet (experimental since AV-07, flyable).
	await ui.tap(KEY_ENTER)
	_check("P-51: shown, experimental, Fly enabled", home.aircraft_id == P51 and not home.fly_button.disabled
		and home.aircraft_status_label.text.begins_with("Experimental") and app.home_scene.airplane.aircraft_id == P51, home.aircraft_id)
	await ui.tap(KEY_ENTER)
	_check("Ventage Jet: shown, experimental, Fly enabled", home.aircraft_id == AVANTI and not home.fly_button.disabled
		and home.aircraft_status_label.text.begins_with("Experimental"), home.aircraft_status_label.text)
	_check("Ventage Jet: the backdrop shows it, focus stays on the arrow", app.home_scene.airplane.aircraft_id == AVANTI and ui.focus_name() == "NextAircraft", ui.focus_name())
	_check("choosing the Ventage Jet never starts a flight", app.flight == null)

	# The Timber is now the experimental, data-backed electric aircraft (TT-08/10).
	await ui.tap(KEY_ENTER)
	_check("Timber: shown, experimental, Fly enabled", home.aircraft_id == TIMBER and not home.fly_button.disabled
		and home.aircraft_status_label.text.begins_with("Experimental") and home.limits_label.visible, home.aircraft_status_label.text)
	var timber_note: String = home.aircraft_status_label.text.to_lower()
	_check("Timber status states the estimated electric, flaps-up configuration",
		timber_note.contains("electric") and timber_note.contains("estimated") and timber_note.contains("flaps up")
		and timber_note.contains("fixed wheels") and timber_note.contains("assists off"), timber_note)
	_check("Timber: the backdrop shows it, focus stays on the arrow", app.home_scene.airplane.aircraft_id == TIMBER and ui.focus_name() == "NextAircraft", ui.focus_name())
	_check("Timber: catalog counter", home.aircraft_count_label.text == _aircraft_counter(TIMBER), home.aircraft_count_label.text)
	_check("Timber selection is saved without starting a session", Preferences.load_from(PREFS).aircraft == TIMBER and app.flight == null)
	# The experimental helicopter is last; next wraps to the Stik. Previous crosses the helicopter before Timber.
	await ui.tap(KEY_ENTER)
	_check("helicopter is last in the catalog with the HX-700 preview and hover-only start",
		home.aircraft_id == HELI and home.aircraft_count_label.text == _aircraft_counter(HELI)
		and app.home_scene.airplane.visual_family == "hx-700" and home.start_choice == "airborne"
		and home.start_button.text == "Start: hover" and home.workshop_button.disabled
		and home.natural_random_button.disabled, "%s / %s" % [home.aircraft_id, home.aircraft_count_label.text])
	_check("helicopter selection is saved without starting a session",
		Preferences.load_from(PREFS).aircraft == HELI and app.flight == null)
	await ui.tap(KEY_ENTER)
	_check("next wraps around to the Ugly Stik", home.aircraft_id == STIK)
	await ui.tap(KEY_LEFT)
	await ui.tap(KEY_ENTER)
	_check("previous arrow from the Stik reaches the last helicopter", home.aircraft_id == HELI, home.aircraft_id)
	await ui.tap(KEY_ENTER)
	_check("previous from the helicopter returns to the Timber", home.aircraft_id == TIMBER, home.aircraft_id)
	await ui.tap(KEY_ENTER)
	_check("previous again: the Ventage Jet", home.aircraft_id == AVANTI, home.aircraft_id)
	app.set_language("es")
	await ui.settle()
	# Labels keep the English source and translate when drawn (auto-translate), so read them the way they are drawn.
	var status: Label = home.aircraft_status_label
	_check("Spanish: catalog counter and status translated", home.aircraft_count_label.text == _aircraft_counter(AVANTI) and status.can_auto_translate()
		and status.atr(status.text).begins_with("Experimental: primera estimación física (turbina") and home.aircraft_summary_label.atr(home.aircraft_summary_label.text).begins_with("Reactor deportivo"),
		"%s / %s" % [home.aircraft_count_label.text, status.atr(status.text)])
	# The Timber's fictional name is the one translated aircraft name (TT-06); the other names pass through tr() unchanged.
	app.set_aircraft(TIMBER)
	await ui.settle()
	_check("Spanish: the Timber card shows its Spanish name", home.aircraft_name_label.text == "Turbo Tronco Evolución", home.aircraft_name_label.text)
	app.set_aircraft(AVANTI)
	await ui.settle()
	_check("Spanish: Ventage Jet keeps its name", home.aircraft_name_label.text == Catalog.entry(AVANTI).name, home.aircraft_name_label.text)
	app.set_language("en")
	await ui.settle()
	_check("English: the Timber card shows its English name", Catalog.entry(TIMBER).name == "Turbo Lumber Evolution" and tr(Catalog.entry(TIMBER).name) == "Turbo Lumber Evolution")
	await _close(app)

	# A new start remembers the Ventage Jet; then fly the Timber through Home's real Fly action.
	app = await _app()
	home = app.home
	_check("restart: the saved Ventage Jet comes back, Fly enabled", home.aircraft_id == AVANTI and not home.fly_button.disabled, ui.focus_name())
	app.set_aircraft(TIMBER)
	await ui.settle()
	_check("reselected Timber: Fly enabled and choice saved", home.aircraft_id == TIMBER and not home.fly_button.disabled
		and Preferences.load_from(PREFS).aircraft == TIMBER)
	home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var timber_flight: Node = app.flight
	var timber_session: Node = timber_flight.session if timber_flight != null else null
	var timber_started: bool = (timber_flight != null and timber_session != null
		and timber_flight._airplane.aircraft_id == TIMBER and timber_session.aircraft.ok
		and timber_session.aircraft.model.id == TIMBER and timber_session.start.ok and app.home == null)
	_check("Fly starts Timber with its own model and physics", timber_started)
	if not timber_started:
		await _close(app)
		print("all UI aircraft checks failed to start Timber")
		quit(1)
		return

	# Pause and restart from the visible menu; the same loaded Timber returns at its trimmed start.
	await ui.tap(KEY_ESCAPE)
	_check("Timber flight pauses from the keyboard", app.pause_menu != null and timber_session.sim.paused)
	await ui.tap(KEY_DOWN)
	_check("Restart is keyboard reachable", ui.focus_name() == "Restart", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Restart restores a fresh trimmed Timber flight", app.flight == timber_flight and app.pause_menu == null
		and not timber_session.sim.paused and timber_session.aircraft.model.id == TIMBER and timber_session.sim.time() < 0.25,
		"t=%.3f s" % timber_session.sim.time())

	# End returns Home with the aircraft selected and persisted; choosing Fly again makes a clean session.
	await ui.tap(KEY_ESCAPE)
	var end_reachable: bool = ui.focus_name() == "End"
	for _step in 12: # Walk the actual menu order so optional entries do not make the test's count stale.
		if end_reachable:
			break
		await ui.tap(KEY_DOWN)
		end_reachable = ui.focus_name() == "End"
	_check("End flight is keyboard reachable", end_reachable, ui.focus_name())
	if not end_reachable:
		await _close(app)
		print("all UI aircraft checks failed to reach End flight")
		quit(1)
		return
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("End returns to Home and releases the old session", app.flight == null and app.home != null
		and root.find_children("FlightSession", "", true, false).is_empty()
		and Preferences.load_from(PREFS).aircraft == TIMBER)
	home = app.home
	if home == null:
		await _close(app)
		print("all UI aircraft checks failed to return Home")
		quit(1)
		return
	home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("reselect after End starts Timber again", app.flight != null and app.flight._airplane.aircraft_id == TIMBER
		and app.flight.session.aircraft.model.id == TIMBER)
	await _close(app)

	# A fresh app reads the persisted Timber choice and can fly it again.
	app = await _app()
	home = app.home
	_check("new app remembers Timber and keeps Fly enabled", home.aircraft_id == TIMBER and not home.fly_button.disabled
		and Preferences.load_from(PREFS).aircraft == TIMBER, home.aircraft_status_label.text)
	home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("persisted Timber choice flies its matching physics", app.flight != null and app.flight._airplane.aircraft_id == TIMBER
		and app.flight.session.aircraft.model.id == TIMBER)
	await _close(app)

	# Keep the existing Extra adapter roundtrip alongside the new Timber session checks.
	app = await _app()
	app.set_aircraft(EXTRA)
	await ui.settle()
	app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Fly with the Extra still starts the matching model and physics", app.flight != null and app.flight._airplane.aircraft_id == EXTRA
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
