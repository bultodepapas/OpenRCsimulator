# L10a: optional windsock field data is exact, bounded, and placement-safe.
# Run: godot --headless --path app --script res://tests/test_windsock_data.gd
extends SceneTree

const Loader := preload("res://data/field_loader.gd")
const DEFAULT_PATH: String = "res://data/fields/default.json"
const CUE_KEYS: Array[String] = ["id", "type", "collides", "north", "east", "pole_height", "length", "throat_diameter", "tail_diameter"]

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
	var raw: Dictionary = _field_with_cue()
	mutate.call(raw)
	var result: Dictionary = Loader.validate(raw)
	var errors: PackedStringArray = result["errors"]
	_check("rejects " + label, not bool(result["ok"]) and _has_error(errors, needle), str(errors))
	_check("invalid " + label + " has no usable field", (result["field"] as Dictionary).is_empty())


func _initialize() -> void:
	_test_optional_normalization()
	_test_valid_cue_normalization()
	_test_real_default_cue()
	_test_exact_schema_and_ids()
	_test_quantity_validation()
	_test_bounded_dimensions()
	_test_placement_validation()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _test_optional_normalization() -> void:
	var raw: Dictionary = _field()
	var omitted: Dictionary = Loader.validate(raw)
	_check("legacy field without flight_cues still validates", bool(omitted["ok"]), str(omitted["errors"]))
	if bool(omitted["ok"]):
		var field: Dictionary = omitted["field"]
		_check("absent flight_cues does not add a normalized key", not field.has("flight_cues") and field.keys().size() == 6, str(field.keys()))
	raw["flight_cues"] = []
	var empty: Dictionary = Loader.validate(raw)
	_check("empty optional flight_cues validates", bool(empty["ok"]), str(empty["errors"]))
	if bool(empty["ok"]):
		var field: Dictionary = empty["field"]
		_check("present empty flight_cues normalizes to an empty array", field.has("flight_cues") and (field["flight_cues"] as Array).is_empty())


func _test_valid_cue_normalization() -> void:
	var result: Dictionary = Loader.validate(_field_with_cue())
	_check("valid windsock data validates", bool(result["ok"]), str(result["errors"]))
	if not bool(result["ok"]):
		return
	var field: Dictionary = result["field"]
	var cues: Array = field["flight_cues"]
	_check("one cue is normalized", cues.size() == 1)
	if cues.size() != 1:
		return
	var cue: Dictionary = cues[0]
	_check("normalized cue contains only renderer data", cue.keys().size() == CUE_KEYS.size() and cue.has_all(CUE_KEYS), str(cue.keys()))
	_check("normalized cue identity and non-collision are stable", cue["id"] == "windsock" and cue["type"] == "windsock" and cue["collides"] == false)
	_check("normalized cue quantities are float metres", typeof(cue["north"]) == TYPE_FLOAT and typeof(cue["pole_height"]) == TYPE_FLOAT and cue["north"] == -6.0 and cue["east"] == -12.0 and cue["pole_height"] == 3.6 and cue["length"] == 2.5 and cue["throat_diameter"] == 0.45 and cue["tail_diameter"] == 0.18, str(cue))


func _test_real_default_cue() -> void:
	var loaded: Dictionary = Loader.load_from(DEFAULT_PATH)
	_check("default field loads with L10a cue data", bool(loaded["ok"]), str(loaded["errors"]))
	if not bool(loaded["ok"]):
		return
	var field: Dictionary = loaded["field"]
	var cues: Array = field.get("flight_cues", [])
	var windsocks: Array[Dictionary] = []
	for cue_value: Variant in cues:
		var cue: Dictionary = cue_value
		if cue.get("type") == "windsock":
			windsocks.append(cue)
	_check("default field has exactly one normalized windsock", windsocks.size() == 1, str(cues))
	if windsocks.size() == 1:
		var cue: Dictionary = windsocks[0]
		_check("default windsock matches the planned field station and FAA Size 1 dimensions", cue["id"] == "windsock" and cue["north"] == -6.0 and cue["east"] == -12.0 and cue["pole_height"] == 3.6 and cue["length"] == 2.5 and cue["throat_diameter"] == 0.45 and cue["tail_diameter"] == 0.18, str(cue))


