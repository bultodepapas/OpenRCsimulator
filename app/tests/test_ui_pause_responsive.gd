## Responsive Pause menu layout probes. Run with the repository's pinned Godot console build:
## godot --headless --path . --script res://tests/test_ui_pause_responsive.gd
extends SceneTree

const PauseMenu := preload("res://ui/pause_menu.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	await _run()
	print("all responsive Pause checks passed (%d)" % _checks if _failures == 0 else "%d of %d responsive Pause checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _run() -> void:
	var saved_text_scale := ScreenTheme.text_scale
	var saved_locale := TranslationServer.get_locale()
	var viewport_sizes: Array[Vector2i] = [
		Vector2i(960, 540),
		Vector2i(1024, 576),
		Vector2i(1024, 768),
		Vector2i(1280, 800),
		Vector2i(1366, 768),
		Vector2i(1920, 1200),
		Vector2i(2560, 1080),
		Vector2i(3440, 1440),
		Vector2i(3840, 2160),
	]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var session := ResponsivePauseSession.new()
	session.pause_reason = "radio disconnected"
	viewport.add_child(session)
	var pause := PauseMenu.new(true) as CanvasLayer
	viewport.add_child(pause)
	pause.show_for(session, {"probability_percent": 70, "include_catastrophic": true})
	pause.failure_settings_button.visible = true
	pause.overlays_button.visible = true
	var screen := pause.get_node("Screen") as Control
	var resume_requests: Array[bool] = []
	pause.continue_requested.connect(func() -> void: resume_requests.append(true))
	await process_frame
	await process_frame

	for scale: float in [1.0, 2.0]:
		ScreenTheme.text_scale = scale
		screen.theme = ScreenTheme.build()
		for locale: String in ["en", "es"]:
			TranslationServer.set_locale(locale)
			for size: Vector2i in viewport_sizes:
				viewport.size = size
				pause._toggle_group("")
				pause.refresh()
				await process_frame
				await process_frame
				await _check_default_layout(pause, size, scale, locale)
				await _check_session_options(pause, size, scale, locale)
				await _check_exit_options(pause, size, scale, locale)
				pause._on_back_requested()
				await process_frame
				_check("%s %s %d×%d Back collapses Exit options and keeps its disclosure reachable" % [
					locale, _scale_label(scale), size.x, size.y,
				], not pause.exit_options_container.visible
					and pause.exit_options_button.has_focus()
					and _scroll_contains(pause, pause.exit_options_button), _layout_detail(pause))
				var resumes_before := resume_requests.size()
				pause._on_back_requested()
				_check("%s %s %d×%d Back from Pause requests Resume" % [
					locale, _scale_label(scale), size.x, size.y,
				], resume_requests.size() == resumes_before + 1)
				pause._focus_primary()
				await process_frame
				_check("%s %s %d×%d Resume remains visible after Back" % [
					locale, _scale_label(scale), size.x, size.y,
				], not pause.continue_button.disabled and _scroll_contains(pause, pause.continue_button), _layout_detail(pause))

	TranslationServer.set_locale("en")
	ScreenTheme.text_scale = 2.0
	screen.theme = ScreenTheme.build()
	for size: Vector2i in [Vector2i(3440, 1440), Vector2i(960, 540), Vector2i(3440, 1440)]:
		viewport.size = size
		await process_frame
		await process_frame
		var expected_width := minf(768.0, maxf(384.0, size.x * 0.45))
		_check("live 200%% resize to %d×%d recomputes the rail width" % [size.x, size.y],
			is_equal_approx(_panel(pause).size.x, expected_width)
			and _panel(pause).get_global_rect().end.x <= size.x + 1.0, _layout_detail(pause))
		_check("live 200%% resize to %d×%d preserves the focused Resume" % [size.x, size.y],
			pause.continue_button.has_focus() and _scroll_contains(pause, pause.continue_button), _layout_detail(pause))

	viewport.size = Vector2i(1920, 1080)
	for scale: float in [1.0, 2.0, 1.0]:
		ScreenTheme.text_scale = scale
		screen.theme = ScreenTheme.build()
		await process_frame
		await process_frame
		var expected_width := 384.0 if scale == 1.0 else 768.0
		_check("live %s → theme change → %s recomputes the rail width" % [
			_scale_label(2.0 if scale == 1.0 else 1.0), _scale_label(scale),
		], is_equal_approx(_panel(pause).size.x, expected_width), _layout_detail(pause))
		_check("live %s theme keeps Resume visible" % _scale_label(scale),
			pause.continue_button.has_focus() and _scroll_contains(pause, pause.continue_button), _layout_detail(pause))

	pause.queue_free()
	session.queue_free()
	viewport.queue_free()
	await process_frame
	TranslationServer.set_locale(saved_locale)
	ScreenTheme.text_scale = saved_text_scale


func _check_default_layout(pause: CanvasLayer, size: Vector2i, scale: float, locale: String) -> void:
	var panel := _panel(pause)
	var scroll := _scroll(pause)
	var rail_rect := panel.get_global_rect()
	var title: Control = (scroll.get_child(0) as VBoxContainer).get_child(0) as Control
	var expected_width := 384.0 if scale == 1.0 else minf(768.0, maxf(384.0, size.x * 0.45))
	_check("%s %s %d×%d keeps the sidebar within its intended width" % [
		locale, _scale_label(scale), size.x, size.y,
	], is_equal_approx(rail_rect.size.x, expected_width)
		and rail_rect.position.x >= 0.0 and rail_rect.end.x <= size.x + 1.0, _layout_detail(pause))
	scroll.scroll_vertical = 0
	await process_frame
	var view_rect := scroll.get_global_rect()
	var title_rect: Rect2 = title.get_global_rect()
	var status_rect: Rect2 = pause.status_label.get_global_rect()
	_check("%s %s %d×%d keeps the pause reason readable from the top of the body" % [
		locale, _scale_label(scale), size.x, size.y,
	], pause.status_label.visible and status_rect.position.y >= view_rect.position.y - 1.0
		and view_rect.intersects(status_rect), _layout_detail(pause))
	if not view_rect.encloses(status_rect):
		var scroll_range := maxf(0.0, scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page)
		scroll.scroll_vertical = roundi(minf(scroll_range, maxf(0.0, status_rect.end.y - view_rect.end.y)))
		await process_frame
		view_rect = scroll.get_global_rect()
		status_rect = pause.status_label.get_global_rect()
		var reason_end_visible := status_rect.end.y <= view_rect.end.y + 1.0
		var full_reason_visible := status_rect.size.y > view_rect.size.y or view_rect.encloses(status_rect)
		_check("%s %s %d×%d lets the full pause reason be read by scrolling" % [
			locale, _scale_label(scale), size.x, size.y,
		], reason_end_visible and full_reason_visible,
		_layout_detail(pause))
	else:
		_check("%s %s %d×%d does not clip the pause reason" % [
			locale, _scale_label(scale), size.x, size.y,
		], view_rect.encloses(status_rect), _layout_detail(pause))
	pause._focus_primary()
	await process_frame
	view_rect = scroll.get_global_rect()
	_check("%s %s %d×%d keeps title, status, and Resume together when the text scale fits" % [
		locale, _scale_label(scale), size.x, size.y,
	], scale > 1.0 or (view_rect.encloses(title_rect)
		and view_rect.encloses(status_rect) and view_rect.encloses(pause.continue_button.get_global_rect())),
	_layout_detail(pause))
	_check("%s %s %d×%d keeps Resume enabled and reachable" % [
		locale, _scale_label(scale), size.x, size.y,
	], not pause.continue_button.disabled and view_rect.encloses(pause.continue_button.get_global_rect()), _layout_detail(pause))
	if scale == 1.0 and size.y >= 768:
		_check("%s 100%% %d×%d avoids scrolling in the default menu when height allows" % [
			locale, size.x, size.y,
		], not scroll.get_v_scroll_bar().visible, _layout_detail(pause))


func _check_session_options(pause: CanvasLayer, size: Vector2i, scale: float, locale: String) -> void:
	pause._toggle_group("session")
	await process_frame
	var scroll := _scroll(pause)
	var target: Button = pause.overlays_button
	target.grab_focus()
	await process_frame
	_check("%s %s %d×%d Session options stay open and its last action is reachable" % [
		locale, _scale_label(scale), size.x, size.y,
	], pause.session_options_container.visible and target.is_visible_in_tree()
		and target.has_focus() and scroll.get_global_rect().encloses(target.get_global_rect()), _layout_detail(pause))


func _check_exit_options(pause: CanvasLayer, size: Vector2i, scale: float, locale: String) -> void:
	pause._toggle_group("exit")
	await process_frame
	var scroll := _scroll(pause)
	var end_button: Button = pause.end_button
	var quit_button: Button = pause.quit_button
	end_button.grab_focus()
	await process_frame
	_check("%s %s %d×%d Exit options keep End flight reachable" % [
		locale, _scale_label(scale), size.x, size.y,
	], pause.exit_options_container.visible and end_button.is_visible_in_tree()
		and scroll.get_global_rect().encloses(end_button.get_global_rect()), _layout_detail(pause))
	quit_button.grab_focus()
	await process_frame
	_check("%s %s %d×%d Exit options keep Quit reachable" % [
		locale, _scale_label(scale), size.x, size.y,
	], quit_button.is_visible_in_tree() and quit_button.has_focus()
		and scroll.get_global_rect().encloses(quit_button.get_global_rect()), _layout_detail(pause))


func _panel(pause: CanvasLayer) -> PanelContainer:
	return pause.find_children("*", "PanelContainer", true, false)[0] as PanelContainer


func _scroll(pause: CanvasLayer) -> ScrollContainer:
	return pause.find_child("PauseScroll", true, false) as ScrollContainer


func _scroll_contains(pause: CanvasLayer, control: Control) -> bool:
	return _scroll(pause).get_global_rect().encloses(control.get_global_rect())


func _layout_detail(pause: CanvasLayer) -> String:
	var rows: PackedStringArray = []
	for child: Control in (_scroll(pause).get_child(0) as VBoxContainer).get_children():
		if child.visible:
			rows.append("%s=%s/min%s" % [child.name, str(child.size), str(child.get_combined_minimum_size())])
	return "panel=%s scroll=%s status=%s" % [
		str(_panel(pause).get_global_rect()),
		"%s (y=%d max=%d)" % [str(_scroll(pause).get_global_rect()), _scroll(pause).scroll_vertical, _scroll(pause).get_v_scroll_bar().max_value],
		str(pause.status_label.get_global_rect()),
	] + " rows=" + str(rows)


func _scale_label(scale: float) -> String:
	return "%d%%" % roundi(scale * 100.0)


class ResponsivePauseSession extends Node:
	var pause_reason := ""
	var external_controller_selection := false
	var crash: Dictionary = {}
	var crash_auto_restart := false

	func is_flyable() -> bool:
		return true
