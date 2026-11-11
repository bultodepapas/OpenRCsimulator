extends RefCounted
## Source-to-structural placement of an imported model (AC-08).
##
## A placement states how the player's file sits in the aircraft's leading-edge frame:
##   p_structural = unit_scale * rotation * (p_source - datum_source)
## with the structural frame [x_aft, y_right, z_up] in metres from the wing leading edge at the
## centreline. The nose axis, up axis, source unit and datum are explicit player decisions: no
## origin, bounding-box centre or unit is assumed. The transform is applied exactly once, to
## source-derived points only; values typed directly in metres are never transformed.
## Arithmetic is float64 on plain arrays, as for every physical quantity.

const R := preload("res://workshop/creator/result.gd")

const STEP := "orient_size"
const AXES := {
	"+x": [1.0, 0.0, 0.0], "-x": [-1.0, 0.0, 0.0],
	"+y": [0.0, 1.0, 0.0], "-y": [0.0, -1.0, 0.0],
	"+z": [0.0, 0.0, 1.0], "-z": [0.0, 0.0, -1.0],
}
## Metres per source unit for the units a player can choose.
const UNITS := {"mm": 0.001, "cm": 0.01, "m": 1.0, "in": 0.0254, "ft": 0.3048}
const SCALE_MIN := 1e-6
const SCALE_MAX := 1e6


## An unresolved placement: nothing is assumed until the player chooses.
static func unresolved() -> Dictionary:
	return {nose_axis = "", up_axis = "", unit_scale = 0.0, datum = []}


## Checks a complete placement. Returns `{rows}`: the three rows of the rotation, so that
## structural = unit_scale * rows * (p - datum).
static func resolve(placement: Dictionary) -> Dictionary:
	var problems: Array = []
	var nose_name := str(placement.get("nose_axis", ""))
	var up_name := str(placement.get("up_axis", ""))
	if not AXES.has(nose_name):
		problems.append(R.diagnostic(R.FIELD_INVALID, "Choose which model axis points to the nose.", "placement/nose_axis", STEP))
	if not AXES.has(up_name):
		problems.append(R.diagnostic(R.FIELD_INVALID, "Choose which model axis points up.", "placement/up_axis", STEP))
	if AXES.has(nose_name) and AXES.has(up_name) and nose_name.substr(1) == up_name.substr(1):
		problems.append(R.diagnostic(R.FIELD_INVALID, "The nose and up directions must be different model axes.", "placement/up_axis", STEP))
	var scale: Variant = placement.get("unit_scale", 0.0)
	if not _is_number(scale) or not is_finite(float(scale)) or float(scale) < SCALE_MIN or float(scale) > SCALE_MAX:
		problems.append(R.diagnostic(R.FIELD_INVALID, "Choose the model units or enter the real wingspan.", "placement/unit_scale", STEP))
	var datum: Variant = placement.get("datum", [])
	if not _is_point(datum):
		problems.append(R.diagnostic(R.DATUM_UNRESOLVED, "Mark the wing leading edge on the centreline.", "placement/datum", STEP))
	if not problems.is_empty():
		return R.fail_all(problems)
	var nose: Array = AXES[nose_name]
	var up: Array = AXES[up_name]
	var aft := [-nose[0], -nose[1], -nose[2]]
	# Right completes the right-handed frame: right = up x aft.
	var right := [up[1] * aft[2] - up[2] * aft[1], up[2] * aft[0] - up[0] * aft[2], up[0] * aft[1] - up[1] * aft[0]]
	return R.ok({rows = [aft, right, up], unit_scale = float(scale),
		datum = [float(datum[0]), float(datum[1]), float(datum[2])]})


## Transforms one source point into the structural leading-edge frame, in metres.
static func to_structural(resolved: Dictionary, point: PackedFloat64Array) -> PackedFloat64Array:
	var d0: float = point[0] - float(resolved.datum[0])
	var d1: float = point[1] - float(resolved.datum[1])
	var d2: float = point[2] - float(resolved.datum[2])
	var s: float = resolved.unit_scale
	var out := PackedFloat64Array([0.0, 0.0, 0.0])
	for row: int in 3:
		var axis: Array = resolved.rows[row]
		out[row] = s * (float(axis[0]) * d0 + float(axis[1]) * d1 + float(axis[2]) * d2)
	return out


## Structural-frame bounds of a source-space box (all eight corners are transformed).
static func structural_bounds(resolved: Dictionary, source_min: PackedFloat64Array, source_max: PackedFloat64Array) -> Dictionary:
	var low := PackedFloat64Array([INF, INF, INF])
	var high := PackedFloat64Array([-INF, -INF, -INF])
	for corner: int in 8:
		var point := PackedFloat64Array([
			source_max[0] if corner & 1 else source_min[0],
			source_max[1] if corner & 2 else source_min[1],
			source_max[2] if corner & 4 else source_min[2]])
		var mapped := to_structural(resolved, point)
		for axis: int in 3:
			low[axis] = minf(low[axis], mapped[axis])
			high[axis] = maxf(high[axis], mapped[axis])
	return {min = low, max = high}


## Metres per source unit such that the model's lateral extent equals a known real wingspan.
## Needs the nose and up axes; returns 0 when they are unresolved or the extent is degenerate.
static func scale_for_wingspan(placement: Dictionary, source_min: PackedFloat64Array, source_max: PackedFloat64Array,
		wingspan_m: float) -> float:
	var probe := placement.duplicate(true)
	probe["unit_scale"] = 1.0
	probe["datum"] = [0.0, 0.0, 0.0]
	var resolved: Dictionary = resolve(probe)
	if not resolved.ok or not is_finite(wingspan_m) or wingspan_m <= 0.0:
		return 0.0
	var bounds: Dictionary = structural_bounds(resolved.value, source_min, source_max)
	var lateral: float = bounds.max[1] - bounds.min[1]
	if not is_finite(lateral) or lateral <= 0.0:
		return 0.0
	return wingspan_m / lateral


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


static func _is_point(value: Variant) -> bool:
	if not (value is Array or value is PackedFloat64Array) or value.size() != 3:
		return false
	for component: Variant in value:
		if not _is_number(component) or not is_finite(float(component)):
			return false
	return true
