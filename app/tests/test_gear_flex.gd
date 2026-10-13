# US-V10: the Stik's legs bend to meet the axles that the contact compression moves (render/ground_gear.gd).
# Rebuilds the deformed meshes on the CPU (base + Σ weight · relative blend shape) and checks the cantilever shape:
# the clamp stays fixed, the axle follows the wheel exactly, mid-leg follows N(t), legs are independent, the nose fork
# rides with its wheel and any attitude-dependent "world up" direction is honoured.
extends SceneTree

const AirplaneBuilder := preload("res://render/airplane.gd")
const GearFlex := preload("res://aircraft/ugly_stik_gear_flex.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")

var _checks := 0
var _failed := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	var airplane: Dictionary = AirplaneBuilder.build(AirplaneBuilder.STIK_ID)
	var root: Node3D = airplane.root
	var flex: Node = root.find_child("gear_flex", false, false)
	_check("gear flex node exists and runs after GroundGearMotion", flex != null and flex.process_priority > 0)
	var main := root.find_child("main_gear_structure", false, false) as MeshInstance3D
	var strut := root.find_child("nose_gear_strut", false, false) as MeshInstance3D
	var fork := root.find_child("nose_fork_and_steering_arm", true, false) as MeshInstance3D
	_check("legs carry three blend shapes each", main.mesh.get_blend_shape_count() == 6 and strut.mesh.get_blend_shape_count() == 3)
	var e: Dictionary = Geometry.DATA.equipment
	var rest := {}
	for key in ["left", "right", "nose"]: rest[key] = airplane.gear[key].position
	var fork_rest := fork.position
	var root_z: float = float(e.main_axle_z) - 0.050
	var right_tip := Vector3(float(e.main_track) * 0.5, float(e.wheel_y), float(e.main_axle_z))

	for c in [0.0, 0.018, 0.08]:
		_press(airplane, rest, {left = c, right = c, nose = c})
		flex.update()
		var tip := _displacement_near(main, right_tip + Vector3(-0.014, 0, 0))
		var clamp := _displacement_near(main, Vector3(0.026, 0, root_z) + Vector3(0, _bottom(root_z) + 0.007, 0))
		_check("compression %.3f m: right axle sleeve follows the wheel" % c, tip.distance_to(Vector3.UP * c) < 1e-4, str(tip))
		_check("compression %.3f m: leg clamp stays on the fuselage" % c, clamp.length() < 1e-4, str(clamp))
		var root_point := Vector3(0.025, _bottom(root_z) + 0.004, root_z)
		var mid := _displacement_near(main, root_point.lerp(right_tip, 0.5))
		# Independent of GearFlex.shape(): a clamped cantilever with a tip load deflects 5/16 of the tip at mid-span.
		_check("compression %.3f m: mid-leg follows the cantilever shape" % c, absf(mid.y - 5.0 / 16.0 * c) < 0.06 * c + 1e-4, "%.5f vs %.5f" % [mid.y, 5.0 / 16.0 * c])
		_check("compression %.3f m: nose fork rides with the nose wheel" % c, fork.position.distance_to(fork_rest + Vector3.UP * c) < 1e-6)

	_press(airplane, rest, {left = 0.05, right = 0.0, nose = 0.0})
	flex.update()
	var right_still := _displacement_near(main, right_tip + Vector3(-0.014, 0, 0))
	var left_moved := _displacement_near(main, Vector3(-right_tip.x + 0.014, right_tip.y, right_tip.z))
	_check("left and right legs bend independently", right_still.length() < 1e-4 and left_moved.distance_to(Vector3.UP * 0.05) < 1e-4, "%s %s" % [right_still, left_moved])

	# A pitched/banked airplane: ground_gear converts world up into each pivot's parent space.
	var tilted := Vector3(0.12, 0.97, -0.21).normalized() * 0.04
	_press(airplane, rest, {left = 0.0, right = 0.0, nose = 0.0})
	airplane.gear.right.position = rest.right + tilted
	flex.update()
	var tilted_tip := _displacement_near(main, right_tip + Vector3(-0.014, 0, 0))
	_check("an attitude-dependent contact direction maps onto the leg", tilted_tip.distance_to(tilted) < 1e-4, str(tilted_tip))

	# Steering: the nose axle offset lives in the steering frame; the strut bends in root space.
	airplane.gear.right.position = rest.right
	airplane.gear.steering.rotation.y = deg_to_rad(30.0)
	airplane.gear.nose.position = rest.nose + Vector3(0.0, 0.03, 0.01)
	flex.update()
	var nose_end := Vector3(0, float(e.wheel_y) + 0.067, float(e.nose_axle_z))
	var strut_end := _displacement_near(strut, nose_end)
	var expected: Vector3 = (airplane.gear.steering as Node3D).basis * Vector3(0.0, 0.03, 0.01)
	_check("steered nose: strut end follows the axle in root space", strut_end.distance_to(expected) < 2e-4, "%s vs %s" % [strut_end, expected])

	_press(airplane, rest, {left = 0.0, right = 0.0, nose = 0.0})
	airplane.gear.steering.rotation.y = 0.0
	flex.update()
	_check("released gear returns to the built legs", _displacement_near(main, right_tip + Vector3(-0.014, 0, 0)).length() < 1e-6 and fork.position.is_equal_approx(fork_rest))
	print("US-V10 gear flex: %d checks, %d failed" % [_checks, _failed])
	root.free()
	quit(1 if _failed > 0 else 0)


static func _bottom(z: float) -> float:
	var stations: Array = Geometry.DATA.fuselage_stations
	for i in range(stations.size() - 1):
		if z <= float(stations[i + 1][0]):
			return lerpf(float(stations[i][3]), float(stations[i + 1][3]), clampf((z - float(stations[i][0])) / (float(stations[i + 1][0]) - float(stations[i][0])), 0.0, 1.0))
	return float(stations.back()[3])


static func _press(airplane: Dictionary, rest: Dictionary, compression: Dictionary) -> void:
	for key in compression:
		airplane.gear[key].position = rest[key] + Vector3.UP * float(compression[key])


# Displacement of the base vertex closest to `point`: Σ weight · relative blend offset (RELATIVE blend-shape mode).
static func _displacement_near(instance: MeshInstance3D, point: Vector3) -> Vector3:
	var mesh := instance.mesh as ArrayMesh
	var best := INF
	var best_surface := 0
	var best_index := 0
	for surface in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			var d := vertices[i].distance_squared_to(point)
			if d < best:
				best = d
				best_surface = surface
				best_index = i
	var offset := Vector3.ZERO
	var blends: Array = mesh.surface_get_blend_shape_arrays(best_surface)
	for shape in blends.size():
		var delta: PackedVector3Array = blends[shape][Mesh.ARRAY_VERTEX]
		offset += delta[best_index] * instance.get_blend_shape_value(shape)
	return offset
