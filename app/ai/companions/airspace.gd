## AFC-02: continuous static clearance of the nominal circuit corridor at launch.
## This is a geometry check, not an invariant of the pilot or a dynamic avoidance proof.
extends RefCounted

const Contacts := preload("res://physics/aircraft_contact_contract.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const Lake := preload("res://physics/lake_surface.gd")
const LakeLoader := preload("res://data/lake_loader.gd")

const POLICY := "openrc-ai-static-circuit v1"
# Engineering allowances, not measured tracking bounds. The 120 s calm/gentle
# matrix observed <=4.05 m radial error and <0.7 m vertical error. Avoidance may
# leave this corridor; widening it is not a substitute for trajectory validation.
const RADIAL_ALLOWANCE_M := 10.0
const VERTICAL_ALLOWANCE_M := 2.0
const OBSTACLE_CLEARANCE_M := 2.0
# Conservative AFC policy around people/pit proxies, not a surveyed field rule.
const EXCLUSION_MARGIN_M := 30.0
const MAX_PROXIES := 10000
const MAX_COORDINATE_M := 1000000.0
const BOUNDS_EPSILON_M := 1.0e-8
const BOUND_KEYS := ["bounds_north_min", "bounds_north_max", "bounds_east_min",
	"bounds_east_max", "bounds_down_min", "bounds_down_max"]
const GEOMETRY_KEYS := ["north", "east", "down", "radius", "half_length", "half_x",
	"half_down", "half_z", "sin_heading", "cos_heading"]


## Inputs are detached normalized session data. Empty world explicitly means
## scenery collision is disabled. Never infer a clear world from malformed data.
static func validate(field_profile: Dictionary, field: Dictionary, world: Dictionary,
		surfaces: PackedFloat64Array, lake: Dictionary, model: Dictionary, count: int) -> Dictionary:
	var route: Variant = field_profile.get("circuit")
	var pilot: Variant = field.get("pilot")
	if count < 1 or count > 3 or typeof(route) != TYPE_DICTIONARY or typeof(pilot) != TYPE_DICTIONARY:
		return _failure("Invalid circuit, pilot station or companion count.")
	for key: String in ["center_north", "center_east", "radius", "base_agl", "slot_agl_step"]:
		if typeof(route.get(key)) != TYPE_DICTIONARY or not _number(route[key].get("value")):
			return _failure("Circuit quantity '%s' is invalid." % key)
	for key: String in ["north", "east", "down"]:
		if not _number(pilot.get(key)):
			return _failure("Pilot station coordinates are invalid.")
	var north := float(route.center_north.value)
	var east := float(route.center_east.value)
	var radius := float(route.radius.value)
	var base := float(route.base_agl.value) - float(pilot.down)
	var step := float(route.slot_agl_step.value)
	if route.get("shape") != "circle" or radius <= 0.0 or step <= 0.0:
		return _failure("Only positive circular circuit geometry is supported.")
	var description: Dictionary = Contacts.describe(model, false)
	if not description.ok:
		return _failure("Aircraft contact geometry is invalid: " + "; ".join(description.errors))
	var aircraft_radius := 0.0
	# Encloses the accepted contact geometry at every orientation. This does not
	# certify that the crash probes describe every vertex of the rendered mesh.
	for point: Dictionary in description.hull_probes + description.support_points:
		aircraft_radius = maxf(aircraft_radius, _length(point.position))
	var disc: Dictionary = description.rotor_disc
	if not disc.is_empty():
		aircraft_radius = maxf(aircraft_radius, _length(disc.hub) + float(disc.radius))
	if not is_finite(aircraft_radius) or aircraft_radius <= 0.0 or aircraft_radius > 100.0:
		return _failure("Aircraft clearance radius is invalid.")
	var ground_upper := Terrain.max_height(surfaces)
	if not is_finite(ground_upper):
		return _failure("Terrain surface table is invalid.")
	if not lake.is_empty():
		if not Lake.is_valid_definition(lake) or LakeLoader.identity(lake) != lake.get("identity", ""):
			return _failure("Lake geometry or identity is invalid.")
		# Validated lake bank/bed only lowers microrelief. Water can rise above it;
		# its authored amplitude bound encloses all permitted wave phases.
		ground_upper = maxf(ground_upper, -float(lake.water_level_down_m) + float(lake.wave_bounds.max_amplitude_m))
	var inventory: Dictionary = _inventory(world)
	if not inventory.ok:
		return inventory
	var horizontal := RADIAL_ALLOWANCE_M + aircraft_radius + OBSTACLE_CLEARANCE_M
	var vertical := VERTICAL_ALLOWANCE_M + aircraft_radius + OBSTACLE_CLEARANCE_M
	var inner := maxf(0.0, radius - horizontal)
	var outer := radius + horizontal
	var corridors: Array[Dictionary] = []
	for slot: int in count:
		corridors.append({slot = slot, center_height_m = base + step * slot,
			min_height_m = base + step * slot - vertical, max_height_m = base + step * slot + vertical})
	var report := {policy = POLICY, scope = "nominal_circuit_corridor", count = count,
		center_north_m = north, center_east_m = east, radius_m = radius,
		inner_radius_m = inner, outer_radius_m = outer, corridors = corridors,
		aircraft_radius_m = aircraft_radius, radial_allowance_m = RADIAL_ALLOWANCE_M,
		vertical_allowance_m = VERTICAL_ALLOWANCE_M, obstacle_clearance_m = OBSTACLE_CLEARANCE_M,
		exclusion_margin_m = EXCLUSION_MARGIN_M, ground_upper_m = ground_upper,
		collision_enabled = not inventory.geometry.is_empty(), collision_world_identity = str(world.get("identity", "")),
		geometry_sha256 = _hash(inventory.geometry), proxy_count = inventory.geometry.size(),
		surfaces_sha256 = _hash(surfaces), lake_identity = str(lake.get("identity", "")),
		protected_proxy_count = 0}
	var pilot_distance := sqrt(pow(north - float(pilot.north), 2.0) + pow(east - float(pilot.east), 2.0))
	if absf(pilot_distance - radius) <= RADIAL_ALLOWANCE_M + aircraft_radius + EXCLUSION_MARGIN_M:
		return _failure("Circuit overlaps the pilot station exclusion.", report)
	for corridor: Dictionary in corridors:
		if float(corridor.min_height_m) <= ground_upper:
			return _failure("Circuit slot %d has insufficient terrain/water clearance." % int(corridor.slot), report)
	var minimum_gap := INF
	for proxy: Dictionary in inventory.geometry:
		var bounds: PackedFloat64Array = proxy.bounds
		if proxy.kind == "person" or (proxy.kind == "building" and
				(str(proxy.part).begins_with("shelter_") or str(proxy.part).begins_with("pavilion_"))):
			report.protected_proxy_count += 1
			var exclusion := bounds.duplicate()
			for index: int in [0, 2]:
				exclusion[index] -= EXCLUSION_MARGIN_M
				exclusion[index + 1] += EXCLUSION_MARGIN_M
			if _annulus_overlaps(exclusion, north, east,
					maxf(0.0, radius - RADIAL_ALLOWANCE_M - aircraft_radius), radius + RADIAL_ALLOWANCE_M + aircraft_radius):
				return _failure("Circuit overflies a protected person/shelter footprint: " + str(proxy.id), report)
		if not _annulus_overlaps(bounds, north, east, inner, outer):
			continue
		var bottom := -bounds[5]
		var top := -bounds[4]
		for corridor: Dictionary in corridors:
			var gap := maxf(float(corridor.min_height_m) - top, bottom - float(corridor.max_height_m))
			minimum_gap = minf(minimum_gap, gap)
			if gap <= 0.0:
				return _failure("Circuit slot %d is obstructed by %s." % [int(corridor.slot), str(proxy.id)], report)
	if is_finite(minimum_gap):
		report.minimum_vertical_gap_after_allowances_m = minimum_gap
	report.identity = _hash([POLICY, report])
	return {ok = true, errors = PackedStringArray(), report = report}


## Continuous radial interval of a rectangle: nearest point and farthest corner.
## The rectangle is connected, so it intersects an annulus iff intervals overlap.
static func _annulus_overlaps(bounds: PackedFloat64Array, north: float, east: float,
		inner: float, outer: float) -> bool:
	var near_n := maxf(bounds[0] - north, maxf(0.0, north - bounds[1]))
	var near_e := maxf(bounds[2] - east, maxf(0.0, east - bounds[3]))
	var far_n := maxf(absf(bounds[0] - north), absf(bounds[1] - north))
	var far_e := maxf(absf(bounds[2] - east), absf(bounds[3] - east))
	return near_n * near_n + near_e * near_e <= outer * outer \
		and far_n * far_n + far_e * far_e >= inner * inner


static func _inventory(world: Dictionary) -> Dictionary:
	var geometry: Array[Dictionary] = []
	if world.is_empty():
		return {ok = true, geometry = geometry}
	if world.get("format") != "openrc-collision-world v1" or typeof(world.get("identity")) != TYPE_STRING \
			or str(world.identity).is_empty() or typeof(world.get("proxies")) != TYPE_ARRAY \
			or typeof(world.get("bins")) != TYPE_DICTIONARY or not _number(world.get("cell_size_m")) \
			or float(world.cell_size_m) != 32.0 or world.proxies.size() > MAX_PROXIES:
		return _failure("Collision inventory is invalid or exceeds the launch budget.")
	var ids := {}
	for value: Variant in world.proxies:
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("Collision inventory contains a malformed proxy.")
		var proxy: Dictionary = value
		for key: String in ["id", "kind", "part", "shape", "response_class"]:
			if typeof(proxy.get(key)) != TYPE_STRING or str(proxy[key]).is_empty():
				return _failure("Collision proxy lacks a valid " + key + ".")
		if ids.has(proxy.id):
			return _failure("Duplicate collision proxy: " + str(proxy.id))
		ids[proxy.id] = true
		for key: String in GEOMETRY_KEYS + BOUND_KEYS:
			if not _number(proxy.get(key)):
				return _failure("Invalid collision geometry: " + str(proxy.id))
		var extent_n := 0.0
		var extent_e := 0.0
		var extent_d := 0.0
		if proxy.shape == "box":
			if float(proxy.half_x) <= 0.0 or float(proxy.half_z) <= 0.0 or float(proxy.half_down) <= 0.0 \
					or absf(float(proxy.sin_heading) * float(proxy.sin_heading) + float(proxy.cos_heading) * float(proxy.cos_heading) - 1.0) > 1.0e-10:
				return _failure("Invalid box dimensions/heading: " + str(proxy.id))
			extent_n = absf(float(proxy.sin_heading)) * float(proxy.half_x) + absf(float(proxy.cos_heading)) * float(proxy.half_z)
			extent_e = absf(float(proxy.cos_heading)) * float(proxy.half_x) + absf(float(proxy.sin_heading)) * float(proxy.half_z)
			extent_d = float(proxy.half_down)
		elif proxy.shape == "capsule":
			if float(proxy.radius) <= 0.0 or float(proxy.half_length) < 0.0:
				return _failure("Invalid capsule dimensions: " + str(proxy.id))
			extent_n = float(proxy.radius)
			extent_e = float(proxy.radius)
			extent_d = float(proxy.radius) + float(proxy.half_length)
		else:
			return _failure("Unsupported collision shape: " + str(proxy.id))
		var computed := PackedFloat64Array([float(proxy.north) - extent_n, float(proxy.north) + extent_n,
			float(proxy.east) - extent_e, float(proxy.east) + extent_e, float(proxy.down) - extent_d, float(proxy.down) + extent_d])
		var bounds := PackedFloat64Array()
		for key: String in BOUND_KEYS:
			bounds.append(float(proxy[key]))
		for axis: int in [0, 2, 4]:
			if bounds[axis] >= bounds[axis + 1] or bounds[axis] > computed[axis] + BOUNDS_EPSILON_M \
					or bounds[axis + 1] < computed[axis + 1] - BOUNDS_EPSILON_M:
				return _failure("Collision bounds do not enclose their shape: " + str(proxy.id))
			# Include both bounds, even within roundoff tolerance; never shrink geometry.
			bounds[axis] = minf(bounds[axis], computed[axis])
			bounds[axis + 1] = maxf(bounds[axis + 1], computed[axis + 1])
		geometry.append({id = proxy.id, kind = proxy.kind, part = proxy.part, bounds = bounds})
	geometry.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	return {ok = true, geometry = geometry}


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and absf(float(value)) <= MAX_COORDINATE_M


static func _length(point: PackedFloat64Array) -> float:
	return sqrt(point[0] * point[0] + point[1] * point[1] + point[2] * point[2])


static func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()


static func _failure(message: String, report: Dictionary = {}) -> Dictionary:
	return {ok = false, errors = PackedStringArray(["Companion airspace: " + message]), report = report}
