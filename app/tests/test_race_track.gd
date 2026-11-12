# DR-23/DR-24 RACE-01, RACE-03 (identity part): the strict `openrc-race-track v1` loader, the shipped practice oval on the
# default field, malformed-document refusals with path-bearing errors, the course identity and the gate frame proxies.
# Local practice course data; no federation course compliance.
extends SceneTree

const Track := preload("res://sim/race/track.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const AirfieldTrack := preload("res://physics/ground_vehicle/airfield_track.gd")

const SHIPPED := "res://data/race/tracks/openrc-practice-oval-1.json"
const TOWER := "res://data/race/tracks/openrc-tower-sprint-1.json"

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _flat(_north: float, _east: float) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0])


func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SHIPPED))


func _run() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	_check("the default field loads", field_result.ok, str(field_result.errors))
	var field: Dictionary = field_result.field
	_shipped(field)
	_refusals(field)
	_identity(field)
	_frames(field)
	_tower(field)
	_venue(field)
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _shipped(field: Dictionary) -> void:
	var loaded: Dictionary = Track.load_file(SHIPPED)
	_check("RACE-01 the shipped practice oval loads under the closed contract", loaded.ok and loaded.sha256.length() == 64,
		str(loaded.errors))
	if not loaded.ok:
		return
	var prepared: Dictionary = Track.prepare(loaded.track, field, _flat)
	_check("RACE-01 it prepares on the default field and its ground", prepared.ok, str(prepared.errors))
	if not prepared.ok:
		return
	var course: Dictionary = prepared.course
	var gates: Array = course.gates
	var geometry: bool = gates.size() == 6 and course.laps == 3 and course.ruleset.id == Track.RULESET
	var nearest_pilot := INF
	var area := 0.0
	var longest := 0.0
	for i in gates.size():
		var gate: Dictionary = gates[i]
		var c: PackedFloat64Array = gate.c
		var n: PackedFloat64Array = gate.n
		var u: PackedFloat64Array = gate.u
		geometry = geometry and gate.w == 1.5 and gate.h == 1.0 and c[2] == -2.0 and n[2] == 0.0 \
			and absf(n[0] * n[0] + n[1] * n[1] - 1.0) < 1e-15 and absf(n[0] * u[0] + n[1] * u[1]) < 1e-15 \
			and absf(u[0] * n[1] - u[1] * n[0] + 1.0) < 1e-15
		nearest_pilot = minf(nearest_pilot, sqrt(c[0] * c[0] + c[1] * c[1]))
		var next: PackedFloat64Array = gates[(i + 1) % gates.size()].c
		area += c[1] * next[0] - next[1] * c[0] # shoelace with x = east, y = north
		longest = maxf(longest, sqrt((next[0] - c[0]) * (next[0] - c[0]) + (next[1] - c[1]) * (next[1] - c[1])))
	_check("the course: six upright 3 m x 2 m apertures, centres 2 m above ground, u is right of travel", geometry)
	_check("the oval is closed and anticlockwise seen from above", area > 0.0, "signed area %.1f m2" % (0.5 * area))
	_check("straights of 25 to 35 m and every gate at least 12 m from the pilot station",
		longest >= 25.0 and longest <= 35.0 and nearest_pilot >= 12.0, "longest %.2f m nearest %.2f m" % [longest, nearest_pilot])
	var pad: Dictionary = course.pad
	var first: Dictionary = gates[0]
	var setback: float = first.n[0] * (pad.north - first.c[0]) + first.n[1] * (pad.east - first.c[1])
	var from_rotor_pad := Vector2(pad.north - float(field.rotorcraft_pad.north), pad.east - float(field.rotorcraft_pad.east))
	_check("the pad lies at least 4 m behind gate 0, away from the field's rotorcraft pad", setback <= -4.0
		and from_rotor_pad.length() > 10.0, "setback %.2f m" % setback)
	print("    minimum horizontal clearance to field objects: %.3f m (%s)" % [course.min_object_clearance_m, course.nearest_object])
	_check("every gate frame and the pad zone clear the listed field objects by at least 1 m",
		course.min_object_clearance_m >= Track.OBJECT_CLEARANCE_M)
	var again: Dictionary = Track.prepare(Track.load_file(SHIPPED).track, field, _flat)
	_check("preparation is deterministic", again.ok and again.course.identity == course.identity
		and var_to_bytes(again.course) == var_to_bytes(course))


## A mutated copy of the shipped document must refuse with an error naming `fragment`.
func _refuses(label: String, raw: Dictionary, fragment: String) -> void:
	var loaded: Dictionary = Track.load_document(raw, "mutation")
	var joined: String = "; ".join(loaded.errors)
	_check("RACE-01 refuses %s" % label, not loaded.ok and joined.contains(fragment), joined.left(220))


