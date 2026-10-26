extends SceneTree

const ControllerSetup := preload("res://ui/controller_setup.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const ControllerPrompts := preload("res://ui/controller_prompts.gd")
const UiInput := preload("res://ui/ui_input.gd")
const Home := preload("res://ui/home.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")

class FakeRegistry extends RefCounted:
	signal devices_changed

	var selections := {"flight": -1, "ui": -1}
	var devices: Array[Dictionary] = [
		{"id": 5, "name": "Known gamepad", "raw_name": "Known gamepad", "kind": "gamepad", "known": true, "connected": true},
		{"id": 7, "name": "Unknown joystick", "raw_name": "Unknown joystick", "kind": "joystick", "known": false, "connected": true, "serial_number": "unknown-pad-7"},
		{"id": 9, "name": "Radio transmitter", "raw_name": "Radio transmitter", "kind": "radio", "connected": true},
		{"id": 11, "name": "Ambiguous joystick", "raw_name": "Ambiguous joystick", "kind": "joystick", "known": false, "connected": true, "serial_number": "ambiguous-pad-11", "ambiguous": true},
		{"id": 12, "name": "Radio-purpose joystick", "raw_name": "Radio-purpose joystick", "kind": "joystick", "known": false, "connected": true, "serial_number": "radio-purpose-pad-12"},
	]

	func get_devices() -> Array[Dictionary]:
		return devices.duplicate(true)

	func selected_device_id(role: String) -> int:
		return int(selections.get(role, -1))


class FakeStore extends RefCounted:
	var saved_count := 0
	var save_succeeds := false
	var profiles: Array[Dictionary] = []
	var last_saved_profile: Dictionary = {}

	func load_all() -> Dictionary:
		return {"ok": true, "profiles": profiles.duplicate(true), "errors": []}

	func import_legacy_radio() -> Dictionary:
		return {"ok": true, "profiles": [], "errors": []}

	func save_profile(candidate: Dictionary) -> Dictionary:
		saved_count += 1
		if not save_succeeds:
			return {"ok": false, "profile": {}, "error": "test save must not run"}
		last_saved_profile = candidate.duplicate(true)
		for index in profiles.size():
			if str(profiles[index].get("profile_id", "")) == str(last_saved_profile.get("profile_id", "")):
				profiles[index] = last_saved_profile.duplicate(true)
				return {"ok": true, "profile": last_saved_profile.duplicate(true), "error": ""}
		profiles.append(last_saved_profile.duplicate(true))
		return {"ok": true, "profile": last_saved_profile.duplicate(true), "error": ""}

	func match_profile(info: Dictionary, connected_devices: Array = []) -> Dictionary:
		var serial := str(info.get("serial_number", ""))
		if serial.is_empty():
			return {}
		var connected_matches := 0
		for device in connected_devices:
			if device is Dictionary and bool(device.get("connected", false)) and str(device.get("serial_number", "")) == serial:
				connected_matches += 1
		if connected_matches != 1:
			return {}
		var matches: Array[Dictionary] = []
		for profile in profiles:
			var association: Dictionary = profile.get("association", {})
			if str(association.get("serial_number", "")) == serial:
				matches.append(profile.duplicate(true))
		return matches[0] if matches.size() == 1 else {}


var failures := 0


func _initialize() -> void:
	InputMap.load_from_project_settings()
	await _test_input_map()
	await _test_setup_draft_and_single_save()
	await _test_profile_name_error_lifecycle()
	await _test_mapping_error_recovery()
	await _test_glyph_family_save_and_cancel()
	await _test_unknown_saved_gamepad_menu_gate()
	await _test_entry_signals()
	await _test_helicopter_default_save()
	print("all controller setup checks passed" if failures == 0 else "%d controller setup checks failed" % failures)
	quit(1 if failures > 0 else 0)


func _test_input_map() -> void:
	var bindings := ControllerActions.default_bindings()
	bindings["accept"] = {"type": "button", "button": JOY_BUTTON_Y}
	bindings["back"] = {"type": "button", "button": JOY_BUTTON_X}
	bindings["navigate_up"] = {"type": "button", "button": JOY_BUTTON_A}
	UiInput.set_gamepad(5, bindings)
	_check("UI Input records the selected menu device", UiInput.selected_gamepad_id() == 5)
	_check("custom Accept reaches native ui_accept", _has_button("ui_accept", 5, JOY_BUTTON_Y))
	_check("custom Back reaches native ui_cancel", _has_button("ui_cancel", 5, JOY_BUTTON_X))
	_check("custom navigation reaches native ui_up", _has_button("ui_up", 5, JOY_BUTTON_A))
	var all_selected := true
	for event_text in UiInput.joypad_ui_events():
		all_selected = all_selected and event_text.ends_with("[device 5]")
	_check("all native joypad GUI events belong to the one selected device", all_selected and not UiInput.joypad_ui_events().is_empty())
	_check("keyboard ui_accept events survive device selection", _has_key_event("ui_accept"))
	bindings["accept"] = {"type": "key", "physical_keycode": KEY_Q, "keycode": KEY_Q}
	UiInput.set_gamepad(5, bindings)
	_check("custom keyboard Accept reaches native ui_accept", _has_key_code("ui_accept", KEY_Q))
	UiInput.isolate_joypads()
	_check("clearing UI ownership removes every joypad GUI event", UiInput.joypad_ui_events().is_empty())
	_check("clearing UI ownership removes the injected remap key", not _has_key_code("ui_accept", KEY_Q))
	_check("keyboard ui_accept remains after isolation", _has_key_event("ui_accept"))


func _test_setup_draft_and_single_save() -> void:
	var registry := FakeRegistry.new()
	var store := FakeStore.new()
	store.profiles.append(ControllerProfile.defaults("gamepad", "mode1"))
	var setup := ControllerSetup.new()
	setup.configure(registry, store)
	var close_count := [0]
	var requested_roles: Array = []
	var calibration_count := [0]
	setup.close_requested.connect(func() -> void: close_count[0] += 1)
	setup.calibration_requested.connect(func() -> void: calibration_count[0] += 1)
	root.add_child(setup)
	await process_frame
	await process_frame
	var setup_scroll := setup.find_child("ControllerSetupScroll", true, false) as ScrollContainer
	_check("setup opens with the controller section at the top of the page", setup_scroll.scroll_vertical <= 1)
	var profile := setup.current_profile()
	_check("new setup opens with a valid Mode 2 draft", ControllerProfile.validate(profile).ok and profile.preset == "mode2")
	_check("preset choices retain full tooltip labels", setup.preset_picker.get_popup().get_item_tooltip(2) == setup.preset_picker.get_item_text(2))
	_check("radio calibration is an explicit public action", setup.calibrate_button.text == "Calibrate selected radio" and not setup.calibrate_button.visible)
	setup.calibrate_button.pressed.emit()
	_check("calibration button emits only the explicit calibration request", calibration_count[0] == 1)
	_check("empty device/profile choices carry the real -1 ID", setup.flight_device_picker.get_item_id(0) == -1 and setup.ui_device_picker.get_item_id(0) == -1 and setup.profile_picker.get_item_id(0) == -1)
	var edited_copy := setup.current_profile()
	edited_copy.roll.axis = 8
	_check("current_profile returns an isolated draft copy", setup.current_profile().roll.axis == profile.roll.axis)
	var roll_controls: Dictionary = setup._axis_controls["roll"]
	(roll_controls["axis"] as SpinBox).value = 8.0
	(roll_controls["deadzone"] as SpinBox).value = 0.15
	(roll_controls["expo"] as SpinBox).value = 0.6
	(roll_controls["invert"] as CheckBox).button_pressed = true
	var tuned_profile := setup.current_profile()
	var tuned: Dictionary = tuned_profile.roll
	_check("axis, deadzone, expo and inversion edit a valid draft", tuned.axis == 8 and is_equal_approx(tuned.deadzone, 0.15) and is_equal_approx(tuned.expo, 0.6) and tuned.invert and ControllerProfile.validate(tuned_profile).ok)
	setup._on_flight_device_selected(1)
	setup._apply_preset("mode1")
	_check("Mode 1 preset updates channel mapping", setup.current_profile().pitch.axis == 1 and setup.current_profile().throttle.axis == 3)
	setup._apply_preset("trigger_absolute")
	_check("trigger help names flight axes without the removed arming step", setup.preset_help_label.text.contains("right X roll, right Y pitch") and setup.preset_help_label.text.contains("RT/R2") and not setup.preset_help_label.text.contains("Release"))
	setup._apply_preset("mode1")
	setup._on_flight_device_selected(setup.flight_device_picker.get_item_index(7))
	_check("unknown joystick exposes an explicit kind choice and starts unconfigured", setup.profile_kind_picker.visible and setup.current_profile().kind == "joystick" and setup.current_profile().preset == "radio_custom" and not setup.current_profile().configured)
	setup._on_profile_kind_selected(setup.profile_kind_picker.get_item_index(0))
	_check("choosing Gamepad creates a Mode 2 draft without applying it", setup.current_profile().kind == "gamepad" and setup.current_profile().preset == "mode2" and registry.selected_device_id("flight") == -1 and store.saved_count == 0)
	setup._on_profile_kind_selected(setup.profile_kind_picker.get_item_index(1))
	_check("choosing Radio creates a custom absolute-throttle draft", setup.current_profile().kind == "radio" and setup.current_profile().preset == "radio_custom" and setup.current_profile().throttle_mode == "radio_absolute")
	_check("changing profile kind never starts radio calibration", calibration_count[0] == 1)
	setup._on_flight_device_selected(setup.flight_device_picker.get_item_index(5))
	var unknown_menu_index := setup.ui_device_picker.get_item_index(7)
	_check("unknown joystick is disabled for menu navigation", unknown_menu_index >= 0 and setup.ui_device_picker.is_item_disabled(unknown_menu_index))
	_check("ambiguous controller identity stays disabled for menu navigation", setup.ui_device_picker.get_item_index(11) >= 0 and setup.ui_device_picker.is_item_disabled(setup.ui_device_picker.get_item_index(11)))
	_check("radio devices are excluded from menu navigation choices", setup.ui_device_picker.get_item_index(9) == -1)
	setup._on_ui_device_selected(setup.ui_device_picker.get_item_index(5))
	_check("device picker edits stay drafts until Save", registry.selected_device_id("flight") == -1 and registry.selected_device_id("ui") == -1)
	_check("the only confirmation action is Save", setup.save_button.text == "Save" and setup.find_child("ApplyDevices", true, false) == null)
	setup._cancel_edits()
	_check("Cancel closes without writing or applying either controller", close_count[0] == 1 and store.saved_count == 0 and registry.selections == {"flight": -1, "ui": -1})
	close_count[0] = 0
	setup.save_and_apply = func(_candidate: Dictionary, _flight_id: int, _menu_id: int) -> Dictionary:
		return {"ok": false, "error": "The selected controller disconnected."}
	_check("failed combined Save leaves the draft open", not setup._save_profile() and close_count[0] == 0 and store.saved_count == 0 and setup.status_label.text.contains("disconnected"))
	store.save_succeeds = true
	setup.save_and_apply = func(candidate: Dictionary, flight_id: int, menu_id: int) -> Dictionary:
		requested_roles.append([flight_id, menu_id])
		registry.selections = {"flight": flight_id, "ui": menu_id}
		return store.save_profile(candidate)
	_check("one Save submits the edited profile and both previously unapplied controllers", setup._save_profile() and requested_roles == [[5, 5]] and store.saved_count == 1 and registry.selections == {"flight": 5, "ui": 5})
	_check("successful Save closes settings once", close_count[0] == 1)
	setup.free()
	await process_frame


func _test_profile_name_error_lifecycle() -> void:
	var store := FakeStore.new()
	var valid_profile := ControllerProfile.defaults("gamepad", "mode1")
	valid_profile["name"] = "Saved profile"
	store.profiles.append(valid_profile)
	var setup := ControllerSetup.new()
	setup.configure(FakeRegistry.new(), store)
	root.add_child(setup)
	await process_frame
	await process_frame
	setup.profile_name_edit.text = "   "
	setup.select_section("axes")
	_check("blank profile name rejects Save before storage", not setup._save_profile(false) and store.saved_count == 0)
	_check("blank name returns to a visible focused field", setup.profile_name_edit.is_visible_in_tree() and setup.profile_name_edit.has_focus())
	_check("blank name has a field highlight and explanatory message", setup.profile_name_edit.has_theme_stylebox_override("normal") and setup.status_label.text.contains("Enter a profile name"))
	var typed := InputEventKey.new()
	typed.keycode = KEY_X
	typed.physical_keycode = KEY_X
	typed.unicode = 120
	typed.pressed = true
	root.push_input(typed)
	await process_frame
	_check("typing clears both error style overrides", setup.profile_name_edit.text.contains("x") and not setup.profile_name_edit.has_theme_stylebox_override("normal") and not setup.profile_name_edit.has_theme_stylebox_override("focus"))
	setup.profile_name_edit.text = ""
	setup._save_profile(false)
	_check("loading a saved profile succeeds", setup.load_selected_profile(str(valid_profile.profile_id)))
	_check("loaded valid name does not retain the previous field error", setup.profile_name_edit.text == "Saved profile" and not setup.profile_name_edit.has_theme_stylebox_override("normal") and not setup.profile_name_edit.has_theme_stylebox_override("focus"))
	store.save_succeeds = true
	_check("loaded valid profile still saves normally", setup._save_profile(false) and store.saved_count == 1)
	setup.free()
	await process_frame


func _test_mapping_error_recovery() -> void:
	root.size = Vector2i(1920, 1080)
	var store := FakeStore.new()
	store.save_succeeds = true
	var setup := ControllerSetup.new()
	setup.configure(FakeRegistry.new(), store, 5, -1)
	root.add_child(setup)
	await process_frame
	await process_frame
	var original := ControllerProfile.defaults("gamepad", "mode2")
	setup._set_draft_profile(original)
	var roll: SpinBox = setup._axis_controls.roll.axis
	var pitch: SpinBox = setup._axis_controls.pitch.axis
	var prior_style := StyleBoxFlat.new()
	prior_style.bg_color = Color(0.1, 0.2, 0.3)
	pitch.get_line_edit().add_theme_stylebox_override("normal", prior_style)
	pitch.value = roll.value
	setup.profile_name_edit.text = ""
	setup.select_section("buttons")
	_check("multiple invalid fields block Save before storage", not setup._save_profile(false) and store.saved_count == 0)
	_check("Save focuses the first field and marks both conflicting axes", setup.profile_name_edit.has_focus() and roll.get_line_edit().has_theme_stylebox_override("normal") and pitch.get_line_edit().get_theme_stylebox("normal") != prior_style)
	_check("axis rows explain both participants", setup._axis_channel_labels.roll.text.contains("Roll, Pitch") and setup._axis_channel_labels.pitch.text.contains("Roll, Pitch"))
	setup.profile_name_edit.text = "Repaired name"
	setup.profile_name_edit.text_changed.emit(setup.profile_name_edit.text)
	_check("fixing the name preserves unrelated axis errors", not setup.profile_name_edit.has_theme_stylebox_override("normal") and roll.get_line_edit().has_theme_stylebox_override("normal") and not setup.status_label.text.contains("Enter a profile name"))
	_check("editing does not steal focus", setup.profile_name_edit.has_focus())
	pitch.value = float(original.pitch.axis)
	_check("correcting a conflict clears both sides and the obsolete message", not roll.get_line_edit().has_theme_stylebox_override("normal") and pitch.get_line_edit().get_theme_stylebox("normal") == prior_style and setup.status_label.text.is_empty())
	_check("corrected draft saves once", setup._save_profile(false) and store.saved_count == 1)

	var conflict := original.duplicate(true)
	var back_button := setup.find_child("Remap_back", true, false) as Button
	var pause_button := setup.find_child("Remap_pause", true, false) as Button
	var back_style := back_button.get_theme_stylebox("normal")
	var pause_style := pause_button.get_theme_stylebox("normal")
	conflict.actions = {"pause": {"type": "button", "button": JOY_BUTTON_B}}
	setup._set_draft_profile(conflict)
	setup.action_filter.select(3)
	setup._on_action_filter_selected(3)
	setup.select_section("axes")
	_check("action collision still blocks saving", not setup._save_profile(false) and store.saved_count == 1)
	await process_frame
	await process_frame
	_check("hidden conflicting actions are exposed without starting capture", setup._selected_section == "buttons" and setup.action_filter.selected == 0 and back_button.is_visible_in_tree() and not setup._is_capture_active())
	_check("both conflicting actions are highlighted and one is focused", back_button.has_theme_stylebox_override("normal") and pause_button.has_theme_stylebox_override("normal") and (back_button.has_focus() or pause_button.has_focus()))
	var scroll := setup.find_child("ControllerSetupScroll", true, false) as ScrollContainer
	_check("focused error is inside the scroll viewport", scroll.get_global_rect().encloses((root.gui_get_focus_owner() as Control).get_global_rect()))
	setup._set_status("Storage disconnected", true)
	setup.profile_name_edit.text_changed.emit(setup.profile_name_edit.text)
	_check("revalidation cannot erase a newer external error", setup.status_label.text.contains("Storage disconnected"))
	setup._set_draft_profile(original)
	_check("profile replacement restores action styles", back_button.get_theme_stylebox("normal") == back_style and pause_button.get_theme_stylebox("normal") == pause_style)

	var with_aux := original.duplicate(true)
	with_aux.aux = {"smoke": {"type": "button", "button": 15, "mode": "level"}}
	setup._set_draft_profile(with_aux)
	var previous := setup.current_profile()
	var remap := setup.find_child("Remap_camera_previous", true, false) as Button
	var remap_style := remap.get_theme_stylebox("normal")
	setup._start_capture("camera_previous", remap)
	var event := InputEventJoypadButton.new()
	event.device = 5
	event.button_index = 15
	event.pressed = true
	setup._capture_binding(event)
	_check("rejected action/AUX remap leaves the accepted draft intact", setup.current_profile() == previous and not setup._is_capture_active() and setup.status_label.text.contains("Binding was not changed"))
	_check("rejected remap highlights the attempted action and conflicting AUX", remap.has_theme_stylebox_override("normal") and setup._aux_controls.smoke.button.get_line_edit().has_theme_stylebox_override("normal"))
	setup._start_capture("camera_previous", remap)
	event.button_index = 16
	setup._capture_binding(event)
	_check("successful remap clears rejected-attempt feedback", remap.get_theme_stylebox("normal") == remap_style and not setup._aux_controls.smoke.button.get_line_edit().has_theme_stylebox_override("normal") and setup.current_profile().actions.camera_previous.button == 16)

	setup._set_draft_profile(original)
	pitch.value = roll.value
	setup._save_profile(false)
	TranslationServer.set_locale("es")
	await process_frame
	_check("language changes refresh inline feedback", setup._axis_channel_labels.roll.text.contains("Elige entradas distintas"))
	for viewport_size: Vector2i in [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1280, 720)]:
		root.size = viewport_size
		setup._save_profile(false)
		for frame in 4:
			await process_frame
		var page_rect: Rect2 = scroll.get_global_rect()
		var owner_rect: Rect2 = (root.gui_get_focus_owner() as Control).get_global_rect()
		_check("error focus remains visible at %s (viewport %s, editor %s)" % [viewport_size, page_rect, owner_rect], page_rect.encloses(owner_rect))
		for label: Label in setup._validation_fields["roll.axis"].labels:
			if label.is_visible_in_tree():
				_check("inline error stays within page width at %s" % viewport_size, label.get_global_rect().position.x >= page_rect.position.x - 1.0 and label.get_global_rect().end.x <= page_rect.end.x + 1.0)
	TranslationServer.set_locale("en")
	setup._set_draft_profile(original)
	setup.free()
	await process_frame


