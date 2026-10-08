## Loads an openrc-field v1 data file into a renderer-neutral, normalized dictionary.
## Quantities are metres in NED coordinates; invalid input always returns an empty field.
extends RefCounted

const DEFAULT_PATH: String = "res://data/fields/default.json"
const FORMAT: String = "openrc-field v1"
# Field coordinates feed Godot's standard float32 render positions; larger finite float64 values overflow there.
const FLOAT32_MAX: float = 3.4028234663852886e38
# L6b/L7 visual-layout assumptions, not measured field or vegetation dimensions.
const MAX_FIELD_OBJECTS: int = 1
const MAX_FLIGHT_CUES: int = 3
const MAX_FLIGHT_CUE_COORDINATE_M: float = 1000000.0
# L10a visual policy bounds are estimates; FAA Size 1 facts cover cloth length and throat only.
const WINDSOCK_POLE_MIN_M: float = 2.0
const WINDSOCK_POLE_MAX_M: float = 10.0
const WINDSOCK_LENGTH_MIN_M: float = 0.5
const WINDSOCK_LENGTH_MAX_M: float = 5.0
const WINDSOCK_THROAT_MIN_M: float = 0.1
const WINDSOCK_THROAT_MAX_M: float = 1.0
# Estimated horizontal envelope and placement margins; keep visual cue support bounded.
const WINDSOCK_CLEARANCE_M: float = 1.0
const WINDSOCK_PILOT_CLEARANCE_M: float = 2.0
# Only the exact 40 km square rough surface uses Horizon.mesh; custom rough surfaces stay flat.
const HORIZON_MESH_ROUGH_SIZE_M: float = 40000.0
const FLIGHT_CUE_HORIZON_RELIEF_RADIUS_M: float = 1500.0
const PILOT_STATION_WIDTH_MIN_M: float = 1.2
const PILOT_STATION_WIDTH_MAX_M: float = 2.4
const PILOT_STATION_DEPTH_MIN_M: float = 1.0
const PILOT_STATION_DEPTH_MAX_M: float = 2.0
const PILOT_STATION_HEIGHT_MIN_M: float = 0.6
const PILOT_STATION_HEIGHT_MAX_M: float = 0.9
# Estimated conservative ground clearance around dimensions that already include fittings and pad.
const PILOT_STATION_CLEARANCE_M: float = 0.1
const PILOT_STATION_EYE_CLEARANCE_M: float = 0.4
const PILOT_STATION_EYE_CLEARANCE_TOLERANCE_M: float = 0.000000001
# L10c visual dimensions and placement limits are estimates, not field-safety standards.
const FLIGHTLINE_BARRIER_WIDTH_MIN_M: float = 10.0
const FLIGHTLINE_BARRIER_WIDTH_MAX_M: float = 80.0
const FLIGHTLINE_BARRIER_HEIGHT_MIN_M: float = 0.5
const FLIGHTLINE_BARRIER_HEIGHT_MAX_M: float = 0.9
const FLIGHTLINE_BARRIER_GAP_MIN_M: float = 2.0
const FLIGHTLINE_BARRIER_GAP_MAX_M: float = 12.0
const FLIGHTLINE_BARRIER_HALF_DEPTH_M: float = 0.04
const FLIGHTLINE_BARRIER_CLEARANCE_M: float = 0.1
const FLIGHTLINE_BARRIER_MIN_PILOT_NORTH_M: float = 2.0
const FLIGHTLINE_BARRIER_MIN_STATION_GAP_M: float = 2.0
const FLIGHTLINE_BARRIER_MAX_STATION_DEPTH_M: float = 2.0
const FLIGHTLINE_BARRIER_RUNWAY_CLEARANCE_M: float = 1.0
const FLIGHTLINE_BARRIER_SIGHTLINE_MARGIN_M: float = 0.05
const MAX_TREELINE_POSITIONS: int = 1680
const TREE_POSITION_GRID_M: float = 0.25
const TREE_POSITION_GRID_TOLERANCE: float = 0.000001
const TREE_MIN_RADIUS_M: float = 250.0
const TREE_MAX_RADIUS_M: float = 1500.0
const TREE_CARD_MAX_HORIZONTAL_RADIUS_M: float = 15.0 # Estimated visible card envelope.
const TREE_FLIGHT_CORRIDOR_HALF_WIDTH_M: float = 35.0 # Estimated approach and low-flight clearance.
const MAX_PILOT_HORIZONTAL_COORDINATE_M: float = 1000000.0 # Keeps absolute tree coordinates stable for render/hash bounds.
const ROOT_KEYS: Array[String] = ["format", "id", "runway", "pilot", "surfaces", "objects"]
const ROOT_ALLOWED_KEYS: Array[String] = ["format", "id", "runway", "pilot", "surfaces", "objects", "flight_cues"]
const FLIGHT_CUE_KEYS: Array[String] = ["id", "type", "collides", "north", "east", "pole_height", "length", "throat_diameter", "tail_diameter"]
const PILOT_STATION_KEYS: Array[String] = ["id", "type", "collides", "north", "east", "width", "depth", "height"]
const FLIGHTLINE_BARRIER_KEYS: Array[String] = ["id", "type", "collides", "north", "east", "width", "height", "gap_width"]
const FLIGHT_CUE_TYPES: Array[String] = ["windsock", "pilot_station", "flightline_barrier"]
const RESERVED_FIELD_CUE_IDS: Array[String] = ["NearGrass", "Scenery", "FlightCueShadows"]
const PILOT_KEYS: Array[String] = ["id", "north", "east", "down", "eye_height"]
const SURFACE_KEYS: Array[String] = ["id", "type", "center_north", "center_east", "length_east_west", "width_north_south"]
const OBJECT_KEYS: Array[String] = ["id", "type", "collides", "positions"]
const QUANTITY_KEYS: Array[String] = ["value", "unit", "kind", "source"]
const SURFACE_TYPES: Array[String] = ["rough", "mown", "runway"]
const EVIDENCE_KINDS: Array[String] = ["manual", "measured", "borrowed", "estimated", "derived"]


