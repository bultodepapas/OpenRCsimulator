# Run with the pinned editor from an empty project, mounting one exported pack.
extends SceneTree

var failed := false

func check(label: String, ok: bool) -> void:
	if not ok:
		failed = true
		printerr("FAIL ", label)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not ProjectSettings.load_resource_pack(args[0], true):
		printerr("Could not mount exported pack")
		quit(1)
		return
	# Mounting a pack does not apply project.godot settings to the empty host. Use the app's 240 Hz contract.
	Engine.physics_ticks_per_second = 240
	ProjectSettings.set_setting("physics/common/physics_ticks_per_second", 240)
	# Dynamic loading happens after mounting; no source project can satisfy these resources.
	var session_script: Script = load("res://sim/flight_session.gd")
	var field_script: Script = load("res://data/field_loader.gd")
	if session_script == null or field_script == null:
		quit(1)
		return
	var field_result: Dictionary = field_script.load_from()
	check("pack field loads", field_result.get("ok", false))
	if failed:
		quit(1)
		return
	for source_choice in ["runway", "airborne"]:
		var destination_choice := "airborne" if source_choice == "runway" else "runway"
		var source: Node = session_script.new()
		var destination: Node = session_script.new()
		for flight: Node in [source, destination]:
			flight.setup()
			flight.input_enabled = false
			check("pack surfaces load", flight.set_field(field_result.field))
		source.start_choice = source_choice
		source.reset()
		destination.start_choice = destination_choice
		destination.reset()
		for tick in 12:
			source.sim.step()
		check("checkpoint restores", destination.restore_checkpoint(source.checkpoint()))
		check("physics boundary preserved", destination.sim.checkpoint() == source.sim.checkpoint())
		var meta: Dictionary = destination.trace_meta()
		check("pack contains UI-06a-R1", meta.launch_kind == "checkpoint_restore"
			and meta.launch_choice == "unknown" and meta.selected_start_choice == "unknown"
			and meta.launch_state == "[]" and meta.launch_aux == "[]"
			and meta.launch_engine_running == "unknown"
			and meta.scenario == "checkpoint replay (original launch unknown)")
		destination.reset()
		check("reset recipe preserved", destination.trace_meta().launch_choice == destination_choice)
		source.free()
		destination.free()
	print("Pack checkpoint origin: ", "FAIL" if failed else "PASS", " ", args[0])
	quit(1 if failed else 0)
