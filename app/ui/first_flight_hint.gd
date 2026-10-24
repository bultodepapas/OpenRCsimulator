# The first-flight hint (MENU-PLAN UI-04b, research 22): three things from the shared controls table, shown once
# over the first flight, then remembered in the settings. It never takes the keyboard focus (the flight keys keep
# flying) and counts only time actually flown: pauses do not use it up. A click dismisses it earlier.
extends CanvasLayer

const UiTheme := preload("res://ui/ui_theme.gd")
const KeyCap := preload("res://ui/key_cap.gd")
const Reference := preload("res://ui/controls_reference.gd")
const AccidentReport := preload("res://ui/accident_report.gd")

## Emitted once, when the hint goes away (time flown or a click): the caller remembers it as seen.
signal done

const LAYER := 5 # above the flight's HUD, below the pause menu (which dims it)

## Seconds of unpaused flight it stays.
var duration_s := 10.0
var _session: Node
var _flown := 0.0
var _finished := false
var _vehicle_type := Reference.AIRPLANE
var _card: PanelContainer
var _report_action: Control


func _init(session: Node, vehicle_type: String = Reference.AIRPLANE) -> void:
	name = "FirstFlightHint"
	layer = LAYER
	_session = session
	_vehicle_type = Reference.ROTORCRAFT if vehicle_type == Reference.ROTORCRAFT else Reference.AIRPLANE
	var screen := Control.new()
	screen.theme = UiTheme.build()
	screen.set_anchors_preset(Control.PRESET_TOP_WIDE)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	# Bottom centre: the flight overlays' Pilot preset holds the corners and the warnings the top centre
	# (docs/plans/flight-overlays.md); tests/test_overlay_manager.gd checks they do not overlap at 1280×720.
	_card = PanelContainer.new()
	_card.name = "Card"
	_card.theme_type_variation = "Card"
	_card.gui_input.connect(_on_card_input)
	_card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	_card.add_child(row)
	for item in Reference.first_flight_table(_vehicle_type):
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 8)
		for key in item[0]:
			pair.add_child(KeyCap.for_key(key))
		var what := Label.new()
		what.text = item[1]
		what.theme_type_variation = "SecondaryLabel"
		pair.add_child(what)
		row.add_child(pair)


func _ready() -> void:
	var report: Node = get_parent().get_node_or_null("AccidentReport")
	if report != null:
		_report_action = report.find_child("ReopenAccidentReport", true, false) as Control
		if _report_action != null:
			_report_action.minimum_size_changed.connect(_layout_card)
	var viewport: Viewport = get_viewport()
	viewport.size_changed.connect(_layout_card)
	_layout_card()


## Reserve the report's measured center-bottom action slot. Both controls use the same responsive gutter.
func _layout_card() -> void:
	if _card == null or not is_instance_valid(_card):
		return
	if _report_action == null or not is_instance_valid(_report_action):
		_card.offset_bottom = -24.0
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var metrics: Dictionary = AccidentReport.layout_metrics(viewport_size, UiTheme.text_scale)
	var gutter: float = float(metrics.gutter)
	var action_height: float = maxf(_report_action.size.y, _report_action.get_combined_minimum_size().y)
	if viewport_size.y <= 0.0 or action_height <= 0.0:
		_card.offset_bottom = -24.0
		return
	# AccidentReport anchors its restore action at H - gutter - height. Leave one gutter above it.
	_card.offset_bottom = -(gutter * 2.0 + action_height)


func _process(delta: float) -> void:
	if _finished:
		return
	# This card describes keyboard flight. A selected/lost controller owns those
	# channels until keyboard recovery is explicitly chosen in Controls.
	visible = not _session.radio.connected and not bool(_session.get("_controller_lost"))
	if not _session.sim.paused:
		_flown += delta
	if _flown >= duration_s:
		finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	visible = false
	done.emit()


func _on_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		finish()
