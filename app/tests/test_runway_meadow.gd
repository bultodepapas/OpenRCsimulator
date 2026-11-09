## L11a-R3: runway meadow colonies are deterministic, nested by quality, budgeted and keep
## the runway, rotor pad, pilot station and grass masks clear.
extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const Meadow := preload("res://scenery/runway_meadow.gd")
const NearGrass := preload("res://render/near_grass.gd")
const GrassMask := preload("res://render/landscape_upgrade/scenery_grass_mask.gd")
const Clock := preload("res://render/shader_clock.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const Scenery := preload("res://scenery/scenery.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	Clock.register()
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads", bool(loaded.get("ok", false)))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var field: Dictionary = loaded.field
	_test_grass_height_transition()
	var high := Meadow.layout(field, "high")
	var repeat := Meadow.layout(field, "high")
	var balanced := Meadow.layout(field, "balanced")
	var low := Meadow.layout(field, "low")
	_check("layout is non-empty", high.size() > 1000, str(high.size()))
	_check("layout is deterministic", _keys(high) == _keys(repeat))
	_check("quality tiers shrink", low.size() < balanced.size() and balanced.size() < high.size(),
		"%d/%d/%d" % [low.size(), balanced.size(), high.size()])
	var high_keys := _key_set(high)
	_check("balanced is a nested subset of high", _subset(balanced, high_keys))
	_check("low is a nested subset of high", _subset(low, high_keys))

	var triangles := 0
	var species: Dictionary = {}
	var colonies: Dictionary = {}
	var clear := true
	var sized := true
	var close_grass := 0
	var short_near_pilot := true
	var accents_keep_height := true
	for plant: Dictionary in high:
		triangles += int(plant.source_triangles)
		species[plant.asset_id] = int(species.get(plant.asset_id, 0)) + 1
		colonies[plant.colony] = int(colonies.get(plant.colony, 0)) + 1
		clear = clear and NearGrass.accepts(float(plant.north), float(plant.east), field)
		var height := float(plant.height_m)
		sized = sized and height > 0.03 and height < 0.7 and is_finite(float(plant.ground_up_m))
		var source_range: Vector2 = Meadow.HEIGHT_RANGES[plant.asset_id]
		if str(plant.asset_id).begins_with("grass_"):
			if Vector2(float(plant.north) - float(field.pilot.north), float(plant.east) - float(field.pilot.east)).length() <= 6.0:
				close_grass += 1
				short_near_pilot = short_near_pilot and height <= source_range.y * 0.45 + 0.000001
		else:
			accents_keep_height = accents_keep_height and height >= source_range.x and height <= source_range.y
	_check("budget holds", triangles <= Meadow.MAX_SOURCE_TRIANGLES, str(triangles))
	_check("runway, rotor pad and pilot station stay clear", clear)
	_check("heights stay within the short-rough envelope", sized)
	_check("near-pilot grass uses shorter whole-plant heights", close_grass > 0 and short_near_pilot)
	_check("flowers and clover retain their source height ranges", accents_keep_height)
	_check("photographic cards dominate", int(species.get("grass_lolipop_small", 0)) \
		+ int(species.get("grass_lolipop_tall", 0)) > high.size() * 0.8, str(species))
	for asset_id: String in Meadow.SPECIES_CAPS.keys():
		_check("%s stays inside its cap" % asset_id,
			int(species.get(asset_id, 0)) <= int(Meadow.SPECIES_CAPS[asset_id]), str(species))
	for kind: String in ["tussock", "clover", "flowers", "lip", "scatter"]:
		_check("colony kind %s is present" % kind, int(colonies.get(kind, 0)) > 0, str(colonies))

	# A footprint mask removes every plant inside it.
	var mask := GrassMask._record("probe", "building", PackedVector2Array([
		Vector2(24.0, -10.0), Vector2(24.0, 10.0), Vector2(34.0, 10.0), Vector2(34.0, -10.0)]))
	var masked := Meadow.layout(field, "high", [mask])
	var inside := 0
	for plant: Dictionary in masked:
		if float(plant.north) >= 24.0 and float(plant.north) <= 34.0 \
				and float(plant.east) >= -10.0 and float(plant.east) <= 10.0:
			inside += 1
	_check("exclusion masks are honoured", inside == 0 and masked.size() < high.size(), str(inside))

	var root := Meadow.build(field, "low")
	_check("build creates bounded batches", root.get_child_count() > 0 and root.get_child_count() <= 24,
		str(root.get_child_count()))
	var tinted := false
	for child: Node in root.get_children():
		if child is MultiMeshInstance3D:
			var batch := child as MultiMeshInstance3D
			_check("%s casts no shadow" % batch.name,
				batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			if str(batch.name).begins_with("grass_lolipop_"):
				var material := batch.multimesh.mesh.surface_get_material(0) as ShaderMaterial
				tinted = material != null and bool(material.get_shader_parameter("use_vertex_color"))
	_check("photographic cards use the clump tint", tinted)
	_check("build joins the live-visibility group", root.is_in_group(Meadow.GROUP))
	root.free()

	# Graphics setting: display preferences mirror the module, unknown values fall back to on.
	_check("display preference levels mirror the module",
		DisplayPreferences.RUNWAY_MEADOW_LEVELS == Meadow.PREFERENCES
		and DisplayPreferences.DEFAULTS.runway_meadow == Meadow.DEFAULT_PREFERENCE)
	var off_config := DisplayPreferences.DEFAULTS.duplicate(true)
	off_config.runway_meadow = "off"
	var checked: Dictionary = DisplayPreferences.validate(off_config)
	_check("off validates", bool(checked.ok) and checked.config.runway_meadow == "off", str(checked.errors))
	off_config.runway_meadow = "dense"
	_check("unknown level is rejected", not bool(DisplayPreferences.validate(off_config).ok))
	Meadow.set_preference("off")
	_check("scenery options follow the off preference", not bool(Scenery.options().runway_meadow))
	Meadow.set_preference("bogus")
	_check("unknown preference falls back to on", Meadow.preference() == "on" and bool(Scenery.options().runway_meadow))
	print("runway meadow checks: %d checks, %d failures; high plants=%d triangles=%d" % [
		checks, failures, high.size(), triangles])
	quit(1 if failures > 0 else 0)


func _test_grass_height_transition() -> void:
	# Separate the pilot and runway to observe each maintained zone independently.
	var area := {rn = 100.0, re = 0.0, half_n = 5.0, half_e = 5.0, pilot_n = 0.0, pilot_e = 0.0}
	_check("pilot turf keeps grass at 45 percent of its rough height",
		is_equal_approx(Meadow._grass_height_scale(area, 0.0, 0.0), 0.45))
	_check("the mown lip keeps grass at 45 percent of its rough height",
		is_equal_approx(Meadow._grass_height_scale(area, 100.0, 5.7), 0.45))
	_check("outer meadow retains full source-recipe height",
		is_equal_approx(Meadow._grass_height_scale(area, 50.0, 0.0), 1.0))
	var bounded_and_continuous := true
	var previous := 0.45
	for step in 121:
		var value := Meadow._grass_height_scale(area, 6.0 + float(step) * 0.1, 0.0)
		bounded_and_continuous = bounded_and_continuous and value >= previous - 0.000001 \
			and value >= 0.45 and value <= 1.0 and value - previous < 0.01
		previous = value
	_check("pilot grass grades continuously into the rough", bounded_and_continuous and is_equal_approx(previous, 1.0))
	var translated := area.duplicate()
	for key: String in ["rn", "pilot_n"]: translated[key] += 137.25
	for key: String in ["re", "pilot_e"]: translated[key] -= 82.75
	_check("grass maintenance follows a translated field",
		is_equal_approx(Meadow._grass_height_scale(area, 11.0, 0.0),
			Meadow._grass_height_scale(translated, 148.25, -82.75)))


func _keys(plants: Array[Dictionary]) -> Array:
	var result: Array = []
	for plant: Dictionary in plants:
		result.append("%d:%s:%.4f:%.4f:%.4f" % [int(plant.seed), plant.asset_id, plant.north, plant.east, plant.height_m])
	return result


func _key_set(plants: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for key: String in _keys(plants):
		result[key] = true
	return result


func _subset(plants: Array[Dictionary], superset: Dictionary) -> bool:
	for key: String in _keys(plants):
		if not superset.has(key):
			return false
	return true


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		return
	failures += 1
	printerr("FAIL: %s %s" % [label, detail])
