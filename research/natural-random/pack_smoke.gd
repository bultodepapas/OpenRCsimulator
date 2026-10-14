## Run with --main-pack=<exported.pck>; uses only resources present in the actual export.
extends SceneTree

const AppRoot = preload("res://app_root.gd")
const Preferences = preload("res://app_state/preferences.gd")
const Generator = preload("res://scenarios/natural_random.gd")
const ScenarioConfig = preload("res://scenarios/scenario_config.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var found: Dictionary = {}
	for seed_value: int in 200:
		var generated: Dictionary = Generator.generate(seed_value)
		if not generated.ok:
			printerr("FAIL packed generation: ", generated.errors)
			quit(1)
			return
		found[generated.scenario.aircraft_id] = true
		if found.size() == 5:
			break
	if found.size() != 5:
		printerr("FAIL exported stock pool incomplete")
		quit(1)
		return
	var preferences_path: String = "user://nr_pack_smoke_%d.cfg" % OS.get_process_id()
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	prefs.check_updates = false
	Preferences.save_to(preferences_path, prefs)
	var original: PackedByteArray = FileAccess.get_file_as_bytes(preferences_path)
	var app := AppRoot.new()
	app.preferences_path = preferences_path
	app.user_args = PackedStringArray()
	app.random_seed_source = func() -> int: return 4
	root.add_child(app)
	app.open_natural_random()
	var ok: bool = app.natural_random_screen != null and not app.natural_random_screen.fly_button.disabled
	if ok:
		app.natural_random_screen.fly_button.pressed.emit()
		ok = app.flight != null and not app.flight.flight_scenario.is_empty()
	if ok:
		ok = ScenarioConfig.validate(app.flight.flight_scenario).ok \
			and app.flight.flight_scenario.build_identity.describe != "development" \
			and app.flight.session.is_flyable() and FileAccess.get_file_as_bytes(preferences_path) == original
	if not ok:
		printerr("FAIL exported Home -> Natural Random -> Fly")
	app.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences_path))
	print("NR packed smoke: ", "PASS; five stock sources and interactive launch" if ok else "FAIL")
	quit(0 if ok else 1)
