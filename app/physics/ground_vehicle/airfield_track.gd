## Float64 heightfield for the RC dirt circuit. Shared by contact sampling and rendering.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const PATH := "res://data/ground_vehicle/airfield_track.json"
const FORMAT := "openrc-airfield-track v1"
## The course's dry-pavement reference (airfield_course.gd DRY_PAVEMENT_MU); track.mu is absolute over it.
const DRY_PAVEMENT_MU := 0.85

static func load_default() -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(PATH)
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not valid(parsed):
		return {"ok": false, "errors": PackedStringArray(["Invalid airfield obstacle track definition"])}
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return {"ok": true, "track": parsed, "sha256": hash.finish().hex_encode()}

static func valid(track: Dictionary) -> bool:
	if track.get("format") != FORMAT or str(track.get("id", "")).is_empty(): return false
	for key in ["center_north_m", "center_east_m", "half_straight_m", "radius_m", "lane_width_m", "shoulder_m", "pad_height_m", "bank_height_m", "mu", "rolling", "technical_width_m"]:
		if not _number(track.get(key)): return false
	for key in ["half_straight_m", "radius_m", "lane_width_m", "shoulder_m", "technical_width_m"]:
		if float(track[key]) <= 0.0 or float(track[key]) > 100.0: return false
	if float(track.pad_height_m) < 0.0 or float(track.pad_height_m) > 0.2 or float(track.bank_height_m) < 0.0 or float(track.bank_height_m) > 2.0: return false
	if float(track.mu) <= 0.0 or float(track.mu) > 2.0 or float(track.rolling) < 0.0 or float(track.rolling) > 20.0: return false
	if typeof(track.get("access")) != TYPE_DICTIONARY: return false
	for key in ["north_min_m", "north_max_m", "east_m", "width_m"]:
		if not _number(track.access.get(key)): return false
	if float(track.access.north_min_m) >= float(track.access.north_max_m) or float(track.access.width_m) <= 0.0: return false
	var ids := {}
	for group in ["ramps", "rollers", "walls", "spawns"]:
		if typeof(track.get(group)) != TYPE_ARRAY or track[group].size() > 16: return false
		for item in track[group]:
			if typeof(item) != TYPE_DICTIONARY or not item.get("id") is String or str(item.id).is_empty() or ids.has(item.id): return false
			ids[item.id] = true
			var keys: Array = ["north_m", "east_m", "height_m", "approach_m", "deck_m", "descent_m", "width_m"]
			if group == "walls": keys = ["north_min_m", "north_max_m", "east_min_m", "east_max_m", "bottom_up_m", "top_up_m", "mu"]
			if group == "spawns": keys = ["north_m", "east_m", "heading_rad", "vehicle_up_m"]
			for key in keys:
				if not _number(item.get(key)): return false
			if group in ["ramps", "rollers"]:
				if float(item.height_m) < 0.0 or float(item.height_m) > 2.0 or float(item.approach_m) <= 0.0 or float(item.descent_m) <= 0.0 or float(item.deck_m) < 0.0 or float(item.width_m) <= 0.0: return false
			elif group == "walls":
				if float(item.north_min_m) >= float(item.north_max_m) or float(item.east_min_m) >= float(item.east_max_m) or float(item.bottom_up_m) >= float(item.top_up_m) or float(item.mu) < 0.0 or float(item.mu) > 2.0: return false
	return not track.spawns.is_empty() and track.walls.size() <= 8

## Only the authored default field geometry receives this course; custom fields remain untouched.
static func matches_field(field: Dictionary) -> bool:
	if str(field.get("id", "")) != "default": return false
	for surface: Dictionary in field.get("surfaces", []):
		if str(surface.get("id", "")) == str(field.get("runway", "")):
			return float(surface.center_north) == 15.0 and float(surface.center_east) == 0.0 and float(surface.length_east_west) == 100.0 and float(surface.width_north_south) == 12.0
	return false

