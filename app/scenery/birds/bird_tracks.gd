## SC-BIRD-05: closed arc-line circuits for birds, compiled on the CPU (float64) and evaluated by sky_birds.gdshader.
## A motif (lines and arcs, each with a speed or a duration and an optional climb) is repeated `repeats` times, each
## copy rotated by the motif's net turn. When that net turn is 2*pi/repeats (mod 2*pi) the circuit closes exactly by
## symmetry, and a full extra circle anywhere keeps it closed, so thermal circling can be inserted freely. Headings
## join tangentially by construction. The period is rescaled to 1024/k s so the shader clock wraps seamlessly.
## Local frame: x east, y north, z up (metres); headings are math angles from east, counter-clockwise.
extends RefCounted

const ANCHORS: Array[String] = ["centre", "first_arc_centre"]
const CLOCK_S := 1024.0
const MAX_TIME_SCALE_CHANGE := 0.08
const CLOSE_TOLERANCE_M := 1e-6
const SAMPLE_STEP_S := 0.25
const MIN_SPEED := 2.0 # m/s; slower is hovering, not a circuit (a kestrel's hover will be its own behaviour)
const MAX_SPEED := 40.0 # m/s; swift dives reach ~23 m/s (Hedrick et al. 2018)
const MIN_SEGMENT_S := 0.25 # so the shader's +-0.8 s bank window spans at most 8 segments
const BANK_STEP_S := 0.8 # sky_birds.gdshader BANK_STEP_S
const MAX_MOTIF_SEGMENTS := 16 # sky_birds.gdshader MAX_MOTIF_SEGMENTS
const MAX_CLIMB_RATE := 10.0 # m/s


## Returns {ok, errors, track: {segments, period, time_scale, bbox_min, bbox_max, length}}.
## Each segment: {x, y, h, t, kappa, v, z, vz, duration}; kappa = signed curvature (1/m, 0 for a line).
static func compile(motif: Variant, repeats: int, heading: float, anchor: String) -> Dictionary:
	var errors: Array[String] = []
	if typeof(motif) != TYPE_ARRAY or (motif as Array).is_empty():
		return {ok = false, errors = ["motif must be a non-empty array"]}
	if repeats < 1:
		return {ok = false, errors = ["repeats must be at least 1"]}
	if not ANCHORS.has(anchor):
		return {ok = false, errors = ["unknown anchor '%s'" % anchor]}
	if (motif as Array).size() > MAX_MOTIF_SEGMENTS:
		return {ok = false, errors = ["a motif has at most %d segments (sky_birds.gdshader)" % MAX_MOTIF_SEGMENTS]}
	var parts: Array[Dictionary] = []
	for i: int in (motif as Array).size():
		var p: Dictionary = _part(i, (motif as Array)[i], errors)
		if not p.is_empty():
			parts.append(p)
	if not errors.is_empty():
		return {ok = false, errors = errors}
	if anchor == "first_arc_centre" and parts[0].kappa == 0.0:
		return {ok = false, errors = ["anchor first_arc_centre needs an arc first"]}
	var x := 0.0
	var y := 0.0
	if anchor == "first_arc_centre":
		# The first arc's centre sits at the origin: start on the circle, on the side its turn needs.
		x = sin(heading) / parts[0].kappa
		y = -cos(heading) / parts[0].kappa
	var h := heading
	var z := 0.0
	var t := 0.0
	var segments: Array[Dictionary] = []
	var length := 0.0
	for k: int in repeats:
		for p: Dictionary in parts:
			var seg := {x = x, y = y, h = h, t = t, kappa = p.kappa, v = p.length / p.duration, z = z,
				vz = p.climb / p.duration, duration = p.duration}
			segments.append(seg)
			var end: Array[float] = _advance(x, y, h, p.kappa, p.length)
			x = end[0]
			y = end[1]
			h = end[2]
			z += p.climb
			t += p.duration
			length += p.length
	var x0: float = segments[0].x
	var y0: float = segments[0].y
	var gap := Vector2(x - x0, y - y0).length()
	var turn_error := absf(_wrap_angle(h - heading))
	if gap > CLOSE_TOLERANCE_M * maxf(1.0, length) or turn_error > 1e-9:
		errors.append("circuit does not close (gap %.6f m, heading %.6f rad): the motif's net turn must be 360/%d deg" % [
			gap, turn_error, repeats])
	if absf(z) > 1e-9:
		errors.append("circuit does not close vertically (net climb %.6f m)" % z)
	var cycles: float = roundf(CLOCK_S / t)
	if cycles < 1.0:
		errors.append("period %.2f s is longer than the %d s clock" % [t, int(CLOCK_S)])
	if not errors.is_empty():
		return {ok = false, errors = errors}
	var period: float = CLOCK_S / cycles
	var scale: float = period / t
	if absf(scale - 1.0) > MAX_TIME_SCALE_CHANGE:
		return {ok = false, errors = ["period %.2f s needs a time scale of %.3f to divide 1024 s (limit %.2f)" % [
			t, scale, MAX_TIME_SCALE_CHANGE]]}
	for seg: Dictionary in segments:
		seg.t *= scale
		seg.duration *= scale
		seg.v /= scale
		seg.vz /= scale
	var track := {segments = segments, period = period, time_scale = scale, length = length, repeats = repeats}
	var bounds: Array[Vector3] = _bounds(track)
	if anchor == "centre":
		var shift: Vector3 = (bounds[0] + bounds[1]) * 0.5
		for seg: Dictionary in segments:
			seg.x -= shift.x
			seg.y -= shift.y
		bounds = _bounds(track)
	track.bbox_min = bounds[0]
	track.bbox_max = bounds[1]
	return {ok = true, errors = errors, track = track}


