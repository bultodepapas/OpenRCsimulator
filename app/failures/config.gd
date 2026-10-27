extends RefCounted

const Catalog := preload("res://failures/catalog.gd")

const DEFAULT_PROBABILITY_PERCENT := 0
const DEFAULT_INCLUDE_CATASTROPHIC := false
const DEFAULT_NOTIFY := true
const DEFAULT_SEVERITY := "standard"
const DEFAULT_ONSET := "standard"

## Training-policy bands, not measured RC failure statistics (EM-29).
const SEVERITIES: Array[String] = ["mild", "standard", "severe"]
const ONSET_WINDOWS: Array[String] = ["early", "standard", "late"]
const ONSET_WINDOW_SECONDS := {
	"early": [20, 60],
	"standard": [20, 120],
	"late": [60, 240],
}

## The original three-key request remains readable and upgrades to the defaults below.
const LEGACY_CONFIG_KEYS: Array[String] = [
	"probability_percent",
	"include_catastrophic",
	"notify",
]
const CONFIG_KEYS: Array[String] = [
	"probability_percent",
	"include_catastrophic",
	"notify",
	"severity",
	"onset",
	"excluded_ids",
]


static func defaults() -> Dictionary:
	return {
		"probability_percent": DEFAULT_PROBABILITY_PERCENT,
		"include_catastrophic": DEFAULT_INCLUDE_CATASTROPHIC,
		"notify": DEFAULT_NOTIFY,
		"severity": DEFAULT_SEVERITY,
		"onset": DEFAULT_ONSET,
		"excluded_ids": [],
	}


## Validate the exact player-facing failure configuration. Values are never coerced;
## the legacy three-key shape is the only accepted upgrade.
static func validate(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("failure config must be an object")
		return {"ok": false, "config": {}, "errors": errors}

	var source: Dictionary = raw
	if _has_exact_keys(source, LEGACY_CONFIG_KEYS):
		source = source.duplicate(true)
		source["severity"] = DEFAULT_SEVERITY
		source["onset"] = DEFAULT_ONSET
		source["excluded_ids"] = []
	for key: String in CONFIG_KEYS:
		if not source.has(key):
			errors.append("failure config is missing '%s'" % key)
	for key: Variant in source.keys():
		if not CONFIG_KEYS.has(str(key)):
			errors.append("failure config has unknown key '%s'" % str(key))
	if not errors.is_empty():
		return {"ok": false, "config": {}, "errors": errors}

	var probability: Variant = source["probability_percent"]
	if typeof(probability) != TYPE_INT:
		errors.append("failure config probability_percent must be an integer")
	elif probability < 0 or probability > 100:
		errors.append("failure config probability_percent must be between 0 and 100")

	var include_catastrophic: Variant = source["include_catastrophic"]
	if typeof(include_catastrophic) != TYPE_BOOL:
		errors.append("failure config include_catastrophic must be a boolean")

	var notify: Variant = source["notify"]
	if typeof(notify) != TYPE_BOOL:
		errors.append("failure config notify must be a boolean")

	var severity: Variant = source["severity"]
	if typeof(severity) != TYPE_STRING or str(severity) not in SEVERITIES:
		errors.append("failure config severity must be mild, standard or severe")

	var onset: Variant = source["onset"]
	if typeof(onset) != TYPE_STRING or str(onset) not in ONSET_WINDOWS:
		errors.append("failure config onset must be early, standard or late")

	var excluded: Array[String] = []
	var excluded_value: Variant = source["excluded_ids"]
	if typeof(excluded_value) != TYPE_ARRAY and typeof(excluded_value) != TYPE_PACKED_STRING_ARRAY:
		errors.append("failure config excluded_ids must be a list of failure IDs")
	else:
		for item: Variant in excluded_value:
			if typeof(item) != TYPE_STRING and typeof(item) != TYPE_STRING_NAME:
				errors.append("failure config excluded_ids must contain only strings")
				break
			var failure_id := str(item)
			if failure_id not in Catalog.KNOWN_IDS:
				errors.append("failure config excludes unknown failure '%s'" % failure_id)
			elif excluded.has(failure_id):
				errors.append("failure config excludes '%s' more than once" % failure_id)
			else:
				excluded.append(failure_id)
	excluded.sort()

	if not errors.is_empty():
		return {"ok": false, "config": {}, "errors": errors}
	return {
		"ok": true,
		"config": {
			"probability_percent": int(probability),
			"include_catastrophic": bool(include_catastrophic),
			"notify": bool(notify),
			"severity": str(severity),
			"onset": str(onset),
			"excluded_ids": excluded,
		},
		"errors": errors,
	}


## True when the player kept every default except probability, catastrophe and notices.
## Historical v1/v2 plans can only express this default selection, severity and onset window.
static func uses_default_selection(config: Dictionary) -> bool:
	var excluded: Variant = config.get("excluded_ids", [])
	return str(config.get("severity", DEFAULT_SEVERITY)) == DEFAULT_SEVERITY \
		and str(config.get("onset", DEFAULT_ONSET)) == DEFAULT_ONSET \
		and (typeof(excluded) == TYPE_ARRAY or typeof(excluded) == TYPE_PACKED_STRING_ARRAY) \
		and excluded.is_empty()


static func legacy_projection(config: Dictionary) -> Dictionary:
	return {
		"probability_percent": int(config.probability_percent),
		"include_catastrophic": bool(config.include_catastrophic),
		"notify": bool(config.notify),
	}


static func onset_window(onset: String) -> Array:
	return ONSET_WINDOW_SECONDS.get(onset, ONSET_WINDOW_SECONDS[DEFAULT_ONSET]).duplicate()


static func _has_exact_keys(source: Dictionary, expected_keys: Array[String]) -> bool:
	if source.size() != expected_keys.size():
		return false
	for key: String in expected_keys:
		if not source.has(key):
			return false
	return true
