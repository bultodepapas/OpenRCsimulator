## LU-18: near-grass sample centers clear normalized scenery foundations and gravel by 0.4 m.
## Run: godot --headless --path . --script res://tests/test_landscape_scenery_grass_mask.gd
extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const FieldBuilder := preload("res://render/field.gd")
const NearGrass := preload("res://render/near_grass.gd")
const ImportedNearGrass := preload("res://scenery/imported_near_grass.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const Scenery := preload("res://scenery/scenery.gd")
const LakeWorld := preload("res://render/lake/lake_world.gd")
const GrassMask := preload("res://render/landscape_upgrade/scenery_grass_mask.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	var field_result: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads", field_result.ok)
	if not field_result.ok:
		_finish()
		return
	var loaded: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field_result.field)
	_check("default normalized scenery loads", loaded.ok, str(loaded.errors))
	if not loaded.ok:
		_finish()
		return
	_test_default_footprints(loaded.scenery)
	_test_rotated_translated_pavilion()
	_test_gravel_clearance()
	_test_empty_and_unrelated_scenery()
	_test_field_builder_mask_integration(field_result.field, loaded.scenery)
	_finish()


func _test_default_footprints(scenery: Dictionary) -> void:
	var footprints := GrassMask.footprints(scenery)
	_check("normalized building, pit and gravel groups produce footprints", footprints.size() >= 5, str(footprints.size()))
	var pavilion := _find(footprints, "pavilion:0:pavilion")
	_check("pavilion mask uses slab dimensions and veranda offset", not pavilion.is_empty()
		and is_equal_approx(float(pavilion.north_min), -25.5)
		and is_equal_approx(float(pavilion.north_max), -15.9)
		and is_equal_approx(float(pavilion.east_min), -5.0)
		and is_equal_approx(float(pavilion.east_max), 5.0), str(pavilion))
	_check("grass centers under the pavilion door/slab are excluded",
		GrassMask.excludes(-18.98, 0.0, footprints))
	_check("grass centers in the open runway field remain eligible for scenery mask",
		not GrassMask.excludes(10.0, 100.0, footprints))
	var pit := _find(footprints, "pit-shelters:0:pit_shelter")
	_check("normalized pit placement masks its concrete slab", not pit.is_empty()
		and is_equal_approx(float(pit.east_min), -45.3)
		and is_equal_approx(float(pit.east_max), -16.7), str(pit))
	var gravel := _find(footprints, "car-park")
	_check("normalized gravel apron masks grass centers", not gravel.is_empty()
		and GrassMask.excludes(-40.0, -15.0, footprints))


func _test_rotated_translated_pavilion() -> void:
	var custom_scenery := {groups = [{
		"id": "custom-club", "type": "instances", "prefab": "pavilion",
		"placements": [{north = 12.0, east = -7.0, heading = 90.0, prefab = "pavilion"}],
	}]}
	var footprints := GrassMask.footprints(custom_scenery)
	_check("a custom translated/rotated pavilion is discovered", footprints.size() == 1)
	if footprints.is_empty():
		return
	var pavilion: Dictionary = footprints[0]
	_check("rotated rectangle follows N/E scenery heading",
		is_equal_approx(float(pavilion.north_min), 7.0)
		and is_equal_approx(float(pavilion.north_max), 17.0)
		and is_equal_approx(float(pavilion.east_min), -10.5)
		and is_equal_approx(float(pavilion.east_max), -0.9), str(pavilion))
	# Local doorway is at X=0, Z=-3.02; with 90° heading it moves 3.02 m east.
	_check("rotated door remains over its slab and grass is omitted there",
		GrassMask.excludes(12.0, -3.98, footprints))
	# The concrete slab ends at local X=5.0; the mask margin is inclusive at 0.4 m.
	_check("clearance excludes centers 0.39 m beyond a rotated slab edge",
		GrassMask.excludes(6.61, -5.7, footprints))
	_check("clearance allows centers 0.41 m beyond a rotated slab edge",
		not GrassMask.excludes(6.59, -5.7, footprints))


