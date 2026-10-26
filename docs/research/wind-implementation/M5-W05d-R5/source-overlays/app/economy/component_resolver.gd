extends RefCounted
class_name ComponentResolver

## Pure interval comparison only. It neither validates caller evidence nor infers damage.
const INPUT_FORMAT := "openrc-component-evidence v1"
const OUTPUT_FORMAT := "openrc-component-resolution v1"
const MAX_COMPONENTS := 64
const MAX_CAUSES := 128
const MAX_CHANNELS := 3
const MAX_TICK := 2147483647
const MAX_VALUE := 1000000000000.0
const MAX_ID_LENGTH := 80
const MAX_PROVENANCE_LENGTH := 1000
const MAX_QUALIFICATION_REF_LENGTH := 200
const COMPARISON_RELATIVE_TOLERANCE: float = 1.0e-12
const CHANNEL_UNITS := {
	"impact_allocated_j": "J",
	"abrasion_j": "J",
	"thermal_dose_k_s": "K*s",
}
const QUANTITY_CLASSES := [
	"accepted_observation", "measured", "isolated_estimate", "scenario_assumption", "independently_validated",
]
const CAPACITY_CLASSES := ["scenario_assumption", "independently_validated"]
const CANDIDATE_OUTCOMES := ["repair_candidate", "replace_candidate"]


