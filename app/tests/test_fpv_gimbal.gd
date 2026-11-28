## CAM-FPV-04a: requested angles, accepted ticks and the final drawn camera.
extends SceneTree

const Rig := preload("res://render/camera/camera_rig.gd")
const Gimbal := preload("res://render/camera/fpv_gimbal.gd")
const DT := 1.0 / 240.0

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["ok" if ok else "FAIL", label])


## Analytic body-frame optical direction for right yaw followed by local uptilt.
func _forward(yaw_deg: float, pitch_deg: float) -> Vector3:
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	return Vector3(sin(y) * cos(p), sin(p), -cos(y) * cos(p))


## Submit the same command tape on accepted ticks. Rendering samples the
## joint bracket at its own cadence and must not advance either endpoint.
func _tape(hz: int) -> Array[Basis]:
	var gimbal := Gimbal.new(Vector2(12, 8))
	var trace: Array[Basis] = []
	var accepted := 0
	for frame in range(1, hz + 1):
		var clock := float(frame * 240) / float(hz)
		while accepted < floori(clock):
			accepted += 1
			match accepted:
				1: gimbal.aim_by(Vector2(100, 100))
				61: gimbal.aim_by(Vector2(-100, -100))
				140: gimbal.recenter()
			gimbal.seal_input_after(accepted - 1)
			gimbal.accept(accepted, accepted * DT, DT)
			trace.append(gimbal.orientation(1.0))
		gimbal.orientation(clock - floor(clock))
	return trace


func _accepted_motion() -> void:
	var trace := _tape(30)
	_check(trace.size() == 240 and trace == _tape(60) and trace == _tape(144),
		"30/60/144 Hz rendering gives the same 240 accepted joint poses")
	_check((-trace[0].z).is_equal_approx(_forward(90.0 * DT, 90.0 * DT)), "first tick obeys the servo rate")
	_check((-trace[59].z).is_equal_approx(_forward(12.0, 8.0)) and (-trace[138].z).is_equal_approx(_forward(-12.0, -8.0)),
		"targets saturate at both mechanical stops")
	_check(trace.back().is_equal_approx(Basis.IDENTITY), "recenter reaches the exact neutral pose")
	var gimbal := Gimbal.new(Vector2(12, 8))
	gimbal.aim_by(Vector2(12, 8))
	gimbal.seal_input_after(6)
	gimbal.accept(7, 7 * DT, DT)
	var endpoint := gimbal.orientation(1.0)
	_check((-gimbal.orientation(0.5).z).is_equal_approx(_forward(45.0 * DT, 45.0 * DT)),
		"half a drawn tick samples the attained joints halfway")
	gimbal.accept(7, 7 * DT, DT)
	gimbal.accept(6, 6 * DT, DT)
	_check(gimbal.orientation(1.0) == endpoint, "duplicate and stale ticks leave achieved angles alone")
	gimbal.accept(12, 12 * DT, DT)
	gimbal.accept(13, 13 * DT, DT)
	_check(gimbal.orientation(0.0).is_equal_approx(endpoint) and gimbal.orientation(1.0).is_equal_approx(endpoint),
		"a missing tick holds aim and clears outstanding motion")
	gimbal.aim_by(Vector2(-12, 0))
	gimbal.seal_input_after(13)
	gimbal.aim_by(Vector2(-1, 0))
	gimbal.hold()
	gimbal.seal_input_after(13)
	gimbal.accept(14, 14 * DT, DT)
	_check(gimbal.orientation(1.0).is_equal_approx(endpoint), "focus loss prevents stale drag on resume")
	gimbal.aim_by(Vector2(12, 8))
	gimbal.seal_input_after(14)
	gimbal.reset()
	gimbal.accept(1, DT, DT)
	_check(gimbal.orientation(1.0).is_equal_approx(Basis.IDENTITY), "a new flight at tick one starts centered")


