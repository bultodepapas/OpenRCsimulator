## VQ-06b: the Scene detail preset maps one saved choice onto scenery tier, 3D field trees and LOD,
## and never changes field-tree collision.
## Run: godot --headless --path . --script res://tests/test_scene_detail.gd
extends SceneTree

const SceneDetail := preload("res://render/scene_detail.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const SettingsScreen := preload("res://ui/settings_screen.gd")
const Scenery := preload("res://scenery/scenery.gd")
const Field := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Treeline := preload("res://render/treeline.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const PREFS := "user://test_scene_detail_display.cfg"

var _failures := 0


func _initialize() -> void:
	await _run()
	_clean()
	print("scene detail tests passed" if _failures == 0 else "%d scene detail test(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	_clean()
	OS.set_environment("OPENRC_SCENE_DETAIL", "")
	OS.set_environment("OPENRC_SCENERY_QUALITY", "")
	_test_levels()
	_test_preferences()
	await _test_settings_row()
	_test_field_and_collision()
	SceneDetail.set_preference("")


func _test_levels() -> void:
	var saved_values: Array[String] = [SceneDetail.AUTO]
	saved_values.append_array(SceneDetail.LEVELS)
	_check("the saved values are Automatic plus the preset levels", DisplayPreferences.SCENE_DETAILS == saved_values
		and DisplayPreferences.DEFAULTS.scene_detail == SceneDetail.AUTO and SceneDetail.DEFAULT == "high")
	_test_recommendations()
	SceneDetail.set_preference("")
	_check("no choice means High", SceneDetail.level() == "high")
	var qualities := []
	var previous := {}
	for level: String in SceneDetail.LEVELS:
		var profile: Dictionary = SceneDetail.PROFILES[level]
		qualities.append(profile.scenery_quality)
		if not previous.is_empty():
			_check("%s never costs less than the level below" % level,
				float(profile.mesh_lod_threshold_px) <= float(previous.mesh_lod_threshold_px)
				and float(profile.field_tree_half_angle_deg) >= float(previous.field_tree_half_angle_deg))
		previous = profile
	_check("scenery tiers rise with the preset", qualities == ["low", "balanced", "high", "high"], str(qualities))
	_check("High keeps the L8a-R1 front trees and Godot's lossless LOD threshold",
		SceneDetail.PROFILES.high.field_tree_half_angle_deg == Treeline.DETAIL_HALF_ANGLE_DEG
		and SceneDetail.PROFILES.high.mesh_lod_threshold_px == 1.0)
	SceneDetail.set_preference("medium")
	_check("the saved choice selects the level", SceneDetail.level() == "medium")
	_check("the saved choice sets the scenery tier", Scenery.options().quality == "balanced")
	OS.set_environment("OPENRC_SCENERY_QUALITY", "high")
	_check("an explicit scenery tier still wins", Scenery.options().quality == "high")
	OS.set_environment("OPENRC_SCENERY_QUALITY", "")
	OS.set_environment("OPENRC_SCENE_DETAIL", "extreme")
	_check("the environment overrides the saved choice", SceneDetail.level() == "extreme")
	OS.set_environment("OPENRC_SCENE_DETAIL", "")
	SceneDetail.set_preference("ultra")
	_check("an unknown saved value falls back to High", SceneDetail.level() == "high")
	var viewport := SubViewport.new()
	root.add_child(viewport)
	SceneDetail.apply(viewport, "low")
	_check("applying Low raises the viewport LOD threshold at once", is_equal_approx(viewport.mesh_lod_threshold, 4.0))
	SceneDetail.apply(viewport, "extreme")
	_check("applying Extreme restores Godot's 1 px threshold", is_equal_approx(viewport.mesh_lod_threshold, 1.0))
	viewport.free()


## VQ-06b-R1: GL renderer strings as drivers report them, and the level Automatic picks.
func _test_recommendations() -> void:
	var cases := {
		"llvmpipe (LLVM 20.1.2, 256 bits)|Mesa": "low",
		"Microsoft Basic Render Driver|Microsoft": "low",
		"Mali-G78|ARM": "low",
		"NVIDIA GeForce RTX 3090/PCIe/SSE2|NVIDIA Corporation": "high",
		"AMD Radeon RX 6800 XT|ATI Technologies Inc.": "high",
		"Intel(R) Arc(TM) A770 Graphics|Intel": "high",
		"ANGLE (NVIDIA, NVIDIA GeForce GTX 1060 Direct3D11 vs_5_0 ps_5_0)|Google Inc.": "high",
		"NVIDIA GeForce MX250/PCIe/SSE2|NVIDIA Corporation": "medium",
		"Intel(R) UHD Graphics 620|Intel": "medium",
		"Mesa Intel(R) Iris(R) Xe Graphics (TGL GT2)|Intel": "medium",
		"AMD Radeon(TM) Graphics|ATI Technologies Inc.": "medium",
		"ANGLE (Apple, ANGLE Metal Renderer: Apple M1, Unspecified Version)|Google Inc.": "medium",
		"Some Future GPU 9000|Acme": "high",
		"|": "high",
	}
	for gpu: String in cases:
		var parts := gpu.split("|")
		var picked: Dictionary = SceneDetail.recommend(parts[0], parts[1])
		_check("Automatic picks %s for '%s'" % [cases[gpu], parts[0]], picked.level == cases[gpu],
			"%s (%s)" % [picked.level, picked.reason])
		_check("Automatic never picks Extreme for '%s'" % parts[0], picked.level != "extreme")
	SceneDetail.set_preference(SceneDetail.AUTO)
	SceneDetail.adapter_override = PackedStringArray(["llvmpipe (LLVM 20.1.2, 256 bits)", "Mesa"])
	_check("a saved Automatic resolves through the detected GPU", SceneDetail.level() == "low"
		and Scenery.options().quality == "low")
	SceneDetail.adapter_override = PackedStringArray(["Intel(R) UHD Graphics 620", "Intel"])
	_check("Automatic follows a different GPU at the next launch", SceneDetail.level() == "medium")
	SceneDetail.adapter_override = PackedStringArray()
	SceneDetail.set_preference("low")
	_check("a saved level wins over detection", SceneDetail.level() == "low")
	SceneDetail.set_preference("")


func _test_preferences() -> void:
	var candidate: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	candidate.scene_detail = "extreme"
	_check("a scene detail choice is saved and reloaded", DisplayPreferences.save_to(PREFS, candidate) == OK
		and DisplayPreferences.load_from(PREFS).scene_detail == "extreme")
	candidate.scene_detail = "ultra"
	_check("an unknown scene detail is refused", not DisplayPreferences.validate(candidate).ok)
	var older: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	older.erase("scene_detail")
	var checked := DisplayPreferences.validate(older)
	_check("settings saved before VQ-06b load with Automatic", checked.ok and checked.config.scene_detail == "auto")


func _test_settings_row() -> void:
	_clean()
	var store := DisplayPreferences.new(PREFS)
	var settings := SettingsScreen.new(store, "en")
	root.add_child(settings)
	await process_frame
	var picker: OptionButton = settings.find_child("SceneDetail", true, false)
	_check("Settings > Graphics shows Scene detail with Automatic selected", picker != null and picker.item_count == 5
		and picker.get_item_metadata(picker.selected) == "auto"
		and picker.get_item_text(0) == "Automatic (%s)" % str(SceneDetail.detected().level).capitalize(),
		picker.get_item_text(0) if picker != null else "")
	if picker != null:
		picker.select(4)
		picker.item_selected.emit(4)
		settings.keep_changes()
		_check("keeping Extreme saves it", DisplayPreferences.load_from(PREFS).scene_detail == "extreme")
		settings._restore_graphics_defaults()
		_check("restoring graphics defaults returns to Automatic", settings._draft.scene_detail == "auto")
	settings.queue_free()
	await process_frame


func _test_field_and_collision() -> void:
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var trees: Dictionary = field.objects[0]
	var near_ring := 0
	for point: Array in trees.positions:
		if Vector2(point[0], point[1]).length() <= Treeline.DETAIL_MAX_RADIUS_M:
			near_ring += 1
	var expected := {"low": 0, "medium": 0, "high": 127, "extreme": near_ring}
	var reference_trees := []
	for level: String in SceneDetail.LEVELS:
		SceneDetail.set_preference(level)
		var built := Field.build(field)
		var cards := 0
		for batch: MultiMeshInstance3D in built.get_node("treeline").get_children():
			cards += batch.multimesh.instance_count
		var detail := 0
		var detail_node := built.get_node_or_null("treelineDetail")
		if detail_node != null:
			for batch: MultiMeshInstance3D in detail_node.find_children("*", "MultiMeshInstance3D", true, false):
				detail += batch.multimesh.instance_count
		_check("%s draws %d field trees in 3D and the rest as cards" % [level, expected[level]],
			detail == expected[level] and cards + detail == trees.positions.size(), "%d + %d" % [cards, detail])
		built.free()
		var world: Dictionary = CollisionWorld.build(field, {groups = []})
		var tree_proxies := []
		if bool(world.get("ok", false)):
			tree_proxies = world.world.proxies.filter(func(p: Dictionary) -> bool: return str(p.id).begins_with("tree:treeline:"))
		if reference_trees.is_empty():
			reference_trees = tree_proxies
		_check("%s leaves field-tree collision unchanged" % level, not tree_proxies.is_empty() and tree_proxies == reference_trees)
	_check("Extreme covers the whole near ring", near_ring > 127, str(near_ring))
	SceneDetail.set_preference("")


func _clean() -> void:
	for candidate in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s %s" % [label, detail])
