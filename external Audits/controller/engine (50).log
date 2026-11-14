extends Node
const ControllerActions = preload("res://input/controller_actions.gd")
const UiInput = preload("res://ui/ui_input.gd")
class Catalog:
	static func is_rotorcraft(_id): return false
class ScreenStack:
	static func _surface(_screen): return null
class Screens extends RefCounted:
	func top(): return null
	func is_top(_name): return false
var controllers
var ground_vehicle = null
var flight = null
var home = null
var screens = Screens.new()
var _exit_request_active = false
var _radio_menu_ingress_connected = true
var _radio_menu_input = null
var _radio_menu_identity = {}
var _controller_action_edges = {}
var _controller_action_require_off = {}
var _controller_action_identities = {}
var _controller_edge_identities = {}
var _controller_edge_require_off = {}
var _controller_restart_edges = {}
var _controller_rate_edges = {}
func _observe_radio_menu_event(_event): pass
func _request_flight_restart(): pass
func open_pause(): pass
func open_controls(): pass
func _radio_menu_popup(): return null


func _controller_bindings(id: int, flight_context := false) -> Dictionary:
	if controllers != null and id >= 0:
		var profile: Dictionary = controllers.profile_for_device(id)
		if profile.is_empty() or not bool(profile.get("configured", true)):
			return ControllerActions.clean_radio_bindings()
		if flight_context:
			var capabilities: Dictionary = ControllerActions.AIRPLANE_CAPABILITIES
			if flight != null and flight.has_method("controller_capabilities"):
				capabilities = flight.controller_capabilities()
			elif home != null and Catalog.is_rotorcraft(home.aircraft_id):
				capabilities = ControllerActions.HELICOPTER_CAPABILITIES
			return ControllerActions.effective_bindings(profile, capabilities)
		return ControllerActions.effective_bindings(profile)
	return ControllerActions.default_bindings()




