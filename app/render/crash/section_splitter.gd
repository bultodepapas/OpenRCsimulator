## CR-09c: splits a merged imported mesh into real section meshes for the crash wreck only. A MeshInstance3D that
## carries meta("crash_section_map") is replaced, inside the wreck's hidden twin, by one child per section built from
## whole triangles of its own surfaces: materials, normals, tangents and UVs are copied, no triangle is cut, none is
## dropped or duplicated. The flying model is never touched. The map is generated offline by the aircraft's pipeline
## (e.g. research/timber/tt13), so the runtime does no welding or classification.
##
## Map format: {format = "openrc-crash-sections v1", sections = ["core", "wing_left", ...],
##   surfaces = [[section_index, triangle_count, section_index, triangle_count, ...], ...]}  (run-length, per surface,
##   in index-buffer triangle order). "core" keeps triangles with the airframe body.
extends RefCounted

const FORMAT := "openrc-crash-sections v1"
const META := "crash_section_map"
const SECTION_META := "crash_section"


## Replaces every mapped MeshInstance3D under `root` (a wreck twin). Returns {ok, replaced, triangles, errors}.
static func apply(root: Node) -> Dictionary:
	var out := {ok = true, replaced = 0, triangles = 0, errors = PackedStringArray()}
	var mapped: Array = []
	_find_mapped(root, mapped)
	for mesh_instance: MeshInstance3D in mapped:
		var result := split(mesh_instance)
		if not result.ok:
			out.ok = false
			out.errors.append_array(result.errors)
			continue
		out.replaced += 1
		out.triangles += int(result.triangles)
	return out


## Validates the map against the mesh and returns {ok, errors}; never modifies anything.
static func validate(mesh: Mesh, map: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if not map is Dictionary or str(map.get("format", "")) != FORMAT:
		errors.append("crash section map: missing or unsupported format")
		return {ok = false, errors = errors}
	var sections: Array = map.get("sections", [])
	var surfaces: Array = map.get("surfaces", [])
	if sections.is_empty() or mesh == null or surfaces.size() != mesh.get_surface_count():
		errors.append("crash section map: %d surface runs for %d mesh surfaces" % [surfaces.size(), mesh.get_surface_count() if mesh else -1])
		return {ok = false, errors = errors}
	for s in mesh.get_surface_count():
		var runs: Array = surfaces[s]
		var index: PackedInt32Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
		var covered := 0
		if runs.size() % 2 != 0:
			errors.append("surface %d: odd run list" % s)
			continue
		for r in range(0, runs.size(), 2):
			if int(runs[r]) < 0 or int(runs[r]) >= sections.size() or int(runs[r + 1]) <= 0:
				errors.append("surface %d: invalid run %d" % [s, r / 2])
			covered += int(runs[r + 1])
		if covered != index.size() / 3:
			errors.append("surface %d: runs cover %d of %d triangles" % [s, covered, index.size() / 3])
	return {ok = errors.is_empty(), errors = errors}


## Splits one mapped MeshInstance3D into section siblings (meta crash_section, same transform and parent) and frees
## it. Returns {ok, triangles, sections, errors}.
static func split(mesh_instance: MeshInstance3D) -> Dictionary:
	var map: Variant = mesh_instance.get_meta(META) if mesh_instance.has_meta(META) else null
	var mesh := mesh_instance.mesh
	var check := validate(mesh, map)
	if not check.ok:
		return {ok = false, triangles = 0, sections = [], errors = check.errors}
	var names: Array = map.sections
	var meshes := {}
	var triangles := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var per_section := {}
		var runs: Array = map.surfaces[s]
		var tri := 0
		for r in range(0, runs.size(), 2):
			var section := int(runs[r])
			if not per_section.has(section):
				per_section[section] = PackedInt32Array()
			var list: PackedInt32Array = per_section[section]
			list.append_array(index.slice(tri * 3, (tri + int(runs[r + 1])) * 3))
			per_section[section] = list
			tri += int(runs[r + 1])
		var keys: Array = per_section.keys()
		keys.sort()
		for section: int in keys:
			if not meshes.has(section):
				meshes[section] = ArrayMesh.new()
			var surface := _subset(arrays, per_section[section])
			var target: ArrayMesh = meshes[section]
			target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
			target.surface_set_material(target.get_surface_count() - 1, mesh_instance.get_active_material(s))
			triangles += (per_section[section] as PackedInt32Array).size() / 3
	var parent := mesh_instance.get_parent()
	var created: Array = []
	var keys: Array = meshes.keys()
	keys.sort()
	for section: int in keys:
		var child := MeshInstance3D.new()
		child.name = "%s_section_%s" % [mesh_instance.name, names[section]]
		child.mesh = meshes[section]
		child.transform = mesh_instance.transform
		child.cast_shadow = mesh_instance.cast_shadow
		child.set_meta(SECTION_META, String(names[section]))
		parent.add_child(child)
		parent.move_child(child, mesh_instance.get_index())
		created.append(String(names[section]))
	parent.remove_child(mesh_instance)
	mesh_instance.free()
	return {ok = true, triangles = triangles, sections = created, errors = PackedStringArray()}


## The vertices a triangle subset uses, with every attribute array present copied for them, re-indexed in first-use
## order (deterministic).
static func _subset(arrays: Array, triangles: PackedInt32Array) -> Array:
	var remap := {}
	var order := PackedInt32Array()
	var index := PackedInt32Array()
	index.resize(triangles.size())
	for i in triangles.size():
		var old := triangles[i]
		var mapped: int = remap.get(old, -1)
		if mapped < 0:
			mapped = order.size()
			remap[old] = mapped
			order.append(old)
		index[i] = mapped
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for a in Mesh.ARRAY_MAX:
		if a == Mesh.ARRAY_INDEX or arrays[a] == null:
			continue
		out[a] = _pick(arrays[a], order, vertex_count)
	out[Mesh.ARRAY_INDEX] = index
	return out


## Copies the per-vertex entries listed in `order`. Flat arrays (tangents: 4 floats, bone weights/indices: 4 or 8)
## carry size / vertex_count entries per vertex.
static func _pick(source: Variant, order: PackedInt32Array, vertex_count: int) -> Variant:
	if source is PackedVector3Array or source is PackedVector2Array or source is PackedColorArray:
		var o: Variant = source.duplicate()
		o.resize(order.size())
		for i in order.size():
			o[i] = source[order[i]]
		return o
	if source is PackedFloat32Array or source is PackedInt32Array:
		var width: int = source.size() / maxi(vertex_count, 1)
		var flat: Variant = source.duplicate()
		flat.resize(order.size() * width)
		for i in order.size():
			for k in width:
				flat[i * width + k] = source[order[i] * width + k]
		return flat
	return null # unsupported custom byte formats are dropped rather than mis-copied


static func _find_mapped(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.has_meta(META):
			out.append(child)
		_find_mapped(child, out)
