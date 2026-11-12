# DR-23/DR-24: strict loader for `openrc-race-track v1` and the pinned ruleset record `openrc-local-race-v1`.
# A track is plain data: ordered upright rectangular gates and one start pad, in metres north/east of the field's
# pilot station. load_file()/load_document() refuse anything outside the closed contract (unknown keys, wrong types,
# non-finite numbers, duplicate ids, tilted gates, out-of-range sizes, inconsistent direction) with path-bearing
# errors; nothing defaults silently. prepare() resolves the gates on one field and ground into immutable world data
# (NED centre, unit normal and in-plane axes, half sizes), the gate frames' solid proxies and the course identity.
#
# Does not claim: FAI, MultiGP or any federation course or rule compliance. These are local practice rules; gate
# timing evidence is the chord-path policy with its declared acceleration envelope (race_director.gd). 64-bit floats.
extends RefCounted

const M := preload("res://physics/math3d.gd")

const FORMAT := "openrc-race-track v1"
const RULESET := "openrc-local-race-v1"
const PATH_POLICY := "openrc-chord-path-v1"
const ORIGIN_PILOT := "pilot"

const TOP_KEYS := ["format", "id", "name", "field_id", "ruleset", "laps", "origin", "pad", "gates"]
const PAD_KEYS := ["north_m", "east_m", "heading_deg"]
const GATE_KEYS := ["id", "north_m", "east_m", "center_height_m", "heading_deg", "width_m", "height_m"]
## Any key naming one of these is an explicit request for a non-upright gate: refused as unsupported in v1.
const ORIENTATION_WORDS := ["tilt", "pitch", "roll", "bank", "incline"]

const MIN_GATES := 3
const MAX_GATES := 32
const MAX_ID_LENGTH := 64
const MAX_NAME_LENGTH := 128
const MAX_COORDINATE_M := 2000.0
const MIN_WIDTH_M := 1.0
const MAX_WIDTH_M := 6.0
const MIN_HEIGHT_M := 1.0
const MAX_HEIGHT_M := 4.0
const MAX_CENTER_HEIGHT_M := 20.0
## Lower aperture edge above the local ground, at the centre and at both post bases.
const MIN_LOWER_EDGE_M := 0.3
const MIN_GATE_SPACING_M := 6.0
## The pad lies at least this far behind gate 0's plane, on its approach side.
const MIN_PAD_SETBACK_M := 4.0
## The pad stays this far from every gate plane wherever it is within this distance of the aperture's side edges.
const PAD_PLANE_CLEARANCE_M := 1.0
## Solid frame proxies: square section of the posts and bars (m).
const FRAME_SECTION_M := 0.06
## Minimum horizontal clearance of a gate frame footprint or the pad zone from listed field objects.
const OBJECT_CLEARANCE_M := 1.0
## Horizontal radius of a tree card (field_loader.gd TREE_CARD_MAX_HORIZONTAL_RADIUS_M).
const TREE_RADIUS_M := 15.0


## The pinned record of the first local ruleset. Every value is part of the course identity.
static func ruleset() -> Dictionary:
	return {id = RULESET, laps = 3, sample_hz = 240, countdown_ticks = 720, tie_window_s = 1.0e-6,
		path_policy = PATH_POLICY, acceleration_envelope_mps2 = 250.0, min_normal_speed_mps = 1.0,
		pad_radius_m = 1.5, pad_rest_speed_mps = 0.2, pad_rest_height_m = 0.25}


## {ok, errors, track, sha256}. The sha256 hashes the file bytes exactly as read.
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {ok = false, errors = PackedStringArray(["%s: cannot open track file" % path]), track = {}, sha256 = ""}
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		return {ok = false, errors = PackedStringArray(["%s: JSON error at line %d: %s" % [path, parser.get_error_line(),
			parser.get_error_message()]]), track = {}, sha256 = ""}
	return _finish(parser.data, path, bytes)


## {ok, errors, track, sha256} for an in-memory document. The sha256 hashes its canonical JSON text (sorted keys),
## computed only for an admitted document (every number in it is then finite).
static func load_document(raw: Variant, label: String = "track document") -> Dictionary:
	return _finish(raw, label, PackedByteArray())


