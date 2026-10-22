extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const TICKS := 120


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var field: Dictionary = FieldLoader.load_from()
	var lake: Dictionary = LakeLoader.load_from()
	if not field.get("ok", false) or not lake.get("ok", false):
		printerr("field or lake fixture failed")
		quit(1)
		return
	var tape: Dictionary = {}
	for id: String in ["p51d-mustang-120", "gp-extra-300s-60", "stik-glow-61fx-2t"]:
		for regime: String in ["runway", "airborne"]:
			var session: Node = Flight.new()
			session.input_enabled = false
			session.crash_auto_restart = false
			session.soft_hull_contacts = true
			session.setup(Catalog.entry(id).data, id)
			if not session.set_field(field.field) or not session.set_lake_context(lake.lake):
				printerr("field/lake setup failed: ", id)
				quit(1)
				return
			session.start_choice = Flight.START_RUNWAY if regime == "runway" else Flight.START_AIRBORNE
			root.add_child(session)
			session.reset()
			if not session.start_error.is_empty():
				printerr("reset failed: ", id, "/", regime, ": ", session.start_error)
				quit(1)
				return
			if session.glow_is_active() and not session.engine_running:
				session.glow_start()
			var inputs: PackedFloat64Array = session.sim.inputs.duplicate()
			inputs[3] = 1.0
			session.sim.inputs = inputs
			var frames: Array[Dictionary] = [_snapshot(session)]
			for tick: int in TICKS:
				session.sim.step()
				frames.append(_snapshot(session))
				if not session.sim.fault_reason.is_empty():
					printerr("solver fault: ", id, "/", regime, " tick ", tick, ": ", session.sim.fault_reason)
					quit(1)
					return
			tape["%s/%s" % [id, regime]] = frames
			print("CLEAR_HULL_CASE ", id, "/", regime, " ticks=", session.sim.tick,
				" hull_points=", session._hull_contact.get("points", PackedFloat64Array()).size() / 3)
			session.queue_free()
			await process_frame
	var out: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out.is_empty():
		printerr("--out=<absolute path> is required")
		quit(2)
		return
	var file: FileAccess = FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		printerr("could not open output ", out)
		quit(2)
		return
	file.store_buffer(var_to_bytes(tape))
	file.close()
	print("CLEAR_HULL_PROBE bytes=", FileAccess.get_file_as_bytes(out).size())
	quit()


func _snapshot(session: Node) -> Dictionary:
	var sim: Node = session.sim
	return {tick = sim.tick, state = sim.state.duplicate(), continuous = sim.continuous.duplicate(),
		aux = sim.aux.duplicate(), inputs = sim.inputs.duplicate(), loads = sim.last_loads.duplicate(),
		events = sim.last_events.duplicate(true), fault = sim.fault_reason,
		engine_running = session.engine_running}
