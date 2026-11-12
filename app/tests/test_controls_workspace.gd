extends SceneTree
# UI-15-UX-03/04/08: the Controls workspace in controller_setup.gd: device rail, device picture with live highlight,
# binding chips, axis gimbals and response curve, the Keyboard's read-only pages and the full-screen layout.

const ControllerSetup := preload("res://ui/controller_setup.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")

class FakeRegistry extends RefCounted:
	signal devices_changed
	var devices: Array[Dictionary] = [
		{"id": 5, "name": "Fixture radio", "raw_name": "Fixture radio", "kind": "radio", "connected": true, "serial_number": "radio-5"},
		{"id": 7, "name": "DualSense Wireless Controller", "raw_name": "DualSense Wireless Controller", "kind": "gamepad", "known": true, "connected": true},
		{"id": 9, "name": "Unplugged pad", "raw_name": "Unplugged pad", "kind": "gamepad", "known": true, "connected": false},
	]
	func get_devices() -> Array[Dictionary]: return devices.duplicate(true)
	func selected_device_id(role: String) -> int: return 5 if role == "flight" else 7
	func device_for_id(id: int) -> Dictionary:
		for device in devices:
			if device.id == id: return device.duplicate(true)
		return {}
	func connection_generation(_id: int) -> int: return 1

class FakeStore extends RefCounted:
	var radio: Dictionary
	func _init() -> void:
		radio = ControllerProfile.defaults("radio", "radio_custom")
		radio["name"] = "Fixture radio"
		radio["aux"] = {"gear": {"type": "switch", "buttons": [2, 3, 4], "invert": false, "label": "SB"}}
		radio["actions"]["camera_cycle"] = {"type": "button", "button": 8}
		radio["association"] = {"serial_number": "radio-5"}
	func load_all() -> Dictionary: return {"ok": true, "profiles": [radio.duplicate(true)], "errors": []}
	func match_profile(device: Dictionary, _devices: Array) -> Dictionary:
		return radio.duplicate(true) if str(device.get("serial_number", "")) == "radio-5" else {}
	func save_profile(profile: Dictionary) -> Dictionary: return {"ok": true, "profile": profile}

var checks := 0
var failures := 0
var axis_value := 0.4
var axis_reads := 0
var pressed: Array[int] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)

func _settle(frames := 4) -> void:
	for frame in frames:
		await process_frame

func _axis(_id: int, _axis_index: int) -> float:
	axis_reads += 1
	return axis_value

func _button(_id: int, button: int) -> bool:
	return pressed.has(button)

func _open() -> Node:
	var setup := ControllerSetup.new()
	setup.axis_preview_provider = _axis
	setup.button_preview_provider = _button
	setup.configure(FakeRegistry.new(), FakeStore.new(), 5, 7)
	root.add_child(setup)
	await _settle(5)
	return setup

