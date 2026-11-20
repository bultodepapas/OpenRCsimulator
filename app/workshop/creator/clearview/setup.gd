extends RefCounted
## One reviewable flight setup for an admitted ClearView visual (import closeout, packet 2).
##
## ClearView render models share one documented frame: metres, nose along -X, up along +Y and the
## wingspan along Z. That dialect rule fixes the orientation and units. The wing leading edge at the
## centreline is not declared anywhere, so it is estimated from the render geometry and labelled as
## an estimate. Nothing here reads ClearView flight coefficients: the flight configuration stays an
## independent OpenRC estimate that the player chooses explicitly (Authoring.apply_clearview_setup).
const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Placement := preload("res://workshop/creator/placement.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")
const Installation := preload("res://workshop/creator/source_installation.gd")

const RULE := "clearview-render-frame-v1"
const NOSE_AXIS := "-x"
const UP_AXIS := "+y"
const UNITS := "m"
## Span stations (fractions of the half-span) cut for the wing leading edge: outboard of the fuselage
## and landing gear, inboard of wing-tip details. The sweep extrapolation to the centreline is limited.
const BAND_INNER := 0.35
const BAND_OUTER := 0.65
const MAX_SWEEP_SHIFT := 0.15
## Realism audit 2026-11-17 (wing planform): chords and dihedral are measured at these stations, then a
## straight line through them gives the root and tip chord; a station whose chord is far from the others
## (an engine nacelle, a wing-tip tank) is ignored. Without a measurement the template AR 5 stays.
const PLANFORM_STATIONS := [0.3, 0.45, 0.6, 0.75]
## A wing section is the run of crossings at one height (thickness and camber within this fraction of the
## half-span) whose gaps along x stay under PLANFORM_GAP of the half-span: a low-polygon wing is crossed
## only at its leading edge, trailing edge and a diagonal, while the tailplane starts far further aft.
const PLANFORM_LAYER := 0.06
const PLANFORM_GAP := 0.35
## Biplane: a second wing layer at every station, each at least this share of the main chord. The pair is
## estimated as one equivalent monoplane wing of BIPLANE_AREA_FACTOR times the main wing's area
## (two wings minus the mutual interference of a typical gap; Munk's equivalent monoplane).
const BIPLANE_MIN_SHARE := 0.5
const BIPLANE_AREA_FACTOR := 1.7
const BIPLANE := "This biplane is estimated as one equivalent wing with the lifting area of both wings."
const PARK_FLYER := "Under 1.45 m it is estimated as a foam park flyer: light foam structure, 9 g servos and a 3S electric power system."
## A size fitted to the package's wingspan domain stays this fraction inside its bound.
const FIT_MARGIN := 0.02
const SCALED := "This model is %s m across; the estimated OpenRC configuration supports %s to %s m. It will fly as a %s m version (%s %% of its size): a different configuration, not the original size."
const SCALED_DONE := "It flies as a %s m version of the model."
const NO_PROPELLER := "No propeller was found in this model. It is estimated as an electric pusher park jet, with the propeller in a slot behind the wing. Jet and ducted-fan power are not modelled."
const MIN_HALF_SPAN_M := 0.1
## Furthest a grown model may reach from its datum: the definition allows 2 m, less room for a spinner.
const MAX_REACH_M := 1.85
const MAX_HALF_SPAN_M := 10.0
const MAX_VERTICES := 2_000_000
const UNAVAILABLE := "The wing leading edge could not be found in this ClearView model. Mark it in Orient and size."
const CONFIRM_FRAME := "Orientation and units follow the ClearView model frame (metres, nose forward along -X, up along +Y). The wing leading edge is estimated from the model shape; check it in Orient and size."
const CONFIRM_ESTIMATES := "Every empty dimension, mass, battery and control value is filled with an OpenRC estimate scaled to this model and marked Estimated. Values you entered are kept."
const ELEVONS := "This model uses elevons (combined aileron and elevator surfaces). The estimated OpenRC configuration supports separate ailerons, elevator and rudder only."
const HELICOPTER_TYPE := 0
const HELICOPTER := "This is a ClearView helicopter, so the aeroplane setup does not apply. Use Fly as a helicopter: it flies with the X-Cell .60 reference helicopter physics and this model's appearance only."
const DONE := "The model is set up with an estimated OpenRC configuration. Review the estimates, then test fly."


