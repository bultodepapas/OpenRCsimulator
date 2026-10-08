# L10b: pilot-station field data is exact, bounded, and placement-safe.
# Run: godot --headless --path app --script res://tests/test_pilot_station_data.gd
extends SceneTree

const Loader := preload("res://data/field_loader.gd")
const DEFAULT_PATH: String = "res://data/fields/default.json"
const STATION_KEYS: Array[String] = ["id", "type", "collides", "north", "east", "width", "depth", "height"]
const QUANTITY_FIELDS: Array[String] = ["north", "east", "width", "depth", "height"]
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
	var raw: Dictionary = _field_with_station()
	mutate.call(raw)
	var result: Dictionary = Loader.validate(raw)
	var errors: PackedStringArray = result["errors"]
	_check("rejects " + label, not bool(result["ok"]) and _has_error(errors, needle), str(errors))
	_check("invalid " + label + " has no usable field", (result["field"] as Dictionary).is_empty())


func _initialize() -> void:
	_test_legacy_shape()
	_test_station_normalization()
	_test_mixed_cues_and_capacity()
	_test_exact_schema_and_ids()
	_test_quantity_validation()
	_test_dimension_bounds()
	_test_placement_validation()
	_test_real_default_field_when_station_exists()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _test_legacy_shape() -> void:
	var omitted: Dictionary = Loader.validate(_field())
	_check("legacy field without flight_cues still validates", bool(omitted["ok"]), str(omitted["errors"]))
	if bool(omitted["ok"]):
		var field: Dictionary = omitted["field"]
		_check("absent flight_cues keeps the six-key normalized shape", not field.has("flight_cues") and field.keys().size() == 6, str(field.keys()))
	var empty_raw: Dictionary = _field()
	empty_raw["flight_cues"] = []
	var empty: Dictionary = Loader.validate(empty_raw)
	_check("empty optional flight_cues validates", bool(empty["ok"]), str(empty["errors"]))
	if bool(empty["ok"]):
		var field: Dictionary = empty["field"]
		_check("present empty flight_cues remains present and empty", field.has("flight_cues") and (field["flight_cues"] as Array).is_empty())


func _test_station_normalization() -> void:
	var result: Dictionary = Loader.validate(_field_with_station())
	_check("valid pilot station data validates", bool(result["ok"]), str(result["errors"]))
	if not bool(result["ok"]):
		return
	var field: Dictionary = result["field"]
	var cues: Array = field["flight_cues"]
	_check("one pilot station is normalized", cues.size() == 1)
	if cues.size() != 1:
		return
	var station: Dictionary = cues[0]
	_check("normalized station contains only renderer data", station.keys().size() == STATION_KEYS.size() and station.has_all(STATION_KEYS), str(station.keys()))
	_check("normalized station identity and visual-only flag are stable", station["id"] == "pilot_station" and station["type"] == "pilot_station" and station["collides"] == false)
	_check("station quantities unwrap to float metres", typeof(station["north"]) == TYPE_FLOAT and typeof(station["east"]) == TYPE_FLOAT and typeof(station["width"]) == TYPE_FLOAT and typeof(station["depth"]) == TYPE_FLOAT and typeof(station["height"]) == TYPE_FLOAT and station["north"] == 0.0 and station["east"] == 0.0 and station["width"] == 1.8 and station["depth"] == 1.4 and station["height"] == 0.8, str(station))


func _test_mixed_cues_and_capacity() -> void:
	var raw: Dictionary = _field_with_station()
	raw["flight_cues"] = [_valid_windsock(), _valid_station()]
	var result: Dictionary = Loader.validate(raw)
	_check("one windsock and one station validate together", bool(result["ok"]), str(result["errors"]))
	if bool(result["ok"]):
		var cues: Array = result["field"]["flight_cues"]
		_check("mixed cues keep source order and type", cues.size() == 2 and cues[0]["type"] == "windsock" and cues[1]["type"] == "pilot_station", str(cues))

	_rejected("duplicate pilot station type", func(data: Dictionary) -> void:
		var duplicate: Dictionary = _valid_station()
		duplicate["id"] = "pilot_station_copy"
		(data["flight_cues"] as Array).append(duplicate),
		"at most one 'pilot_station' cue is supported")
	_rejected("duplicate windsock type", func(data: Dictionary) -> void:
		var cues: Array = [_valid_windsock()]
		var duplicate: Dictionary = _valid_windsock()
		duplicate["id"] = "windsock_copy"
		cues.append(duplicate)
		data["flight_cues"] = cues,
		"at most one 'windsock' cue is supported")
	_rejected("more than two cues", func(data: Dictionary) -> void:
		var cues: Array = [_valid_windsock(), _valid_station(), _valid_station()]
		(cues[2] as Dictionary)["id"] = "pilot_station_third"
		data["flight_cues"] = cues,
		"at most 2 cues are supported")


