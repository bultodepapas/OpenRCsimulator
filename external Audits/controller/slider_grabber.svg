## UI-22-R11: bounded, event-driven feedback beneath native controls.
extends Node2D

const UiTheme := preload("res://ui/ui_theme.gd")
const GLASS := preload("res://ui/shaders/crystal.gdshader")
const PRIMARY_TYPES := [&"PrimaryButton", &"CompactPrimaryButton", &"SettingsAction"]
const PANEL_TYPES := [&"SettingsPanel", &"Card", &"Sidebar", &"HomeSidebar"]
const STATES := [&"normal", &"pressed", &"hover", &"disabled", &"hover_pressed"]
const POINTER_CENTER := Vector2(0.5, 0.5)

var _target: Control
var _button: Button
var _is_primary := false
var _glass: ColorRect
var _material: ShaderMaterial
var _skins: Dictionary = {}
var _sources: Dictionary = {}
var _updating := false
var _energy_tween: Tween
var _shine_tween: Tween
var _press_tween: Tween
var _color_tween: Tween
var _pointer_tween: Tween
var _confirm_tween: Tween
var _uniforms: Dictionary = {}
var _base_goal := Color.TRANSPARENT
var _pointer_goal := POINTER_CENTER
var _pointer_pending := false
var _engaged := false
var _settled := false


static func attach(target: Control) -> void:
	if target.get_node_or_null("CrystalSurface") != null:
		return
	if not target is Button \
		and not (target is PanelContainer and target.theme_type_variation in PANEL_TYPES):
		return
	var effect := new() as Node2D
	effect.name = "CrystalSurface"
	target.add_child(effect, false, Node.INTERNAL_MODE_BACK)


static func decorate(root: Node) -> void:
	if root is Control:
		attach(root)
	for child in root.get_children():
		decorate(child)


func _ready() -> void:
	_target = get_parent() as Control
	_button = _target as Button
	show_behind_parent = true
	_material = ShaderMaterial.new()
	_material.shader = GLASS
	_glass = ColorRect.new()
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.focus_mode = Control.FOCUS_NONE
	_glass.material = _material
	add_child(_glass, false, Node.INTERNAL_MODE_BACK)
	_target.resized.connect(_resize)
	_target.theme_changed.connect(_rebuild_styles)
	_target.visibility_changed.connect(_visibility_changed)
	_target.draw.connect(_sync_state)
	if _button != null:
		_target.mouse_entered.connect(_engage)
		_target.focus_entered.connect(_engage)
		_target.mouse_exited.connect(_release)
		_target.focus_exited.connect(_release)
		_target.button_down.connect(_press.bind(true))
		_target.button_up.connect(_press.bind(false))
		_target.pressed.connect(_confirm)
	_rebuild_styles()
	_resize()
	set_process(false)
	set_physics_process(false)
	if _target is PanelContainer:
		_engage()


func _resize() -> void:
	_glass.size = _target.size
	_uniform(&"rect_size", _target.size)


func _uniform(key: StringName, value: Variant) -> void:
	if _uniforms.get(key) == value:
		return
	_uniforms[key] = value
	_material.set_shader_parameter(key, value)