## Input is a closed, caller-authored evidence bundle. Output is a candidate classification,
## never a physical disposition, cost, salvage credit, or verified qualification.
static func resolve(input: Dictionary) -> Dictionary:
	var validation := _validate_input(input)
	if not bool(validation.get("ok", false)):
		return _failure(str(validation.get("error", "invalid evidence bundle")))

	var components_by_id: Dictionary = {}
	var component_ids := PackedStringArray()
	for component_value: Variant in input.components:
		var component: Dictionary = component_value
		var component_id: String = str(component.component_id)
		components_by_id[component_id] = component
		component_ids.append(component_id)
	component_ids.sort()

	var resolved_components: Array[Dictionary] = []
	var any_qualification_claim := false
	for component_id: String in component_ids:
		var component: Dictionary = components_by_id[component_id]
		var causes_by_key: Dictionary = {}
		var sorted_cause_keys := PackedStringArray()
		for cause_value: Variant in component.causes:
			var cause: Dictionary = cause_value
			var cause_key: String = JSON.stringify([cause.cause_kind, cause.cause_id])
			causes_by_key[cause_key] = cause
			sorted_cause_keys.append(cause_key)
		sorted_cause_keys.sort()

		var channel_state: Dictionary = {}
		var unresolved_cause := false
		for cause_key: String in sorted_cause_keys:
			var cause: Dictionary = causes_by_key[cause_key]
			if cause.channels.is_empty():
				unresolved_cause = true
			var channels_by_name: Dictionary = {}
			var channel_names := PackedStringArray()
			for channel_value: Variant in cause.channels:
				var channel: Dictionary = channel_value
				var channel_name: String = str(channel.channel)
				channels_by_name[channel_name] = channel
				channel_names.append(channel_name)
			channel_names.sort()
			for channel_name: String in channel_names:
				var channel: Dictionary = channels_by_name[channel_name]
				if not channel_state.has(channel_name):
					channel_state[channel_name] = {
						"quantity_low": 0.0,
						"quantity_high": 0.0,
						"capacity_low": float(channel.capacity_low),
						"capacity_high": float(channel.capacity_high),
						"unit": str(channel.unit),
						"over_capacity_candidate": str(channel.over_capacity_candidate),
						"quantity_classes": PackedStringArray(),
						"capacity_classes": PackedStringArray(),
						"quantity_provenance": PackedStringArray(),
						"capacity_provenance": PackedStringArray(),
						"cause_ids": PackedStringArray(),
						"qualification_refs": PackedStringArray(),
				}
				var accumulated: Dictionary = channel_state[channel_name]
				if float(channel.capacity_low) != float(accumulated.capacity_low) \
						or float(channel.capacity_high) != float(accumulated.capacity_high) \
						or str(channel.over_capacity_candidate) != str(accumulated.over_capacity_candidate):
					return _failure("capacity interval and candidate action must match for each component/channel")
				var quantity_low: float = float(accumulated.quantity_low) + float(channel.quantity_low)
				var quantity_high: float = float(accumulated.quantity_high) + float(channel.quantity_high)
				if not is_finite(quantity_low) or not is_finite(quantity_high) \
						or quantity_low > MAX_VALUE or quantity_high > MAX_VALUE:
					return _failure("summed channel quantity exceeds finite bound")
				accumulated.quantity_low = quantity_low
				accumulated.quantity_high = quantity_high
				accumulated.quantity_classes.append(str(channel.quantity_class))
				accumulated.capacity_classes.append(str(channel.capacity_class))
				accumulated.quantity_provenance.append(str(channel.quantity_provenance))
				accumulated.capacity_provenance.append(str(channel.capacity_provenance))
				accumulated.cause_ids.append("%s:%s" % [str(cause.cause_kind), str(cause.cause_id)])
				if not str(channel.qualification_ref).is_empty():
					accumulated.qualification_refs.append(str(channel.qualification_ref))
				channel_state[channel_name] = accumulated

		var resolved_channels: Array[Dictionary] = []
		var channel_names := PackedStringArray()
		for channel_name_value: Variant in channel_state:
			channel_names.append(str(channel_name_value))
		channel_names.sort()
		var component_outcome := "below_declared_capacity"
		var component_evidence_classes := PackedStringArray()
		var component_qualification_claim := false
		for channel_name: String in channel_names:
			var totals: Dictionary = channel_state[channel_name]
			var outcome := "inspect"
			var comparison := "overlap"
			var quantity_low: float = float(totals.quantity_low)
			var quantity_high: float = float(totals.quantity_high)
			var capacity_low: float = float(totals.capacity_low)
			var capacity_high: float = float(totals.capacity_high)
			var comparison_tolerance: float = COMPARISON_RELATIVE_TOLERANCE * maxf(1.0, maxf(quantity_high, capacity_high))
			if capacity_low - quantity_high > comparison_tolerance:
				comparison = "below"
				outcome = "below_declared_capacity"
			elif quantity_low - capacity_high > comparison_tolerance:
				comparison = "exceeds"
				outcome = str(totals.over_capacity_candidate)
			var quantity_classes: PackedStringArray = totals.quantity_classes
			var capacity_classes: PackedStringArray = totals.capacity_classes
			var channel_qualification_claim: bool = quantity_classes.has("independently_validated") \
				or capacity_classes.has("independently_validated")
			component_qualification_claim = component_qualification_claim or channel_qualification_claim
			any_qualification_claim = any_qualification_claim or channel_qualification_claim
			var channel_evidence_class: String = _evidence_class(quantity_classes, capacity_classes)
			component_evidence_classes.append(channel_evidence_class)
			if _outcome_rank(outcome) > _outcome_rank(component_outcome):
				component_outcome = outcome
			if outcome == "inspect":
				unresolved_cause = true
			var cause_ids: PackedStringArray = totals.cause_ids
			cause_ids.sort()
			var quantity_provenance: PackedStringArray = totals.quantity_provenance
			quantity_provenance.sort()
			var capacity_provenance: PackedStringArray = totals.capacity_provenance
			capacity_provenance.sort()
			var qualification_refs: PackedStringArray = totals.qualification_refs
			qualification_refs.sort()
			resolved_channels.append({
				"channel": channel_name,
				"unit": str(totals.unit),
				"quantity_low": quantity_low,
				"quantity_high": quantity_high,
				"capacity_low": capacity_low,
				"capacity_high": capacity_high,
				"comparison_tolerance": comparison_tolerance,
				"comparison": comparison,
				"outcome": outcome,
				"over_capacity_candidate": str(totals.over_capacity_candidate),
				"evidence_class": channel_evidence_class,
				"qualification_claim_unverified": channel_qualification_claim,
				"qualification_verified": false,
				"quantity_classes": _sorted_unique(quantity_classes),
				"capacity_classes": _sorted_unique(capacity_classes),
				"quantity_provenance": _sorted_unique(quantity_provenance),
				"capacity_provenance": _sorted_unique(capacity_provenance),
				"cause_ids": _sorted_unique(cause_ids),
				"qualification_refs": _sorted_unique(qualification_refs),
			})
		if resolved_channels.is_empty() or unresolved_cause:
			if _outcome_rank(component_outcome) < _outcome_rank("inspect"):
				component_outcome = "inspect"
		var component_evidence_class := "unknown" if component_evidence_classes.is_empty() \
			else _combine_evidence_classes(component_evidence_classes)
		resolved_components.append({
			"component_id": component_id,
			"outcome": component_outcome,
			"inspection_required": true,
			"evidence_class": component_evidence_class,
			"qualification_claim_unverified": component_qualification_claim,
			"qualification_verified": false,
			"channels": resolved_channels,
		})

	return {
		"ok": true,
		"format": OUTPUT_FORMAT,
		"incident_id": str(input.incident_id),
		"aircraft_id": str(input.aircraft_id),
		"source_sha256": str(input.source_sha256),
		"components": resolved_components,
		"qualification_claim_unverified": any_qualification_claim,
		"qualification_verified": false,
		"production_billing_enabled": false,
		"provenance_is_caller_declared_not_verified": true,
	}