## {placement, units, rule, estimated_datum, half_span_m, source_span_m, flown_span_m, scaled} for an
## admitted ClearView GLB, or a refusal. `span_range` [min, max] (metres) is the estimated package's
## wingspan domain, or a list of such ranges (size classes, smallest first; `range_index` names the one
## used): a model outside it is proposed at the nearest supported size, as an explicitly scaled
## configuration (`scaled`), never silently. Without a range the source size is kept.
static func propose(source: InspectedSource, span_range: Array = []) -> Dictionary:
	if not Installation.required(source):
		return R.fail(R.SOURCE_UNSUPPORTED, "Automatic setup is only available for converted ClearView models.", "source", "import")
	if _model_type(source) == HELICOPTER_TYPE:
		return R.fail(R.UNSUPPORTED_CAPABILITY, HELICOPTER, "source", "import")
	var points: Dictionary = _points(source)
	if not points.ok:
		return points
	if points.mixed_controls:
		return R.fail(R.UNSUPPORTED_CAPABILITY, ELEVONS, "source", "import")
	var datum: Dictionary = leading_edge(points.value)
	if not datum.ok:
		return datum
	var span := 2.0 * float(datum.value.half_span_m)
	var flown := span
	# Several ranges (size classes, smallest first): the one containing the span, else the nearest.
	var ranges: Array = span_range if not span_range.is_empty() and span_range[0] is Array else [span_range]
	var range_index := -1
	var distance := INF
	for index: int in ranges.size():
		var candidate: Array = ranges[index]
		if candidate.size() != 2 or not float(candidate[0]) > 0.0 or not float(candidate[1]) > float(candidate[0]):
			continue
		var off := maxf(float(candidate[0]) - span, span - float(candidate[1]))
		if off < distance:
			distance = off
			range_index = index
	var chosen: Array = ranges[range_index] if range_index >= 0 else []
	if not chosen.is_empty() and (span < float(chosen[0]) or span > float(chosen[1])):
		flown = clampf(span, float(chosen[0]) * (1.0 + FIT_MARGIN), float(chosen[1]) * (1.0 - FIT_MARGIN))
		# A model grown to the minimum span is grown only as far as its body still fits the definition's
		# lengths (a long jet would otherwise reach more than 2 m ahead of or behind its wing).
		var reach := _reach(points.value, datum.value.datum)
		if flown > span and reach > 0.0:
			flown = clampf(MAX_REACH_M * span / reach, span, flown)
	var scale: float = float(Placement.UNITS[UNITS]) * flown / span
	var scaled := absf(flown - span) > 1e-9
	var placement := {nose_axis = NOSE_AXIS, up_axis = UP_AXIS, unit_scale = scale, datum = datum.value.datum}
	if not Placement.resolve(placement).ok:
		return R.fail(R.DATUM_UNRESOLVED, UNAVAILABLE, "placement/datum", Placement.STEP)
	var result := {placement = placement, units = "" if scaled else UNITS, rule = RULE, estimated_datum = true,
		half_span_m = datum.value.half_span_m, source_span_m = span, flown_span_m = flown, scaled = scaled,
		propeller_found = points.propeller_found, range_index = range_index, span_range = chosen.duplicate()}
	result.merge(planform(points.value, float(datum.value.half_span_m)))
	return R.ok(result)


