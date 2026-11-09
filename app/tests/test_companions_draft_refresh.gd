extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const CompanionConfig := preload("res://ai/companions/config.gd")
const CompanionsDialog := preload("res://ui/companions_dialog.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const UiInput := preload("res://ui/ui_input.gd")
const UiScale := preload("res://ui/ui_scale.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const PREFS := "user://audit6_companions_draft_refresh.cfg"

var checks := 0
var failures := 0
var ui: RefCounted

func _check(label: String, passed: bool, detail: String = "") -> void:
	checks += 1
	print(("ok   " if passed else "FAIL ") + label + (" " + detail if not detail.is_empty() else ""))
	if not passed:
		failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	TranslationServer.set_locale("en")
	InputMap.load_from_project_settings()
	UiInput.isolate_joypads()
	root.size = Vector2i(1920, 1080)
	ui = UiDriver.new(self)
	var initial: Dictionary = Preferences.load_from(PREFS)
	initial.first_flight_hint_seen = true
	initial.companion_config = CompanionConfig.defaults()
	initial.companion_config.enabled = true
	initial.companion_config.count = 1
	initial.companion_config.seed = 101
	var saved := Preferences.save_to(PREFS, initial)
	_check("isolated enabled roster preference saves", saved == OK, str(saved))
	if saved != OK:
		_finish()
		return
	var app: Variant = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var main: Node = app.flight
	_check("normal Home flight starts", main != null)
	if main == null:
		await ui.close_app(app)
		_finish()
		return
	var status: Dictionary = main.companion_status()
	for _frame in 240:
		status = main.companion_status()
		if int(status.get("active", 0)) == 1:
			break
		await process_frame
	var admitted: bool = int(status.get("active", 0)) == 1 and main.companions != null \
		and main.companions.agents.size() == 1 and not status.get("profile_identity", {}).is_empty()
	_check("unmodified qualified profile admits one actual companion", admitted, str(status.get("error", "")))
	if not admitted:
		await ui.close_app(app)
		_finish()
		return
	var manager: Node = main.companions
	var companion: Node = manager.agents[0]
	var companion_ref: WeakRef = weakref(companion)
	var session_ref: WeakRef = weakref(companion.session)
	var view_root: Node = companion.view.get("root")
	var engine: Node = companion.get("_engine")
	var view_ref: WeakRef = weakref(view_root) if view_root != null else null
	var engine_ref: WeakRef = weakref(engine) if engine != null else null
	var player_session: Node = main.session
	app.open_pause()
	await ui.settle()
	var paused_companion_tick: int = companion.session.sim.tick
	await ui.settle()
	_check("Pause freezes admitted player and companion", player_session.sim.paused
		and companion.session.sim.tick == paused_companion_tick)
	await _check_layouts(main.companion_config, status)
	TranslationServer.set_locale("en")
	app.open_companions_settings()
	await ui.settle()
	var dialog: Variant = app.companions_dialog
	_check("Pause opens real roster dialog", dialog != null and dialog.remove_button.visible
		and dialog.status_label.text.contains("1 flying"))
	if dialog == null:
		await ui.close_app(app)
		_finish()
		return
	var accepted_before: Dictionary = main.companion_config.duplicate(true)
	var persisted_before: Dictionary = Preferences.load_from(PREFS).companion_config.duplicate(true)
	dialog.enabled_check.button_pressed = true
	dialog.count_picker.select(2)
	dialog.seed_edit.text = "bad seed"
	dialog.volume_slider.value = 35.0
	dialog.labels_check.button_pressed = true
	dialog.label_distance.value = 600.0
	dialog.save_default_check.button_pressed = true
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("invalid seed refuses Apply and retains draft", app.companions_dialog == dialog
		and dialog.error_label.visible and main.companion_config == accepted_before
		and Preferences.load_from(PREFS).companion_config == persisted_before)
	var invalid_error: String = dialog.error_label.text
	dialog.seed_edit.caret_column = 3
	dialog.seed_edit.select(1, 3)
	var player_state: PackedByteArray = player_session.sim.state.to_byte_array()
	var player_tick: int = player_session.sim.tick
	var companion_state: PackedByteArray = companion.session.sim.state.to_byte_array()
	var companion_tick: int = companion.session.sim.tick
	var draft := _snapshot(dialog)
	app._refresh_companions_dialog_status()
	app._refresh_companions_dialog_status()
	await ui.settle()
	_check("repeated status refresh retains invalid seed and every draft field", _snapshot(dialog) == draft,
		str(_snapshot(dialog)))
	_check("status refresh preserves validation error and seed editing focus", dialog.error_label.visible
		and dialog.error_label.text == invalid_error and root.gui_get_focus_owner() == dialog.seed_edit
		and dialog.seed_edit.caret_column == 3)
	_check("status refresh does not advance player or companion physics", player_session.sim.tick == player_tick
		and player_session.sim.state.to_byte_array() == player_state
		and companion.session.sim.tick == companion_tick
		and companion.session.sim.state.to_byte_array() == companion_state)
	var distance_edit: LineEdit = dialog.label_distance.get_line_edit()
	distance_edit.grab_focus()
	await ui.settle()
	distance_edit.text = "675"
	var distance_before: float = dialog.label_distance.value
	var scroll_before: int = dialog._body_scroll.scroll_vertical
	app._refresh_companions_dialog_status()
	app._refresh_companions_dialog_status()
	await ui.settle()
	_check("status refresh retains uncommitted distance text and focused editor", distance_edit.text == "675"
		and dialog.label_distance.value == distance_before and root.gui_get_focus_owner() == distance_edit,
		"text=%s value=%s before=%s focus=%s" % [distance_edit.text, dialog.label_distance.value, distance_before, ui.focus_name()])
	_check("status refresh retains scroll position", dialog._body_scroll.scroll_vertical == scroll_before)
	# The real focus transition may commit the SpinBox editor; compare removal against that settled state.
	dialog.remove_button.grab_focus()
	await ui.settle()
	var raw_after_blur := distance_edit.text
	print("DISTANCE_BLUR raw=%s value=%s" % [raw_after_blur, dialog.label_distance.value])
	_check("leaving distance editor commits its native value", dialog.label_distance.value == 675.0)
	# Recreate the validation feedback after the edit, then navigate to the real Remove action.
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("invalid seed feedback returns after editing distance", dialog.error_label.visible
		and dialog.error_label.text == invalid_error and root.gui_get_focus_owner() == dialog.seed_edit)
	dialog.remove_button.grab_focus()
	await ui.settle()
	var before_remove := _snapshot(dialog)
	_check("real Remove control has focus", root.gui_get_focus_owner() == dialog.remove_button)
	_check("manager owns active player observer callbacks", player_session.sim.stepped.is_connected(Callable(manager, "_after_step"))
		and player_session.sim.before_step.is_connected(Callable(manager, "_before_step")))
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var removed: Dictionary = main.companion_status()
	_check("actual Remove clears the admitted manager roster", int(removed.get("active", -1)) == 0
		and manager.agents.is_empty() and bool(removed.get("removed", false)), str(removed))
	_check("actual Remove releases companion session, model, and engine nodes", companion_ref.get_ref() == null
		and session_ref.get_ref() == null and (view_ref == null or view_ref.get_ref() == null)
		and (engine_ref == null or engine_ref.get_ref() == null))
	_check("actual Remove disconnects the player observers", not player_session.sim.stepped.is_connected(Callable(manager, "_after_step"))
		and not player_session.sim.before_step.is_connected(Callable(manager, "_before_step")))
	_check("Remove keeps every pending field and default choice", _snapshot(dialog) == before_remove, str(_snapshot(dialog)))
	_check("Remove keeps validation feedback and reports empty traffic", dialog.error_label.visible
		and dialog.error_label.text == invalid_error and dialog.status_label.text.contains("0 flying · 1 after restart")
		and not dialog.remove_button.visible)
	_check("focus moves to Cancel when focused Remove disappears", root.gui_get_focus_owner() == dialog.cancel_button)
	_check("Remove leaves paused player state and accepted settings intact", player_session.sim.tick == player_tick
		and player_session.sim.state.to_byte_array() == player_state and main.companion_config == accepted_before
		and Preferences.load_from(PREFS).companion_config == persisted_before)
	app._refresh_companions_dialog_status()
	await ui.settle()
	_check("post-removal refresh preserves draft, error and Cancel focus", _snapshot(dialog) == before_remove
		and dialog.error_label.text == invalid_error and root.gui_get_focus_owner() == dialog.cancel_button)
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Cancel discards draft while keeping immediate removal", app.companions_dialog == null
		and main.companion_config == accepted_before and manager.agents.is_empty()
		and Preferences.load_from(PREFS).companion_config == persisted_before)
	app.open_companions_settings()
	await ui.settle()
	dialog = app.companions_dialog
	_check("reopened draft comes from accepted config", dialog != null and not dialog.remove_button.visible
		and dialog.volume_slider.value == 100.0 and not dialog.labels_check.button_pressed)
	if dialog != null:
		dialog.count_picker.select(1)
		dialog.seed_edit.text = "77"
		dialog.volume_slider.value = 35.0
		dialog.labels_check.button_pressed = true
		dialog.label_distance.value = 600.0
		dialog.save_default_check.button_pressed = true
		await ui.settle()
		var valid_draft := _snapshot(dialog)
		main.set("_electric_demo", "4s")
		dialog.apply_button.grab_focus()
		await ui.tap(KEY_ENTER)
		_check("flight admission refusal keeps dialog and all draft fields", app.companions_dialog == dialog
			and dialog.error_label.visible and _snapshot(dialog) == valid_draft
			and main.companion_config == accepted_before and Preferences.load_from(PREFS).companion_config == persisted_before,
			"error=%s focus=%s draft=%s expected=%s" % [dialog.error_label.text, ui.focus_name(), str(_snapshot(dialog)), str(valid_draft)])
		var rejected_error: String = dialog.error_label.text
		app._refresh_companions_dialog_status()
		await ui.settle()
		_check("status refresh preserves rejected Apply feedback", dialog.error_label.text == rejected_error
			and dialog.error_label.visible and _snapshot(dialog) == valid_draft)
		main.set("_electric_demo", "")
		dialog.apply_button.grab_focus()
		await ui.tap(KEY_ENTER)
		await ui.settle()
		var expected: Dictionary = accepted_before.duplicate(true)
		expected.enabled = true
		expected.count = 2
		expected.seed = 77
		expected.engine_volume = 0.35
		expected.show_labels = true
		expected.label_distance_m = 600.0
		_check("Apply commits precisely the surviving draft to flight and default", app.companions_dialog == null
			and main.companion_config == expected and Preferences.load_from(PREFS).companion_config == expected,
			str(main.companion_config))
		_check("Apply does not recreate the removed roster before Restart", manager.agents.is_empty()
			and int(main.companion_status().active) == 0)
	await ui.close_app(app)
	await _check_direct_route()
	UiInput.isolate_joypads()
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	_finish()

func _check_direct_route() -> void:
	# Direct flights cannot persist a Home default; status refresh must not re-expose it.
	var app: Variant = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray(["--quick-flight", "--companions=1", "--companions-seed=202"])
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	var main: Node = app.flight
	if main == null:
		_check("direct flight starts for hidden-default coverage", false)
		await ui.close_app(app)
		return
	var status: Dictionary = main.companion_status()
	for _frame in 240:
		status = main.companion_status()
		if int(status.get("active", 0)) == 1:
			break
		await process_frame
	_check("direct flight admits an actual companion", int(status.get("active", 0)) == 1 and not app.has_home)
	if int(status.get("active", 0)) != 1:
		await ui.close_app(app)
		return
	app.open_pause()
	await ui.settle()
	app.open_companions_settings()
	await ui.settle()
	var dialog: Variant = app.companions_dialog
	_check("direct dialog hides default persistence", dialog != null and not dialog.save_default_check.visible
		and dialog.save_default_check.focus_mode == Control.FOCUS_NONE)
	if dialog != null:
		dialog.seed_edit.text = "invalid"
		dialog.volume_slider.value = 35.0
		dialog.labels_check.button_pressed = true
		dialog.label_distance.value = 600.0
		await ui.settle()
		var before := _snapshot(dialog)
		app._refresh_companions_dialog_status()
		await ui.settle()
		_check("direct status refresh keeps hidden default and draft", not dialog.save_default_check.visible
			and dialog.save_default_check.focus_mode == Control.FOCUS_NONE and _snapshot(dialog) == before)
		dialog.remove_button.grab_focus()
		await ui.tap(KEY_ENTER)
		await ui.settle()
		_check("direct real Remove retains hidden default and draft", main.companions.agents.is_empty()
			and int(main.companion_status().active) == 0 and not dialog.save_default_check.visible
			and _snapshot(dialog) == before and root.gui_get_focus_owner() == dialog.cancel_button)
	await ui.close_app(app)

func _check_layouts(config: Dictionary, status: Dictionary) -> void:
	# Headless display drivers can retain a 64px physical window; set the logical
	# canvas explicitly so this is a 1080p layout check, not a window-size request.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1920, 1080)
	var expected_statuses := {
		"en": "1 flying · 2 after restart",
		"es": "1 en vuelo · 2 tras reiniciar",
		"zh_Hans": "1 架在空中 · 重启后有 2 架",
		"pt_BR": "1 no ar · 2 após reiniciar",
		"de": "1 in der Luft · 2 nach dem Neustart",
		"fr": "1 en vol · 2 après redémarrage",
		"it": "1 in volo · 2 dopo il riavvio",
		"ru": "1 в воздухе · 2 после перезапуска",
		"ja": "1機 · 再開後2機",
	}
	for locale: String in expected_statuses:
		TranslationServer.set_locale(locale)
		UiTheme.compact_layout = UiScale.is_compact(root.content_scale_size)
		UiTheme.text_scale = 1.0
		var dialog := CompanionsDialog.new()
		var pending_status := status.duplicate(true)
		pending_status.requested_count = 2
		pending_status.pending_count = 2
		pending_status.pending_restart = true
		dialog.configure(config, pending_status)
		root.add_child(dialog)
		await ui.settle()
		await ui.settle()
		var viewport: Rect2 = root.get_visible_rect()
		_check("%s 1080p pending status is localized" % locale, dialog.status_label.text.contains(expected_statuses[locale]),
			dialog.status_label.text)
		_check("%s 1080p dialog and footer fit" % locale, viewport.size == Vector2(1920.0, 1080.0)
			and viewport.grow(1.0).encloses(dialog.dialog_panel.get_global_rect())
			and viewport.encloses(dialog.cancel_button.get_global_rect()) and viewport.encloses(dialog.apply_button.get_global_rect())
			and dialog._body_scroll.size.y >= 80.0, str(dialog.dialog_panel.get_global_rect()))
		dialog.remove_button.grab_focus()
		await ui.settle()
		_check("%s 1080p Remove focus is visible" % locale, root.gui_get_focus_owner() == dialog.remove_button
			and dialog._body_scroll.get_global_rect().grow(1.0).encloses(dialog.remove_button.get_global_rect()))
		root.remove_child(dialog)
		dialog.free()
		await ui.settle()
	UiTheme.text_scale = 1.0
	UiTheme.compact_layout = false

func _snapshot(dialog: Variant) -> Dictionary:
	return {"enabled": dialog.enabled_check.button_pressed,
		"count": dialog.count_picker.get_selected_id(), "seed": dialog.seed_edit.text,
		"volume": dialog.volume_slider.value, "labels": dialog.labels_check.button_pressed,
		"distance": dialog.label_distance.value, "distance_text": dialog.label_distance.get_line_edit().text,
		"save_default": dialog.save_default_check.button_pressed, "save_as_default": dialog.save_as_default}

func _finish() -> void:
	TranslationServer.set_locale("en")
	print("companions draft refresh: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
