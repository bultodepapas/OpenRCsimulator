extends RefCounted
## CR-30c: native, integrity-checked economics state for an active-flight checkpoint.
## Digests detect changed data; they are not authentication of inspection evidence.
const Events = preload("res://sim/aircraft_contact_events.gd")
const Inspection = preload("res://economy/inspection.gd")
const Calculator = preload("res://economy/calculator.gd")
const RepairPlanner = preload("res://economy/repair_planner.gd")
const DamageAssessment = preload("res://economy/damage_assessment.gd")
const CostTransaction = preload("res://economy/cost_transaction.gd")
const FORMAT := "openrc-economics-checkpoint v3"
const ENVELOPE := "openrc-flight-economics-checkpoint v1"
const MAX_BYTES := 262144
const FIELDS := ["format", "tick", "catalog_hash", "recipe_hash", "profile_hash", "purchase_book_hash", "labor_policy_hash", "costing_mode", "purchase_package_id", "cost_transactions", "quote_history", "quote_history_truncated", "active_cost_receipt", "bindings_hash", "identity", "assessment", "last_tick", "assessment_tick", "revision", "journal", "facts", "fact_revisions", "inspections", "blocked", "repair_choices", "summaries", "game_scopes", "game_receipts", "scope_unresolved", "seen_order", "proof_floor_tick", "tick_event_count", "open_contacts", "decision_revisions", "journal_overflow", "evidence_overflow", "prior_history_unknown", "terminal_qualified", "unmapped_evidence", "unmapped_revision", "payload_sha256"]


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
		recipe_hash = incident.get("_recipe_hash"), profile_hash = incident.get("_profile_hash"),
		purchase_book_hash = incident.get("_purchase_book_hash"), labor_policy_hash = incident.get("_labor_policy_hash"),
		costing_mode = incident.get("_costing_mode"), purchase_package_id = incident.get("_purchase_package_id"),
		cost_transactions = incident.get("_cost_transactions"), quote_history = incident.get("_quote_history"),
		quote_history_truncated = incident.get("_quote_history_truncated"), active_cost_receipt = incident.get("_active_cost_receipt"),
		bindings_hash = digest(bindings),
		identity = incident.get("_identity"), assessment = incident.get("_assessment"),
		last_tick = incident.get("_last_tick"), assessment_tick = incident.get("_assessment_tick"),
		revision = incident.get("_revision"), journal = incident.get("journal"),
		facts = incident.get("_confirmed_facts"), fact_revisions = incident.get("_fact_revisions"), inspections = incident.get("_inspections"),
		blocked = incident.get("_reuse_blocked"), repair_choices = incident.get("_repair_choices"),
		summaries = incident.get("_summaries"), game_scopes = incident.get("_game_scopes"),
		game_receipts = incident.get("_game_receipts"), scope_unresolved = incident.get("_scope_unresolved"),
		seen_order = incident.get("_seen_order"),
		proof_floor_tick = incident.get("_proof_floor_tick"), tick_event_count = incident.get("_tick_event_count"),
		open_contacts = incident.get("_open_contacts"), decision_revisions = incident.get("_decision_revisions"),
		journal_overflow = incident.get("_journal_overflow"), evidence_overflow = incident.get("_evidence_overflow"),
		prior_history_unknown = incident.get("_prior_history_unknown"), terminal_qualified = incident.get("_terminal_qualified"),
		unmapped_evidence = incident.get("_unmapped_evidence"), unmapped_revision = incident.get("_unmapped_revision")}
	if not native_data(value):
		return {}
	value = seal(value)
	return value if prepare(value, incident, tick, bindings).ok else {}