## `bytes` empty: hash the canonical JSON text of the admitted document instead of file bytes.
static func _finish(raw: Variant, label: String, bytes: PackedByteArray) -> Dictionary:
	var parsed: Dictionary = parse(raw)
	if not parsed.ok:
		var labelled := PackedStringArray()
		for message: String in parsed.errors:
			labelled.append("%s: %s" % [label, message])
		return {ok = false, errors = labelled, track = {}, sha256 = ""}
	var source: PackedByteArray = bytes if not bytes.is_empty() else JSON.stringify(raw, "", true, true).to_utf8_buffer()
	var sha: String = _sha256(source)
	parsed.track.source_sha256 = sha
	return {ok = true, errors = PackedStringArray(), track = parsed.track, sha256 = sha}


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


## Validate a decoded document. {ok, errors, track}: the track holds plain validated numbers in local metres.
static func parse(raw: Variant) -> Dictionary:
	var e := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		return {ok = false, errors = PackedStringArray(["track: expected an object"]), track = {}}
	var root: Dictionary = raw
	if root.get("format") != FORMAT:
		e.append("format: expected '%s'" % FORMAT)
		return {ok = false, errors = e, track = {}}
	_closed_keys(root, "track", TOP_KEYS, e)
	var track := {}
	track.id = _text(root, "id", "id", e, MAX_ID_LENGTH)
	track.name = _text(root, "name", "name", e, MAX_NAME_LENGTH)
	track.field_id = _text(root, "field_id", "field_id", e, MAX_ID_LENGTH)
	track.ruleset = _text(root, "ruleset", "ruleset", e, MAX_ID_LENGTH)
	if track.ruleset != RULESET and not track.ruleset.is_empty():
		e.append("ruleset: '%s' is not supported; expected '%s'" % [track.ruleset, RULESET])
	track.origin = _text(root, "origin", "origin", e, MAX_ID_LENGTH)
	if track.origin != ORIGIN_PILOT and not track.origin.is_empty():
		e.append("origin: '%s' is not supported; expected '%s'" % [track.origin, ORIGIN_PILOT])
	var laps: float = _number(root, "laps", "laps", e, 1.0, 99.0)
	if is_finite(laps) and laps != float(int(ruleset().laps)):
		e.append("laps: ruleset %s fixes exactly %d laps" % [RULESET, int(ruleset().laps)])
	track.laps = int(ruleset().laps)
	var pad_node: Variant = root.get("pad")
	var pad := {}
	if typeof(pad_node) != TYPE_DICTIONARY:
		e.append("pad: expected an object")
	else:
		_closed_keys(pad_node, "pad", PAD_KEYS, e)
		pad = {north_m = _number(pad_node, "north_m", "pad.north_m", e, -MAX_COORDINATE_M, MAX_COORDINATE_M),
			east_m = _number(pad_node, "east_m", "pad.east_m", e, -MAX_COORDINATE_M, MAX_COORDINATE_M),
			heading_deg = _heading(pad_node, "heading_deg", "pad.heading_deg", e)}
	track.pad = pad
	var gates_node: Variant = root.get("gates")
	var gates: Array = []
	if typeof(gates_node) != TYPE_ARRAY:
		e.append("gates: expected an array")
	elif gates_node.size() < MIN_GATES or gates_node.size() > MAX_GATES:
		e.append("gates: %d gates; expected %d to %d" % [gates_node.size(), MIN_GATES, MAX_GATES])
	else:
		var ids := {}
		for index: int in gates_node.size():
			var path := "gates[%d]" % index
			var node: Variant = gates_node[index]
			if typeof(node) != TYPE_DICTIONARY:
				e.append("%s: expected an object" % path)
				continue
			_closed_keys(node, path, GATE_KEYS, e)
			var gate := {index = index, id = _text(node, "id", path + ".id", e, MAX_ID_LENGTH),
				north_m = _number(node, "north_m", path + ".north_m", e, -MAX_COORDINATE_M, MAX_COORDINATE_M),
				east_m = _number(node, "east_m", path + ".east_m", e, -MAX_COORDINATE_M, MAX_COORDINATE_M),
				center_height_m = _number(node, "center_height_m", path + ".center_height_m", e, 0.0, MAX_CENTER_HEIGHT_M),
				heading_deg = _heading(node, "heading_deg", path + ".heading_deg", e),
				width_m = _number(node, "width_m", path + ".width_m", e, MIN_WIDTH_M, MAX_WIDTH_M),
				height_m = _number(node, "height_m", path + ".height_m", e, MIN_HEIGHT_M, MAX_HEIGHT_M)}
			if not gate.id.is_empty():
				if ids.has(gate.id):
					e.append("%s.id: duplicate gate id '%s'" % [path, gate.id])
				ids[gate.id] = true
			if is_finite(gate.center_height_m) and is_finite(gate.height_m) \
					and gate.center_height_m - 0.5 * gate.height_m < MIN_LOWER_EDGE_M:
				e.append("%s: lower aperture edge %.3f m is below the %.2f m minimum above ground" % [path,
					gate.center_height_m - 0.5 * gate.height_m, MIN_LOWER_EDGE_M])
			gates.append(gate)
	track.gates = gates
	if e.is_empty():
		_check_layout(track, e)
	if not e.is_empty():
		return {ok = false, errors = e, track = {}}
	return {ok = true, errors = e, track = track}