func _test_exact_schema_and_ids() -> void:
	_rejected("flight_cues with wrong root type", func(data: Dictionary) -> void: data["flight_cues"] = null, "flight_cues: expected an array")
	_rejected("null cue entry", func(data: Dictionary) -> void: (data["flight_cues"] as Array)[0] = null, "flight_cues[0]: expected an object")
	for key: String in STATION_KEYS:
		_rejected("missing station key " + key, func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary).erase(key), "missing '%s'" % key)
	_rejected("unknown station key", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["color"] = "orange", "unknown key 'color'")
	_rejected("station cannot borrow windsock-only keys", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["pole_height"] = _quantity_value(3.6), "unknown key 'pole_height'")
	_rejected("windsock cannot borrow station-only keys", func(data: Dictionary) -> void:
		var data_copy: Dictionary = _field()
		data_copy["flight_cues"] = [_valid_windsock()]
		((data_copy["flight_cues"] as Array)[0] as Dictionary)["width"] = _quantity_value(1.8)
		data.clear()
		data.merge(data_copy, true),
		"unknown key 'width'")
	_rejected("unknown flight cue type", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["type"] = "flag", "type: expected 'windsock' or 'pilot_station'")
	_rejected("station collides with the pilot", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["collides"] = true, "collides=true is unsupported")
	_rejected("station collides value must be boolean", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["collides"] = "false", "collides: expected a boolean")
	_rejected("station ID duplicates pilot ID", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["id"] = "pilot", "duplicate ID 'pilot'")
	_rejected("station ID duplicates surface ID", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["id"] = "rough", "duplicate ID 'rough'")
	_rejected("station ID duplicates other cue ID", func(data: Dictionary) -> void:
		var cues: Array = [_valid_windsock(), _valid_station()]
		(cues[1] as Dictionary)["id"] = "windsock"
		data["flight_cues"] = cues,
		"duplicate ID 'windsock'")
	_rejected("station ID cannot become a node path", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["id"] = "station/frame", "not a valid Godot node name")
	_rejected("station ID cannot have edge whitespace", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["id"] = " station", "leading or trailing whitespace")
	_rejected("station ID cannot steal the near-grass child name", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["id"] = "NearGrass", "reserved for a generated field child")
	_rejected("station ID cannot steal the scenery child name", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["id"] = "Scenery", "reserved for a generated field child")


