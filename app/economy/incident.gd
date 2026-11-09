extends RefCounted
## CR-30: read-only, bounded interpretation of accepted contact events. No solver writes.

signal assessment_changed(report: Dictionary, terminal: bool)

const Catalog = preload("res://economy/catalog.gd")
const Calculator = preload("res://economy/calculator.gd")
const Inspection = preload("res://economy/inspection.gd")
const RepairPlanner = preload("res://economy/repair_planner.gd")
const ReplacementQuote = preload("res://economy/replacement_quote.gd")
const Checkpoint = preload("res://economy/checkpoint.gd")
const DamageAssessment = preload("res://economy/damage_assessment.gd")
const RECIPE_PATH := "res://data/economy/repair-recipes.json"
const Events = preload("res://sim/aircraft_contact_events.gd")
const MAX_EVENTS := 128
const ARCHIVE_PATH := "user://last_accident.json"
const ARCHIVE_MAX_BYTES := 262144
const MAX_INSPECTIONS := 16
const MAX_EVENTS_PER_TICK := 64
const MAX_EVENT_BYTES := 65536
const MAX_JOURNAL_BYTES := 65536
const MAX_OPEN_CONTACTS := 128
const BINDING_NOTE := "Prices were authored for an earlier revision of this aircraft; its priced parts and contacts were verified unchanged."
const REGISTERED_VARIANT_NOTE := "This registered battery configuration preserves the priced inventory and contact bindings."

var dossier: Dictionary = {}
var report: Dictionary = {}
var last_report: Dictionary = {}
var journal: Array = []
var archive_path := ARCHIVE_PATH
var terminal := false
var _assessment: Dictionary = {}
var _seen: Dictionary = {}
var _seen_order: Array = []
var _proof_floor_tick := -1
var _tick_event_count := 0
var _open_contacts: Dictionary = {}
var _summaries: Dictionary = {}
var _decision_revisions: Dictionary = {}
var _damage_profile: Dictionary = {}
var _profile_hash := ""
var _profile_error := ""
var _journal_overflow := false
var _journal_bytes := 0
var _evidence_overflow := false
var _prior_history_unknown := false
var _terminal_qualified := false
var _unmapped_evidence := false
var _unmapped_revision := 0
var _full_inspection_revision := 0
var _last_tick := -1
var _assessment_tick := -1
var _pending := false
var _confirmed_facts: Dictionary = {}
var _fact_revisions: Dictionary = {}
var _catalog_hash := ""
var _identity: Dictionary = {}
var _catalog_errors: Array = []
var _binding := "exact"
var _offer_sources: Dictionary = {}
var _dirty := false
var _revision := 0
var _persisted_revision := -1
var _flush_attempt_revision := -1
var _flush_error := OK
var _inspections: Array = []
var _inspection_hashes: Dictionary = {}
var _reuse_blocked: Dictionary = {}
var _confirmed_replacements: Dictionary = {}
var _recipe_book: Dictionary = {}
var _recipe_hash := ""
var _repair_choices: Array = []
# CR-39e: res:// catalog, aircraft and recipe bytes are fixed for a session; a reset reuses
# the validated load for the same route and physical identity instead of reparsing ~200 KB.
var _catalog_cache_key := ""
var _catalog_cache: Dictionary = {}
var _recipe_cache_loaded := false
var _recipe_cache: Dictionary = {}
var _recipe_cache_hash := ""


func begin(aircraft_id: String, source_hash: String) -> void:
	var key := aircraft_id + "|" + source_hash
	if key != _catalog_cache_key:
		_catalog_cache = Catalog.load_for(aircraft_id, source_hash)
		_catalog_cache_key = key
	begin_with_catalog(_catalog_cache, aircraft_id, source_hash)


