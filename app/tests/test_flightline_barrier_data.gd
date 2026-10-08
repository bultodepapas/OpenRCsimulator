# L10c: flightline-barrier data is exact, bounded, and placement-safe.
# Run: godot --headless --path app --script res://tests/test_flightline_barrier_data.gd
extends SceneTree

const Loader = preload("res://data/field_loader.gd")
const DEFAULT_PATH: String = "res://data/fields/default.json"
const BARRIER_KEYS: Array[String] = ["id", "type", "collides", "north", "east", "width", "height", "gap_width"]
const QUANTITY_FIELDS: Array[String] = ["north", "east", "width", "height", "gap_width"]
const QUANTITY_KEYS: Array[String] = ["value", "unit", "kind", "source"]

var _failures: int = 0
var _count: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _has_error(errors: PackedStringArray, needle: String) -> bool:
	for message: String in errors:
		if needle in message:
			return true
	return false


func _rejected(label: String, mutate: Callable, needle: String) -> void:
	var raw: Dictionary = _field_with_barrier()
	mutate.call(raw)
	var result: Dictionary = Loader.validate(raw)
	var errors: PackedStringArray = result["errors"]
	_check("rejects " + label, not bool(result["ok"]) and _has_error(errors, needle), str(errors))
	_check("invalid " + label + " has no usable field", (result["field"] as Dictionary).is_empty())


func _initialize() -> void:
	_test_legacy_and_default_data()
	_test_normalization_and_capacity()
	_test_exact_schema_and_ids()
	_test_quantity_validation()
	_test_dimension_bounds()
	_test_placement_validation()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _test_legacy_and_default_data() -> void:
	var legacy: Dictionary = Loader.validate(_field())
	_check("legacy field without cues still validates", bool(legacy["ok"]), str(legacy["errors"]))
	if bool(legacy["ok"]):
		var field: Dictionary = legacy["field"]
		_check("legacy normalized shape remains six keys", field.keys().size() == 6 and not field.has("flight_cues"), str(field.keys()))
	var empty_raw: Dictionary = _field()
	empty_raw["flight_cues"] = []
	var empty: Dictionary = Loader.validate(empty_raw)
	_check("empty optional cue list still validates", bool(empty["ok"]), str(empty["errors"]))
	if bool(empty["ok"]):
		_check("empty optional cue list remains present", empty["field"].has("flight_cues") and (empty["field"]["flight_cues"] as Array).is_empty())

	var loaded: Dictionary = Loader.load_from(DEFAULT_PATH)
	_check("default field with all three cues validates", bool(loaded["ok"]), str(loaded["errors"]))
	if not bool(loaded["ok"]):
		return
	var cues: Array = loaded["field"]["flight_cues"]
	_check("default field retains windsock, station, and barrier", cues.size() == 3 and _has_type(cues, "windsock") and _has_type(cues, "pilot_station") and _has_type(cues, "flightline_barrier"), str(cues))
	var barriers: Array[Dictionary] = _matching_type(cues, "flightline_barrier")
	_check("one default barrier uses proposed estimated dimensions", barriers.size() == 1)
	if barriers.size() == 1:
		var barrier: Dictionary = barriers[0]
		_check("default barrier is centered behind runway", barrier["north"] == 4.5 and barrier["east"] == 0.0 and barrier["width"] == 48.0, str(barrier))
		_check("default opening and height match estimates", barrier["gap_width"] == 6.0 and barrier["height"] == 0.65, str(barrier))


func _test_normalization_and_capacity() -> void:
	var result: Dictionary = Loader.validate(_field_with_barrier())
	_check("valid barrier data validates", bool(result["ok"]), str(result["errors"]))
	if bool(result["ok"]):
		var cues: Array = result["field"]["flight_cues"]
		var barrier: Dictionary = cues[0]
		_check("normalized barrier contains only its eight renderer keys", barrier.keys().size() == BARRIER_KEYS.size() and barrier.has_all(BARRIER_KEYS), str(barrier.keys()))
		_check("normalized barrier is visual-only", barrier["id"] == "flightline_barrier" and barrier["type"] == "flightline_barrier" and barrier["collides"] == false)
		_check("all five quantities normalize to float metres", typeof(barrier["north"]) == TYPE_FLOAT and typeof(barrier["east"]) == TYPE_FLOAT and typeof(barrier["width"]) == TYPE_FLOAT and typeof(barrier["height"]) == TYPE_FLOAT and typeof(barrier["gap_width"]) == TYPE_FLOAT)

	var three: Dictionary = _field()
	three["flight_cues"] = [_valid_windsock(), _valid_station(), _valid_barrier()]
	var three_result: Dictionary = Loader.validate(three)
	_check("one of each cue type fits the three-cue capacity", bool(three_result["ok"]), str(three_result["errors"]))
	_rejected("duplicate barrier type", func(data: Dictionary) -> void:
		var duplicate: Dictionary = _valid_barrier()
		duplicate["id"] = "barrier_copy"
		(data["flight_cues"] as Array).append(duplicate),
		"at most one 'flightline_barrier' cue is supported")
	_rejected("more than three cues", func(data: Dictionary) -> void:
		var cues: Array = [_valid_windsock(), _valid_station(), _valid_barrier(), _valid_barrier()]
		(cues[3] as Dictionary)["id"] = "barrier_fourth"
		data["flight_cues"] = cues,
		"at most 3 cues are supported")