func _refusals(field: Dictionary) -> void:
	var raw: Dictionary = _raw()
	var m: Dictionary = raw.duplicate(true)
	m.extra = 1
	_refuses("an unknown top-level key", m, "track.extra: unknown key")
	m = raw.duplicate(true)
	m.gates[3].colour = "red"
	_refuses("an unknown gate key", m, "gates[3].colour: unknown key")
	m = raw.duplicate(true)
	m.gates[2].id = m.gates[0].id
	_refuses("a duplicate gate id", m, "gates[2].id: duplicate")
	m = raw.duplicate(true)
	m.gates[2].tilt_deg = 15.0
	_refuses("a tilted gate", m, "gates[2].tilt_deg: unsupported")
	m = raw.duplicate(true)
	m.gates[1].roll = 0.0
	_refuses("any roll request, even zero", m, "gates[1].roll: unsupported")
	m = raw.duplicate(true)
	m.gates[0].width_m = 6.5
	_refuses("a width above 6 m", m, "gates[0].width_m")
	m = raw.duplicate(true)
	m.gates[0].width_m = 0.8
	_refuses("a width below 1 m", m, "gates[0].width_m")
	m = raw.duplicate(true)
	m.gates[4].height_m = 4.5
	_refuses("a height above 4 m", m, "gates[4].height_m")
	m = raw.duplicate(true)
	m.gates[4].center_height_m = 1.2
	_refuses("a lower edge below 0.3 m", m, "gates[4]: lower aperture edge")
	m = raw.duplicate(true)
	m.gates[1].east_m = 47.0
	_refuses("consecutive gates closer than 6 m", m, "gates[0]->gates[1]: centres")
	m = raw.duplicate(true)
	m.pad = {north_m = 51.0, east_m = 71.5, heading_deg = 270.0}
	_refuses("a pad on a gate's aperture plane", m, "within 1.0 m of gates[3]")
	m = raw.duplicate(true)
	m.pad.east_m = 40.0
	_refuses("a pad less than 4 m behind gate 0", m, "pad: -3.000 m from gates[0]")
	m = raw.duplicate(true)
	m.ruleset = "openrc-local-race-v2"
	_refuses("another ruleset", m, "ruleset:")
	m = raw.duplicate(true)
	m.laps = 2
	_refuses("a lap count other than the ruleset's three", m, "laps:")
	m = raw.duplicate(true)
	m.gates[0].north_m = NAN
	_refuses("a NaN coordinate", m, "gates[0].north_m: must be finite")
	m = raw.duplicate(true)
	m.gates[0].heading_deg = "90"
	_refuses("a string where a number is required", m, "gates[0].heading_deg: expected a number")
	m = raw.duplicate(true)
	m.gates[5].erase("height_m")
	_refuses("a missing key", m, "gates[5].height_m: missing")
	m = raw.duplicate(true)
	m.gates = [m.gates[0], m.gates[1]]
	_refuses("fewer than three gates", m, "gates: 2 gates")
	m = raw.duplicate(true)
	m.gates[2].heading_deg = 180.0
	_refuses("an inconsistent travel direction", m, "inconsistent direction")
	m = raw.duplicate(true)
	m.origin = "runway"
	_refuses("an unsupported origin", m, "origin:")
	m = raw.duplicate(true)
	m.format = "openrc-race-track v2"
	_refuses("another format", m, "format:")
	m = raw.duplicate(true)
	m.field_id = "elsewhere"
	var loaded: Dictionary = Track.load_document(m)
	var prepared: Dictionary = Track.prepare(loaded.track, field, _flat)
	_check("RACE-01 a track for another field refuses at preparation", loaded.ok and not prepared.ok
		and "; ".join(prepared.errors).contains("field_id"), "; ".join(prepared.errors))
	var sloped := func(_north: float, east: float) -> PackedFloat64Array: return PackedFloat64Array([east, 0.0, 1.0])
	prepared = Track.prepare(Track.load_document(raw).track, field, sloped)
	_check("RACE-01 a post base on rising ground that breaks the lower-edge clearance refuses", not prepared.ok
		and "; ".join(prepared.errors).contains("at a post"), "; ".join(prepared.errors).left(200))
	m = raw.duplicate(true)
	# Back beside the pilot station, 6 m south of where the oval first stood: onto the field's listed objects.
	for gate: Dictionary in m.gates:
		gate.north_m = float(gate.north_m) - 28.0
		gate.east_m = float(gate.east_m) - 38.0
	m.pad.north_m = 0.0
	m.pad.east_m = 0.0
	prepared = Track.prepare(Track.load_document(m).track, field, _flat)
	_check("RACE-01 a course moved onto listed field objects refuses with the object named", not prepared.ok
		and "; ".join(prepared.errors).contains("field object"), "; ".join(prepared.errors).left(200))
	_check("an empty or non-object document refuses", not Track.load_document([]).ok and not Track.load_document({}).ok)


