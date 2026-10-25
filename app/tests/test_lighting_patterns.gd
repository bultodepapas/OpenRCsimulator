extends SceneTree

const Patterns := preload("res://render/lighting/lighting_patterns.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	var breath := {
		"id": "breath",
		"palette": ["#808080"],
		"period_ticks": 240,
		"phase_turns": 0.25,
		"floor": 0.2,
		"duty": 0.5,
		"reverse": false,
		"segments": 1,
	}
	var breath_color := Patterns.sample(breath, 0.0, 0.0)
	var gray_linear := _to_linear(Color("#808080").r)
	_check("breath phase_turns shift temporal phase", absf(_to_linear(breath_color.r) / gray_linear - 0.6) < 0.002)

	var pulse := breath.duplicate(true)
	pulse["id"] = "pulse"
	pulse["phase_turns"] = 0.0
	pulse["floor"] = 0.0
	var pulse_shifted := pulse.duplicate(true)
	pulse_shifted["phase_turns"] = 0.25
	var pulse_unshifted_color := Patterns.sample(pulse, 0.28, 0.0)
	var pulse_shifted_color := Patterns.sample(pulse_shifted, 0.28, 0.0)
	_check("pulse phase_turns shift temporal phase", pulse_unshifted_color.r > pulse_shifted_color.r + 0.4)

	var sequence := [
		{"id": "quiet", "duration_ticks": 960, "pattern": {"id": "breath", "palette": ["#FF0000"], "period_ticks": 960, "phase_turns": 0.0, "floor": 0.2, "duty": 0.5}, "zone_ids": ["strip_right"], "effect_anchor_ids": []},
		{"id": "chase", "duration_ticks": 960, "pattern": {"id": "wave", "palette": ["#FF0000", "#0000FF"], "period_ticks": 960, "phase_turns": 0.0, "floor": 1.0, "duty": 0.5}, "zone_ids": ["strip_left"], "effect_anchor_ids": ["vfx_tip_left"]},
	]
	var sequence_pattern := {"id": "sequence", "palette": ["#FFFFFF"], "period_ticks": 240, "phase_turns": 0.0, "floor": 1.0, "duty": 0.5, "reverse": false, "segments": 1}
	var left_state := Patterns.resolve(sequence_pattern, 5.5, sequence, "strip_left")
	_check("sequence resolves local cue phase", int(left_state.cue_index) == 1 and is_equal_approx(float(left_state.cue_start_seconds), 4.0) and is_equal_approx(float(left_state.phase), 0.375))
	var right_state := Patterns.resolve(sequence_pattern, 5.5, sequence, "strip_right")
	_check("untargeted cue zone stays steady", str(right_state.pattern.id) == "steady" and is_zero_approx(float(right_state.phase)))
	var empty_state := Patterns.resolve(sequence_pattern, 2.0, [], "strip_left")
	_check("empty sequence has bounded steady fallback", str(empty_state.pattern.id) == "steady" and is_zero_approx(float(empty_state.phase)))
	var later_cycle := Patterns.sequence_state(sequence, 8.5)
	_check("sequence clock reports cycle and cue start", int(later_cycle.sequence_cycle) == 1 and is_equal_approx(float(later_cycle.cue_start_seconds), 8.0))

	var wave := {"id": "wave", "palette": ["#FF0000", "#0000FF"], "period_ticks": 240, "phase_turns": 0.25, "floor": 1.0, "duty": 0.5, "reverse": false, "segments": 1}
	var wave_color := Patterns.sample(wave, 0.0, 0.0)
	_check("CPU wave interpolation is linear-RGB", absf(_to_linear(wave_color.r) - 0.5) < 0.002 and absf(_to_linear(wave_color.b) - 0.5) < 0.002)

	var reactive := Patterns.reactive_multiplier({"source": "throttle", "gain": 0.5}, {"throttle": 0.8})
	_check("reactive multiplier uses bounded normalized input", is_equal_approx(float(reactive.multiplier), 1.4) and bool(reactive.available))
	var missing := Patterns.reactive_multiplier({"source": "roll_rate", "gain": 0.2}, {})
	_check("missing reactive input preserves base pattern", not bool(missing.available) and is_equal_approx(float(missing.multiplier), 1.0))

	for pattern_id: String in Patterns.PATTERN_IDS:
		var pattern := {"id": pattern_id, "palette": ["#20DFFF", "#794CFF", "#FF38A8"], "period_ticks": 960, "phase_turns": 0.17, "floor": 0.18, "duty": 0.42, "reverse": true, "segments": 16}
		var color: Color = Patterns.sample(pattern, 1.37, 0.31, sequence, "strip_left")
		_check("pattern sample stays finite: %s" % pattern_id, color.r >= 0.0 and color.r <= 1.0 and color.g >= 0.0 and color.g <= 1.0 and color.b >= 0.0 and color.b <= 1.0)

	print("lighting patterns: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label)
	if not ok:
		_failures += 1


func _to_linear(value: float) -> float:
	return value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4)