func _test_glyph_family_save_and_cancel() -> void:
	var registry := FakeRegistry.new()
	registry.selections["flight"] = 5
	var store := FakeStore.new()
	var saved_profile := ControllerProfile.defaults("gamepad", "mode2")
	saved_profile["name"] = "Prompt profile"
	store.profiles.append(saved_profile.duplicate(true))
	var setup := ControllerSetup.new()
	setup.configure(registry, store, 5, -1)
	root.add_child(setup)
	await process_frame
	var binding := {"type": "button", "button": JOY_BUTTON_X}
	setup._action_bindings["accept"] = binding.duplicate(true)
	setup._update_action_controls()
	var accept_cell := setup.action_grid.find_child("BindingCell_accept", true, false) as HBoxContainer
	var accept_label := accept_cell.get_node("Binding_accept") as Label
	var accept_glyph := accept_cell.get_node("BindingGlyph_accept") as TextureRect
	var initial_prompt: Dictionary = ControllerPrompts.prompt(binding, "auto", registry.devices[0])
	_check("Auto renders the actual button binding as text and a packaged glyph", accept_label.text == initial_prompt.text and accept_glyph.texture != null and accept_glyph.texture.resource_path == initial_prompt.texture_path)
	var joy_event := InputEventJoypadButton.new()
	joy_event.device = 5
	joy_event.button_index = JOY_BUTTON_X
	joy_event.pressed = true
	var semantics_before := ControllerActions.resolve_event(joy_event, setup._action_bindings, 5, "both")
	setup._on_glyph_family_selected(setup.glyph_family_picker.get_item_index(1))
	var xbox_prompt: Dictionary = ControllerPrompts.prompt(binding, "xbox", registry.devices[0])
	_check("manual Xbox family changes the icon and readable label for the current remapped button", accept_label.text == xbox_prompt.text and accept_label.text == "X" and accept_glyph.texture.resource_path == xbox_prompt.texture_path and accept_glyph.texture.resource_path.ends_with("xbox/face_left.svg"))
	var semantics_after := ControllerActions.resolve_event(joy_event, setup._action_bindings, 5, "both")
	_check("manual glyph selection leaves semantic actions and the remapped physical button unchanged", semantics_after == semantics_before and semantics_after.has("accept") and setup._action_bindings.accept.button == JOY_BUTTON_X)
	setup.request_close()
	_check("Cancel does not persist a draft glyph-family choice", store.saved_count == 0 and store.profiles[0].presentation.glyph_family == "auto")
	setup.free()
	await process_frame

	var save_setup := ControllerSetup.new()
	store.save_succeeds = true
	save_setup.configure(registry, store, 5, -1)
	root.add_child(save_setup)
	await process_frame
	save_setup._action_bindings["accept"] = binding.duplicate(true)
	save_setup._update_action_controls()
	save_setup._on_glyph_family_selected(save_setup.glyph_family_picker.get_item_index(2))
	var saved_semantics_before := ControllerActions.resolve_event(joy_event, save_setup._action_bindings, 5, "both")
	save_setup._save_profile()
	var saved_semantics_after := ControllerActions.resolve_event(joy_event, save_setup._action_bindings, 5, "both")
	_check("Save persists the chosen PlayStation prompt family", store.last_saved_profile.get("presentation", {}).get("glyph_family", "") == "playstation")
	var saved_actions := ControllerActions.effective_bindings(store.last_saved_profile)
	_check("saving presentation preference leaves semantic bindings intact", saved_semantics_after == saved_semantics_before and saved_actions.accept.button == JOY_BUTTON_X)
	save_setup.free()
	await process_frame


