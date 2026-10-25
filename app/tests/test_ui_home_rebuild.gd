## UI-34c: latest Home lighting selection wins without redundant world construction.
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const Conditions := preload("res://render/world/conditions.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const CORSAIR := "f4u-corsair-250"
const PREFS := "user://test_ui_home_rebuild.cfg"

class CountingRoot extends "res://app_root.gd":
	var rebuild_count := 0
	func _rebuild_home_scene() -> bool:
		rebuild_count += 1
		return super._rebuild_home_scene()

var _failed := 0
var _checks := 0

func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failed += 1
	print(("PASS " if passed else "FAIL ") + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	prefs.start_choice = "airborne"
	_check("private preferences save", Preferences.save_to(PREFS, prefs) == OK)
	var app := CountingRoot.new()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	app.controllers.select_devices(-1, -1)
	var ui := UiDriver.new(self)
	await ui.settle()
	var initial_scene: WeakRef = weakref(app.home_scene)
	var aircraft: String = app.home.aircraft_id
	for preset in ["day", "evening", "night", "day", "evening"]:
		app.set_time_of_day(preset)
	_check("selection feedback updates before building", app.home.time_of_day == "evening" and app.rebuild_count == 0)
	await ui.settle()
	_check("one world built for a selection burst", app.rebuild_count == 1)
	_check("obsolete world released", initial_scene.get_ref() == null)
	_check("latest preset retained in UI, world policy and saved preferences",
		app.home.time_of_day == "evening" and Conditions.session_preset == "evening"
		and Preferences.load_from(PREFS).time_of_day == "evening")
	_check("aircraft and current camera preserved", app.home.aircraft_id == aircraft
		and root.get_camera_3d() == app.home_scene.camera)
	# F4U-19: the Corsair ships one paint until its g2 liveries arrive; then its second scheme is the selection.
	var choices: Array = AirplaneBuilder.livery_choices(CORSAIR)
	var livery: String = choices[1].id if choices.size() > 1 else ""
	app.set_aircraft(CORSAIR)
	app.set_livery(livery)
	_check("Home remembers the selected Corsair livery", app.home.aircraft_id == CORSAIR
		and app.home.livery_id == livery)
	var painted_scene: WeakRef = weakref(app.home_scene)
	_check("Home world rebuild succeeds with selected paint", app._rebuild_home_scene())
	await ui.settle()
	_check("Home world rebuild preserves the selected livery", app.home_scene.airplane.get("livery", "") == livery)
	_check("replaced painted Home scene is released", painted_scene.get_ref() == null)
	app.set_aircraft(aircraft)
	app.rebuild_count = 1 # keep later assertions scoped to the existing time-of-day requests
	_check("original aircraft selection restored after livery check", app.home.aircraft_id == aircraft)
	app.home.time_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("later keyboard selection builds normally", app.rebuild_count == 2
		and app.home.time_of_day == Conditions.next_home_choice("evening"))
	app.rebuild_count = 0
	app.set_time_of_day("day")
	app.set_landscape("green_paradise")
	var landscape_scene: WeakRef = weakref(app.home_scene)
	await ui.settle()
	_check("landscape replacement cancels stale lighting build", app.rebuild_count == 1
		and app.home_scene == landscape_scene.get_ref() and app.landscape_id == "green_paradise")
	app.rebuild_count = 0
	app.set_time_of_day("evening")
	app.start_flight()
	await ui.settle()
	_check("departure cancels pending Home build", app.rebuild_count == 0 and app.home_scene == null
		and app.flight != null and app.flight.session.is_flyable())
	app.end_flight()
	await ui.settle()
	app.set_time_of_day("day")
	await ui.settle()
	_check("new Home accepts a fresh lighting request", app.rebuild_count == 1 and app.home != null
		and app.home.time_of_day == "day")
	var closing_scene: WeakRef = weakref(app.home_scene)
	await ui.close_app(app)
	_check("Home scene is released at app teardown", closing_scene.get_ref() == null)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("Home rebuild: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)