## The measured wing planform in source units: {root_chord_m, tip_chord_m, dihedral_deg, biplane}, or {}
## when the wing sections cannot be read. Chords are clamped to the estimated airframe package's taper
## (0.6-1) and aspect ratio (4-7) range, dihedral to 0-8 degrees: shapes outside it stay estimates.
static func planform(triangles: PackedFloat64Array, half_span: float) -> Dictionary:
	if not is_finite(half_span) or half_span < MIN_HALF_SPAN_M:
		return {}
	var rows: Array = [] # [station fraction, chord, height, second-layer chord, second-layer height]
	for fraction: float in PLANFORM_STATIONS:
		var section := _section(triangles, fraction * half_span, half_span)
		if not section.is_empty():
			rows.append([fraction, section.chord, section.y, section.second, section.second_y])
	if rows.size() < 2:
		return {}
	var chords: Array = []
	for row: Array in rows:
		chords.append(row[1])
	chords.sort()
	var median: float = chords[chords.size() / 2]
	var kept: Array = []
	for row: Array in rows:
		if float(row[1]) <= median * 1.6 and float(row[1]) >= median / 1.6:
			kept.append(row)
	# More than one disagreeing station means the cuts did not find one wing (a canard, nacelles or a
	# tailplane at the wing's height): the template planform is kept rather than a doubtful measurement.
	if kept.size() < 2 or kept.size() < rows.size() - 1:
		return {}
	# Least-squares line chord(f) over the kept stations, f = fraction of the half-span.
	var chord_line := _line(kept, 1)
	if chord_line.is_empty():
		return {}
	var root: float = chord_line.at_zero
	var tip: float = chord_line.at_zero + chord_line.slope
	# Dihedral from the outboard stations only: the inboard cut often meets the fuselage, an intake or a
	# wing-root fairing at another height.
	var outboard: Array = kept.filter(func(row: Array) -> bool: return float(row[0]) >= DIHEDRAL_FROM)
	var height_line := _line(outboard if outboard.size() >= 2 else kept, 2)
	var height_slope: float = height_line.get("slope", 0.0)
	# Biplane: at least three stations, each with a second wing of comparable chord stacked a plausible
	# gap away, always on the same side of the main wing.
	var biplane := kept.size() >= 3
	var side := 0.0
	for row: Array in kept:
		var stacked := float(row[4]) - float(row[2])
		biplane = biplane and float(row[3]) >= BIPLANE_MIN_SHARE * float(row[1]) \
			and absf(stacked) >= BIPLANE_GAP[0] * float(row[1]) and absf(stacked) <= BIPLANE_GAP[1] * float(row[1]) \
			and (side == 0.0 or signf(stacked) == side)
		side = signf(stacked)
	if not is_finite(root) or not is_finite(tip) or root <= 0.0:
		return {}
	tip = clampf(tip, TAPER_RANGE[0] * root, TAPER_RANGE[1] * root)
	var area_factor: float = BIPLANE_AREA_FACTOR if biplane else 1.0
	var span := 2.0 * half_span
	var area := span * (root + tip) * 0.5 * area_factor
	var aspect := span * span / area
	var wanted := clampf(aspect, ASPECT_RANGE[0], ASPECT_RANGE[1])
	var factor := aspect / wanted # chords grow when the wing is too slender, shrink when too stubby
	root *= factor * area_factor
	tip *= factor * area_factor
	var dihedral := clampf(rad_to_deg(atan(height_slope / half_span)), 0.0, 8.0)
	if not is_finite(root) or not is_finite(tip) or not is_finite(dihedral):
		return {}
	return {root_chord_m = root, tip_chord_m = tip, dihedral_deg = dihedral, biplane = biplane}


