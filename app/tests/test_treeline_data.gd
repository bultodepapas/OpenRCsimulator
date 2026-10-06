# L6b: validates the renderer-neutral, non-colliding treeline field object.
# Run: godot --headless --path app --script res://tests/test_treeline_data.gd
extends SceneTree

const Loader := preload("res://data/field_loader.gd")
const DATA_PATH: String = "res://data/fields/default.json"
const GRID_M: float = 0.25

var _failures: int = 0
var _count: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _base_data() -> Dictionary:
	var parser: JSON = JSON.new()
	var parse_result: Error = parser.parse(FileAccess.get_file_as_string(DATA_PATH))
	_check("test fixture parses", parse_result == OK, parser.get_error_message())
	if parse_result != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parser.data.duplicate(true)
	data["objects"] = []
	return data


func _tree(points: Array) -> Dictionary:
	return {
		"id": "treeline",
		"type": "treeline",
		"collides": false,
		"positions": {
			"value": points,
			"unit": "m",
			"kind": "derived",
			"source": "L6b test fixture; estimated visual placement, not surveyed dimensions.",
		},
	}


func _with_treeline(points: Array) -> Dictionary:
	var data: Dictionary = _base_data()
	data["objects"] = [_tree(points)]
	return data


func _tree_object(data: Dictionary) -> Dictionary:
	var objects: Array = data["objects"]
	return objects[0]


func _positions_quantity(data: Dictionary) -> Dictionary:
	var tree_object: Dictionary = _tree_object(data)
	return tree_object["positions"]


func _position_value(data: Dictionary) -> Array:
	var quantity: Dictionary = _positions_quantity(data)
	return quantity["value"]


func _pilot_quantity(data: Dictionary, key: String) -> Dictionary:
	var pilot: Dictionary = data["pilot"]
	return pilot[key]


func _surface_quantity(data: Dictionary, index: int, key: String) -> Dictionary:
	var surfaces: Array = data["surfaces"]
	var surface: Dictionary = surfaces[index]
	return surface[key]


func _quantity(value: float) -> Dictionary:
	return {
		"value": value,
		"unit": "m",
		"kind": "estimated",
		"source": "L6b test fixture surface placement; not a surveyed dimension.",
	}


func _surface(identifier: String, surface_type: String, north: float, east: float, length: float, width: float) -> Dictionary:
	return {
		"id": identifier,
		"type": surface_type,
		"center_north": _quantity(north),
		"center_east": _quantity(east),
		"length_east_west": _quantity(length),
		"width_north_south": _quantity(width),
	}


func _add_surface(data: Dictionary, surface: Dictionary) -> void:
	var surfaces: Array = data["surfaces"]
	surfaces.append(surface)


func _has_error(errors: PackedStringArray, needle: String) -> bool:
	for message: String in errors:
		if needle in message:
			return true
	return false


func _rejects(label: String, data: Dictionary, needle: String) -> Dictionary:
	var result: Dictionary = Loader.validate(data)
	var errors: PackedStringArray = result["errors"]
	_check("rejects " + label, not bool(result["ok"]) and _has_error(errors, needle), str(errors))
	_check("invalid " + label + " has no normalized field", (result["field"] as Dictionary).is_empty())
	return result