func begin_with_catalog(loaded: Dictionary, aircraft_id: String, source_hash: String) -> void:
	dossier = loaded.get("dossier", {}).duplicate(true) if loaded.get("ok", false) else {}
	_catalog_errors = Array(loaded.get("errors", []))
	_binding = str(loaded.get("binding", "exact"))
	_catalog_hash = str(loaded.get("catalog_hash", ""))
	_offer_sources = loaded.get("offer_sources", {}).duplicate(true)
	_identity = {aircraft_id = aircraft_id, source_sha256 = dossier.get("source_sha256", source_hash),
		incident_id = "%s-%d" % [Time.get_datetime_string_from_system(true), Time.get_ticks_usec()]}
	_damage_profile = {}
	_profile_hash = ""
	_profile_error = ""
	if loaded.has("damage_profile"):
		var profile_check := DamageAssessment.validate(loaded.damage_profile, dossier, str(_identity.source_sha256))
		if profile_check.ok:
			_damage_profile = loaded.damage_profile.duplicate(true)
			_profile_hash = Checkpoint.digest(_damage_profile)
		else:
			_profile_error = str(profile_check.error)
	report = {}
	journal = []
	_assessment = {components = {}, terminal = false, total_loss = false, unresolved = []}
	_seen = {}
	_seen_order = []
	_proof_floor_tick = -1
	_tick_event_count = 0
	_open_contacts = {}
	_summaries = {}
	_decision_revisions = {}
	_journal_overflow = false
	_journal_bytes = 0
	_evidence_overflow = false
	_prior_history_unknown = false
	_terminal_qualified = false
	_unmapped_evidence = false
	_unmapped_revision = 0
	_full_inspection_revision = 0
	_last_tick = -1
	_assessment_tick = -1
	_pending = false
	_confirmed_facts = {}
	_fact_revisions = {}
	terminal = false
	_dirty = false
	_revision = 0
	_persisted_revision = -1
	_flush_attempt_revision = -1
	_flush_error = OK
	_inspections = []
	_inspection_hashes = {}
	_reuse_blocked = {}
	_confirmed_replacements = {}
	_repair_choices = []
	if not _recipe_cache_loaded:
		_recipe_cache_loaded = true
		var recipe_bytes := FileAccess.get_file_as_bytes(RECIPE_PATH)
		if not recipe_bytes.is_empty() and recipe_bytes.size() <= Inspection.MAX_BYTES:
			var parsed: Variant = JSON.parse_string(recipe_bytes.get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY:
				_recipe_cache = parsed
				var hash_context := HashingContext.new()
				hash_context.start(HashingContext.HASH_SHA256)
				hash_context.update(recipe_bytes)
				_recipe_cache_hash = hash_context.finish().hex_encode()
	_recipe_book = _recipe_cache.duplicate(true)
	_recipe_hash = _recipe_cache_hash


## Cost an explicitly chosen compatible repair against the frozen session recipe book.
## No cheapest-option auto-selection, damage inference, inventory debit or solver mutation.
func apply_repair_choice(receipt: Dictionary, repair_inspection: Dictionary, component_id: String,
		option_id: String, labor_mode: String, costing_basis: String) -> Dictionary:
	if receipt.get("total_loss", true) or receipt.get("basis") != repair_inspection.get("basis"):
		return {ok = false, errors = ["Repair choice requires a repair assessment with the same evidence basis."]}
	if typeof(receipt.get("components")) != TYPE_DICTIONARY \
		or typeof(receipt.components.get(component_id)) != TYPE_DICTIONARY:
		return {ok = false, errors = ["Repair choice requires an explicit component receipt."]}
	var component_receipt: Dictionary = receipt.components[component_id]
	if typeof(component_receipt.get("damage_flags")) != TYPE_ARRAY:
		return {ok = false, errors = ["Repair choice requires explicit damage flags."]}
	var plan: Dictionary = RepairPlanner.plan(dossier, repair_inspection, _recipe_book, labor_mode)
	if not plan.get("ok", false):
		return plan
	if "structural_damage" in component_receipt.damage_flags \
		and plan.get("components", {}).get(component_id, {}).get("damage_class") != "structural":
		return {ok = false, errors = ["Structural damage cannot use a covering-only repair."]}
	var selection: Dictionary = RepairPlanner.select_option(plan, component_id, option_id, costing_basis)
	if not selection.get("ok", false):
		return selection
	var candidate := receipt.duplicate(true)
	var decision: Dictionary = selection.decision.duplicate(true)
	var choice_identity := JSON.stringify({inspection = repair_inspection, selection = selection,
		recipe_hash = _recipe_hash, labor = labor_mode, material_basis = costing_basis}, "", true, true).sha256_text()
	decision.evidence = str(component_receipt.get("evidence", "")) + " Repair evidence SHA-256: " + choice_identity
	decision.damage_flags = component_receipt.damage_flags.duplicate()
	if component_receipt.has("inspection_minor"):
		decision.inspection_minor = component_receipt.inspection_minor
	candidate.components[component_id] = decision
	candidate.evidence = str(candidate.get("evidence", "")) + " Repair: %s/%s; %s labor; %s material basis." % [component_id, option_id, labor_mode, costing_basis]
	if _inspection_hashes.has(str(candidate.get("inspection_id", ""))):
		return apply_inspection(candidate)
	var choice := {inspection_id = candidate.get("inspection_id", ""), recipe_book_sha256 = _recipe_hash,
		component_id = component_id, option_id = option_id, labor_mode = labor_mode,
		costing_basis = costing_basis, provenance = selection.provenance.duplicate(true)}
	if _repair_choices.size() >= MAX_INSPECTIONS \
		or JSON.stringify(_repair_choices + [choice]).to_utf8_buffer().size() > Inspection.MAX_BYTES:
		return {ok = false, errors = ["Repair choice history limit reached; existing assessment retained."]}
	_repair_choices.append(choice)
	var applied := apply_inspection(candidate)
	if not applied.get("ok", false) or applied.get("duplicate", false):
		_repair_choices.pop_back()
	return applied


## Read-only identity for an assessment producer. Not a player-controlled damage shortcut.
func inspection_context() -> Dictionary:
	return {identity = _identity.duplicate(true), catalog_hash = _catalog_hash, revision = _revision}


func checkpoint(tick: int, bindings: Dictionary) -> Dictionary:
	return Checkpoint.capture(self, tick, bindings)


func prepare_restore(value: Variant, tick: int, bindings: Dictionary) -> Dictionary:
	return Checkpoint.prepare(value, self, tick, bindings)


## Internal transaction commit: call only with a successful prepare_restore result.
## The UI owner commits this after its associated physics checkpoint succeeds.
func commit_restore(prepared: Dictionary) -> void:
	var data: Dictionary = prepared.data
	_identity = data.identity.duplicate(true)
	_assessment = data.assessment.duplicate(true)
	_last_tick = data.last_tick
	_assessment_tick = data.assessment_tick
	_revision = data.revision
	journal = data.journal.duplicate(true)
	_confirmed_facts = data.facts.duplicate(true)
	_fact_revisions = data.fact_revisions.duplicate(true)
	_inspections = data.inspections.duplicate(true)
	_reuse_blocked = data.blocked.duplicate(true)
	_repair_choices = data.repair_choices.duplicate(true)
	_seen = prepared.seen.duplicate(true)
	_seen_order = data.seen_order.duplicate(true)
	_proof_floor_tick = data.proof_floor_tick
	_tick_event_count = data.tick_event_count
	_open_contacts = data.open_contacts.duplicate(true)
	_summaries = data.summaries.duplicate(true)
	_decision_revisions = data.decision_revisions.duplicate(true)
	_journal_overflow = data.journal_overflow
	_journal_bytes = 0
	for event: Dictionary in journal:
		_journal_bytes += var_to_bytes(event).size()
	_evidence_overflow = data.evidence_overflow
	_prior_history_unknown = data.prior_history_unknown
	_terminal_qualified = data.terminal_qualified
	_unmapped_evidence = data.unmapped_evidence
	_unmapped_revision = data.unmapped_revision
	_full_inspection_revision = prepared.last_full_revision
	_inspection_hashes = prepared.receipt_hashes.duplicate(true)
	_confirmed_replacements = prepared.confirmed_replacements.duplicate(true)
	terminal = false
	report = {}
	_pending = _revision > 0
	_dirty = false
	_persisted_revision = -1
	_flush_attempt_revision = -1
	_flush_error = OK
	evaluate_pending()


## Frame-boundary only. An explicit inspection/scenario receipt updates disposition,
## not physical state; rendering/VFX never creates one. Duplicate submission is idempotent.
func apply_inspection(receipt: Dictionary) -> Dictionary:
	if not has_damage() or dossier.is_empty():
		return {ok = false, errors = ["No active incident with a compatible economic dossier."]}
	if JSON.stringify(receipt).to_utf8_buffer().size() > Inspection.MAX_BYTES:
		return {ok = false, errors = ["Inspection size limit exceeded."]}
	var id := str(receipt.get("inspection_id", ""))
	var receipt_hash := JSON.stringify(receipt, "", true, true).sha256_text()
	if _inspection_hashes.has(id):
		if _inspection_hashes[id] != receipt_hash:
			return {ok = false, errors = ["Inspection ID already refers to different evidence."]}
		return {ok = true, duplicate = true}
	if _inspections.size() >= MAX_INSPECTIONS:
		return {ok = false, errors = ["Inspection history limit reached; existing assessment retained."]}
	if JSON.stringify(_inspections + [receipt]).to_utf8_buffer().size() > Inspection.MAX_BYTES:
		return {ok = false, errors = ["Inspection history byte limit reached; existing assessment retained."]}
	var result := Inspection.validate(receipt, dossier, _assessment, _identity, _catalog_hash, _revision, _reuse_blocked, _confirmed_replacements)
	if not result.get("ok", false):
		return result
	var prop_id: String = dossier.get("propeller_component_id", "")
	if _confirmed_facts.has("propeller_strike") or _confirmed_facts.has("restored_propeller_strike"):
		if result.assessment.components.get(prop_id, {}).get("disposition") in ["reuse", "repair"]:
			return {ok = false, errors = ["Confirmed damaged propeller cannot receive repair or salvage credit."]}
	_assessment = result.assessment
	_reuse_blocked = result.blocked
	_inspection_hashes[id] = receipt_hash
	_inspections.append(receipt.duplicate(true))
	_queue_assessment(_last_tick)
	if receipt.full_inspection:
		_full_inspection_revision = _revision
	for component_id: String in receipt.components:
		_decision_revisions[component_id] = _revision
		if receipt.components[component_id].get("disposition") in ["replace", "unrecoverable"]:
			_confirmed_replacements[component_id] = true
	evaluate_pending()
	return {ok = true, duplicate = false, revision = _revision}


func observe(snapshot: Dictionary, bindings: Dictionary, crashed: bool, restored := false) -> Dictionary:
	var tick_value: Variant = snapshot.get("tick", -1)
	if not tick_value is int or tick_value < 0 or tick_value > 9007199254740991:
		return {ok = false, status = "invalid_tick"}
	var tick: int = tick_value
	var events: Variant = snapshot.get("events", [])
	if not events is Array or events.size() > MAX_EVENTS_PER_TICK \
		or JSON.stringify(events).to_utf8_buffer().size() > MAX_EVENT_BYTES:
		_record_refusal(tick, crashed, "Contact evidence exceeded its bound; coverage is incomplete.", true)
		return {ok = false, status = "overflow"}
	if not Events.validate_events(events, tick, bindings):
		_record_refusal(tick, crashed, "Contact evidence is invalid; inspection required.", false)
		return {ok = false, status = "invalid_events"}
	for event: Dictionary in events:
		for key: Variant in event:
			if event[key] is String and event[key].length() > (512 if key == "event_id" else 256):
				_record_refusal(tick, crashed, "Contact evidence is invalid; inspection required.", false)
				return {ok = false, status = "invalid_events"}
	# Check the entire batch before changing even the cursor. The ID alone is not
	# proof of an identical payload, and an evicted payload can never be reverified.
	var fresh: Array = []
	var fresh_digests := {}
	for event: Dictionary in events:
		var id: String = event.event_id
		var digest := _event_digest(event)
		if _seen.has(id):
			if _seen[id] != digest:
				_record_refusal(tick, crashed, "Contact evidence was rejected; inspection required.", false)
				return {ok = false, status = "conflicting_duplicate"}
		elif tick < _last_tick or tick <= _proof_floor_tick:
			_record_refusal(tick, crashed, "Contact evidence was rejected; inspection required.", false)
			return {ok = false, status = "stale_unverifiable"}
		else:
			fresh.append(event)
			fresh_digests[id] = digest
	if tick < _last_tick:
		return {ok = true, status = "duplicate"} if fresh.is_empty() and not events.is_empty() else {ok = false, status = "stale_unverifiable"}
	var count := _tick_event_count if tick == _last_tick else 0
	if count + fresh.size() > MAX_EVENTS_PER_TICK:
		_record_refusal(tick, crashed, "Contact evidence exceeded its bound; coverage is incomplete.", true)
		return {ok = false, status = "overflow"}
	fresh.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.event_id < b.event_id)
	if tick != _last_tick:
		_tick_event_count = 0
	_last_tick = tick
	_tick_event_count += fresh.size()
	var changed := false
	for event: Dictionary in fresh:
		_remember_event(event, fresh_digests[event.event_id])
		if event.lifecycle == "new":
			var event_bytes := var_to_bytes(event).size()
			if journal.size() < MAX_EVENTS and _journal_bytes + event_bytes <= MAX_JOURNAL_BYTES:
				journal.append(event.duplicate(true))
				_journal_bytes += event_bytes
				journal.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
					return a.tick < b.tick or (a.tick == b.tick and a.event_id < b.event_id))
			else:
				_journal_overflow = true
		changed = _observe_event(event, bindings) or changed
	if restored:
		_prior_history_unknown = true
		var active: Variant = snapshot.get("active_hull_ids", PackedStringArray())
		if typeof(active) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY] and not active.is_empty():
			changed = true
		var strike: Variant = snapshot.get("prop_strike", {})
		if strike is Dictionary and not strike.is_empty() and not _confirmed_facts.has("propeller_strike") \
			and not _confirmed_facts.has("restored_propeller_strike") \
			and strike.get("tick") is int and strike.tick <= tick \
			and not Events.strike_event(strike, strike.tick, "restored checkpoint", bindings).is_empty():
			_confirmed_facts.restored_propeller_strike = strike.duplicate(true)
			_fact_revisions.restored_propeller_strike = _revision + 1
			_mark_propeller()
			changed = true
	if crashed and not terminal:
		terminal = true
		_assessment.terminal = true
		_add_unresolved("Crash inspection pending; component survival is not yet established.")
		changed = true
	if _prior_history_unknown and (changed or _revision > 0):
		changed = _add_unresolved("Session restored or aircraft reloaded: earlier damage history is unavailable.") or changed
	if changed:
		_queue_assessment(tick)
	return {ok = true, status = "accepted" if not fresh.is_empty() else "duplicate"}


