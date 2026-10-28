extends SceneTree

const CameraRig := preload("res://render/camera/camera_rig.gd")
const CameraSettings := preload("res://render/camera/camera_settings.gd")
const FlybyView := preload("res://render/camera/flyby_view.gd")
const Reconstruction := preload("res://render/reconstruction.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var viewport := SubViewport.new()
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var rig := CameraRig.new(camera, 1.5)
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var target := Vector3(0.0, 20.0, 0.0)
	var velocity := Vector3(0.0, 0.0, -20.0)
	var dt := 1.0 / 60.0
	var count := _count(viewport)
	_check("same and invalid views do not notify", rig.set_view("pilot") and not rig.set_view("missing")
		and _count(viewport) == count)
	_check("switching the same Camera3D view sends one request", rig.set_view("chase")
		and _count(viewport) == count + 1 and _reason(viewport) == "camera_view_changed")
	count = _count(viewport)
	_check("reselecting a view sends no request", rig.set_view("chase") and _count(viewport) == count)
	rig.select_view("chase")
	_check("changing chase style sends one request", _count(viewport) == count + 1
		and _reason(viewport) == "camera_chase_style_changed")
	rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, dt, false, flat, velocity)
	count = _count(viewport)
	for i in 120:
		target += velocity * dt
		rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, dt, false, flat, velocity)
	_check("ordinary smooth chase updates never request resets", _count(viewport) == count)
	rig.zoom(1.0)
	rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, dt, false, flat, velocity)
	_check("3D follow zoom snap sends one request", _count(viewport) == count + 1
		and _reason(viewport) == "camera_chase_zoom")
	count = _count(viewport)
	rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, dt, false, flat, velocity)
	_check("unchanged 3D follow zoom does not repeat the request", _count(viewport) == count)
	rig.reset()
	_check("flight reset sends one request", _count(viewport) == count + 1
		and _reason(viewport) == "camera_flight_reset")
	count = _count(viewport)
	target = Vector3(400.0, 20.0, 0.0)
	rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, dt, false, flat, velocity)
	_check("first placement after reset does not double-notify", _count(viewport) == count)
	target += Vector3(100.0, 0.0, 0.0)
	rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, dt, false, flat, velocity)
	_check("chase's existing teleport snap sends one request", _count(viewport) == count + 1
		and _reason(viewport) == "camera_target_teleport")
	count = _count(viewport)
	rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, dt, false, flat, velocity)
	_check("settled chase does not repeat the teleport request", _count(viewport) == count)

	rig.set_view("pilot")
	count = _count(viewport)
	rig.zoom(1.0)
	rig.toggle_auto_zoom()
	rig.set_zoom_law("partial")
	rig.set_base_fov(55.0)
	rig.reset_view()
	for i in 30:
		target += velocity * dt
		rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, dt, false, flat, velocity)
	_check("eased pilot zoom and preference changes do not request resets", _count(viewport) == count)

	rig.set_view("orbit")
	rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, dt, false, flat, velocity)
	count = _count(viewport)
	rig.drag(Vector2(20.0, 10.0))
	for i in 30:
		target += velocity * dt
		rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, dt, false, flat, velocity)
	_check("smoothed orbit motion does not request resets", _count(viewport) == count)
	rig.reset_view()
	_check("orbit reset snaps and sends one request", _count(viewport) == count + 1
		and _reason(viewport) == "camera_orbit_reset")
	rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, dt, false, flat, velocity)
	_check("orbit update does not repeat the reset", _count(viewport) == count + 1)

	rig.set_view("flyby")
	rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, dt, false, flat, velocity)
	count = _count(viewport)
	target = rig.flyby.position + velocity.normalized() * (FlybyView.REPLACE_PAST * FlybyView.DISTANCE_M + 1.0)
	rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, 10.0, false, flat, velocity)
	_check("fly-by camera replacement sends one request", _count(viewport) == count + 1
		and _reason(viewport) == "camera_flyby_reposition")
	count = _count(viewport)
	rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, dt, false, flat, velocity)
	_check("stationary fly-by update does not repeat the request", _count(viewport) == count)
	target += Vector3(300.0, 0.0, 0.0)
	rig.update(target, Transform3D(Basis.IDENTITY, target), Basis.IDENTITY, dt, false, flat, velocity)
	_check("fly-by teleport replacement sends one request", _count(viewport) == count + 1
		and _reason(viewport) == "camera_flyby_reposition")
	count = _count(viewport)
	rig.zoom(1.0)
	_check("fly-by FOV zoom sends one request", _count(viewport) == count + 1
		and _reason(viewport) == "camera_flyby_zoom")
	count = _count(viewport)
	rig.reset_view()
	_check("fly-by FOV reset sends one request", _count(viewport) == count + 1)
	count = _count(viewport)
	rig.reset_view()
	_check("unchanged fly-by FOV reset does not notify", _count(viewport) == count)

	var config := CameraSettings.normalized({"camera_view": "pilot"})
	CameraSettings.apply_at_start(rig, config)
	_check("first-view preference uses the same view-change seam", _count(viewport) == count + 1
		and _reason(viewport) == "camera_view_changed")
	count = _count(viewport)
	CameraSettings.apply_at_start(rig, config)
	_check("reapplying the same view preference does not notify", _count(viewport) == count)
	if not RenderingServer.has_method(Reconstruction.HISTORY_RESET_METHOD):
		_check("official engine reports requests without native submissions", int(_receipt(viewport).submitted) == 0)
	camera.free()
	rig.set_view("orbit")
	_check("freed camera cannot request a reset", _count(viewport) == count)
	viewport.free()
	print("camera history: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _receipt(viewport: Viewport) -> Dictionary:
	return viewport.get_meta(Reconstruction.HISTORY_RESET_META, {"notifications": 0, "submitted": 0, "last_reason": ""})


func _count(viewport: Viewport) -> int:
	return int(_receipt(viewport).notifications)


func _reason(viewport: Viewport) -> String:
	return str(_receipt(viewport).last_reason)


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
