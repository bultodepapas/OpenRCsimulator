## L11a-R3 runway meadow: world-anchored plant colonies of catalogued downloaded plants around
## the runway and pilot station. Colonies (tussocks, clover mats, flower stands, mown-lip weeds)
## grade from large central plants to small edge plants, separated by open lawn.
## Deterministic per world cell; quality keeps nested subsets of colonies and members.
## Presentation only: no colliders, terrain, contact or simulation data change.
extends RefCounted

const NearGrass := preload("res://render/near_grass.gd")
const Frames := preload("res://render/frames.gd")
const Palette := preload("res://scenery/palette.gd")
const PlantLibrary := preload("res://scenery/imported_vegetation.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")

const SEED := 731101
const COLONY_CELL_M := 2.6
const SCATTER_CELL_M := 1.7
const SIDE_MARGIN_M := 26.0 # rough band beside each long runway edge
const END_MARGIN_M := 28.0 # beyond each runway threshold
const EDGE_FADE_M := 8.0 # density fade at the outer domain edge
const MOWN_CLEAR_M := 0.7 # bare mown lip next to the runway
const FRINGE_M := 3.0 # short, sparse transition band
const PILOT_FOCUS_M := 26.0 # the fixed pilot view sees this foreground at grazing angles
const MAX_SOURCE_TRIANGLES := 160000
const QUALITY_FRACTION := {"low": 0.3, "balanced": 0.6, "high": 1.0}
const WIND_ENABLED := true
const GOLDEN_ANGLE := 2.399963229728653
const MEMBER_SPACING_M := 0.3
## Graphics setting (display.cfg [graphics] runway_meadow); app_state/display_preferences.gd mirrors it.
const PREFERENCES: Array[String] = ["off", "on"]
const DEFAULT_PREFERENCE := "on"
const GROUP := &"runway_meadow"
static var _preference := DEFAULT_PREFERENCE


static func set_preference(level: String) -> void:
	_preference = level if level in PREFERENCES else DEFAULT_PREFERENCE


static func preference() -> String:
	return _preference
const CULL_CELL_M := 40.0

## High-quality caps for costly downloaded accents (155-758 source triangles each). Surplus
## members fall back to 20-26 triangle photographic grass cards, keeping position and size.
const SPECIES_CAPS := {
	"clover_1": 30, "polyhaven_flower_empodium_a": 20, "flower_3_group": 10,
	"grass_common_short": 30, "grass_common_tall": 16, "grass_wispy_tall": 6,
}
const SUBSTITUTES := {
	"clover_1": "grass_lolipop_small", "polyhaven_flower_empodium_a": "grass_lolipop_small",
	"flower_3_group": "grass_lolipop_tall", "grass_common_short": "grass_lolipop_small",
	"grass_common_tall": "grass_lolipop_tall", "grass_wispy_tall": "grass_lolipop_tall",
}

## Artistic estimates in metres for a maintained club field; not surveyed vegetation.
const HEIGHT_RANGES := {
	"grass_lolipop_small": Vector2(0.10, 0.32),
	"grass_lolipop_tall": Vector2(0.22, 0.62),
	"grass_common_short": Vector2(0.12, 0.26),
	"grass_common_tall": Vector2(0.24, 0.46),
	"grass_wispy_tall": Vector2(0.30, 0.52),
	"clover_1": Vector2(0.06, 0.13),
	"polyhaven_flower_empodium_a": Vector2(0.14, 0.30),
	"flower_3_group": Vector2(0.20, 0.38),
}

