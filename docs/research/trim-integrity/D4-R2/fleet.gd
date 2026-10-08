# D4-R2: same-build exact valid trim results and complete one-second flight boundaries.
# Run with --path app --script <this file> -- <output.bin>.
extends SceneTree
const AD = preload("res://physics/aircraft_data.gd")
const Trim = preload("res://physics/trim.gd")
const Flight = preload("res://sim/flight_session.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")


func _initialize() -> void:
	var results: Array = []
	var failed_trims: int = 0
	for id in ["jensen-das-ugly-stik-60", "gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx"]:
		var path: String = Catalog.entry(id).data
		var model: Dictionary = AD.load_file(path).model
		for factor in [0.85, 1.0, 1.15]:
			for mode in ["level", "glide"]:
				var speed: float = float(model.get("start_speed", 15.0)) * factor
				var result: Dictionary = Trim.solve(mode, speed, model, 9.80665, model.controls.throw_rad)
				if result.ok:
					results.append({aircraft = id, trim = result})
				else:
					failed_trims += 1
		var flight: Node = Flight.new()
		flight.setup(path)
		flight.input_enabled = false
		for tick in 240:
			flight.sim.step()
		var checkpoint: Dictionary = flight.checkpoint()
		if checkpoint.is_empty() or flight.sim.tick != 240 or not flight.sim.fault_reason.is_empty():
			printerr("FAIL flight boundary ", id)
			flight.free()
			quit(1)
			return
		results.append({aircraft = id, checkpoint = checkpoint})
		flight.free()
	var file: FileAccess = FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_buffer(var_to_bytes(results))
	file.close()
	print("D4-R2 fleet: ", results.size() - 4, " valid trims; ", failed_trims, " physical trim refusals; 4 complete flight checkpoints")
	quit(0)