## Complete validation precedes any live mutation. Only the same frozen prices/recipes can resume.
static func prepare(value: Variant, incident: RefCounted, tick: int, bindings: Dictionary) -> Dictionary:
	if value is Dictionary and value.get("format") in ["openrc-economics-checkpoint v1", "openrc-economics-checkpoint v2"]:
		return fail("Legacy economics checkpoint cannot resume; view its archived report instead.")
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
		or value.profile_hash != incident.get("_profile_hash") \
		or value.purchase_book_hash != incident.get("_purchase_book_hash") or value.labor_policy_hash != incident.get("_labor_policy_hash") \
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
	var assessment_fields := ["components", "terminal", "total_loss", "unresolved"]
	if value.assessment is Dictionary and value.assessment.has("incurred_fees"):
		assessment_fields.append("incurred_fees")
	if not value.assessment is Dictionary or not keys(value.assessment, assessment_fields) \
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
	var journal_seen := {}
	var previous_tick := -1
	var journal_bytes := 0
	for event: Variant in value.journal:
		if not valid_event(event, bindings, value.last_tick) or event.lifecycle != "new" or event.tick < previous_tick:
			return fail("Invalid or out-of-order contact journal.")
		journal_bytes += var_to_bytes(event).size()
		if journal_bytes > 65536:
			return fail("Contact journal byte bound exceeded.")
		var key := str(event.event_id)
		if journal_seen.has(key):
			return fail("Duplicate contact journal event.")
		journal_seen[key] = JSON.stringify(event, "", true, true).sha256_text()
		previous_tick = event.tick
	var proof := _validate_contact_state(value, dossier, journal_seen, bindings)
	if not proof.ok:
		return proof
	var seen: Dictionary = proof.seen
	var game_proof := _validate_game_scopes(value, incident, bindings)
	if not game_proof.ok:
		return game_proof
	if not value.journal_overflow:
		for event_id: String in seen:
			if event_id.contains(":new:") and not journal_seen.has(event_id):
				return fail("Contact journal truncation flag was removed.")
		for row: Dictionary in value.summaries.values():
			if str(row.event_id).contains(":new:") and not journal_seen.has(row.event_id):
				return fail("Contact summary refers to truncated journal evidence.")
	for event: Dictionary in value.journal:
		if event.source == "propeller" and event.event_type == "strike":
			continue
		var game := DamageAssessment.resolve(incident.get("_damage_profile"), event) if not incident.get("_damage_profile").is_empty() else {matched = false}
		var targets: Array = game.get("components", []) if game.get("matched", false) else incident._contact_components(event, bindings)
		for id: String in targets:
			if not value.summaries.has(id) or value.summaries[id].first_tick > event.tick:
				return fail("Contact summary omitted a retained mapped component.")
	if value.prior_history_unknown and value.revision > 0 and not value.assessment.unresolved.has("Session restored or aircraft reloaded: earlier damage history is unavailable."):
		return fail("Unpaired checkpoint lost its missing-history warning.")
	if value.evidence_overflow and not value.assessment.unresolved.has("Contact evidence exceeded its bound; coverage is incomplete.") \
		and not value.assessment.unresolved.has("Contact episode limit reached; coverage is incomplete.") \
		and not value.assessment.unresolved.has("Component summary limit reached; coverage is incomplete."):
		return fail("Contact evidence overflow lost its coverage warning.")
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
	if not value.fact_revisions is Dictionary or value.fact_revisions.size() != value.facts.size():
		return fail("Confirmed contact facts lack their evidence revisions.")
	for key: Variant in value.fact_revisions:
		if not value.facts.has(key) or not value.fact_revisions[key] is int \
			or value.fact_revisions[key] <= 0 or value.fact_revisions[key] > value.revision:
			return fail("Invalid confirmed contact fact revision.")
	var blocked := {}
	var confirmed_replacements := {}
	var receipt_hashes := {}
	var receipts_by_id := {}
	var latest_decisions := {}
	var latest_decision_revisions := {}
	var last_revision := -1
	var last_full_revision := 0
	var restriction_timeline := []
	var inspected_assessment := {components = {}, terminal = false, total_loss = false, unresolved = []}
	for receipt: Variant in value.inspections:
		if not receipt is Dictionary or not receipt.get("expected_revision") is int \
			or receipt.expected_revision <= last_revision or receipt.expected_revision >= value.revision:
			return fail("Invalid inspection revision order.")
		var checked := Inspection.validate(receipt, dossier, inspected_assessment, value.identity, value.catalog_hash, receipt.expected_revision, blocked, confirmed_replacements)
		if not checked.ok or receipt_hashes.has(receipt.inspection_id):
			return fail("Invalid or duplicate inspection receipt.")
		blocked = checked.blocked
		inspected_assessment = checked.assessment
		if receipt.full_inspection:
			last_full_revision = receipt.expected_revision + 1
		for id: Variant in receipt.components:
			var decision: Dictionary = checked.assessment.components[id].duplicate(true)
			latest_decisions[id] = decision
			latest_decision_revisions[id] = receipt.expected_revision + 1
			if receipt.components[id].get("disposition") in ["replace", "unrecoverable"]:
				confirmed_replacements[id] = true
		restriction_timeline.append({revision = receipt.expected_revision + 1,
			blocked = blocked.duplicate(true), confirmed = confirmed_replacements.duplicate(true)})
		receipt_hashes[receipt.inspection_id] = JSON.stringify(receipt, "", true, true).sha256_text()
		receipts_by_id[receipt.inspection_id] = receipt
		last_revision = receipt.expected_revision
	if value.assessment.total_loss != inspected_assessment.total_loss:
		return fail("Whole-aircraft disposition disagrees with full inspection evidence.")
	var transactions := _validate_cost_transactions(value, incident, restriction_timeline)
	if not transactions.ok:
		return transactions
	for id: Variant in transactions.decisions:
		var decision: Dictionary = transactions.decisions[id]
		if decision.revision > int(latest_decision_revisions.get(id, 0)):
			latest_decisions[id] = decision.value
			latest_decision_revisions[id] = decision.revision
	if value.unmapped_revision > last_full_revision and not value.assessment.unresolved.has(Inspection.RESOLVABLE[0]):
		return fail("Unmapped contact lost its structural uncertainty.")
	# A later full inspection can resolve older facts, but not a new exposure or strike.
	var required_reasons := []
	if int(value.fact_revisions.get("water_exposure", 0)) > last_full_revision:
		required_reasons.append(Inspection.RESOLVABLE[1])
	var prop_pending := false
	for id: String in dossier.get("propeller_inspection_ids", []):
		if id != dossier.get("propeller_component_id") and value.assessment.components.get(id, {}).get("disposition") in ["inspect", "unknown"]:
			prop_pending = true
	if prop_pending and maxi(int(value.fact_revisions.get("propeller_strike", 0)), int(value.fact_revisions.get("restored_propeller_strike", 0))) > last_full_revision:
		required_reasons.append(Inspection.RESOLVABLE[3] if not dossier.get("propeller_component_id", "").is_empty() else "A propeller strike was recorded; no compatible replacement price is available.")
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
		var cleared: Dictionary = value.game_scopes.get(id, {})
		if not value.assessment.components.has(id) and not (cleared.get("status") == "applied" and cleared.get("action") == "scope_clear"):
			return fail("Assessment omitted a confirmed propeller decision.")
	for id: Variant in latest_decisions:
		if not value.assessment.components.has(id):
			return fail("Assessment omitted an inspected component.")
	for id: Variant in value.assessment.components:
		var decision: Dictionary = value.assessment.components[id]
		if decision.has("quantity") and (not decision.quantity is int or decision.quantity <= 0):
			return fail("Checkpoint decisions require positive affected quantities.")
		var latest: Dictionary = latest_decisions.get(id, {})
		var summary: Dictionary = value.summaries.get(id, {})
		var newer_contact: bool = int(summary.get("evidence_revision", 0)) > int(latest_decision_revisions.get(id, 0))
		if confirmed_replacements.has(id) and decision.get("disposition") not in ["replace", "unrecoverable"]:
			return fail("Confirmed replacement was downgraded by later evidence.")
		var reopened := {disposition = "inspect"}
		if latest.has("inspection_minor"):
			reopened.inspection_minor = latest.inspection_minor
		var permitted_contact: bool = newer_contact and decision == reopened
		var game_replacement := {disposition = "replace", quantity = 1}
		if latest.has("inspection_minor"):
			game_replacement.inspection_minor = latest.inspection_minor
		var permitted_game: bool = not incident.get("_damage_profile").is_empty() and newer_contact \
			and summary.get("recommendation") == "replace" and decision == game_replacement \
			and value.decision_revisions.get(id) == summary.evidence_revision
		var scoped: Dictionary = value.game_scopes.get(id, {})
		if scoped.get("status") == "applied" and scoped.get("action") in ["repair", "replace"]:
			var expected: Dictionary = game_proof.decisions.get(id, {})
			permitted_game = permitted_game or decision == expected
		var forced_decision: Dictionary = forced.get(id, {})
		if latest.has("inspection_minor") and not forced_decision.is_empty():
			forced_decision.inspection_minor = latest.inspection_minor
		if decision != latest and decision != forced_decision and not permitted_contact and not permitted_game:
			return fail("Assessment has no matching inspection or confirmed propeller decision.")
		if newer_contact and latest.get("disposition") in ["reuse", "repair"] and decision == latest:
			return fail("Later contact did not reopen a cleared component.")
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
	return {ok = true, data = copy, seen = seen, receipt_hashes = receipt_hashes,
		confirmed_replacements = confirmed_replacements, last_full_revision = last_full_revision,
		transaction_hashes = transactions.hashes, errors = []}


