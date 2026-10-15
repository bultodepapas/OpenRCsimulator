# UI-23: one logical coordinate system; native 3D resolution is preserved.
extends RefCounted

const DESIGN_SIZE := Vector2i(1280, 720)

static func apply(window: Window) -> void:
	window.content_scale_size = DESIGN_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_factor = 1.0

static func automatic_factor(pixels: Vector2i) -> float:
	return minf(float(pixels.x) / DESIGN_SIZE.x, float(pixels.y) / DESIGN_SIZE.y)
