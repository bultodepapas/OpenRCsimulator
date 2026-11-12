## DR-31b/c: drawing primitives of the FPV quad OSD (Betaflight/INAV-style graphics): white strokes and monospaced
## text with a dark outline so every element reads against bright sky and dark ground, the compass tape, scrolling
## speed/altitude sidebars, pitch ladder, battery gauge, home arrow, vario chevrons, stick overlay and motor bars.
## Stateless: each function draws into the CanvasItem it is given during that item's draw callback.
extends RefCounted

const UiTheme = preload("res://ui/ui_theme.gd")

const TEXT := Color(1.0, 1.0, 1.0)
const OUTLINE := Color(0.0, 0.0, 0.0, 0.85)
const DANGER := Color("#FF5A4A")
const ARMED := UiTheme.FOCUS
const CAUTION := UiTheme.CAUTION
const SHADE := Color(0.0, 0.0, 0.0, 0.42)
## Severity colours of HD DisplayPort fonts (normal, info, warning, critical); analog characters are all white.
const SEVERITY := [TEXT, ARMED, CAUTION, DANGER]
const LADDER_RUNGS: Array[int] = [-40, -30, -20, -10, 10, 20, 30, 40]
const RUNG_LABELS := {10: "10", 20: "20", 30: "30", 40: "40"}
const MOTOR_LABELS: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8"]
const CARDINALS := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}

static var _font: Font


## The OSD face: a bold system monospace (Consolas, Menlo, DejaVu Sans Mono…) like a goggle character set, with the
## theme fallback (and its CJK fallbacks) behind it so translated text never loses glyphs.
static func font() -> Font:
	if _font == null:
		var mono := SystemFont.new()
		mono.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "Liberation Mono",
			"Noto Sans Mono", "Courier New", "monospace"])
		mono.font_weight = 700
		mono.fallbacks = [ThemeDB.fallback_font]
		_font = mono
	return _font


## DR-31d: shaped OSD texts kept by font size, then string (a TextLine is shaped once; drawing one costs a fraction
## of shaping the string again). Bounded: past LINE_CACHE_MAX lines the cache starts over.
const LINE_CACHE_MAX := 768
static var _lines := {}
static var _line_count := 0


static func _line(value: String, size: int) -> TextLine:
	var by_size: Dictionary = _lines.get(size, {})
	if by_size.is_empty() and not _lines.has(size):
		_lines[size] = by_size
	var line: TextLine = by_size.get(value)
	if line == null:
		if _line_count >= LINE_CACHE_MAX:
			_lines.clear()
			_line_count = 0
			by_size = {}
			_lines[size] = by_size
		line = TextLine.new()
		line.add_string(value, font(), size)
		by_size[value] = line
		_line_count += 1
	return line


## Text with a dark outline. align: -1 left of `at`, 0 centred on it, 1 right of it ending at it; `at.y` is the
## vertical centre of the line.
static func text(ci: CanvasItem, at: Vector2, value: String, size: int, color: Color = TEXT, align := -1) -> void:
	if value.is_empty():
		return
	var line := _line(value, size)
	var extent := line.get_size()
	var x := at.x if align < 0 else (at.x - extent.x * 0.5 if align == 0 else at.x - extent.x)
	var top := Vector2(x, at.y - extent.y * 0.5)
	var canvas := ci.get_canvas_item()
	line.draw_outline(canvas, top, maxi(3, int(round(size * 0.24))), OUTLINE)
	line.draw(canvas, top, color)


static func text_width(value: String, size: int) -> float:
	return _line(value, size).get_size().x


## A white stroke over a dark one (readable against sky and ground).
static func stroke(ci: CanvasItem, a: Vector2, b: Vector2, width: float, color: Color = TEXT) -> void:
	ci.draw_line(a, b, Color(OUTLINE, OUTLINE.a * color.a), width + 3.0, true)
	ci.draw_line(a, b, color, width, true)


static func polyline(ci: CanvasItem, points: PackedVector2Array, width: float, color: Color = TEXT) -> void:
	ci.draw_polyline(points, Color(OUTLINE, OUTLINE.a * color.a), width + 3.0, true)
	ci.draw_polyline(points, color, width, true)


