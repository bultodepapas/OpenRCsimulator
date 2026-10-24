# CAM-02/05/08/10: the camera rig and its views on synthetic trajectories (docs/plans/camera-views.md).
#   - pilot, close-up and landscape views are exactly what render/pilot_camera.gd produces (no picture change);
#   - a Z toggle or manual zoom never jumps the FOV and settles on the law; Backspace returns to it;
#   - chase: settled pose, frame-rate independence, circle/vertical/tail-slide/terrain/teleport cases;
#   - CAM-24: chase frame-rate independence in a bank and a loop (sub-steps), no slide after entry (state velocity);
#   - CAM-02b: each view's near plane (pilot 0.5 m, chase and close-up 0.25 m, orbit shrinking near the airframe);
#   - CAM-27: after a crash the orbit, chase and close-up look at the wreck; the orbit still turns; pilot untouched;
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
	_pilot_fov_reference()
	_pilot_zoom()
	_cycle()
	_near_planes()
	_chase()
	_chase_smoothness()
	_orbit()
	_wreck_focus()
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


## CAM-23: the pilot view's FOV comes from the 1080 px reference, whatever viewport the camera renders into (the
## headless test viewport is 64 px tall; the former law read that height and gave its 6° floor here). Camera3D.fov is
## 32-bit, hence the tolerance.
func _pilot_fov_reference() -> void:
	var cam := _camera()
	var target := Vector3(0, 40, -250)
	PilotCamera.aim(cam, target, Transform3D(Basis.IDENTITY, target), false, SPAN)
	var expected := PilotCamera.auto_fov(SPAN, cam.position.distance_to(target))
	_check("CAM-23 pilot view: FOV from the reference height, not the viewport (%d px tall)" % int(cam.get_viewport().get_visible_rect().size.y), absf(cam.fov - expected) < 1e-4, "%.4f vs %.4f" % [cam.fov, expected])
	cam.free()


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


func _near_planes() -> void:
	var cam := _camera()
	var rig := CameraRig.new(cam, SPAN)
	var target := Vector3(0, 30, -80)
	var airplane := Transform3D(_level(0.0), target)
	var seen := {}
	for view: String in ["pilot", "chase", "closeup", "orbit"]:
		rig.set_view(view)
		rig.update(target, airplane, _level(0.0), 1.0 / 60.0, false, _flat)
		seen[view] = cam.near
	_check("CAM-02b near planes: pilot 0.5, chase 0.25, close-up 0.25, orbit 0.25 at its default distance",
		is_equal_approx(seen.pilot, 0.5) and is_equal_approx(seen.chase, 0.25) and is_equal_approx(seen.closeup, 0.25)
		and is_equal_approx(seen.orbit, 0.25), str(seen))
	rig.orbit.distance = OrbitView.MIN_SPANS * SPAN
	rig.update(target, airplane, _level(0.0), 1.0 / 60.0, false, _flat)
	_check("CAM-02b orbit at its closest: 5 cm near plane (a wing tip can be ~0.2 m away)", is_equal_approx(cam.near, CameraRig.ORBIT_NEAR_MIN), "%.3f" % cam.near)
	rig.look = Vector2(90.0, 10.0)
	rig.update(target, airplane, _level(0.0), 1.0 / 60.0, false, _flat)
	_check("CAM-02b landscape look views use the pilot's near plane", is_equal_approx(cam.near, 0.5))
	cam.free()


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


## A 60° bank turn at 20 m/s (radius 23.5 m), level, starting north: { pos, basis, vel } at time t.
static func _bank(t: float) -> Dictionary:
	var v := 20.0
	var r := v * v / (9.81 * tan(deg_to_rad(60.0)))
	var th := v / r * t
	var center := Vector3(r, 30.0, 0.0)
	var pos := center + r * Vector3(-cos(th), 0.0, -sin(th))
	var forward := Vector3(sin(th), 0.0, -cos(th))
	var up := (Vector3.UP * cos(deg_to_rad(60.0)) + (center - pos).normalized() * sin(deg_to_rad(60.0))).normalized()
	return { pos = pos, basis = Basis.looking_at(forward, up), vel = forward * v }


