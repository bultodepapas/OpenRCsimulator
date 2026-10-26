# BAT-04: strict loader for generated battery data (openrc-battery v1 packs and openrc-cell-template v1 cells).
# Format: docs/research/battery/BAT-04/specification.md §1–§2. Generator: research/battery/bat-05/build_batteries.py.
# Invalid data cannot fly: every error is collected and the caller refuses the aircraft.
extends RefCounted
const Timing:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/metrics.gd")

const PACK_DIR: String = "res://data/batteries/packs/"
const CELL_DIR: String = "res://data/batteries/cells/"
const PACK_FORMAT: String = "openrc-battery v1"
const CELL_FORMAT: String = "openrc-cell-template v1"
const CHEMISTRIES: Array[String] = ["lipo", "lihv", "liion", "lifepo4", "nimh"]
const TIERS: Array[String] = ["A", "B", "C"]
const EVIDENCE_KINDS: Array[String] = ["manual", "measured", "borrowed", "estimated", "derived"]
const MAX_SERIES: int = 24
const MAX_PARALLEL: int = 8
const MAX_BRANCHES: int = 2
const PACK_KEYS: Array[String] = ["format", "id", "display_name", "class_note", "chemistry", "cell_template", "series",
	"parallel", "rated_capacity_ah", "resistance_scale", "interconnect_resistance_ohm", "mass_kg", "dimensions_m",
	"heat_transfer", "label"]
const CELL_KEYS: Array[String] = ["format", "id", "display_name", "chemistry", "tier", "generator", "provenance",
	"reference_capacity_ah", "soc_knots", "temperature_knots_k", "ocv_v", "r0_ohm", "rc_branches",
	"specific_heat_j_per_kg_k", "limits"]


## Load, hash-check and normalize one pack and its cell template. Returns {} and appends errors on failure.
static func load_pack(errors: PackedStringArray, path: String, pack_id: Variant, expected_sha256: Variant) -> Dictionary:
	if typeof(pack_id) != TYPE_STRING or not _is_identifier(pack_id):
		errors.append(path + ".id: must be a lowercase identifier [a-z0-9-]")
		return {}
	if typeof(expected_sha256) != TYPE_STRING or not _is_sha256(expected_sha256):
		errors.append(path + ".sha256: must be a lowercase 64-hex SHA-256")
		return {}
	var pack_file: Dictionary = _read_json(PACK_DIR + pack_id + ".json")
	if not pack_file.ok:
		errors.append("%s: %s" % [path, pack_file.message])
		return {}
	if pack_file.sha256 != expected_sha256:
		errors.append("%s.sha256: pack file bytes changed (expected %s, found %s); regenerate the aircraft" % [path, expected_sha256, pack_file.sha256])
		return {}
	var pack: Variant = pack_file.data
	if not pack is Dictionary or pack.get("id") != pack_id:
		errors.append(path + ": pack file id does not match its file name")
		return {}
	var template_ref: Variant = pack.get("cell_template")
	if not template_ref is Dictionary or typeof(template_ref.get("id")) != TYPE_STRING \
			or not _is_identifier(template_ref.id) or typeof(template_ref.get("sha256")) != TYPE_STRING:
		errors.append(path + ".cell_template: needs {id, sha256}")
		return {}
	var cell_file: Dictionary = _read_json(CELL_DIR + str(template_ref.id) + ".json")
	if not cell_file.ok:
		errors.append("%s.cell_template: %s" % [path, cell_file.message])
		return {}
	if cell_file.sha256 != template_ref.sha256:
		errors.append(path + ".cell_template.sha256: template bytes do not match the pack pin")
		return {}
	var normalized: Dictionary = normalize(errors, path, pack, cell_file.data)
	if normalized.is_empty():
		return {}
	normalized.pack_sha256 = pack_file.sha256
	normalized.template_sha256 = cell_file.sha256
	return normalized


