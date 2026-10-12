extends SceneTree

const CollisionWorld := preload("res://scenery/collision_world.gd")
const Collision := preload("res://sim/scenery_collision.gd")
const TreeAssets := preload("res://render/tree_assets.gd")
const Treeline := preload("res://render/treeline.gd")
const RB := preload("res://physics/rigid_body.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_tree_canopy_bounds_and_contacts()
	_test_pavilion_parts_and_open_bays()
	print("landscape collision coverage: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_tree_canopy_bounds_and_contacts() -> void:
	var catalog_result: Dictionary = TreeAssets.catalog()
	_check("tree asset catalog loads", catalog_result.ok)
	if not catalog_result.ok:
		return
	var image_path := ProjectSettings.globalize_path("res://assets/landscape/trees/atlas.png")
	var atlas := Image.load_from_file(image_path)
	_check("tree atlas image loads for occupied-alpha measurement", atlas != null and atlas.get_width() == 1024)
	if atlas == null or atlas.get_width() != 1024:
		return
	var expected_ids := ["CommonTree_1", "CommonTree_3", "Pine_1"]
	var configured: Array = CollisionWorld.FIELD_TREE_ALPHA_HALF_WIDTH_FRACTIONS
	var positions: Array = _one_position_per_species(expected_ids.size())
	_check("deterministic identity search finds all field-tree species", positions.size() == expected_ids.size())
	if positions.size() != expected_ids.size():
		return
	for species_index: int in expected_ids.size():
		var entry: Dictionary = catalog_result.catalog.species[species_index]
		var rect: Array = entry.atlas_rect_px
		var alpha_bounds := _alpha_bounds(atlas, int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]),
			TreeAssets.ALPHA_CUTOFF)
		_check("%s alpha half-width is measured from occupied atlas pixels" % expected_ids[species_index],
			is_equal_approx(float(configured[species_index]), float(alpha_bounds.max_half_fraction)))
		_check("%s frame multiplier matches the card builder" % expected_ids[species_index],
			is_equal_approx(float(entry.frame_size_m), CollisionWorld.FIELD_TREE_CARD_FRAME_SIZE_M))
		_check("%s bound does not use the transparent full-card width" % expected_ids[species_index],
			float(configured[species_index]) < 0.40)
	_check("field-tree wind allowance matches the renderer", CollisionWorld.FIELD_TREE_WIND_LEAN_M == Treeline.WIND_LEAN_M)

	for species_index: int in expected_ids.size():
		var point: Array = positions[species_index]
		var identity: Dictionary = Treeline.identity(float(point[0]), float(point[1]))
		var entry: Dictionary = catalog_result.catalog.species[species_index]
		var rect: Array = entry.atlas_rect_px
		var alpha_bounds := _alpha_bounds(atlas, int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]),
			TreeAssets.ALPHA_CUTOFF)
		var field := _field_with_trees([point])
		var built: Dictionary = CollisionWorld.build(field, {groups = []})
		_check("species %s world builds" % expected_ids[species_index], built.ok)
		if not built.ok:
			continue
		var crown: Variant = _proxy_with_part(built.world, "crown")
		var trunk: Variant = _proxy_with_part(built.world, "trunk")
		_check("species %s retains a solid trunk" % expected_ids[species_index], trunk != null
			and trunk.kind == "tree_trunk" and trunk.response_class == "hard_terminal")
		if crown == null:
			_check("species %s has a separate flexible crown proxy" % expected_ids[species_index], false)
			continue
		var height := float(identity.height)
		var frame_size := float(entry.frame_size_m)
		var radius := height * frame_size * float(configured[species_index]) + CollisionWorld.FIELD_TREE_WIND_LEAN_M
		_check("species %s crown uses a yaw-safe conservative box" % expected_ids[species_index], crown.shape == "box"
			and crown.kind == "tree_foliage" and crown.response_class == "soft_foliage_impulse")
		_check("species %s crown has measured horizontal and preserved vertical extents" % expected_ids[species_index],
			is_equal_approx(float(crown.half_x), radius) and is_equal_approx(float(crown.half_z), radius)
			and is_equal_approx(float(crown.half_down), height * CollisionWorld.TREE_CROWN_VERTICAL_HALF_EXTENT_FRACTION))
		_check("species %s tree identity includes wind allowance" % expected_ids[species_index],
			float(crown.bounds_north_max) > float(crown.north) + height * frame_size * float(configured[species_index]))

		var old_radius := height * 0.18
		var inside_new_only := (old_radius + radius) * 0.5
		var base_north := float(point[0])
		var base_east := float(point[1])
		var down := -height * CollisionWorld.TREE_CROWN_CENTER_FRACTION
		var sweep_extent := radius * 2.0 + 1.0
		var start := _state(base_north - sweep_extent, base_east + inside_new_only, down, 4.0, 0.0, 0.0)
		var finish := _state(base_north + sweep_extent, base_east + inside_new_only, down, 4.0, 0.0, 0.0)
		var hit := Collision.first_hit(start, finish, PackedFloat64Array([0.0, 0.0, 0.0]),
			built.world, species_index, 2.0, PackedFloat64Array([1.0, 1.2, 1.4, 0.0, 0.0, 0.0]))
		_check("species %s now responds beyond the former 0.18-height radius" % expected_ids[species_index],
			hit != null and hit.response_class == "soft_foliage_impulse" and not hit.terminal)
		var outside := sqrt(2.0) * radius + 0.2
		var outside_start := _state(base_north - sweep_extent, base_east + outside, down, 4.0, 0.0, 0.0)
		var outside_finish := _state(base_north + sweep_extent, base_east + outside, down, 4.0, 0.0, 0.0)
		_check("species %s query outside the conservative crown square stays clear" % expected_ids[species_index],
			Collision.first_hit(outside_start, outside_finish, PackedFloat64Array([0.0, 0.0, 0.0]),
				built.world, species_index + 10, 2.0, PackedFloat64Array([1.0, 1.2, 1.4, 0.0, 0.0, 0.0])) == null)
		for sample_index: int in 2:
			var sample_row := int(alpha_bounds.widest_row) if sample_index == 0 else int(alpha_bounds.top_row)
			var sample_width := float(alpha_bounds.widest_half_fraction) if sample_index == 0 \
				else float(alpha_bounds.top_half_fraction)
			var up_fraction := 0.5 + frame_size * 0.5 - frame_size * (float(sample_row) + 0.5) / float(rect[3])
			var sample_down := -height * up_fraction
			var sample_east_offset := height * frame_size * sample_width + CollisionWorld.FIELD_TREE_WIND_LEAN_M * 0.5
			var sample_start := _state(base_north - sweep_extent, base_east + sample_east_offset,
				sample_down, 4.0, 0.0, 0.0)
			var sample_finish := _state(base_north + sweep_extent, base_east + sample_east_offset,
				sample_down, 4.0, 0.0, 0.0)
			var sample_hit := Collision.first_hit(sample_start, sample_finish, PackedFloat64Array([0.0, 0.0, 0.0]),
				built.world, species_index + 20 + sample_index, 2.0, PackedFloat64Array([1.0, 1.2, 1.4, 0.0, 0.0, 0.0]))
			var height_label := "widest" if sample_index == 0 else "topmost"
			_check("species %s crown remains covered off-axis at its %s occupied alpha height" %
				[expected_ids[species_index], height_label], sample_hit != null
				and sample_hit.obstacle_part == "crown" and not sample_hit.terminal)


