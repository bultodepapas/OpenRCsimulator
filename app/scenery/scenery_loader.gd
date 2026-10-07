## SCENERY-PLAN SC-02: loads and validates `openrc-scenery v1` against an already validated field (field_loader.gd).
## Same contract as the field loader: {ok, errors, scenery}; invalid data is refused, never half-built. Every quantity is
## {value, unit, kind, source}. Rules: the distance profile (report 03), the flight-box height limit, the runway and its
## approach corridors (1:20, borrowed from ICAO Annex 14 code 1 as an analogy), clearance from the L6b trees, and
## `collides` must be false (L14 owns collisions).
extends RefCounted

const Prefabs = preload("res://scenery/prefabs.gd")
const Models = preload("res://scenery/models.gd")

const FORMAT := "openrc-scenery v1"
const DEFAULT_PATH := "res://data/scenery/default.json"
const KINDS: Array[String] = ["manual", "measured", "borrowed", "estimated", "derived"]
const GROUP_TYPES: Array[String] = ["instances", "hedge", "fence", "track", "patch", "flowers", "fleet"]
const ZONES: Array[String] = ["club", "pits", "spectators", "parking", "flight_box", "countryside", "horizon", "pilot_line"]
const PROFILE_KEYS: Array[String] = ["pits_min_behind_m", "spectators_min_behind_m", "parking_min_behind_m",
	"pits_min_from_centreline_m", "flight_box_depth_m", "flight_box_half_width_m", "flight_box_max_height_m",
	"approach_slope", "tree_clearance_m", "runway_margin_m"]
const FENCE_STYLES: Array[String] = ["wire", "rail"]
const SURFACES: Array[String] = ["gravel", "dirt", "worn"]
const MAX_POINTS := 4096


