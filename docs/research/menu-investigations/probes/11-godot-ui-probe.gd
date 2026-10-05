# Sonda de la investigación 11 (menús): APIs y comportamiento GUI del Godot fijado.
# Ejecutar sin proyecto, fuera de app/:
#   .tools/Godot_v4.7.2-stable_linux.x86_64 --headless --script docs/research/menu-investigations/probes/11-godot-ui-probe.gd
# Imprime líneas "PROBE <clave> = <valor>". No escribe archivos.
extends SceneTree

func _p(k: String, v) -> void:
	print("PROBE %s = %s" % [k, v])

func _init() -> void:
	_run.call_deferred()

func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	root.push_input(e)

func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = at
		e.global_position = at
		e.pressed = pressed
		root.push_input(e)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	_p("version", Engine.get_version_info().string)
	for c in ["FoldableContainer", "FoldableGroup", "AccessibilityServer", "DPITexture", "VirtualJoystick"]:
		_p("class." + c, ClassDB.class_exists(c))
	for s in ["accessibility/general/accessibility_support", "accessibility/general/accessibility_driver",
			"gui/common/show_focus_state_on_pointer_event", "gui/fonts/dynamic_fonts/use_oversampling",
			"gui/theme/default_theme_scale"]:
		_p("setting." + s, ProjectSettings.get_setting(s))
	_p("display_server", DisplayServer.get_name())
	_p("a11y.server_supported", AccessibilityServer.is_supported())
	_p("a11y.screen_reader_active", DisplayServer.accessibility_screen_reader_active())
	_p("a11y.increase_contrast", DisplayServer.accessibility_should_increase_contrast())
	_p("a11y.reduce_animation", DisplayServer.accessibility_should_reduce_animation())
	# Comprobación en ejecución del hallazgo de la investigación 02. Sin --path, Godot usa
	# InputMap.load_default(), que solo añade teclas: esta lista sale vacía. Con un proyecto
	# (p. ej. una copia de app/project.godot en un directorio temporal y --path a esa copia)
	# ui_left/ui_up muestran D-pad y LEFT_X/LEFT_Y. No ejecutar con --path app.
	var joy := []
	for a in ["ui_left", "ui_up", "ui_accept", "ui_cancel", "ui_focus_next"]:
		for ev in InputMap.action_get_events(a):
			if ev is InputEventJoypadMotion or ev is InputEventJoypadButton:
				joy.append("%s:%s" % [a, ev.as_text()])
	_p("inputmap.joypad_ui_events", joy)

	# Escena mínima: menú con dos botones, panel bloqueado y FoldableContainer.
	var box := VBoxContainer.new()
	box.position = Vector2(10, 10)
	root.add_child(box)
	var fly := Button.new(); fly.text = "Volar"; box.add_child(fly)
	var quit_b := Button.new(); quit_b.text = "Salir"; box.add_child(quit_b)
	var blocked := VBoxContainer.new(); box.add_child(blocked)
	var under := Button.new(); under.text = "Debajo"; blocked.add_child(under)
	var fold := FoldableContainer.new(); fold.title = "Avanzado"; box.add_child(fold)
	var inner := Label.new(); inner.text = "contenido"; fold.add_child(inner)
	await _frames(3)

	fly.grab_focus()
	await _frames(1)
	_p("focus.grab_focus.visible", fly.has_focus(true))
	fly.grab_focus(true)
	await _frames(1)
	_p("focus.grab_focus_hidden.has_focus", fly.has_focus())
	_p("focus.grab_focus_hidden.visible", fly.has_focus(true))
	_click(quit_b.get_global_rect().get_center())
	await _frames(1)
	_p("focus.mouse_click.has_focus", quit_b.has_focus())
	_p("focus.mouse_click.visible", quit_b.has_focus(true))
	_key(KEY_UP, true); _key(KEY_UP, false)
	await _frames(1)
	_p("focus.after_key_up.owner", root.gui_get_focus_owner().name if root.gui_get_focus_owner() else "none")
	_p("focus.after_key_up.visible", fly.has_focus(true))

	blocked.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	blocked.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	await _frames(1)
	_p("recursive.child_focus_mode_override", under.get_focus_mode_with_override())
	_p("recursive.child_mouse_filter_override", under.get_mouse_filter_with_override())
	under.grab_focus()
	await _frames(1)
	_p("recursive.child_grab_focus_got_it", under.has_focus())
	quit_b.grab_focus()
	await _frames(1)
	_key(KEY_DOWN, true); _key(KEY_DOWN, false)
	await _frames(1)
	var o := root.gui_get_focus_owner()
	_p("recursive.key_down_from_salir_skips_blocked", o != under and o != null)
	_p("recursive.key_down_owner_class", o.get_class() if o else "none")

	_p("foldable.focus_mode", fold.focus_mode)
	_p("foldable.folded_before", fold.folded)
	fold.grab_focus()
	await _frames(1)
	_key(KEY_ENTER, true); _key(KEY_ENTER, false)
	await _frames(2)
	_p("foldable.folded_after_enter", fold.folded)
	_p("foldable.child_visible", inner.is_visible_in_tree())
	_p("scroll.scroll_hint_mode_default", ScrollContainer.new().scroll_hint_mode)
	box.queue_free()
	# Issue #103726: ¿las flechas alcanzan botones fuera de la vista de un ScrollContainer?
	for follow in [false, true]:
		var sc := ScrollContainer.new()
		sc.position = Vector2(400, 10)
		sc.size = Vector2(200, 100)
		sc.follow_focus = follow
		root.add_child(sc)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(list)
		var buttons := []
		for i in 12:
			var b := Button.new(); b.text = "Ajuste %d" % i
			list.add_child(b); buttons.append(b)
		await _frames(3)
		buttons[0].grab_focus()
		await _frames(1)
		for i in 11:
			_key(KEY_DOWN, true); _key(KEY_DOWN, false)
			await _frames(1)
		var owner := root.gui_get_focus_owner()
		_p("scroll.follow_focus_%s.reached_last" % follow, owner == buttons[11])
		_p("scroll.follow_focus_%s.scroll_vertical" % follow, sc.scroll_vertical)
		sc.queue_free()
		await _frames(1)
	# custom_maximum_size (4.7): limitar el ancho de lectura en formato ancho.
	var row := HBoxContainer.new(); row.size = Vector2(1600, 200); root.add_child(row)
	var panel := PanelContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_maximum_size = Vector2(640, -1); row.add_child(panel)
	var image := ColorRect.new(); image.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(image)
	await _frames(3)
	_p("max_size.panel_width", panel.size.x)
	_p("max_size.image_width", image.size.x)
	row.queue_free()
	await _frames(1)
	quit()
