# L5: field data is normalized only after its complete schema and geometry validate.
# Run: godot --headless --path app --script res://tests/test_field_loader.gd
extends SceneTree

const Loader := preload("res://data/field_loader.gd")
const DATA_PATH: String = "res://data/fields/default.json"

var _failures: int = 0
var _count: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _fresh_data() -> Dictionary:
	var parser: JSON = JSON.new()
	var parse_result: Error = parser.parse(FileAccess.get_file_as_string(DATA_PATH))
	_check("test fixture parses", parse_result == OK, parser.get_error_message())
	if parse_result != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	var parsed: Dictionary = parser.data
	return parsed.duplicate(true)


func _has_error(errors: PackedStringArray, needle: String) -> bool:
	for message: String in errors:
		if needle in message:
			return true
	return false


func _rejects(label: String, mutate: Callable, needle: String) -> void:
	var raw: Dictionary = _fresh_data()
	mutate.call(raw)
	var result: Dictionary = Loader.validate(raw)
	var errors: PackedStringArray = result["errors"]
	_check("rejects " + label, not bool(result["ok"]) and _has_error(errors, needle), str(errors))
	_check("invalid " + label + " has no usable field", (result["field"] as Dictionary).is_empty())


func _initialize() -> void:
	var loaded: Dictionary = Loader.load_from()
	_check("default field loads", bool(loaded["ok"]), str(loaded["errors"]))
	if bool(loaded["ok"]):
		var field: Dictionary = loaded["field"]
		var pilot: Dictionary = field["pilot"]
		var surfaces: Array = field["surfaces"]
		var rough: Dictionary = surfaces[0]
		var runway: Dictionary = surfaces[1]
		var objects: Array = field["objects"]
		var raw_objects: Array = (_fresh_data()["objects"] as Array)
		_check("normalized root layout", field.keys().size() == 6 and field.has_all(["format", "id", "runway", "pilot", "surfaces", "objects"]))
		_check("normalized identity and runway reference", field["format"] == "openrc-field v1" and field["id"] == "default" and field["runway"] == "runway")
		_check("pilot layout uses float metres", pilot.keys().size() == 5 and typeof(pilot["north"]) == TYPE_FLOAT and typeof(pilot["eye_height"]) == TYPE_FLOAT)
		_check("pilot station is historical origin with 1.7 m eye height", pilot["id"] == "pilot" and pilot["north"] == 0.0 and pilot["east"] == 0.0 and pilot["down"] == 0.0 and pilot["eye_height"] == 1.7)
		_check("rough rectangle keeps the historical 40 km visual ground", rough["id"] == "rough" and rough["type"] == "rough" and rough["center_north"] == 0.0 and rough["center_east"] == 0.0 and rough["length_east_west"] == 40000.0 and rough["width_north_south"] == 40000.0)
		_check("runway keeps Spec geometry", runway["id"] == "runway" and runway["type"] == "runway" and runway["center_north"] == 15.0 and runway["center_east"] == 0.0 and runway["length_east_west"] == 100.0 and runway["width_north_south"] == 12.0)
		_check("normalized surfaces contain only data fields", rough.keys().size() == 6 and runway.keys().size() == 6)
		_check("default objects normalize without changing their count", objects.size() == raw_objects.size() and objects.size() <= 1)
		if objects.size() == 1:
			var treeline: Dictionary = objects[0]
			var tree_positions: Array = treeline["positions"]
			_check("default treeline normalizes to renderer-neutral fields", treeline.keys().size() == 4 and treeline["id"] == "treeline" and treeline["type"] == "treeline" and treeline["collides"] == false and tree_positions.size() == 480)
	_check("default source records historical Spec rather than AMA", _default_sources_are_clear())

	var direct_invalid: Dictionary = Loader.validate("not a field")
	_check("non-object root rejected", not bool(direct_invalid["ok"]) and (direct_invalid["field"] as Dictionary).is_empty() and _has_error(direct_invalid["errors"], "expected an object"))
	var unreadable: Dictionary = Loader.load_from("res://data/fields/missing.json") # lint:ignore res_path — deliberately absent negative fixture
	_check("unreadable file returns the standard empty failure", not bool(unreadable["ok"]) and unreadable.has("errors") and (unreadable["field"] as Dictionary).is_empty())

	_rejects("unknown format", func(data: Dictionary) -> void: data["format"] = "openrc-field v2", "format")
	_rejects("unknown root key", func(data: Dictionary) -> void: data["visual_hint"] = true, "unknown key 'visual_hint'")
	_rejects("missing root key", func(data: Dictionary) -> void: data.erase("objects"), "missing 'objects'")
	_rejects("non-string root ID", func(data: Dictionary) -> void: data["id"] = 4, "id: expected a string")
	_rejects("empty root ID", func(data: Dictionary) -> void: data["id"] = "  ", "id: must not be empty")
	_rejects("duplicate root and surface IDs", func(data: Dictionary) -> void: data["id"] = "rough", "duplicate ID 'rough'")
	_rejects("duplicate pilot and root IDs", func(data: Dictionary) -> void: (data["pilot"] as Dictionary)["id"] = "default", "duplicate ID 'default'")
	_rejects("empty pilot ID", func(data: Dictionary) -> void: (data["pilot"] as Dictionary)["id"] = "", "pilot.id: must not be empty")
	_rejects("unknown nested pilot key", func(data: Dictionary) -> void: (data["pilot"] as Dictionary)["northing"] = 0.0, "unknown key 'northing'")
	_rejects("pilot section with wrong type", func(data: Dictionary) -> void: data["pilot"] = [], "pilot: expected an object")
	_rejects("wrong quantity unit", func(data: Dictionary) -> void: _pilot_quantity(data, "north")["unit"] = "ft", "pilot.north.unit: expected 'm'")
	_rejects("unknown evidence kind", func(data: Dictionary) -> void: _pilot_quantity(data, "east")["kind"] = "guess", "pilot.east.kind: expected one of")
	_rejects("empty provenance", func(data: Dictionary) -> void: _pilot_quantity(data, "down")["source"] = "  ", "pilot.down.source: must be a nonempty string")
	_rejects("non-string provenance", func(data: Dictionary) -> void: _pilot_quantity(data, "down")["source"] = 3, "pilot.down.source: must be a nonempty string")
	_rejects("missing quantity member", func(data: Dictionary) -> void: _pilot_quantity(data, "north").erase("source"), "pilot.north: missing 'source'")
	_rejects("unknown quantity member", func(data: Dictionary) -> void: _pilot_quantity(data, "north")["confidence"] = 1.0, "unknown key 'confidence'")
	_rejects("boolean is not a number", func(data: Dictionary) -> void: _pilot_quantity(data, "north")["value"] = true, "pilot.north.value: expected a number")
	_rejects("non-finite value", func(data: Dictionary) -> void: _pilot_quantity(data, "east")["value"] = NAN, "pilot.east.value: must be finite")
	_rejects("coordinate beyond renderer float range", func(data: Dictionary) -> void: _pilot_quantity(data, "east")["value"] = 1e39, "finite float32 range")
	_rejects("eye height must be positive", func(data: Dictionary) -> void: _pilot_quantity(data, "eye_height")["value"] = 0, "pilot.eye_height.value: must be greater than zero")
	_rejects("positive eye height must survive float32 conversion", func(data: Dictionary) -> void: _pilot_quantity(data, "eye_height")["value"] = 1e-50, "positive metre size rounds to zero")
	_rejects("combined pilot eye position must fit the renderer", func(data: Dictionary) -> void:
		_pilot_quantity(data, "down")["value"] = -3e38
		_pilot_quantity(data, "eye_height")["value"] = 1e38,
		"pilot eye position (down - eye_height)")
	_rejects("unknown runway reference", func(data: Dictionary) -> void: data["runway"] = "grass-strip", "unknown surface ID")
	_rejects("runway reference must name a runway surface", func(data: Dictionary) -> void: data["runway"] = "rough", "must have type 'runway'")
	_rejects("surface collection with wrong type", func(data: Dictionary) -> void: data["surfaces"] = {}, "surfaces: expected an array")
	_rejects("unknown surface key", func(data: Dictionary) -> void: (data["surfaces"] as Array)[0]["material"] = "grass", "unknown key 'material'")
	_rejects("missing rectangle dimension", func(data: Dictionary) -> void: (data["surfaces"] as Array)[0].erase("width_north_south"), "missing 'width_north_south'")
	_rejects("unknown surface type", func(data: Dictionary) -> void: (data["surfaces"] as Array)[0]["type"] = "water", "type: expected one of")
	_rejects("empty surface ID", func(data: Dictionary) -> void: (data["surfaces"] as Array)[0]["id"] = "", "surfaces[0].id: must not be empty")
	_rejects("surface ID cannot become a node path", func(data: Dictionary) -> void: (data["surfaces"] as Array)[0]["id"] = "rough/path", "not a valid Godot node name")
	_rejects("surface ID cannot be silently renamed", func(data: Dictionary) -> void: (data["surfaces"] as Array)[0]["id"] = "rough.detail", "not a valid Godot node name")
	_rejects("surface ID cannot have edge whitespace", func(data: Dictionary) -> void: (data["surfaces"] as Array)[0]["id"] = " rough", "leading or trailing whitespace")
	_rejects("duplicate surface IDs", func(data: Dictionary) -> void: (data["surfaces"] as Array)[1]["id"] = "rough", "duplicate ID 'rough'")
	_rejects("zero surface size", func(data: Dictionary) -> void: _surface_quantity(data, 0, "length_east_west")["value"] = 0, "must be greater than zero")
	_rejects("negative surface size", func(data: Dictionary) -> void: _surface_quantity(data, 0, "width_north_south")["value"] = -2, "must be greater than zero")
	_rejects("endpoint beyond renderer float range", func(data: Dictionary) -> void:
		_surface_quantity(data, 0, "center_east")["value"] = 3e38
		_surface_quantity(data, 0, "length_east_west")["value"] = 1e38,
		_surface_endpoint_error())
	_rejects("non-finite rectangle endpoint", func(data: Dictionary) -> void:
		_surface_quantity(data, 0, "center_east")["value"] = 1.7e308
		_surface_quantity(data, 0, "length_east_west")["value"] = 1.7e308,
		"endpoint must be finite")
	_rejects("rectangle collapses at float64 precision", func(data: Dictionary) -> void: _surface_quantity(data, 0, "center_north")["value"] = 1e30, "degenerates at float64 precision")
	_rejects("rectangle collapses in float32 render coordinates", func(data: Dictionary) -> void: _surface_quantity(data, 0, "length_east_west")["value"] = 1e-50, "degenerates at float32 render precision")
	_rejects("same-type surface overlap", func(data: Dictionary) -> void: _append_surface(data, _surface("rough-2", "rough", 100.0, 0.0, 50.0, 50.0)), "positive-area overlap")
	_rejects("same ID across object and surface", func(data: Dictionary) -> void: _append_object(data, {"id": "rough", "type": "treeline", "collides": false, "positions": _positions([[300.0, 0.0, 0.0]])}), "duplicate ID 'rough'")
	_rejects("object with collision is explicitly deferred", func(data: Dictionary) -> void: _append_object(data, {"id": "tree", "type": "treeline", "collides": true, "positions": _positions([[300.0, 0.0, 0.0]])}), "collides=true is unsupported until L14")
	_rejects("object type must be treeline", func(data: Dictionary) -> void: _append_object(data, {"id": "tree", "type": "rock", "collides": false, "positions": _positions([[300.0, 0.0, 0.0]])}), "type: expected 'treeline'")
	_rejects("object collision flag must be boolean", func(data: Dictionary) -> void: _append_object(data, {"id": "tree", "collides": "yes"}), "collides: expected a boolean")
	_rejects("unknown object field rejected", func(data: Dictionary) -> void: _append_object(data, {"id": "tree", "material": "wood"}), "unknown key 'material'")
	_rejects("objects must be an array", func(data: Dictionary) -> void: data["objects"] = {}, "objects: expected an array")

	var allowed_kinds: Dictionary = _fresh_data()
	_surface_quantity(allowed_kinds, 0, "center_north")["kind"] = "derived"
	_surface_quantity(allowed_kinds, 0, "center_north")["source"] = "Derived from historical Spec ground origin; not an AMA standard."
	var allowed_kind_result: Dictionary = Loader.validate(allowed_kinds)
	_check("valid evidence kinds remain available", bool(allowed_kind_result["ok"]), str(allowed_kind_result["errors"]))
	var elevated_pilot: Dictionary = _fresh_data()
	elevated_pilot["objects"] = []
	_pilot_quantity(elevated_pilot, "down")["value"] = 2.0
	var elevated_result: Dictionary = Loader.validate(elevated_pilot)
	_check("pilot down coordinate can place the camera above or below field datum", bool(elevated_result["ok"]), str(elevated_result["errors"]))

	var touching: Dictionary = _fresh_data()
	_append_surface(touching, _surface("rough-east", "rough", 0.0, 40000.0, 40000.0, 40000.0))
	var touching_result: Dictionary = Loader.validate(touching)
	_check("same-type rectangles sharing an edge are valid", bool(touching_result["ok"]), str(touching_result["errors"]))

	var mixed_priority: Dictionary = _fresh_data()
	_append_surface(mixed_priority, _surface("mown-center", "mown", 15.0, 0.0, 100.0, 12.0))
	var mixed_result: Dictionary = Loader.validate(mixed_priority)
	_check("rough, mown and runway may overlap across priority levels", bool(mixed_result["ok"]), str(mixed_result["errors"]))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _default_sources_are_clear() -> bool:
	var data: Dictionary = _fresh_data()
	var pilot: Dictionary = data["pilot"]
	for key: String in ["north", "east", "down", "eye_height"]:
		var quantity: Dictionary = pilot[key]
		var source: String = quantity["source"]
		if quantity["unit"] != "m" or quantity["kind"] != "estimated" or not source.contains("Historical Spec") or not source.contains("not an AMA"):
			return false
	var surfaces: Array = data["surfaces"]
	for surface_value: Variant in surfaces:
		var surface: Dictionary = surface_value
		for key: String in ["center_north", "center_east", "length_east_west", "width_north_south"]:
			var quantity: Dictionary = surface[key]
			var source: String = quantity["source"]
			if quantity["unit"] != "m" or quantity["kind"] != "estimated" or not source.contains("Historical Spec") or not source.contains("not an AMA"):
				return false
	return true