## Local geometry rules, horizontal (north, east) unless stated:
##   spacing: consecutive centres, finish to gate 0 included, are >= MIN_GATE_SPACING_M apart (height difference included);
##   direction: for each consecutive pair i -> j (cyclic) the next centre lies strictly in front of gate i's plane
##     (n_i·(c_j − c_i) > 0) AND gate i lies strictly behind gate j's plane (n_j·(c_i − c_j) < 0), so the straight
##     line from i to j leaves i forward and approaches j from its allowed side. v1 therefore refuses a hairpin between
##     consecutive gates; an intermediate gate makes it consistent;
##   pad: at least MIN_PAD_SETBACK_M behind gate 0's plane, and for every gate either |n·(pad − c)| >= 1 m or the pad
##     lies more than 1 m beyond the aperture's side edges (starting on, or within 1 m of, an aperture plane is refused).
static func _check_layout(track: Dictionary, e: PackedStringArray) -> void:
	var gates: Array = track.gates
	var count: int = gates.size()
	for i in count:
		var a: Dictionary = gates[i]
		var b: Dictionary = gates[(i + 1) % count]
		var dn: float = b.north_m - a.north_m
		var de: float = b.east_m - a.east_m
		var dh: float = b.center_height_m - a.center_height_m
		var spacing: float = sqrt(dn * dn + de * de + dh * dh)
		if spacing < MIN_GATE_SPACING_M:
			e.append("gates[%d]->gates[%d]: centres %.3f m apart; at least %.1f m required" % [i, (i + 1) % count, spacing,
				MIN_GATE_SPACING_M])
		var na: PackedFloat64Array = heading_normal(a.heading_deg)
		var nb: PackedFloat64Array = heading_normal(b.heading_deg)
		if na[0] * dn + na[1] * de <= 0.0:
			e.append("gates[%d]->gates[%d]: inconsistent direction: the next gate is not in front of gates[%d]'s plane" % [i,
				(i + 1) % count, i])
		if nb[0] * -dn + nb[1] * -de >= 0.0:
			e.append("gates[%d]->gates[%d]: inconsistent direction: gates[%d] is not approached from its allowed side" % [i,
				(i + 1) % count, (i + 1) % count])
	var pad: Dictionary = track.pad
	var first: Dictionary = gates[0]
	var n0: PackedFloat64Array = heading_normal(first.heading_deg)
	var setback: float = n0[0] * (pad.north_m - first.north_m) + n0[1] * (pad.east_m - first.east_m)
	if setback > -MIN_PAD_SETBACK_M:
		e.append("pad: %.3f m from gates[0]'s plane; it must lie at least %.1f m behind it on the approach side" % [setback,
			MIN_PAD_SETBACK_M])
	for i in count:
		var gate: Dictionary = gates[i]
		var n: PackedFloat64Array = heading_normal(gate.heading_deg)
		var dn: float = pad.north_m - gate.north_m
		var de: float = pad.east_m - gate.east_m
		var along: float = n[0] * dn + n[1] * de
		var across: float = -n[1] * dn + n[0] * de
		if absf(along) < PAD_PLANE_CLEARANCE_M and absf(across) < 0.5 * gate.width_m + PAD_PLANE_CLEARANCE_M:
			e.append("pad: within %.1f m of gates[%d]'s aperture plane; starting on a gate plane is refused" % [
				PAD_PLANE_CLEARANCE_M, i])


