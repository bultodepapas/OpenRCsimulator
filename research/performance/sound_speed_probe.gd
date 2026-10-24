## Paired CPU probe for the production FlightAudio adapter.
## Run from the repository root with the pinned Godot build:
## godot --headless --audio-driver Dummy --path app --script <absolute-probe-path> -- --output=<absolute-json-path>
extends SceneTree

const AirplaneBuilder := preload("res://render/airplane.gd")
const WeatherConfig := preload("res://physics/wind_config.gd")

const CASES := [
	{ "id": "stik-calm", "aircraft_id": AirplaneBuilder.STIK_ID, "weather_id": "calm" },
	{ "id": "extra-hot-high", "aircraft_id": AirplaneBuilder.EXTRA_ID, "weather_id": "hot-high" },
	{ "id": "p51-cool-dense", "aircraft_id": AirplaneBuilder.P51_ID, "weather_id": "cool-dense" },
]
const SOURCE_PATHS := {
	"flight_audio": "res://audio/flight_audio.gd",
	"main": "res://main.gd",
	"flight_session": "res://sim/flight_session.gd",
	"wind_config": "res://physics/wind_config.gd",
}
const BATCHES := 9
const CALLS_PER_BATCH := 150

var _failures := 0
var _checksum := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var options: Dictionary = _options()
	if not options.ok:
		printerr("sound speed probe refused: ", options.error)
		quit(1)
		return
	var output_path: String = options.output
	if FileAccess.file_exists(output_path):
		printerr("sound speed probe refuses existing output: ", output_path)
		quit(1)
		return

	var source_hashes: Dictionary = _source_hashes()
	for source_name: String in source_hashes:
		if str(source_hashes[source_name]).is_empty():
			_failures += 1
			printerr("could not hash source ", source_name)

	var case_reports: Array[Dictionary] = []
	for case: Dictionary in CASES:
		var flight: Node = load("res://main.tscn").instantiate()
		flight.aircraft_id = str(case.aircraft_id)
		flight.weather_config = WeatherConfig.preset(str(case.weather_id))
		flight.user_args = PackedStringArray()
		root.add_child(flight)
		await process_frame
		if flight.session == null or not flight.session.is_flyable():
			_failures += 1
			printerr("probe setup failed %s: %s" % [case.id, flight.startup_error])
			flight.free()
			continue

		# Freeze the configured production scene while calling the real snapshot/getter methods.
		flight.process_mode = Node.PROCESS_MODE_DISABLED
		var audio: Variant = flight.get("_soundscape_audio")
		if audio == null:
			_failures += 1
			printerr("FlightAudio was not configured for %s" % case.id)
			flight.free()
			continue
		var atmosphere: Dictionary = flight.session.atmosphere_configuration()
		var expected_speed: float = sqrt(1.4 * 287.05 * float(atmosphere.get("temperature_k", 288.15)))
		var snapshot: Dictionary = audio.call("snapshot")
		var snapshot_speed: float = float(snapshot.get("sound_speed", NAN))
		var getter_speed: float = float(audio.call("sound_speed_mps"))
		var exact_parity: bool = snapshot_speed == getter_speed and getter_speed == expected_speed
		if not exact_parity:
			_failures += 1
			printerr("parity failed %s: snapshot=%0.12f getter=%0.12f expected=%0.12f" % [
				case.id, snapshot_speed, getter_speed, expected_speed])

		# Warm both paths, then alternate which one runs first in each timed batch.
		for _i in 50:
			audio.call("snapshot")
			audio.call("sound_speed_mps")
		var snapshot_samples: Array[float] = []
		var getter_samples: Array[float] = []
		var batch_order: Array[String] = []
		for batch in BATCHES:
			if batch % 2 == 0:
				batch_order.append("snapshot-then-getter")
				snapshot_samples.append(_measure(audio, true))
				getter_samples.append(_measure(audio, false))
			else:
				batch_order.append("getter-then-snapshot")
				getter_samples.append(_measure(audio, false))
				snapshot_samples.append(_measure(audio, true))

		case_reports.append({
			"case": case.id,
			"aircraft_id": case.aircraft_id,
			"weather_id": case.weather_id,
			"temperature_k": atmosphere.get("temperature_k", 288.15),
			"expected_sound_speed_mps": expected_speed,
			"snapshot_sound_speed_mps": snapshot_speed,
			"getter_sound_speed_mps": getter_speed,
			"exact_parity": exact_parity,
			"calls_per_batch": CALLS_PER_BATCH,
			"snapshot_us_per_call_by_batch": snapshot_samples,
			"getter_us_per_call_by_batch": getter_samples,
			"batch_order": batch_order,
			"snapshot_median_us_per_call": _median(snapshot_samples),
			"getter_median_us_per_call": _median(getter_samples),
		})
		flight.free()

	var report := {
		"format": "openrc-sound-speed-probe v1",
		"complete": _failures == 0 and case_reports.size() == CASES.size(),
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"display_server": DisplayServer.get_name(),
		"processor": OS.get_processor_name(),
		"scope": "per-call CPU timing on snapshot/getter methods of a frozen, instantiated production flight scene; excludes rendered-frame and full-callback cost",
		"source_sha256": source_hashes,
		"batch_count": BATCHES,
		"warmup_calls_per_path": 50,
		"cases": case_reports,
		"checksum": _checksum,
		"failures": _failures,
	}
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		printerr("cannot write sound speed probe output: ", error_string(FileAccess.get_open_error()))
		quit(1)
		return
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.flush()
	var write_error: Error = output.get_error()
	output.close()
	if write_error != OK:
		printerr("sound speed probe output write failed: ", error_string(write_error))
		quit(1)
		return
	print("sound speed probe: cases=%d failures=%d → %s" % [case_reports.size(), _failures, output_path])
	quit(0 if report.complete else 1)


func _options() -> Dictionary:
	var output_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		else:
			return {"ok": false, "error": "unknown option " + argument}
	if output_path.is_empty():
		return {"ok": false, "error": "--output is required"}
	return {"ok": true, "output": output_path}


func _source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for source_name: String in SOURCE_PATHS:
		hashes[source_name] = _sha256(str(SOURCE_PATHS[source_name]))
	hashes["probe"] = _sha256(str(get_script().resource_path))
	return hashes


func _sha256(path: String) -> String:
	var file_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	if not FileAccess.file_exists(file_path):
		return ""
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(file.get_buffer(file.get_length()))
	return context.finish().hex_encode()


func _measure(audio: Variant, use_snapshot: bool) -> float:
	var started: int = Time.get_ticks_usec()
	var subtotal := 0.0
	if use_snapshot:
		for _i in CALLS_PER_BATCH:
			var result: Dictionary = audio.call("snapshot")
			subtotal += float(result.get("sound_speed", NAN))
	else:
		for _i in CALLS_PER_BATCH:
			subtotal += float(audio.call("sound_speed_mps"))
	_checksum += subtotal
	return float(Time.get_ticks_usec() - started) / float(CALLS_PER_BATCH)


func _median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[int(sorted.size() / 2)]