func _test_gravel_clearance() -> void:
	var gravel_patch := {groups = [{
		"id": "custom-gravel", "type": "patch", "surface": "gravel",
		"points": PackedVector2Array([Vector2(0, 0), Vector2(0, 2), Vector2(2, 2), Vector2(2, 0)]),
	}]}
	var patch_footprints := GrassMask.footprints(gravel_patch)
	_check("normalized gravel patch is preserved as a polygon", patch_footprints.size() == 1
		and str(patch_footprints[0].kind) == "gravel_patch")
	_check("gravel patch interior excludes grass", GrassMask.excludes(1.0, 1.0, patch_footprints))
	_check("gravel patch margin blocks at 0.39 m", GrassMask.excludes(-0.39, 1.0, patch_footprints))
	_check("gravel patch margin releases beyond 0.4 m", not GrassMask.excludes(-0.41, 1.0, patch_footprints))
	var gravel_track := {groups = [{
		"id": "custom-gravel-track", "type": "track", "surface": "gravel", "width": 2.0,
		"points": PackedVector2Array([Vector2(0, 0), Vector2(0, 4)]),
	}]}
	var track_footprints := GrassMask.footprints(gravel_track)
	_check("normalized gravel track expands to a buffered polygon", track_footprints.size() == 1
		and str(track_footprints[0].kind) == "gravel_track")
	_check("gravel track width and clearance exclude grass", GrassMask.excludes(1.3, 2.0, track_footprints))
	_check("gravel track releases centers beyond width plus clearance",
		not GrassMask.excludes(1.41, 2.0, track_footprints))


func _test_empty_and_unrelated_scenery() -> void:
	_check("empty/off scenery yields no masks", GrassMask.footprints({}).is_empty())
	var props := {groups = [{
		"id": "car-row", "type": "instances", "prefab": "car_sedan",
		"placements": [{north = 0.0, east = 0.0, heading = 0.0, prefab = "car_sedan"}],
	}]}
	_check("unrelated vehicle props do not become building masks", GrassMask.footprints(props).is_empty())
	_check("empty mask never excludes grass", not GrassMask.excludes(0.0, 0.0, []))


