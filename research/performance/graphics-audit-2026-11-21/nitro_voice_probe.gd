## Detached component evidence only. No player, simulation, renderer or audio device.
extends SceneTree

const Voice := preload("res://audio/nitro_voice.gd")
const Audio := preload("res://audio/nitro_engine_audio.gd")
const SAMPLE_COUNT: int = 41
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _snapshot(running: bool, rpm: float, clutch: bool = false) -> Dictionary:
	return {
		"nitro": {"engine_rpm": rpm, "engine_running": running, "fuel_kg": 0.08,
			"fuel_flow_kg_per_s": 0.00012 if running else 0.0, "throttle_fraction": 0.7 if running else 0.0,
			"clutch_slip": 0.7 if clutch else 0.0, "clutch_engagement": 0.8 if clutch else 0.0,
			"clutch_torque_nm": 0.2 if clutch else 0.0, "wheel_drive_torque_nm": 2.0 if clutch else 0.0},
		"wheel_in_contact": PackedByteArray([1, 1, 1, 1]),
		"wheel_slip_speed_m_per_s": PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"wheel_slip_ratio": PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
	}


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: " + label)


func _peak(samples: PackedVector2Array) -> float:
	var peak: float = 0.0
	for sample in samples:
		if not is_finite(sample.x) or not is_finite(sample.y):
			return INF
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	return peak


func _case(label: String, frames: int, running: bool, paused: bool, rpm: float, clutch: bool, fuel_kg: float = 0.08) -> Dictionary:
	var voice := Voice.new()
	var snapshot: Dictionary = _snapshot(running, rpm, clutch)
	snapshot.nitro.fuel_kg = fuel_kg
	voice.observe(snapshot, {}, paused, true)
	# Identical one-second warm-up length across block sizes. No live playback occurs.
	var remaining: int = int(Voice.RATE)
	while remaining > 0:
		var count: int = mini(remaining, 1103)
		voice.render(count)
		remaining -= count
	var durations: Array[int] = []
	var last := PackedVector2Array()
	for sample_index in SAMPLE_COUNT:
		var started: int = Time.get_ticks_usec()
		last = voice.render(frames)
		durations.append(Time.get_ticks_usec() - started)
	var ordered: Array[int] = durations.duplicate()
	ordered.sort()
	var peak: float = _peak(last)
	_check(label + " output size and peak", last.size() == frames and is_finite(peak) and peak <= Voice.MAX_OUTPUT_PEAK)
	if not running or paused:
		_check(label + " remains silent", peak == 0.0)
	return {"case": label, "block_frames": frames, "sample_count": SAMPLE_COUNT,
		"input_rpm": rpm, "input_running": running, "input_paused": paused, "input_fuel_kg": fuel_kg,
		"input_enabled": true, "input_controls": {}, "input_nitro": snapshot.nitro.duplicate(true),
		"input_wheel_in_contact": Array(snapshot.wheel_in_contact),
		"input_wheel_slip_speed_m_per_s": Array(snapshot.wheel_slip_speed_m_per_s),
		"input_wheel_slip_ratio": Array(snapshot.wheel_slip_ratio),
		"input_scope": "hand-authored synthetic voice API snapshot, not captured vehicle telemetry",
		"durations_usec": durations, "median_usec": ordered[int(floor(SAMPLE_COUNT / 2.0))],
		"p95_nearest_rank_usec": ordered[ceili(0.95 * SAMPLE_COUNT) - 1],
		"max_usec": ordered[-1], "last_output_peak": peak,
		"last_output_hex_sha256": last.to_byte_array().hex_encode().sha256_text(),
		"final_rpm": voice.current_rpm, "final_phase_cycles": voice.phase_cycles}


func _run() -> void:
	var voice := Voice.new()
	voice.observe(_snapshot(true, 6000.0), {}, false, true)
	_check("zero request", voice.render(0).is_empty())
	_check("negative request", voice.render(-1).is_empty())
	_check("oversized request is bounded", voice.render(100000).size() == Voice.MAX_BLOCK_FRAMES)
	_check("50 ms target is 1103 frames", ceili(Audio.TARGET_SECONDS * Voice.RATE) == 1103)
	_check("empty queue refill is bounded by target", Audio.bounded_refill_frames(3307, 3307, 1103) == 1103)
	var whole := Voice.new()
	var split := Voice.new()
	whole.observe(_snapshot(true, 9000.0, true), {}, false, true)
	split.observe(_snapshot(true, 9000.0, true), {}, false, true)
	var expected: PackedVector2Array = whole.render(1103)
	var actual: PackedVector2Array = split.render(368)
	actual.append_array(split.render(368))
	actual.append_array(split.render(367))
	_check("block split preserves exact PCM bytes", expected.to_byte_array() == actual.to_byte_array())
	for field in ["phase_cycles", "current_rpm", "_gate", "_transient", "_noise_state", "_skid_noise", "_current_throttle"]:
		_check("block split preserves " + field, whole.get(field) == split.get(field))
	var phase: float = voice.phase_cycles
	voice.observe(_snapshot(true, 6000.0), {}, true, true)
	_check("pause is silent and preserves phase", _peak(voice.render(1103)) == 0.0 and voice.phase_cycles == phase)
	voice.observe(_snapshot(true, 6000.0), {}, false, false)
	_check("disabled is silent and preserves phase", _peak(voice.render(1103)) == 0.0 and voice.phase_cycles == phase)
	var rows: Array[Dictionary] = []
	for frames in [184, 368, 1103]:
		rows.append(_case("running_6000", frames, true, false, 6000.0, false))
		rows.append(_case("running_38000_clutch", frames, true, false, 38000.0, true))
		rows.append(_case("voice_boundary_45000_clutch", frames, true, false, 45000.0, true))
		rows.append(_case("empty_fuel_6000", frames, false, false, 6000.0, false, 0.0))
		rows.append(_case("stopped_0", frames, false, false, 0.0, false))
		rows.append(_case("paused_6000", frames, true, true, 6000.0, false))
	var result: Dictionary = {"schema": "openrc-audit-nitro-component-v1",
		"scope": "synthetic inputs to detached unchanged GDScript component; elapsed time, not a vehicle/audio/FPS measurement",
		"warmup_frames_per_case": int(Voice.RATE), "rows": rows, "checks": _checks, "failures": _failures}
	var output := FileAccess.open("res://nitro-voice-results.json", FileAccess.WRITE)
	_check("result file available", output != null)
	if output != null:
		result.checks = _checks
		result.failures = _failures
		output.store_string(JSON.stringify(result, "\t", true, true) + "\n")
		output.close()
	print("NITRO_AUDIT_COMPONENT: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