## A filled triangle with an outline.
static func triangle(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, color: Color = TEXT) -> void:
	ci.draw_colored_polygon(PackedVector2Array([a, b, c]), color)
	ci.draw_polyline(PackedVector2Array([a, b, c, a]), OUTLINE, 1.5, true)


## Heading tape across the top centre: ±60° of ticks (every 5°, taller every 15°), the cardinal letters, a caret and
## the boxed heading in degrees. The ends fade so the tape has no hard edge.
static func compass(ci: CanvasItem, centre_x: float, top: float, half_width: float, heading: float, s: float) -> void:
	var span := 60.0
	var per_deg := half_width / span
	var base := top + 20.0 * s
	var first := int(floorf((heading - span) / 5.0)) * 5
	var deg := first
	while deg <= int(ceilf(heading + span)):
		var offset := float(deg) - heading
		if absf(offset) <= span:
			var x := centre_x + offset * per_deg
			var fade := 1.0 - 0.65 * pow(absf(offset) / span, 2.0)
			var color := Color(TEXT, fade)
			var wrapped := posmod(deg, 360)
			if CARDINALS.has(wrapped):
				var size := int(round((22.0 if wrapped % 90 == 0 else 17.0) * s))
				text(ci, Vector2(x, base - 8.0 * s), CARDINALS[wrapped], size, Color(CAUTION, fade) if wrapped == 0 else color, 0)
				stroke(ci, Vector2(x, base + 2.0 * s), Vector2(x, base + 12.0 * s), 2.0 * s, color)
			elif wrapped % 15 == 0:
				stroke(ci, Vector2(x, base + 4.0 * s), Vector2(x, base + 12.0 * s), 2.0 * s, color)
			else:
				stroke(ci, Vector2(x, base + 8.0 * s), Vector2(x, base + 12.0 * s), 1.5 * s, color)
		deg += 5
	var tip := Vector2(centre_x, base + 15.0 * s)
	triangle(ci, tip, tip + Vector2(-7.0, 10.0) * s, tip + Vector2(7.0, 10.0) * s)
	var label := "%03d" % (int(round(heading)) % 360)
	var size := int(round(20.0 * s))
	var box := Rect2(Vector2(centre_x - 30.0 * s, tip.y + 11.0 * s), Vector2(60.0 * s, 26.0 * s))
	ci.draw_rect(box, SHADE, true)
	ci.draw_rect(box, TEXT, false, 1.5 * s)
	text(ci, box.get_center(), label, size, TEXT, 0)


## A horizon sidebar: a vertical bracket at x with ticks that scroll with the value (`value` in tick units, so one
## unit = one tick spacing) and an inward pointer at mid-height. side: -1 left bar (ticks point right), +1 right.
static func sidebar(ci: CanvasItem, x: float, centre_y: float, half_height: float, value: float, side: float, s: float) -> void:
	var spacing := 22.0 * s
	var frac := value - floorf(value)
	var count := int(ceilf(half_height / spacing)) + 1
	for i in range(-count, count + 1):
		var y := centre_y + (float(i) + frac) * spacing
		if absf(y - centre_y) > half_height:
			continue
		var fade := 1.0 - 0.7 * absf(y - centre_y) / half_height
		var major := posmod(int(floorf(value)) - i, 5) == 0
		var length := (12.0 if major else 6.0) * s
		stroke(ci, Vector2(x, y), Vector2(x - side * length, y), (2.0 if major else 1.5) * s, Color(TEXT, fade))
	stroke(ci, Vector2(x, centre_y - half_height), Vector2(x, centre_y + half_height), 1.5 * s, Color(TEXT, 0.55))
	var tip := Vector2(x - side * 16.0 * s, centre_y)
	triangle(ci, tip, tip + Vector2(side * 12.0, -7.0) * s, tip + Vector2(side * 12.0, 7.0) * s)