## Validate and normalize already-parsed pack and template dictionaries (no file access; used by tests).
static func normalize(errors: PackedStringArray, path: String, pack: Variant, template: Variant) -> Dictionary:
	var start_errors: int = errors.size()
	if not pack is Dictionary or not template is Dictionary:
		errors.append(path + ": pack and cell template must be dictionaries")
		return {}
	_closed(errors, path, pack, PACK_KEYS)
	_closed(errors, path + ".cell_template", template, CELL_KEYS)
	if pack.get("format") != PACK_FORMAT:
		errors.append("%s.format: must be '%s'" % [path, PACK_FORMAT])
	if template.get("format") != CELL_FORMAT:
		errors.append("%s.cell_template.format: must be '%s'" % [path, CELL_FORMAT])
	for key: String in ["display_name", "class_note"]:
		if typeof(pack.get(key)) != TYPE_STRING or str(pack.get(key)).strip_edges().is_empty():
			errors.append("%s.%s: must be a nonblank string" % [path, key])
	if pack.get("chemistry") not in CHEMISTRIES or template.get("chemistry") != pack.get("chemistry"):
		errors.append(path + ".chemistry: must be a supported chemistry equal to the cell template's")
	if template.get("tier") not in TIERS:
		errors.append(path + ".cell_template.tier: must be A, B or C")
	var series: int = _count(errors, path + ".series", pack.get("series"), MAX_SERIES)
	var parallel: int = _count(errors, path + ".parallel", pack.get("parallel"), MAX_PARALLEL)
	var rated = _q(errors, path + ".rated_capacity_ah", pack.get("rated_capacity_ah"), "Ah", 0.01, 1000.0)
	var scale = _q(errors, path + ".resistance_scale", pack.get("resistance_scale"), "1", 1e-4, 100.0)
	var wiring = _q(errors, path + ".interconnect_resistance_ohm", pack.get("interconnect_resistance_ohm"), "ohm", 0.0, 1.0)
	var mass = _q(errors, path + ".mass_kg", pack.get("mass_kg"), "kg", 0.001, 100.0)
	var dims = _qv(errors, path + ".dimensions_m", pack.get("dimensions_m"), "m", 1e-4, 2.0, 3)
	var heat: Dictionary = pack.get("heat_transfer") if pack.get("heat_transfer") is Dictionary else {}
	_closed(errors, path + ".heat_transfer", heat, ["still_air_w_per_k", "forced_w_per_k_per_sqrt_mps"])
	var h_still = _q(errors, path + ".heat_transfer.still_air_w_per_k", heat.get("still_air_w_per_k"), "W/K", 0.0, 1000.0)
	var h_forced = _q(errors, path + ".heat_transfer.forced_w_per_k_per_sqrt_mps", heat.get("forced_w_per_k_per_sqrt_mps"), "W/(K·(m/s)^0.5)", 0.0, 1000.0)
	if not pack.get("label") is Dictionary:
		errors.append(path + ".label: must be an informative dictionary")

	var cell_path: String = path + ".cell_template"
	var reference = _q(errors, cell_path + ".reference_capacity_ah", template.get("reference_capacity_ah"), "Ah", 0.01, 1000.0)
	var soc_knots = _qv(errors, cell_path + ".soc_knots", template.get("soc_knots"), "1", 0.0, 1.0, -2)
	var t_knots = _qv(errors, cell_path + ".temperature_knots_k", template.get("temperature_knots_k"), "K", 150.0, 400.0, -1)
	var cp = _q(errors, cell_path + ".specific_heat_j_per_kg_k", template.get("specific_heat_j_per_kg_k"), "J/(kg·K)", 100.0, 5000.0)
	var limits_raw: Dictionary = template.get("limits") if template.get("limits") is Dictionary else {}
	_closed(errors, cell_path + ".limits", limits_raw, ["v_max", "v_cutoff", "v_damage_floor", "t_min_k", "t_max_k"])
	var v_max = _q(errors, cell_path + ".limits.v_max", limits_raw.get("v_max"), "V", 0.5, 5.0)
	var v_cutoff = _q(errors, cell_path + ".limits.v_cutoff", limits_raw.get("v_cutoff"), "V", 0.5, 5.0)
	var v_floor = _q(errors, cell_path + ".limits.v_damage_floor", limits_raw.get("v_damage_floor"), "V", 0.0, 5.0)
	var t_min = _q(errors, cell_path + ".limits.t_min_k", limits_raw.get("t_min_k"), "K", 150.0, 400.0)
	var t_max = _q(errors, cell_path + ".limits.t_max_k", limits_raw.get("t_max_k"), "K", 150.0, 450.0)
	if errors.size() > start_errors:
		return {}
	_strictly_increasing(errors, cell_path + ".soc_knots", soc_knots)
	_strictly_increasing(errors, cell_path + ".temperature_knots_k", t_knots)
	if soc_knots[0] != 0.0 or soc_knots[soc_knots.size() - 1] != 1.0:
		errors.append(cell_path + ".soc_knots: must start at 0 and end at 1")
	if not (float(v_floor) < float(v_cutoff) and float(v_cutoff) < float(v_max)) or float(t_min) >= float(t_max):
		errors.append(cell_path + ".limits: need v_damage_floor < v_cutoff < v_max and t_min_k < t_max_k")
	var nz: int = soc_knots.size()
	var nt: int = t_knots.size()
	var ocv: PackedFloat64Array = _matrix(errors, cell_path + ".ocv_v", template.get("ocv_v"), "V", nt, nz, 0.1, 6.0)
	var r0: PackedFloat64Array = _matrix(errors, cell_path + ".r0_ohm", template.get("r0_ohm"), "ohm", nt, nz, 1e-6, 10.0)
	var branches_raw: Variant = template.get("rc_branches")
	var rc_r: Array = []
	var rc_tau: Array = []
	if not branches_raw is Array or branches_raw.size() > MAX_BRANCHES:
		errors.append(cell_path + ".rc_branches: must be an array of 0..%d branches" % MAX_BRANCHES)
	else:
		for k: int in branches_raw.size():
			var branch_path: String = "%s.rc_branches[%d]" % [cell_path, k]
			var branch: Dictionary = branches_raw[k] if branches_raw[k] is Dictionary else {}
			_closed(errors, branch_path, branch, ["r_ohm", "tau_s"])
			rc_r.append(_matrix(errors, branch_path + ".r_ohm", branch.get("r_ohm"), "ohm", nt, nz, 1e-7, 10.0))
			rc_tau.append(_matrix(errors, branch_path + ".tau_s", branch.get("tau_s"), "s", nt, nz, 1e-3, 1e5))
	if errors.size() > start_errors:
		return {}
	for row: int in nt:
		for i: int in range(1, nz):
			if ocv[row * nz + i] < ocv[row * nz + i - 1]:
				errors.append(cell_path + ".ocv_v: OCV must be nondecreasing in SOC on every temperature row")
				return {}
	# Capacity normalization: resistances scale with the reference/pack capacity ratio and the class scale.
	var resistance_factor: float = float(reference) / float(rated) * float(scale)
	var scaled_r0: PackedFloat64Array = _scaled(r0, resistance_factor)
	var scaled_rc: Array = []
	for table: PackedFloat64Array in rc_r:
		scaled_rc.append(_scaled(table, resistance_factor))
	return {
		"pack_id": str(pack.id),
		"display_name": str(pack.display_name),
		"class_note": str(pack.class_note),
		"chemistry": str(pack.chemistry),
		"template_id": str(template.get("id", "")),
		"tier": str(template.tier),
		"series": series,
		"parallel": parallel,
		"rated_capacity_ah": float(rated),
		"group_capacity_c": 3600.0 * float(rated),
		"soc_knots": soc_knots,
		"temperature_knots_k": t_knots,
		"ocv": ocv,
		"r0": scaled_r0,
		"rc_r": scaled_rc,
		"rc_tau": rc_tau,
		"branches": rc_r.size(),
		"interconnect_ohm": float(wiring),
		"mass_kg": float(mass),
		"dimensions_m": dims,
		"thermal_capacity_j_per_k": float(mass) * float(cp),
		"h_still_w_per_k": float(h_still),
		"h_forced_w_per_k_sqrt_mps": float(h_forced),
		"cell_v_max": float(v_max),
		"cell_v_cutoff": float(v_cutoff),
		"cell_v_damage_floor": float(v_floor),
		"cell_t_min_k": float(t_min),
		"cell_t_max_k": float(t_max),
	}


