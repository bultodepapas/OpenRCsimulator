extends SceneTree

const ControllerSetup := preload("res://ui/controller_setup.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")

const SIZES: Array[Vector2i] = [
	Vector2i(960, 540), Vector2i(1024, 576), Vector2i(1024, 768),
	Vector2i(1280, 800), Vector2i(1366, 768), Vector2i(1920, 1200),
	Vector2i(2560, 1080), Vector2i(3440, 1440), Vector2i(3840, 2160),
]

class FixtureRegistry extends RefCounted:
	signal devices_changed
	var devices: Array[Dictionary] = [{
		"id": 15, "name": "DualSense Wireless Controller with a deliberately long device name for layout verification",
		"kind": "gamepad", "known": true, "connected": true,
	}]
	func get_devices() -> Array[Dictionary]: return devices.duplicate(true)
	func selected_device_id(_role: String) -> int: return 15

class FixtureStore extends RefCounted:
	func load_all() -> Dictionary: return {"ok": true, "profiles": [], "errors": []}
	func match_profile(_device: Dictionary, _devices: Array) -> Dictionary: return {}

var failures := 0
var checks := 0
var setup: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)

func _settle() -> void:
	for frame in 3:
		await process_frame

func _check_scroll_width(section: String, tag: String) -> void:
	var scroll := setup.find_child("ControllerSetupScroll", true, false) as ScrollContainer
	var scroll_rect := scroll.get_global_rect()
	var page: Control = setup._section_pages[section]
	var stack: Array[Node] = [page]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Control:
			var control := node as Control
			if control.is_visible_in_tree():
				var rect := control.get_global_rect()
				_check("%s/%s %s stays inside the horizontal scroll viewport" % [tag, section, control.name],
					rect.position.x >= scroll_rect.position.x - 1.0 and rect.end.x <= scroll_rect.end.x + 1.0)
		for child in node.get_children():
			stack.append(child)

func _check_axis_row_labels(tag: String) -> void:
	var control_keys: Array[String] = ["axis", "deadzone", "expo", "invert"]
	var channels: Array[String] = ["roll", "pitch", "yaw", "throttle"]
	for channel_index in range(channels.size()):
		var channel: String = channels[channel_index]
		var row_label: Label = setup._axis_channel_labels[channel]
		_check("%s axis row label %s stays owned by the grid through reflow" % [tag, channel],
			row_label.get_parent() == setup.axis_grid and row_label.is_inside_tree())
		if setup._axis_layout_is_table:
			var row_start: int = setup.axis_grid.columns + channel_index * setup.axis_grid.columns
			_check("%s axis table keeps row label %s in its channel row" % [tag, channel],
				setup.axis_grid.get_child(row_start) == row_label)
			for field_index in control_keys.size():
				var key: String = control_keys[field_index]
				var control: Control = setup._axis_controls[channel][key]
				_check("%s axis table keeps %s in the %s column" % [tag, channel, key],
					setup.axis_grid.get_child(row_start + field_index + 1) == control)

func _check_layout(section: String, tag: String) -> void:
	var view := Rect2(Vector2.ZERO, Vector2(root.size))
	var panel: Rect2 = setup._settings_panel.get_global_rect()
	var footer: Rect2 = (setup.find_child("ControllerSetupFooter", true, false) as Control).get_global_rect()
	var nav: Control = setup.find_child("ControllerSections", true, false) as Control
	var nav_rect: Rect2 = nav.get_global_rect()
	var header: Control = setup.find_child("ControllerSetupHeader", true, false) as Control
	var header_rect: Rect2 = header.get_global_rect()
	_check("%s/%s panel fits the viewport" % [tag, section], view.encloses(panel))
	_check("%s/%s scaled title and Close fit the panel header" % [tag, section], panel.encloses(header_rect) and header_rect.encloses((header.get_child(0) as Control).get_global_rect()) and header_rect.encloses((header.get_child(1) as Control).get_global_rect()))
	_check("%s/%s pinned Save and Cancel fit the viewport" % [tag, section], view.encloses(footer))
	_check("%s/%s navigation fits the viewport" % [tag, section], view.encloses(nav_rect))
	_check("%s/%s Save remains visible and reachable" % [tag, section], setup.save_button.is_visible_in_tree() and view.encloses(setup.save_button.get_global_rect()))
	_check_scroll_width(section, tag)
	_check_axis_row_labels(tag)

func _run() -> void:
	var registry := FixtureRegistry.new()
	setup = ControllerSetup.new()
	setup.configure(registry, FixtureStore.new(), 15, 15)
	root.add_child(setup)
	await _settle()
	for locale in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for scale in [1.0, 2.0]:
			ScreenTheme.text_scale = scale
			setup._screen.theme = ScreenTheme.build()
			await _settle()
			for size in SIZES:
				root.size = size
				await _settle()
				var tag := "%s %d%% %dx%d" % [locale, roundi(scale * 100.0), size.x, size.y]
				for section in ["devices", "profile", "axes", "aux", "buttons"]:
					setup.select_section(section)
					await _settle()
					_check_layout(section, tag)
				_check("%s navigation wraps without clipping its buttons" % tag,
					setup._section_buttons.devices.get_global_rect().intersects(setup._section_buttons.buttons.get_global_rect()) == false)
	# Exercise the same live resize transitions as a user resizing the window.
	ScreenTheme.text_scale = 1.0
	setup._screen.theme = ScreenTheme.build()
	root.size = Vector2i(3440, 1440)
	await _settle()
	for size in [Vector2i(960, 540), Vector2i(3440, 1440)]:
		root.size = size
		await _settle()
		for section in ["devices", "profile", "axes", "aux", "buttons"]:
			setup.select_section(section)
			await _settle()
			_check_layout(section, "live resize %dx%d" % [size.x, size.y])
	for scale in [2.0, 1.0]:
		ScreenTheme.text_scale = scale
		setup._screen.theme = ScreenTheme.build()
		await _settle()
		for section in ["devices", "profile", "axes", "aux", "buttons"]:
			setup.select_section(section)
			await _settle()
			_check_layout(section, "live scale %d%%" % roundi(scale * 100.0))
	ScreenTheme.text_scale = 1.0
	TranslationServer.set_locale("en")
	var axis_row_labels: Array = setup._axis_channel_labels.values()
	setup.free()
	for label in axis_row_labels:
		_check("axis row label is released with its owning setup", not is_instance_valid(label))
	print("Controller responsive layout: %d/%d checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
