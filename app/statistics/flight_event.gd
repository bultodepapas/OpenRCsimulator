## GP-14: detached semantic evidence. This contract classifies no forces or damage.
extends RefCounted

const FORMAT := "openrc-ground-flight-event"
const VERSION := 1
const RULES := "ground-flight-events-v1"
const TYPES := ["TAKEOFF", "TOUCHDOWN", "BOUNCE", "LANDING_SUCCESS", "TOUCH_AND_GO",
	"GEAR_UP_CONTACT", "CRASH", "COMPONENT_DAMAGE", "GEAR_FAILURE", "GROUND_STOP"]
const MEASUREMENTS := ["sample_interval_s", "unsupported_seconds", "first_contact_tick",
	"first_loss_support_tick", "confirmation_tick"]
const KEYS := ["format", "version", "rules_version", "law_identity", "activity_id", "generation_id",
	"flight_id", "contact_episode_id", "accident_id", "event_id", "type", "accepted_tick", "sequence",
	"aircraft_id", "configuration_hash", "field_hash", "contact_ids", "component_ids", "material_id",
	"evidence_coverage", "measurements", "severity_status", "terminal", "continuation", "cause", "revision"]


## Endpoint observations have no substep locator, pre-impact speed or structural
## severity. Unknown fields stay explicit; neither command intent nor damage is inferred.
static func make(profile: Dictionary, kind: String, tick: int, sequence: int, flight_id: String,
		episode_id: String, accident_id: String, measurements: Dictionary = {}, terminal := false,
		revision := 0) -> Dictionary:
	var generation := str(profile.get("generation_id", "0"))
	var value := {format = FORMAT, version = VERSION, rules_version = RULES,
		law_identity = "accepted-endpoint-support-v1", activity_id = str(profile.get("activity_id", generation)),
		generation_id = generation, flight_id = flight_id, contact_episode_id = episode_id,
		accident_id = accident_id, event_id = "g%s:t%d:s%d:%s" % [generation, tick, sequence, kind],
		type = kind, accepted_tick = tick, sequence = sequence,
		aircraft_id = str(profile.get("aircraft_id", "")), configuration_hash = str(profile.get("configuration_hash", "")),
		field_hash = str(profile.get("field_hash", "")), contact_ids = [], component_ids = [], material_id = "",
		evidence_coverage = ["accepted_endpoint_support", "no_substep_timing", "damage_unobserved"],
		measurements = measurements.duplicate(true), severity_status = "unknown", terminal = terminal,
		continuation = "terminal" if terminal else "continues", revision = revision,
		cause = {classification = "unknown", evidence_ids = [], uncertainty = "unavailable"}}
	return value if valid(value) else {}


static func _valid_v1(value: Variant) -> bool:
	if not value is Dictionary or value.size() != KEYS.size() or not value.has_all(KEYS): return false
	if typeof(value.format) != TYPE_STRING or typeof(value.version) != TYPE_INT \
		or typeof(value.rules_version) != TYPE_STRING or typeof(value.type) != TYPE_STRING \
		or value.format != FORMAT or value.version != VERSION or value.rules_version != RULES or value.type not in TYPES: return false
	for key: String in ["law_identity", "activity_id", "generation_id", "event_id", "aircraft_id",
		"configuration_hash", "field_hash", "flight_id", "contact_episode_id", "accident_id", "material_id"]:
		if typeof(value[key]) != TYPE_STRING or value[key].length() > 256: return false
	for key: String in ["law_identity", "activity_id", "generation_id", "event_id"]:
		if value[key].is_empty(): return false
	for key: String in ["accepted_tick", "sequence", "revision"]:
		if not _integer(value[key]) or value[key] < 0: return false
	if typeof(value.terminal) != TYPE_BOOL or typeof(value.continuation) != TYPE_STRING \
		or typeof(value.severity_status) != TYPE_STRING or value.continuation != ("terminal" if value.terminal else "continues") \
		or value.severity_status != "unknown": return false
	for key: String in ["contact_ids", "component_ids", "evidence_coverage"]:
		if not _strings(value[key]): return false
	if not value.measurements is Dictionary: return false
	for key: Variant in value.measurements:
		if key not in MEASUREMENTS: return false
		var number: Variant = value.measurements[key]
		if typeof(number) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(number)) or number < 0: return false
		if str(key).ends_with("_tick") and not _integer(number): return false
	if not value.cause is Dictionary or value.cause.size() != 3 \
		or typeof(value.cause.get("classification")) != TYPE_STRING or typeof(value.cause.get("uncertainty")) != TYPE_STRING \
		or value.cause.get("classification") != "unknown" or value.cause.get("uncertainty") != "unavailable" \
		or not _strings(value.cause.get("evidence_ids")): return false
	return true


static func _integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) \
		and absf(float(value)) <= 9007199254740991.0 and floor(float(value)) == float(value)


static func _strings(value: Variant) -> bool:
	if not value is Array or value.size() > 64: return false
	var seen := {}
	for item: Variant in value:
		if typeof(item) != TYPE_STRING or item.is_empty() or item.length() > 192 or seen.has(item): return false
		seen[item] = true
	return true


