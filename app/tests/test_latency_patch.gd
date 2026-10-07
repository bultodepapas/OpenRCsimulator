# F6a: physics-tick ordering, read-only flight observation and inactive states.
extends SceneTree

const Patch = preload("res://input/latency_patch.gd")
const Flight = preload("res://sim/flight_session.gd")
const Radio = preload("res://input/rc_input.gd")
signal compared

class TickHook extends Node:
	var action: Callable
	func _physics_process(_delta: float) -> void:
		action.call()

var _count: int = 0
var _failures: int = 0
var _session: Flight
var _reference: Flight
var _patch: Patch
var _raw: PackedFloat64Array = PackedFloat64Array([0, 0, -1, 0, 0, 0, 0, 0, 0, 0])
var _ticks: int = 0
var _comparing: bool = false


func check(label: String, ok: bool) -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	check("default off", Patch.options({}).ok and not Patch.options({}).enabled)
	var default: Dictionary = Patch.options({"latency-patch": true})
	check("default axis zero and bipolar midpoint", default.ok and default.axis == 0 and default.threshold == 0.0)
	check("trigger axis explicit midpoint accepted", Patch.options({"latency-patch": true, "latency-axis": "9", "latency-threshold": "0.5"}).ok)
	for key: String in ["trace", "capture", "scripted", "frametimes", "visual_pose"]:
		var args: Dictionary = {"latency-patch": true}
		args[key] = true
		check("refuses " + key, not Patch.options(args).ok)
	for bad: Variant in [true, "-1", "10", "0.1", "nan", "999999999999999999999", ""]:
		check("refuses bad axis %s" % bad, not Patch.options({"latency-patch": true, "latency-axis": bad}).ok)
	for bad: Variant in [true, "-1", "1", "1.1", "nan", "inf", "1e309", ""]:
		check("refuses bad threshold %s" % bad, not Patch.options({"latency-patch": true, "latency-threshold": bad}).ok)
	check("axis requires patch", not Patch.options({"latency-axis": "1"}).ok)
	check("threshold requires patch", not Patch.options({"latency-threshold": "0"}).ok)
	check("patch is a bare flag", not Patch.options({"latency-patch": "false"}).ok)
	var radio: Radio = Radio.new()
	check("disconnected axis is unseen", not radio.has_axis_sample(0))
	radio.connect_device(15, {name = "Fake EdgeTX"})
	radio.on_motion(14, 0, 1.0)
	radio.on_motion(15, 1, 1.0)
	check("unseen polled zero and other-device event do not count", not radio.has_axis_sample(0) and radio.has_axis_sample(1))
	check("out-of-range access is safe", not radio.has_axis_sample(-1) and not radio.has_axis_sample(10))
	radio.disconnect_device()
	radio.connect_device(15, {name = "Fake EdgeTX"})
	check("reconnect clears seen flags", not radio.has_axis_sample(1))

	_session = _flight()
	_reference = _flight()
	_patch = Patch.new()
	_patch.session = _session
	root.add_child(_patch)
	_patch._physics_process(0)
	check("connected but untouched axis is gray", not _patch.active and _patch.marker.color == Patch.INACTIVE)
	for flight: Flight in [_session, _reference]:
		flight.radio.on_motion(15, 0, -0.75)
		flight.radio.on_motion(15, 2, -1.0)
		flight.reset()
	var driver: TickHook = TickHook.new()
	driver.process_physics_priority = -2
	driver.action = func() -> void:
		if _comparing:
			_ticks += 1
			# Change the polled backend value, not radio.axes: only FlightSession may refresh that sample.
			_raw[0] = [-0.75, 0.0, 0.75][_ticks % 3]
	root.add_child(driver)
	var observer: TickHook = TickHook.new()
	observer.process_physics_priority = 2
	observer.action = func() -> void:
		if not _comparing:
			return
		check("first tick reflects latest poll %d" % _ticks, _patch.active and _patch.above == (_raw[0] >= 0.0) and _patch.sampled_tick == _session.sim.tick)
		check("complete checkpoint unchanged by marker %d" % _ticks, var_to_bytes(_session.sim.checkpoint()) == var_to_bytes(_reference.sim.checkpoint()))
		if _ticks == 240:
			_comparing = false
			compared.emit()
	root.add_child(observer)
	_comparing = true
	await compared
	for flight: Flight in [_session, _reference]:
		flight.set_physics_process(false)
		flight.sim.set_physics_process(false)
	_patch.set_physics_process(false)
	driver.free()
	observer.free()
	var before: PackedByteArray = var_to_bytes(_session.sim.checkpoint())
	var axes: PackedByteArray = _session.radio.axes.to_byte_array()
	_patch._physics_process(0)
	check("manual marker update also reads only", var_to_bytes(_session.sim.checkpoint()) == before and _session.radio.axes.to_byte_array() == axes)
	_session.radio.armed = false
	_patch._physics_process(0)
	check("throttle arming does not gate raw-axis trials", _patch.active)
	_session.hold("fixture")
	_gray("session held")
	_session.release("fixture")
	_session.sim.set_paused(false)
	_session.sim.set_paused(true)
	_gray("flight paused")
	_session.sim.set_paused(false)
	_session.input_enabled = false
	_gray("input disabled")
	_session.input_enabled = true
	_session.physics_enabled = false
	_gray("scripted physics disabled")
	_session.physics_enabled = true
	_session.calibration = RefCounted.new()
	_session.sim.set_paused(true)
	_gray("calibrating")
	check("calibration explains its pause", _patch.status == "calibrating")
	_session.calibration = null
	_session.sim.set_paused(false)
	_session.sim.fault_reason = "fixture fault"
	_gray("faulted")
	_session.sim.fault_reason = ""
	_session.crash = {fixture = true}
	_gray("crashed")
	_session.crash = {}
	_session.radio.axes[0] = NAN
	_gray("invalid raw sample")
	_session.radio.axes[0] = 0.0
	_session.radio.disconnect_device()
	_gray("disconnected")
	_session.radio.connect_device(15, {name = "Fake EdgeTX"})
	_gray("reconnect waits for fresh axis")
	_session.radio.on_motion(15, 0, 0.0)
	_patch._physics_process(0)
	check("fresh equality at threshold is white", _patch.active and _patch.marker.color == Color.WHITE)
	_session.radio.on_motion(15, 0, -0.001)
	_patch._physics_process(0)
	check("below threshold is black without hysteresis", _patch.active and _patch.marker.color == Color.BLACK)
	await process_frame
	await process_frame
	for control: Node in _patch.find_children("*", "Control", true, false):
		check("overlay ignores mouse: " + control.name, control.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	check("marker is a visible square", _patch.marker.size == Vector2(Patch.SIZE, Patch.SIZE))
	check("marker %s is inside viewport %s" % [_patch.marker.get_global_rect(), root.get_visible_rect()], root.get_visible_rect().encloses(_patch.marker.get_global_rect()))
	_patch.free()
	_session.free()
	_reference.free()
	print("F6a: %d checks, %d failed; 240 same-tick marker updates and exact checkpoint pairs" % [_count, _failures])
	quit(1 if _failures else 0)


func _flight() -> Flight:
	var flight: Flight = Flight.new()
	flight.setup()
	flight.radio.connect_device(15, {name = "Fake EdgeTX"})
	flight.read_axis = func(_id: int, axis: int) -> float: return _raw[axis]
	root.add_child(flight)
	return flight


func _gray(label: String) -> void:
	_patch._physics_process(0)
	check(label + " is inactive gray", not _patch.active and _patch.sampled_tick == -1 and _patch.marker.color == Patch.INACTIVE)
