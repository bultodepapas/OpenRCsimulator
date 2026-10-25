extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const UiTheme := preload("res://ui/ui_theme.gd")

signal cancel_requested

const LAYER := 11
const TITLE_TEXT := "Preparing flight…"
const CANCEL_TEXT := "Cancel"
const CANCELLING_TEXT := "Cancelling…"
const PANEL_MAX_WIDTH := 760.0
const OUTER_GUTTER := 36.0

var surface: Control
var backdrop: ColorRect
var title_label: Label
var summary_label: Label
var stage_label: Label
var cancel_button: Button

var _panel: PanelContainer
var _stage_source := ""
var _cancelling := false
var _cancel_emitted := false
var _committing := false


## ScreenStack calls open() after adding its wrapper. Skip the standard entrance tween so the opaque
## backdrop covers the live 3D scene on the first frame.
class ImmediateScreen extends "res://ui/screen.gd":
	func open(from: Control = null) -> void:
		return_focus = from
		set_active(true)


func _init(existing_theme: Theme = null) -> void:
	name = "FlightLoading"
	layer = LAYER

	var screen := ImmediateScreen.new()
	surface = screen
	screen.name = "Screen"
	screen.theme = existing_theme if existing_theme != null else UiTheme.build()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	screen.close_requested.connect(_request_cancel)

	backdrop = ColorRect.new()
	backdrop.name = "OpaqueBackdrop"
	backdrop.color = UiTheme.PANEL
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "LoadingCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = OUTER_GUTTER
	center.offset_top = OUTER_GUTTER
	center.offset_right = -OUTER_GUTTER
	center.offset_bottom = -OUTER_GUTTER
	screen.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "LoadingPanel"
	_panel.theme_type_variation = "Notice"
	center.add_child(_panel)

	var content := VBoxContainer.new()
	content.name = "LoadingContent"
	content.add_theme_constant_override("separation", 14)
	_panel.add_child(content)

	title_label = _label("LoadingTitle", "TitleLabel", TITLE_TEXT)
	content.add_child(title_label)

	summary_label = _label("FlightSummary", "SecondaryLabel", "")
	summary_label.custom_minimum_size.x = 0.0
	content.add_child(summary_label)

	stage_label = _label("LoadingStage", "SectionLabel", "")
	stage_label.custom_minimum_size.x = 0.0
	stage_label.visible = false
	content.add_child(stage_label)

	# Native activity feedback stays alive while numeric preparation yields. It is not a percentage.
	# Reduced motion keeps the truthful stage text and cancel action without animated decoration.
	if not UiTheme.reduced_motion:
		var activity := ProgressBar.new()
		activity.name = "LoadingActivity"
		activity.custom_minimum_size.y = 4.0
		activity.show_percentage = false
		activity.indeterminate = true
		activity.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var track := StyleBoxFlat.new()
		track.bg_color = UiTheme.EDGE
		var fill := StyleBoxFlat.new()
		fill.bg_color = UiTheme.FOCUS
		activity.add_theme_stylebox_override("background", track)
		activity.add_theme_stylebox_override("fill", fill)
		content.add_child(activity)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(actions)

	cancel_button = Button.new()
	cancel_button.name = "CancelFlightLoading"
	cancel_button.theme_type_variation = "QuietButton"
	cancel_button.custom_minimum_size = Vector2(176.0, 56.0)
	cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	cancel_button.text = tr(CANCEL_TEXT)
	cancel_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cancel_button.pressed.connect(_request_cancel)
	actions.add_child(cancel_button)

	screen.resized.connect(_resize_panel)
	_refresh_text()


func _ready() -> void:
	_resize_panel()
	cancel_button.grab_focus.call_deferred()


func configure(summary: String) -> void:
	## Summary is caller-formatted and localized because it contains dynamic aircraft/field/start values.
	summary_label.text = summary


func set_stage(stage: String) -> void:
	## The coordinator supplies a truthful English source phrase; translations remain in the owning catalog.
	if _cancelling:
		return
	_stage_source = stage
	_apply_stage()


func set_cancelling() -> void:
	if _cancelling:
		return
	_cancelling = true
	cancel_button.disabled = true
	_stage_source = CANCELLING_TEXT
	_apply_stage()


## The candidate has passed its last cancellable checkpoint and is being committed.
func set_committing() -> void:
	_committing = true
	cancel_button.disabled = true


func _request_cancel() -> void:
	if _cancel_emitted or _cancelling or _committing:
		return
	_cancel_emitted = true
	cancel_requested.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()
		_apply_stage()


func _refresh_text() -> void:
	if title_label != null:
		title_label.text = tr(TITLE_TEXT)
	if cancel_button != null:
		cancel_button.text = tr(CANCEL_TEXT)
		cancel_button.disabled = _cancelling or _committing


func _apply_stage() -> void:
	if stage_label == null:
		return
	stage_label.text = tr(_stage_source) if _stage_source != "" else ""
	stage_label.visible = _stage_source != ""


func _resize_panel() -> void:
	if _panel == null or surface == null or surface.size.x <= 0.0:
		return
	_panel.custom_minimum_size.x = minf(PANEL_MAX_WIDTH, maxf(0.0, surface.size.x - OUTER_GUTTER * 2.0))


func _label(node_name: String, variation: String, text: String) -> Label:
	var result := Label.new()
	result.name = node_name
	result.theme_type_variation = variation
	result.text = tr(text) if text != "" else ""
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return result