func _record_refusal(tick: int, crashed: bool, reason: String, overflow: bool) -> void:
	if tick < _last_tick:
		return
	var changed := false
	if overflow:
		_evidence_overflow = true
		changed = _add_unresolved(reason)
	if crashed and not terminal:
		terminal = true
		_assessment.terminal = true
		changed = _add_unresolved(reason) or changed
		_add_unresolved("Crash inspection pending; component survival is not yet established.")
		changed = true
	if changed:
		if tick > _last_tick:
			_tick_event_count = 0
		_last_tick = tick
		if _prior_history_unknown:
			_add_unresolved("Session restored or aircraft reloaded: earlier damage history is unavailable.")
		_queue_assessment(tick)


static func _event_digest(event: Dictionary) -> String:
	return JSON.stringify(event, "", true, true).sha256_text()


func _remember_event(event: Dictionary, digest: String) -> void:
	var id: String = event.event_id
	_seen[id] = digest
	# Ticks are monotone. Only amendments for the current tick need insertion
	# among peers, avoiding a full replay-window sort on every support sample.
	var position := _seen_order.size()
	while position > 0 and _seen_order[position - 1].tick == event.tick and _seen_order[position - 1].id > id:
		position -= 1
	_seen_order.insert(position, {id = id, tick = event.tick, digest = digest})
	if _seen_order.size() > MAX_EVENTS:
		var evicted: Dictionary = _seen_order.pop_front()
		_seen.erase(evicted.id)
		_proof_floor_tick = maxi(_proof_floor_tick, evicted.tick)