func _frame_backlog() -> void:
	var gimbal := Gimbal.new(Vector2(12, 8))
	gimbal.aim_by(Vector2(8, 4))
	for tick in range(1, 9):
		gimbal.accept(tick, tick * DT, DT)
	_check(gimbal.orientation(1.0).is_equal_approx(Basis.IDENTITY), "catch-up steps preceding the frame seal cannot use new input")
	gimbal.seal_input_after(8)
	gimbal.recenter()
	gimbal.aim_by(Vector2(-3, 0))
	gimbal.seal_input_after(8)
	gimbal.aim_by(Vector2(6, 4)) # Newer unsealed input must not change tick 9.
	gimbal.accept(9, 9 * DT, DT)
	_check((-gimbal.orientation(1.0).z).is_equal_approx(_forward(-90.0 * DT, 0.0)),
		"commands for the same next tick preserve their order and use only its sealed target")
	gimbal.seal_input_after(9)
	gimbal.accept(10, 10 * DT, DT)
	_check((-gimbal.orientation(1.0).z).is_equal_approx(_forward(0.0, 90.0 * DT)),
		"subsequent input starts with its own eligible tick")


func _installed_camera() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	var rig := Rig.new(camera, 1.5)
	var mount := Transform3D(Basis.IDENTITY, Vector3(0.1, 0.2, -0.5))
	var bank := Basis(Vector3.FORWARD, PI / 2.0)
	var datum := Transform3D(bank * Basis.from_scale(Vector3(2, 3, 4)), Vector3.ZERO)
	var activity: Array[bool] = []
	rig.fpv_look_active_changed.connect(func(active: bool) -> void: activity.append(active))
	_check(rig.set_fpv_mount(mount, 90.0, 0.03) and rig.set_view("fpv") and not rig.can_drag_fpv(),
		"rigid mounts require no gimbal or tick observer")
	_check(rig.set_fpv_mount(mount, 90.0, 0.03, Vector2(12, 8)) and activity == [true],
		"admitting look on the active mount starts its observer")
	rig.drag(Vector2(1000, -1000))
	rig.seal_fpv_input_after(0)
	for tick in range(1, 61):
		rig.accept_fpv_tick(tick, tick * DT, DT)
	var invalid := rig.set_fpv_mount(mount, 90.0, 0.03, Vector2(-1, 8))
	_check(not invalid and rig.can_drag_fpv() and activity == [true], "refused replacement preserves the active mount")
	rig.update(Vector3.ZERO, datum, bank, 0.01, false, Callable())
	var real_pose := camera.transform
	var local := _forward(12.0, 8.0)
	_check((-real_pose.basis.z).is_equal_approx(Vector3(local.y, -local.x, local.z))
		and real_pose.origin.is_equal_approx(Vector3(0.6, -0.2, -2.0)), "body bank, yaw then local pitch and once-scaled lever arm")
	_check(rig.evidence().fpv_optics_backend == "godot_transform_ops", "reports the optic path used")
	rig.use_engine_transform = false
	rig.update(Vector3.ZERO, datum, bank, 0.01, false, Callable())
	_check(camera.transform.is_equal_approx(real_pose) and rig.evidence().fpv_optics_backend == "gdscript_reference",
		"reference optic agrees with engine transforms on the installed gimbal")
	rig.reset_view()
	rig.seal_fpv_input_after(60)
	for tick in range(61, 121):
		rig.accept_fpv_tick(tick, tick * DT, DT)
	rig.update(Vector3.ZERO, datum, bank, 0.01, false, Callable())
	_check(camera.transform.basis.is_equal_approx(bank), "Backspace recenters the installed camera")
	rig.set_view("pilot")
	rig.clear_fpv_mount()
	_check(activity == [true, false] and not rig.can_drag_fpv(), "leaving FPV stops the observer once")
	camera.free()


func _run() -> void:
	_accepted_motion()
	_frame_backlog()
	_installed_camera()
	print("FPV manual gimbal: %d failed" % _failures)
	quit(1 if _failures else 0)
