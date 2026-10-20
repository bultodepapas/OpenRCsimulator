## LU-28: static, spatially batched agricultural ground and connected road network.
## Offline source owns all placement and tessellation; no terrain frame callbacks.
extends RefCounted

const Atmosphere := preload("res://render/atmosphere.gd")
const SHADER := preload("res://render/landscape_upgrade/countryside_surface.gdshader")
const GRASS := preload("res://assets/landscape/rc-ground/grass-albedo.jpg")
const DIRT := preload("res://assets/landscape/rc-ground/dirt-albedo.jpg")
const ASPHALT := preload("res://assets/landscape/countryside/aerial_asphalt_01_diff_1k.jpg")
const PATH := "res://data/scenery/countryside.json"
const MAX_TRIANGLES := 14000
const MAX_CELLS := 40
static var _cached_arrays: Dictionary = {}
static var _stats: Dictionary = {}


static func _load() -> bool:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not raw is Dictionary or raw.get("format") != "openrc-countryside v1" \
			or not raw.get("cells") is Dictionary or raw.cells.size() > MAX_CELLS:
		push_error("Countryside: missing or incompatible visual layout")
		return false
	var arrays_by_cell := {}
	var total := 0
	for key: String in raw.cells:
		var cell: Variant = raw.cells[key]
		if not cell is Dictionary or not cell.get("vertices") is Array or not cell.get("indices") is Array \
				or cell.vertices.size() > 30000 or cell.indices.size() % 3 != 0:
			push_error("Countryside: invalid surface buffers")
			return false
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		for item: Variant in cell.vertices:
			if not item is Array or item.size() != 10:
				push_error("Countryside: invalid vertex")
				return false
			for value: Variant in item:
				if not (value is float or value is int) or not is_finite(float(value)):
					push_error("Countryside: nonfinite vertex")
					return false
			vertices.append(Vector3(item[0], item[1], item[2]))
			normals.append(Vector3.UP)
			uv.append(Vector2(item[3], item[4]))
			uv2.append(Vector2(item[5], item[6]))
			colors.append(Color(item[7], item[8], item[9]))
		var indices := PackedInt32Array()
		for index: Variant in cell.indices:
			if not (index is float or index is int) or index != floor(float(index)) \
					or index < 0 or index >= vertices.size():
				push_error("Countryside: invalid triangle index")
				return false
			indices.append(int(index))
		total += indices.size() / 3
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_INDEX] = indices
		arrays_by_cell[key] = arrays
	if total <= 0 or total > MAX_TRIANGLES or total != raw.get("triangles"):
		push_error("Countryside: triangle budget mismatch")
		return false
	_cached_arrays = arrays_by_cell
	_stats = {triangles = total, cells = arrays_by_cell.size(),
		parcels = raw.get("parcels", []).size(), roads = raw.get("roads", []).size()}
	return true


static func build(lighting: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Countryside"
	if _cached_arrays.is_empty() and not _load():
		return root
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("grass_tex", GRASS)
	material.set_shader_parameter("soil_tex", DIRT)
	material.set_shader_parameter("asphalt_tex", ASPHALT)
	Atmosphere.update_ground_material(material, lighting)
	for key: String in _cached_arrays:
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _cached_arrays[key])
		mesh.surface_set_material(0, material)
		var instance := MeshInstance3D.new()
		instance.name = "Surface_" + key
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
	root.set_meta("lighting_material", material)
	root.set_meta("stats", _stats.duplicate())
	return root
