extends Node
## Non-flight input adapter for the HX-700 articulated inspection scene.
## ControllerService retains device identity and profile ownership; RcInput owns
## channel normalization, calibration, gamepad shaping and radio arming evidence.

const ControllerService := preload("res://input/controller_service.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const RcInput := preload("res://input/rc_input.gd")

const MIN_COLLECTIVE_DEG := -13.0
const MAX_COLLECTIVE_DEG := 13.0

signal interrupted(reason: String)
signal devices_changed

var service = ControllerService.new()
var radio = RcInput.new()
var enabled := false

# ControllerService's active-session contract. This inspector does not advance
# a flight session, but the service still needs an owner for explicit selection.
var external_controller_selection := true
var persist_controller_profile: Callable
var persist_full_controller_profile: Callable
var _controller_lost := false

## Injectable seams keep input policy testable without physical hardware.
var read_axis: Callable
var read_button: Callable
var focus_reader: Callable

var _held_inputs := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _collective_pose_deg := 0.0
var _status := "Control del mando desactivado."
var _profile_rejection := ""
var _session_attached := false


func _init() -> void:
	service.allow_automatic_selection = func() -> bool: return true
	add_child(service)
	read_axis = func(device_id: int, axis: int) -> float:
		return Input.get_joy_axis(device_id, axis)
	read_button = func(device_id: int, button: int) -> bool:
		return Input.is_joy_button_pressed(device_id, button)
	focus_reader = func() -> bool:
		if not is_inside_tree():
			return false
		var window := get_window()
		return window != null and window.has_focus()
	service.registry.devices_changed.connect(_on_registry_devices_changed)


func _ready() -> void:
	if not _session_attached:
		_session_attached = true
		service.attach_session(self, true)
	var window := get_window()
	if window != null and not window.focus_exited.is_connected(controller_focus_lost):
		window.focus_exited.connect(controller_focus_lost)


func selected_id() -> int:
	return int(service.registry.selected_device_id("flight"))


func select_device(id: int) -> bool:
	if id < -1:
		_status = "El dispositivo seleccionado no es válido."
		return false
	if id >= 0:
		var info: Dictionary = service.registry.device_for_id(id)
		if not bool(info.get("connected", false)):
			_status = "El mando ya no está conectado."
			return false
	var ui_id: int = int(service.registry.selected_device_id("ui"))
	var selected := bool(service.select_devices(id, ui_id))
	if selected and selected_id() == id and id < 0:
		_status = "Sin mando seleccionado; la pose se conserva."
	# An unconfigured joystick can still be explicitly selected so the inspector
	# can explain why it is unavailable. The route callback leaves it disabled.
	return selected or selected_id() == id


func enable(current_collective_deg: float) -> bool:
	if not is_finite(current_collective_deg) or current_collective_deg < MIN_COLLECTIVE_DEG or current_collective_deg > MAX_COLLECTIVE_DEG:
		_status = "La posición de colectivo está fuera del intervalo del rotor."
		return false
	_collective_pose_deg = current_collective_deg
	_held_inputs[0] = _collective_pose_deg
	if _profile_rejection.is_empty() and radio.connected:
		_held_inputs[1] = 0.0
		_held_inputs[2] = 0.0
		_held_inputs[3] = 0.0
	if not _profile_rejection.is_empty():
		_status = _profile_rejection
		return false
	if selected_id() < 0 or not radio.connected or radio.device_id != selected_id():
		_status = "Selecciona un mando conectado antes de activarlo."
		return false
	var profile_error := controller_profile_rejection(radio.profile)
	if not profile_error.is_empty():
		_profile_rejection = profile_error
		_status = profile_error
		return false
	if not _has_focus():
		_status = "La ventana no tiene el foco; vuelve a activarlo desde el inspector."
		return false
	if _controller_lost:
		_status = "Vuelve a seleccionar el mando para recuperar el control."
		return false

	_held_inputs = PackedFloat64Array([_collective_pose_deg, 0.0, 0.0, 0.0])
	radio.require_neutral(true, true)
	if radio.is_rate_throttle():
		var seed := (_collective_pose_deg - MIN_COLLECTIVE_DEG) / (MAX_COLLECTIVE_DEG - MIN_COLLECTIVE_DEG)
		if not radio.set_rate_throttle_for_start(seed):
			_status = "No se pudo conservar el colectivo inicial del mando."
			return false
	enabled = true
	_status = "Mando activo; verifica los controles antes de mover el rotor."
	return true


func disable() -> void:
	var was_enabled := enabled
	enabled = false
	if radio.connected:
		radio.require_neutral(true, true)
	if was_enabled:
		_status = "Control del mando desactivado; pose conservada."


func sample(dt: float, paused: bool) -> Dictionary:
	if not is_finite(dt) or dt < 0.0:
		_status = "Intervalo de muestreo no válido; pose conservada."
		return _result(false, false)
	if enabled and not _has_focus():
		controller_focus_lost()
		return _result(false, false)
	if enabled and (selected_id() < 0 or selected_id() != radio.device_id or not _selected_device_connected()):
		controller_disconnected()
		return _result(false, false)
	if not _profile_rejection.is_empty():
		_status = _profile_rejection
		return _result(false, false)
	if not radio.connected:
		return _result(true, false)
	if not read_axis.is_valid():
		_status = "No hay lector de ejes disponible; pose conservada."
		return _result(false, false)

	var integrate := enabled and not paused
	radio.poll(read_axis, dt, read_button, integrate)
	if not radio.input_error.is_empty() or not radio.profile_error.is_empty():
		var reason := "Lectura del mando inválida; control detenido y pose conservada."
		_interrupt(reason)
		return _result(false, false)
	if not enabled:
		return _result(true, false)
	if paused:
		_status = "Inspector pausado; pose conservada."
		return _result(true, false)
	if not radio.armed:
		_status = "Baja el acelerador para habilitar el mando." if not radio.is_rate_throttle() else "Esperando una lectura válida del mando."
		return _result(true, false)

	var sticks: Dictionary = radio.sticks()
	var collective := MIN_COLLECTIVE_DEG + clampf(float(sticks.get("throttle", 0.0)), 0.0, 1.0) * (MAX_COLLECTIVE_DEG - MIN_COLLECTIVE_DEG)
	_collective_pose_deg = collective
	_held_inputs = PackedFloat64Array([
		_collective_pose_deg,
		clampf(float(sticks.get("roll", 0.0)), -1.0, 1.0) * 10.0,
		clampf(float(sticks.get("pitch", 0.0)), -1.0, 1.0) * 10.0,
		clampf(float(sticks.get("yaw", 0.0)), -1.0, 1.0) * 20.0,
	])
	_status = "Mando activo; colectivo %.1f°." % _collective_pose_deg
	return _result(true, true)


func handle_event(event: InputEvent) -> bool:
	if event == null or not radio.connected or selected_id() != radio.device_id:
		return false
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.device != radio.device_id:
			return false
		radio.on_motion(motion.device, int(motion.axis), motion.axis_value)
		return true
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if button.device != radio.device_id:
			return false
		radio.on_button(button.device, int(button.button_index), button.pressed)
		return true
	return false


func controller_profile_rejection(candidate: Variant) -> String:
	var validation := ControllerProfile.validate(candidate)
	if not bool(validation.get("ok", false)):
		return "El perfil del mando está vacío o no es válido."
	var profile: Dictionary = candidate
	var kind := str(profile.get("kind", ""))
	var throttle_mode := str(profile.get("throttle_mode", ""))
	if kind == "gamepad" and throttle_mode != "stick_rate":
		return "El inspector HX-700 requiere acelerador de palanca; no admite gatillos de avión."
	if kind in ["radio", "joystick"] and throttle_mode != "radio_absolute":
		return "El perfil de radio o joystick requiere acelerador absoluto calibrado."
	return ""


func apply_controller_selection(device: int, info: Dictionary, profile: Dictionary, _initial_start := false) -> bool:
	if enabled:
		_interrupt("Cambió el mando seleccionado; la pose se conserva.")
	radio.disconnect_device()
	_profile_rejection = ""
	_controller_lost = false
	if device < 0:
		_status = "Sin mando seleccionado; la pose se conserva."
		return true
	if not bool(info.get("connected", false)):
		_profile_rejection = "El mando no está conectado."
		_status = _profile_rejection
		_controller_lost = true
		return false
	_profile_rejection = controller_profile_rejection(profile)
	if not _profile_rejection.is_empty():
		_status = _profile_rejection
		_controller_lost = true
		return false
	radio.connect_device(device, info, profile)
	_status = "Mando configurado; activa el control cuando estés preparado."
	return true


func controller_disconnected() -> void:
	var was_enabled := enabled
	enabled = false
	radio.disconnect_device()
	_profile_rejection = ""
	_controller_lost = true
	_status = "Mando desconectado; pose conservada. Selección manual necesaria."
	if was_enabled:
		interrupted.emit(_status)


func controller_focus_lost() -> void:
	var was_enabled := enabled
	enabled = false
	if radio.connected:
		radio.require_neutral(true, true)
	_status = "Se perdió el foco de la ventana; vuelve a activar el mando. Pose conservada."
	if was_enabled:
		interrupted.emit(_status)


func _selected_device_connected() -> bool:
	var info: Dictionary = service.registry.device_for_id(selected_id())
	return bool(info.get("connected", false))


func _has_focus() -> bool:
	if focus_reader.is_valid():
		return bool(focus_reader.call())
	if not is_inside_tree():
		return false
	var window := get_window()
	return window != null and window.has_focus()


func _result(ok: bool, active: bool) -> Dictionary:
	return {"ok": ok, "active": active, "inputs": _held_inputs.duplicate(), "status": _status}


func _interrupt(reason: String) -> void:
	var was_enabled := enabled
	enabled = false
	if radio.connected:
		radio.require_neutral(true, true)
	_status = reason
	if was_enabled:
		interrupted.emit(reason)


func _on_registry_devices_changed() -> void:
	devices_changed.emit()