func _input(event: InputEvent) -> void:
	if controllers == null: return
	if ground_vehicle != null: return # ground sampler and garage own their distinct control scheme
	if UiInput.is_selected_radio_action(event):
		if event.is_action_pressed("ui_cancel") and not _exit_request_active:
			if screens.top() != null:
				var surface: Control = ScreenStack._surface(screens.top())
				if surface != null: surface.close_requested.emit()
			elif flight != null and flight.has_method("accident_menu_active") and flight.accident_menu_active():
				if bool(event.get_meta("openrc_radio_pause", false)): open_pause()
				else: flight.controller_action("back")
			get_viewport().set_input_as_handled()
		return
	if not _radio_menu_ingress_connected: _observe_radio_menu_event(event)
	if event is not InputEventJoypadButton and event is not InputEventJoypadMotion and event is not InputEventKey: return
	# The same saved Back key may also be installed in native ui_cancel. Keep it
	# available to the editor for this event, including repeats, then restore it.
	if event is InputEventKey and not _exit_request_active and screens.top() != null and _focused_editor_consumes_key(event) \
			and event.keycode != KEY_ESCAPE and event.physical_keycode != KEY_ESCAPE:
		var ui_id: int = controllers.registry.selected_device_id("ui")
		var back: Dictionary = _controller_bindings(ui_id).get("back", {})
		if ControllerActions.matches_binding(back, event, ui_id) and UiInput.suspend_generated_cancel_key():
			UiInput.restore_generated_cancel_key.call_deferred()
	if event is InputEventKey and event.echo: return
	# Both observers need releases, including opposite directions of a shared axis.
	var restart_handled := _route_controller_restart(event)
	var rates_handled := _route_controller_rates(event)
	_sync_controller_generic_actions()
	var source := ControllerActions.event_source(event)
	if source.is_empty(): return
	var previous: PackedStringArray = _controller_action_edges.get(source, PackedStringArray())
	# Observe the selected flight device even when another device (or keyboard)
	# owns menus. Nonfinite samples cannot erase an activation or establish OFF.
	if event is InputEventJoypadMotion and not is_finite(event.axis_value): return
	var observed := PackedStringArray()
	for role: String in ["flight", "ui"]:
		var observer_id: int = controllers.registry.selected_device_id(role)
		if observer_id < 0: continue
		var observer_bindings := _controller_bindings(observer_id, role == "flight")
		for action_id: String in observer_bindings:
			var blocked_key := "%d:%s" % [observer_id, action_id]
			if _controller_action_require_off.has(blocked_key) and _controller_binding_observed_off(
				event, observer_id, _controller_action_require_off[blocked_key], action_id):
				_controller_action_require_off.erase(blocked_key)
		for action_id: String in ControllerActions.resolve_event(event, observer_bindings, observer_id, "both" if role == "flight" else "menu", previous):
			if not observed.has(action_id): observed.append(action_id)
	if observed.is_empty(): _controller_action_edges.erase(source)
	else: _controller_action_edges[source] = observed
	var in_menu := screens.top() != null
	var calibrating: bool = flight != null and flight.session != null and flight.session.calibration != null
	var accident_menu: bool = not in_menu and flight != null and flight.has_method("accident_menu_active") and flight.accident_menu_active()
	var menu_context := in_menu or calibrating or accident_menu
	if menu_context:
		_release_controller_holds()
		var flight_id: int = controllers.registry.selected_device_id("flight")
		var flight_bindings := _controller_bindings(flight_id, true)
		for action_id: String in observed:
			if ControllerActions.action_definition(action_id).get("mode", "press") == "hold" and flight_bindings.has(action_id):
				_controller_action_require_off["%d:%s" % [flight_id, action_id]] = flight_bindings[action_id].duplicate(true)
	var id: int = controllers.registry.selected_device_id("ui" if menu_context else "flight")
	if id < 0: return
	var actions: PackedStringArray = ControllerActions.resolve_event(event, _controller_bindings(id, not menu_context), id, "menu" if menu_context else "flight", previous)
	if _exit_request_active:
		_release_controller_holds()
		return # decision dialogs own input; observe edges without dispatching flight/menu actions
	if flight != null and flight.session != null and flight.session.has_method("set_controller_cut"):
		var held := false
		if not menu_context and not _controller_action_require_off.has("%d:throttle_cut" % id):
			var cut_binding: Dictionary = _controller_bindings(id, true).get("throttle_cut", {})
			var cut_source := _controller_binding_source(cut_binding, id)
			held = _controller_action_edges.get(cut_source, PackedStringArray()).has("throttle_cut")
		flight.session.set_controller_cut(held)
	# Edge observers consume presses only after ordinary holds have seen the release.
	if restart_handled or rates_handled:
		get_viewport().set_input_as_handled()
		return
	for action: String in actions:
		if previous.has(action): continue
		if _controller_action_require_off.has("%d:%s" % [id, action]): continue
		# A held menu source cannot become a flight command, including signed axes.
		if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and not previous.is_empty(): continue
		if menu_context and _radio_menu_input != null and event.device == int(_radio_menu_identity.get("id", -1)) \
				and action in ["back", "pause"]: continue
		if in_menu:
			if action in ["back", "pause"] and (_focused_editor_consumes_key(event) or _controller_capture_owns(event)): continue
			if action == "calibrate" and (screens.is_top("home") or screens.is_top("pause")):
				open_controls()
				get_viewport().set_input_as_handled()
				return
			if action not in ["back", "pause"]: continue
			var focused := get_viewport().gui_get_focus_owner()
			if _radio_menu_popup() != null:
				_radio_menu_popup().hide()
			elif focused is OptionButton and focused.get_popup().visible:
				focused.get_popup().hide()
			else:
				var surface: Control = ScreenStack._surface(screens.top())
				if surface != null: surface.close_requested.emit()
			get_viewport().set_input_as_handled()
			return
		elif flight != null and flight.controller_action(action):
			get_viewport().set_input_as_handled()
			if calibrating and flight.session.calibration == null: open_pause.call_deferred()
			return


