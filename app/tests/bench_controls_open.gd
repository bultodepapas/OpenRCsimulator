## Rendered Pause → Controls benchmark at 1080p. Times are in microseconds.
## The keyboard runs first in a fresh process, followed by a fixture gamepad.
extends SceneTree

const Setup := preload("res://ui/controller_setup.gd")
const Stack := preload("res://ui/screen_stack.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")


class Registry extends RefCounted:
	signal devices_changed
	var selected := -1
	func selected_device_id(_role: String) -> int:
		return selected
	func get_devices() -> Array[Dictionary]:
		var devices: Array[Dictionary] = []
		if selected >= 0:
			devices.append({"id": selected, "name": "Fixture gamepad", "kind": "gamepad", "known": true, "connected": true})
		return devices
	func connection_generation(_id: int) -> int:
		return 1


class Store extends RefCounted:
	func load_all() -> Dictionary:
		return {"ok": true, "profiles": [], "errors": []}
	func match_profile(_device: Dictionary, _devices: Array) -> Dictionary:
		return {}


var registry := Registry.new()
var store := Store.new()
var stack: Stack
var screen: Setup
var sample: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _open(from: Control) -> void:
	var start := Time.get_ticks_usec()
	screen = Setup.new()
	var built := Time.get_ticks_usec()
	screen.configure(registry, store, registry.selected, registry.selected)
	var configured := Time.get_ticks_usec()
	stack.push("controls", screen, from)
	var pushed := Time.get_ticks_usec()
	sample.merge({"construct_us": built - start, "configure_us": configured - built, "push_us": pushed - configured})


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Controls benchmark requires a rendered display")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	stack = Stack.new(root)
	var pause := PauseMenu.new()
	stack.push("pause", pause)
	pause.controls_requested.connect(_open)
	pause.session_options_button.pressed.emit()
	for _frame in 3:
		await process_frame
	for device: int in [-1, 7]:
		registry.selected = device
		for cycle in 2:
			sample = {
				"device": device, "cycle": cycle, "window_px": [root.size.x, root.size.y],
				"renderer": RenderingServer.get_current_rendering_method(), "display": DisplayServer.get_name()
			}
			await process_frame
			var start := Time.get_ticks_usec()
			pause.controls_button.pressed.emit()
			if not stack.is_top("controls"):
				printerr("controls did not open")
				quit(1)
				return
			await RenderingServer.frame_post_draw
			sample["open_us"] = Time.get_ticks_usec() - start
			var tabs := {}
			for section: String in ["profile", "axes", "aux", "buttons", "devices"]:
				await process_frame
				start = Time.get_ticks_usec()
				screen.select_section(section)
				await RenderingServer.frame_post_draw
				tabs[section] = Time.get_ticks_usec() - start
			sample["first_tab_us"] = tabs
			print("CONTROL_SAMPLE ", JSON.stringify(sample))
			stack.pop()
			for _frame in 3:
				await process_frame
	stack.pop()
	await process_frame
	print("CONTROLS_BENCH_COMPLETE")
	quit()
