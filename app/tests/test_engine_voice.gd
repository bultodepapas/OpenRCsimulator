# G3b: independent analytic, partition, state-transition, and isolation checks for the engine voice.
# Run: Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_engine_voice.gd
extends SceneTree

const Voice := preload("res://render/engine_voice.gd")
const EXPECTED_RATE := 22050.0
const EXPECTED_HARMONICS := [1.0, 0.6, 0.45, 0.3, 0.2, 0.12]
const MAX_WAVEFORM_ERROR := 1.0e-5
const MAX_STIK_RPM := 11149.0
const MAX_P51_RPM := 4951.245226
const SMOOTH_SECONDS := 0.003

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _harmonic_total() -> float:
	var total := 0.0
	for value in EXPECTED_HARMONICS:
		total += value
	return total


## Independent Nyquist rule: retain only harmonics strictly below half the sample rate.
func _oracle_harmonic_count(freq: float, rate: float) -> int:
	var retained := 0
	for i in EXPECTED_HARMONICS.size():
		if float(i + 1) * freq < rate * 0.5:
			retained += 1
		else:
			break
	return retained


func _oracle_sample(cycles: float, amp: float, retained: int) -> float:
	var sum := 0.0
	for i in retained:
		sum += EXPECTED_HARMONICS[i] * sin(TAU * float(i + 1) * cycles)
	return amp * sum / _harmonic_total()


func _check_pure_against_oracle(label: String, phase: float, freq: float, amp: float,
		frames: int, rate: float, retained: int, tolerance := MAX_WAVEFORM_ERROR) -> float:
	var actual: Array = Voice.synthesize(phase, freq, amp, frames, rate)
	var samples: PackedFloat32Array = actual[0]
	var worst := 0.0
	var worst_index := -1
	var cycles := fposmod(phase, 1.0)
	for i in samples.size():
		var expected := _oracle_sample(cycles, amp, retained)
		var error := absf(float(samples[i]) - expected)
		if error > worst:
			worst = error
			worst_index = i
		cycles = fposmod(cycles + freq / rate, 1.0)
	_check(label, worst <= tolerance,
		"worst=%s at sample %d (allowed %s)" % [String.num_scientific(worst), worst_index, String.num_scientific(tolerance)])
	return worst


func _check_pure_partition(phase: float, freq: float, amp: float, parts: Array[int]) -> void:
	var frame_count := 0
	for count in parts:
		frame_count += count
	var whole: Array = Voice.synthesize(phase, freq, amp, frame_count, EXPECTED_RATE)
	var expected: PackedFloat32Array = whole[0]
	var joined := PackedFloat32Array()
	var next_phase := phase
	for count in parts:
		var part: Array = Voice.synthesize(next_phase, freq, amp, count, EXPECTED_RATE)
		var samples: PackedFloat32Array = part[0]
		joined.append_array(samples)
		next_phase = float(part[1])
	var exact := expected.size() == joined.size()
	for i in mini(expected.size(), joined.size()):
		if expected[i] != joined[i]:
			exact = false
			break
	_check("pure oscillator partitioning is sample-exact", exact,
		"parts=%s" % str(parts))
	_check("pure oscillator partitioning preserves exact phase", float(whole[1]) == next_phase,
		"whole=%s split=%s" % [str(whole[1]), str(next_phase)])


func _all_zero(samples: PackedFloat32Array) -> bool:
	for value in samples:
		if value != 0.0:
			return false
	return true


func _all_finite(samples: PackedFloat32Array) -> bool:
	for value in samples:
		if not is_finite(value):
			return false
	return true


func _vectors_equal(left: PackedVector2Array, right: PackedVector2Array) -> bool:
	if left.size() != right.size():
		return false
	for i in left.size():
		if left[i].x != right[i].x or left[i].y != right[i].y:
			return false
	return true


func _all_finite_stereo(samples: PackedVector2Array) -> bool:
	for value in samples:
		if not is_finite(value.x) or not is_finite(value.y):
			return false
	return true


func _all_zero_stereo(samples: PackedVector2Array) -> bool:
	for value in samples:
		if value.x != 0.0 or value.y != 0.0:
			return false
	return true