## RC-TRACK: the circuit's solid dressing as scalar NED boxes for the aircraft collision world.
## Placements repeat vehicles/ground/track_furniture.gd, track_service_detail.gd and the view's tyre stacks;
## test_rc_track_flight.gd checks every rendered node against this list. Sizes are the measured source
## bounds times the render scale (billboardLow 1.0 x 0.69 x 0.476 m at 1.35; utility_box_01 0.52 x 1.12 x
## 0.432 m at 0.6; barrier tape 3.35 x 1.0 x 0.35 m; old tyre 0.6 m across, 0.165 m per layer).
## Each record: {id, part, north, east, up (box base above the datum), width (local x), height, length
## (local z), heading_deg (collision_world.gd box heading), response, damage_profile}.
const TYRE_STACKS := [
	{"east": -17.0, "north": 34.5, "count": 3, "yaw": 0.25},
	{"east": 3.4, "north": 34.9, "count": 2, "yaw": -0.32},
	{"east": -21.8, "north": 45.0, "count": 3, "yaw": 0.68},
]
const TYRE_DIAMETER_M := 0.6
const TYRE_LAYER_M := 0.165


static func dressing(track: Dictionary) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if track.is_empty():
		return items
	for wall: Dictionary in track.walls:
		items.append(_dressing_box("wall:" + str(wall.id), "barrier",
			(float(wall.north_min_m) + float(wall.north_max_m)) * 0.5, (float(wall.east_min_m) + float(wall.east_max_m)) * 0.5,
			float(wall.bottom_up_m), float(wall.east_max_m) - float(wall.east_min_m), float(wall.top_up_m) - float(wall.bottom_up_m),
			float(wall.north_max_m) - float(wall.north_min_m), 0.0, "hard_terminal", "masonry"))
	for index: int in TYRE_STACKS.size():
		var stack: Dictionary = TYRE_STACKS[index]
		items.append(_dressing_box("tyres:%02d" % index, "tyre_stack", float(stack.north), float(stack.east), 0.0,
			TYRE_DIAMETER_M, TYRE_LAYER_M * float(stack.count), TYRE_DIAMETER_M, 0.0, "frangible_impulse", "none"))
	var access: Dictionary = track.access
	var signs := [
		["access", float(access.east_m) - float(access.width_m) * 0.5 - float(track.shoulder_m) - 1.0, float(access.north_min_m) + 0.6, 0.0],
		["jumps", 1.0, 35.25, -PI * 0.5],
		["slalom", 21.9, 45.0, -PI * 0.5],
		["rollers", 0.0, 55.1, PI * 0.5],
	]
	for sign: Array in signs:
		# A render yaw about +Y turns the board's local x toward NED (sin yaw, cos yaw): box heading -yaw.
		items.append(_dressing_box("sign:" + str(sign[0]), "sign", float(sign[2]), float(sign[1]), 0.0,
			1.35, 0.93, 0.64, rad_to_deg(-float(sign[3])), "hard_terminal", "metal"))
	var ce := float(track.center_east_m)
	var cn := float(track.center_north_m)
	var radius := float(track.radius_m)
	var clear_half := float(track.lane_width_m) * 0.5 + float(track.shoulder_m)
	var gate_east := ce - float(track.half_straight_m) + 5.9
	for side: float in [-1.0, 1.0]:
		items.append(_dressing_box("timing_post:%s" % ("south" if side < 0.0 else "north"), "timing_post",
			cn - radius + side * (float(track.lane_width_m) * 0.5 + 0.72), gate_east, 0.0,
			0.16, 0.61, 0.16, 0.0, "hard_terminal", "metal"))
	items.append(_dressing_box("tape:south", "tape", cn - radius - clear_half - 2.3, ce + 12.0, 0.0,
		3.35, 1.0, 0.35, 0.0, "frangible_impulse", "none"))
	items.append(_dressing_box("tape:north", "tape", cn + radius + clear_half + 2.5, ce - 8.0, 0.0,
		3.35, 1.0, 0.35, 0.0, "frangible_impulse", "none"))
	items.append(_dressing_box("cabinet", "cabinet", cn - radius - clear_half - 1.5, ce - float(track.half_straight_m) + 10.0, 0.0,
		0.312, 0.672, 0.259, 0.0, "hard_terminal", "metal"))
	return items