## All signal listeners receive the same argument. Freeze every nested map/list
## so one listener cannot alter a later listener's evidence. A consumer needing
## a mutable presentation copy can call duplicate(true).
static func frozen_batch(events: Array) -> Array:
	var result: Array = events.duplicate(true)
	_freeze(result)
	return result


static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for item: Variant in value.values(): _freeze(item)
		value.make_read_only()
	elif value is Array:
		for item: Variant in value: _freeze(item)
		value.make_read_only()

## V2 describes only the qualified physical attached-failure observation. V1
## construction and validation remain unchanged for historical/endpoint events.
const DAMAGE_VERSION := 2
const DAMAGE_RULES := "ground-flight-events-v2"
const DAMAGE_SCHEMA := "openrc-aircraft-component-failure-observation"
const DAMAGE_LAW := "fixed-hub-weaker-compliance-attached-failure-v1"
const DAMAGE_MEASUREMENTS := ["normal_load_n", "normal_failure_force_n", "potential_before_j",
	"potential_after_j", "transition_loss_j", "confirmation_tick", "sample_interval_s"]
const DAMAGE_EVIDENCE := ["source_event_id", "source_generation_id", "damage_profile_identity", "response_identity",
	"qualification", "sampling", "criterion", "response_mode"]
const DAMAGE_COVERAGE := ["accepted_boundary_component_transition", "same_state_potential_loss",
	"experimental_unvalidated", "no_substep_timing", "strength_not_physically_calibrated"]


static func valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or typeof(value.get("version")) != TYPE_INT: return false
	return _valid_damage(value) if value.version == DAMAGE_VERSION else _valid_v1(value)


static func valid_damage_observation(value: Variant, tick: int, generation: Variant, identity: Variant, dt: float) -> bool:
	var keys := ["schema", "version", "tick", "generation_id", "identity", "available", "events", "reason"]
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size() or not value.has_all(keys) \
		or typeof(value.schema) != TYPE_STRING or value.schema != DAMAGE_SCHEMA \
		or typeof(value.version) != TYPE_INT or value.version != 1 or typeof(value.tick) != TYPE_INT \
		or value.tick != tick or tick < 0 or not _integer(tick) or not _id(generation, 128) or not _hash(identity) \
		or typeof(value.generation_id) != TYPE_STRING or value.generation_id != generation \
		or typeof(value.identity) != TYPE_STRING or value.identity != identity \
		or typeof(value.available) != TYPE_BOOL or not value.available \
		or typeof(value.reason) != TYPE_STRING or not value.reason.is_empty() \
		or typeof(value.events) != TYPE_ARRAY or value.events.size() > 16 or not is_finite(dt) or dt <= 0.0: return false
	var seen := {}
	var contacts := {}
	var previous := ""
	for record: Variant in value.events:
		if not valid_damage_record(record, tick, generation, identity, dt) or seen.has(record.component_id) \
			or (not previous.is_empty() and record.component_id <= previous): return false
		seen[record.component_id] = true
		previous = record.component_id
		for id: String in record.contact_ids:
			if contacts.has(id): return false
			contacts[id] = true
	return true


static func valid_damage_record(value: Variant, tick: int, generation: Variant, identity: Variant, dt: float) -> bool:
	var keys := ["component_id", "contact_ids", "law_identity", "accepted_tick", "physical_evidence", "measurements"]
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size() or not value.has_all(keys) \
		or not _id(value.component_id, 128) or not _strings(value.contact_ids) or value.contact_ids.is_empty() \
		or value.contact_ids.size() > 16 or typeof(value.law_identity) != TYPE_STRING or value.law_identity != DAMAGE_LAW \
		or typeof(value.accepted_tick) != TYPE_INT or value.accepted_tick != tick or tick < 1: return false
	for id: String in value.contact_ids:
		if not _id(id, 128): return false
	var evidence: Variant = value.physical_evidence
	if typeof(evidence) != TYPE_DICTIONARY or evidence.size() != DAMAGE_EVIDENCE.size() or not evidence.has_all(DAMAGE_EVIDENCE): return false
	for key: String in DAMAGE_EVIDENCE:
		if typeof(evidence[key]) != TYPE_STRING: return false
	if evidence.source_generation_id != generation or evidence.response_identity != identity \
		or not _id(generation, 128) or not _hash(identity) or not _hash(evidence.damage_profile_identity) \
		or evidence.source_event_id.length() != 68 or not evidence.source_event_id.begins_with("gd1:") \
		or not _hash(evidence.source_event_id.substr(4)) or evidence.qualification != "experimental_unvalidated" \
		or evidence.sampling != "accepted_boundary_only_not_interval_peak" or evidence.criterion != "declared_normal_capacity_exceeded" \
		or evidence.response_mode != "failed_attached": return false
	var source_hash := HashingContext.new()
	source_hash.start(HashingContext.HASH_SHA256)
	source_hash.update(var_to_bytes(["experimental-brittle-normal-capacity-attached-v1", generation, value.component_id, tick]))
	if evidence.source_event_id != "gd1:" + source_hash.finish().hex_encode(): return false
	var values: Variant = value.measurements
	if typeof(values) != TYPE_DICTIONARY or values.size() != DAMAGE_MEASUREMENTS.size() or not values.has_all(DAMAGE_MEASUREMENTS): return false
	for key: String in DAMAGE_MEASUREMENTS:
		if typeof(values[key]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(values[key])) or values[key] < 0.0: return false
	if not _integer(values.confirmation_tick) or values.confirmation_tick != tick or values.sample_interval_s != dt \
		or not is_finite(dt) or dt <= 0.0 or values.normal_failure_force_n <= 0.0 \
		or values.normal_load_n <= values.normal_failure_force_n or values.potential_after_j > values.potential_before_j: return false
	var scale: float = maxf(values.potential_before_j, maxf(values.potential_after_j, values.transition_loss_j))
	return absf(values.potential_before_j - values.potential_after_j - values.transition_loss_j) <= 16.0 * 2.220446049250313e-16 * maxf(scale, 1e-300)