static func _validate_contact_state(value: Dictionary, dossier: Dictionary, journal_seen: Dictionary, bindings: Dictionary) -> Dictionary:
	if not value.seen_order is Array or value.seen_order.size() > 128 or not value.summaries is Dictionary \
		or value.summaries.size() > 256 or not value.open_contacts is Dictionary or value.open_contacts.size() > 128 \
		or not value.decision_revisions is Dictionary or not value.proof_floor_tick is int \
		or value.proof_floor_tick < -1 or value.proof_floor_tick > value.last_tick \
		or not value.tick_event_count is int or value.tick_event_count < 0 or value.tick_event_count > 64:
		return fail("Invalid bounded contact summary or replay cursor.")
	if not value.unmapped_revision is int or value.unmapped_revision < 0 or value.unmapped_revision > value.revision \
		or value.unmapped_evidence != (value.unmapped_revision > 0):
		return fail("Invalid unmapped-contact evidence revision.")
	for flag: String in ["journal_overflow", "evidence_overflow", "prior_history_unknown", "terminal_qualified", "unmapped_evidence"]:
		if not value[flag] is bool:
			return fail("Invalid contact coverage flag.")
	var seen := {}
	var previous_tick := -1
	var current_count := 0
	for proof: Variant in value.seen_order:
		if not proof is Dictionary or not keys(proof, ["id", "tick", "digest"]) \
			or not Inspection._text(proof.id) or not proof.tick is int or proof.tick < previous_tick \
			or proof.tick > value.last_tick or proof.tick < value.proof_floor_tick \
			or not proof.digest is String or proof.digest.length() != 64 or not proof.digest.is_valid_hex_number(false) \
			or seen.has(proof.id):
			return fail("Invalid or duplicate contact replay proof.")
		if journal_seen.has(proof.id) and journal_seen[proof.id] != proof.digest:
			return fail("Contact replay proof conflicts with retained evidence.")
		seen[proof.id] = proof.digest
		previous_tick = proof.tick
		if proof.tick == value.last_tick:
			current_count += 1
	if current_count > value.tick_event_count:
		return fail("Contact tick count is below retained proof.")
	var parts := {}
	for part: Dictionary in dossier.get("components", []):
		parts[part.id] = part
	if parts.size() > 256 or value.decision_revisions.size() > parts.size():
		return fail("Economic component bound exceeded.")
	for id: Variant in value.decision_revisions:
		var scope: Variant = value.game_scopes.get(id, {}) if value.game_scopes is Dictionary else {}
		var clear_scope: bool = scope is Dictionary and scope.get("status") == "applied" and scope.get("action") == "scope_clear"
		if not parts.has(id) or (not value.assessment.components.has(id) and not clear_scope) or not value.decision_revisions[id] is int \
			or value.decision_revisions[id] <= 0 or value.decision_revisions[id] > value.revision:
			return fail("Invalid component decision revision.")
	for id: Variant in value.summaries:
		var row: Variant = value.summaries[id]
		if not parts.has(id) or not row is Dictionary \
			or not keys(row, ["first_tick", "latest_tick", "evidence_revision", "recommendation", "reason", "event_id", "source", "peaks"]) \
			or not row.first_tick is int or not row.latest_tick is int or row.first_tick < 0 \
			or row.first_tick > row.latest_tick or row.latest_tick > value.last_tick \
			or not row.evidence_revision is int or row.evidence_revision < 0 or row.evidence_revision > value.revision \
			or row.recommendation not in ["clear", "scope_clear", "inspect", "repair", "replace"] \
			or not row.reason is String or row.reason.length() > 2048 or not row.event_id is String or row.event_id.length() > 2048 \
			or not row.source is String or row.source not in ["", "hull", "gear", "propeller"] or not row.peaks is Dictionary:
			return fail("Invalid component contact summary.")
		if row.recommendation != "clear" and (row.evidence_revision == 0 or row.event_id.is_empty() or row.reason.is_empty()):
			return fail("Damage recommendation lacks its evidence revision.")
		for channel: Variant in row.peaks:
			var number: Variant = row.peaks[channel]
			if channel not in ["depth_m", "normal_speed_mps", "slide_speed_mps", "compression_m", "compression_ratio", "speed_mps", "down_speed_mps", "endpoint_normal_speed_mps", "contact_normal_proxy_mps"] \
				or typeof(number) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(number)) or float(number) < 0.0:
				return fail("Invalid endpoint channel maximum.")
	for episode: Variant in value.open_contacts:
		if not episode is String or episode.is_empty() or episode.length() > 2048 \
			or not value.open_contacts[episode] is int or value.open_contacts[episode] < 0 \
			or value.open_contacts[episode] > value.last_tick:
			return fail("Invalid open contact episode.")
	return {ok = true, seen = seen}


