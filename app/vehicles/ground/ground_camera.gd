## Presentation-only RC chase, driver's stand and orbit cameras.
extends RefCounted

const Chase = preload("res://render/camera/chase_view.gd")
const CameraMath = preload("res://render/camera/camera_math.gd")
var chase = Chase.new()
var mode := 0
var orbit_yaw := PI + 0.65
var orbit_pitch := 0.28
var distance := 2.0
var pilot_position := Vector3(4.0, 1.6, 2.0)
var track_center := Vector3(0.0, 0.0, -45.0)
var _snap := true

func _init() -> void:
	chase.distance = 2.0
	chase.height = 0.8

func reset() -> void:
	chase.reset()
	_snap = true

func drag(relative: Vector2) -> void:
	orbit_yaw -= relative.x * 0.006
	orbit_pitch = clampf(orbit_pitch + relative.y * 0.005, 0.08, 1.3)

func zoom(factor: float) -> void:
	distance = clampf(distance * factor, 0.9, 8.0)
	chase.distance = distance
	chase.height = distance * 0.4

func update(camera: Camera3D, target: Vector3, body: Basis, dt: float, menu: bool, terrain: Callable) -> void:
	var position: Vector3
	if mode == 3:
		position = track_center + Vector3(-14.0, 27.0, 29.0)
		camera.global_position = position
		camera.global_basis = CameraMath.look_basis(position, track_center + Vector3(2.0 if menu else 0.0, 0.0, 0.0))
		camera.fov = 62.0
	elif mode == 0 and not menu:
		var pose: Dictionary = chase.update(target, body, dt, false, terrain)
		camera.global_position = pose.position
		camera.global_basis = pose.basis
		camera.fov = 54.0
	elif mode == 1 and not menu:
		position = pilot_position
		camera.global_position = position
		camera.global_basis = CameraMath.look_basis(position, target)
		camera.fov = clampf(rad_to_deg(2.0 * atan(2.0 / maxf(position.distance_to(target), 0.1))), 18.0, 65.0)
	else:
		var radius := distance if not menu else 1.65
		position = target + Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch)) * radius
		position.y = maxf(position.y, float(terrain.call(position.x, position.z)) + 0.12)
		camera.global_position = position
		var look_target := target + Vector3(0, 0.01, 0)
		# Shift the truck left while the garage panel occupies the right third.
		if menu:
			look_target += Vector3.UP.cross(position - target).normalized() * 0.28
		camera.global_basis = CameraMath.look_basis(position, look_target)
		camera.fov = 46.0
	_snap = false
