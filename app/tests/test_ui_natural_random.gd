## NR-04/05/06: real menu input, launch rollback, preference isolation and accepted-scenario lifecycle.
extends SceneTree

const AppRoot = preload("res://app_root.gd")
const Main = preload("res://main.gd")
const Preferences = preload("res://app_state/preferences.gd")
const UiDriver = preload("res://tests/ui_driver.gd")
const ScenarioConfig = preload("res://scenarios/scenario_config.gd")
const World = preload("res://render/world/world.gd")
const Atmosphere = preload("res://render/atmosphere.gd")

class CandidateFlight extends Main:
	var refuse_world: bool = false
	func _build_world() -> bool:
		var built: bool = super._build_world()
		if built and refuse_world:
			startup_error = "Injected failure after World.build"
			return false
		return built

class TestApp extends AppRoot:
	var refuse_world: bool = false
	func _create_flight(_aircraft_id: String = "") -> Node:
		var candidate := CandidateFlight.new()
		candidate.refuse_world = refuse_world
		return candidate

var _failures: int = 0
var _checks: int = 0
var ui: RefCounted
var _prefs_path: String = "user://test_natural_random_%d.cfg" % OS.get_process_id()

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL " + label)
	else:
		print("ok   " + label)

func _press(button: Button) -> void:
	button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()

