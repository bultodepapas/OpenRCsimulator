extends RefCounted
## CR-31c: explicit inspection decisions, never a physical damage predictor.
const Calculator = preload("res://economy/calculator.gd")
const FORMAT := "openrc-accident-inspection v1"
const MAX_BYTES := 65536
const KEYS := ["format", "inspection_id", "incident_id", "aircraft_id", "source_sha256", "catalog_hash", "expected_revision", "full_inspection", "total_loss", "basis", "evidence", "components"]
const ROW_KEYS := ["disposition", "quantity", "repair_minor", "inspection_minor", "salvage_eligible", "damage_flags", "evidence"]
const FLAGS := ["structural_damage", "thermal_damage", "electrical_damage", "lipo_damage", "unretrieved"]
const RESOLVABLE := ["Impact or surface contact requires structural inspection.", "Water exposure requires inspection of electronics and powertrain.", "Crash inspection pending; component survival is not yet established.", "Propeller strike: inspect the powertrain, shaft and mount before return to service."]


static func validate(receipt: Dictionary, dossier: Dictionary, current: Dictionary,
		identity: Dictionary, catalog_hash: String, revision: int, blocked: Dictionary) -> Dictionary:
	var errors: Array = []
	if receipt.size() != KEYS.size() or JSON.stringify(receipt).to_utf8_buffer().size() > MAX_BYTES:
		return _failure("inspection has missing/extra fields or exceeds its size limit")
	for key: Variant in receipt:
		if key not in KEYS:
			return _failure("unknown inspection field")
	if receipt.get("format") != FORMAT:
		return _failure("unknown inspection format")
	for key: String in ["inspection_id", "evidence"]:
		if not _text(receipt.get(key)):
			return _failure(key + " must be nonempty bounded text")
	for key: String in ["incident_id", "aircraft_id", "source_sha256"]:
		if receipt.get(key) != identity.get(key) or not _text(receipt.get(key)):
			return _failure("inspection identity mismatch: " + key)
	if receipt.get("catalog_hash") != catalog_hash or catalog_hash.is_empty():
		return _failure("inspection catalog identity mismatch")
	if typeof(receipt.get("expected_revision")) != TYPE_INT or receipt.expected_revision != revision:
		return _failure("stale inspection revision")
	if typeof(receipt.get("full_inspection")) != TYPE_BOOL or typeof(receipt.get("total_loss")) != TYPE_BOOL:
		return _failure("inspection completeness and total loss must be explicit booleans")
	if receipt.get("basis") not in ["inspection", "scenario_assumption"]:
		return _failure("inspection basis must distinguish evidence from a scenario assumption")
	if not receipt.full_inspection and receipt.total_loss != current.get("total_loss", false):
		return _failure("changing whole-aircraft disposition requires a full inspection")
	if typeof(receipt.get("components")) != TYPE_DICTIONARY or receipt.components.is_empty():
		return _failure("inspection requires component decisions")
	var parts: Dictionary = {}
	for part: Dictionary in dossier.get("components", []):
		parts[part.id] = part
	if receipt.components.size() > parts.size():
		return _failure("inspection has unknown components")
	if receipt.full_inspection and receipt.components.size() != parts.size():
		return _failure("full inspection must account for every economic component including labor")
	var assessment := current.duplicate(true)
	var next_blocked := blocked.duplicate(true)
	for id: Variant in receipt.components:
		if not parts.has(id) or typeof(receipt.components[id]) != TYPE_DICTIONARY:
			return _failure("unknown component or malformed inspection decision")
		var decision: Dictionary = receipt.components[id].duplicate(true)
		for key: Variant in decision:
			if key not in ROW_KEYS:
				return _failure("unknown component decision field")
		if not _text(decision.get("evidence")) or typeof(decision.get("damage_flags")) != TYPE_ARRAY:
			return _failure("each component needs evidence and explicit damage flags")
		if decision.damage_flags.size() > FLAGS.size():
			return _failure("too many damage flags")
		var seen: Dictionary = {}
		for flag: Variant in decision.damage_flags:
			if flag not in FLAGS or seen.has(flag):
				return _failure("unknown or duplicate damage flag")
			seen[flag] = true
			if flag == "structural_damage" and not next_blocked.has(id):
				next_blocked[id] = "repair_required"
			if flag in ["thermal_damage", "electrical_damage", "lipo_damage", "unretrieved"]:
				next_blocked[id] = "replace_only"
		if next_blocked.has(id) and (decision.get("disposition") == "reuse" \
			or (decision.get("disposition") == "repair" and next_blocked[id] == "replace_only")):
			return _failure("damaged or unretrieved component is not eligible for reuse/repair in this version")
		var count: Variant = decision.get("quantity", parts[id].quantity)
		if typeof(count) != TYPE_INT or count <= 0:
			return _failure("inspection quantity must be a positive integer")
		if receipt.full_inspection and not receipt.total_loss and count != parts[id].quantity:
			return _failure("full repair inspection must account for every installed unit")
		decision.erase("evidence")
		decision.erase("damage_flags")
		assessment.components[id] = decision
	if receipt.full_inspection:
		assessment.total_loss = receipt.total_loss
		var remaining: Array = []
		for reason: String in assessment.get("unresolved", []):
			if reason not in RESOLVABLE:
				remaining.append(reason)
		assessment.unresolved = remaining
	var calculated := Calculator.calculate(dossier, assessment)
	if not calculated.get("ok", false):
		errors.assign(calculated.get("errors", []))
	return {ok = errors.is_empty(), errors = errors, assessment = assessment, blocked = next_blocked}


static func _text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.strip_edges().is_empty() and value.length() <= 2048


static func _failure(message: String) -> Dictionary:
	return {ok = false, errors = [message]}
