# Rotorcraft-specific crossfade that reuses PropellerBlur's measured blade
# coverage profile and blade-passing transition while accepting either rotor.
extends Node3D
class_name HeliRotorBlur

const PropellerBlur := preload("res://render/propeller_blur.gd")
const RINGS := 36
const SEGMENTS := 72
const GAIN := 1.0

var measured: Dictionary = {}
var _rotor: Node3D
var _original_blades: Array[MeshInstance3D] = []

var _hub_copies: Array[MeshInstance3D] = []
var _blade_copies: Array[MeshInstance3D] = []
var _fade_materials: Array[BaseMaterial3D] = []
var _disc_materials: Array[StandardMaterial3D] = []
var _disc: MeshInstance3D
var _applied := false
var _fraction := -1.0


## Measure `rotor` in its local +Z frame and create a sibling presentation node.
static func attach(rotor: Node3D, root: Node3D, parent: Node) -> Node3D:
	if rotor == null or root == null or parent == null:
		return null
	var profile := PropellerBlur.profile(rotor, root)
	if profile.is_empty():
		return null
	var node := HeliRotorBlur.new()
	node.name = str(rotor.name) + "_blur"
	node._rotor = rotor
	node.measured = profile
	node._build()
	parent.add_child(node)
	return node


## Use the same perceptual transition as airplane propellers, driven by this rotor's own RPM.
static func blur_fraction(rotor_rpm: float, blades: int) -> float:
	return PropellerBlur.blur_fraction(rotor_rpm, blades)


func _build() -> void:
	var copied: Dictionary = {}
	for surface: Dictionary in measured.surfaces:
		var source: MeshInstance3D = surface.node
		if not copied.has(source):
			copied[source] = true
			_original_blades.append(source)
		var arrays: Array = surface.arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := _indices(arrays, vertices.size())
		var transform: Transform3D = surface.transform
		var hub_indices := PackedInt32Array()
		var blade_indices := PackedInt32Array()
		var hub_radius: float = measured.hub_radius
		for first in range(0, indices.size() - 2, 3):
			var inside_hub := true
			for corner in 3:
				var point: Vector3 = transform * vertices[indices[first + corner]]
				if Vector2(point.x, point.y).length() > hub_radius + 1e-6:
					inside_hub = false
					break
			var target := hub_indices if inside_hub else blade_indices
			target.append(indices[first])
			target.append(indices[first + 1])
			target.append(indices[first + 2])
		var material: Material = surface.material
		if not hub_indices.is_empty():
			_hub_copies.append(_copy_surface(source, int(surface.surface), arrays,
				hub_indices, transform, material, "hub"))
		if not blade_indices.is_empty():
			var fade_material := _fade_material(material)
			_blade_copies.append(_copy_surface(source, int(surface.surface), arrays,
				blade_indices, transform, fade_material, "blade_fade"))
			_fade_materials.append(fade_material)
	_build_disc()


func _copy_surface(source: MeshInstance3D, surface: int, arrays: Array,
		indices: PackedInt32Array, transform: Transform3D, material: Material, label: String) -> MeshInstance3D:
	var own_arrays: Array = arrays.duplicate()
	own_arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, own_arrays)
	if material != null:
		mesh.surface_set_material(0, material)
	var copy := MeshInstance3D.new()
	copy.name = "%s_%s_%d" % [source.name, label, surface]
	copy.mesh = mesh
	copy.transform = transform
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	copy.visible = false
	add_child(copy)
	return copy


static func _indices(arrays: Array, vertex_count: int) -> PackedInt32Array:
	var index: Variant = arrays[Mesh.ARRAY_INDEX]
	if index != null and index.size() > 0:
		return index
	var sequential := PackedInt32Array()
	sequential.resize(vertex_count - vertex_count % 3)
	for index_number in sequential.size():
		sequential[index_number] = index_number
	return sequential


