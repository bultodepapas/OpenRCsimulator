extends SceneTree
## F4U-16: paint schemes through the production shell. Home's Paint row cycles every Corsair scheme, the backdrop
## rebuilds each one, every choice is saved per aircraft, another aircraft shows no row, and Fly builds the chosen
## scheme. The direct route accepts --livery=<id> and refuses an unknown one. Writes checks.json and 1080p
## screenshots to a new directory; preferences stay in an isolated user:// file.
## Godot_v4.7.2-stable_win64.exe --rendering-driver opengl3 --resolution 1920x1080 --path app \
##   --script <repo>/research/f4u-corsair/F4U-16/livery_check.gd -- --out=<new dir>
const Preferences := preload("res://app_state/preferences.gd")
const Registry := preload("res://aircraft/model_registry.gd")
const CORSAIR := "f4u-corsair-250"
const STIK := "jensen-das-ugly-stik-60"
const PREFS := "user://f4u16_livery_check.cfg"
var out := ""
var checks := []
var app: Node


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
	if out.is_empty() or DirAccess.dir_exists_absolute(out):
		printerr("F4U-16 livery check: pass --out=<new directory>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	checks.append({label = label, ok = ok, detail = detail})
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else " (" + detail + ")"))


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _wait_until(condition: Callable, seconds: float) -> bool:
	var start := Time.get_ticks_msec()
	while not condition.call() and Time.get_ticks_msec() - start < seconds * 1000.0:
		await process_frame
	return condition.call()


func _backdrop_shows(livery: String) -> Callable:
	return func() -> bool: return not app.home_scene.preview_pending and app.home_scene.airplane.get("livery", "") == livery


func _press_paint(livery: String) -> bool:
	app.home.livery_button.pressed.emit()
	return await _wait_until(_backdrop_shows(livery), 30.0)


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await process_frame
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var preferences: Dictionary = Preferences.DEFAULTS.duplicate(true)
	preferences.aircraft = CORSAIR
	preferences.first_flight_hint_seen = true
	Preferences.save_to(PREFS, preferences)
	var manifest: Dictionary = Registry.describe(CORSAIR).manifest
	app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	var home: Control = app.home
	var opened := await _wait_until(_backdrop_shows("midnight"), 30.0)
	home._select_page(1) # the Aircraft page, where the Paint row sits above the catalog
	await process_frame
	_check("Home opens on the Corsair with its default paint", opened and home.aircraft_id == CORSAIR and home.livery_id == ""
		and home.livery_button.is_visible_in_tree() and home.livery_button.text.contains("Naval 308"), home.livery_button.text)
	await _shot("home-midnight")

	for index in range(1, manifest.liveries.size()):
		var expected: Dictionary = manifest.liveries[index]
		var shown := await _press_paint(expected.id)
		_check("Paint shows %s on the row and the backdrop" % expected.label, shown and home.livery_id == expected.id
			and home.livery_button.text.contains(expected.label) and app.home_scene.airplane.root.get_meta("asset_sha256") == expected.sha256)
		_check("%s is saved for the Corsair" % expected.id, Preferences.load_from(PREFS).liveries == {CORSAIR: expected.id})
		await _shot("home-" + expected.id)
	var wrapped := await _press_paint("midnight")
	_check("the last scheme cycles back to the default paint, saved as no entry", wrapped and home.livery_id == ""
		and Preferences.load_from(PREFS).liveries.is_empty())

	for record: Dictionary in manifest.liveries.slice(1):
		await _press_paint(record.id)
		if record.id == "spectrum": break
	app.set_aircraft(STIK)
	await _wait_until(func() -> bool: return not app.home_scene.preview_pending, 30.0)
	_check("a one-paint aircraft shows no Paint row", not home.livery_button.visible)
	app.set_aircraft(CORSAIR)
	var restored := await _wait_until(_backdrop_shows("spectrum"), 30.0)
	_check("returning to the Corsair restores its scheme from the backdrop cache", restored and home.livery_id == "spectrum")

	app.start_flight()
	# UI-34c: a rendered Home launch is staged, so the flight appears after its loading screen.
	await _wait_until(func() -> bool: return app.flight != null, 60.0)
	var flight: Node = app.flight
	_check("Fly starts", flight != null and str(flight.get("startup_error")) == "", str(flight.get("startup_error")) if flight != null else "no flight")
	if flight != null:
		await create_timer(1.5).timeout
		var airplane: Dictionary = flight.get("_airplane")
		var spectrum: Dictionary = manifest.liveries.filter(func(record: Dictionary) -> bool: return record.id == "spectrum")[0]
		_check("the flight builds the chosen scheme", flight.livery == "spectrum" and airplane.get("livery") == "spectrum"
			and airplane.root.get_meta("asset_sha256") == spectrum.sha256)
		var chase := InputEventKey.new()
		chase.physical_keycode = KEY_2
		chase.pressed = true
		Input.parse_input_event(chase)
		await create_timer(1.0).timeout
		await _shot("flight-spectrum")

	var godot := OS.get_executable_path()
	var app_path := ProjectSettings.globalize_path("res://")
	var output: Array = []
	var refused := OS.execute(godot, ["--headless", "--path", app_path, "--audio-driver", "Dummy", "--", "--aircraft=" + CORSAIR, "--livery=retired"], output, true)
	_check("the direct route refuses an unknown livery", refused == ERR_INVALID_PARAMETER and "\n".join(output).contains("livery refused"), "exit %d" % refused)
	output.clear()
	var accepted := OS.execute(godot, ["--headless", "--path", app_path, "--audio-driver", "Dummy", "--quit-after", "240", "--", "--aircraft=" + CORSAIR, "--livery=blueangels"], output, true)
	_check("the direct route flies --livery=blueangels", accepted == 0 and not "\n".join(output).contains("livery refused"), "exit %d" % accepted)

	var failed := checks.filter(func(c: Dictionary) -> bool: return not c.ok).size()
	var file := FileAccess.open(out.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({format = "F4U-16 livery check v1", checks = checks, failures = failed}, "\t"))
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("F4U-16 livery check: %d checks, %d failures" % [checks.size(), failed])
	quit(1 if failed else 0)