## Result shape: {ok: bool, errors: PackedStringArray, field: Dictionary}.
static func load_from(path: String = DEFAULT_PATH) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("%s: cannot open field file (error %d)" % [path, FileAccess.get_open_error()])
	var text: String = file.get_as_text()
	file.close()
	var parser: JSON = JSON.new()
	var parse_result: Error = parser.parse(text)
	if parse_result != OK:
		return _failure("%s: JSON error at line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
	return validate(parser.data)


## Validate untrusted parsed data and unwrap each {value, unit, kind, source} quantity to a float.
static func validate(raw: Variant) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("field: expected an object")

	var root: Dictionary = raw
	_check_keys(errors, "field", root, ROOT_ALLOWED_KEYS, ROOT_KEYS)
	var format_value: Variant = root.get("format")
	if typeof(format_value) != TYPE_STRING or format_value != FORMAT:
		errors.append("format: expected '%s'" % FORMAT)

	var ids: Dictionary = {}
	var field_id: String = _register_id(errors, ids, "id", root.get("id"))
	var runway_id: String = _read_string(errors, "runway", root.get("runway"), true)

	var pilot: Dictionary = _object(errors, "pilot", root.get("pilot"))
	_check_keys(errors, "pilot", pilot, PILOT_KEYS, PILOT_KEYS)
	var pilot_id: String = _register_id(errors, ids, "pilot.id", pilot.get("id"))
	var pilot_north: float = _quantity_or_zero(errors, "pilot.north", pilot.get("north"), false)
	var pilot_east: float = _quantity_or_zero(errors, "pilot.east", pilot.get("east"), false)
	var pilot_down: float = _quantity_or_zero(errors, "pilot.down", pilot.get("down"), false)
	var eye_height: float = _quantity_or_zero(errors, "pilot.eye_height", pilot.get("eye_height"), true)
	var eye_down: float = pilot_down - eye_height
	if not is_finite(eye_down) or absf(eye_down) > FLOAT32_MAX:
		errors.append("pilot eye position (down - eye_height) exceeds the finite float32 range used by render coordinates")

	var surfaces: Array = _array(errors, "surfaces", root.get("surfaces"))
	var normalized_surfaces: Array = []
	var validated_surfaces: Array = []
	var surface_index_by_id: Dictionary = {}
	for index: int in range(surfaces.size()):
		var surface_path: String = "surfaces[%d]" % index
		var surface: Dictionary = _object(errors, surface_path, surfaces[index])
		_check_keys(errors, surface_path, surface, SURFACE_KEYS, SURFACE_KEYS)
		var surface_id: String = _register_id(errors, ids, surface_path + ".id", surface.get("id"))
		if not surface_id.is_empty():
			if surface_id != surface_id.strip_edges():
				errors.append("%s.id: leading or trailing whitespace is not allowed" % surface_path)
			var node_name: String = surface_id.validate_node_name()
			if node_name != surface_id:
				errors.append("%s.id: '%s' is not a valid Godot node name" % [surface_path, surface_id])
		var surface_type: String = _read_string(errors, surface_path + ".type", surface.get("type"), true)
		if not SURFACE_TYPES.has(surface_type):
			errors.append("%s.type: expected one of %s" % [surface_path, SURFACE_TYPES])
		var center_north: float = _quantity_or_zero(errors, surface_path + ".center_north", surface.get("center_north"), false)
		var center_east: float = _quantity_or_zero(errors, surface_path + ".center_east", surface.get("center_east"), false)
		var length_east_west: float = _quantity_or_zero(errors, surface_path + ".length_east_west", surface.get("length_east_west"), true)
		var width_north_south: float = _quantity_or_zero(errors, surface_path + ".width_north_south", surface.get("width_north_south"), true)
		var bounds: Dictionary = _rectangle_bounds(
			errors,
			surface_path,
			center_north,
			center_east,
			length_east_west,
			width_north_south
		)
		var normalized_surface: Dictionary = {
			"id": surface_id,
			"type": surface_type,
			"center_north": center_north,
			"center_east": center_east,
			"length_east_west": length_east_west,
			"width_north_south": width_north_south,
		}
		normalized_surfaces.append(normalized_surface)
		validated_surfaces.append({
			"id": surface_id,
			"type": surface_type,
			"bounds": bounds,
			"center_north": center_north,
			"length_east_west": length_east_west,
			"width_north_south": width_north_south,
		})
		if not surface_id.is_empty():
			surface_index_by_id[surface_id] = surface_type

	var objects: Array = _array(errors, "objects", root.get("objects"))
	var normalized_objects: Array = []
	if objects.size() > MAX_FIELD_OBJECTS:
		errors.append("objects: at most %d object is supported" % MAX_FIELD_OBJECTS)
	elif objects.size() == 1:
		var object_path: String = "objects[0]"
		var object_node: Dictionary = _object(errors, object_path, objects[0])
		var normalized_object: Dictionary = _validate_treeline(
			errors,
			ids,
			object_path,
			object_node,
			pilot_north,
			pilot_east,
			pilot_down,
			validated_surfaces
		)
		normalized_objects.append(normalized_object)

	var normalized_flight_cues: Array = []
	if root.has("flight_cues"):
		var flight_cues: Array = _array(errors, "flight_cues", root.get("flight_cues"))
		if flight_cues.size() > MAX_FLIGHT_CUES:
			errors.append("flight_cues: at most %d cues are supported" % MAX_FLIGHT_CUES)
		var seen_cue_types: Dictionary = {}
		var cue_count_to_validate: int = mini(flight_cues.size(), MAX_FLIGHT_CUES)
		for index: int in range(cue_count_to_validate):
			var cue_path: String = "flight_cues[%d]" % index
			var cue_node: Dictionary = _object(errors, cue_path, flight_cues[index])
			var cue_type_value: Variant = cue_node.get("type")
			var cue_type: String = String(cue_type_value) if typeof(cue_type_value) == TYPE_STRING else ""
			if FLIGHT_CUE_TYPES.has(cue_type):
				if seen_cue_types.has(cue_type):
					errors.append("flight_cues: at most one '%s' cue is supported" % cue_type)
				else:
					seen_cue_types[cue_type] = true
			normalized_flight_cues.append(_validate_flight_cue(
				errors,
				ids,
				cue_path,
				cue_node,
				pilot_north,
				pilot_east,
				pilot_down,
				eye_height,
				validated_surfaces,
				runway_id
			))

	var selected_runway_type: String = str(surface_index_by_id.get(runway_id, ""))
	if runway_id.is_empty():
		errors.append("runway: must reference a surface ID")
	elif selected_runway_type.is_empty():
		errors.append("runway: unknown surface ID '%s'" % runway_id)
	elif selected_runway_type != "runway":
		errors.append("runway: surface '%s' must have type 'runway'" % runway_id)
	_validate_flight_cue_conflicts(errors, normalized_flight_cues)

	_check_same_type_overlaps(errors, validated_surfaces)

	if not errors.is_empty():
		return {"ok": false, "errors": errors, "field": {}}
	var normalized_field: Dictionary = {
		"format": FORMAT,
		"id": field_id,
		"runway": runway_id,
		"pilot": {
			"id": pilot_id,
			"north": pilot_north,
			"east": pilot_east,
			"down": pilot_down,
			"eye_height": eye_height,
		},
		"surfaces": normalized_surfaces,
		"objects": normalized_objects,
	}
	if root.has("flight_cues"):
		normalized_field["flight_cues"] = normalized_flight_cues
	return {"ok": true, "errors": errors, "field": normalized_field}


static func _validate_flight_cue(
	errors: PackedStringArray,
	ids: Dictionary,
	path: String,
	cue: Dictionary,
	pilot_north: float,
	pilot_east: float,
	pilot_down: float,
	eye_height: float,
	surfaces: Array,
	runway_id: String
) -> Dictionary:
	var cue_type_value: Variant = cue.get("type")
	if typeof(cue_type_value) == TYPE_STRING and cue_type_value == "pilot_station":
		return _validate_pilot_station(errors, ids, path, cue, pilot_north, pilot_east, pilot_down, eye_height, surfaces)
	if typeof(cue_type_value) == TYPE_STRING and cue_type_value == "flightline_barrier":
		return _validate_flightline_barrier(errors, ids, path, cue, pilot_north, pilot_east, pilot_down, eye_height, surfaces, runway_id)
	return _validate_windsock(errors, ids, path, cue, pilot_north, pilot_east, pilot_down, surfaces)


static func _validate_flight_cue_id(errors: PackedStringArray, ids: Dictionary, path: String, cue: Dictionary) -> String:
	var identifier: String = _register_id(errors, ids, path + ".id", cue.get("id"))
	if not identifier.is_empty():
		if identifier != identifier.strip_edges():
			errors.append("%s.id: leading or trailing whitespace is not allowed" % path)
		var node_name: String = identifier.validate_node_name()
		if node_name != identifier:
			errors.append("%s.id: '%s' is not a valid Godot node name" % [path, identifier])
		if RESERVED_FIELD_CUE_IDS.has(identifier):
			errors.append("%s.id: '%s' is reserved for a generated field child" % [path, identifier])
	return identifier


static func _validate_noncolliding_flight_cue(errors: PackedStringArray, path: String, cue: Dictionary) -> void:
	var collides_value: Variant = cue.get("collides")
	if typeof(collides_value) != TYPE_BOOL:
		errors.append("%s.collides: expected a boolean" % path)
	elif collides_value:
		errors.append("%s.collides=true is unsupported; flight cues are visual only" % path)


static func _validate_windsock(
	errors: PackedStringArray,
	ids: Dictionary,
	path: String,
	cue: Dictionary,
	pilot_north: float,
	pilot_east: float,
	pilot_down: float,
	surfaces: Array
) -> Dictionary:
	_check_keys(errors, path, cue, FLIGHT_CUE_KEYS, FLIGHT_CUE_KEYS)
	var identifier: String = _validate_flight_cue_id(errors, ids, path, cue)
	var cue_type: String = _read_string(errors, path + ".type", cue.get("type"), true)
	if cue_type != "windsock":
		errors.append("%s.type: expected 'windsock' or 'pilot_station' or 'flightline_barrier'" % path)
	_validate_noncolliding_flight_cue(errors, path, cue)

	var north: float = _quantity_or_zero(errors, path + ".north", cue.get("north"), false)
	var east: float = _quantity_or_zero(errors, path + ".east", cue.get("east"), false)
	var pole_height: float = _quantity_or_zero(errors, path + ".pole_height", cue.get("pole_height"), true)
	var length: float = _quantity_or_zero(errors, path + ".length", cue.get("length"), true)
	var throat_diameter: float = _quantity_or_zero(errors, path + ".throat_diameter", cue.get("throat_diameter"), true)
	var tail_diameter: float = _quantity_or_zero(errors, path + ".tail_diameter", cue.get("tail_diameter"), true)
	_validate_bounded_dimension(errors, path + ".pole_height", pole_height, WINDSOCK_POLE_MIN_M, WINDSOCK_POLE_MAX_M)
	_validate_bounded_dimension(errors, path + ".length", length, WINDSOCK_LENGTH_MIN_M, WINDSOCK_LENGTH_MAX_M)
	_validate_bounded_dimension(errors, path + ".throat_diameter", throat_diameter, WINDSOCK_THROAT_MIN_M, WINDSOCK_THROAT_MAX_M)
	if is_finite(tail_diameter) and is_finite(throat_diameter) and tail_diameter >= throat_diameter:
		errors.append("%s.tail_diameter.value: must be less than throat_diameter" % path)
	if is_finite(pole_height) and is_finite(length) and is_finite(throat_diameter) and pole_height <= length + throat_diameter:
		errors.append("%s.pole_height.value: must exceed length + throat_diameter for calm-cloth clearance" % path)
	if is_finite(north) and absf(north) > MAX_FLIGHT_CUE_COORDINATE_M:
		errors.append("%s.north.value: must be within +/- %.0f m" % [path, MAX_FLIGHT_CUE_COORDINATE_M])
	if is_finite(east) and absf(east) > MAX_FLIGHT_CUE_COORDINATE_M:
		errors.append("%s.east.value: must be within +/- %.0f m" % [path, MAX_FLIGHT_CUE_COORDINATE_M])
	if cue_type == "windsock":
		if pilot_down != 0.0:
			errors.append("%s: windsock requires pilot.down == 0 m for flat ground" % path)
		_validate_windsock_placement(errors, path, north, east, pilot_north, pilot_east, length, throat_diameter, surfaces)
	return {
		"id": identifier,
		"type": cue_type,
		"collides": false,
		"north": north,
		"east": east,
		"pole_height": pole_height,
		"length": length,
		"throat_diameter": throat_diameter,
		"tail_diameter": tail_diameter,
	}


static func _validate_pilot_station(
	errors: PackedStringArray,
	ids: Dictionary,
	path: String,
	cue: Dictionary,
	pilot_north: float,
	pilot_east: float,
	pilot_down: float,
	eye_height: float,
	surfaces: Array
) -> Dictionary:
	_check_keys(errors, path, cue, PILOT_STATION_KEYS, PILOT_STATION_KEYS)
	var identifier: String = _validate_flight_cue_id(errors, ids, path, cue)
	var cue_type: String = _read_string(errors, path + ".type", cue.get("type"), true)
	if cue_type != "pilot_station":
		errors.append("%s.type: expected 'pilot_station'" % path)
	_validate_noncolliding_flight_cue(errors, path, cue)

	var north: float = _quantity_or_zero(errors, path + ".north", cue.get("north"), false)
	var east: float = _quantity_or_zero(errors, path + ".east", cue.get("east"), false)
	var width: float = _quantity_or_zero(errors, path + ".width", cue.get("width"), true)
	var depth: float = _quantity_or_zero(errors, path + ".depth", cue.get("depth"), true)
	var height: float = _quantity_or_zero(errors, path + ".height", cue.get("height"), true)
	_validate_bounded_dimension(errors, path + ".width", width, PILOT_STATION_WIDTH_MIN_M, PILOT_STATION_WIDTH_MAX_M)
	_validate_bounded_dimension(errors, path + ".depth", depth, PILOT_STATION_DEPTH_MIN_M, PILOT_STATION_DEPTH_MAX_M)
	_validate_bounded_dimension(errors, path + ".height", height, PILOT_STATION_HEIGHT_MIN_M, PILOT_STATION_HEIGHT_MAX_M)
	if is_finite(north) and absf(north) > MAX_FLIGHT_CUE_COORDINATE_M:
		errors.append("%s.north.value: must be within +/- %.0f m" % [path, MAX_FLIGHT_CUE_COORDINATE_M])
	if is_finite(east) and absf(east) > MAX_FLIGHT_CUE_COORDINATE_M:
		errors.append("%s.east.value: must be within +/- %.0f m" % [path, MAX_FLIGHT_CUE_COORDINATE_M])
	if is_finite(north) and is_finite(pilot_north) and north != pilot_north:
		errors.append("%s.north.value: must equal pilot.north.value exactly" % path)
	if is_finite(east) and is_finite(pilot_east) and east != pilot_east:
		errors.append("%s.east.value: must equal pilot.east.value exactly" % path)
	if pilot_down != 0.0:
		errors.append("%s: pilot_station requires pilot.down == 0 m for flat ground" % path)
	if is_finite(height) and is_finite(eye_height) and height + PILOT_STATION_EYE_CLEARANCE_M > eye_height + PILOT_STATION_EYE_CLEARANCE_TOLERANCE_M:
		errors.append("%s.height.value: station top must be at least %.1f m below pilot.eye_height" % [path, PILOT_STATION_EYE_CLEARANCE_M])
	_validate_pilot_station_placement(errors, path, north, east, width, depth, surfaces)
	return {
		"id": identifier,
		"type": cue_type,
		"collides": false,
		"north": north,
		"east": east,
		"width": width,
		"depth": depth,
		"height": height,
}


static func _validate_flightline_barrier(
	errors: PackedStringArray,
	ids: Dictionary,
	path: String,
	cue: Dictionary,
	pilot_north: float,
	pilot_east: float,
	pilot_down: float,
	eye_height: float,
	surfaces: Array,
	runway_id: String
) -> Dictionary:
	_check_keys(errors, path, cue, FLIGHTLINE_BARRIER_KEYS, FLIGHTLINE_BARRIER_KEYS)
	var identifier: String = _validate_flight_cue_id(errors, ids, path, cue)
	var cue_type: String = _read_string(errors, path + ".type", cue.get("type"), true)
	if cue_type != "flightline_barrier":
		errors.append("%s.type: expected 'flightline_barrier'" % path)
	_validate_noncolliding_flight_cue(errors, path, cue)

	var north: float = _quantity_or_zero(errors, path + ".north", cue.get("north"), false)
	var east: float = _quantity_or_zero(errors, path + ".east", cue.get("east"), false)
	var width: float = _quantity_or_zero(errors, path + ".width", cue.get("width"), true)
	var height: float = _quantity_or_zero(errors, path + ".height", cue.get("height"), true)
	var gap_width: float = _quantity_or_zero(errors, path + ".gap_width", cue.get("gap_width"), true)
	_validate_bounded_dimension(errors, path + ".width", width, FLIGHTLINE_BARRIER_WIDTH_MIN_M, FLIGHTLINE_BARRIER_WIDTH_MAX_M)
	_validate_bounded_dimension(errors, path + ".height", height, FLIGHTLINE_BARRIER_HEIGHT_MIN_M, FLIGHTLINE_BARRIER_HEIGHT_MAX_M)
	_validate_bounded_dimension(errors, path + ".gap_width", gap_width, FLIGHTLINE_BARRIER_GAP_MIN_M, FLIGHTLINE_BARRIER_GAP_MAX_M)
	if is_finite(width) and is_finite(gap_width) and gap_width > width - 4.0:
		errors.append("%s.gap_width.value: must be at least 4 m narrower than width" % path)
	if is_finite(north) and absf(north) > MAX_FLIGHT_CUE_COORDINATE_M:
		errors.append("%s.north.value: must be within +/- %.0f m" % [path, MAX_FLIGHT_CUE_COORDINATE_M])
	if is_finite(east) and absf(east) > MAX_FLIGHT_CUE_COORDINATE_M:
		errors.append("%s.east.value: must be within +/- %.0f m" % [path, MAX_FLIGHT_CUE_COORDINATE_M])
	if pilot_down != 0.0:
		errors.append("%s: flightline_barrier requires pilot.down == 0 m for flat ground" % path)
	if is_finite(east) and is_finite(pilot_east) and east != pilot_east:
		errors.append("%s.east.value: must equal pilot.east.value exactly" % path)
	if is_finite(north) and is_finite(pilot_north) and north < pilot_north + FLIGHTLINE_BARRIER_MIN_PILOT_NORTH_M:
		errors.append("%s.north.value: must be at least %.1f m north of pilot.north.value" % [path, FLIGHTLINE_BARRIER_MIN_PILOT_NORTH_M])
	_validate_flightline_barrier_placement(errors, path, north, east, width, height, pilot_north, eye_height, surfaces, runway_id)
	return {
		"id": identifier,
		"type": cue_type,
		"collides": false,
		"north": north,
		"east": east,
		"width": width,
		"height": height,
		"gap_width": gap_width,
	}


static func _validate_flightline_barrier_placement(
	errors: PackedStringArray,
	path: String,
	north: float,
	east: float,
	width: float,
	height: float,
	pilot_north: float,
	eye_height: float,
	surfaces: Array,
	runway_id: String
) -> void:
	if not is_finite(north) or not is_finite(east) or not is_finite(width):
		return
	if absf(north) > MAX_FLIGHT_CUE_COORDINATE_M or absf(east) > MAX_FLIGHT_CUE_COORDINATE_M or width <= 0.0:
		return
	var half_east: float = width * 0.5 + FLIGHTLINE_BARRIER_CLEARANCE_M
	var half_north: float = FLIGHTLINE_BARRIER_CLEARANCE_M
	var has_rough_envelope: bool = false
	var has_exact_rough_envelope: bool = false
	var exact_rough_envelopes_within_relief: bool = true
	var runway_found: bool = false
	var runway_north_min: float = 0.0
	for surface_value: Variant in surfaces:
		var surface: Dictionary = surface_value
		var bounds: Dictionary = surface["bounds"]
		var north_min: float = float(bounds["north_min"])
		var north_max: float = float(bounds["north_max"])
		var east_min: float = float(bounds["east_min"])
		var east_max: float = float(bounds["east_max"])
		if not is_finite(north_min) or not is_finite(north_max) or not is_finite(east_min) or not is_finite(east_max):
			continue
		var surface_type: String = str(surface.get("type", ""))
		if surface_type == "rough":
			var exact_horizon_surface: bool = (
				float(surface["length_east_west"]) == HORIZON_MESH_ROUGH_SIZE_M
				and float(surface["width_north_south"]) == HORIZON_MESH_ROUGH_SIZE_M
			)
			var contains_footprint: bool = (
				north - half_north >= north_min
				and north + half_north <= north_max
				and east - half_east >= east_min
				and east + half_east <= east_max
			)
			if contains_footprint:
				has_rough_envelope = true
				if exact_horizon_surface:
					has_exact_rough_envelope = true
					var rough_center_north: float = (north_min + north_max) * 0.5
					var rough_center_east: float = (east_min + east_max) * 0.5
					var corner_clear: bool = true
					for north_corner: float in [north - half_north, north + half_north]:
						for east_corner: float in [east - half_east, east + half_east]:
							var north_delta: float = north_corner - rough_center_north
							var east_delta: float = east_corner - rough_center_east
							if sqrt(north_delta * north_delta + east_delta * east_delta) >= FLIGHT_CUE_HORIZON_RELIEF_RADIUS_M:
								corner_clear = false
					exact_rough_envelopes_within_relief = exact_rough_envelopes_within_relief and corner_clear
		elif surface_type == "runway" or surface_type == "mown":
			var overlaps_surface: bool = (
				north + half_north >= north_min
				and north - half_north <= north_max
				and east + half_east >= east_min
				and east - half_east <= east_max
			)
			if overlaps_surface:
				errors.append("%s: full barrier footprint intersects %s surface '%s'" % [path, surface_type, surface.get("id", "")])
			if surface_type == "runway" and str(surface.get("id", "")) == runway_id:
				runway_found = true
				runway_north_min = north_min
	if not has_rough_envelope:
		errors.append("%s: full barrier footprint must fit inside a rough surface" % path)
	elif has_exact_rough_envelope and not exact_rough_envelopes_within_relief:
		errors.append("%s: every footprint corner must stay inside the %.0f m flat radius of the exact 40 km rough surface center" % [path, FLIGHT_CUE_HORIZON_RELIEF_RADIUS_M])
	if runway_found and north + FLIGHTLINE_BARRIER_HALF_DEPTH_M + FLIGHTLINE_BARRIER_RUNWAY_CLEARANCE_M > runway_north_min:
		errors.append("%s: full barrier row must stay at least %.1f m behind the near edge of referenced runway '%s'" % [path, FLIGHTLINE_BARRIER_RUNWAY_CLEARANCE_M, runway_id])
	elif not runway_found:
		errors.append("%s: referenced runway '%s' must be a validated runway surface" % [path, runway_id])
	if runway_found and is_finite(north) and is_finite(height) and is_finite(pilot_north) and is_finite(eye_height):
		var pilot_to_near_edge_north: float = runway_north_min - pilot_north
		if pilot_to_near_edge_north <= 0.0:
			errors.append("%s: pilot-to-runway near-edge sightline requires a positive north distance" % path)
		else:
			var barrier_to_near_edge_north: float = runway_north_min - (north + FLIGHTLINE_BARRIER_HALF_DEPTH_M)
			var maximum_barrier_top: float = eye_height * barrier_to_near_edge_north / pilot_to_near_edge_north
			if height + FLIGHTLINE_BARRIER_SIGHTLINE_MARGIN_M > maximum_barrier_top:
				errors.append("%s.height.value: barrier top plus %.2f m margin exceeds the pilot-to-runway near-edge sightline" % [path, FLIGHTLINE_BARRIER_SIGHTLINE_MARGIN_M])
	# The pilot station is centered on the pilot. Use its maximum allowed depth so cue ordering cannot weaken clearance.
	var required_station_gap: float = FLIGHTLINE_BARRIER_MIN_STATION_GAP_M + FLIGHTLINE_BARRIER_MAX_STATION_DEPTH_M * 0.5 + FLIGHTLINE_BARRIER_HALF_DEPTH_M + FLIGHTLINE_BARRIER_CLEARANCE_M
	if north - FLIGHTLINE_BARRIER_HALF_DEPTH_M - (pilot_north + FLIGHTLINE_BARRIER_MAX_STATION_DEPTH_M * 0.5) < FLIGHTLINE_BARRIER_MIN_STATION_GAP_M + FLIGHTLINE_BARRIER_CLEARANCE_M:
		errors.append("%s: barrier row must clear a maximum-depth pilot station by at least %.1f m including margin (center separation %.1f m)" % [path, FLIGHTLINE_BARRIER_MIN_STATION_GAP_M, required_station_gap])


static func _validate_flight_cue_conflicts(errors: PackedStringArray, cues: Array) -> void:
	var barrier: Dictionary = {}
	var windsock: Dictionary = {}
	for cue_value: Variant in cues:
		var cue: Dictionary = cue_value
		if cue.get("type") == "flightline_barrier":
			barrier = cue
		elif cue.get("type") == "windsock":
			windsock = cue
	if barrier.is_empty() or windsock.is_empty():
		return
	var barrier_north: float = float(barrier["north"])
	var barrier_east: float = float(barrier["east"])
	var barrier_width: float = float(barrier["width"])
	var windsock_north: float = float(windsock["north"])
	var windsock_east: float = float(windsock["east"])
	var windsock_length: float = float(windsock["length"])
	var windsock_throat: float = float(windsock["throat_diameter"])
	if not is_finite(barrier_north) or not is_finite(barrier_east) or not is_finite(barrier_width) or barrier_width <= 0.0:
		return
	if not is_finite(windsock_north) or not is_finite(windsock_east) or not is_finite(windsock_length) or not is_finite(windsock_throat):
		return
	var barrier_half_east: float = barrier_width * 0.5 + FLIGHTLINE_BARRIER_CLEARANCE_M
	var barrier_half_north: float = FLIGHTLINE_BARRIER_CLEARANCE_M
	var nearest_north: float = clampf(windsock_north, barrier_north - barrier_half_north, barrier_north + barrier_half_north)
	var nearest_east: float = clampf(windsock_east, barrier_east - barrier_half_east, barrier_east + barrier_half_east)
	var north_delta: float = windsock_north - nearest_north
	var east_delta: float = windsock_east - nearest_east
	var windsock_radius: float = windsock_length + windsock_throat + WINDSOCK_CLEARANCE_M
	if north_delta * north_delta + east_delta * east_delta <= windsock_radius * windsock_radius:
		errors.append("flight_cues: flightline_barrier full span intersects windsock conservative envelope")


static func _validate_pilot_station_placement(
	errors: PackedStringArray,
	path: String,
	north: float,
	east: float,
	width: float,
	depth: float,
	surfaces: Array
) -> void:
	if not is_finite(north) or not is_finite(east) or absf(north) > MAX_FLIGHT_CUE_COORDINATE_M or absf(east) > MAX_FLIGHT_CUE_COORDINATE_M:
		return
	if not is_finite(width) or not is_finite(depth) or width <= 0.0 or depth <= 0.0:
		return
	var half_width: float = width / 2.0
	var half_depth: float = depth / 2.0
	var envelope_radius: float = sqrt(half_width * half_width + half_depth * half_depth) + PILOT_STATION_CLEARANCE_M
	if not is_finite(envelope_radius) or envelope_radius <= 0.0:
		return
	_validate_cue_ground_envelope(errors, path, north, east, envelope_radius, surfaces, "")


static func _validate_bounded_dimension(errors: PackedStringArray, path: String, value: float, minimum: float, maximum: float) -> void:
	if not is_finite(value):
		return
	if value < minimum or value > maximum:
		errors.append("%s.value: must be within %.3f..%.3f m" % [path, minimum, maximum])


static func _validate_cue_ground_envelope(
	errors: PackedStringArray,
	path: String,
	north: float,
	east: float,
	envelope_radius: float,
	surfaces: Array,
	cue_label: String
) -> void:
	if not is_finite(north) or not is_finite(east) or not is_finite(envelope_radius) or envelope_radius <= 0.0:
		return
	if absf(north) > MAX_FLIGHT_CUE_COORDINATE_M or absf(east) > MAX_FLIGHT_CUE_COORDINATE_M:
		return
	var has_rough_envelope: bool = false
	var within_rough_relief_policy: bool = false
	for surface_value: Variant in surfaces:
		var surface: Dictionary = surface_value
		var bounds: Dictionary = surface["bounds"]
		var north_min: float = float(bounds["north_min"])
		var north_max: float = float(bounds["north_max"])
		var east_min: float = float(bounds["east_min"])
		var east_max: float = float(bounds["east_max"])
		if not is_finite(north_min) or not is_finite(north_max) or not is_finite(east_min) or not is_finite(east_max):
			continue
		var surface_type: String = str(surface.get("type", ""))
		if surface_type == "rough":
			var contains_envelope: bool = (
				north - envelope_radius >= north_min
				and north + envelope_radius <= north_max
				and east - envelope_radius >= east_min
				and east + envelope_radius <= east_max
			)
			if contains_envelope:
				has_rough_envelope = true
				var horizon_mesh_surface: bool = (
					float(surface["length_east_west"]) == HORIZON_MESH_ROUGH_SIZE_M
					and float(surface["width_north_south"]) == HORIZON_MESH_ROUGH_SIZE_M
				)
				if not horizon_mesh_surface:
					within_rough_relief_policy = true
				else:
					var rough_center_north: float = (north_min + north_max) * 0.5
					var rough_center_east: float = (east_min + east_max) * 0.5
					var north_delta: float = north - rough_center_north
					var east_delta: float = east - rough_center_east
					var rough_distance: float = sqrt(north_delta * north_delta + east_delta * east_delta)
					if rough_distance + envelope_radius < FLIGHT_CUE_HORIZON_RELIEF_RADIUS_M:
						within_rough_relief_policy = true
		elif surface_type == "runway" or surface_type == "mown":
			var nearest_north: float = clampf(north, north_min, north_max)
			var nearest_east: float = clampf(east, east_min, east_max)
			var north_delta: float = north - nearest_north
			var east_delta: float = east - nearest_east
			var rectangle_distance: float = sqrt(north_delta * north_delta + east_delta * east_delta)
			if rectangle_distance <= envelope_radius:
				var envelope_name: String = "envelope"
				if not cue_label.is_empty():
					envelope_name = "%s envelope" % cue_label
				errors.append("%s: %s intersects %s surface '%s'" % [path, envelope_name, surface_type, surface.get("id", "")])
	if not has_rough_envelope:
		errors.append("%s: envelope radius %.2f m must fit inside a rough surface" % [path, envelope_radius])
	elif not within_rough_relief_policy:
		errors.append("%s: envelope must stay within the %.0f m relief radius of the 40 km square rough surface center" % [path, FLIGHT_CUE_HORIZON_RELIEF_RADIUS_M])


static func _validate_windsock_placement(
	errors: PackedStringArray,
	path: String,
	north: float,
	east: float,
	pilot_north: float,
	pilot_east: float,
	length: float,
	throat_diameter: float,
	surfaces: Array
) -> void:
	if not is_finite(north) or not is_finite(east) or absf(north) > MAX_FLIGHT_CUE_COORDINATE_M or absf(east) > MAX_FLIGHT_CUE_COORDINATE_M:
		return
	if not is_finite(pilot_north) or not is_finite(pilot_east) or not is_finite(length) or not is_finite(throat_diameter):
		return
	var envelope_radius: float = length + throat_diameter + WINDSOCK_CLEARANCE_M
	if not is_finite(envelope_radius) or envelope_radius <= 0.0:
		return
	_validate_cue_ground_envelope(errors, path, north, east, envelope_radius, surfaces, "windsock")
	var pilot_north_delta: float = north - pilot_north
	var pilot_east_delta: float = east - pilot_east
	var pilot_distance: float = sqrt(pilot_north_delta * pilot_north_delta + pilot_east_delta * pilot_east_delta)
	if pilot_distance < envelope_radius + WINDSOCK_PILOT_CLEARANCE_M:
		errors.append("%s: pilot distance must be at least envelope radius + %.1f m" % [path, WINDSOCK_PILOT_CLEARANCE_M])


static func _validate_treeline(
	errors: PackedStringArray,
	ids: Dictionary,
	path: String,
	object_node: Dictionary,
	pilot_north: float,
	pilot_east: float,
	pilot_down: float,
	surfaces: Array
) -> Dictionary:
	_check_keys(errors, path, object_node, OBJECT_KEYS, OBJECT_KEYS)
	var identifier: String = _register_id(errors, ids, path + ".id", object_node.get("id"))
	if not identifier.is_empty():
		if identifier != identifier.strip_edges():
			errors.append("%s.id: leading or trailing whitespace is not allowed" % path)
		var node_name: String = identifier.validate_node_name()
		if node_name != identifier:
			errors.append("%s.id: '%s' is not a valid Godot node name" % [path, identifier])
	var object_type: String = _read_string(errors, path + ".type", object_node.get("type"), true)
	if object_type != "treeline":
		errors.append("%s.type: expected 'treeline'" % path)
	if object_node.has("collides"):
		var collides: Variant = object_node.get("collides")
		if typeof(collides) != TYPE_BOOL:
			errors.append("%s.collides: expected a boolean" % path)
		elif collides:
			errors.append("%s.collides=true is unsupported until L14" % path)

	if object_type == "treeline":
		if pilot_down != 0.0:
			errors.append("%s: treeline requires pilot.down == 0 m for flat ground" % path)
		if absf(pilot_north) > MAX_PILOT_HORIZONTAL_COORDINATE_M or absf(pilot_east) > MAX_PILOT_HORIZONTAL_COORDINATE_M:
			errors.append("%s: pilot north/east coordinates with trees must be within +/- %.0f m" % [path, MAX_PILOT_HORIZONTAL_COORDINATE_M])

	var raw_positions: Variant = object_node.get("positions")
	var position_quantity: Dictionary = _object(errors, path + ".positions", raw_positions)
	_check_keys(errors, path + ".positions", position_quantity, QUANTITY_KEYS, QUANTITY_KEYS)
	_check_position_metadata(errors, path + ".positions", position_quantity)
	var positions: Array[Array] = _validate_tree_positions(
		errors,
		path + ".positions.value",
		position_quantity.get("value"),
		pilot_north,
		pilot_east,
		surfaces
	)
	return {
		"id": identifier,
		"type": object_type,
		"collides": false,
		"positions": positions,
	}


static func _check_position_metadata(errors: PackedStringArray, path: String, quantity: Dictionary) -> void:
	var unit: Variant = quantity.get("unit")
	if typeof(unit) != TYPE_STRING or unit != "m":
		errors.append("%s.unit: expected 'm'" % path)
	var kind: Variant = quantity.get("kind")
	if typeof(kind) != TYPE_STRING or kind != "derived":
		errors.append("%s.kind: expected 'derived'" % path)
	var source: Variant = quantity.get("source")
	if typeof(source) != TYPE_STRING or String(source).strip_edges().is_empty():
		errors.append("%s.source: must be a nonempty string" % path)


static func _validate_tree_positions(
	errors: PackedStringArray,
	path: String,
	raw_positions: Variant,
	pilot_north: float,
	pilot_east: float,
	surfaces: Array
) -> Array[Array]:
	var normalized: Array[Array] = []
	if typeof(raw_positions) != TYPE_ARRAY:
		errors.append("%s: expected an array" % path)
		return normalized
	var positions: Array = raw_positions
	if positions.is_empty() or positions.size() > MAX_TREELINE_POSITIONS:
		errors.append("%s: expected 1..%d positions, got %d" % [path, MAX_TREELINE_POSITIONS, positions.size()])
		return normalized
	var seen_positions: Dictionary = {}
	for index: int in range(positions.size()):
		var point_path: String = "%s[%d]" % [path, index]
		var point_value: Variant = positions[index]
		if typeof(point_value) != TYPE_ARRAY:
			errors.append("%s: expected an array of 3 numbers [north, east, down]" % point_path)
			continue
		var point: Array = point_value
		if point.size() != 3:
			errors.append("%s: expected exactly 3 numbers [north, east, down]" % point_path)
			continue
		var coordinates: Array[float] = []
		var valid_numbers: bool = true
		for axis_index: int in range(3):
			var axis_name: String = ["north", "east", "down"][axis_index]
			var raw_coordinate: Variant = point[axis_index]
			if typeof(raw_coordinate) != TYPE_FLOAT and typeof(raw_coordinate) != TYPE_INT:
				errors.append("%s.%s: expected a number" % [point_path, axis_name])
				valid_numbers = false
				coordinates.append(0.0)
				continue
			var coordinate: float = float(raw_coordinate)
			coordinates.append(coordinate)
			if not is_finite(coordinate):
				errors.append("%s.%s: must be finite" % [point_path, axis_name])
				valid_numbers = false
			elif not _on_position_grid(coordinate):
				errors.append("%s.%s: must be quantized to %.2f m" % [point_path, axis_name, TREE_POSITION_GRID_M])
		if not valid_numbers:
			continue
		var north_offset: float = coordinates[0]
		var east_offset: float = coordinates[1]
		var down_offset: float = coordinates[2]
		normalized.append([north_offset, east_offset, down_offset])
		if down_offset != 0.0:
			errors.append("%s.down: treeline positions must be flat at 0 m" % point_path)
		if absf(north_offset) > TREE_MAX_RADIUS_M or absf(east_offset) > TREE_MAX_RADIUS_M:
			errors.append("%s: horizontal radius must be %.0f..%.0f m" % [point_path, TREE_MIN_RADIUS_M, TREE_MAX_RADIUS_M])
		else:
			var radius: float = sqrt(north_offset * north_offset + east_offset * east_offset)
			if radius < TREE_MIN_RADIUS_M or radius > TREE_MAX_RADIUS_M:
				errors.append("%s: horizontal radius must be %.0f..%.0f m" % [point_path, TREE_MIN_RADIUS_M, TREE_MAX_RADIUS_M])
		if absf(north_offset) <= TREE_MAX_RADIUS_M and absf(east_offset) <= TREE_MAX_RADIUS_M and down_offset == 0.0:
			var duplicate_key: String = "%d,%d,%d" % [
				roundi(north_offset / TREE_POSITION_GRID_M),
				roundi(east_offset / TREE_POSITION_GRID_M),
				roundi(down_offset / TREE_POSITION_GRID_M),
			]
			if seen_positions.has(duplicate_key):
				errors.append("%s: duplicate position (same 0.25 m grid cell as index %d)" % [point_path, int(seen_positions[duplicate_key])])
			else:
				seen_positions[duplicate_key] = index
		_validate_tree_placement(errors, point_path, pilot_north + north_offset, pilot_east + east_offset, surfaces)
	return normalized


static func _on_position_grid(value: float) -> bool:
	var grid_units: float = value / TREE_POSITION_GRID_M
	return absf(grid_units - roundf(grid_units)) <= TREE_POSITION_GRID_TOLERANCE


static func _validate_tree_placement(errors: PackedStringArray, path: String, center_north: float, center_east: float, surfaces: Array) -> void:
	if not is_finite(center_north) or not is_finite(center_east):
		return
	var has_rough_envelope: bool = false
	for surface_value: Variant in surfaces:
		var surface: Dictionary = surface_value
		var surface_type: String = str(surface.get("type", ""))
		if surface_type == "rough":
			var bounds: Dictionary = surface["bounds"]
			if (
				center_north - TREE_CARD_MAX_HORIZONTAL_RADIUS_M >= float(bounds["north_min"])
				and center_north + TREE_CARD_MAX_HORIZONTAL_RADIUS_M <= float(bounds["north_max"])
				and center_east - TREE_CARD_MAX_HORIZONTAL_RADIUS_M >= float(bounds["east_min"])
				and center_east + TREE_CARD_MAX_HORIZONTAL_RADIUS_M <= float(bounds["east_max"])
			):
				has_rough_envelope = true
		elif surface_type == "runway" or surface_type == "mown":
			var strip_center_north: float = float(surface["center_north"])
			var strip_width: float = float(surface["width_north_south"])
			var required_clearance: float = strip_width / 2.0 + TREE_FLIGHT_CORRIDOR_HALF_WIDTH_M + TREE_CARD_MAX_HORIZONTAL_RADIUS_M
			if is_finite(strip_center_north) and is_finite(strip_width) and absf(center_north - strip_center_north) <= required_clearance:
				errors.append("%s: tree center is inside the runway/mown north-south flight corridor (infinite east-west strip)" % path)
	if not has_rough_envelope:
		errors.append("%s: tree center +/- %.0f m envelope must be fully contained by a rough surface" % [path, TREE_CARD_MAX_HORIZONTAL_RADIUS_M])


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message]), "field": {}}


