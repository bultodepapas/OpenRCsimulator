# CAM-02/05/08/10: the camera rig and its views on synthetic trajectories (docs/plans/camera-views.md).
#   - pilot, close-up and landscape views are exactly what render/pilot_camera.gd produces (no picture change);
#   - a Z toggle or manual zoom never jumps the FOV and settles on the law; Backspace returns to it;
#   - chase: settled pose, frame-rate independence, circle/vertical/tail-slide/terrain/teleport cases;
#   - orbit: starts where the previous view was, clamps, keeps clear of the ground.
# Run: godot --headless --path . --script res://tests/test_camera_views.gd
extends SceneTree

const Spec := preload("res://spec.gd")
const PilotCamera := preload("res://render/pilot_camera.gd")
const CameraMath := preload("res://render/camera/camera_math.gd")
const CameraRig := preload("res://render/camera/camera_rig.gd")
const ChaseView := preload("res://render/camera/chase_view.gd")
const OrbitView := preload("res://render/camera/orbit_view.gd")

const SPAN := 1.524

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _camera() -> Camera3D:
	var pilot := { north = 0.0, east = 0.0, down = 0.0, eye_height = 1.7 }
	return PilotCamera.create(root, pilot)


static func _flat(_x: float, _z: float) -> float:
	return 0.0


## A level airplane flying along a render heading: its basis has the nose (−z) on that heading.
static func _level(heading: float) -> Basis:
	return Basis(Vector3.UP, -heading)


## Chase camera relative to the airplane after `duration` s of straight flight north at 20 m/s, sampled at fps.
func _straight(fps: float, duration: float) -> Vector3:
	var chase := ChaseView.new()
	chase.configure(SPAN)
	var dt := 1.0 / fps
	var target := Vector3(0, 30, 0)
	var placed := {}
	for i in roundi(duration * fps) + 1:
		target = Vector3(0, 30, -20.0 * i * dt)
		placed = chase.update(target, _level(0.0), dt, false, _flat)
	return (placed.position as Vector3) - target


func _initialize() -> void:
	_run.call_deferred() # cameras must be inside the tree for look_at


func _run() -> void:
	_pilot_parity()
	_pilot_singularities()
	_pilot_zoom()
	_cycle()
	_chase()
	_orbit()
	print("all %d camera view checks passed" % _count if _failures == 0 else "%d of %d failed" % [_failures, _count])
	quit(1 if _failures > 0 else 0)


func _pilot_parity() -> void:
	var cam := _camera()
	var ref := _camera()
	var rig := CameraRig.new(cam, SPAN)
	var airplane := Transform3D(Basis(Vector3.UP, 0.4), Vector3(40, 25, -90))
	for auto_zoom: bool in [true, false]:
		rig.auto_zoom = auto_zoom
		rig.update(airplane.origin, airplane, airplane.basis, 1.0 / 60.0, false, _flat)
		PilotCamera.aim(ref, airplane.origin, airplane, false, SPAN if auto_zoom else 0.0)
		_check("pilot view (auto-zoom %s) is exactly PilotCamera.aim" % auto_zoom, cam.transform == ref.transform and cam.fov == ref.fov, "%f vs %f" % [cam.fov, ref.fov])
	rig.set_view("closeup")
	rig.update(airplane.origin, airplane, airplane.basis, 1.0 / 60.0, false, _flat)
	PilotCamera.aim(ref, airplane.origin, airplane, true)
	_check("close-up view is exactly PilotCamera.aim(inspect)", cam.transform == ref.transform and cam.fov == ref.fov)
	rig.look = Vector2(90.0, 10.0)
	rig.look_height = 30.0
	rig.update(airplane.origin, airplane, airplane.basis, 1.0 / 60.0, false, _flat)
	PilotCamera.look(ref, 90.0, 10.0, 30.0)
	_check("landscape look view is exactly PilotCamera.look", cam.transform == ref.transform and cam.fov == ref.fov)
	cam.queue_free()
	ref.queue_free()