static func make_damage(profile: Dictionary, kind: String, record: Dictionary, sequence: int,
		flight_id: String, episode_id: String, accident_id: String) -> Dictionary:
	if kind not in ["COMPONENT_DAMAGE", "GEAR_FAILURE"]: return {}
	if not _integer(record.get("accepted_tick")) or typeof(record.get("measurements")) != TYPE_DICTIONARY \
		or typeof(record.get("physical_evidence")) != TYPE_DICTIONARY \
		or typeof(record.measurements.get("sample_interval_s")) not in [TYPE_FLOAT, TYPE_INT]: return {}
	if not valid_damage_record(record, int(record.accepted_tick), record.physical_evidence.get("source_generation_id"),
		record.physical_evidence.get("response_identity"), float(record.measurements.sample_interval_s)): return {}
	var value := make(profile, kind, int(record.get("accepted_tick", -1)), sequence, flight_id, episode_id, accident_id)
	if value.is_empty(): return {}
	value.version = DAMAGE_VERSION
	value.rules_version = DAMAGE_RULES
	value.law_identity = DAMAGE_LAW
	value.contact_ids = record.get("contact_ids", []).duplicate()
	value.component_ids = [record.get("component_id", "")]
	value.evidence_coverage = DAMAGE_COVERAGE.duplicate()
	value.physical_evidence = record.get("physical_evidence", {}).duplicate(true)
	value.measurements = record.get("measurements", {}).duplicate(true)
	value.cause.evidence_ids = [value.physical_evidence.get("source_event_id", "")]
	return value if valid(value) else {}


static func _valid_damage(value: Dictionary) -> bool:
	if value.size() != KEYS.size() + 1 or not value.has_all(KEYS) or not value.has("physical_evidence") \
		or typeof(value.rules_version) != TYPE_STRING or value.rules_version != DAMAGE_RULES \
		or typeof(value.type) != TYPE_STRING or value.type not in ["COMPONENT_DAMAGE", "GEAR_FAILURE"] \
		or typeof(value.terminal) != TYPE_BOOL or value.terminal or not _integer(value.revision) or value.revision != 0 \
		or typeof(value.component_ids) != TYPE_ARRAY or value.component_ids.size() != 1 \
		or typeof(value.measurements) != TYPE_DICTIONARY or typeof(value.physical_evidence) != TYPE_DICTIONARY: return false
	if typeof(value.measurements.get("sample_interval_s")) not in [TYPE_FLOAT, TYPE_INT]: return false
	var evidence: Dictionary = value.physical_evidence
	var values: Dictionary = value.measurements
	var record := {component_id = value.component_ids[0], contact_ids = value.contact_ids, law_identity = value.law_identity,
		accepted_tick = value.accepted_tick, physical_evidence = evidence, measurements = values}
	if not _integer(value.accepted_tick) or not valid_damage_record(record, int(value.accepted_tick),
		evidence.get("source_generation_id"), evidence.get("response_identity"), float(values.get("sample_interval_s", NAN))): return false
	var legacy := value.duplicate(false)
	legacy.erase("physical_evidence")
	legacy.version = VERSION
	legacy.rules_version = RULES
	legacy.measurements = {sample_interval_s = values.sample_interval_s, confirmation_tick = values.confirmation_tick}
	if not _valid_v1(legacy) or value.evidence_coverage != DAMAGE_COVERAGE or not value.material_id.is_empty() \
		or value.cause.evidence_ids != [evidence.source_event_id]: return false
	if value.accident_id.is_empty() or value.event_id != "g%s:t%d:s%d:%s" % [value.generation_id, value.accepted_tick, value.sequence, value.type]: return false
	return true


static func _id(value: Variant, limit: int) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= limit \
		and value == value.strip_edges() and not value.contains("\n") and not value.contains("\r") and not value.contains("\t")


static func _hash(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 64: return false
	for letter: String in value:
		if letter not in "0123456789abcdef": return false
	return true