func _initialize() -> void:
	var default_result: Dictionary = Loader.load_from()
	_check("generated default treeline loads", bool(default_result["ok"]), str(default_result["errors"]))
	if bool(default_result["ok"]):
		var default_field: Dictionary = default_result["field"]
		var default_objects: Array = default_field["objects"]
		_check("default field normalizes one treeline", default_objects.size() == 1)
		if default_objects.size() == 1:
			var default_tree: Dictionary = default_objects[0]
			var default_positions: Array = default_tree["positions"]
			_check("default field normalizes all 480 positions", default_positions.size() == 480)

	var valid: Dictionary = Loader.validate(_with_treeline([[300.0, 0.0, 0.0]]))
	_check("valid treeline is accepted", bool(valid["ok"]), str(valid["errors"]))
	if bool(valid["ok"]):
		var field: Dictionary = valid["field"]
		var objects: Array = field["objects"]
		var normalized_tree: Dictionary = objects[0]
		var positions: Array = normalized_tree["positions"]
		var point: Array = positions[0]
		_check("normalized object has only id, type, collides and positions", normalized_tree.keys().size() == 4 and normalized_tree.has_all(["id", "type", "collides", "positions"]))
		_check("normalized position is three float metre offsets", point.size() == 3 and typeof(point[0]) == TYPE_FLOAT and typeof(point[1]) == TYPE_FLOAT and typeof(point[2]) == TYPE_FLOAT and point == [300.0, 0.0, 0.0])

	var data: Dictionary = _with_treeline([[300.0, 0.0, 0.0]])
	_tree_object(data)["material"] = "pine"
	_rejects("unknown treeline object key", data, "unknown key 'material'")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_tree_object(data)["type"] = "tree"
	_rejects("unknown object type", data, "type: expected 'treeline'")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_tree_object(data).erase("collides")
	_rejects("collides is mandatory", data, "missing 'collides'")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_tree_object(data)["collides"] = true
	_rejects("colliding objects retain the L14 diagnostic", data, "objects[0].collides=true is unsupported until L14")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_tree_object(data)["collides"] = "false"
	_rejects("collision flag must be boolean", data, "objects[0].collides: expected a boolean")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	data["objects"] = [null, {"id": "bad"}]
	var too_many: Dictionary = _rejects("more than one object is rejected before nested checks", data, "at most 1 object")
	_check("object count limit precedes nested validation", not _has_error(too_many["errors"], "objects[0]"), str(too_many["errors"]))

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_tree_object(data)["id"] = "tree/path"
	_rejects("object ID must be a valid node name", data, "not a valid Godot node name")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_tree_object(data)["id"] = "rough"
	_rejects("object ID must be unique across surfaces", data, "duplicate ID 'rough'")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_tree_object(data).erase("positions")
	_rejects("positions quantity is mandatory", data, "missing 'positions'")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_tree_object(data)["positions"] = []
	_rejects("positions quantity must be an object", data, "objects[0].positions: expected an object")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_positions_quantity(data)["extra"] = 1
	_rejects("unknown positions quantity key", data, "unknown key 'extra'")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_positions_quantity(data).erase("unit")
	_rejects("positions unit is mandatory", data, "missing 'unit'")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_positions_quantity(data)["unit"] = "ft"
	_rejects("positions unit must be metres", data, "positions.unit: expected 'm'")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_positions_quantity(data)["kind"] = "estimated"
	_rejects("positions evidence kind must be derived", data, "positions.kind: expected 'derived'")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_positions_quantity(data)["source"] = "  "
	_rejects("positions provenance must be explicit", data, "positions.source: must be a nonempty string")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_positions_quantity(data)["value"] = true
	_rejects("positions value must be an array", data, "positions.value: expected an array")

	data = _with_treeline([])
	_rejects("empty positions rejected", data, "expected 1..800 positions, got 0")

	var malformed_positions: Array = []
	for index: int in range(801):
		malformed_positions.append([])
	data = _with_treeline(malformed_positions)
	var too_many_positions: Dictionary = _rejects("more than 800 positions are rejected before point checks", data, "expected 1..800 positions, got 801")
	_check("position count limit precedes nested validation", not _has_error(too_many_positions["errors"], "positions.value[0]"), str(too_many_positions["errors"]))

	data = _with_treeline([{}])
	_rejects("position entry must be an array", data, "expected an array of 3 numbers")

	data = _with_treeline([[300.0, 0.0]])
	_rejects("position entry must contain exactly three values", data, "expected exactly 3 numbers")

	data = _with_treeline([[300.0, 0.0, true]])
	_rejects("boolean position coordinate is rejected", data, "positions.value[0].down: expected a number")

	data = _with_treeline([[NAN, 0.0, 0.0]])
	_rejects("non-finite position coordinate is rejected", data, "positions.value[0].north: must be finite")

	data = _with_treeline([[300.125, 0.0, 0.0]])
	_rejects("position must be quantized to a quarter metre", data, "must be quantized to 0.25 m")

	data = _with_treeline([[300.0, 0.0, 0.25]])
	_rejects("treeline must lie on flat ground", data, "treeline positions must be flat at 0 m")

	data = _with_treeline([[249.75, 0.0, 0.0]])
	_rejects("radius below 250 metres is rejected", data, "horizontal radius must be 250..600 m")

	data = _with_treeline([[600.25, 0.0, 0.0]])
	_rejects("radius above 600 metres is rejected", data, "horizontal radius must be 250..600 m")

	data = _with_treeline([[300.0, 0.0, 0.0], [300.0, 0.0, 0.0]])
	_rejects("duplicate positions are rejected", data, "duplicate position")

	data = _with_treeline([[0.0, 300.0, 0.0]])
	_rejects("runway corridor extends east-west without a finite end", data, "infinite east-west strip")

	data = _with_treeline([[71.0, 300.0, 0.0]])
	_rejects("runway corridor boundary is excluded", data, "flight corridor")

	var corridor_edge: Dictionary = Loader.validate(_with_treeline([[71.25, 300.0, 0.0]]))
	_check("tree just beyond runway corridor is accepted", bool(corridor_edge["ok"]), str(corridor_edge["errors"]))

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_add_surface(data, _surface("mown", "mown", 300.0, 0.0, 1000.0, 20.0))
	_rejects("mown surface has the same infinite flight corridor", data, "runway/mown north-south flight corridor")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_surface_quantity(data, 0, "center_north")["value"] = 300.0
	_surface_quantity(data, 0, "center_east")["value"] = 0.0
	_surface_quantity(data, 0, "length_east_west")["value"] = 20.0
	_surface_quantity(data, 0, "width_north_south")["value"] = 20.0
	_rejects("rough surface must contain the whole 15 metre envelope", data, "must be fully contained by a rough surface")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_pilot_quantity(data, "down")["value"] = 0.25
	_rejects("pilot datum must be flat when trees are present", data, "pilot.down == 0 m for flat ground")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_pilot_quantity(data, "north")["value"] = 1000000.25
	_rejects("large absolute pilot coordinates with trees are rejected", data, "pilot north/east coordinates with trees")

	data = _with_treeline([[300.0, 0.0, 0.0]])
	_pilot_quantity(data, "north")["value"] = 1000.0
	_pilot_quantity(data, "east")["value"] = -500.0
	var shifted: Dictionary = Loader.validate(data)
	_check("trees use pilot-relative positions at a shifted pilot station", bool(shifted["ok"]), str(shifted["errors"]))

	var maximum_positions: Array = _unique_ring_positions(800)
	data = _with_treeline(maximum_positions)
	_surface_quantity(data, 1, "center_north")["value"] = 2000.0
	var maximum: Dictionary = Loader.validate(data)
	_check("exactly 800 valid positions are accepted", bool(maximum["ok"]), str(maximum["errors"]))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _unique_ring_positions(count: int) -> Array:
	var positions: Array = []
	for index: int in range(count):
		var angle: float = TAU * float(index) / float(count)
		var north: float = roundf(cos(angle) * 300.0 / GRID_M) * GRID_M
		var east: float = roundf(sin(angle) * 300.0 / GRID_M) * GRID_M
		positions.append([north, east, 0.0])
	return positions
