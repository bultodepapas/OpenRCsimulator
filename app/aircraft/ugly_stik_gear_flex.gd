# US-V10: visible landing-gear flex. The physics contact compression already moves each wheel pivot up
# (render/ground_gear.gd). This node bends the main legs to meet the moved axle: a clamped cantilever with a tip
# displacement takes the shape N(t) = (3t² - t³)/2 along the leg (t = 0 at the fuselage clamp, 1 at the axle).
# US-V10b: the nose wire telescopes instead: its axial compression slides it up through the bearing against the
# compression spring until the spring is solid. Beyond that the straight leg below the torsion coil, loaded along its
# axis, bows aft (toward the coil) while its ends approach: a half-sine bow of amplitude a shortens the chord by
# Δ = π²a²/(4L), so a = 2·sqrt(L·Δ)/π keeps the axle exactly where the physics contact puts it. The bow is capped at
# NOSE_BOW_MAX_M (about 30° end slope, where linear vertex offsets still read as a round wire); any compression beyond
# spring travel plus that bow — only near the 0.12 m breaking compression of the soft physics contact — drives the
# solid spring, collar and wire up into the fuselage, as a yielding gear mount would.
# Each leg carries three blend shapes (unit displacement along model X, Y and Z), so the GPU deforms the mesh and
# the attitude-dependent "world up" of the contact maps onto any direction. Visual only: it never writes physics.
extends Node

const UNIT_M := 0.1 # blend-shape displacement at weight 1
const LEG_SEGMENTS := 12 # leg subdivisions; the bending shape needs interior vertices
## Share of the nose contact's compression taken by the compression spring before it is solid. A spring of a few N/mm
## in series with a 5/32 in wire takes essentially all of it (estimate; neither rate is measured).
const NOSE_SPRING_SHARE := 1.0
const NOSE_BOW_MAX_M := 0.015
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]

# Each leg: {instance, shapes: [x, y, z] blend indices, pivot, rest, frame} — frame converts the pivot's parent space
# displacement into the mesh's space (the nose wheel turns with the steering pivot; the main legs live in root space).
var _legs: Array = []
var _slider: Node3D
var _spring: Node3D
var _spring_length := 0.0
var _spring_travel := 0.0
var _nose_leg_length := 0.0
var _spring_rest := Vector3.ZERO


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
			shapes.append(mesh.get_blend_shape_count() - 1)
		if legs[leg_index].get("column", false):
			mesh.add_blend_shape("leg%d_bow" % leg_index)
			shapes.append(mesh.get_blend_shape_count() - 1)
		indices.append(shapes)
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var blends: Array = []
		for leg: Dictionary in legs:
			var root: Vector3 = leg.root
			var axis_vector: Vector3 = leg.tip - root
			var side: float = leg.side
			var column: bool = leg.get("column", false)
			var weights := PackedFloat32Array() # cantilever shape (lateral offsets)
			var axial := PackedFloat32Array() # linear chord shortening (column legs, along the leg)
			var bow := PackedFloat32Array() # half-sine bow (column legs)
			weights.resize(vertices.size())
			axial.resize(vertices.size())
			bow.resize(vertices.size())
			for i in vertices.size():
				var on_side: bool = side == 0.0 or signf(vertices[i].x) == side
				var at_axle: bool = vertices[i].distance_to(leg.tip) <= float(leg.rigid_radius)
				var t: float = (vertices[i] - root).dot(axis_vector) / axis_vector.length_squared()
				weights[i] = (1.0 if at_axle else shape(t)) if on_side else 0.0
				axial[i] = (1.0 if at_axle else clampf(t, 0.0, 1.0)) if on_side else 0.0
				bow[i] = (0.0 if at_axle else sin(PI * clampf(t, 0.0, 1.0))) if on_side else 0.0
			var profiles: Array = [weights, axial if column else weights, weights]
			for axis_index in AXES.size():
				var axis: Vector3 = AXES[axis_index]
				var profile: PackedFloat32Array = profiles[axis_index]
				var delta := PackedVector3Array()
				delta.resize(vertices.size())
				for i in vertices.size():
					delta[i] = axis * (UNIT_M * profile[i])
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
			if column:
				var bow_delta := PackedVector3Array()
				bow_delta.resize(vertices.size())
				var bow_axis: Vector3 = leg.get("bow_axis", Vector3.BACK)
				for i in vertices.size():
					bow_delta[i] = bow_axis * (UNIT_M * bow[i])
				var bow_blend: Array = blends[blends.size() - 1].duplicate()
				bow_blend[Mesh.ARRAY_VERTEX] = bow_delta
				blends.append(bow_blend)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blends)
		mesh.surface_set_material(surface, source.surface_get_material(surface))
	instance.mesh = mesh
	return indices


