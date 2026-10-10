# TOD-09c1: bind an exact physics checkpoint to a fixed or progressing visual timeline.
extends RefCounted

const Config: Script = preload("res://environment/time_of_day_config.gd")
const VisualTimeline: Script = preload("res://environment/visual_timeline.gd")

const FORMAT: String = "openrc-visual-checkpoint v1"
const FORMAT_PROGRESSING: String = "openrc-visual-checkpoint v2"
const TIMELINE_FORMAT_FIXED: String = "openrc-visual-timeline v1"
const TIMELINE_FORMAT_PROGRESSING: String = "openrc-visual-timeline v2"
const PHYSICS_FORMATS: Array[String] = [
	"openrc-flight-checkpoint v1", "openrc-flight-checkpoint v2",
	"openrc-flight-checkpoint v3", "openrc-flight-checkpoint v4",
]
const PAIRED_FIELDS: Array[String] = ["format", "physics", "timeline", "field_identity", "payload_sha256"]
const PAIRED_MARKERS: Array[String] = ["physics", "timeline", "field_identity", "payload_sha256"]
const MAX_SAFE_TICK: int = 9007199254740991
const MAX_DATA_DEPTH: int = 64


## Wrap an unchanged FlightSession checkpoint with validated visual context.
static func make(snapshot: Dictionary, timeline: Variant, field_identity: String) -> Dictionary:
	var errors: Array[String] = []
	if not _valid_identity(field_identity):
		return _failure_make(["field_identity must be non-blank and at most 512 characters"])
	if not _is_native_data(snapshot):
		return _failure_make(["physics checkpoint contains an unsupported nested Variant"])
	var physics_check: Dictionary = _physics_tick(snapshot)
	if not physics_check.ok:
		return _failure_make(physics_check.errors)
	var visual: Dictionary = _timeline_at_tick(timeline, physics_check.tick)
	if not visual.ok:
		return _failure_make(visual.errors)
	var checkpoint_format: String = FORMAT
	if visual.timeline.format == TIMELINE_FORMAT_PROGRESSING:
		checkpoint_format = FORMAT_PROGRESSING
		var timestep_check: Dictionary = _physics_timestep(snapshot, int(visual.timeline.ticks_per_second))
		if not timestep_check.ok:
			return _failure_make(timestep_check.errors)
	var physics_copy: Dictionary = bytes_to_var(var_to_bytes(snapshot))
	var timeline_copy: Dictionary = bytes_to_var(var_to_bytes(visual.timeline))
	var checkpoint: Dictionary = {
		"format": checkpoint_format,
		"physics": physics_copy,
		"timeline": timeline_copy,
		"field_identity": field_identity,
	}
	checkpoint["payload_sha256"] = _payload_sha256(physics_copy, timeline_copy, field_identity)
	return {"ok": true, "checkpoint": checkpoint, "errors": errors}


## Open a paired checkpoint or a physics-only v1-v4 checkpoint with explicit legacy context.
static func read(candidate: Variant, expected_field_identity: String) -> Dictionary:
	if not _valid_identity(expected_field_identity):
		return _failure_read(["expected_field_identity must be non-blank and at most 512 characters"])
	if typeof(candidate) != TYPE_DICTIONARY:
		return _failure_read(["checkpoint must be an object"])
	if not _is_native_data(candidate):
		return _failure_read(["checkpoint contains an unsupported nested Variant"])
	var source: Dictionary = candidate
	var format_value: Variant = source.get("format", null)
	if typeof(format_value) != TYPE_STRING:
		return _failure_read(["checkpoint format must be a string"])
	if format_value == FORMAT:
		return _read_paired(source, expected_field_identity, TIMELINE_FORMAT_FIXED)
	if format_value == FORMAT_PROGRESSING:
		return _read_paired(source, expected_field_identity, TIMELINE_FORMAT_PROGRESSING)
	if not PHYSICS_FORMATS.has(str(format_value)):
		return _failure_read(["unknown checkpoint format '%s'" % str(format_value)])
	for marker: String in PAIRED_MARKERS:
		if source.has(marker):
			return _failure_read(["physics-only checkpoint contains paired visual field '%s'" % marker])
	var physics_check: Dictionary = _physics_tick(source)
	if not physics_check.ok:
		return _failure_read(physics_check.errors)
	var created: Dictionary = VisualTimeline.create(Config.defaults(), 0)
	if not created.get("ok", false):
		return _failure_read(["could not create legacy visual fallback timeline"])
	var visual: Dictionary = _timeline_at_tick(created.timeline, physics_check.tick)
	if not visual.ok:
		return _failure_read(visual.errors)
	return {
		"ok": true,
		"physics": bytes_to_var(var_to_bytes(source)),
		"timeline": bytes_to_var(var_to_bytes(visual.timeline)),
		"config": bytes_to_var(var_to_bytes(visual.config)),
		"profile": visual.profile,
		"rate": visual.rate,
		"anchor_tick": visual.anchor_tick,
		"context_status": "legacy_missing_visual",
		"errors": [],
	}