static func _object(errors: PackedStringArray, path: String, node: Variant) -> Dictionary:
	if typeof(node) != TYPE_DICTIONARY:
		errors.append("%s: expected an object" % path)
		return {}
	return node


static func _array(errors: PackedStringArray, path: String, node: Variant) -> Array:
	if typeof(node) != TYPE_ARRAY:
		errors.append("%s: expected an array" % path)
		return []
	return node


static func _check_keys(
	errors: PackedStringArray,
	path: String,
	node: Dictionary,
	allowed: Array[String],
	required: Array[String]
) -> void:
	for key: String in required:
		if not node.has(key):
			errors.append("%s: missing '%s'" % [path, key])
	for key_variant: Variant in node.keys():
		var key: String = str(key_variant)
		if not allowed.has(key):
			errors.append("%s: unknown key '%s'" % [path, key])


static func _read_string(errors: PackedStringArray, path: String, value: Variant, nonempty: bool) -> String:
	if typeof(value) != TYPE_STRING:
		errors.append("%s: expected a string" % path)
		return ""
	var text: String = value
	if nonempty and text.strip_edges().is_empty():
		errors.append("%s: must not be empty" % path)
	return text


static func _register_id(errors: PackedStringArray, ids: Dictionary, path: String, value: Variant) -> String:
	var identifier: String = _read_string(errors, path, value, true)
	if identifier.is_empty():
		return identifier
	if ids.has(identifier):
		errors.append("%s: duplicate ID '%s' (already used by %s)" % [path, identifier, ids[identifier]])
	else:
		ids[identifier] = path
	return identifier


