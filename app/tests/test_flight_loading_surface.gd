extends SceneTree

const FlightLoading := preload("res://ui/flight_loading.gd")
const Screen := preload("res://ui/screen.gd")
const ScreenStack := preload("res://ui/screen_stack.gd")
const UiTheme := preload("res://ui/ui_theme.gd")

var _failures := 0


func _initialize() -> void:
	TranslationServer.set_locale("en")
	_run.call_deferred()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _run() -> void:
	var button_probe := FlightLoading.new()
	var button_cancel_count := [0]
	button_probe.cancel_requested.connect(func() -> void: button_cancel_count[0] += 1)
	button_probe.cancel_button.pressed.emit()
	button_probe.cancel_button.pressed.emit()
	_check("Cancel button requests cancellation exactly once", button_cancel_count[0] == 1,
		str(button_cancel_count[0]))
	button_probe.free()

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var host := Node.new()
	viewport.add_child(host)
	var stack := ScreenStack.new(host)
	var lower := Screen.new()
	lower.name = "HomeSurface"
	lower.theme = UiTheme.build()
	lower.set_anchors_preset(Control.PRESET_FULL_RECT)
	var lower_button := Button.new()
	lower_button.name = "CoveredAction"
	lower_button.position = Vector2(24.0, 24.0)
	lower_button.size = Vector2(180.0, 64.0)
	lower.add_child(lower_button)
	var lower_clicks := [0]
	lower_button.pressed.connect(func() -> void: lower_clicks[0] += 1)
	_check("lower screen enters the stack", stack.push("home", lower))
	await process_frame

	var loading := FlightLoading.new()
	loading.configure("Ugly Stik\nClub Field\nRunway start")
	loading.set_stage("Building landscape")
	var cancel_count := [0]
	loading.cancel_requested.connect(func() -> void: cancel_count[0] += 1)
	_check("Screen exists before the wrapper is attached", loading.surface != null
		and loading.surface.get_parent() == loading and ScreenStack._surface(loading) == loading.surface)
	_check("loading surface is accepted as a blocking screen", stack.push("flight_loading", loading, lower_button))
	await process_frame
	await process_frame

	_check("loading wrapper is the top screen", stack.top() == loading and stack.is_top("flight_loading"))
	_check("screen layer is modal and does not start an entrance tween",
		loading.surface.kind == Screen.Kind.MODAL and loading.surface.get("_entrance") == null
		and is_equal_approx(loading.surface.modulate.a, 1.0))
	_check("opaque backdrop fills the viewport and stops mouse input",
		loading.backdrop.mouse_filter == Control.MOUSE_FILTER_STOP
		and is_equal_approx(loading.backdrop.color.a, 1.0)
		and Rect2(Vector2.ZERO, loading.surface.size).encloses(loading.backdrop.get_global_rect()))
	_check("ScreenStack suspends the lower screen", not lower.visible and not lower_button.is_visible_in_tree())
	_check("summary is caller supplied and stage text is shown",
		loading.summary_label.text == "Ugly Stik\nClub Field\nRunway start"
		and loading.stage_label.text == TranslationServer.translate("Building landscape"))

	var covered_point: Vector2 = lower_button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = covered_point
	motion.global_position = covered_point
	viewport.push_input(motion, true)
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = covered_point
		click.global_position = covered_point
		click.pressed = pressed
		viewport.push_input(click, true)
	await process_frame
	_check("covered mouse input cannot activate the lower screen", lower_clicks[0] == 0)

	for _index in 2:
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.physical_keycode = KEY_ESCAPE
		escape.pressed = true
		viewport.push_input(escape, true)
		escape = InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.physical_keycode = KEY_ESCAPE
		escape.pressed = false
		viewport.push_input(escape, true)
	await process_frame
	_check("Escape requests cancellation exactly once", cancel_count[0] == 1, str(cancel_count[0]))

	loading.set_cancelling()
	_check("cancelling disables Cancel and replaces the truthful stage",
		loading.cancel_button.disabled and loading.stage_label.text == TranslationServer.translate("Cancelling…"))
	loading.cancel_button.pressed.emit()
	_check("button cannot emit another request after cancellation starts", cancel_count[0] == 1)

	UiTheme.text_scale = 2.0
	loading.surface.theme = UiTheme.build()
	TranslationServer.set_locale("es")
	await process_frame
	await process_frame
	var bounds := Rect2(Vector2.ZERO, loading.surface.size)
	_check("static labels track the current translation",
		loading.title_label.text == TranslationServer.translate("Preparing flight…")
		and loading.cancel_button.text == TranslationServer.translate("Cancel")
		and loading.stage_label.text == TranslationServer.translate("Cancelling…"))
	_check("Spanish dynamic summary stays as supplied", loading.summary_label.text == "Ugly Stik\nClub Field\nRunway start")
	_check("panel and actions fit 1080p at 200 percent text",
	_inside(loading.find_child("LoadingPanel", true, false) as Control, bounds)
		and _inside(loading.cancel_button, bounds)
		and _inside(loading.title_label, bounds) and _inside(loading.summary_label, bounds),
		"panel=%s cancel=%s title=%s summary=%s" % [str((loading.find_child("LoadingPanel", true, false) as Control).get_global_rect()),
		str(loading.cancel_button.get_global_rect()), str(loading.title_label.get_global_rect()),
		str(loading.summary_label.get_global_rect())])

	stack.pop(true, false)
	stack.pop(true, false)
	viewport.queue_free()
	await process_frame
	TranslationServer.set_locale("en")
	UiTheme.text_scale = 1.0
	print("all flight loading surface checks passed" if _failures == 0 else "%d flight loading surface checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _inside(control: Control, bounds: Rect2) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= bounds.position.x - 1.0 and rect.position.y >= bounds.position.y - 1.0 \
		and rect.end.x <= bounds.end.x + 1.0 and rect.end.y <= bounds.end.y + 1.0