func _run() -> void:
	ui = UiDriver.new(self)
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	prefs.check_updates = false
	prefs.language = "en"
	prefs.time_of_day = "evening"
	check("write isolated preferences", Preferences.save_to(_prefs_path, prefs) == OK)
	var saved_bytes: PackedByteArray = FileAccess.get_file_as_bytes(_prefs_path)
	var app := TestApp.new()
	app.user_args = PackedStringArray()
	app.preferences_path = _prefs_path
	var draws: Array[int] = [0]
	app.random_seed_source = func() -> int:
		draws[0] += 1
		return draws[0]
	root.add_child(app)
	await ui.settle()
	var normal: Dictionary = app.preferences.duplicate(true)
	var home_sky: Dictionary = Atmosphere.state.duplicate(true)
	check("ordinary Home still opens with Fly focused", ui.focus_name() == "Fly")
	await _press(app.home.natural_random_button)
	check("Home opens briefing without a flight", app.natural_random_screen != null and app.flight == null)
	if app.natural_random_screen == null:
		app.free()
		_finish()
		return
	check("prepared draw can fly", not app.natural_random_screen.fly_button.disabled)
	await _press(app.natural_random_screen.reroll_button)
	check("Another flight consumes exactly one seed", draws[0] == 2)
	check("draft and reroll do not change Home or preferences", app.preferences == normal
		and FileAccess.get_file_as_bytes(_prefs_path) == saved_bytes)
	var focus_before_radio: String = ui.focus_name()
	await ui.joy_axis(JOY_AXIS_LEFT_X, 1.0)
	check("radio does not navigate briefing", ui.focus_name() == focus_before_radio)
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	check("cancel restores focus to Home action", app.natural_random_screen == null and ui.focus_name() == "NaturalRandom")
	await _press(app.home.natural_random_button)
	app.refuse_world = true
	await _press(app.natural_random_screen.fly_button)
	check("late launch failure keeps the briefing and Home", app.flight == null and app.home != null and app.natural_random_screen != null)
	check("late failure restores flowing Home world", not World._flow.is_empty()
		and Atmosphere.state == home_sky
		and World._flow.environment == app.home_scene.find_children("*", "WorldEnvironment", true, false)[0].environment)
	check("late failure does not change normal preferences", app.preferences == normal and FileAccess.get_file_as_bytes(_prefs_path) == saved_bytes)
	app.refuse_world = false
	await _press(app.natural_random_screen.reroll_button)
	await _press(app.natural_random_screen.fly_button)
	check("briefing launches one accepted random flight", app.flight != null and app.home == null and app.natural_random_screen == null)
	if app.flight == null:
		app.free()
		_finish()
		return
	var flight: Node = app.flight
	flight.session.physics_enabled = false
	flight.session.input_enabled = false
	flight.session.sim.set_paused(true)
	var accepted: Dictionary = flight.flight_scenario.duplicate(true)
	check("accepted stock scenario has valid provenance", ScenarioConfig.validate(accepted).ok and accepted.provenance == "generated"
		and flight.workshop_trial.is_empty() and flight.start_choice == "airborne")
	check("actual physical conditions match the accepted draw", flight.session.weather_configuration() == accepted.weather_config
		and flight.lighting_config == accepted.lighting_config)
	check("random launch preserved saved normal-flight defaults", app.preferences == normal and FileAccess.get_file_as_bytes(_prefs_path) == saved_bytes)
	check("fixed random lighting retired the Home clock", World._flow.is_empty() and not flight._field_world_lighting)
	var meta: Dictionary = flight._trace_meta()
	var decoded: Dictionary = ScenarioConfig.validate(JSON.parse_string(meta.flight_scenario))
	check("trace contains the complete accepted scenario", decoded.ok and decoded.scenario.identity == accepted.identity)
	if not decoded.ok:
		printerr("Trace scenario errors: ", decoded.errors)
	app.open_pause()
	await ui.settle()
	var count_before: int = draws[0]
	app.restart_flight()
	check("Restart keeps the draw and turbulence seed", draws[0] == count_before and flight.flight_scenario == accepted
		and flight.session.sim.tick == 0 and flight.session.weather_configuration() == accepted.weather_config)
	flight.session.sim.set_paused(true)
	app.open_pause()
	await ui.settle()
	app.open_time_of_day()
	await ui.settle()
	var edited: Dictionary = accepted.lighting_config.duplicate(true)
	edited.local_seconds = 40000 if edited.local_seconds != 40000 else 42000
	flight.recorder.start(flight._trace_meta())
	app._on_time_of_day_applied(edited)
	check("pause lighting edit becomes a customized scenario", flight.flight_scenario.provenance == "customized"
		and flight.flight_scenario.parent_identity == accepted.identity and flight.lighting_config == edited
		and app.last_random_scenario == flight.flight_scenario)
	check("random pause edit never writes normal preferences", app.preferences == normal and FileAccess.get_file_as_bytes(_prefs_path) == saved_bytes)
	var trace_initial: Dictionary = ScenarioConfig.validate(JSON.parse_string(flight.recorder.trace.meta.flight_scenario))
	var trace_edits: Array = JSON.parse_string(flight.recorder.trace.meta.flight_scenario_edits)
	var trace_edited: Dictionary = ScenarioConfig.validate(trace_edits[0].scenario)
	check("recording preserves initial scenario and records the lighting edit at its tick", trace_initial.ok
		and trace_initial.scenario.identity == accepted.identity and trace_edits.size() == 1 and trace_edited.ok
		and trace_edited.scenario.identity == flight.flight_scenario.identity and int(trace_edits[0].tick) == flight.session.sim.tick)
	flight.recorder.recording = false # Keep this test's trace in memory; no player trace-file writes.
	app.restart_flight()
	check("edited lighting is the restart selection", flight.lighting_config == edited and flight.session.sim.tick == 0)
	flight.session.sim.set_paused(true)
	var customized: Dictionary = flight.flight_scenario.duplicate(true)
	app.open_pause()
	await ui.settle()
	app.end_flight()
	await ui.settle()
	check("End flight restores ordinary Home selections", app.home != null and app.preferences == normal
		and app.home.aircraft_id == normal.aircraft and app.home.weather_config == normal.weather_config)
	await _press(app.home.natural_random_button)
	await _press(app.natural_random_screen.repeat_button)
	check("Repeat last flight does not draw a new seed", draws[0] == count_before + 1)
	await _press(app.natural_random_screen.fly_button)
	check("Repeat launches the accepted customized selection", app.flight != null and app.flight.flight_scenario == customized)
	if app.flight != null:
		flight = app.flight
		flight.session.physics_enabled = false
		flight.session.input_enabled = false
		flight.session.sim.set_paused(true)
		var checkpoint: Dictionary = flight.checkpoint()
		var restored: Dictionary = flight.restore_checkpoint(checkpoint)
		check("legacy paired checkpoint clears unrecorded random provenance", restored.ok and flight.flight_scenario.is_empty()
			and not flight._trace_meta().has("flight_scenario") and not flight._note.contains("Natural Random"))
		app.open_pause()
		await ui.settle()
		app.open_time_of_day()
		await ui.settle()
		edited.local_seconds = 43000
		app._on_time_of_day_applied(edited)
		check("checkpoint restore preserves normal preference isolation", app.preferences == normal
			and FileAccess.get_file_as_bytes(_prefs_path) == saved_bytes)
	app.free()
	await ui.settle()
	_finish()

func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_prefs_path))
	print("NR UI: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