func _test_field_builder_mask_integration(field: Dictionary, scenery: Dictionary) -> void:
	var saved := {
		"OPENRC_SCENERY": OS.get_environment("OPENRC_SCENERY"),
		"OPENRC_SCENERY_FILE": OS.get_environment("OPENRC_SCENERY_FILE"),
		"OPENRC_SCENERY_AUDIO": OS.get_environment("OPENRC_SCENERY_AUDIO"),
		"OPENRC_SCENERY_BIRDS": OS.get_environment("OPENRC_SCENERY_BIRDS"),
	}
	OS.set_environment("OPENRC_SCENERY_FILE", "")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	var default_footprints := GrassMask.footprints(scenery)
	var raw_rows: Variant = JSON.parse_string(FileAccess.get_file_as_string(NearGrass.DATA_PATH))
	var rows: Array = NearGrass.validated_rows(raw_rows)
	OS.set_environment("OPENRC_SCENERY", "off")
	var plain_field: Node3D = FieldBuilder.build(field)
	var plain_grass: Node3D = plain_field.get_node_or_null("NearGrass") as Node3D
	var plain_chunks: Array = NearGrass.clipped_chunks(field, rows)
	var plain_centers := _layout_centers(plain_chunks)
	var plain_overlaps := _count_excluded(plain_centers, default_footprints)
	var plain_expected := _layout_count(plain_chunks)
	_check("scenery-off field builds without a scenery exclusion node",
		plain_field.get_node_or_null("Scenery") == null and plain_grass != null)
	_check("scenery-off field retains grass centers under the default pavilion slab",
		plain_overlaps > 0, "overlapping clump centers=%d" % plain_overlaps)
	_check("scenery-off field keeps the unmasked grass count",
		plain_centers.size() == plain_expected and plain_grass != null
		and int(plain_grass.get_meta("clumps", -1)) == plain_expected,
		"actual=%d expected=%d" % [plain_centers.size(), plain_expected])
	plain_field.free()

	OS.set_environment("OPENRC_SCENERY", "on")
	var furnished_field: Node3D = FieldBuilder.build(field)
	var scenery_node: Node = furnished_field.get_node_or_null("Scenery")
	var grass_node: Node3D = furnished_field.get_node_or_null("NearGrass") as Node3D
	var exclusions: Array = scenery_node.get_meta("grass_exclusions", []) if scenery_node != null else []
	var furnished_chunks: Array = NearGrass.clipped_chunks(field, rows, exclusions)
	var furnished_centers := _layout_centers(furnished_chunks)
	var furnished_overlaps := _count_excluded(furnished_centers, default_footprints)
	var furnished_legacy_expected := _layout_count(furnished_chunks)
	_check("enabled full-field build attaches normalized grass exclusions to Scenery",
		scenery_node != null and not exclusions.is_empty())
	_check("enabled full-field build removes centers under concrete while scenery-off retains them",
		plain_overlaps > 0 and furnished_overlaps == 0 and furnished_centers.size() < plain_centers.size(),
		"off=%d on=%d clumps off=%d on=%d" % [plain_overlaps, furnished_overlaps, plain_centers.size(), furnished_centers.size()])
	_check("legacy NearGrass clipping consumes the attached exclusion array",
		furnished_centers.size() == furnished_legacy_expected and furnished_overlaps == 0,
		"centers=%d expected=%d exclusions=%d" % [furnished_centers.size(), furnished_legacy_expected, exclusions.size()])
	var source_definition: Dictionary = scenery_node.get_meta("source_definition", {}) if scenery_node != null else {}
	var lake: Dictionary = LakeWorld.resolve(field, Scenery.options()).get("lake", {})
	var production_masks := ImportedNearGrass.exclusions_for(source_definition, lake)
	var imported_expected := ImportedNearGrass.layout(field, "high", production_masks)
	var imported_unmasked := ImportedNearGrass.layout(field, "high")
	var imported_placements: Array = grass_node.get_meta("cpu_placements", []) if grass_node != null else []
	var imported_indices: Dictionary = {}
	for plant: Dictionary in imported_placements:
		imported_indices[int(plant.get("row_index", -1))] = true
	var expected_indices: Dictionary = {}
	for plant: Dictionary in imported_expected:
		expected_indices[int(plant.get("row_index", -1))] = true
	var unmasked_indices: Dictionary = {}
	for plant: Dictionary in imported_unmasked:
		unmasked_indices[int(plant.get("row_index", -1))] = true
	var imported_clear := grass_node != null and bool(grass_node.get_meta("imported", false))
	for plant: Dictionary in imported_placements:
		imported_clear = imported_clear and NearGrass.accepts(float(plant.north), float(plant.east), field, production_masks)
	_check("production NearGrass batches only downloaded clumps allowed by attached exclusions",
		imported_clear and imported_indices == expected_indices and imported_placements.size() == imported_expected.size()
		and _multimesh_count(grass_node) == imported_expected.size()
		and not production_masks.is_empty() and imported_indices != unmasked_indices,
		"actual=%d expected=%d unmasked=%d clear=%s row_ids_match=%s changed_by_masks=%s meshes=%d masks=%d"
		% [imported_placements.size(), imported_expected.size(), imported_unmasked.size(), imported_clear,
		imported_indices == expected_indices, imported_indices != unmasked_indices,
		_multimesh_count(grass_node), production_masks.size()])
	furnished_field.free()

	var translated := _translated_ineligible_field(1.0, 0.5)
	_check("translated default-id field remains valid but is scenery-ineligible", not translated.is_empty())
	var translated_ghost_overlaps := 0
	if not translated.is_empty():
		var translated_field: Node3D = FieldBuilder.build(translated)
		var translated_scenery: Node = translated_field.get_node_or_null("Scenery")
		var translated_grass: Node3D = translated_field.get_node_or_null("NearGrass") as Node3D
		var translated_chunks: Array = NearGrass.clipped_chunks(translated, rows)
		var translated_centers := _layout_centers(translated_chunks)
		var ghost_overlaps := _count_excluded(translated_centers, default_footprints)
		translated_ghost_overlaps = ghost_overlaps
		_check("ineligible translated field attaches no default scenery or ghost mask",
			translated_scenery == null and not translated_field.has_meta("grass_exclusions"))
		_check("ineligible field's grass remains at the old default building coordinates",
			translated_grass != null and ghost_overlaps > 0
			and _multimesh_count(translated_grass) == _layout_count(translated_chunks)
			and int(translated_grass.get_meta("clumps", -1)) == _layout_count(translated_chunks),
			"grass centers under old pavilion footprint=%d" % ghost_overlaps)
		translated_field.free()
	print("LU-18 field integration: off=%d clumps, on=%d clumps, %d default-footprint centers removed, translated no-scenery=%d"
		% [plain_centers.size(), furnished_centers.size(), plain_centers.size() - furnished_centers.size(), translated_ghost_overlaps])
	for key: String in saved:
		OS.set_environment(key, str(saved[key]))