func _pilot_quantity(data: Dictionary, key: String) -> Dictionary:
	var pilot: Dictionary = data["pilot"]
	return pilot[key]


func _surface_quantity(data: Dictionary, surface_index: int, key: String) -> Dictionary:
	var surfaces: Array = data["surfaces"]
	var surface: Dictionary = surfaces[surface_index]
	return surface[key]


func _surface(identifier: String, surface_type: String, north: float, east: float, length: float, width: float) -> Dictionary:
	return {
		"id": identifier,
		"type": surface_type,
		"center_north": _quantity(north),
		"center_east": _quantity(east),
		"length_east_west": _quantity(length),
		"width_north_south": _quantity(width),
	}


func _quantity(value: float) -> Dictionary:
	return {
		"value": value,
		"unit": "m",
		"kind": "estimated",
		"source": "Historical Spec test fixture value, explicitly not an AMA standard.",
	}


func _append_surface(data: Dictionary, surface: Dictionary) -> void:
	var surfaces: Array = data["surfaces"]
	surfaces.append(surface)


func _append_object(data: Dictionary, object_data: Dictionary) -> void:
	data["objects"] = []
	var objects: Array = data["objects"]
	objects.append(object_data)


func _positions(points: Array) -> Dictionary:
	return {
		"value": points,
		"unit": "m",
		"kind": "derived",
		"source": "L6b loader test fixture; estimated visual layout, not surveyed dimensions.",
	}


func _surface_endpoint_error() -> String:
	return "endpoint exceeds the finite float32 range"
