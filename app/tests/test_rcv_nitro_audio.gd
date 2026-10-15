## Focused procedural Nitro voice and bounded AudioStreamGenerator checks.
extends SceneTree

const NitroVoice := preload("res://audio/nitro_voice.gd")
const NitroAudio := preload("res://audio/nitro_engine_audio.gd")
const RATE: float = NitroVoice.RATE
const PREVIEW_PATH := "res://../docs/research/rc-monster-truck/RCV-36/audio/nitro_engine_preview.wav"

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("PASS %s" % label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _telemetry(rpm: float = 6000.0, throttle: float = 0.25, running: bool = true, fuel: float = 0.08) -> Dictionary:
	return {
		"nitro": {
			"engine_rpm": rpm,
			"engine_running": running,
			"fuel_kg": fuel,
			"fuel_flow_kg_per_s": 0.00012,
			"throttle_fraction": throttle,
			"clutch_slip": 0.0,
			"clutch_engagement": 0.0,
			"clutch_torque_nm": 0.0,
			"wheel_drive_torque_nm": 0.0,
		},
		"wheel_in_contact": PackedByteArray([1, 1, 1, 1]),
		"wheel_slip_speed_m_per_s": PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"wheel_slip_ratio": PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
	}


func _mono(samples: PackedVector2Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(samples.size())
	for index in samples.size():
		result[index] = samples[index].x
	return result


func _rms(samples: PackedFloat32Array) -> float:
	var total: float = 0.0
	for sample in samples:
		total += sample * sample
	return sqrt(total / float(maxi(samples.size(), 1)))


func _tone_power(samples: PackedFloat32Array, frequency_hz: float) -> float:
	var coefficient: float = 2.0 * cos(TAU * frequency_hz / RATE)
	var previous: float = 0.0
	var previous_previous: float = 0.0
	for sample in samples:
		var current: float = sample + coefficient * previous - previous_previous
		previous_previous = previous
		previous = current
	return maxf(0.0, previous * previous + previous_previous * previous_previous - coefficient * previous * previous_previous)


func _append_blocks(voice: RefCounted, output: PackedVector2Array, frames: int) -> PackedVector2Array:
	var remaining: int = frames
	while remaining > 0:
		var count: int = mini(remaining, NitroVoice.MAX_BLOCK_FRAMES)
		output.append_array(voice.render(count))
		remaining -= count
	return output


func _run() -> void:
	_check("bounded generator target returns only available frames",
		NitroAudio.bounded_refill_frames(2048, 500, 1102) == 0)
	_check("bounded generator tops up to target without exceeding free frames",
		NitroAudio.bounded_refill_frames(2048, 1800, 1102) == 854)
	_check("large target is capped at one render block",
		NitroAudio.bounded_refill_frames(8192, 8192, 8192, 4096) == 4096)
	_check("invalid generator capacity is silent",
		NitroAudio.bounded_refill_frames(0, 0, 1102) == 0)

	var voice := NitroVoice.new()
	voice.observe(_telemetry(6000.0), {"throttle": 0.25}, false, true)
	var steady := voice.render(12000)
	var mono := _mono(steady)
	_check("steady two-stroke voice emits audible finite PCM", _rms(mono) > 0.035 and _all_finite_and_bounded(steady))
	var fundamental_power: float = _tone_power(mono.slice(3000, 11000), 100.0)
	var subharmonic_power: float = _tone_power(mono.slice(3000, 11000), 50.0)
	_check("exhaust pulse repeats once per revolution at 6000 RPM", fundamental_power > subharmonic_power * 1.5,
		"100 Hz=%.4f, 50 Hz=%.4f" % [fundamental_power, subharmonic_power])
	_check("render caps oversized frame requests", voice.render(100000).size() == NitroVoice.MAX_BLOCK_FRAMES)

	var idle_voice := NitroVoice.new()
	idle_voice.observe(_telemetry(6000.0, 0.0), {}, false, true)
	var idle_audio: PackedFloat32Array = _mono(idle_voice.render(12000))
	var loaded_voice := NitroVoice.new()
	loaded_voice.observe(_telemetry(6000.0, 1.0), {}, false, true)
	var loaded_audio: PackedFloat32Array = _mono(loaded_voice.render(12000))
	_check("load and fuel flow increase engine level at fixed RPM", _rms(loaded_audio) > _rms(idle_audio) * 1.08)

	var stalled := NitroVoice.new()
	stalled.observe(_telemetry(6000.0, 1.0, false, 0.08), {}, false, true)
	_check("stalled engine is silent", _all_zero(stalled.render(1024)))
	var empty := NitroVoice.new()
	empty.observe(_telemetry(6000.0, 1.0, true, 0.0), {}, false, true)
	_check("empty tank is silent", _all_zero(empty.render(1024)))

	var pause_voice := NitroVoice.new()
	pause_voice.observe(_telemetry(8000.0), {}, false, true)
	pause_voice.render(4096)
	var frozen_phase: float = pause_voice.phase_cycles
	pause_voice.observe(_telemetry(8000.0), {}, true, true)
	_check("paused voice emits silence and freezes its crank phase",
		_all_zero(pause_voice.render(2048)) and is_equal_approx(pause_voice.phase_cycles, frozen_phase))
	pause_voice.observe(_telemetry(8000.0), {}, false, true)
	var resumed: PackedVector2Array = pause_voice.render(512)
	var first_eight_peak: float = _peak(resumed.slice(0, 8))
	_check("resume fades from silence without a chirp", first_eight_peak < 0.025 and _all_finite_and_bounded(resumed))

	var transient := NitroVoice.new()
	transient.observe(_telemetry(6000.0), {}, false, true)
	transient.render(2048)
	transient.observe(_telemetry(18000.0, 0.9), {}, false, true)
	transient.render(256)
	_check("rapid RPM/load change creates a bounded transient", transient.last_transient_level > 0.0 and transient.last_transient_level < 0.2)

	var clutch_snapshot: Dictionary = _telemetry(9000.0, 0.8)
	clutch_snapshot.nitro.clutch_slip = -0.7
	clutch_snapshot.nitro.clutch_engagement = 0.8
	clutch_snapshot.nitro.clutch_torque_nm = -0.2
	clutch_snapshot.nitro.wheel_drive_torque_nm = -2.0
	var clutch_voice := NitroVoice.new()
	clutch_voice.observe(clutch_snapshot, {}, false, true)
	clutch_voice.render(4096)
	_check("signed engine-braking clutch slip and torque drive the mechanical layer", clutch_voice.last_clutch_level > 0.0)
	var no_clutch := NitroVoice.new()
	no_clutch.observe(_telemetry(9000.0, 0.8), {}, false, true)
	no_clutch.render(4096)
	_check("clutch layer is absent without slip telemetry", no_clutch.last_clutch_level == 0.0)
	var high_rpm_clutch := NitroVoice.new()
	var high_rpm_snapshot: Dictionary = _telemetry(45000.0, 0.8)
	high_rpm_snapshot.nitro.clutch_slip = 0.5
	high_rpm_snapshot.nitro.clutch_engagement = 0.8
	high_rpm_snapshot.nitro.clutch_torque_nm = 0.2
	high_rpm_clutch.observe(high_rpm_snapshot, {}, false, true)
	_check("45,000 RPM clutch harmonics stay finite and below the peak ceiling",
		_all_finite_and_bounded(high_rpm_clutch.render(4096)))

	var skid_snapshot: Dictionary = _telemetry(10000.0, 0.7)
	skid_snapshot["wheel_in_contact"] = PackedByteArray([1, 1, 1, 1])
	skid_snapshot["wheel_slip_speed_m_per_s"] = PackedFloat64Array([4.0, 0.0, 0.0, 0.0])
	skid_snapshot["wheel_slip_ratio"] = PackedFloat64Array([0.5, 0.0, 0.0, 0.0])
	var skid_voice := NitroVoice.new()
	skid_voice.observe(skid_snapshot, {}, false, true)
	skid_voice.render(4096)
	_check("tire skid is grounded by contact plus tire slip", skid_voice.last_skid_level > 0.0)
	var airborne_snapshot: Dictionary = skid_snapshot.duplicate(true)
	airborne_snapshot["wheel_in_contact"] = PackedByteArray([0, 0, 0, 0])
	var airborne_voice := NitroVoice.new()
	airborne_voice.observe(airborne_snapshot, {}, false, true)
	airborne_voice.render(4096)
	_check("airborne wheel slip does not synthesize tire skid", airborne_voice.last_skid_level == 0.0)

	var malformed: Dictionary = _telemetry(17000.0)
	malformed.nitro.engine_rpm = NAN
	malformed.nitro.fuel_flow_kg_per_s = INF
	malformed.wheel_slip_speed_m_per_s = PackedFloat64Array([NAN, INF, -INF, 100.0])
	var safe_voice := NitroVoice.new()
	safe_voice.observe(malformed, {}, false, true)
	_check("malformed non-finite telemetry cannot escape the limiter", _all_finite_and_bounded(safe_voice.render(4096)))

	await _test_player_factory()
	_write_preview()
	print("NITRO_AUDIO_CHECKS=%d FAILURES=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_player_factory() -> void:
	await process_frame
	var player := NitroAudio.create(root)
	await process_frame
	_check("factory creates isolated generator playback", player != null and player.stream is AudioStreamGenerator and player.playing)
	if player != null:
		player.observe(_telemetry(), {"throttle": 0.3}, false, true)
		await process_frame
		player.refill()
		_check("player refill stays within the configured generator ring",
			player.capacity_frames > 0 and player.queued_frames <= player.capacity_frames)
		player.observe(_telemetry(6000.0, 0.3, false, 0.08), {}, false, true)
		_check("stopped engine flushes the running generator state", player.voice.is_sound_eligible() == false)
		player.queue_free()
		await process_frame


func _write_preview() -> void:
	var voice := NitroVoice.new()
	var samples := PackedVector2Array()
	var total_frames: int = int(RATE * 4.0)
	var frame: int = 0
	while frame < total_frames:
		var progress: float = float(frame) / RATE
		var snapshot: Dictionary
		if progress < 0.8:
			snapshot = _telemetry(4500.0, 0.04)
		elif progress < 2.1:
			var rpm: float = lerpf(4500.0, 22000.0, clampf((progress - 0.8) / 1.3, 0.0, 1.0))
			snapshot = _telemetry(rpm, 0.88)
			snapshot.nitro.fuel_flow_kg_per_s = 0.00036
			snapshot.nitro.clutch_slip = 0.38
			snapshot.nitro.clutch_engagement = 0.82
			snapshot.nitro.clutch_torque_nm = 0.34
			snapshot.nitro.wheel_drive_torque_nm = 2.8
		elif progress < 3.4:
			snapshot = _telemetry(22000.0, 0.85)
			snapshot.nitro.fuel_flow_kg_per_s = 0.00034
			snapshot["wheel_in_contact"] = PackedByteArray([1, 1, 1, 1])
			snapshot["wheel_slip_speed_m_per_s"] = PackedFloat64Array([3.4, 3.0, 4.1, 3.8])
			snapshot["wheel_slip_ratio"] = PackedFloat64Array([0.42, 0.36, 0.55, 0.47])
		else:
			snapshot = _telemetry(0.0, 0.0, false, 0.0)
		voice.observe(snapshot, {"throttle": float(snapshot.nitro.throttle_fraction)}, false, true)
		var count: int = mini(NitroVoice.MAX_BLOCK_FRAMES, total_frames - frame)
		samples = _append_blocks(voice, samples, count)
		frame += count
	var absolute_path: String = ProjectSettings.globalize_path(PREVIEW_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		_check("preview WAV file opens", false, error_string(FileAccess.get_open_error()))
		return
	var data_bytes: int = samples.size() * 4
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data_bytes)
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(2)
	file.store_32(int(RATE))
	file.store_32(int(RATE) * 4)
	file.store_16(4)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_bytes)
	for sample: Vector2 in samples:
		file.store_16(clampi(roundi(sample.x * 32767.0), -32768, 32767) & 0xffff)
		file.store_16(clampi(roundi(sample.y * 32767.0), -32768, 32767) & 0xffff)
	file.close()
	_check("writes four-second stereo WAV preview", FileAccess.get_file_as_bytes(absolute_path).size() == 44 + data_bytes, absolute_path)


func _all_finite_and_bounded(samples: PackedVector2Array) -> bool:
	for sample: Vector2 in samples:
		if not is_finite(sample.x) or not is_finite(sample.y) or absf(sample.x) > NitroVoice.MAX_OUTPUT_PEAK or absf(sample.y) > NitroVoice.MAX_OUTPUT_PEAK:
			return false
	return true


func _all_zero(samples: PackedVector2Array) -> bool:
	for sample: Vector2 in samples:
		if sample.x != 0.0 or sample.y != 0.0:
			return false
	return true


func _peak(samples: PackedVector2Array) -> float:
	var result: float = 0.0
	for sample: Vector2 in samples:
		result = maxf(result, absf(sample.x))
	return result
