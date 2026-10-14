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
	var empty := {"height_m": 0.0, "dn": 0.0, "de": 0.0, "coverage": 0.0, "feature_id": ""}
	if track.is_empty(): return empty
	var n := north - float(track.center_north_m)
	var e := east - float(track.center_east_m)
	var length := float(track.half_straight_m)
	var radius := float(track.radius_m)
	var half := float(track.lane_width_m) * 0.5
	var shoulder := float(track.shoulder_m)
	if absf(e) > length + radius + half + shoulder or north < float(track.access.north_min_m) - shoulder or absf(n) > radius + half + shoulder and north > float(track.center_north_m): return empty
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
	var turn := _smooth((absf(e) - (length - 2.0)) / 3.5)
	var turn_e := turn[1] * signf(e) / 3.5
	var across := clampf((lateral + half) / (2.0 * half), 0.0, 1.0)
	var across_d := 1.0 / (2.0 * half) if lateral > -half and lateral < half else 0.0
	var bank_shape := _smooth(across)
	var bank := float(track.bank_height_m) * bank_shape[0]
	var bank_d := float(track.bank_height_m) * bank_shape[1] * across_d
	height += bank * turn[0] * strip[0]
	dn += turn[0] * (bank_d * strip[0] + bank * strip[1]) * radial_n
	de += turn[0] * (bank_d * strip[0] + bank * strip[1]) * radial_e + bank * turn_e * strip[0]
	if turn[0] * strip[0] > 0.05: feature = "banked_turn"
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

static func _smooth(t: float) -> PackedFloat64Array:
	if t <= 0.0: return PackedFloat64Array([0.0, 0.0])
	if t >= 1.0: return PackedFloat64Array([1.0, 0.0])
	return PackedFloat64Array([t * t * (3.0 - 2.0 * t), 6.0 * t * (1.0 - t)])

static func _band(offset: float, half: float, shoulder: float) -> PackedFloat64Array:
	var edge := _smooth((absf(offset) - half) / shoulder)
	return PackedFloat64Array([1.0 - edge[0], -edge[1] * signf(offset) / shoulder])

static func _ramp(offset: float, approach: float, deck: float, descent: float) -> PackedFloat64Array:
	if offset < -deck * 0.5:
		var up := _smooth((offset + deck * 0.5 + approach) / approach)
		return PackedFloat64Array([up[0], up[1] / approach])
	var down := _smooth((offset - deck * 0.5) / descent)
	return PackedFloat64Array([1.0 - down[0], -down[1] / descent])

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
