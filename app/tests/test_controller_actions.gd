extends SceneTree

const ControllerActions := preload("res://input/controller_actions.gd")

var failures := 0


func _initialize() -> void:
	var defaults := ControllerActions.default_bindings()
	_check("default semantic actions have recovery and no overlapping conflicts", ControllerActions.validate(defaults).ok)
	var other_pad := _button_event(2, JOY_BUTTON_A, true)
	var selected_pad := _button_event(7, JOY_BUTTON_A, true)
	var release := _button_event(7, JOY_BUTTON_A, false)
	_check("same button on another device is ignored", ControllerActions.resolve_event(other_pad, defaults, 7, "menu").is_empty())
	_check("selected-device A resolves to menu accept", ControllerActions.resolve_event(selected_pad, defaults, 7, "menu") == PackedStringArray(["accept"]))
	_check("button release produces no semantic action", ControllerActions.resolve_event(release, defaults, 7, "menu").is_empty())
	_check("menu navigation is not routed as flight trim", ControllerActions.resolve_event(_button_event(7, JOY_BUTTON_DPAD_UP, true), defaults, 7, "flight").has("trim_up"))
	_check("menu navigation resolves only in menu context", ControllerActions.resolve_event(_button_event(7, JOY_BUTTON_DPAD_UP, true), defaults, 7, "menu").has("navigate_up"))
	_check("axis threshold resolves matching sign on selected device", ControllerActions.resolve_event(_axis_event(7, JOY_AXIS_LEFT_X, -0.8), {"trim_left": {"type": "axis", "axis": JOY_AXIS_LEFT_X, "sign": -1, "threshold": 0.65}}, 7, "flight").has("trim_left"))
	_check("axis value below threshold does not resolve", ControllerActions.resolve_event(_axis_event(7, JOY_AXIS_LEFT_X, -0.2), {"trim_left": {"type": "axis", "axis": JOY_AXIS_LEFT_X, "sign": -1, "threshold": 0.65}}, 7, "flight").is_empty())
	var key_bindings := defaults.duplicate(true)
	key_bindings["accept"] = {"type": "key", "physical_keycode": KEY_Q, "keycode": KEY_Q}
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Q
	key.keycode = KEY_Q
	key.pressed = true
	_check("keyboard remap resolves without a gamepad id", ControllerActions.resolve_event(key, key_bindings, -1, "menu").has("accept"))
	key.pressed = false
	_check("keyboard release produces no semantic action", ControllerActions.resolve_event(key, key_bindings, -1, "menu").is_empty())
	var conflict := defaults.duplicate(true)
	conflict["pause"] = conflict["back"].duplicate(true)
	_check("duplicate back/pause recovery binding is rejected", not ControllerActions.validate(conflict).ok)
	var invalid_range := defaults.duplicate(true)
	invalid_range["accept"] = {"type": "button", "button": JOY_BUTTON_MAX}
	_check("the sentinel button index is rejected", not ControllerActions.validate(invalid_range).ok)
	TranslationServer.set_locale("es")
	_check("semantic action labels translate to Spanish", TranslationServer.translate("Navigate up") == "Navegar arriba")
	_check("controller binding labels translate to Spanish", ControllerActions.binding_text({"type": "button", "button": JOY_BUTTON_BACK}) == "Atrás / Compartir")
	_check("pause recovery notice translates to Spanish", TranslationServer.translate("Release the controls to neutral before continuing; use Controls to select a disconnected device.") == "Suelta los controles y déjalos en posición neutra antes de continuar; usa Controles para seleccionar un dispositivo desconectado.")
	_check("controller form and axis controls are translated", TranslationServer.translate("Name") == "Nombre" and TranslationServer.translate("Unknown joystick") == "Palanca de mando desconocida" and TranslationServer.translate("Channel") == "Canal" and TranslationServer.translate("Source axis") == "Eje de origen" and TranslationServer.translate("Deadzone") == "Zona muerta" and TranslationServer.translate("Expo") == "Exponencial" and TranslationServer.translate("Invert") == "Invertir")
	_check("rate and absolute throttle presets are distinguished in Spanish", TranslationServer.translate("Mode 2 · rate throttle") == "Modo 2 · acelerador incremental" and TranslationServer.translate("Trigger throttle") == "Acelerador absoluto en gatillo")
	_check("radio recovery, profile type and safety prompts translate", TranslationServer.translate("Calibrate selected radio") == "Calibrar la radio seleccionada" and TranslationServer.translate("Profile type") == "Tipo de perfil" and TranslationServer.translate("Device selection changed; refresh and choose connected controllers.") == "La selección de controles cambió; actualiza la lista y elige controles conectados." and TranslationServer.translate("GAMEPAD SAFE · move controls, then release") == "GAMEPAD SEGURO · mueve los controles y suéltalos" and TranslationServer.translate("CONTROLLER LOST · select controls to continue") == "CONTROL DESCONECTADO · selecciona controles para continuar")
	var safety_translations := {
		"Controller unavailable. Select a connected device or keyboard in Controller settings.": "Controlador no disponible. Elige un dispositivo conectado o el teclado en Configuración de controles.",
		"Move each mapped control once, release sticks and triggers, then wait for neutral. Continue is an explicit action.": "Mueve una vez cada control asignado, suelta las palancas y los gatillos y espera el neutro. Debes elegir Continuar explícitamente.",
		"Lower the throttle to arm. If the mapping is wrong, open Controller settings and calibrate the selected radio.": "Baja el acelerador para armar. Si la asignación no es correcta, abre Configuración de controles y calibra la radio seleccionada.",
	}
	var safety_translations_ok := true
	for source in safety_translations:
		safety_translations_ok = safety_translations_ok and TranslationServer.translate(source) == safety_translations[source]
	_check("controller setup and arming prompts translate", safety_translations_ok)
	TranslationServer.set_locale("en")
	print("all controller action checks passed" if failures == 0 else "%d controller action checks failed" % failures)
	quit(1 if failures > 0 else 0)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label)


func _button_event(device_id: int, button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device_id
	event.button_index = button
	event.pressed = pressed
	return event


func _axis_event(device_id: int, axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device_id
	event.axis = axis
	event.axis_value = value
	return event
