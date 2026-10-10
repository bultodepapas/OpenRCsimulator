## TOD-08a: deterministic visual selection history, independent of rendering and simulation.
extends RefCounted

const TimeOfDayConfig: Script = preload("res://environment/time_of_day_config.gd")
const FORMAT: String = "openrc-visual-timeline v1"
const PROFILE_LEGACY: String = "legacy-spec"
const PROFILE_ASTRONOMICAL: String = "openrc-lighting-curves v1"
const MAX_SAFE_TICK: int = 9007199254740991
const TIMELINE_FIELDS: Array[String] = ["format", "anchor_tick", "rate", "initial", "events"]
const INITIAL_FIELDS: Array[String] = ["config", "config_sha256", "profile"]
const EVENT_FIELDS: Array[String] = ["tick", "config", "config_sha256", "profile"]


## Creates a fixed-time timeline. The anchor rate is always zero for this schema version.
static func create(config: Variant, anchor_tick: Variant = 0) -> Dictionary:
	var errors: Array[String] = []
	var parsed_anchor: Dictionary = _parse_tick(anchor_tick, "anchor_tick")
	if not bool(parsed_anchor.get("ok", false)):
		errors.append(str(parsed_anchor.error))
	var validated_config: Dictionary = TimeOfDayConfig.validate(config)
	if not bool(validated_config.get("ok", false)):
		_append_errors(errors, "config", validated_config.get("errors", []))
	if not errors.is_empty():
		return _timeline_failure(errors)

	var normalized_config: Dictionary = (validated_config["config"] as Dictionary).duplicate(true)
	var identity: Dictionary = _identity(normalized_config)
	var timeline: Dictionary = {
		"format": FORMAT,
		"anchor_tick": int(parsed_anchor.value),
		"rate": 0.0,
		"initial": {
			"config": normalized_config,
			"config_sha256": identity.config_sha256,
			"profile": identity.profile,
		},
		"events": [],
	}
	return validate(timeline)


