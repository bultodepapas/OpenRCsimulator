extends RefCounted
## CR-30: read-only, bounded interpretation of accepted contact events. No solver writes.

signal assessment_changed(report: Dictionary, terminal: bool)

const Catalog = preload("res://economy/catalog.gd")
const Calculator = preload("res://economy/calculator.gd")
const Inspection = preload("res://economy/inspection.gd")
const RepairPlanner = preload("res://economy/repair_planner.gd")
const ReplacementQuote = preload("res://economy/replacement_quote.gd")
const Checkpoint = preload("res://economy/checkpoint.gd")
const RECIPE_PATH := "res://data/economy/repair-recipes.json"
const Events = preload("res://sim/aircraft_contact_events.gd")
const MAX_EVENTS := 128
const ARCHIVE_PATH := "user://last_accident.json"
const ARCHIVE_MAX_BYTES := 262144
const MAX_INSPECTIONS := 16

var dossier: Dictionary = {}
var report: Dictionary = {}
var last_report: Dictionary = {}
var journal: Array = []
var archive_path := ARCHIVE_PATH
var terminal := false
var _assessment: Dictionary = {}
var _seen: Dictionary = {}
var _last_tick := -1
var _assessment_tick := -1
var _pending := false
var _confirmed_facts: Dictionary = {}
var _catalog_hash := ""
var _identity: Dictionary = {}
var _catalog_errors: Array = []
var _offer_sources: Dictionary = {}
var _dirty := false
var _revision := 0
var _persisted_revision := -1
var _flush_attempt_revision := -1
var _flush_error := OK
var _inspections: Array = []
var _inspection_hashes: Dictionary = {}
var _reuse_blocked: Dictionary = {}
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
	_catalog_hash = str(loaded.get("catalog_hash", ""))
	_offer_sources = loaded.get("offer_sources", {}).duplicate(true)
	_identity = {aircraft_id = aircraft_id, source_sha256 = dossier.get("source_sha256", source_hash),
		incident_id = "%s-%d" % [Time.get_datetime_string_from_system(true), Time.get_ticks_usec()]}
	report = {}
	journal = []
	_assessment = {components = {}, terminal = false, total_loss = false, unresolved = []}
	_seen = {}
	_last_tick = -1
	_assessment_tick = -1
	_pending = false
	_confirmed_facts = {}
	terminal = false
	_dirty = false
	_revision = 0
	_persisted_revision = -1
	_flush_attempt_revision = -1
	_flush_error = OK
	_inspections = []
	_inspection_hashes = {}
	_reuse_blocked = {}
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
	_inspections = data.inspections.duplicate(true)
	_reuse_blocked = data.blocked.duplicate(true)
	_repair_choices = data.repair_choices.duplicate(true)
	_seen = prepared.seen.duplicate(true)
	_inspection_hashes = prepared.receipt_hashes.duplicate(true)
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
	var result := Inspection.validate(receipt, dossier, _assessment, _identity, _catalog_hash, _revision, _reuse_blocked)
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
	evaluate_pending()
	return {ok = true, duplicate = false, revision = _revision}


