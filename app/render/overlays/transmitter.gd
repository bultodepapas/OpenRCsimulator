# O2 Transmitter (HUD-05): both gimbals as the pilot holds them, trim marks, throttle, rates and the radio's state.
# Mode 2: left = throttle (vertical) + rudder, right = elevator + aileron. Mode 1 swaps throttle and elevator.
extends "res://render/overlays/overlay_frame.gd"

const GIMBAL := 88.0 # px, one gimbal's square
const GAP := 14.0
const DOT := 6.0

var gimbals: Control
var footer: Label
var mode := 2
## Normalised screen positions (x right, y down, −1…1) and trims, set by refresh(), drawn by gimbals.
var _layout: Array = [Vector2.ZERO, Vector2.ZERO]
var _trims: Array = [Vector2.ZERO, Vector2.ZERO]


func _init() -> void:
	super("transmitter", tr("Transmitter"))
	gimbals = Control.new()
	gimbals.name = "Gimbals"
	gimbals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gimbals.custom_minimum_size = Vector2(2.0 * GIMBAL + GAP, GIMBAL)
	gimbals.draw.connect(_draw_gimbals)
	body.add_child(gimbals)
	footer = text_label("", LABEL_SIZE, UiTheme.TEXT_2)
	body.add_child(footer)
	_set_title()


## [left, right] stick positions on screen (x right, y down, each −1…1). sticks: { roll, pitch, yaw } (−1…1,
## pitch +1 = stick back) and throttle (0…1, the stick, not the held command). A stick pulled back sits low.
static func stick_layout(stick_mode: int, sticks: Dictionary) -> Array:
	var throttle_y: float = 1.0 - 2.0 * clampf(float(sticks.throttle), 0.0, 1.0)
	var pitch_y: float = clampf(float(sticks.pitch), -1.0, 1.0)
	var yaw_x: float = clampf(float(sticks.yaw), -1.0, 1.0)
	var roll_x: float = clampf(float(sticks.roll), -1.0, 1.0)
	if stick_mode == 1:
		return [Vector2(yaw_x, pitch_y), Vector2(roll_x, throttle_y)]
	return [Vector2(yaw_x, throttle_y), Vector2(roll_x, pitch_y)]


## Trim marks per gimbal, same scale as the sticks (trims are fractions of the maximum throw). Throttle has none.
static func trim_layout(stick_mode: int, trims: Dictionary) -> Array:
	var pitch: float = clampf(float(trims.get("pitch", 0.0)), -1.0, 1.0)
	var yaw: float = clampf(float(trims.get("yaw", 0.0)), -1.0, 1.0)
	var roll: float = clampf(float(trims.get("roll", 0.0)), -1.0, 1.0)
	if stick_mode == 1:
		return [Vector2(yaw, pitch), Vector2(roll, 0.0)]
	return [Vector2(yaw, 0.0), Vector2(roll, pitch)]


## Every frame. sticks/trims: see stick_layout() and trim_layout(). The footer is set at 10 Hz by the manager.
func refresh(sticks: Dictionary, trims: Dictionary, stick_mode: int) -> void:
	if stick_mode != mode:
		mode = stick_mode
		_set_title()
	_layout = stick_layout(mode, sticks)
	_trims = trim_layout(mode, trims)
	gimbals.queue_redraw()


func _set_title() -> void:
	title_label.text = (tr("Transmitter") + " · " + tr("Mode %d") % mode).to_upper()


func _draw_gimbals() -> void:
	for side in 2:
		var origin := Vector2(side * (GIMBAL + GAP), 0.0)
		var rect := Rect2(origin, Vector2(GIMBAL, GIMBAL))
		var centre := rect.get_center()
		var half := GIMBAL * 0.5 - DOT - 2.0
		gimbals.draw_rect(rect, Color(0.0, 0.0, 0.0, 0.28))
		gimbals.draw_rect(rect, Color(UiTheme.TEXT_2, 0.55), false, 1.0)
		gimbals.draw_line(Vector2(centre.x, rect.position.y + 4.0), Vector2(centre.x, rect.end.y - 4.0), Color(UiTheme.TEXT_2, 0.25))
		gimbals.draw_line(Vector2(rect.position.x + 4.0, centre.y), Vector2(rect.end.x - 4.0, centre.y), Color(UiTheme.TEXT_2, 0.25))
		var trim: Vector2 = _trims[side]
		if trim.x != 0.0:
			var tx := centre.x + trim.x * half
			gimbals.draw_line(Vector2(tx, rect.end.y - 7.0), Vector2(tx, rect.end.y - 1.0), UiTheme.FOCUS, 3.0)
		if trim.y != 0.0:
			var ty := centre.y + trim.y * half
			var edge := rect.end.x if side == 1 else rect.position.x
			var inward := -1.0 if side == 1 else 1.0
			gimbals.draw_line(Vector2(edge + inward, ty), Vector2(edge + inward * 7.0, ty), UiTheme.FOCUS, 3.0)
		var dot: Vector2 = centre + (_layout[side] as Vector2) * half
		gimbals.draw_line(centre, dot, Color(UiTheme.TEXT, 0.5), 2.0)
		gimbals.draw_circle(dot, DOT, UiTheme.TEXT)
		gimbals.draw_circle(dot, DOT - 2.5, UiTheme.PRIMARY.normal)
