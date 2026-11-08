extends SceneTree
const UiDriver = preload("res://tests/ui_driver.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const Profile = preload("res://input/controller_profile.gd")
var checks := 0
var failures := 0
func check(ok: bool, desc: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", desc)
func select_id(picker: OptionButton, id: int) -> bool:
	for i in picker.item_count:
		if picker.get_item_id(i) == id:
			picker.select(i)
			picker.item_selected.emit(i)
			return true
	return false
func settle() -> void:
	for i in 4: await process_frame
func control_reachable(setup: Node, control: Control) -> bool:
	var scroll: ScrollContainer = setup._section_body.get_parent()
	scroll.ensure_control_visible(control)
	await settle()
	var area: Rect2 = scroll.get_global_rect()
	var bounds: Rect2 = control.get_global_rect()
	var panel: Rect2 = setup._settings_panel.get_global_rect()
	var ok := bounds.position.x >= panel.position.x - 1.0 and bounds.end.x <= panel.end.x + 1.0 \
		and bounds.position.y >= area.position.y - 1.0 and bounds.end.y <= area.end.y + 1.0
	if not ok: print("NOT REACHABLE ", control.name, " bounds=", bounds, " scroll=", area, " panel=", panel, " visible=", control.is_visible_in_tree())
	return ok
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1920, 1080)
	var prefs := "user://audit7-disclosure-%d.cfg" % OS.get_process_id()
	var ui = UiDriver.new(self)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = prefs
	root.add_child(app)
	await settle()
	var devices: Array = [{"id": 18, "name": "Unknown USB joystick", "guid": "audit7-unknown", "known": false}, {"id": 19, "name": "Synthetic Xbox", "guid": "audit7-pad1", "known": true, "vendor_id": 1118, "product_id": 1}, {"id": 20, "name": "Synthetic DualSense", "guid": "audit7-pad2", "known": true, "vendor_id": 1356, "product_id": 2}, {"id": 21, "name": "Synthetic recognized radio", "guid": "audit7-radio", "known": true, "kind": "radio"}]
	app.controllers.enumerate_devices = func() -> Array: return devices
	app.controllers.refresh()
	for locale in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for scale in [1.0, 2.0]:
			UiTheme.text_scale = scale
			app.open_controls()
			await settle()
			var setup: Node = app.screens.top()
			check(select_id(setup.flight_device_picker, 18), "%s %.1f unknown selected" % [locale, scale])
			await settle()
			check(setup.calibration_prerequisite.is_visible_in_tree() and setup.choose_radio_profile_button.is_visible_in_tree() and not setup.calibrate_button.visible, "%s %.1f contextual prerequisite is offered" % [locale, scale])
			check(await control_reachable(setup, setup.calibration_prerequisite) and await control_reachable(setup, setup.choose_radio_profile_button) and await control_reachable(setup, setup.device_lifetime_help), "%s %.1f prerequisite and lifetime text reachable" % [locale, scale])
			var profile_before: Dictionary = setup.current_profile()
			var roles_before := [app.controllers.registry.selected_device_id("flight"), app.controllers.registry.selected_device_id("ui")]
			setup.choose_radio_profile_button.grab_focus()
			await ui.tap(KEY_ENTER)
			check(setup._selected_section == "profile" and setup.profile_kind_picker.has_focus() and setup.current_profile() == profile_before and app.controllers.store.load_all().profiles.is_empty() and roles_before == [app.controllers.registry.selected_device_id("flight"), app.controllers.registry.selected_device_id("ui")], "%s %.1f choose action navigates without selecting or saving" % [locale, scale])
			setup._on_profile_kind_selected(1)
			setup.select_section("devices")
			await settle()
			check(setup.current_profile().kind == "radio" and setup.calibrate_button.visible and not setup.choose_radio_profile_button.visible, "%s %.1f explicit radio draft enables calibration" % [locale, scale])
			check(setup.calibrate_button.text == setup.tr("Calibrate selected radio") and setup.calibration_scope_help.text == setup.tr("Calibration changes only the draft. Cancelling calibration leaves the draft unchanged; Save applies it."), "%s %.1f Home describes draft-only calibration" % [locale, scale])
			check(await control_reachable(setup, setup.calibrate_button) and await control_reachable(setup, setup.calibration_scope_help), "%s %.1f Home action and explanation reachable" % [locale, scale])
			var panel: Rect2 = setup._settings_panel.get_global_rect()
			check(panel.position.x >= 0 and panel.end.x <= 1920 and panel.position.y >= 0 and panel.end.y <= 1080, "%s %.1f Controls panel stays within 1080p" % [locale, scale])
			var draft_before: Dictionary = setup.current_profile()
			setup.calibrate_button.grab_focus()
			await ui.tap(KEY_ENTER)
			check(app.screens.is_top("radio_calibration"), "%s %.1f Home wizard opens" % [locale, scale])
			await ui.tap(KEY_ESCAPE)
			check(app.screens.is_top("controls") and setup.current_profile() == draft_before and app.controllers.store.load_all().profiles.is_empty() and setup.status_label.text == setup.tr("Calibration cancelled. The draft is unchanged."), "%s %.1f Home cancellation preserves draft and says so" % [locale, scale])
			setup._cancel_edits()
			await settle()
	UiTheme.text_scale = 1.0
	TranslationServer.set_locale("en")
	var empty_store := ConfigFile.new()
	empty_store.set_value("controller_profiles", "schema_version", Profile.SCHEMA_VERSION)
	empty_store.set_value("controller_profiles", "profiles", [])
	check(empty_store.save(app.controllers.store.path) == OK, "existing empty profile file fixture created")
	app.open_controls()
	await settle()
	var known: Node = app.screens.top()
	check(select_id(known.flight_device_picker, 19) and known.current_profile().kind == "gamepad" and not known.choose_radio_profile_button.visible and known.calibration_prerequisite.visible, "known gamepad gets an explanation without a new radio conversion path")
	var known_draft: Dictionary = known.current_profile()
	var known_roles := [app.controllers.registry.selected_device_id("flight"), app.controllers.registry.selected_device_id("ui")]
	var known_store: Dictionary = app.controllers.store.load_all()
	var store_path: String = app.controllers.store.path
	var store_exists := FileAccess.file_exists(store_path)
	var store_bytes := FileAccess.get_file_as_bytes(store_path) if store_exists else PackedByteArray()
	known.select_section("profile")
	check(not known.profile_kind_picker.visible and known.current_profile() == known_draft and app.controllers.store.load_all() == known_store and FileAccess.file_exists(store_path) == store_exists and known_roles == [app.controllers.registry.selected_device_id("flight"), app.controllers.registry.selected_device_id("ui")], "known gamepad conversion remains unavailable and unchanged")
	known.select_section("devices")
	check(select_id(known.flight_device_picker, 20), "switch to another known device")
	known.select_section("profile")
	check(not known.profile_kind_picker.visible, "known gamepad does not expose a new type selector")
	known.select_section("devices")
	check(select_id(known.flight_device_picker, 21), "select recognized synthetic radio")
	known.load_selected_profile(Profile.defaults())
	var prior_radio_draft: Dictionary = known.current_profile()
	check(not known.choose_radio_profile_button.visible and known.calibration_prerequisite.text == known.tr("Radio calibration requires a supported radio profile."), "recognized radio with non-radio draft receives truthful information only")
	known.choose_radio_profile_button.pressed.emit()
	check(known._selected_section == "devices" and known.current_profile() == prior_radio_draft and FileAccess.get_file_as_bytes(store_path) == store_bytes and known_roles == [app.controllers.registry.selected_device_id("flight"), app.controllers.registry.selected_device_id("ui")], "hidden Choose cannot create a new recognized-radio override or mutate roles and bytes")
	known.select_section("profile")
	check(not known.profile_kind_picker.visible, "recognized radio retains the baseline type-picker restriction")
	var previous_generation: int = app.controllers.registry.connection_generation(21)
	devices[3].kind = "gamepad"
	app.controllers.refresh()
	await settle()
	check(app.controllers.registry.connection_generation(21) == previous_generation and not known.profile_kind_picker.visible and known.current_profile() == prior_radio_draft and known_roles == [app.controllers.registry.selected_device_id("flight"), app.controllers.registry.selected_device_id("ui")] and FileAccess.get_file_as_bytes(store_path) == store_bytes, "same-generation known-gamepad reclassification creates no override or role mutation")
	known._cancel_edits()
	await settle()
	app.start_flight()
	await settle()
	check(app.flight != null, "flight starts")
	if app.flight == null:
		await ui.close_app(app)
		quit(1)
		return
	if app.pause_menu == null: app.open_pause()
	app.open_controls()
	await settle()
	var setup: Node = app.screens.top()
	check(select_id(setup.flight_device_picker, 18) and select_id(setup.ui_device_picker, 20), "flight draft changes both roles")
	setup._on_profile_kind_selected(1)
	setup._axis_controls.roll.axis.value = 4
	check(setup.calibrate_button.text == "Save controller settings and calibrate" and setup.calibration_scope_help.text.contains("saved") and setup.calibration_scope_help.text.contains("Cancelling"), "flight action and adjacent explanation disclose save before calibration")
	var old_roles := [app.controllers.registry.selected_device_id("flight"), app.controllers.registry.selected_device_id("ui")]
	var stored_before: Dictionary = app.controllers.store.load_all()
	var real_save: Callable = setup.save_and_apply
	setup.save_and_apply = func(_profile: Dictionary, _flight: int, _ui: int) -> Dictionary: return {"ok": false, "error": "injected refusal"}
	setup.calibrate_button.grab_focus()
	await ui.tap(KEY_ENTER)
	check(app.screens.is_top("controls") and app.flight.session.calibration == null and app.controllers.store.load_all() == stored_before and old_roles == [app.controllers.registry.selected_device_id("flight"), app.controllers.registry.selected_device_id("ui")] and setup.current_profile().roll.axis == 4, "failed Save keeps the draft, roles and storage and does not open wizard")
	setup.save_and_apply = real_save
	setup.calibrate_button.grab_focus()
	await ui.tap(KEY_ENTER)
	check(app.flight.session.calibration != null and app.controllers.registry.selected_device_id("flight") == 18 and app.controllers.registry.selected_device_id("ui") == 20, "flight calibration commits distinct roles before starting")
	var saved: Dictionary = app.controllers.store.load_all().profiles[0]
	check(saved.roll.axis == 4 and saved.kind == "radio" and app.flight.session.radio.profile.roll.axis == 4, "actual saved and active radio profile carries changed mapping")
	await ui.tap(KEY_ESCAPE)
	await create_timer(0.3).timeout
	check(app.pause_menu != null and app.flight.session.calibration == null and app.controllers.store.load_all().profiles[0].roll.axis == 4 and app.controllers.registry.selected_device_id("flight") == 18 and app.controllers.registry.selected_device_id("ui") == 20, "in-flight cancellation preserves saved profile and both roles")
	check(app.pause_menu.status_label.text.contains("settings remain active") and app.pause_menu.status_label.text.contains("saved before calibration are kept"), "Pause cancellation message survives periodic refresh")
	for flight_locale in ["en", "es"]:
		TranslationServer.set_locale(flight_locale)
		for flight_scale in [1.0, 2.0]:
			UiTheme.text_scale = flight_scale
			app.open_controls()
			await settle()
			var flight_setup: Node = app.screens.top()
			check(flight_setup.calibrate_button.visible and flight_setup.calibrate_button.text == flight_setup.tr("Save controller settings and calibrate") and flight_setup.calibration_scope_help.text == flight_setup.tr("The profile is saved and device selections are applied before calibration. Cancelling keeps them."), "%s %.1f live flight discloses the save boundary" % [flight_locale, flight_scale])
			flight_setup.legacy_import_button.grab_focus()
			await settle()
			await ui.tap(KEY_TAB)
			await settle()
			var focus_scroll: ScrollContainer = flight_setup._section_body.get_parent()
			var focus_area: Rect2 = focus_scroll.get_global_rect()
			var action_rect: Rect2 = flight_setup.calibrate_button.get_global_rect()
			var help_rect: Rect2 = flight_setup.calibration_scope_help.get_global_rect()
			check(flight_setup.calibrate_button.has_focus() and action_rect.position.y >= focus_area.position.y - 1.0 and help_rect.end.y <= focus_area.end.y + 1.0, "%s %.1f Tab focus reveals action and full explanation together" % [flight_locale, flight_scale])
			if flight_locale == "es" and flight_scale == 2.0:
				var draft_before_scroll: Dictionary = flight_setup.current_profile()
				var roles_before_scroll := [app.controllers.registry.selected_device_id("flight"), app.controllers.registry.selected_device_id("ui")]
				var scroll_before_wheel: int = focus_scroll.scroll_vertical
				var wheel := InputEventMouseButton.new()
				wheel.position = focus_area.get_center()
				wheel.global_position = wheel.position
				wheel.button_index = MOUSE_BUTTON_WHEEL_UP
				wheel.pressed = true
				Input.parse_input_event(wheel)
				await settle()
				check(focus_scroll.scroll_vertical < scroll_before_wheel and flight_setup.calibrate_button.has_focus() and flight_setup.current_profile() == draft_before_scroll and roles_before_scroll == [app.controllers.registry.selected_device_id("flight"), app.controllers.registry.selected_device_id("ui")], "explicit wheel scroll wins while focused and preserves draft and roles")
				flight_setup.legacy_import_button.grab_focus()
				await settle()
				for pressed in [true, false]:
					var pad := InputEventJoypadButton.new()
					pad.device = 20
					pad.button_index = JOY_BUTTON_DPAD_DOWN
					pad.pressed = pressed
					Input.parse_input_event(pad)
				await settle()
				action_rect = flight_setup.calibrate_button.get_global_rect()
				help_rect = flight_setup.calibration_scope_help.get_global_rect()
				check(flight_setup.calibrate_button.has_focus() and action_rect.position.y >= focus_area.position.y - 1.0 and help_rect.end.y <= focus_area.end.y + 1.0, "selected pad navigation reveals action and explanation together")
				flight_setup.flight_device_picker.grab_focus()
				await settle()
				var unrelated_scroll: int = focus_scroll.scroll_vertical
				await settle()
				check(flight_setup.flight_device_picker.has_focus() and focus_scroll.scroll_vertical == unrelated_scroll and flight_setup.current_profile() == draft_before_scroll, "unrelated focus and settled scroll are preserved")
			check(await control_reachable(flight_setup, flight_setup.calibrate_button) and await control_reachable(flight_setup, flight_setup.calibration_scope_help), "%s %.1f flight action and explanation fit the scroll viewport" % [flight_locale, flight_scale])
			var flight_panel: Rect2 = flight_setup._settings_panel.get_global_rect()
			check(flight_panel.position.x >= 0 and flight_panel.end.x <= 1920 and flight_panel.position.y >= 0 and flight_panel.end.y <= 1080, "%s %.1f flight Controls panel remains within 1080p" % [flight_locale, flight_scale])
			if flight_locale == "es":
				check(flight_setup.calibrate_button.text != "Save controller settings and calibrate", "Spanish flight action uses the imported translation at %.1f" % flight_scale)
			flight_setup._cancel_edits()
			await settle()
	TranslationServer.set_locale("en")
	UiTheme.text_scale = 1.0
	app.open_controls()
	await settle()
	setup = app.screens.top()
	setup._axis_controls.roll.axis.value = 5
	check(select_id(setup.ui_device_picker, 19), "second flight draft changes menu role")
	var session: Node = app.flight.session
	setup.profile_saved.connect(func(_profile: Dictionary) -> void: session.external_driver_enabled = true)
	UiTheme.text_scale = 2.0
	setup.calibrate_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await create_timer(0.3).timeout
	check(app.pause_menu != null and app.flight.session.calibration == null and app.controllers.store.load_all().profiles[0].roll.axis == 5 and app.controllers.registry.selected_device_id("ui") == 19, "post-save start refusal leaves committed profile and menu role")
	if app.pause_menu != null:
		var note: Label = app.pause_menu.note_label
		check(note.visible and note.text == "Profile saved and device selections applied, but calibration could not start.", "start refusal says settings were saved, and note survives periodic refresh")
		var rect: Rect2 = note.get_global_rect()
		var pause_scroll: ScrollContainer = app.pause_menu._panel.get_node("PauseScroll")
		var viewport: Rect2 = pause_scroll.get_global_rect()
		var focus: Control = root.gui_get_focus_owner()
		check(rect.position.x >= 0 and rect.end.x <= 1920 and rect.position.y >= viewport.position.y and rect.end.y <= viewport.end.y and rect.end.y <= 1080, "200% start-refusal note is visible in the Pause viewport")
		check(is_instance_valid(focus) and focus.is_visible_in_tree(), "start-refusal Pause retains a visible focus owner")
		TranslationServer.set_locale("es")
		await create_timer(0.3).timeout
		check(note.text == app.pause_menu.tr("Profile saved and device selections applied, but calibration could not start.") and note.text != "Profile saved and device selections applied, but calibration could not start.", "start-refusal note follows a live Spanish locale change")
		TranslationServer.set_locale("en")
	UiTheme.text_scale = 1.0
	session.external_driver_enabled = false
	await ui.close_app(app)
	for suffix in ["", ".controllers", ".controllers.rollback", ".controllers.tmp", ".legacy_rc", ".renderer", ".display"]:
		var path := ProjectSettings.globalize_path(prefs + suffix)
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("Controller calibration disclosure: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