## Editable text keeps its editing keys, including user-remapped Back keys and
## modifiers. Escape remains the deliberate way to leave the current screen.


func _route_controller_restart(event: InputEvent) -> bool:
	var id: int = controllers.registry.selected_device_id("flight")
	if id < 0: return false
	var binding: Dictionary = _controller_bindings(id, true).get("restart_flight", {"type": "unbound"})
	var transition := _controller_edge_transition(event, "restart_flight", id, binding)
	var previous: PackedStringArray = transition.previous
	var actions: PackedStringArray = transition.actions
	if actions.is_empty() or flight == null or flight.session == null: return false
	if _exit_request_active or screens.top() != null or flight.session.calibration != null: return false
	if previous.is_empty():
		_request_flight_restart()
	return true




func _route_controller_rates(event: InputEvent) -> bool:
	var id: int = controllers.registry.selected_device_id("flight")
	if id < 0: return false
	var binding: Dictionary = _controller_bindings(id, true).get("rates_toggle", {"type": "unbound"})
	var transition := _controller_edge_transition(event, "rates_toggle", id, binding)
	var previous: PackedStringArray = transition.previous
	var actions: PackedStringArray = transition.actions
	if actions.is_empty() or flight == null or flight.session == null: return false
	if _exit_request_active or screens.top() != null or flight.session.calibration != null: return false
	if flight.has_method("accident_menu_active") and flight.accident_menu_active(): return false
	if previous.is_empty(): flight.controller_action("rates_toggle")
	return true


## Restart belongs to the flight device even when a separate pad navigates the crash report.
## Observe its edge in menus too: holding a switch while closing setup cannot queue a reset.


func _controller_edge_transition(event: InputEvent, action: String, id: int, binding: Dictionary) -> Dictionary:
	_sync_controller_edge_identity(action, id, binding)
	if event is InputEventJoypadMotion and not is_finite(event.axis_value):
		return {"actions": PackedStringArray(), "previous": PackedStringArray()}
	var source := ControllerActions.event_source(event)
	if source.is_empty(): return {"actions": PackedStringArray(), "previous": PackedStringArray()}
	var edges := _controller_edges_for(action)
	var only_binding := {action: binding}
	var previous: PackedStringArray = edges.get(source, PackedStringArray())
	if bool(_controller_edge_require_off.get(action, false)):
		# Treat a blocked assignment as active until its own OFF is observed.
		var held := PackedStringArray([action])
		var actions := ControllerActions.resolve_event(event, only_binding, id, "flight", held)
		if _controller_binding_observed_off(event, id, binding, action):
			_controller_edge_require_off[action] = false
			edges.erase(source)
		return {"actions": actions, "previous": held}
	var actions := ControllerActions.resolve_event(event, only_binding, id, "flight", previous)
	if actions.is_empty(): edges.erase(source)
	else: edges[source] = actions
	return {"actions": actions, "previous": previous}




func _sync_controller_edge_identity(action: String, id: int, binding: Dictionary) -> void:
	var identity := {"device": id, "generation": controllers.registry.connection_generation(id),
		"binding": binding.duplicate(true)}
	if not _controller_edge_identities.has(action):
		_controller_edge_identities[action] = identity
		_controller_edge_require_off[action] = id >= 0 and binding.get("type", "unbound") != "unbound"
		return
	if _controller_edge_identities[action] != identity:
		_controller_edge_identities[action] = identity
		_controller_edges_for(action).clear()
		_controller_edge_require_off[action] = id >= 0 and binding.get("type", "unbound") != "unbound"




func _controller_edges_for(action: String) -> Dictionary:
	return _controller_restart_edges if action == "restart_flight" else _controller_rate_edges


## An unrelated event, a nonfinite axis value, or threshold jitter is not an OFF
## observation. Direction reversal is OFF for the opposite signed assignment.