static func _read_paired(source: Dictionary, expected_field_identity: String, expected_timeline_format: String) -> Dictionary:
	if not _has_exact_keys(source, PAIRED_FIELDS):
		return _failure_read(["paired checkpoint has an invalid schema"])
	var physics: Variant = source.get("physics", null)
	var timeline: Variant = source.get("timeline", null)
	var identity: Variant = source.get("field_identity", null)
	var digest: Variant = source.get("payload_sha256", null)
	if typeof(physics) != TYPE_DICTIONARY or typeof(timeline) != TYPE_DICTIONARY \
			or typeof(identity) != TYPE_STRING or typeof(digest) != TYPE_STRING:
		return _failure_read(["paired checkpoint fields have invalid types"])
	if not _valid_identity(identity) or identity != expected_field_identity:
		return _failure_read(["paired checkpoint field_identity does not match the active field"])
	if not _is_sha256(digest) or digest != _payload_sha256(physics, timeline, identity):
		return _failure_read(["paired checkpoint payload_sha256 does not match its native payload"])
	var physics_check: Dictionary = _physics_tick(physics)
	if not physics_check.ok:
		return _failure_read(physics_check.errors)
	var visual: Dictionary = _timeline_at_tick(timeline, physics_check.tick, expected_timeline_format)
	if not visual.ok:
		return _failure_read(visual.errors)
	if expected_timeline_format == TIMELINE_FORMAT_PROGRESSING:
		var timestep_check: Dictionary = _physics_timestep(physics, int(visual.timeline.ticks_per_second))
		if not timestep_check.ok:
			return _failure_read(timestep_check.errors)
	var result: Dictionary = {
		"ok": true,
		"physics": bytes_to_var(var_to_bytes(physics)),
		"timeline": bytes_to_var(var_to_bytes(visual.timeline)),
		"config": bytes_to_var(var_to_bytes(visual.config)),
		"profile": visual.profile,
		"rate": visual.rate,
		"anchor_tick": visual.anchor_tick,
		"context_status": "paired",
		"errors": [],
	}
	if expected_timeline_format == TIMELINE_FORMAT_PROGRESSING:
		result["subsecond_ticks"] = visual.subsecond_ticks
		result["configured_start"] = bytes_to_var(var_to_bytes(visual.configured_start))
	return result


static func _physics_tick(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["physics checkpoint must be an object"]}
	var checkpoint: Dictionary = raw
	if typeof(checkpoint.get("format", null)) != TYPE_STRING or not PHYSICS_FORMATS.has(str(checkpoint.get("format"))):
		return {"ok": false, "errors": ["physics checkpoint format must be v1 through v4"]}
	var simulation: Variant = checkpoint.get("simulation", null)
	if typeof(simulation) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["physics checkpoint must contain a simulation object"]}
	var tick: Variant = simulation.get("tick", null)
	if typeof(tick) != TYPE_INT or tick < 0 or tick > MAX_SAFE_TICK:
		return {"ok": false, "errors": ["physics simulation.tick must be a non-negative safe integer"]}
	return {"ok": true, "tick": int(tick), "errors": []}


