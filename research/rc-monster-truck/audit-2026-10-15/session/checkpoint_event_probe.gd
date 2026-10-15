extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source := Session.new()
	var braking_checkpoint_restorable := false
	var saw_braking_event := false
	var prepared := source.prepare_default()
	if prepared and source.tick_once(NEUTRAL) and source.resume():
		var throttle := NEUTRAL.duplicate()
		throttle.throttle = 1.0
		for _tick in 480:
			if not source.tick_once(throttle):
				break
		var brake := NEUTRAL.duplicate()
		brake.brake = 1.0
		for _tick in 1200:
			if not source.tick_once(brake):
				break
			for event: Dictionary in source.event_tape_snapshot():
				if event.get("type") == "braking_distance":
					saw_braking_event = true
					break
			if saw_braking_event:
				break
	var braking_checkpoint: Dictionary = source.checkpoint()
	if not braking_checkpoint.is_empty():
		braking_checkpoint_restorable = source.can_restore_checkpoint(braking_checkpoint)
	print("braking_event_seen=", saw_braking_event,
		" braking_checkpoint_restorable=", braking_checkpoint_restorable)

	var verifier := Session.new()
	var verifier_prepared := verifier.prepare_default()
	var candidate: Dictionary = verifier.checkpoint() if verifier_prepared else {}
	if candidate.is_empty():
		printerr("FAIL: could not create a tick-zero checkpoint")
		source.free()
		verifier.free()
		quit(1)
		return
	# Checkpoint digests detect accidental changes, but are unkeyed. Recompute both
	# after adding an event that the live session never emits.
	candidate.event_tape.append({"type": "forged_event", "tick": 0, "time_s": 0.0})
	candidate.event_tape_sha256 = verifier._hash_variant(candidate.event_tape)
	candidate.checkpoint_sha256 = verifier._checkpoint_hash(candidate)
	var verifier_state_before: PackedFloat64Array = verifier.state_snapshot()
	var accepted := verifier.can_restore_checkpoint(candidate)
	var restored := verifier.restore_checkpoint(candidate)
	var unchanged := verifier.state_snapshot().to_byte_array() == verifier_state_before.to_byte_array()
	print("forged_event_accepted=", accepted,
		" restored=", restored,
		" state_unchanged=", unchanged)
	print("checkpoint_event_probe=" + ("FAIL" if accepted and restored else "PASS"))
	print("braking_event_checkpoint_probe=" + ("FAIL" if saw_braking_event and not braking_checkpoint_restorable else "PASS"))
	var has_defect := (accepted and restored) or not unchanged \
		or (saw_braking_event and not braking_checkpoint_restorable)
	source.free()
	verifier.free()
	quit(1 if has_defect else 0)
