# D5: the placeholder engine sound — pitch follows rpm, no clicks between blocks, bounded amplitude.
# Run: godot --headless --path . --script res://tests/test_engine_sound.gd
extends SceneTree

const Sound := preload("res://render/engine_sound.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## Goertzel: signal power at one frequency.
func _power(x: PackedFloat32Array, freq: float, rate: float) -> float:
	var w := TAU * freq / rate
	var coeff := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for v in x:
		var s0 := v + coeff * s1 - s2
		s2 = s1
		s1 = s0
	return s1 * s1 + s2 * s2 - coeff * s1 * s2


func _initialize() -> void:
	var rate := Sound.MIX_RATE
	_check("firing frequency = rpm / 60", Sound.firing_frequency(6000.0) == 100.0 and Sound.firing_frequency(-5.0) == 0.0)

	# The buzz has its fundamental at rpm/60, not in between harmonics.
	for rpm in [2800.0, 5139.0, 11149.0]:
		var f := Sound.firing_frequency(rpm)
		var x: PackedFloat32Array = Sound.synthesize(0.0, f, 0.5, 8192)[0]
		var at_f := _power(x, f, rate)
		var off := _power(x, 1.5 * f, rate)
		_check("%d rpm: energy at %.1f Hz ≫ at 1.5×" % [rpm, f], at_f > 100.0 * off, "%s vs %s" % [String.num_scientific(at_f), String.num_scientific(off)])

	# Doubling rpm doubles the pitch.
	var lo: PackedFloat32Array = Sound.synthesize(0.0, 50.0, 0.5, 8192)[0]
	var hi: PackedFloat32Array = Sound.synthesize(0.0, 100.0, 0.5, 8192)[0]
	_check("2× rpm → the fundamental moves to 2× frequency", _power(hi, 100.0, rate) > 50.0 * _power(hi, 50.0, rate) and _power(lo, 50.0, rate) > 50.0 * _power(hi, 50.0, rate))

	# Phase-continuous: two blocks equal one long block (no clicks at block joins).
	var whole: PackedFloat32Array = Sound.synthesize(0.0, 137.0, 0.5, 2000)[0]
	var first := Sound.synthesize(0.0, 137.0, 0.5, 1200)
	var second: PackedFloat32Array = Sound.synthesize(first[1], 137.0, 0.5, 800)[0]
	var joined: PackedFloat32Array = first[0]
	joined.append_array(second)
	var worst := 0.0
	for i in 2000:
		worst = maxf(worst, absf(joined[i] - whole[i]))
	_check("blocks join without a click", worst < 1e-5, String.num_scientific(worst))

	# Never louder than requested.
	var peak := 0.0
	for v in Sound.synthesize(0.3, 186.0, 0.6, 22050)[0]:
		peak = maxf(peak, absf(v))
	_check("|sample| <= amp", peak <= 0.6 + 1e-6, str(peak))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