## Validate the stored game decisions against their frozen profile and accepted
## event records. The digest is an integrity check, not authenticated evidence.
static func _validate_game_scopes(value: Dictionary, incident: RefCounted, bindings: Dictionary) -> Dictionary:
	if not value.game_scopes is Dictionary or value.game_scopes.size() > 256 \
		or not value.game_receipts is Array or value.game_receipts.size() > 64 \
		or not value.scope_unresolved is Dictionary or value.scope_unresolved.size() > 256 \
		or var_to_bytes(value.game_receipts).size() > 32768:
		return fail("Invalid or unbounded game assessment history.")
	var profile: Dictionary = incident.get("_damage_profile")
	if profile.get("format") != DamageAssessment.FORMAT_V2:
		return {ok = true, decisions = {}} if value.game_scopes.is_empty() and value.game_receipts.is_empty() and value.scope_unresolved.is_empty() else fail("Game assessment profile version mismatch.")
	var parts := {}
	for part: Dictionary in incident.get("dossier").get("components", []):
		parts[part.id] = part
	for id: Variant in value.scope_unresolved:
		if not parts.has(id) or not value.summaries.has(id) or not value.scope_unresolved[id] is int \
			or value.scope_unresolved[id] <= 0 or value.scope_unresolved[id] > value.revision \
			or not value.assessment.components.has(id):
			return fail("Invalid unresolved game assessment scope.")
	var receipts := {}
	var receipt_components := {}
	for receipt: Variant in value.game_receipts:
		if not receipt is Dictionary or not keys(receipt, ["format", "component_id", "evidence_revision", "observations", "action", "service_minor", "basis", "profile_sha256", "policy_version", "floor_receipt_id", "service_basis", "receipt_id"]) \
			or receipt.format != "openrc-game-scope-receipt v1" or not parts.has(receipt.component_id) \
			or receipt.basis != "scenario_assumption" or receipt.profile_sha256 != value.profile_hash \
			or receipt.policy_version != profile.policy_version \
			or receipt.service_basis != "authored whole-group cash materials or outside service; labor excluded; affected unit count unknown" \
			or not receipt.evidence_revision is int or receipt.evidence_revision <= 0 or receipt.evidence_revision > value.revision \
			or not receipt.receipt_id is String or receipts.has(receipt.receipt_id) or receipt_components.has(receipt.component_id):
			return fail("Invalid scoped game receipt.")
		var copy: Dictionary = receipt.duplicate(true)
		copy.erase("receipt_id")
		if receipt.receipt_id != digest(copy):
			return fail("Scoped game receipt digest mismatch.")
		var checked := _validate_game_candidate(receipt, profile, parts, receipts, bindings, value.last_tick)
		if not checked.ok:
			return checked
		receipts[receipt.receipt_id] = receipt
		receipt_components[receipt.component_id] = true
	var decisions := {}
	for id: Variant in value.game_scopes:
		var candidate: Variant = value.game_scopes[id]
		if not parts.has(id) or not candidate is Dictionary \
			or not keys(candidate, ["status", "observations", "evidence_revision", "action", "service_minor", "floor_receipt_id", "supersedes_receipt_id", "receipt_id"]) \
			or candidate.status not in ["pending", "applied"] or not candidate.evidence_revision is int \
			or candidate.evidence_revision <= 0 or candidate.evidence_revision > value.revision \
			or not value.summaries.has(id) or value.summaries[id].evidence_revision < candidate.evidence_revision \
			or not candidate.supersedes_receipt_id is String:
			return fail("Invalid active scoped game assessment.")
		var model: Dictionary = candidate.duplicate(true)
		model["component_id"] = id
		var checked := _validate_game_candidate(model, profile, parts, receipts, bindings, value.last_tick)
		if not checked.ok:
			return checked
		if candidate.status == "pending":
			if candidate.receipt_id != "" or value.summaries[id].evidence_revision != candidate.evidence_revision \
				or value.assessment.components.get(id, {}).get("disposition") not in ["inspect", "replace"] \
				or (not candidate.supersedes_receipt_id.is_empty() and (not receipts.has(candidate.supersedes_receipt_id) \
					or receipts[candidate.supersedes_receipt_id].component_id != id)):
				return fail("Pending game scope is not inspection-only.")
			continue
		if not candidate.supersedes_receipt_id.is_empty() or not receipts.has(candidate.receipt_id):
			return fail("Active scoped game result lacks its receipt.")
		var receipt: Dictionary = receipts[candidate.receipt_id]
		for field: String in ["evidence_revision", "observations", "action", "service_minor", "floor_receipt_id"]:
			if receipt[field] != candidate[field]:
				return fail("Active scoped game result disagrees with its receipt.")
		if value.decision_revisions.get(id) != candidate.evidence_revision:
			return fail("Scoped game decision revision mismatch.")
		if value.scope_unresolved.has(id) and candidate.action != "replace":
			return fail("An unresolved scope contradicts the active game outcome.")
		if candidate.action == "scope_clear":
			if value.assessment.components.has(id):
				return fail("A scoped clear cannot create a salvage or repair decision.")
		elif candidate.action == "repair":
			decisions[id] = {disposition = "repair", quantity = parts[id].quantity,
				repair_minor = int(candidate.service_minor), replacement_comparable = false}
			if value.assessment.components.get(id, {}).has("inspection_minor"):
				decisions[id].inspection_minor = value.assessment.components[id].inspection_minor
		else:
			if parts[id].quantity != 1:
				return fail("Grouped replacement lacks an affected-unit count.")
			decisions[id] = {disposition = "replace", quantity = 1}
			if value.assessment.components.get(id, {}).has("inspection_minor"):
				decisions[id].inspection_minor = value.assessment.components[id].inspection_minor
	return {ok = true, decisions = decisions}


