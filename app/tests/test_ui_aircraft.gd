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
const CORSAIR := "f4u-corsair-250"
const GLOW_61FX := "stik-glow-61fx-2t"
const GLOW_55AX := "stik-glow-55ax-2t"
const GLOW_FS64V := "stik-glow-fs64v-4t"
const HELI := "xcell-60-research"
const X8 := "skywalker-x8"

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
	# The headless SceneTree starts at 64×64; use the Home layout that keyboard focus was designed for.
	root.size = Vector2i(1280, 720)
	await ui.settle()
	return app


func _close(app: Node) -> void:
	await ui.close_app(app)


## UI-05-R3: input settles separately from asynchronous preview preparation.
func _preview(app: Node) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while app.home_scene != null and app.home_scene.preview_pending and Time.get_ticks_msec() < deadline:
		await process_frame
	_check("preview preparation completes", app.home_scene == null or not app.home_scene.preview_pending)


func _tab_until(target: String, max_presses := 32) -> bool:
	for _step in max_presses:
		if ui.focus_name() == target:
			return true
		await ui.tap(KEY_TAB)
	return ui.focus_name() == target


func _aircraft_counter(id: String) -> String:
	var ids: PackedStringArray = Catalog.ids()
	return "%d / %d" % [ids.find(id) + 1, ids.size()]


