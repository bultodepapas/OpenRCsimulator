extends SceneTree

const CustomPaint := preload("res://aircraft/custom_skin.gd")
const Registry := preload("res://aircraft/model_registry.gd")
const Builder := preload("res://render/airplane.gd")
const Preview := preload("res://ui/home_preview_resources.gd")
const Preferences := preload("res://app_state/preferences.gd")
const Manifest := preload("res://aircraft/model_manifest.gd")
const X8 := "skywalker-x8"

var checks := 0
var failed := 0
var fixtures: Array[String] = []
var nonce := ""

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed: failed += 1
	print(("PASS " if passed else "FAIL ") + label)

func _initialize() -> void:
	_run.call_deferred()

func _zip(name: String, manifest: Dictionary, extra: Dictionary = {}, raw_manifest := "") -> String:
	var path := "user://skin-test-%s-%s.orskin" % [nonce, name]
	fixtures.append(path)
	var zip := ZIPPacker.new()
	if zip.open(path) != OK: return ""
	zip.start_file("manifest.json")
	zip.write_file((JSON.stringify(manifest) if raw_manifest.is_empty() else raw_manifest).to_utf8_buffer())
	zip.close_file()
	for filename in extra:
		zip.start_file(filename)
		zip.write_file(extra[filename])
		zip.close_file()
	zip.close()
	return path

func _manifest(base_hash: String) -> Dictionary:
	return {format = "openrc-skin", version = 1, aircraft_id = X8, base_asset_sha256 = base_hash,
		label = "Paint test " + nonce, materials = [{name = "x8_livery", base_color = [0.25, 0.5, 0.75, 1.0], texture = "paint.png"}]}

func _png() -> PackedByteArray:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.8, 0.3, 1.0))
	return image.save_png_to_buffer()

func _material(root_node: Node, name: String) -> Dictionary:
	for node: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.get_active_material(surface)
			if mat != null and mat.resource_name == name:
				return {node = mesh_node, surface = surface, material = mat}
	return {}