func _test_quantity_validation() -> void:
	for field_name: String in QUANTITY_FIELDS:
		for metadata_key: String in QUANTITY_KEYS:
			_rejected("missing %s quantity metadata %s" % [field_name, metadata_key], func(data: Dictionary) -> void: _station_quantity(data, field_name).erase(metadata_key), "%s: missing '%s'" % [field_name, metadata_key])
	_rejected("quantity with null value", func(data: Dictionary) -> void: _station_quantity(data, "north")["value"] = null, "north.value: expected a number")
	_rejected("boolean quantity is not numeric", func(data: Dictionary) -> void: _station_quantity(data, "width")["value"] = true, "width.value: expected a number")
	_rejected("non-finite station coordinate", func(data: Dictionary) -> void: _station_quantity(data, "north")["value"] = NAN, "north.value: must be finite")
	_rejected("non-finite station dimension", func(data: Dictionary) -> void: _station_quantity(data, "height")["value"] = INF, "height.value: must be finite")
	_rejected("coordinate is bounded to one million metres", func(data: Dictionary) -> void: _station_quantity(data, "north")["value"] = 1000001.0, "north.value: must be within +/- 1000000 m")
	_rejected("wrong station quantity unit", func(data: Dictionary) -> void: _station_quantity(data, "east")["unit"] = "ft", "east.unit: expected 'm'")
	_rejected("unknown station evidence kind", func(data: Dictionary) -> void: _station_quantity(data, "width")["kind"] = "assumed", "width.kind: expected one of")
	_rejected("empty station provenance", func(data: Dictionary) -> void: _station_quantity(data, "height")["source"] = "  ", "height.source: must be a nonempty string")
	_rejected("non-string station provenance", func(data: Dictionary) -> void: _station_quantity(data, "east")["source"] = 3, "east.source: must be a nonempty string")
	_rejected("unknown quantity metadata", func(data: Dictionary) -> void: _station_quantity(data, "depth")["confidence"] = 1.0, "unknown key 'confidence'")
	_rejected("quantity must be an object", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["height"] = null, "height: expected a quantity object")


func _test_dimension_bounds() -> void:
	_rejected("width below visual policy range", func(data: Dictionary) -> void: _station_quantity(data, "width")["value"] = 1.19, "width.value: must be within 1.200..2.400 m")
	_rejected("width above visual policy range", func(data: Dictionary) -> void: _station_quantity(data, "width")["value"] = 2.41, "width.value: must be within 1.200..2.400 m")
	_rejected("depth below visual policy range", func(data: Dictionary) -> void: _station_quantity(data, "depth")["value"] = 0.99, "depth.value: must be within 1.000..2.000 m")
	_rejected("depth above visual policy range", func(data: Dictionary) -> void: _station_quantity(data, "depth")["value"] = 2.01, "depth.value: must be within 1.000..2.000 m")
	_rejected("height below visual policy range", func(data: Dictionary) -> void: _station_quantity(data, "height")["value"] = 0.59, "height.value: must be within 0.600..0.900 m")
	_rejected("height above visual policy range", func(data: Dictionary) -> void: _station_quantity(data, "height")["value"] = 0.91, "height.value: must be within 0.600..0.900 m")
	var boundaries: Dictionary = _field_with_station()
	_station_quantity(boundaries, "width")["value"] = 1.2
	_station_quantity(boundaries, "depth")["value"] = 1.0
	_station_quantity(boundaries, "height")["value"] = 0.6
	var lower_result: Dictionary = Loader.validate(boundaries)
	_check("lower station dimension bounds are inclusive", bool(lower_result["ok"]), str(lower_result["errors"]))
	_station_quantity(boundaries, "width")["value"] = 2.4
	_station_quantity(boundaries, "depth")["value"] = 2.0
	_station_quantity(boundaries, "height")["value"] = 0.9
	var upper_result: Dictionary = Loader.validate(boundaries)
	_check("upper station dimension bounds are inclusive", bool(upper_result["ok"]), str(upper_result["errors"]))


