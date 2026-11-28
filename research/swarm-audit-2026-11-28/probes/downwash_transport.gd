# Run with the pinned engine and the repository's app project.
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const RECORD := "res://data/aircraft/jensen_ugly_stik_60.json"
const DT := 1.0 / 240.0


func _initialize() -> void:
	var stock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORD))
	var custom: Dictionary = stock.duplicate(true)
	custom.aero.surfaces.horizontal.position.value[0] = 0.0
	var test_path: String = get_script().resource_path.get_base_dir().path_join("downwash-input-%d.json" % OS.get_process_id())
	var file := FileAccess.open(test_path, FileAccess.WRITE)
	if file == null:
		print("DOWNWASH_TRANSPORT unable to write temporary input")
		quit(1)
		return
	file.store_string(JSON.stringify(custom, "", false, true))
	file.close()
	var control := sample(RECORD, stock.id)
	var altered := sample(test_path, custom.id)
	DirAccess.remove_absolute(test_path)
	print("DOWNWASH_TRANSPORT ", JSON.stringify({stock = control, custom = altered}))
	var reproduced: bool = control.get("bounded", false) and altered.get("grew", false) \
		and control.get("maneuver_end_tick", 0) == 40 and altered.get("maneuver_end_tick", 0) == 40 \
		and control.get("maneuver_fault", "missing").is_empty() \
		and altered.get("maneuver_fault", "missing").is_empty() \
		and absf(control.maneuver_samples[-1].error_mps) < 1.0 \
		and absf(altered.maneuver_samples[-1].error_mps) > 1.0e10
	quit(0 if reproduced else 1)


func sample(path: String, expected_id: String) -> Dictionary:
	var data := AircraftData.load_file(path)
	var result := {loader_ok = data.ok, loader_errors = Array(data.errors)}
	if not data.ok:
		return result
	var length_m: float = data.model.surfaces.horizontal.downwash_lag_length
	result["length_m"] = length_m
	var session := FlightSession.new()
	session.setup_stage_backend("gdscript_reference")
	session.setup(path, expected_id)
	root.add_child(session)
	session.input_enabled = false
	result["start_ok"] = session.start.get("ok", false)
	result["start_message"] = session.start.get("message", "")
	if not result.start_ok:
		session.free()
		return result
	var index: int = session.downwash_index()
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var aux: PackedFloat64Array = session.sim.aux.duplicate()
	var source: float = session._wing_cl(state, aux)
	var speed_mps: float = session.air_data(state).V
	aux[index] = source + 0.3
	var error_mps := PackedFloat64Array([aux[index] - source])
	for _tick in 8:
		aux = session._pre_step(aux, session.sim.inputs, DT)
		error_mps.append(aux[index] - source)
	result["airspeed_mps"] = speed_mps
	result["lag_error_mps"] = Array(error_mps)
	result["factor_per_tick"] = error_mps[1] / error_mps[0]
	result["analytic_factor"] = exp(-DT * speed_mps / length_m)
	result["bounded"] = absf(error_mps[8]) < absf(error_mps[0])
	result["grew"] = absf(error_mps[8]) > 100.0 * absf(error_mps[0])
	# The isolated sequence above uses a private copy. This second run starts at
	# the original settled trim and changes only the ordinary elevator input.
	var maneuver_input: PackedFloat64Array = session.sim.inputs.duplicate()
	maneuver_input[1] = clampf(maneuver_input[1] + 0.25, -1.0, 1.0)
	session.sim.inputs = maneuver_input
	var sample_ticks := [0, 1, 8, 16, 24, 32, 40]
	var maneuver: Array = []
	for requested_tick in 41:
		if requested_tick > 0:
			session.sim.step()
		if requested_tick in sample_ticks:
			var wing: float = session._wing_cl(session.sim.state, session.sim.aux)
			var tail_proxy: float = session.sim.aux[index]
			maneuver.append({tick = session.sim.tick, wing_mps = wing, lag_mps = tail_proxy,
					error_mps = tail_proxy - wing})
		if not session.sim.fault_reason.is_empty():
			break
	result["maneuver_elevator"] = maneuver_input[1]
	result["maneuver_samples"] = maneuver
	result["maneuver_end_tick"] = session.sim.tick
	result["maneuver_fault"] = session.sim.fault_reason
	session.free()
	return result
