# SCENERY-PLAN SC-19a: the synthesised ambience is deterministic, quiet, seamless at its loop point and pausable.
# Tested on the samples, like engine_sound.gd: no sound card needed.
# Run: godot --headless --path . --script res://tests/test_scenery_ambience.gd
extends SceneTree

const Ambience = preload("res://scenery/ambience.gd")

var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var a := Ambience.samples(1253)
	var b := Ambience.samples(1253)
	var c := Ambience.samples(77)
	_check("one loop is RATE × LOOP_S samples", a.size() == Ambience.RATE * Ambience.LOOP_S)
	_check("the same seed gives the same samples", a == b)
	_check("another seed gives other samples", a != c)
	var peak := 0
	var sum2 := 0.0
	for v: int in a:
		peak = maxi(peak, absi(v))
		sum2 += float(v) * v
	var rms := sqrt(sum2 / a.size()) / 32768.0
	_check("normalised to −6 dBFS (peak %d)" % peak, absi(peak - 16384) <= 2)
	_check("a bed, not silence nor noise blast (RMS %.3f FS)" % rms, rms > 0.02 and rms < 0.25)
	# Seam: the last sample flows into the first like any neighbouring pair does.
	var typical := 0.0
	for i in range(1, 2000):
		typical = maxf(typical, absf(float(a[i] - a[i - 1])))
	var seam := absf(float(a[0] - a[a.size() - 1]))
	_check("the loop point is seamless (step %d ≤ the largest of 2000 neighbouring steps, %d)" % [seam, typical], seam <= typical)
	var wav := Ambience.stream(1253)
	_check("a looping 16-bit mono stream", wav.format == AudioStreamWAV.FORMAT_16_BITS and not wav.stereo and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.loop_end == a.size())
	var p := Ambience.player(1253)
	_check("the player is quiet and pausable", p.volume_db <= -12.0 and p.process_mode == Node.PROCESS_MODE_PAUSABLE)
	p.free()
	print("all scenery ambience checks passed" if _failures == 0 else "%d scenery ambience checks failed" % _failures)
	quit(1 if _failures > 0 else 0)