static func _dressing_box(id: String, part: String, north: float, east: float, up: float, width: float,
		height: float, length: float, heading_deg: float, response: String, damage_profile: String) -> Dictionary:
	return {id = "rc_track:" + id, part = part, north = north, east = east, up = up, width = width, height = height,
		length = length, heading_deg = heading_deg, response = response, damage_profile = damage_profile}


## Conservative [north_min, north_max, east_min, east_max] (m) outside which sample() is exactly zero.
static func bounds_ne(track: Dictionary) -> PackedFloat64Array:
	var shoulder := float(track.shoulder_m)
	var half := float(track.lane_width_m) * 0.5
	var reach := float(track.half_straight_m) + float(track.radius_m) + half + shoulder
	var technical := float(track.technical_width_m) * 0.5 + shoulder
	var north_max := maxf(float(track.center_north_m) + float(track.radius_m) + half + shoulder,
		float(track.center_north_m) + technical)
	north_max = maxf(north_max, float(track.access.north_max_m) + shoulder)
	return PackedFloat64Array([float(track.access.north_min_m) - shoulder, north_max,
		float(track.center_east_m) - reach, float(track.center_east_m) + reach])


## Upper bound of the additive elevation (m): the pad, the bank and every ramp and roller stacked.
## Contact broadphases add it to the field's own bound, so it must never be below the true maximum.
static func max_height_m(track: Dictionary) -> float:
	if track.is_empty():
		return 0.0
	var bound := float(track.pad_height_m) + float(track.bank_height_m)
	for group in ["ramps", "rollers"]:
		for ramp: Dictionary in track[group]:
			bound += float(ramp.height_m)
	return bound


## A validated field terrain sample [height_up, dh/dn, dh/de] with the circuit added, as a new
## [height_up, dh/dn, dh/de, dirt coverage]. Same arithmetic as AirfieldCourse.sample, so the
## ground-vehicle course, the aircraft wheels and the rendered dirt agree exactly.
static func composed(terrain: PackedFloat64Array, track: Dictionary, north: float, east: float) -> PackedFloat64Array:
	var overlay := sample(track, north, east)
	return PackedFloat64Array([terrain[0] + float(overlay.height_m), terrain[1] + float(overlay.dn),
		terrain[2] + float(overlay.de), float(overlay.coverage)])


## Tyre friction and rolling factors on the dirt, in the field surface table's units (ground_surfaces.gd).
## The course uses mu absolutely over dry pavement; the aircraft table scales its gear's own coefficients.
static func surface_factors(track: Dictionary) -> PackedFloat64Array:
	return PackedFloat64Array([float(track.mu) / DRY_PAVEMENT_MU, float(track.rolling)])


## Session identity of an installed circuit: its id and the SHA-256 of its normalized definition.
static func identity(track: Dictionary) -> String:
	if track.is_empty():
		return ""
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(track))
	return "%s:%s" % [str(track.id), hash.finish().hex_encode()]


