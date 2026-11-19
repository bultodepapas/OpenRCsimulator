# O2 Transmitter (HUD-05, HUD-RADIO-01/02a): catalog-driven appearance, live controls and simulated readings.
# Mode 2: left = throttle (vertical) + rudder, right = elevator + aileron. Mode 1 swaps throttle and elevator.
extends "res://render/overlays/overlay_frame.gd"

const Catalog := preload("res://render/overlays/radio_catalog.gd")
const Display := preload("res://render/overlays/radio_display.gd")
const LCD_TEXT := Color("e2f4ff")
const LCD_DIM := Color("9ab6c8")

var gimbals: Control
var footer: Label
var mode := 2
var radio_model := Catalog.DEFAULT_ID
var _definition := Catalog.definition(Catalog.DEFAULT_ID)
var _artwork: Texture2D
var _display_system := "si"
var _readings := Display.readings({}, {}, "si")
## Normalised screen positions (x right, y down, −1…1) and trims, set by refresh(), drawn by gimbals.
var _layout: Array = [Vector2.ZERO, Vector2.ZERO]
var _trims: Array = [Vector2.ZERO, Vector2.ZERO]


func _init() -> void:
	super("transmitter", tr("Transmitter"))
	gimbals = Control.new()
	gimbals.name = "Gimbals"
	gimbals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gimbals.custom_minimum_size = _definition.canvas_size
	_artwork = load(str(_definition.artwork)) as Texture2D
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
	var next_layout := stick_layout(stick_mode, sticks)
	var next_trims := trim_layout(stick_mode, trims)
	if stick_mode == mode and next_layout == _layout and next_trims == _trims:
		return
	if stick_mode != mode:
		mode = stick_mode
		_set_title()
	_layout = next_layout
	_trims = next_trims
	gimbals.queue_redraw()


func set_radio_model(value: String) -> void:
	if not Catalog.contains(value) or value == radio_model:
		return
	radio_model = value
	_definition = Catalog.definition(value)
	_artwork = load(str(_definition.artwork)) as Texture2D
	gimbals.custom_minimum_size = _definition.canvas_size
	_set_title()
	gimbals.queue_redraw()


## At the existing 10 Hz snapshot boundary, independently of stationary stick positions.
func refresh_display(telemetry: Dictionary, battery: Dictionary, system: String) -> void:
	_display_system = system
	var next := Display.readings(telemetry, battery, system)
	if next == _readings:
		return
	_readings = next
	gimbals.queue_redraw()


func reset_display() -> void:
	refresh_display({}, {}, _display_system)


## A caller-owned presentation snapshot, never an input/control source.
func display_readings() -> Dictionary:
	return _readings.duplicate()


func _set_title() -> void:
	title_label.text = "%s · M%d" % [Catalog.label(radio_model).to_upper(), mode]


func _draw_gimbals() -> void:
	var device_size: Vector2 = _definition.canvas_size
	var centres: Array = _definition.gimbals
	var accent: Color = _definition.accent
	if _artwork != null:
		gimbals.draw_texture_rect(_artwork, Rect2(Vector2.ZERO, device_size), false)
	_draw_display()
	for side in 2:
		var centre: Vector2 = centres[side]
		# Cover the photographed, stationary stick within the real metal gimbal ring.
		gimbals.draw_circle(centre, 18.0, Color("080d13"))
		gimbals.draw_circle(centre, 15.5, Color("151d25"))
		gimbals.draw_arc(centre, 18.5, 0.0, TAU, 48, Color("53606a"), 1.0, true)
		gimbals.draw_line(centre + Vector2(-13.0, 0.0), centre + Vector2(13.0, 0.0), Color(LCD_DIM, 0.28), 1.0)
		gimbals.draw_line(centre + Vector2(0.0, -13.0), centre + Vector2(0.0, 13.0), Color(LCD_DIM, 0.28), 1.0)
		var trim: Vector2 = _trims[side]
		if trim.x != 0.0:
			var tx := centre.x + trim.x * 12.0
			gimbals.draw_line(Vector2(tx, centre.y + 22.0), Vector2(tx, centre.y + 27.0), accent, 2.0)
		if trim.y != 0.0:
			var ty := centre.y + trim.y * 12.0
			var edge := centre.x + (24.0 if side == 1 else -24.0)
			gimbals.draw_line(Vector2(edge, ty), Vector2(edge + (-5.0 if side == 1 else 5.0), ty), accent, 2.0)
		var tip: Vector2 = centre + (_layout[side] as Vector2) * 12.0
		gimbals.draw_line(centre + Vector2(1.5, 2.0), tip + Vector2(1.5, 2.0), Color.BLACK, 6.0, true)
		gimbals.draw_line(centre, tip, Color("87949b"), 4.0, true)
		gimbals.draw_circle(tip + Vector2(1.0, 1.5), 6.5, Color("03070a"))
		gimbals.draw_circle(tip, 5.8, Color("aab3b6"))
		gimbals.draw_circle(tip, 4.4, Color("172029"))
		gimbals.draw_circle(tip, 2.5, accent)


func _draw_display() -> void:
	var display: Rect2 = _definition.lcd
	gimbals.draw_rect(display, Color("0d1e30"))
	gimbals.draw_rect(display, Color("5285a1"), false, 1.0)
	var header_height := 10.0 if display.size.y < 50.0 else 12.0
	gimbals.draw_rect(Rect2(display.position, Vector2(display.size.x, header_height)), Color("143d58"))
	var font: Font = ThemeDB.fallback_font
	var font_size := 7 if display.size.x < 70.0 else 8
	var origin := display.position + Vector2(3.0, header_height - 2.0)
	var width := display.size.x - 6.0
	gimbals.draw_string(font, origin, "SIM " + str(_readings.elapsed), HORIZONTAL_ALIGNMENT_LEFT, width, font_size, LCD_TEXT)
	# AS is airspeed, AGL is height above local terrain; the help names both explicitly.
	# The smaller LCDs show fewer rows instead of shrinking text further or drawing outside their bounds.
	var rows := ["AS " + str(_readings.airspeed), "AGL " + str(_readings.height_agl),
		"BAT " + str(_readings.pack_voltage), str(_readings.used_mah)]
	var line_height := 10.0 if font_size == 7 else 11.0
	for row in rows.size():
		var baseline := header_height + (row + 1) * line_height - 1.0
		if baseline > display.size.y - 3.0:
			break
		gimbals.draw_string(font, Vector2(display.position.x + 3.0, display.position.y + baseline),
			rows[row], HORIZONTAL_ALIGNMENT_LEFT, width, font_size, LCD_TEXT)
