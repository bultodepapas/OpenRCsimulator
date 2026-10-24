# LU-21: verify optimized population GLBs, shared PBR data, catalog fitting, and batching.
# Run after all six distinct population sources have been installed:
#   godot --headless --path . --script res://tests/test_landscape_population_assets.gd
extends SceneTree

const FieldLoader = preload("res://data/field_loader.gd")
const Loader = preload("res://scenery/scenery_loader.gd")
const Models = preload("res://scenery/models.gd")
const Population = preload("res://scenery/population.gd")
const Scenery = preload("res://scenery/scenery.gd")
const ShaderClock = preload("res://render/shader_clock.gd")

const CAR_ASSETS := ["sedan", "hatch", "crossover"]
const HUMAN_ASSETS := ["standing", "sitting", "pilot"]
const EXPECTED_CAR_IDS := ["car_sedan", "car_hatch", "car_suv", "car_sport"]
const EXPECTED_HUMAN_IDS := ["person_standing", "person_sitting", "person_pilot", "person_working"]
const CAR_TRIANGLE_LIMIT := 30000
const HUMAN_TRIANGLE_LIMIT := 8000
## SC-HUM-01: pilots also hold the owner's transmitter (plan §7 allows up to 3k; the T12D ships at about 1.1k).
const TRANSMITTER_TRIANGLE_ALLOWANCE := 1200

