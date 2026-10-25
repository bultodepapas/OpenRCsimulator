# CAM-02: the flight's camera rig (docs/plans/camera-views.md §4). One Camera3D, one active view:
#   pilot    the RC pilot's eyes at the field's station (render/pilot_camera.gd), auto-zoom (Z) and manual zoom;
#   chase    horizon-locked follow behind the flight path (chase_view.gd);
#   orbit    a sphere around the airplane, right mouse drag and wheel (orbit_view.gd);
#   closeup  the rigid inspection offset (Spec.INSPECT_OFFSET), unchanged.
# Presentation only: it reads the interpolated render pose main.gd draws the airplane with and never writes the
# session. Pilot and close-up delegate to PilotCamera, so their pictures are unchanged when no zoom is applied.
extends RefCounted

const Spec := preload("res://spec.gd")
const PilotCamera := preload("res://render/pilot_camera.gd")
const CameraMath := preload("res://render/camera/camera_math.gd")
const ChaseView := preload("res://render/camera/chase_view.gd")
const OrbitView := preload("res://render/camera/orbit_view.gd")
const FlybyView := preload("res://render/camera/flyby_view.gd")

## The C cycle, in order. Number keys select pilot (1), chase (2), fly-by (4) and orbit (5); 3, 6, 7 are reserved
## (plan §4.4).
const VIEWS := ["pilot", "chase", "flyby", "orbit", "closeup"]
## Names the input panel, captures and evidence show (the historical "pilot" and "close-up" are kept).
const NAMES := { pilot = "pilot", chase = "chase", flyby = "fly-by", orbit = "orbit", closeup = "close-up" }
## One +/− step or wheel notch: a quarter of a doubling.
const ZOOM_STEP := 1.189207115002721 # 2^(1/4)
## Pilot manual zoom limits (multiplies tan(fov/2): < 1 narrows) and chase boom limits.
const PILOT_ZOOM_MIN := 0.125
const PILOT_ZOOM_MAX := 2.0
const CHASE_ZOOM_MIN := 0.4
const CHASE_ZOOM_MAX := 4.0
## A changed zoom law or factor reaches its new FOV smoothly (half-life, s); a moving airplane is tracked without lag.
const FOV_JUMP_HALF_LIFE := 0.15
const PILOT_FOV_MIN := 1.0
const PILOT_FOV_MAX := 120.0
## CAM-02b: near plane per view (m). Compatibility's 24-bit depth step grows as z²/near (0.6 m at 1 km with 0.1 m),
## so each view takes the largest near plane its closest geometry allows. Pilot: the nearest surface is the station
## barrier, 1.11 m from the eye (CAM-02b probe), still 0.52 m deep at the widest manual zoom. Chase and close-up stay
## ≥ 1 m from the airframe. The orbit can come within centimetres of a wing tip, so its near plane shrinks with distance.
const NEAR_M := { pilot = 0.5, chase = 0.25, flyby = 0.5, closeup = 0.25 }
const ORBIT_NEAR_MIN := 0.05
const ORBIT_NEAR_MAX := 0.25
## CAM-06b: the horizon tilt keeps the aircraft within this share of the half-frame from the centre and lifts the
## horizon this share of the half-frame above the bottom edge; it eases in or out with this half-life (s).
const HORIZON_KEEP := 0.75
const HORIZON_MARGIN := 0.3
const HORIZON_EASE_HALF_LIFE := 0.25
## CAM-28: the most the picture may turn about the view axis (°/s); an exact pass beside the zenith turned 2388°/s.
const OVERHEAD_ROLL_RATE := 180.0
## CAM-27: the close-up's view of a wreck (the crash director's former fixed framing, now kept on the wreck itself).
const WRECK_CLOSEUP_OFFSET := Vector3(5.0, 3.2, 6.0)
const WRECK_CLOSEUP_FOV := 58.0
const WRECK_CLEARANCE_M := 0.6
## The held chase narrows its FOV so a wreck that slid away still spans this share of the frame height, like an
## operator zooming in; never narrower than WRECK_CHASE_MIN_FOV, never wider than the chase's own FOV.
const WRECK_FRAME_SHARE := 0.25
const WRECK_CHASE_MIN_FOV := 12.0

