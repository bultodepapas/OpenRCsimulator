extends Control
## UI-28-R4: presentation only. Every moving piece comes from the refined vector master.

const Segments := preload("res://assets/branding/logo_segments.gd")
const ATLAS := preload("res://assets/branding/logo-segments.svg")
const ATMOSPHERE := preload("res://ui/shaders/brand_atmosphere.gdshader")
const INK := preload("res://ui/shaders/brand_segments.gdshader")
const LoadingBar := preload("res://ui/loading_bar.gd")
const DURATION := 4.8
const LOGO_CENTER := Vector2(847.5, 456.5)

signal skip_requested

var elapsed := 0.0
var playing := true
var text_scale := 1.0:
	set(value):
		text_scale = value
		_layout_footer()
var status_text := "Loading…":
	set(value):
		status_text = value
		_update_status()
## UI-28-R5: truthful preparation progress in [0, 1], set by the startup owner from completed stages.
## Monotonic, like the bar that draws it.
var progress := 0.0:
	set(value):
		if is_finite(value):
			progress = clampf(maxf(progress, value), 0.0, 1.0)
		if is_instance_valid(progress_bar):
			progress_bar.value = progress
## The current construction stage (an English source phrase, translated when drawn).
var detail_text := "":
	set(value):
		detail_text = value
		queue_redraw()
var status_label: Label
var skip_button: Button
var progress_bar: Control
var _footer: HBoxContainer
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
	progress_bar = LoadingBar.new()
	progress_bar.name = "StartupProgress"
	progress_bar.value = progress
	add_child(progress_bar)
	_build_footer()
	resized.connect(_on_resized)
	_layout_footer()
	_refresh()
	_focus_initial.call_deferred()


func _focus_initial() -> void:
	if not is_inside_tree():
		return
	if skip_button.disabled:
		if status_label.focus_mode != Control.FOCUS_NONE:
			status_label.grab_focus()
	else:
		skip_button.grab_focus()


func _process(delta: float) -> void:
	if playing:
		elapsed += minf(delta, 0.1) # Preserve the reveal after a slow first shader frame.
	_refresh()


## Deterministic presentation seam for the existing debug bridge and visual review.
func seek(seconds: float) -> void:
	playing = false
	elapsed = maxf(0.0, seconds)
	_refresh()


## UI-28-R5: resolve the lockup while Home is prepared, but keep the atmosphere and bar alive.
## Reduced motion and review stills keep their frozen seek() frame.
func settle() -> void:
	elapsed = maxf(elapsed, DURATION)
	_refresh()


func _refresh() -> void:
	if _mark == null:
		return
	_atmosphere.set_shader_parameter("clock", elapsed)
	_atmosphere.set_shader_parameter("viewport_size", size)
	_ink.set_shader_parameter("clock", elapsed)
	# Live-only decoration stays out of seek() stills, reduced motion and the trailer end card.
	_atmosphere.set_shader_parameter("live", 1.0 if playing else 0.0)
	_ink.set_shader_parameter("idle_clock", elapsed - DURATION if playing and elapsed > DURATION else -1.0)
	if is_instance_valid(progress_bar):
		progress_bar.reduced_motion = not playing
		progress_bar.modulate = Color(1.0, 1.0, 1.0, self_modulate.a * smoothstep(0.5, 1.2, elapsed))
	# The trailer hides this control's caption/footer with self_modulate while retaining the logo.
	if _footer != null and _footer.modulate != self_modulate:
		_footer.modulate = self_modulate
	_mark.queue_redraw()
	queue_redraw()


func _on_resized() -> void:
	_layout_footer()
	_refresh()


func _build_footer() -> void:
	_footer = HBoxContainer.new()
	_footer.name = "StartupFooter"
	_footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.add_theme_constant_override("separation", 24)
	add_child(_footer)
	status_label = Label.new()
	status_label.name = "StartupStatus"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color(0.85, 0.92, 0.95))
	_footer.add_child(status_label)
	skip_button = Button.new()
	skip_button.name = "SkipIntro"
	skip_button.focus_mode = Control.FOCUS_ALL
	skip_button.pressed.connect(func() -> void: skip_requested.emit())
	_footer.add_child(skip_button)
	_update_status()
	_update_skip_text()


func _update_status() -> void:
	if not is_instance_valid(status_label):
		return
	status_label.text = tr(status_text)
	status_label.accessibility_name = status_label.text
	# Control.accessibility_live is Off, Polite, Assertive in this order.
	var failed := status_text == "Unable to load. Please restart."
	status_label.accessibility_live = 2 if failed else 1
	status_label.focus_mode = Control.FOCUS_ALL if failed else Control.FOCUS_NONE
	if is_instance_valid(skip_button):
		skip_button.disabled = failed
		if failed and is_inside_tree():
			status_label.grab_focus()


func _update_skip_text() -> void:
	if not is_instance_valid(skip_button):
		return
	skip_button.text = tr("Skip intro") + "  /  ESC"
	skip_button.accessibility_name = tr("Skip intro")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_status()
		_update_skip_text()


func _layout_footer() -> void:
	if _footer == null:
		return
	var fit := minf(size.x / 1920.0, size.y / 1080.0)
	var scale := clampf(text_scale, 1.0, 2.0) if is_finite(text_scale) else 1.0
	var font_size := roundi(maxf(16.0, 18.0 * fit) * scale)
	var margin := maxf(24.0, 64.0 * fit)
	status_label.add_theme_font_size_override("font_size", font_size)
	skip_button.add_theme_font_size_override("font_size", font_size)
	skip_button.custom_minimum_size.y = maxf(44.0, font_size * 1.5)
	_footer.offset_left = margin
	_footer.offset_right = -margin
	_footer.offset_bottom = -margin
	_footer.offset_top = -margin - maxf(56.0, font_size * 3.0)
	if is_instance_valid(progress_bar):
		var bar_size := Vector2(minf(size.x - margin * 2.0, 560.0 * fit), maxf(5.0, roundf(8.0 * fit)))
		progress_bar.size = bar_size
		progress_bar.position = Vector2((size.x - bar_size.x) * 0.5, size.y * 0.765)


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
		elif piece.group == "BETA":
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
	# UI-28-R5: the current stage sits under the bar; the footer keeps the accessible status.
	if detail_text != "" and is_instance_valid(progress_bar):
		var detail := tr(detail_text)
		var detail_size := maxi(13, roundi(15.0 * fit * clampf(text_scale, 1.0, 2.0)))
		var detail_width := font.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size).x
		var top := progress_bar.position.y + progress_bar.size.y + 18.0 * fit + detail_size
		draw_string(font, Vector2((size.x - detail_width) * 0.5, top), detail, HORIZONTAL_ALIGNMENT_LEFT, -1,
			detail_size, Color(0.55, 0.70, 0.76, smoothstep(0.5, 1.2, elapsed)))