func _test_unknown_saved_gamepad_menu_gate() -> void:
	var registry := FakeRegistry.new()
	registry.selections["flight"] = 7
	var store := FakeStore.new()
	var setup := ControllerSetup.new()
	setup.configure(registry, store, 7, -1)
	root.add_child(setup)
	await process_frame
	var unknown_index := setup.ui_device_picker.get_item_index(7)
	_check("unknown device has no menu ownership before a saved profile matches", unknown_index >= 0 and setup.ui_device_picker.is_item_disabled(unknown_index))
	setup._on_profile_kind_selected(setup.profile_kind_picker.get_item_index(0))
	_check("explicit Gamepad choice remains a draft and does not enable the menu device", setup.current_profile().kind == "gamepad" and setup.ui_device_picker.is_item_disabled(setup.ui_device_picker.get_item_index(7)) and store.saved_count == 0)
	store.save_succeeds = true
	setup._save_profile()
	unknown_index = setup.ui_device_picker.get_item_index(7)
	_check("a saved, validated and identity-matched Gamepad profile enables the unknown menu pad", unknown_index >= 0 and not setup.ui_device_picker.is_item_disabled(unknown_index) and store.last_saved_profile.kind == "gamepad")
	var radio_profile := ControllerProfile.defaults("radio", "radio_custom")
	radio_profile["association"] = {"serial_number": "radio-purpose-pad-12"}
	store.profiles.append(radio_profile)
	setup._refresh_devices()
	var radio_profile_index := setup.ui_device_picker.get_item_index(12)
	_check("radio-kind profiles and radio-purpose devices never gain menu navigation", setup.ui_device_picker.get_item_index(9) == -1 and radio_profile_index >= 0 and setup.ui_device_picker.is_item_disabled(radio_profile_index) and setup.ui_device_picker.is_item_disabled(setup.ui_device_picker.get_item_index(11)))
	setup.free()
	await process_frame


