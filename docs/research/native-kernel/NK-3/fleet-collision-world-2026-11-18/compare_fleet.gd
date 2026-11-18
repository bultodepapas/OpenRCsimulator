extends SceneTree
## DR-19e fleet renewal: the A35 recipe (../../../project-audit-2026-11-09/remediation/compare_fleet.gd) with one
## change. A collision-world edit changes live-configuration index 7 (the detached world's typed digest) as well as
## index 2 (the checkpoint configuration, which embeds the world identity). Every other field stays exact.

const ALLOWED_CHANGED_INDICES: Array[int] = [2, 7]
const CAPTURE_FORMAT := "ci-audit-fleet-reset-v1"
const EXPECTED_CASES := 8
const MAX_CAPTURE_BYTES := 32 * 1024 * 1024
const LIVE_FIELDS := ["before_live_config_bytes_hex", "live_config_bytes_hex", "live_config_sha256"]

var _checks := 0
var _failures := 0
var _errors: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(passed: bool, label: String) -> bool:
	_checks += 1
	if not passed:
		_failures += 1
		if _errors.size() < 20:
			_errors.append(label)
		printerr("FAIL ", label)
	return passed


func _sha256(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()


func _valid_hash(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and value.length() == 64 \
		and value.is_valid_hex_number() and value == value.to_lower()


func _capture(path: String, label: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not _check(file != null, label + " capture opens"):
		return {}
	var length: int = file.get_length()
	if not _check(length > 0 and length <= MAX_CAPTURE_BYTES, label + " capture length is bounded"):
		file.close()
		return {}
	var bytes: PackedByteArray = file.get_buffer(length)
	var complete: bool = bytes.size() == length and file.get_error() == OK
	file.close()
	if not _check(complete, label + " capture read completes"):
		return {}
	var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not _check(value is Dictionary, label + " capture is a dictionary"):
		return {}
	return value


func _payload(proof: Dictionary, field: String, label: String) -> PackedByteArray:
	var hex: Variant = proof.get(field + "_bytes_hex")
	if not _check(typeof(hex) == TYPE_STRING and not hex.is_empty() and hex.length() <= 1048576 \
		and hex.length() % 2 == 0 and hex.is_valid_hex_number(), label + " " + field + " payload is bounded hex"):
		return PackedByteArray()
	var bytes: PackedByteArray = hex.hex_decode()
	_check(hex == bytes.hex_encode() and _valid_hash(proof.get(field + "_sha256")) \
		and _sha256(bytes) == proof.get(field + "_sha256"), label + " " + field + " payload hash matches")
	return bytes


func _compare_case(left: Variant, right: Variant, index: int) -> Dictionary:
	var label := "case %d" % index
	if not _check(left is Dictionary and right is Dictionary, label + " records are dictionaries"):
		return {}
	if not _check(left.get("row") is Dictionary and right.get("row") is Dictionary \
		and left.get("proof") is Dictionary and right.get("proof") is Dictionary, label + " row and proof exist"):
		return {}
	_check(var_to_bytes(left.row) == var_to_bytes(right.row), label + " row is exact")
	_check(var_to_bytes(left.get("reason")) == var_to_bytes(right.get("reason")), label + " refusal reason is exact")
	_check(typeof(left.get("original_pin_matches")) == TYPE_BOOL and left.original_pin_matches, label + " baseline matches original pins")
	var a: Dictionary = left.proof
	var b: Dictionary = right.proof
	_check(var_to_bytes(a.keys()) == var_to_bytes(b.keys()), label + " proof field set and order are exact")
	for key: String in a:
		if key not in LIVE_FIELDS:
			_check(b.has(key) and var_to_bytes(a[key]) == var_to_bytes(b.get(key)), label + " proof field is exact " + key)
	for field: String in ["frame", "config", "outcome"]:
		_payload(a, field, label + " baseline")
		_payload(b, field, label + " candidate")
	var left_bytes: PackedByteArray = _payload(a, "live_config", label + " baseline")
	var right_bytes: PackedByteArray = _payload(b, "live_config", label + " candidate")
	_check(a.get("before_live_config_bytes_hex") == a.get("live_config_bytes_hex") \
		and b.get("before_live_config_bytes_hex") == b.get("live_config_bytes_hex"), label + " both live configurations are retained")
	if left_bytes.is_empty() or right_bytes.is_empty():
		return {}
	var old_live: Variant = bytes_to_var(left_bytes)
	var new_live: Variant = bytes_to_var(right_bytes)
	if not _check(old_live is Array and new_live is Array and old_live.size() > 2 \
		and new_live.size() == old_live.size(), label + " decoded live arrays have equal sizes"):
		return {}
	var old_checkpoint: Variant = old_live[2]
	var new_checkpoint: Variant = new_live[2]
	_check(_valid_hash(old_checkpoint) and _valid_hash(new_checkpoint) and old_checkpoint != new_checkpoint,
		label + " checkpoint hashes are valid and changed")
	var changed_indices: Array[int] = []
	for at: int in old_live.size():
		if var_to_bytes(old_live[at]) != var_to_bytes(new_live[at]):
			changed_indices.append(at)
	var normalized: Array = new_live.duplicate(true)
	for at: int in ALLOWED_CHANGED_INDICES:
		normalized[at] = old_live[at]
	_check(_valid_hash(old_live[7]) and _valid_hash(new_live[7]) and old_live[7] != new_live[7],
		label + " collision world digests are valid and changed")
	_check(var_to_bytes(normalized) == var_to_bytes(old_live) and changed_indices == ALLOWED_CHANGED_INDICES,
		label + " only live array indices 2 and 7 change")
	return {row = left.row, baseline_live_config_sha256 = a.get("live_config_sha256"),
		candidate_live_config_sha256 = b.get("live_config_sha256"), baseline_checkpoint_configuration = old_checkpoint,
		candidate_checkpoint_configuration = new_checkpoint, changed_live_configuration_indices = changed_indices}


func _run() -> void:
	var left_path := OS.get_environment("OPENRC_AUDIT_LEFT")
	var right_path := OS.get_environment("OPENRC_AUDIT_RIGHT")
	var output_path := OS.get_environment("OPENRC_AUDIT_COMPARISON")
	if output_path.is_empty() or FileAccess.file_exists(output_path) or DirAccess.dir_exists_absolute(output_path):
		printerr("FAIL comparison output must be a fresh file path")
		quit(1)
		return
	var left: Dictionary = _capture(left_path, "baseline")
	var right: Dictionary = _capture(right_path, "candidate")
	var rows: Array[Dictionary] = []
	var identity_ok: bool = _check(left.get("format") == CAPTURE_FORMAT and right.get("format") == CAPTURE_FORMAT \
		and left.get("engine") is Dictionary and right.get("engine") is Dictionary \
		and var_to_bytes(left.get("engine")) == var_to_bytes(right.get("engine")) \
		and typeof(left.get("os")) == TYPE_STRING and left.get("os") == right.get("os"), "capture format, engine and OS match")
	var cases_ok: bool = _check(left.get("cases") is Array and right.get("cases") is Array \
		and left.get("cases", []).size() == EXPECTED_CASES and right.get("cases", []).size() == EXPECTED_CASES,
		"both captures contain exactly eight cases")
	if identity_ok and cases_ok:
		var seen: Dictionary = {}
		for index: int in EXPECTED_CASES:
			var row: Dictionary = _compare_case(left.cases[index], right.cases[index], index)
			rows.append(row)
			var key: String = var_to_bytes(row.get("row")).hex_encode()
			_check(not seen.has(key), "capture row is unique %d" % index)
			seen[key] = true
	var report := {format = "openrc-dr19e-fleet-live-configuration-comparison-v1", engine = left.get("engine"),
		os = left.get("os"), baseline_capture_sha256 = FileAccess.get_sha256(left_path),
		candidate_capture_sha256 = FileAccess.get_sha256(right_path), cases = rows,
		checks = _checks, failures = _failures, errors = _errors, ok = _failures == 0 and rows.size() == EXPECTED_CASES}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if not _check(file != null, "comparison receipt opens"):
		quit(1)
		return
	report.checks = _checks + 1 # Include the write-completion check reported below.
	file.store_string(JSON.stringify(report, "  "))
	file.flush()
	var write_ok: bool = file.get_error() == OK
	file.close()
	_check(write_ok, "comparison receipt write completes")
	print("DR19E_FLEET_COMPARISON checks=%d failures=%d cases=%d" % [_checks, _failures, rows.size()])
	quit(0 if _failures == 0 else 1)
