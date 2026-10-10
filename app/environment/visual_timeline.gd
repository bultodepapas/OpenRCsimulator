## TOD-08a: deterministic visual selection history, independent of rendering and simulation.
extends RefCounted

const TimeOfDayConfig: Script = preload("res://environment/time_of_day_config.gd")
const SolarClock: Script = preload("res://environment/solar_clock.gd")
const FORMAT: String = "openrc-visual-timeline v1"
const PROGRESSING_FORMAT: String = "openrc-visual-timeline v2"
const PROFILE_LEGACY: String = "legacy-spec"
const PROFILE_ASTRONOMICAL: String = "openrc-lighting-curves v1"
const MAX_SAFE_TICK: int = 9007199254740991
const TICKS_PER_SECOND: int = 240
const TIMELINE_FIELDS: Array[String] = ["format", "anchor_tick", "rate", "initial", "events"]
const INITIAL_FIELDS: Array[String] = ["config", "config_sha256", "profile"]
const EVENT_FIELDS: Array[String] = ["tick", "config", "config_sha256", "profile"]
const PROGRESSING_TIMELINE_FIELDS: Array[String] = [
	"format", "anchor_tick", "ticks_per_second", "initial", "events",
]
const PROGRESSING_INITIAL_FIELDS: Array[String] = ["clock", "config_sha256", "profile"]
const PROGRESSING_EVENT_FIELDS: Array[String] = [
	"tick", "kind", "clock", "config_sha256", "profile",
]


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


## Creates a progressing solar timeline. A selected config starts at an exact civil second.
static func create_progressing(config: Variant, anchor_tick: Variant = 0, rate: Variant = 1) -> Dictionary:
	var errors: Array[String] = []
	var parsed_anchor: Dictionary = _parse_tick(anchor_tick, "anchor_tick")
	if not bool(parsed_anchor.get("ok", false)):
		errors.append(str(parsed_anchor.error))
	var created_clock: Dictionary = SolarClock.create(config, anchor_tick, rate)
	if not bool(created_clock.get("ok", false)):
		_append_errors(errors, "clock", created_clock.get("errors", []))
	if not errors.is_empty():
		return _timeline_failure(errors)

	var clock: Dictionary = (created_clock["clock"] as Dictionary).duplicate(true)
	var identity: Dictionary = _identity(clock.config)
	return validate({
		"format": PROGRESSING_FORMAT,
		"anchor_tick": int(parsed_anchor.value),
		"ticks_per_second": TICKS_PER_SECOND,
		"initial": {
			"clock": clock,
			"config_sha256": identity.config_sha256,
			"profile": identity.profile,
		},
		"events": [],
	})


## Validates either supported version and returns a normalized, detached copy.
static func validate(raw: Variant) -> Dictionary:
	if typeof(raw) == TYPE_DICTIONARY and str((raw as Dictionary).get("format", "")) == PROGRESSING_FORMAT:
		return _validate_v2(raw)
	return _validate_v1(raw)


## Validates the fixed-time v1 schema. Keep this path stable for saved traces and checkpoints.
static func _validate_v1(raw: Variant) -> Dictionary:
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
	if typeof(raw) == TYPE_DICTIONARY and str((raw as Dictionary).get("format", "")) == PROGRESSING_FORMAT:
		return _append_v2_config_edit(raw, tick, config)
	return _append_v1_config_edit(raw, tick, config)


static func _append_v1_config_edit(raw: Variant, tick: Variant, config: Variant) -> Dictionary:
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
	if typeof(raw) == TYPE_DICTIONARY and str((raw as Dictionary).get("format", "")) == PROGRESSING_FORMAT:
		return _evaluate_v2(raw, tick)
	return _evaluate_v1(raw, tick)


static func _evaluate_v1(raw: Variant, tick: Variant) -> Dictionary:
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
		"subsecond_ticks": 0,
		"configured_start": selected_config.duplicate(true),
		"errors": [] as Array[String],
	}


