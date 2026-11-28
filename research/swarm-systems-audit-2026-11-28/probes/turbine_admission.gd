extends SceneTree

const Aircraft := preload("res://physics/aircraft_data.gd")
const Flight := preload("res://sim/flight_session.gd")
const Turbine := preload("res://physics/turbine.gd")
const Field := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const CATALOG := "res://data/aircraft/sebart_avanti_s_a200.json"
const ID := "sebart-avanti-s-a200-p100rx"
const RUN_TICKS := 2400
var failures: int = 0
var checks: int = 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

# Use the normal top-level file loader, including the wheel profile and input identity.
func load_variant(raw: Dictionary, label: String) -> Dictionary:
	var path := "user://audit_turbine_%d_%s.json" % [OS.get_process_id(), label]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {ok = false}
	file.store_string(JSON.stringify(raw, "", true, true))
	file.close()
	var loaded := Aircraft.load_file(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return loaded

func session_run(label: String, data: Dictionary, should_fault: bool) -> void:
	var flight := Flight.new()
	flight.input_enabled = false
	check("selected reference backend", flight.setup_stage_backend("gdscript_reference"))
	flight.setup("synthetic://audit-turbine-" + label, ID, data)
	check(label + " completed normal setup", flight.is_flyable() and flight.liquid_fuel_is_active())
	if not flight.is_flyable():
		print("setup ", label, " error=", flight.start_error)
		flight.free()
		return
	var initial_rpm: float = flight.sim.continuous[0]
	flight.sim.inputs[3] = 1.0
	var before_rpm: float = initial_rpm
	var before_tick: int = flight.sim.tick
	var before_body := PackedByteArray()
	for iteration: int in RUN_TICKS:
		before_rpm = flight.sim.continuous[0]
		before_tick = flight.sim.tick
		before_body = flight.sim.state.to_byte_array()
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			break
	var faulted: bool = not flight.sim.fault_reason.is_empty()
	check(label + " full throttle result", faulted == should_fault)
	if should_fault:
		check("fault occurs during final half RPM", absf(154000.0 - before_rpm) < 0.5)
		check("refused RPM and body are uncommitted", flight.sim.tick == before_tick
			and flight.sim.continuous[0] == before_rpm and flight.sim.state.to_byte_array() == before_body)
	else:
		check("all requested ticks accepted", flight.sim.tick == RUN_TICKS)
	print("TURBINE_RUN ", label, " initial_rpm=", String.num(initial_rpm, 12), " tick=", flight.sim.tick,
		" rpm=", String.num(flight.sim.continuous[0], 12), " fault=", flight.sim.fault_reason)
	flight.free()

func runway_idle(label: String, data: Dictionary, expected_sign: float) -> void:
	var flight := Flight.new()
	flight.input_enabled = false
	check("runway reference backend", flight.setup_stage_backend("gdscript_reference"))
	flight.setup("synthetic://audit-intake-" + label, ID, data)
	var field: Dictionary = Field.load_from().field
	var spot := GroundStart.threshold(field)
	var field_ok := flight.is_flyable() and flight.set_field(field)
	check(label + " prepared runway field", field_ok)
	if field_ok:
		var start := flight.try_runway_start(spot.north, spot.east, spot.heading)
		check(label + " running runway idle admitted", start.ok)
		if start.ok:
			flight.sim.step()
			var endpoint := flight.turbine_state()
			check("one accepted idle tick", flight.sim.tick == 1 and endpoint.ok and endpoint.engine_running
				and endpoint.rpm == 44000.0 and flight.sim.fault_reason.is_empty())
			if endpoint.ok:
				check("runway endpoint reports expected flow and gross signs",
					endpoint.mass_flow_kg_s * expected_sign > 0.0 and endpoint.gross_thrust_n * expected_sign > 0.0)
				print("TURBINE_RUNWAY ", label, " rpm=", endpoint.rpm, " flow=", endpoint.mass_flow_kg_s,
					" gross_N=", endpoint.gross_thrust_n, " tick=", flight.sim.tick)
		else:
			print("TURBINE_RUNWAY refused ", label, " ", start.get("message", ""))
	flight.free()

func _initialize() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	var stock := Aircraft.load_file(CATALOG)
	var overspeed_raw: Dictionary = raw.duplicate(true)
	overspeed_raw.propulsion.engine.throttle_map.value[-1][1] = 154000.5
	var overspeed := load_variant(overspeed_raw, "governor")
	check("stock and +0.5 full records admitted", stock.ok and overspeed.ok)
	var outside_raw: Dictionary = raw.duplicate(true)
	outside_raw.propulsion.engine.throttle_map.value[-1][1] = 154001.5
	check("+1.5 RPM full record rejected", not load_variant(outside_raw, "outside").ok)
	var flow_raw: Dictionary = raw.duplicate(true)
	flow_raw.propulsion.engine.mass_flow.value = [[100000.0, 0.10], [150000.0, 0.20]]
	flow_raw.propulsion.engine.mass_flow.source = "Synthetic, positive two-point audit fixture"
	var flow_data := load_variant(flow_raw, "capture")
	check("two-row positive mass-flow record admitted", flow_data.ok)
	if stock.ok and flow_data.ok:
		for case: Array in [["stock", stock.model.propulsion, 44000.0, 0.06571],
				["custom_idle", flow_data.model.propulsion, 44000.0, -0.012],
				["custom_knot", flow_data.model.propulsion, 100000.0, 0.10]]:
			var prop: Dictionary = case[1]
			var rpm: float = case[2]
			var actual_flow := Turbine.mass_flow(rpm, prop, 1.225, 0.0)
			var gross := Turbine.gross_thrust(rpm, prop, 1.225, 0.0)
			var v_plus := PackedFloat64Array([0.0, 10.0, 0.0])
			var v_minus := PackedFloat64Array([0.0, -10.0, 0.0])
			var plus := Turbine.loads(v_plus, rpm, prop, 1.225)
			var minus := Turbine.loads(v_minus, rpm, prop, 1.225)
			check("axis perpendicular to test crossflow", prop.axis[1] == 0.0)
			check("capture flow at " + str(case[0]), absf(actual_flow - float(case[3])) < 1e-12)
			check("odd lateral capture force", absf(plus[1] + actual_flow * 10.0) < 1e-12 and plus[1] == -minus[1])
			check("static gross thrust sign", gross * actual_flow > 0.0)
			print("TURBINE_FLOW ", case[0], " rpm=", rpm, " kg_s=", String.num(actual_flow, 12),
				" gross_N=", String.num(gross, 12), " side_N=", String.num(plus[1], 12))
		runway_idle("stock", stock, 1.0)
		runway_idle("custom_flow", flow_data, -1.0)
	if stock.ok and overspeed.ok:
		session_run("stock", stock, false)
		session_run("max_plus_half", overspeed, true)
	print("TURBINE ADMISSION ", checks, " checks, ", failures, " failed")
	quit(1 if failures > 0 else 0)
