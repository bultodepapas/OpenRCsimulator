# Pilot camera: the RC pilot's eyes at a fixed spot on the field, always looking at the airplane; or (inspect)
# a close-up fixed to the airplane, to check geometry. Auto-zoom (D7) keeps a distant airplane readable.
extends RefCounted

const Spec := preload("res://spec.gd")
const Frames := preload("res://render/frames.gd")


static func create(parent: Node) -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = Spec.CAMERA.fov_deg
	camera.near = Spec.CAMERA.near
	camera.far = Spec.CAMERA.far
	parent.add_child(camera)
	camera.current = true
	return camera


## Projected size (pixels of the viewport height) of a length seen face-on at a distance, vertical FOV in degrees.
static func projected_px(length: float, distance: float, fov_deg: float, viewport_h: float) -> float:
	return length / (2.0 * maxf(distance, 1e-6) * tan(deg_to_rad(fov_deg) * 0.5)) * viewport_h


## Vertical FOV (degrees) that shows `span` at `target_px` at this distance: never wider than the base FOV,
## never narrower than the minimum.
static func auto_fov(span: float, distance: float, viewport_h: float, target_px := float(Spec.AUTO_ZOOM.target_px),
		base_fov := float(Spec.CAMERA.fov_deg), min_fov := float(Spec.AUTO_ZOOM.min_fov_deg)) -> float:
	var fov := rad_to_deg(2.0 * atan(span * viewport_h / (2.0 * maxf(distance, 1e-6) * target_px)))
	return clampf(fov, min_fov, base_fov)


## Landscape review views (L0): from above the pilot station (height in m, default the eye height), looking at an
## azimuth (deg from north, clockwise) and an elevation (deg above the horizon; −90 = straight down), base FOV.
## Independent of the airplane.
static func look(camera: Camera3D, azimuth_deg: float, elevation_deg: float, height := float(Spec.CAMERA.eye_height)) -> void:
	camera.fov = Spec.CAMERA.fov_deg
	camera.position = Frames.ned_to_render([0.0, 0.0, -height])
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	var dir := Frames.ned_to_render([cos(az) * cos(el), sin(az) * cos(el), -sin(el)])
	# Straight down, "up" on screen is north (Vector3.UP would be parallel to the view).
	var up := Vector3.UP if absf(elevation_deg) < 89.0 else Frames.ned_to_render([1.0, 0.0, 0.0])
	camera.look_at(camera.position + dir * 100.0, up)


## target: airplane position (render axes); airplane: its root transform (for the inspect offset).
## auto_zoom_span > 0: the pilot view narrows its FOV for an airplane of that span.
static func aim(camera: Camera3D, target: Vector3, airplane: Transform3D, inspect: bool, auto_zoom_span := 0.0) -> void:
	camera.fov = Spec.CAMERA.fov_deg
	if inspect:
		# Inspection view: camera fixed to the airplane (left, above, behind), to check geometry.
		camera.position = airplane * Spec.INSPECT_OFFSET
	else:
		camera.position = Frames.ned_to_render([0.0, 0.0, -Spec.CAMERA.eye_height])
		if auto_zoom_span > 0.0:
			var h := float(camera.get_viewport().get_visible_rect().size.y) if camera.is_inside_tree() else float(Spec.CAPTURE.height)
			camera.fov = auto_fov(auto_zoom_span, camera.position.distance_to(target), h)
	camera.look_at(target, Vector3.UP)