## Appends a phase-preserving rate change to v2, promoting a v1 timeline when needed.
static func append_rate_edit(raw: Variant, tick: Variant, rate: Variant) -> Dictionary:
	var errors: Array[String] = []
	var validated: Dictionary = validate(raw)
	if not bool(validated.get("ok", false)):
		_append_errors(errors, "timeline", validated.get("errors", []))
	var parsed_tick: Dictionary = _parse_tick(tick, "edit tick")
	if not bool(parsed_tick.get("ok", false)):
		errors.append(str(parsed_tick.error))
	if not _is_rate(rate):
		errors.append("rate must be exactly 0 or 1")
	if not errors.is_empty():
		return _timeline_failure(errors)

	var timeline: Dictionary = (validated["timeline"] as Dictionary).duplicate(true)
	if str(timeline.format) == FORMAT:
		var promoted: Dictionary = _promote_v1(timeline)
		if not bool(promoted.get("ok", false)):
			return _timeline_failure(promoted.get("errors", []))
		timeline = promoted.timeline

	var edit_tick: int = int(parsed_tick.value)
	var last_tick: int = int(timeline.anchor_tick)
	if not timeline.events.is_empty():
		last_tick = int(timeline.events.back().tick)
	if edit_tick < last_tick:
		return _timeline_failure([
			"edit tick must be ordered after the previous event; equal ticks use array order",
		])

	var previous_clock: Dictionary = _last_clock(timeline)
	var changed: Dictionary = SolarClock.reanchor(previous_clock, edit_tick, rate)
	if not bool(changed.get("ok", false)):
		_append_errors(errors, "clock transition", changed.get("errors", []))
		return _timeline_failure(errors)
	var next_clock: Dictionary = (changed.clock as Dictionary).duplicate(true)
	var identity: Dictionary = _identity(next_clock.config)
	var events: Array = timeline.events
	events.append({
		"tick": edit_tick,
		"kind": "rate",
		"clock": next_clock,
		"config_sha256": identity.config_sha256,
		"profile": identity.profile,
	})
	timeline.events = events
	return validate(timeline)