func _test_pavilion_parts_and_open_bays() -> void:
	var scenery := {groups = [{id = "clubhouse", type = "instances", placements = [
		{north = 20.0, east = -7.0, heading = 0.0, prefab = "pavilion"}]}]}
	var field := _field_with_trees([])
	var built: Dictionary = CollisionWorld.build(field, scenery)
	_check("pavilion collision inventory builds", built.ok)
	if not built.ok:
		return
	var world: Dictionary = built.world
	var second: Dictionary = CollisionWorld.build(field, scenery)
	_check("pavilion identity is stable for a repeated build", second.ok and second.world.identity == world.identity)
	var changed_scenery: Dictionary = scenery.duplicate(true)
	changed_scenery.groups[0].placements[0].north += 0.25
	var changed: Dictionary = CollisionWorld.build(field, changed_scenery)
	_check("pavilion geometry change updates checkpoint world identity", changed.ok and changed.world.identity != world.identity)
	var pavilion_parts := 0
	for proxy: Dictionary in world.proxies:
		if str(proxy.id).begins_with("building:clubhouse:00:pavilion:"):
			pavilion_parts += 1
	_check("pavilion uses eleven bounded parts instead of a filled air envelope", pavilion_parts == 11)
	var slab: Variant = _proxy_with_part(world, "pavilion_slab")
	var shell: Variant = _proxy_with_part(world, "pavilion_main")
	var roof: Variant = _proxy_with_part(world, "pavilion_main_roof")
	var porch_roof: Variant = _proxy_with_part(world, "pavilion_porch_roof")
	var bench: Variant = _proxy_with_part(world, "pavilion_bench")
	_check("pavilion slab bounds match its ten-by-nine-point-six metre mesh", slab != null
		and is_equal_approx(float(slab.half_x), 5.0) and is_equal_approx(float(slab.half_z), 4.8)
		and is_equal_approx(float(slab.half_down), 0.075))
	_check("pavilion main block and pitched roof have separate bounds", shell != null and roof != null
		and is_equal_approx(float(shell.half_x), 4.5) and is_equal_approx(float(shell.half_z), 3.0)
		and is_equal_approx(float(roof.half_x), 5.0) and is_equal_approx(float(roof.half_z), 3.5))
	_check("porch roof stays a thin conservative bound over the measured overhang", porch_roof != null
		and float(porch_roof.half_down) < 0.25 and is_equal_approx(float(porch_roof.north), 24.6))
	_check("built-in pavilion bench receives a low-obstacle proxy", bench != null and bench.part == "pavilion_bench")
	var post_count := 0
	var rail_count := 0
	for proxy: Dictionary in world.proxies:
		if str(proxy.part) == "pavilion_porch_post":
			post_count += 1
		elif str(proxy.part) == "pavilion_porch_rail":
			rail_count += 1
	_check("all four porch posts and two interrupted top rails remain separate", post_count == 4 and rail_count == 2)

	var hull := PackedFloat64Array([0.0, 0.0, 0.0])
	var bay_start := _state(24.0, -7.0, -1.2, 3.0, 0.0, 0.0)
	var bay_finish := _state(27.0, -7.0, -1.2, 3.0, 0.0, 0.0)
	_check("center porch step bay remains open to an aircraft at 1.2 m", Collision.contacts(bay_start, bay_finish,
		hull, world, 30, 2.0, _inertia()).is_empty())
	var post_start := _state(24.0, -11.2, -1.2, 3.0, 0.0, 0.0)
	var post_finish := _state(27.0, -11.2, -1.2, 3.0, 0.0, 0.0)
	var post_hit := Collision.first_hit(post_start, post_finish, hull, world, 31, 2.0, _inertia())
	_check("porch corner support post is collidable", post_hit != null and post_hit.obstacle_part == "pavilion_porch_post")
	var rail_start := _state(24.0, -9.8, -0.95, 3.0, 0.0, 0.0)
	var rail_finish := _state(27.0, -9.8, -0.95, 3.0, 0.0, 0.0)
	var rail_hit := Collision.first_hit(rail_start, rail_finish, hull, world, 32, 2.0, _inertia())
	_check("porch low rail is collidable", rail_hit != null and rail_hit.obstacle_part == "pavilion_porch_rail")
	var slab_start := _state(25.0, -7.0, -0.4, 0.0, 0.0, 2.0)
	var slab_finish := _state(25.0, -7.0, 0.2, 0.0, 0.0, 2.0)
	var slab_hit := Collision.first_hit(slab_start, slab_finish, hull, world, 33, 2.0, _inertia())
	_check("porch floor slab is collidable from above", slab_hit != null and slab_hit.obstacle_part == "pavilion_slab")
	var roof_start := _state(24.6, -7.0, -2.2, 0.0, 0.0, -4.0)
	var roof_finish := _state(24.6, -7.0, -3.2, 0.0, 0.0, -4.0)
	var roof_hit := Collision.first_hit(roof_start, roof_finish, hull, world, 34, 2.0, _inertia())
	_check("porch roof underside is independently collidable", roof_hit != null
		and roof_hit.obstacle_part == "pavilion_porch_roof")


