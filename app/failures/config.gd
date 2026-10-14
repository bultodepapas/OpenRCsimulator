extends RefCounted

const DEFAULT_PROBABILITY_PERCENT := 0
const DEFAULT_INCLUDE_CATASTROPHIC := false
const DEFAULT_NOTIFY := true

const CONFIG_KEYS: Array[String] = [
	"probability_percent",
	"include_catastrophic",
	"notify",
]


static func defaults() -> Dictionary:
	return {
		"probability_percent": DEFAULT_PROBABILITY_PERCENT,
		"include_catastrophic": DEFAULT_INCLUDE_CATASTROPHIC,
		"notify": DEFAULT_NOTIFY,
	}


## Validate the exact player-facing failure configuration. Values are never coerced.
static func validate(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("failure config must be an object")
		return {"ok": false, "config": {}, "errors": errors}

	var source: Dictionary = raw
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

	if not errors.is_empty():
		return {"ok": false, "config": {}, "errors": errors}
	return {
		"ok": true,
		"config": {
			"probability_percent": int(probability),
			"include_catastrophic": bool(include_catastrophic),
			"notify": bool(notify),
		},
		"errors": errors,
	}