func _expected_level(rpm: float, max_rpm: float) -> float:
	if rpm <= 0.0 or max_rpm <= 0.0:
		return 0.0
	return 0.15 + 0.45 * clampf(rpm / max_rpm, 0.0, 1.0)


func _pure_oracle_checks() -> void:
	# max_rpm_static and idle_rpm from jensen_ugly_stik_60.json and p51d_mustang_120.json.
	var supported_rpm := [2800.0, 6500.0, MAX_STIK_RPM, 1400.0, 3200.0, MAX_P51_RPM]
	var names := ["Stik idle", "Stik mid", "Stik static maximum", "P-51 idle", "P-51 mid", "P-51 static maximum"]
	var phases := [0.017, 0.2718281828459045, 0.9993]
	for rpm_index in supported_rpm.size():
		var rpm: float = supported_rpm[rpm_index]
		var freq := rpm / 60.0
		for phase_index in phases.size():
			var phase: float = phases[phase_index]
			var retained := _oracle_harmonic_count(freq, EXPECTED_RATE)
			_check_pure_against_oracle("%s analytic waveform, phase %d" % [names[rpm_index], phase_index],
				phase, freq, 0.73, 1024, EXPECTED_RATE, retained)

	# Around each harmonic's exact Nyquist cutoff the oracle changes its retained count.
	# This directly checks the waveform and cannot pass by reusing Voice.band/sample/level.
	var cutoff_frequencies := [1837.49, 1837.5, 2204.99, 2205.0, 2756.24, 2756.25,
		3674.99, 3675.0, 5512.49, 5512.5, 11024.5, 11025.0, 12000.0]
	for freq_value in cutoff_frequencies:
		var freq: float = freq_value
		var retained := _oracle_harmonic_count(freq, EXPECTED_RATE)
		for phase in [0.1234567, 0.723819]:
			_check_pure_against_oracle("Nyquist-truncated oracle f=%s phase=%s" % [String.num(freq, 5), String.num(phase, 6)],
				phase, freq, 0.81, 512, EXPECTED_RATE, retained)

	_check_pure_partition(0.91627, MAX_STIK_RPM / 60.0, 0.62, [1, 17, 257, 3, 1024, 91, 511])
	_check_pure_partition(0.314159, 137.125, 0.37, [137, 1200, 1, 642, 19, 3001])
	var zero_freq: Array = Voice.synthesize(2.375, 0.0, 0.8, 128, EXPECTED_RATE)
	var zero_samples: PackedFloat32Array = zero_freq[0]
	_check("zero frequency returns exact silence and normalized phase",
		zero_samples.size() == 128 and _all_zero(zero_samples) and float(zero_freq[1]) == 0.375,
		"frames=%s phase=%s" % [str(zero_samples.size()), str(zero_freq[1])])

	var invalid_cases: Array[Dictionary] = [
		{"label": "NaN phase", "phase": NAN, "freq": 100.0, "amp": 0.5, "rate": EXPECTED_RATE},
		{"label": "infinite phase", "phase": INF, "freq": 100.0, "amp": 0.5, "rate": EXPECTED_RATE},
		{"label": "NaN frequency", "phase": 0.2, "freq": NAN, "amp": 0.5, "rate": EXPECTED_RATE},
		{"label": "infinite frequency", "phase": 0.2, "freq": INF, "amp": 0.5, "rate": EXPECTED_RATE},
		{"label": "NaN amplitude", "phase": 0.2, "freq": 100.0, "amp": NAN, "rate": EXPECTED_RATE},
		{"label": "infinite amplitude", "phase": 0.2, "freq": 100.0, "amp": INF, "rate": EXPECTED_RATE},
		{"label": "zero sample rate", "phase": 0.2, "freq": 100.0, "amp": 0.5, "rate": 0.0},
		{"label": "infinite sample rate", "phase": 0.2, "freq": 100.0, "amp": 0.5, "rate": INF},
		{"label": "negative sample rate", "phase": 0.2, "freq": 100.0, "amp": 0.5, "rate": -EXPECTED_RATE},
	]
	for invalid in invalid_cases:
		var result: Array = Voice.synthesize(invalid.phase, invalid.freq, invalid.amp, 16, invalid.rate)
		var samples: PackedFloat32Array = result[0]
		_check("%s is finite silence" % invalid.label,
			samples.size() == 16 and _all_zero(samples) and is_finite(float(result[1])),
			"phase=%s samples_finite=%s" % [str(result[1]), str(_all_finite(samples))])