func _one_position_per_species(count: int) -> Array:
	var positions: Array = []
	for wanted_species: int in count:
		for index: int in 4000:
			var north := float(index)
			var east := float((index * 37) % 211)
			var identity: Dictionary = Treeline.identity(north, east)
			if int(identity.species) == wanted_species:
				positions.append([north, east, 0.0])
				break
	return positions


func _alpha_bounds(atlas: Image, x0: int, y0: int, width: int, height: int, cutoff: float) -> Dictionary:
	var max_half_fraction := 0.0
	var widest_row := -1
	var widest_half_fraction := 0.0
	var top_row := -1
	var top_half_fraction := 0.0
	var center_x := float(x0) + float(width) * 0.5
	for local_y: int in height:
		var row_half := 0.0
		for x: int in range(x0, x0 + width):
			if atlas.get_pixel(x, y0 + local_y).a >= cutoff:
				row_half = maxf(row_half, absf(float(x) + 0.5 - center_x) / float(width))
		if row_half <= 0.0:
			continue
		if top_row < 0:
			top_row = local_y
			top_half_fraction = row_half
		max_half_fraction = maxf(max_half_fraction, row_half)
		if row_half > widest_half_fraction:
			widest_row = local_y
			widest_half_fraction = row_half
	return {max_half_fraction = max_half_fraction, widest_row = widest_row,
		widest_half_fraction = widest_half_fraction, top_row = top_row, top_half_fraction = top_half_fraction}


func _field_with_trees(positions: Array) -> Dictionary:
	return {id = "collision-coverage-test", pilot = {north = 0.0, east = 0.0, down = 0.0},
		objects = [{id = "coverage", type = "treeline", positions = positions}]}


func _proxy_with_part(world: Dictionary, part: String) -> Variant:
	for proxy: Dictionary in world.proxies:
		if str(proxy.part) == part:
			return proxy
	return null


func _state(north: float, east: float, down: float, vn: float, ve: float, vd: float) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([north, east, down]), PackedFloat64Array([vn, ve, vd]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))


func _inertia() -> PackedFloat64Array:
	return PackedFloat64Array([1.0, 1.2, 1.4, 0.0, 0.0, 0.0])


func _check(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("ok ", label)
	else:
		failures += 1
		printerr("FAIL ", label)