## {slope, at_zero}: least-squares line of rows[column] against the station fraction rows[0], or {}.
static func _line(rows: Array, column: int) -> Dictionary:
	var n := float(rows.size())
	var sf := 0.0
	var sff := 0.0
	var sv := 0.0
	var sfv := 0.0
	for row: Array in rows:
		var f := float(row[0])
		sf += f
		sff += f * f
		sv += float(row[column])
		sfv += f * float(row[column])
	var den := n * sff - sf * sf
	if n < 2.0 or absf(den) < 1e-12:
		return {}
	var slope := (n * sfv - sf * sv) / den
	return {slope = slope, at_zero = (sv - slope * sf) / n}


## Stations at or beyond this fraction of the half-span measure the dihedral.
const DIHEDRAL_FROM := 0.45
## A biplane's wings are stacked 0.25 to 1.6 main chords apart.
const BIPLANE_GAP := [0.25, 1.6]


## Inside the estimated airframe package's taper and aspect-ratio domain, with a small margin.
const TAPER_RANGE := [0.62, 1.0]
const ASPECT_RANGE := [4.2, 6.8]


## One wing section at |z| = station: {chord, y, second} or {}. The leading edge is the most forward
## crossing; the section is the contiguous run of crossings at its height; `second` is the chord of
## another layer (a biplane's other wing) overlapping it along x, or 0.
static func _section(triangles: PackedFloat64Array, station: float, half_span: float) -> Dictionary:
	var crossings := _crossings(triangles, station)
	if crossings.size() < 8:
		return {}
	var front := INF
	var front_y := 0.0
	for i in range(0, crossings.size(), 2):
		if crossings[i] < front:
			front = crossings[i]
			front_y = crossings[i + 1]
	var layer := PLANFORM_LAYER * half_span
	var gap := PLANFORM_GAP * half_span
	var main := _run(crossings, front_y, layer, gap, front)
	if main <= 0.0:
		return {}
	# Another layer: the most forward crossing away from the main layer that overlaps the main chord.
	var other := INF
	var other_y := 0.0
	for i in range(0, crossings.size(), 2):
		var x: float = crossings[i]
		if absf(crossings[i + 1] - front_y) > 2.0 * layer and x > front - 0.5 * main and x < front + main and x < other:
			other = x
			other_y = crossings[i + 1]
	var second := _run(crossings, other_y, layer, gap, other) if is_finite(other) else 0.0
	return {chord = main, y = front_y, second = second, second_y = other_y}


## Length of the contiguous run of crossings at height `y` (within `layer`) starting at `start` along x.
static func _run(crossings: PackedFloat64Array, y: float, layer: float, gap: float, start: float) -> float:
	var xs := PackedFloat64Array()
	for i in range(0, crossings.size(), 2):
		if absf(crossings[i + 1] - y) <= layer and crossings[i] >= start:
			xs.append(crossings[i])
	if xs.is_empty():
		return 0.0
	xs.sort()
	var end := xs[0]
	for x: float in xs:
		if x - end > gap:
			break
		end = x
	return end - start