var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ShaderClock.register()
	_test_catalog_mapping()
	var source_assets := {}
	for asset: String in CAR_ASSETS:
		source_assets[asset] = true
	# SC-HUM-07: every shipped outfit variant ("<pose>/<outfit>") is a separate source asset.
	for asset: String in Population.human_assets():
		source_assets[asset] = true
	for asset: String in source_assets:
		_test_source_asset(asset)
	_test_shared_human_textures()
	var field_result: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var loaded: Dictionary = Loader.load_from(Loader.DEFAULT_PATH, field_result.field)
	_check("default population layout validates", loaded.get("ok", false), str(loaded.get("errors", [])))
	if loaded.get("ok", false):
		_test_production_batches(field_result.field, loaded.scenery)
	print("all population asset checks passed" if _failures == 0 else "%d population asset checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_catalog_mapping() -> void:
	var source_styles: Dictionary = {}
	var expected_sources := {
		"car_sedan": "sedan", "car_hatch": "hatch", "car_suv": "crossover", "car_sport": "hatch",
	}
	for id: String in EXPECTED_CAR_IDS:
		var asset := str(Population.ASSETS.get(id, ""))
		source_styles[asset] = true
		_check("%s maps to a population vehicle source" % id,
			Models.CATALOG.has(id) and Population.handles(id) and asset == str(expected_sources[id]), asset)
	_check("four legacy vehicle IDs use the three reviewed body styles",
		source_styles.size() == 3 and source_styles.has("sedan")
		and source_styles.has("hatch") and source_styles.has("crossover"), str(source_styles.keys()))
	for id: String in EXPECTED_HUMAN_IDS:
		var asset := id.trim_prefix("person_")
		_check("%s maps to a population person source" % id,
			Population.ASSETS.has(id) and Population.handles(id)
			and str(Population.ASSETS.get(id, "")) == asset, str(Population.ASSETS.get(id, "missing")))


func _triangle_count(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var indices: int = mesh.surface_get_array_index_len(surface)
		var vertices: int = mesh.surface_get_array_len(surface)
		total += (indices if indices > 0 else vertices) / 3
	return total


func _collect_scene(node: Node, parent_xf: Transform3D, parts: Array[Dictionary], flags: Dictionary) -> void:
	var xf: Transform3D = parent_xf * node.transform if node is Node3D else parent_xf
	if node is Skeleton3D or node is AnimationPlayer or node is AnimationTree:
		flags.rig_or_animation = true
	if node.get_script() != null or node.is_processing():
		flags.runtime_behavior = true
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		parts.append({mesh = (node as MeshInstance3D).mesh, transform = xf})
	for child: Node in node.get_children():
		_collect_scene(child, xf, parts, flags)


func _inspect_mesh_data(asset: String, parts: Array[Dictionary]) -> void:
	var triangle_total := 0
	var surfaces := 0
	var textured_surfaces := 0
	var missing_uv := 0
	var missing_normals := 0
	var non_unit_normals := 0
	for part: Dictionary in parts:
		var mesh: Mesh = part.mesh
		triangle_total += _triangle_count(mesh)
		for surface in mesh.get_surface_count():
			surfaces += 1
			var arrays: Array = mesh.surface_get_arrays(surface)
			var vertex_value: Variant = arrays[Mesh.ARRAY_VERTEX]
			var normal_value: Variant = arrays[Mesh.ARRAY_NORMAL]
			var uv_value: Variant = arrays[Mesh.ARRAY_TEX_UV]
			var vertices: PackedVector3Array = vertex_value if vertex_value is PackedVector3Array else PackedVector3Array()
			var normals: PackedVector3Array = normal_value if normal_value is PackedVector3Array else PackedVector3Array()
			var uvs: PackedVector2Array = uv_value if uv_value is PackedVector2Array else PackedVector2Array()
			if normals.size() != vertices.size() or normals.is_empty():
				missing_normals += 1
			else:
				for normal: Vector3 in normals:
					if absf(normal.length() - 1.0) > 0.03:
						non_unit_normals += 1
			var material := mesh.surface_get_material(surface)
			var textured := false
			if material is StandardMaterial3D:
				var standard := material as StandardMaterial3D
				textured = standard.albedo_texture != null or standard.normal_enabled
			elif material is ShaderMaterial:
				textured = (material as ShaderMaterial).get_shader_parameter("base_texture") != null
			if textured:
				textured_surfaces += 1
				if uvs.size() != vertices.size():
					missing_uv += 1
	var is_car := CAR_ASSETS.has(asset)
	var limit := CAR_TRIANGLE_LIMIT if is_car else HUMAN_TRIANGLE_LIMIT
	if Population.pose_of(asset) == "pilot":
		limit += TRANSMITTER_TRIANGLE_ALLOWANCE
	_check("%s stays within its source triangle cap (%d <= %d)" % [asset, triangle_total, limit],
		triangle_total > 0 and triangle_total <= limit, str(triangle_total))
	_check("%s retains usable textured surfaces and UVs" % asset,
		textured_surfaces > 0 and missing_uv == 0,
		"textured=%d missing_uv=%d" % [textured_surfaces, missing_uv])
	_check("%s retains unit-length imported normals on every surface" % asset,
		missing_normals == 0 and non_unit_normals == 0,
		"surfaces=%d missing=%d non_unit=%d" % [surfaces, missing_normals, non_unit_normals])


func _test_source_asset(asset: String) -> void:
	var path := Population.asset_path(asset)
	if "/" in asset:
		# Outfit variants are declared in Population.OUTFITS; a declared but missing file is a defect.
		_check("%s outfit variant is shipped" % asset, ResourceLoader.exists(path), path)
	if not ResourceLoader.exists(path):
		print("skip source audit; asset is not staged yet: ", path)
		return
	var packed := load(path) as PackedScene
	_check("%s GLB imports as a PackedScene" % asset, packed != null)
	if packed == null:
		return
	var root := packed.instantiate()
	var parts: Array[Dictionary] = []
	var flags := {rig_or_animation = false, runtime_behavior = false}
	_collect_scene(root, Transform3D.IDENTITY, parts, flags)
	_check("%s is baked geometry without a skeleton or animation player" % asset,
		not flags.rig_or_animation)
	_check("%s has no attached runtime scripts or processing callbacks" % asset,
		not flags.runtime_behavior)
	_check("%s contains visible mesh geometry" % asset, not parts.is_empty())
	if not parts.is_empty():
		_inspect_mesh_data(asset, parts)
	root.free()


func _human_texture_paths(asset: String) -> Dictionary:
	if not ResourceLoader.exists(Population.asset_path(asset)):
		return {}
	var source: Dictionary = Population._source(asset)
	var paths: Dictionary = {}
	for part: Dictionary in source.get("parts", []):
		var mesh: Mesh = part.mesh
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as ShaderMaterial
			if material == null:
				continue
			for parameter: String in ["base_texture", "normal_texture"]:
				var texture := material.get_shader_parameter(parameter) as Texture2D
				if texture != null:
					var key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
					paths[key] = true
	return paths


func _test_shared_human_textures() -> void:
	var all_paths: Array[Dictionary] = []
	for asset: String in Population.human_assets():
		var paths := _human_texture_paths(asset)
		if paths.is_empty():
			print("skip shared-texture audit; pose asset is not staged yet: ", asset)
			return
		_check("%s resolves shared shader textures" % asset, not paths.is_empty())
		all_paths.append(paths)
	if all_paths.size() != Population.human_assets().size():
		_check("standing, sitting, and pilot assets share PBR textures", false, "missing human texture set")
		return
	var common := all_paths[0].duplicate()
	for paths: Dictionary in all_paths.slice(1):
		for path: String in common.keys():
			if not paths.has(path):
				common.erase(path)
	_check("standing, sitting, and pilot reuse at least one PBR texture resource",
		not common.is_empty(), str(common.keys()))


func _record_asset_expectations(groups: Array) -> Dictionary:
	var by_asset: Dictionary = {}
	var people := 0
	var cars := 0
	for group: Dictionary in groups:
		if group.get("type", "") != "instances":
			continue
		for placement: Dictionary in group.get("placements", []):
			var id := str(placement.get("prefab", ""))
			if not Population.ASSETS.has(id):
				continue
			var asset := str(Population.ASSETS[id])
			by_asset[asset] = int(by_asset.get(asset, 0)) + 1
			if id.begins_with("car_"):
				cars += 1
			else:
				people += 1
	return {by_asset = by_asset, cars = cars, people = people}


func _test_production_batches(field: Dictionary, scenery: Dictionary) -> void:
	var expected := _record_asset_expectations(scenery.groups)
	_check("source layout contributes 11 cars and 13 people", expected.cars == 11 and expected.people == 13,
		"cars=%d people=%d" % [expected.cars, expected.people])
	for asset: String in Population.ASSETS.values():
		var path := Population.DIR + asset + ".glb"
		if not ResourceLoader.exists(path):
			print("skip production population readback; asset is not staged yet: ", path)
			return
	var root := Scenery.build(field, scenery, {audio = false, birds = false, theme = "", quality = "high"})
	var population := root.get_node_or_null("Population") as Node3D
	_check("scenery owns the population batch root", population != null)
	if population == null:
		root.free()
		return
	var stats: Dictionary = root.get_meta("stats")
	_check("production batches all 24 placed vehicles and people",
		int(stats.get("population", -1)) == 24 and int(population.get_meta("instances", -1)) == 24,
		"stats=%s metadata=%s" % [stats.get("population", -1), population.get_meta("instances", -1)])
	_check("the three car styles and all four person poses are batched",
		expected.by_asset.size() == 7 and ["sedan", "hatch", "crossover", "standing", "sitting", "pilot", "working"].all(
			func(asset: String) -> bool: return expected.by_asset.has(asset)), str(expected.by_asset))
	var observed_counts: Dictionary = {}
	var variant_counts: Dictionary = {}
	var fit_boxes: Dictionary = {}
	var expected_sizes: Dictionary = {}
	var population_triangles := 0
	var can_read_fit_bounds := DisplayServer.get_name() != "headless"
	if not can_read_fit_bounds:
		print("skip transformed population fit readback: native renderer required; headless MultiMesh transform readback is unavailable")
	for node: Node in population.get_children():
		var batch := node as MultiMeshInstance3D
		if batch == null or batch.multimesh == null or batch.multimesh.mesh == null:
			continue
		var asset := str(batch.get_meta("source_asset", ""))
		var asset_key := str(batch.get_meta("asset_key", asset))
		var placements: Array = batch.get_meta("placements", [])
		_check("%s uses one shared mesh per part with no node script" % batch.name,
			batch.get_script() == null and not batch.is_processing()
			and batch.multimesh.instance_count == placements.size(),
			"instances=%d placements=%d" % [batch.multimesh.instance_count, placements.size()])
		if not variant_counts.has(asset_key):
			variant_counts[asset_key] = placements.size()
			observed_counts[asset] = int(observed_counts.get(asset, 0)) + placements.size()
		elif int(variant_counts[asset_key]) != placements.size():
			_check("%s parts share the same placement list" % asset_key, false)
		population_triangles += _triangle_count(batch.multimesh.mesh) * batch.multimesh.instance_count
		if can_read_fit_bounds:
			var mesh_box: AABB = batch.multimesh.mesh.get_aabb()
			for i in placements.size():
				var placement: Dictionary = placements[i]
				var placement_xf: Transform3D = placement.transform
				var fitted_part: Transform3D = placement_xf.affine_inverse() * batch.multimesh.get_instance_transform(i)
				var local_box: AABB = fitted_part * mesh_box
				var key := "%s:%d" % [asset_key, i]
				if fit_boxes.has(key):
					var prior_box: AABB = fit_boxes[key]
					fit_boxes[key] = prior_box.merge(local_box)
				else:
					fit_boxes[key] = local_box
				expected_sizes[key] = placement.size
	for asset: String in expected.by_asset:
		_check("%s population batch count matches its source placements" % asset,
			int(observed_counts.get(asset, -1)) == int(expected.by_asset[asset]),
			"expected=%d observed=%d" % [int(expected.by_asset[asset]), int(observed_counts.get(asset, -1))])
	_check("population triangle metadata includes every indexed mesh surface and instance",
		int(population.get_meta("triangles", -1)) == population_triangles
		and int(stats.get("population_triangles", -1)) == population_triangles,
		"root=%s stats=%s calculated=%d" % [population.get_meta("triangles", -1), stats.get("population_triangles", -1), population_triangles])
	if can_read_fit_bounds:
		for key: String in fit_boxes:
			var box: AABB = fit_boxes[key]
			var target: Vector3 = expected_sizes[key]
			var asset := Population.pose_of(key.get_slice(":", 0))
			var error := maxf(maxf(absf(box.size.x - target.x), absf(box.size.y - target.y)), absf(box.size.z - target.z))
			if CAR_ASSETS.has(asset):
				_check("%s fitted mesh bounds match its catalog collision envelope" % key,
					error <= maxf(0.025, maxf(target.x, maxf(target.y, target.z)) * 0.015)
					and absf(box.position.y) <= 0.01,
					"bounds=%s catalog=%s bottom=%.4f" % [box.size, target, box.position.y])
			else:
				_check("%s human bounds stay inside the catalog proxy and rest on the ground" % key,
					box.size.x <= target.x + 0.025 and box.size.y <= target.y + 0.025
					and box.size.z <= target.z + 0.025 and box.size.y >= target.y * 0.70
					and absf(box.position.y) <= 0.015,
					"bounds=%s catalog=%s bottom=%.4f" % [box.size, target, box.position.y])
	_check("bounded shader motion metadata stays between 2 and 9 people",
		int(population.get_meta("moving_people", -1)) >= 2 and int(population.get_meta("moving_people", -1)) <= 9,
		str(population.get_meta("moving_people", -1)))
	root.free()
