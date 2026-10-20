## AUD-15 presentation bench for the installed engine and ground-contact sound routes.
## It stages fixed snapshots; it is not a flight, physics replay, or acoustic validation.
## Usage: godot --headless --audio-driver WASAPI --path app --script ../tools/audio/contact_mix_probe.gd -- --out=<absolute-mix.json>
extends SceneTree

const SoundscapeScript := preload("res://audio/soundscape.gd")
const GroundAudioScript := preload("res://audio/ground_audio.gd")
const PowertrainAudioScript := preload("res://audio/powertrain_audio.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const RotorcraftData := preload("res://physics/rotorcraft_data.gd")

const PROFILE_IDS: Array[String] = [
	"stik-glow-61fx-2t",
	"stik-glow-fs64v-4t",
	"p51d-mustang-120",
	"turbo-lumber-evolution",
	"sebart-avanti-s-a200-p100rx",
	"xcell-60-research",
]
const LISTENER := Vector3(0.0, 2.0, 0.0)
const ROLL_SPEED_MPS := 8.0
const CONTACT_FORCE_N := 20.0
const CONTACT_REFERENCE_N := 40.0
const TICK_RATE_HZ := 240.0
const SILENCE_DBFS := -240.0
const CAPTURE_RING_SECONDS := 2.0
const STEADY_SETTLE_SECONDS := 0.5
const CAPTURE_DURATION_TOLERANCE_SECONDS := 0.12
const PAUSE_FADE_AND_BUFFER_SECONDS := 0.18

var _output_path: String = ""
var _wall_start_usec: int = 0
var _elapsed_s: float = 0.0
var _tick: int = 0
var _profile_results: Array[Dictionary] = []
var _global_peak: float = 0.0
var _total_frames: int = 0
var _profile_failures: Array[String] = []


func _initialize() -> void:
	Engine.max_fps = 60
	_parse_args()
	_run.call_deferred()


func _parse_args() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_output_path = argument.trim_prefix("--out=")
	if _output_path.is_empty():
		_output_path = ProjectSettings.globalize_path("res://../docs/research/audio/AUD-15/mix.json")


func _run() -> void:
	if not _output_path.is_absolute_path():
		printerr("--out must be an absolute JSON path")
		quit(2)
		return
	var output_directory: String = _output_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(output_directory):
		var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(output_directory)
		if mkdir_error != OK:
			printerr("Could not create mix report directory: ", output_directory)
			quit(2)
			return
	if PROFILE_IDS.size() != 6:
		printerr("The presentation bench must cover its six installed engine families")
		quit(2)
		return

	root.audio_listener_enable_3d = true
	_wall_start_usec = Time.get_ticks_usec()
	for aircraft_id: String in PROFILE_IDS:
		var profile_result: Dictionary = await _run_profile(aircraft_id)
		if not bool(profile_result.get("ok", false)):
			_profile_failures.append("%s: %s" % [aircraft_id, str(profile_result.get("error", "profile setup failed"))])
		else:
			profile_result.erase("ok")
			_profile_results.append(profile_result)

	var report: Dictionary = _build_report()
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write mix report: ", _output_path)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("AUD-15 contact mix presentation bench: ", _output_path)
	print("driver=", AudioServer.get_driver_name(), " profiles=", _profile_results.size(),
		" captured_frames=", _total_frames, " checks=", report.get("checks", {}).get("summary", "not evaluated"))
	quit(1 if bool(report.get("checks", {}).get("has_failures", false)) else 0)


func _run_profile(aircraft_id: String) -> Dictionary:
	var catalog_entry: Dictionary = Catalog.entry(aircraft_id)
	if catalog_entry.is_empty():
		return {ok = false, error = "aircraft ID is absent from the catalog"}
	var rotor_skids_only: bool = Catalog.is_rotorcraft(aircraft_id)
	var propulsion: Dictionary = {}
	var profile: Dictionary
	var kind: String
	if rotor_skids_only:
		var rotor_loaded: Dictionary = RotorcraftData.load_file(str(catalog_entry.get("data", "")))
		if not bool(rotor_loaded.get("ok", false)):
			return {ok = false, error = "catalog rotorcraft data refused: " + "; ".join(rotor_loaded.get("errors", PackedStringArray()))}
		var rotor_context: Dictionary = rotor_loaded.get("context", {})
		var drive_model: Dictionary = rotor_context.get("drive_model", {})
		profile = PowertrainAudioScript.profile_for(aircraft_id, {})
		profile["max_rpm"] = float(drive_model.get("governor_target_main_rad_s", 0.0)) * 60.0 / TAU
		kind = "electric_prop"
	else:
		var loaded: Dictionary = AircraftData.load_file(str(catalog_entry.get("data", "")))
		if not bool(loaded.get("ok", false)):
			return {ok = false, error = "catalog data refused: " + "; ".join(loaded.get("errors", PackedStringArray()))}
		var aircraft_model: Dictionary = loaded.get("model", {})
		propulsion = aircraft_model.get("propulsion", {})
		profile = PowertrainAudioScript.profile_for(aircraft_id, propulsion)
		kind = str(propulsion.get("kind", "glow_prop"))
	var family: String = str(profile.get("family", ""))
	if family.is_empty():
		return {ok = false, error = "production profile_for returned no family"}

	var rig := Node3D.new()
	rig.name = "ContactMixBench_" + aircraft_id
	root.add_child(rig)
	var camera := Camera3D.new()
	camera.name = "BenchListenerCamera"
	camera.position = LISTENER
	rig.add_child(camera)
	var listener := AudioListener3D.new()
	camera.add_child(listener)
	camera.make_current()
	listener.make_current()
	var soundscape := SoundscapeScript.new()
	soundscape.name = "ProductionSoundscape"
	rig.add_child(soundscape)
	await process_frame
	var glow_family: String = family if family in ["glow_2t", "glow_4t"] else ""
	soundscape.configure({"pilot": {"east": 0.0, "north": 0.0, "down": 0.0}, "objects": [], "flight_cues": []},
		kind, 4102026, glow_family, profile)
	var bus_names: Array = soundscape.get("_bus_names")
	if bus_names.size() < 3:
		await _cleanup_profile(rig, soundscape, null, &"", {})
		return {ok = false, error = "production Soundscape did not create aircraft/output buses"}
	var output_bus: StringName = StringName(soundscape.call("output_bus"))
	var engine_bus: StringName = StringName(bus_names[1])
	var ground_bus: StringName = StringName("Ground Contact Probe %d" % soundscape.get_instance_id())
	var ground_bus_index: int = _add_child_bus(ground_bus, output_bus)
	if ground_bus_index < 0:
		await _cleanup_profile(rig, soundscape, null, &"", {})
		return {ok = false, error = "could not create dedicated ground child bus"}

	var captures: Dictionary = {
		"engine": _add_capture(engine_bus),
		"ground": _add_capture(ground_bus),
		"sum_pre_master": _add_capture(output_bus),
	}
	for name: String in captures:
		if captures[name] == null:
			await _cleanup_profile(rig, soundscape, null, ground_bus, captures)
			return {ok = false, error = "could not capture %s bus" % name}

	var ground_audio := GroundAudioScript.new()
	ground_audio.name = "ProductionGroundAudio"
	ground_audio.configure(rig, ground_bus)
	ground_audio.bind_soundscape(soundscape)
	ground_audio.rebind(ground_bus)
	soundscape.gain = 1.0
	_tick = 0
	var stages: Array[Dictionary] = []
	for stage_name: String in ["engine_off_roll", "idle_roll", "full_power_roll", "stationary_idle",
			"touchdown_idle", "airborne_release", "pause_resume"]:
		var result: Dictionary = await _run_stage(stage_name, aircraft_id, profile, family, kind,
			rotor_skids_only, soundscape, ground_audio, ground_bus, captures)
		stages.append(result)
	var checks: Dictionary = _profile_checks(stages, rotor_skids_only)
	var surface_distances: Array[float] = []
	for contact: Dictionary in _contacts(rotor_skids_only, true, ROLL_SPEED_MPS, 0.0):
		var contact_position: Vector3 = contact["position"]
		surface_distances.append(contact_position.distance_to(LISTENER))
	var result: Dictionary = {
		ok = true,
		aircraft_id = aircraft_id,
		catalog_data = str(catalog_entry.get("data", "")),
		vehicle = "rotorcraft" if rotor_skids_only else "airplane",
		powertrain_profile = profile,
		propulsion_kind = kind,
		engine_audio = "production glow voice" if glow_family != "" else "production recorded powertrain bank",
		contact_audio = "skids, touchdown only" if rotor_skids_only else "three staged wheels",
		contact_distance_m = surface_distances,
		roll_speed_mps = ROLL_SPEED_MPS,
		contact_force_n_each = CONTACT_FORCE_N,
		contact_reference_load_n_each = CONTACT_REFERENCE_N,
		stages = stages,
		checks = checks,
		touchdown_events = int(stages[4].get("touchdown_events", 0)),
	}
	await _cleanup_profile(rig, soundscape, ground_audio, ground_bus, captures)
	return result


func _run_stage(stage_name: String, aircraft_id: String, profile: Dictionary, family: String, kind: String,
		rotor_skids_only: bool, soundscape: Node, ground_audio: Node, ground_bus: StringName,
		captures: Dictionary) -> Dictionary:
	var duration: float = _stage_duration(stage_name)
	if stage_name in ["stationary_idle", "touchdown_idle", "airborne_release", "pause_resume"]:
		ground_audio.reset()
	await _flush_captures(captures)
	var stage_start_usec: int = Time.get_ticks_usec()
	var previous_usec: int = stage_start_usec
	var metrics: Dictionary = {name = stage_name, requested_seconds = duration,
		buses = _new_bus_meters(), settled_buses = _new_bus_meters(), phases = {}, touchdown_events = 0,
		settled_window_start_seconds = _settle_after(stage_name)}
	var discarded_before: Dictionary = {}
	for bus_key: String in captures:
		discarded_before[bus_key] = int((captures[bus_key] as AudioEffectCapture).get_discarded_frames())
	var touchdown_before: int = int(ground_audio.get("touchdown_events"))
	while true:
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		var elapsed: float = float(now_usec - stage_start_usec) / 1000000.0
		if elapsed >= duration:
			_collect_captures(metrics, captures, "", false)
			break
		var dt: float = clampf(float(now_usec - previous_usec) / 1000000.0, 0.0, 0.1)
		if dt <= 0.0:
			dt = 1.0 / 60.0
		previous_usec = now_usec
		_elapsed_s = float(now_usec - _wall_start_usec) / 1000000.0
		var frame_state: Dictionary = _stage_state(stage_name, elapsed, profile, family, rotor_skids_only)
		var snapshot: Dictionary = _sound_snapshot(profile, family, kind, frame_state, _elapsed_s)
		soundscape.update_sound(snapshot, dt)
		var contacts: Array[Dictionary] = _contacts(rotor_skids_only,
			bool(frame_state.get("grounded", false)), float(frame_state.get("rolling_speed_mps", 0.0)),
			float(frame_state.get("approach_speed_mps", 0.0)))
		var engine_power: float = float(frame_state.get("throttle", 0.0)) if bool(frame_state.get("running", false)) else 0.0
		_tick += maxi(1, roundi(dt * TICK_RATE_HZ))
		ground_audio.update_contacts(_tick, bool(frame_state.get("paused", false)), contacts,
			engine_power, dt, LISTENER, TICK_RATE_HZ)
		_route_ground_players(ground_audio, ground_bus)
		if stage_name == "touchdown_idle" and elapsed >= 0.22 and int(ground_audio.get("touchdown_events")) > touchdown_before:
			metrics["touchdown_events"] = int(ground_audio.get("touchdown_events")) - touchdown_before
		var phase_name: String = str(frame_state.get("phase", "steady"))
		var phase_record: String = phase_name if _phase_is_settled(stage_name, elapsed) else ""
		_collect_captures(metrics, captures, phase_record, elapsed >= _settle_after(stage_name))
	var actual_usec: int = Time.get_ticks_usec() - stage_start_usec
	metrics["actual_seconds"] = float(actual_usec) / 1000000.0
	metrics["touchdown_events"] = int(ground_audio.get("touchdown_events")) - touchdown_before
	for bus_key: String in captures:
		_finalize_meter(metrics["buses"][bus_key])
		_finalize_meter(metrics["settled_buses"][bus_key])
		for phase_name: String in metrics["phases"]:
			_finalize_meter(metrics["phases"][phase_name][bus_key])
		metrics["buses"][bus_key]["discarded_frames"] = maxi(0,
			int((captures[bus_key] as AudioEffectCapture).get_discarded_frames()) - int(discarded_before[bus_key]))
		metrics["buses"][bus_key]["captured_to_wall_ratio"] = float(metrics["buses"][bus_key]["captured_seconds"]) / maxf(float(metrics["actual_seconds"]), 1e-6)
	return metrics


func _collect_captures(metrics: Dictionary, captures: Dictionary, phase_name: String, settled: bool) -> void:
	for bus_key: String in captures:
		var capture: AudioEffectCapture = captures[bus_key]
		var available: int = capture.get_frames_available()
		if available <= 0:
			continue
		var samples: PackedVector2Array = capture.get_buffer(available)
		_measure_buffer(metrics["buses"][bus_key], samples)
		if settled:
			_measure_buffer(metrics["settled_buses"][bus_key], samples)
		if not phase_name.is_empty():
			if not metrics["phases"].has(phase_name):
				metrics["phases"][phase_name] = _new_bus_meters()
			_measure_buffer(metrics["phases"][phase_name][bus_key], samples)
		_total_frames += samples.size()
		_global_peak = maxf(_global_peak, float(metrics["buses"][bus_key]["peak"]))


func _flush_captures(captures: Dictionary) -> void:
	# Drain old route buffers before timing the next stage, then flush one mixer block.
	for bus_key: String in captures:
		var capture: AudioEffectCapture = captures[bus_key]
		var available: int = capture.get_frames_available()
		if available > 0:
			capture.get_buffer(available)
	await process_frame
	for bus_key: String in captures:
		var capture: AudioEffectCapture = captures[bus_key]
		var available: int = capture.get_frames_available()
		if available > 0:
			capture.get_buffer(available)


func _stage_state(stage_name: String, elapsed: float, profile: Dictionary, family: String,
		rotor_skids_only: bool) -> Dictionary:
	var max_rpm: float = maxf(float(profile.get("max_rpm", 12000.0)), 1.0)
	var idle_fraction: float = 0.34 if family == "turbine" else (0.38 if family in ["electric", "rotor"] else 0.28)
	var state: Dictionary = {rpm = max_rpm * idle_fraction, running = true, throttle = 0.16, load = 0.16,
		grounded = true, rolling_speed_mps = ROLL_SPEED_MPS, approach_speed_mps = 0.0, paused = false, phase = "roll"}
	match stage_name:
		"engine_off_roll":
			state.merge({rpm = 0.0, running = false, throttle = 0.0, load = 0.0}, true)
		"idle_roll":
			pass
		"full_power_roll":
			state.merge({rpm = max_rpm * 0.91, running = true, throttle = 1.0, load = 0.88}, true)
		"stationary_idle":
			state["rolling_speed_mps"] = 0.0
			state["phase"] = "stationary"
		"touchdown_idle":
			if elapsed < 0.24:
				state.merge({grounded = false, rolling_speed_mps = 0.0, approach_speed_mps = 2.4, phase = "airborne_approach"}, true)
			else:
				state.merge({grounded = true, rolling_speed_mps = ROLL_SPEED_MPS, approach_speed_mps = 0.0, phase = "touchdown"}, true)
		"airborne_release":
			if elapsed < 0.22:
				state["phase"] = "loaded_roll"
			elif elapsed < 0.40:
				state.merge({grounded = false, rolling_speed_mps = 0.0, phase = "airborne_transition"}, true)
			else:
				state.merge({grounded = false, rolling_speed_mps = 0.0, phase = "airborne_silence"}, true)
		"pause_resume":
			if elapsed >= 0.75 and elapsed < 0.75 + PAUSE_FADE_AND_BUFFER_SECONDS:
				state.merge({paused = true, phase = "pause_transition"}, true)
			elif elapsed >= 0.75 + PAUSE_FADE_AND_BUFFER_SECONDS and elapsed < 1.35:
				state.merge({paused = true, phase = "pause_quiet"}, true)
			elif elapsed >= 1.35 and elapsed < 1.35 + PAUSE_FADE_AND_BUFFER_SECONDS:
				state.merge({phase = "resume_transition"}, true)
			elif elapsed >= 1.35 + PAUSE_FADE_AND_BUFFER_SECONDS:
				state["phase"] = "resumed_roll"
			else:
				state["phase"] = "loaded_roll"
	if rotor_skids_only:
		state["rolling_speed_mps"] = 0.0
	return state


func _sound_snapshot(profile: Dictionary, family: String, kind: String, state: Dictionary, time_s: float) -> Dictionary:
	var rpm: float = float(state.get("rpm", 0.0))
	var max_rpm: float = float(profile.get("max_rpm", 12000.0))
	var running: bool = bool(state.get("running", false))
	var throttle: float = float(state.get("throttle", 0.0))
	var load: float = float(state.get("load", 0.0))
	var glow: Dictionary = {
		"family": family, "rpm": rpm, "max_rpm": max_rpm, "running": running,
		"firing_fraction": 1.0 if running else 0.0, "load": load, "throttle": throttle,
		"blade_count": int(profile.get("blades", 2)), "sample_tick": _tick,
	}
	return {
		"rpm": rpm, "max_rpm": max_rpm, "running": running, "load": load, "throttle": throttle,
		"blades": int(profile.get("blades", 2)), "airspeed": 0.0, "wind_speed": 0.0,
		"wind_direction": Vector3.RIGHT, "sound_speed": 343.0,
		"source": Vector3(0.0, 0.0, -sqrt(60.0)), "listener": LISTENER,
		"source_velocity": Vector3.ZERO, "paused": bool(state.get("paused", false)),
		"sun_elevation": -90.0, "time": time_s,
		"temperature_c": 15.0, "pressure_pa": 101325.0, "humidity_molar_pct": 1.0,
		"jet_velocity": 0.0, "jet_velocity_max": 1.0, "exhaust_direction": Vector3(0.0, 0.0, -1.0),
		"glow": glow,
	}


func _contacts(rotor_skids_only: bool, grounded: bool, rolling_speed: float, approach_speed: float) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var ids: Array = ["left_main", "right_main", "nose"] if not rotor_skids_only else ["left_skid", "right_skid"]
	var x_values: Array = [-0.45, 0.45, 0.0] if not rotor_skids_only else [-0.35, 0.35]
	for index: int in ids.size():
		var x: float = x_values[index]
		var z: float = -sqrt(64.0 - LISTENER.y * LISTENER.y - x * x)
		var point := Vector3(x, 0.0, z)
		rows.append({
			"id": ids[index], "position": point, "velocity_mps": Vector3(0.0, 0.0, rolling_speed),
			"force_n": CONTACT_FORCE_N if grounded else 0.0,
			"normal_force_n": CONTACT_FORCE_N if grounded else 0.0,
			"reference_load_n": CONTACT_REFERENCE_N,
			"surface_normal": Vector3.UP, "normal_speed_mps": approach_speed,
			"compression_m": 0.018 if grounded else 0.0,
			"approach_speed_mps": approach_speed,
			"rolling_speed_mps": rolling_speed, "rim_speed_mps": rolling_speed,
			"surface": "hard", "grounded": grounded,
			"roll_enabled": not rotor_skids_only,
		})
	return rows


func _stage_duration(stage_name: String) -> float:
	match stage_name:
		"engine_off_roll", "idle_roll", "full_power_roll": return 1.8
		"touchdown_idle": return 0.95
		"airborne_release": return 1.2
		"pause_resume": return 2.0
		"stationary_idle": return 0.8
		_: return 1.0


func _settle_after(stage_name: String) -> float:
	if stage_name in ["engine_off_roll", "idle_roll", "full_power_roll"]:
		return STEADY_SETTLE_SECONDS
	return 0.2


func _phase_is_settled(stage_name: String, elapsed: float) -> bool:
	if stage_name == "pause_resume":
		return elapsed >= 0.75 + PAUSE_FADE_AND_BUFFER_SECONDS or elapsed < 0.75
	if stage_name == "airborne_release":
		return elapsed < 0.22 or elapsed >= 0.22 + PAUSE_FADE_AND_BUFFER_SECONDS
	return true


func _add_child_bus(bus_name: StringName, parent_bus: StringName) -> int:
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, parent_bus)
	AudioServer.set_bus_volume_db(index, 0.0)
	return index


