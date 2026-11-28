extends SceneTree
## NK-6r: the native kernel's retarded_emission equals SoundscapeModel.retarded_emission bit for bit (index, alpha,
## delay, truncated) on random source histories (subsonic to supersonic motion, listeners up to 1.5 km, sound speeds
## across and beyond its clamp, any history start) and on empty, single and mismatched histories. Skips (passes)
## without the verified native library.

const Model := preload("res://audio/soundscape_model.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _native(kernel: Object, times: PackedFloat64Array, positions: PackedVector3Array, listener: Vector3, now: float,
		speed: float, start: int) -> Dictionary:
	var r: PackedFloat64Array = kernel.retarded_emission(times, positions, listener, now, speed, start)
	return {index = int(r[0]), alpha = r[1], delay = r[2], truncated = r[3] != 0.0}


func _run() -> void:
	# The verified library loads through NativeStage (a native flight does this before its audio runs).
	var status: Dictionary = load("res://sim/native_stage.gd").library_status()
	if not status.get("ok", false) or not ClassDB.class_exists(&"OpenRCNativeKernel"):
		print("NK6R_SKIP no native library")
		quit(0)
		return
	var kernel: Object = ClassDB.instantiate(&"OpenRCNativeKernel")
	if kernel == null or not kernel.has_method(&"retarded_emission"):
		print("NK6R_SKIP library without retarded_emission")
		quit(0)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 6064
	var mismatched := 0
	var interpolated := 0
	var samples := 0
	for round: int in 4000:
		var count: int = rng.randi_range(0, 400)
		var times := PackedFloat64Array()
		var positions := PackedVector3Array()
		var t: float = rng.randf_range(0.0, 3000.0)
		var p := Vector3(rng.randf_range(-800, 800), rng.randf_range(0, 300), rng.randf_range(-800, 800))
		var v: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)).normalized() \
			* [5.0, 40.0, 90.0, 400.0][rng.randi() % 4]
		for i in count:
			times.append(t)
			positions.append(p)
			t += 1.0 / 60.0 * rng.randf_range(0.5, 1.5)
			p += v / 60.0
			v += Vector3(rng.randf_range(-3, 3), rng.randf_range(-1, 1), rng.randf_range(-3, 3))
		if round % 50 == 0 and count > 1:
			positions.resize(count - rng.randi_range(1, count - 1)) # mismatched sizes
		var listener := Vector3(rng.randf_range(-1500, 1500), rng.randf_range(0, 20), rng.randf_range(-1500, 1500))
		if round % 3 == 0 and count > 0:
			listener = positions[positions.size() - 1] + Vector3(rng.randf_range(-60, 60), 1.0, rng.randf_range(-60, 60))
		var now: float = (times[count - 1] if count > 0 else t) + rng.randf_range(0.0, 0.05)
		var speed: float = [343.0, 290.0, 390.0, rng.randf_range(300.0, 380.0)][rng.randi() % 4]
		var start: int = rng.randi_range(-2, maxi(count - 1, 0) + 2) if round % 5 == 0 else 0
		var reference: Dictionary = Model.retarded_emission(times, positions, listener, now, speed, start)
		var answer := _native(kernel, times, positions, listener, now, speed, start)
		samples += 1
		interpolated += int(not reference.truncated and float(reference.alpha) > 0.0)
		if var_to_bytes(reference) != var_to_bytes(answer):
			mismatched += 1
			if mismatched <= 3:
				printerr("NK6R_MISMATCH ", reference, " vs ", answer)
	_check("native retarded emission equals the model's (%d histories, %d interpolated)" % [samples, interpolated],
		mismatched == 0 and interpolated > 1000, str(mismatched))
	print("native retarded emission: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