## Straight north for 2 s, then a 15 m loop at 20 m/s, then straight again.
static func _loop(t: float) -> Dictionary:
	var v := 20.0
	var r := 15.0
	if t < 2.0:
		return { pos = Vector3(0, 30, -v * t), basis = Basis.IDENTITY, vel = Vector3(0, 0, -v) }
	var th := minf(v * (t - 2.0) / r, TAU)
	var center := Vector3(0, 30 + r, -2.0 * v)
	var pos := center + r * Vector3(0, -cos(th), -sin(th))
	var forward := Vector3(0, sin(th), -cos(th))
	if th >= TAU:
		pos += Vector3(0, 0, -v * (t - 2.0 - TAU * r / v))
	return { pos = pos, basis = Basis.looking_at(forward, (center - pos).normalized() if th < TAU else Vector3.UP), vel = forward * v }


## The chase camera's position at time `until` for a trajectory sampled at fps; measured velocity or estimated.
func _chase_at(trajectory: Callable, fps: float, until: float, measured: bool) -> Vector3:
	var chase := ChaseView.new()
	chase.configure(SPAN)
	var dt := 1.0 / fps
	var placed := {}
	for i in roundi(until * fps) + 1:
		var s: Dictionary = trajectory.call(i * dt)
		placed = chase.update(s.pos, s.basis, dt if i > 0 else 0.0, false, _flat, s.vel if measured else Vector3.INF)
	return placed.position


func _chase_smoothness() -> void:
	for measured: bool in [true, false]:
		var label := "state velocity" if measured else "estimated velocity"
		var bank := _chase_at(_bank, 30.0, 6.0, measured).distance_to(_chase_at(_bank, 144.0, 6.0, measured))
		_check("CAM-24 chase (%s): 60° bank, camera at 30 and 144 fps within 1 cm" % label, bank < 0.01, "%.4f m" % bank)
		var loop := _chase_at(_loop, 30.0, 7.0, measured).distance_to(_chase_at(_loop, 144.0, 7.0, measured))
		_check("CAM-24 chase (%s): loop, camera at 30 and 144 fps within 2 cm" % label, loop < 0.02, "%.4f m" % loop)
	# Entry: with the state velocity the look-ahead is settled on the first frame, so the airplane does not slide.
	var chase := ChaseView.new()
	chase.configure(SPAN)
	var first := NAN
	var worst := 0.0
	var outside := 0
	for i in 60:
		var s := _loop(i / 60.0)
		var placed := chase.update(s.pos, s.basis, 1.0 / 60.0 if i > 0 else 0.0, false, _flat, s.vel)
		var b: Basis = placed.basis
		var angle := rad_to_deg((-b.z).angle_to((s.pos as Vector3) - (placed.position as Vector3)))
		if is_nan(first):
			first = angle
		worst = maxf(worst, absf(angle - first))
	_check("CAM-24 chase: no slide after entry with the state velocity (≤ 0.01°)", worst < 0.01, "%.4f°" % worst)
	chase.reset()
	for i in 600:
		var s := _loop(i / 60.0)
		var placed := chase.update(s.pos, s.basis, 1.0 / 60.0 if i > 0 else 0.0, false, _flat, s.vel)
		var local: Vector3 = (placed.basis as Basis).inverse() * ((s.pos as Vector3) - (placed.position as Vector3))
		if absf(rad_to_deg(atan2(local.y, -local.z))) > ChaseView.FOV_DEG * 0.5 or local.z > 0.0:
			outside += 1
	_check("CAM-24 chase: the airplane stays in frame through a loop", outside == 0, "%d frames outside" % outside)
	# A hard touchdown: 15 → 5 m/s within two ticks. The state velocity is damped like the estimate, so the aim moves
	# 0.33° per 60 fps frame at most (0.96° with the estimate); an unfiltered velocity gave 1.8° (CAM-24 review).
	chase.reset()
	var worst_turn := 0.0
	var previous_forward := Vector3.ZERO
	var x := 0.0
	for i in 120:
		var t := i / 60.0
		var speed := 15.0 if t < 1.0 else (5.0 if t > 1.0 + 2.0 / 240.0 else 10.0)
		x += speed / 60.0
		var placed := chase.update(Vector3(0, 0.3, -x), _level(0.0), 1.0 / 60.0 if i > 0 else 0.0, false, _flat, Vector3(0, 0, -speed))
		var forward := -(placed.basis as Basis).z
		if previous_forward != Vector3.ZERO:
			worst_turn = maxf(worst_turn, rad_to_deg(previous_forward.angle_to(forward)))
		previous_forward = forward
	_check("CAM-24 chase: a hard touchdown turns the aim ≤ 0.6° per 60 fps frame", worst_turn <= 0.6, "%.2f°" % worst_turn)
	# A hovering pirouette (no track, nose turning 180°/s): the nose is interpolated inside each frame, so 30 and 144 fps
	# agree; stepping every sub-step with the frame-end attitude would not.
	var at := {}
	for fps: float in [30.0, 144.0]:
		var spin := ChaseView.new()
		spin.configure(SPAN)
		var placed := {}
		for i in roundi(2.0 * fps) + 1:
			placed = spin.update(Vector3(0, 3, 0), _level(PI * i / fps), 1.0 / fps if i > 0 else 0.0, false, _flat, Vector3.ZERO)
		at[fps] = placed.position
	var spin_gap: float = (at[30.0] as Vector3).distance_to(at[144.0])
	_check("CAM-24 chase: hovering pirouette, 30 and 144 fps within 1 cm", spin_gap < 0.01, "%.4f m" % spin_gap)


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