var camera: Camera3D
var view := "pilot"
var auto_zoom := true
## Pilot view: multiplies tan(fov/2) on top of the auto-zoom law (1 = the law's own FOV).
var pilot_zoom := 1.0
## CAM-26: the vehicle's own pilot zoom, which Backspace restores (the helicopter needs more screen than an airplane).
var default_pilot_zoom := 1.0
## CAM-17: the pilot view's widest vertical FOV (deg), the player's setting; the auto-zoom narrows from it.
var base_fov := float(Spec.CAMERA.fov_deg)
## CAM-06/06b/28 pilot aids, all off by default until the pilot picks them (CAM-22): the auto-zoom law
## (PilotCamera.ZOOM_LAWS), a tilt toward the horizon that keeps the aircraft in frame, and a cap on how fast the
## picture may roll when the aircraft passes overhead.
var zoom_law := "constant"
var horizon_bias := false
var overhead_smoothing := false
## CAM-18: magnifier inset mode ("off", "auto", "on"); the route's Magnifier node draws it.
var magnifier := "off"
var _bias_amount := 0.0 # 0 → 1 as the horizon tilt eases in or out
var _screen_up := Vector3.ZERO # the overhead-smoothed screen up (ZERO: follow the exact one)
## Landscape review (L0): (azimuth, elevation) in degrees from the pilot's eye; NAN follows the airplane.
var look := Vector2(NAN, NAN)
var look_height := 1.7
var chase := ChaseView.new()
var orbit := OrbitView.new()
var flyby := FlybyView.new()
## Direction toward the sun (render), set by the route each frame; the fly-by stands with the sun behind it.
var light_direction := Vector3.ZERO
var _span := 1.5
var _fov_offset := 0.0 # ln(tan) difference still being blended out after a zoom change
var _absorb_from := NAN # the FOV on screen just before a zoom change
var _orbit_primed := false
## The eye the orbit started from this frame (INF otherwise): focus() re-anchors that start on the wreck (CAM-27).
var _orbit_entry_eye := Vector3.INF
var _placed := false # the camera has been placed by a view at least once (orbit can start from it)


func _init(rig_camera: Camera3D, span: float) -> void:
	camera = rig_camera
	set_span(span)


func set_span(span: float) -> void:
	_span = span
	chase.configure(span)
	orbit.configure(span)
	flyby.configure(span)


static func is_view(id: String) -> bool:
	return id in VIEWS


func view_name() -> String:
	return str(NAMES.get(view, view))


## Selects a view. Chase restarts settled behind the airplane; orbit starts from the camera's current position.
func set_view(id: String) -> bool:
	if not is_view(id):
		return false
	if id == view:
		return true
	view = id
	_screen_up = Vector3.ZERO
	if id == "chase":
		chase.reset()
	elif id == "flyby":
		flyby.reset()
	elif id == "orbit":
		_orbit_primed = false
	_fov_offset = 0.0
	_absorb_from = NAN
	return true


func cycle(step: int) -> void:
	set_view(VIEWS[posmod(VIEWS.find(view) + step, VIEWS.size())])


## CAM-06: another auto-zoom law, reached smoothly like a zoom change.
func set_zoom_law(law: String) -> void:
	if law == zoom_law or law not in PilotCamera.ZOOM_LAWS:
		return
	_mark_fov_jump()
	zoom_law = law


## CAM-17: a new widest pilot FOV, reached smoothly like a zoom change.
func set_base_fov(fov_deg: float) -> void:
	if is_equal_approx(fov_deg, base_fov):
		return
	_mark_fov_jump()
	base_fov = fov_deg


func toggle_auto_zoom() -> void:
	_mark_fov_jump()
	auto_zoom = not auto_zoom


## steps > 0 zooms in (pilot: narrower FOV; chase/orbit: closer), < 0 out.
func zoom(steps: float) -> void:
	var factor := pow(ZOOM_STEP, -steps)
	match view:
		"pilot":
			_mark_fov_jump()
			pilot_zoom = clampf(pilot_zoom * factor, PILOT_ZOOM_MIN, PILOT_ZOOM_MAX)
		"chase":
			chase.zoom = clampf(chase.zoom * factor, CHASE_ZOOM_MIN, CHASE_ZOOM_MAX)
		"orbit":
			orbit.dolly(factor)
		"flyby":
			flyby.zoom = clampf(flyby.zoom / factor, 0.25, 4.0)


## Backspace: the current view's zoom and offsets back to their defaults.
func reset_view() -> void:
	match view:
		"pilot":
			if pilot_zoom != default_pilot_zoom:
				_mark_fov_jump()
			pilot_zoom = default_pilot_zoom
		"chase":
			chase.zoom = 1.0
		"orbit":
			orbit.reset()
		"flyby":
			flyby.zoom = 1.0