func _add_capture(bus_name: StringName) -> AudioEffectCapture:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return null
	var capture := AudioEffectCapture.new()
	capture.buffer_length = CAPTURE_RING_SECONDS
	AudioServer.add_bus_effect(bus_index, capture)
	return capture


func _route_ground_players(ground_audio: Node, ground_bus: StringName) -> void:
	var slots: Array = ground_audio.get("_slots")
	for slot: Dictionary in slots:
		for player: AudioStreamPlayer3D in slot.get("roll", []):
			player.bus = ground_bus
		var impact: AudioStreamPlayer3D = slot.get("impact") as AudioStreamPlayer3D
		if impact != null:
			impact.bus = ground_bus


func _new_bus_meters() -> Dictionary:
	return {engine = _new_meter(), ground = _new_meter(), sum_pre_master = _new_meter()}


func _new_meter() -> Dictionary:
	return {frames = 0, sum_squares = 0.0, peak = 0.0, over_unity = 0}


func _measure_buffer(meter: Dictionary, samples: PackedVector2Array) -> void:
	for sample: Vector2 in samples:
		var peak: float = maxf(absf(sample.x), absf(sample.y))
		meter["sum_squares"] = float(meter["sum_squares"]) + 0.5 * (sample.x * sample.x + sample.y * sample.y)
		meter["peak"] = maxf(float(meter["peak"]), peak)
		meter["over_unity"] = int(meter["over_unity"]) + (1 if peak >= 1.0 else 0)
		meter["frames"] = int(meter["frames"]) + 1