func _test_exact_schema_and_ids() -> void:
	_rejected("flight_cues with wrong root type", func(data: Dictionary) -> void: data["flight_cues"] = null, "flight_cues: expected an array")
	_rejected("duplicate windsock type remains rejected", func(data: Dictionary) -> void:
		var duplicate: Dictionary = _valid_cue()
		duplicate["id"] = "windsock_copy"
		(data["flight_cues"] as Array).append(duplicate),
		"at most one 'windsock' cue is supported")
	_rejected("more than two flight cues", func(data: Dictionary) -> void:
		var cues: Array = data["flight_cues"]
		var second: Dictionary = _valid_cue()
		second["id"] = "windsock_copy"
		var third: Dictionary = _valid_cue()
		third["id"] = "windsock_third"
		cues.append(second)
		cues.append(third),
		"at most 2 cues are supported")
	_rejected("null cue entry", func(data: Dictionary) -> void: (data["flight_cues"] as Array)[0] = null, "flight_cues[0]: expected an object")
	for key: String in CUE_KEYS:
		_rejected("missing cue key " + key, func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary).erase(key), "missing '%s'" % key)
	_rejected("unknown cue key", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["color"] = "orange", "unknown key 'color'")
	_rejected("cue type other than windsock", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["type"] = "flag", "type: expected 'windsock' or 'pilot_station'")
	_rejected("colliding cue", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["collides"] = true, "collides=true is unsupported")
	_rejected("non-boolean collides value", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["collides"] = "false", "collides: expected a boolean")
	_rejected("ID duplicates pilot ID", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["id"] = "pilot", "duplicate ID 'pilot'")
	_rejected("ID duplicates surface ID", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["id"] = "rough", "duplicate ID 'rough'")
	_rejected("ID cannot become a node path", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["id"] = "wind/sock", "not a valid Godot node name")
	_rejected("ID cannot have edge whitespace", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["id"] = " windsock", "leading or trailing whitespace")
	_rejected("ID cannot steal the near-grass child name", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["id"] = "NearGrass", "reserved for a generated field child")
	_rejected("ID cannot steal the scenery child name", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["id"] = "Scenery", "reserved for a generated field child")


func _test_quantity_validation() -> void:
	_rejected("quantity with null value", func(data: Dictionary) -> void: _quantity(data, "north")["value"] = null, "north.value: expected a number")
	_rejected("boolean quantity is not numeric", func(data: Dictionary) -> void: _quantity(data, "length")["value"] = true, "length.value: expected a number")
	_rejected("non-finite cue coordinate", func(data: Dictionary) -> void: _quantity(data, "north")["value"] = NAN, "north.value: must be finite")
	_rejected("non-finite cue dimension", func(data: Dictionary) -> void: _quantity(data, "length")["value"] = INF, "length.value: must be finite")
	_rejected("coordinate is bounded to one million metres", func(data: Dictionary) -> void: _quantity(data, "north")["value"] = 1000001.0, "north.value: must be within +/- 1000000 m")
	_rejected("wrong cue quantity unit", func(data: Dictionary) -> void: _quantity(data, "east")["unit"] = "ft", "east.unit: expected 'm'")
	_rejected("unknown cue evidence kind", func(data: Dictionary) -> void: _quantity(data, "tail_diameter")["kind"] = "assumed", "tail_diameter.kind: expected one of")
	_rejected("empty cue provenance", func(data: Dictionary) -> void: _quantity(data, "length")["source"] = "  ", "length.source: must be a nonempty string")
	_rejected("non-string cue provenance", func(data: Dictionary) -> void: _quantity(data, "east")["source"] = 3, "east.source: must be a nonempty string")
	_rejected("missing quantity value", func(data: Dictionary) -> void: _quantity(data, "north").erase("value"), "north: missing 'value'")
	_rejected("missing quantity unit", func(data: Dictionary) -> void: _quantity(data, "east").erase("unit"), "east: missing 'unit'")
	_rejected("missing quantity evidence kind", func(data: Dictionary) -> void: _quantity(data, "tail_diameter").erase("kind"), "tail_diameter: missing 'kind'")
	_rejected("missing quantity provenance", func(data: Dictionary) -> void: _quantity(data, "north").erase("source"), "north: missing 'source'")
	_rejected("unknown quantity metadata", func(data: Dictionary) -> void: _quantity(data, "pole_height")["confidence"] = 1.0, "unknown key 'confidence'")
	_rejected("quantity must be an object", func(data: Dictionary) -> void: ((data["flight_cues"] as Array)[0] as Dictionary)["east"] = null, "east: expected a quantity object")