## Horizontal unit normal (north, east) of a compass heading in degrees.
static func heading_normal(heading_deg: float) -> PackedFloat64Array:
	var radians: float = deg_to_rad(heading_deg)
	return PackedFloat64Array([M.cos_(radians), M.sin_(radians)])


## Resolve a parsed track on a loaded field (data/field_loader.gd result `field`) and a ground callable
## ground(north, east) -> [height_up_m, slope_north, slope_east]. {ok, errors, course}.
## Course gate record: c (NED centre), n (unit normal, horizontal, direction of allowed travel), u (horizontal, right of
## travel), v (down), w and h (half width and half height), plus `frames`: four solid box proxies in this order
## [left post, right post, top bar, bottom bar]. Each box is {north, east, down, half_x, half_down, half_z, heading_deg}:
## centre in world NED metres; the box x axis is the gate normal n (horizontal, compass heading heading_deg), the z axis
## is u (right of travel) and `down` is vertical; half_* are the half extents along those axes. The posts run from the
## ground at their base to the top of the top bar; bars span both posts; inner faces lie exactly on the aperture edges.
static func prepare(track: Dictionary, field: Dictionary, ground: Callable) -> Dictionary:
	var e := PackedStringArray()
	if track.is_empty() or not track.has_all(["id", "field_id", "gates", "pad", "laps", "source_sha256"]):
		return {ok = false, errors = PackedStringArray(["prepare: the track is not a loaded openrc-race-track v1"]), course = {}}
	var field_id: Variant = field.get("id")
	var pilot: Variant = field.get("pilot")
	if typeof(field_id) != TYPE_STRING or typeof(pilot) != TYPE_DICTIONARY or typeof(pilot.get("north")) != TYPE_FLOAT \
			or typeof(pilot.get("east")) != TYPE_FLOAT:
		return {ok = false, errors = PackedStringArray(["prepare: the field is not a loaded openrc-field v1"]), course = {}}
	if field_id != track.field_id:
		e.append("field_id: the track is for field '%s' but the session loaded field '%s'" % [track.field_id, field_id])
	if not ground.is_valid():
		e.append("prepare: a ground height callable is required")
	if not e.is_empty():
		return {ok = false, errors = e, course = {}}
	var origin_north: float = pilot.north
	var origin_east: float = pilot.east
	var gates: Array = []
	var frames: Array = []
	var footprints: Array = []
	for gate: Dictionary in track.gates:
		var path := "gates[%d]" % int(gate.index)
		var north: float = origin_north + float(gate.north_m)
		var east: float = origin_east + float(gate.east_m)
		var surface: PackedFloat64Array = _ground(ground, north, east, path, e)
		var normal: PackedFloat64Array = heading_normal(gate.heading_deg)
		var w: float = 0.5 * float(gate.width_m)
		var h: float = 0.5 * float(gate.height_m)
		var altitude: float = surface[0] + float(gate.center_height_m)
		var c := PackedFloat64Array([north, east, -altitude])
		var n := PackedFloat64Array([normal[0], normal[1], 0.0])
		var u := PackedFloat64Array([-normal[1], normal[0], 0.0])
		var v := PackedFloat64Array([0.0, 0.0, 1.0])
		var half_section: float = 0.5 * FRAME_SECTION_M
		var top: float = altitude + h + FRAME_SECTION_M
		var boxes: Array = []
		for side: float in [-1.0, 1.0]:
			var post_north: float = north + side * (w + half_section) * u[0]
			var post_east: float = east + side * (w + half_section) * u[1]
			var base: PackedFloat64Array = _ground(ground, post_north, post_east, path, e)
			if altitude - h - base[0] < MIN_LOWER_EDGE_M:
				e.append("%s: lower aperture edge is %.3f m above the ground at a post; at least %.2f m required" % [path,
					altitude - h - base[0], MIN_LOWER_EDGE_M])
			boxes.append({north = post_north, east = post_east, down = -0.5 * (top + base[0]), half_x = half_section,
				half_down = 0.5 * (top - base[0]), half_z = half_section, heading_deg = float(gate.heading_deg)})
		for bar_side: float in [-1.0, 1.0]:
			boxes.append({north = north, east = east, down = -altitude + bar_side * (h + half_section), half_x = half_section,
				half_down = half_section, half_z = w + FRAME_SECTION_M, heading_deg = float(gate.heading_deg)})
		if altitude - h - surface[0] < MIN_LOWER_EDGE_M:
			e.append("%s: lower aperture edge below %.2f m above the ground" % [path, MIN_LOWER_EDGE_M])
		frames.append_array(boxes)
		var reach: float = w + FRAME_SECTION_M
		footprints.append({path = path, a = PackedFloat64Array([north - reach * u[0], east - reach * u[1]]),
			b = PackedFloat64Array([north + reach * u[0], east + reach * u[1]])})
		gates.append({index = int(gate.index), id = str(gate.id), c = c, n = n, u = u, v = v, w = w, h = h,
			heading_deg = float(gate.heading_deg), width_m = float(gate.width_m), height_m = float(gate.height_m),
			frames = boxes})
	var count: int = gates.size()
	for i in count:
		var a: PackedFloat64Array = gates[i].c
		var b: PackedFloat64Array = gates[(i + 1) % count].c
		var spacing: float = sqrt((b[0] - a[0]) * (b[0] - a[0]) + (b[1] - a[1]) * (b[1] - a[1]) + (b[2] - a[2]) * (b[2] - a[2]))
		if spacing < MIN_GATE_SPACING_M:
			e.append("gates[%d]->gates[%d]: world centres %.3f m apart; at least %.1f m required" % [i, (i + 1) % count,
				spacing, MIN_GATE_SPACING_M])
	var pad_north: float = origin_north + float(track.pad.north_m)
	var pad_east: float = origin_east + float(track.pad.east_m)
	var pad_ground: PackedFloat64Array = _ground(ground, pad_north, pad_east, "pad", e)
	var rules: Dictionary = ruleset()
	var clearance: Dictionary = _field_clearance(field, footprints, pad_north, pad_east, float(rules.pad_radius_m), e)
	if not e.is_empty():
		return {ok = false, errors = e, course = {}}
	var resolved: Array = []
	for gate: Dictionary in gates:
		resolved.append([gate.id, gate.c, gate.n, gate.w, gate.h])
	var identity: String = _sha256(var_to_bytes([FORMAT, str(track.source_sha256), str(field_id), rules, resolved,
		pad_north, pad_east, -pad_ground[0]]))
	var course := {identity = identity, tag = float(identity.substr(0, 13).hex_to_int()), track_id = str(track.id),
		track_name = str(track.name), track_sha256 = str(track.source_sha256), field_id = str(field_id), ruleset = rules,
		laps = int(track.laps), gate_count = count, gates = gates, frames = frames,
		pad = {north = pad_north, east = pad_east, down = -pad_ground[0], heading_deg = float(track.pad.heading_deg)},
		min_object_clearance_m = clearance.minimum, nearest_object = clearance.nearest}
	return {ok = true, errors = e, course = course}


