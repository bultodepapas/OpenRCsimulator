## NITRO-01: closed, provenance-bearing standalone glow profiles. Not aircraft capabilities.
extends RefCounted

const FORMAT := "openrc-glow-engine v1"
const CONTRACT := "res://data/glow/profile_contract.json"
const KINDS := ["manual", "measured", "borrowed", "estimated", "derived"]
const ROOT_KEYS := ["format", "id", "manufacturer", "model", "family", "status", "feed", "oil_model", "parameters", "fuel", "operation"]


static func load_file(path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return _fail("Cannot read glow profile: " + path)
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		return _fail("Invalid glow profile JSON: " + json.get_error_message())
	var result: Dictionary = prepare(json.data)
	if result.ok:
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(bytes)
		result.input_identity = {format = FORMAT, sha256 = hashing.finish().hex_encode()}
		result.model.identity.input_sha256 = result.input_identity.sha256
	return result


static func prepare(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not _exact_keys(raw, ROOT_KEYS):
		return _fail("Glow profile root must contain exactly the declared fields")
	if raw.format != FORMAT or raw.status != "candidate" or raw.feed != "naturally_aspirated" or raw.oil_model != "inert":
		return _fail("Unsupported glow format/status/feed/oil model")
	for name: String in ["id", "manufacturer", "model", "family"]:
		if not raw[name] is String or raw[name].strip_edges().is_empty():
			return _fail(name + " must be a nonempty string")
	var spec: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	if not spec is Dictionary or spec.get("format") != "openrc-glow-profile-contract v1" or not spec.families.has(raw.family):
		return _fail("Unknown family or unavailable glow profile contract")
	var rules: Dictionary = spec.common.duplicate(true)
	rules.merge(spec.families[raw.family])
	var params: Dictionary = _group(raw.parameters, rules)
	var fuel: Dictionary = _group(raw.fuel, spec.fuel)
	var operation: Dictionary = _group(raw.operation, spec.operation)
	for group: Dictionary in [params, fuel, operation]:
		if not group.ok:
			return group
	var f: Dictionary = fuel.values
	var methanol_volume: float = 1.0 - f.nitromethane_volume_fraction - f.lubricant_volume_fraction
	if methanol_volume <= 0.0:
		return _fail("Fuel requires positive methanol and fractions summing below one")
	var methanol_mass: float = methanol_volume * f.methanol_density_kg_m3
	var nitro_mass: float = f.nitromethane_volume_fraction * f.nitromethane_density_kg_m3
	var oil_mass: float = f.lubricant_volume_fraction * f.lubricant_density_kg_m3
	var combustible_mass: float = methanol_mass + nitro_mass
	var density: float = combustible_mass + oil_mass
	if not is_finite(density) or density <= 0.0 or not is_finite(combustible_mass) or combustible_mass <= 0.0:
		return _fail("Fuel blend derivation is nonfinite")
	var p: Dictionary = params.values
	p.oil_fraction = oil_mass / density
	p.stoich_air_fuel_ratio = (methanol_mass * f.methanol_stoich_air_fuel_ratio + nitro_mass * f.nitromethane_stoich_air_fuel_ratio) / combustible_mass
	p.fuel_lhv_j_kg = (methanol_mass * f.methanol_lhv_j_kg + nitro_mass * f.nitromethane_lhv_j_kg) / combustible_mass
	for key: String in ["oil_fraction", "stoich_air_fuel_ratio", "fuel_lhv_j_kg"]:
		if not is_finite(float(p[key])):
			return _fail("Derived fuel quantity is nonfinite: " + key)
	if p.oil_fraction >= 1.0 or p.stoich_air_fuel_ratio <= 0.0 or p.fuel_lhv_j_kg <= 0.0:
		return _fail("Derived fuel blend is not representable inside the kernel domain")
	f.density_kg_m3 = density
	f.methanol_volume_fraction = methanol_volume
	var op: Dictionary = operation.values
	if op.rated_rpm > op.max_rpm:
		return _fail("Rated RPM exceeds the supported maximum")
	for key: String in rules:
		if rules[key].shape == "curve":
			var table: PackedFloat64Array = p[key]
			var last: int = table.size() - 2
			if table[0] != 0.0 or (rules[key].axis == "rpm" and table[last] < op.max_rpm) or (rules[key].axis == "mixture" and table[last] < op.nominal_mixture):
				return _fail("Curve must start at zero and cover the declared operating range: " + key)
	var provenance: Dictionary = raw.duplicate(true)
	return {ok = true, errors = PackedStringArray(), model = {family = raw.family, parameters = p,
		fuel = f, operation = op, identity = {id = raw.id, manufacturer = raw.manufacturer, model = raw.model,
		status = raw.status, cycle_revolutions = 1 if raw.family == "glow_2t" else 2}, provenance = provenance}}


static func _group(raw: Variant, rules: Dictionary) -> Dictionary:
	if not raw is Dictionary or not _exact_keys(raw, rules.keys()):
		return _fail("Glow quantity group has missing or unknown fields")
	var out: Dictionary = {}
	for key: String in rules:
		var q: Variant = raw[key]
		var rule: Dictionary = rules[key]
		if not q is Dictionary or not _exact_keys(q, ["value", "unit", "kind", "source"]):
			return _fail(key + " must be an exact provenance quantity")
		if q.unit != rule.unit or q.kind not in KINDS or not q.source is String or q.source.strip_edges().is_empty():
			return _fail(key + " has invalid unit, evidence kind or source")
		if rule.shape == "scalar":
			if not _number(q.value, rule):
				return _fail(key + " has an invalid finite scalar")
			out[key] = float(q.value)
		else:
			if not q.value is Array or q.value.size() < 2:
				return _fail(key + " needs at least two curve rows")
			var curve: PackedFloat64Array = PackedFloat64Array()
			var previous: float = -1.0
			for row: Variant in q.value:
				if not row is Array or row.size() != 2 or typeof(row[0]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(row[0])) or float(row[0]) < 0.0 or float(row[0]) <= previous or not _number(row[1], rule):
					return _fail(key + " has malformed, nonfinite or unordered curve rows")
				previous = float(row[0])
				curve.append(previous)
				curve.append(float(row[1]))
			out[key] = curve
	return {ok = true, values = out}


static func _number(value: Variant, rule: Dictionary) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric: float = float(value)
	return is_finite(numeric) and numeric >= rule.minimum and numeric <= rule.maximum and (not rule.positive or numeric > rule.minimum)


static func _exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key: Variant in keys:
		if not value.has(key):
			return false
	return true


static func _fail(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message]), model = {}}
