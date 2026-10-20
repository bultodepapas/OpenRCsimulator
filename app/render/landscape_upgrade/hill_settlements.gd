## LU-29: static distant houses fitted to the authored visual ridge triangles.
extends RefCounted

const Prefabs := preload("res://scenery/prefabs.gd")
const MeshKit := preload("res://scenery/mesh_kit.gd")
const Palette := preload("res://scenery/palette.gd")

const LAYOUT_PATH := "res://data/scenery/hill_settlements.json"
const PROFILE_PATH := "res://data/fields/mountains.json"
const LAYOUT_FORMAT := "openrc-hill-settlements v1"
const RIDGE_SURFACE_OFFSET_M := 0.02
const HOUSE_PREFAB := "village_house"
const HOUSE_THEME := "temperate"
const HOUSE_MAX_WIDTH_M := 9.0
const HOUSE_MAX_DEPTH_M := 11.0
const FOUNDATION_TOP_CLEARANCE_M := 0.02
const FOUNDATION_CAP_HEIGHT_M := 0.08
const FOUNDATION_BASE_MARGIN_M := 0.25
const FOUNDATION_CAP_MARGIN_M := 0.15


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "HillSettlements"
	root.set_meta("houses", [])
	root.set_meta("stats", {"clusters": 0, "houses": 0, "triangles": 0, "batches": 0})
	var inputs := _load_inputs()
	if inputs.is_empty():
		return root
	var layout: Dictionary = inputs.layout
	var profile: Dictionary = inputs.profile
	var batch := MeshKit.new()
	var houses: Array[Dictionary] = []
	var max_slope_deg := 0.0
	var max_footing_range_m := 0.0
	var max_foundation_height_m := 0.0
	var house_triangles := 0
	var foundation_triangles := 0
	for item: Variant in layout.houses:
		if not item is Dictionary:
			return _invalid_root(root, "Hill settlement entry is not an object")
		var entry: Dictionary = item
		var north := float(entry.get("north_m", NAN))
		var east := float(entry.get("east_m", NAN))
		var height := float(entry.get("height_m", NAN))
		var heading := float(entry.get("heading_deg", NAN))
		var seed := int(entry.get("seed", 0))
		if not is_finite(north) or not is_finite(east) or not is_finite(height) or not is_finite(heading):
			return _invalid_root(root, "Hill settlement entry contains non-finite placement data")
		var surface := _sample_triangle(profile, north, east)
		var terrain_height := float(entry.get("terrain_height_m", NAN))
		if surface.is_empty() or absf(terrain_height - float(surface.get("height", NAN))) > 0.001:
			return _invalid_root(root, "Hill settlement center disagrees with its ridge triangle")
		var slope_deg := rad_to_deg(atan(Vector2(float(surface.north_gradient), float(surface.east_gradient)).length()))
		var footprint := _world_up_footprint(profile, north, east, heading)
		if footprint.is_empty():
			return _invalid_root(root, "Hill settlement footprint crosses ridge triangles")
		var terrain_min := float(entry.get("terrain_min_height_m", NAN))
		var terrain_max := float(entry.get("terrain_max_height_m", NAN))
		if absf(terrain_min - float(footprint.terrain_min)) > 0.001 \
				or absf(terrain_max - float(footprint.terrain_max)) > 0.001:
			return _invalid_root(root, "Hill settlement footing disagrees with its ridge triangles")
		var foundation_body_height := terrain_max - terrain_min + FOUNDATION_TOP_CLEARANCE_M
		var foundation_height := foundation_body_height + FOUNDATION_CAP_HEIGHT_M
		var foundation_base_y := terrain_min + RIDGE_SURFACE_OFFSET_M
		var expected_house_y := foundation_base_y + foundation_height
		if absf(height - expected_house_y) > 0.001:
			return _invalid_root(root, "Hill settlement foundation height is stale")
		var basis := Basis(Vector3.UP, -deg_to_rad(heading))
		var position := Vector3(east, height, -north)
		var foundation := MeshKit.new()
		var stone := Palette.col("stone_dark")
		foundation.block(
			Vector3(HOUSE_MAX_WIDTH_M + FOUNDATION_BASE_MARGIN_M * 2.0, foundation_body_height,
				HOUSE_MAX_DEPTH_M + FOUNDATION_BASE_MARGIN_M * 2.0),
			Vector3.ZERO, stone)
		foundation.block(
			Vector3(HOUSE_MAX_WIDTH_M + FOUNDATION_CAP_MARGIN_M * 2.0, FOUNDATION_CAP_HEIGHT_M,
				HOUSE_MAX_DEPTH_M + FOUNDATION_CAP_MARGIN_M * 2.0),
			Vector3(0.0, foundation_body_height, 0.0), stone.lightened(0.12))
		batch.append_arrays(foundation.verts, foundation.norms, foundation.cols,
			Transform3D(basis, Vector3(east, foundation_base_y, -north)))
		var source := MeshKit.new()
		Prefabs.build(HOUSE_PREFAB, source, seed, HOUSE_THEME)
		if source.is_empty():
			return _invalid_root(root, "Village house prefab produced no geometry")
		batch.append_arrays(source.verts, source.norms, source.cols, Transform3D(basis, position))
		foundation_triangles += foundation.triangle_count()
		house_triangles += source.triangle_count()
		houses.append({
			"id": str(entry.get("id", "")),
			"cluster": str(entry.get("cluster", "")),
			"position": position,
			"basis": basis,
			"seed": seed,
			"north_m": north,
			"east_m": east,
			"height_m": height,
			"heading_deg": heading,
			"slope_deg": slope_deg,
			"terrain_min_height_m": terrain_min,
			"terrain_max_height_m": terrain_max,
			"foundation_height_m": foundation_height,
		})
		max_slope_deg = maxf(max_slope_deg, slope_deg)
		max_footing_range_m = maxf(max_footing_range_m, float(footprint.footing_range))
		max_foundation_height_m = maxf(max_foundation_height_m, foundation_height)
	var material := _house_material()
	var instance := MeshInstance3D.new()
	instance.name = "VillageHouseBatch"
	instance.mesh = batch.to_mesh(material)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)
	root.set_meta("houses", houses)
	root.set_meta("profile_sha256", str(layout.profile_sha256))
	root.set_meta("stats", {
		"clusters": layout.clusters.size(),
		"houses": houses.size(),
		"triangles": batch.triangle_count(),
		"house_triangles": house_triangles,
		"foundation_triangles": foundation_triangles,
		"batches": 1,
		"max_slope_deg": max_slope_deg,
		"max_footing_range_m": max_footing_range_m,
		"max_foundation_height_m": max_foundation_height_m,
		"profile_sha256": str(layout.profile_sha256),
	})
	return root