static func attach(root: Node3D, gear: Dictionary, main: MeshInstance3D, main_legs: Array, strut: MeshInstance3D, strut_leg: Dictionary, slider: Node3D, spring: Node3D) -> Node:
	var flex := new()
	flex.name = "gear_flex"
	flex.process_priority = 10 # after GroundGearMotion has placed the wheels this frame
	var main_shapes := make_flexible(main, main_legs)
	for i in main_legs.size():
		var key: String = "right" if main_legs[i].side > 0.0 else "left"
		flex._legs.append({instance = main, shapes = main_shapes[i], pivot = gear[key], rest = gear[key].position, nose = false})
	var strut_shapes := make_flexible(strut, [strut_leg])
	flex._nose_leg_length = (strut_leg.tip - strut_leg.root).length()
	flex._legs.append({instance = strut, shapes = strut_shapes[0], pivot = gear.nose, rest = gear.nose.position, nose = true})
	flex._slider = slider
	flex._spring = spring
	flex._spring_length = float(spring.get_meta("free_length_m", 0.045))
	flex._spring_rest = spring.position
	flex._spring_travel = float(slider.get_meta("spring_travel_m", 0.0))
	root.add_child(flex)
	return flex


## Half-sine bow amplitude that shortens the nose leg's chord by `shortening` (small-slope column geometry).
func bow_amplitude(shortening: float) -> float:
	return 2.0 * sqrt(_nose_leg_length * shortening) / PI


## Chord shortening of the nose leg at the capped bow.
func max_bow_shortening() -> float:
	return PI * PI * NOSE_BOW_MAX_M * NOSE_BOW_MAX_M / (4.0 * _nose_leg_length)


## Spring compression of the nose for a pivot offset `delta` in the steering frame (wire axis = +Y).
func nose_spring_compression(delta: Vector3) -> float:
	return clampf(NOSE_SPRING_SHARE * delta.y, 0.0, _spring_travel)


func _process(_dt: float) -> void:
	update()


## Apply the wheels' current offsets to the legs (also callable from tests without a running tree).
func update() -> void:
	for leg: Dictionary in _legs:
		if not is_instance_valid(leg.pivot) or not is_instance_valid(leg.instance):
			continue
		var delta: Vector3 = (leg.pivot as Node3D).position - leg.rest
		if leg.nose and is_instance_valid(_slider) and is_instance_valid(_spring):
			# The wire slides up through its bearing; the spring between bearing and collar shortens by the same amount.
			var sliding := nose_spring_compression(delta)
			var bowing := minf(maxf(delta.y - sliding, 0.0), max_bow_shortening())
			var excess := maxf(delta.y - sliding - bowing, 0.0)
			_slider.position = Vector3(0, sliding + excess, 0)
			_spring.position = _spring_rest + Vector3(0, excess, 0)
			_spring.scale = Vector3(1, (_spring_length - sliding) / _spring_length, 1)
			delta -= Vector3(0, sliding + excess, 0)
		var instance: MeshInstance3D = leg.instance
		for axis in AXES.size():
			instance.set_blend_shape_value(leg.shapes[axis], delta[axis] / UNIT_M)
		if leg.shapes.size() > AXES.size():
			# Column leg: the remaining axial shortening Δ appears as the aft bow that shortens its chord by Δ.
			instance.set_blend_shape_value(leg.shapes[AXES.size()], bow_amplitude(maxf(delta.y, 0.0)) / UNIT_M)
