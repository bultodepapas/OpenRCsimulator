extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Skins := preload("res://aircraft/custom_skin.gd")
const Builder := preload("res://render/airplane.gd")
const ProceduralSkin := preload("res://aircraft/procedural_skin.gd")
const ElectricSkin := preload("res://aircraft/stik_electric_skin.gd")
const TIMBER := "turbo-lumber-evolution"
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
	_test_paint_identity_guards(ids)
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
		var painted_material: WeakRef
		check(id + " builds stock and custom", not stock.is_empty() and not painted.is_empty())
		if not stock.is_empty() and not painted.is_empty():
			root.add_child(stock.root)
			root.add_child(painted.root)
			await process_frame
			await process_frame
			check(id + " selected identity retained", painted.get("custom_skin", {}).get("id") == imported.id)
			if not Catalog.is_rotorcraft(id):
				var had_asset_identity: bool = stock.root.has_meta("asset_sha256")
				var same_asset_identity: bool = painted.root.has_meta("asset_sha256") == had_asset_identity
				if had_asset_identity and same_asset_identity:
					same_asset_identity = painted.root.get_meta("asset_sha256") == stock.root.get_meta("asset_sha256")
				check(id + " preserves stock asset identity", same_asset_identity)
			_compare(id, stock.root, painted.root, spec)
			if id == TIMBER:
				painted_material = _timber_paint_ref(painted.root)
		if painted.get("root") is Node:
			if id == TIMBER: painted.root.free()
			else: _free_children_first(painted.root)
		if stock.get("root") is Node:
			if id == TIMBER: stock.root.free()
			else: _free_children_first(stock.root)
		if id == TIMBER:
			check("Timber custom paint is released with its model", painted_material != null and painted_material.get_ref() == null)
		await process_frame
	if ids.has(TIMBER):
		_test_timber_material_lifetime()
	for id: String in packages:
		var other := "moonrunner-x99" if id != "moonrunner-x99" else "xcell-60-research"
		check(id + " rejects wrong family", not Skins.import_file(packages[id], other).get("ok", false))
	for path: String in paths:
		DirAccess.remove_absolute(path)
	for id: String in ids:
		DirAccess.remove_absolute(Skins._root + Skins.family(id))
	DirAccess.remove_absolute(Skins._root)
	Skins._root = Skins.ROOT
	print("Skin fleet: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _test_paint_identity_guards(ids: PackedStringArray) -> void:
	for pair: Array in [
		[ProceduralSkin.STIK, Skins.STIK_LEGACY_PAINT_IDENTITY, Skins.STIK_CURRENT_PAINT_IDENTITY],
		[ProceduralSkin.EXTRA, Skins.EXTRA_LEGACY_PAINT_IDENTITY, Skins.EXTRA_CURRENT_PAINT_IDENTITY],
	]:
		var family: String = pair[0]
		if not ids.has(family): continue
		var legacy: String = pair[1]
		var current: String = pair[2]
		check(family + " has the reviewed live paint identity", ProceduralSkin.identity(family) == current)
		check(family + " admits the reviewed template pair", Skins._compatible_paint_template(family, legacy, current))
		check(family + " rejects another template identity", not Skins._compatible_paint_template(family, "0".repeat(64), current))
		check(family + " rejects another live identity", not Skins._compatible_paint_template(family, legacy, "0".repeat(64)))
		check(family + " rejects the pair for another family", not Skins._compatible_paint_template(ElectricSkin.FAMILY, legacy, current))
		var spec := Skins.kit(family)
		if not spec.is_empty():
			var saved: String = spec.stock_sha256
			spec.stock_sha256 = "0".repeat(64)
			check(family + " rejects a changed kit identity", Skins.base_identity(family).is_empty())
			spec.stock_sha256 = saved
			check(family + " accepts the restored kit identity", Skins.base_identity(family) == saved)
	if ids.has(ElectricSkin.FAMILY):
		var spec := Skins.kit(ElectricSkin.FAMILY)
		check("electric paint binds its own verified model", not spec.is_empty() and ElectricSkin.identity(ElectricSkin.FAMILY) == spec.get("stock_sha256", ""))
		check("electric paint rejects the Stik family", ElectricSkin.identity(ProceduralSkin.STIK).is_empty())
		check("electric adapter rejects an unrelated family", not ElectricSkin.prepare(ProceduralSkin.STIK, null).ok)
		if not spec.is_empty():
			var saved: String = spec.stock_sha256
			spec.stock_sha256 = "0".repeat(64)
			check("electric paint rejects a changed kit identity", Skins.base_identity(ElectricSkin.FAMILY).is_empty())
			spec.stock_sha256 = saved
			check("electric paint accepts the restored kit identity", Skins.base_identity(ElectricSkin.FAMILY) == saved)


func _timber_paint_ref(model: Node3D) -> WeakRef:
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_surface_override_material(surface)
			if material != null and material.resource_name.begins_with("openrc-paint-"):
				check("Timber custom paint is retained by its mesh", (mesh.get_meta("_timber_override_materials", []) as Array).has(material))
				return weakref(material)
	check("Timber custom paint exists", false)
	return null


func _guarded_overrides(mesh: MeshInstance3D) -> bool:
	var retained: Array = mesh.get_meta("_timber_override_materials", [])
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.get_surface_override_material(surface)
		if material != null and not retained.has(material): return false
	return true


func _test_timber_material_lifetime() -> void:
	# Warm and rebuild without a renderer flush: the second complete tree used to
	# release its tailwheel overrides before the dirty instances were retired.
	var first: Dictionary = Builder.build(TIMBER)
	var second: Dictionary = Builder.build(TIMBER)
	var original_wheel := first.root.find_child("tailwheel", true, false) as MeshInstance3D
	var second_wheel := second.root.find_child("tailwheel", true, false) as MeshInstance3D
	check("Timber builds two distinct guarded tailwheels", original_wheel != null and second_wheel != null
		and second_wheel.mesh.get_surface_count() >= 2 and _guarded_overrides(second_wheel)
		and original_wheel.get_surface_override_material(0) != second_wheel.get_surface_override_material(0))
	var second_model: WeakRef = weakref(second.root)
	var second_material: WeakRef = weakref(second_wheel.get_surface_override_material(0))
	second.root.free()
	second.clear()
	check("whole Timber model releases its own material", second_model.get_ref() == null and second_material.get_ref() == null)
	# Wrecks duplicate/reparent pieces. The guard must follow the mesh and its
	# actual overrides, then release the material after the last piece dies.
	var copy := first.root.duplicate() as Node3D
	var copied_wheel := copy.find_child("tailwheel", true, false) as MeshInstance3D
	var copied_material: WeakRef = weakref(copied_wheel.get_surface_override_material(0))
	check("duplicated Timber mesh retains its active overrides", _guarded_overrides(copied_wheel))
	first.root.free()
	first.clear()
	check("copied Timber material survives the source", copied_material.get_ref() != null)
	copied_wheel.get_parent().remove_child(copied_wheel)
	copy.free()
	check("detached Timber wheel retains its material", copied_material.get_ref() != null and is_instance_valid(copied_wheel))
	copied_wheel.free()
	check("detached Timber material is released", copied_material.get_ref() == null)


func _free_children_first(node: Node) -> void:
	# Preserve the existing children-first fallback for other aircraft.
	for child: Node in node.get_children(): _free_children_first(child)
	node.free()


func _compare(id: String, stock: Node3D, painted: Node3D, spec: Dictionary) -> void:
	var names := {}
	for group: Dictionary in spec.paints:
		for material: String in group.materials: names[material] = 0
	var geometry_equal := true
	var transforms_equal := true
	for original: Node in stock.find_children("*", "Node3D", true, false):
		var target := painted.get_node_or_null(stock.get_path_to(original)) as Node3D
		if target == null and str(original.name).begins_with("@"):
			var parent := painted.get_node_or_null(stock.get_path_to(original.get_parent()))
			if parent != null and original.get_index() < parent.get_child_count():
				target = parent.get_child(original.get_index()) as Node3D
		if target == null:
			printerr("MISSING NODE ", id, " ", stock.get_path_to(original))
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
			geometry_equal = geometry_equal and _same_triangles(before, after)
			var material: Material = target.get_active_material(surface)
			if material != null and names.has(material.resource_name):
				names[material.resource_name] += 1
				check(id + " material is instance-owned", material != original.get_active_material(surface))
				var texture: Texture2D = material.albedo_texture if material is StandardMaterial3D else material.get_shader_parameter("paint_texture" if material.resource_name.begins_with("openrc-paint-") else "openrc_paint_texture")
				check(id + " receives the edited PNG", texture != null and texture.get_width() == 4 and texture.get_height() == 4)
	check(id + " preserves vertex positions, normals and triangles", geometry_equal)
	check(id + " preserves names, transforms and hinges", transforms_equal)
	for material: String in names:
		check(id + " applies " + material, names[material] > 0)


func _same_triangles(before: Array, after: Array) -> bool:
	var indices_a: PackedInt32Array = before[Mesh.ARRAY_INDEX] if before[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var indices_b: PackedInt32Array = after[Mesh.ARRAY_INDEX] if after[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count_a: int = indices_a.size() if not indices_a.is_empty() else before[Mesh.ARRAY_VERTEX].size()
	var count_b: int = indices_b.size() if not indices_b.is_empty() else after[Mesh.ARRAY_VERTEX].size()
	if count_a != count_b: return false
	for i in count_a:
		var a := indices_a[i] if not indices_a.is_empty() else i
		var b := indices_b[i] if not indices_b.is_empty() else i
		if before[Mesh.ARRAY_VERTEX][a] != after[Mesh.ARRAY_VERTEX][b]: return false
		if before[Mesh.ARRAY_NORMAL] != null and (before[Mesh.ARRAY_NORMAL][a] - after[Mesh.ARRAY_NORMAL][b]).length() > 0.0002: return false
	return true
