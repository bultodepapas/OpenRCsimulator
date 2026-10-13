# RCV-04a: strict research-bench input. This is not a truck configuration or catalog entry.
extends RefCounted

const FORMAT := "openrc-suspension-bench"
const VERSION := 1
const UNITS := {
	"sprung_mass_kg": "kg",
	"unsprung_mass_kg": "kg",
	"suspension_stiffness_n_per_m": "N/m",
	"suspension_damping_n_s_per_m": "N*s/m",
	"tire_stiffness_n_per_m": "N/m",
	"gravity_m_per_s2": "m/s^2",
	"suspension_rest_length_m": "m",
	"tire_radius_m": "m",
}
const KINDS := ["manual", "measured", "derived", "borrowed", "estimated"]


static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _result(PackedStringArray(["Cannot read suspension bench: " + path]))
	return parse_text(file.get_as_text())


static func parse_text(source: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return _result(PackedStringArray(["Invalid bench JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]]))
	return validate(parser.data)


## Atomic: failed validation never exposes partial parameters. Input is never mutated.
static func validate(data: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if not data is Dictionary:
		return _result(PackedStringArray(["Bench must be an object"]))
	_exact_keys(data, ["format", "version", "id", "description", "parameters"], "bench", errors)
	if data.get("format") != FORMAT:
		errors.append("Unsupported bench format")
	if not _number(data.get("version")) or float(data.get("version", -1)) != VERSION:
		errors.append("Unsupported bench version")
	for key in ["id", "description"]:
		if not _text(data.get(key)):
			errors.append("bench.%s must be nonempty text" % key)
	var raw: Variant = data.get("parameters")
	if not raw is Dictionary:
		errors.append("bench.parameters must be an object")
		return _result(errors)
	_exact_keys(raw, UNITS.keys(), "parameters", errors)
	var parameters := {}
	for key in UNITS:
		var q: Variant = raw.get(key)
		if not q is Dictionary:
			errors.append("parameters.%s must be a quantity object" % key)
			continue
		_exact_keys(q, ["value", "unit", "kind", "source"], "parameters." + key, errors)
		if q.get("unit") != UNITS[key]:
			errors.append("parameters.%s requires unit %s" % [key, UNITS[key]])
		if not q.get("kind") in KINDS:
			errors.append("parameters.%s has an unsupported provenance kind" % key)
		if not _text(q.get("source")):
			errors.append("parameters.%s requires a nonempty source" % key)
		var value: Variant = q.get("value")
		if not _number(value):
			errors.append("parameters.%s must be a finite number (not a boolean)" % key)
			continue
		var nonnegative: bool = key in ["suspension_damping_n_s_per_m", "gravity_m_per_s2"]
		if float(value) < 0.0 or (not nonnegative and float(value) == 0.0):
			errors.append("parameters.%s must be %s" % [key, "nonnegative" if nonnegative else "positive"])
		parameters[key] = float(value)
	if errors.is_empty():
		# The nominal flat-road pose must not invert the spring or collapse the tire.
		var ms: float = parameters.sprung_mass_kg
		var mu: float = parameters.unsprung_mass_kg
		var g: float = parameters.gravity_m_per_s2
		var spring_sag: float = ms * g / parameters.suspension_stiffness_n_per_m
		var tire_sag: float = (ms + mu) * g / parameters.tire_stiffness_n_per_m
		if not is_finite(spring_sag) or spring_sag >= parameters.suspension_rest_length_m:
			errors.append("Static suspension compression must be less than its rest length")
		if not is_finite(tire_sag) or tire_sag >= parameters.tire_radius_m:
			errors.append("Static tire compression must be less than its radius")
	return _result(errors, parameters, str(data.get("id", "")))


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
	return {"ok": errors.is_empty(), "errors": errors,
		"parameters": parameters if errors.is_empty() else {}, "id": id if errors.is_empty() else ""}
