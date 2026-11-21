# Counts production reader calls; this is not an elapsed-time or hardware latency benchmark.
extends SceneTree

const Reader := preload("res://input/rc_input.gd")
const Profile := preload("res://input/controller_profile.gd")
var axis_calls := 0
var button_calls := 0


func _axis(_device: int, _axis_id: int) -> float:
	axis_calls += 1
	return 0.0


func _button(_device: int, _button_id: int) -> bool:
	button_calls += 1
	return false


func _initialize() -> void:
	var reader := Reader.new()
	reader.connect_device(7, {name = "Synthetic gamepad", known = true, kind = "gamepad"}, Profile.defaults("gamepad", "mode2"))
	reader.confirmed_gamepad_connection = func(_id: int) -> bool: return true
	for tick in 240:
		reader.poll(_axis, 1.0 / 240.0, _button)
	var complete := reader.armed and axis_calls == 2400 and button_calls == 30720
	print("AUDIT_OBSERVATIONS ", JSON.stringify({id = "GCA-O1", ticks = 240, axis_callback_calls = axis_calls,
		button_callback_calls = button_calls, reader_ready = reader.armed,
		evidence = "Deterministic callback counts; not measured OS polling, CPU cost, FPS, or latency"}))
	print("POLL_BUDGET_AUDIT_COMPLETE ", "passed" if complete else "failed")
	quit(0 if complete else 1)