func _observe_event(event: Dictionary, bindings: Dictionary) -> bool:
	var source := str(event.get("probe_source", event.source))
	var probe := str(event.get("probe_id", event.contact_id))
	var episode := "%s/%s" % [source, probe]
	var changed := false
	if event.event_type in ["hull_contact", "support_contact"]:
		if event.lifecycle == "ended":
			_open_contacts.erase(episode)
			return false # Separation is not evidence of repair or survival.
		if not _open_contacts.has(episode) and _open_contacts.size() >= MAX_OPEN_CONTACTS:
			_evidence_overflow = true
			changed = _add_unresolved("Contact episode limit reached; coverage is incomplete.") or changed
		else:
			_open_contacts[episode] = event.tick
	if event.source == "propeller" and event.event_type == "strike":
		if not _confirmed_facts.has("propeller_strike"):
			_confirmed_facts.propeller_strike = event.duplicate(true)
		_fact_revisions.propeller_strike = _revision + 1
		var prop_id := str(dossier.get("propeller_component_id", ""))
		if not prop_id.is_empty():
			_record_summary(prop_id, event, "replace", "accepted powered propeller envelope strike", "", null)
		for id: String in dossier.get("propeller_inspection_ids", []):
			if id != prop_id:
				_record_summary(id, event, "inspect", "propeller strike requires related inspection", "", null)
		_mark_propeller()
		return true
	var resolved := DamageAssessment.resolve(_damage_profile, event) if not _damage_profile.is_empty() else {matched = false}
	if not resolved.get("matched", false):
		_unmapped_evidence = true
	if resolved.get("matched", false) and event.response == "terminal" \
		and not (event.source == "lake" and event.get("material") == "water"):
		_terminal_qualified = true
	var targets: Array = resolved.get("components", []) if resolved.get("matched", false) else _contact_components(event, bindings)
	var recommendation: String = resolved.get("recommendation", "inspect")
	var relevant := false
	var recorded_targets := []
	for id: String in targets:
		relevant = _record_summary(id, event, recommendation, str(resolved.get("reason", "accepted contact requires inspection")),
			str(resolved.get("channel", "")), resolved.get("value")) or relevant
		if _summaries.has(id):
			recorded_targets.append(id)
	if not resolved.get("matched", false) and (relevant or _unmapped_revision <= _full_inspection_revision \
			or event.lifecycle == "new" or event.event_type == "impact"):
		_unmapped_revision = _revision + 1
		changed = true
	if recommendation != "clear" and relevant:
		changed = _mark_contact_inspection(recorded_targets) or changed
		changed = true
	if not resolved.get("matched", false) or recommendation == "inspect":
		changed = _add_unresolved("Impact or surface contact requires structural inspection.") or changed
	if not resolved.get("matched", false) and targets.is_empty():
		changed = _add_unresolved("Contact has no unambiguous economic component binding.") or changed
	if not _profile_error.is_empty():
		changed = _add_unresolved("Compatible local game assessment is unavailable.") or changed
	if event.source == "lake" and event.get("material") == "water":
		if not _confirmed_facts.has("water_exposure"):
			_confirmed_facts.water_exposure = event.duplicate(true)
			changed = true
		_fact_revisions.water_exposure = _revision + 1
		changed = true
		changed = _add_unresolved("Water exposure requires inspection of electronics and powertrain.") or changed
	return changed


