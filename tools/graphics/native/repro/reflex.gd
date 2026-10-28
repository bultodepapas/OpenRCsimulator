extends SceneTree

# Bounded SDK-call/marker smoke, not a latency or visual-quality measurement.
const STREAMLINE := "Streamline"
const FRAMES_PER_PHASE := 48
const COUNT_KEYS: Array[String] = [
	"state_calls", "sleep_successes", "simulation_start_successes", "render_start_successes",
	"render_end_successes", "present_start_successes", "present_end_successes",
]

var _cube: MeshInstance3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless" or not Engine.has_singleton(STREAMLINE):
		printerr("REFLEX_SMOKE|UNAVAILABLE|reason=rendered_streamline_required")
		quit(2)
		return
	var streamline: Object = Engine.get_singleton(STREAMLINE)
	if not streamline.has_method("get_reflex_status") or not streamline.has_method("set_parameter") \
			or not ClassDB.class_has_integer_constant(STREAMLINE, "STREAMLINE_PARAM_REFLEX_MODE"):
		printerr("REFLEX_SMOKE|UNAVAILABLE|reason=reflex_status_api_missing")
		quit(2)
		return
	_build_scene()
	for _frame: int in range(8):
		_cube.rotate_y(0.01)
		await RenderingServer.frame_post_draw
	var initial: Dictionary = streamline.call("get_reflex_status")
	print("REFLEX_SMOKE|INITIAL|status=%s" % JSON.stringify(initial))
	if not bool(initial.get("available", false)):
		printerr("REFLEX_SMOKE|UNAVAILABLE|reason=reflex_not_available")
		quit(2)
		return
	var parameter := ClassDB.class_get_integer_constant(STREAMLINE, "STREAMLINE_PARAM_REFLEX_MODE")
	for mode: int in [0, 1, 2, 0]:
		if not await _run_phase(streamline, parameter, mode):
			quit(3)
			return
	print("REFLEX_SMOKE|COMPLETE|phases=4|frames_per_phase=%d" % FRAMES_PER_PHASE)
	quit(0)


func _build_scene() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 5)
	scene.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	var mesh := BoxMesh.new()
	_cube = MeshInstance3D.new()
	_cube.mesh = mesh
	scene.add_child(_cube)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	scene.add_child(light)


func _run_phase(streamline: Object, parameter: int, mode: int) -> bool:
	var before: Dictionary = streamline.call("get_reflex_status")
	streamline.call("set_parameter", parameter, float(mode))
	for _frame: int in range(FRAMES_PER_PHASE):
		_cube.rotate_y(0.01)
		await RenderingServer.frame_post_draw
	var after: Dictionary = streamline.call("get_reflex_status")
	print("REFLEX_SMOKE|PHASE|mode=%d|status=%s" % [mode, JSON.stringify(after)])
	if not bool(after.get("available", false)) or bool(after.get("backend_failed", true)) \
			or int(after.get("requested_mode", -1)) != mode or int(after.get("applied_mode", -1)) != mode \
			or int(after.get("state_result", -1)) != 0 or int(after.get("set_result", -1)) != 0 \
			or int(after.get("sleep_result", -1)) != 0 \
			or int(after.get("pcl_marker_result", -1)) != 0 or int(after.get("expired_tokens", -1)) != 0:
		printerr("REFLEX_SMOKE|FAIL|reason=mode_or_backend|mode=%d" % mode)
		return false
	for key: String in COUNT_KEYS:
		if int(after.get(key, 0)) <= int(before.get(key, 0)):
			printerr("REFLEX_SMOKE|FAIL|reason=counter_did_not_advance|mode=%d|key=%s" % [mode, key])
			return false
	return true