static func _fade_material(source: Material) -> BaseMaterial3D:
	var material: BaseMaterial3D
	if source is BaseMaterial3D:
		material = (source as BaseMaterial3D).duplicate() as BaseMaterial3D
	else:
		material = StandardMaterial3D.new()
		material.albedo_color = Color("25292f")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _build_disc() -> void:
	var coverage: PackedFloat64Array = measured.coverage
	var ring_width: float = measured.ring_width
	var first_ring := clampi(ceili(float(measured.inner_radius) / ring_width - 1e-6), 0, RINGS)
	var mesh := ArrayMesh.new()
	var ring := first_ring
	while ring < RINGS:
		var source_material: Material = measured.colors[ring]
		var last := ring
		while last + 1 < RINGS and measured.colors[last + 1] == source_material:
			last += 1
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for band in range(ring, last + 1):
			var alpha_inner := _boundary_alpha(coverage, band)
			var alpha_outer := _boundary_alpha(coverage, band + 1)
			if alpha_inner <= 0.0 and alpha_outer <= 0.0:
				continue
			_annulus_band(tool, band * ring_width, (band + 1) * ring_width,
				alpha_inner, alpha_outer, float(measured.plane_z), _color(source_material))
		tool.generate_normals()
		var band_mesh := tool.commit()
		if band_mesh.get_surface_count() > 0:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, band_mesh.surface_get_arrays(0))
			var disc_material := _disc_material(source_material)
			mesh.surface_set_material(mesh.get_surface_count() - 1, disc_material)
			_disc_materials.append(disc_material)
		ring = last + 1
	_disc = MeshInstance3D.new()
	_disc.name = "analytic_rotor_disc"
	_disc.mesh = mesh
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.visible = false
	add_child(_disc)


static func _color(source: Material) -> Color:
	if source is BaseMaterial3D:
		var base := (source as BaseMaterial3D).albedo_color
		return Color(base.r, base.g, base.b, 1.0)
	return Color("25292f")


static func _disc_material(source: Material) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(_color(source).r, _color(source).g, _color(source).b, 0.0)
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _boundary_alpha(coverage: PackedFloat64Array, boundary: int) -> float:
	var inner := coverage[boundary - 1] if boundary > 0 else 0.0
	var outer := coverage[boundary] if boundary < coverage.size() else 0.0
	return clampf(0.5 * (inner + outer), 0.0, 1.0)


static func _annulus_band(tool: SurfaceTool, r0: float, r1: float, a0: float, a1: float,
		plane_z: float, tint: Color) -> void:
	for segment in SEGMENTS:
		var theta0 := TAU * float(segment) / SEGMENTS
		var theta1 := TAU * float(segment + 1) / SEGMENTS
		var p00 := Vector3(r0 * cos(theta0), r0 * sin(theta0), plane_z)
		var p01 := Vector3(r0 * cos(theta1), r0 * sin(theta1), plane_z)
		var p10 := Vector3(r1 * cos(theta0), r1 * sin(theta0), plane_z)
		var p11 := Vector3(r1 * cos(theta1), r1 * sin(theta1), plane_z)
		for triangle in [[p00, a0, p10, a1, p01, a0], [p01, a0, p10, a1, p11, a1]]:
			for vertex in 3:
				var point: Vector3 = triangle[2 * vertex]
				var alpha: float = float(triangle[2 * vertex + 1])
				tool.set_color(Color(tint.r, tint.g, tint.b, alpha))
				tool.add_vertex(point)


## `rotor_rpm` is presentation input only. The measured source blades remain visible below the transition;
## the profile-matched analytic disc fades in over the same 12–48 blade-pass-Hz interval as PropellerBlur.
func update(rotor_rpm: float) -> void:
	if not is_finite(rotor_rpm) or _rotor == null or not is_instance_valid(_rotor):
		rotor_rpm = 0.0
	var shown := _rotor != null and is_instance_valid(_rotor) and _rotor.is_inside_tree() and _rotor.is_visible_in_tree()
	if shown:
		global_transform = _rotor.global_transform
	var next_fraction := blur_fraction(rotor_rpm, int(measured.blades)) if shown else 0.0
	if _applied and next_fraction == _fraction:
		return
	_applied = true
	_fraction = next_fraction
	for node: MeshInstance3D in _original_blades:
		node.visible = next_fraction <= 0.0
	for node: MeshInstance3D in _blade_copies:
		node.visible = shown and next_fraction > 0.0 and next_fraction < 1.0
	for node: MeshInstance3D in _hub_copies:
		node.visible = shown and next_fraction > 0.0
	for material: BaseMaterial3D in _fade_materials:
		var color := material.albedo_color
		color.a = 1.0 - next_fraction
		material.albedo_color = color
	_disc.visible = shown and next_fraction > 0.0
	for material: StandardMaterial3D in _disc_materials:
		var color := material.albedo_color
		color.a = clampf(GAIN * next_fraction, 0.0, 1.0)
		material.albedo_color = color


func _exit_tree() -> void:
	for node: MeshInstance3D in _original_blades:
		if is_instance_valid(node):
			node.visible = true
