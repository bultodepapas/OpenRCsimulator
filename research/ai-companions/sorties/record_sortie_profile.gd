## AFC-09 focused environment baseline. Runs the accepted external-tick driver once and preserves its trace.
extends SceneTree

const WindConfig := preload("res://physics/wind_config.gd")

var options: Dictionary = {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		options[pair[0]] = pair[1] if pair.size() > 1 else true
	call_deferred("_run")


func _run() -> void:
	var direction := str(options.get("direction", ""))
	var profile := str(options.get("profile", "calm"))
	var log_path := str(options.get("log", ""))
	var output_path := str(options.get("out", ""))
	var pilot_path := str(options.get("pilot", get_script().resource_path.get_base_dir().path_join("circuit_pilot_candidate.gd")))
	var seed_value := int(options.get("seed", 0))
	var duration_s := float(options.get("duration", 240.0))
	if direction not in ["east", "west"] or profile not in ["calm", "headwind", "tailwind", "north_crosswind", "south_crosswind"] \
			or log_path.is_empty() or output_path.is_empty() or not log_path.to_lower().ends_with(".orfl"):
		printerr("Required: --direction=east|west --profile=calm|headwind|tailwind|north_crosswind|south_crosswind --log=<new.orfl> --out=<new.json> [--seed=N]")
		quit(2)
		return
	if FileAccess.file_exists(log_path) or FileAccess.file_exists(output_path):
		printerr("Profile baseline outputs must be new files.")
		quit(2)
	var weather := WindConfig.defaults()
	if profile != "calm":
		weather = WindConfig.GENTLE_PRACTICE.duplicate(true)
		weather.from_deg = _from_degrees(profile, direction)
		weather.turbulence_seed = seed_value
	var checked: Dictionary = WindConfig.validate(weather)
	if not checked.get("ok", false):
		printerr("Weather setup refused: " + str(checked.get("errors", [])))
		quit(2)
		return
	var driver_path: String = get_script().resource_path.get_base_dir().path_join("external_sortie_driver.gd")
	var driver: Script = load(driver_path)
	if driver == null or load(pilot_path) == null:
		printerr("Profile driver or pilot could not be loaded.")
		quit(2)
		return
	var result: Dictionary = driver.run(direction == "east", log_path, duration_s, pilot_path,
		checked.config, profile, true)
	var report := {
		format = "openrc-ai-sortie-profile-record v1",
		complete = bool(result.get("complete", false)),
		profile = profile,
		direction = direction,
		seed = seed_value,
		pilot_path = pilot_path,
		pilot_sha256 = FileAccess.get_sha256(pilot_path),
		log_path = log_path,
		log_sha256 = FileAccess.get_sha256(log_path) if FileAccess.file_exists(log_path) else "",
		result = result,
	}
	var absolute: String = ProjectSettings.globalize_path(output_path)
	var make_error: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if make_error != OK:
		printerr("Cannot create report directory: " + str(make_error))
		quit(2)
		return
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write profile report: " + output_path)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("AFC-09 profile %s/%s: complete=%s ticks=%d ORFL=%s report=%s" % [direction, profile,
		str(report.complete), int(result.get("tick_count", 0)), log_path, output_path])
	quit(0 if bool(result.get("ok", false)) and bool(result.get("complete", false)) else 1)


func _from_degrees(profile: String, direction: String) -> float:
	match profile:
		"headwind":
			return 90.0 if direction == "east" else 270.0
		"tailwind":
			return 270.0 if direction == "east" else 90.0
		"north_crosswind":
			return 0.0
		"south_crosswind":
			return 180.0
		_:
			return 0.0