## Validates the versioned schema and returns a normalized, detached copy.
static func validate(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	if typeof(raw) != TYPE_DICTIONARY:
		return _timeline_failure(["timeline must be an object"])
	var source: Dictionary = raw
	_check_keys(source, TIMELINE_FIELDS, "timeline", errors)

	var format_value: Variant = source.get("format", null)
	if typeof(format_value) != TYPE_STRING or str(format_value) != FORMAT:
		errors.append("timeline.format must be '%s'" % FORMAT)

	var parsed_anchor: Dictionary = _parse_tick(source.get("anchor_tick", null), "timeline.anchor_tick")
	if not bool(parsed_anchor.get("ok", false)):
		errors.append(str(parsed_anchor.error))
	var anchor_tick: int = int(parsed_anchor.get("value", -1))

	var rate_value: Variant = source.get("rate", null)
	if not _is_finite_number(rate_value) or float(rate_value) != 0.0:
		errors.append("timeline.rate must be finite and exactly 0 for v1")

	var initial_value: Variant = source.get("initial", null)
	var normalized_initial: Dictionary = {}
	if typeof(initial_value) != TYPE_DICTIONARY:
		errors.append("timeline.initial must be an object")
	else:
		normalized_initial = _normalize_record(initial_value, "timeline.initial", INITIAL_FIELDS, errors)

	var normalized_events: Array[Dictionary] = []
	var events_value: Variant = source.get("events", null)
	if typeof(events_value) != TYPE_ARRAY:
		errors.append("timeline.events must be an array")
	elif bool(parsed_anchor.get("ok", false)):
		var previous_tick: int = anchor_tick
		var events: Array = events_value
		for index: int in events.size():
			var event_context: String = "timeline.events[%d]" % index
			var normalized_event: Dictionary = _normalize_record(events[index], event_context, EVENT_FIELDS, errors)
			if normalized_event.has("tick"):
				var event_tick: int = int(normalized_event["tick"])
				if event_tick < anchor_tick:
					errors.append("%s.tick must be at or after anchor_tick" % event_context)
				if event_tick < previous_tick:
					errors.append("%s.tick must be ordered after the previous event; equal ticks use array order" % event_context)
				if event_tick >= previous_tick:
					previous_tick = event_tick
			normalized_events.append(normalized_event)
	elif typeof(events_value) == TYPE_ARRAY:
		# Validate individual event contents even when the anchor is malformed.
		var events_without_anchor: Array = events_value
		for index: int in events_without_anchor.size():
			normalized_events.append(_normalize_record(events_without_anchor[index],
				"timeline.events[%d]" % index, EVENT_FIELDS, errors))

	if not errors.is_empty():
		return _timeline_failure(errors)

	var normalized_timeline: Dictionary = {
		"format": FORMAT,
		"anchor_tick": anchor_tick,
		"rate": 0.0,
		"initial": normalized_initial,
		"events": normalized_events,
	}
	return _timeline_success(normalized_timeline)


## Adds an immutable config event. Same-tick events are retained in order; the last one wins at that tick.
static func append_config_edit(raw: Variant, tick: Variant, config: Variant) -> Dictionary:
	var errors: Array[String] = []
	var validated_timeline: Dictionary = validate(raw)
	if not bool(validated_timeline.get("ok", false)):
		_append_errors(errors, "timeline", validated_timeline.get("errors", []))
	var parsed_tick: Dictionary = _parse_tick(tick, "edit tick")
	if not bool(parsed_tick.get("ok", false)):
		errors.append(str(parsed_tick.error))
	var validated_config: Dictionary = TimeOfDayConfig.validate(config)
	if not bool(validated_config.get("ok", false)):
		_append_errors(errors, "config", validated_config.get("errors", []))
	if not errors.is_empty():
		return _timeline_failure(errors)

	var timeline: Dictionary = (validated_timeline["timeline"] as Dictionary).duplicate(true)
	var event_tick: int = int(parsed_tick.value)
	if event_tick < int(timeline.anchor_tick):
		errors.append("edit tick must be at or after timeline.anchor_tick")
	var events: Array = timeline.events
	if not events.is_empty() and event_tick < int(events.back().tick):
		errors.append("edit tick must be ordered after the previous event; equal ticks use array order")
	if not errors.is_empty():
		return _timeline_failure(errors)

	var normalized_config: Dictionary = (validated_config["config"] as Dictionary).duplicate(true)
	var identity: Dictionary = _identity(normalized_config)
	events.append({
		"tick": event_tick,
		"config": normalized_config,
		"config_sha256": identity.config_sha256,
		"profile": identity.profile,
	})
	timeline["events"] = events
	return validate(timeline)


## Resolves the config in force at a known simulation tick without advancing time.
static func evaluate(raw: Variant, tick: Variant) -> Dictionary:
	var errors: Array[String] = []
	var validated_timeline: Dictionary = validate(raw)
	if not bool(validated_timeline.get("ok", false)):
		_append_errors(errors, "timeline", validated_timeline.get("errors", []))
	var parsed_tick: Dictionary = _parse_tick(tick, "evaluation tick")
	if not bool(parsed_tick.get("ok", false)):
		errors.append(str(parsed_tick.error))
	if not errors.is_empty():
		return _evaluation_failure(errors)

	var timeline: Dictionary = validated_timeline["timeline"]
	var evaluation_tick: int = int(parsed_tick.value)
	var anchor_tick: int = int(timeline.anchor_tick)
	if evaluation_tick < anchor_tick:
		return _evaluation_failure(["evaluation tick precedes timeline.anchor_tick"], anchor_tick, evaluation_tick)

	var initial: Dictionary = timeline.initial
	var selected_config: Dictionary = (initial.config as Dictionary).duplicate(true)
	var selected_profile: String = str(initial.profile)
	for event_value: Variant in timeline.events:
		var event: Dictionary = event_value
		if int(event.tick) > evaluation_tick:
			break
		selected_config = (event.config as Dictionary).duplicate(true)
		selected_profile = str(event.profile)
	return {
		"ok": true,
		"config": selected_config.duplicate(true),
		"profile": selected_profile,
		"anchor_tick": anchor_tick,
		"rate": 0.0,
		"tick": evaluation_tick,
		"errors": [] as Array[String],
	}


static func _normalize_record(raw: Variant, context: String, fields: Array[String], errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s must be an object" % context)
		return {}
	var source: Dictionary = raw
	_check_keys(source, fields, context, errors)

	var parsed_tick: Dictionary = {}
	if fields.has("tick"):
		parsed_tick = _parse_tick(source.get("tick", null), "%s.tick" % context)
		if not bool(parsed_tick.get("ok", false)):
			errors.append(str(parsed_tick.error))

	var config_result: Dictionary = TimeOfDayConfig.validate(source.get("config", null))
	var normalized_config: Dictionary = {}
	if not bool(config_result.get("ok", false)):
		_append_errors(errors, "%s.config" % context, config_result.get("errors", []))
	else:
		normalized_config = (config_result["config"] as Dictionary).duplicate(true)

	var result: Dictionary = {}
	if fields.has("tick") and bool(parsed_tick.get("ok", false)):
		result["tick"] = int(parsed_tick.value)
	if normalized_config.is_empty():
		return result

	var identity: Dictionary = _identity(normalized_config)
	var hash_value: Variant = source.get("config_sha256", null)
	if typeof(hash_value) != TYPE_STRING or str(hash_value) != str(identity.config_sha256):
		errors.append("%s.config_sha256 does not match its normalized config" % context)
	var profile_value: Variant = source.get("profile", null)
	if typeof(profile_value) != TYPE_STRING or str(profile_value) != str(identity.profile):
		errors.append("%s.profile does not match the config mode" % context)
	result["config"] = normalized_config
	result["config_sha256"] = identity.config_sha256
	result["profile"] = identity.profile
	return result


static func _identity(config: Dictionary) -> Dictionary:
	var profile: String = PROFILE_LEGACY if str(config.get("mode", "")) == "legacy" else PROFILE_ASTRONOMICAL
	var encoded: String = JSON.stringify(config, "", true, true)
	return {"config_sha256": encoded.sha256_text(), "profile": profile}


static func _parse_tick(value: Variant, label: String) -> Dictionary:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return {"ok": false, "error": "%s must be an integer from 0 through %d" % [label, MAX_SAFE_TICK]}
	if not is_finite(float(value)):
		return {"ok": false, "error": "%s must be finite" % label}
	var number: float = float(value)
	if number < 0.0 or number > float(MAX_SAFE_TICK):
		return {"ok": false, "error": "%s must be from 0 through %d" % [label, MAX_SAFE_TICK]}
	if floor(number) != number:
		return {"ok": false, "error": "%s must be an integer" % label}
	return {"ok": true, "value": int(number)}


static func _check_keys(source: Dictionary, required: Array[String], context: String, errors: Array[String]) -> void:
	for field: String in required:
		if not source.has(field):
			errors.append("%s is missing required field '%s'" % [context, field])
	for key: Variant in source.keys():
		if typeof(key) != TYPE_STRING or not required.has(str(key)):
			errors.append("%s has unknown field '%s'" % [context, str(key)])


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	return is_finite(float(value))


static func _append_errors(target: Array[String], context: String, source: Variant) -> void:
	if typeof(source) != TYPE_ARRAY:
		target.append("%s validation failed" % context)
		return
	for error_value: Variant in source:
		target.append("%s: %s" % [context, str(error_value)])


static func _timeline_success(timeline: Dictionary) -> Dictionary:
	return {"ok": true, "timeline": timeline.duplicate(true), "errors": [] as Array[String]}


static func _timeline_failure(errors: Array[String]) -> Dictionary:
	return {"ok": false, "timeline": {}, "errors": errors.duplicate()}


static func _evaluation_failure(errors: Array[String], anchor_tick: int = -1, tick: int = -1) -> Dictionary:
	return {
		"ok": false,
		"config": {},
		"profile": "",
		"anchor_tick": anchor_tick,
		"rate": 0.0,
		"tick": tick,
		"errors": errors.duplicate(),
	}