## Maxima are accepted endpoint values, not incoming speed or measured strength.
## An episode's peak never decreases when a contact ends or a milder sample arrives.
func _record_summary(id: String, event: Dictionary, recommendation: String, reason: String,
		channel: String, value: Variant) -> bool:
	if not _summaries.has(id) and _summaries.size() >= DamageAssessment.MAX_COMPONENTS:
		_evidence_overflow = true
		_add_unresolved("Component summary limit reached; coverage is incomplete.")
		return true
	var summary: Dictionary = _summaries.get(id, {first_tick = event.tick, latest_tick = event.tick,
		evidence_revision = 0, recommendation = "clear", reason = "", event_id = "", source = "", peaks = {}})
	var old_rank := _recommendation_rank(str(summary.recommendation))
	var rank := _recommendation_rank(recommendation)
	var increased := false
	var measure: Dictionary = event.get("measure", {})
	for key: String in ["depth_m", "normal_speed_mps", "slide_speed_mps", "compression_m"]:
		var sample: Variant = measure.get(key)
		if typeof(sample) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(sample)) and float(sample) >= 0.0 \
			and (not summary.peaks.has(key) or float(sample) > float(summary.peaks[key])):
			summary.peaks[key] = float(sample)
			increased = true
	if not channel.is_empty() and value != null and (not summary.peaks.has(channel) or float(value) > float(summary.peaks[channel])):
		summary.peaks[channel] = float(value)
		increased = true
	var relevant: bool = rank > 0 and (event.lifecycle == "new" or event.event_type == "impact" or increased or rank > old_rank)
	var previous_latest_tick: int = summary.latest_tick
	summary.latest_tick = event.tick
	if rank > old_rank or (rank == old_rank and relevant and (event.tick > previous_latest_tick \
		or (event.tick == previous_latest_tick and (summary.event_id.is_empty() or event.event_id < summary.event_id)))):
		summary.recommendation = recommendation
		summary.reason = reason
		summary.event_id = event.event_id
		summary.source = str(event.get("probe_source", event.source))
	if relevant:
		summary.evidence_revision = _revision + 1
	_summaries[id] = summary
	return relevant


static func _recommendation_rank(value: String) -> int:
	return ["clear", "inspect", "replace"].find(value)


func has_damage() -> bool:
	return _revision > 0


func _queue_assessment(tick: int) -> void:
	_assessment_tick = tick
	_revision += 1 # Evidence revision, independent of render/publish cadence.
	_pending = true


## Frame/reset/exit boundary only: no price calculation, UI signal or disk I/O in observe().
func evaluate_pending() -> void:
	if not _pending:
		return
	_pending = false
	_apply_game_assessment()
	_recalculate()


func _apply_game_assessment() -> void:
	if _damage_profile.is_empty():
		return
	var quantities := {}
	for part: Dictionary in dossier.get("components", []):
		quantities[part.id] = part.quantity
	var grouped_pending := false
	for id: String in _summaries:
		var summary: Dictionary = _summaries[id]
		if summary.recommendation != "replace":
			continue
		# A grouped row with several units does not prove which or how many failed.
		if int(quantities.get(id, 0)) != 1:
			if summary.evidence_revision > int(_decision_revisions.get(id, 0)) \
					or _assessment.components.get(id, {}).get("disposition") in ["inspect", "unknown"]:
				grouped_pending = true
			continue
		if summary.evidence_revision <= int(_decision_revisions.get(id, 0)):
			continue
		if _assessment.components.get(id, {}).get("disposition") != "replace":
			var replacement := {disposition = "replace", quantity = 1}
			if _assessment.components.get(id, {}).has("inspection_minor"):
				replacement.inspection_minor = _assessment.components[id].inspection_minor
			_assessment.components[id] = replacement
		_decision_revisions[id] = summary.evidence_revision
	if grouped_pending:
		_add_unresolved("A grouped component needs a quantity-specific inspection.")
	else:
		_assessment.unresolved.erase("A grouped component needs a quantity-specific inspection.")
	var resolved: bool = _unmapped_revision <= _full_inspection_revision and not _assessment.components.is_empty()
	for id: String in _assessment.components:
		if _assessment.components[id].get("disposition") in ["inspect", "unknown"]:
			resolved = false
	if resolved:
		_assessment.unresolved.erase("Impact or surface contact requires structural inspection.")
	if terminal and _terminal_qualified and resolved:
		for reason: String in _assessment.unresolved:
			if reason != "Crash inspection pending; component survival is not yet established.":
				resolved = false
		if resolved:
			_assessment.unresolved.erase("Crash inspection pending; component survival is not yet established.")


func _mark_propeller() -> void:
	var id := str(dossier.get("propeller_component_id", ""))
	if id.is_empty():
		_add_unresolved("A propeller strike was recorded; no compatible replacement price is available.")
		return
	var replacement := {disposition = "replace", quantity = 1}
	if _assessment.components.get(id, {}).has("inspection_minor"):
		replacement.inspection_minor = _assessment.components[id].inspection_minor
	_assessment.components[id] = replacement
	var associated: Array = dossier.get("propeller_inspection_ids", []).duplicate()
	associated.erase(id)
	_mark_contact_inspection(associated)
	_add_unresolved("Propeller strike: inspect the powertrain, shaft and mount before return to service.")


## CR-39d: the dossier's authored contact → economic-component binding. Hull/gear events carry
## the probe in contact_id; scenery/lake events carry the obstacle there and the probe in probe_id.
func _contact_components(event: Dictionary, contract: Dictionary = {}) -> Array:
	var bindings: Variant = dossier.get("contact_components", {})
	if typeof(bindings) != TYPE_DICTIONARY or bindings.is_empty():
		return []
	var result: Array = []
	var source := str(event.get("probe_source", "hull" if event.get("source") == "scenery" else event.get("source", "")))
	var probe_id := str(event.get("probe_id", event.get("contact_id", "")))
	var keys := ["%s/%s" % [source, probe_id]]
	# A v1 naked binding is safe only if the current physical contract proves it
	# belongs to one source namespace. An environment ID is never an aircraft part.
	if contract.is_empty() or _unique_probe(contract, source, probe_id):
		keys.append(probe_id)
	for key: String in keys:
		var mapped: Variant = bindings.get(key)
		if key.is_empty() or typeof(mapped) != TYPE_ARRAY:
			continue
		for component_id: Variant in mapped:
			if typeof(component_id) == TYPE_STRING and not result.has(component_id):
				result.append(component_id)
	return result


