extends SceneTree

const Controller := preload("res://render/flight_compatibility_resolution.gd")
const Reconstruction := preload("res://render/reconstruction.gd")

var _view: SubViewport
var _controller: RefCounted
var _config := {dynamic_resolution_fps = 30, render_scale = 75}
var _time_usec := 0
var _draws := 0
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(1920, 1080)
	root.add_child(_view)

	_start(0.75)
	_frames(110, 40_000) # Initial settle and fewer than two slow windows.
	_check("one slow window leaves the saved scale alone", _at(0.75))
	_frames(70, 40_000)
	_check("sustained slow rendered frames try the measured 67 percent rung",
		_at(0.67) and _reason() == "testing_lower_scale")
	_frames(140, 32_000)
	_check("a pacing gain keeps the lower rung without changing the saved setting",
		_at(0.67) and _config.render_scale == 75)
	_check("status separately identifies rendered-frame timing", _view.get_meta(Controller.STATUS_META).source == "rendered_frame_interval")
	_frames(550, 20_000)
	_check("sustained headroom tries the higher rung", _at(0.75) and _reason() == "testing_higher_scale")
	_frames(170, 26_000)
	_check("the higher rung stays when it meets the target", _at(0.75))
	_controller.stop(_view)

	_start(0.75)
	_frames(180, 40_000)
	_check("the comparison starts at the lower rung", _at(0.67))
	_frames(180, 39_000)
	_check("a lower scale with no meaningful gain restores the previous rung",
		_at(0.75) and _reason() == "no_measured_gain")
	_frames(300, 42_000)
	_check("a rejected reduction stays parked for the active session", _at(0.75))
	_controller.stop(_view)

	_start(0.75)
	_frames(250, 40_000, 0)
	_frames(250, 40_000, 2)
	_frames(250, 300_000)
	_check("process-only ticks, draw gaps and long stalls do not cause a reduction", _at(0.75))
	_frames(180, 40_000)
	_check("normal draw intervals are sampled after gaps", _at(0.67))
	_controller.tick(_view, 1, false, _config)
	_check("suspending restores the saved scale and clears status",
		_at(0.75) and not _view.has_meta(Controller.STATUS_META))
	_frames(180, 40_000)
	_check("resuming starts a fresh comparison", _at(0.67))
	_config.dynamic_resolution_fps = 0
	_frames(1, 40_000)
	_check("turning dynamic resolution off restores the saved scale", _at(0.75))
	_controller.stop(_view)

	_start(0.75)
	_frames(180, 40_000)
	_view.size = Vector2i(1367, 769)
	_frames(1, 40_000)
	_check("resizing restores the ceiling before making new decisions", _at(0.75) and _reason() == "warming")
	_frames(180, 40_000)
	_view.set_meta(Reconstruction.POLICY_META, {provider = "native", scale = 0.85})
	_view.scaling_3d_scale = 0.85
	_controller.stop(_view)
	_check("another reconstruction owner keeps its value on stop", _at(0.85))

	_start(0.67)
	_frames(250, 42_000)
	_check("a saved scale at the floor stays fixed", _at(0.67) and _reason() == "no_legal_scale_range")
	_controller.stop(_view)
	_view.queue_free()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _start(scale: float) -> void:
	_view.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_view.scaling_3d_scale = scale
	_view.set_meta(Reconstruction.POLICY_META, {provider = "native", scale = scale})
	_config.dynamic_resolution_fps = 30
	_config.render_scale = roundi(scale * 100.0)
	_controller = Controller.new()
	_controller.clock_usec = func() -> int: return _time_usec
	_controller.draw_count = func() -> int: return _draws


func _frames(count: int, elapsed_usec: int, draws: int = 1) -> void:
	for i in count:
		_time_usec += elapsed_usec
		_draws += draws
		_controller.tick(_view, 1, true, _config)


func _at(scale: float) -> bool:
	return is_equal_approx(_view.scaling_3d_scale, scale)


func _reason() -> String:
	return str(_view.get_meta(Controller.STATUS_META, {}).get("reason", ""))


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label)
