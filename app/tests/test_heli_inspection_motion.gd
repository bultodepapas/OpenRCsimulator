extends SceneTree

const Motion := preload("res://render/rotor/hx700_inspection_motion.gd")
const Model := preload("res://aircraft/hx700_articulated_model.gd")
const Mechanism := preload("res://render/rotor/hx700_mechanism.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var motion := Motion.new()
	motion.set_controls(PackedFloat64Array([10, -8, 6, -15]))
	motion.set_speed(12)
	_check("changing demand does not teleport the animated pose", motion.inputs == PackedFloat64Array([0, 0, 0, 0, 0]) and motion.rpm == 0)
	motion.advance(0.25)
	# Independent closed-form step values: w=14 controls, w=6 rotor, initially at rest.
	_check("quarter-second collective follows the analytic step response", absf(motion.inputs[0] - 8.641117745995668) < 1e-12)
	# Phase reference from independent composite Simpson quadrature (10,000 panels).
	_check("rotor phase integrates the acceleration instead of using endpoint RPM", absf(motion.inputs[4] - 0.058843194994218584) < 1e-12)
	_check("rotor speed follows the independent analytic step value", absf(motion.rpm - 5.306095195547106) < 1e-12)
	var pose_before := motion.inputs.duplicate()
	var velocity_before := (motion._stage[0] - motion.inputs[0]) * Motion.CONTROL_RATE
	motion.set_controls(PackedFloat64Array([-13, 10, -10, 20]))
	_check("interrupted reversal preserves both position and velocity", motion.inputs == pose_before and (motion._stage[0] - motion.inputs[0]) * Motion.CONTROL_RATE == velocity_before)
	var maximum_error := 0.0
	var reference := _tape(1)
	for hz in [30, 60, 144]:
		var observed := _tape(hz)
		for i in reference.size():
			maximum_error = maxf(maximum_error, absf(reference[i] - observed[i]))
	_check("identical timed commands agree at 1, 30, 60 and 144 Hz including shaft phase", maximum_error < 1e-11)
	print("TIMING maximum_state_difference=", maximum_error)
	var one := Motion.new()
	var split := Motion.new()
	for item in [one, split]:
		item.set_speed(6)
		item.set_controls(PackedFloat64Array([10, 8, -5, 12]))
	one.advance(1)
	for dt in [0.001, 0.017, 0.282, 0.5, 0.2]:
		split.advance(dt)
	_check("a half-second render stall does not discard animation time", _difference(one.inputs, split.inputs) < 1e-12)
	var bounds_ok := true
	var preview := Model.load_preview()
	root.add_child(preview.root)
	var rig := Mechanism.new()
	_check("advanced geometry admits the animated trajectory", rig.configure(preview))
	var closure_ok := true
	var residual := 0.0
	var animated := Motion.new()
	animated.set_speed(12)
	for i in 960:
		if i % 48 == 0:
			var sign_value := 1.0 if (i / 48) % 2 == 0 else -1.0
			animated.set_controls(PackedFloat64Array([13 * sign_value, 10 * sign_value, -10 * sign_value, -20 * sign_value]))
		animated.advance(1.0 / 120.0)
		for axis in 4:
			bounds_ok = bounds_ok and absf(animated.inputs[axis]) <= Motion.LIMITS[axis]
		var result: Dictionary = rig.apply(animated.inputs)
		closure_ok = closure_ok and result.ok
		if result.ok:
			residual = maxf(residual, result.residual_m)
	_check("rapid full-travel reversals remain inside all four mechanical limits", bounds_ok)
	_check("all nine rods close throughout 960 animated combined poses", closure_ok and residual <= Mechanism.CLOSURE_TOLERANCE_M)
	print("ANIMATION poses=960 maximum_rod_residual_m=", residual)
	preview.root.free()
	motion = Motion.new()
	motion.inputs[4] = 12 * TAU + deg_to_rad(359)
	var unwrapped := motion.inputs[4]
	motion.set_speed(6)
	motion.seek_azimuth(1)
	_check("azimuth scrub crosses north without resetting twelve shaft revolutions", absf(motion.inputs[4] - unwrapped - deg_to_rad(2)) < 1e-12)
	_check("manual azimuth stops automatic rotation for precise inspection", motion.speed_rpm == 0 and motion.rpm == 0)
	unwrapped = motion.inputs[4]
	motion.seek_azimuth(359)
	_check("reverse azimuth scrub preserves transmission history", absf(motion.inputs[4] - unwrapped + deg_to_rad(2)) < 1e-12)
	var half_turn := Motion.new()
	half_turn.seek_azimuth(180)
	_check("antipodal forward scrub follows the positive slider direction", absf(half_turn.inputs[4] - PI) < 1e-12)
	half_turn.seek_azimuth(0)
	_check("antipodal reverse scrub retraces the same transmission path", absf(half_turn.inputs[4]) < 1e-12)
	pose_before = motion.inputs.duplicate()
	_check("invalid time and azimuth leave the accepted state unchanged", not motion.advance(NAN) and not motion.advance(-1) and not motion.seek_azimuth(INF) and motion.inputs == pose_before)
	_check("invalid controls and RPM retain the previous demand", not motion.set_controls(PackedFloat64Array([14, 0, 0, 0])) and not motion.set_controls(PackedFloat64Array([0, NAN, 0, 0])) and not motion.set_speed(-1) and not motion.set_speed(INF) and motion.demand == PackedFloat64Array([0, 0, 0, 0]))
	motion.set_smooth(false)
	motion.set_controls(PackedFloat64Array([10, -6, 4, 15]))
	motion.advance(0)
	_check("exact inspection mode applies unfiltered control poses", motion.inputs.slice(0, 4) == motion.demand)
	motion.set_speed(6)
	pose_before = motion.inputs.duplicate()
	motion.advance(0.5)
	_check("exact rotation mode integrates constant RPM", absf(motion.inputs[4] - pose_before[4] - PI / 10) < 1e-12)
	motion = Motion.new()
	motion.set_speed(12)
	motion.advance(1)
	motion.set_speed(0)
	var previous_rpm := motion.rpm
	var previous_phase := motion.inputs[4]
	var stopping_ok := true
	for i in 120:
		motion.advance(1.0 / 60)
		stopping_ok = stopping_ok and motion.rpm >= 0 and motion.inputs[4] >= previous_phase and motion.rpm <= previous_rpm + 0.01
		previous_rpm = motion.rpm
		previous_phase = motion.inputs[4]
	_check("rotor stopping remains forward and approaches rest smoothly", stopping_ok and motion.rpm < 0.001)
	print("%d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _tape(hz: int) -> PackedFloat64Array:
	var motion := Motion.new()
	var tape := [[13, 8, -10, 20, 12], [-13, -10, 10, -20, 3], [3, 0, 5, -4, 0]]
	var result := PackedFloat64Array()
	for entry: Array in tape:
		motion.set_controls(PackedFloat64Array(entry.slice(0, 4)))
		motion.set_speed(entry[4])
		for frame in hz:
			motion.advance(1.0 / hz)
		result.append_array(motion.inputs)
		result.append(motion.rpm)
	return result


func _difference(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var maximum := 0.0
	for i in a.size():
		maximum = maxf(maximum, absf(a[i] - b[i]))
	return maximum


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok " if ok else "FAIL ") + label)