## A readout box beside a sidebar: the value text (and an optional second, smaller line) on a translucent shade.
static func readout(ci: CanvasItem, anchor: Vector2, value: String, side: float, s: float, color: Color = TEXT,
		small := "") -> void:
	var size := int(round(26.0 * s))
	var width := text_width(value, size) + 16.0 * s
	var height := 34.0 * s
	var x := anchor.x - width if side < 0.0 else anchor.x
	var box := Rect2(Vector2(x, anchor.y - height * 0.5), Vector2(width, height))
	ci.draw_rect(box, SHADE, true)
	ci.draw_rect(box, Color(TEXT, 0.8), false, 1.5 * s)
	text(ci, box.get_center(), value, size, color, 0)
	if not small.is_empty():
		var small_size := int(round(17.0 * s))
		var at := Vector2(box.end.x if side < 0.0 else box.position.x, box.end.y + 14.0 * s)
		text(ci, at, small, small_size, TEXT, 1 if side < 0.0 else -1)


## Pitch ladder rungs every 10° (±10…±40) parallel to the horizon line. p: the horizon line point (px), along/ground:
## unit pixel directions along the line and toward the ground, focal: focal length (px). Positive rungs are solid
## with end ticks toward the horizon, negative ones dashed (a pilot reads which side of level the nose is).
static func ladder(ci: CanvasItem, centre: Vector2, p: Vector2, along: Vector2, ground: Vector2, focal: float,
		clip_half: Vector2, s: float) -> void:
	var d0 := (p - centre).dot(ground)
	var elevation := atan2(d0, focal)
	var half_len := 46.0 * s
	var gap := 22.0 * s
	var size := int(round(16.0 * s))
	for k: int in LADDER_RUNGS:
		var e := elevation - deg_to_rad(float(k))
		if absf(e) >= PI * 0.45:
			continue
		var dk := focal * tan(e)
		# p is the line point nearest the centre, so the rungs stack along the ground normal through the centre.
		var c := centre + ground * dk
		var rel := c - centre
		if absf(rel.x) > clip_half.x or absf(rel.y) > clip_half.y:
			continue
		var color := Color(TEXT, 0.85)
		var tick := ground * (8.0 * s) * (1.0 if k > 0 else -1.0)
		for side: float in [-1.0, 1.0]:
			var a := c + along * side * gap
			var b := c + along * side * (gap + half_len)
			if k > 0:
				stroke(ci, a, b, 2.0 * s, color)
			else:
				var parts := 3
				for j in parts:
					var t0 := float(j) / parts
					var t1 := t0 + 0.6 / parts
					stroke(ci, a.lerp(b, t0), a.lerp(b, t1), 2.0 * s, color)
			stroke(ci, b, b + tick, 2.0 * s, color)
			text(ci, b + along * side * 18.0 * s, RUNG_LABELS[absi(k)], size, color, 0)


## A vertical battery gauge: outline, terminal, and a fill by state of charge in the band's colour.
static func battery_icon(ci: CanvasItem, rect: Rect2, soc: float, color: Color, s: float) -> void:
	var nub := Rect2(Vector2(rect.position.x + rect.size.x * 0.3, rect.position.y - 5.0 * s), Vector2(rect.size.x * 0.4, 5.0 * s))
	ci.draw_rect(rect.grow(2.0), OUTLINE, true)
	ci.draw_rect(nub.grow(1.5), OUTLINE, true)
	ci.draw_rect(nub, TEXT, true)
	var inner := rect.grow(-3.0 * s)
	var fill := clampf(soc, 0.0, 1.0)
	if fill > 0.0:
		ci.draw_rect(Rect2(Vector2(inner.position.x, inner.end.y - inner.size.y * fill), Vector2(inner.size.x, inner.size.y * fill)), color, true)
	ci.draw_rect(rect, TEXT, false, 2.0 * s)


## The home arrow: an arrow at `at` pointing toward home relative to the nose (0 = up/ahead, clockwise).
static func home_arrow(ci: CanvasItem, at: Vector2, relative_deg: float, size: float, color: Color = TEXT) -> void:
	var a := deg_to_rad(relative_deg)
	var fwd := Vector2(sin(a), -cos(a))
	var side := Vector2(-fwd.y, fwd.x)
	var tip := at + fwd * size
	var tail := at - fwd * size * 0.75
	var points := PackedVector2Array([tip, at + side * size * 0.75 - fwd * size * 0.75, tail + fwd * size * 0.35,
		at - side * size * 0.75 - fwd * size * 0.75])
	ci.draw_colored_polygon(points, color)
	points.append(tip)
	ci.draw_polyline(points, OUTLINE, 2.0, true)