static func _validate_input(input: Dictionary) -> Dictionary:
	if not _exact_keys(input, ["format", "incident_id", "aircraft_id", "source_sha256", "components"]) \
			or input.get("format") != INPUT_FORMAT:
		return {"ok": false, "error": "input must match the closed openrc-component-evidence v1 schema"}
	if not _valid_text(input.get("incident_id"), MAX_ID_LENGTH) \
			or not _valid_text(input.get("aircraft_id"), MAX_ID_LENGTH):
		return {"ok": false, "error": "incident_id and aircraft_id must be nonempty bounded strings"}
	if not _is_sha256(input.get("source_sha256")):
		return {"ok": false, "error": "source_sha256 must be 64 lowercase hexadecimal characters"}
	var components_value: Variant = input.get("components")
	if typeof(components_value) != TYPE_ARRAY or components_value.is_empty() \
			or components_value.size() > MAX_COMPONENTS:
		return {"ok": false, "error": "components must contain 1..64 rows"}
	var component_ids: Dictionary = {}
	var cause_rows := 0
	for component_index: int in range(components_value.size()):
		var component_value: Variant = components_value[component_index]
		if typeof(component_value) != TYPE_DICTIONARY \
				or not _exact_keys(component_value, ["component_id", "causes"]):
			return {"ok": false, "error": "components[%d] has unknown fields or is not an object" % component_index}
		var component: Dictionary = component_value
		if not _valid_text(component.get("component_id"), MAX_ID_LENGTH) \
				or component_ids.has(component.component_id):
			return {"ok": false, "error": "component IDs must be unique nonempty bounded strings"}
		component_ids[component.component_id] = true
		if typeof(component.get("causes")) != TYPE_ARRAY:
			return {"ok": false, "error": "component causes must be an array"}
		cause_rows += component.causes.size()
		if cause_rows > MAX_CAUSES:
			return {"ok": false, "error": "cause/component row limit exceeded"}
		var seen_causes: Dictionary = {}
		for cause_index: int in range(component.causes.size()):
			var cause_value: Variant = component.causes[cause_index]
			if typeof(cause_value) != TYPE_DICTIONARY \
					or not _exact_keys(cause_value, ["cause_kind", "cause_id", "tick", "channels"]):
				return {"ok": false, "error": "component cause has unknown fields or is not an object"}
			var cause: Dictionary = cause_value
			if cause.cause_kind not in ["accepted_event", "authored_scenario"] \
					or not _valid_text(cause.get("cause_id"), MAX_ID_LENGTH):
				return {"ok": false, "error": "cause kind and identity are invalid"}
			if typeof(cause.get("tick")) != TYPE_INT or int(cause.tick) < 0 or int(cause.tick) > MAX_TICK:
				return {"ok": false, "error": "cause tick is outside finite accepted-tick bounds"}
			var cause_key: String = JSON.stringify([cause.cause_kind, cause.cause_id])
			if seen_causes.has(cause_key):
				return {"ok": false, "error": "duplicate cause/component row would double allocate evidence"}
			seen_causes[cause_key] = true
			if typeof(cause.get("channels")) != TYPE_ARRAY or cause.channels.size() > MAX_CHANNELS:
				return {"ok": false, "error": "cause channels must contain 0..3 rows"}
			var seen_channels: Dictionary = {}
			for channel_index: int in range(cause.channels.size()):
				var channel_value: Variant = cause.channels[channel_index]
				var channel_keys := ["channel", "unit", "quantity_low", "quantity_high", "quantity_class",
					"quantity_provenance", "capacity_low", "capacity_high", "capacity_class",
					"capacity_provenance", "over_capacity_candidate", "qualification_ref"]
				if typeof(channel_value) != TYPE_DICTIONARY or not _exact_keys(channel_value, channel_keys):
					return {"ok": false, "error": "channel row has unknown fields or is not an object"}
				var channel: Dictionary = channel_value
				var channel_name: String = str(channel.get("channel", ""))
				if not CHANNEL_UNITS.has(channel_name) or seen_channels.has(channel_name):
					return {"ok": false, "error": "unsupported or duplicate damage channel"}
				seen_channels[channel_name] = true
				if channel.get("unit") != CHANNEL_UNITS[channel_name]:
					return {"ok": false, "error": "damage channel unit does not match its closed definition"}
				if not CANDIDATE_OUTCOMES.has(channel.get("over_capacity_candidate")):
					return {"ok": false, "error": "over-capacity action must be repair_candidate or replace_candidate"}
				if not QUANTITY_CLASSES.has(channel.get("quantity_class")) \
						or not CAPACITY_CLASSES.has(channel.get("capacity_class")):
					return {"ok": false, "error": "quantity or capacity evidence class is unsupported"}
				for key: String in ["quantity_provenance", "capacity_provenance"]:
					if not _valid_text(channel.get(key), MAX_PROVENANCE_LENGTH):
						return {"ok": false, "error": key + " must be nonempty bounded text"}
				for key: String in ["quantity_low", "quantity_high", "capacity_low", "capacity_high"]:
					if not _bounded_nonnegative(channel.get(key)):
						return {"ok": false, "error": key + " must be finite and within [0, 1e12]"}
				if float(channel.quantity_low) > float(channel.quantity_high) \
						or float(channel.capacity_low) > float(channel.capacity_high):
					return {"ok": false, "error": "quantity and capacity intervals must be ordered low-to-high"}
				var qualification_ref: Variant = channel.get("qualification_ref")
				if typeof(qualification_ref) != TYPE_STRING or str(qualification_ref).length() > MAX_QUALIFICATION_REF_LENGTH:
					return {"ok": false, "error": "qualification_ref must be a bounded string"}
				var claims_qualified: bool = channel.quantity_class == "independently_validated" \
					or channel.capacity_class == "independently_validated"
				if claims_qualified and not _valid_text(qualification_ref, MAX_QUALIFICATION_REF_LENGTH):
					return {"ok": false, "error": "independently_validated claim requires a qualification_ref"}
				if not claims_qualified and not str(qualification_ref).is_empty():
					return {"ok": false, "error": "qualification_ref must be empty unless evidence claims independent validation"}
	return {"ok": true}


