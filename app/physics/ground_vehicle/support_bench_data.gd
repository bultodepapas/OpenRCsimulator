# RCV four-corner support input. This is a synthetic research bench, not a vehicle tune.
# Coordinates: x forward, y left, z up. Corners are ordered FL, FR, RL, RR.
extends RefCounted

const FourCorner := preload("res://physics/ground_vehicle/four_corner.gd")

const FORMAT := "openrc-support-bench"
const VERSION := 1
const TOP_LEVEL_KEYS := ["format", "version", "id", "description", "parameters"]
const UNITS := {
	"sprung_mass_kg": "kg",
	"unsprung_mass_kg": "kg",
	"suspension_stiffness_n_per_m": "N/m",
	"suspension_damping_n_s_per_m": "N*s/m",
	"tire_stiffness_n_per_m": "N/m",
	"gravity_m_per_s2": "m/s^2",
	"suspension_rest_length_m": "m",
	"tire_radius_m": "m",
	"roll_inertia_kg_m2": "kg*m^2",
	"pitch_inertia_kg_m2": "kg*m^2",
	"front_axle_x_m": "m",
	"rear_axle_x_m": "m",
	"half_track_m": "m",
}
const KINDS := ["manual", "measured", "derived", "borrowed", "estimated"]
const NONNEGATIVE_FIELDS := ["suspension_damping_n_s_per_m", "gravity_m_per_s2"]


static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _result(PackedStringArray(["Cannot read support bench: " + path]))
	var source: String = file.get_as_text()
	file.close()
	return parse_text(source)


static func parse_text(source: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return _result(PackedStringArray([
			"Invalid support bench JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		]))
	return validate(parser.data)


## Atomic: rejected input returns no parameters and is never mutated.
static func validate(data: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if not data is Dictionary:
		return _result(PackedStringArray(["Support bench must be an object"]))
	_exact_keys(data, TOP_LEVEL_KEYS, "bench", errors)
	if data.get("format") != FORMAT:
		errors.append("Unsupported support bench format")
	if not _number(data.get("version")) or float(data.get("version", -1.0)) != float(VERSION):
		errors.append("Unsupported support bench version")
	if not _text(data.get("id")):
		errors.append("bench.id must be nonempty text")
	if not _text(data.get("description")):
		errors.append("bench.description must be nonempty text")

	var raw: Variant = data.get("parameters")
	if not raw is Dictionary:
		errors.append("bench.parameters must be an object")
		return _result(errors)
	_exact_keys(raw, UNITS.keys(), "parameters", errors)
	var parameters := {}
	for key: String in UNITS:
		var quantity: Variant = raw.get(key)
		if not quantity is Dictionary:
			errors.append("parameters.%s must be a quantity object" % key)
			continue
		_exact_keys(quantity, ["value", "unit", "kind", "source"], "parameters." + key, errors)
		if quantity.get("unit") != UNITS[key]:
			errors.append("parameters.%s requires unit %s" % [key, UNITS[key]])
		if not quantity.get("kind") in KINDS:
			errors.append("parameters.%s has an unsupported provenance kind" % key)
		if not _text(quantity.get("source")):
			errors.append("parameters.%s requires a nonempty source" % key)
		var value: Variant = quantity.get("value")
		if not _number(value):
			errors.append("parameters.%s must be a finite number (not a boolean)" % key)
			continue
		var minimum_is_zero: bool = key in NONNEGATIVE_FIELDS
		var axle_station: bool = key in ["front_axle_x_m", "rear_axle_x_m"]
		if minimum_is_zero and float(value) < 0.0:
			errors.append("parameters.%s must be nonnegative" % key)
		elif not minimum_is_zero and not axle_station and float(value) <= 0.0:
			errors.append("parameters.%s must be positive" % key)
		parameters[key] = float(value)
	if not errors.is_empty():
		return _result(errors)

	if parameters.front_axle_x_m <= 0.0:
		errors.append("parameters.front_axle_x_m must be forward of the CG")
	if parameters.rear_axle_x_m >= 0.0:
		errors.append("parameters.rear_axle_x_m must be aft of the CG")
	if parameters.half_track_m <= 0.0:
		errors.append("parameters.half_track_m must be positive")
	if not errors.is_empty():
		return _result(errors)

	parameters["corner_x_m"] = PackedFloat64Array([
		parameters.front_axle_x_m,
		parameters.front_axle_x_m,
		parameters.rear_axle_x_m,
		parameters.rear_axle_x_m,
	])
	parameters["corner_y_m"] = PackedFloat64Array([
		parameters.half_track_m,
		-parameters.half_track_m,
		parameters.half_track_m,
		-parameters.half_track_m,
	])
	_check_static_pose(parameters, errors)
	if not errors.is_empty():
		return _result(errors)
	return _result(errors, parameters, str(data.get("id", "")))


## Check the real seven-DOF flat-road solve. Positive spring length and hub height
## reject inverted mounts and a tire compressed through its full radius.
static func _check_static_pose(parameters: Dictionary, errors: PackedStringArray) -> void:
	var flat_road := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var equilibrium: Dictionary = FourCorner.equilibrium(parameters, flat_road)
	if not bool(equilibrium.get("ok", false)):
		var details: PackedStringArray = equilibrium.get("errors", PackedStringArray())
		errors.append_array(details)
		return
	var state: PackedFloat64Array = equilibrium.state
	var loads: Dictionary = FourCorner.loads(state, parameters, flat_road)
	var tire_force: PackedFloat64Array = loads.tire_force_n
	var suspension_compression: PackedFloat64Array = loads.suspension_compression_m
	var tire_compression: PackedFloat64Array = loads.tire_compression_m
	if (
		tire_force.size() != FourCorner.CORNER_COUNT
		or suspension_compression.size() != FourCorner.CORNER_COUNT
		or tire_compression.size() != FourCorner.CORNER_COUNT
	):
		errors.append("Flat-road equilibrium returned invalid corner arrays")
		return
	for corner in FourCorner.CORNER_COUNT:
		var spring_length_m: float = parameters.suspension_rest_length_m - suspension_compression[corner]
		var hub_height_m: float = state[FourCorner.HUB_FL + corner]
		if not is_finite(tire_force[corner]) or not is_finite(spring_length_m) or not is_finite(hub_height_m):
			errors.append("Flat-road equilibrium contains non-finite corner geometry or loads")
			return
		var gravity_is_zero: bool = parameters.gravity_m_per_s2 == 0.0
		if tire_force[corner] < 0.0 or (not gravity_is_zero and tire_force[corner] <= 0.0):
			errors.append("Flat-road equilibrium requires positive tire load at every corner")
		if spring_length_m <= 0.0:
			errors.append("Flat-road suspension mount separation must stay positive at every corner")
		if hub_height_m <= 0.0:
			errors.append("Flat-road tire sag must leave positive hub height at every corner")


static func _exact_keys(data: Dictionary, allowed: Array, path: String, errors: PackedStringArray) -> void:
	for key in allowed:
		if not data.has(key):
			errors.append("%s.%s is required" % [path, key])
	for key in data:
		if not key in allowed:
			errors.append("Unknown field %s.%s" % [path, key])


static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()


static func _result(errors: PackedStringArray, parameters := {}, id := "") -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"parameters": parameters if errors.is_empty() else {},
		"id": id if errors.is_empty() else "",
	}