## SHA-256 of exact file bytes, or "" when unreadable.
static func file_sha256(file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return ""
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(file_path)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _read_json(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {ok = false, message = "missing battery data file " + file_path}
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(file_path)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		return {ok = false, message = "invalid JSON in " + file_path}
	return {ok = true, data = json.data, sha256 = context.finish().hex_encode()}


static func _closed(errors: PackedStringArray, path: String, node: Variant, keys: Array[String]) -> void:
	if not node is Dictionary:
		errors.append(path + ": expected a dictionary")
		return
	for key: Variant in node:
		if str(key) not in keys:
			errors.append("%s: unknown field '%s'" % [path, key])
	for key: String in keys:
		if not node.has(key):
			errors.append("%s: missing field '%s'" % [path, key])


static func _evidence(errors: PackedStringArray, path: String, node: Variant, unit: String) -> bool:
	if not node is Dictionary:
		errors.append(path + ": expected {value, unit, kind, source}")
		return false
	for key: Variant in node:
		if str(key) not in ["value", "unit", "kind", "source"]:
			errors.append("%s: unknown field '%s'" % [path, key])
	if node.get("unit") != unit:
		errors.append("%s.unit: must be '%s'" % [path, unit])
	if node.get("kind") not in EVIDENCE_KINDS:
		errors.append(path + ".kind: must be a supported evidence kind")
	if typeof(node.get("source")) != TYPE_STRING or str(node.get("source")).strip_edges().is_empty():
		errors.append(path + ".source: must be a nonblank string")
	return node.get("unit") == unit and node.get("kind") in EVIDENCE_KINDS and typeof(node.get("source")) == TYPE_STRING


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _q(errors: PackedStringArray, path: String, node: Variant, unit: String, lo: float, hi: float) -> Variant:
	if not _evidence(errors, path, node, unit):
		return null
	var value: Variant = node.get("value")
	if not _number(value) or float(value) < lo or float(value) > hi:
		errors.append("%s.value: must be a finite number in [%s, %s]" % [path, lo, hi])
		return null
	return float(value)


## Vector quantity; size > 0 is exact, size < 0 means "at least -size".
static func _qv(errors: PackedStringArray, path: String, node: Variant, unit: String, lo: float, hi: float, size: int) -> Variant:
	if not _evidence(errors, path, node, unit):
		return null
	var raw: Variant = node.get("value")
	if not raw is Array or (size > 0 and raw.size() != size) or (size < 0 and raw.size() < -size):
		errors.append("%s.value: expected %s numbers" % [path, str(size) if size > 0 else "at least %d" % -size])
		return null
	var out := PackedFloat64Array()
	for value: Variant in raw:
		if not _number(value) or float(value) < lo or float(value) > hi:
			errors.append("%s.value: every entry must be finite in [%s, %s]" % [path, lo, hi])
			return null
		out.append(float(value))
	return out


static func _matrix(errors: PackedStringArray, path: String, node: Variant, unit: String, rows: int, columns: int,
		lo: float, hi: float) -> PackedFloat64Array:
	if not _evidence(errors, path, node, unit):
		return PackedFloat64Array()
	var raw: Variant = node.get("value")
	if not raw is Array or raw.size() != rows:
		errors.append("%s.value: expected %d temperature rows" % [path, rows])
		return PackedFloat64Array()
	var out := PackedFloat64Array()
	for row: Variant in raw:
		if not row is Array or row.size() != columns:
			errors.append("%s.value: every row needs %d SOC values" % [path, columns])
			return PackedFloat64Array()
		for value: Variant in row:
			if not _number(value) or float(value) < lo or float(value) > hi:
				errors.append("%s.value: entries must be finite in [%s, %s]" % [path, lo, hi])
				return PackedFloat64Array()
			out.append(float(value))
	return out


static func _scaled(values: PackedFloat64Array, factor: float) -> PackedFloat64Array:
	var out: PackedFloat64Array = values.duplicate()
	for i: int in out.size():
		out[i] *= factor
	return out


static func _count(errors: PackedStringArray, path: String, value: Variant, maximum: int) -> int:
	if not _number(value) or float(value) != floorf(float(value)) or float(value) < 1.0 or float(value) > float(maximum):
		errors.append("%s: must be an integer in [1, %d]" % [path, maximum])
		return 0
	return int(value)


static func _strictly_increasing(errors: PackedStringArray, path: String, values: PackedFloat64Array) -> void:
	for i: int in range(1, values.size()):
		if values[i] <= values[i - 1]:
			errors.append(path + ": must be strictly increasing")
			return


static func _is_identifier(text: String) -> bool:
	if text.is_empty() or text.length() > 96:
		return false
	for i: int in text.length():
		var c: String = text[i]
		if not (c >= "a" and c <= "z") and not (c >= "0" and c <= "9") and c != "-":
			return false
	return text[0] != "-"


static func _is_sha256(text: String) -> bool:
	if text.length() != 64:
		return false
	for i: int in text.length():
		var c: String = text[i]
		if not (c >= "0" and c <= "9") and not (c >= "a" and c <= "f"):
			return false
	return true