func _finalize_meter(meter: Dictionary) -> void:
	var frames: int = int(meter["frames"])
	var rms: float = sqrt(float(meter["sum_squares"]) / float(frames)) if frames > 0 else 0.0
	var peak: float = float(meter["peak"])
	meter["rms_linear"] = rms
	meter["rms_dbfs"] = linear_to_db(maxf(rms, 1e-12))
	meter["peak_dbfs"] = linear_to_db(maxf(peak, 1e-12))
	meter["captured_seconds"] = float(frames) / float(AudioServer.get_mix_rate())
	meter["frames"] = frames
	meter.erase("sum_squares")
	meter.erase("peak")


func _profile_checks(stages: Array[Dictionary], rotor_skids_only: bool) -> Dictionary:
	var by_name: Dictionary = {}
	for stage: Dictionary in stages:
		by_name[str(stage.name)] = stage
	var off_ground: float = _stage_rms(by_name, "engine_off_roll", "ground")
	var idle_ground: float = _stage_rms(by_name, "idle_roll", "ground")
	var full_ground: float = _stage_rms(by_name, "full_power_roll", "ground")
	var full_engine: float = _stage_rms(by_name, "full_power_roll", "engine")
	var stationary_ground: float = _stage_rms(by_name, "stationary_idle", "ground")
	var airborne_ground: float = _phase_rms(by_name, "airborne_release", "airborne", "ground")
	var touchdown_events: int = int(by_name.get("touchdown_idle", {}).get("touchdown_events", 0))
	var has_frames: bool = int(by_name.get("full_power_roll", {}).get("buses", {}).get("engine", {}).get("frames", 0)) > 0
	var checks: Dictionary = {}
	checks["engine_exceeds_ground_at_full_power"] = _check_value(full_engine > full_ground, has_frames,
		"engine bus RMS is above the hard-surface roll bus at full power", {engine_rms = full_engine, ground_rms = full_ground})
	checks["roll_gain_rises_at_low_throttle"] = _check_value(off_ground > full_ground and idle_ground > full_ground,
		has_frames and not rotor_skids_only, "same force and 8 m/s wheel roll is louder with engine off/idle than at full power",
		{engine_off_ground_rms = off_ground, idle_ground_rms = idle_ground, full_power_ground_rms = full_ground})
	checks["stationary_contact_has_no_roll"] = _check_value(stationary_ground < maxf(off_ground * 0.12, 1e-7),
		has_frames and not rotor_skids_only, "loaded stationary wheels produce no sustained roll loop",
		{stationary_ground_rms = stationary_ground, moving_off_ground_rms = off_ground})
	checks["airborne_release_fades_roll"] = _check_value(airborne_ground < maxf(off_ground * 0.55, 1e-7), has_frames and not rotor_skids_only,
		"ground roll fades after the staged contact unloads", {airborne_ground_rms = airborne_ground, moving_off_ground_rms = off_ground})
	checks["touchdown_idle_emits_impact"] = _check_value(touchdown_events > 0, has_frames,
		"airborne approach followed by loaded contact emits one impact per contact point", {touchdown_events = touchdown_events})
	var pause_ground: float = _phase_rms(by_name, "pause_resume", "paused", "ground")
	var resume_ground: float = _phase_rms(by_name, "pause_resume", "resumed_roll", "ground")
	checks["pause_resume_fades_and_recovers"] = _check_value(pause_ground < off_ground and resume_ground > pause_ground,
		has_frames and not rotor_skids_only, "pause fades ground audio and resume restores rolling without an impact", {
			paused_ground_rms = pause_ground, resumed_ground_rms = resume_ground,
			resume_touchdown_events = int(by_name.get("pause_resume", {}).get("touchdown_events", 0)),
		})
	var sum_peak: float = -240.0
	for stage: Dictionary in stages:
		sum_peak = maxf(sum_peak, float(stage.get("buses", {}).get("sum_pre_master", {}).get("peak_dbfs", -240.0)))
	checks["pre_master_headroom"] = _check_value(sum_peak < 0.0,
		has_frames, "sum pre-Master peak remains below 0 dBFS", {peak_dbfs = sum_peak})
	return checks