## Colony recipes: centre and edge species weights, member count and radius ranges.
const COLONIES := {
	"tussock": {
		"centre": {"grass_lolipop_tall": 6.0, "grass_common_tall": 0.8, "grass_wispy_tall": 0.35},
		"edge": {"grass_lolipop_small": 6.0, "grass_lolipop_tall": 1.5, "grass_common_short": 0.8},
		"members": Vector2i(5, 18), "radius_m": Vector2(0.45, 1.5),
	},
	"clover": {
		"centre": {"clover_1": 5.0, "grass_lolipop_small": 1.0, "polyhaven_flower_empodium_a": 0.5},
		"edge": {"clover_1": 3.0, "grass_lolipop_small": 3.0},
		"members": Vector2i(6, 16), "radius_m": Vector2(0.5, 1.3),
	},
	"flowers": {
		"centre": {"polyhaven_flower_empodium_a": 3.0, "flower_3_group": 1.5, "grass_lolipop_tall": 1.5},
		"edge": {"grass_lolipop_small": 3.0, "polyhaven_flower_empodium_a": 1.2, "clover_1": 0.8},
		"members": Vector2i(5, 12), "radius_m": Vector2(0.4, 1.1),
	},
	"lip": {
		"centre": {"grass_lolipop_small": 4.0, "clover_1": 1.5, "grass_common_short": 0.8},
		"edge": {"grass_lolipop_small": 4.0, "clover_1": 1.0},
		"members": Vector2i(2, 7), "radius_m": Vector2(0.25, 0.7),
	},
}