func _translated_ineligible_field(north_delta: float, east_delta: float) -> Dictionary:
	var raw_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(FieldLoader.DEFAULT_PATH))
	if typeof(raw_value) != TYPE_DICTIONARY:
		return {}
	var raw: Dictionary = raw_value.duplicate(true)
	var pilot: Dictionary = raw.pilot
	_edit_quantity(pilot, "north", north_delta)
	_edit_quantity(pilot, "east", east_delta)
	for surface: Dictionary in raw.surfaces:
		_edit_quantity(surface, "center_north", north_delta)
		_edit_quantity(surface, "center_east", east_delta)
	# Translate the complete pad geometry with its referenced surface. Leaving
	# this newer module behind makes the fixture invalid before scenery is tested.
	if raw.has("rotorcraft_pad"):
		var pad: Dictionary = raw.rotorcraft_pad
		_edit_quantity(pad, "north", north_delta)
		_edit_quantity(pad, "east", east_delta)
		for keepout: Dictionary in pad.get("keepouts", []):
			_edit_quantity(keepout, "north", north_delta)
			_edit_quantity(keepout, "east", east_delta)
	for cue: Dictionary in raw.get("flight_cues", []):
		if cue.has("north"):
			_edit_quantity(cue, "north", north_delta)
		if cue.has("east"):
			_edit_quantity(cue, "east", east_delta)
	raw.objects = []
	var result: Dictionary = FieldLoader.validate(raw)
	_check("translated field geometry validates", bool(result.get("ok", false)), str(result.get("errors", [])))
	return result.field if bool(result.get("ok", false)) else {}


func _edit_quantity(owner: Dictionary, key: String, delta: float) -> void:
	var quantity: Dictionary = owner[key]
	quantity.value = float(quantity.value) + delta


func _layout_centers(chunks: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for chunk: Array in chunks:
		for point: Array in chunk:
			result.append(Vector2(float(point[0]), float(point[1])))
	return result


func _count_excluded(centers: Array[Vector2], footprints: Array[Dictionary]) -> int:
	var result := 0
	for center: Vector2 in centers:
		if GrassMask.excludes(center.x, center.y, footprints):
			result += 1
	return result


func _multimesh_count(grass: Node3D) -> int:
	var result := 0
	if grass == null:
		return result
	for child: Node in grass.get_children():
		if child is MultiMeshInstance3D and (child as MultiMeshInstance3D).multimesh != null:
			result += (child as MultiMeshInstance3D).multimesh.instance_count
	return result


func _layout_count(chunks: Array) -> int:
	var result := 0
	for chunk: Array in chunks:
		result += chunk.size()
	return result


func _find(footprints: Array[Dictionary], id: String) -> Dictionary:
	for footprint: Dictionary in footprints:
		if str(footprint.get("id", "")) == id:
			return footprint
	return {}


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _finish() -> void:
	print("LU-18 scenery grass mask: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