static func _quantity_or_zero(errors: PackedStringArray, path: String, node: Variant, positive: bool) -> float:
	if typeof(node) != TYPE_DICTIONARY:
		errors.append("%s: expected a quantity object" % path)
		return 0.0
	var quantity: Dictionary = node
	_check_keys(errors, path, quantity, QUANTITY_KEYS, QUANTITY_KEYS)
	var unit: Variant = quantity.get("unit")
	if typeof(unit) != TYPE_STRING or unit != "m":
		errors.append("%s.unit: expected 'm'" % path)
	var kind: Variant = quantity.get("kind")
	if typeof(kind) != TYPE_STRING:
		errors.append("%s.kind: expected one of %s" % [path, EVIDENCE_KINDS])
	elif not EVIDENCE_KINDS.has(kind):
		errors.append("%s.kind: expected one of %s" % [path, EVIDENCE_KINDS])
	var source: Variant = quantity.get("source")
	if typeof(source) != TYPE_STRING or String(source).strip_edges().is_empty():
		errors.append("%s.source: must be a nonempty string" % path)
	var raw_value: Variant = quantity.get("value")
	if typeof(raw_value) != TYPE_FLOAT and typeof(raw_value) != TYPE_INT:
		errors.append("%s.value: expected a number" % path)
		return 0.0
	var numeric_value: float = float(raw_value)
	if not is_finite(numeric_value):
		errors.append("%s.value: must be finite" % path)
	elif absf(numeric_value) > FLOAT32_MAX:
		errors.append("%s.value: exceeds the finite float32 range used by render coordinates" % path)
	if positive and numeric_value <= 0.0:
		errors.append("%s.value: must be greater than zero" % path)
	elif positive and is_finite(numeric_value) and absf(numeric_value) <= FLOAT32_MAX and _render_float(numeric_value) <= 0.0:
		errors.append("%s.value: positive metre size rounds to zero in float32 render coordinates" % path)
	return numeric_value


