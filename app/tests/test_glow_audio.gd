## Audio-only proof for NITRO glow cadence. Levels and timbres are authored, not measured.
## Run: godot --headless --path . --script res://tests/test_glow_audio.gd
## Add `-- --write-glow-audio-wavs` to write native PCM comparison clips under user://.
extends SceneTree

const GlowVoice := preload("res://audio/glow_voice.gd")
const Soundscape := preload("res://audio/soundscape.gd")

var _failures: int = 0
var _count: int = 0
var _artifacts: bool = false
var _native_capture: bool = false
var _artifact_paths: PackedStringArray = PackedStringArray()
var _native_tick: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _power(samples: PackedFloat32Array, frequency_hz: float) -> float:
	return _power_at_rate(samples, frequency_hz, GlowVoice.RATE)


func _power_at_rate(samples: PackedFloat32Array, frequency_hz: float, sample_rate: float) -> float:
	var w: float = TAU * frequency_hz / sample_rate
	var coefficient: float = 2.0 * cos(w)
	var s1: float = 0.0
	var s2: float = 0.0
	for sample: float in samples:
		var s0: float = sample + coefficient * s1 - s2
		s2 = s1
		s1 = s0
	return maxf(0.0, s1 * s1 + s2 * s2 - coefficient * s1 * s2)


func _band_amplitude(samples: PackedFloat32Array, low_hz: float, high_hz: float, sample_rate: float) -> float:
	if samples.is_empty():
		return 0.0
	var peak_power: float = 0.0
	for frequency_bin: int in range(floori(low_hz), ceili(high_hz) + 1):
		peak_power = maxf(peak_power, _power_at_rate(samples, float(frequency_bin), sample_rate))
	return sqrt(peak_power) / float(samples.size())


func _rms(samples: PackedFloat32Array) -> float:
	var total: float = 0.0
	for sample: float in samples:
		total += sample * sample
	return sqrt(total / float(maxi(samples.size(), 1)))