## Returns additive elevation and its exact partial derivatives, plus the dirt coverage mask.
static func sample(track: Dictionary, north: float, east: float) -> Dictionary:
	if track.is_empty():
		return {"height_m": 0.0, "dn": 0.0, "de": 0.0, "coverage": 0.0, "feature_id": ""}
	var n := north - float(track.center_north_m)
	var e := east - float(track.center_east_m)
	var length := float(track.half_straight_m)
	var radius := float(track.radius_m)
	var half := float(track.lane_width_m) * 0.5
	var shoulder := float(track.shoulder_m)
	if absf(e) > length + radius + half + shoulder or north < float(track.access.north_min_m) - shoulder or absf(n) > radius + half + shoulder and north > float(track.center_north_m):
		return {"height_m": 0.0, "dn": 0.0, "de": 0.0, "coverage": 0.0, "feature_id": ""}
	var excess_e := e - clampf(e, -length, length)
	var distance := sqrt(n * n + excess_e * excess_e)
	var radial_n := n / distance if distance > 1e-12 else 0.0
	var radial_e := excess_e / distance if distance > 1e-12 else 0.0
	var lateral := distance - radius
	var strip := _band(lateral, half, shoulder)
	var coverage := strip[0]
	var cn := strip[1] * radial_n
	var ce := strip[1] * radial_e
	var feature := "dirt_loop" if coverage > 0.0 else ""
	# Coverage masks are bounded by one and only a strict increase wins.
	# Preserve tie precedence and slopes without evaluating losing masks.
	if coverage < 1.0:
		var technical_n := _band(n, float(track.technical_width_m) * 0.5, shoulder)
		var technical_e := _band(e, length + radius, shoulder)
		var technical := technical_n[0] * technical_e[0]
		if technical > coverage:
			coverage = technical
			cn = technical_n[1] * technical_e[0]
			ce = technical_n[0] * technical_e[1]
			feature = "wall_slalom"
	if coverage < 1.0:
		var access: Dictionary = track.access
		var access_n := _band(north - (float(access.north_min_m) + float(access.north_max_m)) * 0.5, (float(access.north_max_m) - float(access.north_min_m)) * 0.5, shoulder)
		var access_e := _band(east - float(access.east_m), float(access.width_m) * 0.5, shoulder)
		var access_mask := access_n[0] * access_e[0]
		if access_mask > coverage:
			coverage = access_mask
			cn = access_n[1] * access_e[0]
			ce = access_n[0] * access_e[1]
			feature = "access"
	var height := float(track.pad_height_m) * coverage
	var dn := float(track.pad_height_m) * cn
	var de := float(track.pad_height_m) * ce
	var turn_t := (absf(e) - (length - 2.0)) / 3.5
	var turn_value := 0.0
	var turn_slope := 0.0
	if turn_t <= 0.0:
		turn_value = 0.0
		turn_slope = 0.0
	elif turn_t >= 1.0:
		turn_value = 1.0
		turn_slope = 0.0
	else:
		turn_value = turn_t * turn_t * (3.0 - 2.0 * turn_t)
		turn_slope = 6.0 * turn_t * (1.0 - turn_t)
	var turn_e := turn_slope * signf(e) / 3.5
	var across := clampf((lateral + half) / (2.0 * half), 0.0, 1.0)
	var across_d := 1.0 / (2.0 * half) if lateral > -half and lateral < half else 0.0
	var bank_slope := 0.0
	var bank_shape_value := 0.0
	if across <= 0.0:
		bank_shape_value = 0.0
		bank_slope = 0.0
	elif across >= 1.0:
		bank_shape_value = 1.0
		bank_slope = 0.0
	else:
		bank_shape_value = across * across * (3.0 - 2.0 * across)
		bank_slope = 6.0 * across * (1.0 - across)
	var bank := float(track.bank_height_m) * bank_shape_value
	var bank_d := float(track.bank_height_m) * bank_slope * across_d
	height += bank * turn_value * strip[0]
	dn += turn_value * (bank_d * strip[0] + bank * strip[1]) * radial_n
	de += turn_value * (bank_d * strip[0] + bank * strip[1]) * radial_e + bank * turn_e * strip[0]
	if turn_value * strip[0] > 0.05: feature = "banked_turn"
	for group in ["ramps", "rollers"]:
		for ramp: Dictionary in track[group]:
			# Same _ramp arithmetic, without a temporary packed array for every
			# distant obstacle. Keep the exact zero test before cross-band work.
			var offset := east - float(ramp.east_m)
			var deck := float(ramp.deck_m)
			var along_value := 0.0
			var along_slope := 0.0
			if offset < -deck * 0.5:
				var approach := float(ramp.approach_m)
				var t := (offset + deck * 0.5 + approach) / approach
				if t <= 0.0: continue
				if t >= 1.0:
					along_value = 1.0
				else:
					along_value = t * t * (3.0 - 2.0 * t)
					along_slope = 6.0 * t * (1.0 - t) / approach
			else:
				var descent := float(ramp.descent_m)
				var t := (offset - deck * 0.5) / descent
				var down_slope := 0.0
				if t >= 1.0: continue
				if t <= 0.0:
					along_value = 1.0
				else:
					along_value = 1.0 - t * t * (3.0 - 2.0 * t)
					down_slope = 6.0 * t * (1.0 - t)
				# Negate the runtime value to preserve the original signed zero.
				along_slope = -down_slope / descent
			if along_value == 0.0: continue
			var cross := _band(north - float(ramp.north_m), float(ramp.width_m) * 0.5, shoulder)
			var h := float(ramp.height_m)
			height += h * along_value * cross[0]
			dn += h * along_value * cross[1]
			de += h * along_slope * cross[0]
			if cross[0] > 0.0: feature = str(ramp.id)
	return {"height_m": height, "dn": dn, "de": de, "coverage": coverage, "feature_id": feature}