func _controller_binding_observed_off(event: InputEvent, id: int, binding: Dictionary, action: String) -> bool:
	match str(binding.get("type", "")):
		"button":
			return event is InputEventJoypadButton and event.device == id \
				and event.button_index == int(binding.get("button", -1)) and not event.pressed
		"axis":
			if not event is InputEventJoypadMotion or event.device != id \
					or event.axis != int(binding.get("axis", -1)) or not is_finite(event.axis_value):
				return false
			return not ControllerActions.matches_binding(binding, event, id, true)
		"key":
			if not event is InputEventKey or event.pressed:
				return false
			var physical := int(binding.get("physical_keycode", 0))
			return event.physical_keycode == physical if physical != 0 else event.keycode == int(binding.get("keycode", 0))
	return false




func _sync_controller_generic_actions(require_off := false) -> void:
	var id: int = controllers.registry.selected_device_id("flight")
	var bindings := _controller_bindings(id, true)
	var kind := str(controllers.profile_for_device(id).get("kind", ""))
	for action_id: String in bindings:
		if ControllerActions.action_definition(action_id).get("context", "menu") not in ["flight", "both"]: continue
		var binding: Dictionary = bindings[action_id]
		var identity := {device = id, generation = controllers.registry.connection_generation(id), binding = binding.duplicate(true)}
		var changed: bool = _controller_action_identities.has(action_id) and _controller_action_identities[action_id] != identity
		if changed:
			var old_id: int = _controller_action_identities[action_id].device
			_controller_action_require_off.erase("%d:%s" % [old_id, action_id])
		var first_raw_device := not _controller_action_identities.has(action_id) and kind in ["radio", "joystick"]
		_controller_action_identities[action_id] = identity
		if (changed or require_off or first_raw_device) and id >= 0 and binding.get("type", "unbound") in ["button", "axis"]:
			_controller_action_require_off["%d:%s" % [id, action_id]] = binding.duplicate(true)


## Mapped gamepads can establish released controls from the same trusted live
## poll used by flight readiness. Raw radios still require actual OFF events.


func _release_controller_holds() -> void:
	if controllers != null:
		var id: int = controllers.registry.selected_device_id("flight")
		var bindings := _controller_bindings(id, true)
		for action_id: String in bindings:
			var source := _controller_binding_source(bindings[action_id], id)
			if ControllerActions.action_definition(action_id).get("mode", "press") == "hold" \
				and _controller_action_edges.get(source, PackedStringArray()).has(action_id):
				_controller_action_require_off["%d:%s" % [id, action_id]] = bindings[action_id].duplicate(true)
	if flight != null and flight.session != null and flight.session.has_method("set_controller_cut"):
		flight.session.set_controller_cut(false)




static func _controller_binding_source(binding: Dictionary, id: int) -> String:
	match str(binding.get("type", "")):
		"axis": return "%d:axis:%d" % [id, int(binding.get("axis", -1))]
		"button": return "%d:button:%d" % [id, int(binding.get("button", -1))]
		"key": return "key:%d" % int(binding.get("physical_keycode", 0) if binding.get("physical_keycode", 0) != 0 else binding.get("keycode", 0))
	return ""




func _focused_editor_consumes_key(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var focused := get_viewport().gui_get_focus_owner()
	if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
		return focused is LineEdit and focused.editable and focused.is_editing()
	return (focused is LineEdit and focused.editable) or (focused is TextEdit and focused.editable)




func _controller_capture_owns(event: InputEvent) -> bool:
	if screens.top() != null and screens.top().has_method("owns_controller_event") \
			and screens.top().owns_controller_event(event): return true
	if not screens.is_top("controls"):
		return false
	var setup: Node = screens.top()
	if not setup.has_method("_is_capture_active") or not setup._is_capture_active():
		return false
	return event is InputEventKey or ((event is InputEventJoypadButton or event is InputEventJoypadMotion) \
		and event.device == int(setup.get("_capturing_device_id")))


## Observe rate controls even while another device owns menus. Held buttons/axes must
## return OFF before selecting a new rate after closing a menu or calibration.
