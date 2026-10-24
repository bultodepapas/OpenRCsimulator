## UI-22-R4: crystal decoration preserves controls, settles when hidden and respects live motion policy.
extends SceneTree

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
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
	print("Crystal UI: %d failed" % _failed)
	quit(1 if _failed else 0)
