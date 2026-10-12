## LU-05: immutable scalar obstacle inventory built once from normalized field/scenery/light inputs.
## Coordinates are world N/E/down metres; no render-space transform reaches the flight solver.
extends RefCounted

const Treeline := preload("res://render/treeline.gd")
const Prefabs := preload("res://scenery/prefabs.gd")
const Models := preload("res://scenery/models.gd")
const Palette := preload("res://scenery/palette.gd")

const FORMAT := "openrc-collision-world v1"
const CELL_SIZE_M := 32.0
const MAX_BIN_REFERENCES := 250000
const TREE_TRUNK_RADIUS_M := 0.18 # estimated gameplay envelope; visual source is a tree card, not a trunk mesh
const TREE_TRUNK_HEIGHT_FRACTION := 0.34
const FIELD_TREE_ALPHA_HALF_WIDTH_FRACTIONS := [0.2294921875, 0.1708984375, 0.2900390625] # raw atlas ratios at alpha 0.5
const FIELD_TREE_CARD_FRAME_SIZE_M := 1.125001 # source frame size multiplied by Treeline.identity.height in shader
const FIELD_TREE_WIND_LEAN_M := 0.24 # maximum lean in render/tree_wind.gdshaderinc (L15b)
const TREE_CROWN_VERTICAL_HALF_EXTENT_FRACTION := 0.34 # preserve old crown y envelope around its measured center
const TREE_CROWN_CENTER_FRACTION := 0.66

const BUILDINGS: Array[String] = ["pavilion", "shed", "barn", "silo", "farmhouse", "church", "village_house"]
const VEHICLES: Array[String] = ["car_sedan", "car_hatch", "car_suv", "car_sport", "tractor"]
static func build(field: Dictionary, scenery: Dictionary, lights: Dictionary = {}) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(field.get("pilot")) != TYPE_DICTIONARY or typeof(field.get("objects")) != TYPE_ARRAY:
		return _failure("field must be normalized before collision inventory construction")
	if typeof(scenery.get("groups")) != TYPE_ARRAY:
		return _failure("scenery must be normalized before collision inventory construction")
	if not lights.is_empty() and typeof(lights.get("fixtures")) != TYPE_ARRAY:
		return _failure("lights must be normalized before collision inventory construction")
	var proxies: Array[Dictionary] = []
	_add_field_trees(proxies, field)
	_add_scenery(proxies, scenery)
	_add_lights(proxies, lights)
	proxies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	for proxy: Dictionary in proxies:
		if not _proxy_is_valid(proxy):
			errors.append("invalid obstacle proxy '%s'" % str(proxy.get("id", "?")))
	if not errors.is_empty():
		return {ok = false, errors = errors, world = {}}
	var bins: Dictionary = _build_bins(proxies)
	if bins.is_empty() and not proxies.is_empty():
		return _failure("collision broadphase exceeded its bounded bin-reference budget")
	var identity_parts: Array = [FORMAT, CELL_SIZE_M]
	for proxy: Dictionary in proxies:
		identity_parts.append([
			proxy.id, proxy.kind, proxy.part, proxy.shape, proxy.response_class,
			proxy.north, proxy.east, proxy.down, proxy.radius, proxy.half_length,
			proxy.half_x, proxy.half_down, proxy.half_z, proxy.sin_heading, proxy.cos_heading,
			proxy.bounds_north_min, proxy.bounds_north_max, proxy.bounds_east_min, proxy.bounds_east_max,
			proxy.bounds_down_min, proxy.bounds_down_max,
		])
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(identity_parts))
	var world := {
		"format": FORMAT,
		"identity": hash.finish().hex_encode(),
		"cell_size_m": CELL_SIZE_M,
		"proxies": proxies,
		"bins": bins,
	}
	return {ok = true, errors = PackedStringArray(), world = world}


