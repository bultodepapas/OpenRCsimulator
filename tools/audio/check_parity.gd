## AUD-04 / AUD-15: compare the real main scene with the full engine + gear adapter on/off.
## Run against the isolated work app:
## godot --headless --path .tools/audio-work/app --script C:/DEVELOPMENT/OpenRCsimulator/tools/audio/check_parity.gd -- --soundscape=off --report=C:/DEVELOPMENT/OpenRCsimulator/docs/research/audio/AUD-04/parity.json
## Add --electric-demo=4s for the separate electric route. This qualifies simulation parity only,
## not acoustic quality or speaker acceptance.
extends SceneTree

const MAIN_SCENE := "res://main.tscn"
const FlightAudio = preload("res://audio/flight_audio.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const WindConfig = preload("res://physics/wind_config.gd")
const TICKS := 1200 # 5 s per flight, paired on/off (10 simulated seconds per aircraft total).
const PAUSE_SAMPLES := 24
const PAUSE_AT_TICK := 600
const SEED := 4102026
const WEATHER := "turbulent"
const TAPE := [
	{end = 240, input = [0.00, 0.00, 0.00, 0.45]},
	{end = 480, input = [0.06, -0.03, 0.00, 0.60]},
	{end = 720, input = [-0.06, 0.04, 0.02, 0.53]},
	{end = 960, input = [0.03, 0.00, -0.02, 0.68]},
	{end = 1200, input = [0.00, 0.00, 0.00, 0.50]},
]

var _checks := 0
var _failures: Array[String] = []
var _skipped: Array[Dictionary] = []
var _aircraft_results: Array[Dictionary] = []
var _run_args: Dictionary = {}


func _initialize() -> void:
	_run_args = _parse_args(OS.get_cmdline_user_args())
	if Engine.physics_ticks_per_second != 240:
		_fail("fixed timestep", "expected 240 Hz, got %d" % Engine.physics_ticks_per_second)
		_finish()
		return
	if str(_run_args.get("soundscape", "")) != "off":
		_fail("route isolation", "pass --soundscape=off so both real main scenes start without automatic audio")
		_finish()
		return
	var electric_demo: String = str(_run_args.get("electric-demo", ""))
	var aircraft_ids: PackedStringArray = PackedStringArray([Catalog.DEFAULT_ID]) if not electric_demo.is_empty() else Catalog.ids()
	for aircraft_id: String in aircraft_ids:
		if Catalog.is_rotorcraft(aircraft_id):
			# main.tscn is the fixed-wing route; it loads rotorcraft data as an invalid airplane. Report, never hide.
			_skipped.append({aircraft_id = aircraft_id, reason = "rotorcraft: not a main.tscn fixed-wing flight; parity not covered"})
			print("SKIP ", aircraft_id, " — rotorcraft route is not covered by this fixed-wing harness")
			continue
		if not Catalog.can_fly(aircraft_id):
			_fail("catalog route", "%s has no flight data" % aircraft_id)
			continue
		var result: Dictionary = await _run_pair(aircraft_id, electric_demo)
		_aircraft_results.append(result)
		if not result.get("ok", false):
			_fail("pair %s" % aircraft_id, str(result.get("error", "unknown failure")))
	# Let the mixer retire the last pair's released playback resources before the fast exit.
	await create_timer(0.1, true, false, true).timeout
	_finish()


func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for value: String in args:
		var pair: PackedStringArray = value.trim_prefix("--").split("=", true, 1)
		parsed[pair[0]] = pair[1] if pair.size() > 1 else true
	return parsed


func _make_main(aircraft_id: String) -> Node:
	var main: Node = load(MAIN_SCENE).instantiate()
	main.set("aircraft_id", aircraft_id)
	main.set("weather_config", WindConfig.preset(WEATHER))
	main.set("start_choice", "airborne")
	# Inherit a disabled process mode before tree entry, so the real scene can initialize without an automatic tick.
	main.set("process_mode", Node.PROCESS_MODE_DISABLED)
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.set_physics_process(false)
	var session: Node = main.get("session") as Node
	if session == null:
		return main
	session.set("input_enabled", false)
	session.set_process(false)
	session.set_physics_process(false)
	var sim: Node = session.get("sim") as Node
	if sim != null:
		sim.set("process_mode", Node.PROCESS_MODE_DISABLED)
		sim.set_process(false)
		sim.set_physics_process(false)
	return main


func _run_pair(aircraft_id: String, electric_demo: String) -> Dictionary:
	var baseline: Node = await _make_main(aircraft_id)
	var candidate: Node = await _make_main(aircraft_id)
	if not electric_demo.is_empty():
		# The command-line option is consumed by main.gd; both instances receive the same route.
		if str(candidate.get("_electric_demo")) != electric_demo or str(baseline.get("_electric_demo")) != electric_demo:
			baseline.free()
			candidate.free()
			return {ok = false, error = "electric demo argument was not applied to both main scenes"}
	var baseline_session: Node = baseline.get("session") as Node
	var candidate_session: Node = candidate.get("session") as Node
	if baseline_session == null or candidate_session == null:
		baseline.free()
		candidate.free()
		return {ok = false, error = "main.tscn did not create both sessions"}
	if not baseline_session.call("is_flyable") or not candidate_session.call("is_flyable"):
		var reason: String = str(candidate_session.get("start_error"))
		baseline.free()
		candidate.free()
		return {ok = false, error = "trimmed start refused: " + reason}
	var baseline_sim: Node = baseline_session.get("sim") as Node
	var candidate_sim: Node = candidate_session.get("sim") as Node
	if int(baseline_sim.get("tick")) != 0 or int(candidate_sim.get("tick")) != 0:
		baseline.free()
		candidate.free()
		return {ok = false, error = "main scene did not begin at tick zero"}
	if baseline.get("_soundscape_audio") != null or candidate.get("_soundscape_audio") != null:
		baseline.free()
		candidate.free()
		return {ok = false, error = "soundscape=off unexpectedly created automatic FlightAudio"}

	# Judge this pair by its own checks; earlier aircraft's failures stay in the run status, not in this result.
	var failures_before_pair: int = _failures.size()
	var seed_probe := RandomNumberGenerator.new()
	seed_probe.seed = SEED
	var seeded_audio_rng_state: int = seed_probe.state
	var configure_guard: PackedByteArray = _session_guard(candidate_session)
	var audio: FlightAudio = FlightAudio.new()
	audio.name = "AUD04FlightAudio"
	candidate.add_child(audio)
	audio.configure(candidate)
	audio.set_process(false)
	candidate.set("_soundscape_audio", audio)
	candidate.set("_engine_audio", audio.soundscape.voices[0])
	var audio_rng_advanced_at_configure: bool = audio.soundscape.rng.state != seeded_audio_rng_state
	var start_match: bool = _session_bytes(baseline_session) == _session_bytes(candidate_session)
	_check("%s starts at identical full checkpoints" % aircraft_id, start_match)
	var configure_read_only: bool = _session_guard(candidate_session) == configure_guard
	_check("%s audio configure leaves session unchanged" % aircraft_id, configure_read_only)

	var aircraft: Dictionary = candidate_session.get("aircraft")
	var model: Dictionary = aircraft.get("model", {})
	var propulsion: Dictionary = model.get("propulsion", {})
	var kind: String = str(propulsion.get("kind", "glow_prop"))
	var simulation_rng_advanced: bool = false
	var read_snapshot_checks: int = 0
	var read_update_checks: int = 0
	var compared_ticks: int = 0
	var paused_samples: int = 0
	var restart_checkpoint_equal: bool = false
	var restart_audio_read_only: bool = false
	var error_text := ""
	if not start_match:
		error_text = "on/off sessions did not start at identical full checkpoints"
	elif not configure_read_only:
		error_text = "FlightAudio.configure mutated the candidate session"
	var previous_rng_state: int = int(candidate_sim.get("modes")[1])
	# The tape drives the four primary controls; extra channels (gear, flaps, smoke) keep their accepted start values.
	var start_inputs: PackedFloat64Array = (baseline_sim.get("inputs") as PackedFloat64Array).duplicate()
	var highest_audio_update_usec := 0

	for accepted_tick: int in TICKS:
		if accepted_tick == PAUSE_AT_TICK:
			baseline_session.call("hold", "AUD-04 parity pause")
			candidate_session.call("hold", "AUD-04 parity pause")
			for _sample: int in PAUSE_SAMPLES:
				_render_accepted_pose(candidate)
				var paused_before: PackedByteArray = _session_guard(candidate_session)
				audio.snapshot()
				if _session_guard(candidate_session) != paused_before:
					error_text = "snapshot mutated session during pause at accepted tick %d" % accepted_tick
					break
				audio._process(1.0 / 240.0)
				highest_audio_update_usec = maxi(highest_audio_update_usec, audio.last_update_usec)
				if _session_guard(candidate_session) != paused_before or _session_bytes(baseline_session) != _session_bytes(candidate_session):
					error_text = "audio update changed paused session parity at accepted tick %d" % accepted_tick
					break
				paused_samples += 1
			if not error_text.is_empty():
				break
			baseline_session.call("release", "AUD-04 parity pause")
			candidate_session.call("release", "AUD-04 parity pause")
			baseline_session.call("resume")
			candidate_session.call("resume")
			if _session_bytes(baseline_session) != _session_bytes(candidate_session):
				error_text = "resume boundary differs at accepted tick %d" % accepted_tick
				break

		var accepted_input: PackedFloat64Array = _input_at(accepted_tick, start_inputs)
		baseline_sim.set("inputs", accepted_input.duplicate())
		candidate_sim.set("inputs", accepted_input.duplicate())
		baseline_sim.call("step")
		candidate_sim.call("step")
		if int(baseline_sim.get("tick")) != accepted_tick + 1 or int(candidate_sim.get("tick")) != accepted_tick + 1:
			error_text = "manual fixed step did not advance both scenes at accepted tick %d" % accepted_tick
			break
		if not str(baseline_sim.get("fault_reason")).is_empty() or not str(candidate_sim.get("fault_reason")).is_empty():
			error_text = "simulation fault at accepted tick %d: baseline=%s candidate=%s" % [accepted_tick,
				str(baseline_sim.get("fault_reason")), str(candidate_sim.get("fault_reason"))]
			break
		if _session_bytes(baseline_session) != _session_bytes(candidate_session):
			error_text = "full checkpoint mismatch before audio at accepted tick %d" % accepted_tick
			break
		var rng_state: int = int(candidate_sim.get("modes")[1])
		if rng_state != previous_rng_state:
			simulation_rng_advanced = true
		previous_rng_state = rng_state

		_render_accepted_pose(candidate)
		var before_snapshot: PackedByteArray = _session_guard(candidate_session)
		var sound_snapshot: Dictionary = audio.snapshot()
		if _session_guard(candidate_session) != before_snapshot:
			error_text = "snapshot mutated session at accepted tick %d" % accepted_tick
			break
		read_snapshot_checks += 1
		var before_update: PackedByteArray = _session_guard(candidate_session)
		audio._process(1.0 / 240.0)
		highest_audio_update_usec = maxi(highest_audio_update_usec, audio.last_update_usec)
		if _session_guard(candidate_session) != before_update:
			error_text = "update_sound mutated session at accepted tick %d" % accepted_tick
			break
		read_update_checks += 1
		if _session_bytes(baseline_session) != _session_bytes(candidate_session):
			error_text = "full checkpoint mismatch after audio at accepted tick %d" % accepted_tick
			break
		compared_ticks += 1

	var flight_end_off: PackedByteArray = _session_bytes(baseline_session)
	var flight_end_on: PackedByteArray = _session_bytes(candidate_session)
	if error_text.is_empty():
		baseline_session.call("reset")
		candidate_session.call("reset")
		restart_checkpoint_equal = _session_bytes(baseline_session) == _session_bytes(candidate_session)
		if not restart_checkpoint_equal:
			error_text = "restart reset produced different full checkpoints"
		else:
			_render_accepted_pose(candidate)
			var after_reset_before_audio: PackedByteArray = _session_guard(candidate_session)
			var reset_snapshot: Dictionary = audio.snapshot()
			audio._process(1.0 / 240.0)
			restart_audio_read_only = _session_guard(candidate_session) == after_reset_before_audio
			if not restart_audio_read_only or _session_bytes(baseline_session) != _session_bytes(candidate_session):
				error_text = "audio mutated state or parity after restart reset"
	_check("%s audio configure consumes its private RNG" % aircraft_id, audio_rng_advanced_at_configure)
	_check("%s turbulence simulation RNG advances under equal on/off states" % aircraft_id, simulation_rng_advanced)

	var final_baseline: PackedByteArray = _session_bytes(baseline_session)
	var final_candidate: PackedByteArray = _session_bytes(candidate_session)
	var result := {
		"aircraft_id": aircraft_id,
		"propulsion_kind": kind,
		"electric_demo": electric_demo,
		"ok": error_text.is_empty() and final_baseline == final_candidate and compared_ticks == TICKS and restart_checkpoint_equal and restart_audio_read_only and configure_read_only and _failures.size() == failures_before_pair,
		"accepted_ticks_compared": compared_ticks,
		"simulated_seconds_per_run": float(TICKS) / 240.0,
		"paired_simulated_seconds_total": 2.0 * float(TICKS) / 240.0,
		"pause_samples": paused_samples,
		"snapshot_read_only_checks": read_snapshot_checks,
		"update_read_only_checks": read_update_checks,
		"configure_read_only": configure_read_only,
		"restart_checkpoint_equal": restart_checkpoint_equal,
		"restart_audio_read_only": restart_audio_read_only,
		"full_checkpoint_equal_each_step": compared_ticks == TICKS and error_text.is_empty(),
		"checkpoint_hash_off_after_tape": _sha256(flight_end_off),
		"checkpoint_hash_on_after_tape": _sha256(flight_end_on),
		"post_reset_checkpoint_hash_off": _sha256(final_baseline),
		"post_reset_checkpoint_hash_on": _sha256(final_candidate),
		"turbulence_rng_advanced_identically": simulation_rng_advanced and final_baseline == final_candidate,
		"audio_rng_advanced_during_configure": audio_rng_advanced_at_configure,
		"max_update_usec_observed": highest_audio_update_usec,
		"error": error_text,
	}
	baseline.free()
	candidate.free()
	return result


func _input_at(tick: int, layout: PackedFloat64Array) -> PackedFloat64Array:
	var primary: Array = TAPE[-1].input
	for segment: Dictionary in TAPE:
		if tick < int(segment.end):
			primary = segment.input
			break
	var accepted: PackedFloat64Array = layout.duplicate()
	for channel: int in mini(primary.size(), accepted.size()):
		accepted[channel] = float(primary[channel])
	return accepted


func _render_accepted_pose(main: Node) -> void:
	var session: Node = main.get("session") as Node
	var sim: Node = session.get("sim") as Node
	var pose: Dictionary = main.call("_pose_of", sim.get("state"))
	var prop_angle: float = fposmod(TAU * float(sim.get("aux")[0]) / 60.0 * float(sim.call("time")), TAU)
	main.call("_render_pose", pose, session.call("surfaces"), prop_angle)


func _session_bytes(session: Node) -> PackedByteArray:
	return var_to_bytes(session.call("checkpoint"))


func _session_guard(session: Node) -> PackedByteArray:
	var sim: Node = session.get("sim") as Node
	return var_to_bytes([
		session.call("checkpoint"),
		session.get("engine_running"),
		session.get("pause_reason"),
		session.get("crash"),
		session.get("holds"),
		sim.get("paused"),
		sim.get("fault_reason"),
	])


func _sha256(value: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(value)
	return hash.finish().hex_encode()


func _resource_sha256(path: String) -> String:
	return _sha256(FileAccess.get_file_as_bytes(path))


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_fail(label, "assertion failed")


func _fail(label: String, detail: String) -> void:
	_failures.append(label + ": " + detail)
	printerr("FAIL ", label, " — ", detail)


func _finish() -> void:
	var expected: int = 1 if not str(_run_args.get("electric-demo", "")).is_empty() else Catalog.ids().size() - _skipped.size()
	var passed_pairs: int = 0
	for result: Dictionary in _aircraft_results:
		if result.get("ok", false):
			passed_pairs += 1
	var report: Dictionary = {
		"format": "openrc-audio-simulation-parity v1",
		"status": "pass" if _failures.is_empty() and passed_pairs == expected else "fail",
		"tested_at_utc": Time.get_datetime_string_from_system(true, true),
		"engine": Engine.get_version_info().string,
		"project_route": ProjectSettings.globalize_path(MAIN_SCENE),
		"audio_modules_sha256": {
			"soundscape_model.gd": _resource_sha256("res://audio/soundscape_model.gd"),
			"soundscape.gd": _resource_sha256("res://audio/soundscape.gd"),
			"glow_audio_pump.gd": _resource_sha256("res://audio/glow_audio_pump.gd"),
			"glow_voice.gd": _resource_sha256("res://audio/glow_voice.gd"),
			"flight_audio.gd": _resource_sha256("res://audio/flight_audio.gd"),
			"powertrain_audio.gd": _resource_sha256("res://audio/powertrain_audio.gd"),
			"ground_audio.gd": _resource_sha256("res://audio/ground_audio.gd"),
			"ground_audio_model.gd": _resource_sha256("res://audio/ground_audio_model.gd"),
			"mechanical_audio.gd": _resource_sha256("res://audio/mechanical_audio.gd"),
			"mechanical_motion.gd": _resource_sha256("res://audio/mechanical_motion.gd"),
			"mechanical_profile.gd": _resource_sha256("res://audio/mechanical_profile.gd"),
		},
		"adapter_update": "FlightAudio._process: soundscape, ground contacts and mechanical actuators",
		"headless": true,
		"physics_hz": Engine.physics_ticks_per_second,
		"weather": WEATHER,
		"accepted_input_tape": TAPE,
		"ticks_per_pair_run": TICKS,
		"simulated_seconds_per_run": float(TICKS) / 240.0,
		"pause_samples_per_pair": PAUSE_SAMPLES,
		"checkpoint_encoding": "var_to_bytes(FlightSession.checkpoint()) exact Variant bytes",
		"checks": _checks,
		"passed_pairs": passed_pairs,
		"expected_pairs": expected,
		"runs": _aircraft_results,
		"skipped": _skipped,
		"failures": _failures,
		"scope": "simulation parity only; no acoustic, latency, speaker, or human acceptance",
	}
	var report_path: String = str(_run_args.get("report", ""))
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file == null:
			_fail("report write", "cannot open %s (error %d)" % [report_path, FileAccess.get_open_error()])
			report.status = "fail"
			report.failures = _failures
		else:
			file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
			file.close()
			print("AUD04_REPORT=", report_path)
	print("AUD04_JSON_BEGIN")
	print(JSON.stringify(report, "\t", true, true))
	print("AUD04_JSON_END")
	quit(0 if _failures.is_empty() and passed_pairs == expected else 1)
