## SC-BIRD-02: loads and validates `openrc-birds v1` (app/data/scenery/birds/birds.json). Invalid data never builds a
## flock: load_from() returns {ok = false, errors} and the scenery shows no birds. Quantities carry
## {value, unit, kind, source}; shapes and colours are plain numbers. Every flock's track is compiled here too, so a
## track that does not close, or whose period does not divide the 1024 s shader clock, is a data error.
extends RefCounted

const BirdTracks = preload("res://scenery/birds/bird_tracks.gd")

const DEFAULT_PATH := "res://data/scenery/birds/birds.json"
const FORMAT := "openrc-birds v1"
const KINDS: Array[String] = ["measured", "estimated", "derived", "borrowed", "manual"]
const GROUPS: Array[String] = ["soaring", "small"]
const TAIL_SHAPES: Array[String] = ["square", "forked", "wedge"]
const PERIODS: Array[String] = ["day", "evening"] # evening: afternoon only (screaming parties before sunset)
const DEPARTURES: Array[String] = ["away", "climb"] # how a bird leaves when its species stops flying
const MAX_SPECIES_PER_GROUP := 4
const MAX_TRACKS_PER_GROUP := 8
const MAX_SEGMENTS_PER_GROUP := 48
const MAX_COUNT := 64
const MAX_BIRDS_PER_GROUP := 32 # with 35 soaring triangles: 1,120 primitives if every bird were out at once
const MAX_DEPARTURE_SPEED := 30.0 # m/s

# [key, unit, min, max]
const SPECIES_FIELDS := [["span", "m", 0.1, 3.5], ["mass", "kg", 0.005, 15.0]]
const PLANFORM_FIELDS := [
	["body_length", "m", 0.02, 1.5], ["body_width", "m", 0.005, 0.5], ["wrist", "1", 0.15, 0.8],
	["root_chord", "m", 0.01, 1.0], ["wrist_chord", "m", 0.01, 1.0], ["tip_chord", "m", 0.0, 1.0],
	["wrist_sweep", "m", -0.5, 0.5], ["tip_sweep", "m", -0.8, 0.5], ["fingers", "1", 0.0, 8.0],
	["finger_length", "1", 0.0, 0.6], ["tail_length", "m", 0.0, 0.6], ["tail_width", "m", 0.0, 0.6],
	["tail_fork", "m", 0.0, 0.3],
]
const GAIT_FIELDS := [
	["flap_frequency", "Hz", 0.5, 16.0], ["flap_amplitude", "deg", 0.0, 70.0], ["burst_period", "s", 1.0, 1024.0],
	["burst_duty", "1", 0.0, 1.0], ["dihedral", "deg", -20.0, 20.0], ["hand_lag", "deg", 0.0, 90.0],
	["tip_curl", "deg", -30.0, 30.0], ["fold", "1", 0.0, 0.6], ["tail_twist", "1", 0.0, 2.0],
	["tail_wobble", "deg", 0.0, 20.0],
]
const ACTIVITY_FIELDS := [["sun_min", "deg", -10.0, 45.0]]
const ACTIVITY_OPTIONAL := [["sun_max", "deg", -5.0, 90.0, 90.0], ["clouds_max", "1", 0.2, 1.0, 1.0]]
const DEPARTURE_FIELDS := [["distance", "m", 50.0, 1000.0], ["duration", "s", 10.0, 300.0]]
const FLOCK_FIELDS := [["base_height", "m", 0.1, 400.0], ["spread_time", "s", 0.0, 1024.0],
	["spread_height", "m", 0.0, 50.0], ["heading", "deg", -360.0, 360.0]]


