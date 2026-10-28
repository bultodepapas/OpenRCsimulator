## UI-34c: compare the actual synchronous and overlapping Main launch paths at tick zero.
## Both paths keep Main disabled while it builds, so no simulation tick or live input can intervene.
extends SceneTree

const Main := preload("res://main.gd")
const Flight := preload("res://sim/flight_session.gd")
const Weather := preload("res://physics/wind_config.gd")
const AIRCRAFT_ID := "stik-glow-61fx-2t"
const FUEL_FILL := 0.5
const TIMEOUT_MSEC := 120000

var _checks := 0
var _failures := 0
var _stages: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok   ", label)


## A real yielding checkpoint exercises the same staged world path used by interactive Home.
func _loading_checkpoint(stage: String) -> bool:
	_stages.append(stage)
	await process_frame
	return true


func _wait_for_trim_drain() -> bool:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while Flight.menu_trim_busy() and Time.get_ticks_msec() < deadline:
		Flight.poll_menu_trim()
		await process_frame
	return not Flight.menu_trim_busy()


func _silence_audio(node: Node) -> void:
	if node is AudioStreamPlayer3D:
		var player_3d := node as AudioStreamPlayer3D
		player_3d.stop()
		player_3d.stream = null
	elif node is AudioStreamPlayer2D:
		var player_2d := node as AudioStreamPlayer2D
		player_2d.stop()
		player_2d.stream = null
	elif node is AudioStreamPlayer:
		var player := node as AudioStreamPlayer
		player.stop()
		player.stream = null
	for child: Node in node.get_children():
		_silence_audio(child)


func _close(flight: Node) -> void:
	if is_instance_valid(flight):
		if flight.recorder != null:
			flight.recorder.detach()
			flight.recorder = null
		_silence_audio(flight)
		var drain_until: int = Time.get_ticks_usec() + 50000
		while Time.get_ticks_usec() < drain_until:
			await process_frame
		flight.free()
	await process_frame


func _launch(start_choice: String, overlap: bool, expected_weather: Dictionary) -> Dictionary:
	var label := "%s %s" % [start_choice, "overlap" if overlap else "synchronous"]
	if not await _wait_for_trim_drain():
		_check(label + " has no prior trim worker", false)
		return {ok = false}
	Flight._launch_trim_cache.clear()
	_stages.clear()
	var flight: Node = Main.new()
	flight.process_mode = Node.PROCESS_MODE_DISABLED
	flight.interactive_start = true
	flight.external_controller_selection = true
	flight.aircraft_id = AIRCRAFT_ID
	flight.start_choice = start_choice
	flight.trim_throttle = Flight.CRUISE_TRIM_THROTTLE
	flight.fuel_start_fill = FUEL_FILL
	flight.weather_config = expected_weather.duplicate(true)
	flight.crash_effects_enabled = false
	flight.accident_reports_enabled = false
	flight.set_user_args(PackedStringArray([
		"--physics-backend=gdscript_reference", "--soundscape=off", "--smoke=off",
		"--crash-effects=off", "--accident-report=off", "--scenery_audio=off",
	]))
	if overlap:
		flight.startup_checkpoint = _loading_checkpoint
		flight.startup_cancel_requested = func() -> bool: return false
	root.add_child(flight)
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while is_instance_valid(flight) and not flight.startup_complete and Time.get_ticks_msec() < deadline:
		await process_frame
	var session: Node = flight.session if is_instance_valid(flight) else null
	var ready: bool = is_instance_valid(flight) and flight.startup_complete and flight.startup_error.is_empty() \
		and is_instance_valid(session) and session.is_flyable()
	_check(label + " completes a valid Main launch", ready,
		str(flight.startup_error if is_instance_valid(flight) else "Main was destroyed"))
	if not ready:
		await _close(flight)
		await _wait_for_trim_drain()
		return {ok = false}
	var checkpoint: Dictionary = session.checkpoint()
	var mass: Dictionary = session.mass_properties()
	var metrics: Dictionary = flight.startup_preparation_metrics
	var expected_fuel: float = session.start_fuel_kg()
	var fixture_ok: bool = int(session.sim.tick) == 0 and not checkpoint.is_empty() \
		and session.finite_fuel_is_active() and session.fuel_start_fill == FUEL_FILL \
		and bool(mass.get("ok", false)) and is_equal_approx(float(mass.get("fuel_remaining_kg", -1.0)), expected_fuel) \
		and checkpoint.get("fuel_session", {}).get("start_fill", NAN) == FUEL_FILL \
		and checkpoint.get("weather_config", {}) == expected_weather \
		and not session.weather_is_calm() and session.weather_configuration() == expected_weather \
		and session.soft_hull_contacts and session.start_choice == start_choice \
		and session.stage_backend_identity().backend == "gdscript_reference"
	_check(label + " retains the nondefault weather/fuel at tick zero", fixture_ok,
		"tick=%s fill=%s weather=%s start=%s" % [session.sim.tick, session.fuel_start_fill,
			str(session.weather_configuration()), session.start_choice])
	var exercised: bool = bool(metrics.get("overlapped", false)) == overlap
	if overlap:
		exercised = exercised and int(metrics.get("workers_after", 0)) - int(metrics.get("workers_before", 0)) == 1 \
			and "Preparing aircraft" in _stages and "Checking flight" in _stages \
			and flight._preparing_session == null
	else:
		exercised = exercised and int(metrics.get("workers_after", -1)) == 0
	_check(label + " exercises the intended setup path", exercised, str(metrics))
	var result := {ok = fixture_ok and exercised, checkpoint = var_to_bytes(checkpoint),
		start = var_to_bytes(session.start), aircraft = var_to_bytes(session.aircraft.input_identity)}
	await _close(flight)
	return result


func _run() -> void:
	var weather: Dictionary = Weather.validate(Weather.GENTLE_PRACTICE)
	_check("fixed non-calm weather fixture validates", bool(weather.get("ok", false)))
	if not weather.get("ok", false):
		quit(1)
		return
	for start_choice: String in [Flight.START_AIRBORNE, Flight.START_RUNWAY]:
		var synchronous: Dictionary = await _launch(start_choice, false, weather.config)
		var overlapping: Dictionary = await _launch(start_choice, true, weather.config)
		var comparable: bool = bool(synchronous.get("ok", false)) and bool(overlapping.get("ok", false))
		_check(start_choice + " complete checkpoint matches synchronous Main byte for byte", comparable \
			and synchronous.get("checkpoint", PackedByteArray()) == overlapping.get("checkpoint", PackedByteArray()))
		_check(start_choice + " start and aircraft identity match synchronous Main byte for byte", comparable \
			and synchronous.get("start", PackedByteArray()) == overlapping.get("start", PackedByteArray()) \
			and synchronous.get("aircraft", PackedByteArray()) == overlapping.get("aircraft", PackedByteArray()))
	var drained: bool = await _wait_for_trim_drain()
	_check("no trim worker survives the comparison", drained)
	Flight._launch_trim_cache.clear()
	print("Main startup overlap: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
