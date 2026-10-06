# The first-flight hint (MENU-PLAN UI-04b, research 22): three things from the shared controls table, shown once
# over the first flight, then remembered in the settings. It never takes the keyboard focus (the flight keys keep
# flying) and counts only time actually flown: pauses do not use it up. A click dismisses it earlier.
extends CanvasLayer

const UiTheme := preload("res://ui/ui_theme.gd")
const KeyCap := preload("res://ui/key_cap.gd")
const Reference := preload("res://ui/controls_reference.gd")

## Emitted once, when the hint goes away (time flown or a click): the caller remembers it as seen.
signal done

const LAYER := 5 # above the flight's HUD, below the pause menu (which dims it)

## Seconds of unpaused flight it stays.
var duration_s := 10.0
var _session: Node
var _flown := 0.0
var _finished := false


func _init(session: Node) -> void:
	name = "FirstFlightHint"
	layer = LAYER
	_session = session
	var screen := Control.new()
	screen.theme = UiTheme.build()
	screen.set_anchors_preset(Control.PRESET_TOP_WIDE)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	# Top right: the flight's input panel is top left and the HUD bottom left.
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.gui_input.connect(_on_card_input)
	card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.offset_right = -24
	card.offset_top = 24
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	card.add_child(row)
	for item in Reference.FIRST_FLIGHT:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 8)
		for key in item[0]:
			pair.add_child(KeyCap.for_key(key))
		var what := Label.new()
		what.text = item[1]
		what.theme_type_variation = "SecondaryLabel"
		pair.add_child(what)
		row.add_child(pair)


func _process(delta: float) -> void:
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