static func load_from(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {ok = false, errors = ["missing %s" % path]}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return validate(raw)


## Returns {ok, errors, species: {id: normalized}, flocks: [normalized with compiled tracks]}.
static func validate(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	if typeof(raw) != TYPE_DICTIONARY:
		return {ok = false, errors = ["root is not an object"]}
	var data: Dictionary = raw
	if data.get("format", "") != FORMAT:
		errors.append("format must be '%s'" % FORMAT)
	var species: Dictionary = {}
	var raw_species: Variant = data.get("species", null)
	if typeof(raw_species) != TYPE_DICTIONARY or (raw_species as Dictionary).is_empty():
		errors.append("species must be a non-empty object")
	else:
		var ids: Array = (raw_species as Dictionary).keys()
		ids.sort()
		for id: String in ids:
			var s: Dictionary = _species(id, (raw_species as Dictionary)[id], errors)
			if not s.is_empty():
				species[id] = s
	var flocks: Array[Dictionary] = []
	var raw_flocks: Variant = data.get("flocks", null)
	if typeof(raw_flocks) != TYPE_ARRAY or (raw_flocks as Array).is_empty():
		errors.append("flocks must be a non-empty array")
	else:
		var seen: Dictionary = {}
		for i: int in (raw_flocks as Array).size():
			var f: Dictionary = _flock(i, (raw_flocks as Array)[i], species, errors)
			if f.is_empty():
				continue
			if seen.has(f.id):
				errors.append("flock id '%s' repeated" % f.id)
			seen[f.id] = true
			flocks.append(f)
		_check_group_limits(flocks, errors)
	return {ok = errors.is_empty(), errors = errors, species = species, flocks = flocks}


## Rendering quantization: shader frequencies are multiples of 1/1024 Hz so the clock wrap is seamless.
static func clock_frequency(hz: float) -> float:
	return maxf(1.0, roundf(hz * 1024.0)) / 1024.0


static func _species(id: String, raw: Variant, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("species '%s' is not an object" % id)
		return {}
	var d: Dictionary = raw
	var before := errors.size()
	var out := {id = id, name = str(d.get("name", id))}
	_fields(out, d, SPECIES_FIELDS, "species '%s'" % id, errors)
	var planform: Dictionary = {}
	if typeof(d.get("planform")) != TYPE_DICTIONARY:
		errors.append("species '%s': planform missing" % id)
	else:
		_fields(planform, d.planform, PLANFORM_FIELDS, "species '%s' planform" % id, errors)
		var shape: String = str(d.planform.get("tail_shape", ""))
		if not TAIL_SHAPES.has(shape):
			errors.append("species '%s': tail_shape must be one of %s" % [id, TAIL_SHAPES])
		planform.tail_shape = shape
		if planform.has("fingers") and planform.fingers != roundf(planform.fingers):
			errors.append("species '%s': fingers must be a whole number" % id)
		if planform.has("tail_fork") and planform.has("tail_length") and planform.tail_fork > planform.tail_length:
			errors.append("species '%s': tail_fork longer than the tail" % id)
	out.planform = planform
	var gait: Dictionary = {}
	if typeof(d.get("gait")) != TYPE_DICTIONARY:
		errors.append("species '%s': gait missing" % id)
	else:
		_fields(gait, d.gait, GAIT_FIELDS, "species '%s' gait" % id, errors)
		if gait.has("burst_period"):
			var cycles: float = 1024.0 / float(gait.burst_period)
			if absf(cycles - roundf(cycles)) > 1e-9:
				errors.append("species '%s': burst_period must divide 1024 s" % id)
		if gait.has("flap_frequency"):
			gait.flap_frequency_clock = clock_frequency(gait.flap_frequency)
	out.gait = gait
	var colors: Dictionary = {}
	for key: String in ["top", "under", "tip"]:
		var c: Variant = d.get("colors", {}).get(key, null) if typeof(d.get("colors")) == TYPE_DICTIONARY else null
		if not _color_ok(c):
			errors.append("species '%s': colors.%s must be three numbers in [0, 1]" % [id, key])
			colors[key] = Color.BLACK
		else:
			colors[key] = Color(float(c[0]), float(c[1]), float(c[2]))
	out.colors = colors
	var activity: Dictionary = {}
	if typeof(d.get("activity")) != TYPE_DICTIONARY:
		errors.append("species '%s': activity missing" % id)
	else:
		var where := "species '%s' activity" % id
		_fields(activity, d.activity, ACTIVITY_FIELDS, where, errors)
		for spec: Array in ACTIVITY_OPTIONAL:
			activity[spec[0]] = spec[4]
			if d.activity.has(spec[0]):
				_fields(activity, d.activity, [spec.slice(0, 4)], where, errors)
		var period: String = str(d.activity.get("period", ""))
		if not PERIODS.has(period):
			errors.append("%s: period must be one of %s" % [where, PERIODS])
		activity.period = period
		if activity.has("sun_min") and float(activity.sun_max) < float(activity.sun_min) + 4.0:
			errors.append(where + ": sun_max must be at least 4 deg above sun_min")
	out.activity = activity
	var departure: Dictionary = {}
	if typeof(d.get("departure")) != TYPE_DICTIONARY:
		errors.append("species '%s': departure missing" % id)
	else:
		_fields(departure, d.departure, DEPARTURE_FIELDS, "species '%s' departure" % id, errors)
		var mode: String = str(d.departure.get("mode", ""))
		if not DEPARTURES.has(mode):
			errors.append("species '%s' departure: mode must be one of %s" % [id, DEPARTURES])
		departure.mode = mode
		if departure.has("distance") and departure.has("duration") \
				and float(departure.distance) / float(departure.duration) > MAX_DEPARTURE_SPEED:
			errors.append("species '%s' departure: faster than %s m/s" % [id, MAX_DEPARTURE_SPEED])
	out.departure = departure
	return out if errors.size() == before else {}


static func _flock(i: int, raw: Variant, species: Dictionary, errors: Array[String]) -> Dictionary:
	var where := "flock %d" % i
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append(where + " is not an object")
		return {}
	var d: Dictionary = raw
	var before := errors.size()
	var id: String = str(d.get("id", ""))
	if id.is_empty():
		errors.append(where + ": id missing")
	where = "flock '%s'" % id
	var out := {id = id}
	var group: String = str(d.get("group", ""))
	if not GROUPS.has(group):
		errors.append(where + ": group must be one of %s" % [GROUPS])
	out.group = group
	var sid: String = str(d.get("species", ""))
	if not species.has(sid):
		errors.append(where + ": unknown or invalid species '%s'" % sid)
	out.species = sid
	var count: Variant = d.get("count", null)
	if not _number(count) or float(count) != roundf(float(count)) or int(count) < 1 or int(count) > MAX_COUNT:
		errors.append(where + ": count must be a whole number in [1, %d]" % MAX_COUNT)
	else:
		out.count = int(count)
	var origin: Variant = _quantity(d.get("origin"), "m", where + " origin", errors)
	if origin != null:
		if typeof(origin) != TYPE_ARRAY or (origin as Array).size() != 3 \
				or not (_number(origin[0]) and _number(origin[1]) and _number(origin[2])):
			errors.append(where + ": origin must be [north, east, down] metres")
		else:
			out.origin = [float(origin[0]), float(origin[1]), float(origin[2])]
	_fields(out, d, FLOCK_FIELDS, where, errors)
	var offset: Variant = d.get("spread_offset", null)
	out.spread_offset = 0.0
	if offset != null:
		var o: Variant = _quantity(offset, "m", where + " spread_offset", errors)
		if o != null and (not _number(o) or float(o) < 0.0 or float(o) > 100.0):
			errors.append(where + ": spread_offset out of [0, 100] m")
		elif o != null:
			out.spread_offset = float(o)
	for key: String in ["rotate_instances", "mirror_instances"]:
		var flag: Variant = d.get(key, false)
		if typeof(flag) != TYPE_BOOL:
			errors.append(where + ": %s must be true or false" % key)
			flag = false
		out[key] = flag
	var anchor: String = str(d.get("anchor", ""))
	if not BirdTracks.ANCHORS.has(anchor):
		errors.append(where + ": anchor must be one of %s" % [BirdTracks.ANCHORS])
	out.anchor = anchor
	var repeats: Variant = d.get("repeats", null)
	if not _number(repeats) or float(repeats) != roundf(float(repeats)) or int(repeats) < 1 or int(repeats) > 12:
		errors.append(where + ": repeats must be a whole number in [1, 12]")
	else:
		out.repeats = int(repeats)
	var tracks: Variant = d.get("tracks", null)
	if typeof(tracks) != TYPE_ARRAY or (tracks as Array).is_empty():
		errors.append(where + ": tracks must be a non-empty array")
	elif errors.size() == before:
		var compiled: Array[Dictionary] = []
		for t: int in (tracks as Array).size():
			var raw_track: Variant = (tracks as Array)[t]
			if typeof(raw_track) != TYPE_DICTIONARY:
				errors.append(where + ": track %d is not an object" % t)
				continue
			var result: Dictionary = BirdTracks.compile((raw_track as Dictionary).get("motif", null), out.repeats,
				deg_to_rad(out.heading), out.anchor)
			if not result.ok:
				for e: String in result.errors:
					errors.append(where + " track %d: %s" % [t, e])
			else:
				compiled.append(result.track)
		out.tracks = compiled
	return out if errors.size() == before else {}


static func _check_group_limits(flocks: Array[Dictionary], errors: Array[String]) -> void:
	for group: String in GROUPS:
		var species: Dictionary = {}
		var tracks := 0
		var segments := 0
		var birds := 0
		for f: Dictionary in flocks:
			if f.group != group:
				continue
			species[f.species] = true
			birds += int(f.get("count", 0))
			tracks += (f.tracks as Array).size()
			for t: Dictionary in f.tracks:
				segments += (t.segments as Array).size()
		if birds > MAX_BIRDS_PER_GROUP:
			errors.append("group '%s': %d birds, more than %d" % [group, birds, MAX_BIRDS_PER_GROUP])
		if species.size() > MAX_SPECIES_PER_GROUP:
			errors.append("group '%s': more than %d species" % [group, MAX_SPECIES_PER_GROUP])
		if tracks > MAX_TRACKS_PER_GROUP:
			errors.append("group '%s': more than %d tracks" % [group, MAX_TRACKS_PER_GROUP])
		if segments > MAX_SEGMENTS_PER_GROUP:
			errors.append("group '%s': %d segments, more than %d" % [group, segments, MAX_SEGMENTS_PER_GROUP])


static func _fields(out: Dictionary, d: Dictionary, specs: Array, where: String, errors: Array[String]) -> void:
	for spec: Array in specs:
		var v: Variant = _quantity(d.get(spec[0], null), spec[1], "%s %s" % [where, spec[0]], errors)
		if v == null:
			continue
		if not _number(v) or float(v) < float(spec[2]) or float(v) > float(spec[3]):
			errors.append("%s %s: %s outside [%s, %s] %s" % [where, spec[0], v, spec[2], spec[3], spec[1]])
			continue
		out[spec[0]] = float(v)


## The value of a {value, unit, kind, source} quantity with the expected unit, or null (with an error).
static func _quantity(raw: Variant, unit: String, where: String, errors: Array[String]) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append(where + ": missing quantity")
		return null
	var q: Dictionary = raw
	if str(q.get("unit", "")) != unit:
		errors.append("%s: unit must be '%s'" % [where, unit])
		return null
	if not KINDS.has(str(q.get("kind", ""))):
		errors.append("%s: kind must be one of %s" % [where, KINDS])
		return null
	if str(q.get("source", "")).strip_edges().is_empty():
		errors.append(where + ": source missing")
		return null
	if not q.has("value"):
		errors.append(where + ": value missing")
		return null
	return q.value


static func _number(v: Variant) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v))


static func _color_ok(c: Variant) -> bool:
	if typeof(c) != TYPE_ARRAY or (c as Array).size() != 3:
		return false
	for x: Variant in c:
		if not _number(x) or float(x) < 0.0 or float(x) > 1.0:
			return false
	return true