func _test_exact_schema_and_ids() -> void:
	for key: String in BARRIER_KEYS:
		_rejected("missing key " + key, func(data: Dictionary) -> void: _barrier(data).erase(key), "missing '%s'" % key)
	_rejected("unknown barrier key", func(data: Dictionary) -> void: _barrier(data)["color"] = "orange", "unknown key 'color'")
	_rejected("barrier cannot borrow station-only depth", func(data: Dictionary) -> void: _barrier(data)["depth"] = _quantity_value(1.0), "unknown key 'depth'")
	_rejected("barrier cannot borrow windsock-only pole height", func(data: Dictionary) -> void: _barrier(data)["pole_height"] = _quantity_value(3.6), "unknown key 'pole_height'")
	_rejected("unknown cue type", func(data: Dictionary) -> void: _barrier(data)["type"] = "flag", "type: expected")
	_rejected("colliding barrier", func(data: Dictionary) -> void: _barrier(data)["collides"] = true, "collides=true is unsupported")
	_rejected("non-boolean collides value", func(data: Dictionary) -> void: _barrier(data)["collides"] = "false", "collides: expected a boolean")
	_rejected("ID duplicates pilot", func(data: Dictionary) -> void: _barrier(data)["id"] = "pilot", "duplicate ID 'pilot'")
	_rejected("ID cannot become a node path", func(data: Dictionary) -> void: _barrier(data)["id"] = "flightline/barrier", "not a valid Godot node name")
	_rejected("ID cannot steal generated contact shadows", func(data: Dictionary) -> void: _barrier(data)["id"] = "FlightCueShadows", "reserved for a generated field child")


func _test_quantity_validation() -> void:
	for field_name: String in QUANTITY_FIELDS:
		for metadata_key: String in QUANTITY_KEYS:
			_rejected("missing %s metadata %s" % [field_name, metadata_key], func(data: Dictionary) -> void: _barrier_quantity(data, field_name).erase(metadata_key), "%s: missing '%s'" % [field_name, metadata_key])
	_rejected("non-finite barrier coordinate", func(data: Dictionary) -> void: _barrier_quantity(data, "north")["value"] = NAN, "north.value: must be finite")
	_rejected("boolean is not a dimension", func(data: Dictionary) -> void: _barrier_quantity(data, "width")["value"] = true, "width.value: expected a number")
	_rejected("wrong quantity unit", func(data: Dictionary) -> void: _barrier_quantity(data, "gap_width")["unit"] = "ft", "gap_width.unit: expected 'm'")
	_rejected("unknown evidence kind", func(data: Dictionary) -> void: _barrier_quantity(data, "height")["kind"] = "assumed", "height.kind: expected one of")
	_rejected("empty provenance", func(data: Dictionary) -> void: _barrier_quantity(data, "width")["source"] = "  ", "width.source: must be a nonempty string")


