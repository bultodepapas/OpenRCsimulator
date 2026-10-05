# D6a: the radio reader's rules, as a pure state machine (no Input, no device).
# Run: godot --headless --path . --script res://tests/test_rc_input.gd
extends SceneTree

const RcInput := preload("res://input/rc_input.gd")
const INFO := { guid = "03000000091200004f54000000000000", name = "EdgeTX RadioMaster TX16S", vendor_id = 0x1209, product_id = 0x4f54 }

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## A connected radio whose axes read `values` (axis index → value; others 0).
func _radio(values: Dictionary, moved: Array) -> RcInput:
	var r := RcInput.new()
	r.connect_device(3, INFO)
	for axis in moved:
		r.on_motion(3, axis, values.get(axis, 0.0))
	r.poll(func(_device: int, axis: int) -> float: return values.get(axis, 0.0))
	return r


func _initialize() -> void:
	# Identity for a saved calibration.
	var r := _radio({}, [])
	_check("device key = guid|vid:pid|name", r.device_key == "03000000091200004f54000000000000|1209:4f54|EdgeTX RadioMaster TX16S", r.device_key)

	# Mapping (AETR, EdgeTX Classic): axis 0 roll, 1 pitch (inverted), 2 throttle, 3 yaw.
	r = _radio({ 0: 0.5, 1: -0.25, 2: -1.0, 3: 0.75 }, [0, 1, 2, 3])
	var s := r.sticks()
	_check("roll from axis 0", s.roll == 0.5, str(s))
	_check("pitch from axis 1, inverted (stick back = nose up = +)", s.pitch == 0.25, str(s))
	_check("yaw from axis 3", s.yaw == 0.75, str(s))
	_check("throttle −1 → 0 % (bipolar axis)", r.throttle_position() == 0.0)
	_check("no deadzone: a tiny deflection passes", _radio({ 0: 0.001 }, [0]).sticks().roll == 0.001)

	# Inversion is per channel.
	r = _radio({ 0: 0.5 }, [0])
	r.profile.roll.invert = true
	_check("inverted roll", r.sticks().roll == -0.5)

	# Arming: a never-moved throttle axis reads 0 = 50 % stick, and must NOT fly the engine.
	r = _radio({}, [])
	_check("never-moved throttle reads mid-stick", r.throttle_position() == 0.5)
	_check("...but stays SAFE: not armed, throttle idle", not r.armed and r.sticks().throttle == 0.0)
	r = _radio({ 2: 0.2 }, [2])
	_check("throttle seen at 60 %: still SAFE", not r.armed and r.sticks().throttle == 0.0)
	r = _radio({ 2: -1.0 }, [2])
	_check("throttle seen low: armed", r.armed)
	r.poll(func(_d: int, axis: int) -> float: return 1.0 if axis == 2 else 0.0)
	_check("armed: throttle follows the stick", r.sticks().throttle == 1.0)
	r = _radio({ 2: -0.92 }, [2])
	_check("4 % arms (limit 5 %)", r.armed)
	r = _radio({ 2: -0.88 }, [2])
	_check("6 % does not arm", not r.armed)
	r = _radio({ 2: -1.0 }, [0, 1, 3])
	_check("a low reading without a throttle event does not arm", not r.armed)

	# Unipolar throttle (an SDL gamepad trigger: 0 at rest … 1 full).
	r = _radio({ 2: 0.0 }, [2])
	r.profile.throttle_unipolar = true
	_check("unipolar: 0 → 0 %", r.throttle_position() == 0.0)
	r.poll(func(_d: int, axis: int) -> float: return 0.0)
	_check("unipolar trigger at rest arms", r.armed)
	r.poll(func(_d: int, axis: int) -> float: return 1.0 if axis == 2 else 0.0)
	_check("unipolar: 1 → 100 %", r.sticks().throttle == 1.0)
	var bipolar := _radio({ 2: 0.0 }, [2])
	_check("the same trigger read as bipolar never arms (safe failure)", not bipolar.armed and bipolar.sticks().throttle == 0.0)

	# Disconnect and reconnect.
	r = _radio({ 2: -1.0 }, [2])
	r.disconnect_device()
	_check("disconnect: disarmed, axes zeroed", not r.connected and not r.armed and r.axes[2] == 0.0)
	r.connect_device(3, INFO)
	r.poll(func(_d: int, axis: int) -> float: return 1.0 if axis == 2 else 0.0)
	_check("reconnect with the throttle high: SAFE until seen low again", not r.armed and r.sticks().throttle == 0.0)

	# Robustness: other devices and out-of-range axes are ignored; values clamp to ±1.
	r = _radio({}, [])
	r.on_motion(7, 2, -1.0)
	r.poll(func(_d: int, _a: int) -> float: return -1.0)
	_check("events from another device do not arm", not r.armed)
	r.on_motion(3, 12, 1.0)
	_check("axis ≥ 10 ignored (Godot's JoyAxis.MAX)", r.axes.size() == RcInput.AXES)
	r = _radio({ 0: 3.0 }, [0])
	_check("clamped to ±1", r.sticks().roll == 1.0)
	_check("panel: SAFE explains how to arm", "SAFE" in _radio({}, []).describe() and "low" in _radio({}, []).describe())

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