static func _rectangle_bounds(
	errors: PackedStringArray,
	path: String,
	center_north: float,
	center_east: float,
	length_east_west: float,
	width_north_south: float
) -> Dictionary:
	var north_min: float = center_north - width_north_south / 2.0
	var north_max: float = center_north + width_north_south / 2.0
	var east_min: float = center_east - length_east_west / 2.0
	var east_max: float = center_east + length_east_west / 2.0
	var bounds: Dictionary = {
		"north_min": north_min,
		"north_max": north_max,
		"east_min": east_min,
		"east_max": east_max,
	}
	var endpoints_renderable: bool = true
	for endpoint_name: String in ["north_min", "north_max", "east_min", "east_max"]:
		var endpoint: float = bounds[endpoint_name]
		if not is_finite(endpoint):
			errors.append("%s: %s endpoint must be finite" % [path, endpoint_name])
			endpoints_renderable = false
		elif absf(endpoint) > FLOAT32_MAX:
			errors.append("%s: %s endpoint exceeds the finite float32 range used by render coordinates" % [path, endpoint_name])
			endpoints_renderable = false
	if north_min >= north_max or east_min >= east_max:
		errors.append("%s: rectangle degenerates at float64 precision" % path)
	elif endpoints_renderable and (
		_render_float(north_min) >= _render_float(north_max)
		or _render_float(east_min) >= _render_float(east_max)
	):
		errors.append("%s: rectangle degenerates at float32 render precision" % path)
	return bounds


static func _render_float(value: float) -> float:
	var packed: PackedFloat32Array = PackedFloat32Array([value])
	return float(packed[0])


static func _check_same_type_overlaps(errors: PackedStringArray, surfaces: Array) -> void:
	for first_index: int in range(surfaces.size()):
		var first: Dictionary = surfaces[first_index]
		for second_index: int in range(first_index + 1, surfaces.size()):
			var second: Dictionary = surfaces[second_index]
			if first.get("type") != second.get("type"):
				continue
			var first_bounds: Dictionary = first["bounds"]
			var second_bounds: Dictionary = second["bounds"]
			var overlap_north: bool = float(first_bounds["north_min"]) < float(second_bounds["north_max"]) and float(second_bounds["north_min"]) < float(first_bounds["north_max"])
			var overlap_east: bool = float(first_bounds["east_min"]) < float(second_bounds["east_max"]) and float(second_bounds["east_min"]) < float(first_bounds["east_max"])
			if overlap_north and overlap_east:
				errors.append("surfaces[%d] and surfaces[%d]: positive-area overlap between same-type '%s' surfaces" % [first_index, second_index, first.get("type")])