func _identity(field: Dictionary) -> void:
	var raw: Dictionary = _raw()
	var base: Dictionary = Track.prepare(Track.load_document(raw).track, field, _flat)
	var edited: Dictionary = raw.duplicate(true)
	edited.gates[4].east_m = 43.5
	var moved: Dictionary = Track.prepare(Track.load_document(edited).track, field, _flat)
	var renamed: Dictionary = raw.duplicate(true)
	renamed.gates[1].id = "south-east-b"
	var relabelled: Dictionary = Track.prepare(Track.load_document(renamed).track, field, _flat)
	var other_field: Dictionary = field.duplicate(true)
	other_field.id = "default-copy"
	var other_raw: Dictionary = raw.duplicate(true)
	other_raw.field_id = "default-copy"
	var on_other: Dictionary = Track.prepare(Track.load_document(other_raw).track, other_field, _flat)
	var raised := func(_north: float, _east: float) -> PackedFloat64Array: return PackedFloat64Array([0.25, 0.0, 0.0])
	var lifted: Dictionary = Track.prepare(Track.load_document(raw).track, field, raised)
	_check("RACE-03 the course identity changes with any gate edit", base.ok and moved.ok and relabelled.ok
		and moved.course.identity != base.course.identity and relabelled.course.identity != base.course.identity)
	_check("RACE-03 the course identity changes with the field id and with the resolved ground", on_other.ok and lifted.ok
		and on_other.course.identity != base.course.identity and lifted.course.identity != base.course.identity)
	_check("the course tag is the identity's first 52 bits as an exact float64", base.course.tag == float(base.course.identity.substr(0, 13).hex_to_int())
		and base.course.tag < 4503599627370496.0 and moved.course.tag != base.course.tag)


func _frames(field: Dictionary) -> void:
	var course: Dictionary = Track.prepare(Track.load_file(SHIPPED).track, field, _flat).course
	var surround := true
	var clear := true
	var detail := ""
	for gate: Dictionary in course.gates:
		var boxes: Array = gate.frames
		if boxes.size() != 4:
			surround = false
			continue
		var local: Array = []
		for box: Dictionary in boxes:
			var d := PackedFloat64Array([box.north - gate.c[0], box.east - gate.c[1], box.down - gate.c[2]])
			var du: float = gate.u[0] * d[0] + gate.u[1] * d[1] + gate.u[2] * d[2]
			var dv: float = gate.v[0] * d[0] + gate.v[1] * d[1] + gate.v[2] * d[2]
			var dn: float = gate.n[0] * d[0] + gate.n[1] * d[1] + gate.n[2] * d[2]
			local.append({u0 = du - box.half_z, u1 = du + box.half_z, v0 = dv - box.half_down, v1 = dv + box.half_down,
				n = dn, heading = box.heading_deg, ground = box.down + box.half_down})
			# An open-aperture intrusion needs overlap on BOTH in-plane axes.
			if du - box.half_z < gate.w - 1e-9 and du + box.half_z > -gate.w + 1e-9 					and dv - box.half_down < gate.h - 1e-9 and dv + box.half_down > -gate.h + 1e-9:
				clear = false
				detail = "%s intrudes" % gate.id
		var w: float = gate.w
		var h: float = gate.h
		var left: Dictionary = local[0]
		var right: Dictionary = local[1]
		var top: Dictionary = local[2]
		var bottom: Dictionary = local[3]
		surround = surround and absf(left.u1 + w) < 1e-12 and absf(right.u0 - w) < 1e-12 \
			and absf(top.v1 + h) < 1e-12 and absf(bottom.v0 - h) < 1e-12 \
			and left.v0 <= -h - Track.FRAME_SECTION_M + 1e-12 and absf(left.ground) < 1e-12 and absf(right.ground) < 1e-12 \
			and top.u0 <= -w - Track.FRAME_SECTION_M + 1e-12 and top.u1 >= w + Track.FRAME_SECTION_M - 1e-12 \
			and bottom.u0 <= -w and bottom.u1 >= w
		for item: Dictionary in local:
			surround = surround and absf(item.n) < 1e-12 and item.heading == gate.heading_deg
	_check("RACE-01 the four frame boxes (posts to the ground, top and bottom bars) surround each aperture exactly",
		surround and course.frames.size() == 4 * course.gates.size())
	_check("RACE-01 no frame box intrudes into an open aperture", clear, detail)