static func _load_inputs() -> Dictionary:
	if not FileAccess.file_exists(LAYOUT_PATH) or not FileAccess.file_exists(PROFILE_PATH):
		push_error("Hill settlements require both baked placement and mountain profile data")
		return {}
	var layout_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	var profile_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not layout_variant is Dictionary or not profile_variant is Dictionary:
		push_error("Hill settlements data is not valid JSON")
		return {}
	var layout: Dictionary = layout_variant
	var profile: Dictionary = profile_variant
	if str(layout.get("format", "")) != LAYOUT_FORMAT or str(layout.get("prefab", "")) != HOUSE_PREFAB \
			or bool(layout.get("physical", true)):
		push_error("Hill settlements data has an unsupported format or prefab")
		return {}
	if str(layout.get("profile_sha256", "")) != FileAccess.get_sha256(PROFILE_PATH):
		push_error("Hill settlement placements are stale for the current ridge profile")
		return {}
	if profile.get("format") != "openrc-visual-mountains v1" or profile.get("physical_terrain") != false:
		push_error("Hill settlements profile is not the visual-only ridge grid")
		return {}
	if int(layout.get("columns", -1)) != int(profile.get("columns", -2)) \
			or int(layout.get("rows", -1)) != int(profile.get("rows", -2)) \
			or layout.get("profile_source_crop_sha256") != profile.get("source_crop_sha256"):
		push_error("Hill settlement grid metadata does not match the ridge profile")
		return {}
	var heights: Variant = profile.get("heights_m", null)
	var houses: Variant = layout.get("houses", null)
	var clusters: Variant = layout.get("clusters", null)
	var expected_height_count := (int(profile.columns) + 1) * (int(profile.rows) + 1)
	if not heights is Array or heights.size() != expected_height_count \
			or not houses is Array or houses.size() != 12 or not clusters is Array or clusters.size() != 3:
		push_error("Hill settlements or ridge profile has an unexpected count")
		return {}
	return {"layout": layout, "profile": profile}


