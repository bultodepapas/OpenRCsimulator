# In-memory malformed/implausible model probes; never write the aircraft JSON.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Session := preload("res://sim/flight_session.gd")
const Scenarios := preload("res://sim/scenarios.gd")

func _initialize() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Scenarios.AIRCRAFT))
	var excessive := raw.duplicate(true)
	excessive.aero.coefficients.Cndr.value *= 10.0
	var accepted := AD.validate_and_derive(excessive)
	var insufficient := raw.duplicate(true)
	insufficient.controls.max_throw.elevator.value = 1.0
	var data := AD.validate_and_derive(insufficient)
	assert(data.ok)
	var session := Session.new()
	session.setup()
	root.add_child(session)
	session._apply(data)
	session.reset()
	var result := {Cndr_times_10_accepted = accepted.ok, insufficient_elevator_data_ok = data.ok, insufficient_elevator_trim_ok = session.start.ok, insufficient_elevator_trim_message = session.start.message, insufficient_elevator_sim_paused = session.sim.paused, cg_inventory_le = Array(session.aircraft.model.cg_inventory_le), cg_flight_le = Array(session.aircraft.model.cg_le), inertia = Array(session.aircraft.model.inertia)}
	print("DATA_GUARD_PROBE ", JSON.stringify(result))
	var out := OS.get_environment("FLIGHT_AUDIT_OUT")
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		var file := FileAccess.open(out.path_join("guards.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t") + "\n")
	var failed: bool = not session.start.ok and not session.sim.paused
	session.free()
	quit(1 if failed else 0)
