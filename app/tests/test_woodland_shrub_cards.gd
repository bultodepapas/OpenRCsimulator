## L7-R8: source shrubs preserve the qualified woodland layout and opt-outs.
## Headless checks cover CPU records; rendered invocations add eight pixel cases.
extends SceneTree

const Woodland = preload("res://scenery/woodland_edge_habitat.gd")
const Hedge = preload("res://scenery/imported_hedge.gd")
const GroundSurfaces = preload("res://physics/ground_surfaces.gd")
const GroundTerrain = preload("res://physics/ground_terrain.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const SceneryLoader = preload("res://scenery/scenery_loader.gd")
const LakeLoader = preload("res://data/lake_loader.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const IDS := ["polyhaven_shrub_03_a", "polyhaven_shrub_03_b"]
const ATLAS_ROOT := "res://assets/landscape/vegetation/impostors/"
const NEW_SHADER := "res://scenery/woodland_shrub_cards.gdshader"
const OLD_SHADER := "res://scenery/woodland_cards.gdshader"
const ENV_KEYS := ["OPENRC_WOODLAND_SHRUBS", "OPENRC_WOODLAND_CARDS", "OPENRC_WOODLAND_MESHES"]
const PIXELS := 64
const REFERENCE_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform float frame_number;
void fragment() {
    vec2 size = vec2(textureSize(atlas, 0));
    float width = size.x / 4.0;
    vec2 uv = vec2((frame_number + clamp(UV.x, 0.5 / width, 1.0 - 0.5 / width)) / 4.0,
                   clamp(UV.y, 0.5 / size.y, 1.0 - 0.5 / size.y));
    vec4 sample_color = texture(atlas, uv);
    ALBEDO = sample_color.rgb;
    NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    ALPHA = sample_color.a;
    ALPHA_SCISSOR_THRESHOLD = 0.32;
}
"""

var _checks := 0
var _failures := 0
var _pixel_checks := 0
var _saved_env := {}


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _run() -> void:
	ShaderClock.register()
	for key: String in ENV_KEYS:
		_saved_env[key] = {present = OS.has_environment(key), value = OS.get_environment(key)}
	OS.set_environment(ENV_KEYS[0], "source")
	OS.set_environment(ENV_KEYS[1], "source")
	OS.unset_environment(ENV_KEYS[2])
	var field_result: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not bool(field_result.get("ok", false)):
		_check("default field loads", false, str(field_result.get("errors", [])))
		_finish()
		return
	var field: Dictionary = field_result.field
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field)
	var lake_result: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not bool(scenery_result.get("ok", false)) or not bool(lake_result.get("ok", false)):
		_check("default scenery and lake load", false, str([scenery_result, lake_result]))
		_finish()
		return
	var scenery: Dictionary = scenery_result.scenery
	var lake: Dictionary = lake_result.lake

	_check("new shrub resources start cold", _new_resources_cold())
	var low: Node3D = Woodland.build(field, scenery, "low", lake)
	var custom := field.duplicate(true)
	custom.pilot.north = float(custom.pilot.north) + 1.0
	var custom_root: Node3D = Woodland.build(custom, scenery, "high", lake)
	_check("low and custom builds skip new manifests, textures and materials",
		low.get_child_count() == 0 and custom_root.get_child_count() == 0 and _new_resources_cold())
	low.free()
	custom_root.free()

	OS.set_environment(ENV_KEYS[0], "legacy")
	OS.set_environment(ENV_KEYS[1], "legacy")
	var legacy: Node3D = Woodland.build(field, scenery, "high", lake)
	var legacy_plants: Array = legacy.get_meta("plants", [])
	var legacy_material := _batch_material(legacy)
	_check("legacy shrubs use the original shader without loading new sources",
		str(legacy.get_meta("shrub_cards", "")) == "legacy" and _new_resources_cold()
		and legacy_material != null and legacy_material.shader.resource_path == OLD_SHADER
		and not legacy_material.shader.code.contains("shrub_atlas"))
	_check("legacy mixed mode retains six flowering cards and two shrub meshes",
		legacy_plants.size() == 220 and _count(legacy_plants, "bush_common_flowers", "card") == 6
		and _count(legacy_plants, "forest_leafy_shrub", "mesh") == 2)

	# Inject an invalid process-local cached manifest, then restore it even if the check fails.
	var old_manifests: Dictionary = Woodland._shrub_manifests.duplicate(true)
	Woodland._shrub_manifests[IDS[0]] = {}
	OS.set_environment(ENV_KEYS[0], "source")
	var invalid: Node3D = Woodland.build(field, scenery, "high", lake)
	Woodland._shrub_manifests = old_manifests
	_check("an empty cached manifest falls back to the legacy appearance",
		str(invalid.get_meta("shrub_cards", "")) == "legacy"
		and invalid.get_meta("plants", []) == legacy_plants and _new_resources_cold())
	invalid.free()

	OS.set_environment(ENV_KEYS[0], "legacy")
	OS.set_environment(ENV_KEYS[2], "off")
	var legacy_cards: Node3D = Woodland.build(field, scenery, "high", lake)
	OS.unset_environment(ENV_KEYS[2])
	OS.set_environment(ENV_KEYS[0], "source")
	var mixed: Node3D = Woodland.build(field, scenery, "high", lake)
	var balanced: Node3D = Woodland.build(field, scenery, "balanced", lake)
	OS.set_environment(ENV_KEYS[2], "off")
	var cards: Node3D = Woodland.build(field, scenery, "high", lake)
	OS.unset_environment(ENV_KEYS[2])
	var plants: Array = mixed.get_meta("plants", [])
	var expected := _expected_shrub_ids()
	var selection := _selection_contract(plants, legacy_plants, expected)
	_check("four intended paths use two cards of each source and preserve all other records",
		bool(selection.ok), str(selection))
	_check("mixed mode retains 220 IDs, 18 meshes, 202 cards, 2656 triangles and 13 batches",
		plants.size() == 220 and _unique_index(plants).size() == 220
		and _rendering_count(plants, "mesh") == 18 and _rendering_count(plants, "card") == 202
		and _geometry(mixed) == {triangles = 2656, batches = 13}
		and int(mixed.get_meta("triangles", -1)) == 2656 and int(mixed.get_meta("batches", -1)) == 13)
	_check("mesh opt-out keeps the same four shrub IDs with 472 triangles and five batches",
		bool(_selection_contract(cards.get_meta("plants", []), legacy_cards.get_meta("plants", []), expected).ok)
		and _geometry(cards) == {triangles = 472, batches = 5}
		and int(cards.get_meta("triangles", -1)) == 472 and int(cards.get_meta("batches", -1)) == 5)
	_check("all 18 mesh plans are byte-identical to the legacy build",
		legacy.get_meta("mesh_plans", []).size() == 18
		and var_to_bytes(legacy.get_meta("mesh_plans", [])) == var_to_bytes(mixed.get_meta("mesh_plans", [])))
	var mixed_bounds := _source_bounds(mixed, legacy, expected, field, lake)
	_check("mixed shrub transforms fit the old card side and height and touch sampled ground",
		bool(mixed_bounds.ok), str(mixed_bounds))
	var card_bounds := _source_bounds(cards, legacy_cards, expected, field, lake)
	_check("card-only shrub transforms fit the same independent legacy references",
		bool(card_bounds.ok), str(card_bounds))
	_check("balanced mode is a stable strict subset of high",
		_is_strict_subset(balanced.get_meta("plants", []), plants))
	var material := _batch_material(mixed)
	_check("source shader binds both four-frame shrub atlases", _material_contract(material))
	_check("source material is shared by the four independent pocket batches", _same_material(mixed, material))

	_check("source manifests identify valid four-view, square-frame shrub atlases", _manifest_contract())

	OS.unset_environment(ENV_KEYS[0])
	var default_shrubs: Node3D = Woodland.build(field, scenery, "high", lake)
	_check("the default shrub setting selects the available source cards",
		str(default_shrubs.get_meta("shrub_cards", "")) == "source"
		and default_shrubs.get_meta("plants", []) == plants)
	OS.set_environment(ENV_KEYS[0], "source")

	OS.set_environment(ENV_KEYS[1], "source")
	var both_sources: Node3D = Woodland.build(field, scenery, "high", lake)
	OS.set_environment(ENV_KEYS[0], "legacy")
	var fern_only: Node3D = Woodland.build(field, scenery, "high", lake)
	_check("fern and shrub switches independently select both source and legacy modes",
		str(mixed.get_meta("fern_cards", "")) == "legacy" and str(mixed.get_meta("shrub_cards", "")) == "source"
		and str(both_sources.get_meta("fern_cards", "")) == "source" and str(both_sources.get_meta("shrub_cards", "")) == "source"
		and str(fern_only.get_meta("fern_cards", "")) == "source" and str(fern_only.get_meta("shrub_cards", "")) == "legacy"
		and _count(both_sources.get_meta("plants", []), "polyhaven_fern_02_a", "card") == 22
		and _count(fern_only.get_meta("plants", []), "polyhaven_fern_02_a", "card") == 22
		and _count(fern_only.get_meta("plants", []), "bush_common_flowers", "card") == 6
		and _batch_material(fern_only).shader.resource_path == OLD_SHADER)

	if DisplayServer.get_name() == "headless":
		print("skip woodland shrub pixels: the headless renderer draws nothing")
	else:
		_check("compiled legacy shader exposes no shrub atlas samplers", _legacy_uniforms(legacy_material))
		await _pixel_cases(material)
	for node: Node in [legacy, legacy_cards, mixed, balanced, cards, both_sources, fern_only, default_shrubs]:
		node.free()
	_finish()


func _new_resources_cold() -> bool:
	if not Woodland._shrub_manifests.is_empty() or not Woodland._shrub_materials.is_empty():
		return false
	if ResourceLoader.has_cached(NEW_SHADER):
		return false
	for id: String in IDS:
		if ResourceLoader.has_cached(ATLAS_ROOT + id + "_4view.png"):
			return false
	return true


func _count(plants: Array, asset: String, rendering: String) -> int:
	var total := 0
	for plant: Dictionary in plants:
		if str(plant.get("asset_id", "")) == asset and str(plant.get("rendering", "")) == rendering:
			total += 1
	return total


func _rendering_count(plants: Array, rendering: String) -> int:
	var total := 0
	for plant: Dictionary in plants:
		if str(plant.get("rendering", "")) == rendering:
			total += 1
	return total


func _unique_index(plants: Array) -> Dictionary:
	var result := {}
	for plant: Dictionary in plants:
		var id := str(plant.get("id", ""))
		if id.is_empty() or result.has(id):
			return {}
		result[id] = plant
	return result


func _expected_shrub_ids() -> Dictionary:
	var recipe: Variant = JSON.parse_string(FileAccess.get_file_as_string(Woodland.DATA_PATH))
	var mapping := {"woodland-edge-east-north": IDS[0], "woodland-edge-east-south": IDS[0],
		"woodland-edge-southwest": IDS[1], "woodland-edge-northwest": IDS[1]}
	var expected := {}
	if not recipe is Dictionary:
		return expected
	for patch: Dictionary in recipe.get("patches", []):
		var patch_id := str(patch.id)
		var index: int = patch.shrub_species.rfind("bush_common_flowers")
		if not mapping.has(patch_id) or index < 0:
			return {}
		var points: Array[Vector2] = []
		for point: Array in patch.paths_ne_m[index]:
			points.append(Vector2(float(point[1]), -float(point[0])))
		var placements := Hedge.layout(points, float(patch.shrub_heights_m[index]),
			float(patch.shrub_width_m), int(patch.path_seeds[index]), "high")
		for record: Dictionary in placements:
			expected[str(record.id)] = mapping[patch_id]
	return expected


func _selection_contract(source: Array, legacy: Array, expected: Dictionary) -> Dictionary:
	var source_index := _unique_index(source)
	var old_index := _unique_index(legacy)
	var errors: Array[String] = []
	var counts := {IDS[0]: 0, IDS[1]: 0}
	if source_index.size() != source.size() or old_index.size() != legacy.size() or expected.size() != 4 \
			or source.size() != legacy.size():
		return {ok = false, errors = ["missing, duplicate or unexpected plant IDs"]}
	for id: Variant in old_index:
		if not source_index.has(id):
			errors.append("missing " + str(id))
			continue
		var old: Dictionary = old_index[id]
		var current: Dictionary = source_index[id]
		if expected.has(id):
			var asset := str(expected[id])
			counts[asset] = int(counts[asset]) + 1
			var normalized := current.duplicate(true)
			normalized.asset_id = old.asset_id
			normalized.height_m = old.height_m
			if normalized != old or str(current.asset_id) != asset or str(current.source_asset_id) != "bush_common_flowers" \
					or str(current.rendering) != "card" or float(current.height_m) <= 0.0 \
					or float(current.height_m) > float(old.height_m) + 0.00001:
				errors.append("source changed the identity or height of " + str(id))
		elif current != old:
			errors.append("unrelated plant changed " + str(id))
	if int(counts[IDS[0]]) != 2 or int(counts[IDS[1]]) != 2:
		errors.append("wrong source counts")
	return {ok = errors.is_empty(), counts = counts, errors = errors}


func _source_bounds(source: Node3D, legacy: Node3D, expected: Dictionary, field: Dictionary, lake: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var actual := _unique_index(source.get_meta("plants", []))
	var old := _unique_index(legacy.get_meta("plants", []))
	var table := GroundSurfaces.load_table()
	if not bool(table.get("ok", false)):
		return {ok = false, errors = ["surface table unavailable"]}
	var surfaces := GroundSurfaces.build(table.table, field)
	if not bool(surfaces.get("ok", false)):
		return {ok = false, errors = ["ground surfaces unavailable"]}
	var flower: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_ROOT + "bush_common_flowers_4view.json"))
	if not flower is Dictionary:
		return {ok = false, errors = ["legacy manifest unavailable"]}
	var flower_fraction := float(flower.source_height_m) / float(flower.frame_world_size_m[0])
	var frame := Hedge._frame_size(Hedge._manifest())
	var seen := {}
	for child: Node in source.get_children():
		if not child is MultiMeshInstance3D:
			continue
		var batch := child as MultiMeshInstance3D
		for item: Dictionary in batch.get_meta("source_card_records", []):
			var asset := str(item.get("asset_id", ""))
			if asset not in IDS:
				continue
			var id := str(item.get("id", ""))
			var index := int(item.get("index", -1))
			if not expected.has(id) or str(expected[id]) != asset or seen.has(id) \
					or not old.has(id) or not actual.has(id) or not item.get("transform") is Transform3D \
					or index < 0 or index >= batch.multimesh.instance_count:
				errors.append("invalid consumed record " + id)
				continue
			seen[id] = true
			var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_ROOT + asset + "_4view.json"))
			if not manifest is Dictionary:
				errors.append("missing source manifest " + asset)
				continue
			var previous: Dictionary = old[id]
			var plant: Dictionary = actual[id]
			var fraction := float(manifest.source_height_m) / float(manifest.frame_world_size_m[0])
			var transform: Transform3D = item.transform
			var scale := transform.basis.get_scale().abs()
			var side := frame * scale.x
			var old_side := float(previous.height_m) / flower_fraction
			var expected_side := minf(old_side, float(previous.height_m) / fraction)
			var ground: PackedFloat64Array = GroundTerrain.sample_validated(float(previous.north), float(previous.east), surfaces.rects, lake)
			var yaw := Basis(Vector3.UP, float(previous.yaw_rad))
			if ground.size() != 3 or absf(side - expected_side) > 0.0001 \
					or side * sqrt(0.5) > old_side * sqrt(0.5) + 0.0001 \
					or absf(side * fraction - float(plant.height_m)) > 0.0001 \
					or absf(float(item.height_m) - float(plant.height_m)) > 0.0001 \
					or absf(scale.x - scale.y) > 0.0001 or absf(scale.x - scale.z) > 0.0001 \
					or absf(transform.origin.x - float(previous.east)) > 0.002 \
					or absf(transform.origin.z + float(previous.north)) > 0.002 \
					or (ground.size() == 3 and absf(transform.origin.y - 0.5 * float(plant.height_m) - float(ground[0])) > 0.002) \
					or transform.basis.orthonormalized().x.distance_to(yaw.x) > 0.0001 \
					or transform.basis.orthonormalized().z.distance_to(yaw.z) > 0.0001:
				errors.append("side, visible height, yaw, position or terrain differs for " + id)
			if DisplayServer.get_name() != "headless":
				var data := batch.multimesh.get_instance_custom_data(index)
				var variant := float(IDS.find(asset) + 1)
				if not batch.multimesh.get_instance_transform(index).is_equal_approx(transform) \
						or absf(data.g - 1.0) > 0.001 or absf(data.b - variant) > 0.001:
					errors.append("GPU instance readback differs for " + id)
	if seen.size() != 4:
		errors.append("expected four consumed source-card records")
	return {ok = errors.is_empty(), cards = seen.size(), errors = errors}


func _is_strict_subset(subset: Array, superset: Array) -> bool:
	var small := _unique_index(subset)
	var large := _unique_index(superset)
	if small.size() != subset.size() or large.size() != superset.size() or subset.size() >= superset.size():
		return false
	for id: Variant in small:
		if not large.has(id) or small[id] != large[id]:
			return false
	return true


func _batch_material(root_node: Node3D) -> ShaderMaterial:
	for child: Node in root_node.get_children():
		if child is MultiMeshInstance3D:
			return (child as MultiMeshInstance3D).material_override as ShaderMaterial
	return null


func _same_material(root_node: Node3D, material: ShaderMaterial) -> bool:
	var batches := 0
	for child: Node in root_node.get_children():
		if child is MultiMeshInstance3D:
			batches += 1
			if (child as MultiMeshInstance3D).material_override != material:
				return false
	return batches == 4 and material != null


func _material_contract(material: ShaderMaterial) -> bool:
	if material == null or material.shader == null or material.shader.resource_path != NEW_SHADER:
		return false
	for index in IDS.size():
		var uniform_name := "shrub_atlas_a" if index == 0 else "shrub_atlas_b"
		var texture := material.get_shader_parameter(uniform_name) as Texture2D
		var path: String = ATLAS_ROOT + IDS[index] + "_4view.png"
		if texture == null or texture.resource_path != path or texture.get_width() != 1024 or texture.get_height() != 256:
			return false
	return true


func _manifest_contract() -> bool:
	for id: String in IDS:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_ROOT + id + "_4view.json"))
		if not data is Dictionary or data.get("format") != "openrc-vegetation-impostor v1" \
				or data.get("derived_from_asset_id") != id \
				or not data.get("atlas_size_px") is Array or data.atlas_size_px.size() != 2 \
				or not data.get("frame_size_px") is Array or data.frame_size_px.size() != 2 \
				or not data.get("baked_azimuth_deg") is Array or data.baked_azimuth_deg.size() != 4 \
				or not data.get("frame_world_size_m") is Array or data.frame_world_size_m.size() != 2:
			return false
		if float(data.atlas_size_px[0]) != 1024.0 or float(data.atlas_size_px[1]) != 256.0 \
				or float(data.frame_size_px[0]) != 256.0 or float(data.frame_size_px[1]) != 256.0:
			return false
		for frame in 4:
			if float(data.baked_azimuth_deg[frame]) != float(frame) * 90.0:
				return false
		var height := float(data.get("source_height_m", 0.0))
		var width := float(data.frame_world_size_m[0])
		var frame_height := float(data.frame_world_size_m[1])
		if not is_finite(height) or not is_finite(width) or not is_finite(frame_height) \
				or height <= 0.0 or width < height or not is_equal_approx(width, frame_height) \
				or Woodland._source_shrub_manifest(id) != data:
			return false
	return true


func _legacy_uniforms(material: ShaderMaterial) -> bool:
	if material == null or material.shader == null:
		return false
	var names: Array[String] = []
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		names.append(str(uniform.get("name", "")))
	return "impostor_atlas" in names and "shrub_atlas_a" not in names and "shrub_atlas_b" not in names


func _geometry(node: Node) -> Dictionary:
	var result := {triangles = 0, batches = 0}
	var mesh: Mesh = null
	var instances := 1
	if node is MultiMeshInstance3D:
		var multi := (node as MultiMeshInstance3D).multimesh
		if multi == null or multi.mesh == null:
			return {triangles = -1, batches = -1}
		mesh = multi.mesh
		instances = multi.instance_count
	elif node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
	if mesh != null:
		result.batches = 1
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			var count: int = indices.size() if indices is PackedInt32Array and not indices.is_empty() else vertices.size()
			result.triangles += int(count / 3) * instances
	for child: Node in node.get_children():
		var part := _geometry(child)
		if int(part.triangles) < 0:
			return part
		result.triangles += int(part.triangles)
		result.batches += int(part.batches)
	return result


# The eight rendered cases compare production sampling with a manual frame selector.
# Distinct colors make wrong atlas, frame, species or custom-data branches visible.
func _pixel_cases(production: ShaderMaterial) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(PIXELS, PIXELS)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.near = 0.01
	camera.far = 10.0
	viewport.add_child(camera)
	camera.current = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = quad
	multi.instance_count = 1
	multi.set_instance_color(0, Color.WHITE)
	var actual := MultiMeshInstance3D.new()
	actual.multimesh = multi
	actual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := production.duplicate() as ShaderMaterial
	var texture_a := _test_atlas([Color(0.8, 0.1, 0.1), Color(0.1, 0.8, 0.1), Color(0.1, 0.1, 0.8), Color(0.8, 0.8, 0.1)])
	var texture_b := _test_atlas([Color(0.7, 0.2, 0.7), Color(0.1, 0.7, 0.7), Color(0.7, 0.4, 0.1), Color(0.4, 0.2, 0.8)])
	var distractor := _test_atlas([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	material.set_shader_parameter("shrub_atlas_a", texture_a)
	material.set_shader_parameter("shrub_atlas_b", texture_b)
	material.set_shader_parameter("impostor_atlas", distractor)
	actual.material_override = material
	viewport.add_child(actual)
	var reference := MeshInstance3D.new()
	reference.mesh = quad
	reference.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var reference_material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = REFERENCE_SHADER
	reference_material.shader = shader
	reference.material_override = reference_material
	viewport.add_child(reference)
	for variant in [1, 2]:
		for frame in 4:
			var yaw := 0.0 if frame % 2 == 0 else PI * 0.5
			var angle := float(frame) * PI * 0.5 + yaw
			camera.look_at_from_position(Vector3(cos(angle), 0, -sin(angle)) * 3.0, Vector3.ZERO)
			reference.look_at(camera.position, Vector3.UP, true)
			multi.set_instance_transform(0, Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO))
			multi.set_instance_custom_data(0, Color(yaw / TAU, 1.0, float(variant), 1.0))
			reference_material.set_shader_parameter("atlas", texture_a if variant == 1 else texture_b)
			reference_material.set_shader_parameter("frame_number", float(frame))
			actual.visible = true
			reference.visible = false
			var got := await _viewport_pixel(viewport)
			actual.visible = false
			reference.visible = true
			var expected := await _viewport_pixel(viewport)
			var difference := maxf(absf(got.r - expected.r), maxf(absf(got.g - expected.g), absf(got.b - expected.b)))
			_pixel_checks += 1
			_check("variant %d frame %d yaw %d pixel selects its source" % [variant, frame, roundi(rad_to_deg(yaw))],
				got.a > 0.9 and expected.a > 0.9 and difference <= 3.0 / 255.0,
				str({actual = got, reference = expected, difference = difference}))
	viewport.free()
	await process_frame


func _test_atlas(colors: Array) -> ImageTexture:
	var image := Image.create(256, 64, false, Image.FORMAT_RGBA8)
	for frame in 4:
		for y in 64:
			for x in 64:
				image.set_pixel(frame * 64 + x, y, colors[frame])
	return ImageTexture.create_from_image(image)


func _viewport_pixel(viewport: SubViewport) -> Color:
	for _index in 3:
		await process_frame
		RenderingServer.force_draw(false)
	return viewport.get_texture().get_image().get_pixel(PIXELS / 2, PIXELS / 2)


func _finish() -> void:
	for key: String in _saved_env:
		var saved: Dictionary = _saved_env[key]
		if bool(saved.present):
			OS.set_environment(key, str(saved.value))
		else:
			OS.unset_environment(key)
	print("woodland shrub cards: %d checks, %d pixel checks, %d failures" % [_checks, _pixel_checks, _failures])
	quit(1 if _failures > 0 else 0)
