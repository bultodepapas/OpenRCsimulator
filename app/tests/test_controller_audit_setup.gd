extends SceneTree

const Setup := preload("res://ui/controller_setup.gd")
const Profile := preload("res://input/controller_profile.gd")
const Actions := preload("res://input/controller_actions.gd")
const Registry := preload("res://input/controller_registry.gd")
const Store := preload("res://input/controller_profile_store.gd")
const RcInput := preload("res://input/rc_input.gd")
const UiInput := preload("res://ui/ui_input.gd")

var checks := 0
var failures := 0
var paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _store(label: String) -> RefCounted:
	var path := "user://controller_audit_setup_%d_%s.cfg" % [OS.get_process_id(), label]
	paths.append(path)
	return Store.new(path, path + ".legacy")


func _registry(id: int, kind: String, serial: String) -> RefCounted:
	var registry := Registry.new()
	registry.update_devices([{"id": id, "name": "Synthetic " + kind, "guid": "audit-" + serial,
		"raw_name": "Synthetic " + kind, "kind": kind, "known": kind == "gamepad", "serial_number": serial}])
	return registry


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	InputMap.load_from_project_settings()
	await _preview_test()
	await _radio_test()
	_legacy_aux_test()
	_menu_validation_test()
	UiInput.isolate_joypads()
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".rollback", ".legacy"]:
			var target := path + suffix
			if FileAccess.file_exists(target):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	print("Controller audit setup: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _preview_test() -> void:
	var registry := _registry(21, "gamepad", "preview-pad")
	var store := _store("preview")
	var screen := Setup.new()
	screen.configure(registry, store, 21)
	var raw: Array = []
	raw.resize(RcInput.AXES)
	raw.fill(0.0)
	screen.axis_preview_provider = func(_id: int, axis: int) -> float: return float(raw[axis])
	root.add_child(screen)
	await process_frame
	await process_frame
	screen.set_process(false)
	screen._apply_preset("trigger_absolute")
	var draft: Dictionary = screen.current_profile()
	draft.throttle.min = -0.6
	draft.throttle.center = -0.6
	draft.throttle.max = 0.8
	draft.throttle.deadzone = 0.0
	draft.throttle.expo = 1.0
	screen._set_draft_profile(draft)
	var controls: Dictionary = screen._axis_controls.throttle
	_check("absolute trigger deadzone and expo are disabled", not controls.deadzone.editable and not controls.expo.editable)
	_check("centered gamepad shaping remains editable", screen._axis_controls.roll.deadzone.editable and screen._axis_controls.roll.expo.editable)
	var reader := RcInput.new()
	reader.connect_device(21, {"name": "Synthetic gamepad", "known": true}, draft)
	for inverted: bool in [false, true]:
		draft.throttle.invert = inverted
		screen._set_draft_profile(draft)
		_check("trigger fixture activates", reader.use_profile(draft, "audit"))
		for raw_value: float in [-0.6, -0.25, 0.1, 0.45, 0.8]:
			raw[int(draft.throttle.axis)] = raw_value
			reader.on_motion(21, int(draft.throttle.axis), raw_value)
			screen._update_axis_preview()
			var actual: float = reader.throttle_position()
			var meter: ProgressBar = screen._preview_bars.throttle
			_check("trigger preview equals runtime at %s invert=%s" % [raw_value, inverted],
				absf(meter.value - actual) < 0.005 and screen._preview_labels.throttle.text.contains("out %+.2f" % actual),
				str([meter.value, actual, screen._preview_labels.throttle.text]))
	screen.free()
	await process_frame


func _radio_test() -> void:
	var registry := _registry(15, "radio", "new-radio")
	var store := _store("radio")
	var other := Profile.defaults("radio", "radio_custom")
	other.association = {"serial_number": "different-radio"}
	_check("unrelated saved profile fixture stores", store.save_profile(other).ok)
	var screen := Setup.new()
	screen.configure(registry, store, 15)
	var raw: Array = []
	raw.resize(RcInput.AXES)
	raw.fill(0.0)
	screen.axis_preview_provider = func(_id: int, axis: int) -> Variant: return raw[axis]
	root.add_child(screen)
	await process_frame
	await process_frame
	screen.set_process(false)
	var original: Dictionary = screen.current_profile()
	_check("radio starts as an unsaved starter with same mapping as unrelated profile",
		original.profile_id != other.profile_id and Setup._radio_mapping(original) == Setup._radio_mapping(other))
	_check("unrelated identical profile cannot authorize new radio", not screen._save_profile(false)
		and store.load_all().profiles.size() == 1 and "Calibrate" in screen.status_label.text)
	screen._on_profile_kind_selected(screen.profile_kind_picker.get_item_index(0))
	_check("changing type cannot bypass a known radio's verification gate", screen.current_profile().kind == "gamepad"
		and not screen._save_profile(false) and store.load_all().profiles.size() == 1)
	screen._on_profile_kind_selected(screen.profile_kind_picker.get_item_index(1))
	_check("radio draft is restored before calibration", screen.current_profile().kind == "radio")
	var calibration := RcInput.DEFAULT_PROFILE.duplicate(true)
	var generation: int = registry.connection_generation(15)
	_check("current connection accepts a completed calibration draft", screen.apply_calibration_draft(calibration, 15, generation))
	var calibrated_draft: Dictionary = screen.current_profile()
	var tampered: Dictionary = calibrated_draft.duplicate(true)
	tampered.roll.invert = not tampered.roll.invert
	screen._set_draft_profile(tampered)
	_check("changed measured mapping invalidates verification", not screen._save_profile(false) and store.load_all().profiles.size() == 1)
	screen._set_draft_profile(calibrated_draft)
	_check("wizard-origin mapping can be saved", screen._save_profile(false) and store.load_all().profiles.size() == 2,
		screen.status_label.text)
	var verified: Dictionary = screen.current_profile()
	_check("committed mapping reloads as explicitly saved", screen.load_selected_profile(str(verified.profile_id))
		and screen.radio_mapping_verified(screen.current_profile()))
	await _capture_tests(screen, registry, store, raw)
	# Selecting an existing profile is explicit and remains a compatible recovery path.
	_check("explicitly selecting a saved radio keeps its mapping", screen.load_selected_profile(str(other.profile_id))
		and screen.current_profile().profile_id == other.profile_id and screen._save_profile(false), screen.status_label.text)
	screen.free()
	await process_frame
	var matched_registry := _registry(22, "radio", "different-radio")
	var matched_store := _store("matched")
	_check("matched saved fixture stores", matched_store.save_profile(other).ok)
	var matched := Setup.new()
	matched.configure(matched_registry, matched_store, 22)
	root.add_child(matched)
	await process_frame
	_check("uniquely matched saved radio retains its profile and can save", matched.current_profile().profile_id == other.profile_id
		and matched._save_profile(false), matched.status_label.text)
	matched.free()
	await process_frame


func _begin(screen: CanvasLayer, action: String) -> void:
	(screen._axis_capture_buttons[action] as Button).pressed.emit()


func _learn(screen: CanvasLayer, raw: Array, action: String, axis: int, off: float, on: float) -> void:
	raw[axis] = off
	_begin(screen, action)
	if screen._axis_capture_dialog == null:
		return
	screen._axis_capture_dialog.confirmed.emit()
	if screen._axis_capture == null:
		return
	raw[axis] = on
	for i in 3:
		if screen._axis_capture != null:
			screen._sample_axis_capture(0.1)
	raw[axis] = off
	for i in 3:
		if screen._axis_capture != null:
			screen._sample_axis_capture(0.1)


func _capture_tests(screen: CanvasLayer, registry: RefCounted, store: RefCounted, raw: Array) -> void:
	screen.select_section("buttons")
	await process_frame
	await process_frame
	await _spanish_action_bounds(screen)
	var before: Dictionary = screen.current_profile()
	raw[5] = -0.5
	var learn_button: Button = screen._axis_capture_buttons.restart_flight
	learn_button.grab_focus()
	_check("visible Learn axis button receives GUI focus", learn_button.is_visible_in_tree() and learn_button.has_focus())
	_begin(screen, "restart_flight")
	_check("Learn axis opens explicit OFF confirmation", screen._axis_capture_dialog != null
		and screen._axis_capture == null and "OFF" in screen._axis_capture_dialog.dialog_text,
		str([screen.selected_flight_device_id(), screen._capturing_action, screen.status_label.text, screen._axis_capture_buttons.restart_flight.disabled]))
	_check("unconfirmed OFF cannot change the draft", screen.current_profile() == before)
	if screen._axis_capture_dialog == null:
		return
	screen._axis_capture_dialog.confirmed.emit()
	_check("OFF confirmation enters capture", screen._axis_capture != null and screen.current_profile() == before)
	_check("the selected Learn axis control is retained after OFF confirmation", screen._capture_button == learn_button
		and root.gui_get_focus_owner() == learn_button, str(root.gui_get_focus_owner()))
	raw[5] = 0.5
	for i in 3:
		screen._sample_axis_capture(0.1)
	_check("stable ON requests a return to OFF", screen._axis_capture != null and screen._axis_capture.returning
		and screen.current_profile() == before)
	raw[5] = -0.5
	screen._sample_axis_capture(0.1)
	_check("one short OFF sample cannot finish learning", screen._axis_capture != null and screen.current_profile() == before)
	for i in 2:
		if screen._axis_capture != null: screen._sample_axis_capture(0.1)
	var learned: Dictionary = screen.current_profile().actions.get("restart_flight", {})
	_check("reduced symmetric switch learns OFF and ON", Actions.valid_binding(learned)
		and learned.get("axis") == 5 and learned.get("off") == -0.5 and learned.get("on") == 0.5,
		str([learned, screen.status_label.text]))
	var motion := InputEventJoypadMotion.new()
	motion.device = 15
	motion.axis = 5
	motion.axis_value = -0.5
	_check("learned OFF does not activate", not Actions.matches_binding(learned, motion, 15))
	motion.axis_value = 0.5
	_check("learned ON activates", Actions.matches_binding(learned, motion, 15))
	_check("learned binding remains a savable profile", Profile.validate(screen.current_profile()).ok,
		str(Profile.validate(screen.current_profile()).errors))
	await process_frame
	before = screen.current_profile()
	_learn(screen, raw, "camera_cycle", 5, -0.5, 0.5)
	_check("capturing another action on learned source is rejected", screen.current_profile() == before and not screen._is_capture_active(), screen.status_label.text)
	await process_frame
	_learn(screen, raw, "camera_cycle", 6, 0.8, 0.2)
	var reversed: Dictionary = screen.current_profile().actions.get("camera_cycle", {})
	_check("offset reversed switch is learned with its actual endpoints", Actions.valid_binding(reversed)
		and reversed.get("axis") == 6 and is_equal_approx(reversed.get("off", 0.0), 0.8)
		and is_equal_approx(reversed.get("on", 0.0), 0.2) and reversed.get("invert", false), str(reversed))
	motion.axis = 6
	motion.axis_value = 0.8
	_check("reversed offset OFF is inactive", not Actions.matches_binding(reversed, motion, 15))
	motion.axis_value = 0.2
	_check("reversed offset ON activates", Actions.matches_binding(reversed, motion, 15))
	await process_frame
	var with_aux: Dictionary = screen.current_profile()
	with_aux.aux["gear"] = {"type": "axis", "axis": 8, "off": -1.0, "on": 1.0, "invert": false}
	screen._set_draft_profile(with_aux)
	before = screen.current_profile()
	_learn(screen, raw, "view_reset", 8, -0.5, 0.5)
	_check("learned shortcut cannot overlap a configured AUX axis", screen.current_profile() == before
		and not screen._is_capture_active(), screen.status_label.text)
	await process_frame
	_check("learned ranges save through real storage", screen._save_profile(false), screen.status_label.text)
	var saved: Dictionary = screen.current_profile()
	var reloaded: Dictionary = store.load_all()
	var saved_match := false
	for candidate: Dictionary in reloaded.get("profiles", []):
		if candidate.get("profile_id", "") == saved.profile_id and candidate.actions.get("restart_flight", {}) == saved.actions.get("restart_flight", {}) \
				and candidate.actions.get("camera_cycle", {}) == saved.actions.get("camera_cycle", {}):
			saved_match = true
	_check("learned ranges survive profile reload", reloaded.ok and saved_match)
	before = screen.current_profile()
	_begin(screen, "view_reset")
	screen._axis_capture_dialog.canceled.emit()
	_check("Cancel at OFF confirmation leaves draft intact", not screen._is_capture_active() and screen.current_profile() == before)
	await process_frame
	raw[7] = NAN
	_begin(screen, "view_reset")
	screen._axis_capture_dialog.confirmed.emit()
	raw[7] = 0.0
	_check("invalid OFF confirmation leaves draft intact", not screen._is_capture_active() and screen.current_profile() == before)
	await process_frame
	_begin(screen, "view_reset")
	screen._axis_capture_dialog.confirmed.emit()
	raw[7] = NAN
	screen._sample_axis_capture(0.1)
	raw[7] = 0.0
	_check("nonfinite sample aborts without changing draft", not screen._is_capture_active() and screen.current_profile() == before)
	await process_frame
	_begin(screen, "view_reset")
	screen._axis_capture_dialog.confirmed.emit()
	screen._sample_axis_capture(2.0)
	_check("interrupted sampling aborts without changing draft", not screen._is_capture_active() and screen.current_profile() == before)
	await process_frame
	_begin(screen, "view_reset")
	screen._axis_capture_dialog.confirmed.emit()
	raw[7] = 0.6
	raw[9] = 0.6
	screen._sample_axis_capture(0.1)
	raw[7] = 0.0
	raw[9] = 0.0
	_check("simultaneous switch movement cancels learning", not screen._is_capture_active() and screen.current_profile() == before)
	await process_frame
	_begin(screen, "view_reset")
	screen._axis_capture_dialog.confirmed.emit()
	screen.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("application focus loss cancels learning without changing draft", not screen._is_capture_active() and screen.current_profile() == before)
	await process_frame
	_begin(screen, "view_reset")
	screen._axis_capture_dialog.confirmed.emit()
	registry.disconnect_device(15)
	_check("disconnect cancels capture and preserves draft", not screen._is_capture_active() and screen.current_profile() == before)
	await process_frame
	registry.update_devices([{"id": 15, "name": "Synthetic radio", "guid": "audit-new-radio", "raw_name": "Synthetic radio", "kind": "radio", "serial_number": "new-radio"}])
	_check("reconnected handle has a new generation", registry.connection_generation(15) > 1)
	_begin(screen, "view_reset")
	screen._axis_capture_dialog.confirmed.emit()
	registry.update_devices([{"id": 15, "name": "Replacement", "guid": "replacement", "kind": "radio", "serial_number": "replacement"}])
	_check("generation change cancels capture and preserves draft", not screen._is_capture_active() and screen.current_profile() == before)
	await process_frame
	var legacy := {"type": "axis", "axis": 7, "sign": 1, "threshold": 0.65}
	motion.axis = 7
	motion.axis_value = 0.7
	_check("legacy raw-threshold binding remains valid and active", Actions.valid_binding(legacy)
		and Actions.matches_binding(legacy, motion, 15))


func _spanish_action_bounds(screen: CanvasLayer) -> void:
	TranslationServer.set_locale("es")
	for i in 4:
		await process_frame
	var scroll := screen.find_child("ControllerSetupScroll", true, false) as ScrollContainer
	var viewport: Rect2 = scroll.get_global_rect()
	var grid: Rect2 = screen.action_grid.get_global_rect()
	_check("Spanish action grid fits the 1080p scroll viewport horizontally",
		grid.position.x >= viewport.position.x - 1.0 and grid.end.x <= viewport.end.x + 1.0,
		str([viewport, grid]))
	var clipped: Array[String] = []
	var spanish_helicopter_labels := 0
	var index := 3
	for definition: Dictionary in Actions.ACTIONS:
		var label := screen.action_grid.get_child(index) as Label
		var learn: Button = screen._axis_capture_buttons[str(definition.id)]
		if label.is_visible_in_tree():
			var bounds := label.get_global_rect()
			if bounds.position.x < viewport.position.x - 1.0 or bounds.end.x > viewport.end.x + 1.0:
				clipped.append("label %s %s" % [str(definition.id), str(bounds)])
			if "Helicóptero" in label.text:
				spanish_helicopter_labels += 1
		if learn.is_visible_in_tree():
			var bounds := learn.get_global_rect()
			if bounds.position.x < viewport.position.x - 1.0 or bounds.end.x > viewport.end.x + 1.0:
				clipped.append("learn %s %s" % [str(definition.id), str(bounds)])
		index += 3
	_check("all visible Spanish labels and Learn controls fit horizontally", clipped.is_empty(), str([viewport, clipped]))
	_check("Spanish layout checked the helicopter action rows", spanish_helicopter_labels == 4, str(spanish_helicopter_labels))
	TranslationServer.set_locale("en")
	for i in 2:
		await process_frame


func _menu_validation_test() -> void:
	var learned := {"type": "axis", "axis": 7, "sign": 1, "threshold": 0.65,
		"off": -0.5, "on": 0.5, "invert": false}
	for action: String in ["accept", "back", "navigate_up", "navigate_down", "navigate_left", "navigate_right"]:
		var candidate := Profile.defaults("gamepad", "mode2")
		candidate.actions[action] = learned.duplicate(true)
		_check("native menu action rejects learned range: " + action, not Profile.validate(candidate).ok)
	var raw_menu := Profile.defaults("gamepad", "mode2")
	raw_menu.actions["accept"] = {"type": "axis", "axis": 7, "sign": 1, "threshold": 0.65}
	_check("legacy raw-axis menu action stays valid", Profile.validate(raw_menu).ok, str(Profile.validate(raw_menu).errors))
	UiInput.set_gamepad(21, {"accept": learned})
	var learned_mapped := false
	for event: InputEvent in InputMap.action_get_events("ui_accept"):
		if event is InputEventJoypadMotion and event.device == 21 and event.axis == 7:
			learned_mapped = true
	_check("native GUI never installs a learned range as a raw axis", not learned_mapped)
	UiInput.set_gamepad(21, {"accept": raw_menu.actions.accept})
	var raw_mapped := false
	for event: InputEvent in InputMap.action_get_events("ui_accept"):
		if event is InputEventJoypadMotion and event.device == 21 and event.axis == 7:
			raw_mapped = true
	_check("native GUI still installs valid legacy raw axes", raw_mapped)
	TranslationServer.set_locale("es")
	for original: String in ["Learn axis", "Learn axis switch", "Confirm OFF",
			"Hold the chosen switch at OFF, then confirm. Keep the flight sticks still. Next hold ON until asked to return to OFF.",
			"Hold the switch at ON. Keep all other switches still.",
			"Return the switch to OFF and hold it there to finish learning.",
			"Invalid or interrupted switch capture. The binding is unchanged.",
			"Axis switch learned. Save, then move away from OFF and back to OFF before use.",
			"More than one switch axis moved. Capture one switch at a time.", "Invalid switch range. The binding is unchanged.",
			"Calibrate this new radio before saving. A device name cannot verify its channel mapping.",
			"Hold the AILERON stick fully RIGHT and press Enter", "Hold the ELEVATOR stick fully BACK and press Enter",
			"Hold the RUDDER stick fully RIGHT and press Enter", "Move the AILERON stick fully LEFT, then centre. Press Enter",
			"Move the ELEVATOR stick fully FORWARD, then centre. Press Enter", "Move the RUDDER stick fully LEFT, then centre. Press Enter",
			"Hold the requested direction away from centre before continuing; then try again."]:
		_check("Spanish switch-learning text is translated: " + original, TranslationServer.translate(original) != original)
	TranslationServer.set_locale("en")


func _legacy_aux_test() -> void:
	var info := {"name": "EdgeTX legacy radio"}
	var saved: Dictionary = RcInput.DEFAULT_PROFILE.duplicate(true)
	saved.roll.axis = 5
	saved.roll.invert = true
	saved.aux = {"smoke": {"type": "axis", "axis": 5, "off": -1.0, "on": 1.0, "invert": false}}
	var before := saved.duplicate(true)
	var input := RcInput.new()
	input.connect_device(13, info, saved)
	_check("bad optional legacy AUX does not discard a non-default calibration", input.profile_source == "calibrated"
		and input.profile.roll.axis == 5 and input.profile.roll.invert and not input.profile.get("aux", {}).has("smoke")
		and saved == before)
	saved.roll.axis = 99
	input.connect_device(13, info, saved)
	_check("invalid legacy primary mapping cannot be activated", input.profile_source == "unconfigured"
		and not input.armed and input.sticks() == {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0})
