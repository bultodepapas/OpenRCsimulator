extends RefCounted
## CR-30c: native, integrity-checked economics state for an active-flight checkpoint.
## Digests detect changed data; they are not authentication of inspection evidence.
const Events = preload("res://sim/aircraft_contact_events.gd")
const Inspection = preload("res://economy/inspection.gd")
const Calculator = preload("res://economy/calculator.gd")
const RepairPlanner = preload("res://economy/repair_planner.gd")
const FORMAT := "openrc-economics-checkpoint v1"
const ENVELOPE := "openrc-flight-economics-checkpoint v1"
const MAX_BYTES := 262144
const FIELDS := ["format", "tick", "catalog_hash", "recipe_hash", "bindings_hash", "identity", "assessment", "last_tick", "assessment_tick", "revision", "journal", "facts", "inspections", "blocked", "repair_choices", "payload_sha256"]


static func digest(value: Variant) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(value))
	return hashing.finish().hex_encode()


static func seal(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	result.erase("payload_sha256")
	result.payload_sha256 = digest(result)
	return result


static func capture(incident: RefCounted, tick: int, bindings: Dictionary) -> Dictionary:
	var value := {
		format = FORMAT, tick = tick, catalog_hash = incident.get("_catalog_hash"),
		recipe_hash = incident.get("_recipe_hash"), bindings_hash = digest(bindings),
		identity = incident.get("_identity"), assessment = incident.get("_assessment"),
		last_tick = incident.get("_last_tick"), assessment_tick = incident.get("_assessment_tick"),
		revision = incident.get("_revision"), journal = incident.get("journal"),
		facts = incident.get("_confirmed_facts"), inspections = incident.get("_inspections"),
		blocked = incident.get("_reuse_blocked"), repair_choices = incident.get("_repair_choices")}
	if not native_data(value):
		return {}
	value = seal(value)
	return value if prepare(value, incident, tick, bindings).ok else {}


## Complete validation precedes any live mutation. Only the same frozen prices/recipes can resume.
static func prepare(value: Variant, incident: RefCounted, tick: int, bindings: Dictionary) -> Dictionary:
	if not native_data(value) or not value is Dictionary or not keys(value, FIELDS):
		return fail("Invalid economics checkpoint schema.")
	if var_to_bytes(value).size() > MAX_BYTES or value.format != FORMAT:
		return fail("Unsupported or oversized economics checkpoint.")
	var copy: Dictionary = value.duplicate(true)
	copy.erase("payload_sha256")
	if value.payload_sha256 != digest(copy):
		return fail("Economics checkpoint integrity mismatch.")
	if not value.tick is int or value.tick != tick or tick < 0:
		return fail("Economics and physics checkpoint ticks disagree.")
	if value.catalog_hash != incident.get("_catalog_hash") or value.recipe_hash != incident.get("_recipe_hash") \
		or value.bindings_hash != digest(bindings):
		return fail("Economics catalog, recipe or contact bindings changed.")
	var identity: Dictionary = incident.get("_identity")
	if not value.identity is Dictionary or not keys(value.identity, ["aircraft_id", "source_sha256", "incident_id"]):
		return fail("Invalid incident identity.")
	for field: String in ["aircraft_id", "source_sha256"]:
		if value.identity[field] != identity.get(field):
			return fail("Economics aircraft identity mismatch.")
	if not Inspection._text(value.identity.incident_id):
		return fail("Invalid incident ID.")
	for field: String in ["last_tick", "assessment_tick", "revision"]:
		if not value[field] is int or value[field] < (-1 if field != "revision" else 0) or value[field] > 9007199254740991:
			return fail("Invalid economics clock or revision.")
	if value.last_tick > tick or value.assessment_tick > value.last_tick:
		return fail("Economics evidence is ahead of the physics clock.")
	if not value.assessment is Dictionary or not keys(value.assessment, ["components", "terminal", "total_loss", "unresolved"]) \
		or value.assessment.terminal != false:
		return fail("Only active-flight economics can resume; terminal reports remain view-only.")
	var dossier: Dictionary = incident.get("dossier")
	if not Calculator.calculate(dossier, value.assessment).get("ok", false):
		return fail("Invalid checkpoint assessment.")
	if not value.journal is Array or value.journal.size() > 128 or not value.facts is Dictionary \
		or not value.inspections is Array or value.inspections.size() > 16 or not value.blocked is Dictionary \
		or not value.repair_choices is Array or value.repair_choices.size() > 16:
		return fail("Invalid or unbounded economics history.")
	if JSON.stringify(value.inspections).to_utf8_buffer().size() > Inspection.MAX_BYTES \
		or JSON.stringify(value.repair_choices).to_utf8_buffer().size() > Inspection.MAX_BYTES:
		return fail("Inspection or repair history exceeds its byte limit.")
	var seen := {}
	var previous_tick := -1
	for event: Variant in value.journal:
		if not valid_event(event, bindings, value.last_tick) or event.lifecycle != "new" or event.tick < previous_tick:
			return fail("Invalid or out-of-order contact journal.")
		var key := str(event.event_id) + ":" + str(event.response)
		if seen.has(key):
			return fail("Duplicate contact journal event.")
		seen[key] = true
		previous_tick = event.tick
	for key: Variant in value.facts:
		var fact: Variant = value.facts[key]
		if key == "restored_propeller_strike":
			if not fact is Dictionary or not keys(fact, ["tick", "rpm", "point_ned", "velocity_ned"]) \
				or not fact.tick is int or fact.tick < 0 or fact.tick > value.last_tick \
				or Events.strike_event(fact, fact.tick, "restored checkpoint", bindings).is_empty():
				return fail("Invalid restored propeller evidence.")
		elif key in ["propeller_strike", "water_exposure"]:
			if not valid_event(fact, bindings, value.last_tick):
				return fail("Invalid confirmed contact fact.")
			if key == "propeller_strike" and (fact.source != "propeller" or fact.event_type != "strike"):
				return fail("Mismatched propeller fact.")
			if key == "water_exposure" and (fact.source != "lake" or fact.get("material") != "water"):
				return fail("Mismatched water fact.")
		else:
			return fail("Unknown confirmed contact fact.")
	var blocked := {}
	var receipt_hashes := {}
	var receipts_by_id := {}
	var latest_decisions := {}
	var last_revision := -1
	var has_full_inspection := false
	var inspected_assessment := {components = {}, terminal = false, total_loss = false, unresolved = []}
	for receipt: Variant in value.inspections:
		if not receipt is Dictionary or not receipt.get("expected_revision") is int \
			or receipt.expected_revision <= last_revision or receipt.expected_revision >= value.revision:
			return fail("Invalid inspection revision order.")
		var checked := Inspection.validate(receipt, dossier, inspected_assessment, value.identity, value.catalog_hash, receipt.expected_revision, blocked)
		if not checked.ok or receipt_hashes.has(receipt.inspection_id):
			return fail("Invalid or duplicate inspection receipt.")
		blocked = checked.blocked
		inspected_assessment = checked.assessment
		has_full_inspection = has_full_inspection or receipt.full_inspection
		for id: Variant in receipt.components:
			var decision: Dictionary = receipt.components[id].duplicate(true)
			decision.erase("evidence")
			decision.erase("damage_flags")
			latest_decisions[id] = decision
		receipt_hashes[receipt.inspection_id] = JSON.stringify(receipt, "", true, true).sha256_text()
		receipts_by_id[receipt.inspection_id] = receipt
		last_revision = receipt.expected_revision
	if value.assessment.total_loss != inspected_assessment.total_loss:
		return fail("Whole-aircraft disposition disagrees with full inspection evidence.")
	# Only a full inspection can remove these contact-derived caveats. Diagnostics
	# without retained contacts still require an unresolved reason, never a zero bill.
	if not has_full_inspection:
		var required_reasons := []
		for event: Dictionary in value.journal:
			if event.source != "propeller" or event.event_type != "strike":
				required_reasons.append(Inspection.RESOLVABLE[0])
		if value.facts.has("water_exposure"):
			required_reasons.append(Inspection.RESOLVABLE[1])
		if value.facts.has("propeller_strike") or value.facts.has("restored_propeller_strike"):
			required_reasons.append(Inspection.RESOLVABLE[3] if not dossier.get("propeller_component_id", "").is_empty() else "A propeller strike was recorded; no compatible replacement price is available.")
		if value.facts.has("restored_propeller_strike"):
			required_reasons.append("Session restored or aircraft reloaded: earlier damage history is unavailable.")
		for reason: String in required_reasons:
			if not value.assessment.unresolved.has(reason):
				return fail("Uninspected contact lost its unresolved assessment reason.")
		if value.revision > 0 and value.journal.is_empty() and value.facts.is_empty() and value.inspections.is_empty() and value.assessment.unresolved.is_empty():
			return fail("Damage revision lost its unresolved diagnostic evidence.")
	if blocked != value.blocked:
		return fail("Inspection restrictions disagree with their evidence.")
	for id: Variant in blocked:
		var disposition: Variant = value.assessment.components.get(id, {}).get("disposition")
		if disposition == "reuse" or (disposition == "repair" and blocked[id] == "replace_only"):
			return fail("Assessment contradicts an inspection restriction.")
	var prop_id: String = dossier.get("propeller_component_id", "")
	var forced := {}
	if value.facts.has("propeller_strike") or value.facts.has("restored_propeller_strike"):
		if not prop_id.is_empty():
			forced[prop_id] = {disposition = "replace", quantity = 1}
			for id: String in dossier.get("propeller_inspection_ids", []):
				if id != prop_id:
					forced[id] = {disposition = "inspect"}
	for id: String in forced:
		if not value.assessment.components.has(id):
			return fail("Assessment omitted a confirmed propeller decision.")
	# CR-39d: a retained non-propeller contact may name its mapped parts as pending inspection.
	var contact_inspections := {}
	var contact_map: Variant = dossier.get("contact_components", {})
	if contact_map is Dictionary:
		for event: Dictionary in value.journal:
			if event.source == "propeller" and event.event_type == "strike":
				continue
			var contact_id := str(event.get("contact_id", ""))
			for key: String in [contact_id, str(event.get("probe_id", "")), "%s/%s" % [event.source, contact_id]]:
				if not key.is_empty() and contact_map.get(key) is Array:
					for mapped: Variant in contact_map[key]:
						contact_inspections[str(mapped)] = true
	for id: Variant in latest_decisions:
		if not value.assessment.components.has(id):
			return fail("Assessment omitted an inspected component.")
	for id: Variant in value.assessment.components:
		var decision: Dictionary = value.assessment.components[id]
		if decision.has("quantity") and (not decision.quantity is int or decision.quantity <= 0):
			return fail("Checkpoint decisions require positive affected quantities.")
		if decision != latest_decisions.get(id) and decision != forced.get(id) \
			and not (contact_inspections.has(id) and decision == {disposition = "inspect"}):
			return fail("Assessment has no matching inspection or confirmed propeller decision.")
	if (value.facts.has("propeller_strike") or value.facts.has("restored_propeller_strike")) \
		and value.assessment.components.get(prop_id, {}).get("disposition") in ["reuse", "repair"]:
		return fail("Confirmed propeller damage contradicts the assessment.")
	var choices := {}
	for choice: Variant in value.repair_choices:
		if not choice is Dictionary or not keys(choice, ["inspection_id", "recipe_book_sha256", "component_id", "option_id", "labor_mode", "costing_basis", "provenance"]) \
			or not receipt_hashes.has(choice.inspection_id) or choices.has(choice.inspection_id) \
			or choice.recipe_book_sha256 != value.recipe_hash or not choice.provenance is Dictionary \
			or choice.labor_mode not in ["diy", "paid"] or choice.costing_basis not in ["cash", "consumption"] \
			or not Inspection._text(choice.component_id) or not Inspection._text(choice.option_id):
			return fail("Invalid repair choice provenance.")
		if not valid_choice(choice, receipts_by_id[choice.inspection_id], dossier, incident.get("_recipe_book")):
			return fail("Repair provenance disagrees with its recipe or inspection decision.")
		choices[choice.inspection_id] = true
	if value.revision == 0 and (not value.journal.is_empty() or not value.facts.is_empty() or not value.inspections.is_empty() \
		or value.assessment_tick != -1 or not value.assessment.components.is_empty() or not value.assessment.unresolved.is_empty()):
		return fail("Healthy revision contains damage evidence.")
	if value.revision > 0 and value.assessment_tick < 0:
		return fail("Damage revision has no accepted evidence tick.")
	return {ok = true, data = copy, seen = seen, receipt_hashes = receipt_hashes, errors = []}


static func valid_choice(choice: Dictionary, receipt: Dictionary, dossier: Dictionary, recipes: Dictionary) -> bool:
	var id: String = choice.component_id
	if not receipt.components.has(id):
		return false
	var decision: Dictionary = receipt.components[id].duplicate(true)
	decision.erase("evidence")
	decision.erase("damage_flags")
	decision.erase("inspection_minor")
	var provenance: Dictionary = choice.provenance
	var inspected := {format = "openrc-repair-inspection v1", basis = receipt.basis,
		components = {id: {status = "inspected", damage_class = provenance.get("damage_class"),
			quantity = decision.get("quantity"), measurements = provenance.get("inspection_measurements"),
			evidence = provenance.get("inspection_evidence"), labor_minutes = provenance.get("labor_minutes", 0),
			replacement_comparable = provenance.get("replacement_comparable", provenance.get("replacement_minor") != null)}}}
	var plan := RepairPlanner.plan(dossier, inspected, recipes, choice.labor_mode)
	var selection := RepairPlanner.select_option(plan, id, choice.option_id, choice.costing_basis)
	return selection.get("ok", false) and selection.decision == decision and selection.provenance == provenance


static func valid_event(event: Variant, bindings: Dictionary, tick: int) -> bool:
	return event is Dictionary and event.get("tick") is int and event.tick <= tick \
		and Events.validate_events([event], event.tick, bindings)


static func wrap(visual: Dictionary, economy: Dictionary) -> Dictionary:
	return seal({format = ENVELOPE, visual = visual, economy = economy})


static func unwrap(value: Variant) -> Dictionary:
	if not native_data(value) or not value is Dictionary or not keys(value, ["format", "visual", "economy", "payload_sha256"]) \
		or value.format != ENVELOPE or not value.visual is Dictionary or not value.economy is Dictionary:
		return fail("Invalid paired economics checkpoint.")
	var copy: Dictionary = value.duplicate(true)
	copy.erase("payload_sha256")
	if value.payload_sha256 != digest(copy):
		return fail("Paired economics checkpoint integrity mismatch.")
	return {ok = true, visual = value.visual.duplicate(true), economy = value.economy.duplicate(true), errors = []}


static func native_data(value: Variant, depth := 0, budget: Array = [0]) -> bool:
	if depth == 0:
		budget = [0]
	budget[0] += 1
	if depth > 24 or budget[0] > 65536:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value).length() <= 65536
		TYPE_ARRAY, TYPE_DICTIONARY:
			if value.size() > 4096:
				return false
			for key: Variant in value:
				if value is Dictionary:
					if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not native_data(value[key], depth + 1, budget):
						return false
				elif not native_data(key, depth + 1, budget):
					return false
			return true
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_BYTE_ARRAY:
			if value.size() > 65536:
				return false
			for element: Variant in value:
				if not native_data(element, depth + 1, budget):
					return false
			return true
	return false


static func keys(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for key: Variant in value:
		if key not in fields:
			return false
	return true


static func fail(message: String) -> Dictionary:
	return {ok = false, errors = [message]}