## CAM-29: while the right button turns the orbit the cursor is held (hidden, no window edge to run into); it is
## released with the button. Routes call release_cursor_if_up() every frame, because a menu may take the release event.
static func hold_cursor(held: bool) -> void:
	var mode := Input.MOUSE_MODE_CAPTURED if held else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode


static func release_cursor_if_up() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Right-button drag (relative pixels). Only the orbit view turns today.
func drag(relative: Vector2) -> void:
	if view == "orbit":
		orbit.rotate(relative)


## A restarted flight: views with memory start settled again.
func reset() -> void:
	chase.reset()
	flyby.reset()
	_screen_up = Vector3.ZERO
	_fov_offset = 0.0
	_absorb_from = NAN


## Places the camera for this frame. target: the airplane's CG (render); airplane: its root transform (close-up
## offset); dt: frame time (s); paused: the simulation is frozen; ground_y: Callable(x, z) → terrain height;
## velocity: the CG velocity (render, m/s) from the simulation state, INF when unknown (views then estimate it).
## Camera consumers (audio listener, lake reflection, sun glare) must run after this call, and after focus() during a
## crash aftermath, in the same frame.
func update(target: Vector3, airplane: Transform3D, body: Basis, dt: float, paused: bool, ground_y: Callable,
		velocity := Vector3.INF) -> void:
	# SUN-04: the pilot's eyes see the sun as an eye (veil, afterimage); the other views are camera lenses (flares).
	camera.set_meta(&"openrc_optics", "eye" if view == "pilot" or not is_nan(look.x) else "lens")
	_orbit_entry_eye = Vector3.INF
	camera.near = near_plane()
	if not is_nan(look.x):
		PilotCamera.look(camera, look.x, look.y, look_height)
		return
	match view:
		"pilot":
			PilotCamera.aim(camera, target, airplane, false, _span if auto_zoom and zoom_law == "constant" else 0.0, base_fov)
			if auto_zoom and zoom_law != "constant":
				camera.fov = PilotCamera.law_fov(zoom_law, _span, camera.position.distance_to(target), base_fov)
			_apply_pilot_zoom(dt)
			_bias_amount = CameraMath.damp(_bias_amount, 1.0 if horizon_bias else 0.0, dt, HORIZON_EASE_HALF_LIFE)
			if _bias_amount > 1e-4:
				_tilt_to_horizon(target)
			_smooth_overhead(dt)
		"closeup":
			PilotCamera.aim(camera, target, airplane, true)
		"chase":
			_apply(chase.update(target, body, dt, paused, ground_y, velocity))
		"flyby":
			_apply(flyby.update(target, body, velocity, dt, paused, ground_y, light_direction))
		"orbit":
			if not _orbit_primed:
				if _placed:
					_orbit_entry_eye = camera.position
					orbit.start_from(camera.position, target)
				else:
					orbit.start_behind(body)
				_orbit_primed = true
			_apply(orbit.update(target, ground_y, dt))
	_placed = true


## CAM-27: a crash aftermath, called after update() in the same frame. Non-pilot views look at `point` (the wreck's
## core from the crash director) instead of a fixed spot near the impact: the orbit turns around it and stays under
## the player's control, the chase holds its (paused) position and turns to it, and the close-up keeps its offset from
## it above the terrain. The held chase narrows its FOV as the wreck slides away. The pilot view keeps the director's
## rule (main.gd).
func focus(point: Vector3, ground_y: Callable) -> void:
	if not is_nan(look.x):
		return
	match view:
		"orbit":
			if _orbit_entry_eye.is_finite():
				orbit.start_from(_orbit_entry_eye, point) # entered this frame: start where the last view was, around the wreck
			_apply(orbit.update(point, ground_y, 0.0)) # eased once this frame already, in update()
		"chase", "flyby":
			camera.basis = CameraMath.look_basis(camera.position, point)
			var away := maxf(camera.position.distance_to(point), 0.1)
			camera.fov = clampf(rad_to_deg(2.0 * atan(_span / (2.0 * away * WRECK_FRAME_SHARE))), WRECK_CHASE_MIN_FOV,
				ChaseView.FOV_DEG)
		"closeup":
			var eye := point + WRECK_CLOSEUP_OFFSET
			if ground_y.is_valid():
				var y: float = ground_y.call(eye.x, eye.z)
				eye.y = maxf(eye.y, (y if is_finite(y) else 0.0) + WRECK_CLEARANCE_M)
			camera.transform = Transform3D(CameraMath.look_basis(eye, point), eye)
			camera.fov = WRECK_CLOSEUP_FOV