func _runtime_voice_checks() -> void:
	var invalid_voice_inputs: Array[Dictionary] = [
		{"label": "NaN runtime rpm", "rpm": NAN, "max_rpm": MAX_STIK_RPM},
		{"label": "infinite runtime rpm", "rpm": INF, "max_rpm": MAX_STIK_RPM},
		{"label": "NaN runtime maximum RPM", "rpm": 2800.0, "max_rpm": NAN},
	]
	for invalid in invalid_voice_inputs:
		var quiet_voice := Voice.new()
		quiet_voice.reset()
		var invalid_audio: PackedVector2Array = quiet_voice.render(invalid.rpm, invalid.max_rpm, 32)
		_check("%s produces finite silence from reset" % invalid.label,
			invalid_audio.size() == 32 and _all_finite_stereo(invalid_audio) and _all_zero_stereo(invalid_audio)
			and is_finite(quiet_voice.frequency) and is_finite(quiet_voice.amplitude) and is_finite(quiet_voice.phase))

	var up := Voice.new()
	up.reset(2800.0, MAX_STIK_RPM)
	var start_frequency: float = up.frequency
	var start_amplitude: float = up.amplitude
	var target_frequency := MAX_STIK_RPM / 60.0
	var target_amplitude := _expected_level(MAX_STIK_RPM, MAX_STIK_RPM)
	var alpha := 1.0 - exp(-1.0 / (SMOOTH_SECONDS * EXPECTED_RATE))
	var one_frame: PackedVector2Array = up.render(MAX_STIK_RPM, MAX_STIK_RPM, 1)
	var frequency_after_one: float = up.frequency
	var amplitude_after_one: float = up.amplitude
	_check("rpm-up transition advances smoothly without a one-sample jump",
		one_frame.size() == 1 and frequency_after_one > start_frequency and frequency_after_one < target_frequency
		and amplitude_after_one > start_amplitude and amplitude_after_one < target_amplitude,
		"frequency %s→%s of %s, amplitude %s→%s of %s"
		% [String.num(start_frequency, 9), String.num(frequency_after_one, 9), String.num(target_frequency, 9),
			String.num(start_amplitude, 9), String.num(amplitude_after_one, 9), String.num(target_amplitude, 9)])
	_check("first upward smoothing step matches the independent exponential rule",
		absf(frequency_after_one - (start_frequency + alpha * (target_frequency - start_frequency))) < 1.0e-10
		and absf(amplitude_after_one - (start_amplitude + alpha * (target_amplitude - start_amplitude))) < 1.0e-10)
	var upward_rest: PackedVector2Array = up.render(MAX_STIK_RPM, MAX_STIK_RPM, 2047)
	_check("upward RPM and level approach their targets monotonically",
		up.frequency > frequency_after_one and up.frequency < target_frequency
		and up.amplitude > amplitude_after_one and up.amplitude < target_amplitude
		and _all_finite(_vector_x(upward_rest)))

	var down := Voice.new()
	down.reset(MAX_STIK_RPM, MAX_STIK_RPM)
	var down_start_frequency: float = down.frequency
	var down_start_amplitude: float = down.amplitude
	var low_target_frequency := 2800.0 / 60.0
	var low_target_amplitude := _expected_level(2800.0, MAX_STIK_RPM)
	var down_first: PackedVector2Array = down.render(2800.0, MAX_STIK_RPM, 1)
	_check("rpm-down transition advances smoothly without a one-sample drop",
		down_first.size() == 1 and down.frequency < down_start_frequency and down.frequency > low_target_frequency
		and down.amplitude < down_start_amplitude and down.amplitude > low_target_amplitude)
	var down_rest: PackedVector2Array = down.render(2800.0, MAX_STIK_RPM, 2047)
	_check("downward RPM and level approach their targets monotonically",
		down.frequency < down_start_frequency and down.frequency > low_target_frequency
		and down.amplitude < down_start_amplitude and down.amplitude > low_target_amplitude
		and _all_finite(_vector_x(down_rest)))

	var whole_voice := Voice.new()
	whole_voice.reset(2800.0, MAX_STIK_RPM)
	var whole_render: PackedVector2Array = whole_voice.render(8000.0, MAX_STIK_RPM, 1793)
	var split_voice := Voice.new()
	split_voice.reset(2800.0, MAX_STIK_RPM)
	var split_render := PackedVector2Array()
	for count in [1, 512, 37, 1000, 243]:
		var block: PackedVector2Array = split_voice.render(8000.0, MAX_STIK_RPM, count)
		split_render.append_array(block)
	_check("stateful renderer is sample-exact across block partitions",
		_vectors_equal(whole_render, split_render),
		"whole=%d split=%d" % [whole_render.size(), split_render.size()])
	_check("partitioned render ends in identical frequency, level, and phase",
		whole_voice.frequency == split_voice.frequency and whole_voice.amplitude == split_voice.amplitude
		and whole_voice.phase == split_voice.phase,
		"whole=(%s,%s,%s) split=(%s,%s,%s)"
		% [str(whole_voice.frequency), str(whole_voice.amplitude), str(whole_voice.phase),
			str(split_voice.frequency), str(split_voice.amplitude), str(split_voice.phase)])

	var coast := Voice.new()
	coast.reset(MAX_STIK_RPM, MAX_STIK_RPM)
	var coast_samples: PackedVector2Array = coast.render(0.0, MAX_STIK_RPM, 22050)
	var tail_sum := 0.0
	var tail_peak := 0.0
	var tail_finite := true
	for i in range(coast_samples.size() - 2048, coast_samples.size()):
		var value := float(coast_samples[i].x)
		tail_sum += value
		tail_peak = maxf(tail_peak, absf(value))
		tail_finite = tail_finite and is_finite(value) and is_finite(coast_samples[i].y)
	var tail_mean := tail_sum / 2048.0
	_check("coast settles to finite audio with no residual DC",
		tail_finite and absf(tail_mean) < 1.0e-8 and tail_peak < 1.0e-7,
		"tail mean=%s peak=%s" % [String.num_scientific(tail_mean), String.num_scientific(tail_peak)])

	var changed := Voice.new()
	var isolated := Voice.new()
	changed.reset(2800.0, MAX_STIK_RPM)
	isolated.reset(2800.0, MAX_STIK_RPM)
	var changed_output: PackedVector2Array = changed.render(MAX_STIK_RPM, MAX_STIK_RPM, 256)
	var isolated_frequency_before: float = isolated.frequency
	var isolated_amplitude_before: float = isolated.amplitude
	var isolated_phase_before: float = isolated.phase
	var isolated_output: PackedVector2Array = isolated.render(2800.0, MAX_STIK_RPM, 256)
	var reference := Voice.new()
	reference.reset(2800.0, MAX_STIK_RPM)
	var reference_output: PackedVector2Array = reference.render(2800.0, MAX_STIK_RPM, 256)
	_check("voice phase and smoothing state are per instance",
		changed_output.size() == 256 and changed.phase != isolated.phase
		and isolated_frequency_before == 2800.0 / 60.0
		and isolated_amplitude_before == _expected_level(2800.0, MAX_STIK_RPM)
		and _vectors_equal(isolated_output, reference_output)
		and isolated.frequency == reference.frequency and isolated.amplitude == reference.amplitude
		and isolated.phase == reference.phase,
		"changed phase=%s isolated phase=%s" % [str(changed.phase), str(isolated.phase)])


func _vector_x(values: PackedVector2Array) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	output.resize(values.size())
	for i in values.size():
		output[i] = values[i].x
	return output


func _initialize() -> void:
	_pure_oracle_checks()
	_runtime_voice_checks()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
