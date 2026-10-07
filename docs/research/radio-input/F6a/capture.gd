# Run with the real project and a display; synthetic samples are visual verification only.
extends SceneTree

class MeasuredFlight extends "res://main.gd":
	func _user_args() -> Dictionary:
		return {"latency-patch": true}

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var flight: MeasuredFlight = MeasuredFlight.new()
	root.add_child(flight)
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	var patch: CanvasLayer = flight.get_node("LatencyPatch")
	patch.set_physics_process(false)
	await _capture(patch, "inactive-1280", Color(0.4, 0.4, 0.4))
	flight.session.radio.connect_device(15, {name = "Fake EdgeTX"})
	flight.session.radio.on_motion(15, 0, -0.5)
	await _capture(patch, "below-1280", Color.BLACK)
	flight.session.radio.on_motion(15, 0, 0.5)
	await _capture(patch, "above-1280", Color.WHITE)
	root.size = Vector2i(800, 600)
	await _capture(patch, "above-800", Color.WHITE)
	flight.free()
	print("F6a rendered checks: 4 captures, %d failures; fake radio, no latency measurement" % _failures)
	quit(1 if _failures else 0)


func _capture(patch: CanvasLayer, filename: String, color: Color) -> void:
	patch._physics_process(0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var rect: Rect2 = patch.marker.get_global_rect()
	var shot: Image = root.get_texture().get_image()
	var center: Vector2i = Vector2i(rect.get_center())
	var actual: Color = shot.get_pixelv(center)
	if not root.get_visible_rect().encloses(rect) or rect.size != Vector2(192, 192) or not actual.is_equal_approx(color):
		_failures += 1
		printerr("FAIL ", filename, " rect=", rect, " pixel=", actual, " expected=", color)
	var output: String = get_script().resource_path.get_base_dir().path_join(filename + ".png")
	if shot.save_png(output) != OK:
		_failures += 1
		printerr("FAIL writing ", output)
	print(filename, ": viewport=", root.size, " marker=", rect, " pixel=", actual)