## The current view's near plane (m); the landscape look views stand at the pilot's eye.
func near_plane() -> float:
	if view == "orbit" and is_nan(look.x):
		# Half the gap between the camera and a sphere of 0.7 span around the CG: 0.25 m at the default two spans.
		var closest := minf(orbit.distance, orbit.shown_distance()) # easing in or out, the nearer of the two
		return clampf(0.5 * (closest - 0.7 * _span), ORBIT_NEAR_MIN, ORBIT_NEAR_MAX)
	return float(NEAR_M.get(view if is_nan(look.x) else "pilot", NEAR_M.pilot))


func evidence() -> Dictionary:
	return { view = view, auto_zoom = auto_zoom, pilot_zoom = pilot_zoom, chase_zoom = chase.zoom,
		orbit = [orbit.azimuth_deg, orbit.elevation_deg, orbit.distance] }


func _apply(placed: Dictionary) -> void:
	camera.transform = Transform3D(placed.basis, placed.position)
	camera.fov = placed.fov


## The law's FOV (set by PilotCamera.aim) times the manual factor, with any recent jump blended out in ln(tan)
## space. With no factor and no pending jump the law's FOV is left exactly as PilotCamera computed it.
func _apply_pilot_zoom(dt: float) -> void:
	var law := camera.fov
	var wanted := law if pilot_zoom == 1.0 else CameraMath.zoomed_fov(law, pilot_zoom)
	if not is_nan(_absorb_from):
		_fov_offset = CameraMath.log_tan(_absorb_from) - CameraMath.log_tan(wanted)
		_absorb_from = NAN
	else:
		_fov_offset *= 1.0 - CameraMath.damp_factor(dt, FOV_JUMP_HALF_LIFE)
		if absf(_fov_offset) < 1e-4:
			_fov_offset = 0.0
	if _fov_offset != 0.0:
		wanted = CameraMath.from_log_tan(CameraMath.log_tan(wanted) + _fov_offset)
	if wanted != law:
		camera.fov = clampf(wanted, PILOT_FOV_MIN, PILOT_FOV_MAX)


## CAM-06b: tilt the pilot's look down toward the horizon as far as keeps the aircraft within HORIZON_KEEP of the
## half-frame, so the ground and horizon show under a high aircraft; an aircraft already low is looked at directly.
## Only the elevation changes: the azimuth, eye and FOV stay, and the tilt eases in and out (_bias_amount).
func _tilt_to_horizon(target: Vector3) -> void:
	var to_target := target - camera.global_position
	var flat := Vector2(to_target.x, to_target.z).length()
	if flat < 1e-3 or to_target.y <= 0.0:
		return # overhead or below the eye: nothing to gain
	var elevation := atan2(to_target.y, flat)
	var half := deg_to_rad(camera.fov) * 0.5
	var biased := minf(elevation, maxf(elevation - HORIZON_KEEP * half, (1.0 - HORIZON_MARGIN) * half))
	var aim := lerpf(elevation, biased, _bias_amount)
	var heading := atan2(to_target.x, -to_target.z)
	var forward := Vector3(sin(heading) * cos(aim), sin(aim), -cos(heading) * cos(aim))
	camera.basis = Basis.looking_at(forward, Vector3.UP)


## CAM-28: with overhead_smoothing the screen-up direction turns at most OVERHEAD_ROLL_RATE; the gaze stays exact,
## so the aircraft keeps its place while the horizon catches up. Otherwise the smoothed up just follows.
func _smooth_overhead(dt: float) -> void:
	var forward := -camera.basis.z
	var exact := camera.basis.y
	var up := _screen_up - forward * forward.dot(_screen_up)
	if not overhead_smoothing or _screen_up == Vector3.ZERO or up.length() < 1e-6:
		_screen_up = exact
		return
	up = up.normalized()
	var step := deg_to_rad(OVERHEAD_ROLL_RATE) * maxf(dt, 0.0)
	var angle := up.angle_to(exact)
	if angle > step:
		var axis := up.cross(exact)
		up = up.rotated(axis.normalized() if axis.length() > 1e-9 else forward, step)
	else:
		up = exact
	_screen_up = up
	camera.basis = Basis.looking_at(forward, up)


func _mark_fov_jump() -> void:
	if view == "pilot" and camera != null:
		_absorb_from = camera.fov
