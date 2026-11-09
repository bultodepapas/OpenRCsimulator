## A read-only copy of the latest alert selection, opened only above a held Pause screen.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")
const Widgets := preload("res://ui/widgets.gd")
const MenuInput := preload("res://ui/ui_input.gd")
const AlertPolicy := preload("res://render/overlays/alert_policy.gd")

signal closed

var close_button: Button
var alert_buttons: Array[Button] = []
var _codes := PackedStringArray()
var _sampled := false
var _panel: PanelContainer
var _screen: Control


func _init(snapshot: Dictionary = {}) -> void:
	name = "ActiveAlerts"
	layer = 11
	_sampled = bool(snapshot.get("sampled", false))
	var codes: Variant = snapshot.get("codes", PackedStringArray())
	if _sampled and codes is PackedStringArray:
		_codes = codes.duplicate()
	_screen = Screen.mount(self, "Screen")
	_screen.escape_before_gui = true
	_screen.focus_fallback = _focus_initial
	_screen.close_requested.connect(close)
	_screen.dim(0.55)
	var center: CenterContainer = _screen.center(24.0)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "Sidebar"
	center.add_child(_panel)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	_panel.add_child(shell)
	var title := Widgets.label("Review active alerts", "TitleLabel", true)
	shell.add_child(title)
	var note := Widgets.label("Flight is paused. This list shows the latest sampled alerts when opened; it does not update while open.", "SecondaryLabel", true)
	shell.add_child(note)
	var scope := Widgets.label("Shows selected alert categories, even if the warning panel is hidden.", "SecondaryLabel", true)
	shell.add_child(scope)
	var scroll := ScrollContainer.new()
	scroll.name = "AlertScroll"
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "AlertList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var group := ButtonGroup.new()
	for index in _codes.size():
		var button := Button.new()
		button.name = "Alert%d" % index
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_entered.connect(_select.bind(index))
		button.pressed.connect(_select.bind(index))
		list.add_child(button)
		alert_buttons.append(button)
	if alert_buttons.is_empty():
		list.add_child(Widgets.label("No selected alerts in the latest sample." if _sampled else "No alert sample is available yet.", "SecondaryLabel", true))
	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = "Close"
	close_button.pressed.connect(close)
	shell.add_child(close_button)
	_bind_focus()
	_refresh_alert_text()
	_screen.resized.connect(_resize_panel)
	_screen.theme_changed.connect(_resize_panel)


func _ready() -> void:
	_resize_panel()
	_screen.ensure_focus.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_alert_text()


func _refresh_alert_text() -> void:
	for index in alert_buttons.size():
		var title := tr(AlertPolicy.title_for(_codes[index]))
		var detail := tr(AlertPolicy.detail_for(_codes[index]))
		alert_buttons[index].text = title + ("\n" + detail if not detail.is_empty() else "")


func _bind_focus() -> void:
	var controls: Array[Button] = alert_buttons.duplicate()
	controls.append(close_button)
	for index in controls.size():
		var current := controls[index]
		var previous := controls[(index - 1 + controls.size()) % controls.size()]
		var next := controls[(index + 1) % controls.size()]
		current.focus_neighbor_top = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_previous = current.get_path_to(previous)
		current.focus_next = current.get_path_to(next)


func _select(index: int) -> void:
	if index >= 0 and index < alert_buttons.size():
		for at in alert_buttons.size():
			alert_buttons[at].set_pressed_no_signal(at == index)


func _focus_initial() -> void:
	if not is_inside_tree() or not _screen._active:
		return
	var initial: Button = alert_buttons[0] if not alert_buttons.is_empty() else close_button
	if Screen.can_focus(initial):
		initial.grab_focus()


func _resize_panel() -> void:
	if not is_inside_tree():
		return
	var area := get_viewport().get_visible_rect().size
	var scale := clampf(ScreenTheme.text_scale, 1.0, 2.0)
	_panel.custom_minimum_size = Vector2(minf(760.0 * scale, maxf(1.0, area.x - 48.0)),
		minf(700.0 * scale, maxf(1.0, area.y - 48.0)))


func _unhandled_input(event: InputEvent) -> void:
	if not _screen._active or not event.is_action_pressed("ui_cancel"):
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if MenuInput.selected_gamepad_id() < 0 or event.device != MenuInput.selected_gamepad_id():
			return
	get_viewport().set_input_as_handled()
	close()


func close() -> void:
	closed.emit()
