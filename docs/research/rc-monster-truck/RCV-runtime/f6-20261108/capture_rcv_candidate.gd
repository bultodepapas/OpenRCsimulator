extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const OUTPUT := "res://../tmp/audit-20261108-ground-passivity"

func _initialize() -> void:
	run.call_deferred()


func fail(message: String) -> void:
	printerr("CANDIDATE FAILED: ", message)
	quit(1)


func run() -> void:
	if not Vehicle.set_backend_override_for_tests("gdscript_reference"):
		fail("cannot select reference backend")
		return
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("baseline-checkpoint.json")))
	if typeof(source) != TYPE_DICTIONARY or int(source.get("tick", -1)) != 840:
		fail("baseline checkpoint missing or incomplete")
		return
	var tape := Marshalls.base64_to_raw(source.control_tape_f64_base64).to_float64_array()
	if tape.size() != 840 * 4:
		fail("baseline input tape incomplete")
		return
	var session := Session.new()
	root.add_child(session)
	if not session.prepare_default():
		fail("candidate prepare failed: " + session.load_error)
		return
	var initial: PackedFloat64Array = session.state_snapshot()
	var old_refused := not session.can_restore_checkpoint(source) and not session.restore_checkpoint(source) \
		and session.tick == 0 and session.state_snapshot().to_byte_array() == initial.to_byte_array()
	if not old_refused or source.solver_identity.solver_version == Vehicle.SOLVER_VERSION:
		fail("old-law checkpoint was not refused atomically")
		return
	if not session.start_recording():
		fail("candidate recording failed")
		return
	var neutral := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
	if not session.tick_once(neutral) or not session.resume():
		fail("neutral arm/resume failed")
		return
	for tick in 840:
		var offset := tick * 4
		var sample := {"throttle": tape[offset], "steering": tape[offset + 1], "brake": tape[offset + 2],
			"reverse": tape[offset + 3] != 0.0, "armed": true}
		if not session.tick_once(sample):
			fail("candidate tick %d: %s" % [tick, session.fault_reason])
			return
	if not session.stop_recording():
		fail("candidate stop recording failed")
		return
	var exported: Dictionary = session.export_recording("f6_candidate")
	if not exported.get("ok", false) or exported.samples != 841:
		fail("candidate recording export: " + str(exported))
		return
	var checkpoint: Dictionary = session.checkpoint()
	var state: PackedFloat64Array = session.state_snapshot()
	var damage: PackedFloat64Array = session.damage_snapshot()
	var controls: PackedFloat64Array = session.control_tape_snapshot()
	var events: Array[Dictionary] = session.event_tape_snapshot()
	if checkpoint.is_empty() or controls.to_byte_array() != tape.to_byte_array():
		fail("candidate did not use the same complete input tape")
		return
	for pair in [[str(exported.csv_path), OUTPUT.path_join("candidate.csv")],
			[str(exported.metadata_path), OUTPUT.path_join("candidate-recording.json")]]:
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(pair[0]), ProjectSettings.globalize_path(pair[1])) != OK:
			fail("could not preserve candidate recording")
			return
	var checkpoint_file := FileAccess.open(OUTPUT.path_join("candidate-checkpoint.json"), FileAccess.WRITE)
	checkpoint_file.store_string(JSON.stringify(checkpoint, "\t", true, true))
	checkpoint_file.close()
	if not session.replay(tape) or session.tick != 840 \
			or session.state_snapshot().to_byte_array() != state.to_byte_array() \
			or session.damage_snapshot().to_byte_array() != damage.to_byte_array() \
			or session.control_tape_snapshot().to_byte_array() != tape.to_byte_array() \
			or session.event_tape_snapshot() != events:
		fail("candidate self-replay failed or differs: " + session.load_error)
		return
	var result := {"complete": true, "solver_changed": true, "same_tape": true,
		"old_checkpoint_refused": old_refused, "candidate_self_replay": true,
		"ticks": 840, "samples": 841, "identities": session.identities_snapshot(),
		"baseline_solver": source.solver_identity, "candidate_solver": Vehicle.backend_identity(),
		"checkpoint_sha256": checkpoint.checkpoint_sha256, "state_sha256": checkpoint.state_sha256,
		"tape_sha256": checkpoint.control_tape_sha256, "events": events}
	var result_file := FileAccess.open(OUTPUT.path_join("candidate-replay.json"), FileAccess.WRITE)
	result_file.store_string(JSON.stringify(result, "\t", true, true))
	result_file.close()
	print("F6 candidate: 840 ticks, same tape, old checkpoint refused, self-replay exact")
	session.free()
	quit(0)