static func _ground(ground: Callable, north: float, east: float, path: String, e: PackedStringArray) -> PackedFloat64Array:
	var value: Variant = ground.call(north, east)
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != 3 or not is_finite(value[0]) \
			or not is_finite(value[1]) or not is_finite(value[2]):
		e.append("%s: the ground callable returned no finite [height, slope_north, slope_east]" % path)
		return PackedFloat64Array([0.0, 0.0, 0.0])
	return value


## Horizontal clearance of every gate footprint (outer post faces) and the pad zone from the field's listed objects:
## flight cues (windsock, pilot station, flightline barrier), rotorcraft-pad keepouts and treeline cards. Every gate
## post base and the pad also lie inside at least one field surface. {minimum, nearest}.
static func _field_clearance(field: Dictionary, footprints: Array, pad_north: float, pad_east: float, pad_radius: float,
		e: PackedStringArray) -> Dictionary:
	var obstacles: Array = [] # {id, kind: "point"|"rect"|"segment", ...}
	for cue: Variant in field.get("flight_cues", []):
		if typeof(cue) != TYPE_DICTIONARY:
			continue
		match str(cue.get("type", "")):
			"windsock":
				obstacles.append({id = "windsock", kind = "point", p = PackedFloat64Array([float(cue.north), float(cue.east)]),
					radius = 0.5 * float(cue.length) + 0.5 * float(cue.throat_diameter)})
			"pilot_station":
				obstacles.append({id = "pilot_station", kind = "rect", center = PackedFloat64Array([float(cue.north), float(cue.east)]),
					half = PackedFloat64Array([0.5 * float(cue.depth), 0.5 * float(cue.width)])})
			"flightline_barrier":
				var half_width: float = 0.5 * float(cue.width)
				var half_gap: float = 0.5 * float(cue.gap_width)
				for side_sign: float in [-1.0, 1.0]:
					obstacles.append({id = "flightline_barrier", kind = "segment",
						a = PackedFloat64Array([float(cue.north), float(cue.east) + side_sign * half_gap]),
						b = PackedFloat64Array([float(cue.north), float(cue.east) + side_sign * half_width]), radius = 0.04})
	var rotor_pad: Variant = field.get("rotorcraft_pad", {})
	if typeof(rotor_pad) == TYPE_DICTIONARY:
		for keepout: Variant in rotor_pad.get("keepouts", []):
			if typeof(keepout) == TYPE_DICTIONARY:
				obstacles.append({id = str(keepout.get("id", "keepout")), kind = "rect",
					center = PackedFloat64Array([float(keepout.north), float(keepout.east)]),
					half = PackedFloat64Array([0.5 * float(keepout.width_north_south), 0.5 * float(keepout.length_east_west)])})
	for item: Variant in field.get("objects", []):
		if typeof(item) == TYPE_DICTIONARY and str(item.get("type", "")) == "treeline":
			for position: Variant in item.get("positions", []):
				obstacles.append({id = "treeline", kind = "point",
					p = PackedFloat64Array([float(position[0]), float(position[1])]), radius = TREE_RADIUS_M})
	var minimum: float = INF
	var nearest := ""
	var shapes: Array = []
	for footprint: Dictionary in footprints:
		shapes.append({path = footprint.path, a = footprint.a, b = footprint.b, radius = 0.5 * FRAME_SECTION_M})
	var pad := PackedFloat64Array([pad_north, pad_east])
	shapes.append({path = "pad", a = pad, b = pad, radius = pad_radius})
	for shape: Dictionary in shapes:
		for obstacle: Dictionary in obstacles:
			var gap: float
			match str(obstacle.kind):
				"point":
					gap = _point_segment(obstacle.p, shape.a, shape.b) - float(obstacle.radius)
				"segment":
					gap = _segment_segment(shape.a, shape.b, obstacle.a, obstacle.b) - float(obstacle.radius)
				_:
					gap = _segment_rect(shape.a, shape.b, obstacle.center, obstacle.half)
			gap -= float(shape.radius)
			if gap < minimum:
				minimum = gap
				nearest = "%s to %s" % [shape.path, obstacle.id]
			if gap < OBJECT_CLEARANCE_M:
				e.append("%s: %.3f m from field object '%s'; at least %.1f m required" % [shape.path, gap, obstacle.id,
					OBJECT_CLEARANCE_M])
		for end: PackedFloat64Array in [shape.a, shape.b]:
			if not _inside_surface(field, end):
				e.append("%s: lies outside every field surface" % shape.path)
	return {minimum = minimum, nearest = nearest}