static func _evidence_class(quantity_classes: PackedStringArray, capacity_classes: PackedStringArray) -> String:
	var classes := PackedStringArray()
	for value: String in quantity_classes:
		if not classes.has(value):
			classes.append(value)
	for value: String in capacity_classes:
		if not classes.has(value):
			classes.append(value)
	classes.sort()
	if classes.is_empty():
		return "unknown"
	if classes.has("scenario_assumption"):
		return "scenario_assumption"
	if classes.size() > 1:
		return "mixed"
	if classes[0] == "independently_validated":
		return "independently_validated_claim"
	return "unqualified"


static func _combine_evidence_classes(classes: PackedStringArray) -> String:
	var unique := _sorted_unique(classes)
	if unique.size() > 1:
		return "mixed"
	return str(unique[0])


static func _outcome_rank(outcome: String) -> int:
	match outcome:
		"below_declared_capacity":
			return 0
		"inspect":
			return 1
		"repair_candidate":
			return 2
		"replace_candidate":
			return 3
	return 1


static func _sorted_unique(values: PackedStringArray) -> PackedStringArray:
	var unique := PackedStringArray()
	for value: String in values:
		if not unique.has(value):
			unique.append(value)
	unique.sort()
	return unique


static func _exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key: Variant in keys:
		if not value.has(key):
			return false
	return true


static func _valid_text(value: Variant, max_length: int) -> bool:
	return typeof(value) == TYPE_STRING and not str(value).strip_edges().is_empty() \
		and str(value).length() <= max_length


static func _bounded_nonnegative(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) \
		and float(value) >= 0.0 and float(value) <= MAX_VALUE


static func _is_sha256(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or str(value).length() != 64:
		return false
	var hex := "0123456789abcdef"
	for index: int in range(64):
		if not hex.contains(str(value).substr(index, 1)):
			return false
	return true


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message]}
