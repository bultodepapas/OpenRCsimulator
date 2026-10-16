# UI-25-R2: catalog-wide render-only grounding and viewport framing.
extends SceneTree
const HomeScene = preload("res://ui/home_scene.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(label: String, ok: bool) -> void:
	print("ok   " + label if ok else "FAIL " + label)
	if not ok: failures += 1
func run() -> void:
	var scene := HomeScene.new()
	root.add_child(scene)
	for entry in Catalog.ENTRIES:
		check(entry.id + " builds", scene.show_aircraft(entry.id))
		var pose: Dictionary = scene._presentation
		check(entry.id + " has wheel/skid support", pose.grounded)
		var low := INF
		var high := -INF
		for contact: Vector3 in pose.contacts:
			var height: float = (scene.airplane.root.transform * contact).y
			low = minf(low, height)
			high = maxf(high, height)
		check(entry.id + " rests on the field without contact penetration", low >= 0.0 and high <= 0.016)
		for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3840,2160),Vector2i(2560,1080),Vector2i(720,1280)]:
			root.size = dimensions
			await process_frame
			scene._frame_aircraft()
			var extent := Rect2()
			for i in 8:
				var point := scene.camera.unproject_position(scene.airplane.root.transform * pose.bounds.get_endpoint(i))
				extent = Rect2(point,Vector2.ZERO) if i == 0 else extent.expand(point)
			var viewport_size := root.get_visible_rect().size
			check(entry.id + " inside " + str(dimensions), extent.position.x > viewport_size.x * 0.25 and extent.end.x < viewport_size.x * 0.98 and extent.position.y > 0 and extent.end.y < viewport_size.y * 0.92)
		check("preview cache remains bounded", scene._preview_models.size() <= HomeScene.PREVIEW_MODEL_LIMIT)
	scene.queue_free()
	await process_frame
	print("Home presentation: %d failures" % failures)
	quit(1 if failures else 0)