## Every crossing of the planes z = +/-station by a triangle edge, as [x, y] pairs (bounded).
static func _crossings(triangles: PackedFloat64Array, station: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for triangle: int in triangles.size() / 9:
		var at := triangle * 9
		for edge: int in 3:
			var a := at + edge * 3
			var b := at + ((edge + 1) % 3) * 3
			for side: float in [station, -station]:
				var za: float = triangles[a + 2] - side
				var zb: float = triangles[b + 2] - side
				if za == zb or (za > 0.0) == (zb > 0.0) and za != 0.0 and zb != 0.0:
					continue
				var t := za / (za - zb)
				var x: float = triangles[a] + t * (triangles[b] - triangles[a])
				var y: float = triangles[a + 1] + t * (triangles[b + 1] - triangles[a + 1])
				if is_finite(x) and is_finite(y) and out.size() < 400_000:
					out.append(x)
					out.append(y)
	return out


## The largest distance (source units) of any model point from the datum along any axis.
static func _reach(triangles: PackedFloat64Array, datum: Array) -> float:
	var reach := 0.0
	for i in range(0, triangles.size() - 2, 3):
		for axis in 3:
			reach = maxf(reach, absf(triangles[i + axis] - float(datum[axis])))
	return reach if is_finite(reach) else 0.0


## Leading edge at the centreline from model-space triangles (9 floats each, ClearView frame).
## The wing is cut at two span stations; at each cut the most forward crossing (smallest x) is the
## leading edge. Low-polygon wings have vertices only at root and tip, so edges, not vertices, are cut.
## The two stations are extrapolated linearly to the centreline (sweep), limited to a small shift.
static func leading_edge(triangles: PackedFloat64Array) -> Dictionary:
	var count := triangles.size() / 3
	if count < 3:
		return R.fail(R.DATUM_UNRESOLVED, UNAVAILABLE, "placement/datum", Placement.STEP)
	var half_span := 0.0
	for index: int in count:
		half_span = maxf(half_span, absf(triangles[index * 3 + 2]))
	if not is_finite(half_span) or half_span < MIN_HALF_SPAN_M or half_span > MAX_HALF_SPAN_M:
		return R.fail(R.DATUM_UNRESOLVED, UNAVAILABLE, "placement/datum", Placement.STEP)
	var inner := _station(triangles, BAND_INNER * half_span)
	var outer := _station(triangles, BAND_OUTER * half_span)
	if inner.is_empty() or outer.is_empty():
		return R.fail(R.DATUM_UNRESOLVED, UNAVAILABLE, "placement/datum", Placement.STEP)
	var slope := (float(outer.x) - float(inner.x)) / ((BAND_OUTER - BAND_INNER) * half_span)
	var shift := clampf(slope * BAND_INNER * half_span, -MAX_SWEEP_SHIFT * half_span, MAX_SWEEP_SHIFT * half_span)
	var root_x := float(inner.x) - shift
	if not is_finite(root_x):
		return R.fail(R.DATUM_UNRESOLVED, UNAVAILABLE, "placement/datum", Placement.STEP)
	return R.ok({datum = [root_x, float(inner.y), 0.0], half_span_m = half_span})


## The most forward crossing of the plane |z| = station by any triangle edge: {x, y} or {}.
static func _station(triangles: PackedFloat64Array, station: float) -> Dictionary:
	var best := INF
	var height := 0.0
	for triangle: int in triangles.size() / 9:
		var at := triangle * 9
		for edge: int in 3:
			var a := at + edge * 3
			var b := at + ((edge + 1) % 3) * 3
			for side: float in [station, -station]:
				var za: float = triangles[a + 2] - side
				var zb: float = triangles[b + 2] - side
				if za == zb or (za > 0.0) == (zb > 0.0) and za != 0.0 and zb != 0.0:
					continue
				var t := za / (za - zb)
				var x: float = triangles[a] + t * (triangles[b] - triangles[a])
				if x < best:
					best = x
					height = triangles[a + 1] + t * (triangles[b + 1] - triangles[a + 1])
	return {x = best, y = height} if is_finite(best) and is_finite(height) else {}


## Every mesh triangle of the admitted GLB in model space (node transforms applied), 9 floats each.
static func _points(source: InspectedSource) -> Dictionary:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if source.format() != "glb" or document.append_from_buffer(source.source_bytes(), "", state) != OK:
		return R.fail(R.SOURCE_INVALID, UNAVAILABLE, "placement/datum", Placement.STEP)
	var nodes: Array[GLTFNode] = state.get_nodes()
	var meshes: Array[GLTFMesh] = state.get_meshes()
	var world: Array[Transform3D] = []
	world.resize(nodes.size())
	var done: Array[bool] = []
	done.resize(nodes.size())
	var out := PackedFloat64Array()
	var mixed := false
	var propeller := false
	for node: GLTFNode in nodes:
		var lowered := str(node.resource_name).to_lower()
		mixed = mixed or "elevon" in lowered
		propeller = propeller or "prop" in lowered or "spinner" in lowered
	for index: int in nodes.size():
		var transform := _world(nodes, index, world, done, 0)
		if _rotating_or_ground(nodes, index):
			continue
		var mesh_index: int = nodes[index].mesh
		if mesh_index < 0 or mesh_index >= meshes.size():
			continue
		var mesh: ImporterMesh = meshes[mesh_index].mesh
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var arrays: Array = mesh.get_surface_arrays(surface)
			if arrays.size() <= Mesh.ARRAY_INDEX:
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array else PackedVector3Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			var corners := indices.size() if not indices.is_empty() else vertices.size()
			if out.size() / 3 + corners > MAX_VERTICES:
				return R.fail(R.SOURCE_LIMIT, UNAVAILABLE, "placement/datum", Placement.STEP)
			for corner: int in corners - corners % 3:
				var vertex_index: int = indices[corner] if not indices.is_empty() else corner
				if vertex_index < 0 or vertex_index >= vertices.size():
					return R.fail(R.SOURCE_INVALID, UNAVAILABLE, "placement/datum", Placement.STEP)
				var placed: Vector3 = transform * vertices[vertex_index]
				out.append(placed.x)
				out.append(placed.y)
				out.append(placed.z)
	var result := R.ok(out)
	result["mixed_controls"] = mixed
	result["propeller_found"] = propeller
	return result


## A converted ClearView helicopter (receipt modelType 0). It selects the donor helicopter offer only.
static func is_helicopter(source: InspectedSource) -> bool:
	return source != null and Installation.required(source) and _model_type(source) == HELICOPTER_TYPE


## The ClearView modelType recorded in the conversion receipt (1 aeroplane, 0 helicopter), or -1.
## Read from the admitted GLB's bounded JSON chunk; it only selects a refusal, never grants flight.
static func _model_type(source: InspectedSource) -> int:
	var bytes := source.source_bytes()
	if bytes.size() < 20:
		return -1
	var length := bytes.decode_u32(12)
	if length > Limits.GLB_JSON_BYTES or 20 + length > bytes.size():
		return -1
	var document: Variant = JSON.parse_string(bytes.slice(20, 20 + length).get_string_from_utf8())
	if not document is Dictionary or not document.get("asset", {}) is Dictionary:
		return -1
	var extras: Variant = document.asset.get("extras", {})
	var receipt: Variant = extras.get("openrc_clearview", {}) if extras is Dictionary else {}
	var value: Variant = receipt.get("model_type") if receipt is Dictionary else null
	if not typeof(value) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value)) > 1000.0:
		return -1
	return int(value) if float(value) == floor(float(value)) else -1


## ClearView names propellers, their disks and spinners, and wheels conventionally; their swept or
## ground geometry is not wing. A name match on the node or any ancestor excludes it.
const NOT_WING := ["prop", "spinner", "disk", "disc", "wheel", "gear", "strut", "smoke"]

static func _rotating_or_ground(nodes: Array[GLTFNode], index: int) -> bool:
	var at := index
	for _depth: int in Limits.GLB_NODES:
		if at < 0 or at >= nodes.size():
			return false
		var lowered := str(nodes[at].resource_name).to_lower()
		for word: String in NOT_WING:
			if word in lowered:
				return true
		if nodes[at].parent == at:
			return false
		at = nodes[at].parent
	return false


static func _world(nodes: Array[GLTFNode], index: int, world: Array[Transform3D], done: Array[bool], depth: int) -> Transform3D:
	if done[index]:
		return world[index]
	var local: Transform3D = nodes[index].xform
	var parent: int = nodes[index].parent
	if parent >= 0 and parent < nodes.size() and parent != index and depth < Limits.GLB_NODES:
		local = _world(nodes, parent, world, done, depth + 1) * local
	world[index] = local
	done[index] = true
	return local