static func _sample_triangle(profile: Dictionary, north: float, east: float) -> Dictionary:
	var columns := int(profile.columns)
	var rows := int(profile.rows)
	var step_e := (float(profile.east_max_m) - float(profile.east_min_m)) / float(columns)
	var step_n := (float(profile.north_max_m) - float(profile.north_min_m)) / float(rows)
	var x := clampf((east - float(profile.east_min_m)) / step_e, 0.0, float(columns))
	var y := clampf((north - float(profile.north_min_m)) / step_n, 0.0, float(rows))
	var col := mini(int(x), columns - 1)
	var row := mini(int(y), rows - 1)
	var u := x - float(col)
	var v := y - float(row)
	var heights: Array = profile.heights_m
	var a := row * (columns + 1) + col
	var b := a + columns + 1
	var h00 := float(heights[a])
	var h01 := float(heights[a + 1])
	var h10 := float(heights[b])
	var h11 := float(heights[b + 1])
	var height: float
	var north_gradient: float
	var east_gradient: float
	if u + v <= 1.0:
		height = h00 * (1.0 - u - v) + h10 * v + h01 * u
		north_gradient = (h10 - h00) / step_n
		east_gradient = (h01 - h00) / step_e
	else:
		height = h10 * (1.0 - u) + h11 * (u + v - 1.0) + h01 * (1.0 - v)
		north_gradient = (h11 - h01) / step_n
		east_gradient = (h11 - h10) / step_e
	return {"height": height, "north_gradient": north_gradient, "east_gradient": east_gradient,
		"row": row, "column": col, "triangle": 0 if u + v <= 1.0 else 1}


static func _world_up_footprint(profile: Dictionary, north: float, east: float, heading_deg: float) -> Dictionary:
	var angle := deg_to_rad(heading_deg)
	var right := Vector3(cos(angle), 0.0, sin(angle))
	var back := Vector3(-sin(angle), 0.0, cos(angle))
	var center := _sample_triangle(profile, north, east)
	var terrain_min := INF
	var terrain_max := -INF
	for x: float in [-HOUSE_MAX_WIDTH_M * 0.5, HOUSE_MAX_WIDTH_M * 0.5]:
		for z: float in [-HOUSE_MAX_DEPTH_M * 0.5, HOUSE_MAX_DEPTH_M * 0.5]:
			var east_delta := right.x * x + back.x * z
			var north_delta := -(right.z * x + back.z * z)
			var corner := _sample_triangle(profile, north + north_delta, east + east_delta)
			if corner.row != center.row or corner.column != center.column or corner.triangle != center.triangle:
				return {}
			terrain_min = minf(terrain_min, float(corner.height))
			terrain_max = maxf(terrain_max, float(corner.height))
	return {"terrain_min": terrain_min, "terrain_max": terrain_max, "footing_range": terrain_max - terrain_min}


static func _house_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.88
	material.metallic_specular = 0.3
	return material


static func _invalid_root(root: Node3D, reason: String) -> Node3D:
	push_error("Hill settlements: " + reason)
	return root
