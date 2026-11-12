## UI-32-R8 / A18 section 5: the ordinary Fly caption previews resolved Home values.
extends SceneTree

const Home := preload("res://ui/home.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Landscapes := preload("res://landscapes/catalog.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Failures := preload("res://failures/config.gd")
const Weather := preload("res://physics/wind_config.gd")
const Driver := preload("res://tests/ui_driver.gd")
const Preferences := preload("res://app_state/preferences.gd")
const App := preload("res://app_root.gd")
const PREFS := "user://test_home_launch_summary.cfg"

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


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)
	else:
		print("ok ", label)


func settle() -> void:
	for _i in 10:
		await process_frame


func fits(control: Control) -> bool:
	return Rect2(Vector2.ZERO, Vector2(1920, 1080)).grow(0.5).encloses(control.get_global_rect())


func summary_matches(home: Control) -> bool:
	var text: String = home._fly_caption.text
	return text.contains(home.tr(Catalog.short_name(home.aircraft_id))) \
		and text.contains(home.tr(Landscapes.entry(home.landscape_id).name)) \
		and text.contains(home.start_button.text)


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var ui := Driver.new(self)
	for locale: String in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for scale: float in [1.0, 2.0]:
			UiTheme.text_scale = scale
			var home := Home.new()
			home.theme = UiTheme.build()
			root.add_child(home)
			await settle()
			for page: int in [1, 2]:
				home._select_page(page)
				home.set_start_preferences("runway", "runway")
				home.set_aircraft("moonrunner-x99")
				await settle()
				check("%s %s page%d gearless selection resolves hand launch" % [locale, scale, page], home.start_choice == "hand_launch" and home.start_preference(false) == "runway")
				check("resolved hand launch, field and aircraft are beside Fly", summary_matches(home) and home._fly_caption.is_visible_in_tree())
				home.fly_button.grab_focus()
				home.set_start_choice("airborne")
				await settle()
				check("start-only change refreshes caption without stealing focus", summary_matches(home) and home.fly_button.has_focus())
				home.set_aircraft("jensen-das-ugly-stik-60")
				home.set_start_choice("runway")
				home.runway_available = false
				home.rotorcraft_pad_available = false
				home.set_landscape("green_paradise")
				home.reapply_start_preference()
				await settle()
				check("field change describes effective airborne start, keeping runway preference", home.start_choice == "airborne" and home.start_preference(false) == "runway" and summary_matches(home))
				home.set_aircraft("xcell-60-research")
				await settle()
				check("rotorcraft field without pad describes effective hover", home.start_choice == "airborne" and home.start_preference(true) == "runway" and summary_matches(home))
				home.runway_available = true
				home.rotorcraft_pad_available = true
				home.set_landscape("club_field")
				home.reapply_start_preference()
				await settle()
				check("pad restored without rewriting remembered helicopter preference", home.start_choice == "runway" and summary_matches(home))
				home.set_aircraft("moonrunner-x99")
				var active := Failures.defaults()
				active.probability_percent = 35
				home.set_failure_config(active)
				home.set_note("Could not save settings (error 13).")
				await settle()
				check("caption, practice, feedback and Fly fit together", fits(home._fly_caption) and fits(home.failure_launch_notice) and fits(home.note_label) and fits(home.fly_button))
				check("utilities remain visible", fits(home.controls_button) and fits(home.help_button) and fits(home.quit_button))
				var prior := home.start_preference(false)
				TranslationServer.set_locale("es" if locale == "en" else "en")
				await settle()
				check("live language updates summary and retains effective and remembered starts", summary_matches(home) and home.start_choice == "hand_launch" and home.start_preference(false) == prior)
				TranslationServer.set_locale(locale)
				home.set_note("")
				home.set_failure_config(Failures.defaults())
				home.set_aircraft("xcell-60-research")
				home.set_weather_config(Weather.spatial_defaults())
				await settle()
				check("refused conditions preserve setup summary and correction action", summary_matches(home) and home.launch_warning.visible and home.review_conditions_button.visible and fits(home._fly_caption) and fits(home.review_conditions_button))
				home.set_weather_config(Weather.defaults())
				# UI-39: an RC car shows its own caption (Next drive), never the helicopter's refused conditions.
				home.set_activity("mt8-bisonte")
				home._select_page(1)
				await settle()
				check("an RC car caption names the car and drops the conditions warning",
					home._fly_caption.text.begins_with(home.tr("Next drive: %s") % "Bisonte MT8") and not home.launch_warning.visible
					and fits(home._fly_caption))
				home._select_page(page)
				home.set_aircraft("jensen-das-ugly-stik-60")
				home.set_start_choice("runway")
				await settle()
				check("ordinary page return restores current summary", summary_matches(home) and home._fly_caption.is_visible_in_tree())
			home.free()
			await settle()
	UiTheme.text_scale = 1.0
	TranslationServer.set_locale("en")
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	prefs.check_updates = false
	prefs.language = "en"
	check("save isolated handoff preferences", Preferences.save_to(PREFS, prefs) == OK)
	var app := TestApp.new()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	app.home_flight_prefetch_mode = "off"
	app.flight_loading_enabled = true
	app.window_focus_probe = func() -> bool: return true
	root.add_child(app)
	await settle()
	for setup: Array in [["moonrunner-x99", "club_field", "hand_launch"], ["jensen-das-ugly-stik-60", "green_paradise", "airborne"], ["xcell-60-research", "green_paradise", "airborne"]]:
		app.set_aircraft(setup[0])
		app.set_landscape(setup[1])
		app.home.set_start_choice("runway")
		app.home._select_page(1)
		await settle()
		check("root resolver summary before Fly", app.home.start_choice == setup[2] and summary_matches(app.home))
		var shown: String = app.home._fly_caption.text
		var shown_aircraft: String = app.home.tr(Catalog.short_name(setup[0]))
		var shown_landscape: String = app.home.tr(Landscapes.entry(setup[1]).name)
		app.home._on_fly()
		for _i in 1500:
			if app.flight != null or not app._loading_active:
				break
			await process_frame
		check("Fly submits the displayed resolved values", app.flight != null and app._loading_active and app.flight.aircraft_id == setup[0] and app.flight.landscape_id == setup[1] and app.flight.start_choice == setup[2])
		check("loading retains displayed aircraft and field", app._loading_screen != null and app._loading_screen.summary_label.text.contains(shown_aircraft) and app._loading_screen.summary_label.text.contains(shown_landscape))
		app.cancel_flight_loading()
		for _i in 1500:
			if not app._loading_active:
				break
			await process_frame
		await settle()
		check("cancellation restores the same actionable summary", app.flight == null and app.last_flight_loading.get("status") == "cancelled" and app.home._fly_caption.text == shown and not app.home.fly_button.disabled)
	await ui.close_app(app)
	for suffix: String in ["", ".display", ".controllers", ".legacy_rc"]:
		var path := ProjectSettings.globalize_path(PREFS + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("Home launch summary: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
