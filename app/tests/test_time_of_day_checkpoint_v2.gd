## TOD-09c1: paired progressing visual checkpoints bind physics tick rate and resolve solar phase.
extends SceneTree

const Config: Script = preload("res://environment/time_of_day_config.gd")
const Timeline: Script = preload("res://environment/visual_timeline.gd")
const Envelope: Script = preload("res://app_state/visual_checkpoint.gd")

const CHECKPOINT_V1: String = "openrc-visual-checkpoint v1"
const CHECKPOINT_V2: String = "openrc-visual-checkpoint v2"

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
	var start: Dictionary = _astronomical_start()
	var created: Dictionary = Timeline.create_progressing(start, 0, 1)
	_check("progressing timeline creates", created.get("ok", false), str(created.get("errors", [])))
	var progressing: Dictionary = created.get("timeline", {})
	var paused: Dictionary = Timeline.append_rate_edit(progressing, 1, 0)
	_check("timeline pauses at a tick boundary", paused.get("ok", false), str(paused.get("errors", [])))
	var resumed: Dictionary = Timeline.append_rate_edit(paused.get("timeline", {}), 4, 1)
	_check("timeline resumes from its exact phase", resumed.get("ok", false), str(resumed.get("errors", [])))
	var phase_timeline: Dictionary = resumed.get("timeline", {})
	var phase_physics: Dictionary = _physics(122, true)
	var phase_physics_bytes: PackedByteArray = var_to_bytes(phase_physics)
	var made: Dictionary = Envelope.make(phase_physics, phase_timeline, "field:west")
	_check("progressing checkpoint makes", made.get("ok", false), str(made.get("errors", [])))
	var phase_pair: Dictionary = made.get("checkpoint", {})
	_check("progressing envelope uses v2", phase_pair.get("format", "") == CHECKPOINT_V2)
	var loaded: Dictionary = Envelope.read(bytes_to_var(var_to_bytes(phase_pair)), "field:west")
	_check("native progressing pair round-trips", loaded.get("ok", false), str(loaded.get("errors", [])))
	_check("physics checkpoint native bytes stay exact", var_to_bytes(loaded.get("physics", {})) == phase_physics_bytes)
	_check("timeline native bytes stay exact", var_to_bytes(loaded.get("timeline", {})) == var_to_bytes(phase_timeline))
	_check("pause and resume preserve fractional ticks", loaded.get("rate", -1) == 1
		and loaded.get("subsecond_ticks", -1) == 119
		and loaded.get("config", {}).get("local_seconds", -1) == 43200)
	_check("v2 read returns the configured start", loaded.get("configured_start", {}).get("local_seconds", -1) == 43200)
	loaded.config.local_seconds = 1
	loaded.configured_start.local_seconds = 2
	_check("resolved config and configured start are detached from each other and saved history",
		loaded.timeline.initial.clock.config.local_seconds == 43200
		and phase_pair.timeline.initial.clock.config.local_seconds == 43200)

	var future_config: Dictionary = start.duplicate(true)
	future_config.local_seconds = 46800
	var future: Dictionary = Timeline.append_config_edit(phase_timeline, 123, future_config)
	_check("progressing timeline can describe a later edit", future.get("ok", false))
	_check("make rejects an event after the checkpoint", not Envelope.make(phase_physics, future.get("timeline", {}), "field:west").get("ok", false))
	var future_record: Dictionary = _record(CHECKPOINT_V2, phase_physics, future.get("timeline", {}), "field:west")
	var future_read: Dictionary = Envelope.read(future_record, "field:west")
	_check("read rejects a validly hashed future event", not future_read.get("ok", false)
		and future_read.get("context_status", "") == "invalid")

	var wrong_dt: Dictionary = phase_pair.duplicate(true)
	wrong_dt.physics.simulation.dt = 0.01
	wrong_dt.payload_sha256 = _digest(wrong_dt.physics, wrong_dt.timeline, wrong_dt.field_identity)
	_check("valid hash cannot hide a mismatched physics timestep", not Envelope.read(wrong_dt, "field:west").get("ok", false))
	for invalid_dt: Variant in [NAN, INF, true, "1/240", 0.0, -1.0]:
		var invalid_physics: Dictionary = _physics(122, true)
		invalid_physics.simulation.dt = invalid_dt
		_check("v2 creation rejects invalid dt %s" % str(invalid_dt),
			not Envelope.make(invalid_physics, phase_timeline, "field:west").get("ok", false))
		var invalid_record: Dictionary = _record(CHECKPOINT_V2, invalid_physics, phase_timeline, "field:west")
		_check("v2 read rejects validly hashed invalid dt %s" % str(invalid_dt),
			not Envelope.read(invalid_record, "field:west").get("ok", false))
	var missing_dt_physics: Dictionary = _physics(122, false)
	_check("v2 creation requires physics simulation.dt", not Envelope.make(missing_dt_physics, phase_timeline, "field:west").get("ok", false))
	var missing_dt_record: Dictionary = _record(CHECKPOINT_V2, missing_dt_physics, phase_timeline, "field:west")
	_check("v2 read requires physics simulation.dt", not Envelope.read(missing_dt_record, "field:west").get("ok", false))

	var fixed_timeline: Dictionary = Timeline.create(Config.defaults(), 0).get("timeline", {})
	var mismatched_v1: Dictionary = _record(CHECKPOINT_V1, phase_physics, phase_timeline, "field:west")
	var mismatched_v2: Dictionary = _record(CHECKPOINT_V2, phase_physics, fixed_timeline, "field:west")
	_check("v1 envelope refuses a v2 timeline", not Envelope.read(mismatched_v1, "field:west").get("ok", false))
	_check("v2 envelope refuses a v1 timeline", not Envelope.read(mismatched_v2, "field:west").get("ok", false))

	var hour_timeline: Dictionary = Timeline.create_progressing(start, 0, 1).get("timeline", {})
	var hour_physics: Dictionary = _physics(864000, true)
	var hour_pair: Dictionary = Envelope.make(hour_physics, hour_timeline, "field:west").get("checkpoint", {})
	var hour_read: Dictionary = Envelope.read(hour_pair, "field:west")
	_check("one simulated hour resolves the solar clock", hour_read.get("ok", false)
		and hour_read.get("config", {}).get("local_seconds", -1) == 46800)
	_check("configured start remains distinct from elapsed solar time", hour_read.get("configured_start", {}).get("local_seconds", -1) == 43200)
	var restarted: Dictionary = Timeline.append_config_edit(phase_timeline, 6, future_config)
	var restarted_pair: Dictionary = Envelope.make(_physics(122, true), restarted.get("timeline", {}), "field:west").get("checkpoint", {})
	var restarted_read: Dictionary = Envelope.read(restarted_pair, "field:west")
	_check("explicit solar time selection becomes the new configured start", restarted_read.get("ok", false)
		and restarted_read.get("configured_start", {}).get("local_seconds", -1) == 46800
		and restarted_read.get("config", {}).get("local_seconds", -1) == 46800)

	var old_physics: Dictionary = _physics(10, false)
	var old_timeline: Dictionary = Timeline.create(Config.defaults(), 0).get("timeline", {})
	var old_pair: Dictionary = Envelope.make(old_physics, old_timeline, "field:west").get("checkpoint", {})
	var old_loaded: Dictionary = Envelope.read(bytes_to_var(var_to_bytes(old_pair)), "field:west")
	_check("v1 fixed-time paired checkpoint remains compatible", old_pair.get("format", "") == CHECKPOINT_V1
		and old_loaded.get("ok", false) and old_loaded.get("config", {}).get("mode", "") == "legacy")
	var old_fallback: Dictionary = Envelope.read(old_physics, "field:west")
	_check("old physics-only fallback remains compatible", old_fallback.get("ok", false)
		and old_fallback.get("context_status", "") == "legacy_missing_visual")

	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _astronomical_start() -> Dictionary:
	var result: Dictionary = Config.defaults()
	result.mode = "astronomical"
	result.local_seconds = 43200
	return result


func _physics(tick: int, include_dt: bool) -> Dictionary:
	var simulation: Dictionary = {"tick": tick}
	if include_dt:
		simulation["dt"] = 1.0 / 240.0
	return {
		"format": "openrc-flight-checkpoint v1",
		"configuration": "physics-fixture",
		"simulation": simulation,
	}


func _record(format: String, physics: Dictionary, timeline: Dictionary, field_identity: String) -> Dictionary:
	var record: Dictionary = {
		"format": format,
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