func _run() -> void:
	nonce = "%d-%d" % [Time.get_ticks_usec(), randi()]
	CustomPaint._root = "user://skin-test-%s/" % nonce
	var stock: Dictionary = Registry.describe(X8)
	_check("stock model is verified", stock.get("ok", false))
	if not stock.get("ok", false):
		_finish()
		return
	var base_hash: String = stock.manifest.asset.sha256
	var png := _png()
	var manifest := _manifest(base_hash)
	var path := _zip("valid", manifest, {"paint.png": png})
	var original := FileAccess.get_file_as_bytes(path)
	var result: Dictionary = CustomPaint.import_file(path, X8)
	_check("valid paint imports", result.get("ok", false))
	if not result.get("ok", false):
		print("Import errors: ", result.get("errors", []))
		_finish()
		return
	var id: String = result.id
	var stored := CustomPaint._path_for(X8, id)
	_check("stable ID fits existing preferences", CustomPaint.is_custom_id(id) and Manifest.is_livery_id(id))
	_check("archive stored with exact source bytes", FileAccess.get_file_as_bytes(stored) == original)
	_check("reimport is idempotent", CustomPaint.import_file(path, X8).get("id", "") == id)
	var choices := Builder.livery_choices(X8)
	_check("custom paint is available through the existing choices", choices.any(func(row: Dictionary) -> bool: return row.id == id and row.label == manifest.label))
	_check("custom choice resolves and unknown choice falls back", Builder.resolve_livery_choice(choices, id) == id and Builder.resolve_livery_choice(choices, "missing") == "")
	_check("custom preview preloads the verified default asset", Preview.path_for(X8, id) == stock.manifest.asset.path)
	_check("unrelated aircraft does not support paint", not CustomPaint.supports("f4u-corsair-250") and CustomPaint.choices("f4u-corsair-250").is_empty())
	var prefs := Preferences.DEFAULTS.duplicate(true)
	prefs.liveries = {X8: id}
	var pref_path := "user://skin-test-%s.cfg" % nonce
	fixtures.append(pref_path)
	_check("custom selection saves and reloads", Preferences.save_to(pref_path, prefs) == OK and Preferences.load_from(pref_path).liveries.get(X8, "") == id)
	var default_plane: Dictionary = Builder.build(X8)
	var painted_plane: Dictionary = Builder.build(X8, NAN, {}, id)
	var stock_orange := Color()
	_check("custom build succeeds", not painted_plane.is_empty())
	if not default_plane.is_empty() and not painted_plane.is_empty():
		var original_mat := _material(default_plane.root, "x8_livery")
		var painted_mat := _material(painted_plane.root, "x8_livery")
		_check("material binding is present", not original_mat.is_empty() and not painted_mat.is_empty())
		if not original_mat.is_empty() and not painted_mat.is_empty():
			var a := original_mat.material as StandardMaterial3D
			var b := painted_mat.material as StandardMaterial3D
			_check("paint duplicates the material and replaces only base color/texture", a != b and b.albedo_color.is_equal_approx(Color(0.25, 0.5, 0.75, 1.0).linear_to_srgb()) and b.albedo_texture != a.albedo_texture and b.normal_texture == a.normal_texture and b.roughness_texture == a.roughness_texture and b.roughness == a.roughness and b.metallic == a.metallic)
			_check("custom texture has mipmaps", b.albedo_texture.get_image().has_mipmaps())
			_check("stock scene and shared mesh remain untouched", original_mat.node.get_surface_override_material(original_mat.surface) == null and original_mat.node.mesh == painted_mat.node.mesh)
		_check("stock asset and binding identity remain unchanged", painted_plane.root.get_meta("asset_sha256") == base_hash and painted_plane.root.get_meta("livery") == default_plane.root.get_meta("livery") and painted_plane.model_manifest_sha256 == default_plane.model_manifest_sha256 and painted_plane.custom_skin.id == id)
		stock_orange = _material(default_plane.root, "x8_orange").material.albedo_color
	if not default_plane.is_empty(): default_plane.root.free()
	if not painted_plane.is_empty(): painted_plane.root.free()
	var solid_manifest := manifest.duplicate(true)
	solid_manifest.materials[0].erase("texture")
	solid_manifest.materials.append({name = "x8_orange", base_color = [0.95, 0.3, 0.02, 1.0]})
	var solid_result: Dictionary = CustomPaint.import_file(_zip("solid", solid_manifest), X8)
	_check("solid-color paint imports without a PNG", solid_result.get("ok", false))
	if solid_result.get("ok", false):
		var solid_plane: Dictionary = Builder.build(X8, NAN, {}, solid_result.id)
		var solid_material := _material(solid_plane.root, "x8_livery") if not solid_plane.is_empty() else {}
		_check("solid color clears the stock base-color texture", not solid_material.is_empty() and solid_material.material.albedo_texture == null)
		var solid_orange := _material(solid_plane.root, "x8_orange") if not solid_plane.is_empty() else {}
		_check("linear GLB factor round-trips to the imported Godot color", not solid_orange.is_empty() and solid_orange.material.albedo_color.is_equal_approx(stock_orange))
		if not solid_plane.is_empty(): solid_plane.root.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomPaint._path_for(X8, solid_result.id)))

	var bad := manifest.duplicate(true)
	bad.aircraft_id = "f4u-corsair-250"
	_check("foreign aircraft rejected", not CustomPaint.import_file(_zip("foreign", bad, {"paint.png": png}), X8).ok)
	bad = manifest.duplicate(true)
	bad.base_asset_sha256 = "0".repeat(64)
	_check("foreign model version rejected", not CustomPaint.import_file(_zip("hash", bad, {"paint.png": png}), X8).ok)
	bad = manifest.duplicate(true)
	bad.materials[0].name = "unknown"
	_check("unknown material rejected", not CustomPaint.import_file(_zip("unknown", bad, {"paint.png": png}), X8).ok)
	bad = manifest.duplicate(true)
	bad.materials.append(bad.materials[0].duplicate(true))
	_check("duplicate material rejected", not CustomPaint.import_file(_zip("duplicate", bad, {"paint.png": png}), X8).ok)
	bad = manifest.duplicate(true)
	bad.materials[0].base_color[0] = 1.01
	_check("out of range color rejected", not CustomPaint.import_file(_zip("color", bad, {"paint.png": png}), X8).ok)
	bad = manifest.duplicate(true)
	bad.geometry = "foreign.glb"
	_check("unsupported manifest field rejected", not CustomPaint.import_file(_zip("geometry", bad, {"paint.png": png}), X8).ok)
	bad = manifest.duplicate(true)
	bad.label = "x".repeat(49)
	_check("oversized label rejected", not CustomPaint.import_file(_zip("label", bad, {"paint.png": png}), X8).ok)
	bad = manifest.duplicate(true)
	bad.materials[0].texture = "../paint.png"
	_check("unsafe texture path rejected", not CustomPaint.import_file(_zip("traversal", bad, {"../paint.png": png}), X8).ok)
	_check("unreferenced payload rejected", not CustomPaint.import_file(_zip("extra", manifest, {"paint.png": png, "payload.gd": "bad".to_utf8_buffer()}), X8).ok)
	_check("missing PNG rejected", not CustomPaint.import_file(_zip("missing", manifest), X8).ok)
	var too_wide := png.duplicate()
	too_wide[16] = 0
	too_wide[17] = 0
	too_wide[18] = 16
	too_wide[19] = 1
	_check("oversized PNG dimensions rejected before decoding", not CustomPaint.import_file(_zip("wide", manifest, {"paint.png": too_wide}), X8).ok)
	var compressed_metadata := png.duplicate()
	var metadata := PackedByteArray([0, 0, 0, 0, 105, 67, 67, 80, 0, 0, 0, 0])
	compressed_metadata = compressed_metadata.slice(0, 33) + metadata + compressed_metadata.slice(33)
	_check("compressed PNG metadata rejected before decoding", not CustomPaint.import_file(_zip("png-metadata", manifest, {"paint.png": compressed_metadata}), X8).ok)
	var raw := JSON.stringify(manifest)
	raw = raw.insert(1, '"format":"openrc-skin",')
	_check("duplicate JSON keys rejected", not CustomPaint.import_file(_zip("duplicate-keys", manifest, {"paint.png": png}, raw), X8).ok)
	var damaged := original.duplicate()
	var end := damaged.size() - 22
	var directory_offset := damaged.decode_u32(end + 16)
	damaged.encode_u32(directory_offset + 24, CustomPaint.PNG_LIMIT + 1)
	var bomb_path := "user://skin-test-%s-bomb.orskin" % nonce
	fixtures.append(bomb_path)
	var file := FileAccess.open(bomb_path, FileAccess.WRITE)
	file.store_buffer(damaged)
	file.close()
	_check("forged expanded ZIP size rejected", not CustomPaint.import_file(bomb_path, X8).ok)
	var target := FileAccess.open(stored, FileAccess.WRITE)
	target.store_buffer("tampered".to_utf8_buffer())
	target.close()
	_check("tampered installed paint is not offered", not CustomPaint.choices(X8).any(func(row: Dictionary) -> bool: return row.id == id))
	var unpainted: Dictionary = Builder.build(X8)
	if not unpainted.is_empty():
		var before := _material(unpainted.root, "x8_livery")
		var apply_result := CustomPaint.apply(X8, id, base_hash, unpainted.root)
		var after := _material(unpainted.root, "x8_livery")
		_check("failed application leaves surfaces unchanged", not apply_result.ok and before.material == after.material and after.node.get_surface_override_material(after.surface) == null)
		unpainted.root.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stored))
	var dummy_paths: Array[String] = []
	for index in CustomPaint.INSTALLED_LIMIT:
		var dummy_id := "custom_" + ("%024x" % (index + 1))
		var dummy := CustomPaint._path_for(X8, dummy_id)
		dummy_paths.append(dummy)
		var dummy_file := FileAccess.open(dummy, FileAccess.WRITE)
		dummy_file.store_string("placeholder")
		dummy_file.close()
	_check("installation refuses an overfull directory", not CustomPaint.import_file(path, X8).ok)
	for dummy in dummy_paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(dummy))
	_finish()

func _finish() -> void:
	for path in fixtures:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomPaint._root + X8))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomPaint._root))
	CustomPaint._root = CustomPaint.ROOT
	print("Custom skin: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)


