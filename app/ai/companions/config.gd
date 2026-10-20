extends RefCounted

## The first companion preset is intentionally narrower than the aircraft catalog.
const AIRCRAFT_ID := "jensen-das-ugly-stik-60"
const ACTIVITY := "circuits"
const PILOT_SKILL := "experienced"
const MAX_COUNT := 3
const UINT32_MAX := 4294967295

const ALLOWED_KEYS := [
	"enabled",
	"count",
	"seed",
	"aircraft_id",
	"activity",
	"pilot",
	"incidents_enabled",
	"engine_volume",
	"show_labels",
	"label_distance_m",
]


static func defaults() -> Dictionary:
	return {
		"enabled": false,
		"count": 1,
		"seed": 1,
		"aircraft_id": AIRCRAFT_ID,
		"activity": ACTIVITY,
		"pilot": PILOT_SKILL,
		"incidents_enabled": false,
		"engine_volume": 1.0,
		"show_labels": false,
		"label_distance_m": 250.0,
	}


## Accept a partial UI record, fill the fixed MVP choices, and reject unsupported settings.
static func validate(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("companion config must be an object")
		return {"ok": false, "config": {}, "errors": errors}
	var source: Dictionary = raw
	for key: Variant in source:
		if key not in ALLOWED_KEYS:
			errors.append("unknown companion config field '%s'" % str(key))

	var normalized: Dictionary = defaults()
	var enabled_value: Variant = source.get("enabled", normalized.enabled)
	if typeof(enabled_value) != TYPE_BOOL:
		errors.append("enabled must be a boolean")
	else:
		normalized.enabled = enabled_value

	var count_value: Variant = source.get("count", normalized.count)
	if typeof(count_value) != TYPE_INT or int(count_value) < 0 or int(count_value) > MAX_COUNT:
		errors.append("count must be an integer in [0, %d]" % MAX_COUNT)
	else:
		normalized.count = int(count_value)

	var seed_value: Variant = source.get("seed", normalized.seed)
	if typeof(seed_value) != TYPE_INT or int(seed_value) < 0 or int(seed_value) > UINT32_MAX:
		errors.append("seed must be an unsigned 32-bit integer")
	else:
		normalized.seed = int(seed_value)

	var aircraft_value: Variant = source.get("aircraft_id", normalized.aircraft_id)
	if typeof(aircraft_value) != TYPE_STRING or aircraft_value != AIRCRAFT_ID:
		errors.append("aircraft_id must be '%s'" % AIRCRAFT_ID)
	else:
		normalized.aircraft_id = aircraft_value

	var activity_value: Variant = source.get("activity", normalized.activity)
	if typeof(activity_value) != TYPE_STRING or activity_value != ACTIVITY:
		errors.append("activity must be '%s'" % ACTIVITY)
	else:
		normalized.activity = activity_value

	var pilot_value: Variant = source.get("pilot", normalized.pilot)
	if typeof(pilot_value) != TYPE_STRING or pilot_value != PILOT_SKILL:
		errors.append("pilot must be '%s'" % PILOT_SKILL)
	else:
		normalized.pilot = pilot_value

	var incidents_value: Variant = source.get("incidents_enabled", normalized.incidents_enabled)
	if typeof(incidents_value) != TYPE_BOOL or incidents_value:
		errors.append("incidents_enabled must be false for the MVP")
	else:
		normalized.incidents_enabled = false

	var labels_value: Variant = source.get("show_labels", normalized.show_labels)
	if typeof(labels_value) != TYPE_BOOL:
		errors.append("show_labels must be a boolean")
	else:
		normalized.show_labels = labels_value
	for key: String in ["engine_volume", "label_distance_m"]:
		var value: Variant = source.get(key, normalized[key])
		var lower := 0.0 if key == "engine_volume" else 50.0
		var upper := 1.0 if key == "engine_volume" else 1000.0
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) \
				or float(value) < lower or float(value) > upper:
			errors.append("%s must be a finite number in [%s, %s]" % [key, lower, upper])
		else:
			normalized[key] = float(value)

	if normalized.enabled and normalized.count == 0:
		errors.append("enabled companions require a count from 1 to %d" % MAX_COUNT)
	if not errors.is_empty():
		return {"ok": false, "config": {}, "errors": errors}
	return {"ok": true, "config": normalized, "errors": errors}


## Overlay only explicit developer CLI settings on an injected UI/default record.
## Capture options are validated here but never merged into the persisted record.
static func from_args(args: PackedStringArray, base: Variant = {}) -> Dictionary:
	var starting: Variant = defaults()
	if typeof(base) == TYPE_DICTIONARY and not base.is_empty():
		starting = base
	var checked_base: Dictionary = validate(starting)
	if not checked_base.ok:
		return checked_base
	var candidate: Dictionary = checked_base.config.duplicate(true)
	var errors := PackedStringArray()
	var saw_count := false
	var saw_seed := false
	for arg_value: String in args:
		if arg_value == "--companions":
			errors.append("--companions requires an '=count' value")
		elif arg_value == "--companions-seed":
			errors.append("--companions-seed requires an '=seed' value")
		elif arg_value.begins_with("--companions="):
			if saw_count:
				errors.append("--companions may be supplied once")
				continue
			saw_count = true
			var count_text: String = arg_value.trim_prefix("--companions=")
			if not count_text.is_valid_int():
				errors.append("--companions must be an integer in [0, %d]" % MAX_COUNT)
				continue
			var count_value: int = count_text.to_int()
			if count_value < 0 or count_value > MAX_COUNT:
				errors.append("--companions must be an integer in [0, %d]" % MAX_COUNT)
				continue
			candidate.count = count_value
			candidate.enabled = count_value > 0
		elif arg_value.begins_with("--companions-seed="):
			if saw_seed:
				errors.append("--companions-seed may be supplied once")
				continue
			saw_seed = true
			var seed_text: String = arg_value.trim_prefix("--companions-seed=")
			if not seed_text.is_valid_int():
				errors.append("--companions-seed must be an unsigned 32-bit integer")
				continue
			var seed_value: int = seed_text.to_int()
			if seed_value < 0 or seed_value > UINT32_MAX:
				errors.append("--companions-seed must be an unsigned 32-bit integer")
				continue
			candidate.seed = seed_value
	var recording: Dictionary = recording_options(args)
	errors.append_array(recording.errors)
	if not str(recording.directory).is_empty() and not candidate.enabled:
		errors.append("--companions-record requires enabled companions")
	if not errors.is_empty():
		return {"ok": false, "config": {}, "errors": errors}
	return validate(candidate)


## Developer-only capture paths never enter persisted companion settings.
static func recording_options(args: PackedStringArray) -> Dictionary:
	var directory := ""
	var found := false
	var player_log := false
	var errors := PackedStringArray()
	for arg: String in args:
		if arg == "--flight-log" or arg.begins_with("--flight-log="): player_log = true
		if arg != "--companions-record" and not arg.begins_with("--companions-record="): continue
		if found:
			errors.append("--companions-record may be supplied once")
		found = true
		if arg == "--companions-record" or arg.trim_prefix("--companions-record=").strip_edges().is_empty():
			errors.append("--companions-record requires a new output directory")
		else:
			directory = arg.trim_prefix("--companions-record=")
	if found and player_log:
		errors.append("Use --companions-record or --flight-log, not both")
	return {ok = errors.is_empty(), errors = errors, directory = directory}
