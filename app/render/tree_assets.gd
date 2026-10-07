# L6a: validated runtime adapter for baked Quaternius tree cards. Source meshes stay in the offline pipeline;
# close tree scenes belong to L8 after a <=1k-triangle LOD has been approved.
# Card meshes and materials are per-call resources so callers can own or edit them safely.
extends RefCounted

const CATALOG_PATH := "res://assets/landscape/trees/catalog.json"
const FORMAT := "openrc-tree-assets v1"
const ATLAS_SIZE_PX := 1024
const TILE_SIZE_PX := 512
const ALPHA_CUTOFF := 0.5
const SPECIES_RECTS := {
	"CommonTree_1": [0, 0, 512, 512],
	"CommonTree_3": [512, 0, 512, 512],
	"Pine_1": [0, 512, 512, 512],
}


## Result: {ok: bool, errors: PackedStringArray, catalog: Dictionary}. The returned catalog is freshly parsed.
static func catalog() -> Dictionary:
	var errors := PackedStringArray()
	if not FileAccess.file_exists(CATALOG_PATH):
		return _catalog_failure("cannot read %s" % CATALOG_PATH)
	var json := JSON.new()
	var text := FileAccess.get_file_as_string(CATALOG_PATH)
	if json.parse(text) != OK:
		return _catalog_failure("%s: JSON error at line %d: %s" % [CATALOG_PATH, json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _catalog_failure("%s: top level must be an object" % CATALOG_PATH)
	var raw: Dictionary = json.data
	if raw.get("format") != FORMAT:
		errors.append("format must be '%s'" % FORMAT)
	if raw.get("atlas") != "res://assets/landscape/trees/atlas.png":
		errors.append("atlas must be res://assets/landscape/trees/atlas.png")
	if raw.get("atlas_size_px") != ATLAS_SIZE_PX:
		errors.append("atlas_size_px must be %d" % ATLAS_SIZE_PX)
	if raw.get("tile_size_px") != TILE_SIZE_PX:
		errors.append("tile_size_px must be %d" % TILE_SIZE_PX)
	var cutoff: Variant = raw.get("alpha_cutoff")
	if not _is_number(cutoff) or not is_finite(float(cutoff)) or absf(float(cutoff) - ALPHA_CUTOFF) > 0.000001:
		errors.append("alpha_cutoff must be %s" % ALPHA_CUTOFF)

	var species_value: Variant = raw.get("species")
	if typeof(species_value) != TYPE_ARRAY:
		errors.append("species must be an array")
		return { ok = false, errors = errors, catalog = {} }
	var seen := {}
	for index in species_value.size():
		var entry_value: Variant = species_value[index]
		if typeof(entry_value) != TYPE_DICTIONARY:
			errors.append("species[%d] must be an object" % index)
			continue
		var entry: Dictionary = entry_value
		var id_value: Variant = entry.get("id")
		if typeof(id_value) != TYPE_STRING or not SPECIES_RECTS.has(id_value):
			errors.append("species[%d].id is unknown" % index)
			continue
		var id: String = id_value
		if seen.has(id):
			errors.append("duplicate species id '%s'" % id)
			continue
		seen[id] = true
		if entry.has("scene"):
			errors.append("%s.scene is not part of the L6a card catalog" % id)
		var frame_size: Variant = entry.get("frame_size_m")
		if not _is_number(frame_size) or not is_finite(float(frame_size)) or float(frame_size) <= 0.0:
			errors.append("%s.frame_size_m must be a finite positive number" % id)
		var pivot_y: Variant = entry.get("pivot_y_m")
		if not _is_number(pivot_y) or not is_finite(float(pivot_y)) or absf(float(pivot_y) - 0.5) > 0.000001:
			errors.append("%s.pivot_y_m must be 0.5 m" % id)
		if not _matches_rect(entry.get("atlas_rect_px"), SPECIES_RECTS[id]):
			errors.append("%s.atlas_rect_px must be %s" % [id, SPECIES_RECTS[id]])
	for id in SPECIES_RECTS:
		if not seen.has(id):
			errors.append("missing species '%s'" % id)
	if not errors.is_empty():
		return { ok = false, errors = errors, catalog = {} }
	return { ok = true, errors = PackedStringArray(), catalog = raw }


## Makes a lit, alpha-scissored three-plane card. Unknown IDs or invalid/missing assets return null.
## The caller owns the MeshInstance3D and must disable its shadow casting when placing a card.
static func card_mesh(id: String) -> ArrayMesh:
	var result := catalog()
	if not result.ok:
		return null
	var entry := _species_entry(result.catalog, id)
	if entry.is_empty():
		return null
	var texture := load(String(result.catalog.atlas)) as Texture2D
	if texture == null:
		return null

	var frame_size := float(entry.frame_size_m)
	var rect: Array = entry.atlas_rect_px
	var atlas_size := float(result.catalog.atlas_size_px)
	var inset := 0.5 / atlas_size
	var u_min := float(rect[0]) / atlas_size + inset
	var v_min := float(rect[1]) / atlas_size + inset
	var u_max := float(rect[0] + rect[2]) / atlas_size - inset
	var v_max := float(rect[1] + rect[3]) / atlas_size - inset
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var bottom_y := float(entry.pivot_y_m) - frame_size * 0.5
	var top_y := float(entry.pivot_y_m) + frame_size * 0.5
	for plane in 3:
		var angle := deg_to_rad(float(plane) * 60.0)
		var plane_basis := Basis(Vector3.UP, angle)
		var base := vertices.size()
		var corners := [
			Vector3(-frame_size * 0.5, bottom_y, 0.0),
			Vector3(frame_size * 0.5, bottom_y, 0.0),
			Vector3(frame_size * 0.5, top_y, 0.0),
			Vector3(-frame_size * 0.5, top_y, 0.0),
		]
		for corner: Vector3 in corners:
			vertices.append(plane_basis * corner)
		var normal := plane_basis * Vector3.BACK
		for _corner in 4:
			normals.append(normal)
		uvs.append(Vector2(u_min, v_max))
		uvs.append(Vector2(u_max, v_max))
		uvs.append(Vector2(u_max, v_min))
		uvs.append(Vector2(u_min, v_min))
		# Clockwise seen from +Z, matching the +Z normal: Godot's front faces are clockwise. The old counter-clockwise
		# order gave the visible side a normal pointing away from the viewer (front-lit trees rendered dark; report 02).
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _card_material(texture))
	return mesh


static func _catalog_failure(message: String) -> Dictionary:
	return { ok = false, errors = PackedStringArray([message]), catalog = {} }


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _matches_rect(value: Variant, expected: Array) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 4:
		return false
	for index in 4:
		if not _is_number(value[index]) or not is_finite(float(value[index])) or float(value[index]) != float(expected[index]):
			return false
	return true


static func _species_entry(data: Dictionary, id: String) -> Dictionary:
	if not SPECIES_RECTS.has(id):
		return {}
	for value: Variant in data.species:
		var entry: Dictionary = value
		if entry.id == id:
			return entry
	return {}


static func _card_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = ALPHA_CUTOFF
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.metallic = 0.0
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material