func _rebuild_styles() -> void:
	if _updating:
		return
	_updating = true
	_target.begin_bulk_theme_override()
	for key: StringName in STATES if _button != null else [&"panel"]:
		if _skins.has(key) and _target.get_theme_stylebox(key) == _skins[key]:
			_target.remove_theme_stylebox_override(key)
		# Respect any screen-specific style override; do not replace another owner's customization.
		if _target.has_theme_stylebox_override(key):
			_sources[key] = _target.get_theme_stylebox(key)
			_skins.erase(key)
			continue
		var source := _target.get_theme_stylebox(key) as StyleBoxFlat
		if source == null or not source.draw_center:
			_sources.erase(key)
			_skins.erase(key)
			continue
		_sources[key] = source
		var skin := source.duplicate() as StyleBoxFlat
		skin.draw_center = false
		_skins[key] = skin
		_target.add_theme_stylebox_override(key, skin)
	_target.end_bulk_theme_override()
	_updating = false
	var was_primary := _is_primary
	_is_primary = _button != null and _target.theme_type_variation in PRIMARY_TYPES
	if was_primary != _is_primary:
		_settle() # Do not carry pending input or unused channels into another material kind.
	# Secondary controls have no pointer-local lighting and need no GUI-input listener.
	if _is_primary and not _target.gui_input.is_connected(_pointer_input):
		_target.gui_input.connect(_pointer_input)
	elif not _is_primary and _target.gui_input.is_connected(_pointer_input):
		_target.gui_input.disconnect(_pointer_input)
	_uniform(&"primary", 1.0 if _is_primary else (-1.0 if _button != null else 0.0))
	_uniform(&"crystal_color", UiTheme.CRYSTAL if _is_primary else UiTheme.SURFACE_LIGHT)
	var accent := UiTheme.ERROR if _target.theme_type_variation == &"DestructiveButton" else UiTheme.FOCUS
	_uniform(&"emission_color", UiTheme.GLASS_EMISSION if _is_primary else (accent if _button != null else UiTheme.SURFACE_LIGHT))
	_sync_state(false)
	if was_primary != _is_primary and _button != null and (_button.has_focus() or _button.is_hovered()):
		_engage()


func _sync_state(animate := true) -> void:
	if _updating or _material == null:
		return
	var key: StringName = STATES[_button.get_draw_mode()] if _button != null else &"panel"
	# Respect flat buttons and screen-owned styles before applying focus parity.
	var supported := _skins.has(key)
	if _button != null and _button.flat and key in [&"normal", &"disabled"]:
		supported = false
	if _button != null and key == &"normal" and _target.has_focus() and _skins.has(&"hover"):
		key = &"hover"
	var source := _sources.get(key) as StyleBoxFlat
	_glass.visible = source != null and supported
	if not _glass.visible:
		_settle()
	if source == null:
		return
	_fade_base(source.bg_color, animate)
	_uniform(&"corner_radius", float(source.corner_radius_top_left))
	_uniform(&"disabled", 1.0 if _button != null and _button.disabled else 0.0)
	if _button != null and _button.disabled:
		_settle()


func _fade_base(color: Color, animate: bool) -> void:
	if animate and _base_goal == color and _uniforms.has(&"base_color"):
		return
	_base_goal = color
	if not animate or not _can_animate() or not _uniforms.has(&"base_color") or _uniforms[&"base_color"] == color:
		if _color_tween != null and _color_tween.is_valid(): _color_tween.kill()
		_uniform(&"base_color", color)
		return
	_color_tween = _replace_tween(_color_tween, Tween.TRANS_CUBIC)
	_color_tween.tween_method(_color, _uniforms[&"base_color"], color, 0.14)


func _color(value: Color) -> void:
	if not _can_animate():
		_settle()
		return
	_uniform(&"base_color", value)


func _can_animate() -> bool:
	return is_inside_tree() and _target.is_visible_in_tree() and _glass.visible and not UiTheme.reduced_motion \
		and (_button == null or not _button.disabled)


## Each channel has one owner; replacing it preserves its displayed value.
func _replace_tween(previous: Tween, transition := Tween.TRANS_QUAD, ease := Tween.EASE_OUT) -> Tween:
	if previous != null and previous.is_valid(): previous.kill()
	_settled = false
	return create_tween().set_trans(transition).set_ease(ease)