func observe(snapshot: Dictionary, bindings: Dictionary, crashed: bool, restored := false) -> void:
	var tick := int(snapshot.get("tick", -1))
	if tick < 0 or tick < _last_tick:
		return # A reset must establish a fresh ledger before the physics clock goes backwards.
	_last_tick = tick
	var events: Variant = snapshot.get("events", [])
	if not Events.validate_events(events, tick, bindings):
		var invalid_changed := _add_unresolved("Contact evidence is invalid; inspection required.")
		if crashed and not terminal:
			terminal = true
			_assessment.terminal = true
			invalid_changed = true
		if invalid_changed:
			_queue_assessment(tick)
		return
	var changed := false
	for event: Dictionary in events:
		if event.get("lifecycle") != "new":
			continue # Sustained and ended contacts cannot produce repeated purchases.
		var key := str(event.event_id) + ":" + str(event.response)
		if _seen.has(key):
			continue
		if journal.size() < MAX_EVENTS:
			_seen[key] = true
			journal.append(event.duplicate(true))
			changed = true
		else:
			changed = _add_unresolved("Contact journal limit reached; inspection required.") or changed
		# Confirmed facts outlive the bounded diagnostic history. Never grow a second
		# unbounded event-ID set or discard a later strike because earlier contacts filled it.
		if event.source == "propeller" and event.event_type == "strike":
			if not _confirmed_facts.has("propeller_strike"):
				_confirmed_facts.propeller_strike = event.duplicate(true)
				_mark_propeller()
				changed = true
		else:
			var mapped := _contact_components(event)
			if mapped.is_empty():
				changed = _add_unresolved("Impact or surface contact requires structural inspection.") or changed
			else:
				changed = _mark_contact_inspection(mapped) or changed
		if event.source == "lake" and event.get("material") == "water":
			if not _confirmed_facts.has("water_exposure"):
				_confirmed_facts.water_exposure = event.duplicate(true)
				changed = true
			changed = _add_unresolved("Water exposure requires inspection of electronics and powertrain.") or changed
	var active_hull_ids: Variant = snapshot.get("active_hull_ids", PackedStringArray())
	var restored_contact: bool = typeof(active_hull_ids) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY] and not active_hull_ids.is_empty()
	if restored and (restored_contact or not snapshot.get("prop_strike", {}).is_empty() or not journal.is_empty()):
		changed = _add_unresolved("Session restored or aircraft reloaded: earlier damage history is unavailable.") or changed
		if not snapshot.get("prop_strike", {}).is_empty() and not _confirmed_facts.has("propeller_strike") \
			and not _confirmed_facts.has("restored_propeller_strike"):
			_confirmed_facts.restored_propeller_strike = snapshot.prop_strike.duplicate(true)
			_mark_propeller()
			changed = true
	if crashed and not terminal:
		terminal = true
		_assessment.terminal = true
		_add_unresolved("Crash inspection pending; component survival is not yet established.")
		changed = true
	if changed:
		_queue_assessment(tick)


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
	_recalculate()


func _mark_propeller() -> void:
	var id := str(dossier.get("propeller_component_id", ""))
	if id.is_empty():
		_add_unresolved("A propeller strike was recorded; no compatible replacement price is available.")
		return
	_assessment.components[id] = {disposition = "replace", quantity = 1}
	for inspection_id: String in dossier.get("propeller_inspection_ids", []):
		_assessment.components[inspection_id] = {disposition = "inspect"}
	_add_unresolved("Propeller strike: inspect the powertrain, shaft and mount before return to service.")


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
		report.unresolved.append("Compatible aircraft cost dossier is unavailable.")
	else:
		report = Calculator.calculate(dossier, _assessment)
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
	for receipt: Dictionary in _inspections:
		report.assumptions.append("%s [%s]: %s" % [receipt.inspection_id, receipt.basis, receipt.evidence])
	report["inspections"] = _inspections.duplicate(true)
	report["repair_choices"] = _repair_choices.duplicate(true)
	var comparison := compare_replacements()
	if comparison.get("status") in ["optimal", "unknown_cost", "search_limit", "infeasible", "cost_out_of_range"]:
		comparison.erase("candidate_catalog") # Freeze only the selected comparison, not every alternative.
		comparison["format"] = "openrc-replacement-comparison v2"
		comparison["catalog_hash"] = _catalog_hash
		report["replacement_comparison"] = comparison
	report["format"] = "openrc-accident-report v1"
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
	var encoded := JSON.stringify(report, "\t", true, true)
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
	if typeof(value) != TYPE_DICTIONARY or value.get("format") != "openrc-accident-report v1":
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
	if not value is Dictionary or value.get("format") not in ["openrc-replacement-comparison v1", "openrc-replacement-comparison v2"] \
		or value.get("coverage_scope") != "replacements_only" or value.get("catalog_hash") != catalog_hash \
		or value.get("status") not in ["optimal", "unknown_cost", "search_limit", "infeasible", "cost_out_of_range"]:
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
	return true


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
