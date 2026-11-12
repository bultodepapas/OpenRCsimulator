extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const LoadingBar := preload("res://ui/loading_bar.gd")
const ATMOSPHERE := preload("res://ui/shaders/brand_atmosphere.gdshader")

signal cancel_requested

const LAYER := 11
const TITLE_TEXT := "Preparing flight…"
const CANCEL_TEXT := "Cancel"
const CANCELLING_TEXT := "Cancelling…"
const PANEL_MAX_WIDTH := 760.0
const OUTER_GUTTER := 36.0
## UI-28-R5: top-level preparation stages in the order AppRoot and Main report them (UI-34c). The bar
## counts completed stages; a stage that a route skips is passed over, and any other name (field and
## scenery sub-stages) advances only within the current stage. It is not a time estimate or percentage.
const STAGES := ["Preparing resources", "Preparing flight scene", "Checking landscape", "Preparing aircraft",
	"Preparing world", "Building landscape", "Preparing sky", "Preparing field lighting", "Finalizing world",
	"Preparing aircraft lighting", "Preparing instruments", "Checking flight", "Preparing flight model",
	"Preparing contacts", "Preparing start", "Preparing effects", "Preparing sound", "Preparing companions",
	"Finishing flight"]
## UI-28-R5b: the stages of a staged Home rebuild (World.build_staged, then the aircraft).
const HOME_STAGES := ["Preparing world", "Building landscape", "Preparing sky", "Preparing field lighting",
	"Finalizing world", "Preparing aircraft"]
const HOME_TITLE_TEXT := "Preparing home…"
const SEE_THROUGH_OPACITY := 0.8
## The brand atmosphere's one-time ignition has passed by this clock; dust and motes keep drifting.
const ATMOSPHERE_CLOCK := 6.0

var surface: Control
var backdrop: ColorRect
var title_label: Label
var summary_label: Label
var stage_label: Label
## UI-28-R5b: the current sub-stage (field and scenery chunks), dimmer and below the stable stage line.
var detail_label: Label
var cancel_button: Button
var progress_bar: Control

var _panel: PanelContainer
var _stage_source := ""
var _detail_source := ""
var _cancelling := false
var _cancel_emitted := false
var _committing := false
var _stage_index := -1
var _stages: Array = STAGES
var _title_source := TITLE_TEXT
var _atmosphere: ShaderMaterial
var _clock := ATMOSPHERE_CLOCK


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
	# UI-28-R5: the opaque brand atmosphere (the same shader as the startup intro) instead of a flat fill.
	_atmosphere = ShaderMaterial.new()
	_atmosphere.shader = ATMOSPHERE
	_atmosphere.set_shader_parameter("clock", _clock)
	_atmosphere.set_shader_parameter("live", 0.0 if UiTheme.reduced_motion else 1.0)
	backdrop.material = _atmosphere
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

	detail_label = _label("LoadingDetail", "SectionLabel", "")
	detail_label.custom_minimum_size.x = 0.0
	detail_label.modulate.a = 0.55 # same type as the stage line, visibly secondary
	detail_label.visible = false
	content.add_child(detail_label)

	# UI-28-R5: completed stages fill the bar; its sweep shows activity while a stage works (the
	# threaded scene load included). It is not a percentage. Reduced motion shows the same position
	# without sweep or easing.
	progress_bar = LoadingBar.new()
	progress_bar.name = "LoadingActivity"
	progress_bar.custom_minimum_size.y = 8.0
	progress_bar.reduced_motion = UiTheme.reduced_motion
	content.add_child(progress_bar)

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


func _enter_tree() -> void:
	# The coordinator temporarily detaches this same screen while installing the flight.
	_focus_cancel.call_deferred()


func _ready() -> void:
	_resize_panel()


func _process(delta: float) -> void:
	if UiTheme.reduced_motion or not surface.is_visible_in_tree():
		return
	_clock += minf(delta, 0.1)
	_atmosphere.set_shader_parameter("clock", _clock)


func _focus_cancel() -> void:
	if is_inside_tree() and surface.is_visible_in_tree() and not cancel_button.disabled:
		cancel_button.grab_focus()


## UI-28-R5b: the same surface while Home is rebuilt after an activity. It cannot be cancelled: the
## activity has already ended, so there is nothing to return to.
## `see_through` (a landscape change): the previous Home view stays visible, dimmed, and the surface
## fades in briefly, so a short rebuild reads as a transition rather than a full-screen flash.
func configure_home(summary: String, see_through := false) -> void:
	_title_source = HOME_TITLE_TEXT
	_stages = HOME_STAGES
	_committing = true
	cancel_button.visible = false
	summary_label.text = summary
	_refresh_text()
	if see_through:
		_atmosphere.set_shader_parameter("opacity", SEE_THROUGH_OPACITY)
		# The card itself stays solid over the dimmed view so its text keeps full contrast.
		var card: StyleBox = _panel.get_theme_stylebox("panel", "Notice")
		if card is StyleBoxFlat:
			var solid := card.duplicate() as StyleBoxFlat
			solid.bg_color.a = 1.0
			_panel.add_theme_stylebox_override("panel", solid)
		if not UiTheme.reduced_motion:
			surface.modulate.a = 0.0
			surface.ready.connect(func() -> void:
				surface.create_tween().tween_property(surface, "modulate:a", 1.0, 0.18), CONNECT_ONE_SHOT)


func configure(summary: String) -> void:
	## Summary is caller-formatted and localized because it contains dynamic aircraft/field/start values.
	summary_label.text = summary


func set_stage(stage: String) -> void:
	## The coordinator supplies a truthful English source phrase; translations remain in the owning catalog.
	if _cancelling:
		return
	# Top-level stages hold the main line; anything else is a sub-stage of the current one, so the
	# main line stays readable instead of flickering through chunk names.
	if _stages.has(stage) or _stage_source == "":
		_stage_source = stage
		_detail_source = ""
	else:
		_detail_source = stage
	_advance_progress(stage)
	_apply_stage()


func _advance_progress(stage: String) -> void:
	var index := _stages.find(stage)
	if index > _stage_index:
		_stage_index = index
		progress_bar.value = float(index) / _stages.size()
	elif index < 0 and _stage_index >= 0:
		progress_bar.nudge(float(_stage_index + 1) / _stages.size(), 0.08)


func set_cancelling() -> void:
	if _cancelling:
		return
	_cancelling = true
	cancel_button.disabled = true
	progress_bar.active = false
	_stage_source = CANCELLING_TEXT
	_detail_source = ""
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
		title_label.text = tr(_title_source)
	if cancel_button != null:
		cancel_button.text = tr(CANCEL_TEXT)
		cancel_button.disabled = _cancelling or _committing


func _apply_stage() -> void:
	if stage_label == null:
		return
	stage_label.text = tr(_stage_source) if _stage_source != "" else ""
	stage_label.visible = _stage_source != ""
	# Once shown, the detail line keeps its height (a space) so the panel does not jump between chunks.
	if _detail_source != "":
		detail_label.text = tr(_detail_source)
		detail_label.visible = true
	elif detail_label.visible:
		detail_label.text = " "
	detail_label.accessibility_name = detail_label.text.strip_edges()


func _resize_panel() -> void:
	if _panel == null or surface == null or surface.size.x <= 0.0:
		return
	_atmosphere.set_shader_parameter("viewport_size", surface.size)
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
