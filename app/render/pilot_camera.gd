# Pilot camera: the RC pilot's eyes at a fixed spot on the field, always looking at the airplane; or (inspect)
# a close-up fixed to the airplane, to check geometry. Auto-zoom comes with ROADMAP D7.
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


## target: airplane position (render axes); airplane: its root transform (for the inspect offset).
static func aim(camera: Camera3D, target: Vector3, airplane: Transform3D, inspect: bool) -> void:
	if inspect:
		# Inspection view: camera fixed to the airplane (left, above, behind), to check geometry.
		camera.position = airplane * Spec.INSPECT_OFFSET
	else:
		camera.position = Frames.ned_to_render([0.0, 0.0, -Spec.CAMERA.eye_height])
	camera.look_at(target, Vector3.UP)