static func _validate_game_candidate(candidate: Dictionary, profile: Dictionary, parts: Dictionary,
		receipts: Dictionary, bindings: Dictionary, last_tick: int) -> Dictionary:
	if not candidate.get("observations") is Array or candidate.observations.is_empty() or candidate.observations.size() > 16 \
		or candidate.get("action") not in ["scope_clear", "repair", "replace"] or not candidate.get("floor_receipt_id") is String:
		return fail("Invalid scoped game candidate.")
	var result_action := "scope_clear"
	var amount: Variant = null
	if not candidate.floor_receipt_id.is_empty():
		if not receipts.has(candidate.floor_receipt_id):
			return fail("Scoped repair floor lacks an earlier receipt.")
		var floor_receipt: Dictionary = receipts[candidate.floor_receipt_id]
		if floor_receipt.component_id != candidate.component_id or floor_receipt.action != "repair":
			return fail("Scoped repair floor names an incompatible receipt.")
		result_action = "repair"
		amount = floor_receipt.service_minor
	var seen := {}
	for item: Variant in candidate.observations:
		if not item is Dictionary or not keys(item, ["scope", "event", "action", "service_minor", "reason", "channel", "value"]) \
			or item.scope not in ["local_contact", "propeller_followup"] or not valid_event(item.event, bindings, last_tick) \
			or seen.has(item.event.event_id):
			return fail("Invalid scoped game observation.")
		seen[item.event.event_id] = true
		var assessed: Dictionary = DamageAssessment.propeller_followup(profile, item.event, candidate.component_id) if item.scope == "propeller_followup" \
			else DamageAssessment.resolve(profile, item.event).get("actions", {}).get(candidate.component_id, {})
		var matches_action: bool = assessed.get("recommendation") == item.action \
			or (item.scope == "local_contact" and assessed.get("recommendation") == "clear" and item.action == "scope_clear")
		if not assessed.get("matched", false) or not matches_action \
			or item.action not in ["scope_clear", "repair", "replace"] \
			or item.reason != assessed.get("reason", "") or item.channel != assessed.get("channel", "") \
			or item.value != assessed.get("value") \
			or (item.action == "repair" and assessed.get("service_minor") != item.service_minor) \
			or (item.action != "repair" and item.service_minor != null):
			return fail("Scoped game observation disagrees with its authored rule.")
		if _game_rank(item.action) > _game_rank(result_action):
			result_action = item.action
			amount = item.service_minor
		elif item.action == "repair" and result_action == "repair":
			amount = maxi(int(amount), int(item.service_minor))
	if candidate.action != result_action or candidate.service_minor != amount:
		return fail("Scoped game aggregation disagrees with the evidence.")
	return {ok = true}