static func _timeline_at_tick(raw: Variant, checkpoint_tick: int, expected_format: String = "") -> Dictionary:
	var validated: Dictionary = VisualTimeline.validate(raw)
	if not validated.get("ok", false):
		return {"ok": false, "errors": _prefixed_errors("timeline", validated.get("errors", []))}
	var timeline: Dictionary = validated.timeline
	if not expected_format.is_empty() and timeline.get("format", "") != expected_format:
		return {"ok": false, "errors": ["timeline format does not match paired checkpoint format"]}
	if int(timeline.anchor_tick) > checkpoint_tick:
		return {"ok": false, "errors": ["checkpoint tick precedes the timeline anchor"]}
	for event: Dictionary in timeline.events:
		if int(event.tick) > checkpoint_tick:
			return {"ok": false, "errors": ["timeline contains an event after the physics checkpoint tick"]}
	var evaluated: Dictionary = VisualTimeline.evaluate(timeline, checkpoint_tick)
	if not evaluated.get("ok", false):
		return {"ok": false, "errors": _prefixed_errors("timeline evaluation", evaluated.get("errors", []))}
	var result: Dictionary = {
		"ok": true,
		"timeline": timeline,
		"config": evaluated.config,
		"profile": evaluated.profile,
		"rate": evaluated.rate,
		"anchor_tick": evaluated.anchor_tick,
		"errors": [],
	}
	if timeline.format == TIMELINE_FORMAT_PROGRESSING:
		result["subsecond_ticks"] = evaluated.subsecond_ticks
		result["configured_start"] = bytes_to_var(var_to_bytes(evaluated.configured_start))
	return result


static func _physics_timestep(raw: Variant, ticks_per_second: int) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY or ticks_per_second <= 0:
		return {"ok": false, "errors": ["progressing timeline requires a positive physics timestep"]}
	var simulation: Variant = raw.get("simulation", null)
	if typeof(simulation) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["progressing timeline requires physics simulation.dt"]}
	var timestep: Variant = simulation.get("dt", null)
	if (typeof(timestep) != TYPE_FLOAT and typeof(timestep) != TYPE_INT) \
			or not is_finite(float(timestep)) or float(timestep) <= 0.0:
		return {"ok": false, "errors": ["progressing timeline requires finite positive physics simulation.dt"]}
	var expected: float = 1.0 / float(ticks_per_second)
	if float(timestep) != expected:
		return {"ok": false, "errors": ["physics simulation.dt does not match timeline.ticks_per_second"]}
	return {"ok": true, "errors": []}


static func _payload_sha256(physics: Dictionary, timeline: Dictionary, field_identity: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes([physics, timeline, field_identity]))
	return context.finish().hex_encode()


static func _valid_identity(value: String) -> bool:
	return not value.strip_edges().is_empty() and value.length() <= 512


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in value.length():
		var codepoint: int = value.unicode_at(index)
		if not ((codepoint >= 48 and codepoint <= 57) or (codepoint >= 97 and codepoint <= 102)):
			return false
	return true


static func _has_exact_keys(source: Dictionary, fields: Array[String]) -> bool:
	if source.size() != fields.size():
		return false
	for key: Variant in source.keys():
		if (typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME) or not fields.has(str(key)):
			return false
	return true


static func _is_native_data(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_DATA_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_ARRAY:
			for item: Variant in value:
				if not _is_native_data(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			for key: Variant in dictionary.keys():
				if (typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME) \
						or not _is_native_data(dictionary[key], depth + 1):
					return false
			return true
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return true
	return false


static func _prefixed_errors(prefix: String, raw: Variant) -> Array[String]:
	var errors: Array[String] = []
	if typeof(raw) == TYPE_ARRAY:
		for message: Variant in raw:
			errors.append("%s: %s" % [prefix, str(message)])
	if errors.is_empty():
		errors.append("%s validation failed" % prefix)
	return errors


static func _failure_make(raw_errors: Variant) -> Dictionary:
	return {"ok": false, "checkpoint": {}, "errors": _string_errors(raw_errors)}


static func _failure_read(raw_errors: Variant) -> Dictionary:
	return {
		"ok": false, "physics": {}, "timeline": {}, "config": {},
		"context_status": "invalid", "errors": _string_errors(raw_errors),
	}


static func _string_errors(raw: Variant) -> Array[String]:
	var errors: Array[String] = []
	if typeof(raw) == TYPE_ARRAY:
		for message: Variant in raw:
			errors.append(str(message))
	return errors