func _test_dimension_bounds() -> void:
	_rejected("width below range", func(data: Dictionary) -> void: _barrier_quantity(data, "width")["value"] = 9.99, "width.value: must be within 10.000..80.000 m")
	_rejected("width above range", func(data: Dictionary) -> void: _barrier_quantity(data, "width")["value"] = 80.01, "width.value: must be within 10.000..80.000 m")
	_rejected("height below range", func(data: Dictionary) -> void: _barrier_quantity(data, "height")["value"] = 0.49, "height.value: must be within 0.500..0.900 m")
	_rejected("height above range", func(data: Dictionary) -> void: _barrier_quantity(data, "height")["value"] = 0.91, "height.value: must be within 0.500..0.900 m")
	_rejected("gap below range", func(data: Dictionary) -> void: _barrier_quantity(data, "gap_width")["value"] = 1.99, "gap_width.value: must be within 2.000..12.000 m")
	_rejected("gap above range", func(data: Dictionary) -> void: _barrier_quantity(data, "gap_width")["value"] = 12.01, "gap_width.value: must be within 2.000..12.000 m")
	_rejected("gap must leave at least four metres of barrier", func(data: Dictionary) -> void:
		_barrier_quantity(data, "width")["value"] = 10.0
		_barrier_quantity(data, "gap_width")["value"] = 6.01,
		"gap_width.value: must be at least 4 m narrower than width")
	var lower: Dictionary = _field_with_barrier()
	_barrier_quantity(lower, "width")["value"] = 10.0
	_barrier_quantity(lower, "height")["value"] = 0.5
	_barrier_quantity(lower, "gap_width")["value"] = 2.0
	var lower_result: Dictionary = Loader.validate(lower)
	_check("lower dimensions are inclusive", bool(lower_result["ok"]), str(lower_result["errors"]))
	var upper: Dictionary = _field_with_barrier()
	_barrier_quantity(upper, "width")["value"] = 80.0
	_barrier_quantity(upper, "height")["value"] = 0.9
	_barrier_quantity(upper, "gap_width")["value"] = 12.0
	_barrier_quantity(upper, "north")["value"] = 3.5
	var upper_result: Dictionary = Loader.validate(upper)
	_check("upper dimensions at north 3.5 preserve the runway sightline", bool(upper_result["ok"]), str(upper_result["errors"]))


func _test_placement_validation() -> void:
	_rejected("barrier must be at least two metres north of pilot", func(data: Dictionary) -> void: _barrier_quantity(data, "north")["value"] = 1.99, "at least 2.0 m north of pilot")
	_rejected("barrier east must exactly align with pilot", func(data: Dictionary) -> void: _barrier_quantity(data, "east")["value"] = 0.001, "must equal pilot.east.value exactly")
	_rejected("barrier requires a level field datum", func(data: Dictionary) -> void: _quantity(data, "down", true)["value"] = 0.01, "pilot.down == 0 m")
	_rejected("barrier keeps two metres clear of maximum station depth", func(data: Dictionary) -> void: _barrier_quantity(data, "north")["value"] = 3.1, "maximum-depth pilot station")
	_rejected("barrier stays one metre behind runway near edge", func(data: Dictionary) -> void: _barrier_quantity(data, "north")["value"] = 8.0, "at least 1.0 m behind the near edge")
	_rejected("maximum barrier height preserves the default runway sightline", func(data: Dictionary) -> void: _barrier_quantity(data, "height")["value"] = 0.9, "exceeds the pilot-to-runway near-edge sightline")
	_rejected("low pilot eye height preserves the runway sightline", func(data: Dictionary) -> void: _quantity(data, "eye_height", true)["value"] = 1.0, "exceeds the pilot-to-runway near-edge sightline")
	var near_runway: Dictionary = _field_with_barrier()
	var near_surfaces: Array = near_runway["surfaces"]
	var near_runway_surface: Dictionary = near_surfaces[1]
	(near_runway_surface["center_north"] as Dictionary)["value"] = 11.54
	near_surfaces.append(_surface("mown", "mown", -20.0, 0.0, 60.0, 20.0))
	near_runway["surfaces"] = near_surfaces
	_barrier_quantity(near_runway, "north")["value"] = 4.4
	var near_result: Dictionary = Loader.validate(near_runway)
	var near_errors: PackedStringArray = near_result["errors"]
	_check("near-runway sightline is the only error when runway and mown clearances pass", not bool(near_result["ok"]) and near_errors.size() == 1 and _has_error(near_errors, "exceeds the pilot-to-runway near-edge sightline"), str(near_errors))
	_rejected("full row footprint avoids mown surface", func(data: Dictionary) -> void:
		var surfaces: Array = data["surfaces"]
		surfaces.append(_surface("mown", "mown", 4.5, 0.0, 30.0, 1.0)),
		"full barrier footprint intersects mown surface 'mown'")
	_rejected("barrier footprint fits inside rough", func(data: Dictionary) -> void: _barrier_quantity(data, "east")["value"] = 20000.0, "full barrier footprint must fit inside a rough surface")
	_rejected("barrier corners stay in the flat relief radius", func(data: Dictionary) -> void:
		_quantity(data, "east", true)["value"] = 1480.0
		_barrier_quantity(data, "east")["value"] = 1480.0,
		"every footprint corner must stay inside the 1500 m flat radius")
	_rejected("custom rough cannot bypass an overlapping exact horizon bound", func(data: Dictionary) -> void:
		var surfaces: Array = data["surfaces"]
		surfaces.append(_surface("custom_rough", "rough", 0.0, 0.0, 60000.0, 60000.0))
		data["surfaces"] = surfaces
		_quantity(data, "east", true)["value"] = 1480.0
		_barrier_quantity(data, "east")["value"] = 1480.0,
		"every footprint corner must stay inside the 1500 m flat radius")
	var custom_flat: Dictionary = _field_with_barrier()
	var custom_surfaces: Array = custom_flat["surfaces"]
	custom_surfaces[0] = _surface("rough", "rough", 0.0, 0.0, 60000.0, 60000.0)
	custom_flat["surfaces"] = custom_surfaces
	_quantity(custom_flat, "east", true)["value"] = 2000.0
	_barrier_quantity(custom_flat, "east")["value"] = 2000.0
	_quantity(custom_flat, "north", true)["value"] = 2000.0
	_barrier_quantity(custom_flat, "north")["value"] = 2004.5
	var custom_runway: Dictionary = custom_surfaces[1]
	(custom_runway["center_north"] as Dictionary)["value"] = 2015.0
	(custom_runway["center_east"] as Dictionary)["value"] = 2000.0
	var custom_result: Dictionary = Loader.validate(custom_flat)
	_check("translated custom rough retains relative runway sightline and stays flat beyond 1.5 km", bool(custom_result["ok"]), str(custom_result["errors"]))
	_rejected("barrier checks the full windsock envelope", func(data: Dictionary) -> void:
		var wind: Dictionary = _valid_windsock()
		_quantity_from(wind, "east")["value"] = 24.0
		_quantity_from(wind, "north")["value"] = 5.0
		data["flight_cues"] = [wind, _valid_barrier()],
		"flightline_barrier full span intersects windsock conservative envelope")