static func nearby(world: Dictionary, north: float, east: float, down: float, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _world_header_is_valid(world) or not _finite_all([north, east, down, radius]) or radius < 0.0:
		return out
	var indices := _candidate_indices(world, north - radius, north + radius, east - radius, east + radius,
		down - radius, down + radius)
	for index: int in indices:
		var proxy: Dictionary = world.proxies[index]
		if _aabb_sphere_overlap(proxy, north, east, down, radius):
			out.append(proxy.duplicate())
	return out


static func _add_field_trees(proxies: Array[Dictionary], field: Dictionary) -> void:
	var pilot: Dictionary = field.pilot
	var pilot_north := float(pilot.get("north", NAN))
	var pilot_east := float(pilot.get("east", NAN))
	var pilot_down := float(pilot.get("down", 0.0))
	for object_value: Variant in field.get("objects", []):
		if typeof(object_value) != TYPE_DICTIONARY:
			continue
		var object: Dictionary = object_value
		if str(object.get("type", "")) != "treeline":
			continue
		var tree_id := str(object.get("id", "trees"))
		for index: int in object.get("positions", []).size():
			var point: Array = object.positions[index]
			if point.size() != 3:
				continue
			var local_north := float(point[0])
			var local_east := float(point[1])
			var base_down := pilot_down + float(point[2])
			var north := pilot_north + local_north
			var east := pilot_east + local_east
			var tree: Dictionary = Treeline.identity(local_north, local_east)
			_add_field_tree_proxies(proxies, "%s:%04d" % [tree_id, index], north, east,
				base_down, float(tree.height), int(tree.species), float(tree.yaw))


static func _add_scenery(proxies: Array[Dictionary], scenery: Dictionary) -> void:
	for group_value: Variant in scenery.get("groups", []):
		if typeof(group_value) != TYPE_DICTIONARY:
			continue
		var group: Dictionary = group_value
		var group_id := str(group.get("id", "group"))
		if str(group.get("type", "")) == "fleet":
			for index: int in group.get("placements", []).size():
				var placement: Dictionary = group.placements[index]
				var aircraft_id := str(placement.get("aircraft", ""))
				if not Models.FLEET.values().has(aircraft_id):
					continue
				var model_key: Variant = Models.FLEET.find_key(aircraft_id)
				if model_key == null or not Models.CATALOG.has(model_key):
					continue
				var model_key_text := str(model_key)
				var model_arrays: Dictionary = Models.arrays(model_key_text)
				if model_arrays.is_empty():
					continue
				var size: Vector3 = model_arrays.get("size", Models.CATALOG[model_key].size)
				var center_down := -(Models.parked_base_height(model_key_text) + size.y * 0.5)
				_add_box_at_down(proxies, "fleet:%s:%02d:%s" % [group_id, index, aircraft_id], "parked_aircraft", "airframe",
					"light_airframe_impulse", float(placement.north), float(placement.east), center_down, size.x, size.y, size.z,
					float(placement.heading))
			continue
		if str(group.get("type", "")) in ["hedge", "fence"]:
			_add_line_obstacles(proxies, group)
			continue
		for index: int in group.get("placements", []).size():
			var placement: Dictionary = group.placements[index]
			var prefab := str(placement.get("prefab", group.get("prefab", "")))
			var north := float(placement.get("north", NAN))
			var east := float(placement.get("east", NAN))
			var heading := float(placement.get("heading", 0.0))
			if prefab == "pit_shelter":
				_add_pit_shelter(proxies, "%s:%02d" % [group_id, index], north, east, heading)
			elif prefab == "pavilion":
				_add_pavilion(proxies, "%s:%02d" % [group_id, index], north, east, heading)
			elif prefab == "avanti_cradle":
				_add_avanti_cradle(proxies, "%s:%02d" % [group_id, index], north, east, heading)
			elif prefab == "shade_tree":
				_add_shade_tree_proxies(proxies, "%s:%02d" % [group_id, index], north, east, int(placement.get("seed", 0)))
			elif BUILDINGS.has(prefab):
				var spec: Dictionary = Prefabs.CATALOG[prefab]
				var size: Vector3 = spec.size
				_add_box(proxies, "building:%s:%02d:%s" % [group_id, index, prefab], "building", prefab,
					"hard_terminal", north, east, size.x, size.y, size.z, heading)
			elif VEHICLES.has(prefab):
				var spec: Dictionary = Prefabs.CATALOG[prefab] if Prefabs.CATALOG.has(prefab) else Models.CATALOG[prefab]
				var size: Vector3 = spec.size
				_add_box(proxies, "vehicle:%s:%02d:%s" % [group_id, index, prefab], "vehicle", prefab,
					"hard_terminal", north, east, size.x, size.y, size.z, heading)
			elif prefab in ["flagpole", "club_sign"]:
				_add_sign_and_pole(proxies, group_id, index, prefab, north, east, heading)
			elif prefab in ["picnic_table", "bench"]:
				_add_table_or_bench(proxies, group_id, index, prefab, north, east, heading)
			elif prefab in ["round_bale", "bale_stack"]:
				var size: Vector3 = Prefabs.CATALOG[prefab].size
				if prefab == "round_bale":
					_add_capsule(proxies, "equipment:%s:%02d:bale" % [group_id, index], "equipment", prefab,
						"frangible_impulse", north, east, -size.y * 0.5, size.x * 0.5, 0.0)
				else:
					_add_box(proxies, "equipment:%s:%02d:%s" % [group_id, index, prefab], "equipment", prefab,
						"hard_terminal", north, east, size.x, size.y, size.z, heading)
			elif prefab in ["person_pilot", "person_standing", "person_sitting"]:
				_add_person_proxy(proxies, group_id, index, prefab, north, east, heading)
			elif prefab == "bush":
				_add_capsule(proxies, "vegetation:%s:%02d:bush" % [group_id, index], "tree_foliage", "bush",
					"soft_foliage_impulse", north, east, -0.43, 0.80, 0.0)
			elif prefab in ["cow", "sheep"]:
				var size: Vector3 = Models.CATALOG[prefab].size
				_add_box(proxies, "animal:%s:%02d:%s" % [group_id, index, prefab], "animal", prefab,
					"light_airframe_impulse", north, east, size.x, size.y, size.z, heading)
			elif prefab == "turbine":
				var size: Vector3 = Prefabs.CATALOG[prefab].size
				_add_capsule(proxies, "landmark:%s:%02d:tower" % [group_id, index], "landmark", "turbine_tower",
					"hard_terminal", north, east, -size.y * 0.5, size.x * 0.16, size.y * 0.5 - size.x * 0.16)
			elif prefab == "pylon":
				_add_pylon(proxies, group_id, index, north, east, heading)


static func _add_field_tree_proxies(proxies: Array[Dictionary], id: String, north: float, east: float,
		base_down: float, height: float, species: int, yaw: float) -> void:
	var trunk_half_length := maxf(0.0, (height * TREE_TRUNK_HEIGHT_FRACTION - 2.0 * TREE_TRUNK_RADIUS_M) * 0.5)
	_add_capsule(proxies, "tree:%s:trunk" % id, "tree_trunk", "trunk", "hard_terminal",
		north, east, base_down - height * TREE_TRUNK_HEIGHT_FRACTION * 0.5,
		TREE_TRUNK_RADIUS_M, trunk_half_length)
	var species_index := clampi(species, 0, FIELD_TREE_ALPHA_HALF_WIDTH_FRACTIONS.size() - 1)
	var horizontal_half_extent := height * FIELD_TREE_CARD_FRAME_SIZE_M \
		* float(FIELD_TREE_ALPHA_HALF_WIDTH_FRACTIONS[species_index]) + FIELD_TREE_WIND_LEAN_M
	var vertical_half_extent := height * TREE_CROWN_VERTICAL_HALF_EXTENT_FRACTION
	# The box bounds every occupied atlas row, including near the top and the broad low Pine crown.
	# It deliberately encloses the gaps between the crossed cards; wind is a further radial .24 m allowance.
	_add_box_at_down(proxies, "tree:%s:crown" % id, "tree_foliage", "crown", "soft_foliage_impulse",
		north, east, base_down - height * TREE_CROWN_CENTER_FRACTION,
		horizontal_half_extent * 2.0, vertical_half_extent * 2.0, horizontal_half_extent * 2.0,
		rad_to_deg(-yaw))


static func _add_shade_tree_proxies(proxies: Array[Dictionary], id: String, north: float, east: float,
		seed: int) -> void:
	# Match the deterministic mesh recipe: 9.35–10.30 m broadleaf crown, 0.34 m basal trunk.
	var height := 9.35 + 0.95 * Palette.hash01(seed, 1)
	var trunk_height := height * (0.355 + 0.025 * Palette.hash01(seed, 2))
	var trunk_half := maxf(0.0, trunk_height * 0.5 - 0.34)
	_add_capsule(proxies, "tree:shade-tree:%s:trunk" % id, "tree_trunk", "trunk", "hard_terminal",
		north, east, -trunk_height * 0.5, 0.34, trunk_half)
	var crown_center_up := trunk_height + 3.2
	_add_capsule(proxies, "tree:shade-tree:%s:crown" % id, "tree_foliage", "crown", "soft_foliage_impulse",
		north, east, -crown_center_up, 4.0, 0.0)


static func _add_line_obstacles(proxies: Array[Dictionary], group: Dictionary) -> void:
	var group_id := str(group.get("id", "line"))
	var points: Array = group.get("points", [])
	if points.size() < 2:
		return
	var group_type := str(group.get("type", ""))
	var height := float(group.get("height", 0.0))
	if group_type == "hedge":
		var width := float(group.get("width", 1.0))
		for index: int in range(points.size() - 1):
			_add_line_box(proxies, "hedge:%s:%02d" % [group_id, index], "tree_foliage", "hedge",
				"soft_foliage_impulse", points[index], points[index + 1], width, height, -height * 0.5)
		return
	var style := str(group.get("style", "wire"))
	var rail_levels := PackedFloat64Array([0.35, 0.90]) if style == "rail" else PackedFloat64Array([0.25, 1.10])
	for index: int in range(points.size() - 1):
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		var length := a.distance_to(b)
		if length <= 1.0e-9:
			continue
		var post_count := maxi(1, ceili(length / 4.0))
		for post_index: int in range(post_count + 1):
			var fraction := float(post_index) / float(post_count)
			var n := lerpf(a.x, b.x, fraction)
			var e := lerpf(a.y, b.y, fraction)
			_add_box(proxies, "fence:%s:%02d:post:%02d" % [group_id, index, post_index], "fence", "post",
				"hard_terminal", n, e, 0.10, height, 0.10, 0.0)
		for level: int in rail_levels.size():
			_add_line_box(proxies, "fence:%s:%02d:rail:%d" % [group_id, index, level], "fence", style,
				"hard_terminal", a, b, 0.035, 0.035, -rail_levels[level])


static func _add_line_box(proxies: Array[Dictionary], id: String, kind: String, part: String,
		response: String, a: Variant, b: Variant, width: float, height: float, center_down: float) -> void:
	var start := Vector2(a.x, a.y) if a is Vector2 else Vector2(float(a[0]), float(a[1]))
	var finish := Vector2(b.x, b.y) if b is Vector2 else Vector2(float(b[0]), float(b[1]))
	var delta := finish - start
	var length := delta.length()
	if not is_finite(length) or length <= 1.0e-9:
		return
	var center_north := (start.x + finish.x) * 0.5
	var center_east := (start.y + finish.y) * 0.5
	var heading := rad_to_deg(atan2(delta.y, delta.x))
	_add_box_at_down(proxies, id, kind, part, response, center_north, center_east, center_down,
		width, height, length, heading)


static func _add_sign_and_pole(proxies: Array[Dictionary], group_id: String, index: int, prefab: String,
		north: float, east: float, heading: float) -> void:
	if prefab == "flagpole":
		_add_capsule(proxies, "fixture:%s:%02d:flagpole" % [group_id, index], "fixture", "flagpole",
			"hard_terminal", north, east, -4.0, 0.06, 3.94)
		return
	_add_box(proxies, "fixture:%s:%02d:sign" % [group_id, index], "fixture", "club_sign",
		"hard_terminal", north, east, 2.5, 2.2, 0.14, heading)


static func _add_table_or_bench(proxies: Array[Dictionary], group_id: String, index: int, prefab: String,
		north: float, east: float, heading: float) -> void:
	if prefab == "picnic_table":
		_add_box_at_down(proxies, "equipment:%s:%02d:tabletop" % [group_id, index], "equipment", "tabletop",
			"hard_terminal", north, east, -0.71, 1.8, 0.05, 0.75, heading)
		for side: int in 2:
			var local_z := -0.6 if side == 0 else 0.6
			var seat := _placement_point(north, east, heading, 0.0, local_z)
			_add_box_at_down(proxies, "equipment:%s:%02d:seat:%d" % [group_id, index, side], "equipment", "seat",
				"hard_terminal", seat[0], seat[1], -0.42, 1.8, 0.05, 0.25, heading)
		return
	_add_box_at_down(proxies, "equipment:%s:%02d:bench_seat" % [group_id, index], "equipment", "bench_seat",
		"hard_terminal", north, east, -0.43, 1.8, 0.05, 0.42, heading)
	var back := _placement_point(north, east, heading, 0.0, 0.25)
	_add_box_at_down(proxies, "equipment:%s:%02d:bench_back" % [group_id, index], "equipment", "bench_back",
		"hard_terminal", back[0], back[1], -0.675, 1.8, 0.35, 0.05, heading)


static func _add_person_proxy(proxies: Array[Dictionary], group_id: String, index: int, prefab: String,
		north: float, east: float, _heading: float) -> void:
	var size: Vector3 = Prefabs.CATALOG[prefab].size
	var radius := 0.28 if prefab != "person_sitting" else 0.34
	_add_capsule(proxies, "person:%s:%02d" % [group_id, index], "person", prefab, "soft_foliage_impulse",
		north, east, -size.y * 0.5, radius, maxf(0.0, size.y * 0.5 - radius))


static func _add_pylon(proxies: Array[Dictionary], group_id: String, index: int, north: float, east: float,
		heading: float) -> void:
	# Open lattice stays open in collision too: four tapered corner columns and cross arms, not a solid tower box.
	for corner: int in 4:
		var local_x := -2.0 if corner in [0, 3] else 2.0
		var local_z := -2.0 if corner < 2 else 2.0
		var base := _placement_point(north, east, heading, local_x * 1.5, local_z * 1.5)
		_add_capsule(proxies, "landmark:%s:%02d:pylon_leg:%d" % [group_id, index, corner], "landmark", "pylon_leg",
			"hard_terminal", base[0], base[1], -15.0, 0.18, 14.82)
	for arm: int in 3:
		var height: float = [18.0, 23.0, 27.5][arm]
		var half_span: float = [16.0, 13.0, 8.0][arm]
		_add_box_at_down(proxies, "landmark:%s:%02d:pylon_arm:%d" % [group_id, index, arm], "landmark", "pylon_arm",
			"hard_terminal", north, east, -height, half_span, 0.22, 0.22, heading + 90.0)


static func _add_pit_shelter(proxies: Array[Dictionary], id: String, north: float, east: float, heading: float) -> void:
	# The shelter is an open pole structure: 9 posts on each long side and one roof slab.
	# There is deliberately no enclosing solid box and no floor collider.
	var length := 28.0
	var depth := 5.0
	var post_h := 3.35
	for row: int in 2:
		var local_z := (-1.0 if row == 0 else 1.0) * (depth * 0.5 - 0.1)
		for post_index: int in 9:
			var local_x := -length * 0.5 + float(post_index) * length / 8.0
			var at := _placement_point(north, east, heading, local_x, local_z)
			_add_box(proxies, "building:%s:post:%d:%d" % [id, row, post_index], "building", "shelter_post",
				"hard_terminal", at[0], at[1], 0.16, post_h, 0.16, heading)
	var roof := _placement_point(north, east, heading, 0.0, 0.0)
	_add_box_at_down(proxies, "building:%s:roof" % id, "building", "shelter_roof", "hard_terminal",
		roof[0], roof[1], -3.22, 29.0, 0.14, 6.6, heading)


static func _add_pavilion(proxies: Array[Dictionary], id: String, north: float, east: float, heading: float) -> void:
	# Match the open front veranda in Prefabs._pavilion: slab, main shell, posts, rails,
	# built-in bench and thin roof bounds. The two center step bays stay open.
	_add_local_box(proxies, "building:%s:pavilion:slab" % id, "building", "pavilion_slab", "hard_terminal",
		north, east, heading, 0.0, 0.075, -1.3, 10.0, 0.15, 9.6)
	_add_local_box(proxies, "building:%s:pavilion:main" % id, "building", "pavilion_main", "hard_terminal",
		north, east, heading, 0.0, 1.5, 0.0, 9.0, 2.7, 6.0)
	# The prefab's hip roof spans x ±5, z ±3.5 and y 2.85–4.65. This AABB
	# conservatively covers the pitched surfaces and the volume below their slopes.
	_add_local_box(proxies, "building:%s:pavilion:main_roof" % id, "building", "pavilion_main_roof", "hard_terminal",
		north, east, heading, 0.0, 3.75, 0.0, 10.0, 1.8, 7.0)
	for post_index: int in 4:
		var local_x: float = [-4.2, -1.4, 1.4, 4.2][post_index]
		_add_local_box(proxies, "building:%s:pavilion:porch_post:%02d" % [id, post_index], "building", "pavilion_porch_post",
			"hard_terminal", north, east, heading, local_x, 1.375, -5.85, 0.14, 2.45, 0.14)
	# The fascia reaches y=2.48; include it in the conservative thin porch-roof AABB.
	_add_local_box(proxies, "building:%s:pavilion:porch_roof" % id, "building", "pavilion_porch_roof", "hard_terminal",
		north, east, heading, 0.0, 2.715, -4.6, 9.4, 0.47, 3.2)
	# The prefab's built-in bench is a seat, two feet and a narrow sloped back; this
	# small AABB contains that measured envelope without extending into the step bay.
	_add_local_box(proxies, "building:%s:pavilion:bench" % id, "building", "pavilion_bench", "hard_terminal",
		north, east, heading, -2.8, 0.575, -3.455, 1.8, 0.85, 0.49)
	for segment_index: int in 2:
		var segment: Array = [[-4.2, -1.4], [1.4, 4.2]][segment_index]
		var rail_start := _placement_point(north, east, heading, float(segment[0]), -5.85)
		var rail_end := _placement_point(north, east, heading, float(segment[1]), -5.85)
		_add_line_box(proxies, "building:%s:pavilion:porch_rail:%d" % [id, segment_index], "building", "pavilion_porch_rail",
			"hard_terminal", rail_start, rail_end, 0.06, 0.06, -0.95)


static func _add_local_box(proxies: Array[Dictionary], id: String, kind: String, part: String, response: String,
		north: float, east: float, heading: float, local_x: float, center_up: float, local_z: float,
		width: float, height: float, length: float) -> void:
	var center: PackedFloat64Array = _placement_point(north, east, heading, local_x, local_z)
	_add_box_at_down(proxies, id, kind, part, response, center[0], center[1], -center_up,
		width, height, length, heading)


static func _add_avanti_cradle(proxies: Array[Dictionary], id: String, north: float, east: float,
		heading: float) -> void:
	# Two padded crossbars and their four low trestle feet support the parked gear-up Avanti.
	for row: int in 2:
		var local_z := -0.62 if row == 0 else 0.62
		for side: int in 2:
			var local_x := -0.20 if side == 0 else 0.20
			var foot := _placement_point(north, east, heading, local_x, local_z)
			_add_box_at_down(proxies, "support:%s:leg:%d:%d" % [id, row, side], "aircraft_support", "cradle_leg",
				"hard_terminal", foot[0], foot[1], -0.20, 0.055, 0.40, 0.055, heading)
		var crossbar := _placement_point(north, east, heading, 0.0, local_z)
		_add_box_at_down(proxies, "support:%s:pad:%d" % [id, row], "aircraft_support", "cradle_pad",
			"hard_terminal", crossbar[0], crossbar[1], -0.40, 0.70, 0.07, 0.34, heading)


static func _add_lights(proxies: Array[Dictionary], lights: Dictionary) -> void:
	for fixture_value: Variant in lights.get("fixtures", []):
		if typeof(fixture_value) != TYPE_DICTIONARY:
			continue
		var fixture: Dictionary = fixture_value
		var fixture_id := str(fixture.get("id", "lamp"))
		var height := float(fixture.get("height", 0.0))
		if str(fixture.get("type", "")) == "flood":
			_add_capsule(proxies, "lamp:%s:pole" % fixture_id, "lamp", "flood_pole", "frangible_impulse",
				float(fixture.get("north", NAN)), float(fixture.get("east", NAN)), -height * 0.5,
				0.07, maxf(0.0, height * 0.5 - 0.07))
		elif str(fixture.get("type", "")) == "stake_row":
			for index: int in fixture.get("points", []).size():
				var point: Array = fixture.points[index]
				if point.size() != 2:
					continue
				_add_capsule(proxies, "lamp:%s:%02d" % [fixture_id, index], "lamp", "stake", "frangible_impulse",
					float(point[0]), float(point[1]), -height * 0.5, 0.035, maxf(0.0, height * 0.5 - 0.035))


static func _placement_point(center_north: float, center_east: float, heading_deg: float, local_x: float, local_z: float) -> PackedFloat64Array:
	var heading := deg_to_rad(heading_deg)
	var sin_heading := sin(heading)
	var cos_heading := cos(heading)
	return PackedFloat64Array([
		center_north - sin_heading * local_x - cos_heading * local_z,
		center_east + cos_heading * local_x - sin_heading * local_z,
	])


static func _add_box(proxies: Array[Dictionary], id: String, kind: String, part: String, response: String,
		north: float, east: float, width: float, height: float, length: float, heading_deg: float) -> void:
	_add_box_at_down(proxies, id, kind, part, response, north, east, -height * 0.5, width, height, length, heading_deg)


static func _add_box_at_down(proxies: Array[Dictionary], id: String, kind: String, part: String, response: String,
		north: float, east: float, down: float, width: float, height: float, length: float, heading_deg: float) -> void:
	var half_x := width * 0.5
	var half_down := height * 0.5
	var half_z := length * 0.5
	var heading := deg_to_rad(heading_deg)
	var sin_heading := sin(heading)
	var cos_heading := cos(heading)
	var north_extent := absf(sin_heading) * half_x + absf(cos_heading) * half_z
	var east_extent := absf(cos_heading) * half_x + absf(sin_heading) * half_z
	proxies.append({
		"id": id, "kind": kind, "part": part, "shape": "box", "response_class": response,
		"north": north, "east": east, "down": down, "radius": 0.0, "half_length": 0.0,
		"half_x": half_x, "half_down": half_down, "half_z": half_z,
		"sin_heading": sin_heading, "cos_heading": cos_heading,
		"bounds_north_min": north - north_extent, "bounds_north_max": north + north_extent,
		"bounds_east_min": east - east_extent, "bounds_east_max": east + east_extent,
		"bounds_down_min": down - half_down, "bounds_down_max": down + half_down,
	})


static func _add_capsule(proxies: Array[Dictionary], id: String, kind: String, part: String, response: String,
		north: float, east: float, down: float, radius: float, half_length: float) -> void:
	proxies.append({
		"id": id, "kind": kind, "part": part, "shape": "capsule", "response_class": response,
		"north": north, "east": east, "down": down, "radius": radius, "half_length": half_length,
		"half_x": 0.0, "half_down": 0.0, "half_z": 0.0, "sin_heading": 0.0, "cos_heading": 1.0,
		"bounds_north_min": north - radius, "bounds_north_max": north + radius,
		"bounds_east_min": east - radius, "bounds_east_max": east + radius,
		"bounds_down_min": down - half_length - radius, "bounds_down_max": down + half_length + radius,
	})


static func _build_bins(proxies: Array[Dictionary]) -> Dictionary:
	var bins: Dictionary = {}
	var references := 0
	for index: int in proxies.size():
		var proxy: Dictionary = proxies[index]
		var min_n := floori(float(proxy.bounds_north_min) / CELL_SIZE_M)
		var max_n := floori(float(proxy.bounds_north_max) / CELL_SIZE_M)
		var min_e := floori(float(proxy.bounds_east_min) / CELL_SIZE_M)
		var max_e := floori(float(proxy.bounds_east_max) / CELL_SIZE_M)
		var min_d := floori(float(proxy.bounds_down_min) / CELL_SIZE_M)
		var max_d := floori(float(proxy.bounds_down_max) / CELL_SIZE_M)
		var item_references := (max_n - min_n + 1) * (max_e - min_e + 1) * (max_d - min_d + 1)
		if item_references <= 0 or item_references > MAX_BIN_REFERENCES or references + item_references > MAX_BIN_REFERENCES:
			return {}
		references += item_references
		for n_cell: int in range(min_n, max_n + 1):
			for e_cell: int in range(min_e, max_e + 1):
				for d_cell: int in range(min_d, max_d + 1):
					var key := _cell_key(n_cell, e_cell, d_cell)
					if not bins.has(key):
						bins[key] = PackedInt64Array()
					bins[key].append(index)
	return bins


static func _candidate_indices(world: Dictionary, north_min: float, north_max: float, east_min: float,
		east_max: float, down_min: float, down_max: float) -> Array[int]:
	var candidates: Dictionary = {}
	var result: Array[int] = []
	var min_n := floori(north_min / CELL_SIZE_M)
	var max_n := floori(north_max / CELL_SIZE_M)
	var min_e := floori(east_min / CELL_SIZE_M)
	var max_e := floori(east_max / CELL_SIZE_M)
	var min_d := floori(down_min / CELL_SIZE_M)
	var max_d := floori(down_max / CELL_SIZE_M)
	var cells: int = (max_n - min_n + 1) * (max_e - min_e + 1) * (max_d - min_d + 1)
	if cells <= 0 or cells > 4096:
		for index: int in world.proxies.size():
			result.append(index)
		return result
	for n_cell: int in range(min_n, max_n + 1):
		for e_cell: int in range(min_e, max_e + 1):
			for d_cell: int in range(min_d, max_d + 1):
				var key := _cell_key(n_cell, e_cell, d_cell)
				if not world.bins.has(key):
					continue
				for index: int in world.bins[key]:
					candidates[index] = true
	for key: Variant in candidates.keys():
		result.append(int(key))
	result.sort()
	return result


static func _cell_key(north_cell: int, east_cell: int, down_cell: int) -> String:
	return "%d,%d,%d" % [north_cell, east_cell, down_cell]


static func _aabb_sphere_overlap(proxy: Dictionary, north: float, east: float, down: float, radius: float) -> bool:
	var dn := maxf(float(proxy.bounds_north_min) - north, maxf(0.0, north - float(proxy.bounds_north_max)))
	var de := maxf(float(proxy.bounds_east_min) - east, maxf(0.0, east - float(proxy.bounds_east_max)))
	var dd := maxf(float(proxy.bounds_down_min) - down, maxf(0.0, down - float(proxy.bounds_down_max)))
	return dn * dn + de * de + dd * dd <= radius * radius


static func _proxy_is_valid(proxy: Dictionary) -> bool:
	for key: String in ["id", "kind", "part", "response_class", "shape"]:
		if typeof(proxy.get(key)) != TYPE_STRING or str(proxy[key]).is_empty():
			return false
	if proxy.shape not in ["box", "capsule"]:
		return false
	for key: String in ["north", "east", "down", "radius", "half_length", "half_x", "half_down", "half_z",
			"sin_heading", "cos_heading", "bounds_north_min", "bounds_north_max", "bounds_east_min",
			"bounds_east_max", "bounds_down_min", "bounds_down_max"]:
		if typeof(proxy.get(key)) != TYPE_FLOAT and typeof(proxy.get(key)) != TYPE_INT:
			return false
		if not is_finite(float(proxy[key])):
			return false
	if proxy.shape == "capsule":
		return float(proxy.radius) > 0.0 and float(proxy.half_length) >= 0.0
	return float(proxy.half_x) > 0.0 and float(proxy.half_down) > 0.0 and float(proxy.half_z) > 0.0


static func _world_header_is_valid(world: Dictionary) -> bool:
	return str(world.get("format", "")) == FORMAT and typeof(world.get("identity")) == TYPE_STRING \
		and typeof(world.get("proxies")) == TYPE_ARRAY and typeof(world.get("bins")) == TYPE_DICTIONARY \
		and float(world.get("cell_size_m", 0.0)) == CELL_SIZE_M


static func _finite_all(values: Array) -> bool:
	for value: Variant in values:
		if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or not is_finite(float(value)):
			return false
	return true


static func _failure(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message]), world = {}}