## Pure deterministic layout; masks are the same footprints the imported near grass uses.
static func layout(field: Dictionary, quality: String = "high", exclusions: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var area := _area(field)
	if area.is_empty():
		return result
	var grid := NearGrass._build_exclusion_grid(exclusions)
	var candidates: Array[Dictionary] = []
	_colonies(candidates, field, area, exclusions, grid)
	_scatter(candidates, field, area, exclusions, grid)
	# Expensive accents are capped on the complete high-quality set by stable rank, so lower
	# qualities keep a nested subset with identical species, positions and sizes.
	_cap_species(candidates)
	var keep_fraction := float(QUALITY_FRACTION.get(quality, 1.0))
	var keep_root := sqrt(keep_fraction)
	var surface_rects := _surface_rects(field)
	var triangles := 0
	for plant: Dictionary in candidates:
		if float(plant.group_u) >= keep_root or float(plant.member_u) >= keep_root:
			continue
		var asset_id := str(plant.asset_id)
		var source_triangles := int(PlantLibrary.get_asset(asset_id).get("source_triangles", 0))
		if source_triangles <= 0:
			continue
		if triangles + source_triangles > MAX_SOURCE_TRIANGLES:
			push_error("Runway meadow exceeds its %d source-triangle budget" % MAX_SOURCE_TRIANGLES)
			return []
		var range_m: Vector2 = HEIGHT_RANGES.get(asset_id, Vector2(0.1, 0.3))
		var north := float(plant.north)
		var east := float(plant.east)
		result.append({
			"asset_id": asset_id,
			"colony": str(plant.colony),
			"north": north,
			"east": east,
			"ground_up_m": _ground_up(north, east, surface_rects),
			"height_m": lerpf(range_m.x, range_m.y, clampf(float(plant.size_u), 0.0, 1.0)),
			"yaw_rad": float(plant.yaw_rad),
			"tint": plant.tint,
			"seed": int(plant.seed),
			"source_triangles": source_triangles,
		})
		triangles += source_triangles
	return result


static func build(field: Dictionary, quality: String = "high", exclusions: Array = []) -> Node3D:
	var plants := layout(field, quality, exclusions)
	var area := _area(field)
	# Bulk photographic cards are split into world cells so frustum culling skips unseen strips;
	# the few costly accents stay in one batch per species to bound draw calls.
	var cell_batches: Dictionary = {"": {}}
	var groups: Dictionary = {}
	var colonies: Dictionary = {}
	var triangles := 0
	for plant: Dictionary in plants:
		var cell := ""
		if str(plant.asset_id).begins_with("grass_lolipop_"):
			# Split at the runway centreline: two side strips, four lengthwise sections.
			cell = "_Cell_%d_%d" % [floori((float(plant.north) - float(area.rn)) / CULL_CELL_M),
				floori((float(plant.east) - float(area.re)) / CULL_CELL_M)]
		if not cell_batches.has(cell):
			cell_batches[cell] = {}
		var batches: Dictionary = cell_batches[cell]
		var asset_id := str(plant.asset_id)
		var origin := Frames.ned_to_render([float(plant.north), float(plant.east), -float(plant.ground_up_m)])
		var placement := Transform3D(Basis(Vector3.UP, float(plant.yaw_rad)), origin)
		placement = PlantLibrary.fit_to_height(asset_id, float(plant.height_m), placement)
		var queued_id := PlantLibrary.queue(batches, asset_id, placement, int(plant.seed), "",
			plant.tint as Color)
		if queued_id.is_empty():
			continue
		triangles += int(plant.source_triangles)
		var record: Dictionary = groups.get(queued_id, {"plants": 0, "triangles": 0})
		record["plants"] = int(record.plants) + 1
		record["triangles"] = int(record.triangles) + int(plant.source_triangles)
		groups[queued_id] = record
		colonies[str(plant.colony)] = int(colonies.get(str(plant.colony), 0)) + 1
	var root := Node3D.new()
	root.name = "RunwayMeadow"
	root.add_to_group(GROUP, true)
	var cells: Array = cell_batches.keys()
	cells.sort()
	for cell: String in cells:
		var cell_root := PlantLibrary.build(cell_batches[cell], WIND_ENABLED)
		for child: Node in cell_root.get_children():
			if not child is MultiMeshInstance3D:
				continue
			var batch := child as MultiMeshInstance3D
			batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_enable_instance_tint(batch)
			cell_root.remove_child(batch)
			batch.name = str(batch.name) + cell
			root.add_child(batch)
		cell_root.free()
	root.set_meta("plants", plants.size())
	root.set_meta("source_triangles", triangles)
	root.set_meta("triangle_budget", MAX_SOURCE_TRIANGLES)
	root.set_meta("batches", root.get_child_count())
	root.set_meta("groups", groups)
	root.set_meta("colonies", colonies)
	root.set_meta("quality", quality)
	return root


static func _area(field: Dictionary) -> Dictionary:
	var runway: Dictionary = {}
	for surface: Dictionary in field.get("surfaces", []):
		if str(surface.get("type", "")) == "runway":
			runway = surface
			break
	if runway.is_empty() or not field.has("pilot"):
		return {}
	var rn := float(runway.center_north)
	var re := float(runway.center_east)
	var half_n := float(runway.width_north_south) * 0.5
	var half_e := float(runway.length_east_west) * 0.5
	return {
		"rn": rn, "re": re, "half_n": half_n, "half_e": half_e,
		"min_n": rn - half_n - SIDE_MARGIN_M, "max_n": rn + half_n + SIDE_MARGIN_M,
		"min_e": re - half_e - END_MARGIN_M, "max_e": re + half_e + END_MARGIN_M,
		"pilot_n": float(field.pilot.get("north", 0.0)), "pilot_e": float(field.pilot.get("east", 0.0)),
	}


static func _colonies(output: Array[Dictionary], field: Dictionary, area: Dictionary,
		exclusions: Array, grid: Dictionary) -> void:
	var first_n := floori(float(area.min_n) / COLONY_CELL_M)
	var first_e := floori(float(area.min_e) / COLONY_CELL_M)
	var last_n := floori(float(area.max_n) / COLONY_CELL_M)
	var last_e := floori(float(area.max_e) / COLONY_CELL_M)
	for cell_n: int in range(first_n, last_n + 1):
		for cell_e: int in range(first_e, last_e + 1):
			var cell_id := _cell_id(cell_n, cell_e)
			var north := (float(cell_n) + Palette.hash01(SEED, cell_id, 1)) * COLONY_CELL_M
			var east := (float(cell_e) + Palette.hash01(SEED, cell_id, 2)) * COLONY_CELL_M
			var edge := _edge_distance(area, north, east)
			if edge < MOWN_CLEAR_M:
				continue
			var richness := _richness(area, north, east, edge)
			if Palette.hash01(SEED, cell_id, 3) >= richness:
				continue
			var kind := _colony_kind(north, east, edge, Palette.hash01(SEED, cell_id, 6))
			var recipe: Dictionary = COLONIES[kind]
			var vigor := _vigor(north, east, edge)
			var members_range: Vector2i = recipe.members
			var radius_range: Vector2 = recipe.radius_m
			var lush := clampf(richness * (0.6 + 0.6 * Palette.hash01(SEED, cell_id, 7)), 0.0, 1.0)
			var members := int(round(lerpf(float(members_range.x), float(members_range.y), lush)))
			# Members sit ~0.3 m apart (bunchgrass overdispersion scale), so clumps read as clumps.
			var radius := clampf(MEMBER_SPACING_M * sqrt(float(members)) * 0.62, radius_range.x, radius_range.y)
			var aspect := lerpf(0.55, 1.0, Palette.hash01(SEED, cell_id, 8))
			var axis := TAU * Palette.hash01(SEED, cell_id, 9)
			var group_u := Palette.hash01(SEED, cell_id, 4)
			# Clump-shared parameters (Ghost of Tsushima-style clumping): height, colour and facing.
			var clump_height := lerpf(0.75, 1.15, Palette.hash01(SEED, cell_id, 10))
			var clump_dry := clampf(_dryness(north, east) + (Palette.hash01(SEED, cell_id, 19) - 0.5) * 0.5, 0.0, 1.0)
			var clump_facing := TAU * Palette.hash01(SEED, cell_id, 20)
			var facing_spread := lerpf(0.35, 1.0, Palette.hash01(SEED, cell_id, 23)) * PI
			var spiral_phase := TAU * Palette.hash01(SEED, cell_id, 24)
			for index: int in members:
				var seed := cell_id * 32 + index
				# Vogel spiral plus jitter: members keep roughly even spacing (bunchgrass overdispersion)
				# and the exponent pulls them toward the clump centre.
				var spiral_r := sqrt((float(index) + 0.5) / float(members))
				var r := 0.0 if index == 0 else clampf(pow(spiral_r, 1.2) + (Palette.hash01(SEED, seed, 11) - 0.5) * 0.18, 0.0, 1.0)
				var angle := spiral_phase + float(index) * GOLDEN_ANGLE + (Palette.hash01(SEED, seed, 12) - 0.5) * 0.6
				var local := Vector2(cos(angle) * r * radius, sin(angle) * r * radius * aspect).rotated(axis)
				var plant_n := north + local.x
				var plant_e := east + local.y
				if _edge_distance(area, plant_n, plant_e) < MOWN_CLEAR_M:
					continue
				if not NearGrass.accepts(plant_n, plant_e, field, exclusions, grid):
					continue
				# Large plants first at the centre, smaller fill toward the margin.
				var mix: Dictionary = recipe.centre if r < 0.45 else recipe.edge
				var profile := lerpf(1.0, 0.4, pow(r, 1.3))
				var jitter := lerpf(0.78, 1.12, Palette.hash01(SEED, seed, 14))
				var size_u := profile * jitter * vigor * clump_height
				output.append({
					"asset_id": _pick(mix, Palette.hash01(SEED, seed, 13)),
					"colony": kind,
					"north": plant_n,
					"east": plant_e,
					"size_u": size_u,
					"yaw_rad": clump_facing + (Palette.hash01(SEED, seed, 16) - 0.5) * 2.0 * facing_spread,
					"tint": _tint(clump_dry, size_u),
					"seed": SEED + seed,
					"rank": Palette.hash01(SEED, seed, 17),
					"group_u": group_u,
					"member_u": 0.0 if index == 0 else Palette.hash01(SEED, seed, 18),
				})


## Sparse single tufts break up the lawn between colonies.
static func _scatter(output: Array[Dictionary], field: Dictionary, area: Dictionary,
		exclusions: Array, grid: Dictionary) -> void:
	var first_n := floori(float(area.min_n) / SCATTER_CELL_M)
	var first_e := floori(float(area.min_e) / SCATTER_CELL_M)
	var last_n := floori(float(area.max_n) / SCATTER_CELL_M)
	var last_e := floori(float(area.max_e) / SCATTER_CELL_M)
	for cell_n: int in range(first_n, last_n + 1):
		for cell_e: int in range(first_e, last_e + 1):
			var cell_id := _cell_id(cell_n, cell_e) + 33554432
			var north := (float(cell_n) + Palette.hash01(SEED, cell_id, 1)) * SCATTER_CELL_M
			var east := (float(cell_e) + Palette.hash01(SEED, cell_id, 2)) * SCATTER_CELL_M
			var edge := _edge_distance(area, north, east)
			if edge < MOWN_CLEAR_M + 0.3:
				continue
			var chance := 0.12 * _outer_fade(area, north, east) * smoothstep(MOWN_CLEAR_M, FRINGE_M, edge) \
				* _pilot_focus(area, north, east)
			if Palette.hash01(SEED, cell_id, 3) >= chance:
				continue
			if not NearGrass.accepts(north, east, field, exclusions, grid):
				continue
			output.append({
				"asset_id": "grass_lolipop_tall" if Palette.hash01(SEED, cell_id, 13) < 0.3 else "grass_lolipop_small",
				"colony": "scatter",
				"north": north,
				"east": east,
				"size_u": lerpf(0.15, 0.7, Palette.hash01(SEED, cell_id, 14)) * _vigor(north, east, edge),
				"yaw_rad": TAU * Palette.hash01(SEED, cell_id, 16),
				"tint": _tint(_dryness(north, east), 0.4),
				"seed": SEED + cell_id,
				"rank": Palette.hash01(SEED, cell_id, 17),
				"group_u": Palette.hash01(SEED, cell_id, 4),
				"member_u": 0.0,
			})


## Clump colour, Unity-terrain style: dry patches warm toward straw, larger plants stay lusher.
## Values stay inside the library's bounded instance tint (0.86-1.0 per channel).
static func _tint(dryness: float, size_u: float) -> Color:
	var dry := clampf(dryness * lerpf(1.15, 0.7, clampf(size_u, 0.0, 1.0)), 0.0, 1.0)
	var lush := Color(0.88, 0.97, 0.90)
	var straw := Color(1.0, 0.95, 0.86)
	return lush.lerp(straw, dry)


static func _dryness(north: float, east: float) -> float:
	return smoothstep(0.35, 0.85, _noise(north, east, 16.0, 51))


## The photographic cards have no vertex colours, so COLOR carries only the instance tint.
## Wind materials are duplicated per vegetation root, so this never touches other layers.
static func _enable_instance_tint(batch: MultiMeshInstance3D) -> void:
	if batch.multimesh == null or batch.multimesh.mesh == null or not str(batch.name).begins_with("grass_lolipop_"):
		return
	var mesh := batch.multimesh.mesh
	for surface: int in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as ShaderMaterial
		if material != null:
			material.set_shader_parameter("use_vertex_color", true)
			material.set_shader_parameter("vertex_color_is_srgb", false)


## Fewer colonies far from the fixed pilot station (distance-based density, as in Horizon/GoT).
static func _distance_thinning(area: Dictionary, north: float, east: float) -> float:
	var distance := Vector2(north - float(area.pilot_n), east - float(area.pilot_e)).length()
	return lerpf(1.0, 0.55, smoothstep(40.0, 75.0, distance))


static func _cap_species(candidates: Array[Dictionary]) -> void:
	var ranked: Dictionary = {}
	for index: int in candidates.size():
		var asset_id := str(candidates[index].asset_id)
		if SPECIES_CAPS.has(asset_id):
			if not ranked.has(asset_id):
				ranked[asset_id] = []
			(ranked[asset_id] as Array).append(Vector2(float(candidates[index].rank), float(index)))
	for asset_id: String in ranked.keys():
		var entries: Array = ranked[asset_id]
		entries.sort()
		for order: int in range(int(SPECIES_CAPS[asset_id]), entries.size()):
			var plant: Dictionary = candidates[int((entries[order] as Vector2).y)]
			plant["asset_id"] = SUBSTITUTES.get(asset_id, "grass_lolipop_small")


## Distance from a point to the runway rectangle; zero inside.
static func _edge_distance(area: Dictionary, north: float, east: float) -> float:
	var on := maxf(absf(north - float(area.rn)) - float(area.half_n), 0.0)
	var oe := maxf(absf(east - float(area.re)) - float(area.half_e), 0.0)
	return sqrt(on * on + oe * oe)


static func _outer_fade(area: Dictionary, north: float, east: float) -> float:
	var inset := minf(minf(north - float(area.min_n), float(area.max_n) - north),
		minf(east - float(area.min_e), float(area.max_e) - east))
	return smoothstep(0.0, EDGE_FADE_M, inset)


## Up to 1.5x colonies in the fixed pilot view's foreground.
static func _pilot_focus(area: Dictionary, north: float, east: float) -> float:
	var distance := Vector2(north - float(area.pilot_n), east - float(area.pilot_e)).length()
	return lerpf(1.5, 1.0, smoothstep(6.0, PILOT_FOCUS_M, distance))


## Colony probability: broad meadow patches, thinned on the mown lip and at the outer edge.
static func _richness(area: Dictionary, north: float, east: float, edge: float) -> float:
	var broad := _noise(north, east, 11.0, 21)
	var fine := _noise(north, east, 4.0, 22)
	var patchy := smoothstep(0.22, 0.72, broad * 0.65 + fine * 0.35)
	var fringe := lerpf(0.35, 1.0, smoothstep(MOWN_CLEAR_M, FRINGE_M + 2.0, edge))
	var value := (0.09 + 0.68 * patchy) * fringe * _outer_fade(area, north, east) \
		* _pilot_focus(area, north, east) * _distance_thinning(area, north, east)
	return clampf(value, 0.0, 0.95)


static func _colony_kind(north: float, east: float, edge: float, u: float) -> String:
	if edge < FRINGE_M:
		return "lip"
	if _noise(north, east, 9.0, 31) > 0.66 and u < 0.55:
		return "flowers"
	if _noise(north, east, 7.0, 32) > 0.62 and u < 0.65:
		return "clover"
	return "tussock"


## Taller, lusher growth farther from the mown edge and in some broad patches.
static func _vigor(north: float, east: float, edge: float) -> float:
	var away := smoothstep(FRINGE_M, FRINGE_M + 12.0, edge)
	return lerpf(0.55, 1.0, away) * lerpf(0.8, 1.15, _noise(north, east, 13.0, 41))


static func _pick(mix: Dictionary, u: float) -> String:
	var total := 0.0
	for weight: float in mix.values():
		total += weight
	var target := u * total
	for key: String in mix.keys():
		target -= float(mix[key])
		if target <= 0.0:
			return key
	return str(mix.keys()[mix.size() - 1])


## Smooth value noise in [0,1] from the shared integer hash; world-anchored and deterministic.
static func _noise(north: float, east: float, scale_m: float, salt: int) -> float:
	var x := north / scale_m
	var y := east / scale_m
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - float(ix)
	var fy := y - float(iy)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := Palette.hash01(SEED + salt, _cell_id(ix, iy), salt)
	var b := Palette.hash01(SEED + salt, _cell_id(ix + 1, iy), salt)
	var c := Palette.hash01(SEED + salt, _cell_id(ix, iy + 1), salt)
	var d := Palette.hash01(SEED + salt, _cell_id(ix + 1, iy + 1), salt)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func _cell_id(cell_n: int, cell_e: int) -> int:
	return (cell_n + 4096) * 8192 + (cell_e + 4096)


static func _surface_rects(field: Dictionary) -> PackedFloat64Array:
	var table := GroundSurfaces.load_table()
	if not bool(table.get("ok", false)):
		return PackedFloat64Array()
	var built := GroundSurfaces.build(table.table, field)
	return built.rects if bool(built.get("ok", false)) else PackedFloat64Array()


static func _ground_up(north: float, east: float, surface_rects: PackedFloat64Array) -> float:
	if surface_rects.is_empty():
		return 0.0
	var terrain := GroundTerrain.sample_validated(north, east, surface_rects)
	return terrain[0] if terrain.size() == 3 and is_finite(terrain[0]) else 0.0
