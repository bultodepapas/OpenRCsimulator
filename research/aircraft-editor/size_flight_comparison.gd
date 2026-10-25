extends SceneTree
## AE-23a: replay a baseline tape against authentic frozen Workshop models.
## Raw aircraft JSON alone loses compiler-inherited wheel profiles.
const Session := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Trial := preload("res://workshop/trial.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var baseline := ""
	var out := ""
	var extreme := false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--extreme": extreme = true
		if arg.begins_with("--baseline="): baseline = arg.trim_prefix("--baseline=")
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if baseline.is_empty() or out.is_empty():
		push_error("Required --baseline=<complete.orfl> --out=<new-directory>")
		quit(1)
		return
	if DirAccess.dir_exists_absolute(out):
		push_error("Evidence directory already exists.")
		quit(1)
		return
	var checked := Reader.inspect(baseline)
	if not checked.ok or not checked.complete:
		push_error("A complete validated baseline is required.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var header: Dictionary = checked.header
	Engine.physics_ticks_per_second = roundi(1.0 / float(header.dt_s))
	var bytes := FileAccess.get_file_as_bytes("res://data/aircraft/jensen_ugly_stik_60.json")
	var report := {"baseline_sha256": FileAccess.get_sha256(baseline),
		"baseline_solver_sha256": header.solver_sha256, "current_solver_sha256": Log.solver_identity(),
		"solver_changed": header.solver_sha256 != Log.solver_identity(),
		"method": "Open-loop, baseline body/internal initial state and exact post-conditioning tape; authentic frozen Workshop mass/inertia/configuration. Not physical validation or equivalence.",
		"candidates": []}
	var passed := true
	for scale: float in ([0.1, 1.0, 5.0] if extreme else [0.35, 2.25]):
		var recipe := {"scale": scale}
		if extreme: recipe.size_model = "virtual_similarity_v1"
		var frozen := Trial.freeze({"base_id": "jensen-das-ugly-stik-60", "base_bytes": bytes, "recipe": recipe})
		var result := {"scale": scale, "ok": false, "complete": false, "errors": Array(frozen.errors)}
		if frozen.ok:
			result.identity = frozen.identity
			var flight := Session.new()
			flight.physics_enabled = true
			flight.input_enabled = false
			flight.crash_auto_restart = false
			flight.soft_hull_contacts = header.soft_hull_contacts
			flight.setup(header.aircraft_path, "", frozen.data)
			flight.ground_surfaces = header.ground_surfaces.duplicate()
			flight.airframe_surfaces = header.get("airframe_surfaces", PackedFloat64Array()) # GP-07c
			flight.ground_field_id = header.ground_field_id
			var ready: bool = flight.setup_shaft_integrator(header.shaft_integrator) \
				and flight.setup_weather(header.weather) and flight.set_collision_world(header.collision_world) and flight.set_lake_context(header.lake)
			flight.reset()
			var checkpoint: Dictionary = header.checkpoint.duplicate(true)
			var candidate_checkpoint: Dictionary = flight.checkpoint()
			if candidate_checkpoint.is_empty(): ready = false
			else:
				checkpoint.configuration = candidate_checkpoint.configuration
				for key: String in ["mass", "inertia", "gravity"]:
					checkpoint.simulation[key] = candidate_checkpoint.simulation[key]
			ready = ready and flight.restore_checkpoint(checkpoint)
			if ready:
				var path := out.path_join("size-%d.orfl" % roundi(scale * 100.0))
				var logger := Log.new(flight)
				ready = logger.start(path) == OK
				if ready:
					var tape := FileAccess.open(baseline, FileAccess.READ)
					tape.seek(8)
					Log.read_packet(tape)
					var first := true
					while tape.get_position() < tape.get_length() and ready:
						var packet := Log.read_packet(tape)
						if not packet.ok:
							ready = false
							break
						if packet.value.kind == "footer": break
						for row: Dictionary in packet.value.rows:
							if first:
								first = false
								continue
							for key: String in row.intervention:
								flight.sim.set(key, row.intervention[key].duplicate())
							flight.sim.inputs = row.inputs.duplicate()
							flight.sim.step()
							if flight.sim.tick == 121: logger.mark("bounded roll pulse; copied baseline tape")
							if not flight.sim.fault_reason.is_empty() or flight.sim.tick != row.tick:
								ready = false
								break
					tape.close()
					logger.stop()
					var recorded := Reader.inspect(path)
					result.complete = recorded.ok and recorded.get("complete", false)
					result.final_tick = flight.sim.tick
					result.fault = flight.sim.fault_reason
					result.log_sha256 = FileAccess.get_sha256(path)
					result.ok = ready and result.complete and flight.sim.tick == checked.footer.final_tick
			else:
				result.errors.append("Baseline checkpoint incompatible with frozen candidate.")
			flight.free()
		passed = passed and bool(result.ok)
		report.candidates.append(result)
	var output := FileAccess.open(out.path_join("comparison-recording.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t", true, true))
	output.close()
	print("AE-23a authentic candidate recordings: ", passed)
	quit(0 if passed else 1)
