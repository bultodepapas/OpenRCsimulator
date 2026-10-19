extends SceneTree

const ControllerSetup := preload("res://ui/controller_setup.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const ControllerPrompts := preload("res://ui/controller_prompts.gd")
const JetiRadio := preload("res://input/jeti_radio.gd")
const SmokeAux := preload("res://input/smoke_aux.gd")


class FakeRegistry extends RefCounted:
	signal devices_changed

	var devices: Array[Dictionary] = []
	var selections := {"flight": 5, "ui": -1}

	func _init(profile_id := "") -> void:
		var device := {
			"id": 5,
			"name": "JETI DC/DS Mass Storage",
			"raw_name": "JETI DC/DS Mass Storage",
			"manufacturer": "JETI model s.r.o.",
			"product": "JETI DC/DS Mass Storage",
			"vendor_id": 0x0483,
			"product_id": 0xA07C,
			"kind": "radio",
			"connected": true,
		}
		if not profile_id.is_empty():
			device["profile_id"] = profile_id
		devices.append(device)

	func get_devices() -> Array[Dictionary]:
		return devices.duplicate(true)

	func selected_device_id(role: String) -> int:
		return int(selections.get(role, -1))


class FakeStore extends RefCounted:
	var profiles: Array[Dictionary] = []
	var saved_count := 0
	var last_saved_profile: Dictionary = {}
	var save_succeeds := true

	func load_all() -> Dictionary:
		return {"ok": true, "profiles": profiles.duplicate(true), "errors": []}

	func save_profile(candidate: Dictionary) -> Dictionary:
		saved_count += 1
		if not save_succeeds:
			return {"ok": false, "profile": {}, "error": "fixture save failed"}
		var validation: Dictionary = ControllerProfile.validate(candidate)
		if not bool(validation.get("ok", false)):
			return {"ok": false, "profile": {}, "error": "; ".join(validation.get("errors", []))}
		last_saved_profile = candidate.duplicate(true)
		for index in profiles.size():
			if str(profiles[index].get("profile_id", "")) == str(candidate.get("profile_id", "")):
				profiles[index] = last_saved_profile.duplicate(true)
				return {"ok": true, "profile": last_saved_profile.duplicate(true), "error": ""}
		profiles.append(last_saved_profile.duplicate(true))
		return {"ok": true, "profile": last_saved_profile.duplicate(true), "error": ""}

	func import_legacy_radio() -> Dictionary:
		return {"ok": true, "profiles": [], "errors": []}


var failures := 0
var _fixture_buttons: Dictionary = {}
var _capture_dir := ""
var _capture_locale := ""
var _capture_size := Vector2i(1280, 720)


func _initialize() -> void:
	InputMap.load_from_project_settings()
	_read_capture_options()
	TranslationServer.set_locale("en")
	root.size = _capture_size
	_run.call_deferred()


func _read_capture_options() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			_capture_dir = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--lang="):
			_capture_locale = argument.trim_prefix("--lang=")
		elif argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x", false, 1)
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				_capture_size = Vector2i(parts[0].to_int(), parts[1].to_int())


func _run() -> void:
	await _test_jeti_preset_and_identity()
	await _test_clean_radio_action_draft()
	await _test_switch_editor_capture_and_prompts()
	if not _capture_dir.is_empty():
		await _write_software_fixture_capture()
	if failures == 0:
		print("PASS JETI setup: all checks")
	else:
		printerr("FAIL JETI setup: %d checks failed" % failures)
	quit(1 if failures > 0 else 0)


func _make_setup(store: FakeStore, profile_id := "") -> ControllerSetup:
	var setup := ControllerSetup.new()
	setup.axis_preview_provider = Callable(self, "_fixture_axis_value")
	setup.button_preview_provider = Callable(self, "_fixture_button_pressed")
	setup.configure(FakeRegistry.new(profile_id), store, 5, -1)
	root.add_child(setup)
	return setup


func _fixture_axis_value(device_id: int, axis: int) -> float:
	return float(axis) / 10.0 if device_id == 5 else 0.0


func _fixture_button_pressed(device_id: int, button: int) -> bool:
	return device_id == 5 and bool(_fixture_buttons.get(button, false))


func _jeti_profile() -> Dictionary:
	var profile := ControllerProfile.defaults("radio", "radio_custom")
	profile["name"] = "JETI saved radio"
	profile["association"] = {"serial_number": "fixture-radio"}
	profile.roll["min"] = -0.92
	profile.roll["center"] = 0.02
	profile.roll["max"] = 0.91
	profile.pitch["min"] = -0.88
	profile.pitch["center"] = 0.01
	profile.pitch["max"] = 0.93
	profile.actions = {"camera_previous": {"type": "unbound"}}
	profile.aux = {"gear": {"type": "switch", "buttons": [115, 116, 117], "invert": true, "label": "Sb"}}
	return profile


func _test_jeti_preset_and_identity() -> void:
	var profile := _jeti_profile()
	_check("radio fixture profile is valid", ControllerProfile.validate(profile).ok)
	var store := FakeStore.new()
	store.profiles.append(profile.duplicate(true))
	var setup := _make_setup(store, str(profile.profile_id))
	await process_frame
	await process_frame
	var device_index := setup.flight_device_picker.get_item_index(5)
	var device_tip := setup.flight_device_picker.get_popup().get_item_tooltip(device_index)
	_check("strict JETI identity is recognized", JetiRadio.matches(setup._device_for_id(5)))
	_check("device picker uses a recognizable JETI family name", setup.flight_device_picker.get_item_text(device_index).contains(JetiRadio.FAMILY_LABEL))
	_check("JETI tooltip and details preserve the full raw backend name", device_tip.contains("JETI DC/DS Mass Storage") and setup._device_details_label.text.contains("JETI DC/DS Mass Storage"))
	var jeti_preset_index := setup._preset_ids.find("jeti_mode2")
	_check("recognized radio explicitly offers the JETI Mode 2 preset", jeti_preset_index >= 0 and setup.preset_picker.visible and setup.preset_picker.get_item_text(jeti_preset_index).contains("JETI Mode 2"))
	setup._on_preset_selected(jeti_preset_index)
	var draft: Dictionary = setup.current_profile()
	_check("JETI Mode 2 sets roll 0, inverted pitch 1, absolute throttle 2 and yaw 3", draft.kind == "radio" and draft.preset == "jeti_mode2" and draft.roll.axis == 0 and draft.pitch.axis == 1 and draft.pitch.invert and draft.throttle.axis == 2 and draft.throttle.range_kind == "absolute" and draft.yaw.axis == 3)
	_check("JETI preset preserves calibrated endpoints and explicit action clears", is_equal_approx(draft.roll.min, -0.92) and is_equal_approx(draft.roll.center, 0.02) and is_equal_approx(draft.roll.max, 0.91) and draft.actions.camera_previous.type == "unbound")
	_check("JETI preset preserves switch AUX, identity and profile ID", draft.aux.gear == profile.aux.gear and draft.association == profile.association and draft.profile_id == profile.profile_id)
	_check("JETI preset selection edits only the draft", store.saved_count == 0 and store.profiles[0].preset == "radio_custom")
	_check("JETI preset draft passes profile validation", ControllerProfile.validate(draft).ok)
	_check("JETI Mode 2 help states the explicit mapping and hardware caution", setup.preset_help_label.text.contains("axis 0") and setup.preset_help_label.text.contains("Confirm your own"))
	setup.free()
	await process_frame

	var fresh_setup := _make_setup(FakeStore.new())
	await process_frame
	_check("new recognized radio starts with the JETI Mode 2 preset", fresh_setup.current_profile().preset == "jeti_mode2")
	_check("new JETI profile includes explicit safe recovery actions", fresh_setup.current_profile().actions == ControllerActions.clean_radio_bindings())
	fresh_setup.free()
	await process_frame


func _test_clean_radio_action_draft() -> void:
	var profile := ControllerProfile.defaults("radio", "jeti_mode2")
	profile["actions"]["camera_previous"] = {"type": "button", "button": 100}
	var store := FakeStore.new()
	store.profiles.append(profile.duplicate(true))
	var cancel_setup := _make_setup(store, str(profile.profile_id))
	await process_frame
	cancel_setup._apply_clean_radio_actions_to_draft()
	_check("clean action button writes the safe map into the draft", cancel_setup.current_profile().actions == ControllerActions.clean_radio_bindings())
	_check("safe draft keeps Backspace and Escape recovery", cancel_setup.current_profile().actions.back.type == "key" and cancel_setup.current_profile().actions.back.physical_keycode == KEY_BACKSPACE and cancel_setup.current_profile().actions.pause.physical_keycode == KEY_ESCAPE)
	_check("safe draft clears inherited button actions explicitly", cancel_setup.current_profile().actions.camera_previous.type == "unbound")
	cancel_setup._cancel_edits()
	_check("Cancel discards the clean radio action draft", store.saved_count == 0 and store.profiles[0].actions.camera_previous.button == 100)
	cancel_setup.free()
	await process_frame

	var save_setup := _make_setup(store, str(profile.profile_id))
	await process_frame
	save_setup._apply_clean_radio_actions_to_draft()
	_check("one explicit Save persists the clean radio action map", save_setup._save_profile() and store.saved_count == 1 and store.last_saved_profile.actions == ControllerActions.clean_radio_bindings())
	save_setup.free()
	await process_frame

	var jeti_joystick := ControllerProfile.defaults("joystick", "radio_custom")
	jeti_joystick["actions"]["camera_previous"] = {"type": "button", "button": 100}
	jeti_joystick["roll"]["min"] = -0.91
	jeti_joystick["roll"]["center"] = 0.03
	jeti_joystick["roll"]["max"] = 0.89
	var joystick_store := FakeStore.new()
	joystick_store.profiles.append(jeti_joystick.duplicate(true))
	var joystick_setup := _make_setup(joystick_store, str(jeti_joystick.profile_id))
	await process_frame
	var clean_button := joystick_setup.find_child("CleanRadioActionsDraft", true, false) as Button
	_check("corroborated JETI joystick keeps its kind and exposes clean actions", joystick_setup.current_profile().kind == "joystick" and clean_button.visible)
	clean_button.pressed.emit()
	var cleaned_joystick: Dictionary = joystick_setup.current_profile()
	_check("JETI joystick clean actions preserve identity and calibration in the draft", cleaned_joystick.kind == "joystick" and cleaned_joystick.profile_id == jeti_joystick.profile_id and cleaned_joystick.roll.min == -0.91 and cleaned_joystick.roll.center == 0.03 and cleaned_joystick.roll.max == 0.89 and cleaned_joystick.actions == ControllerActions.clean_radio_bindings() and joystick_store.saved_count == 0)
	_check("JETI joystick safe action draft saves without migrating the profile", joystick_setup._save_profile(false) and joystick_store.last_saved_profile.kind == "joystick" and joystick_store.last_saved_profile.profile_id == jeti_joystick.profile_id and joystick_store.last_saved_profile.roll == cleaned_joystick.roll)
	var gamepad_profile := ControllerProfile.defaults("gamepad", "mode2")
	joystick_setup._set_draft_profile(gamepad_profile)
	var original_gamepad_actions: Dictionary = joystick_setup.current_profile().actions.duplicate(true)
	_check("ordinary gamepad does not expose radio action cleanup", not clean_button.visible)
	joystick_setup._apply_clean_radio_actions_to_draft()
	_check("ordinary gamepad remains unchanged by the guarded cleanup action", joystick_setup.current_profile().actions == original_gamepad_actions)
	joystick_setup.free()
	await process_frame


func _test_switch_editor_capture_and_prompts() -> void:
	_fixture_buttons.clear()
	var store := FakeStore.new()
	var setup := _make_setup(store)
	await process_frame
	var smoke_type := setup.find_child("AuxType_smoke", true, false) as OptionButton
	smoke_type.select(3)
	setup._on_aux_type_selected(3, "smoke")
	var profile: Dictionary = setup.current_profile()
	_check("extra-channel editor offers two-position maintained switches", smoke_type.get_item_id(3) == 3 and profile.aux.smoke.type == "switch" and profile.aux.smoke.buttons.size() == 2)
	_check("new switch group uses distinct numeric indices and validates", profile.aux.smoke.buttons[0] != profile.aux.smoke.buttons[1] and SmokeAux.valid_binding(profile.aux.smoke) and ControllerProfile.validate(profile).ok)
	setup._on_aux_switch_label_changed("Sa", "smoke")
	profile = setup.current_profile()
	_check("switch group stores the optional physical name", profile.aux.smoke.label == "Sa")

	var capture_button := setup.find_child("AuxSwitchCapture_smoke_0", true, false) as Button
	setup._start_aux_capture("smoke", 0, capture_button)
	var wrong_device_event := InputEventJoypadButton.new()
	wrong_device_event.device = 9
	wrong_device_event.button_index = 76
	wrong_device_event.pressed = true
	setup._input(wrong_device_event)
	_check("switch capture ignores a button from another device", setup._capturing_aux_name == "smoke")
	var maintained_release := InputEventJoypadButton.new()
	maintained_release.device = 5
	maintained_release.button_index = 23
	maintained_release.pressed = false
	setup._input(maintained_release)
	_check("switch capture ignores releases and does not wait for other maintained switches", setup._capturing_aux_name == "smoke")
	var target_press := InputEventJoypadButton.new()
	target_press.device = 5
	target_press.button_index = 54
	target_press.pressed = true
	setup._input(target_press)
	profile = setup.current_profile()
	_check("switch capture accepts the selected device's deliberate button transition", profile.aux.smoke.buttons[0] == 54 and setup._capturing_aux_name.is_empty())
	var captured_release := InputEventJoypadButton.new()
	captured_release.device = 5
	captured_release.button_index = 54
	captured_release.pressed = false
	setup._input(captured_release)
	_check("captured release is consumed after the capture ends", setup._capture_release_tokens.is_empty())
	var two_position_buttons: Array = profile.aux.smoke.buttons.duplicate()
	var swap_capture := setup.find_child("AuxSwitchCapture_smoke_0", true, false) as Button
	setup._start_aux_capture("smoke", 0, swap_capture)
	var existing_member_press := InputEventJoypadButton.new()
	existing_member_press.device = 5
	existing_member_press.button_index = two_position_buttons[1]
	existing_member_press.pressed = true
	setup._input(existing_member_press)
	profile = setup.current_profile()
	_check("capturing an existing member atomically swaps two-position detents", profile.aux.smoke.buttons == [two_position_buttons[1], two_position_buttons[0]])
	var existing_member_release := InputEventJoypadButton.new()
	existing_member_release.device = 5
	existing_member_release.button_index = two_position_buttons[1]
	existing_member_release.pressed = false
	setup._input(existing_member_release)
	setup._on_aux_switch_button_changed(float(two_position_buttons[0]), "smoke", 0)
	profile = setup.current_profile()
	_check("direct member edit can restore a valid switched pair", profile.aux.smoke.buttons == two_position_buttons)

	var count_picker := setup.find_child("AuxSwitchPositions_smoke", true, false) as OptionButton
	count_picker.select(1)
	setup._on_aux_switch_count_selected(1, "smoke")
	profile = setup.current_profile()
	_check("extra-channel editor supports a three-position group", profile.aux.smoke.buttons.size() == 3 and SmokeAux.valid_binding(profile.aux.smoke))
	_check("three-position group keeps physical Up/Middle/Down order", setup.find_child("AuxSwitchButtonRow_smoke_0", true, false).visible and setup.find_child("AuxSwitchButtonRow_smoke_1", true, false).visible and setup.find_child("AuxSwitchButtonRow_smoke_2", true, false).visible)
	var three_position_buttons: Array = profile.aux.smoke.buttons.duplicate()
	setup._on_aux_switch_button_changed(float(three_position_buttons[2]), "smoke", 0)
	profile = setup.current_profile()
	_check("direct assignment of a used member swaps three-position detents", profile.aux.smoke.buttons == [three_position_buttons[2], three_position_buttons[1], three_position_buttons[0]])
	setup._on_aux_switch_button_changed(float(three_position_buttons[0]), "smoke", 0)
	profile = setup.current_profile()
	_check("three-position member swap remains reversible", profile.aux.smoke.buttons == three_position_buttons)
	setup._on_aux_switch_invert_toggled(true, "smoke")
	_fixture_buttons[54] = true
	setup._update_aux_preview()
	var smoke_preview := setup.find_child("AuxPreview_smoke", true, false) as Label
	_check("live preview shows named physical detent, numeric button and inverted request", smoke_preview.text.contains("Sa") and smoke_preview.text.contains("Up") and smoke_preview.text.contains("Button 54") and smoke_preview.text.contains("100%"))
	var named_prompt := ControllerPrompts.prompt({"type": "button", "button": 54}, "auto", setup._device_for_id(5), setup.current_profile())
	_check("named radio button renders its physical detent without a gamepad glyph", named_prompt.text == "Sa Up · Button 54" and str(named_prompt.texture_path).is_empty())
	var unknown_prompt := ControllerPrompts.prompt({"type": "button", "button": 127}, "auto", setup._device_for_id(5), setup.current_profile())
	_check("unknown radio button keeps a numeric label and no gamepad glyph", unknown_prompt.text == "Button 127" and str(unknown_prompt.texture_path).is_empty())
	var partial_identity := {"kind": "joystick", "name": "JETI DC/DS", "vendor_id": JetiRadio.VENDOR_ID}
	var partial_jeti_prompt := ControllerPrompts.prompt({"type": "button", "button": 54}, "xbox", partial_identity, {"kind": "joystick"})
	_check("partial JETI identity retains numeric radio labeling without a pad glyph", partial_jeti_prompt.text == "Button 54" and str(partial_jeti_prompt.texture_path).is_empty())
	var two_position_prompt := ControllerPrompts.prompt({"type": "switch", "buttons": [54, 56], "invert": false, "label": "Sa"}, "xbox", setup._device_for_id(5))
	_check("two-position switch prompt names both detents and numeric buttons without a glyph", two_position_prompt.text == "Sa Up · Button 54 / Sa Down · Button 56" and str(two_position_prompt.texture_path).is_empty())
	var three_position_prompt := ControllerPrompts.prompt({"type": "switch", "buttons": [54, 55, 56], "invert": true, "label": "Sa"}, "playstation", setup._device_for_id(5))
	_check("three-position switch prompt names ordered detents and numeric buttons", three_position_prompt.text == "Sa Up · Button 54 / Sa Middle · Button 55 / Sa Down · Button 56" and str(three_position_prompt.texture_path).is_empty())
	var invalid_switch_prompt := ControllerPrompts.prompt({"type": "switch", "buttons": [54, 54], "invert": false, "label": "Sa"}, "xbox", setup._device_for_id(5))
	_check("invalid switch prompt uses a readable glyph-free fallback", invalid_switch_prompt.text == "Invalid switch group." and str(invalid_switch_prompt.texture_path).is_empty())
	setup._action_bindings["camera_previous"] = {"type": "button", "button": 54}
	setup._update_action_controls()
	var named_action_label := setup.find_child("Binding_camera_previous", true, false) as Label
	var action_glyph := setup.find_child("BindingGlyph_camera_previous", true, false) as TextureRect
	_check("setup action row uses named radio position and hides the pad glyph", named_action_label.text == "Sa Up · Button 54" and not action_glyph.visible)
	setup._action_bindings["camera_previous"] = {"type": "button", "button": 127}
	setup._update_action_controls()
	_check("setup leaves unknown radio action numeric", named_action_label.text == "Button 127" and not action_glyph.visible)

	var gear_switch := {"type": "switch", "buttons": [90, 91], "invert": false, "label": "Sb"}
	_check("second AUX group can be configured without collision", setup._commit_aux_binding("gear", gear_switch) and setup.current_profile().aux.gear == gear_switch)
	var prior_group: Dictionary = setup.current_profile().aux.smoke.duplicate(true)
	setup._on_aux_switch_button_changed(90.0, "smoke", 1)
	_check("overlapping switch member keeps the prior valid group", setup.current_profile().aux.smoke == prior_group and setup.status_label.text.contains("Switch mapping was not changed"))
	TranslationServer.set_locale("es")
	await process_frame
	var position_label_up := setup.find_child("AuxSwitchPositionLabel_smoke_0", true, false) as Label
	var position_label_middle := setup.find_child("AuxSwitchPositionLabel_smoke_1", true, false) as Label
	var position_label_down := setup.find_child("AuxSwitchPositionLabel_smoke_2", true, false) as Label
	_check("locale change retranslates configured switch detent labels", position_label_up.text.contains("Arriba") and position_label_middle.text.contains("Centro") and position_label_down.text.contains("Abajo"))
	_check("locale change retranslates the live named switch preview", smoke_preview.text.contains("Arriba") and smoke_preview.text.contains("Botón 54") and smoke_preview.text.contains("solicitud 100%"))
	var spanish_switch_prompt := ControllerPrompts.prompt({"type": "switch", "buttons": [54, 55, 56], "invert": true, "label": "Sa"}, "xbox", setup._device_for_id(5))
	_check("switch prompts reuse Spanish detent and button labels", spanish_switch_prompt.text == "Sa Arriba · Botón 54 / Sa Centro · Botón 55 / Sa Abajo · Botón 56" and str(spanish_switch_prompt.texture_path).is_empty())
	var spanish_invalid_switch_prompt := ControllerPrompts.prompt({"type": "switch", "buttons": [54, 54], "invert": false, "label": "Sa"}, "xbox", setup._device_for_id(5))
	_check("invalid switch fallback is Spanish and glyph-free", spanish_invalid_switch_prompt.text == "El grupo de interruptor no es válido." and str(spanish_invalid_switch_prompt.texture_path).is_empty())
	TranslationServer.set_locale("en")
	await process_frame
	var draft_validity: Dictionary = ControllerProfile.validate(setup.current_profile())
	_check("valid captured and named detent groups can be saved", draft_validity.ok and setup._save_profile(false) and store.last_saved_profile.aux.smoke == prior_group)
	setup.free()
	await process_frame


func _write_software_fixture_capture() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(_capture_size)
	root.size = _capture_size
	var profile := ControllerProfile.defaults("radio", "jeti_mode2")
	profile["aux"] = {"smoke": {"type": "switch", "buttons": [81, 82, 83], "invert": false, "label": "Sa"}}
	var store := FakeStore.new()
	store.profiles.append(profile.duplicate(true))
	_fixture_buttons.clear()
	_fixture_buttons[82] = true
	var setup := _make_setup(store, str(profile.profile_id))
	for _frame in 4:
		await process_frame
	setup.select_section("aux")
	if not _capture_locale.is_empty():
		TranslationServer.set_locale(_capture_locale)
	for _frame in 2:
		await process_frame
	var directory_result := DirAccess.make_dir_recursive_absolute(_capture_dir)
	if directory_result != OK:
		_fail("capture output directory could be created", "error %d" % directory_result)
	else:
		var root_texture := root.get_texture()
		if root_texture == null:
			_fail("fixture viewport has a rendered texture", "run the capture mode with the desktop renderer")
		else:
			var image := root_texture.get_image()
			var file_name := "jeti-setup-%s-%dx%d.png" % ["es" if _capture_locale.begins_with("es") else "en", image.get_width(), image.get_height()]
			var output_path := _capture_dir.path_join(file_name)
			var save_result := image.save_png(output_path)
			if save_result == OK:
				print("SOFTWARE FIXTURE capture (%dx%d): %s" % [image.get_width(), image.get_height(), output_path])
			else:
				_fail("fixture screenshot saved", "error %d" % save_result)
	setup.free()
	await process_frame


func _check(label: String, condition: bool) -> void:
	if condition:
		print("ok   ", label)
	else:
		_fail(label)


func _fail(label: String, detail := "") -> void:
	failures += 1
	printerr("FAIL ", label, " ", detail)
