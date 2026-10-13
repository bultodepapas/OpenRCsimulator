# US-V10: visible landing-gear flex. The physics contact compression already moves each wheel pivot up
# (render/ground_gear.gd). This node bends the legs to meet the moved axle: a clamped cantilever with a tip
# displacement takes the shape N(t) = (3t² - t³)/2 along the leg (t = 0 at the fuselage clamp, 1 at the axle).
# Each leg carries three blend shapes (unit displacement along model X, Y and Z), so the GPU deforms the mesh and
# the attitude-dependent "world up" of the contact maps onto any direction. Visual only: it never writes physics.
extends Node

const UNIT_M := 0.1 # blend-shape displacement at weight 1
const LEG_SEGMENTS := 12 # main strap subdivisions; the bending shape needs interior vertices
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]

# Each leg: {instance, shapes: [x, y, z] blend indices, pivot, rest, frame} — frame converts the pivot's parent space
# displacement into the mesh's space (the nose wheel turns with the steering pivot; the main legs live in root space).
var _legs: Array = []
var _fork: Node3D
var _fork_rest := Vector3.ZERO


## Cantilever shape function for a tip displacement, 0 at the clamp and 1 at the tip; constant beyond the tip.
static func shape(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	return 0.5 * (3.0 * u * u - u * u * u)


## Rebuild `instance`'s mesh with three blend shapes per leg. legs: [{root, tip: Vector3, side, rigid_radius: float}];
## side 0 = every vertex, ±1 = only vertices on that side of the symmetry plane. Hardware within rigid_radius of the
## tip (axle sleeve, nut, washers, the clamped strap end) moves rigidly with the axle. Returns the blend-shape indices.
static func make_flexible(instance: MeshInstance3D, legs: Array) -> Array:
	var source := instance.mesh as ArrayMesh
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	var indices: Array = []
	for leg_index in legs.size():
		var shapes: Array = []
		for axis in AXES.size():
			mesh.add_blend_shape("leg%d_%s" % [leg_index, "xyz"[axis]])
			shapes.append(leg_index * AXES.size() + axis)
		indices.append(shapes)
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var blends: Array = []
		for leg: Dictionary in legs:
			var root: Vector3 = leg.root
			var axis_vector: Vector3 = leg.tip - root
			var side: float = leg.side
			var weights := PackedFloat32Array()
			weights.resize(vertices.size())
			for i in vertices.size():
				var on_side: bool = side == 0.0 or signf(vertices[i].x) == side
				var at_axle: bool = vertices[i].distance_to(leg.tip) <= float(leg.rigid_radius)
				weights[i] = (1.0 if at_axle else shape((vertices[i] - root).dot(axis_vector) / axis_vector.length_squared())) if on_side else 0.0
			for axis: Vector3 in AXES:
				var delta := PackedVector3Array()
				delta.resize(vertices.size())
				for i in vertices.size():
					delta[i] = axis * (UNIT_M * weights[i])
				# Relative mode: offsets only; normals (and tangents, when present) do not change at these small slopes.
				var blend: Array = []
				blend.resize(Mesh.ARRAY_MAX)
				blend[Mesh.ARRAY_VERTEX] = delta
				var zero_normals := PackedVector3Array()
				zero_normals.resize(vertices.size())
				blend[Mesh.ARRAY_NORMAL] = zero_normals
				if arrays[Mesh.ARRAY_TANGENT] != null:
					var zero_tangents := PackedFloat32Array()
					zero_tangents.resize(vertices.size() * 4)
					blend[Mesh.ARRAY_TANGENT] = zero_tangents
				blends.append(blend)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blends)
		mesh.surface_set_material(surface, source.surface_get_material(surface))
	instance.mesh = mesh
	return indices


static func attach(root: Node3D, gear: Dictionary, main: MeshInstance3D, main_legs: Array, strut: MeshInstance3D, strut_leg: Dictionary, fork: Node3D) -> Node:
	var flex := new()
	flex.name = "gear_flex"
	flex.process_priority = 10 # after GroundGearMotion has placed the wheels this frame
	var main_shapes := make_flexible(main, main_legs)
	for i in main_legs.size():
		var key: String = "right" if main_legs[i].side > 0.0 else "left"
		flex._legs.append({instance = main, shapes = main_shapes[i], pivot = gear[key], rest = gear[key].position, frame = null})
	var strut_shapes := make_flexible(strut, [strut_leg])
	flex._legs.append({instance = strut, shapes = strut_shapes[0], pivot = gear.nose, rest = gear.nose.position, frame = gear.steering})
	flex._fork = fork
	flex._fork_rest = fork.position
	root.add_child(flex)
	return flex


func _process(_dt: float) -> void:
	update()


## Apply the wheels' current offsets to the legs (also callable from tests without a running tree).
func update() -> void:
	for leg: Dictionary in _legs:
		if not is_instance_valid(leg.pivot) or not is_instance_valid(leg.instance):
			continue
		var delta: Vector3 = (leg.pivot as Node3D).position - leg.rest
		if leg.frame != null and is_instance_valid(leg.frame):
			if _fork != null and is_instance_valid(_fork):
				_fork.position = _fork_rest + delta # the fork rides with the nose axle inside the steering frame
			delta = (leg.frame as Node3D).basis * delta
		var instance: MeshInstance3D = leg.instance
		for axis in AXES.size():
			instance.set_blend_shape_value(leg.shapes[axis], delta[axis] / UNIT_M)