static func _aims_at(cam: Camera3D, point: Vector3) -> bool:
	return (-cam.basis.z).dot((point - cam.position).normalized()) > 0.9999


func _wreck_focus() -> void:
	var cam := _camera()
	var rig := CameraRig.new(cam, SPAN)
	var impact := Vector3(40, 0.3, -50)
	var wreck := Vector3(28, 0.4, -43) # the core slid 14 m from the impact
	var airplane := Transform3D(_level(0.0), impact)
	var hill := func(_x: float, _z: float) -> float: return 2.0
	rig.set_view("orbit")
	rig.update(impact, airplane, _level(0.0), 1.0 / 60.0, true, _flat)
	rig.focus(wreck, _flat)
	_check("CAM-27 orbit: looks at the wreck, not the impact", _aims_at(cam, wreck))
	_check("CAM-27 orbit: at the orbit distance from the wreck", absf(cam.position.distance_to(wreck) - rig.orbit.distance) < 1e-3, "%.3f vs %.3f" % [cam.position.distance_to(wreck), rig.orbit.distance])
	var before := cam.position
	rig.drag(Vector2(400, 0))
	rig.update(impact, airplane, _level(0.0), 1.0 / 60.0, true, _flat)
	rig.focus(wreck, _flat)
	_check("CAM-27 orbit: a drag still turns the camera around the wreck", cam.position.distance_to(before) > 0.5 and _aims_at(cam, wreck))
	rig.set_view("chase")
	rig.update(impact, airplane, _level(0.0), 1.0 / 60.0, true, _flat)
	var held := cam.position
	rig.focus(wreck, _flat)
	_check("CAM-27 chase: holds its position and turns to the wreck", cam.position == held and _aims_at(cam, wreck))
	rig.set_view("orbit")
	rig.update(impact, airplane, _level(0.0), 1.0 / 60.0, true, _flat)
	rig.focus(wreck, _flat)
	_check("CAM-27 orbit entered after the slide starts where the chase was (no jump)", cam.position.distance_to(held) < 1e-3 and _aims_at(cam, wreck), "%.3f m" % cam.position.distance_to(held))
	rig.set_view("closeup")
	rig.update(impact, airplane, _level(0.0), 1.0 / 60.0, true, hill)
	rig.focus(wreck, hill)
	_check("CAM-27 close-up: keeps its offset from the wreck, above the terrain", cam.position.distance_to(wreck + CameraRig.WRECK_CLOSEUP_OFFSET) < 1e-4 and cam.position.y >= 2.6 and _aims_at(cam, wreck) and cam.fov == CameraRig.WRECK_CLOSEUP_FOV)
	var high_hill := func(_x: float, _z: float) -> float: return 10.0
	rig.focus(wreck, high_hill)
	_check("CAM-27 close-up: lifted clear of terrain higher than its offset", cam.position.y >= 10.6 - 1e-6 and _aims_at(cam, wreck))
	rig.set_view("pilot")
	rig.update(impact, airplane, _level(0.0), 1.0 / 60.0, true, _flat)
	var pilot := cam.transform
	rig.focus(wreck, _flat)
	_check("CAM-27 pilot: focus leaves the pilot view to the crash director", cam.transform == pilot)
	cam.free()
