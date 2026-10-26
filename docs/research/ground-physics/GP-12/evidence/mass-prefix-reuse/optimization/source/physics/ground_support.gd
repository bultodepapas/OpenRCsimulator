## GP-10: prepared, versioned solid height-field queries. No force, mutable solver
## state or native Godot vectors. The vertical gap is exact for the height field;
## its footpoint is NOT the Euclidean closest point on curved terrain.
extends RefCounted

const Terrain := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/ground_terrain.gd")
const LakeSurface := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/lake_surface.gd")
const FORMAT := "openrc-ground-support v1"
const LEGACY := "legacy-field-relief-v1"
const EXPLICIT := "explicit-field-relief-v1"


## Region provenance is optional. A raw stride-6 table cannot establish material
## identity from its friction multipliers. Copies detach the setup inputs.
static func prepare_legacy(surfaces: PackedFloat64Array, regions: Array = []) -> Dictionary:
	return _prepare(surfaces, PackedFloat64Array(), regions, LEGACY)


## Prepared research/authoring route, not a silent upgrade of legacy consumers.
## Same bounded GP-01 waves, independently specified amplitude per rectangle.
static func prepare_explicit(surfaces: PackedFloat64Array, relief_m: PackedFloat64Array,
		regions: Array = []) -> Dictionary:
	if relief_m.size() != surfaces.size() / Terrain.SURFACE_STRIDE:
		return _failure("relief count must match surface rows")
	for value: float in relief_m:
		if not is_finite(value) or value < 0.0 or value > Terrain.RELIEF_ROUGH_M:
			return _failure("explicit relief exceeds the qualified 0..7 mm geometry envelope")
	return _prepare(surfaces, relief_m, regions, EXPLICIT)


static func _prepare(surfaces: PackedFloat64Array, relief_m: PackedFloat64Array,
		regions: Array, geometry_law: String) -> Dictionary:
	if not Terrain.is_valid_surface_table(surfaces):
		return _failure("invalid legacy surface layout")
	var count: int = maxi(1, surfaces.size() / Terrain.SURFACE_STRIDE)
	if not regions.is_empty() and regions.size() != count:
		return _failure("region count must match surface rows")
	var registry: Array[Dictionary] = []
	var seen := {}
	for row: int in count:
		var item := {region_id = "legacy_row_%d" % row, usage_id = "unspecified", material_id = "unspecified"}
		if surfaces.is_empty():
			item = {region_id = "flat_fixture", usage_id = "fixture", material_id = "dry_pavement"}
		if not regions.is_empty():
			if typeof(regions[row]) != TYPE_DICTIONARY:
				return _failure("region must be an object")
			for key: String in ["region_id", "usage_id", "material_id"]:
				if typeof(regions[row].get(key)) != TYPE_STRING or str(regions[row][key]).strip_edges().is_empty() \
					or str(regions[row][key]).length() > 128:
					return _failure("region identity must be a nonempty bounded string")
				item[key] = regions[row][key]
		if seen.has(item.region_id):
			return _failure("duplicate region identity")
		seen[item.region_id] = true
		registry.append(item)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update((FORMAT + ":" + geometry_law).to_utf8_buffer())
	if not surfaces.is_empty():
		hash.update(surfaces.to_byte_array())
	if not relief_m.is_empty():
		hash.update(relief_m.to_byte_array())
	hash.update(JSON.stringify(registry).to_utf8_buffer())
	return {ok = true, format = FORMAT, geometry_law = geometry_law, surfaces = surfaces.duplicate(),
		relief_m = relief_m.duplicate(), regions = registry, identity = hash.finish().hex_encode()}