func _field_with_barrier() -> Dictionary:
	var data: Dictionary = _field()
	data["flight_cues"] = [_valid_barrier()]
	return data


func _field() -> Dictionary:
	return {
		"format": "openrc-field v1",
		"id": "test_field",
		"runway": "runway",
		"pilot": {
			"id": "pilot",
			"north": _quantity_value(0.0),
			"east": _quantity_value(0.0),
			"down": _quantity_value(0.0),
			"eye_height": _quantity_value(1.7),
		},
		"surfaces": [
			_surface("rough", "rough", 0.0, 0.0, 40000.0, 40000.0),
			_surface("runway", "runway", 15.0, 0.0, 100.0, 12.0),
		],
		"objects": [],
	}


func _valid_barrier() -> Dictionary:
	return {
		"id": "flightline_barrier",
		"type": "flightline_barrier",
		"collides": false,
		"north": _quantity_value(4.5),
		"east": _quantity_value(0.0),
		"width": _quantity_value(48.0),
		"height": _quantity_value(0.65),
		"gap_width": _quantity_value(6.0),
	}


func _valid_station() -> Dictionary:
	return {
		"id": "pilot_station",
		"type": "pilot_station",
		"collides": false,
		"north": _quantity_value(0.0),
		"east": _quantity_value(0.0),
		"width": _quantity_value(1.5),
		"depth": _quantity_value(1.2),
		"height": _quantity_value(0.75),
	}


func _valid_windsock() -> Dictionary:
	return {
		"id": "windsock",
		"type": "windsock",
		"collides": false,
		"north": _quantity_value(-6.0),
		"east": _quantity_value(-12.0),
		"pole_height": _quantity_value(3.6),
		"length": _quantity_value(2.5),
		"throat_diameter": _quantity_value(0.45),
		"tail_diameter": _quantity_value(0.18),
	}


func _quantity_value(value: float) -> Dictionary:
	return {"value": value, "unit": "m", "kind": "estimated", "source": "L10c test estimate."}


func _quantity(data: Dictionary, key: String, pilot: bool = false) -> Dictionary:
	var section: Dictionary = data["pilot"] if pilot else (data["flight_cues"] as Array)[0]
	return section[key]


func _quantity_from(cue: Dictionary, key: String) -> Dictionary:
	return cue[key]


func _barrier(data: Dictionary) -> Dictionary:
	return (data["flight_cues"] as Array)[0]


func _barrier_quantity(data: Dictionary, key: String) -> Dictionary:
	return _barrier(data)[key]


func _surface(identifier: String, surface_type: String, north: float, east: float, length: float, width: float) -> Dictionary:
	return {
		"id": identifier,
		"type": surface_type,
		"center_north": _quantity_value(north),
		"center_east": _quantity_value(east),
		"length_east_west": _quantity_value(length),
		"width_north_south": _quantity_value(width),
	}


func _has_type(cues: Array, cue_type: String) -> bool:
	return not _matching_type(cues, cue_type).is_empty()


func _matching_type(cues: Array, cue_type: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for cue_value: Variant in cues:
		var cue: Dictionary = cue_value
		if cue.get("type") == cue_type:
			matches.append(cue)
	return matches
