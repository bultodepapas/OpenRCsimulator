# AE-27-01a preparation: INTERNAL, UNQUALIFIED native wheel study.
# Only composes detached models. No Workshop/flight caller or exported source proof.
# Requires an unchanged Airplane.build result and exclusive ownership of this study.
# Source meshes/cached materials stay immutable; in-place edits by another owner
# are outside this prototype contract. Attaching a prepared model remains the
# caller's responsibility; a detached root alone does not prove flight admission.
# Keep original builder/manifest bytes unchanged until the coordinated migration.
extends RefCounted

const Selection := preload("res://workshop/attachment_selection.gd")
const Equipment := preload("res://aircraft/ugly_stik_equipment.gd")
const ROLES := ["left", "right", "nose"]
const MESH_NAMES := ["gear_left", "gear_right", "nosewheel"]
const WIDTHS_M := [0.024, 0.024, 0.022]
const SEGMENTS := 40
const GROOVE_HALF_WIDTH_M := 0.0005
const GROOVE_DEPTH_M := 0.0004
const SOURCE_TIRE_VERTICES := 2400 # Existing 10 profile bands × 40 segments × 6 vertices.

var _root: Node3D
var _entries: Array[Dictionary] = []
var _alternate := false
var _applied := false


## Stage every replacement before touching any live mesh. The resolved metadata is
## checked here again; caller-provided availability/factory/paths are never trusted.
static func stage(airplane: Dictionary, document: Variant, scale: Variant = null) -> Dictionary:
	var aircraft_id: Variant = airplane.get("aircraft_id")
	if typeof(aircraft_id) != TYPE_STRING or aircraft_id != Selection.PILOT_ID \
			or airplane.get("visual_family") != Selection.PILOT_ID:
		return _failure("The wheel study only supports the baseline Ugly Stick.")
	var resolved := Selection.resolve(document, aircraft_id, scale)
	if not resolved.ok:
		return resolved
	var root: Variant = airplane.get("root")
	if typeof(root) != TYPE_OBJECT or not is_instance_valid(root) or not (root is Node3D) \
			or root.is_inside_tree() or root.name != "airplane":
		return _failure("Stage the wheel study on a detached airplane before adding visual observers.")
	if not root.scale.is_equal_approx(Vector3.ONE):
		return _failure("The wheel study requires the unscaled native model.")
	var gear: Variant = airplane.get("gear")
	if typeof(gear) != TYPE_DICTIONARY:
		return _failure("The model has no native wheel handles.")
	var staged := new()
	staged._root = root
	staged._alternate = resolved.selection.selections.wheels == Selection.TWIN_GROOVE_ID
	for index in ROLES.size():
		var pivot: Variant = gear.get(ROLES[index])
		if typeof(pivot) != TYPE_OBJECT or not is_instance_valid(pivot) or not (pivot is Node3D) or not root.is_ancestor_of(pivot):
			return _failure("A native wheel pivot is missing: " + ROLES[index])
		var node := pivot.get_node_or_null(NodePath(MESH_NAMES[index])) as MeshInstance3D
		if node == null or not _source_mesh_valid(node.mesh):
			return _failure("The original wheel mesh contract changed: " + ROLES[index])
		if not _unit_scale_chain(node, root):
			return _failure("The wheel study requires unscaled native wheel frames.")
		var radius: float = float(Equipment.D.equipment.nose_wheel_diameter \
			if ROLES[index] == "nose" else Equipment.D.equipment.main_wheel_diameter) * 0.5
		var source := node.mesh as ArrayMesh
		if not _envelope_matches(source, radius, WIDTHS_M[index]):
			return _failure("The original tire envelope changed: " + ROLES[index])
		var replacement: ArrayMesh = _make_mesh(source, radius, WIDTHS_M[index]) if staged._alternate else source
		if replacement == null:
			return _failure("The engine's stored wheel surface format is unavailable.")
		staged._entries.append({"node": node, "pivot": pivot, "original": source,
			"replacement": replacement, "overrides": _overrides(node)})
	return {"ok": true, "errors": PackedStringArray(), "preview": staged,
		"availability": resolved.availability}


## Idempotent, all-or-nothing publication on the same detached model.
func apply() -> Dictionary:
	var checked := _check_live(_applied)
	if not checked.ok:
		return checked
	for entry: Dictionary in _entries:
		if not _unit_scale_chain(entry.node, _root):
			return _failure("The native model scale changed after staging.")
	if _applied:
		return _success(false)
	if not _alternate:
		return _success(false) # Original must not invoke mesh/material setters.
	for entry: Dictionary in _entries:
		if _overrides(entry.node) != entry.overrides:
			return _failure("Wheel materials changed after staging; stage the selection again.")
	for entry: Dictionary in _entries:
		_set_mesh(entry.node, entry.replacement, entry.overrides)
	_applied = true
	return _success(_alternate)


## Preserve any subsequent paint overrides while restoring the exact stock Mesh
## resources. Parts reset must not undo unrelated paint edits.
func restore() -> Dictionary:
	var checked := _check_live(_applied)
	if not checked.ok:
		return checked
	if not _applied:
		return _success(false)
	for entry: Dictionary in _entries:
		_set_mesh(entry.node, entry.original, _overrides(entry.node))
	_applied = false
	# A fresh apply should retain paint edits made since the first staging.
	for entry: Dictionary in _entries:
		entry.overrides = _overrides(entry.node)
	return _success(_alternate)