func _test_placement_validation() -> void:
	_rejected("station north must exactly equal pilot north", func(data: Dictionary) -> void: _station_quantity(data, "north")["value"] = 0.001, "must equal pilot.north.value exactly")
	_rejected("station east must exactly equal pilot east", func(data: Dictionary) -> void: _station_quantity(data, "east")["value"] = -0.001, "must equal pilot.east.value exactly")
	_rejected("station requires level field datum", func(data: Dictionary) -> void: _quantity(data, "down", true)["value"] = 0.01, "pilot.down == 0 m")

	var clearance_boundary: Dictionary = _field_with_station()
	_quantity(clearance_boundary, "eye_height", true)["value"] = 1.2
	var clearance_result: Dictionary = Loader.validate(clearance_boundary)
	_check("station top may meet the exact 0.4 m eye-height clearance", bool(clearance_result["ok"]), str(clearance_result["errors"]))
	_rejected("station top stays at least 0.4 m below eye height", func(data: Dictionary) -> void: _quantity(data, "eye_height", true)["value"] = 1.199, "at least 0.4 m below pilot.eye_height")

	_rejected("station envelope intersects runway", func(data: Dictionary) -> void: _set_pilot_and_station_xy(data, 15.0, 0.0), "envelope intersects runway surface")
	_rejected("station envelope intersects mown area", func(data: Dictionary) -> void:
		var surfaces: Array = data["surfaces"]
		surfaces.append(_surface("mown", "mown", 0.0, 0.0, 8.0, 8.0)),
		"envelope intersects mown surface 'mown'")
	_rejected("station envelope must fit inside rough surface", func(data: Dictionary) -> void: _set_pilot_and_station_xy(data, 19999.5, 0.0), "must fit inside a rough surface")
	_rejected("40 km rough enforces its 1500 m relief radius", func(data: Dictionary) -> void: _set_pilot_and_station_xy(data, 1499.0, 0.0), "40 km square rough surface center")

	var custom_flat: Dictionary = _field_with_station()
	var custom_surfaces: Array = custom_flat["surfaces"]
	custom_surfaces[0] = _surface("rough", "rough", 0.0, 0.0, 60000.0, 60000.0)
	custom_flat["surfaces"] = custom_surfaces
	_set_pilot_and_station_xy(custom_flat, 2000.0, 0.0)
	var custom_result: Dictionary = Loader.validate(custom_flat)
	_check("custom wide flat rough allows station beyond 1.5 km", bool(custom_result["ok"]), str(custom_result["errors"]))


func _test_real_default_field_when_station_exists() -> void:
	var loaded: Dictionary = Loader.load_from(DEFAULT_PATH)
	_check("real default field still loads", bool(loaded["ok"]), str(loaded["errors"]))
	if not bool(loaded["ok"]):
		return
	var field: Dictionary = loaded["field"]
	var cues: Array = field.get("flight_cues", [])
	var stations: Array[Dictionary] = []
	for cue_value: Variant in cues:
		var cue: Dictionary = cue_value
		if cue.get("type") == "pilot_station":
			stations.append(cue)
	_check("default has at most one pilot station", stations.size() <= 1, str(stations))
	if stations.size() == 1:
		var station: Dictionary = stations[0]
		var pilot: Dictionary = field["pilot"]
		_check("default station shares the pilot's exact horizontal position", station["north"] == pilot["north"] and station["east"] == pilot["east"], str(station))
		_check("default station uses bounded dimensions", station["width"] >= 1.2 and station["width"] <= 2.4 and station["depth"] >= 1.0 and station["depth"] <= 2.0 and station["height"] >= 0.6 and station["height"] <= 0.9, str(station))


func _field_with_station() -> Dictionary:
	var data: Dictionary = _field()
	data["flight_cues"] = [_valid_station()]
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


func _valid_station() -> Dictionary:
	return {
		"id": "pilot_station",
		"type": "pilot_station",
		"collides": false,
		"north": _quantity_value(0.0),
		"east": _quantity_value(0.0),
		"width": _quantity_value(1.8),
		"depth": _quantity_value(1.4),
		"height": _quantity_value(0.8),
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
	return {"value": value, "unit": "m", "kind": "estimated", "source": "L10b pilot-station policy estimate."}


func _quantity(data: Dictionary, key: String, pilot: bool = false) -> Dictionary:
	var section: Dictionary
	if pilot:
		section = data["pilot"]
	else:
		section = (data["flight_cues"] as Array)[0]
	return section[key]


func _station_quantity(data: Dictionary, key: String) -> Dictionary:
	return ((data["flight_cues"] as Array)[0] as Dictionary)[key]


func _set_pilot_and_station_xy(data: Dictionary, north: float, east: float) -> void:
	_quantity(data, "north", true)["value"] = north
	_quantity(data, "east", true)["value"] = east
	_station_quantity(data, "north")["value"] = north
	_station_quantity(data, "east")["value"] = east


func _surface(identifier: String, surface_type: String, north: float, east: float, length: float, width: float) -> Dictionary:
	return {
		"id": identifier,
		"type": surface_type,
		"center_north": _quantity_value(north),
		"center_east": _quantity_value(east),
		"length_east_west": _quantity_value(length),
		"width_north_south": _quantity_value(width),
	}
