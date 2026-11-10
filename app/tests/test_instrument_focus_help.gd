extends SceneTree

const Manager := preload("res://render/overlays/overlay_manager.gd")
const Dialog := preload("res://ui/overlays_dialog.gd")
const Settings := preload("res://render/overlays/overlay_settings.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const UiInput := preload("res://ui/ui_input.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const Shell := preload("res://app_root.gd")
const Service := preload("res://input/controller_service.gd")
const Profile := preload("res://input/controller_profile.gd")
const Store := preload("res://input/controller_profile_store.gd")

class RoutingShell extends Shell:
	func _ready() -> void: pass

class FixtureService extends Service:
	var ui_profile := Profile.defaults()
	func profile_for_device(id: int) -> Dictionary:
		return ui_profile.duplicate(true) if registry.device_for_id(id).get("connected", false) else {}

var checks := 0
var failures := 0
var ui: RefCounted

func _check(label: String, ok: bool, details := "") -> void:
	checks += 1
	if ok:
		print("ok  ", label)
	else:
		failures += 1
		printerr("FAIL %s %s" % [label, details])

func _initialize() -> void:
	_run.call_deferred()

func _frames(count := 5) -> void:
	for _frame in count:
		await process_frame

func _page_for(id: String) -> int:
	if id == "warnings": return 5
	if id in Settings.CLASSIC_IDS: return 1
	if id in Settings.NAVIGATION_IDS or id in Settings.TRAINING_IDS: return 2
	if id in Settings.PLAYER_IDS: return 0
	return 4

func _expected(id: String) -> String:
	return TranslationServer.translate(str(Dialog.DESCRIPTIONS.get(id, Dialog.LEGACY_DESCRIPTIONS.get(id, ""))))

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	InputMap.load_from_project_settings()
	UiInput.set_gamepad(UiDriver.FAKE_DEVICE)
	ui = UiDriver.new(self)
	for locale: String in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for scale: float in [1.0, 2.0]:
			UiTheme.text_scale = scale
			UiTheme.compact_layout = false
			var manager := Manager.new({}, locale)
			root.add_child(manager)
			var dialog := Dialog.new(manager)
			root.add_child(dialog)
			await _frames()
			var initial: Dictionary = manager.settings.duplicate(true)
			for id: String in Settings.IDS:
				dialog.tab_bar.current_tab = _page_for(id)
				await _frames(2)
				var box: CheckBox = dialog.switches[id]
				box.grab_focus()
				await _frames()
				var help: Label = dialog.instrument_help
				var expected := _expected(id)
				var viewport: Rect2 = root.get_visible_rect()
				var row: Rect2 = box.get_global_rect()
				var scroll: Rect2 = dialog._scroll.get_global_rect()
				var details := "id=%s row=%s scroll=%s help=%s panel=%s lines=%d/%d focus=%s" % [id, row, scroll,
					help.get_global_rect(), dialog.dialog_panel.get_global_rect(), help.get_visible_line_count(),
					help.get_line_count(), ui.focus_name()]
				_check("%s %.0f%% %s focus and localized description" % [locale, scale * 100, id],
					box.has_focus() and not expected.is_empty() and box.accessibility_description == expected
					and help.visible and help.text == "%s: %s" % [box.text, expected], details)
				_check("%s %.0f%% %s row and all help visible" % [locale, scale * 100, id],
					viewport.grow(1).encloses(dialog.dialog_panel.get_global_rect())
					and viewport.encloses(dialog.tab_bar.get_global_rect()) and viewport.encloses(dialog.done_button.get_global_rect())
					and scroll.grow(1).encloses(row) and viewport.encloses(help.get_global_rect())
					and dialog._help_scroll.get_global_rect().grow(1).encloses(help.get_global_rect())
					and not dialog._help_can_scroll() and help.get_visible_line_count() == help.get_line_count(), details)
			_check("focus navigation never alters settings", manager.settings == initial)
			if scale == 2.0:
				await _keyboard_walk(dialog)
			await _interaction_checks(dialog, manager)
			dialog.free()
			manager.free()
			await _frames(2)
	await _short_view_checks()
	await _neighbor_checks()
	await _real_overflow_routes()
	await _rapid_close_checks()
	await _saved_binding_checks()
	UiInput.isolate_joypads()
	UiTheme.text_scale = 1.0
	UiTheme.compact_layout = false
	TranslationServer.set_locale("en")
	print("instrument focus help: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _keyboard_walk(dialog: Variant) -> void:
	dialog.tab_bar.current_tab = 0
	await _frames()
	for page in dialog.tab_bar.tab_count:
		dialog.tab_bar.grab_focus()
		await _frames(2)
		var reached: Array[String] = []
		var consistent := true
		for _step in 60:
			await ui.tap(KEY_TAB)
			await _frames(3)
			var focused: Control = root.gui_get_focus_owner()
			if focused == dialog.tab_bar:
				break
			for id: String in Settings.IDS:
				if focused == dialog.switches[id]:
					if not reached.has(id): reached.append(id)
					consistent = consistent and _page_for(id) == page \
						and dialog.instrument_help.text.contains(_expected(id))
		var expected: Array[String] = []
		for id: String in Settings.IDS:
			if _page_for(id) == page: expected.append(id)
		_check("keyboard traversal reaches every switch on page %d" % page,
			consistent and expected.all(func(id: String) -> bool: return reached.has(id)),
			"expected=%s reached=%s" % [str(expected), str(reached)])
		if page + 1 < dialog.tab_bar.tab_count:
			dialog.tab_bar.grab_focus()
			await ui.tap(KEY_RIGHT)
			await _frames()
			_check("keyboard selects next overlay page %d" % (page + 1), dialog.tab_bar.current_tab == page + 1)


func _short_view_checks() -> void:
	UiTheme.text_scale = 2.0
	UiTheme.compact_layout = true
	for locale: String in ["en", "es"]:
		root.size = Vector2i(1280, 720)
		TranslationServer.set_locale(locale)
		var manager := Manager.new({}, locale)
		root.add_child(manager)
		var dialog := Dialog.new(manager)
		root.add_child(dialog)
		await _frames()
		dialog.tab_bar.current_tab = 2
		await _frames()
		var box: CheckBox = dialog.switches.glide
		box.grab_focus()
		await _frames(10)
		var original_pressed := box.button_pressed
		var viewport := root.get_visible_rect()
		var details := "panel=%s row=%s body=%s help=%s hint=%s" % [dialog.dialog_panel.get_global_rect(),
			box.get_global_rect(), dialog._scroll.get_global_rect(), dialog._help_scroll.get_global_rect(), dialog._help_hint.get_global_rect()]
		_check(locale + " 720p keeps focused switch, help and Done bounded", viewport.encloses(dialog.dialog_panel.get_global_rect())
			and viewport.encloses(dialog.done_button.get_global_rect()) and box.has_focus()
			and dialog._scroll.get_global_rect().grow(1).encloses(box.get_global_rect())
			and viewport.encloses(dialog._help_scroll.get_global_rect()) and dialog._help_hint.visible
			and dialog._help_can_scroll(), details)
		await ui.joy_button(JOY_BUTTON_DPAD_RIGHT)
		_check(locale + " selected pad can focus the description", dialog._help_scroll.has_focus()
			and dialog.instrument_help.text.contains(_expected("glide")), ui.focus_name())
		_check(locale + " focused help exposes its name and description", dialog._help_scroll.accessibility_name == box.text
			and dialog._help_scroll.accessibility_description.contains(_expected("glide")))
		var before: float = dialog._help_scroll.get_v_scroll_bar().value
		await ui.joy_button(JOY_BUTTON_DPAD_DOWN)
		var after_pad: float = dialog._help_scroll.get_v_scroll_bar().value
		_check(locale + " selected pad scrolls focused description", after_pad > before and dialog._help_scroll.has_focus())
		await ui.joy_axis(JOY_AXIS_RIGHT_Y, -1.0)
		await ui.joy_axis(JOY_AXIS_RIGHT_Y, 0.0)
		_check(locale + " unbound right stick does not scroll focused description", dialog._help_scroll.get_v_scroll_bar().value == after_pad
			and dialog._help_scroll.has_focus())
		var other := InputEventJoypadButton.new()
		other.device = UiDriver.FAKE_DEVICE - 1
		other.button_index = JOY_BUTTON_DPAD_UP
		other.pressed = true
		Input.parse_input_event(other)
		other = other.duplicate()
		other.pressed = false
		Input.parse_input_event(other)
		await _frames()
		_check(locale + " unselected pad cannot scroll help", dialog._help_scroll.get_v_scroll_bar().value == after_pad
			and dialog._help_scroll.has_focus())
		await ui.tap(KEY_PAGEUP)
		_check(locale + " Page Up reverses focused help scroll", dialog._help_scroll.get_v_scroll_bar().value < after_pad
			and dialog._help_scroll.has_focus())
		await ui.tap(KEY_PAGEDOWN)
		_check(locale + " Page Down scrolls focused help", dialog._help_scroll.get_v_scroll_bar().value > before
			and dialog._help_scroll.has_focus())
		await ui.joy_button(JOY_BUTTON_DPAD_LEFT)
		_check(locale + " selected pad returns to unchanged instrument", box.has_focus() and box.button_pressed == original_pressed)
		dialog._help_scroll.grab_focus()
		root.size = Vector2i(1920, 1080)
		await _frames(10)
		_check(locale + " removing overflow restores instrument focus", box.has_focus() and not dialog._help_hint.visible)
		dialog.free()
		manager.free()
		await _frames(2)
	root.size = Vector2i(1920, 1080)


func _neighbor_checks() -> void:
	# Force description overflow while retaining the ordinary two-column layout.
	root.size = Vector2i(1920, 1080)
	UiTheme.text_scale = 1.0
	UiTheme.compact_layout = false
	TranslationServer.set_locale("en")
	var manager := Manager.new({}, "en")
	root.add_child(manager)
	var dialog := Dialog.new(manager)
	root.add_child(dialog)
	await _frames()
	var speed: CheckBox = dialog.switches.speed
	var height: CheckBox = dialog.switches.height
	speed.grab_focus()
	await _frames()
	dialog.instrument_help.text = "Description overflow for focus routing. ".repeat(150)
	await _frames(10)
	dialog._queue_help_layout()
	await _frames(10)
	_check("two-column routing fixture has scrollable help", dialog._player_grid.columns == 2 and dialog._help_can_scroll())
	var before: float = dialog._help_scroll.get_v_scroll_bar().value
	await ui.tap(KEY_PAGEDOWN)
	_check("Page Down on a switch does not scroll help", speed.has_focus()
		and dialog._help_scroll.get_v_scroll_bar().value == before)
	await ui.joy_axis(JOY_AXIS_RIGHT_Y, 1.0)
	await ui.joy_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_check("unbound right stick on a switch leaves focus and help alone", speed.has_focus()
		and dialog._help_scroll.get_v_scroll_bar().value == before)
	await ui.tap(KEY_RIGHT)
	_check("Right keeps the normal two-column neighbor", height.has_focus(), ui.focus_name())
	dialog.free()
	manager.free()
	await _frames(2)

	# An explicit pre-existing neighbor also wins in a stacked layout.
	root.size = Vector2i(1280, 720)
	UiTheme.text_scale = 2.0
	UiTheme.compact_layout = true
	manager = Manager.new({}, "en")
	root.add_child(manager)
	dialog = Dialog.new(manager)
	root.add_child(dialog)
	await _frames()
	var glide: CheckBox = dialog.switches.glide
	var maneuver: CheckBox = dialog.switches.maneuver
	glide.focus_neighbor_right = glide.get_path_to(maneuver)
	dialog.tab_bar.current_tab = 2
	await _frames()
	glide.grab_focus()
	await _frames(10)
	_check("stacked routing fixture has scrollable help", dialog._training_grid.columns == 1 and dialog._help_can_scroll())
	await ui.tap(KEY_RIGHT)
	_check("Right preserves an existing explicit neighbor", maneuver.has_focus(), ui.focus_name())
	dialog.free()
	manager.free()
	await _frames(2)

	# Exercise the full selected-pad route on the primary layout and on Alerts.
	# Long fixture text forces overflow without claiming these descriptions overflow
	# at every viewport and language.
	root.size = Vector2i(1920, 1080)
	UiTheme.text_scale = 2.0
	manager = Manager.new({}, "en")
	root.add_child(manager)
	dialog = Dialog.new(manager)
	root.add_child(dialog)
	await _frames()
	await _overflow_pad_route(dialog, "glide", 2, "1080p flight tools")
	root.size = Vector2i(1280, 720)
	await _frames(10)
	await _overflow_pad_route(dialog, "warnings", 5, "720p alerts")
	dialog.free()
	manager.free()
	await _frames(2)
	root.size = Vector2i(1920, 1080)


func _overflow_pad_route(dialog: Variant, id: String, page: int, label: String) -> void:
	dialog.tab_bar.current_tab = page
	await _frames()
	var box: CheckBox = dialog.switches[id]
	box.grab_focus()
	await _frames()
	var pressed := box.button_pressed
	dialog.instrument_help.text += " More detail for the overflow fixture.".repeat(150)
	await _frames(10)
	dialog._queue_help_layout()
	await _frames(10)
	_check(label + " overflow fixture is ready", box.has_focus() and dialog._help_can_scroll())
	await ui.joy_button(JOY_BUTTON_DPAD_RIGHT)
	var reached: bool = dialog._help_scroll.has_focus()
	_check(label + " selected pad reaches the same description", reached and dialog._help_id == id, ui.focus_name())
	if reached:
		var before: float = dialog._help_scroll.get_v_scroll_bar().value
		await ui.joy_button(JOY_BUTTON_DPAD_DOWN)
		_check(label + " selected pad scrolls the description", dialog._help_scroll.has_focus()
			and dialog._help_scroll.get_v_scroll_bar().value > before)
		await ui.joy_button(JOY_BUTTON_DPAD_LEFT)
		_check(label + " selected pad returns without changing the switch", box.has_focus() and box.button_pressed == pressed,
			ui.focus_name())


func _real_overflow_routes() -> void:
	# Audit the actual descriptions in every shipped locale at the 720p fallback.
	# Earlier tests cover the primary layout and a deliberately long description.
	root.size = Vector2i(1280, 720)
	UiTheme.text_scale = 2.0
	UiTheme.compact_layout = true
	var found := 0
	for locale: String in ["en", "es", "zh_Hans", "pt_BR", "de", "fr", "it", "ru", "ja"]:
		TranslationServer.set_locale(locale)
		var manager := Manager.new({}, locale)
		root.add_child(manager)
		var dialog := Dialog.new(manager)
		root.add_child(dialog)
		await _frames()
		for id: String in Settings.IDS:
			dialog.tab_bar.current_tab = _page_for(id)
			await _frames(2)
			var box: CheckBox = dialog.switches[id]
			box.grab_focus()
			await _frames(8)
			if not dialog._help_can_scroll():
				continue
			found += 1
			var neighbor := box.find_valid_focus_neighbor(SIDE_RIGHT)
			if neighbor == dialog._help_scroll:
				await ui.joy_button(JOY_BUTTON_DPAD_RIGHT)
				var reached: bool = dialog._help_scroll.has_focus() and dialog._help_id == id
				_check("%s %s overflowing help is reachable by selected pad" % [locale, id], reached, ui.focus_name())
				if reached:
					await ui.joy_button(JOY_BUTTON_DPAD_LEFT)
			else:
				_check("%s %s overflowing help is reachable by selected pad" % [locale, id], false,
					"right neighbor=%s" % (neighbor.name if neighbor != null else "none"))
		dialog.free()
		manager.free()
		await _frames(2)
	_check("real-description overflow was exercised", found > 0, "count=%d" % found)
	root.size = Vector2i(1920, 1080)


func _rapid_close_checks() -> void:
	for delay_frames in [0, 1, 2, 3]:
		var manager := Manager.new({}, "en")
		root.add_child(manager)
		var dialog := Dialog.new(manager)
		root.add_child(dialog)
		await _frames()
		dialog.switches.speed.grab_focus()
		if delay_frames > 0:
			await _frames(delay_frames)
		# Close at each reveal phase. The checked runner detects any callback
		# errors that occur after this dialog has been freed.
		dialog.free()
		manager.free()
		await _frames(5)
	_check("immediate close after focus completes", true)


func _saved_binding_checks() -> void:
	root.size = Vector2i(1280, 720)
	UiTheme.text_scale = 2.0
	UiTheme.compact_layout = true
	TranslationServer.set_locale("en")
	var service := FixtureService.new()
	service.registry.update_devices([{id = UiDriver.FAKE_DEVICE, known = true, name = "Menu pad"}])
	service.registry.select_device("ui", UiDriver.FAKE_DEVICE)
	var profile := Profile.defaults()
	profile["actions"]["pause"] = {"type": "key", "physical_keycode": int(KEY_PAGEDOWN)}
	var path := "user://instrument_help_bindings_%d.cfg" % OS.get_process_id()
	var store := Store.new(path, path + ".legacy")
	service.store = store
	_check("fixture admits only its connected known gamepad", service.is_ui_gamepad(UiDriver.FAKE_DEVICE)
		and not service.is_ui_gamepad(-1) and not service.is_ui_gamepad(UiDriver.FAKE_DEVICE + 1))
	var saved := store.save_profile(profile)
	var loaded := Store.new(path, path + ".legacy").load_all()
	_check("Page Down Pause binding survives storage", saved.ok and loaded.ok and loaded.profiles.size() == 1,
		str([saved, loaded]))
	if not saved.ok or not loaded.ok or loaded.profiles.size() != 1:
		service.free()
		return
	service.ui_profile = loaded.profiles[0]
	var shell := RoutingShell.new()
	shell.controllers = service
	root.add_child(shell)
	shell._controller_ui_changed(UiDriver.FAKE_DEVICE)
	var manager := Manager.new({}, "en")
	root.add_child(manager)
	var dialog := Dialog.new(manager)
	var closed := [0]
	dialog.closed.connect(func() -> void: closed[0] += 1)
	_check("real screen stack opens overlays", shell.screens.push("overlays", dialog, null, false))
	await _frames()
	dialog.tab_bar.current_tab = 2
	await _frames()
	dialog.switches.glide.grab_focus()
	await _frames(10)
	dialog._help_scroll.grab_focus()
	await _frames()
	var before: float = dialog._help_scroll.get_v_scroll_bar().value
	await ui.tap(KEY_PAGEDOWN)
	_check("saved Pause closes before focused help can scroll", closed[0] == 1
		and dialog._help_scroll.get_v_scroll_bar().value == before, "focus=%s" % ui.focus_name())
	profile["actions"].erase("pause")
	profile["actions"]["accept"] = {"type": "key", "physical_keycode": int(KEY_PAGEDOWN)}
	saved = store.save_profile(profile)
	loaded = Store.new(path, path + ".legacy").load_all()
	_check("Page Down Accept binding survives storage", saved.ok and loaded.ok and loaded.profiles.size() == 1,
		str([saved, loaded]))
	if saved.ok and loaded.ok and loaded.profiles.size() == 1:
		service.ui_profile = loaded.profiles[0]
		shell._controller_ui_changed(UiDriver.FAKE_DEVICE)
		dialog._help_scroll.grab_focus()
		before = dialog._help_scroll.get_v_scroll_bar().value
		await ui.tap(KEY_PAGEDOWN)
		_check("saved Accept on help is not consumed as scrolling", closed[0] == 1
			and dialog._help_scroll.get_v_scroll_bar().value == before and dialog._help_scroll.has_focus())
		var glide: CheckBox = dialog.switches.glide
		glide.grab_focus()
		await _frames()
		var old_pressed := glide.button_pressed
		await ui.tap(KEY_PAGEDOWN)
		_check("saved Page Down Accept activates the focused switch", glide.has_focus() and glide.button_pressed != old_pressed)
	profile["actions"].erase("accept")
	profile["actions"]["back"] = {"type": "key", "physical_keycode": int(KEY_PAGEDOWN)}
	saved = store.save_profile(profile)
	loaded = Store.new(path, path + ".legacy").load_all()
	_check("Page Down Back binding survives storage", saved.ok and loaded.ok and loaded.profiles.size() == 1,
		str([saved, loaded]))
	if saved.ok and loaded.ok and loaded.profiles.size() == 1:
		service.ui_profile = loaded.profiles[0]
		shell._controller_ui_changed(UiDriver.FAKE_DEVICE)
		dialog._help_scroll.grab_focus()
		before = dialog._help_scroll.get_v_scroll_bar().value
		await ui.tap(KEY_PAGEDOWN)
		_check("saved Back closes before focused help can scroll", closed[0] == 2
			and dialog._help_scroll.get_v_scroll_bar().value == before)
	profile["actions"].erase("back")
	profile["actions"]["navigate_left"] = {"type": "key", "physical_keycode": int(KEY_PAGEDOWN)}
	profile["actions"]["navigate_down"] = {"type": "axis", "axis": int(JOY_AXIS_RIGHT_Y), "sign": 1, "threshold": 0.65}
	saved = store.save_profile(profile)
	loaded = Store.new(path, path + ".legacy").load_all()
	_check("navigation remaps survive storage", saved.ok and loaded.ok and loaded.profiles.size() == 1,
		str([saved, loaded]))
	if saved.ok and loaded.ok and loaded.profiles.size() == 1:
		service.ui_profile = loaded.profiles[0]
		shell._controller_ui_changed(UiDriver.FAKE_DEVICE)
		dialog._help_scroll.grab_focus()
		before = dialog._help_scroll.get_v_scroll_bar().value
		await ui.joy_axis(JOY_AXIS_RIGHT_Y, 1.0)
		await ui.joy_axis(JOY_AXIS_RIGHT_Y, 0.0)
		_check("saved right-stick navigation scrolls only the focused help", dialog._help_scroll.has_focus()
			and dialog._help_scroll.get_v_scroll_bar().value > before)
		before = dialog._help_scroll.get_v_scroll_bar().value
		await ui.tap(KEY_PAGEDOWN)
		_check("saved Page Down navigation takes priority over help paging", dialog.switches.glide.has_focus()
			and dialog._help_scroll.get_v_scroll_bar().value == before, ui.focus_name())
	shell.screens.pop(false, false)
	dialog.free()
	manager.free()
	shell.free()
	service.free()
	for suffix: String in ["", ".rollback", ".tmp", ".legacy"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	root.size = Vector2i(1920, 1080)
	UiInput.set_gamepad(UiDriver.FAKE_DEVICE)


func _interaction_checks(dialog: Variant, manager: Variant) -> void:
	dialog.tab_bar.current_tab = 0
	await _frames()
	var speed: CheckBox = dialog.switches.speed
	var height: CheckBox = dialog.switches.height
	var power: CheckBox = dialog.switches.power
	dialog.tab_bar.grab_focus()
	await _frames()
	var initial_mouse := InputEventMouseMotion.new()
	initial_mouse.position = Vector2(5, 5)
	initial_mouse.global_position = initial_mouse.position
	Input.parse_input_event(initial_mouse)
	await _frames()
	dialog._scroll.ensure_control_visible(speed)
	await _frames()
	var pointer := InputEventMouseMotion.new()
	pointer.position = speed.get_global_rect().get_center()
	pointer.global_position = pointer.position
	Input.parse_input_event(pointer)
	await _frames(12)
	_check("pointer-only hover remains stable across layout", dialog.instrument_help.visible
		and dialog.instrument_help.text.contains(_expected("speed")) and root.gui_get_focus_owner() == dialog.tab_bar,
		"pointer=%s speed=%s scroll=%s help=%s" % [pointer.position, speed.get_global_rect(), dialog._scroll.get_global_rect(), dialog.instrument_help.text])
	initial_mouse = InputEventMouseMotion.new()
	initial_mouse.position = Vector2(5, 5)
	initial_mouse.global_position = initial_mouse.position
	Input.parse_input_event(initial_mouse)
	await _frames()
	speed.grab_focus()
	await _frames()
	await ui.tap(KEY_TAB)
	_check("keyboard Tab moves focus and updates help", root.gui_get_focus_owner() == height
		and dialog.instrument_help.text.contains(_expected("height")), ui.focus_name())
	speed.grab_focus()
	await _frames()
	await ui.joy_button(JOY_BUTTON_DPAD_DOWN)
	var pad_focus: Control = root.gui_get_focus_owner()
	var pad_id := ""
	for id: String in dialog.switches:
		if dialog.switches[id] == pad_focus:
			pad_id = id
	_check("selected gamepad moves focus and updates help", pad_focus != speed and not pad_id.is_empty()
		and dialog.instrument_help.text.contains(_expected(pad_id)), ui.focus_name())
	var other := InputEventJoypadButton.new()
	other.device = UiDriver.FAKE_DEVICE - 1
	other.button_index = JOY_BUTTON_DPAD_DOWN
	other.pressed = true
	Input.parse_input_event(other)
	other = other.duplicate()
	other.pressed = false
	Input.parse_input_event(other)
	await _frames()
	_check("unselected pad does not move focus or change help", root.gui_get_focus_owner() == pad_focus
		and dialog.instrument_help.text.contains(_expected(pad_id)), ui.focus_name())
	# Directly invoke the engine's hover signal to test the visibility/focus arbitration.
	speed.mouse_entered.emit()
	_check("hover updates help without stealing focus", root.gui_get_focus_owner() == pad_focus
		and dialog.instrument_help.text.contains(_expected("speed")))
	var next_focus: CheckBox = height if pad_focus == power else power
	var next_id := "height" if next_focus == height else "power"
	next_focus.grab_focus()
	await _frames()
	_check("new keyboard focus takes precedence over old hover", root.gui_get_focus_owner() == next_focus
		and dialog.instrument_help.text.contains(_expected(next_id)))
	speed.mouse_exited.emit()
	_check("hover exit does not replace newer focused help", dialog.instrument_help.text.contains(_expected(next_id)))
	dialog.tab_bar.current_tab = 2
	await _frames()
	var maneuver: CheckBox = dialog.switches.maneuver
	maneuver.grab_focus()
	await _frames()
	dialog.switches.glide.mouse_entered.emit()
	await _frames()
	_check("longer hovered help keeps the focused switch and help visible", maneuver.has_focus()
		and dialog.instrument_help.text.contains(_expected("glide"))
		and dialog._scroll.get_global_rect().grow(1).encloses(maneuver.get_global_rect())
		and root.get_visible_rect().encloses(dialog.instrument_help.get_global_rect())
		and dialog.instrument_help.get_visible_line_count() == dialog.instrument_help.get_line_count())
	dialog.switches.glide.mouse_exited.emit()
	await _frames()
	_check("hover exit restores focused instrument help", dialog.instrument_help.text.contains(_expected("maneuver")))
	dialog.tab_bar.current_tab = 1
	await _frames()
	_check("tab change clears stale help and preserves focus recovery", not dialog.instrument_help.visible
		and root.gui_get_focus_owner() == dialog.tab_bar)
	var old: Dictionary = manager.settings.duplicate(true)
	dialog.tab_bar.current_tab = 0
	await _frames()
	speed.grab_focus()
	await _frames()
	var previous_locale := TranslationServer.get_locale()
	var next_locale := "es" if previous_locale == "en" else "en"
	TranslationServer.set_locale(next_locale)
	await _frames()
	_check("live locale change refreshes visible and accessible help", speed.accessibility_description == _expected("speed")
		and dialog.instrument_help.text == "%s: %s" % [speed.text, _expected("speed")])
	TranslationServer.set_locale(previous_locale)
	await _frames()
	# Bring the hover target into view; the focus remains on Speed.
	dialog._scroll.ensure_control_visible(height)
	await _frames()
	# Real pointer motion, not a synthetic signal invocation.
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(5, 5)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await _frames()
	motion = InputEventMouseMotion.new()
	motion.position = height.get_global_rect().get_center()
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await _frames()
	_check("pointer hover updates visible help", dialog.instrument_help.text.contains(_expected("height")),
		str(motion.position) + " height=" + str(height.get_global_rect()) + " scroll=" + str(dialog._scroll.get_global_rect()) + " hover=" + dialog._hovered_instrument + " " + dialog.instrument_help.text)
	motion = InputEventMouseMotion.new()
	motion.position = Vector2(5, 5)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await _frames()
	_check("pointer exit restores focused help", dialog.instrument_help.text.contains(_expected("speed")))
	await ui.tap(KEY_SPACE)
	_check("switch action still applies immediately", manager.settings != old
		and manager.settings.visible.has("speed") == speed.button_pressed)
	if UiTheme.text_scale == 2.0:
		dialog.tab_bar.current_tab = 2
		await _frames()
		dialog.switches.flight_summary.grab_focus()
		await _frames()
		dialog.switches.pilot_radar.grab_focus()
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.position = dialog._scroll.get_global_rect().get_center()
		wheel.global_position = wheel.position
		wheel.pressed = true
		Input.parse_input_event(wheel)
		wheel = wheel.duplicate()
		wheel.pressed = false
		Input.parse_input_event(wheel)
		await process_frame
		var after_wheel: int = dialog._scroll.scroll_vertical
		await _frames()
		_check("manual wheel cancels queued focus reveal", dialog._manual_scroll_after_focus
			and dialog._scroll.scroll_vertical == after_wheel,
			"after=%d final=%d" % [after_wheel, dialog._scroll.scroll_vertical])
	var closed := [0]
	dialog.closed.connect(func() -> void: closed[0] += 1)
	await ui.tap(KEY_ESCAPE)
	_check("Escape still requests close", closed[0] == 1)