func _pilot_singularities() -> void:
	var cam := _camera()
	var rig := CameraRig.new(cam, SPAN)
	rig.auto_zoom = false
	var eye := Vector3(0, 1.7, 0)
	cam.position = eye
	cam.look_at(eye + Vector3(20, 10, 0), Vector3.UP)
	for offset: Vector3 in [Vector3(0, 30, 0), Vector3(0, -30, 0), Vector3(0.000001, 30, 0), Vector3(0.00024, 30, 0.00024)]:
		var previous_right := cam.basis.x
		var target := eye + offset
		var pose := Transform3D(Basis.IDENTITY, target)
		rig.update(target, pose, pose.basis, 1.0 / 60.0, false, _flat)
		_check("pilot vertical target remains aimed " + str(offset), (-cam.basis.z).dot(offset.normalized()) > 0.99999)
		_check("pilot vertical basis stays orthonormal", cam.basis.is_finite() and cam.basis.is_equal_approx(cam.basis.orthonormalized()) and absf(cam.basis.determinant() - 1.0) < 0.00001)
		_check("pilot pole keeps the preceding screen-right direction", cam.basis.x.dot(previous_right) > 0.99999)
	# A preceding rolled view can put its right axis on the new viewing direction.
	var pole := eye + Vector3(0, 30, 0)
	for preceding: Basis in [Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)), Basis(Vector3.FORWARD, -PI / 2.0 + 1e-7)]:
		cam.basis = preceding
		rig.update(pole, Transform3D(Basis.IDENTITY, pole), Basis.IDENTITY, 1.0 / 60.0, false, _flat)
		_check("parallel or nearly parallel preceding right axis falls back to finite aimed basis", cam.basis.is_finite() and (-cam.basis.z).dot(Vector3.UP) > 0.99999)
		_check("parallel or nearly parallel preceding right axis falls back to north-up", cam.basis.y.dot(Vector3.FORWARD) > 0.99999)
	var previous := cam.basis
	rig.update(eye, Transform3D(Basis.IDENTITY, eye), Basis.IDENTITY, 1.0 / 60.0, false, _flat)
	_check("coincident pilot target preserves last orientation", cam.basis == previous)
	var ordinary := eye + Vector3(20, 10, -40)
	rig.update(ordinary, Transform3D(Basis.IDENTITY, ordinary), Basis.IDENTITY, 1.0 / 60.0, false, _flat)
	var reference := _camera()
	reference.position = eye
	reference.look_at(ordinary, Vector3.UP)
	_check("ordinary pilot target retains exact look_at basis", cam.basis == reference.basis)
	cam.free()
	reference.free()


func _pilot_zoom() -> void:
	var cam := _camera()
	var rig := CameraRig.new(cam, SPAN)
	var airplane := Transform3D(Basis.IDENTITY, Vector3(0, 40, -200))
	var dt := 1.0 / 60.0
	rig.update(airplane.origin, airplane, airplane.basis, dt, false, _flat)
	var law_on := cam.fov
	_check("far airplane: the auto-zoom law is narrower than the base FOV", law_on < Spec.CAMERA.fov_deg - 1.0, "%.2f" % law_on)
	rig.toggle_auto_zoom()
	rig.update(airplane.origin, airplane, airplane.basis, dt, false, _flat)
	_check("Z: the first frame after the toggle keeps the FOV (no jump)", absf(cam.fov - law_on) < 1e-6, "%.4f → %.4f" % [law_on, cam.fov])
	var largest_step := 0.0
	var last := cam.fov
	for i in 120:
		rig.update(airplane.origin, airplane, airplane.basis, dt, false, _flat)
		largest_step = maxf(largest_step, absf(cam.fov - last))
		last = cam.fov
	_check("Z: settles on the base FOV within 2 s", absf(cam.fov - Spec.CAMERA.fov_deg) < 0.01, "%.4f" % cam.fov)
	_check("Z: no frame changes the FOV by more than 3°", largest_step < 3.0, "%.3f" % largest_step)
	rig.toggle_auto_zoom()
	for i in 180:
		rig.update(airplane.origin, airplane, airplane.basis, dt, false, _flat)
	_check("Z back on: the law's exact FOV again after 3 s", cam.fov == law_on, "%.6f vs %.6f" % [cam.fov, law_on])
	rig.zoom(2.0)
	for i in 120:
		rig.update(airplane.origin, airplane, airplane.basis, dt, false, _flat)
	var expected := CameraMath.zoomed_fov(law_on, pow(CameraRig.ZOOM_STEP, -2.0))
	_check("two zoom-in steps narrow tan(fov/2) by √2", absf(cam.fov - expected) < 0.01, "%.4f vs %.4f" % [cam.fov, expected])
	for i in 40:
		rig.zoom(1.0)
	_check("pilot zoom stops at its limit", rig.pilot_zoom == CameraRig.PILOT_ZOOM_MIN)
	rig.reset_view()
	for i in 180:
		rig.update(airplane.origin, airplane, airplane.basis, dt, false, _flat)
	_check("Backspace: back to the law's exact FOV", cam.fov == law_on and rig.pilot_zoom == 1.0, "%.6f" % cam.fov)
	cam.queue_free()


