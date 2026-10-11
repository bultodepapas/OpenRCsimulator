## TOD-02 integration seam: an interactive flight owns a fixed copied selection.
extends SceneTree

const Main = preload("res://main.gd")
const Config = preload("res://environment/time_of_day_config.gd")

var _checks: int = 0
var _failures: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var input_config: Dictionary = Config.defaults()
	input_config["mode"] = "astronomical"
	input_config["date"] = "2024-06-21"
	input_config["local_seconds"] = 43200
	input_config["utc_offset_minutes"] = -360
	input_config["latitude_deg"] = 40.0
	input_config["longitude_deg"] = -105.0
	input_config["location_name"] = "Session test field (synthetic)"
	var flight: Main = Main.new()
	flight.interactive_start = true
	flight.lighting_config = input_config
	root.add_child(flight)
	await process_frame
	_check("actual Main starts a valid interactive flight", flight.session != null and flight.session.is_flyable(), flight.startup_error)
	_check("Main keeps the selected complete lighting config", flight.lighting_config == input_config)
	_check("Main builds astronomical solar snapshot before flight", flight._lighting.has("solar")
		and float(flight._lighting.solar.elevation_deg) > 0.0)
	var selected_seconds: int = int(flight.lighting_config["local_seconds"])
	var selected_solar: PackedByteArray = var_to_bytes(flight._lighting.solar)
	input_config["local_seconds"] = 0
	input_config["latitude_deg"] = -90.0
	_check("Main owns a copy of the incoming dictionary", flight.lighting_config.local_seconds == selected_seconds
		and flight.lighting_config.latitude_deg == 40.0
		and var_to_bytes(flight._lighting.solar) == selected_solar)

	for _frame: int in 3:
		await physics_frame
	var running_tick: int = int(flight.session.sim.tick)
	_check("flight sim time advances independently of the fixed light", running_tick > 0
		and var_to_bytes(flight._lighting.solar) == selected_solar)
	flight.session.sim.set_paused(true)
	var paused_tick: int = int(flight.session.sim.tick)
	for _frame: int in 3:
		await physics_frame
	_check("pause freezes simulation time and leaves selected light fixed",
			int(flight.session.sim.tick) == paused_tick
			and var_to_bytes(flight._lighting.solar) == selected_solar)

	flight._unhandled_input(_key_event(KEY_R))
	_check("R restart resets the flight without changing selected light",
		int(flight.session.sim.tick) == 0 and flight.lighting_config.local_seconds == selected_seconds
		and var_to_bytes(flight._lighting.solar) == selected_solar)

	flight._unhandled_input(_key_event(KEY_T))
	var recorder: RefCounted = flight.recorder
	var recorded_context: String = str(recorder.trace.meta.get("visual_context", ""))
	var parsed_context: Variant = JSON.parse_string(recorded_context)
	_check("T recording starts with a self-contained visual context",
		recorder.recording and typeof(parsed_context) == TYPE_DICTIONARY
		and parsed_context.get("config", {}).get("local_seconds", -1) == selected_seconds,
		recorded_context)
	flight.lighting_config["local_seconds"] = 0
	var current_context: String = str(flight._trace_meta().get("visual_context", ""))
	_check("Recorder keeps the context frozen after its T start seam",
		recorded_context != current_context
		and str(recorder.trace.meta.get("visual_context", "")) == recorded_context)
	recorder.recording = false
	recorder.detach()
	recorder = null
	flight.set_process(false)
	flight.session.sim.set_paused(true)
	if flight._engine_audio != null and flight._engine_audio.playing:
		flight._engine_audio.stop()
	if flight._engine_audio != null:
		flight._engine_audio.stream = null
	await create_timer(0.2).timeout
	flight.free()
	flight = null
	await process_frame
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _key_event(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event
