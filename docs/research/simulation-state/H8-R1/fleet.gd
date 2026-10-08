# H8-R1: same-build full-state fingerprints before and after restoration hardening.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
func _initialize() -> void:
	var rows: Array = []
	for id in ["jensen-das-ugly-stik-60", "gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx"]:
		var flight: Node = Flight.new()
		flight.setup(Catalog.entry(id).data)
		flight.input_enabled = false
		for tick in 120:
			flight.sim.inputs[0] = 0.2
			flight.sim.step()
		var cp: Dictionary = flight.checkpoint()
		assert(not cp.is_empty())
		rows.append(cp)
		for tick in 120:
			flight.sim.inputs[1] = -0.1
			flight.sim.step()
		var expected: Dictionary = flight.checkpoint()
		assert(flight.restore_checkpoint(bytes_to_var(var_to_bytes(cp))))
		for tick in 120:
			flight.sim.inputs[1] = -0.1
			flight.sim.step()
		assert(var_to_bytes(flight.checkpoint()) == var_to_bytes(expected))
		rows.append(expected)
		flight.free()
	var file: FileAccess = FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	file.store_buffer(var_to_bytes(rows))
	file.close()
	print("H8-R1: four aircraft; eight complete checkpoints; four exact continuations")
	quit()