## DR-28/32 second shipped course: the tower sprint loads and prepares on the default field, varies its gate heights
## and sizes (a low hurdle, a raised tower gate), and every frame box stays out of every aperture.
func _tower(field: Dictionary) -> void:
	var loaded: Dictionary = Track.load_file(TOWER)
	_check("DR-28 the tower sprint loads under the closed contract", loaded.ok, str(loaded.errors))
	if not loaded.ok:
		return
	var prepared: Dictionary = Track.prepare(loaded.track, field, _flat)
	_check("DR-28 the tower sprint prepares on the default field", prepared.ok, str(prepared.errors))
	if not prepared.ok:
		return
	var gates: Array = prepared.course.gates
	var lowest := INF
	var highest := -INF
	var widths := {}
	for gate: Dictionary in gates:
		lowest = minf(lowest, -float(gate.c[2]) - float(gate.h))
		highest = maxf(highest, -float(gate.c[2]))
		widths[gate.width_m] = true
	_check("DR-28 the tower sprint varies height and size: a low hurdle, a raised tower, three gate widths",
		gates.size() == 7 and lowest < 0.4 and highest > 4.0 and widths.size() == 3 and prepared.course.frames.size() == 28,
		"lowest edge %.2f m, highest centre %.2f m, widths %s" % [lowest, highest, widths.keys()])


## RC-TRACK venue: every shipped course keeps its gate frames and its pad off the airplane runway and outside the RC car
## circuit (its lane, shoulders, banks, access lane and dressing), with a margin, so the field reads as three areas.
func _venue(field: Dictionary) -> void:
	var circuit: Dictionary = AirfieldTrack.load_default()
	_check("RC-TRACK the club circuit loads", circuit.ok)
	if not circuit.ok:
		return
	var bounds: PackedFloat64Array = AirfieldTrack.bounds_ne(circuit.track)
	var runway: Dictionary = {}
	for surface: Dictionary in field.surfaces:
		if str(surface.id) == str(field.runway):
			runway = surface
	var runway_north := [float(runway.center_north) - 0.5 * float(runway.width_north_south),
		float(runway.center_north) + 0.5 * float(runway.width_north_south)]
	var runway_east := [float(runway.center_east) - 0.5 * float(runway.length_east_west),
		float(runway.center_east) + 0.5 * float(runway.length_east_west)]
	for path: String in [SHIPPED, TOWER]:
		var prepared: Dictionary = Track.prepare(Track.load_file(path).track, field, _flat)
		if not prepared.ok:
			_check("RC-TRACK %s prepares" % path.get_file(), false, str(prepared.errors))
			continue
		var circuit_gap := INF
		var runway_gap := INF
		var points: Array = []
		for box: Dictionary in prepared.course.frames:
			var reach: float = maxf(float(box.half_x), float(box.half_z))
			points.append([float(box.north), float(box.east), reach])
		points.append([float(prepared.course.pad.north), float(prepared.course.pad.east), 1.0])
		for point: Array in points:
			circuit_gap = minf(circuit_gap, _rect_gap(point, bounds[0], bounds[1], bounds[2], bounds[3]))
			# Its dressing (signs, tape, tyres) stands partly outside the surface bounds.
			for item: Dictionary in AirfieldTrack.dressing(circuit.track):
				var half: float = 0.5 * maxf(float(item.width), float(item.length))
				circuit_gap = minf(circuit_gap, _rect_gap(point, float(item.north) - half, float(item.north) + half,
					float(item.east) - half, float(item.east) + half))
			runway_gap = minf(runway_gap, _rect_gap(point, runway_north[0], runway_north[1], runway_east[0], runway_east[1]))
		_check("RC-TRACK %s stays 5 m clear of the RC car circuit and the runway" % prepared.course.track_id,
			circuit_gap >= 5.0 and runway_gap >= 5.0, "circuit %.2f m, runway %.2f m" % [circuit_gap, runway_gap])


## Horizontal gap (m) from a disc [north, east, radius] to a north/east rectangle (negative inside).
func _rect_gap(point: Array, north_min: float, north_max: float, east_min: float, east_max: float) -> float:
	var dn: float = maxf(north_min - float(point[0]), float(point[0]) - north_max)
	var de: float = maxf(east_min - float(point[1]), float(point[1]) - east_max)
	var outside: float = Vector2(maxf(dn, 0.0), maxf(de, 0.0)).length()
	return (outside if dn > 0.0 or de > 0.0 else maxf(dn, de)) - float(point[2])