func _engage() -> void:
	_sync_state()
	if not _can_animate():
		_settle()
		return
	if _engaged:
		return # Mouse entry and focus acquisition are one engagement, not two sweeps.
	_engaged = true
	if _button != null:
		if _is_primary and not _button.is_hovered(): _point_to(POINTER_CENTER)
		_energy_tween = _replace_tween(_energy_tween)
		_energy_tween.tween_method(_energy, float(_uniforms.get(&"energy", 0.0)), 1.0, 0.18)
	# Panel reflections use shine only; they do not consume button energy.
	_shine_tween = _replace_tween(_shine_tween, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	_shine_tween.tween_method(_shine, -0.25, 1.65, 0.56)


func _release() -> void:
	if _button == null:
		return
	if _button.has_focus() or _button.is_hovered():
		if _is_primary and not _button.is_hovered(): _point_to(POINTER_CENTER)
		return
	var was_engaged := _engaged
	_engaged = false
	_sync_state()
	if not _can_animate():
		_settle()
		return
	if not was_engaged:
		return
	if _is_primary: _point_to(POINTER_CENTER)
	_energy_tween = _replace_tween(_energy_tween)
	_energy_tween.tween_method(_energy, float(_uniforms.get(&"energy", 0.0)), 0.0, 0.22)


func _press(down: bool) -> void:
	_sync_state()
	if not _can_animate():
		_settle()
		return
	if not _is_primary:
		return # Secondary controls already transition their native pressed color.
	_press_tween = _replace_tween(_press_tween)
	_press_tween.tween_method(_depth, float(_uniforms.get(&"press_depth", 0.0)), 1.0 if down else 0.0, 0.08 if down else 0.14)


func _pointer_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _button.is_hovered():
		_point_to((event.position / _target.size.max(Vector2.ONE)).clamp(Vector2.ZERO, Vector2.ONE))


func _point_to(position: Vector2) -> void:
	if not _is_primary or not _can_animate() or _pointer_goal.is_equal_approx(position):
		return
	_pointer_goal = position
	_settled = false
	if not _pointer_pending:
		_pointer_pending = true
		_flush_pointer.call_deferred()


## Keep the newest position in a burst instead of allocating a Tween for every event.
func _flush_pointer() -> void:
	if not _pointer_pending:
		return
	_pointer_pending = false
	if not _can_animate():
		_settle()
		return
	var current: Vector2 = _uniforms.get(&"pointer_uv", POINTER_CENTER)
	if current.is_equal_approx(_pointer_goal):
		if _pointer_tween != null and _pointer_tween.is_valid(): _pointer_tween.kill()
		return
	_pointer_tween = _replace_tween(_pointer_tween)
	_pointer_tween.tween_method(_pointer, current, _pointer_goal, 0.12)


func _pointer(value: Vector2) -> void:
	if not _can_animate():
		_settle()
		return
	_uniform(&"pointer_uv", value)


func _confirm() -> void:
	# Only native activation confirms: releasing a cancelled press does not.
	_sync_state()
	if not _can_animate():
		_settle()
		return
	_confirm_tween = _replace_tween(_confirm_tween)
	_confirm_tween.tween_method(_confirmation, float(_uniforms.get(&"confirmation", 0.0)), 1.0, 0.06)
	_confirm_tween.tween_method(_confirmation, 1.0, 0.0, 0.24)


func _confirmation(value: float) -> void:
	if not _can_animate():
		_settle()
		return
	_uniform(&"confirmation", value)


func _energy(value: float) -> void:
	if not _can_animate():
		_settle()
		return
	_uniform(&"energy", value)


func _shine(value: float) -> void:
	if not _can_animate():
		_settle()
		return
	_uniform(&"shine_progress", value)


func _depth(value: float) -> void:
	if not _can_animate():
		_settle()
		return
	_uniform(&"press_depth", value)


func _visibility_changed() -> void:
	if not _target.is_visible_in_tree():
		_settle()
	elif _target is PanelContainer:
		_engage()


func _settle() -> void:
	if _settled:
		return
	_settled = true
	for tween in [_energy_tween, _shine_tween, _press_tween, _color_tween, _pointer_tween, _confirm_tween]:
		if tween != null and tween.is_valid(): tween.kill()
	_engaged = false
	_pointer_pending = false
	_pointer_goal = POINTER_CENTER
	_uniform(&"base_color", _base_goal)
	_uniform(&"pointer_uv", _pointer_goal)
	_uniform(&"confirmation", 0.0)
	_uniform(&"energy", 0.0)
	_uniform(&"shine_progress", -1.0)
	_uniform(&"press_depth", 0.0)


func _exit_tree() -> void:
	_settle()