func _check_live(replacement: bool) -> Dictionary:
	if not is_instance_valid(_root) or _root.is_inside_tree():
		return _failure("The study requires the original detached airplane.")
	for entry: Dictionary in _entries:
		if not is_instance_valid(entry.node) or not is_instance_valid(entry.pivot) \
				or not _root.is_ancestor_of(entry.pivot) or entry.node.get_parent() != entry.pivot:
			return _failure("A staged wheel handle was removed or reparented.")
		var expected: Mesh = entry.replacement if replacement else entry.original
		if entry.node.mesh != expected:
			return _failure("A staged wheel mesh was replaced by another owner.")
	return {"ok": true}


static func _unit_scale_chain(node: Node3D, root: Node3D) -> bool:
	var current: Node = node
	while current is Node3D:
		var frame := current as Node3D
		if not frame.basis.is_conformal() or not frame.scale.is_equal_approx(Vector3.ONE):
			return false
		if current == root:
			return true
		current = current.get_parent()
	return false


static func _source_mesh_valid(mesh: Mesh) -> bool:
	if not (mesh is ArrayMesh) or mesh.get_surface_count() != 4 or mesh.get_blend_shape_count() != 0:
		return false
	var names := ["rubber:" + Equipment.RUBBER_COLOR.to_html(), "rubber:" + Equipment.TIRE_LINE_COLOR.to_html(),
		"aluminum:" + Equipment.CASE_COLOR.to_html(), "steel:" + Equipment.STEEL_COLOR.to_html()]
	for surface in 4:
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		var material := mesh.surface_get_material(surface)
		if material == null or material.resource_name != names[surface]:
			return false
	var arrays := mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array and arrays[Mesh.ARRAY_VERTEX].size() == SOURCE_TIRE_VERTICES


static func _envelope_matches(mesh: ArrayMesh, radius: float, width: float) -> bool:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var maximum_radius := 0.0
	var minimum_x := INF
	var maximum_x := -INF
	for vertex: Vector3 in vertices:
		if not vertex.is_finite():
			return false
		maximum_radius = maxf(maximum_radius, Vector2(vertex.y, vertex.z).length())
		minimum_x = minf(minimum_x, vertex.x)
		maximum_x = maxf(maximum_x, vertex.x)
	return absf(maximum_radius - radius) < 0.0000001 \
		and absf(minimum_x + width * 0.5) < 0.0000001 and absf(maximum_x - width * 0.5) < 0.0000001


static func _make_mesh(source: ArrayMesh, radius: float, width: float) -> ArrayMesh:
	var half := width * 0.5
	var groove := width * 0.07
	var profile: Array[Vector2] = [
		Vector2(-half, 0.010), Vector2(-half, radius * 0.77),
		Vector2(-half * 0.83, radius * 0.90), Vector2(-half * 0.56, radius * 0.98),
		Vector2(-half * 0.25, radius),
		Vector2(-groove - GROOVE_HALF_WIDTH_M, radius), Vector2(-groove, radius - GROOVE_DEPTH_M),
		Vector2(-groove + GROOVE_HALF_WIDTH_M, radius),
		Vector2(groove - GROOVE_HALF_WIDTH_M, radius), Vector2(groove, radius - GROOVE_DEPTH_M),
		Vector2(groove + GROOVE_HALF_WIDTH_M, radius),
		Vector2(half * 0.25, radius), Vector2(half * 0.56, radius * 0.98),
		Vector2(half * 0.83, radius * 0.90), Vector2(half, radius * 0.77),
		Vector2(half, 0.010), Vector2(-half, 0.010),
	]
	var tire := SurfaceTool.new()
	tire.begin(Mesh.PRIMITIVE_TRIANGLES)
	tire.set_material(source.surface_get_material(0).duplicate(true) as Material)
	Equipment._turned(tire, Vector3.ZERO, Vector3.RIGHT, profile, SEGMENTS, true)
	var tire_mesh: ArrayMesh = tire.commit()
	var tire_surfaces: Variant = tire_mesh.get("_surfaces")
	var source_surfaces: Variant = source.get("_surfaces")
	if not tire_surfaces is Array or tire_surfaces.size() != 1 \
			or not source_surfaces is Array or source_surfaces.size() != 4:
		return null
	if not tire_surfaces[0] is Dictionary:
		return null
	# Use the pinned engine's stored surface format, as imported_vegetation does.
	# Decoding/re-encoding hardware arrays changes packed normals/tangents. Keep
	# their buffers and indices exact; region updates would leave CPU copies stale.
	var surfaces: Array = [tire_surfaces[0].duplicate(true)]
	for surface in range(1, 4):
		if not source_surfaces[surface] is Dictionary:
			return null
		var copied: Dictionary = source_surfaces[surface].duplicate(true)
		copied["material"] = source.surface_get_material(surface).duplicate(true) as Material
		surfaces.append(copied)
	var result := ArrayMesh.new()
	result.set("_surfaces", surfaces)
	if result.get_surface_count() != 4:
		return null
	for surface in 4:
		var material := result.surface_get_material(surface)
		if material == null or material.resource_name != source.surface_get_material(surface).resource_name:
			return null
	result.surface_set_name(0, source.surface_get_name(0))
	return result


static func _overrides(node: MeshInstance3D) -> Array:
	var result: Array = []
	for surface in 4:
		result.append(node.get_surface_override_material(surface))
	return result


static func _set_mesh(node: MeshInstance3D, mesh: Mesh, overrides: Array) -> void:
	node.mesh = mesh
	for surface in 4:
		node.set_surface_override_material(surface, overrides[surface])


static func _success(changed: bool) -> Dictionary:
	return {"ok": true, "errors": PackedStringArray(), "geometry_changed": changed}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}
