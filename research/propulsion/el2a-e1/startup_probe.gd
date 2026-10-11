extends SceneTree

const Flight: Script = preload("res://sim/flight_session.gd")
const FieldLoader: Script = preload("res://data/field_loader.gd")
const GroundStart: Script = preload("res://physics/ground_start.gd")
const Ground: Script = preload("res://physics/ground_contact.gd")
const Commands: Script = preload("res://input/commands.gd")
const Propulsion: Script = preload("res://physics/propulsion.gd")
const RB: Script = preload("res://physics/rigid_body.gd")
var results: Dictionary = {}
var output_path: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_path = arg.trim_prefix("--output=")
	var field_result: Dictionary = FieldLoader.load_from()
	print("FIELD ok=", field_result.get("ok", false), " id=", field_result.get("field", {}).get("id", ""))
	if not field_result.get("ok", false):
		quit(2)
		return
	var field: Dictionary = field_result.field
	var spot: Dictionary = GroundStart.threshold(field)
	print("THRESHOLD ", spot)
	results = {
		"engine": Engine.get_version_info(),
		"field_id": field.get("id", ""),
		"threshold": spot,
		"fixtures": {},
	}
	for config: String in ["4s", "6s"]:
		_probe(config, field, spot)
	if not output_path.is_empty():
		var output: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		if output == null:
			push_error("Cannot write probe JSON: " + output_path)
			quit(3)
			return
		output.store_string(JSON.stringify(results, "\t", false, true) + "\n")
		output.close()
		print("JSON_RESULT ", output_path)
	quit(0)

func _probe(config: String, field: Dictionary, spot: Dictionary) -> void:
	var flight: Node = Flight.new()
	flight.setup("res://data/aircraft/synthetic_stik_electric_%s_battery.json" % config)
	root.add_child(flight)
	flight.input_enabled = false
	var fixture: Dictionary = {
		"fixture": "synthetic_stik_electric_%s_battery" % config,
		"flyable": flight.is_flyable(),
		"model_id": flight.aircraft.get("model", {}).get("id", ""),
		"anchor_count": flight.anchor_count(),
	}
	results.fixtures[config] = fixture
	print("FIXTURE ", config, " flyable=", flight.is_flyable(), " model=", flight.aircraft.get("model", {}).get("id", ""), " anchors=", flight.anchor_count())
	fixture["set_field"] = flight.set_field(field)
	print("SET_FIELD ", fixture.set_field)
	var equilibrium: Dictionary = Propulsion.steady_operating_point(0.0, 0.0, flight.aircraft.model.propulsion, flight.air_density())
	var idle_rpm: float = Propulsion.steady_rpm(0.0, 0.0, flight.aircraft.model.propulsion, flight.air_density())
	fixture["zero_duty_equilibrium_status"] = equilibrium.get("status", "")
	fixture["zero_duty_equilibrium_ok"] = equilibrium.get("ok", false)
	fixture["zero_duty_steady_rpm_finite"] = is_finite(idle_rpm)
	fixture["zero_duty_steady_rpm"] = idle_rpm if is_finite(idle_rpm) else null
	print("IDLE_EQUILIBRIUM ", config, " rpm=", idle_rpm, " operating=", equilibrium)
	var helper_ok: bool = flight.reset_on_runway(float(spot.north), float(spot.east), float(spot.heading))
	fixture["public_runway_reset_ok"] = helper_ok
	fixture["public_runway_start_error"] = flight.start_error
	fixture["public_runway_fault"] = flight.sim.fault_reason
	print("PUBLIC_RUNWAY ", config, " ok=", helper_ok, " start_error=", flight.start_error, " fault=", flight.sim.fault_reason, " tick=", flight.sim.tick, " z=", flight.sim.state[RB.POS + 2], " rpm=", flight.sim.aux[0], " launch=", flight._launch_metadata)
	if helper_ok:
		_run_idle_then_start(flight, config, "public", fixture)
	else:
		var prepared_ok: bool = _prepare_zero_rpm_runway(flight, spot)
		fixture["manual_zero_rpm_runway_ok"] = prepared_ok
		fixture["manual_zero_rpm_runway_fault"] = flight.sim.fault_reason
		print("MANUAL_ZERO_RPM_RUNWAY ", config, " ok=", prepared_ok, " fault=", flight.sim.fault_reason, " tick=", flight.sim.tick, " state_z=", flight.sim.state[RB.POS + 2])
		if prepared_ok:
			_run_idle_then_start(flight, config, "manual", fixture)
	flight.free()

