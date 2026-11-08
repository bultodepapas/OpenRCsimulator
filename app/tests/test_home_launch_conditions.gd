## UI-32 / A14 F13: visible admission, recovery and staged cancellation.
extends SceneTree
const Home = preload("res://ui/home.gd")
const App = preload("res://app_root.gd")
const Weather = preload("res://physics/wind_config.gd")
const Preferences = preload("res://app_state/preferences.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const Driver = preload("res://tests/ui_driver.gd")
const PREFS = "user://test_home_launch_conditions.cfg"
# Seed 4 selects Timber, whose cancelled preview exercises material teardown.
const RANDOM_SEED = 4
const RANDOM_AIRCRAFT = "turbo-lumber-evolution"
class Candidate extends Node:
	signal startup_finished
	var startup_error := ""
	var startup_complete := false
	var startup_cancel_requested: Callable
	var recorder: Node
	var session: Node
	func _set(_property: StringName, _value: Variant) -> bool:
		return true
	func _ready() -> void:
		while not startup_cancel_requested.call():
			await get_tree().process_frame
		startup_error = "Flight preparation cancelled."
		startup_complete = true
		startup_finished.emit()
class TestApp extends App:
	var creations := 0
	func _create_flight(_aircraft_id: String = "") -> Node:
		creations += 1
		return Candidate.new()
var checks := 0
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ",label)
	else:
		print("ok   ",label)
func frames(count: int = 5) -> void:
	for _i in count:
		await process_frame
func run() -> void:
	var ui = Driver.new(self)
	root.size = Vector2i(1920,1080)
	for locale in ["en","es"]:
		TranslationServer.set_locale(locale)
		for scale in [1.0,2.0]:
			UiTheme.text_scale = scale
			var h = Home.new()
			h.theme = UiTheme.build()
			h.set_aircraft("xcell-60-research")
			h.set_weather_config(Weather.spatial_defaults())
			root.add_child(h)
			await frames()
			for page in [0,1]:
				h._select_page(page)
				await frames()
				check("%s/%s page %s admission beside Fly" % [locale,scale,page],h.launch_warning.is_visible_in_tree() and h.review_conditions_button.is_visible_in_tree() and h.fly_button.disabled)
				var r: Rect2 = h.review_conditions_button.get_global_rect()
				check("%s/%s page %s recovery inside primary viewport" % [locale,scale,page],r.position.y >= 0 and r.end.y <= 1080 and r.end.x <= 1920)
				check("shared Fly and utilities remain fully in viewport",h.fly_button.get_global_rect().end.y <= 1080 and h.quit_button.get_global_rect().end.y <= 1080)
				h.reject_start("Injected runtime refusal")
				check("runtime refusal visible on both pages",h.note_label.is_visible_in_tree())
				h.controls_button.grab_focus()
				await ui.tap(KEY_UP)
				check("directional navigation reaches corrective action",h.review_conditions_button.has_focus())
			h.fail_start("Flight scene could not be created.")
			TranslationServer.set_locale("es" if locale == "en" else "en")
			check("runtime launch outcome follows locale",h.note_label.text == h.tr("Could not start flight: %s") % h.tr("Flight scene could not be created."))
			TranslationServer.set_locale(locale)
			h.set_weather_config(Weather.defaults())
			check("correcting conditions clears launch-owned failure",not h.note_label.visible)
			h.set_note("Independent save failure")
			h.set_aircraft("jensen-das-ugly-stik-60")
			check("aircraft correction preserves independent feedback",h.note_label.text == "Independent save failure")
			check("supported correction enables Fly",not h.fly_button.disabled and not h.launch_warning.visible and not h.review_conditions_button.visible)
			h.cancel_start()
			check("cancel message differs from failure",h.note_label.text == h.tr("Flight preparation cancelled.") and h.fly_button.has_focus())
			h._select_page(3)
			h.get_viewport().gui_release_focus()
			h.ensure_focus()
			check("Garage has visible fallback focus",h.ground_vehicle_button.has_focus())
			h.free()
			await frames(1)
	UiTheme.text_scale = 1.0
	TranslationServer.set_locale("en")
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	prefs.check_updates = false
	prefs.language = "en"
	prefs.aircraft = "xcell-60-research"
	prefs.weather_config = Weather.spatial_defaults()
	check("save isolated preferences",Preferences.save_to(PREFS,prefs) == OK)
	var app = TestApp.new()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	app.home_flight_prefetch_mode = "off"
	app.flight_loading_enabled = true
	app.window_focus_probe = func() -> bool: return true
	app.random_seed_source = func() -> int: return RANDOM_SEED
	root.add_child(app)
	root.size = Vector2i(1920,1080)
	await frames(8)
	var saved: PackedByteArray = FileAccess.get_file_as_bytes(PREFS)
	app.start_flight()
	check("root rejects known conditions before candidate or loading",app.creations == 0 and not app._loading_active and app.flight == null)
	app.home._select_page(1)
	app.home.review_conditions_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await frames()
	check("Review opens Conditions from Aircraft",app.screens.is_top("weather"))
	app.weather_dialog.cancel_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await frames()
	check("Conditions Cancel returns to invoking action",app.screens.is_top("home") and app.home.review_conditions_button.has_focus() and FileAccess.get_file_as_bytes(PREFS) == saved)
	app.home.review_conditions_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await frames()
	app.weather_dialog._on_preset_selected(1)
	app.weather_dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await frames()
	check("Conditions Apply restores focus after corrective action disappears",app.screens.is_top("home") and not app.home.review_conditions_button.visible and app.home.fly_button.has_focus())
	var turbulence: Dictionary = Weather.upgrade_atmosphere(Weather.defaults())
	turbulence.turbulence_rms_mps = [0.3,0.2,0.1]
	app.preferences.weather_config = turbulence.duplicate(true)
	app.home.set_weather_config(App.weather_for_aircraft("xcell-60-research",turbulence))
	check("effective rotor weather admitted while saved airplane turbulence survives",not app.home.fly_button.disabled and app.preferences.weather_config == turbulence and not Weather.has_turbulence(app.home.weather_config))
	# Cancel a candidate that exists, then cancel an actual Random briefing candidate.
	for random_route in [false,true]:
		if random_route:
			app.open_natural_random()
			await frames()
			check("seeded Random cancellation covers Timber preview",str(app.natural_random_screen._scenario.get("aircraft_id","")) == RANDOM_AIRCRAFT)
		if random_route:
			app.natural_random_screen._on_fly()
		else:
			app.home._on_fly()
		for _i in 1500:
			if app.flight != null or not app._loading_active:
				break
			await process_frame
		check("candidate reached before cancellation",app.flight != null and app._loading_active)
		app.cancel_flight_loading()
		for _i in 1500:
			if not app._loading_active:
				break
			await process_frame
		await frames()
		check("candidate cancellation returns without failure wording",app.flight == null and app.last_flight_loading.get("status") == "cancelled" and app.home.note_label.text == app.home.tr("Flight preparation cancelled."))
		if random_route:
			check("Random cancellation keeps briefing usable",app.screens.is_top("natural_random") and not app.natural_random_screen.fly_button.disabled and not app.natural_random_screen.error_label.visible)
			app.close_natural_random()
	await ui.close_app(app)
	for suffix in ["",".display",".controllers",".legacy_rc"]:
		var path: String = ProjectSettings.globalize_path(PREFS+suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("Home launch conditions: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