static func _promote_v1(timeline: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var anchor_tick: int = int(timeline.anchor_tick)
	var initial_config: Dictionary = (timeline.initial.config as Dictionary).duplicate(true)
	var created: Dictionary = SolarClock.create(initial_config, anchor_tick, 0)
	if not bool(created.get("ok", false)):
		_append_errors(errors, "v1 initial clock", created.get("errors", []))
		return {"ok": false, "errors": errors}

	var current_clock: Dictionary = (created.clock as Dictionary).duplicate(true)
	var identity: Dictionary = _identity(current_clock.config)
	var promoted: Dictionary = {
		"format": PROGRESSING_FORMAT,
		"anchor_tick": anchor_tick,
		"ticks_per_second": TICKS_PER_SECOND,
		"initial": {
			"clock": current_clock.duplicate(true),
			"config_sha256": identity.config_sha256,
			"profile": identity.profile,
		},
		"events": [],
	}
	var promoted_events: Array = []
	for event_value: Variant in timeline.events:
		var event: Dictionary = event_value
		var event_tick: int = int(event.tick)
		var next_config: Dictionary = (event.config as Dictionary).duplicate(true)
		var changed: Dictionary = SolarClock.reanchor(current_clock, event_tick, 0, next_config)
		if not bool(changed.get("ok", false)):
			_append_errors(errors, "v1 event at tick %d" % event_tick, changed.get("errors", []))
			return {"ok": false, "errors": errors}
		current_clock = (changed.clock as Dictionary).duplicate(true)
		identity = _identity(current_clock.config)
		promoted_events.append({
			"tick": event_tick,
			"kind": "config",
			"clock": current_clock.duplicate(true),
			"config_sha256": identity.config_sha256,
			"profile": identity.profile,
		})
	promoted.events = promoted_events
	return {"ok": true, "timeline": promoted, "errors": [] as Array[String]}


## Appends a v2 config selection. Selecting a config resets the fractional phase.
static func _append_v2_config_edit(raw: Variant, tick: Variant, config: Variant) -> Dictionary:
	var errors: Array[String] = []
	var validated: Dictionary = validate(raw)
	if not bool(validated.get("ok", false)):
		_append_errors(errors, "timeline", validated.get("errors", []))
	var parsed_tick: Dictionary = _parse_tick(tick, "edit tick")
	if not bool(parsed_tick.get("ok", false)):
		errors.append(str(parsed_tick.error))
	var checked_config: Dictionary = TimeOfDayConfig.validate(config)
	if not bool(checked_config.get("ok", false)):
		_append_errors(errors, "config", checked_config.get("errors", []))
	if not errors.is_empty():
		return _timeline_failure(errors)

	var timeline: Dictionary = (validated.timeline as Dictionary).duplicate(true)
	var edit_tick: int = int(parsed_tick.value)
	var last_tick: int = int(timeline.anchor_tick)
	if not timeline.events.is_empty():
		last_tick = int(timeline.events.back().tick)
	if edit_tick < last_tick:
		return _timeline_failure([
			"edit tick must be ordered after the previous event; equal ticks use array order",
		])

	var next_config: Dictionary = (checked_config.config as Dictionary).duplicate(true)
	var previous_clock: Dictionary = _last_clock(timeline)
	var next_rate: int = int(previous_clock.rate)
	if str(next_config.get("mode", "")) == "legacy":
		next_rate = 0
	var changed: Dictionary = SolarClock.reanchor(previous_clock, edit_tick, next_rate, next_config)
	if not bool(changed.get("ok", false)):
		_append_errors(errors, "clock transition", changed.get("errors", []))
		return _timeline_failure(errors)

	var next_clock: Dictionary = (changed.clock as Dictionary).duplicate(true)
	var identity: Dictionary = _identity(next_clock.config)
	var events: Array = timeline.events
	events.append({
		"tick": edit_tick,
		"kind": "config",
		"clock": next_clock,
		"config_sha256": identity.config_sha256,
		"profile": identity.profile,
	})
	timeline.events = events
	return validate(timeline)


static func _validate_v2(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	if typeof(raw) != TYPE_DICTIONARY:
		return _timeline_failure(["timeline must be an object"])
	var source: Dictionary = raw
	_check_keys(source, PROGRESSING_TIMELINE_FIELDS, "timeline", errors)
	if typeof(source.get("format", null)) != TYPE_STRING or str(source.get("format", "")) != PROGRESSING_FORMAT:
		errors.append("timeline.format must be '%s'" % PROGRESSING_FORMAT)

	var parsed_anchor: Dictionary = _parse_tick(source.get("anchor_tick", null), "timeline.anchor_tick")
	if not bool(parsed_anchor.get("ok", false)):
		errors.append(str(parsed_anchor.error))
	var anchor_tick: int = int(parsed_anchor.get("value", -1))
	var ticks_value: Variant = source.get("ticks_per_second", null)
	if not _is_finite_number(ticks_value) or float(ticks_value) != float(TICKS_PER_SECOND):
		errors.append("timeline.ticks_per_second must be exactly %d" % TICKS_PER_SECOND)

	var normalized_initial: Dictionary = {}
	var initial_clock: Dictionary = {}
	var initial_value: Variant = source.get("initial", null)
	if typeof(initial_value) != TYPE_DICTIONARY:
		errors.append("timeline.initial must be an object")
	else:
		var initial_source: Dictionary = initial_value
		_check_keys(initial_source, PROGRESSING_INITIAL_FIELDS, "timeline.initial", errors)
		var clock_result: Dictionary = SolarClock.validate(initial_source.get("clock", null))
		if not bool(clock_result.get("ok", false)):
			_append_errors(errors, "timeline.initial.clock", clock_result.get("errors", []))
		else:
			initial_clock = (clock_result.clock as Dictionary).duplicate(true)
			if bool(parsed_anchor.get("ok", false)) and int(initial_clock.anchor_tick) != anchor_tick:
				errors.append("timeline.initial.clock.anchor_tick must match timeline.anchor_tick")
			if int(initial_clock.ticks_per_second) != TICKS_PER_SECOND:
				errors.append("timeline.initial.clock.ticks_per_second must be exactly %d" % TICKS_PER_SECOND)
			if int(initial_clock.subsecond_ticks) != 0:
				errors.append("timeline.initial.clock.subsecond_ticks must be zero")
			var identity: Dictionary = _identity(initial_clock.config)
			_check_identity(initial_source, identity, "timeline.initial", errors)
			normalized_initial = {
				"clock": initial_clock.duplicate(true),
				"config_sha256": identity.config_sha256,
				"profile": identity.profile,
			}

	var normalized_events: Array[Dictionary] = []
	var events_value: Variant = source.get("events", null)
	if typeof(events_value) != TYPE_ARRAY:
		errors.append("timeline.events must be an array")
	else:
		var previous_tick: int = anchor_tick
		var previous_clock: Dictionary = initial_clock.duplicate(true)
		var events: Array = events_value
		for index: int in events.size():
			var context: String = "timeline.events[%d]" % index
			var event_value: Variant = events[index]
			if typeof(event_value) != TYPE_DICTIONARY:
				errors.append("%s must be an object" % context)
				normalized_events.append({})
				continue
			var event_source: Dictionary = event_value
			_check_keys(event_source, PROGRESSING_EVENT_FIELDS, context, errors)
			var parsed_event_tick: Dictionary = _parse_tick(event_source.get("tick", null), "%s.tick" % context)
			if not bool(parsed_event_tick.get("ok", false)):
				errors.append(str(parsed_event_tick.error))
			var event_tick: int = int(parsed_event_tick.get("value", -1))
			var tick_is_ordered: bool = bool(parsed_anchor.get("ok", false)) and bool(parsed_event_tick.get("ok", false))
			if tick_is_ordered:
				if event_tick < anchor_tick:
					errors.append("%s.tick must be at or after anchor_tick" % context)
				if event_tick < previous_tick:
					errors.append("%s.tick must be ordered after the previous event; equal ticks use array order" % context)
				else:
					previous_tick = event_tick

			var kind_value: Variant = event_source.get("kind", null)
			var event_kind: String = ""
			if typeof(kind_value) != TYPE_STRING or (str(kind_value) != "config" and str(kind_value) != "rate"):
				errors.append("%s.kind must be 'config' or 'rate'" % context)
			else:
				event_kind = str(kind_value)

			var event_clock: Dictionary = {}
			var event_clock_result: Dictionary = SolarClock.validate(event_source.get("clock", null))
			if not bool(event_clock_result.get("ok", false)):
				_append_errors(errors, "%s.clock" % context, event_clock_result.get("errors", []))
			else:
				event_clock = (event_clock_result.clock as Dictionary).duplicate(true)
				if bool(parsed_event_tick.get("ok", false)) and int(event_clock.anchor_tick) != event_tick:
					errors.append("%s.clock.anchor_tick must match event tick" % context)
				if int(event_clock.ticks_per_second) != TICKS_PER_SECOND:
					errors.append("%s.clock.ticks_per_second must be exactly %d" % [context, TICKS_PER_SECOND])
				var identity: Dictionary = _identity(event_clock.config)
				_check_identity(event_source, identity, context, errors)
				if (not previous_clock.is_empty() and tick_is_ordered and event_tick >= previous_tick
						and not event_kind.is_empty() and bool(parsed_event_tick.get("ok", false))):
					_validate_v2_transition(previous_clock, event_clock, event_tick, event_kind, context, errors)
				normalized_events.append({
					"tick": event_tick if bool(parsed_event_tick.get("ok", false)) else -1,
					"kind": event_kind,
					"clock": event_clock.duplicate(true),
					"config_sha256": identity.config_sha256,
					"profile": identity.profile,
				})
				if tick_is_ordered and event_tick >= previous_tick:
					previous_clock = event_clock.duplicate(true)
				continue

			normalized_events.append({
				"tick": event_tick if bool(parsed_event_tick.get("ok", false)) else -1,
				"kind": event_kind,
			})

	if not errors.is_empty():
		return _timeline_failure(errors)
	return _timeline_success({
		"format": PROGRESSING_FORMAT,
		"anchor_tick": anchor_tick,
		"ticks_per_second": TICKS_PER_SECOND,
		"initial": normalized_initial,
		"events": normalized_events,
	})


static func _validate_v2_transition(
	previous_clock: Dictionary,
	event_clock: Dictionary,
	event_tick: int,
	event_kind: String,
	context: String,
	errors: Array[String]
) -> void:
	var expected_rate: int = int(event_clock.rate)
	var expected_clock_result: Dictionary
	if event_kind == "rate":
		expected_clock_result = SolarClock.reanchor(previous_clock, event_tick, expected_rate)
	else:
		expected_rate = int(previous_clock.rate)
		if str(event_clock.config.get("mode", "")) == "legacy":
			expected_rate = 0
		expected_clock_result = SolarClock.reanchor(
			previous_clock, event_tick, expected_rate, event_clock.config
		)
	if not bool(expected_clock_result.get("ok", false)):
		_append_errors(errors, "%s.clock transition" % context, expected_clock_result.get("errors", []))
		return
	var expected_clock: Dictionary = expected_clock_result.clock
	if expected_clock != event_clock:
		if event_kind == "rate":
			errors.append("%s.clock must exactly preserve the prior phase through SolarClock.reanchor" % context)
		else:
			errors.append("%s.clock must reset phase for the selected config and retain the compatible rate" % context)


static func _check_identity(source: Dictionary, identity: Dictionary, context: String, errors: Array[String]) -> void:
	var hash_value: Variant = source.get("config_sha256", null)
	if typeof(hash_value) != TYPE_STRING or str(hash_value) != str(identity.config_sha256):
		errors.append("%s.config_sha256 does not match its normalized clock config" % context)
	var profile_value: Variant = source.get("profile", null)
	if typeof(profile_value) != TYPE_STRING or str(profile_value) != str(identity.profile):
		errors.append("%s.profile does not match the clock config mode" % context)


static func _last_clock(timeline: Dictionary) -> Dictionary:
	if not timeline.events.is_empty():
		return (timeline.events.back().clock as Dictionary).duplicate(true)
	return (timeline.initial.clock as Dictionary).duplicate(true)


static func _is_rate(value: Variant) -> bool:
	if not _is_finite_number(value):
		return false
	return float(value) == 0.0 or float(value) == 1.0


static func _evaluate_v2(raw: Variant, tick: Variant) -> Dictionary:
	var errors: Array[String] = []
	var validated: Dictionary = validate(raw)
	if not bool(validated.get("ok", false)):
		_append_errors(errors, "timeline", validated.get("errors", []))
	var parsed_tick: Dictionary = _parse_tick(tick, "evaluation tick")
	if not bool(parsed_tick.get("ok", false)):
		errors.append(str(parsed_tick.error))
	if not errors.is_empty():
		return _evaluation_failure(errors)

	var timeline: Dictionary = validated.timeline
	var evaluation_tick: int = int(parsed_tick.value)
	var anchor_tick: int = int(timeline.anchor_tick)
	if evaluation_tick < anchor_tick:
		return _evaluation_failure(
			["evaluation tick precedes timeline.anchor_tick"], anchor_tick, evaluation_tick
		)

	var initial: Dictionary = timeline.initial
	var current_clock: Dictionary = (initial.clock as Dictionary).duplicate(true)
	var configured_start: Dictionary = (current_clock.config as Dictionary).duplicate(true)
	var selected_profile: String = str(initial.profile)
	for event_value: Variant in timeline.events:
		var event: Dictionary = event_value
		if int(event.tick) > evaluation_tick:
			break
		current_clock = (event.clock as Dictionary).duplicate(true)
		selected_profile = str(event.profile)
		if str(event.kind) == "config":
			configured_start = (current_clock.config as Dictionary).duplicate(true)

	var resolved: Dictionary = SolarClock.evaluate(current_clock, evaluation_tick)
	if not bool(resolved.get("ok", false)):
		_append_errors(errors, "solar clock", resolved.get("errors", []))
		return _evaluation_failure(errors, anchor_tick, evaluation_tick)
	return {
		"ok": true,
		"config": (resolved.config as Dictionary).duplicate(true),
		"profile": selected_profile,
		"anchor_tick": anchor_tick,
		"rate": int(resolved.rate),
		"tick": evaluation_tick,
		"subsecond_ticks": int(resolved.subsecond_ticks),
		"configured_start": configured_start.duplicate(true),
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
		"subsecond_ticks": 0,
		"configured_start": {},
		"errors": errors.duplicate(),
	}
