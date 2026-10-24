## UI-22-R4: crystal decoration preserves controls, settles when hidden and respects live motion policy.
extends SceneTree

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const UiInput := preload("res://ui/ui_input.gd")
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, valid: bool) -> void:
	print("ok   " if valid else "FAIL ", label)
	if not valid: _failed += 1


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var screen := Screen.new()
	screen.theme = UiTheme.build()
	root.add_child(screen)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "SettingsPanel"
	panel.size = Vector2(800, 500)
	screen.add_child(panel)
	var button := Widgets.button("Continue", "PrimaryButton")
	screen.add_child(button)
	button.position = Vector2(40, 600)
	button.size = Vector2(320, 56)
	var original_rect := button.get_rect()
	var original_minimum := button.get_combined_minimum_size()
	screen.open()
	if DisplayServer.get_name() != "headless":
		UiTheme.reduced_motion = true
		screen._entrance.custom_step(0.016)
		_check("live reduced motion settles the screen entrance too", not screen._entrance.is_running() and screen.modulate.a == 1.0)
		UiTheme.reduced_motion = false
		screen.open()
		screen.set_active(false)
		_check("suspension cancels the screen entrance", not screen._entrance.is_running() and screen.modulate.a == 1.0)
		screen.set_active(true)
	await process_frame
	await process_frame
	var effect := button.get_node("CrystalSurface")
	var panel_effect := panel.get_node("CrystalSurface")
	_check("decoration preserves button geometry and minimum size", button.get_rect() == original_rect
		and button.get_combined_minimum_size() == original_minimum)
	_check("glass stays behind text and cannot intercept input", effect.show_behind_parent
		and effect._glass.mouse_filter == Control.MOUSE_FILTER_IGNORE and effect._glass.focus_mode == Control.FOCUS_NONE)
	_check("panel underlay fills the whole panel outside its content margins", panel_effect._glass.size == panel.size)
	_check("effects have no frame or physics processing loop", not effect.is_processing() and not effect.is_physics_processing()
		and not panel_effect.is_processing())
	_check("focus remains a native visible pair of brackets", not button.get_theme_stylebox("focus").draw_center
		and button.get_theme_stylebox("focus").border_width_left == UiTheme.FOCUS_WIDTH
		and button.get_theme_stylebox("focus").border_width_right == UiTheme.FOCUS_WIDTH)
	# The shader caps light in the text well, including the moving reflection.
	# Alpha is checked over white AND black; the native check samples actual pixels.
	var brightest := Color(0.10, 0.30, 0.10, UiTheme.PRIMARY.normal.a)
	_check("light text meets 4.5:1 at the brightest translucent glass interior", UiTheme.contrast(UiTheme.PRIMARY_TEXT, brightest) >= 4.5)
	if DisplayServer.get_name() != "headless":
		# Read the actual shader result against the most demanding bright backdrop.
		# Hide glyphs only for sampling, keeping native surface geometry and styles.
		var backdrop := ColorRect.new()
		backdrop.color = Color.WHITE
		backdrop.position = button.position
		backdrop.size = button.size
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(backdrop)
		screen.move_child(backdrop, 0)
		button.text = ""
		button.release_focus()
		await RenderingServer.frame_post_draw
		var rendered := root.get_texture().get_image()
		var origin := Vector2i(button.get_global_rect().position)
		var center := rendered.get_pixelv(origin + Vector2i(160, 28))
		var rim := rendered.get_pixelv(origin + Vector2i(160, 2))
		_check("rendered glass center keeps light text readable over white", UiTheme.contrast(UiTheme.PRIMARY_TEXT, center) >= 4.5)
		var worst_contrast := INF
		for x in range(14, 307, 12):
			for y in range(11, 46, 3):
				worst_contrast = minf(worst_contrast, UiTheme.contrast(UiTheme.PRIMARY_TEXT, rendered.get_pixelv(origin + Vector2i(x, y))))
		_check("the rendered text area stays readable across the glass reflections", worst_contrast >= 4.5)
		var focus_color: Color = button.get_theme_stylebox("focus").border_color
		_check("native focus brackets contrast with the actual glass beneath them",
			UiTheme.contrast(focus_color, rendered.get_pixelv(origin + Vector2i(10, 28))) >= 3.0
			and UiTheme.contrast(focus_color, rendered.get_pixelv(origin + Vector2i(309, 28))) >= 3.0)
		_check("rendered green fluorescence is concentrated at the lip", rim.g > center.g + 0.15 and rim.g > rim.r * 1.4)
		button.text = "Continue"
		backdrop.queue_free()
	button.grab_focus()
	_check("keyboard focus starts a finite shine", effect._shine_tween != null and effect._shine_tween.is_running())
	effect._shine_tween.custom_step(0.36)
	_check("the reflection advances through the surface", effect._material.get_shader_parameter("shine_progress") > 0.0)
	button.disabled = true
	effect._shine_tween.custom_step(0.016)
	_check("disabling an active button settles its motion", not effect._shine_tween.is_running()
		and effect._material.get_shader_parameter("shine_progress") == -1.0)
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		_check("disabled glass keeps its muted native fill", effect._material.get_shader_parameter("disabled") == 1.0
			and effect._material.get_shader_parameter("base_color") == UiTheme.PRIMARY.disabled)
	button.disabled = false
	button.release_focus()
	button.grab_focus()
	screen.set_active(false)
	_check("suspending a screen kills its decorative motion", not effect._shine_tween.is_running()
		and effect._material.get_shader_parameter("shine_progress") == -1.0)
	screen.set_active(true)
	button.release_focus()
	button.grab_focus()
	var theme_before: Theme = screen.theme
	UiTheme.reduced_motion = true
	effect._shine_tween.custom_step(0.016)
	_check("live reduced motion settles an active effect without a theme rebuild", screen.theme == theme_before
		and not effect._shine_tween.is_running() and effect._material.get_shader_parameter("shine_progress") == -1.0)
	button.release_focus()
	button.grab_focus()
	_check("reduced motion does not restart a shine", not effect._shine_tween.is_running())
	UiTheme.opaque_panels = true
	screen.theme = UiTheme.build()
	await process_frame
	await process_frame
	_check("theme replacement retains decoration and opaque surfaces", not button.get_theme_stylebox("normal").draw_center
		and panel_effect._sources[&"panel"].bg_color.a == 1.0 and effect._sources[&"normal"].bg_color.a == 1.0)
	var custom := StyleBoxFlat.new()
	custom.bg_color = Color.DARK_GREEN
	button.add_theme_stylebox_override("normal", custom)
	await process_frame
	_check("a screen-specific style override is preserved", button.get_theme_stylebox("normal") == custom)
	UiTheme.reduced_motion = false
	UiTheme.opaque_panels = false
	screen.queue_free()
	await process_frame
	await process_frame
	_check("screen teardown releases all decorative tweens", get_processed_tweens().is_empty())
	await _interaction_checks()
	print("Crystal UI: %d failed" % _failed)
	quit(1 if _failed else 0)


