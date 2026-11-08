extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const OUTPUT := "res://../tmp/audit-20261108-ground-passivity"

func _initialize() -> void:
	run.call_deferred()


func fail(message: String) -> void:
	printerr("BASELINE FAILED: ", message)
	quit(1)


func run() -> void:
	if not Vehicle.set_backend_override_for_tests("gdscript_reference"):
		fail("cannot select reference backend")
		return
	var session := Session.new()
	root.add_child(session)
	if not session.prepare_default() or not session.start_recording():
		fail("prepare/record failed: " + session.load_error)
		return
	var neutral := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
	if not session.tick_once(neutral) or not session.resume():
		fail("neutral arm/resume failed")
		return
	for tick in 840:
		var driving := tick < 360 or (tick >= 420 and tick < 660)
		var sample := {"throttle": 1.0 if driving else 0.0, "steering": 0.0,
			"brake": 0.0 if driving else 1.0, "reverse": false, "armed": true}
		if not session.tick_once(sample):
			fail("tick %d: %s" % [tick, session.fault_reason])
			return
	if not session.stop_recording():
		fail("stop recording failed")
		return
	var exported: Dictionary = session.export_recording("f6_baseline")
	if not exported.get("ok", false) or exported.samples != 841:
		fail("recording export: " + str(exported))
		return
	var checkpoint: Dictionary = session.checkpoint()
	var state: PackedFloat64Array = session.state_snapshot()
	var damage: PackedFloat64Array = session.damage_snapshot()
	var tape: PackedFloat64Array = session.control_tape_snapshot()
	var events: Array[Dictionary] = session.event_tape_snapshot()
	if checkpoint.is_empty() or tape.size() != 840 * 4:
		fail("checkpoint/tape incomplete")
		return
	for pair in [[str(exported.csv_path), OUTPUT.path_join("baseline.csv")],
			[str(exported.metadata_path), OUTPUT.path_join("baseline-recording.json")]]:
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(pair[0]), ProjectSettings.globalize_path(pair[1])) != OK:
			fail("could not preserve recording")
			return
	var checkpoint_file := FileAccess.open(OUTPUT.path_join("baseline-checkpoint.json"), FileAccess.WRITE)
	checkpoint_file.store_string(JSON.stringify(checkpoint, "\t", true, true))
	checkpoint_file.close()
	if not session.replay(tape) or session.tick != 840 \
			or session.state_snapshot().to_byte_array() != state.to_byte_array() \
			or session.damage_snapshot().to_byte_array() != damage.to_byte_array() \
			or session.control_tape_snapshot().to_byte_array() != tape.to_byte_array() \
			or session.event_tape_snapshot() != events:
		fail("same-backend replay failed or differs: " + session.load_error)
		return
	var result := {"complete": true, "exact_replay": true, "ticks": 840, "samples": 841,
		"phases": [[0, 360, "drive"], [360, 420, "brake"], [420, 660, "drive"], [660, 840, "brake"]],
		"identities": session.identities_snapshot(), "solver_identity": Vehicle.backend_identity(),
		"checkpoint_sha256": checkpoint.checkpoint_sha256, "state_sha256": checkpoint.state_sha256,
		"tape_sha256": checkpoint.control_tape_sha256, "events": events}
	var result_file := FileAccess.open(OUTPUT.path_join("baseline-replay.json"), FileAccess.WRITE)
	result_file.store_string(JSON.stringify(result, "\t", true, true))
	result_file.close()
	print("F6 baseline: 840 ticks, 841 samples, exact replay")
	session.free()
	quit(0)