func _cycle() -> void:
	var cam := _camera()
	var rig := CameraRig.new(cam, SPAN)
	var seen := []
	for i in CameraRig.VIEWS.size():
		seen.append(rig.view)
		rig.cycle(1)
	_check("C cycles pilot → chase → orbit → close-up → pilot", seen == ["pilot", "chase", "orbit", "closeup"] and rig.view == "pilot", str(seen))
	rig.cycle(-1)
	_check("Shift+C goes back", rig.view == "closeup")
	_check("unknown view refused", not rig.set_view("cockpit") and rig.view == "closeup")
	_check("names keep the historical panel text", rig.view_name() == "close-up" and CameraRig.NAMES.pilot == "pilot")
	cam.queue_free()


func _chase() -> void:
	var chase := ChaseView.new()
	chase.configure(SPAN)
	var target := Vector3(10, 30, -50)
	var placed := chase.update(target, _level(0.0), 0.0, false, _flat)
	var expected := target + Vector3(0, chase.height, chase.distance)
	_check("chase: first frame is settled behind and above (south of a northbound airplane)", (placed.position as Vector3).distance_to(expected) < 1e-4, "%s vs %s" % [placed.position, expected])
	_check("chase: looks at the airplane", (-(placed.basis as Basis).z).dot((target - placed.position).normalized()) > 0.999)
	_check("chase: no roll (world up stays up)", absf((placed.basis as Basis).x.y) < 1e-6)
	var r30 := _straight(30.0, 3.0)
	var r60 := _straight(60.0, 3.0)
	var r144 := _straight(144.0, 3.0)
	_check("chase: straight flight, same camera offset at 30/60/144 fps (≤ 1 cm)", r30.distance_to(r60) < 0.01 and r60.distance_to(r144) < 0.01, "%s %s %s" % [r30, r60, r144])
	_check("chase: straight flight, exactly one boom behind and above (no speed lag)", r60.distance_to(Vector3(0, chase.height, chase.distance)) < 1e-4, str(r60))
	# A 60 m circle at 20 m/s for 12 s at 60 fps: never NaN, never too close or lost, always aimed at the airplane.
	chase.reset()
	var ok := true
	var worst_aim := 1.0
	var radius := 60.0
	var omega := 20.0 / radius
	for i in 721:
		var t := i / 60.0
		var p := Vector3(radius * sin(omega * t), 30.0, -radius * cos(omega * t) + radius)
		var heading := omega * t + PI / 2.0 # tangent: east at t = 0, then turning right
		placed = chase.update(p, _level(heading), 1.0 / 60.0, false, _flat)
		var cam_pos: Vector3 = placed.position
		var d := cam_pos.distance_to(p)
		ok = ok and cam_pos.is_finite() and d > 0.5 * chase.distance and d < 2.5 * chase.distance
		worst_aim = minf(worst_aim, (-(placed.basis as Basis).z).dot((p - cam_pos).normalized()))
	_check("chase: 12 s circle stays finite and within 0.5–2.5 booms", ok)
	_check("chase: circle keeps the airplane near the centre (look-ahead ≤ 10°)", worst_aim > cos(deg_to_rad(10.0)), "%.4f" % worst_aim)
	# Vertical line: the nose points up and the track has no horizontal part; the heading is held.
	chase.reset()
	chase.update(Vector3(0, 30, 0), _level(0.7), 0.0, false, _flat)
	var up_nose := _level(0.7) * Basis(Vector3.RIGHT, PI / 2.0) # pitched up about its own right axis
	var finite := true
	for i in 120:
		placed = chase.update(Vector3(0, 30 + 15.0 * (i + 1) / 60.0, 0), up_nose, 1.0 / 60.0, false, _flat)
		finite = finite and (placed.position as Vector3).is_finite() and (placed.basis as Basis).is_finite()
	var behind := CameraMath.horizontal_dir(Vector3(0, 30, 0) - (placed.position as Vector3))
	_check("chase: vertical climb holds the last heading, no NaN", finite and absf(angle_difference(CameraMath.heading_of(behind), 0.7)) < deg_to_rad(5.0), "%s" % placed.position)
	# Tail slide: moving backwards, the boom stays behind the nose.
	_check("chase: sliding backwards follows the nose", absf(angle_difference(ChaseView.alignment_heading(Vector3(0, -3, 8), _level(0.0), 1.0), 0.0)) < 1e-9)
	_check("chase: slow (taxi) follows the nose", absf(angle_difference(ChaseView.alignment_heading(Vector3(1.0, 0, -0.5), _level(0.0), 0.3), 0.0)) < 1e-9)
	_check("chase: fast track wins over the nose (crab)", absf(angle_difference(ChaseView.alignment_heading(Vector3(5, 0, -20), _level(0.0), 0.0), atan2(5.0, 20.0))) < 1e-9)
	# Terrain: a 10 m hill everywhere keeps the camera 0.6 m above it even for a low airplane.
	chase.reset()
	var hill := func(_x: float, _z: float) -> float: return 10.0
	placed = chase.update(Vector3(0, 10.2, 0), _level(0.0), 0.0, false, hill)
	_check("chase: clearance above terrain", (placed.position as Vector3).y >= 10.6 - 1e-9, str(placed.position))
	var nan_ground := func(_x: float, _z: float) -> float: return NAN
	placed = chase.update(Vector3(0, 10.2, -0.3), _level(0.0), 1.0 / 60.0, false, nan_ground)
	_check("chase: unknown terrain reads as flat, never NaN", (placed.position as Vector3).is_finite())
	# Teleport (restart): no chase across the field.
	chase.reset()
	chase.update(Vector3(0, 30, 0), _level(0.0), 0.0, false, _flat)
	placed = chase.update(Vector3(800, 5, 0), _level(0.0), 1.0 / 60.0, false, _flat)
	_check("chase: a teleport snaps behind the new position", (placed.position as Vector3).distance_to(Vector3(800, 5, 0)) < 1.2 * Vector3(chase.distance, chase.height, 0).length())
	# Paused: nothing moves.
	var before: Vector3 = placed.position
	for i in 30:
		placed = chase.update(Vector3(800, 5, 0), _level(1.0), 1.0 / 60.0, true, _flat)
	_check("chase: frozen while paused", (placed.position as Vector3) == before)


