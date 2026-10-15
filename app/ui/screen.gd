# UI-21: shared screen surface. Home inherits it; CanvasLayer screens keep their wrappers and mount it.
# Chrome stays configurable so the existing layout and node paths are preserved byte-for-byte in captures.
extends Control

const ScreenTheme := preload("res://ui/ui_theme.gd")
const ScreenWidgets := preload("res://ui/widgets.gd")

signal close_requested

enum Kind { SIDEBAR, MODAL, TOAST }
var kind: Kind = Kind.MODAL
var escape_before_gui := false
var dismiss_option_popup_first := false
var return_focus: Control
var _active := true
var _focus_policy: FocusBehaviorRecursive
var _mouse_policy: MouseBehaviorRecursive
var _entrance: Tween


static func mount(host: CanvasLayer, node_name: String = "") -> Control:
	var surface := load("res://ui/screen.gd").new() as Control
	if node_name != "":
		surface.name = node_name
	surface.theme = ScreenTheme.build()
	surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(surface)
	return surface


func dim(opacity: float, node_name: String = "") -> ColorRect:
	var rect := ColorRect.new()
	if node_name != "":
		rect.name = node_name
	rect.color = Color(0.0, 0.0, 0.0, opacity)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	return rect


func center(gutter: float = 0.0) -> CenterContainer:
	var container := CenterContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.offset_left = gutter
	container.offset_top = gutter
	container.offset_right = -gutter
	container.offset_bottom = -gutter
	add_child(container)
	return container


func fade(width: int) -> TextureRect:
	var rect := ScreenWidgets.sidebar_fade(width)
	add_child(rect)
	return rect


## The stack opens after attach, without an extra frame or a tween (motion is a later step).
func open(from: Control = null) -> void:
	return_focus = from
	set_active(true)
	if is_inside_tree() and not ScreenTheme.reduced_motion and not DisplayServer.get_name() == "headless":
		if _entrance != null: _entrance.kill()
		modulate.a = 0.0
		_entrance = create_tween()
		_entrance.tween_property(self, "modulate:a", 1.0, 0.14)


func close(restore_focus := true) -> void:
	if _entrance != null: _entrance.kill()
	modulate.a = 1.0
	if restore_focus and is_instance_valid(return_focus) and return_focus.is_inside_tree() \
		and return_focus.is_visible_in_tree() and return_focus.focus_mode != Control.FOCUS_NONE:
		return_focus.grab_focus()
	return_focus = null


## Keep lower screens drawn, but remove all of their controls from mouse and keyboard navigation.
# Recursive policies also cover controls rebuilt while a lower screen is suspended (research 11).
func set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	visible = active # a child page replaces navigation chrome, retaining the live/frozen 3D scene
	set_process_input(active)
	set_process_unhandled_input(active)
	if not active:
		_focus_policy = focus_behavior_recursive
		_mouse_policy = mouse_behavior_recursive
		focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
		mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	else:
		focus_behavior_recursive = _focus_policy
		mouse_behavior_recursive = _mouse_policy


func _input(event: InputEvent) -> void:
	if kind == Kind.TOAST or not _is_escape(event):
		return
	if dismiss_option_popup_first:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is OptionButton and focused.get_popup().visible:
			focused.get_popup().hide()
			get_viewport().set_input_as_handled()
			return
	if escape_before_gui:
		get_viewport().set_input_as_handled()
		close_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if kind != Kind.TOAST and event is InputEventKey:
		get_viewport().set_input_as_handled() # before a close callback can remove this surface
		if _is_escape(event):
			close_requested.emit()


static func _is_escape(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE
