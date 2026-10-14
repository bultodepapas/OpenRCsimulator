## Float64 heightfield for the RC dirt circuit. Shared by contact sampling and rendering.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const PATH := "res://data/ground_vehicle/airfield_track.json"
const FORMAT := "openrc-airfield-track v1"

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
	var distance := M.sqrt_(n * n + excess_e * excess_e)
	var radial_n := n / distance if distance > 1e-12 else 0.0
	var radial_e := excess_e / distance if distance > 1e-12 else 0.0
	var lateral := distance - radius
	var strip := _band(lateral, half, shoulder)
	var coverage := strip[0]
	var cn := strip[1] * radial_n
	var ce := strip[1] * radial_e
	var feature := "dirt_loop" if coverage > 0.0 else ""
	var technical_n := _band(n, float(track.technical_width_m) * 0.5, shoulder)
	var technical_e := _band(e, length + radius, shoulder)
	var technical := technical_n[0] * technical_e[0]
	if technical > coverage:
		coverage = technical
		cn = technical_n[1] * technical_e[0]
		ce = technical_n[0] * technical_e[1]
		feature = "wall_slalom"
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
			var along := _ramp(east - float(ramp.east_m), float(ramp.approach_m), float(ramp.deck_m), float(ramp.descent_m))
			if along[0] == 0.0: continue
			var cross := _band(north - float(ramp.north_m), float(ramp.width_m) * 0.5, shoulder)
			var h := float(ramp.height_m)
			height += h * along[0] * cross[0]
			dn += h * along[0] * cross[1]
			de += h * along[1] * cross[0]
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
