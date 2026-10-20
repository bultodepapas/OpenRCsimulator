# TOD-08a: paired checkpoint integrity, visual event evaluation and legacy fallback.
extends SceneTree

const Config: Script = preload("res://environment/time_of_day_config.gd")
const VisualTimeline: Script = preload("res://environment/visual_timeline.gd")
const VisualCheckpoint: Script = preload("res://app_state/visual_checkpoint.gd")

var checks: int = 0
var failures: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config: Dictionary = Config.defaults()
	var created: Dictionary = VisualTimeline.create(config, 0)
	_check("default timeline creates", created.get("ok", false))
	var timeline: Dictionary = created.get("timeline", {})
	var edit_one: Dictionary = config.duplicate(true)
	edit_one["local_seconds"] = 46800
	var appended_one: Dictionary = VisualTimeline.append_config_edit(timeline, 10, edit_one)
	_check("timeline accepts a tick edit", appended_one.get("ok", false))
	var edit_two: Dictionary = edit_one.duplicate(true)
	edit_two["local_seconds"] = 50400
	var appended_two: Dictionary = VisualTimeline.append_config_edit(appended_one.get("timeline", {}), 10, edit_two)
	_check("timeline keeps same-tick edits in order", appended_two.get("ok", false))
	var event_timeline: Dictionary = appended_two.get("timeline", {})

	var physics: Dictionary = _physics(10)
	var original_physics_bytes: PackedByteArray = var_to_bytes(physics)
	var original_timeline_bytes: PackedByteArray = var_to_bytes(event_timeline)
	var made: Dictionary = VisualCheckpoint.make(physics, event_timeline, "field:west")
	_check("paired checkpoint makes", made.get("ok", false), str(made.get("errors", [])))
	var checkpoint: Dictionary = made.get("checkpoint", {})
	_check("paired record has exact envelope schema", _exact_keys(checkpoint, ["format", "physics", "timeline", "field_identity", "payload_sha256"]))
	_check("format is versioned", checkpoint.get("format", "") == "openrc-visual-checkpoint v1")
	_check("payload digest is lowercase SHA256", _is_sha256(str(checkpoint.get("payload_sha256", ""))))
	_check("physics payload is exact native data", var_to_bytes(checkpoint.get("physics", {})) == original_physics_bytes)
	_check("timeline payload is exact native data", var_to_bytes(checkpoint.get("timeline", {})) == original_timeline_bytes)

	# Inputs and outputs are detached from the returned envelope through native Variant copying.
	physics.simulation.sample[0] = 42.0
	event_timeline.initial.config.local_seconds = 1
	_check("make deep-copies both caller inputs", var_to_bytes(checkpoint.physics) == original_physics_bytes
		and var_to_bytes(checkpoint.timeline) == original_timeline_bytes)
	var loaded: Dictionary = VisualCheckpoint.read(bytes_to_var(var_to_bytes(checkpoint)), "field:west")
	_check("native serialization round-trip reads paired record", loaded.get("ok", false), str(loaded.get("errors", [])))
	_check("paired context is identified", loaded.get("context_status", "") == "paired")
	_check("visual selection is evaluated at checkpoint tick", loaded.get("config", {}).get("local_seconds", -1) == 50400
		and loaded.get("profile", "") == "legacy-spec" and loaded.get("anchor_tick", -1) == 0)
	var loaded_physics_bytes: PackedByteArray = var_to_bytes(loaded.physics)
	loaded.physics.simulation.sample[0] = -9.0
	loaded.timeline.initial.config.local_seconds = 2
	_check("read deep-copies the candidate", var_to_bytes(checkpoint.physics) != var_to_bytes(loaded.physics)
		and var_to_bytes(checkpoint.timeline) != var_to_bytes(loaded.timeline)
		and loaded_physics_bytes == original_physics_bytes)

	var exact_tick_config: Dictionary = Config.defaults()
	exact_tick_config["mode"] = "astronomical"
	var astro_timeline: Dictionary = VisualTimeline.create(exact_tick_config, 2).get("timeline", {})
	var astro_pair: Dictionary = VisualCheckpoint.make(_physics(2), astro_timeline, "field:west")
	var astro_read: Dictionary = VisualCheckpoint.read(astro_pair.get("checkpoint", {}), "field:west")
	_check("astronomical profile survives pairing", astro_read.get("ok", false)
		and astro_read.get("profile", "") == "openrc-lighting-curves v1"
		and astro_read.get("config", {}).get("mode", "") == "astronomical")

	var future_edit: Dictionary = Config.defaults()
	future_edit["local_seconds"] = 100
	var future_result: Dictionary = VisualTimeline.append_config_edit(timeline, 11, future_edit)
	var future_timeline: Dictionary = future_result.get("timeline", {})
	_check("timeline can retain a later edit for other historical queries", future_result.get("ok", false))
	_check("make rejects an event after the checkpoint", not VisualCheckpoint.make(_physics(10), future_timeline, "field:west").get("ok", false))
	var future_record: Dictionary = _unchecked_record(_physics(10), future_timeline, "field:west")
	var future_read: Dictionary = VisualCheckpoint.read(future_record, "field:west")
	_check("read rejects a validly hashed future event", not future_read.get("ok", false)
		and future_read.get("context_status", "") == "invalid")
	var later_anchor: Dictionary = VisualTimeline.create(Config.defaults(), 11).get("timeline", {})
	_check("make rejects a checkpoint before its timeline anchor", not VisualCheckpoint.make(_physics(10), later_anchor, "field:west").get("ok", false))
	var early_event: Dictionary = VisualTimeline.append_config_edit(later_anchor, 10, edit_one)
	_check("timeline rejects an event before its anchor", not early_event.get("ok", false))

	var tampered_physics: Dictionary = _unchecked_record(_physics(10), timeline, "field:west")
	tampered_physics.physics.simulation.sample[0] = 0.125
	_check("payload digest binds exact physics Variant bytes", not VisualCheckpoint.read(tampered_physics, "field:west").get("ok", false))
	var tampered_visual: Dictionary = _unchecked_record(_physics(10), timeline, "field:west")
	tampered_visual.timeline.initial.config.local_seconds = 11
	_check("payload digest binds exact visual Variant bytes", not VisualCheckpoint.read(tampered_visual, "field:west").get("ok", false))
	var rebound_field: Dictionary = _unchecked_record(_physics(10), timeline, "field:west")
	rebound_field.field_identity = "field:east"
	_check("payload digest binds field identity", not VisualCheckpoint.read(rebound_field, "field:east").get("ok", false))
	_check("active field mismatch is refused", not VisualCheckpoint.read(checkpoint, "field:east").get("ok", false))
	var rehashed_bad_profile: Dictionary = _unchecked_record(_physics(10), timeline, "field:west")
	rehashed_bad_profile.timeline.initial.profile = "wrong-profile"
	rehashed_bad_profile.payload_sha256 = _digest(rehashed_bad_profile.physics, rehashed_bad_profile.timeline, rehashed_bad_profile.field_identity)
	_check("timeline profile mismatch is refused after valid rehash", not VisualCheckpoint.read(rehashed_bad_profile, "field:west").get("ok", false))

	var missing_timeline: Dictionary = _unchecked_record(_physics(10), timeline, "field:west")
	missing_timeline.erase("timeline")
	var missing_read: Dictionary = VisualCheckpoint.read(missing_timeline, "field:west")
	_check("paired checkpoint with missing visual data never falls back", not missing_read.get("ok", false)
		and missing_read.get("context_status", "") == "invalid")
	var disguised_pair: Dictionary = _unchecked_record(_physics(10), timeline, "field:west")
	disguised_pair.format = "openrc-flight-checkpoint v1"
	var disguised_read: Dictionary = VisualCheckpoint.read(disguised_pair, "field:west")
	_check("paired checkpoint cannot fall through as legacy after format damage", not disguised_read.get("ok", false)
		and disguised_read.get("context_status", "") == "invalid")
	var extra_field: Dictionary = _unchecked_record(_physics(10), timeline, "field:west")
	extra_field["unknown"] = true
	_check("unknown paired schema field is refused", not VisualCheckpoint.read(extra_field, "field:west").get("ok", false))
	var unknown_format: Dictionary = _physics(10)
	unknown_format.format = "openrc-visual-checkpoint v99"
	_check("unknown checkpoint format is refused", not VisualCheckpoint.read(unknown_format, "field:west").get("ok", false))

	for version: int in [1, 2, 3, 4, 5, 6, 8, 9, 11]:
		var legacy: Dictionary = _physics(10, version)
		var legacy_read: Dictionary = VisualCheckpoint.read(legacy, "field:west")
		_check("legacy physics v%d gets explicit fallback" % version,
			legacy_read.get("ok", false)
			and legacy_read.get("context_status", "") == "legacy_missing_visual"
			and legacy_read.get("timeline", {}).get("anchor_tick", -1) == 0
			and legacy_read.get("config", {}).get("mode", "") == "legacy"
			and legacy_read.get("profile", "") == "legacy-spec")
	var liquid: Dictionary = _physics(10, 11)
	liquid.liquid_physics_format = "openrc-flight-checkpoint v4"
	var collision: Dictionary = liquid.duplicate(true)
	collision.physics_format = liquid.format
	collision.format = "openrc-flight-checkpoint v7"
	collision.collision_world_identity = "a".repeat(64)
	for finite_snapshot: Dictionary in [liquid, collision]:
		var finite_pair: Dictionary = VisualCheckpoint.make(finite_snapshot, timeline, "field:west")
		var finite_read: Dictionary = VisualCheckpoint.read(finite_pair.get("checkpoint", {}), "field:west")
		_check("finite liquid physics survives visual pairing exactly " + finite_snapshot.format,
			finite_read.get("ok", false)
			and var_to_bytes(finite_read.get("physics", {})) == var_to_bytes(finite_snapshot))
	collision.physics_format = "openrc-flight-checkpoint v12"
	_check("collision envelope still refuses unknown physics", not VisualCheckpoint.make(collision, timeline, "field:west").ok)
	var partial_legacy: Dictionary = _physics(10)
	partial_legacy["timeline"] = {}
	_check("physics-only record with a visual marker never falls back", not VisualCheckpoint.read(partial_legacy, "field:west").get("ok", false))

	for bad_tick: Variant in [-1, 1.5, "10", true, 9007199254740992]:
		var malformed: Dictionary = _physics(10)
		malformed.simulation.tick = bad_tick
		_check("invalid physics tick is refused (%s)" % str(bad_tick), not VisualCheckpoint.make(malformed, timeline, "field:west").get("ok", false))
	var unsupported: Dictionary = _physics(10)
	unsupported.simulation["callable"] = func() -> bool:
		return true
	_check("unsupported nested Variant is refused", not VisualCheckpoint.make(unsupported, timeline, "field:west").get("ok", false))

	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _physics(tick: Variant, version: int = 1) -> Dictionary:
	return {
		"format": "openrc-flight-checkpoint v%d" % version,
		"configuration": "physics-fixture",
		"simulation": {
			"format": "openrc-simulation-checkpoint v1",
			"tick": tick,
			"sample": PackedFloat64Array([0.10000000000000002, -3.25]),
		},
	}


func _unchecked_record(physics: Dictionary, timeline: Dictionary, field_identity: String) -> Dictionary:
	var record: Dictionary = {
		"format": "openrc-visual-checkpoint v1",
		"physics": bytes_to_var(var_to_bytes(physics)),
		"timeline": bytes_to_var(var_to_bytes(timeline)),
		"field_identity": field_identity,
	}
	record["payload_sha256"] = _digest(record.physics, record.timeline, field_identity)
	return record


func _digest(physics: Dictionary, timeline: Dictionary, field_identity: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes([physics, timeline, field_identity]))
	return context.finish().hex_encode()


func _exact_keys(source: Dictionary, expected: Array[String]) -> bool:
	if source.size() != expected.size():
		return false
	for key: Variant in source.keys():
		if not expected.has(str(key)):
			return false
	return true


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in value.length():
		var codepoint: int = value.unicode_at(index)
		if not ((codepoint >= 48 and codepoint <= 57) or (codepoint >= 97 and codepoint <= 102)):
			return false
	return true