## Vario chevrons stacked at `at`: |steps| chevrons pointing up (climb) or down (sink).
static func vario(ci: CanvasItem, at: Vector2, steps: int, s: float) -> void:
	var up := steps > 0
	var h := (4.0 if up else -4.0) * s
	for i in absi(steps):
		var y := at.y + (-1.0 if up else 1.0) * float(i) * 9.0 * s
		polyline(ci, PackedVector2Array([Vector2(at.x - 7.0 * s, y + h), Vector2(at.x, y - h), Vector2(at.x + 7.0 * s, y + h)]), 2.0 * s)


## One stick gimbal: a square with a centre cross and the stick dot. stick: x right, y down, both in [-1, 1].
static func gimbal(ci: CanvasItem, rect: Rect2, stick: Vector2, s: float) -> void:
	ci.draw_rect(rect, SHADE, true)
	ci.draw_rect(rect, Color(TEXT, 0.7), false, 1.5 * s)
	var c := rect.get_center()
	ci.draw_line(Vector2(c.x, rect.position.y + 4.0 * s), Vector2(c.x, rect.end.y - 4.0 * s), Color(TEXT, 0.3), 1.0)
	ci.draw_line(Vector2(rect.position.x + 4.0 * s, c.y), Vector2(rect.end.x - 4.0 * s, c.y), Color(TEXT, 0.3), 1.0)
	var half := rect.size * 0.5 - Vector2(6.0, 6.0) * s
	var dot := c + Vector2(clampf(stick.x, -1.0, 1.0) * half.x, clampf(stick.y, -1.0, 1.0) * half.y)
	ci.draw_circle(dot, 6.0 * s, OUTLINE)
	ci.draw_circle(dot, 4.5 * s, ARMED)


## Four motor command bars (0…1, the ESC outputs) in motor order, with their numbers under them.
static func motors(ci: CanvasItem, rect: Rect2, commands: PackedFloat64Array, s: float) -> void:
	var count := commands.size()
	if count == 0:
		return
	var gap := 5.0 * s
	var width := (rect.size.x - gap * float(count - 1)) / float(count)
	var size := int(round(14.0 * s))
	for i in count:
		var bar := Rect2(Vector2(rect.position.x + float(i) * (width + gap), rect.position.y), Vector2(width, rect.size.y))
		ci.draw_rect(bar.grow(1.5), SHADE, true)
		var fill := clampf(commands[i], 0.0, 1.0)
		var color := DANGER if fill > 0.97 else TEXT
		if fill > 0.0:
			ci.draw_rect(Rect2(Vector2(bar.position.x, bar.end.y - bar.size.y * fill), Vector2(bar.size.x, bar.size.y * fill)), color, true)
		ci.draw_rect(bar, Color(TEXT, 0.8), false, 1.0)
		text(ci, Vector2(bar.get_center().x, bar.end.y + 10.0 * s), MOTOR_LABELS[i] if i < MOTOR_LABELS.size() else str(i + 1), size, TEXT, 0)


## The crosshair at the picture centre in one of INAV's styles: default (wings and a centre tick), aircraft (wings,
## fin and tail), cross (+) or dot.
static func crosshair(ci: CanvasItem, centre: Vector2, style: String, s: float) -> void:
	match style:
		"aircraft":
			var span := 34.0 * s
			stroke(ci, centre + Vector2(-span, 0.0), centre + Vector2(-8.0 * s, 0.0), 2.5 * s)
			stroke(ci, centre + Vector2(8.0 * s, 0.0), centre + Vector2(span, 0.0), 2.5 * s)
			polyline(ci, PackedVector2Array([centre + Vector2(-8.0, 0.0) * s, centre + Vector2(0.0, 7.0) * s,
				centre + Vector2(8.0, 0.0) * s]), 2.5 * s)
			stroke(ci, centre + Vector2(0.0, -12.0 * s), centre + Vector2(0.0, -4.0 * s), 2.5 * s)
		"cross":
			var arm := 14.0 * s
			stroke(ci, centre + Vector2(-arm, 0.0), centre + Vector2(arm, 0.0), 2.5 * s)
			stroke(ci, centre + Vector2(0.0, -arm), centre + Vector2(0.0, arm), 2.5 * s)
		"dot":
			ci.draw_circle(centre, 5.0 * s, OUTLINE)
			ci.draw_circle(centre, 3.2 * s, TEXT)
		_:
			var wing := 26.0 * s
			var gap := 9.0 * s
			for side: float in [-1.0, 1.0]:
				stroke(ci, centre + Vector2(side * gap, 0.0), centre + Vector2(side * (gap + wing), 0.0), 2.5 * s)
			stroke(ci, centre + Vector2(0.0, -gap * 0.6), centre + Vector2(0.0, gap * 0.6), 2.5 * s)