static func load_from(path: String, field: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {ok = false, errors = PackedStringArray(["%s: file not found" % path]), scenery = {}}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return {ok = false, errors = PackedStringArray(["%s: JSON line %d: %s" % [path, json.get_error_line(), json.get_error_message()]]), scenery = {}}
	return validate(json.data, field)


static func validate(raw: Variant, field: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("root: expected an object")
		return {ok = false, errors = errors, scenery = {}}
	var root: Dictionary = raw
	if root.get("format") != FORMAT:
		errors.append("format: expected '%s'" % FORMAT)
	if str(root.get("field", "")) != str(field.get("id", "")):
		errors.append("field: expected '%s' (the loaded field's id)" % field.get("id", ""))
	var theme := str(root.get("theme", "temperate"))
	if not ["temperate", "summer", "autumn"].has(theme):
		errors.append("theme: expected temperate, summer or autumn")
	var profile := {}
	var prof_node: Variant = root.get("profile")
	if typeof(prof_node) != TYPE_DICTIONARY:
		errors.append("profile: expected an object")
	else:
		var pd: Dictionary = prof_node
		profile.name = str(pd.get("name", ""))
		if profile.name.is_empty():
			errors.append("profile.name: required")
		for key: String in PROFILE_KEYS:
			profile[key] = _quantity(errors, "profile." + key, pd.get(key), "1" if key == "approach_slope" else "m")
	var geometry := _field_geometry(field)
	var trees := _tree_points(field)
	var groups: Array = []
	var ids := {}
	var groups_node: Variant = root.get("groups")
	if typeof(groups_node) != TYPE_ARRAY or (groups_node as Array).is_empty():
		errors.append("groups: expected a non-empty array")
	elif errors.is_empty():
		var gi := 0
		for g: Variant in groups_node:
			var path := "groups[%d]" % gi
			gi += 1
			if typeof(g) != TYPE_DICTIONARY:
				errors.append(path + ": expected an object")
				continue
			var gd: Dictionary = g
			var id := str(gd.get("id", ""))
			if id.is_empty() or ids.has(id):
				errors.append(path + ".id: missing or duplicate")
				continue
			ids[id] = true
			if gd.get("collides", false) != false:
				errors.append(path + ".collides: scenery is visual only until L14 (must be false)")
			var gtype := str(gd.get("type", ""))
			if not GROUP_TYPES.has(gtype):
				errors.append(path + ".type: expected one of %s" % [GROUP_TYPES])
				continue
			var zone := str(gd.get("zone", ""))
			if not ZONES.has(zone):
				errors.append(path + ".zone: expected one of %s" % [ZONES])
				continue
			var group := {id = id, type = gtype, zone = zone, seed = _seed(id)}
			match gtype:
				"instances", "fleet":
					_instances(errors, path, gd, group, geometry, profile, trees)
				"hedge", "fence", "track", "patch":
					_line(errors, path, gd, group, geometry, profile)
				"flowers":
					_flowers(errors, path, gd, group, geometry)
			groups.append(group)
	var ok := errors.is_empty()
	return {ok = ok, errors = errors, scenery = {theme = theme, profile = profile, groups = groups} if ok else {}}


## A deterministic per-group seed from the id (FNV-1a, integers only).
static func _seed(id: String) -> int:
	var h := 2166136261
	for b: int in id.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


static func _quantity(errors: PackedStringArray, path: String, node: Variant, unit: String) -> float:
	if typeof(node) != TYPE_DICTIONARY:
		errors.append(path + ": expected {value, unit, kind, source}")
		return 0.0
	var q: Dictionary = node
	var v: Variant = q.get("value")
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		errors.append(path + ".value: expected a number")
		return 0.0
	var f := float(v)
	if not is_finite(f) or f < 0.0:
		errors.append(path + ".value: expected a finite, non-negative number")
	_meta(errors, path, q, unit)
	return f


static func _meta(errors: PackedStringArray, path: String, q: Dictionary, unit: String) -> void:
	if str(q.get("unit", "")) != unit:
		errors.append("%s.unit: expected '%s'" % [path, unit])
	if not KINDS.has(str(q.get("kind", ""))):
		errors.append("%s.kind: expected one of %s" % [path, KINDS])
	if str(q.get("source", "")).strip_edges().is_empty():
		errors.append(path + ".source: required")


## Field facts the rules need, in NED metres.
static func _field_geometry(field: Dictionary) -> Dictionary:
	var runway := {}
	for s: Dictionary in field.surfaces:
		if s.id == field.runway:
			runway = s
	var half_w := float(runway.width_north_south) * 0.5
	var half_l := float(runway.length_east_west) * 0.5
	return {
		safety_north = float(runway.center_north) - half_w, # AMA: the safety line is the runway's pilot-side edge
		centre_north = float(runway.center_north),
		runway_n0 = float(runway.center_north) - half_w, runway_n1 = float(runway.center_north) + half_w,
		runway_e0 = float(runway.center_east) - half_l, runway_e1 = float(runway.center_east) + half_l,
		runway_centre_east = float(runway.center_east),
		pilot_north = float(field.pilot.north), pilot_east = float(field.pilot.east),
	}


static func _tree_points(field: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for o: Dictionary in field.get("objects", []):
		if o.get("type") == "treeline":
			for p: Array in o.positions:
				pts.append(Vector2(float(p[0]), float(p[1])))
	return pts


static func _points(errors: PackedStringArray, path: String, node: Variant, width: int, unit: String) -> Array:
	if typeof(node) != TYPE_DICTIONARY:
		errors.append(path + ": expected {value, unit, kind, source}")
		return []
	var q: Dictionary = node
	_meta(errors, path, q, unit)
	var v: Variant = q.get("value")
	if typeof(v) != TYPE_ARRAY or (v as Array).is_empty() or (v as Array).size() > MAX_POINTS:
		errors.append(path + ".value: expected 1–%d rows" % MAX_POINTS)
		return []
	var rows: Array = []
	var i := 0
	for r: Variant in v:
		if typeof(r) != TYPE_ARRAY or (r as Array).size() != width:
			errors.append("%s.value[%d]: expected %d numbers" % [path, i, width])
			return []
		var row: Array = []
		for x: Variant in r:
			if (typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT) or not is_finite(float(x)):
				errors.append("%s.value[%d]: non-finite or non-numeric" % [path, i])
				return []
			row.append(float(x))
		rows.append(row)
		i += 1
	return rows


static func _prefab_height(prefab: String) -> float:
	if Prefabs.CATALOG.has(prefab):
		return (Prefabs.CATALOG[prefab].size as Vector3).y
	if Models.CATALOG.has(prefab):
		return (Models.CATALOG[prefab].size as Vector3).y
	return 0.0


static func _prefab_radius(prefab: String) -> float:
	var size := Vector3.ONE
	if Prefabs.CATALOG.has(prefab):
		size = Prefabs.CATALOG[prefab].size
	elif Models.CATALOG.has(prefab):
		size = Models.CATALOG[prefab].size
	return 0.5 * Vector2(size.x, size.z).length()


## Zone and obstacle rules for one point with a height and footprint radius. Returns an error string or "".
static func _check_point(n: float, e: float, height: float, radius: float, zone: String, geo: Dictionary, profile: Dictionary) -> String:
	var safety: float = geo.safety_north
	var centre_n: float = geo.centre_north
	var rn0: float = geo.runway_n0
	var rn1: float = geo.runway_n1
	var re0: float = geo.runway_e0
	var re1: float = geo.runway_e1
	var pilot_n: float = geo.pilot_north
	var pilot_e: float = geo.pilot_east
	var margin: float = profile.runway_margin_m
	var slope: float = profile.approach_slope
	var pits_behind: float = profile.pits_min_behind_m
	var pits_centre: float = profile.pits_min_from_centreline_m
	var spect_behind: float = profile.spectators_min_behind_m
	var park_behind: float = profile.parking_min_behind_m
	var box_depth: float = profile.flight_box_depth_m
	var box_half: float = profile.flight_box_half_width_m
	var box_height: float = profile.flight_box_max_height_m
	var behind := safety - n # metres behind the safety line (positive = pilot side)
	if n + radius > rn0 - margin and n - radius < rn1 + margin and e + radius > re0 - margin and e - radius < re1 + margin:
		return "on the runway or inside its %.1f m margin" % margin
	# Approach corridors beyond each runway end: height ≤ slope × distance past the end, within the runway's width + 20 m.
	var past := maxf(re0 - e, e - re1) - radius
	if past > 0.0 and absf(n - centre_n) < 20.0 + radius and height > slope * past:
		return "%.1f m tall %.0f m past the runway end, above the 1:%d approach surface" % [height, past, int(round(1.0 / maxf(slope, 1e-6)))]
	match zone:
		"pits", "club":
			if behind < pits_behind:
				return "%s zone %.1f m behind the safety line, needs ≥ %.1f" % [zone, behind, pits_behind]
			if centre_n - n < pits_centre:
				return "%s zone %.1f m from the take-off path, needs ≥ %.1f (BMFA)" % [zone, centre_n - n, pits_centre]
		"spectators":
			if behind < spect_behind:
				return "spectators %.1f m behind the safety line, needs ≥ %.1f" % [behind, spect_behind]
		"parking":
			if behind < park_behind:
				return "parking %.1f m behind the safety line, needs ≥ %.1f" % [behind, park_behind]
		"pilot_line":
			if behind < 0.0:
				return "pilot-line item in front of the safety line"
	var in_box := behind < 0.0 and -behind <= box_depth and absf(e - pilot_e) <= box_half
	if in_box and height > box_height:
		return "%.1f m tall inside the flight box (max %.1f m)" % [height, box_height]
	if zone == "flight_box" and not in_box:
		return "flight_box item outside the flight box"
	var dist := Vector2(n - pilot_n, e - pilot_e).length()
	if zone == "horizon" and dist < 1000.0:
		return "horizon landmark closer than 1 km"
	if zone == "horizon" and dist > 5000.0:
		return "horizon landmark beyond 5 km (SC-01 depth rule)"
	return ""


static func _tree_clash(n: float, e: float, radius: float, trees: PackedVector2Array, clearance: float) -> bool:
	var p := Vector2(n, e)
	var r: float = radius + clearance
	for t: Vector2 in trees:
		if p.distance_squared_to(t) < r * r:
			return true
	return false


static func _instances(errors: PackedStringArray, path: String, gd: Dictionary, group: Dictionary, geo: Dictionary,
		profile: Dictionary, trees: PackedVector2Array) -> void:
	var placements: Array = []
	if group.type == "fleet":
		var ids: Variant = gd.get("aircraft")
		if typeof(ids) != TYPE_ARRAY or (ids as Array).is_empty():
			errors.append(path + ".aircraft: expected a non-empty list of catalog ids")
			return
		group.aircraft = (ids as Array).map(func(x: Variant) -> String: return str(x))
		for a: String in group.aircraft:
			if Models.FLEET.find_key(a) == null:
				errors.append("%s.aircraft: '%s' has no baked fleet model (tools/scenery/bake_fleet.gd)" % [path, a])
				return
		group.prefab = "fleet"
		var rows := _points(errors, path + ".placements", gd.get("placements"), 4, "m, m, deg, index")
		for r: Array in rows:
			var idx := int(r[3])
			if idx < 0 or idx >= (group.aircraft as Array).size():
				errors.append(path + ".placements: aircraft index out of range")
				return
			var err := _check_point(r[0], r[1], 1.0, 1.6, group.zone, geo, profile)
			if not err.is_empty():
				errors.append("%s at (%.1f, %.1f): %s" % [path, r[0], r[1], err])
				return
			placements.append({north = r[0], east = r[1], heading = r[2], aircraft = group.aircraft[idx]})
		group.placements = placements
		return
	var prefab := str(gd.get("prefab", ""))
	var choices: Array = []
	var pv: Variant = gd.get("prefabs")
	if typeof(pv) == TYPE_ARRAY:
		for x: Variant in pv:
			choices.append(str(x))
	else:
		choices.append(prefab)
	for c: String in choices:
		if not Prefabs.CATALOG.has(c) and not Models.CATALOG.has(c):
			errors.append("%s: unknown prefab '%s'" % [path, c])
			return
	group.prefab = choices[0]
	group.choices = choices
	var rows := _points(errors, path + ".placements", gd.get("placements"), 3, "m, m, deg")
	var i := 0
	for r: Array in rows:
		var chosen: String = choices[i % choices.size()] if choices.size() == 1 else choices[int(_seed("%s/%d" % [group.id, i]) % choices.size())]
		var height := _prefab_height(chosen)
		var radius := _prefab_radius(chosen)
		var err := _check_point(r[0], r[1], height, radius, group.zone, geo, profile)
		if err.is_empty() and _tree_clash(r[0], r[1], radius, trees, profile.tree_clearance_m):
			err = "within %.1f m of a treeline tree" % profile.tree_clearance_m
		if not err.is_empty():
			errors.append("%s[%d] %s at (%.1f, %.1f): %s" % [path, i, chosen, r[0], r[1], err])
			return
		placements.append({north = r[0], east = r[1], heading = r[2], prefab = chosen, seed = (group.seed + i * 7919) & 0x7FFFFFFF})
		i += 1
	group.placements = placements


static func _line(errors: PackedStringArray, path: String, gd: Dictionary, group: Dictionary, geo: Dictionary, profile: Dictionary) -> void:
	var rows := _points(errors, path + ".points", gd.get("points"), 2, "m")
	var min_points := 3 if group.type == "patch" else 2
	if rows.size() < min_points:
		errors.append("%s.points: needs at least %d points" % [path, min_points])
		return
	var height := 0.0
	var width := 0.0
	match group.type:
		"hedge":
			height = _quantity(errors, path + ".height", gd.get("height"), "m")
			width = _quantity(errors, path + ".width", gd.get("width"), "m")
		"fence":
			group.style = str(gd.get("style", ""))
			if not FENCE_STYLES.has(group.style):
				errors.append(path + ".style: expected wire or rail")
			height = 1.2
		"track":
			width = _quantity(errors, path + ".width", gd.get("width"), "m")
			group.surface = str(gd.get("surface", ""))
			if not SURFACES.has(group.surface):
				errors.append(path + ".surface: expected one of %s" % [SURFACES])
		"patch":
			group.surface = str(gd.get("surface", ""))
			if not SURFACES.has(group.surface):
				errors.append(path + ".surface: expected one of %s" % [SURFACES])
	group.height = height
	group.width = width
	var pts: Array = []
	for r: Array in rows:
		# Lines are checked point by point; flat items (track, patch) are 0 m tall but still kept off the runway.
		var err := _check_point(r[0], r[1], height, maxf(width * 0.5, 0.2), group.zone, geo, profile)
		if not err.is_empty():
			errors.append("%s point (%.1f, %.1f): %s" % [path, r[0], r[1], err])
			return
		pts.append(Vector2(r[0], r[1]))
	group.points = pts


static func _flowers(errors: PackedStringArray, path: String, gd: Dictionary, group: Dictionary, geo: Dictionary) -> void:
	var rows := _points(errors, path + ".positions", gd.get("positions"), 3, "m, m, size m")
	var pts: Array = []
	for r: Array in rows:
		if r[2] <= 0.0 or r[2] > 1.0:
			errors.append(path + ": cushion size must be in (0, 1] m")
			return
		if r[0] > geo.runway_n0 - 1.0 and r[0] < geo.runway_n1 + 1.0 and r[1] > geo.runway_e0 - 1.0 and r[1] < geo.runway_e1 + 1.0:
			errors.append("%s: flower at (%.1f, %.1f) on the runway" % [path, r[0], r[1]])
			return
		pts.append(Vector3(r[0], r[1], r[2]))
	group.positions = pts
