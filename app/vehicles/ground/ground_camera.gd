## One presentation camera for driving and the garage.
extends RefCounted

const Chase = preload("res://render/camera/chase_view.gd")
const CameraMath = preload("res://render/camera/camera_math.gd")
const FpvOptics := preload("res://render/camera/fpv_optics.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
const VehicleCatalog := preload("res://vehicles/ground/vehicle_catalog.gd")

const OVERVIEW := 3
const FPV := 4
const GARAGE := 5
const GARAGE_OVERVIEW := 6
const FPV_HFOV_DEG := 90.0

var chase = Chase.new()
var mode := 0
var orbit_yaw := PI + 0.65
var orbit_pitch := 0.28
var distance := 2.0
var pilot_position := Vector3(4.0, 1.6, 2.0)
var track_center := Vector3(0.0, 0.0, -45.0)
var _front_mount := Transform3D.IDENTITY
var _has_front_mount := false
var _last_view := -1
var _teleported := false

func _init() -> void:
	chase.distance = 2.0
	chase.height = 0.8

## Both stock adapters bind the front bumper. Resolve the fixed lens once in chassis coordinates,
## including Monster Car 2's imported art rotation and vertical datum correction.
func bind_front(vehicle_id: String, visual: Dictionary) -> bool:
	if not VehicleCatalog.contains(vehicle_id) or not visual.get("ok", false):
		return false
	var chassis := visual.get("root") as Node3D
	var bumper := visual.get("nodes", {}).get("Bumper_F") as MeshInstance3D
	if chassis == null or not chassis.is_inside_tree() or bumper == null or bumper.mesh == null \
			or not chassis.is_ancestor_of(bumper):
		return false
	var pose := chassis.global_transform.affine_inverse() * bumper.global_transform
	if not FpvOptics.is_valid_frame(pose):
		return false
	var bounds := pose * bumper.mesh.get_aabb()
	if not bounds.is_finite() or not bounds.has_volume() or bounds.position.z >= 0.0:
		return false
	# Virtual bracket 8 cm above the bumper and 3 cm forward of its leading face.
	var point := Vector3(bounds.get_center().x, bounds.end.y + 0.08, bounds.position.z - 0.03)
	_front_mount = Transform3D(Basis.IDENTITY, point)
	_has_front_mount = true
	return true


func cycle(has_overview: bool) -> void:
	var count := FPV + 1 if _has_front_mount else OVERVIEW + 1
	mode = (mode + 1) % count
	if mode == OVERVIEW and not has_overview:
		mode = (mode + 1) % count
	reset()


func reset(teleported := false) -> void:
	chase.reset()
	_teleported = _teleported or teleported

func drag(relative: Vector2) -> void:
	orbit_yaw -= relative.x * 0.006
	orbit_pitch = clampf(orbit_pitch + relative.y * 0.005, 0.08, 1.3)

func zoom(factor: float) -> void:
	distance = clampf(distance * factor, 0.9, 8.0)
	chase.distance = distance
	chase.height = distance * 0.4

func update(camera: Camera3D, target: Vector3, body: Basis, dt: float, menu: bool, terrain: Callable,
		chassis: Node3D = null) -> void:
	var position: Vector3
	var view := mode
	if menu:
		view = GARAGE_OVERVIEW if mode == OVERVIEW else GARAGE
	if view == FPV:
		if not _has_front_mount or not is_instance_valid(chassis):
			return
		var chassis_pose := chassis.global_transform
		if not FpvOptics.is_valid_frame(chassis_pose):
			return
		camera.global_transform = FpvOptics.compose(chassis_pose, _front_mount)
		var size := camera.get_viewport().get_visible_rect().size
		if size.x > 0.0 and size.y > 0.0:
			camera.fov = CameraMath.vertical_fov(FPV_HFOV_DEG, size.x / size.y)
	elif mode == OVERVIEW:
		position = track_center + Vector3(-6.0, 27.0, 26.0)
		camera.global_position = position
		camera.global_basis = CameraMath.look_basis(position, track_center + Vector3(4.0 if menu else 0.0, 0.0, 4.0))
		camera.fov = 48.0
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
	# The garage shows an external inspection view even when Drive will start in FPV.
	# Submit one cut after the final pose and optics have been applied.
	if _last_view != view or _teleported:
		Reconstruction.request_history_reset(camera.get_viewport(), "ground_camera_cut", null, true)
		_last_view = view
		_teleported = false
