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


static func valid(value: Variant) -> bool:
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