func _test_entry_signals() -> void:
	var home := Home.new()
	var home_requests: Array[Control] = []
	home.controls_requested.connect(func(from: Control) -> void: home_requests.append(from))
	root.add_child(home)
	await process_frame
	home.controls_button.pressed.emit()
	_check("Home exposes Controller settings with a source control", home_requests.size() == 1 and home_requests[0] == home.controls_button)
	home.set_controller_devices("Flight pad", "Menu pad")
	_check("Home displays explicit controller state", home.controller_prompt_label.visible and "Menu pad" in home.controller_prompt_label.text)
	home.free()

	var pause := PauseMenu.new()
	var pause_requests: Array[Control] = []
	pause.controls_requested.connect(func(from: Control) -> void: pause_requests.append(from))
	root.add_child(pause)
	await process_frame
	pause.controls_button.pressed.emit()
	_check("Pause exposes Controller settings with a source control", pause_requests.size() == 1 and pause_requests[0] == pause.controls_button)
	pause.free()
	await process_frame


func _test_helicopter_default_save() -> void:
	var registry := FakeRegistry.new()
	var store := FakeStore.new()
	store.save_succeeds = true
	var setup := ControllerSetup.new()
	setup.configure(registry, store, 5, 5, ControllerActions.HELICOPTER_CAPABILITIES)
	root.add_child(setup)
	await process_frame
	_check("helicopter setup displays the automatic arm and hold buttons", setup._action_bindings.helicopter_arm.button == JOY_BUTTON_A and setup._action_bindings.helicopter_hold.button == JOY_BUTTON_B)
	_check("helicopter setup does not promise fixed-wing equipment", setup._action_bindings.flaps_cycle.type == "unbound" and setup._action_bindings.gear_toggle.type == "unbound")
	_check("saving untouched helicopter defaults succeeds", setup._save_profile(false))
	_check("saving does not freeze automatic assignments or disable airplane equipment", store.last_saved_profile.actions.is_empty())
	setup._clear_action_binding("helicopter_trainer")
	var remap := setup.action_grid.find_child("Remap_helicopter_arm", true, false) as Button
	setup._start_capture("helicopter_arm", remap)
	var event := InputEventJoypadButton.new()
	event.device = 5
	event.button_index = 25
	event.pressed = true
	setup._capture_binding(event)
	_check("helicopter remap capture preserves unrelated automatic defaults", setup._action_bindings.helicopter_arm.button == 25 and setup._action_bindings.helicopter_hold.button == JOY_BUTTON_B)
	_check("edited helicopter profile saves", setup._save_profile(false))
	setup.load_selected_profile(store.last_saved_profile)
	_check("saved helicopter remap and Clear reload", setup._action_bindings.helicopter_arm.button == 25 and setup._action_bindings.helicopter_trainer.type == "unbound")
	setup.free()
	await process_frame


func _has_button(action: String, device_id: int, button: JoyButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.device == device_id and event.button_index == button:
			return true
	return false


func _has_key_event(action: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return true
	return false


func _has_key_code(action: String, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event.keycode == keycode or event.physical_keycode == keycode):
			return true
	return false


func _check(label: String, condition: bool) -> void:
	if condition:
		print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label)
