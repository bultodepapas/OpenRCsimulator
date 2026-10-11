## TOD-08b: paused lighting edits are atomic visual events on the real Main flight.
extends SceneTree

const Main = preload("res://main.gd")
const Config = preload("res://environment/time_of_day_config.gd")
const Timeline = preload("res://environment/visual_timeline.gd")
const WeatherConfig = preload("res://physics/wind_config.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const ShaderClock = preload("res://render/shader_clock.gd")


class TestFlight extends Main:
	var refuse_lighting_preparation: bool = false
	var refuse_lighting_commit: bool = false
	var requested_args: Dictionary = {}

	func _user_args() -> Dictionary:
		return requested_args.duplicate(true) if not requested_args.is_empty() else super._user_args()

	func _commit_lighting(staged: Dictionary, config: Dictionary) -> bool:
		return false if refuse_lighting_commit else super._commit_lighting(staged, config)

	func _prepare_checkpoint_lighting(config: Dictionary) -> Dictionary:
		if refuse_lighting_preparation:
			return {ok = false}
		return super._prepare_checkpoint_lighting(config)


class MemoryRecorder extends "res://sim/recorder.gd":
	var stops: int = 0

	func stop(path: String = "") -> Error:
		recording = false
		stops += 1
		if path.is_empty():
			return OK
		return super.stop(path)


var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var flight: TestFlight = TestFlight.new()
	flight.interactive_start = true
	root.add_child(flight)
	await process_frame
	if flight.session == null or not flight.startup_error.is_empty():
		_check("production Main starts a ready flight", false, flight.startup_error)
		flight.free()
		quit(1)
		return

	# Stop automatic clocks and input sampling. Manual fixed ticks below keep the real simulation and recorder path.
	flight.set_process(false)
	flight.set_physics_process(false)
	flight.session.set_process(false)
	flight.session.set_physics_process(false)
	flight.session.sim.process_mode = Node.PROCESS_MODE_DISABLED
	flight.recorder.detach()
	flight.recorder = MemoryRecorder.new(flight.session.sim)
	var sim: Node = flight.session.sim
	for _tick: int in 12:
		sim.step()
	var initial_config: Dictionary = Config.defaults()
	var first_config: Dictionary = _astronomical_config(0, "First same-tick edit")
	var second_config: Dictionary = _astronomical_config(64800, "Last same-tick edit")

	var unpaused_before: Dictionary = _observed(flight)
	var unpaused: Dictionary = flight.apply_lighting_config(first_config)
	_check("an unpaused edit is refused with a structured result", not unpaused.ok and not unpaused.changed
		and not unpaused.errors.is_empty(), str(unpaused))
	_check("refusing an unpaused edit is atomic", _observed(flight) == unpaused_before)

	flight.recorder.start(flight._trace_meta())
	sim.step()
	sim.set_paused(true)
	flight.session.input_enabled = true
	flight.session.pause_reason = "test pause provenance"
	flight.session.hold("menu")
	flight.session.hold("calibration")
	var radio: RefCounted = flight.session.radio
	radio.connect_device(7, {guid = "tod08b-radio", name = "RadioMaster test", vendor_id = 10, product_id = 20},
		{kind = "radio", source = "test calibration"})
	radio.profile_source = "calibrated"
	flight._prop_angle = 1.234567890123
	flight._airplane.propeller.rotation.z = flight._prop_angle
	var paused_baseline: Dictionary = _observed(flight)
	_check("fixture is paused with an active recorder and input provenance", sim.paused
		and flight.recorder.recording and flight.recorder.trace.row_count() == 2
		and flight.session.input_enabled and flight.session.holds.size() == 2
		and flight.session.radio.connected and flight.session.radio.profile_source == "calibrated")

	flight.refuse_lighting_commit = true
	var refused_commit: Dictionary = flight.apply_lighting_config(first_config)
	_check("TOD-09b refused scene commit reports failure", not refused_commit.ok and not refused_commit.changed)
	_check("TOD-09b refused scene commit preserves recording and world", _observed(flight) == paused_baseline)
	flight.refuse_lighting_commit = false

	var invalid_config: Dictionary = first_config.duplicate(true)
	invalid_config.local_seconds = 86400
	var invalid: Dictionary = flight.apply_lighting_config(invalid_config)
	_check("invalid edit reports validation errors", not invalid.ok and not invalid.changed and not invalid.errors.is_empty())
	_check("invalid edit preserves the whole live flight", _observed(flight) == paused_baseline)

	var noop: Dictionary = flight.apply_lighting_config(flight.lighting_config.duplicate(true))
	_check("same-config edit reports a successful no-op", noop.ok and not noop.changed and noop.errors.is_empty())
	_check("no-op edit preserves the whole live flight", _observed(flight) == paused_baseline)

	flight.refuse_lighting_preparation = true
	var preparation_failure: Dictionary = flight.apply_lighting_config(first_config)
	_check("lighting preparation failure is reported", not preparation_failure.ok and not preparation_failure.changed
		and not preparation_failure.errors.is_empty())
	_check("preparation failure preserves the whole live flight", _observed(flight) == paused_baseline)
	flight.refuse_lighting_preparation = false

	var baseline_samples: String = _sample_rows(flight.recorder.trace.to_csv())
	var baseline_physics: PackedByteArray = var_to_bytes(flight.session.checkpoint())
	var baseline_input: Dictionary = _input_snapshot(flight)
	var baseline_prop_phase: PackedByteArray = var_to_bytes(flight._prop_angle)
	var baseline_prop_rotation: PackedByteArray = var_to_bytes(flight._airplane.propeller.rotation)
	var baseline_tick: int = sim.tick
	var baseline_rows: int = flight.recorder.trace.row_count()
	var first_result: Dictionary = flight.apply_lighting_config(first_config)
	_check("first paused edit commits", first_result.ok and first_result.changed and first_result.errors.is_empty(), str(first_result))
	_check("TOD-09b retains field, Sun and environment identity during Apply",
		flight._field_node.get_instance_id() == paused_baseline.field_id
		and flight._sun.get_instance_id() == paused_baseline.sun_id
		and flight._env.get_instance_id() == paused_baseline.environment_id)
	_check("visual edit preserves exact physical checkpoint bytes", var_to_bytes(flight.session.checkpoint()) == baseline_physics)
	_check("visual edit preserves input owner, radio provenance, pause reason and holds",
		_input_snapshot(flight) == baseline_input)
	_check("visual edit preserves prop phase and rendered prop rotation",
		var_to_bytes(flight._prop_angle) == baseline_prop_phase
		and var_to_bytes(flight._airplane.propeller.rotation) == baseline_prop_rotation)
	_check("visual edit preserves tick and active recorder samples",
		sim.tick == baseline_tick and flight.recorder.recording
		and flight.recorder.trace.row_count() == baseline_rows
		and _sample_rows(flight.recorder.trace.to_csv()) == baseline_samples)
	_check("first event is attached to the paused simulation tick",
		flight._visual_timeline.events.size() == 1
		and flight._visual_timeline.events[0].tick == baseline_tick
		and flight._visual_timeline.events[0].config == first_config)

	var frozen_context: String = str(flight.recorder.trace.meta.get("visual_context", ""))
	var parsed_context: Variant = JSON.parse_string(frozen_context)
	var normalized_frozen_config: Dictionary = Config.validate(parsed_context.get("config", {})).config if typeof(parsed_context) == TYPE_DICTIONARY else {}
	_check("first edit freezes the recording's pre-edit visual context",
		typeof(parsed_context) == TYPE_DICTIONARY
		and normalized_frozen_config == initial_config, str(parsed_context))
	var first_trace_timeline_text: String = str(flight.recorder.trace.meta.get("visual_timeline", ""))
	var first_trace_timeline: Variant = JSON.parse_string(first_trace_timeline_text)
	_check("active trace receives the first serialized timeline event",
		Timeline.validate(first_trace_timeline).ok
		and Timeline.evaluate(first_trace_timeline, sim.tick).config == first_config)

	var second_result: Dictionary = flight.apply_lighting_config(second_config)
	_check("a second edit at the same tick commits", second_result.ok and second_result.changed, str(second_result))
	_check("same-tick events are retained in append order and the last one wins",
		flight._visual_timeline.events.size() == 2
		and flight._visual_timeline.events[0].tick == baseline_tick
		and flight._visual_timeline.events[1].tick == baseline_tick
		and Timeline.evaluate(flight._visual_timeline, baseline_tick).config == second_config
		and flight.lighting_config == second_config)
	_check("later visual edits keep the initial trace context frozen", flight.recorder.trace.meta.visual_context == frozen_context)
	var active_timeline: Variant = JSON.parse_string(str(flight.recorder.trace.meta.get("visual_timeline", "")))
	_check("active trace timeline is replaced with both events and reconstructs the last selection",
		Timeline.validate(active_timeline).ok
		and active_timeline.events.size() == 2
		and Timeline.evaluate(active_timeline, sim.tick).config == second_config)
	_check("same-tick edit leaves physics and recorded rows unchanged",
		var_to_bytes(flight.session.checkpoint()) == baseline_physics
		and sim.tick == baseline_tick and flight.recorder.trace.row_count() == baseline_rows
		and _sample_rows(flight.recorder.trace.to_csv()) == baseline_samples)

	# A fresh recording starts with the selected context and the full history already in its CSV header.
	flight.recorder.start(flight._trace_meta())
	var started_context: Variant = JSON.parse_string(str(flight.recorder.trace.meta.get("visual_context", "")))
	var normalized_started_config: Dictionary = Config.validate(started_context.get("config", {})).config if typeof(started_context) == TYPE_DICTIONARY else {}
	var started_timeline: Variant = JSON.parse_string(str(flight.recorder.trace.meta.get("visual_timeline", "")))
	_check("recording started after edits captures current visual context and history",
		flight.recorder.recording and flight.recorder.trace.row_count() == 1
		and typeof(started_context) == TYPE_DICTIONARY
		and normalized_started_config == second_config
		and Timeline.validate(started_timeline).ok
		and Timeline.evaluate(started_timeline, sim.tick).config == second_config,
		"context=%s timeline=%s" % [str(started_context), str(started_timeline)])
	var csv_path: String = "user://test-time-of-day-edit.csv"
	var save_error: Error = flight.recorder.stop(csv_path)
	var saved_csv: String = FileAccess.get_file_as_string(csv_path) if FileAccess.file_exists(csv_path) else ""
	var csv_timeline_text: String = _metadata_value(saved_csv, "visual_timeline")
	var csv_timeline: Variant = JSON.parse_string(csv_timeline_text)
	_check("CSV save retains reconstructable visual context and timeline", save_error == OK
		and saved_csv.contains("# visual_context: ")
		and Timeline.validate(csv_timeline).ok
		and csv_timeline.events.size() == 2
		and Timeline.evaluate(csv_timeline, sim.tick).config == second_config)
	if FileAccess.file_exists(csv_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(csv_path))

	flight.recorder.start(flight._trace_meta())
	var stops_before_restart: int = flight.recorder.stops
	flight.session.reset()
	_check("restart keeps the selected config and starts a clean visual timeline",
		sim.tick == 0 and flight.lighting_config == second_config
		and flight._visual_timeline.anchor_tick == 0
		and flight._visual_timeline.initial.config == second_config
		and flight._visual_timeline.events.is_empty())
	_check("restart closes the old active recording", not flight.recorder.recording
		and flight.recorder.stops == stops_before_restart + 1)

	flight.recorder.detach()
	await _release_engine_audio(flight)
	flight.free()
	await process_frame
	for condition: String in ["steady", "turbulent", "hot-high"]:
		await _check_weather_csv_case(condition, condition)
	await _check_weather_csv_case("p51-coupled", "", "p51d-mustang-120", {"shaft-integrator": "coupled-rk4"})
	print("TOD-08b Main lighting edit: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _astronomical_config(local_seconds: int, location_name: String) -> Dictionary:
	var config: Dictionary = Config.defaults()
	config.mode = "astronomical"
	config.date = "2026-06-21"
	config.local_seconds = local_seconds
	config.latitude_deg = 40.7128
	config.longitude_deg = -74.006
	config.location_name = location_name
	return Config.validate(config).config


func _observed(flight: TestFlight) -> Dictionary:
	var radio: RefCounted = flight.session.radio
	return {
		physics = var_to_bytes(flight.session.checkpoint()),
		config = var_to_bytes(flight.lighting_config),
		lighting = var_to_bytes(flight._lighting),
		timeline = var_to_bytes(flight._visual_timeline),
		context_status = flight._visual_context_status,
		tick = flight.session.sim.tick,
		paused = flight.session.sim.paused,
		input = var_to_bytes(_input_snapshot(flight)),
		prop_phase = var_to_bytes(flight._prop_angle),
		prop_rotation = var_to_bytes(flight._airplane.propeller.rotation),
		field_id = flight.get_node("Field").get_instance_id(),
		sun_id = flight._sun.get_instance_id(),
		environment_id = flight._env.get_instance_id(),
		clock = ShaderClock.last_clock,
		wind = ShaderClock.last_wind,
		clouds = Atmosphere.last_cloud_offset,
		note = flight._note,
		recording = flight.recorder.recording,
		recorder_stops = flight.recorder.stops,
		recorder_meta = var_to_bytes(flight.recorder.trace.meta),
		recorder_rows = flight.recorder.trace.row_count(),
		recorder_samples = _sample_rows(flight.recorder.trace.to_csv()),
		recorder_note = flight.recorder.note,
		radio_connected = radio.connected,
	}


func _input_snapshot(flight: TestFlight) -> Dictionary:
	var session: Node = flight.session
	var radio: RefCounted = session.radio
	return {
		input_enabled = session.input_enabled,
		pause_reason = session.pause_reason,
		holds = var_to_bytes(session.holds),
		commands = var_to_bytes(session.commands),
		raw = var_to_bytes(session.raw),
		radio_connected = radio.connected,
		radio_device_id = radio.device_id,
		radio_device_key = radio.device_key,
		radio_device_name = radio.device_name,
		radio_profile_source = radio.profile_source,
		radio_profile = var_to_bytes(radio.profile),
		radio_axes = var_to_bytes(radio.axes),
		radio_armed = radio.armed,
	}


func _sample_rows(csv: String) -> String:
	var lines: PackedStringArray = csv.split("\n", false)
	var rows: PackedStringArray = []
	var reading_rows: bool = false
	for line: String in lines:
		if not reading_rows:
			if line.begins_with("tick,"):
				reading_rows = true
			continue
		rows.append(line)
	return "\n".join(rows)


func _metadata_value(csv: String, key: String) -> String:
	var prefix: String = "# %s: " % key
	for line: String in csv.split("\n", false):
		if line.begins_with(prefix):
			return line.trim_prefix(prefix)
	return ""


func _physical_headers(csv: String) -> String:
	var physical: PackedStringArray = []
	for line: String in csv.split("\n", false):
		if line.begins_with("# ") and not line.begins_with("# visual_context: ") \
				and not line.begins_with("# visual_timeline: "):
			physical.append(line)
	return "\n".join(physical)


func _check_weather_csv_case(case_id: String, weather_id: String, aircraft: String = "jensen-das-ugly-stik-60",
		launch_args: Dictionary = {}) -> void:
	var flight: TestFlight = TestFlight.new()
	flight.interactive_start = true
	flight.aircraft_id = aircraft
	flight.requested_args = launch_args.duplicate(true)
	if not weather_id.is_empty():
		flight.weather_config = WeatherConfig.preset(weather_id)
	root.add_child(flight)
	await process_frame
	if flight.session == null or not flight.startup_error.is_empty():
		_check("%s production flight starts" % case_id, false, flight.startup_error)
		flight.free()
		await process_frame
		return

	flight.set_process(false)
	flight.set_physics_process(false)
	flight.session.set_process(false)
	flight.session.set_physics_process(false)
	flight.session.sim.process_mode = Node.PROCESS_MODE_DISABLED
	flight.session.input_enabled = false
	flight.recorder.detach()
	flight.recorder = MemoryRecorder.new(flight.session.sim)
	var sim: Node = flight.session.sim
	flight.recorder.start(flight._trace_meta())
	var first_row_count: int = flight.recorder.trace.row_count()
	sim.step()
	sim.set_paused(true)
	var trace_meta_before: Dictionary = flight.recorder.trace.meta.duplicate(true)
	var physics_before: PackedByteArray = var_to_bytes(flight.session.checkpoint())
	var rows_before: int = flight.recorder.trace.row_count()
	var samples_before: String = _sample_rows(flight.recorder.trace.to_csv())
	var headers_before: String = _physical_headers(flight.recorder.trace.to_csv())
	var columns_before: Array = flight.recorder.trace.columns()
	var edit_config: Dictionary = _astronomical_config(64800, "%s visual edit" % case_id)
	var edit: Dictionary = flight.apply_lighting_config(edit_config)
	var edited_csv: String = flight.recorder.trace.to_csv()
	var edited_timeline: Variant = JSON.parse_string(_metadata_value(edited_csv, "visual_timeline"))
	var edited_context: Variant = JSON.parse_string(_metadata_value(edited_csv, "visual_context"))
	var physical_meta_after: Dictionary = flight.recorder.trace.meta.duplicate(true)
	physical_meta_after.erase("visual_context")
	physical_meta_after.erase("visual_timeline")
	_check("%s trace starts with its first row before editing" % case_id, first_row_count == 1 and rows_before == 2)
	if not weather_id.is_empty():
		var parsed_weather: Variant = JSON.parse_string(str(trace_meta_before.get("weather_config", "")))
		_check("%s recorder owns the selected physical weather" % case_id,
			typeof(parsed_weather) == TYPE_DICTIONARY and parsed_weather.format == WeatherConfig.preset(weather_id).format)
	else:
		_check("%s coupled P-51 recorder owns shaft metadata" % case_id,
			trace_meta_before.get("propulsion_model") == "propeller-shaft-coupled-rk4-v1"
			and trace_meta_before.get("shaft_integrator") == "coupled-rk4")
	_check("%s paused edit stays in the original live recording" % case_id,
		edit.ok and edit.changed and flight.recorder.recording
		and flight.recorder.trace.row_count() == rows_before
		and var_to_bytes(flight.session.checkpoint()) == physics_before)
	_check("%s CSV overlays reconstructable visual metadata" % case_id,
		Timeline.validate(edited_timeline).ok and Timeline.evaluate(edited_timeline, sim.tick).config == edit_config
		and typeof(edited_context) == TYPE_DICTIONARY
		and Config.validate(edited_context.get("config", {})).config == Config.defaults())
	_check("%s physical headers and every recorded sample stay unchanged" % case_id,
		_physical_headers(edited_csv) == headers_before
		and _sample_rows(edited_csv) == samples_before
		and physical_meta_after == trace_meta_before)
	_check("%s trace keeps its physical columns" % case_id, flight.recorder.trace.columns() == columns_before)
	var output_path: String = "user://test-time-of-day-edit-%s.csv" % case_id
	var save_error: Error = flight.recorder.stop(output_path)
	var saved_csv: String = FileAccess.get_file_as_string(output_path) if FileAccess.file_exists(output_path) else ""
	var saved_timeline: Variant = JSON.parse_string(_metadata_value(saved_csv, "visual_timeline"))
	_check("%s saved CSV preserves visual history, physical headers and samples" % case_id,
		save_error == OK and saved_csv == edited_csv
		and Timeline.validate(saved_timeline).ok
		and Timeline.evaluate(saved_timeline, sim.tick).config == edit_config
		and _physical_headers(saved_csv) == headers_before
		and _sample_rows(saved_csv) == samples_before)
	if FileAccess.file_exists(output_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(output_path))
	flight.recorder.detach()
	await _release_engine_audio(flight)
	flight.free()
	await process_frame


func _release_engine_audio(flight: TestFlight) -> void:
	if flight._soundscape_audio != null:
		# The inspection alias now belongs to the complete scene-local soundscape.
		flight._soundscape_audio.free()
		flight._soundscape_audio = null
		flight._engine_audio = null
		await create_timer(0.2).timeout
		return
	if flight._engine_audio == null:
		return
	var player: AudioStreamPlayer3D = flight._engine_audio
	player.stop()
	player.stream = null
	player.queue_free()
	flight._engine_audio = null
	await create_timer(0.2).timeout


func _check(label: String, valid: bool, detail: String = "") -> void:
	_checks += 1
	if not valid:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