static func nearby_walls(track: Dictionary, north: float, east: float) -> Array:
	var result: Array = []
	# Largest hub/hull distance is <0.6 m; 1.0 m also covers RK stage motion at the supported speeds.
	for wall: Dictionary in track.get("walls", []):
		if north >= float(wall.north_min_m) - 1.0 and north <= float(wall.north_max_m) + 1.0 and east >= float(wall.east_min_m) - 1.0 and east <= float(wall.east_max_m) + 1.0:
			result.append(wall)
	return result

static func _band(offset: float, half: float, shoulder: float) -> PackedFloat64Array:
	var edge_t := (absf(offset) - half) / shoulder
	var edge_value := 0.0
	var edge_slope := 0.0
	if edge_t <= 0.0:
		edge_value = 0.0
		edge_slope = 0.0
	elif edge_t >= 1.0:
		edge_value = 1.0
		edge_slope = 0.0
	else:
		edge_value = edge_t * edge_t * (3.0 - 2.0 * edge_t)
		edge_slope = 6.0 * edge_t * (1.0 - edge_t)
	return PackedFloat64Array([1.0 - edge_value, -edge_slope * signf(offset) / shoulder])

static func _ramp(offset: float, approach: float, deck: float, descent: float) -> PackedFloat64Array:
	if offset < -deck * 0.5:
		var up_t := (offset + deck * 0.5 + approach) / approach
		var up_value := 0.0
		var up_slope := 0.0
		if up_t <= 0.0:
			up_value = 0.0
			up_slope = 0.0
		elif up_t >= 1.0:
			up_value = 1.0
			up_slope = 0.0
		else:
			up_value = up_t * up_t * (3.0 - 2.0 * up_t)
			up_slope = 6.0 * up_t * (1.0 - up_t)
		return PackedFloat64Array([up_value, up_slope / approach])
	var down_t := (offset - deck * 0.5) / descent
	var down_value := 0.0
	var down_slope := 0.0
	if down_t <= 0.0:
		down_value = 0.0
		down_slope = 0.0
	elif down_t >= 1.0:
		down_value = 1.0
		down_slope = 0.0
	else:
		down_value = down_t * down_t * (3.0 - 2.0 * down_t)
		down_slope = 6.0 * down_t * (1.0 - down_t)
	return PackedFloat64Array([1.0 - down_value, -down_slope / descent])

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
