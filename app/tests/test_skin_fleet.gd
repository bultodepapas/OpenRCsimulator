extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Skins := preload("res://aircraft/custom_skin.gd")
const Builder := preload("res://render/airplane.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, value: bool) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", label)

func package(id: String, spec: Dictionary) -> String:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.8, 0.6, 1))
	var records := []
	for group: Dictionary in spec.paints:
		for material: String in group.materials:
			records.append({name = material, base_color = [1, 1, 1, 1], texture = "paint.png"})
	var manifest := {format = "openrc-skin", version = 1, aircraft_id = Skins.family(id),
		base_asset_sha256 = spec.stock_sha256, label = "Fleet paint", materials = records}
	var path := Skins._root + Skins.family(id) + ".orskin"
	var zip := ZIPPacker.new()
	if zip.open(path) != OK: return ""
	zip.start_file("manifest.json")
	zip.write_file(JSON.stringify(manifest).to_utf8_buffer())
	zip.close_file()
	zip.start_file("paint.png")
	zip.write_file(image.save_png_to_buffer())
	zip.close_file()
	zip.close()
	paths.append(path)
	return path

func _run() -> void:
	Skins._root = "user://skin-fleet-%d/" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(Skins._root)
	var requested := OS.get_cmdline_user_args()
	var ids := requested if not requested.is_empty() else Catalog.ids()
	var packages := {}
	for id: String in ids:
		var spec := Skins.kit(id)
		check(id + " has a kit", not spec.is_empty() and FileAccess.file_exists(Skins.kit_path(id)))
		if spec.is_empty(): continue
		check(id + " matches its stock identity", Skins.base_identity(id) == spec.stock_sha256)
		var path := package(id, spec)
		var imported := Skins.import_file(path, id)
		check(id + " imports", imported.get("ok", false))
		if not imported.get("ok", false):
			printerr(imported)
			continue
		paths.append(Skins._path_for(id, imported.id))
		packages[id] = path
		check(id + " resolves after import", Builder.resolve_livery(id, imported.id) == imported.id)
		var stock := Builder.build(id)
		var painted := Builder.build(id, NAN, {}, imported.id)
		check(id + " builds stock and custom", not stock.is_empty() and not painted.is_empty())
		if not stock.is_empty() and not painted.is_empty():
			check(id + " selected identity retained", painted.get("custom_skin", {}).get("id") == imported.id)
			_compare(id, stock.root, painted.root, spec)
		if stock.get("root") is Node: stock.root.free()
		if painted.get("root") is Node: painted.root.free()
		await process_frame
	for id: String in packages:
		var other := "skywalker-x8" if id != "skywalker-x8" else "xcell-60-research"
		check(id + " rejects wrong family", not Skins.import_file(packages[id], other).get("ok", false))
	for path: String in paths:
		DirAccess.remove_absolute(path)
	for id: String in ids:
		DirAccess.remove_absolute(Skins._root + Skins.family(id))
	DirAccess.remove_absolute(Skins._root)
	Skins._root = Skins.ROOT
	print("Skin fleet: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _compare(id: String, stock: Node3D, painted: Node3D, spec: Dictionary) -> void:
	var names := {}
	for group: Dictionary in spec.paints:
		for material: String in group.materials: names[material] = 0
	var geometry_equal := true
	var transforms_equal := true
	for original: Node in stock.find_children("*", "Node3D", true, false):
		var target := painted.get_node_or_null(stock.get_path_to(original)) as Node3D
		if target == null:
			transforms_equal = false
			continue
		transforms_equal = transforms_equal and target.transform.is_equal_approx(original.transform)
		if not original is MeshInstance3D or original.mesh == null: continue
		if not target is MeshInstance3D or target.mesh == null or target.mesh.get_surface_count() != original.mesh.get_surface_count():
			geometry_equal = false
			continue
		for surface in original.mesh.get_surface_count():
			var before: Array = original.mesh.surface_get_arrays(surface)
			var after: Array = target.mesh.surface_get_arrays(surface)
			for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_INDEX]:
				geometry_equal = geometry_equal and before[channel] == after[channel]
			var material: Material = target.get_active_material(surface)
			if material != null and names.has(material.resource_name):
				names[material.resource_name] += 1
				check(id + " material is instance-owned", material != original.get_active_material(surface))
	check(id + " preserves vertex positions, normals and triangles", geometry_equal)
	check(id + " preserves names, transforms and hinges", transforms_equal)
	for material: String in names:
		check(id + " applies " + material, names[material] > 0)

