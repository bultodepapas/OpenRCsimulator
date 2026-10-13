# CAM-10: orbit view (docs/plans/camera-views.md §5.5). A camera on a sphere around the airplane's CG, turned with
# the right mouse button and moved in or out with the wheel or +/−; world up, no roll. It works while the flight is
# paused. It starts from wherever the previous view was, so switching into it never jumps. Read-only.
extends RefCounted

const CameraMath := preload("res://render/camera/camera_math.gd")

const FOV_DEG := 45.0
const DEGREES_PER_PIXEL := 0.3
const MIN_ELEVATION_DEG := -20.0
const MAX_ELEVATION_DEG := 85.0
## Distance limits as multiples of the span; the default framing is about two spans away.
const MIN_SPANS := 0.6
const MAX_SPANS := 20.0
const DEFAULT_SPANS := 2.0
const CLEARANCE_M := 0.3

var azimuth_deg := 0.0 # where the camera sits, seen from the CG: 0 = north of it, 90 = east
var elevation_deg := 20.0
var distance := 3.0
var _span := 1.5


func configure(span: float) -> void:
	_span = maxf(span, 0.3)
	distance = DEFAULT_SPANS * _span


## Starts the orbit in the direction of an existing camera (continuity when switching views); from farther than
## the orbit reaches (the pilot station) it keeps the direction at the default distance.
func start_from(eye: Vector3, target: Vector3) -> void:
	var offset := eye - target
	if offset.length() < 1e-3:
		return
	distance = offset.length() if offset.length() <= MAX_SPANS * _span else DEFAULT_SPANS * _span
	distance = maxf(distance, MIN_SPANS * _span)
	elevation_deg = clampf(rad_to_deg(asin(clampf(offset.y / offset.length(), -1.0, 1.0))), MIN_ELEVATION_DEG, MAX_ELEVATION_DEG)
	var flat := CameraMath.horizontal_dir(offset)
	if flat != Vector3.ZERO:
		azimuth_deg = rad_to_deg(CameraMath.heading_of(flat))


## Starts behind and to the left of the airplane's nose, slightly above (a flight that begins in this view).
func start_behind(body: Basis) -> void:
	reset()
	var nose := CameraMath.horizontal_dir(-body.z, 0.05)
	azimuth_deg = wrapf(rad_to_deg(CameraMath.heading_of(nose)) + 180.0 + 35.0 if nose != Vector3.ZERO else 0.0, -180.0, 180.0)


func rotate(pixels: Vector2) -> void:
	azimuth_deg = wrapf(azimuth_deg - pixels.x * DEGREES_PER_PIXEL, -180.0, 180.0)
	elevation_deg = clampf(elevation_deg + pixels.y * DEGREES_PER_PIXEL, MIN_ELEVATION_DEG, MAX_ELEVATION_DEG)


## factor < 1 moves in, > 1 moves out.
func dolly(factor: float) -> void:
	distance = clampf(distance * factor, MIN_SPANS * _span, MAX_SPANS * _span)


func reset() -> void:
	azimuth_deg = 0.0
	elevation_deg = 20.0
	distance = DEFAULT_SPANS * _span


## ground_y: Callable(x, z) → terrain height (render y). Returns { position, basis, fov }.
func update(target: Vector3, ground_y: Callable) -> Dictionary:
	var el := deg_to_rad(elevation_deg)
	var dir := CameraMath.dir_of_heading(deg_to_rad(azimuth_deg)) * cos(el) + Vector3.UP * sin(el)
	var eye := target + dir * distance
	var floor_y := 0.0
	if ground_y.is_valid():
		var y: float = ground_y.call(eye.x, eye.z)
		floor_y = y if is_finite(y) else 0.0
	eye.y = maxf(eye.y, floor_y + CLEARANCE_M)
	return { position = eye, basis = CameraMath.look_basis(eye, target), fov = FOV_DEG }
