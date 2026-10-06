# L6a: the baked Quaternius card catalog, atlas, geometry and material obey the runtime asset contract.
# Run: godot --headless --path . --script res://tests/test_tree_assets.gd
extends SceneTree

const Trees := preload("res://render/tree_assets.gd")

const EXPECTED := {
	"CommonTree_1": { "rect": [0, 0, 512, 512] },
	"CommonTree_3": { "rect": [512, 0, 512, 512] },
	"Pine_1": { "rect": [0, 512, 512, 512] },
}
const ALPHA_CUTOFF := 0.5

var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if condition:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var loaded := Trees.catalog()
	_check("catalog loads and validates", loaded.ok, str(loaded.errors))
	if not loaded.ok:
		print("%d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	var data: Dictionary = loaded.catalog
	_check("catalog format is openrc-tree-assets v1", data.format == "openrc-tree-assets v1")
	_check("catalog covers exactly the three baked species", data.species.size() == EXPECTED.size(), str(data.species.size()))
	_check("catalog atlas is 1024 square with 512 tiles", data.atlas_size_px == 1024 and data.tile_size_px == 512)
	_check("catalog alpha cutoff is 0.5", is_equal_approx(float(data.alpha_cutoff), ALPHA_CUTOFF), str(data.alpha_cutoff))
	for id in EXPECTED:
		var entry := _entry(data, id)
		_check("catalog includes " + id, not entry.is_empty())
		if entry.is_empty():
			continue
		_check(id + " uses its canonical atlas slot", _rect_matches(entry.atlas_rect_px, EXPECTED[id].rect), str(entry.atlas_rect_px))
		_check(id + " has a positive frame size and 0.5 m pivot", float(entry.frame_size_m) > 0.0 and is_equal_approx(float(entry.pivot_y_m), 0.5))
		_check(id + " catalog entry has no runtime scene reference", not entry.has("scene"))

	var opaque_base_rows := _test_atlas(data)
	_test_cards(data, opaque_base_rows)
	_test_unknown_ids()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_atlas(data: Dictionary) -> Dictionary:
	var atlas := load(String(data.atlas)) as Texture2D
	_check("atlas loads as a texture", atlas != null)
	if atlas == null:
		return {}
	_check("atlas dimensions match catalog", atlas.get_width() == 1024 and atlas.get_height() == 1024,
		"%dx%d" % [atlas.get_width(), atlas.get_height()])
	var image := atlas.get_image()
	_check("atlas import has mipmaps", image != null and image.has_mipmaps())
	if image == null:
		return {}
	var alpha_present := {}
	var opaque_present := {}
	var lowest_opaque_y := {}
	for id in EXPECTED:
		alpha_present[id] = false
		opaque_present[id] = false
		lowest_opaque_y[id] = -1
	for id in EXPECTED:
		var rect: Array = EXPECTED[id].rect
		for y in range(rect[1], rect[1] + rect[3]):
			for x in range(rect[0], rect[0] + rect[2]):
				var alpha := image.get_pixel(x, y).a
				if alpha < ALPHA_CUTOFF:
					alpha_present[id] = true
				elif alpha >= ALPHA_CUTOFF:
					opaque_present[id] = true
					lowest_opaque_y[id] = maxi(int(lowest_opaque_y[id]), y)
	for id in EXPECTED:
		_check(id + " atlas tile contains transparent pixels", alpha_present[id])
		_check(id + " atlas tile contains opaque pixels", opaque_present[id])
	return lowest_opaque_y


func _test_cards(data: Dictionary, opaque_base_rows: Dictionary) -> void:
	for id in EXPECTED:
		var mesh := Trees.card_mesh(id)
		_check(id + " card mesh builds", mesh != null)
		if mesh == null:
			continue
		_check(id + " card has exactly one surface", mesh.get_surface_count() == 1, str(mesh.get_surface_count()))
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		_check(id + " three crossed quads have six triangles", vertices.size() == 12 and indices.size() == 18,
			"%d vertices, %d indices" % [vertices.size(), indices.size()])
		var entry := _entry(data, id)
		var frame_size := float(entry.frame_size_m)
		var pivot_y := float(entry.pivot_y_m)
		var expected_bottom_y := pivot_y - frame_size * 0.5
		var expected_top_y := pivot_y + frame_size * 0.5
		var bounds := mesh.get_aabb()
		_check(id + " card frame is centered on its catalog pivot", absf(bounds.position.y - expected_bottom_y) < 0.00001
			and absf(bounds.end.y - expected_top_y) < 0.00001 and absf(bounds.size.x - frame_size) < 0.00001,
			str(bounds))
		var rect: Array = entry.atlas_rect_px
		var atlas_size := float(data.atlas_size_px)
		var lowest_opaque_y: int = int(opaque_base_rows.get(id, -1))
		var sampled_base_y := INF
		if lowest_opaque_y >= rect[1]:
			var tile_v_bottom := (float(rect[1] + rect[3]) - 0.5) / atlas_size
			var tile_v_top := (float(rect[1]) + 0.5) / atlas_size
			var opaque_sample_v := (float(lowest_opaque_y) + 0.5) / atlas_size
			var height_fraction := (tile_v_bottom - opaque_sample_v) / (tile_v_bottom - tile_v_top)
			sampled_base_y = expected_bottom_y + frame_size * height_fraction
		_check(id + " lowest sampled opaque atlas row maps to ground within one texel", lowest_opaque_y >= rect[1]
			and absf(sampled_base_y) <= frame_size / float(rect[3]), "row=%d maps to y=%.6f m" % [lowest_opaque_y, sampled_base_y])
		_check(id + " bounds include all three rotated planes", absf(bounds.size.z - frame_size * sqrt(3.0) * 0.5) < 0.0001,
			str(bounds.size))
		_check(id + " card repeats full tile UVs with half-texel inset", _uvs_match_tile(uvs, entry.atlas_rect_px, data.atlas_size_px), str(uvs))
		var material := mesh.surface_get_material(0) as StandardMaterial3D
		_check(id + " card material uses lit alpha scissor at 0.5", material != null
			and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			and is_equal_approx(material.alpha_scissor_threshold, ALPHA_CUTOFF)
			and material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED)
		_check(id + " card material is two-sided, nonmetallic and fully rough", material != null
			and material.cull_mode == BaseMaterial3D.CULL_DISABLED and absf(material.metallic) < 0.000001
			and absf(material.roughness - 1.0) < 0.000001)
		_check(id + " card material uses anisotropic mip filtering and the atlas", material != null
			and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			and material.albedo_texture != null and material.albedo_texture.get_width() == 1024
			and material.albedo_texture.get_height() == 1024)
		var second := Trees.card_mesh(id)
		_check(id + " card mesh and material are per-call resources", second != null and second != mesh
			and second.surface_get_material(0) != mesh.surface_get_material(0))


func _test_unknown_ids() -> void:
	_check("unknown card ID fails without a fallback", Trees.card_mesh("tree_missing") == null)


func _uvs_match_tile(uvs: PackedVector2Array, rect: Array, atlas_size_value: Variant) -> bool:
	if uvs.size() != 12:
		return false
	var atlas_size := float(atlas_size_value)
	var u_min := (float(rect[0]) + 0.5) / atlas_size
	var v_min := (float(rect[1]) + 0.5) / atlas_size
	var u_max := (float(rect[0] + rect[2]) - 0.5) / atlas_size
	var v_max := (float(rect[1] + rect[3]) - 0.5) / atlas_size
	for uv in uvs:
		if not (is_equal_approx(uv.x, u_min) or is_equal_approx(uv.x, u_max)):
			return false
		if not (is_equal_approx(uv.y, v_min) or is_equal_approx(uv.y, v_max)):
			return false
	return true


func _entry(data: Dictionary, id: String) -> Dictionary:
	for entry_value: Variant in data.species:
		var entry: Dictionary = entry_value
		if entry.get("id") == id:
			return entry
	return {}


func _rect_matches(value: Variant, expected: Array) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 4:
		return false
	for index in 4:
		if (typeof(value[index]) != TYPE_INT and typeof(value[index]) != TYPE_FLOAT) or float(value[index]) != float(expected[index]):
			return false
	return true