func _test_bounded_dimensions() -> void:
	_rejected("pole below visual policy range", func(data: Dictionary) -> void: _quantity(data, "pole_height")["value"] = 1.99, "pole_height.value: must be within 2.000..10.000 m")
	_rejected("pole above visual policy range", func(data: Dictionary) -> void: _quantity(data, "pole_height")["value"] = 10.01, "pole_height.value: must be within 2.000..10.000 m")
	_rejected("sock length below visual policy range", func(data: Dictionary) -> void: _quantity(data, "length")["value"] = 0.49, "length.value: must be within 0.500..5.000 m")
	_rejected("sock length above visual policy range", func(data: Dictionary) -> void: _quantity(data, "length")["value"] = 5.01, "length.value: must be within 0.500..5.000 m")
	_rejected("throat below visual policy range", func(data: Dictionary) -> void: _quantity(data, "throat_diameter")["value"] = 0.099, "throat_diameter.value: must be within 0.100..1.000 m")
	_rejected("throat above visual policy range", func(data: Dictionary) -> void: _quantity(data, "throat_diameter")["value"] = 1.01, "throat_diameter.value: must be within 0.100..1.000 m")
	_rejected("tail diameter must be positive", func(data: Dictionary) -> void: _quantity(data, "tail_diameter")["value"] = 0.0, "tail_diameter.value: must be greater than zero")
	_rejected("tail diameter must be narrower than throat", func(data: Dictionary) -> void: _quantity(data, "tail_diameter")["value"] = 0.45, "tail_diameter.value: must be less than throat_diameter")
	_rejected("pole must clear calm cloth length and throat", func(data: Dictionary) -> void: _quantity(data, "pole_height")["value"] = 2.95, "pole_height.value: must exceed length + throat_diameter")


func _test_placement_validation() -> void:
	_rejected("cue requires level field datum", func(data: Dictionary) -> void: _quantity(data, "down", true)["value"] = 0.5, "pilot.down == 0 m")
	_rejected("windsock envelope intersects runway", func(data: Dictionary) -> void:
		_quantity(data, "north")["value"] = 12.0
		_quantity(data, "east")["value"] = 0.0,
		"envelope intersects runway surface")
	_rejected("windsock envelope intersects mown area", func(data: Dictionary) -> void:
		var surfaces: Array = data["surfaces"]
		surfaces.append(_surface("mown", "mown", -6.0, -12.0, 10.0, 10.0)),
		"envelope intersects mown surface 'mown'")
	_rejected("windsock envelope must fit inside rough", func(data: Dictionary) -> void: _quantity(data, "east")["value"] = 20000.0, "must fit inside a rough surface")
	_rejected("40 km square rough enforces its Horizon relief radius", func(data: Dictionary) -> void:
		_quantity(data, "north")["value"] = 1497.0
		_quantity(data, "east")["value"] = 0.0,
		"40 km square rough surface center")
	var custom_flat: Dictionary = _field_with_cue()
	var custom_surfaces: Array = custom_flat["surfaces"]
	custom_surfaces[0] = _surface("rough", "rough", 0.0, 0.0, 60000.0, 60000.0)
	custom_flat["surfaces"] = custom_surfaces
	_quantity(custom_flat, "north")["value"] = 2000.0
	_quantity(custom_flat, "east")["value"] = 0.0
	var custom_result: Dictionary = Loader.validate(custom_flat)
	_check("custom wide flat rough allows a cue beyond 1.5 km", bool(custom_result["ok"]), str(custom_result["errors"]))
	_rejected("windsock clears pilot envelope", func(data: Dictionary) -> void:
		_quantity(data, "north")["value"] = -5.5
		_quantity(data, "east")["value"] = 0.0,
		"pilot distance must be at least envelope radius")


func _field_with_cue() -> Dictionary:
	var data: Dictionary = _field()
	data["flight_cues"] = [_valid_cue()]
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


func _valid_cue() -> Dictionary:
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
	return {"value": value, "unit": "m", "kind": "estimated", "source": "L10a visual policy estimate; FAA Size 1 dimensions where specified."}


func _quantity(data: Dictionary, key: String, pilot: bool = false) -> Dictionary:
	var section: Dictionary
	if pilot:
		section = data["pilot"]
	else:
		section = (data["flight_cues"] as Array)[0]
	return section[key]


func _surface(identifier: String, surface_type: String, north: float, east: float, length: float, width: float) -> Dictionary:
	return {
		"id": identifier,
		"type": surface_type,
		"center_north": _quantity_value(north),
		"center_east": _quantity_value(east),
		"length_east_west": _quantity_value(length),
		"width_north_south": _quantity_value(width),
	}