## A stopwatch icon (the fly-timer symbol) centred at `at` with radius r.
static func icon_clock(ci: CanvasItem, at: Vector2, r: float, color: Color = TEXT) -> void:
	ci.draw_arc(at, r, 0.0, TAU, 20, OUTLINE, r * 0.55, true)
	ci.draw_arc(at, r, 0.0, TAU, 20, color, r * 0.25, true)
	ci.draw_line(at, at + Vector2(0.0, -r * 0.65), color, r * 0.22, true)
	ci.draw_line(at, at + Vector2(r * 0.5, 0.0), color, r * 0.22, true)
	ci.draw_line(at + Vector2(0.0, -r * 1.15), at + Vector2(0.0, -r * 1.45), color, r * 0.3, true)


## A house icon (the home symbol) centred at `at`, `size` high.
static func icon_home(ci: CanvasItem, at: Vector2, size: float, color: Color = TEXT) -> void:
	var h := size * 0.5
	var points := PackedVector2Array([at + Vector2(-h, h), at + Vector2(-h, -h * 0.1), at + Vector2(0.0, -h),
		at + Vector2(h, -h * 0.1), at + Vector2(h, h)])
	ci.draw_colored_polygon(points, color)
	points.append(points[0])
	ci.draw_polyline(points, OUTLINE, 1.5, true)
	ci.draw_rect(Rect2(at + Vector2(-h * 0.22, h * 0.15), Vector2(h * 0.44, h * 0.85)), OUTLINE, true)


## The next race gate: on the picture a diamond marker with the gate number and distance; off it (or behind the
## camera) an arrow at the picture edge pointing toward it, like a racing simulator's gate guide.
## screen: projected gate centre (px); behind: the gate lies behind the camera.
static func gate_marker(ci: CanvasItem, size: Vector2, screen: Vector2, behind: bool, label: String, margin: float,
		s: float, color: Color) -> void:
	var centre := size * 0.5
	if size.x <= margin * 2.0 or size.y <= margin * 2.0:
		return # a window smaller than the margins (headless runs) has no room for the guide
	var inner := Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)
	if not behind and inner.has_point(screen):
		var r := 13.0 * s
		var diamond := PackedVector2Array([screen + Vector2(0.0, -r), screen + Vector2(r, 0.0), screen + Vector2(0.0, r),
			screen + Vector2(-r, 0.0), screen + Vector2(0.0, -r)])
		ci.draw_polyline(diamond, OUTLINE, 5.0 * s, true)
		ci.draw_polyline(diamond, color, 2.5 * s, true)
		text(ci, screen + Vector2(0.0, r + 14.0 * s), label, int(round(18.0 * s)), color, 0)
		return
	# Off the picture: the direction from the centre (mirrored when the gate is behind the camera).
	var toward := (screen - centre) * (-1.0 if behind else 1.0)
	if toward.length() < 1.0:
		toward = Vector2(0.0, 1.0)
	toward = toward.normalized()
	var half := inner.size * 0.5
	var reach := minf(half.x / maxf(absf(toward.x), 1.0e-6), half.y / maxf(absf(toward.y), 1.0e-6))
	var tip := centre + toward * reach
	var side := Vector2(-toward.y, toward.x)
	var a := tip
	var b := tip - toward * 26.0 * s + side * 15.0 * s
	var c := tip - toward * 26.0 * s - side * 15.0 * s
	ci.draw_colored_polygon(PackedVector2Array([a, b, c]), color)
	ci.draw_polyline(PackedVector2Array([a, b, c, a]), OUTLINE, 2.0 * s, true)
	text(ci, tip - toward * 46.0 * s, label, int(round(18.0 * s)), color, 0)