static func _unique_probe(contract: Dictionary, source: String, probe_id: String) -> bool:
	var matches := 0
	var correct := false
	for entry: Array in [["hull", "hull_probes"], ["gear", "support_points"]]:
		for item: Variant in contract.get(entry[1], []):
			if item is Dictionary and item.get("id") == probe_id:
				matches += 1
				correct = correct or source == entry[0]
	var rotor: Variant = contract.get("rotor_disc", {})
	if rotor is Dictionary and not rotor.is_empty() and contract.get("rotor_id", "propeller/single") == probe_id:
		matches += 1
		correct = correct or source == "propeller"
	return correct and matches == 1


## New relevant evidence reopens reuse or repair, but never downgrades replacement.
func _mark_contact_inspection(component_ids: Array) -> bool:
	var changed := false
	for component_id: String in component_ids:
		var prior: String = _assessment.components.get(component_id, {}).get("disposition", "")
		if prior in ["", "reuse", "repair"]:
			var reopened := {disposition = "inspect"}
			if _assessment.components.get(component_id, {}).has("inspection_minor"):
				reopened.inspection_minor = _assessment.components[component_id].inspection_minor
			_assessment.components[component_id] = reopened
			changed = true
	return changed


func _add_unresolved(reason: String) -> bool:
	if _assessment.unresolved.has(reason):
		return false
	_assessment.unresolved.append(reason)
	return true


## Frame-boundary comparison only. Authored alternatives never apply purchases or change this ledger.
func compare_replacements(package_candidates: Array = []) -> Dictionary:
	return ReplacementQuote.quote(dossier, _assessment, package_candidates)


func _recalculate() -> void:
	if dossier.is_empty():
		report = {ok = false, currency = "USD", known_subtotal_minor = 0, total_minor = null,
			low_minor = null, high_minor = null, complete = false, outcome = "unavailable",
			lines = [], salvage_minor = 0, replacement_minor = null, price_date = "",
			valuation_kind = "unavailable", unresolved = _assessment.unresolved.duplicate(),
			errors = _catalog_errors.duplicate()}
		var stale := false
		for error: Variant in _catalog_errors:
			stale = stale or str(error).contains("stale")
		# CR-39g: name the cause the player can act on instead of a generic unavailable.
		report.unresolved.append("Cost data is out of date for this aircraft version; no prices were applied." if stale
			else "Compatible aircraft cost dossier is unavailable.")
	else:
		report = Calculator.calculate(dossier, _assessment)
	# CR-39f: quote from this calculation; lines gain display fields only after the quote.
	var comparison := ReplacementQuote.quote_calculated(dossier, _assessment, report)
	var component_lookup: Dictionary = {}
	for component: Dictionary in dossier.get("components", []):
		component_lookup[component.id] = component
	for line: Dictionary in report.get("lines", []):
		var component: Dictionary = component_lookup.get(line.get("id", ""), {})
		line["notes"] = str(component.get("notes", ""))
		var source: Dictionary = _offer_sources.get(str(line.get("offer_id", "")), {})
		for field: String in source:
			line[field] = source[field]
	report["assumptions"] = ["USD prices exclude tax, shipping and transmitter/field equipment."]
	if _binding == "physical_signature" and not dossier.is_empty():
		report.assumptions.append(BINDING_NOTE)
	elif _binding == "registered_variant" and not dossier.is_empty():
		report.assumptions.append(REGISTERED_VARIANT_NOTE)
	for receipt: Dictionary in _inspections:
		report.assumptions.append("%s [%s]: %s" % [receipt.inspection_id, receipt.basis, receipt.evidence])
	if not _damage_profile.is_empty():
		report.assumptions.append("Local damage outcomes are deterministic game assumptions, not measured component survival.")
		report.assumptions.append_array(_damage_profile.assumptions)
		report["game_assessment"] = {format = "openrc-game-assessment v1", basis = "scenario_assumption",
			profile_id = _damage_profile.profile_id, policy_version = _damage_profile.policy_version,
			profile_sha256 = _profile_hash, components = _summaries.duplicate(true)}
	report["contact_summary"] = _summaries.duplicate(true)
	report["journal_truncated"] = _journal_overflow
	report["contact_coverage_incomplete"] = _unmapped_revision > _full_inspection_revision or _evidence_overflow
	if _journal_overflow:
		report.assumptions.append("The diagnostic event journal is truncated; bounded component summaries retain supported contact evidence.")
	report["inspections"] = _inspections.duplicate(true)
	report["repair_choices"] = _repair_choices.duplicate(true)
	if comparison.get("status") in ["optimal", "unknown_cost", "unknown_eligibility", "search_limit", "infeasible", "cost_out_of_range"]:
		comparison.erase("candidate_catalog") # Freeze only the selected comparison, not every alternative.
		comparison["format"] = "openrc-replacement-comparison v3"
		comparison["catalog_hash"] = _catalog_hash
		report["replacement_comparison"] = comparison
	report["format"] = "openrc-accident-report v2"
	report["identity"] = _identity.duplicate(true)
	report["aircraft_name"] = _identity.aircraft_id
	report["incident_id"] = _identity.incident_id
	report["catalog_hash"] = _catalog_hash
	report["evidence"] = journal.duplicate(true)
	report["confirmed_facts"] = _confirmed_facts.duplicate(true)
	report["terminal"] = terminal
	report["tick"] = _assessment_tick
	report["revision"] = _revision
	_dirty = true
	assessment_changed.emit(report.duplicate(true), terminal)


