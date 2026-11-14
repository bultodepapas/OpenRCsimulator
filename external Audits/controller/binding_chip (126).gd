## A confirmed OFF sample followed by stable ON and return to OFF. No raw
## threshold assumption; shares the AUX range validation and normalization.
extends RefCounted

const SmokeAux := preload("res://input/smoke_aux.gd")
const STABLE_SECONDS := 0.2
const STABLE_TOLERANCE := 0.02
const RETURN_TOLERANCE := 0.03

var _off := PackedFloat64Array()
var _reserved: Array = []
var _axis := -1
var _on := 0.0
var _stable := 0.0
var returning := false

func begin(axes: PackedFloat64Array, reserved: Array) -> bool:
	if not _valid_axes(axes): return false
	_off = axes.duplicate()
	_reserved = reserved.duplicate()
	_axis = -1
	_stable = 0.0
	returning = false
	return true

func sample(axes: PackedFloat64Array, delta: float) -> Dictionary:
	if _off.is_empty() or not _valid_axes(axes) or not is_finite(delta) or delta < 0.0 or delta > 1.0:
		return {error = "Invalid or interrupted switch capture. The binding is unchanged."}
	var moved: Array[int] = []
	for axis: int in axes.size():
		if not _reserved.has(axis) and absf(axes[axis] - _off[axis]) >= SmokeAux.MIN_AXIS_SPAN:
			moved.append(axis)
	if moved.size() > 1 or (_axis >= 0 and not moved.is_empty() and moved[0] != _axis):
		return {error = "More than one switch axis moved. Capture one switch at a time."}
	if _axis < 0:
		if moved.is_empty(): return {}
		_axis = moved[0]
		_on = axes[_axis]
		_stable = 0.0
	if not returning:
		if absf(axes[_axis] - _on) > STABLE_TOLERANCE:
			_on = axes[_axis]
			_stable = 0.0
		elif absf(_on - _off[_axis]) >= SmokeAux.MIN_AXIS_SPAN:
			_stable += delta
		if _stable >= STABLE_SECONDS:
			returning = true
			_stable = 0.0
		return {}
	_stable = _stable + delta if absf(axes[_axis] - _off[_axis]) <= RETURN_TOLERANCE else 0.0
	if _stable < STABLE_SECONDS: return {}
	var binding := {"type": "axis", "axis": _axis, "off": _off[_axis], "on": _on,
		"invert": _on < _off[_axis], "sign": -1 if _on < _off[_axis] else 1, "threshold": 0.65}
	return {binding = binding} if SmokeAux.valid_binding(binding, _reserved) else {error = "Invalid switch range. The binding is unchanged."}

static func _valid_axes(axes: PackedFloat64Array) -> bool:
	if axes.size() != SmokeAux.AXES: return false
	for value: float in axes:
		if not is_finite(value) or absf(value) > 1.0: return false
	return true