func _prepare_zero_rpm_runway(flight: Node, spot: Dictionary) -> bool:
	if not flight._reset_airborne_start():
		return false
	flight.commands = Commands.neutral_commands()
	flight.commands.throttle = 0.0
	flight.engine_running = true
	flight.sim.inputs = flight._inputs()
	var aux: PackedFloat64Array = PackedFloat64Array([0.0, flight.sim.inputs[0], flight.sim.inputs[1], flight.sim.inputs[2]])
	flight.sim.aux = aux
	var solved: Dictionary = GroundStart.solve(flight.aircraft.model, flight.ground_surfaces,
		float(spot.north), float(spot.east), float(spot.heading), flight._deflections(aux),
		flight.sim.inputs[2], 0.0, flight.air_density(), flight.sim.gravity, flight._initial_wind())
	if not solved.get("ok", false):
		print("MANUAL_SOLVE_FAILURE ", solved)
		return false
	aux.append_array(solved.anchors)
	if flight.downwash_index() >= 0:
		aux.append(0.0)
	aux.append_array(flight._restart_weather_aux())
	flight.sim.aux = aux
	if flight.downwash_index() >= 0:
		aux[flight.downwash_index()] = flight._wing_cl(solved.state, aux, 0.0)
	flight.sim.aux = aux
	flight.sim.continuous = flight._settled_continuous(solved.state, aux)
	if not flight.sim.reset(solved.state):
		print("MANUAL_RESET_FAILURE ", flight.sim.fault_reason)
		return false
	return true

func _run_idle_then_start(flight: Node, config: String, route: String, fixture: Dictionary) -> void:
	var before: Dictionary = flight.electrical_state()
	var start_pos: PackedFloat64Array = flight.sim.state.slice(RB.POS, RB.POS + 3)
	flight.sim.inputs[3] = 0.0
	var idle_ok: bool = _advance(flight, 120)
	var idle_state: Dictionary = flight.electrical_state()
	fixture["route_used"] = route
	fixture["zero_duty_0_5s"] = {
		"advanced": idle_ok,
		"fault": flight.sim.fault_reason,
		"rpm": flight.sim.aux[0],
		"motor_current_a": idle_state.get("motor_current_a", NAN),
		"pack_current_a": idle_state.get("pack_current_a", NAN),
		"charge_drop_c": before.get("remaining_charge_c", NAN) - idle_state.get("remaining_charge_c", NAN),
		"remaining_charge_c": idle_state.get("remaining_charge_c", NAN),
		"terminal_energy_j": idle_state.get("terminal_energy_j", NAN),
		"pack_heat_j": idle_state.get("pack_heat_j", NAN),
	}
	print("ZERO_DUTY ", config, " route=", route, " advanced=", idle_ok, " fault=", flight.sim.fault_reason,
		" rpm=", flight.sim.aux[0], " motor_a=", idle_state.get("motor_current_a", NAN),
		" pack_a=", idle_state.get("pack_current_a", NAN), " charge_drop_c=", before.get("remaining_charge_c", NAN) - idle_state.get("remaining_charge_c", NAN),
		" energy_j=", idle_state.get("terminal_energy_j", NAN), " heat_j=", idle_state.get("pack_heat_j", NAN))
	flight.sim.inputs[3] = 1.0
	var startup_ok: bool = _advance(flight, 120)
	var started: Dictionary = flight.electrical_state()
	var speed: float = sqrt(flight.sim.state[RB.VEL] ** 2 + flight.sim.state[RB.VEL + 1] ** 2 + flight.sim.state[RB.VEL + 2] ** 2)
	var moved: float = sqrt((flight.sim.state[RB.POS] - start_pos[0]) ** 2 + (flight.sim.state[RB.POS + 1] - start_pos[1]) ** 2 + (flight.sim.state[RB.POS + 2] - start_pos[2]) ** 2)
	fixture["startup_0_5s"] = {
		"advanced": startup_ok,
		"fault": flight.sim.fault_reason,
		"rpm": flight.sim.aux[0],
		"speed_mps": speed,
		"moved_m": moved,
		"motor_current_a": started.get("motor_current_a", NAN),
		"pack_current_a": started.get("pack_current_a", NAN),
		"remaining_charge_c": started.get("remaining_charge_c", NAN),
		"soc": started.get("soc", NAN),
		"terminal_energy_j": started.get("terminal_energy_j", NAN),
		"pack_heat_j": started.get("pack_heat_j", NAN),
	}
	print("STARTUP_0.5S ", config, " route=", route, " advanced=", startup_ok, " fault=", flight.sim.fault_reason,
		" rpm=", flight.sim.aux[0], " speed_mps=", speed, " moved_m=", moved,
		" motor_a=", started.get("motor_current_a", NAN), " bus_a=", started.get("pack_current_a", NAN),
		" charge_c=", started.get("remaining_charge_c", NAN), " soc=", started.get("soc", NAN),
		" terminal_j=", started.get("terminal_energy_j", NAN), " heat_j=", started.get("pack_heat_j", NAN))

func _advance(flight: Node, count: int) -> bool:
	for _i: int in count:
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			return false
	return true