func _check_value(passed: bool, evaluated: bool, message: String, observed: Dictionary) -> Dictionary:
	return {status = ("pass" if passed else "fail") if evaluated else "not_evaluated",
		passed = passed if evaluated else null, message = message, observed = observed}


func _stage_rms(by_name: Dictionary, stage_name: String, bus_key: String) -> float:
	return float(by_name.get(stage_name, {}).get("buses", {}).get(bus_key, {}).get("rms_linear", 0.0))


func _phase_rms(by_name: Dictionary, stage_name: String, phase_name: String, bus_key: String) -> float:
	return float(by_name.get(stage_name, {}).get("phases", {}).get(phase_name, {}).get(bus_key, {}).get("rms_linear", 0.0))


func _build_report() -> Dictionary:
	var all_checks: Array[Dictionary] = []
	var evaluated: int = 0
	var failed: int = 0
	var not_evaluated: int = 0
	var headroom: float = linear_to_db(maxf(_global_peak, 1e-12))
	for profile_result: Dictionary in _profile_results:
		for check_name: String in profile_result.get("checks", {}):
			var check: Dictionary = profile_result.checks[check_name]
			if str(check.status) == "not_evaluated":
				not_evaluated += 1
			elif bool(check.passed):
				evaluated += 1
			else:
				evaluated += 1
				failed += 1
			all_checks.append({aircraft_id = profile_result.aircraft_id, check = check_name, status = check.status,
				passed = check.passed, observed = check.observed})
	for failure: String in _profile_failures:
		all_checks.append({status = "fail", message = failure})
	var no_capture: bool = _total_frames <= 0
	var has_failures: bool = failed > 0 or not _profile_failures.is_empty()
	var summary: String = "%d passed, %d failed, %d not evaluated" % [evaluated - failed, failed, not_evaluated]
	if no_capture:
		summary = "capture unavailable; " + summary
	return {
		"format": "openrc-audio-contact-mix-v1",
		"captured_utc": Time.get_datetime_string_from_system(true),
		"run_type": "staged presentation bench; not a flight, physics replay, or acoustic validation",
		"driver": AudioServer.get_driver_name(),
		"mix_rate_hz": AudioServer.get_mix_rate(),
		"audio_buffer_frames": AudioServer.get_output_latency() * float(AudioServer.get_mix_rate()),
		"listener_position_m": [LISTENER.x, LISTENER.y, LISTENER.z],
		"source_listener_distance_m": 8.0,
		"stage_conditions": {"steady_roll_speed_mps": ROLL_SPEED_MPS, "normal_force_n_each": CONTACT_FORCE_N,
			"reference_load_n_each": CONTACT_REFERENCE_N, "hard_surface": true,
			"touchdown_approach_speed_mps": 2.4, "touchdown_contact_approach_speed_mps": 0.0,
			"engine_stages": ["off", "idle", "full power"], "staged_state_source": "detached dictionaries; no FlightSession"},
		"capture_routes": {"engine": "Soundscape aircraft bus", "ground": "dedicated child bus routed to Soundscape output",
			"sum_pre_master": "Soundscape output bus, before Master"},
		"profiles": _profile_results,
		"checks": {"summary": summary, "evaluated": evaluated, "failed": failed,
			"not_evaluated": not_evaluated, "headroom_peak_dbfs": headroom,
			"has_failures": has_failures, "items": all_checks},
		"setup_failures": _profile_failures,
		"total_captured_frames_across_routes": _total_frames,
		"notes": [
			"Ground snapshots are explicit staged dictionaries at an 8 m source-listener range; they are not sampled from physics.",
			"The six engine profiles are resolved from installed aircraft catalog data with PowertrainAudio.profile_for.",
			"Rotor contacts are staged as skids with roll_enabled=false; they exercise impact playback only.",
			"Separate bus meters and the pre-Master sum are digital presentation measurements, not SPL or acoustic realism evidence.",
			"Under the Dummy driver, the script verifies execution but the report is not native-device evidence.",
		],
	}


func _cleanup_profile(rig: Node3D, soundscape: Node, ground_audio: Node, ground_bus: StringName,
		captures: Dictionary) -> void:
	for bus_key: String in captures:
		var capture: AudioEffectCapture = captures[bus_key]
		if capture == null:
			continue
		var bus_name: StringName = ground_bus if bus_key == "ground" else StringName(soundscape.get("_bus_names")[1] if bus_key == "engine" else soundscape.call("output_bus"))
		var bus_index: int = AudioServer.get_bus_index(bus_name)
		if bus_index >= 0:
			for effect_index: int in range(AudioServer.get_bus_effect_count(bus_index) - 1, -1, -1):
				if AudioServer.get_bus_effect(bus_index, effect_index) == capture:
					AudioServer.remove_bus_effect(bus_index, effect_index)
	if not ground_bus.is_empty():
		var ground_bus_index: int = AudioServer.get_bus_index(ground_bus)
		if ground_bus_index > 0:
			AudioServer.remove_bus(ground_bus_index)
	if is_instance_valid(ground_audio):
		ground_audio.queue_free()
	if is_instance_valid(soundscape):
		soundscape.queue_free()
	if is_instance_valid(rig):
		rig.queue_free()
	await process_frame