## Detached observation. Stage time is explicit even though this solid geometry
## is static; moving water/road/obstacle support is a different provider contract.
## Use an unchanged successful prepared result. Environment owns its private copy.
static func sample(prepared: Dictionary, position: PackedFloat64Array,
		velocity: PackedFloat64Array, time_s: float, lake: Dictionary = {}) -> Dictionary:
	if not prepared.get("ok", false) or prepared.get("format") != FORMAT \
		or not _vector(position) or not _vector(velocity) or not is_finite(time_s) or time_s < 0.0:
		return _failure("invalid support query")
	var surfaces: PackedFloat64Array = prepared.surfaces
	var height: PackedFloat64Array
	if prepared.geometry_law == LEGACY:
		height = Terrain.sample(position[0], position[1], surfaces, lake)
	elif prepared.geometry_law == EXPLICIT:
		height = Terrain.sample_profiled(position[0], position[1], surfaces, prepared.relief_m, lake)
	else:
		return _failure("unsupported geometry law", "unsupported_geometry")
	if not _vector(height):
		return _failure("invalid surface geometry")
	var normal := Terrain.normal_from_up_slopes(height[1], height[2])
	if normal.is_empty():
		return _failure("invalid surface normal")
	var row := 0
	if not surfaces.is_empty():
		var offset := 0
		while offset + Terrain.SURFACE_STRIDE < surfaces.size():
			if position[0] >= surfaces[offset] and position[0] <= surfaces[offset + 1] \
				and position[1] >= surfaces[offset + 2] and position[1] <= surfaces[offset + 3]:
				break
			offset += Terrain.SURFACE_STRIDE
		row = offset / Terrain.SURFACE_STRIDE
	var region: Dictionary = prepared.regions[row]
	var gap := -position[2] - height[0]
	var gradient := PackedFloat64Array([-height[1], -height[2], -1.0])
	var gap_rate := gradient[0] * velocity[0] + gradient[1] * velocity[1] + gradient[2] * velocity[2]
	var normal_speed := normal[0] * velocity[0] + normal[1] * velocity[1] + normal[2] * velocity[2]
	if not is_finite(gap) or not is_finite(gap_rate) or not is_finite(normal_speed):
		return _failure("support query overflow")
	var geometry_id: String = prepared.geometry_law
	var material_id: String = region.material_id
	var coverage := "field"
	var derivative_method := "analytic"
	var derivative_stencil_m := 0.0
	if not lake.is_empty():
		var basin := LakeSurface.sample_covered_terrain_validated(lake, position[0], position[1])
		if bool(basin.get("covered", false)):
			derivative_method = "provider_finite_difference"
			derivative_stencil_m = LakeSurface.SAMPLE_EPSILON_M
			coverage = "lake_" + str(basin.get("region", "unknown"))
			geometry_id += ":lake:" + str(lake.get("identity", "unspecified"))
			# A lake's solid bed/bank is not its moving water surface and does not
			# acquire a measured soil material from the overlaid grass rectangle.
			material_id = "unspecified"
	return {ok = true, status = "support", format = FORMAT, geometry_id = geometry_id,
		environment_identity = str(prepared.identity) + ":lake:" + str(lake.get("identity", "none")),
		coverage = coverage, surface_kind = "solid",
		region_id = region.region_id, usage_id = region.usage_id, material_id = material_id,
		profile_index = row, material_resolved = material_id != "unspecified",
		height_up_m = height[0], slopes_up = height.slice(1),
		vertical_footpoint_ned = PackedFloat64Array([position[0], position[1], -height[0]]),
		closest_point_valid = false, gap_kind = "vertical_height",
		derivative_method = derivative_method, derivative_stencil_m = derivative_stencil_m,
		signed_gap_m = gap, gap_gradient_ned = gradient, gap_rate_mps = gap_rate,
		normal_ned = normal, normal_velocity_mps = normal_speed,
		surface_velocity_ned = PackedFloat64Array([0.0, 0.0, 0.0])}


static func _vector(value: PackedFloat64Array) -> bool:
	return value.size() == 3 and is_finite(value[0]) and is_finite(value[1]) and is_finite(value[2])


static func _failure(message: String, status := "invalid") -> Dictionary:
	return {ok = false, status = status, format = FORMAT, reason = message}
