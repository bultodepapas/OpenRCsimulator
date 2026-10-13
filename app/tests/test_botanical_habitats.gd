## LU-23: the default scene's understory uses downloaded geometry and retained damage IDs.
extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const Scenery := preload("res://scenery/scenery.gd")
const ImportedVegetation := preload("res://scenery/imported_vegetation.gd")
const Clock := preload("res://render/shader_clock.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	Clock.register()
	var field_result: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads", bool(field_result.get("ok", false)))
	if not bool(field_result.get("ok", false)):
		quit(1)
		return
	var field: Dictionary = field_result.field
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field)
	_check("downloaded scenery layout loads", bool(scenery_result.get("ok", false)))
	if not bool(scenery_result.get("ok", false)):
		quit(1)
		return
	var source_scenery: Dictionary = scenery_result.scenery
	_check("generated default has no retired procedural cushion group",
		not source_scenery.groups.any(func(group: Dictionary) -> bool: return str(group.get("id", "")) == "wildflowers"))
	var built := Scenery.build(field, source_scenery, {audio = false, birds = false, theme = "", quality = "high"})
	_test_imported_habitats(built.get_node_or_null("BotanicalHabitats") as Node3D)
	_test_downloaded_damage(built.get_node_or_null("ImportedVegetationBatches") as Node3D)
	built.free()
	print("downloaded vegetation scene checks: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_imported_habitats(root: Node3D) -> void:
	var plants: Array = root.get_meta("plants", []) if root != null else []
	var triangle_total := int(root.get_meta("triangles", 0)) if root != null else 0
	var budget := int(root.get_meta("triangle_budget", 0)) if root != null else 0
	var batch_limit := int(root.get_meta("batch_limit", 0)) if root != null else 0
	var batches := int(root.get_meta("batches", 0)) if root != null else 0
	_check("production attaches downloaded habitat batches", root != null and not plants.is_empty()
		and root.get_children().all(func(child: Node) -> bool: return child is MultiMeshInstance3D))
	_check("source geometry stays within the provisional triangle budget",
		triangle_total > 0 and budget == 70000 and triangle_total <= budget)
	_check("source meshes share no more than 24 runtime batches", batch_limit == 24 and batches <= batch_limit
		and batches == root.get_child_count())
	var only_downloads := true
	for plant_value: Variant in plants:
		if not plant_value is Dictionary:
			only_downloads = false
			continue
		var plant: Dictionary = plant_value
		var asset_id := str(plant.get("asset_id", ""))
		only_downloads = only_downloads and not ImportedVegetation.get_asset(asset_id).is_empty()
		only_downloads = only_downloads and int(plant.get("source_triangles", 0)) > 0
	_check("every habitat placement resolves to a downloaded catalog mesh", only_downloads)


func _test_downloaded_damage(root: Node3D) -> void:
	var state: Dictionary = root.get_meta("_imported_vegetation_state", {}) if root != null else {}
	var damage: Dictionary = state.get("damage", {})
	var damage_ids: Array = damage.keys()
	damage_ids.sort()
	_check("near vegetation retains production damage IDs", not damage_ids.is_empty())
	if root == null or damage_ids.is_empty():
		return
	var damage_id := str(damage_ids[0])
	var hidden := ImportedVegetation.set_damage_hidden(root, damage_id, true)
	var after_hide: Dictionary = root.get_meta("_imported_vegetation_state", {})
	var bounds_records: Array = after_hide.get("bounds", [])
	var records_hidden := hidden
	for item: Dictionary in damage.get(damage_id, []):
		var bounds_index := int(item.get("bounds_index", -1))
		records_hidden = records_hidden and bounds_index >= 0 and bounds_index < bounds_records.size()
		if bounds_index >= 0 and bounds_index < bounds_records.size():
			records_hidden = records_hidden and bool(bounds_records[bounds_index].get("hidden", false))
	_check("breaking one prop hides its downloaded mesh record", records_hidden, damage_id)
	_check("damage reset restores its downloaded mesh record", ImportedVegetation.set_damage_hidden(root, damage_id, false), damage_id)


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		return
	failures += 1
	printerr("FAIL: %s %s" % [label, detail])
