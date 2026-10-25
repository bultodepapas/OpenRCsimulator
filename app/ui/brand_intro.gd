extends Control
## UI-28-R4: presentation only. Every moving piece comes from an untouched official SVG contour.

const Segments := preload("res://assets/branding/logo_segments.gd")
const ATLAS := preload("res://assets/branding/logo-segments.svg")
const ATMOSPHERE := preload("res://ui/shaders/brand_atmosphere.gdshader")
const INK := preload("res://ui/shaders/brand_segments.gdshader")
const DURATION := 4.8
const LOGO_CENTER := Vector2(847.5, 456.5)

var elapsed := 0.0
var playing := true
var status_text := "Loading…"
var _background: ColorRect
var _mark: Node2D
var _atmosphere: ShaderMaterial
var _ink: ShaderMaterial


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_background = ColorRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.show_behind_parent = true
	_atmosphere = ShaderMaterial.new()
	_atmosphere.shader = ATMOSPHERE
	_background.material = _atmosphere
	add_child(_background)
	_mark = Node2D.new()
	_mark.name = "VectorSegments"
	_ink = ShaderMaterial.new()
	_ink.shader = INK
	_mark.material = _ink
	_mark.draw.connect(_draw_mark)
	add_child(_mark)
	resized.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if playing:
		elapsed += minf(delta, 0.1) # Preserve the reveal after a slow first shader frame.
	_refresh()


## Deterministic presentation seam for the existing debug bridge and visual review.
func seek(seconds: float) -> void:
	playing = false
	elapsed = maxf(0.0, seconds)
	_refresh()


func _refresh() -> void:
	if _mark == null:
		return
	_atmosphere.set_shader_parameter("clock", elapsed)
	_atmosphere.set_shader_parameter("viewport_size", size)
	_ink.set_shader_parameter("clock", elapsed)
	_mark.queue_redraw()
	queue_redraw()


func _draw_mark() -> void:
	var fit := minf(size.x / 1920.0, size.y / 1080.0)
	var zoom := 0.85 + 0.045 * (1.0 - smoothstep(0.4, 4.3, elapsed))
	var center := Vector2(size.x * 0.5, size.y * 0.46)
	for index in Segments.PIECES.size():
		var piece: Dictionary = Segments.PIECES[index]
		var rect: Array = piece.rect
		var atlas: Array = piece.atlas
		var target := Vector2(float(rect[0]), float(rect[1])) - LOGO_CENTER
		var extent := Vector2(float(rect[2]), float(rect[3]))
		var delay := 0.32 + (target.x + 740.0) / 1465.0 * 0.7
		if piece.group == "SIMULATOR":
			delay += 0.62
		elif piece.group == "ALPHA":
			delay += 0.45
		var phase := clampf((elapsed - delay) / 1.5, 0.0, 1.0)
		var ease := 1.0 - pow(1.0 - phase, 4.0)
		var side := -1.0 if index % 2 == 0 else 1.0
		var drift := Vector2(target.x * 0.2, side * (65.0 + float(index % 5) * 18.0)) * (1.0 - ease)
		var location := center + (target + drift) * fit * zoom
		var opacity := smoothstep(0.0, 0.4, phase)
		_mark.draw_set_transform(location + extent * fit * zoom * 0.5, side * (1.0 - ease) * 0.08,
			Vector2.ONE * fit * zoom)
		_mark.draw_texture_rect_region(ATLAS, Rect2(-extent * 0.5, extent),
			Rect2(float(atlas[0]) * 2.0, float(atlas[1]) * 2.0, float(atlas[2]) * 2.0, float(atlas[3]) * 2.0),
			Color(1.0, 1.0, 1.0, opacity))
	_mark.draw_set_transform(Vector2.ZERO)


func _draw() -> void:
	var fit := minf(size.x / 1920.0, size.y / 1080.0)
	var font := ThemeDB.fallback_font
	var caption_alpha := smoothstep(2.7, 3.7, elapsed)
	var muted := Color(0.40, 0.58, 0.66, caption_alpha)
	var small := maxi(12, roundi(14.0 * fit))
	var caption := "R A D I O   C O N T R O L   /   F L I G H T   S I M U L A T O R"
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	draw_string(font, Vector2((size.x - width) * 0.5, size.y * 0.70), caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1, small, muted)
	var margin := maxf(24.0, 64.0 * fit)
	var baseline := size.y - margin
	var footer_color := Color(0.55, 0.64, 0.69, smoothstep(0.5, 1.2, elapsed))
	draw_string(font, Vector2(margin, baseline), tr(status_text), HORIZONTAL_ALIGNMENT_LEFT,
		-1, maxi(14, roundi(16.0 * fit)), footer_color)
	var rail := Rect2(margin, baseline + 15.0 * fit, 180.0 * fit, 1.0 * fit)
	draw_rect(rail, Color(0.12, 0.22, 0.27, footer_color.a))
	var runner := fmod(elapsed * 0.35, 1.0)
	draw_rect(Rect2(rail.position + Vector2(runner * rail.size.x * 0.7, 0.0),
		Vector2(rail.size.x * 0.3, maxf(1.0, fit))), Color(0.1, 0.72, 0.85, footer_color.a))
	var skip := tr("Skip intro") + "  /  ESC"
	var skip_width := font.get_string_size(skip, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	draw_string(font, Vector2(size.x - margin - skip_width, baseline), skip,
		HORIZONTAL_ALIGNMENT_LEFT, -1, small, footer_color)
