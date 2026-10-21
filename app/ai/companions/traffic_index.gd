## AFC-04/12: conservative float64 swept-bounds broad phase. No flight authority.
extends RefCounted

const Math3D := preload("res://physics/math3d.gd")
const MAX_ENTRIES := 256
const CELL_M := 50.0
const MAX_CELLS_PER_BOX := 4096
const MAX_CELL_REFERENCES := 65536
const MAX_ABS_COORDINATE_M := 10000000.0
const ROUNDING_PADDING_M := 0.000001

var _boxes: Array[PackedFloat64Array] = []
var _cells: Dictionary = {}
var _overflow := PackedInt32Array()
var _generation := 0
var _current_valid := false

## Each observation has id:String, state:PackedFloat64Array[13], optional
## radius_m, uncertainty_m and acceleration_bound_m_s2 (nonnegative scalars).
## The acceleration bound applies to EVERY world axis over the whole horizon;
## the caller owns its model-specific qualification. Zero means linear motion.
## A failed rebuild retains previous storage/generation but invalidates queries.
## The caller MUST fall back to all traffic for that observation set. An empty
## valid rebuild clears previous traffic; only a successful rebuild permits queries.
func rebuild(observations: Array, horizon_s: float) -> Dictionary:
	_current_valid = false
	if observations.size() > MAX_ENTRIES or not is_finite(horizon_s) or horizon_s < 0.0 or horizon_s > 10.0:
		return _refuse("invalid_count_or_horizon")
	var boxes: Array[PackedFloat64Array] = []
	var cells: Dictionary = {}
	var overflow := PackedInt32Array()
	var identities := {}
	var cell_references := 0
	for entry: Variant in observations:
		if not entry is Dictionary or not entry.get("id") is String or entry.id.is_empty() \
				or identities.has(entry.id):
			return _refuse("invalid_or_duplicate_identity")
		identities[entry.id] = true
		var state: Variant = entry.get("state")
		if not state is PackedFloat64Array or state.size() != 13:
			return _refuse("invalid_state_layout")
		for value: float in state:
			if not is_finite(value):
				return _refuse("nonfinite_state")
		var quaternion: PackedFloat64Array = state.slice(6, 10)
		var norm_squared := 0.0
		for value: float in quaternion:
			norm_squared += value * value
		if absf(norm_squared - 1.0) > 0.0001:
			return _refuse("nonunit_attitude")
		var padding := ROUNDING_PADDING_M
		for key: String in ["radius_m", "uncertainty_m", "acceleration_bound_m_s2"]:
			var number: Variant = entry.get(key, 0.0)
			if typeof(number) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(number)) \
					or float(number) < 0.0 or float(number) > 10000.0:
				return _refuse("invalid_motion_bound")
			padding += float(number) * 0.5 * horizon_s * horizon_s if key == "acceleration_bound_m_s2" else float(number)
		var velocity: PackedFloat64Array = Math3D.q_rotate(quaternion, state.slice(3, 6))
		for component: float in velocity:
			if not is_finite(component):
				return _refuse("nonfinite_derived_motion")
		var box := PackedFloat64Array()
		box.resize(6)
		for axis: int in 3:
			var endpoint: float = state[axis] + velocity[axis] * horizon_s
			if not is_finite(endpoint):
				return _refuse("nonfinite_derived_motion")
			box[axis] = minf(state[axis], endpoint) - padding
			box[axis + 3] = maxf(state[axis], endpoint) + padding
			if not is_finite(box[axis]) or not is_finite(box[axis + 3]) \
					or absf(box[axis]) > MAX_ABS_COORDINATE_M or absf(box[axis + 3]) > MAX_ABS_COORDINATE_M:
				return _refuse("motion_outside_index_domain")
		var index := boxes.size()
		boxes.append(box)
		var bounds := _cell_bounds(box)
		var cell_count := _cell_count(bounds)
		if cell_count > MAX_CELLS_PER_BOX or cell_references + cell_count > MAX_CELL_REFERENCES:
			overflow.append(index) # Preserve coverage with a bounded all-query fallback.
			continue
		cell_references += cell_count
		for north: int in range(bounds[0], bounds[3] + 1):
			for east: int in range(bounds[1], bounds[4] + 1):
				for down: int in range(bounds[2], bounds[5] + 1):
					var key := _cell_key(north, east, down)
					if not cells.has(key):
						cells[key] = PackedInt32Array()
					var bucket: PackedInt32Array = cells[key]
					bucket.append(index)
					cells[key] = bucket
	_boxes = boxes
	_cells = cells
	_overflow = overflow
	_generation += 1
	_current_valid = true
	return {ok = true, entries = boxes.size(), cells = cells.size(), references = cell_references,
		overflow = overflow.size(), generation = _generation}

## Returns ORIGINAL observation indices in original order, excluding own_index.
## This preserves existing deterministic threat tie-breaking. Box overlap is only
## a candidate test: refine with continuous closest approach/reachable trajectories.
func query(own_index: int, separation_m: float) -> Dictionary:
	if not _current_valid:
		return _refuse("rebuild_required")
	if own_index < 0 or own_index >= _boxes.size() or not is_finite(separation_m) \
			or separation_m < 0.0 or separation_m > 10000.0:
		return _refuse("invalid_query")
	var box: PackedFloat64Array = _boxes[own_index].duplicate()
	for axis: int in 3:
		box[axis] -= separation_m
		box[axis + 3] += separation_m
	var bounds := _cell_bounds(box)
	var seen := {}
	if _cell_count(bounds) > MAX_CELLS_PER_BOX:
		for index: int in _boxes.size():
			seen[index] = true
	else:
		for index: int in _overflow:
			seen[index] = true
		for north: int in range(bounds[0], bounds[3] + 1):
			for east: int in range(bounds[1], bounds[4] + 1):
				for down: int in range(bounds[2], bounds[5] + 1):
					for index: int in _cells.get(_cell_key(north, east, down), PackedInt32Array()):
						seen[index] = true
	var matches := PackedInt32Array()
	for index: int in _boxes.size():
		if index != own_index and seen.has(index) and _overlap(box, _boxes[index]):
			matches.append(index)
	return {ok = true, indices = matches, generation = _generation}

static func _cell_bounds(box: PackedFloat64Array) -> PackedInt64Array:
	var result := PackedInt64Array()
	for value: float in box:
		result.append(floori(value / CELL_M))
	return result

static func _cell_count(bounds: PackedInt64Array) -> int:
	return (bounds[3] - bounds[0] + 1) * (bounds[4] - bounds[1] + 1) * (bounds[5] - bounds[2] + 1)

static func _cell_key(north: int, east: int, down: int) -> String:
	return "%d,%d,%d" % [north, east, down]

static func _overlap(first: PackedFloat64Array, second: PackedFloat64Array) -> bool:
	for axis: int in 3:
		if first[axis] > second[axis + 3] or second[axis] > first[axis + 3]:
			return false
	return true

static func _refuse(reason: String) -> Dictionary:
	return {ok = false, reason = reason}
