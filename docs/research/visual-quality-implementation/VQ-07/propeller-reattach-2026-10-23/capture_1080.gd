## Fix the render viewport even when the desktop clips the requested window.
extends "res://tests/capture_propeller_blur.gd"

func _initialize() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	super._initialize()