## Position [x, y, z] at local time t (any real; the circuit repeats every period).
static func evaluate(track: Dictionary, t: float) -> Array[float]:
	var tt: float = fposmod(t, float(track.period))
	var seg: Dictionary = track.segments[segment_index(track, tt)]
	var d: float = tt - float(seg.t)
	var end: Array[float] = _advance(seg.x, seg.y, seg.h, seg.kappa, float(seg.v) * d)
	return [end[0], end[1], float(seg.z) + float(seg.vz) * d]


## What sky_birds.gdshader computes for the attitude: speed, climb, the analytic heading and the bank from the
## lateral acceleration averaged with a triangle kernel over +-BANK_STEP_S (exactly integrated over the segments, as
## the position's second difference over +-BANK_STEP_S gives). Returns {speed, horizontal_speed, climb, heading,
## lateral_acceleration, bank}; bank > 0 turning left.
static func kinematics(track: Dictionary, t: float) -> Dictionary:
	var tt: float = fposmod(t, float(track.period))
	var index: int = segment_index(track, tt)
	var seg: Dictionary = track.segments[index]
	var d: float = tt - float(seg.t)
	var v: float = seg.v
	var vz: float = seg.vz
	var lateral: float = lateral_acceleration(track, tt)
	return {speed = sqrt(v * v + vz * vz), horizontal_speed = v, climb = vz,
		heading = float(seg.h) + float(seg.kappa) * v * d, lateral_acceleration = lateral, bank = atan2(lateral, 9.81)}


## The active segment's index at local time tt in [0, period): the repeat directly, then a search in its motif.
static func segment_index(track: Dictionary, tt: float) -> int:
	var segments: Array = track.segments
	var repeats: int = track.get("repeats", 1)
	var motif: int = segments.size() / repeats
	var base: int = mini(int(tt / (float(track.period) / repeats)), repeats - 1) * motif
	var index := base
	for i: int in range(1, motif):
		if float(segments[base + i].t) > tt:
			break
		index = base + i
	return index


## Triangle-kernel average of v^2 * curvature over [tt - BANK_STEP_S, tt + BANK_STEP_S] (sky_birds.gdshader
## smoothed_lateral()).
static func lateral_acceleration(track: Dictionary, tt: float) -> float:
	var segments: Array = track.segments
	var period: float = track.period
	var w0: float = tt - BANK_STEP_S
	var w1: float = tt + BANK_STEP_S
	var offset: float = -period if w0 < 0.0 else 0.0
	var index: int = segment_index(track, w0 - offset)
	var lateral := 0.0
	for k: int in segments.size() + 2:
		var seg: Dictionary = segments[index]
		var start: float = float(seg.t) + offset
		var end: float = (float(segments[index + 1].t) if index + 1 < segments.size() else period) + offset
		var lo: float = maxf(start, w0)
		var hi: float = minf(end, w1)
		if hi > lo:
			lateral += float(seg.kappa) * float(seg.v) * float(seg.v) * (_kernel_cdf(hi - tt) - _kernel_cdf(lo - tt))
		if end >= w1:
			break
		index += 1
		if index == segments.size():
			index = 0
			offset += period
	return lateral


