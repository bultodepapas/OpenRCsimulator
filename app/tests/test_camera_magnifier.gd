# CAM-18: magnifier inset (docs/plans/camera-views.md §5.7).
#   - the aircraft's meshes join the magnifier layer; scenery does not; the main camera still sees everything;
#   - auto mode shows below 4 % of the main view's height and hides above 5 %, never flickering in between;
#   - the inset camera stands on the pilot's line of sight (Godot refuses FOV < 1°), sees only the aircraft layer,
#     frames the span at 60 % and keeps a tight depth range; a close aircraft is framed from the eye; hidden, it
#     renders nothing;
#   - a Home flight with the magnifier on shows it in the pilot view and hides it in chase.
# Run: godot --headless --path . --script res://tests/test_camera_magnifier.gd
extends SceneTree

const Magnifier := preload("res://render/camera/magnifier.gd")
const CameraSettings := preload("res://render/camera/camera_settings.gd")

class TestFlight extends "res://main.gd":
	var options: Dictionary = {}
	func _user_args() -> Dictionary:
		return options

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_tagging()
	_hysteresis()
	await _inset_camera()
	await _flight()
	print("all %d magnifier checks passed" % _count if _failures == 0 else "%d of %d failed" % [_failures, _count])
	quit(1 if _failures > 0 else 0)


func _tagging() -> void:
	var model := Node3D.new()
	var wing := MeshInstance3D.new()
	var nested := Node3D.new()
	var tail := MeshInstance3D.new()
	model.add_child(wing)
	model.add_child(nested)
	nested.add_child(tail)
	var scenery := MeshInstance3D.new()
	Magnifier.tag(model)
	_check("every aircraft mesh joins the magnifier layer, nested ones too", (wing.layers & Magnifier.LAYER) != 0 and (tail.layers & Magnifier.LAYER) != 0)
	_check("and keeps its own layer for the main camera", (wing.layers & 1) != 0)
	_check("scenery stays off the magnifier layer", (scenery.layers & Magnifier.LAYER) == 0)
	_check("the magnifier layer is not crash debris's (1 << 19)", Magnifier.LAYER != (1 << 19))
	model.free()
	scenery.free()


func _hysteresis() -> void:
	var inset := Magnifier.new()
	inset.mode = "auto"
	var seen: Array = []
	for share: float in [0.08, 0.045, 0.03, 0.045, 0.049, 0.06, 0.045]:
		seen.append(inset.wants(share, true))
	_check("auto: hidden while large, shown below 4 %, kept until above 5 %", seen == [false, false, true, true, true, false, false], str(seen))
	inset.mode = "on"
	_check("on: shown whatever the size", inset.wants(0.5, true))
	_check("never outside the pilot view", not inset.wants(0.01, false))
	inset.mode = "off"
	_check("off: never", not inset.wants(0.01, true))
	inset.free()


func _inset_camera() -> void:
	var main_camera := Camera3D.new()
	root.add_child(main_camera)
	main_camera.position = Vector3(0, 1.7, 0)
	main_camera.fov = 50.0
	var inset := Magnifier.new()
	root.add_child(inset)
	await process_frame
	var model := MeshInstance3D.new()
	inset.mode = "on"
	var target := Vector3(30, 40, -200)
	var span := 1.5
	inset.update(main_camera, target, span, model, true)
	var cam: Camera3D = inset.camera
	_check("on: the inset shows and renders", inset.shown and inset._viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	_check("its camera sees only the aircraft layer", cam.cull_mask == Magnifier.LAYER)
	var sight := (target - main_camera.position).normalized()
	_check("on the pilot's line of sight, looking the same way at the aircraft", (cam.global_position - main_camera.position).normalized().dot(sight) > 0.99999
		and (-cam.global_basis.z).dot(sight) > 0.99999 and is_equal_approx(cam.fov, Magnifier.INSET_FOV_DEG))
	var frame := cam.global_position.distance_to(target)
	var share := span / (2.0 * frame * tan(deg_to_rad(cam.fov) * 0.5))
	_check("the span fills 60 % of the inset", absf(share - Magnifier.FILL) < 0.01, "%.3f" % share)
	_check("a tight depth range around the aircraft", cam.near < frame - span and cam.far > frame + span and cam.far < frame + 3.0 * span, "%.1f…%.1f at %.1f" % [cam.near, cam.far, frame])
	var close := Vector3(0, 3, -6)
	inset.update(main_camera, close, span, model, true)
	_check("a close aircraft is framed from the pilot's eye with a wider FOV", cam.global_position.distance_to(main_camera.position) < 1e-4 and cam.fov > Magnifier.INSET_FOV_DEG)
	_check("the passed model was tagged", (model.layers & Magnifier.LAYER) != 0)
	inset.mode = "off"
	inset.update(main_camera, target, span, model, true)
	_check("off: hidden and not rendering", not inset.shown and not inset.visible and inset._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	model.free()
	inset.queue_free()
	main_camera.queue_free()
	await process_frame


func _flight() -> void:
	var flight: TestFlight = TestFlight.new()
	flight.options = {"soundscape": "off", "crash-effects": "off", "smoke": "off"}
	flight.camera_preferences = CameraSettings.normalized({camera_magnifier = "on"})
	root.add_child(flight)
	await process_frame
	for i in 3:
		flight._process(1.0 / 60.0)
	var inset: Magnifier = flight._magnifier
	_check("Home flight with the magnifier on: shown in the pilot view", inset != null and inset.shown and flight._rig.view == "pilot")
	var tagged := true
	for node: Node in flight._airplane.root.find_children("*", "VisualInstance3D", true, false):
		tagged = tagged and ((node as VisualInstance3D).layers & Magnifier.LAYER) != 0
	_check("every mesh of the flown airplane is on the magnifier layer", tagged)
	var field := flight.get_node_or_null("Field")
	var scenery_clean := true
	if field != null:
		for node: Node in field.find_children("*", "VisualInstance3D", true, false):
			scenery_clean = scenery_clean and ((node as VisualInstance3D).layers & Magnifier.LAYER) == 0
	_check("no field mesh is on it", scenery_clean)
	flight._rig.set_view("chase")
	flight._process(1.0 / 60.0)
	_check("hidden in the chase view", not inset.shown)
	flight.free()
	await process_frame
	var plain: TestFlight = TestFlight.new()
	plain.options = {"soundscape": "off", "crash-effects": "off", "smoke": "off"}
	root.add_child(plain)
	await process_frame
	plain._process(1.0 / 60.0)
	_check("a command-line flight never shows it", not plain._magnifier.shown)
	plain.free()
	await process_frame
