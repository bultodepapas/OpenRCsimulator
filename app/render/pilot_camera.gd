# Pilot camera: the RC pilot's eyes at a fixed spot on the field, always looking at the airplane; or (inspect)
# a close-up fixed to the airplane, to check geometry. Auto-zoom (D7) keeps a distant airplane readable.
extends RefCounted

const Spec := preload("res://spec.gd")
const Frames := preload("res://render/frames.gd")


static func create(parent: Node, pilot: Dictionary = {}) -> Camera3D:
	var camera := Camera3D.new()
	# Metadata belongs to this camera: independent scenes never share a mutable pilot position.
	var station: Array = [pilot.get("north", 0.0), pilot.get("east", 0.0), pilot.get("down", 0.0)]
	camera.set_meta("pilot_station", station)
	camera.set_meta("pilot_eye_height", pilot.get("eye_height", Spec.CAMERA.eye_height))
	camera.fov = Spec.CAMERA.fov_deg
	camera.near = Spec.CAMERA.near
	camera.far = Spec.CAMERA.far
	parent.add_child(camera)
	camera.current = true
	return camera


## Projected size (pixels of the viewport height) of a length seen face-on at a distance, vertical FOV in degrees.
static func projected_px(length: float, distance: float, fov_deg: float, viewport_h: float) -> float:
	return length / (2.0 * maxf(distance, 1e-6) * tan(deg_to_rad(fov_deg) * 0.5)) * viewport_h


## Vertical FOV (degrees) that shows `span` at `target_px` of a `reference_h`-tall view at this distance (the same
## share of any viewport's height): never wider than the base FOV, never narrower than the minimum.
static func auto_fov(span: float, distance: float, target_px := float(Spec.AUTO_ZOOM.target_px),
		reference_h := float(Spec.AUTO_ZOOM.reference_height_px), base_fov := float(Spec.CAMERA.fov_deg),
		min_fov := float(Spec.AUTO_ZOOM.min_fov_deg)) -> float:
	var fov := rad_to_deg(2.0 * atan(span * reference_h / (2.0 * maxf(distance, 1e-6) * target_px)))
	return clampf(fov, min_fov, base_fov)


## CAM-06: the auto-zoom law family (plan §5.1, X-PERC-2). "constant" keeps the span at target_px of the reference
## height (today's law, which removes looming between ~58 and ~523 m at 1080p); "partial" lets the span shrink as
## d^-PARTIAL_K beyond the distance where the constant law starts, so approach and retreat still read from size;
## "gentle" is CRRCSim's form, fov = atan(tan(base)·d0 / (d0 + (d − d0)·a)), which reproduces its 35° → 26° → 20°.
const ZOOM_LAWS: Array[String] = ["constant", "partial", "gentle"]
const PARTIAL_K := 0.5
const GENTLE_D0_M := 21.5
const GENTLE_SLOPE := 0.05


## Vertical FOV (degrees) of an auto-zoom law for a span at a distance, never wider than base_fov or narrower than
## the minimum.
static func law_fov(law: String, span: float, distance: float, base_fov := float(Spec.CAMERA.fov_deg)) -> float:
	var d := maxf(distance, 1e-6)
	var min_fov := float(Spec.AUTO_ZOOM.min_fov_deg)
	match law:
		"partial":
			var target := float(Spec.AUTO_ZOOM.target_px)
			var height := float(Spec.AUTO_ZOOM.reference_height_px)
			var start := span * height / (2.0 * target * tan(deg_to_rad(base_fov) * 0.5))
			if d <= start:
				return base_fov
			var px := target * pow(start / d, PARTIAL_K)
			return clampf(rad_to_deg(2.0 * atan(span * height / (2.0 * d * px))), min_fov, base_fov)
		"gentle":
			if d <= GENTLE_D0_M:
				return base_fov
			var fov := rad_to_deg(atan(tan(deg_to_rad(base_fov)) * GENTLE_D0_M / (GENTLE_D0_M + (d - GENTLE_D0_M) * GENTLE_SLOPE)))
			return clampf(fov, min_fov, base_fov)
	return auto_fov(span, d, float(Spec.AUTO_ZOOM.target_px), float(Spec.AUTO_ZOOM.reference_height_px), base_fov, min_fov)


## Landscape review views (L0): from above the pilot station (height in m, default the eye height), looking at an
## azimuth (deg from north, clockwise) and an elevation (deg above the horizon; −90 = straight down), base FOV.
## Independent of the airplane.
static func look(camera: Camera3D, azimuth_deg: float, elevation_deg: float, height: float = NAN) -> void:
	camera.fov = Spec.CAMERA.fov_deg
	var station: Array = camera.get_meta("pilot_station", [0.0, 0.0, 0.0])
	var eye_height: float = float(camera.get_meta("pilot_eye_height", Spec.CAMERA.eye_height)) if is_nan(height) else height
	camera.position = Frames.ned_to_render([station[0], station[1], float(station[2]) - eye_height])
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	var dir := Frames.ned_to_render([cos(az) * cos(el), sin(az) * cos(el), -sin(el)])
	# Straight down, "up" on screen is north (Vector3.UP would be parallel to the view).
	var up := Vector3.UP if absf(elevation_deg) < 89.0 else Frames.ned_to_render([1.0, 0.0, 0.0])
	camera.look_at(camera.position + dir * 100.0, up)


## target: airplane position (render axes); airplane: its root transform (for the inspect offset).
## auto_zoom_span > 0: the pilot view narrows its FOV for an airplane of that span. base_fov: the pilot view's widest
## vertical FOV (CAM-17 player setting; the close-up keeps the default).
static func aim(camera: Camera3D, target: Vector3, airplane: Transform3D, inspect: bool, auto_zoom_span := 0.0,
		base_fov := float(Spec.CAMERA.fov_deg)) -> void:
	camera.fov = Spec.CAMERA.fov_deg if inspect else base_fov
	if inspect:
		# Inspection view: camera fixed to the airplane (left, above, behind), to check geometry.
		camera.position = airplane * Spec.INSPECT_OFFSET
	else:
		var station: Array = camera.get_meta("pilot_station", [0.0, 0.0, 0.0])
		var eye_height: float = float(camera.get_meta("pilot_eye_height", Spec.CAMERA.eye_height))
		camera.position = Frames.ned_to_render([station[0], station[1], float(station[2]) - eye_height])
		if auto_zoom_span > 0.0:
			camera.fov = auto_fov(auto_zoom_span, camera.position.distance_to(target), float(Spec.AUTO_ZOOM.target_px),
				float(Spec.AUTO_ZOOM.reference_height_px), base_fov)
	var direction := target - camera.global_position
	# An eye-coincident target has no viewing direction. Preserve the last pose.
	if direction.length_squared() < 1e-12:
		return
	direction = direction.normalized()
	if direction.cross(Vector3.UP).is_zero_approx():
		# World-up cannot define roll at the pole. Preserve screen-right there;
		# fall back to north only if the previous right axis is also parallel.
		var up := camera.global_basis.x.cross(direction)
		if up.is_zero_approx():
			up = Vector3.FORWARD
		else:
			up = up.normalized()
		camera.look_at(target, up)
	else:
		camera.look_at(target, Vector3.UP)