func _run() -> void:
	TranslationServer.set_locale("en")
	root.size = Vector2i(1920, 1080)
	await _test_rail_and_picture()
	await _test_highlight_chips_and_live_views()
	await _test_keyboard_read_only()
	await _test_layout()
	print("Controls workspace: %d/%d checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func _test_rail_and_picture() -> void:
	var setup: Node = await _open()
	var workspace: Node = setup.workspace
	_check("rail lists connected controllers, then the Keyboard", workspace.card_ids() == [5, 7, -1], str(workspace.card_ids()))
	var radio_card: Button = workspace.card_for(5)
	_check("selected radio card is selected, calibrated and flight", radio_card.is_selected()
		and Array(radio_card.statuses()) == ["connected", "calibrated", "flight"], str(radio_card.statuses()))
	_check("menu card names its role", Array((workspace.card_for(7) as Button).statuses()) == ["connected", "menus"])
	_check("Keyboard card is always present and connected", Array((workspace.card_for(-1) as Button).statuses()) == ["connected"])
	_check("picture shows the selected radio", workspace.device_kind() == "radio" and workspace.picture.has_control("button:8"))
	_check("clean draft before any activation", not setup.has_unsaved_changes())
	(workspace.card_for(7) as Button).pressed.emit()
	await _settle()
	_check("activating a card selects the draft flight controller", setup.selected_flight_device_id() == 7
		and setup.flight_device_picker.get_item_id(setup.flight_device_picker.selected) == 7)
	_check("activation marks unsaved changes", setup.has_unsaved_changes())
	_check("cards follow the new selection", (workspace.card_for(7) as Button).is_selected()
		and not (workspace.card_for(5) as Button).is_selected())
	var device: Dictionary = setup._device_for_id(7)
	_check("picture follows the gamepad and its glyph family", workspace.device_kind() == "gamepad"
		and workspace.picture.device_family() == ControllerPrompts.resolve_family("auto", device))
	var via_picker: Node = await _open()
	for index in via_picker.flight_device_picker.item_count:
		if via_picker.flight_device_picker.get_item_id(index) == 7:
			via_picker.flight_device_picker.select(index)
			via_picker._on_flight_device_selected(index)
	var card_draft: Dictionary = setup.current_profile()
	var picker_draft: Dictionary = via_picker.current_profile()
	card_draft.erase("profile_id") # a new default profile draws its own UUID
	picker_draft.erase("profile_id")
	_check("card and picker produce the same draft", card_draft == picker_draft
		and via_picker.selected_flight_device_id() == setup.selected_flight_device_id()
		and via_picker.has_unsaved_changes() == setup.has_unsaved_changes())
	via_picker.free()
	setup.flight_device_picker.select(0)
	setup._on_flight_device_selected(0)
	await _settle()
	_check("picker selection updates the rail", (workspace.card_for(-1) as Button).is_selected()
		and workspace.device_kind() == "keyboard")
	setup.free()
	await process_frame

func _test_highlight_chips_and_live_views() -> void:
	var setup: Node = await _open()
	var workspace: Node = setup.workspace
	var picture: Control = workspace.picture
	setup.select_section("buttons")
	await _settle()
	(setup.find_child("Remap_camera_cycle", true, false) as Control).grab_focus()
	await _settle()
	_check("focused action row highlights its button", picture.highlighted_id == "button:8", picture.highlighted_id)
	setup.select_section("aux")
	await _settle()
	(setup._aux_controls.gear.type as Control).grab_focus()
	await _settle()
	_check("focused AUX row highlights its switch", picture.highlighted_id == "button:2", picture.highlighted_id)
	setup.select_section("axes")
	await _settle()
	(setup._axis_controls.pitch.axis as SpinBox).get_line_edit().grab_focus()
	await _settle()
	var pitch_axis := int(setup.current_profile().pitch.axis)
	_check("focused axis row highlights its gimbal axis", picture.highlighted_id == "axis:%d" % pitch_axis, picture.highlighted_id)
	_check("focused axis row selects the response curve", setup._curve_channel == "pitch")
	workspace.set_hover_control("button:3")
	_check("hover wins over focus", picture.highlighted_id == "button:3")
	workspace.set_hover_control("")
	_check("hover end restores the focused row", picture.highlighted_id == "axis:%d" % pitch_axis)
	var chip: Control = setup.find_child("BindingChip_camera_cycle", true, false)
	pressed = [8]
	workspace.sample()
	_check("pressing the bound control lights the picture and glows its chip", picture.is_button_pressed(8) and chip.live_pressed)
	pressed = []
	workspace.sample()
	_check("release clears the glow", not chip.live_pressed and not picture.is_button_pressed(8))
	setup._draft_profile.actions["restart_flight"] = {"type": "button", "button": 8}
	setup._action_bindings = ControllerActions.effective_bindings(setup._draft_profile, setup.action_capabilities)
	setup._update_action_controls()
	var restart_chip: Control = setup.find_child("BindingChip_restart_flight", true, false)
	_check("chips badge actions the draft reports in conflict", chip.conflict and restart_chip.conflict)
	_check("former binding nodes stay for callers but are hidden", not (setup.find_child("Binding_camera_cycle", true, false) as Control).visible
		and not (setup.find_child("BindingGlyph_camera_cycle", true, false) as Control).visible)
	# Gimbals and curve: the four channel reads of the visible tab, nothing else.
	setup.set_process(false)
	setup.select_section("devices")
	var gimbal: Control = setup._axis_gimbals[1]
	var before: Vector2 = gimbal.stick()
	axis_value = -0.7
	setup._preview_clock = 0.0
	setup._process(0.08)
	_check("hidden Flight axes tab leaves the gimbals alone", gimbal.stick() == before)
	axis_reads = 0
	setup.select_section("axes")
	_check("opening the tab reads only the four channels", axis_reads == 4, str(axis_reads))
	_check("gimbals move with the conditioned values", gimbal.stick() != before and gimbal.is_live())
	_check("curve dot is live for the focused channel", setup._response_curve.is_live())
	var curve_out: float = setup._response_curve.live_point().y
	_check("curve dot equals the profile's conditioned output", absf(curve_out
		- ControllerProfile.channel_value(-0.7, "pitch", setup.current_profile())) < 0.002, str(curve_out))
	setup.set_process(true)
	# The picture polls only while visible.
	await _settle()
	var samples: int = workspace.samples
	setup.visible = false
	await _settle(8)
	_check("hidden Controls does not poll the picture", workspace.samples == samples)
	setup.visible = true
	await _settle(8)
	_check("shown Controls polls the picture again", workspace.samples > samples)
	setup.free()
	await process_frame

func _test_keyboard_read_only() -> void:
	var setup: Node = await _open()
	(setup.workspace.card_for(-1) as Button).pressed.emit()
	await _settle()
	for section: String in ["profile", "axes", "aux", "buttons"]:
		setup.select_section(section, true)
		await _settle()
		var block: Control = setup.find_child("KeyboardReadOnly_%s" % section, true, false)
		var editable: Control = setup.find_child("EditablePage_%s" % section, true, false)
		_check("%s shows the Keyboard read-only" % section, block.is_visible_in_tree() and not editable.visible)
		_check("%s note says keys cannot be remapped" % section,
			(setup.find_child("KeyboardReadOnlyNote_%s" % section, true, false) as Label).text == "Keyboard keys cannot be remapped yet.")
		_check("%s keeps focus on a visible control" % section, root.gui_get_focus_owner() != null
			and root.gui_get_focus_owner().is_visible_in_tree())
	_check("keyboard picture shows the key map", setup.workspace.device_kind() == "keyboard"
		and setup.workspace.picture.has_control("key:%d" % KEY_W))
	_check("keyboard map lists the flight keys", setup.find_child("KeyboardKeys_axes", true, false).get_child_count() == 2)
	(setup.workspace.card_for(5) as Button).pressed.emit()
	await _settle()
	setup.select_section("buttons", true)
	await _settle()
	_check("a controller restores its editors", (setup.find_child("EditablePage_buttons", true, false) as Control).visible
		and setup.action_filter.has_focus())
	setup.free()
	await process_frame

func _no_focus_trap(setup: Node) -> void:
	var start: Control = setup.workspace.card_for(5)
	start.grab_focus()
	var seen := {}
	var current: Control = start
	var reached_tabs := false
	var reached_save := false
	var order: Array[String] = []
	for step in 200:
		current = current.find_next_valid_focus()
		if current == null or seen.has(current):
			break
		seen[current] = true
		order.append(str(current.name))
		reached_tabs = reached_tabs or current == setup._section_buttons.buttons
		reached_save = reached_save or current == setup.save_button
	_check("Tab from the rail reaches the tabs and Save, then returns to the rail", reached_tabs and reached_save
		and current != null and setup.workspace.rail.is_ancestor_of(current), str(order))

func _test_layout() -> void:
	var setup: Node = await _open()
	await _no_focus_trap(setup)
	for config: Array in [[Vector2i(1920, 1080), 1.0], [Vector2i(2560, 1440), 1.0], [Vector2i(3840, 2160), 1.0],
			[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 2.0]]:
		var size: Vector2i = config[0]
		var scale: float = config[1]
		ScreenTheme.text_scale = scale
		setup._screen.theme = ScreenTheme.build()
		root.size = size
		await _settle()
		var tag := "%dx%d@%d%%" % [size.x, size.y, roundi(scale * 100.0)]
		var view := Rect2(Vector2.ZERO, Vector2(size))
		var panel: Rect2 = setup._settings_panel.get_global_rect()
		_check("%s workspace fits the viewport" % tag, view.grow(1.0).encloses(panel), str(panel))
		var wide: bool = size.x / scale >= 1500.0 and size.y / scale >= 880.0
		_check("%s rail and picture shown only with room" % tag, setup.workspace.rail.visible == wide
			and setup.workspace.picture_panel.visible == wide)
		if size == Vector2i(1920, 1080) and scale == 1.0:
			_check("1080p uses a 48 px safe inset", absf(panel.position.x - 48.0) < 1.0 and absf(panel.size.x - 1824.0) < 1.0)
		var regions: Array[Control] = [setup.workspace.rail, setup.workspace.picture_panel, setup._page_column]
		var previous_end := -INF
		for region in regions:
			if not region.is_visible_in_tree():
				continue
			var rect := region.get_global_rect()
			_check("%s %s stays inside the panel" % [tag, region.name], panel.grow(1.0).encloses(rect), str(rect))
			_check("%s %s does not overlap its neighbour" % [tag, region.name], rect.position.x >= previous_end - 1.0)
			previous_end = rect.end.x
		for section: String in ["devices", "profile", "axes", "aux", "buttons"]:
			setup.select_section(section)
			await _settle(3)
			var scroll_rect: Rect2 = (setup.find_child("ControllerSetupScroll", true, false) as Control).get_global_rect()
			var overflow := ""
			var stack: Array[Node] = [setup._section_pages[section]]
			while not stack.is_empty():
				var node: Node = stack.pop_back()
				if node is Control and (node as Control).is_visible_in_tree():
					var rect := (node as Control).get_global_rect()
					if rect.position.x < scroll_rect.position.x - 1.0 or rect.end.x > scroll_rect.end.x + 1.0:
						overflow = "%s %s" % [node.name, rect]
						break
				stack.append_array(node.get_children())
			_check("%s %s has no horizontal overflow" % [tag, section], overflow.is_empty(), overflow)
		if setup.workspace.picture_panel.visible:
			var picture_rect: Rect2 = setup.workspace.picture.get_global_rect()
			_check("%s picture is drawn inside its panel" % tag, setup.workspace.picture_panel.get_global_rect().grow(1.0).encloses(picture_rect))
	ScreenTheme.text_scale = 1.0
	setup.free()
	await process_frame