func _orbit() -> void:
	var orbit := OrbitView.new()
	orbit.configure(SPAN)
	var target := Vector3(5, 20, -30)
	var eye := target + Vector3(3, 2, -4)
	orbit.start_from(eye, target)
	var placed := orbit.update(target, _flat)
	_check("orbit: starts exactly where the previous view was", (placed.position as Vector3).distance_to(eye) < 1e-4, "%s vs %s" % [placed.position, eye])
	orbit.rotate(Vector2(0, 10000))
	_check("orbit: elevation clamps below the zenith", orbit.elevation_deg == OrbitView.MAX_ELEVATION_DEG)
	placed = orbit.update(target, _flat)
	_check("orbit: near the zenith the basis stays finite and aimed", (placed.basis as Basis).is_finite() and (-(placed.basis as Basis).z).dot((target - placed.position).normalized()) > 0.999)
	orbit.dolly(1000.0)
	_check("orbit: distance limit", is_equal_approx(orbit.distance, OrbitView.MAX_SPANS * SPAN))
	orbit.reset()
	orbit.rotate(Vector2(0, -10000))
	placed = orbit.update(Vector3(0, 0.2, 0), _flat)
	_check("orbit: low airplane, camera kept above the ground", (placed.position as Vector3).y >= OrbitView.CLEARANCE_M - 1e-9, str(placed.position))
	# Rig: entering orbit from the pilot view keeps the camera where it was.
	var cam := _camera()
	var rig := CameraRig.new(cam, SPAN)
	var airplane := Transform3D(Basis.IDENTITY, Vector3(0, 5, -20)) # seen 9° below the airplane: inside the orbit limits
	rig.update(airplane.origin, airplane, airplane.basis, 1.0 / 60.0, false, _flat)
	var pilot_eye := cam.position
	rig.set_view("orbit")
	rig.update(airplane.origin, airplane, airplane.basis, 1.0 / 60.0, false, _flat)
	_check("rig: pilot → orbit keeps the eye when within reach", cam.position.distance_to(pilot_eye) < 1e-3, "%s vs %s" % [cam.position, pilot_eye])
	var far := Transform3D(Basis.IDENTITY, Vector3(0, 40, -200))
	rig.set_view("pilot")
	rig.update(far.origin, far, far.basis, 1.0 / 60.0, false, _flat)
	pilot_eye = cam.position
	rig.set_view("orbit")
	rig.update(far.origin, far, far.basis, 1.0 / 60.0, false, _flat)
	_check("rig: pilot → orbit from far keeps the direction at the default distance", is_equal_approx(cam.position.distance_to(far.origin), OrbitView.DEFAULT_SPANS * SPAN)
		and (cam.position - far.origin).normalized().dot((pilot_eye - far.origin).normalized()) > 0.999)
	var fresh := CameraRig.new(cam, SPAN)
	fresh.set_view("orbit")
	fresh.update(airplane.origin, airplane, Basis.IDENTITY, 1.0 / 60.0, false, _flat)
	var from_target := cam.position - airplane.origin
	_check("rig: a flight that starts in orbit sees it from behind-left, above", from_target.z > 0.0 and from_target.x < 0.0 and from_target.y > 0.0, str(from_target))
	cam.queue_free()
