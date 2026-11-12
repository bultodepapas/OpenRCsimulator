## A18: loading describes the same effective start that the selected flight will receive.
extends SceneTree

const App := preload("res://app_root.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Landscapes := preload("res://landscapes/catalog.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const PREFS := "user://test_loading_start_label.cfg"


class Candidate extends Node:
	signal startup_finished
	var startup_error := ""
	var startup_complete := false
	var startup_cancel_requested: Callable
	var recorder: Node
	var session: Node
	var aircraft_id := ""
	var landscape_id := ""
	var start_choice := ""

	func _set(_property: StringName, _value: Variant) -> bool:
		return true

	func _ready() -> void:
		while not startup_cancel_requested.call():
			await get_tree().process_frame
		startup_error = "Flight preparation cancelled."
		startup_complete = true
		startup_finished.emit()


class TestApp extends App:
	func _create_flight(_aircraft_id: String = "") -> Node:
		return Candidate.new()


var checks := 0
var failures := 0
var ui: RefCounted


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run.call_deferred()


func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if condition:
		print("ok ", label)
	else:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func settle() -> void:
	for _i in 8:
		await process_frame


## UI-28-R5b: a rendered landscape change builds Home in stages under its loading surface.
func settle_home(app: Node) -> void:
	for _i in 3000:
		if not app.home_build_pending:
			break
		await process_frame
	await settle()


func wait_loading_idle(app: Node) -> bool:
	for _i in 1500:
		if not app._loading_active:
			return true
		await process_frame
	return false


func wait_candidate(app: Node) -> bool:
	for _i in 1500:
		if app.flight != null or not app._loading_active:
			break
		await process_frame
	return app.flight != null and app._loading_active


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	prefs.check_updates = false
	check("isolated preferences saved", Preferences.save_to(PREFS, prefs) == OK)
	var app := TestApp.new()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	app.home_flight_prefetch_mode = "off"
	app.flight_loading_enabled = true
	app.window_focus_probe = func() -> bool: return true
	root.add_child(app)
	await settle()
	# The last field is the Home label source, independent of the loading code.
	var cases := [
		["jensen-das-ugly-stik-60", "club_field", "runway", "runway", "Start: runway"],
		["jensen-das-ugly-stik-60", "green_paradise", "runway", "airborne", "Start: in the air"],
		["moonrunner-x99", "club_field", "runway", "hand_launch", "Start: hand launch"],
		["xcell-60-research", "club_field", "runway", "runway", "Start: helicopter pad"],
		["xcell-60-research", "club_field", "airborne", "airborne", "Start: hover"],
		["xcell-60-research", "green_paradise", "runway", "airborne", "Start: hover"],
	]
	for locale: String in ["en", "es"]:
		TranslationServer.set_locale(locale)
		await settle()
		for row: Array in cases:
			app.set_aircraft(row[0])
			app.set_landscape(row[1])
			await settle_home(app)
			app.home.set_start_choice(row[2])
			await settle()
			var name := "%s %s %s %s" % [locale, row[0], row[1], row[2]]
			var expected_start: String = TranslationServer.translate(row[4])
			var expected_summary: String = "%s · %s · %s" % [app.tr(Catalog.short_name(row[0])),
				app.tr(Landscapes.entry(row[1]).name), expected_start]
			check("Home resolves " + name, app.home.start_choice == row[3]
				and app.home.start_button.text == expected_start)
			app.start_flight()
			check("loading uses resolved label " + name, app._loading_screen != null
				and app._loading_screen.summary_label.text == expected_summary,
				app._loading_screen.summary_label.text if app._loading_screen != null else "no loading screen")
			# Exercise the actual candidate handoff for both helicopter starts in English.
			if locale == "en" and row[0] == "xcell-60-research" and row[1] == "club_field":
				var candidate_ready := await wait_candidate(app)
				check("candidate receives displayed " + row[4], candidate_ready
					and app.flight.aircraft_id == row[0] and app.flight.start_choice == row[3])
			app.cancel_flight_loading()
			var idle := await wait_loading_idle(app)
			await settle()
			check("cancellation returns to same resolved setup " + name, idle and app.flight == null
				and app.screens.is_top("home") and app.home.start_choice == row[3]
				and app.home.start_button.text == expected_start and app.home.fly_button.has_focus())
	TranslationServer.set_locale("en")
	app.set_aircraft("xcell-60-research")
	app.set_landscape("club_field")
	await settle_home(app)
	app.home.set_start_choice("runway")
	await settle()
	app.random_seed_source = func() -> int: return 12345
	app.open_natural_random()
	await settle()
	check("Natural Random briefing opens from pad-selected Home", app.screens.is_top("natural_random")
		and app.home.start_button.text == TranslationServer.translate("Start: helicopter pad"))
	var briefing: CanvasLayer = app.natural_random_screen
	var scenario: Dictionary = briefing.get("_scenario").duplicate(true)
	check("briefing has an airplane airborne start", not scenario.is_empty()
		and scenario.start_choice == "airborne" and not Catalog.is_rotorcraft(scenario.aircraft_id))
	app.start_flight(scenario)
	var random_expected: String = "%s · %s · %s" % [app.tr(Catalog.short_name(scenario.aircraft_id)),
		app.tr(Landscapes.entry(app.landscape_id).name), TranslationServer.translate("Airborne")]
	check("random loading describes the briefing, not Home's pad", app._loading_screen != null
		and app._loading_screen.summary_label.text == random_expected)
	app.cancel_flight_loading()
	var random_idle := await wait_loading_idle(app)
	await settle()
	check("random cancellation restores the same briefing", random_idle and app.flight == null
		and app.screens.is_top("natural_random") and app.natural_random_screen == briefing
		and briefing.get("_scenario") == scenario and briefing.fly_button.has_focus())
	app.start_flight(scenario)
	var random_candidate_ready := await wait_candidate(app)
	check("random candidate receives briefing start", random_candidate_ready
		and app.flight.aircraft_id == scenario.aircraft_id and app.flight.start_choice == scenario.start_choice)
	app.cancel_flight_loading()
	var candidate_idle := await wait_loading_idle(app)
	await settle()
	check("random candidate cancellation returns focus and draft to briefing", candidate_idle and app.flight == null
		and app.screens.is_top("natural_random") and app.natural_random_screen == briefing
		and briefing.get("_scenario") == scenario and briefing.fly_button.has_focus())
	await ui.close_app(app)
	for suffix: String in ["", ".display", ".controllers", ".legacy_rc"]:
		var path := ProjectSettings.globalize_path(PREFS + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	TranslationServer.set_locale("en")
	print("Loading start label: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
