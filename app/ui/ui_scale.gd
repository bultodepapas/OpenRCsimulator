# UI-23: fit the logical CanvasItem area to the display while keeping the 3D viewport native resolution.
extends RefCounted

const REFERENCE_SIZE := Vector2i(1920, 1080)
const COMPACT_WIDTH := 1500
const COMPACT_HEIGHT := 850


static func apply(window: Window) -> Dictionary:
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_factor = 1.0
	var pixels := window.size
	if pixels.x <= 0 or pixels.y <= 0:
		return {"factor": 1.0, "logical_size": window.content_scale_size, "compact": true}
	var logical := logical_size_for(pixels)
	if window.content_scale_size != logical:
		window.content_scale_size = logical
	return {"factor": automatic_factor(pixels), "logical_size": logical, "compact": is_compact(logical)}


## Kept as the shared scale API for existing callers and tests.
static func automatic_factor(pixels: Vector2i) -> float:
	if pixels.x <= 0 or pixels.y <= 0:
		return 1.0
	return maxf(1.0, minf(float(pixels.x) / REFERENCE_SIZE.x, float(pixels.y) / REFERENCE_SIZE.y))


static func logical_size_for(pixels: Vector2i) -> Vector2i:
	if pixels.x <= 0 or pixels.y <= 0:
		return Vector2i.ZERO
	var factor := automatic_factor(pixels)
	return Vector2i(maxi(1, roundi(float(pixels.x) / factor)), maxi(1, roundi(float(pixels.y) / factor)))


## UI-35c (UI-30 SP-5): beyond a 21:9 canvas the menus keep a centred 2560-wide span; the scene still fills the screen.
const SPAN_WIDTH := 2560.0


## Logical pixels between each screen edge and the menu span (0 up to 21:9).
static func span_margin(logical_width: float) -> float:
	return maxf(0.0, (logical_width - SPAN_WIDTH) * 0.5) if logical_width > SPAN_WIDTH + 40.0 else 0.0


static func is_compact(logical_size: Vector2i) -> bool:
	return logical_size.x < COMPACT_WIDTH or logical_size.y < COMPACT_HEIGHT


## PopupMenu windows cache their opening position; reshow visible OptionButton popups after layout reflows.
static func realign_popups(root: Node) -> void:
	for node: Node in root.find_children("*", "OptionButton", true, false):
		var option := node as OptionButton
		var popup: PopupMenu = option.get_popup()
		if popup.visible:
			option.show_popup()