## Called outside accepted-tick callbacks. Persistence is a single bounded latest-report snapshot.
func flush(force_retry := false) -> Error:
	evaluate_pending()
	if not _dirty or report.is_empty() or _persisted_revision == _revision:
		return OK
	if _flush_attempt_revision == _revision and not force_retry:
		return _flush_error as Error
	_flush_attempt_revision = _revision
	_flush_error = _write_archive()
	return _flush_error as Error


func _write_archive() -> Error:
	var encoded := JSON.stringify(report, "", true, true) # CR-39f: compact; readers accept either form.
	if encoded.to_utf8_buffer().size() > ARCHIVE_MAX_BYTES:
		return ERR_OUT_OF_MEMORY
	var file := FileAccess.open(archive_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(encoded)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return write_error
	var rename_error := DirAccess.rename_absolute(archive_path + ".tmp", archive_path)
	if rename_error == OK:
		_dirty = false
		_persisted_revision = _revision
	return rename_error


func archive() -> Dictionary:
	evaluate_pending()
	if not report.is_empty():
		flush(true) # Explicit reset/exit gets one retry; the per-frame path never spins on a failed disk.
		last_report = report.duplicate(true)
	return last_report.duplicate(true)


func load_archive() -> Dictionary:
	if not FileAccess.file_exists(archive_path):
		return {}
	var file := FileAccess.open(archive_path, FileAccess.READ)
	if file == null or file.get_length() > ARCHIVE_MAX_BYTES:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(value) != TYPE_DICTIONARY or value.get("format") not in ["openrc-accident-report v1", "openrc-accident-report v2"]:
		return {}
	# Disk history is presentation-only; it never enters a new flight's ledger or credits a wallet.
	if typeof(value.get("identity")) != TYPE_DICTIONARY or typeof(value.get("lines")) != TYPE_ARRAY \
		or typeof(value.get("unresolved")) != TYPE_ARRAY or typeof(value.get("complete")) != TYPE_BOOL:
		return {}
	for line: Variant in value.lines:
		if typeof(line) != TYPE_DICTIONARY:
			return {}
	for reason: Variant in value.unresolved:
		if typeof(reason) != TYPE_STRING:
			return {}
	if value.has("replacement_comparison") and not _valid_comparison_archive(value.replacement_comparison, value.get("catalog_hash")):
		return {}
	for field: String in ["inspections", "repair_choices"]:
		if not value.has(field):
			continue # Older view-only archives predate explicit inspection receipts.
		if typeof(value[field]) != TYPE_ARRAY or value[field].size() > MAX_INSPECTIONS:
			return {}
		for entry: Variant in value[field]:
			if typeof(entry) != TYPE_DICTIONARY or not Inspection._text(entry.get("inspection_id")):
				return {}
			if field == "inspections":
				if entry.get("format") != Inspection.FORMAT or typeof(entry.get("components")) != TYPE_DICTIONARY \
					or entry.get("basis") not in ["inspection", "scenario_assumption"] or not Inspection._text(entry.get("evidence")):
					return {}
			elif typeof(entry.get("provenance")) != TYPE_DICTIONARY \
				or not Inspection._text(entry.get("recipe_book_sha256")) \
				or entry.get("labor_mode") not in ["diy", "paid"] or entry.get("costing_basis") not in ["cash", "consumption"]:
				return {}
	for field: String in ["known_subtotal_minor", "salvage_minor", "total_minor", "low_minor", "high_minor", "replacement_minor"]:
		var amount: Variant = value.get(field)
		if amount != null and (typeof(amount) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(amount)) \
			or float(amount) < 0.0 or float(amount) != floor(float(amount)) or float(amount) > 9000000000000000.0):
			return {}
	if value.complete and value.get("total_minor") == null:
		return {}
	last_report = value.duplicate(true)
	return last_report.duplicate(true)


static func _valid_comparison_archive(value: Variant, catalog_hash: Variant) -> bool:
	if not value is Dictionary or value.get("format") not in ["openrc-replacement-comparison v1", "openrc-replacement-comparison v2", "openrc-replacement-comparison v3"] \
		or value.get("coverage_scope") != "replacements_only" or value.get("catalog_hash") != catalog_hash \
		or value.get("status") not in ["optimal", "unknown_cost", "unknown_eligibility", "search_limit", "infeasible", "cost_out_of_range"]:
		return false
	if value.get("format") != "openrc-replacement-comparison v3" and value.get("status") == "unknown_eligibility":
		return false
	if value.get("format") == "openrc-replacement-comparison v3" \
		and (not value.get("unknown_eligibility_alternative_found") is bool \
		or value.get("optimality_scope") != "declared_candidate_set"):
		return false
	for field: String in ["assessment_complete", "complete", "optimality_proven", "search_complete", "unknown_cost_alternative_found", "selected_provenance_truncated"]:
		if not value.get(field) is bool:
			return false
	var amount: Variant = value.get("total_cost_cents")
	if amount != null and (typeof(amount) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(amount)) \
		or float(amount) < 0.0 or float(amount) > 9000000000000000.0 or float(amount) != floor(float(amount))):
		return false
	if value.optimality_proven != (value.status == "optimal") \
		or (value.optimality_proven and (amount == null or not value.search_complete)) \
		or value.complete != (value.assessment_complete and value.optimality_proven):
		return false
	for field: String in ["required_unit_ids", "selected_candidate_ids"]:
		if not value.get(field) is Array or value[field].size() > ReplacementQuote.MAX_REQUIRED_UNITS:
			return false
		var unique := {}
		var max_length: int = ReplacementQuote.MAX_COVERAGE_ID_LENGTH if field == "required_unit_ids" else ReplacementQuote.MAX_ID_LENGTH
		for id: Variant in value[field]:
			if not id is String or id.is_empty() or id.length() > max_length or unique.has(id):
				return false
			unique[id] = true
	if not value.get("selected_provenance") is Array or value.selected_provenance.size() != value.selected_candidate_ids.size():
		return false
	var provenance_ids := {}
	for source: Variant in value.selected_provenance:
		if not source is Dictionary or source.size() != 2 or not source.get("provenance") is String \
			or source.provenance.is_empty() or source.provenance.length() > ReplacementQuote.MAX_PROVENANCE_LENGTH \
			or source.get("candidate_id") not in value.selected_candidate_ids or provenance_ids.has(source.get("candidate_id")):
			return false
		provenance_ids[source.candidate_id] = true
	if value.get("format") == "openrc-replacement-comparison v2":
		return _valid_selection_archive(value)
	if value.get("format") == "openrc-replacement-comparison v3":
		return _valid_selection_archive_v3(value)
	return true