func _move_pointer(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func _mouse_button(position: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func _interaction_checks() -> void:
	InputMap.load_from_project_settings()
	UiInput.set_gamepad(UiDriver.FAKE_DEVICE)
	var driver := UiDriver.new(self)
	var screen := Screen.new()
	screen.size = Vector2(root.size)
	screen.theme = UiTheme.build()
	root.add_child(screen)
	var action := Widgets.button("Action", "PrimaryButton", "Action")
	action.position = Vector2(50, 100)
	action.size = Vector2(320, 56)
	screen.add_child(action)
	var choice := Widgets.button("Select", "HomeNav", "Choice")
	choice.position = Vector2(400, 100)
	choice.size = Vector2(320, 56)
	choice.toggle_mode = true
	screen.add_child(choice)
	action.focus_neighbor_right = choice.get_path()
	choice.focus_neighbor_left = action.get_path()
	var activations := [0]
	action.pressed.connect(func() -> void: activations[0] += 1)
	screen.open()
	await driver.settle()
	var effect: Node = action.get_node("CrystalSurface")
	var choice_effect: Node = choice.get_node("CrystalSurface")
	var original := action.get_rect()
	await _move_pointer(Vector2(80, 110))
	_check("pointer entry engages the actual native button", action.is_hovered() and effect._engaged)
	_check("pointer position drives a local glass reflection", effect._pointer_goal.x < 0.2 and effect._pointer_goal.y < 0.3)
	var sweep: Tween = effect._shine_tween
	await _mouse_button(Vector2(80, 110), true)
	_check("click focus does not restart an existing hover sweep", action.has_focus() and effect._shine_tween == sweep)
	await _move_pointer(Vector2(1000, 800))
	await _mouse_button(Vector2(1000, 800), false)
	_check("a cancelled press does not activate or play confirmation", activations[0] == 0 and effect._confirm_tween == null)
	await driver.tap(KEY_ENTER)
	_check("keyboard acceptance confirms exactly one native activation", activations[0] == 1 and effect._confirm_tween != null)
	effect._confirm_tween.custom_step(0.4)
	_check("confirmation returns to rest without a loop", not effect._confirm_tween.is_running()
		and is_zero_approx(float(effect._uniforms[&"confirmation"])))
	await driver.joy_button(JOY_BUTTON_DPAD_RIGHT)
	_check("selected gamepad moves focus and lights a secondary action", choice.has_focus() and choice_effect._engaged
		and choice_effect._base_goal == choice_effect._sources[&"hover"].bg_color)
	_check("secondary actions keep neutral material and native geometry", choice_effect._material.get_shader_parameter("primary") == -1.0
		and action.get_rect() == original and choice.size == Vector2(320, 56))
	await driver.joy_button(JOY_BUTTON_A)
	_check("gamepad selection retains the native toggle and confirms", choice.button_pressed and choice_effect._confirm_tween != null
		and choice.get_theme_stylebox("pressed").border_color == UiTheme.FOCUS)
	await driver.joy_button(JOY_BUTTON_DPAD_LEFT)
	_check("rapid navigation releases the old focus without moving controls", action.has_focus() and not choice_effect._engaged
		and action.get_rect() == original)
	effect._point_to(Vector2(0.9, 0.2))
	effect._confirm()
	UiTheme.reduced_motion = true
	for tween in get_processed_tweens():
		if tween.is_running(): tween.custom_step(0.016)
	_check("live reduced motion settles color, pointer and activation together", get_processed_tweens().all(func(tween: Tween) -> bool: return not tween.is_running())
		and effect._uniforms[&"pointer_uv"] == Vector2(0.5, 0.5) and effect._uniforms[&"confirmation"] == 0.0
		and effect._uniforms[&"base_color"] == effect._base_goal)
	UiTheme.reduced_motion = false
	# Reversible interruption must preserve the current color, not jump to either endpoint.
	effect._fade_base(Color(0.1, 0.2, 0.1, 0.8), true)
	effect._color_tween.pause()
	effect._color_tween.custom_step(0.04)
	var middle: Color = effect._uniforms[&"base_color"]
	effect._fade_base(Color(0.02, 0.08, 0.02, 0.76), true)
	_check("interrupting a color transition starts from its current value", effect._uniforms[&"base_color"] == middle)
	effect._point_to(Vector2(0.1, 0.8))
	effect._confirm()
	screen.set_active(false)
	_check("suspension settles every interaction channel", effect._uniforms[&"confirmation"] == 0.0
		and not effect._color_tween.is_running() and not effect._pointer_tween.is_running() and not effect._confirm_tween.is_running())
	screen.set_active(true)
	var custom := StyleBoxFlat.new()
	custom.bg_color = Color.DARK_RED
	action.add_theme_stylebox_override("normal", custom)
	action.release_focus()
	await driver.settle()
	effect._engage()
	_check("screen-owned surfaces neither get replaced nor run hidden effects", action.get_theme_stylebox("normal") == custom
		and not effect._glass.visible and not effect._engaged and not effect._shine_tween.is_running())
	choice.flat = true
	choice.set_pressed_no_signal(false)
	choice.release_focus()
	choice_effect._sync_state()
	_check("flat idle buttons keep their empty native background", not choice_effect._glass.visible)
	screen.queue_free()
	await driver.settle()
	UiInput.isolate_joypads()
	_check("extended interaction teardown leaves no active tweens", get_processed_tweens().is_empty())
