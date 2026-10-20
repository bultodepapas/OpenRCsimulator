# O2 Transmitter (HUD-05): JETI DS-24 II photo with live gimbals, trims and a simulator LCD.
# Mode 2: left = throttle (vertical) + rudder, right = elevator + aileron. Mode 1 swaps throttle and elevator.
extends "res://render/overlays/overlay_frame.gd"

const RADIO_IMAGE: Texture2D = preload("res://assets/ui/jeti_ds24_ii_orange.png")
const DEVICE_SIZE := Vector2(180.0, 222.0)
const GIMBAL_CENTRES := [Vector2(39.0, 126.0), Vector2(139.0, 126.0)]
const GIMBAL_TRAVEL := 12.0
const DISPLAY := Rect2(58.0, 23.0, 67.0, 64.0)
const ORANGE := Color("ff8d40")
const LCD_TEXT := Color("e2f4ff")
const LCD_DIM := Color("9ab6c8")

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
	gimbals.custom_minimum_size = DEVICE_SIZE
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
	title_label.text = "JETI DS-24 II · M%d" % mode


func _draw_gimbals() -> void:
	gimbals.draw_texture_rect(RADIO_IMAGE, Rect2(Vector2.ZERO, DEVICE_SIZE), false)
	_draw_display()
	for side in 2:
		var centre: Vector2 = GIMBAL_CENTRES[side]
		# Cover the photographed, stationary stick within the real metal gimbal ring.
		gimbals.draw_circle(centre, 18.0, Color("080d13"))
		gimbals.draw_circle(centre, 15.5, Color("151d25"))
		gimbals.draw_arc(centre, 18.5, 0.0, TAU, 48, Color("53606a"), 1.0, true)
		gimbals.draw_line(centre + Vector2(-13.0, 0.0), centre + Vector2(13.0, 0.0), Color(LCD_DIM, 0.28), 1.0)
		gimbals.draw_line(centre + Vector2(0.0, -13.0), centre + Vector2(0.0, 13.0), Color(LCD_DIM, 0.28), 1.0)
		var trim: Vector2 = _trims[side]
		if trim.x != 0.0:
			var tx := centre.x + trim.x * GIMBAL_TRAVEL
			gimbals.draw_line(Vector2(tx, centre.y + 22.0), Vector2(tx, centre.y + 27.0), ORANGE, 2.0)
		if trim.y != 0.0:
			var ty := centre.y + trim.y * GIMBAL_TRAVEL
			var edge := centre.x + (24.0 if side == 1 else -24.0)
			gimbals.draw_line(Vector2(edge, ty), Vector2(edge + (-5.0 if side == 1 else 5.0), ty), ORANGE, 2.0)
		var tip: Vector2 = centre + (_layout[side] as Vector2) * GIMBAL_TRAVEL
		gimbals.draw_line(centre + Vector2(1.5, 2.0), tip + Vector2(1.5, 2.0), Color.BLACK, 6.0, true)
		gimbals.draw_line(centre, tip, Color("87949b"), 4.0, true)
		gimbals.draw_circle(tip + Vector2(1.0, 1.5), 6.5, Color("03070a"))
		gimbals.draw_circle(tip, 5.8, Color("aab3b6"))
		gimbals.draw_circle(tip, 4.4, Color("172029"))
		gimbals.draw_circle(tip, 2.5, ORANGE)


func _draw_display() -> void:
	gimbals.draw_rect(DISPLAY, Color("0d1e30"))
	gimbals.draw_rect(DISPLAY, Color("5285a1"), false, 1.0)
	gimbals.draw_rect(Rect2(DISPLAY.position, Vector2(DISPLAY.size.x, 12.0)), Color("143d58"))
	var font: Font = ThemeDB.fallback_font
	gimbals.draw_string(font, Vector2(62.0, 32.0), "OPENRC  SIM", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, LCD_TEXT)
	gimbals.draw_string(font, Vector2(62.0, 45.0), "DS-24 II  M%d" % mode, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ORANGE)
	gimbals.draw_line(Vector2(62.0, 49.0), Vector2(121.0, 49.0), Color(LCD_DIM, 0.55), 1.0)
	var throttle_y: float = (_layout[1] as Vector2).y if mode == 1 else (_layout[0] as Vector2).y
	var throttle: int = roundi((1.0 - throttle_y) * 50.0)
	var roll: int = roundi((_layout[1] as Vector2).x * 100.0)
	var pitch: int = roundi((_layout[0] as Vector2).y * 100.0) if mode == 1 else roundi((_layout[1] as Vector2).y * 100.0)
	gimbals.draw_string(font, Vector2(62.0, 59.0), "THR  %3d%%" % throttle, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, LCD_TEXT)
	gimbals.draw_string(font, Vector2(62.0, 70.0), "AIL %+4d%%" % roll, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, LCD_TEXT)
	gimbals.draw_string(font, Vector2(62.0, 81.0), "ELE %+4d%%" % pitch, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, LCD_TEXT)
