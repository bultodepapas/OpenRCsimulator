# F3b: exhaust the ten-axis seen-state combinations without inspecting storage.
extends SceneTree

const Radio = preload("res://input/rc_input.gd")
const INFO: Dictionary = {name = "Fake EdgeTX"}
var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	var radio: Radio = Radio.new()
	for selection: int in 1024:
		radio.connect_device(15, INFO)
		var observed: Dictionary = {}
		# A set oracle verifies every sparse combination, including axes 0 and 9.
		for axis: int in Radio.AXES:
			if (selection & (1 << axis)) != 0:
				radio.on_motion(15, axis, 0.25)
				observed[axis] = true
		var correct: bool = true
		for axis: int in Radio.AXES:
			correct = correct and radio.has_axis_sample(axis) == observed.has(axis)
		check("independent axis history %d" % selection, correct)
		var before: PackedByteArray = radio.axes.to_byte_array()
		for axis: int in [-1, 10, 63, 64, 1024]:
			radio.on_motion(15, axis, -1.0)
			check("invalid axis neither aliases history nor writes: %d / %d" % [selection, axis], not radio.has_axis_sample(axis) and before == radio.axes.to_byte_array())
		radio.on_motion(14, 2, -1.0)
		check("other device ignored %d" % selection, before == radio.axes.to_byte_array() and radio.has_axis_sample(2) == observed.has(2))
		# Polling does not turn an unreported axis into evidence, even at low throttle.
		radio.poll(func(_id: int, _axis: int) -> float: return -1.0, 1.0 / 240.0)
		correct = not radio.armed # the actual throttle events above were high, even if polling now reads low
		for axis: int in Radio.AXES:
			correct = correct and radio.has_axis_sample(axis) == observed.has(axis)
		check("poll preserves history and safe arming %d" % selection, correct)
		radio.disconnect_device()
		radio.on_motion(15, 9, 1.0)
		correct = not radio.armed
		for axis: int in Radio.AXES:
			correct = correct and not radio.has_axis_sample(axis) and radio.axes[axis] == 0.0
		check("disconnect clears every history combination %d" % selection, correct)
	# An armed reader must continue receiving repeated and previously untouched axes.
	radio.connect_device(15, INFO)
	radio.on_motion(15, 2, -1.0)
	radio.poll(func(_id: int, _axis: int) -> float: return -1.0, 1.0 / 240.0)
	check("fixture armed", radio.armed)
	for axis: int in Radio.AXES:
		for sample: float in [-0.75, 0.0, 0.75]:
			radio.on_motion(15, axis, sample)
			check("armed reader retains latest axis %d / %s" % [axis, sample], radio.has_axis_sample(axis) and radio.axes[axis] == sample)
	# Profile replacement disarms and retains diagnostic history; fresh arming evidence is separate.
	radio.use_profile(Radio.DEFAULT_PROFILE, "fixture")
	check("profile change disarms but retains seen throttle", not radio.armed and radio.has_axis_sample(2))
	radio.poll(func(_id: int, _axis: int) -> float: return 1.0, 1.0 / 240.0)
	check("new profile high throttle remains unarmed", not radio.armed)
	radio.poll(func(_id: int, _axis: int) -> float: return -1.0, 1.0 / 240.0)
	check("new profile ignores low polling with stale event history", not radio.armed)
	radio.on_motion(15, 2, -1.0)
	radio.poll(func(_id: int, _axis: int) -> float: return -1.0, 1.0 / 240.0)
	check("new profile arms after fresh low throttle event", radio.armed)
	radio.connect_device(15, INFO)
	var clear: bool = not radio.armed
	for axis: int in Radio.AXES:
		clear = clear and not radio.has_axis_sample(axis)
	check("reused device ID begins fresh", clear)
	print("F3b: %d checks, %d failed; all 1024 axis-history combinations" % [checks, failures])
	quit(1 if failures else 0)