func _mono(stereo: PackedVector2Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(stereo.size())
	for i: int in stereo.size():
		result[i] = stereo[i].x
	return result


func _telemetry(family: String, running: bool = true, firing_fraction: float = 1.0,
		blade_count: int = 2) -> Dictionary:
	return {
		"family": family,
		"rpm": 6000.0,
		"max_rpm": 12000.0,
		"running": running,
		"firing_fraction": firing_fraction,
		"load": 0.65,
		"throttle": 0.7,
		"blade_count": blade_count,
	}


func _render(snapshot: Dictionary, frames: int) -> PackedFloat32Array:
	var voice := GlowVoice.new()
	voice.reset()
	return _mono(voice.render_telemetry(snapshot, frames))


func _difference(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(mini(a.size(), b.size()))
	for i: int in result.size():
		result[i] = a[i] - b[i]
	return result


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_artifacts = args.has("--write-glow-audio-wavs")
	_native_capture = args.has("--capture-native-glow") or _artifacts
	var frames: int = int(GlowVoice.RATE)
	_check("2T uses one firing opportunity per crank revolution", GlowVoice.cycle_revolutions("glow_2t") == 1 and GlowVoice.firing_order("glow_2t") == 1.0)
	_check("true 4T uses one firing opportunity per two crank revolutions", GlowVoice.cycle_revolutions("glow_4t") == 2 and GlowVoice.firing_order("glow_4t") == 0.5)
	_check("legacy glow_prop does not choose an engine family", GlowVoice.cycle_revolutions("glow_prop") == 0 and GlowVoice.firing_order("glow_prop") == 0.0)
	_check("rich 2T fraction changes cadence without changing its family", GlowVoice.cycle_revolutions("glow_2t") == 1 and is_equal_approx(GlowVoice.firing_frequency_hz("glow_2t", 6000.0, 0.5), 50.0))
	_check("blade-pass frequency depends on shaft RPM and blade count only", is_equal_approx(GlowVoice.blade_pass_frequency_hz(6000.0, 3), 300.0))

	var two_t: PackedFloat32Array = _render(_telemetry("glow_2t"), frames)
	var four_t: PackedFloat32Array = _render(_telemetry("glow_4t"), frames)
	var rich_two_t: PackedFloat32Array = _render(_telemetry("glow_2t", true, 0.5), frames)
	var two_t_100: float = _power(two_t, 100.0)
	var two_t_50: float = _power(two_t, 50.0)
	var four_t_50: float = _power(four_t, 50.0)
	var four_t_100: float = _power(four_t, 100.0)
	var rich_50: float = _power(rich_two_t, 50.0)
	var rich_100: float = _power(rich_two_t, 100.0)
	_check("full-fire 2T spectrum has its exhaust line at shaft order 1", two_t_100 > 10.0 * maxf(two_t_50, 1e-9), "%s at 100 Hz vs %s at 50 Hz" % [String.num_scientific(two_t_100), String.num_scientific(two_t_50)])
	_check("true 4T spectrum has its exhaust/cam line at shaft order 0.5", four_t_50 > 2.0 * maxf(four_t_100, 1e-9), "%s at 50 Hz vs %s at 100 Hz" % [String.num_scientific(four_t_50), String.num_scientific(four_t_100)])
	_check("rich 2T missed opportunities create a 50 Hz subharmonic while staying 2T", rich_50 > 0.15 * maxf(rich_100, 1e-9) and GlowVoice.cycle_revolutions("glow_2t") == 1, "%s at 50 Hz vs %s at 100 Hz" % [String.num_scientific(rich_50), String.num_scientific(rich_100)])

	var three_blade_two_t: PackedFloat32Array = _render(_telemetry("glow_2t", false, 1.0, 3), frames)
	var three_blade_four_t: PackedFloat32Array = _render(_telemetry("glow_4t", false, 1.0, 3), frames)
	var prop_two_t: float = _power(three_blade_two_t, 300.0)
	var prop_four_t: float = _power(three_blade_four_t, 300.0)
	_check("3-blade prop order remains 300 Hz at 6000 RPM for either family", prop_two_t > 0.0 and prop_four_t > 0.0 and absf(prop_two_t - prop_four_t) < 1e-4 * maxf(prop_two_t, prop_four_t), "%s vs %s" % [String.num_scientific(prop_two_t), String.num_scientific(prop_four_t)])

	# Compare identical phase histories to isolate what a throttle cut changes.
	var active_voice := GlowVoice.new()
	var cut_voice := GlowVoice.new()
	active_voice.reset()
	cut_voice.reset()
	var active: PackedFloat32Array = _mono(active_voice.render_telemetry(_telemetry("glow_2t", true), frames))
	var cut: PackedFloat32Array = _mono(cut_voice.render_telemetry(_telemetry("glow_2t", false), frames))
	var combustion_only: PackedFloat32Array = _difference(active, cut)
	_check("throttle cut preserves shaft mechanics and prop sound", _rms(cut) > 0.015 and _power(cut, 100.0) > 0.0 and _power(cut, 200.0) > 0.0, "cut RMS %.5f" % _rms(cut))
	_check("throttle cut removes the combustion contribution", _power(combustion_only, 100.0) > 100.0 * maxf(_power(combustion_only, 50.0), 1e-9), "%s at order 1" % String.num_scientific(_power(combustion_only, 100.0)))

	var resumed := GlowVoice.new()
	var stopped_baseline := GlowVoice.new()
	resumed.reset()
	stopped_baseline.reset()
	var first: PackedVector2Array = resumed.render_telemetry(_telemetry("glow_2t", true), 4096)
	var stopped: PackedVector2Array = resumed.render_telemetry(_telemetry("glow_2t", false), 2205)
	var restarted: PackedFloat32Array = _mono(resumed.render_telemetry(_telemetry("glow_2t", true), 5512))
	stopped_baseline.render_telemetry(_telemetry("glow_2t", false), 4096)
	stopped_baseline.render_telemetry(_telemetry("glow_2t", false), 2205)
	var no_combustion_restart: PackedFloat32Array = _mono(stopped_baseline.render_telemetry(_telemetry("glow_2t", false), 5512))
	var restart_combustion: PackedFloat32Array = _difference(restarted, no_combustion_restart)
	_check("restart restores combustion without resetting the crank phase", _power(restart_combustion, 100.0) > 100.0 * maxf(_power(restart_combustion, 50.0), 1e-9) and is_equal_approx(resumed.phase, stopped_baseline.phase), "phase %.6f vs %.6f" % [resumed.phase, stopped_baseline.phase])
	_check("renderer samples remain bounded through cut and restart", _bounded(first) and _bounded(stopped) and _bounded(resumed.render_telemetry(_telemetry("glow_2t", true), 256)))

	# State continuity includes the deterministic missed-fire accumulator.
	var continuity_snapshot: Dictionary = _telemetry("glow_2t", true, 0.37)
	var whole_voice := GlowVoice.new()
	var split_voice := GlowVoice.new()
	var whole: PackedVector2Array = whole_voice.render_telemetry(continuity_snapshot, 8192)
	var split_a: PackedVector2Array = split_voice.render_telemetry(continuity_snapshot, 3017)
	var split_b: PackedVector2Array = split_voice.render_telemetry(continuity_snapshot, 5175)
	split_a.append_array(split_b)
	_check("two generator blocks join with deterministic phase and fire scheduling", _worst_difference(whole, split_a) < 1e-6, "max difference %s" % String.num_scientific(_worst_difference(whole, split_a)))
	var native_adapter_voice := GlowVoice.new()
	native_adapter_voice.set_telemetry(_telemetry("glow_4t"))
	_check("legacy native-generator render signature returns stereo PCM", native_adapter_voice.render(6000.0, 12000.0, 512).size() == 512)
	_test_physical_telemetry_sync()

	if _artifacts:
		_write_wav("glow_2t_full_fire.wav", two_t)
		_write_wav("glow_4t_full_fire.wav", four_t)
		_write_wav("glow_2t_rich_half_fire.wav", rich_two_t)
		_write_wav("glow_2t_throttle_cut.wav", cut)
		_write_wav("glow_2t_restart.wav", restarted)
	if _native_capture:
		await _capture_native_scenario()
	if _artifacts:
		print("WAV artifacts: %s" % ", ".join(_artifact_paths))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _bounded(samples: PackedVector2Array) -> bool:
	for sample: Vector2 in samples:
		if not is_finite(sample.x) or not is_finite(sample.y) or absf(sample.x) > 1.0 or absf(sample.y) > 1.0:
			return false
	return true


func _worst_difference(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.size() != b.size():
		return INF
	var worst: float = 0.0
	for i: int in a.size():
		worst = maxf(worst, absf(a[i].x - b[i].x))
	return worst


func _test_physical_telemetry_sync() -> void:
	var voice := GlowVoice.new()
	var accepted: Dictionary = _telemetry("glow_2t")
	accepted.merge({
		"phase_revolutions": 0.25, "opportunity_count": 20, "fire_count": 8,
		"firing_accumulator": 0.23, "fuel_kg": 0.5, "sample_tick": 100,
		"audio_queue_frames": 2205.0,
	}, true)
	voice.render_telemetry(accepted, 1)
	var expected_phase: float = 20.25 + 100.0 * 0.1 + 100.0 / GlowVoice.RATE
	_check("physical phase uses cycle count plus normalized crank phase and queued lead",
		absf(voice._shaft_phase_cycles - expected_phase) < 1e-10,
		"got %.12f, expected %.12f" % [voice._shaft_phase_cycles, expected_phase])
	var expected_accumulator: float = fposmod(0.23 + 10.0 * 1.0, 1.0)
	_check("audio missed-fire scheduling starts from the accepted physical accumulator",
		absf(voice._fraction_accumulator - expected_accumulator) < 1e-10,
		"got %.12f, expected %.12f" % [voice._fraction_accumulator, expected_accumulator])

	var modulated: Dictionary = accepted.duplicate(true)
	modulated.merge({
		"phase_revolutions": 0.4, "opportunity_count": 24, "fire_count": 9,
		"firing_accumulator": 0.61, "firing_fraction": 0.25,
		"sample_tick": 101, "audio_queue_frames": 0.0,
	}, true)
	voice.render_telemetry(modulated, 1)
	_check("new accepted snapshot reanchors phase after RPM/firing modulation",
		absf(voice._shaft_phase_cycles - (24.4 + 100.0 / GlowVoice.RATE)) < 1e-10,
		"got %.12f" % voice._shaft_phase_cycles)
	_check("new accepted snapshot restores its accumulator instead of retaining audio history",
		absf(voice._fraction_accumulator - 0.61) < 1e-10, "got %.12f" % voice._fraction_accumulator)

	var cut_snapshot: Dictionary = _telemetry("glow_2t", false, 0.4)
	cut_snapshot.merge({
		"phase_revolutions": 0.45, "opportunity_count": 20, "fire_count": 8,
		"firing_accumulator": 0.2, "fuel_kg": 0.5, "sample_tick": 200,
	}, true)
	var no_fire_snapshot: Dictionary = cut_snapshot.duplicate(true)
	no_fire_snapshot["fire_count"] = 0
	var cut_voice := GlowVoice.new()
	var no_fire_voice := GlowVoice.new()
	var cut_samples: PackedVector2Array = cut_voice.render_telemetry(cut_snapshot, 256)
	var no_fire_samples: PackedVector2Array = no_fire_voice.render_telemetry(no_fire_snapshot, 256)
	_check("a cut gates the accepted successful-fire cycle while shaft and prop layers remain",
		_worst_difference(cut_samples, no_fire_samples) < 1e-10 and _rms(_mono(cut_samples)) > 0.01,
		"RMS %.5f, mechanical difference %s" % [_rms(_mono(cut_samples)), String.num_scientific(_worst_difference(cut_samples, no_fire_samples))])

	var restart: Dictionary = cut_snapshot.duplicate(true)
	restart["running"] = true
	restart["sample_tick"] = 201
	cut_voice.render_telemetry(restart, 1)
	_check("restart after a cut waits for a new accepted opportunity before combustion",
		not cut_voice._opportunity_fires and absf(cut_voice._fraction_accumulator - 0.2) < 1e-10)
	restart.merge({
		"phase_revolutions": 0.002, "opportunity_count": 21, "fire_count": 8,
		"firing_accumulator": 0.6, "sample_tick": 202,
	}, true)
	cut_voice.render_telemetry(restart, 1)
	_check("restart reconciliation honors a missed accepted firing opportunity", not cut_voice._opportunity_fires
		and absf(cut_voice._fraction_accumulator - 0.6) < 1e-10)
	restart.merge({
		"phase_revolutions": 0.002, "opportunity_count": 22, "fire_count": 9,
		"firing_accumulator": 0.0, "sample_tick": 203,
	}, true)
	cut_voice.render_telemetry(restart, 1)
	_check("restart resumes combustion only after physics reports a successful fire",
		cut_voice._opportunity_fires and absf(cut_voice._fraction_accumulator) < 1e-10)


func _write_wav(name: String, samples: PackedFloat32Array) -> void:
	var directory: String = OS.get_user_data_dir().path_join("glow_audio_artifacts")
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join(name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("write %s" % name, false, error_string(FileAccess.get_open_error()))
		return
	var data_bytes: int = samples.size() * 2
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data_bytes)
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(int(GlowVoice.RATE))
	file.store_32(int(GlowVoice.RATE) * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_bytes)
	for sample: float in samples:
		var signed_sample: int = clampi(roundi(sample * 32767.0), -32768, 32767)
		file.store_16(signed_sample & 0xffff)
	file.close()
	_artifact_paths.append(path)
	_check("write %s" % name, FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).size() == 44 + data_bytes, path)


func _capture_native_scenario() -> void:
	root.audio_listener_enable_3d = true
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0.0, 0.0, 20.0)
	camera.make_current()
	var listener := AudioListener3D.new()
	camera.add_child(listener)
	listener.make_current()
	var soundscape := Soundscape.new()
	root.add_child(soundscape)
	# SceneTree._initialize runs before the root has entered its first frame. Let
	# child _ready callbacks and AudioServer buses settle before configuring audio.
	await process_frame
	soundscape.configure({}, "glow_prop", 4102026, "glow_2t")
	_check("explicit glow profile suppresses legacy motor/prop loops while retaining airframe", soundscape.voices[0].stream == null and soundscape.voices[1].stream == null and soundscape.voices[2].stream != null)
	var aircraft_bus: int = AudioServer.get_bus_index(soundscape._bus_names[1])
	var capture := AudioEffectCapture.new()
	AudioServer.add_bus_effect(aircraft_bus, capture)
	var phase_revolutions: float = 0.0
	var full: PackedVector2Array = await _capture_segment(soundscape, capture, "glow_2t", true, 1.0, 0.8, phase_revolutions, 0)
	phase_revolutions += 100.0 * 0.8
	var cut: PackedVector2Array = await _capture_segment(soundscape, capture, "glow_2t", false, 1.0, 0.4, phase_revolutions, 80)
	phase_revolutions += 100.0 * 0.4
	var restart: PackedVector2Array = await _capture_segment(soundscape, capture, "glow_2t", true, 1.0, 0.8, phase_revolutions, 80)
	var native_rate: float = float(AudioServer.get_mix_rate())
	var full_mono: PackedFloat32Array = _mono(full)
	var cut_mono: PackedFloat32Array = _mono(cut)
	var restart_mono: PackedFloat32Array = _mono(restart)
	_check("native AudioEffectCapture receives procedural generator PCM", full_mono.size() > int(native_rate * 0.5), "captured %d frames at %d Hz" % [full_mono.size(), int(native_rate)])
	var native_full_100_order: float = _band_amplitude(full_mono, 95.0, 105.0, native_rate)
	var native_full_50_order: float = _band_amplitude(full_mono, 45.0, 55.0, native_rate)
	_check("native 2T generator output has the 100 Hz order-1 line", native_full_100_order > 1.5 * maxf(native_full_50_order, 1e-9),
		"100 Hz band %s vs 50 Hz band %s" % [String.num_scientific(native_full_100_order), String.num_scientific(native_full_50_order)])
	var native_full_100: float = _band_amplitude(full_mono, 95.0, 105.0, native_rate)
	var native_cut_100: float = _band_amplitude(cut_mono, 95.0, 105.0, native_rate)
	_check("native throttle cut keeps shaft/prop sound and lowers the combustion line", _rms(cut_mono) > 1e-5 and _power_at_rate(cut_mono, 200.0, native_rate) > 0.0 and native_full_100 > 1.5 * maxf(native_cut_100, 1e-9), "cut RMS %.7f; 100 Hz band full=%s cut=%s" % [_rms(cut_mono), String.num_scientific(native_full_100), String.num_scientific(native_cut_100)])
	var native_restart_100: float = _band_amplitude(restart_mono, 95.0, 105.0, native_rate)
	var native_restart_50: float = _band_amplitude(restart_mono, 45.0, 55.0, native_rate)
	_check("native restart restores the 100 Hz combustion line", native_restart_100 > 1.5 * maxf(native_restart_50, 1e-9),
		"100 Hz band %s vs 50 Hz band %s; RMS %.7f" % [String.num_scientific(native_restart_100), String.num_scientific(native_restart_50), _rms(restart_mono)])
	soundscape.glow_family = "glow_4t"
	var four_t: PackedVector2Array = await _capture_segment(soundscape, capture, "glow_4t", true, 1.0, 0.8, phase_revolutions + 80.0, -1)
	var four_t_mono: PackedFloat32Array = _mono(four_t)
	var four_t_50: float = _band_amplitude(four_t_mono, 45.0, 55.0, native_rate)
	var four_t_100: float = _band_amplitude(four_t_mono, 95.0, 105.0, native_rate)
	_check("native true 4T output exposes the 50 Hz exhaust/cam order", four_t_50 > 1.25 * maxf(four_t_100, 1e-9), "50 Hz %s vs 100 Hz %s" % [String.num_scientific(four_t_50), String.num_scientific(four_t_100)])
	if _artifacts:
		_write_stereo_wav("native_glow_2t_full_cut_restart_full.wav", full, native_rate)
		_write_stereo_wav("native_glow_2t_throttle_cut.wav", cut, native_rate)
		_write_stereo_wav("native_glow_2t_restart.wav", restart, native_rate)
		_write_stereo_wav("native_glow_4t_full_fire.wav", four_t, native_rate)
	var capture_bus_index: int = AudioServer.get_bus_index(soundscape._bus_names[1])
	var capture_effect_index: int = AudioServer.get_bus_effect_count(capture_bus_index) - 1
	if capture_effect_index >= 0:
		AudioServer.remove_bus_effect(capture_bus_index, capture_effect_index)
	root.remove_child(soundscape)
	soundscape.free()
	root.remove_child(camera)
	camera.free()
	await process_frame
	# Let the audio mix thread observe stop/free before this short-lived test exits.
	await create_timer(0.15).timeout


func _capture_segment(soundscape: Node, capture: AudioEffectCapture, family: String, running: bool,
		firing_fraction: float, seconds: float, phase_revolutions: float, initial_fire_count: int) -> PackedVector2Array:
	var captured := PackedVector2Array()
	var steps: int = ceili(seconds * 60.0)
	var cycle_revolutions: int = GlowVoice.cycle_revolutions(family)
	var initial_opportunity: int = floori(phase_revolutions / float(cycle_revolutions))
	var fire_base: int = initial_fire_count if initial_fire_count >= 0 else initial_opportunity
	for frame: int in steps:
		var elapsed: float = float(frame) / 60.0
		var unwrapped_phase: float = phase_revolutions + elapsed * 100.0
		var opportunity_count: int = floori(unwrapped_phase / float(cycle_revolutions))
		var fire_count: int = fire_base + (opportunity_count - initial_opportunity) if running else fire_base
		var glow: Dictionary = {
			"family": family, "rpm": 6000.0, "max_rpm": 12000.0,
			"running": running, "firing_fraction": firing_fraction,
			"phase_revolutions": fposmod(unwrapped_phase, float(cycle_revolutions)),
			"opportunity_count": opportunity_count, "fire_count": fire_count,
			"firing_accumulator": 0.0, "fuel_kg": 0.5, "sample_tick": _native_tick,
			"blade_count": 2, "load": 0.65, "throttle": 0.7,
		}
		_native_tick += 1
		var snapshot: Dictionary = {
			"rpm": 6000.0, "max_rpm": 12000.0, "load": 0.65, "throttle": 0.7,
			"running": running, "blades": 2, "kind": "glow_prop", "airspeed": 0.0,
			"wind_speed": 0.0, "wind_direction": Vector3.RIGHT,
			"source": Vector3.ZERO, "listener": Vector3(0.0, 0.0, 20.0),
			"source_velocity": Vector3.ZERO, "sound_speed": 343.0,
			"paused": false, "sun_elevation": 0.0, "glow": glow,
		}
		soundscape.update_sound(snapshot, 1.0 / 60.0)
		await create_timer(1.0 / 60.0).timeout
		var available: int = capture.get_frames_available()
		if available > 0:
			captured.append_array(capture.get_buffer(available))
	var remaining: int = capture.get_frames_available()
	if remaining > 0:
		captured.append_array(capture.get_buffer(remaining))
	return captured


func _write_stereo_wav(name: String, samples: PackedVector2Array, sample_rate: float) -> void:
	var directory: String = OS.get_user_data_dir().path_join("glow_audio_artifacts")
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join(name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("write %s" % name, false, error_string(FileAccess.get_open_error()))
		return
	var data_bytes: int = samples.size() * 4
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data_bytes)
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(2)
	file.store_32(int(sample_rate))
	file.store_32(int(sample_rate) * 4)
	file.store_16(4)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_bytes)
	for sample: Vector2 in samples:
		var left: int = clampi(roundi(sample.x * 32767.0), -32768, 32767)
		var right: int = clampi(roundi(sample.y * 32767.0), -32768, 32767)
		file.store_16(left & 0xffff)
		file.store_16(right & 0xffff)
	file.close()
	_artifact_paths.append(path)
	_check("write %s" % name, FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).size() == 44 + data_bytes, path)
