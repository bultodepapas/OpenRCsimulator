# CAM-02: the flight's camera rig (docs/plans/camera-views.md §4). One Camera3D, one active view:
#   pilot    the RC pilot's eyes at the field's station (render/pilot_camera.gd), auto-zoom (Z) and manual zoom;
#   chase    horizon-locked follow behind the flight path (chase_view.gd);
#   orbit    a sphere around the airplane, right mouse drag and wheel (orbit_view.gd);
#   closeup  the rigid inspection offset (Spec.INSPECT_OFFSET), unchanged.
# Presentation only: it reads the interpolated render pose main.gd draws the airplane with and never writes the
# session. Pilot and close-up delegate to PilotCamera, so their pictures are unchanged when no zoom is applied.
extends RefCounted

const PilotCamera := preload("res://render/pilot_camera.gd")
const CameraMath := preload("res://render/camera/camera_math.gd")
const ChaseView := preload("res://render/camera/chase_view.gd")
const OrbitView := preload("res://render/camera/orbit_view.gd")

## The C cycle, in order. Number keys select pilot (1), chase (2) and orbit (5); 3, 4, 6, 7 are reserved (plan §4.4).
const VIEWS := ["pilot", "chase", "orbit", "closeup"]
## Names the input panel, captures and evidence show (the historical "pilot" and "close-up" are kept).
const NAMES := { pilot = "pilot", chase = "chase", orbit = "orbit", closeup = "close-up" }
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

var camera: Camera3D
var view := "pilot"
var auto_zoom := true
## Pilot view: multiplies tan(fov/2) on top of the auto-zoom law (1 = the law's own FOV).
var pilot_zoom := 1.0
## Landscape review (L0): (azimuth, elevation) in degrees from the pilot's eye; NAN follows the airplane.
var look := Vector2(NAN, NAN)
var look_height := 1.7
var chase := ChaseView.new()
var orbit := OrbitView.new()
var _span := 1.5
var _fov_offset := 0.0 # ln(tan) difference still being blended out after a zoom change
var _absorb_from := NAN # the FOV on screen just before a zoom change
var _orbit_primed := false


func _init(rig_camera: Camera3D, span: float) -> void:
	camera = rig_camera
	set_span(span)


func set_span(span: float) -> void:
	_span = span
	chase.configure(span)
	orbit.configure(span)


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
	if id == "chase":
		chase.reset()
	elif id == "orbit":
		_orbit_primed = false
	_fov_offset = 0.0
	_absorb_from = NAN
	return true


func cycle(step: int) -> void:
	set_view(VIEWS[posmod(VIEWS.find(view) + step, VIEWS.size())])


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


## Backspace: the current view's zoom and offsets back to their defaults.
func reset_view() -> void:
	match view:
		"pilot":
			if pilot_zoom != 1.0:
				_mark_fov_jump()
			pilot_zoom = 1.0
		"chase":
			chase.zoom = 1.0
		"orbit":
			orbit.reset()


## Right-button drag (relative pixels). Only the orbit view turns today.
func drag(relative: Vector2) -> void:
	if view == "orbit":
		orbit.rotate(relative)


## A restarted flight: views with memory start settled again.
func reset() -> void:
	chase.reset()
	_fov_offset = 0.0
	_absorb_from = NAN


## Places the camera for this frame. target: the airplane's CG (render); airplane: its root transform (close-up
## offset); dt: frame time (s); paused: the simulation is frozen; ground_y: Callable(x, z) → terrain height.
func update(target: Vector3, airplane: Transform3D, body: Basis, dt: float, paused: bool, ground_y: Callable) -> void:
	if not is_nan(look.x):
		PilotCamera.look(camera, look.x, look.y, look_height)
		return
	match view:
		"pilot":
			PilotCamera.aim(camera, target, airplane, false, _span if auto_zoom else 0.0)
			_apply_pilot_zoom(dt)
		"closeup":
			PilotCamera.aim(camera, target, airplane, true)
		"chase":
			_apply(chase.update(target, body, dt, paused, ground_y))
		"orbit":
			if not _orbit_primed:
				orbit.start_from(camera.position, target)
				_orbit_primed = true
			_apply(orbit.update(target, ground_y))


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


func _mark_fov_jump() -> void:
	if view == "pilot" and camera != null:
		_absorb_from = camera.fov