static func _kernel_cdf(x: float) -> float:
	var h := BANK_STEP_S
	x = clampf(x, -h, h)
	return (x + h) * (x + h) / (2.0 * h * h) if x <= 0.0 else 1.0 - (h - x) * (h - x) / (2.0 * h * h)


## Shader tables for one MultiMesh: seg_a = (x, y, h, t0), seg_b = (kappa, v, z0, vz), track_info = (first, count,
## period, repeats). Every repeat of the motif lasts period / repeats, so the shader finds the repeat directly and
## searches only its motif's segments. Headings are wrapped to [-pi, pi) so float32 keeps their precision.
static func pack(tracks: Array) -> Dictionary:
	var seg_a := PackedVector4Array()
	var seg_b := PackedVector4Array()
	var info := PackedVector4Array()
	for track: Dictionary in tracks:
		info.append(Vector4(seg_a.size(), (track.segments as Array).size(), float(track.period), float(track.repeats)))
		for s: Dictionary in track.segments:
			seg_a.append(Vector4(s.x, s.y, _wrap_angle(s.h), s.t))
			seg_b.append(Vector4(s.kappa, s.v, s.z, s.vz))
	return {seg_a = seg_a, seg_b = seg_b, track_info = info}


static func _part(i: int, raw: Variant, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("segment %d is not an object" % i)
		return {}
	var d: Dictionary = raw
	var length := 0.0
	var kappa := 0.0
	if d.has("line") == d.has("radius"):
		errors.append("segment %d needs exactly one of line or radius" % i)
		return {}
	if d.has("line"):
		if not _positive(d.line):
			errors.append("segment %d: line must be a positive length" % i)
			return {}
		length = float(d.line)
	else:
		if not _positive(d.radius) or not _number(d.get("turn")) or float(d.get("turn", 0.0)) == 0.0:
			errors.append("segment %d: an arc needs a positive radius and a non-zero turn (deg)" % i)
			return {}
		length = deg_to_rad(absf(float(d.turn))) * float(d.radius)
		kappa = signf(float(d.turn)) / float(d.radius)
	if d.has("speed") == d.has("duration"):
		errors.append("segment %d needs exactly one of speed or duration" % i)
		return {}
	var given: Variant = d.get("speed", d.get("duration"))
	if not _positive(given):
		errors.append("segment %d: speed or duration must be a positive number" % i)
		return {}
	var duration: float = length / float(given) if d.has("speed") else float(given)
	var speed: float = length / duration
	# The same limits whichever was given, so a short duration cannot hide an impossible speed.
	if duration < MIN_SEGMENT_S or speed < MIN_SPEED or speed > MAX_SPEED:
		errors.append("segment %d: %.3f m/s over %.3f s, outside [%s, %s] m/s or shorter than %s s" % [
			i, speed, duration, MIN_SPEED, MAX_SPEED, MIN_SEGMENT_S])
		return {}
	var climb: Variant = d.get("climb", 0.0)
	if not _number(climb) or absf(float(climb)) / duration > MAX_CLIMB_RATE:
		errors.append("segment %d: climb must be a number with a rate within %s m/s" % [i, MAX_CLIMB_RATE])
		return {}
	return {length = length, kappa = kappa, duration = duration, climb = float(climb)}


## End [x, y, heading] after `s` metres from (x, y, h) with curvature kappa.
static func _advance(x: float, y: float, h: float, kappa: float, s: float) -> Array[float]:
	if kappa == 0.0:
		return [x + s * cos(h), y + s * sin(h), h]
	var h2: float = h + kappa * s
	return [x + (sin(h2) - sin(h)) / kappa, y - (cos(h2) - cos(h)) / kappa, h2]


static func _bounds(track: Dictionary) -> Array[Vector3]:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var steps: int = int(ceil(float(track.period) / SAMPLE_STEP_S))
	for j: int in steps + 1:
		var p: Array[float] = evaluate(track, j * SAMPLE_STEP_S)
		var v := Vector3(p[0], p[1], p[2])
		lo = lo.min(v)
		hi = hi.max(v)
	return [lo, hi]


static func _wrap_angle(a: float) -> float:
	return fposmod(a + PI, TAU) - PI


static func _number(v: Variant) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v))


static func _positive(v: Variant) -> bool:
	return _number(v) and float(v) > 0.0