static func _game_rank(action: String) -> int:
	return ["scope_clear", "repair", "replace"].find(action)


static func _validate_cost_transactions(value: Dictionary, incident: RefCounted, timeline: Array) -> Dictionary:
	if value.costing_mode not in ["diy", "paid"] or not value.purchase_package_id is String \
		or value.purchase_package_id.length() > 128 or not value.cost_transactions is Array \
		or value.cost_transactions.size() > 16 or var_to_bytes(value.cost_transactions).size() > 98304 \
		or not value.quote_history is Array or value.quote_history.size() > 8 or var_to_bytes(value.quote_history).size() > 32768 \
		or not value.quote_history_truncated is bool \
		or not value.active_cost_receipt is Dictionary:
		return fail("Invalid or unbounded selected cost history.")
	var book: Dictionary = incident.get("_package_book")
	var labor: Dictionary = incident.get("_labor_policy")
	if book.is_empty() or labor.is_empty():
		if not value.cost_transactions.is_empty() or not value.quote_history.is_empty() or value.quote_history_truncated or not value.active_cost_receipt.is_empty() \
			or value.costing_mode != "diy" or not value.purchase_package_id.is_empty():
			return fail("Selected cost history lacks a compatible frozen book.")
		return {ok = true, hashes = {}, decisions = {}}
	if CostTransaction.digest(book) != value.purchase_book_hash or CostTransaction.digest(labor) != value.labor_policy_hash:
		return fail("Frozen purchase book or labor policy changed.")
	var context := {identity = value.identity.duplicate(true), catalog_hash = value.catalog_hash,
		profile_hash = value.profile_hash, recipe_hash = value.recipe_hash,
		purchase_book_hash = value.purchase_book_hash, labor_policy_hash = value.labor_policy_hash,
		package_book = book.duplicate(true), labor_policy = labor.duplicate(true)}
	var dossier: Dictionary = incident.get("dossier")
	var recipes: Dictionary = incident.get("_recipe_book")
	var hashes := {}
	var decisions := {}
	var receipts := {}
	var previous_revision := -1
	for receipt: Variant in value.cost_transactions:
		if not receipt is Dictionary or not receipt.get("expected_revision") is int \
			or receipt.expected_revision <= previous_revision or receipt.expected_revision >= value.revision \
			or not receipt.get("transaction_id") is String or hashes.has(receipt.transaction_id) \
			or not _cost_restrictions_match(receipt, timeline) \
			or not CostTransaction.verify_receipt(receipt, dossier, recipes, context):
			return fail("Invalid historical cost transaction or restriction snapshot.")
		hashes[receipt.transaction_id] = receipt.request_digest
		receipts[receipt.transaction_id] = receipt
		previous_revision = receipt.expected_revision
		for fee: Dictionary in receipt.request.incurred_fees:
			if fee not in value.assessment.get("incurred_fees", []):
				return fail("A committed incident fee was removed.")
		for id: String in receipt.repair.get("component_ids", []):
			if not receipt.covered_decisions.has(id):
				return fail("Cost transaction lost its selected repair decision.")
			decisions[id] = {revision = receipt.expected_revision + 1,
				value = receipt.covered_decisions[id].duplicate(true)}
	previous_revision = -1
	for receipt: Variant in value.quote_history:
		if not receipt is Dictionary or not receipt.get("expected_revision") is int \
			or receipt.expected_revision <= previous_revision or receipt.expected_revision >= value.revision \
			or not receipt.get("request") is Dictionary or not receipt.request.get("repair_choices", []).is_empty() \
			or not receipt.request.get("incurred_fees", []).is_empty() or receipts.has(receipt.get("transaction_id")) \
			or not _cost_restrictions_match(receipt, timeline) \
			or not CostTransaction.verify_receipt(receipt, dossier, recipes, context):
			return fail("Invalid historical quote selection.")
		receipts[receipt.transaction_id] = receipt
		previous_revision = receipt.expected_revision
	if not value.active_cost_receipt.is_empty():
		var active: Dictionary = value.active_cost_receipt
		if not active.get("expected_revision") is int or active.expected_revision > value.revision \
			or active.get("request", {}).get("labor_mode") != value.costing_mode \
			or not _cost_restrictions_match(active, timeline) \
			or not CostTransaction.verify_receipt(active, dossier, recipes, context):
			return fail("Invalid active selected cost receipt.")
		if receipts.has(active.transaction_id) and receipts[active.transaction_id] != active:
			return fail("Active cost receipt conflicts with retained history.")
		if not value.purchase_package_id.is_empty():
			var scope: Dictionary = active.base_assessment.duplicate(true)
			for id: Variant in active.covered_decisions:
				scope.components[id] = active.covered_decisions[id].duplicate(true)
			var adapted := CostTransaction.package_candidates(book, dossier, scope)
			var found := false
			if adapted.get("ok", false):
				for candidate: Variant in active.request.selected_candidate_ids:
					found = found or adapted.get("candidate_package_ids", {}).get(candidate) == value.purchase_package_id
			if active.request.purchase_mode != "explicit" or not found:
				return fail("Selected package does not match its frozen receipt.")
		var reconciled := CostTransaction.reconcile(dossier, value.assessment, active)
		if not reconciled.get("ok", false) and active.get("repair", {}).get("component_ids", []).is_empty():
			return fail("Automatic cost plan is stale for the current incident.")
	elif not value.purchase_package_id.is_empty():
		# A selected package may become unavailable; it is not silently reset to auto.
		var known := false
		for package: Dictionary in book.get("packages", []):
			known = known or package.get("id") == value.purchase_package_id
		if not known:
			return fail("Selected package is absent from the frozen book.")
	return {ok = true, hashes = hashes, decisions = decisions}


static func _cost_restrictions_match(receipt: Dictionary, timeline: Array) -> bool:
	var blocked := {}
	var confirmed := {}
	for item: Dictionary in timeline:
		if item.revision > receipt.expected_revision:
			break
		blocked = item.blocked
		confirmed = item.confirmed
	return receipt.get("blocked_at_prepare") == blocked and receipt.get("confirmed_replacements_at_prepare") == confirmed


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
