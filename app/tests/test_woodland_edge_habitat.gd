## L7-R1: default woodland-edge decoration stays bounded, repeatable and collision-free.
## Run from app/: godot --headless --path . --script res://tests/test_woodland_edge_habitat.gd
extends SceneTree

const WoodlandEdges = preload("res://scenery/woodland_edge_habitat.gd")
const Hedge = preload("res://scenery/imported_hedge.gd")
const PlantLibrary = preload("res://scenery/imported_vegetation.gd")
const GroundSurfaces = preload("res://physics/ground_surfaces.gd")
const GroundTerrain = preload("res://physics/ground_terrain.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const SceneryLoader = preload("res://scenery/scenery_loader.gd")
const LakeLoader = preload("res://data/lake_loader.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const SOURCE_FERN_ATLAS := "res://assets/landscape/vegetation/impostors/polyhaven_fern_02_a_4view.png"

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	ShaderClock.register()
	var field_result: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads", bool(field_result.get("ok", false)), str(field_result.get("errors", [])))
	if not bool(field_result.get("ok", false)):
		_finish()
		return
	var field: Dictionary = field_result.field
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field)
	_check("default scenery loads", bool(scenery_result.get("ok", false)), str(scenery_result.get("errors", [])))
	if not bool(scenery_result.get("ok", false)):
		_finish()
		return
	var scenery: Dictionary = scenery_result.scenery
	var lake_result: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("default lake loads", bool(lake_result.get("ok", false)), str(lake_result.get("errors", [])))
	if not bool(lake_result.get("ok", false)):
		_finish()
		return
	var lake: Dictionary = lake_result.lake

	var field_before := JSON.stringify(field)
	var scenery_before := JSON.stringify(scenery)
	var lake_before := JSON.stringify(lake)
	var input_hashes_before := _input_hashes()
	_check("the exact default field/scenery/lake pair is applicable",
		WoodlandEdges.applicable(field, scenery, lake))
	_check("the documented recipe hash is readable", FileAccess.get_sha256(WoodlandEdges.DATA_PATH).length() == 64)

	# Pin the fallback explicitly even if the test process inherited a user override.
	var environment_had_override := OS.has_environment("OPENRC_WOODLAND_MESHES")
	var environment_before := OS.get_environment("OPENRC_WOODLAND_MESHES")
	var card_mode_had_override := OS.has_environment("OPENRC_WOODLAND_CARDS")
	var card_mode_before := OS.get_environment("OPENRC_WOODLAND_CARDS")
	var shrub_mode_had_override := OS.has_environment("OPENRC_WOODLAND_SHRUBS")
	var shrub_mode_before := OS.get_environment("OPENRC_WOODLAND_SHRUBS")
	OS.set_environment("OPENRC_WOODLAND_SHRUBS", "legacy")
	OS.set_environment("OPENRC_WOODLAND_CARDS", "legacy")
	OS.set_environment("OPENRC_WOODLAND_MESHES", "off")
	var cards: Node3D = WoodlandEdges.build(field, scenery, "high", lake)
	var card_plants: Array = cards.get_meta("plants", [])
	var card_index := _plant_index(card_plants)
	var card_geometry := _geometry_totals(cards)
	_check("mesh opt-out restores the 472-triangle five-batch card layout",
		bool(card_geometry.valid) and int(card_geometry.triangles) == 472 and int(card_geometry.batches) == 5
		and int(cards.get_meta("triangles", -1)) == 472 and int(cards.get_meta("batches", -1)) == 5,
		str(card_geometry))
	_check("mesh opt-out retains all 220 original source cards",
		card_plants.size() == 220 and bool(card_index.unique)
		and _counts(card_plants, "asset_id") == {fern_1 = 24, grass_common_tall = 16,
			bush_common_flowers = 8, grass_common_short = 172}
		and _counts(card_plants, "rendering") == {card = 220}, str(_counts(card_plants, "asset_id")))
	_check("fallback matches original recipe and hedge placement IDs, positions, yaw and heights",
		_layout_matches_recipe(card_plants), "fallback plant records differ from recipe/hedge layout")
	_check("fallback retains four 55-card batches and the shared source-atlas material",
		_shrub_layout_contract(cards, 55) and _shrub_render_contract(cards), str(_shrub_batch_counts(cards)))
	var balanced_cards: Node3D = WoodlandEdges.build(field, scenery, "balanced", lake)
	var balanced_card_plants: Array = balanced_cards.get_meta("plants", [])
	OS.unset_environment("OPENRC_WOODLAND_MESHES")

	var high: Node3D = WoodlandEdges.build(field, scenery, "high", lake)
	var high_plants: Array = high.get_meta("plants", [])
	var high_index := _plant_index(high_plants)
	var high_geometry := _geometry_totals(high)
	_check("high tier realizes 2656 source triangles", int(high.get_meta("triangles", -1)) == 2656,
		str(high.get_meta("triangles", -1)))
	_check("high tier realizes 13 render batches", int(high.get_meta("batches", -1)) == 13,
		str(high.get_meta("batches", -1)))
	_check("high-tier surfaces independently total 2656 triangles",
		bool(high_geometry.valid) and int(high_geometry.triangles) == 2656, str(high_geometry))
	_check("high-tier subtree independently contains 13 render batches",
		int(high_geometry.batches) == 13, str(high_geometry))
	_check("geometry counts agree with emitted metadata",
		int(high_geometry.triangles) == int(high.get_meta("triangles", -1))
		and int(high_geometry.batches) == int(high.get_meta("batches", -1)), str(high_geometry))
	_check("high tier realizes 220 plants", high_plants.size() == 220, str(high_plants.size()))
	_check("all high-tier plant IDs are unique", bool(high_index.unique), str(high_index.ids.keys()))
	_check("high-tier subtree contains no CollisionObject3D", not _has_collision_object(high))
	_check("all woodland geometry casts no shadow", _shadows_are_off(high))

	_check("mixed tier preserves all four original source families",
		_counts(high_plants, "source_asset_id") == {fern_1 = 24, grass_common_tall = 16,
			bush_common_flowers = 8, grass_common_short = 172}, str(_counts(high_plants, "source_asset_id")))
	_check("mixed tier uses the intended source meshes and remaining cards",
		_counts(high_plants, "asset_id") == {grass_lolipop_small = 14, polyhaven_fern_02_a = 2,
			forest_leafy_shrub = 2, grass_common_tall = 2, fern_1 = 22, bush_common_flowers = 6, grass_common_short = 172}
		and _counts(high_plants, "rendering") == {mesh = 18, card = 202}, str(_counts(high_plants, "asset_id")))
	_check("mesh accents use the specified first species paths in each patch",
		_mesh_selection_matches_recipe(high_plants))
	_check("mixed and fallback plants keep their IDs, positions, yaw and source families",
		_placement_contract(high_plants, card_plants), "mixed plant records differ from fallback")
	var mesh_bounds := _mesh_bounds_contract(high, card_index.ids, field, lake)
	_check("every grounded mesh part fits its original card's height and horizontal envelope",
		bool(mesh_bounds.ok), str(mesh_bounds))
	var floor_mesh: MeshInstance3D = high.get_node("WoodlandLitter")
	_check("litter uses 32 terrain triangles and casts no shadow",
		_mesh_triangle_count(floor_mesh.mesh) == 32 and floor_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	var high_again: Node3D = WoodlandEdges.build(field, scenery, "high", lake)
	_check("high rebuild preserves ordered plant records",
		JSON.stringify(high_plants) == JSON.stringify(high_again.get_meta("plants", [])))
	_check("high tier retains two 51-card and two 50-card patch batches",
		_shrub_batch_counts(high) == {"woodland-edge-east-north_Shrubs": 51,
			"woodland-edge-northwest_Shrubs": 51, "woodland-edge-east-south_Shrubs": 50,
			"woodland-edge-southwest_Shrubs": 50}, str(_shrub_batch_counts(high)))
	_check("high tier preserves shrub render settings and shared source-atlas material",
		_shrub_render_contract(high))

	var balanced: Node3D = WoodlandEdges.build(field, scenery, "balanced", lake)
	var balanced_plants: Array = balanced.get_meta("plants", [])
	var balanced_index := _plant_index(balanced_plants)
	var subset := bool(balanced_index.unique) and balanced_plants.size() < high_plants.size()
	for plant_id: Variant in balanced_index.ids:
		if not high_index.ids.has(plant_id) or balanced_index.ids[plant_id] != high_index.ids[plant_id]:
			subset = false
	_check("balanced tier is a stable strict subset of high", subset,
		"balanced=%d high=%d" % [balanced_plants.size(), high_plants.size()])
	_check("balanced mixed and card modes retain the same placement identities",
		_placement_contract(balanced_plants, balanced_card_plants))
	var balanced_again: Node3D = WoodlandEdges.build(field, scenery, "balanced", lake)
	_check("balanced rebuild preserves ordered plant records",
		JSON.stringify(balanced_plants) == JSON.stringify(balanced_again.get_meta("plants", [])))
	_check("all final shrub batches own separate MultiMesh and card meshes",
		_shrub_resources_are_independent([high, high_again, balanced, balanced_again]))

	_check("terrain sample cache stays bounded across quality rebuilds",
		WoodlandEdges._ground_heights.size() == 220, str(WoodlandEdges._ground_heights.size()))
	_test_unavailable_mesh(field, scenery, lake, card_plants)

	# An empty process-local parts cache makes accidental mesh work observable.
	var previous_parts_cache: Dictionary = PlantLibrary._parts_cache
	PlantLibrary._parts_cache = {}
	OS.set_environment("OPENRC_WOODLAND_CARDS", "source")
	_check("source fern caches are cold before low and custom builds",
		WoodlandEdges._fern_manifest.is_empty() and WoodlandEdges._source_card_material == null
		and not ResourceLoader.has_cached(SOURCE_FERN_ATLAS))
	var low: Node3D = WoodlandEdges.build(field, scenery, "low", lake)
	_check("low tier builds zero woodland plants, triangles and batches",
		low.get_meta("plants", []).is_empty() and int(low.get_meta("triangles", -1)) == 0
		and int(low.get_meta("batches", -1)) == 0 and low.get_child_count() == 0)
	_check("low tier skips source mesh loading", PlantLibrary._parts_cache.is_empty())
	PlantLibrary._parts_cache = {}

	var custom_field := field.duplicate(true)
	custom_field["pilot"]["north"] = float(custom_field.pilot.north) + 1.0
	var custom_scenery := scenery.duplicate(true)
	custom_scenery["groups"] = []
	var custom_lake := lake.duplicate(true)
	custom_lake["water_level_down_m"] = float(custom_lake.water_level_down_m) + 0.01
	_check("custom field is not applicable", not WoodlandEdges.applicable(custom_field, scenery, lake))
	_check("custom scenery is not applicable", not WoodlandEdges.applicable(field, custom_scenery, lake))
	_check("custom lake is not applicable", not WoodlandEdges.applicable(field, scenery, custom_lake))
	var custom_field_root: Node3D = WoodlandEdges.build(custom_field, scenery, "high", lake)
	var custom_scenery_root: Node3D = WoodlandEdges.build(field, custom_scenery, "high", lake)
	var custom_lake_root: Node3D = WoodlandEdges.build(field, scenery, "high", custom_lake)
	_check("all custom inputs skip woodland geometry",
		custom_field_root.get_child_count() == 0 and custom_scenery_root.get_child_count() == 0
		and custom_lake_root.get_child_count() == 0
		and int(custom_field_root.get_meta("triangles", -1)) == 0
		and int(custom_scenery_root.get_meta("triangles", -1)) == 0
		and int(custom_lake_root.get_meta("triangles", -1)) == 0)
	_check("custom inputs skip source mesh loading", PlantLibrary._parts_cache.is_empty())
	PlantLibrary._parts_cache = previous_parts_cache
	_check("low and custom inputs skip source fern manifest and texture loading",
		WoodlandEdges._fern_manifest.is_empty() and WoodlandEdges._source_card_material == null
		and not ResourceLoader.has_cached(SOURCE_FERN_ATLAS))

	var source_high: Node3D = WoodlandEdges.build(field, scenery, "high", lake)
	var source_balanced: Node3D = WoodlandEdges.build(field, scenery, "balanced", lake)
	OS.set_environment("OPENRC_WOODLAND_MESHES", "off")
	var source_cards: Node3D = WoodlandEdges.build(field, scenery, "high", lake)
	OS.unset_environment("OPENRC_WOODLAND_MESHES")
	_check("fern mode identifies source and legacy builds",
		str(high.get_meta("fern_cards", "")) == "legacy" and str(cards.get_meta("fern_cards", "")) == "legacy"
		and str(source_high.get_meta("fern_cards", "")) == "source"
		and str(source_cards.get_meta("fern_cards", "")) == "source")
	var mixed_source := _source_fern_contract(source_high, high, field, lake, 22)
	_check("source mode refits exactly 22 mixed fern cards within their legacy envelopes",
		bool(mixed_source.ok), str(mixed_source))
	var cards_source := _source_fern_contract(source_cards, cards, field, lake, 24)
	_check("mesh opt-out refits exactly 24 fern cards within their legacy envelopes",
		bool(cards_source.ok), str(cards_source))
	var balanced_fern_count := _fern_card_count(balanced_plants)
	var balanced_source := _source_fern_contract(source_balanced, balanced, field, lake, balanced_fern_count)
	_check("balanced source ferns retain the same bounded placement identities",
		bool(balanced_source.ok), str(balanced_source))
	_check("source fern mode preserves all mixed and balanced mesh plans exactly",
		var_to_bytes(source_high.get_meta("mesh_plans", [])) == var_to_bytes(high.get_meta("mesh_plans", []))
		and var_to_bytes(source_balanced.get_meta("mesh_plans", [])) == var_to_bytes(balanced.get_meta("mesh_plans", [])))
	_check("source fern mode binds its own atlas without changing the other card textures",
		_source_material_contract(high, source_high))
	_check("source fern mode preserves the mixed and card-only geometry budgets",
		_geometry_totals(source_high) == high_geometry and _geometry_totals(source_cards) == card_geometry
		and int(source_high.get_meta("triangles", -1)) == 2656 and int(source_high.get_meta("batches", -1)) == 13
		and int(source_cards.get_meta("triangles", -1)) == 472 and int(source_cards.get_meta("batches", -1)) == 5)
	OS.unset_environment("OPENRC_WOODLAND_CARDS")
	var default_fern: Node3D = WoodlandEdges.build(field, scenery, "high", lake)
	_check("the default fern-card mode selects the available source atlas",
		str(default_fern.get_meta("fern_cards", "")) == "source"
		and default_fern.get_meta("plants", []) == source_high.get_meta("plants", []))
	OS.set_environment("OPENRC_WOODLAND_CARDS", "legacy")

	_check("field/scenery/lake dictionaries are read-only",
		JSON.stringify(field) == field_before and JSON.stringify(scenery) == scenery_before
		and JSON.stringify(lake) == lake_before)
	_check("recipe, field, scenery and lake input hashes are unchanged",
		_input_hashes() == input_hashes_before, str(input_hashes_before) + " -> " + str(_input_hashes()))

	for node: Node in [cards, balanced_cards, high, high_again, balanced, balanced_again, low,
		source_high, source_balanced, source_cards, default_fern,
		custom_field_root, custom_scenery_root, custom_lake_root]:
		node.free()
	if environment_had_override:
		OS.set_environment("OPENRC_WOODLAND_MESHES", environment_before)
	else:
		OS.unset_environment("OPENRC_WOODLAND_MESHES")
	await _check_impostor_view_frames()
	if card_mode_had_override:
		OS.set_environment("OPENRC_WOODLAND_CARDS", card_mode_before)
	else:
		OS.unset_environment("OPENRC_WOODLAND_CARDS")
	if shrub_mode_had_override:
		OS.set_environment("OPENRC_WOODLAND_SHRUBS", shrub_mode_before)
	else:
		OS.unset_environment("OPENRC_WOODLAND_SHRUBS")
	_finish()


## Regression: the 4-view cards showed the opposite side's frame from north and south.
## The bake's Blender azimuth a reaches Godot as the source-local direction (cos a, 0, -sin a);
## a camera in that direction must see frame a / 90 degrees, also for a yawed instance.
func _check_impostor_view_frames() -> void:
	if DisplayServer.get_name() == "headless":
		print("skip impostor view-frame readback: the Dummy renderer draws nothing")
		return
	var colors: Array[Color] = [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1), Color(1, 1, 0)]
	var atlas := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	for frame in 4:
		atlas.fill_rect(Rect2i(frame * 16, 0, 16, 16), colors[frame])
	var texture := ImageTexture.create_from_image(atlas)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(32, 32)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	for shader_path: String in ["res://scenery/woodland_cards.gdshader",
			"res://assets/landscape/vegetation/impostors/bush_common_4view.gdshader"]:
		for yaw: float in [0.0, PI * 0.5]:
			var material := ShaderMaterial.new()
			material.shader = load(shader_path)
			for uniform_name: String in ["impostor_atlas", "plain_atlas", "short_grass_atlas", "fern_atlas"]:
				material.set_shader_parameter(uniform_name, texture)
			var quad := QuadMesh.new()
			quad.material = material
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_colors = true
			multimesh.use_custom_data = true
			multimesh.mesh = quad
			multimesh.instance_count = 1
			var placement := Basis(Vector3.UP, yaw)
			multimesh.set_instance_transform(0, Transform3D(placement, Vector3.ZERO))
			multimesh.set_instance_color(0, Color.WHITE)
			multimesh.set_instance_custom_data(0, Color(yaw / TAU, 0.0, 0.0, 1.0))
			var card := MultiMeshInstance3D.new()
			card.multimesh = multimesh
			viewport.add_child(card)
			var shown: Array[int] = []
			for frame in 4:
				var azimuth := deg_to_rad(90.0 * frame)
				camera.look_at_from_position(placement * Vector3(cos(azimuth), 0.0, -sin(azimuth)) * 3.0, Vector3.ZERO)
				for _index in 3:
					await process_frame
					RenderingServer.force_draw(false)
				var pixel := viewport.get_texture().get_image().get_pixel(16, 16)
				var nearest := -1
				var nearest_distance := INF
				for candidate in 4:
					var distance := Vector3(pixel.r, pixel.g, pixel.b).normalized() \
						.distance_to(Vector3(colors[candidate].r, colors[candidate].g, colors[candidate].b).normalized())
					if distance < nearest_distance:
						nearest_distance = distance
						nearest = candidate
				shown.append(nearest)
			_check("%s shows bake frames 0..3 from their bake azimuths at yaw %.0f deg" % [
				shader_path.get_file(), rad_to_deg(yaw)], shown == [0, 1, 2, 3], str(shown))
			card.free()
	viewport.free()


func _shrub_layout_contract(root: Node3D, expected_count: int) -> bool:
	var batches := _shrub_batches(root)
	if batches.size() != 4:
		return false
	for batch_value: Variant in batches.values():
		var batch: MultiMeshInstance3D = batch_value
		if batch.multimesh == null or batch.multimesh.instance_count != expected_count:
			return false
	return true


func _shrub_render_contract(root: Node3D) -> bool:
	var batches := _shrub_batches(root)
	var manifest := Hedge._manifest()
	var frame_value: Variant = manifest.get("frame_world_size_m", [])
	var frame_size := maxf(float(frame_value[0]), 0.001) if frame_value is Array and not frame_value.is_empty() else 2.16
	for batch_value: Variant in batches.values():
		var batch: MultiMeshInstance3D = batch_value
		var multimesh := batch.multimesh
		if multimesh == null or not multimesh.mesh is QuadMesh:
			return false
		var card := multimesh.mesh as QuadMesh
		if card.size != Vector2(frame_size, frame_size):
			return false
		if multimesh.transform_format != MultiMesh.TRANSFORM_3D or not multimesh.use_colors or not multimesh.use_custom_data:
			return false
		if batch.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return false
		if batch.get_meta("source_asset_ids", []) != WoodlandEdges.SPECIES:
			return false
		if batch.material_override != WoodlandEdges._material():
			return false
		var material := batch.material_override as ShaderMaterial
		if material == null or material.shader.resource_path != "res://scenery/woodland_cards.gdshader":
			return false
		if material.get_shader_parameter("impostor_atlas") != Hedge._atlas() \
			or material.get_shader_parameter("plain_atlas") == null or material.get_shader_parameter("fern_atlas") == null \
			or material.get_shader_parameter("short_grass_atlas") == null:
			return false
		if not is_equal_approx(float(material.get_shader_parameter("alpha_cutoff")), 0.32):
			return false
		if not is_equal_approx(float(material.get_shader_parameter("atlas_frames")), 4.0):
			return false
	return batches.size() == 4


func _shrub_resources_are_independent(roots: Array[Node3D]) -> bool:
	var multimesh_ids: Dictionary = {}
	var mesh_ids: Dictionary = {}
	var material_ids: Dictionary = {}
	for root: Node3D in roots:
		for batch_value: Variant in _shrub_batches(root).values():
			var batch: MultiMeshInstance3D = batch_value
			if batch.multimesh == null or batch.multimesh.mesh == null or batch.material_override == null:
				return false
			var multimesh_id := batch.multimesh.get_instance_id()
			var mesh_id := batch.multimesh.mesh.get_instance_id()
			var material_id := batch.material_override.get_instance_id()
			if multimesh_ids.has(multimesh_id) or mesh_ids.has(mesh_id):
				return false
			multimesh_ids[multimesh_id] = true
			mesh_ids[mesh_id] = true
			material_ids[material_id] = true
	return multimesh_ids.size() == 16 and mesh_ids.size() == 16 and material_ids.size() == 1


func _shrub_batches(root: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for child: Node in root.get_children():
		if child is MultiMeshInstance3D and str(child.name).ends_with("_Shrubs"):
			result[str(child.name)] = child
	return result


func _shrub_batch_counts(root: Node3D) -> Dictionary:
	var result: Dictionary = {}
	var batches := _shrub_batches(root)
	for batch_name: Variant in batches:
		var batch: MultiMeshInstance3D = batches[batch_name]
		result[batch_name] = -1 if batch.multimesh == null else batch.multimesh.instance_count
	return result


func _counts(plants: Array, key: String) -> Dictionary:
	var result: Dictionary = {}
	for plant: Dictionary in plants:
		var value := str(plant.get(key, ""))
		result[value] = int(result.get(value, 0)) + 1
	return result


func _fern_card_count(plants: Array) -> int:
	var count := 0
	for plant: Dictionary in plants:
		if str(plant.get("source_asset_id", "")) == "fern_1" and str(plant.get("rendering", "")) == "card":
			count += 1
	return count


## Verify the actual CPU transforms consumed by card batches: headless MultiMesh
## transform readback is a dummy. The original side comes from the legacy atlas.
func _source_fern_contract(source: Node3D, legacy: Node3D, field: Dictionary, lake: Dictionary,
		expected_count: int) -> Dictionary:
	var errors: Array[String] = []
	var source_plants: Array = source.get_meta("plants", [])
	var legacy_plants: Array = legacy.get_meta("plants", [])
	var source_index := _plant_index(source_plants)
	var legacy_index := _plant_index(legacy_plants)
	var source_manifest := WoodlandEdges._source_fern_manifest()
	var legacy_manifest := WoodlandEdges._species_manifest("fern_1")
	var surfaces := _surface_rects(field)
	if not bool(source_index.unique) or not bool(legacy_index.unique) or source_plants.size() != legacy_plants.size() \
			or source_manifest.is_empty() or legacy_manifest.is_empty() or surfaces.is_empty():
		return {ok = false, errors = ["missing unique plants, manifests or ground surfaces"]}
	var source_fraction := float(source_manifest.source_height_m) / float(source_manifest.frame_world_size_m[0])
	var legacy_fraction := float(legacy_manifest.source_height_m) / float(legacy_manifest.frame_world_size_m[0])
	if source_fraction <= 0.0 or legacy_fraction <= 0.0:
		return {ok = false, errors = ["invalid source height/frame fraction"]}
	var expected_ids: Dictionary = {}
	for plant: Dictionary in legacy_plants:
		var id := str(plant.id)
		if not source_index.ids.has(id):
			_problem(errors, "source build lost plant " + id)
			continue
		var current: Dictionary = source_index.ids[id]
		if str(plant.source_asset_id) == "fern_1" and str(plant.rendering) == "card":
			expected_ids[id] = true
			var normalized := current.duplicate(true)
			normalized["asset_id"] = plant.asset_id
			normalized["height_m"] = plant.height_m
			if normalized != plant or str(current.asset_id) != "polyhaven_fern_02_a" \
					or float(current.height_m) <= 0.0 or float(current.height_m) > float(plant.height_m) + 0.00001:
				_problem(errors, "source fern changed identity or exceeded height for " + id)
		elif current != plant:
			_problem(errors, "source fern mode changed another plant " + id)
	if expected_ids.size() != expected_count:
		_problem(errors, "unexpected source fern card count")

	var seen: Dictionary = {}
	var frame := Hedge._frame_size(Hedge._manifest())
	for batch_value: Variant in _shrub_batches(source).values():
		var batch := batch_value as MultiMeshInstance3D
		var indices: Dictionary = {}
		for item: Dictionary in batch.get_meta("source_card_records", []):
			var id := str(item.get("id", ""))
			var index := int(item.get("index", -1))
			if not expected_ids.has(id) or seen.has(id) or indices.has(index) \
					or index < 0 or index >= batch.multimesh.instance_count or not item.get("transform") is Transform3D:
				_problem(errors, "missing, duplicated or malformed source-card record " + id)
				continue
			seen[id] = true
			indices[index] = true
			var plant: Dictionary = source_index.ids[id]
			var old: Dictionary = legacy_index.ids[id]
			var transform: Transform3D = item.transform
			var ground: PackedFloat64Array = GroundTerrain.sample_validated(float(old.north), float(old.east), surfaces, lake)
			if ground.size() != 3:
				_problem(errors, "terrain sample missing for " + id)
				continue
			var scale := transform.basis.get_scale().abs()
			var actual_side := frame * scale.x
			var old_side := float(old.height_m) / legacy_fraction
			var desired_side := minf(old_side, float(old.height_m) / source_fraction)
			var yaw := Basis(Vector3.UP, float(old.yaw_rad))
			if str(item.get("asset_id", "")) != "polyhaven_fern_02_a" \
					or absf(float(item.get("height_m", -1.0)) - float(plant.height_m)) > 0.00001 \
					or absf(actual_side - desired_side) > 0.0001 \
					or absf(actual_side * source_fraction - float(plant.height_m)) > 0.0001 \
					or absf(scale.x - scale.y) > 0.0001 or absf(scale.x - scale.z) > 0.0001 \
					or absf(transform.origin.x - float(old.east)) > 0.002 \
					or absf(transform.origin.z + float(old.north)) > 0.002 \
					or absf(transform.origin.y - 0.5 * actual_side * source_fraction - float(ground[0])) > 0.002 \
					or transform.basis.orthonormalized().x.distance_to(yaw.x) > 0.0001 \
					or transform.basis.orthonormalized().z.distance_to(yaw.z) > 0.0001:
				_problem(errors, "source-card size, yaw or ground contact differs for " + id)
			if DisplayServer.get_name() != "headless" \
					and not batch.multimesh.get_instance_transform(index).is_equal_approx(transform):
				_problem(errors, "rendered instance transform differs from its CPU record " + id)
	if seen.size() != expected_count:
		_problem(errors, "CPU source-card record count does not match retained fern cards")
	return {ok = errors.is_empty(), cards = expected_ids.size(), records = seen.size(), errors = errors}


func _source_material_contract(legacy: Node3D, source: Node3D) -> bool:
	var old_batches := _shrub_batches(legacy)
	var new_batches := _shrub_batches(source)
	if old_batches.size() != 4 or new_batches.size() != 4 or WoodlandEdges._card_material == null \
			or WoodlandEdges._source_card_material == null or WoodlandEdges._card_material == WoodlandEdges._source_card_material:
		return false
	var old_material := WoodlandEdges._card_material
	var new_material := WoodlandEdges._source_card_material
	var source_texture := new_material.get_shader_parameter("fern_atlas") as Texture2D
	var manifest := WoodlandEdges._source_fern_manifest()
	if old_material.shader != new_material.shader or source_texture == null \
			or source_texture.resource_path != SOURCE_FERN_ATLAS or str(manifest.get("atlas_path", "")) != SOURCE_FERN_ATLAS \
			or old_material.get_shader_parameter("fern_atlas") == source_texture:
		return false
	for parameter: String in ["impostor_atlas", "plain_atlas", "short_grass_atlas", "alpha_cutoff", "atlas_frames", "grass_height_fractions"]:
		if old_material.get_shader_parameter(parameter) != new_material.get_shader_parameter(parameter):
			return false
	for value: Variant in old_batches.values():
		if (value as MultiMeshInstance3D).material_override != old_material:
			return false
	for value: Variant in new_batches.values():
		if (value as MultiMeshInstance3D).material_override != new_material:
			return false
	return true


## Compare fallback records to the retained recipe and the existing hedge placement
## contract, rather than to a second set of hard-coded positions.
func _layout_matches_recipe(plants: Array) -> bool:
	var recipe: Variant = JSON.parse_string(FileAccess.get_file_as_string(WoodlandEdges.DATA_PATH))
	if not recipe is Dictionary:
		return false
	var expected: Dictionary = {}
	for patch: Dictionary in recipe.get("patches", []):
		for path_index in patch.paths_ne_m.size():
			var points: Array[Vector2] = []
			for point: Array in patch.paths_ne_m[path_index]:
				points.append(Vector2(float(point[1]), -float(point[0])))
			var placements := Hedge.layout(points, float(patch.shrub_heights_m[path_index]),
				float(patch.shrub_width_m), int(patch.path_seeds[path_index]), "high")
			for placement: Dictionary in placements:
				var pos: Vector2 = placement.position
				var manifest := WoodlandEdges._species_manifest(str(patch.shrub_species[path_index]))
				var original: Transform3D = placement.transform
				var max_side := Hedge._frame_size(Hedge._manifest()) * original.basis.get_scale().x \
					* float(patch.shrub_height_m) / float(patch.shrub_heights_m[path_index])
				var height := minf(float(placement.height_m), max_side * float(manifest.source_height_m) \
					/ float(manifest.frame_world_size_m[0]))
				expected[str(placement.id)] = {north = -pos.y, east = pos.x,
					yaw_rad = float(placement.yaw_rad), asset_id = str(patch.shrub_species[path_index]),
					height_m = height, patch = str(patch.id)}
		for grass: Dictionary in patch.grass_cards:
			expected[str(grass.id)] = {north = float(grass.north_m), east = float(grass.east_m),
				yaw_rad = float(grass.yaw_rad), asset_id = "grass_common_short",
				height_m = float(grass.height_m), patch = str(patch.id)}
	var index := _plant_index(plants)
	if not bool(index.unique) or expected.size() != plants.size():
		return false
	for plant: Dictionary in plants:
		var id := str(plant.get("id", ""))
		if not expected.has(id) or not plant.has("yaw_rad"):
			return false
		var reference: Dictionary = expected[id]
		if absf(float(plant.north) - float(reference.north)) > 0.0001 \
				or absf(float(plant.east) - float(reference.east)) > 0.0001 \
				or not is_equal_approx(float(plant.yaw_rad), float(reference.yaw_rad)) \
				or absf(float(plant.height_m) - float(reference.height_m)) > 0.00001 \
				or str(plant.asset_id) != str(reference.asset_id) or str(plant.patch) != str(reference.patch):
			return false
	return true


func _mesh_selection_matches_recipe(plants: Array) -> bool:
	var recipe: Variant = JSON.parse_string(FileAccess.get_file_as_string(WoodlandEdges.DATA_PATH))
	if not recipe is Dictionary:
		return false
	var expected: Dictionary = {}
	for patch: Dictionary in recipe.get("patches", []):
		var patch_id := str(patch.id)
		for path_index in patch.paths_ne_m.size():
			var species := str(patch.shrub_species[path_index])
			var asset := ""
			if species == "grass_common_tall" and (patch_id not in ["woodland-edge-east-north", "woodland-edge-northwest"] \
					or path_index != patch.shrub_species.rfind("grass_common_tall")):
				asset = "grass_lolipop_small"
			elif patch_id in ["woodland-edge-east-north", "woodland-edge-northwest"] \
					and path_index == patch.shrub_species.find("fern_1"):
				asset = "polyhaven_fern_02_a"
			elif patch_id in ["woodland-edge-east-south", "woodland-edge-southwest"] \
					and path_index == patch.shrub_species.find("bush_common_flowers"):
				asset = "forest_leafy_shrub"
			if asset.is_empty():
				continue
			var points: Array[Vector2] = []
			for point: Array in patch.paths_ne_m[path_index]:
				points.append(Vector2(float(point[1]), -float(point[0])))
			for placement: Dictionary in Hedge.layout(points, float(patch.shrub_heights_m[path_index]),
					float(patch.shrub_width_m), int(patch.path_seeds[path_index]), "high"):
				expected[str(placement.id)] = asset
	var seen := 0
	for plant: Dictionary in plants:
		var id := str(plant.get("id", ""))
		if expected.has(id):
			if str(plant.get("rendering", "")) != "mesh" or str(plant.get("asset_id", "")) != str(expected[id]):
				return false
			seen += 1
		elif str(plant.get("rendering", "")) != "card":
			return false
	return seen == 18 and expected.size() == 18


func _placement_contract(mixed: Array, fallback: Array) -> bool:
	var reference := _plant_index(fallback)
	var actual := _plant_index(mixed)
	if not bool(reference.unique) or not bool(actual.unique) or mixed.size() != fallback.size():
		return false
	for id: Variant in actual.ids:
		if not reference.ids.has(id):
			return false
		var plant: Dictionary = actual.ids[id]
		var old: Dictionary = reference.ids[id]
		if not plant.has("yaw_rad") or not old.has("yaw_rad"):
			return false
		if float(plant.north) != float(old.north) or float(plant.east) != float(old.east) \
				or float(plant.yaw_rad) != float(old.yaw_rad) or str(plant.patch) != str(old.patch) \
				or str(plant.get("source_asset_id", "")) != str(old.asset_id) \
				or float(plant.height_m) <= 0.0 or float(plant.height_m) > float(old.height_m) + 0.00001:
			return false
		if str(plant.get("rendering", "")) == "card" and (str(plant.asset_id) != str(old.asset_id) \
				or not is_equal_approx(float(plant.height_m), float(old.height_m))):
			return false
	return true


func _surface_rects(field: Dictionary) -> PackedFloat64Array:
	var table := GroundSurfaces.load_table()
	if not bool(table.get("ok", false)):
		return PackedFloat64Array()
	var result := GroundSurfaces.build(table.table, field)
	return result.rects if bool(result.get("ok", false)) else PackedFloat64Array()


func _collect_mesh_groups(node: Node, output: Array[Node3D]) -> void:
	if node is Node3D and node.has_meta("_imported_vegetation_state"):
		output.append(node as Node3D)
	for child: Node in node.get_children():
		_collect_mesh_groups(child, output)


func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _problem(errors: Array[String], message: String) -> void:
	if errors.size() < 20:
		errors.append(message)


## Inspect CPU-retained source-part bounds: headless MultiMesh transform readback is
## a dummy. Every corner is checked against the old card envelope and terrain.
func _mesh_bounds_contract(root: Node3D, fallback_by_id: Dictionary, field: Dictionary, lake: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var surfaces := _surface_rects(field)
	var plans: Array = root.get_meta("mesh_plans", [])
	var plants := _plant_index(root.get_meta("plants", []))
	var by_id: Dictionary = {}
	var ground_by_id: Dictionary = {}
	var radius_by_id: Dictionary = {}
	var minimum_by_id: Dictionary = {}
	var records_by_id: Dictionary = {}
	if surfaces.is_empty():
		_problem(errors, "terrain surface table was unavailable")
	for plan: Dictionary in plans:
		var id := str(plan.get("id", ""))
		if id.is_empty() or by_id.has(id) or not fallback_by_id.has(id) or not plants.ids.has(id):
			_problem(errors, "missing or repeated mesh plan ID " + id)
			continue
		var old: Dictionary = fallback_by_id[id]
		var plant: Dictionary = plants.ids[id]
		var source_id := str(old.asset_id)
		var manifest := WoodlandEdges._species_manifest(source_id)
		var sample: PackedFloat64Array = GroundTerrain.sample_validated(float(old.north), float(old.east), surfaces, lake)
		if sample.size() != 3 or manifest.is_empty() or not plan.get("placement") is Transform3D:
			_problem(errors, "missing source, ground or placement for " + id)
			continue
		var ground := float(sample[0])
		var radius := float(old.height_m) * float(manifest.frame_world_size_m[0]) \
			/ float(manifest.source_height_m) * sqrt(2.0) * 0.5
		var placement: Transform3D = plan.placement
		var yaw_basis := Basis(Vector3.UP, float(old.yaw_rad))
		if str(plant.get("rendering", "")) != "mesh" or str(plan.get("asset_id", "")) != str(plant.asset_id) \
				or str(plan.get("source_asset_id", "")) != source_id \
				or absf(float(plan.get("reference_height_m", -1)) - float(old.height_m)) > 0.0001 \
				or absf(float(plan.get("height_m", -1)) - float(plant.height_m)) > 0.0001 \
				or absf(float(plan.get("ground_height_m", INF)) - ground) > 0.002 \
				or float(plan.get("envelope_radius_m", INF)) > radius + 0.002 \
				or absf(placement.origin.x - float(old.east)) > 0.002 \
				or absf(placement.origin.z + float(old.north)) > 0.002 \
				or absf(placement.origin.y - ground) > 0.002 \
				or placement.basis.orthonormalized().x.distance_to(yaw_basis.x) > 0.0001 \
				or placement.basis.orthonormalized().z.distance_to(yaw_basis.z) > 0.0001:
			_problem(errors, "mesh plan changed identity, height, ground, envelope or yaw for " + id)
		by_id[id] = plan
		ground_by_id[id] = ground
		radius_by_id[id] = radius
		minimum_by_id[id] = INF
		records_by_id[id] = 0

	var groups: Array[Node3D] = []
	_collect_mesh_groups(root, groups)
	var record_count := 0
	for group: Node3D in groups:
		var state: Dictionary = group.get_meta("_imported_vegetation_state", {})
		var group_transform := _relative_transform(group, root)
		for record: Dictionary in state.get("bounds", []):
			var id := str(record.get("damage_id", ""))
			if not by_id.has(id) or not record.get("bounds") is AABB or not record.get("transform") is Transform3D:
				_problem(errors, "unassociated or malformed imported part " + id)
				continue
			if str(record.get("asset_id", "")) != str((by_id[id] as Dictionary).asset_id) or bool(record.get("hidden", false)):
				_problem(errors, "wrong or hidden imported part " + id)
			var old: Dictionary = fallback_by_id[id]
			var bounds: AABB = record.bounds
			var transform: Transform3D = group_transform * (record.transform as Transform3D)
			var ground := float(ground_by_id[id])
			for corner_index in 8:
				var point := transform * bounds.get_endpoint(corner_index)
				minimum_by_id[id] = minf(float(minimum_by_id[id]), point.y)
				var distance := Vector2(point.x - float(old.east), point.z + float(old.north)).length()
				if distance > float(radius_by_id[id]) + 0.002 \
						or point.y < ground - 0.002 or point.y > ground + float(old.height_m) + 0.002:
					_problem(errors, "part corner outside the old card envelope for " + id)
			records_by_id[id] = int(records_by_id[id]) + 1
			record_count += 1
	for id: Variant in by_id:
		if int(records_by_id[id]) == 0 or absf(float(minimum_by_id[id]) - float(ground_by_id[id])) > 0.002:
			_problem(errors, "mesh part was missing or did not touch ground for " + str(id))
	if plans.size() != 18 or by_id.size() != 18 or groups.size() != 4 or record_count < 18:
		_problem(errors, "unexpected plan, group or part counts")
	return {ok = errors.is_empty(), plans = plans.size(), groups = groups.size(), records = record_count, errors = errors}


func _test_unavailable_mesh(field: Dictionary, scenery: Dictionary, lake: Dictionary, cards: Array) -> void:
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WoodlandEdges.DATA_PATH))
	var record := WoodlandEdges._grass_record(recipe.patches[0].grass_cards[0])
	var before := var_to_bytes(record)
	var plan := WoodlandEdges._mesh_plan(record, "not-a-vegetation-asset", _surface_rects(field), lake)
	_check("unknown mesh source yields no plan and leaves the card record untouched",
		plan.is_empty() and before == var_to_bytes(record))
	# The parts cache is process-local; restore its prior entry before assertions.
	var asset_id := "grass_lolipop_small"
	var had_entry := PlantLibrary._parts_cache.has(asset_id)
	var old_entry: Variant = PlantLibrary._parts_cache.get(asset_id)
	PlantLibrary._parts_cache[asset_id] = []
	var missing: Node3D = WoodlandEdges.build(field, scenery, "high", lake)
	if had_entry:
		PlantLibrary._parts_cache[asset_id] = old_entry
	else:
		PlantLibrary._parts_cache.erase(asset_id)
	var missing_plants: Array = missing.get_meta("plants", [])
	var geometry := _geometry_totals(missing)
	var mix := _counts(missing_plants, "asset_id")
	_check("unavailable small-grass mesh restores 14 original cards",
		_placement_contract(missing_plants, cards) and int(mix.get("grass_common_tall", 0)) == 16 \
		and int(mix.get(asset_id, 0)) == 0 and _counts(missing_plants, "rendering") == {mesh = 4, card = 216},
		str(mix))
	_check("unavailable source keeps the remaining mesh groups and correct geometry counts",
		bool(geometry.valid) and int(geometry.triangles) == 2320 and int(geometry.batches) == 9 \
		and int(missing.get_meta("triangles", -1)) == 2320 and int(missing.get_meta("batches", -1)) == 9,
		str(geometry))
	missing.free()


func _shadows_are_off(node: Node) -> bool:
	if node is GeometryInstance3D and (node as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		return false
	for child: Node in node.get_children():
		if not _shadows_are_off(child):
			return false
	return true


func _plant_index(plants: Array) -> Dictionary:
	var ids: Dictionary = {}
	var unique := true
	for plant_value: Variant in plants:
		if typeof(plant_value) != TYPE_DICTIONARY:
			unique = false
			continue
		var plant: Dictionary = plant_value
		var plant_id := str(plant.get("id", ""))
		if plant_id.is_empty() or ids.has(plant_id):
			unique = false
		else:
			ids[plant_id] = plant
	return {unique = unique, ids = ids}


func _has_collision_object(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	for child: Node in node.get_children():
		if _has_collision_object(child):
			return true
	return false


func _geometry_totals(node: Node) -> Dictionary:
	var result := {triangles = 0, batches = 0, valid = true}
	if node is MultiMeshInstance3D:
		var multimesh := (node as MultiMeshInstance3D).multimesh
		if multimesh == null or multimesh.mesh == null:
			result.valid = false
		else:
			var surface_count := _mesh_triangle_count(multimesh.mesh)
			if surface_count < 0 or multimesh.instance_count <= 0:
				result.valid = false
			else:
				result.triangles += surface_count * multimesh.instance_count
				result.batches += 1
	elif node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			result.valid = false
		else:
			var surface_count := _mesh_triangle_count(mesh)
			if surface_count < 0:
				result.valid = false
			else:
				result.triangles += surface_count
				result.batches += 1
	for child: Node in node.get_children():
		var child_totals := _geometry_totals(child)
		result.triangles += int(child_totals.triangles)
		result.batches += int(child_totals.batches)
		result.valid = bool(result.valid) and bool(child_totals.valid)
	return result


func _mesh_triangle_count(mesh: Mesh) -> int:
	var triangles := 0
	for surface_index in mesh.get_surface_count():
		if mesh is ArrayMesh:
			if (mesh as ArrayMesh).surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
				return -1
		elif not mesh is QuadMesh:
			return -1
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			return -1
		var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
		if index_data is PackedInt32Array and not index_data.is_empty():
			if index_data.size() % 3 != 0:
				return -1
			triangles += int(index_data.size() / 3)
		else:
			var vertex_data: Variant = arrays[Mesh.ARRAY_VERTEX]
			if not vertex_data is PackedVector3Array or vertex_data.is_empty() or vertex_data.size() % 3 != 0:
				return -1
			triangles += int(vertex_data.size() / 3)
	return triangles


func _input_hashes() -> Dictionary:
	return {
		"field": FileAccess.get_sha256(FieldLoader.DEFAULT_PATH),
		"scenery": FileAccess.get_sha256(SceneryLoader.DEFAULT_PATH),
		"lake": FileAccess.get_sha256(LakeLoader.DEFAULT_PATH),
		"recipe": FileAccess.get_sha256(WoodlandEdges.DATA_PATH),
	}


func _finish() -> void:
	print("woodland-edge habitat: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
