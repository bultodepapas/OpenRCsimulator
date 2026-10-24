extends SceneTree

const Scale = preload("res://ui/ui_scale.gd")
const UiTheme = preload("res://ui/ui_theme.gd")

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var cases: Array[Dictionary] = [
		{"pixels": Vector2i(1280, 720), "factor": 1.0, "logical": Vector2i(1280, 720), "compact": true},
		{"pixels": Vector2i(1920, 1080), "factor": 1.0, "logical": Vector2i(1920, 1080), "compact": false},
		{"pixels": Vector2i(2560, 1440), "factor": 4.0 / 3.0, "logical": Vector2i(1920, 1080), "compact": false},
		{"pixels": Vector2i(3840, 2160), "factor": 2.0, "logical": Vector2i(1920, 1080), "compact": false},
		{"pixels": Vector2i(1920, 1200), "factor": 1.0, "logical": Vector2i(1920, 1200), "compact": false},
		{"pixels": Vector2i(3440, 1440), "factor": 4.0 / 3.0, "logical": Vector2i(2580, 1080), "compact": false},
		{"pixels": Vector2i(1024, 576), "factor": 1.0, "logical": Vector2i(1024, 576), "compact": true},
	]
	Scale.apply(root)
	for entry in cases:
		var pixels: Vector2i = entry.pixels
		root.size = pixels
		var state: Dictionary = Scale.apply(root)
		await process_frame
		await process_frame
		var logical := root.get_visible_rect().size
		var expected: Vector2i = entry.logical
		_check("factor %s -> %.3f" % [pixels, entry.factor], is_equal_approx(Scale.automatic_factor(pixels), entry.factor))
		_check("logical size %s -> %s" % [pixels, expected], state.logical_size == expected and root.content_scale_size == expected)
		_check("viewport follows scale at %s" % pixels, logical.is_equal_approx(Vector2(expected)))
		_check("compact breakpoint %s" % pixels, state.compact == entry.compact and Scale.is_compact(expected) == entry.compact)
		_check("CanvasItems scaling preserves native 3D resolution mode", root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
		print("ok   " if state.logical_size == expected else "FAIL ", pixels, " logical=", logical, " factor=", state.factor)

	_check("zero-sized window uses a finite factor", Scale.automatic_factor(Vector2i.ZERO) == 1.0)
	_check("zero-sized window does not invent a logical canvas", Scale.logical_size_for(Vector2i.ZERO) == Vector2i.ZERO)
	_check("text contrast on charcoal meets 4.5:1", UiTheme.contrast(UiTheme.TEXT, UiTheme.PANEL) >= 4.5)
	_check("secondary text on translucent navigation surface meets 4.5:1", UiTheme.contrast(UiTheme.TEXT_2, UiTheme.SIDEBAR) >= 4.5)
	_check("lime focus on graphite meets 3:1", UiTheme.contrast(UiTheme.FOCUS, UiTheme.PANEL) >= 3.0)
	await _check_popup_anchor_after_resize()

	UiTheme.compact_layout = true
	UiTheme.text_scale = 1.0
	var compact_theme := UiTheme.build()
	_check("compact body remains 22 logical pixels", compact_theme.default_font_size == 22)
	UiTheme.compact_layout = false
	var desktop_theme := UiTheme.build()
	_check("desktop body is 26 logical pixels", desktop_theme.default_font_size == 26)
	UiTheme.text_scale = 2.0
	var large_theme := UiTheme.build()
	_check("200% body scaling remains available", large_theme.default_font_size == 52)
	for type in ["PrimaryButton", "CompactPrimaryButton", "SettingsAction"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var primary_box := large_theme.get_stylebox(state, type) as StyleBoxFlat
			var primary_text_key: String = {"normal": "font_color", "hover": "font_hover_color", "pressed": "font_pressed_color", "disabled": "font_disabled_color"}[state]
			var primary_text: Color = large_theme.get_color(primary_text_key, type)
			_check("%s %s light text contrasts with composited glass" % [type, state], UiTheme.contrast(primary_text, primary_box.bg_color) >= 4.5)
			var expected: Color = UiTheme.BUTTON.disabled if type == "SettingsAction" and state == "disabled" else UiTheme.PRIMARY[state]
			_check("%s %s state keeps its glass or disabled palette" % [type, state], primary_box.bg_color == expected)
			var focus := large_theme.get_stylebox("focus", type) as StyleBoxFlat
			_check("%s %s focus remains visible inside dark glass" % [type, state],
				not focus.draw_center and UiTheme.contrast(focus.border_color, primary_box.bg_color) >= 3.0)
	var destructive_box := large_theme.get_stylebox("normal", "DestructiveButton") as StyleBoxFlat
	_check("checked symbols retain dark ink on fluorescent green", UiTheme.contrast(UiTheme.ACCENT_INK, UiTheme.FOCUS) >= 4.5)
	var destructive_text: Color = large_theme.get_color("font_color", "DestructiveButton")
	_check("destructive action uses readable text on red", UiTheme.contrast(destructive_text, destructive_box.bg_color) >= 4.5)
	_check("danger announcement chip uses readable text on red", UiTheme.contrast(UiTheme.TEXT, UiTheme.DANGER.pressed) >= 4.5)
	UiTheme.text_scale = 1.0
	UiTheme.compact_layout = false
	quit(1 if failures else 0)


func _check(description: String, ok: bool) -> void:
	print("ok   " if ok else "FAIL ", description)
	if not ok:
		failures += 1


func _check_popup_anchor_after_resize() -> void:
	root.size = Vector2i(1920, 1080)
	Scale.apply(root)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var option := OptionButton.new()
	option.position = Vector2(320, 200)
	option.size = Vector2(300, 56)
	option.add_item("Trainer")
	host.add_child(option)
	await process_frame
	option.show_popup()
	await process_frame
	var popup: PopupMenu = option.get_popup()
	_check("OptionButton popup opens in the logical canvas", popup.visible)
	if popup.visible:
		root.size = Vector2i(3840, 2160)
		Scale.apply(root)
		await process_frame
		await process_frame
		option.position = Vector2(480, 300) # model a responsive row moving during the resize
		await process_frame
		Scale.realign_popups(host)
		await process_frame
		var control_rect: Rect2 = option.get_global_rect()
		var expected_popup_position := Vector2i(roundi(control_rect.position.x), roundi(control_rect.end.y))
		_check("resized popup stays aligned with its OptionButton", popup.visible and popup.position == expected_popup_position)
	host.queue_free()