func _aircraft_counter_tooltip(id: String) -> String:
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
		and home.aircraft_count_label.text == _aircraft_counter(STIK)
		and home.aircraft_count_label.tooltip_text == _aircraft_counter_tooltip(STIK),
		home.aircraft_count_label.text)

	# Keep aircraft selection on the real keyboard route even when headless focus order differs by viewport.
	var next_reachable := await _tab_until("NextAircraft")
	_check("Next aircraft arrow is keyboard reachable", next_reachable, ui.focus_name())
	if not next_reachable:
		await _close(app)
		quit(1)
		return
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("MAX-61FX Stik: experimental 2-stroke on card and backdrop", home.aircraft_id == GLOW_61FX
		and home.aircraft_count_label.text == _aircraft_counter(GLOW_61FX)
		and home.aircraft_name_label.text.contains("61FX")
		and home.aircraft_name_label.tooltip_text == tr(Catalog.entry(GLOW_61FX).name)
		and app.home_scene.airplane.aircraft_id == GLOW_61FX and not home.fly_button.disabled
		and home.aircraft_status_label.text.contains("MAX-61FX") and home.aircraft_status_label.text.contains("not flight-validated"),
		"%s / %s / %s / %s" % [home.aircraft_id, home.aircraft_name_label.text,
			home.aircraft_name_label.tooltip_text, home.aircraft_status_label.text])
	_check("MAX-61FX selection does not start a flight", app.flight == null)
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("55AX glow Stik: experimental 2-stroke on card and backdrop", home.aircraft_id == GLOW_55AX
		and home.aircraft_name_label.text.contains("55AX")
		and home.aircraft_name_label.tooltip_text == tr(Catalog.entry(GLOW_55AX).name)
		and app.home_scene.airplane.aircraft_id == GLOW_55AX and not home.fly_button.disabled
		and home.aircraft_status_label.text.contains("inferred") and home.aircraft_status_label.text.contains("2-stroke"),
		"%s / %s / %s / %s" % [home.aircraft_id, home.aircraft_name_label.text,
			home.aircraft_name_label.tooltip_text, home.aircraft_status_label.text])
	_check("55AX selection does not start a flight", app.flight == null)
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("FS-64V glow Stik: experimental true 4-stroke on card and backdrop", home.aircraft_id == GLOW_FS64V
		and home.aircraft_name_label.text.contains("FS-64V")
		and home.aircraft_name_label.tooltip_text == tr(Catalog.entry(GLOW_FS64V).name)
		and app.home_scene.airplane.aircraft_id == GLOW_FS64V and not home.fly_button.disabled
		and home.aircraft_status_label.text.contains("inferred") and home.aircraft_status_label.text.contains("4-stroke"),
		"%s / %s / %s / %s" % [home.aircraft_id, home.aircraft_name_label.text,
			home.aircraft_name_label.tooltip_text, home.aircraft_status_label.text])
	_check("FS-64V selection does not start a flight", app.flight == null)
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("Enter on the arrow: the Extra on the card, in the backdrop and saved", home.aircraft_id == EXTRA and home.aircraft_name_label.text == Catalog.short_name(EXTRA)
		and home.aircraft_name_label.tooltip_text == tr(Catalog.entry(EXTRA).name) # UI-34b: short card name, full tooltip
		and app.home_scene.airplane.aircraft_id == EXTRA and Preferences.load_from(PREFS).aircraft == EXTRA)
	_check("Extra: Fly enabled, its status says experimental", not home.fly_button.disabled and home.aircraft_status_label.text.begins_with("Experimental"))
	_check("choosing never starts a flight", app.flight == null)

	# Next again: the P-51 (experimental, flyable); then the Vantage Jet (experimental since AV-07, flyable).
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("P-51: shown, experimental, Fly enabled", home.aircraft_id == P51 and not home.fly_button.disabled
		and home.aircraft_status_label.text.begins_with("Experimental") and app.home_scene.airplane.aircraft_id == P51, home.aircraft_id)
	# F4U-09: the F4U Corsair follows the P-51 (experimental, flyable).
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("F4U Corsair: shown, experimental, Fly enabled", home.aircraft_id == CORSAIR and not home.fly_button.disabled
		and home.aircraft_status_label.text.begins_with("Experimental") and app.home_scene.airplane.aircraft_id == CORSAIR, home.aircraft_id)
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("Vantage Jet: shown, experimental, Fly enabled", home.aircraft_id == AVANTI and not home.fly_button.disabled
		and home.aircraft_status_label.text.begins_with("Experimental"), home.aircraft_status_label.text)
	_check("Vantage Jet: the backdrop shows it, focus stays on the arrow", app.home_scene.airplane.aircraft_id == AVANTI and ui.focus_name() == "NextAircraft", ui.focus_name())
	_check("choosing the Vantage Jet never starts a flight", app.flight == null)

	# The Lumber is now the experimental, data-backed electric aircraft (TT-08/10).
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("Lumber: shown, experimental, Fly enabled", home.aircraft_id == TIMBER and not home.fly_button.disabled
		and home.aircraft_status_label.text.begins_with("Experimental") and home.limits_label.visible, home.aircraft_status_label.text)
	var timber_note: String = home.aircraft_status_label.text.to_lower()
	_check("Lumber status states the estimated electric, flaps-up configuration",
		timber_note.contains("electric") and timber_note.contains("estimated") and timber_note.contains("flaps up")
		and timber_note.contains("fixed wheels") and timber_note.contains("assists off"), timber_note)
	_check("Lumber: the backdrop shows it, focus stays on the arrow", app.home_scene.airplane.aircraft_id == TIMBER and ui.focus_name() == "NextAircraft", ui.focus_name())
	_check("Lumber: catalog counter", home.aircraft_count_label.text == _aircraft_counter(TIMBER), home.aircraft_count_label.text)
	_check("Lumber selection is saved without starting a session", Preferences.load_from(PREFS).aircraft == TIMBER and app.flight == null)
	# X8-09: the X8 flying wing follows the Lumber; without landing gear it starts by hand (X8-07).
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("X8: shown, experimental, Fly enabled, starts by hand", home.aircraft_id == X8 and not home.fly_button.disabled
		and home.aircraft_status_label.text.begins_with("Experimental") and home.start_choice == "hand_launch"
		and app.home_scene.airplane.aircraft_id == X8, "%s / %s / %s" % [home.aircraft_id, home.start_choice, home.aircraft_status_label.text])
	_check("X8: catalog counter", home.aircraft_count_label.text == _aircraft_counter(X8), home.aircraft_count_label.text)
	# The experimental helicopter is last; next wraps to the Stik. Previous crosses the helicopter before the X8.
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("helicopter is last in the catalog with the HX-700 preview and pad start",
		home.aircraft_id == HELI and home.aircraft_count_label.text == _aircraft_counter(HELI)
		and app.home_scene.airplane.visual_family == "hx-700" and home.start_choice == "runway"
		and home.start_button.text == "Start: helicopter pad" and not home.workshop_button.disabled
		and not home.natural_random_button.disabled, "%s / %s" % [home.aircraft_id, home.aircraft_count_label.text])
	_check("helicopter selection is saved without starting a session",
		Preferences.load_from(PREFS).aircraft == HELI and app.flight == null)
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("next wraps around to the Ugly Stik", home.aircraft_id == STIK)
	await ui.tap(KEY_LEFT)
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("previous arrow from the Stik reaches the last helicopter", home.aircraft_id == HELI, home.aircraft_id)
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("previous from the helicopter returns to the X8", home.aircraft_id == X8, home.aircraft_id)
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("previous again: the Lumber", home.aircraft_id == TIMBER, home.aircraft_id)
	await ui.tap(KEY_ENTER)
	await _preview(app)
	_check("previous again: the Vantage Jet", home.aircraft_id == AVANTI, home.aircraft_id)
	app.set_language("es")
	await ui.settle()
	# Labels keep the English source and translate when drawn (auto-translate), so read them the way they are drawn.
	var status: Label = home.aircraft_status_label
	_check("Spanish: catalog counter and status translated", home.aircraft_count_label.text == _aircraft_counter(AVANTI)
		and home.aircraft_count_label.tooltip_text == _aircraft_counter_tooltip(AVANTI)
		and status.atr(status.text).begins_with("Experimental: primera estimación física (turbina") and home.aircraft_summary_label.atr(home.aircraft_summary_label.text).begins_with("Reactor deportivo"),
		"count=%s tooltip=%s expected=%s status=%s summary=%s" % [home.aircraft_count_label.text,
			home.aircraft_count_label.tooltip_text, _aircraft_counter_tooltip(AVANTI), status.atr(status.text),
			home.aircraft_summary_label.atr(home.aircraft_summary_label.text)])
	# Proper aircraft names stay unchanged through tr(); summaries and status text still translate.
	app.set_aircraft(TIMBER)
	await ui.settle()
	_check("Spanish: the Lumber card keeps its name", home.aircraft_name_label.text == "Turbo Lumber"
		and home.aircraft_name_label.tooltip_text == "Turbo Lumber Evolution", home.aircraft_name_label.text)
	app.set_aircraft(AVANTI)
	await ui.settle()
	_check("Spanish: Vantage Jet keeps its name", home.aircraft_name_label.text == "Vantage Jet"
		and Catalog.entry(AVANTI).name == "Vantage Jet" and Catalog.entry(AVANTI).short_name == "Vantage Jet",
		home.aircraft_name_label.text)
	app.set_language("en")
	await ui.settle()
	_check("English: the Lumber card shows its full name", Catalog.entry(TIMBER).name == "Turbo Lumber Evolution" and tr(Catalog.entry(TIMBER).name) == "Turbo Lumber Evolution")
	await _close(app)

	# A new start remembers the Vantage Jet; then fly the Lumber through Home's real Fly action.
	app = await _app()
	home = app.home
	_check("restart: the saved Vantage Jet comes back, Fly enabled", home.aircraft_id == AVANTI and not home.fly_button.disabled, ui.focus_name())
	app.set_aircraft(TIMBER)
	await ui.settle()
	_check("reselected Lumber: Fly enabled and choice saved", home.aircraft_id == TIMBER and not home.fly_button.disabled
		and Preferences.load_from(PREFS).aircraft == TIMBER)
	home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await _preview(app)
	await ui.settle()
	var timber_flight: Node = app.flight
	var timber_session: Node = timber_flight.session if timber_flight != null else null
	var timber_started: bool = (timber_flight != null and timber_session != null
		and timber_flight._airplane.aircraft_id == TIMBER and timber_session.aircraft.ok
		and timber_session.aircraft.model.id == TIMBER and timber_session.start.ok and app.home == null)
	_check("Fly starts Lumber with its own model and physics", timber_started)
	if not timber_started:
		await _close(app)
		print("all UI aircraft checks failed to start Lumber")
		quit(1)
		return

	# Pause and restart from the visible menu; the same loaded Lumber returns at its trimmed start.
	await ui.tap(KEY_ESCAPE)
	_check("Lumber flight pauses from the keyboard", app.pause_menu != null and timber_session.sim.paused)
	await ui.tap(KEY_DOWN)
	_check("Restart is keyboard reachable", ui.focus_name() == "Restart", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await _preview(app)
	await ui.settle()
	_check("Restart restores a fresh trimmed Lumber flight", app.flight == timber_flight and app.pause_menu == null
		and not timber_session.sim.paused and timber_session.aircraft.model.id == TIMBER and timber_session.sim.time() < 0.25,
		"t=%.3f s" % timber_session.sim.time())

	# End returns Home with the aircraft selected and persisted; Exit options now discloses End flight.
	await ui.tap(KEY_ESCAPE)
	await ui.tap(KEY_DOWN) # Restart
	await ui.tap(KEY_DOWN) # Session options
	await ui.tap(KEY_DOWN) # Settings
	await ui.tap(KEY_DOWN) # Help
	await ui.tap(KEY_DOWN) # Change aircraft (UI-34a)
	await ui.tap(KEY_DOWN) # Exit options
	_check("Exit options is keyboard reachable", ui.focus_name() == "ExitOptions", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.tap(KEY_DOWN)
	var end_reachable: bool = ui.focus_name() == "End"
	_check("End flight is keyboard reachable inside Exit options", end_reachable, ui.focus_name())
	if not end_reachable:
		await _close(app)
		print("all UI aircraft checks failed to reach End flight")
		quit(1)
		return
	await ui.tap(KEY_ENTER)
	await _preview(app)
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
	await _preview(app)
	await ui.settle()
	_check("reselect after End starts Lumber again", app.flight != null and app.flight._airplane.aircraft_id == TIMBER
		and app.flight.session.aircraft.model.id == TIMBER)
	await _close(app)

	# A fresh app reads the persisted Lumber choice and can fly it again.
	app = await _app()
	home = app.home
	_check("new app remembers Lumber and keeps Fly enabled", home.aircraft_id == TIMBER and not home.fly_button.disabled
		and Preferences.load_from(PREFS).aircraft == TIMBER, home.aircraft_status_label.text)
	home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await _preview(app)
	await ui.settle()
	_check("persisted Lumber choice flies its matching physics", app.flight != null and app.flight._airplane.aircraft_id == TIMBER
		and app.flight.session.aircraft.model.id == TIMBER)
	await _close(app)

	# Keep the existing Extra adapter roundtrip alongside the new Lumber session checks.
	app = await _app()
	app.set_aircraft(EXTRA)
	await ui.settle()
	app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await _preview(app)
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