static func _inside_surface(field: Dictionary, p: PackedFloat64Array) -> bool:
	for surface: Variant in field.get("surfaces", []):
		if typeof(surface) != TYPE_DICTIONARY:
			continue
		if absf(p[0] - float(surface.center_north)) <= 0.5 * float(surface.width_north_south) \
				and absf(p[1] - float(surface.center_east)) <= 0.5 * float(surface.length_east_west):
			return true
	return false


static func _point_segment(p: PackedFloat64Array, a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var dx: float = b[0] - a[0]
	var dy: float = b[1] - a[1]
	var length_sq: float = dx * dx + dy * dy
	var s: float = 0.0
	if length_sq > 0.0:
		s = clampf(((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / length_sq, 0.0, 1.0)
	var qx: float = a[0] + s * dx - p[0]
	var qy: float = a[1] + s * dy - p[1]
	return sqrt(qx * qx + qy * qy)


static func _cross2(o: PackedFloat64Array, a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


static func _segment_segment(a: PackedFloat64Array, b: PackedFloat64Array, c: PackedFloat64Array, d: PackedFloat64Array) -> float:
	var d1: float = _cross2(c, d, a)
	var d2: float = _cross2(c, d, b)
	var d3: float = _cross2(a, b, c)
	var d4: float = _cross2(a, b, d)
	if ((d1 > 0.0 and d2 < 0.0) or (d1 < 0.0 and d2 > 0.0)) and ((d3 > 0.0 and d4 < 0.0) or (d3 < 0.0 and d4 > 0.0)):
		return 0.0
	return minf(minf(_point_segment(a, c, d), _point_segment(b, c, d)), minf(_point_segment(c, a, b), _point_segment(d, a, b)))


static func _segment_rect(a: PackedFloat64Array, b: PackedFloat64Array, center: PackedFloat64Array, half: PackedFloat64Array) -> float:
	if absf(a[0] - center[0]) <= half[0] and absf(a[1] - center[1]) <= half[1]:
		return 0.0
	var corners: Array = [PackedFloat64Array([center[0] - half[0], center[1] - half[1]]),
		PackedFloat64Array([center[0] - half[0], center[1] + half[1]]), PackedFloat64Array([center[0] + half[0], center[1] + half[1]]),
		PackedFloat64Array([center[0] + half[0], center[1] - half[1]])]
	var best: float = INF
	for i in 4:
		best = minf(best, _segment_segment(a, b, corners[i], corners[(i + 1) % 4]))
	return best


static func _closed_keys(node: Dictionary, path: String, allowed: Array, e: PackedStringArray) -> void:
	for key: Variant in node.keys():
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME]:
			e.append("%s: keys must be strings" % path)
			continue
		if allowed.has(str(key)):
			continue
		var lowered: String = str(key).to_lower()
		var orientation := false
		for word: String in ORIENTATION_WORDS:
			if lowered.contains(word):
				orientation = true
		if orientation:
			e.append("%s.%s: unsupported: v1 admits upright rectangular gates only (no tilt, pitch or roll)" % [path, key])
		else:
			e.append("%s.%s: unknown key (closed contract)" % [path, key])
	for key: String in allowed:
		if not node.has(key):
			e.append("%s.%s: missing" % [path, key])


static func _text(node: Dictionary, key: String, path: String, e: PackedStringArray, max_length: int) -> String:
	if not node.has(key):
		return ""
	var value: Variant = node[key]
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > max_length or value != value.strip_edges():
		e.append("%s: expected a nonempty string of at most %d characters without edge whitespace" % [path, max_length])
		return ""
	return value


## NAN when missing or invalid (the error is recorded).
static func _number(node: Dictionary, key: String, path: String, e: PackedStringArray, low: float, high: float) -> float:
	if not node.has(key):
		return NAN
	var value: Variant = node[key]
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT]:
		e.append("%s: expected a number" % path)
		return NAN
	var number: float = float(value)
	if not is_finite(number):
		e.append("%s: must be finite" % path)
		return NAN
	if number < low or number > high:
		e.append("%s: %s outside [%s, %s]" % [path, str(number), str(low), str(high)])
		return NAN
	return number


static func _heading(node: Dictionary, key: String, path: String, e: PackedStringArray) -> float:
	var value: float = _number(node, key, path, e, 0.0, 360.0)
	if is_finite(value) and value >= 360.0:
		e.append("%s: compass heading must lie in [0, 360) degrees" % path)
		return NAN
	return value
