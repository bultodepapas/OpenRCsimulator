# UI-06a-R1: physics-only checkpoints cannot inherit the destination session's launch identity.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Field := preload("res://data/field_loader.gd")
const Recorder := preload("res://sim/recorder.gd")

var checks := 0
var failures := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func session(choice: String) -> Node:
	var flight := Session.new()
	flight.setup()
	flight.input_enabled = false
	flight.set_field(Field.load_from().field)
	flight.start_choice = choice
	flight.reset()
	return flight

func replay(source_choice: String, destination_choice: String) -> void:
	var source := session(source_choice)
	var destination := session(destination_choice)
	for tick in 12:
		source.sim.step()
	var snapshot: Dictionary = source.checkpoint()
	var before: Dictionary = destination.trace_meta()
	var bad := snapshot.duplicate(true)
	bad.configuration = "incompatible"
	check("rejected restore retains launch metadata", not destination.restore_checkpoint(bad)
		and destination.trace_meta() == before)
	check("cross-start checkpoint restores", destination.restore_checkpoint(bytes_to_var(var_to_bytes(snapshot))))
	check("restoration keeps exact physical boundary", destination.sim.checkpoint() == source.sim.checkpoint())
	var meta: Dictionary = destination.trace_meta()
	check("replay declares unknown launch origin", meta.launch_choice == "unknown"
		and meta.selected_start_choice == "unknown" and meta.launch_kind == "checkpoint_restore"
		and meta.scenario == "checkpoint replay (original launch unknown)")
	check("replay does not borrow another flight's launch snapshots", meta.launch_state == "[]"
		and meta.launch_aux == "[]" and meta.launch_ground_anchors == "[]"
		and meta.launch_field_id == "" and meta.launch_engine_running == "unknown" and meta.launch_error == "")
	var recorder := Recorder.new(destination.sim)
	recorder.start(meta)
	check("recording boundary remains the restored tick", recorder.trace.meta.recording_start_tick == 12
		and recorder.trace.value(0, "north_m") == source.sim.state[0]
		and recorder.trace.value(0, "down_m") == source.sim.state[2])
	recorder.detach()
	destination.reset()
	check("reset retains destination's selected recipe", destination.start_choice == destination_choice
		and destination.trace_meta().launch_choice == destination_choice
		and destination.trace_meta().selected_start_choice == destination_choice
		and destination.is_flyable())
	source.free()
	destination.free()

func _initialize() -> void:
	replay("runway", "airborne")
	replay("airborne", "runway")
	print("UI-06a-R1: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