static func _valid_selection_archive_v3(value: Dictionary) -> bool:
	var selected: Variant = value.get("selected_lines")
	var coverage: Variant = value.get("selected_coverage")
	if not selected is Array or not coverage is Array or selected.size() != value.selected_candidate_ids.size() \
		or coverage.size() != selected.size() or value.required_unit_ids.is_empty():
		return false
	if (value.status == "search_limit") == bool(value.search_complete):
		return false
	if value.status not in ["unknown_cost", "search_limit"] and value.unknown_cost_alternative_found:
		return false
	if value.status == "unknown_cost" and not value.unknown_cost_alternative_found:
		return false
	if value.status == "unknown_eligibility" and not value.unknown_eligibility_alternative_found:
		return false
	if value.status == "optimal" and value.unknown_eligibility_alternative_found:
		return false
	if value.status in ["infeasible", "cost_out_of_range"] and value.total_cost_cents != null:
		return false
	if selected.is_empty():
		return value.total_cost_cents == null and value.status != "optimal"
	if value.total_cost_cents == null:
		return false
	var lines := {}
	var total := 0
	for row: Variant in selected:
		if not row is Dictionary or row.size() != 3 or row.get("candidate_id") not in value.selected_candidate_ids \
			or lines.has(row.get("candidate_id")) or not row.get("coverage_ids") is Array \
			or row.coverage_ids.is_empty() or row.coverage_ids.size() > ReplacementQuote.MAX_REQUIRED_UNITS:
			return false
		var amount: Variant = row.get("cost_cents")
		if typeof(amount) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(amount)) or float(amount) < 0 \
			or float(amount) != floor(float(amount)) or float(amount) > 9000000000000000.0 \
			or int(amount) > 9000000000000000 - total:
			return false
		total += int(amount)
		lines[row.candidate_id] = row
	if total != int(value.total_cost_cents):
		return false
	var coverage_by_id := {}
	for row: Variant in coverage:
		if not row is Dictionary or row.size() != 4 or row.get("candidate_id") not in lines \
			or coverage_by_id.has(row.get("candidate_id")):
			return false
		coverage_by_id[row.candidate_id] = row
	var ids: Array = value.selected_candidate_ids.duplicate()
	ids.sort()
	var assigned := {}
	for id: String in ids:
		if not coverage_by_id.has(id):
			return false
		var row: Dictionary = coverage_by_id[id]
		var supplied := {}
		for field: String in ["allocated_ids", "overlap_ids", "surplus_ids"]:
			if not row.get(field) is Array or row[field].size() > ReplacementQuote.MAX_REQUIRED_UNITS:
				return false
			for unit: Variant in row[field]:
				if not unit is String or unit.is_empty() or unit.length() > ReplacementQuote.MAX_COVERAGE_ID_LENGTH or supplied.has(unit):
					return false
				supplied[unit] = true
				if field == "surplus_ids":
					if unit in value.required_unit_ids:
						return false
				elif unit not in value.required_unit_ids or (field == "allocated_ids" and assigned.has(unit)) \
					or (field == "overlap_ids" and not assigned.has(unit)):
					return false
				elif field == "allocated_ids":
					assigned[unit] = true
		var line_ids := {}
		for unit: Variant in lines[id].coverage_ids:
			if not unit is String or unit not in value.required_unit_ids or line_ids.has(unit):
				return false
			line_ids[unit] = true
		var required_supplied := {}
		for unit: Variant in row.allocated_ids + row.overlap_ids:
			required_supplied[unit] = true
		if line_ids != required_supplied:
			return false
	return assigned.size() == value.required_unit_ids.size()


## Checks stored arithmetic and exact unit coverage; this is not file authentication
## or an independent proof of optimizer optimality / physical package compatibility.
static func _valid_selection_archive(value: Dictionary) -> bool:
	var selected: Variant = value.get("selected_lines")
	if not selected is Array or selected.size() != value.selected_candidate_ids.size() or value.required_unit_ids.is_empty():
		return false
	if (value.status == "search_limit") == bool(value.search_complete):
		return false
	if value.status not in ["unknown_cost", "search_limit"] and value.unknown_cost_alternative_found:
		return false
	if value.status == "unknown_cost" and not value.unknown_cost_alternative_found:
		return false
	if value.status in ["infeasible", "cost_out_of_range"] and value.total_cost_cents != null:
		return false
	if selected.is_empty():
		return value.total_cost_cents == null and value.status != "optimal"
	if value.total_cost_cents == null:
		return false
	var ids := {}
	var covered := {}
	var total: int = 0
	for row: Variant in selected:
		if not row is Dictionary or row.size() != 3 or row.get("candidate_id") not in value.selected_candidate_ids \
			or ids.has(row.get("candidate_id")) or not row.get("coverage_ids") is Array \
			or row.coverage_ids.is_empty() or row.coverage_ids.size() > ReplacementQuote.MAX_REQUIRED_UNITS:
			return false
		ids[row.candidate_id] = true
		var cost: Variant = row.get("cost_cents")
		if typeof(cost) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(cost)) \
			or float(cost) < 0.0 or float(cost) > 9000000000000000.0 or float(cost) != floor(float(cost)):
			return false
		if int(cost) > 9000000000000000 - total:
			return false
		total += int(cost)
		for unit: Variant in row.coverage_ids:
			if not unit is String or unit not in value.required_unit_ids or covered.has(unit):
				return false
			covered[unit] = true
	return covered.size() == value.required_unit_ids.size() and total == int(value.total_cost_cents)
