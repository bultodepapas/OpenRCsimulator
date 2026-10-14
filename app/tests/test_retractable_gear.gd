extends SceneTree

const Gear := preload("res://physics/retractable_gear.gd")
const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Sim := preload("res://sim/simulation.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Rig := preload("res://aircraft/retractable_model.gd")
const Geometry := preload("res://aircraft/avanti_s_blender_geometry.gd")
var checks := 0
var failures := 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL AV-09 ", label)


func actuator() -> void:
	var gear := {retraction = {extension_time = 2.5, retraction_time = 3.0, drag_area = 0.02, drag_center = M.v3(0.1, 0, 0.2)}}
	for hz in [120, 240, 480]:
		var value := 0.0
		for i in int(2.5 * hz): value = Gear.advance(value, 1.0, 1.0 / hz, gear)
		check("exact downlock at %d Hz" % hz, value == 1.0)
		for i in 3 * hz: value = Gear.advance(value, 0.0, 1.0 / hz, gear)
		check("exact stow at %d Hz" % hz, value == 0.0)
	check("reversal uses retraction rate", absf(Gear.advance(0.5, 0.0, 0.3, gear) - 0.4) < 1e-14)
	for bad in [NAN, -0.1, 1.1]: check("invalid actuator state rejected", is_nan(Gear.advance(bad, 1.0, 0.01, gear)))
	check("nonbinary target rejected", is_nan(Gear.advance(0.5, 0.5, 0.01, gear)))
	check("zero step rejected", is_nan(Gear.advance(0.5, 1.0, 0, gear)))
	var path := PackedFloat64Array([0, 1, 2, 2, 3, 4, 0, 1, 0])
	check("piecewise trajectory interpolation", Gear.path_point(path, 0.75) == PackedFloat64Array([1, 2, 2]))
	var state := RB.make_state(M.v3(0, 0, -20), M.v3(30, 0, 0), M.q_identity(), M.v3(0, 0, 0))
	var drag := Gear.drag_loads(state, M.v3(30, 0, 0), gear, 1, 1.225)
	check("analytical drag magnitude", absf(drag[0] + 11.025) < 1e-12)
	check("drag moment application point", M.norm(M.sub(drag.slice(3), M.cross(gear.retraction.drag_center, drag.slice(0, 3)))) < 1e-12)
	check("stowed drag is exactly absent", Gear.drag_loads(state, M.v3(30, 0, 0), gear, 0, 1.225).is_empty())
	state[RB.RATE + 1] = 2.0
	drag = Gear.drag_loads(state, M.v3(0, 0, 0), gear, 0.5, 1.225)
	check("rotational gear drag dissipates power", M.dot(drag.slice(3), state.slice(RB.RATE, RB.RATE + 3)) < 0)


func input_kernel() -> void:
	var sim := Sim.new()
	sim.input_size = 6
	sim.inputs = PackedFloat64Array([0, 0, 0, 0, 1, 0.4])
	var state := RB.make_state(M.v3(0, 0, -20), M.v3(30, 0, 0), M.q_identity(), M.v3(0, 0, 0))
	check("six inputs explicitly accepted", sim.reset(state))
	var cp := sim.checkpoint()
	sim.inputs = PackedFloat64Array([0, 0, 0, 0])
	sim.step()
	check("truncated demand fails atomically", sim.tick == 0 and sim.state == state and sim.inputs == cp.inputs and not sim.fault_reason.is_empty())
	check("extended checkpoint restores", sim.restore_checkpoint(cp))
	sim.input_size = 4
	check("wrong owner input layout rejects checkpoint", not sim.restore_checkpoint(cp))
	sim.free()


func contracts() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/sebart_avanti_s_a200.json"))
	for mutation in ["missing_path", "bad_endpoint", "unequal_knots", "nonfinite", "short_cycle", "negative_drag", "wrong_capability"]:
		var bad: Dictionary = raw.duplicate(true)
		match mutation:
			"missing_path": bad.landing_gear.contacts[0].erase("retraction_path")
			"bad_endpoint": bad.landing_gear.contacts[0].retraction_path.value[-1] += 0.01
			"unequal_knots": bad.landing_gear.contacts[0].retraction_path.value.resize(6)
			"nonfinite": bad.landing_gear.contacts[0].retraction_path.value[4] = NAN
			"short_cycle": bad.landing_gear.retraction.extension_time.value = 0.0
			"negative_drag": bad.landing_gear.retraction.drag_area.value = -1.0
			"wrong_capability": bad.capabilities.gear = "fixed_tricycle"
		check("physical contract rejects " + mutation, not AD.validate_and_derive(bad).ok)
	check("sampled rig is valid", Rig.validate(Geometry.DATA.gear).is_empty())
	for mutation in ["nonuniform", "rotation", "missing_carrier", "reused_helper", "missing_wheel_path"]:
		var bad: Dictionary = Geometry.DATA.gear.duplicate(true)
		match mutation:
			"nonuniform": bad.retraction.samples[1].extension = 0.9
			"rotation": bad.retraction.samples[1].nodes.MainGear_L_Pivot.rotation_wxyz = [0, 0, 0, 0]
			"missing_carrier": bad.retraction.samples[1].nodes.erase("MainGear_L_Pivot")
			"reused_helper": bad.wheels.right.spin_node = bad.wheels.left.spin_node
			"missing_wheel_path": bad.wheels.left.contact_model.pop_back()
		check("model contract rejects " + mutation, not Rig.validate(bad).is_empty())


func session() -> void:
	var flight := Flight.new()
	flight.setup(Catalog.entry("sebart-avanti-s-a200-p100rx").data)
	check("aircraft loads with continuous turbine and three wheels", flight.is_flyable() and flight.turbine_is_continuous() and flight.wheel_count() == 3)
	if not flight.is_flyable() or not flight.gear_is_retractable():
		flight.free()
		return
	check("airborne start stows gear", flight.gear_state().extension == 0 and flight.sim.inputs.size() == 6)
	check("deployment command accepted", flight.set_gear_down(true))
	flight.input_enabled = false
	flight.sim.inputs[4] = 1
	for i in 240: flight.sim.step()
	check("accepted ticks advance gear at declared rate", absf(flight.gear_state().extension - 0.4) < 1e-12)
	var cp: Dictionary = flight.checkpoint()
	check("mid-transit checkpoint is complete", not cp.is_empty() and cp.get("gear_law") == Gear.LAW)
	if cp.is_empty():
		flight.free()
		return
	flight.hold("gear test")
	flight._physics_process(1.0)
	check("pause holds actuator and accepted clock", flight.sim.tick == cp.simulation.tick and flight.sim.aux == cp.simulation.aux)
	flight.release("gear test")
	var evaluate: Callable = flight.sim.continuous_evaluate
	flight.sim.continuous_evaluate = func(_s: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> Dictionary:
		return {}
	flight.sim.step()
	check("rejected RK transaction rolls gear back", flight.sim.aux == cp.simulation.aux and flight.sim.tick == cp.simulation.tick and not flight.sim.fault_reason.is_empty())
	flight.sim.continuous_evaluate = evaluate
	check("recover rejected gear step", flight.restore_checkpoint(cp))
	for i in 120: flight.sim.step()
	var expected: Dictionary = flight.sim.checkpoint()
	check("mid-transit restore", flight.restore_checkpoint(cp))
	for i in 120: flight.sim.step()
	var repeated: Dictionary = flight.sim.checkpoint()
	for key in ["state", "aux", "continuous", "inputs", "modes", "tick", "last_loads"]:
		check("mid-transit exact continuation " + key, var_to_bytes(expected[key]) == var_to_bytes(repeated[key]))
	for field in ["gear_law", "gear_aux_index"]:
		var bad: Dictionary = cp.duplicate(true)
		bad.erase(field)
		check("missing gear checkpoint field rejected " + field, not flight.restore_checkpoint(bad))
	for bad_value in [-0.1, 1.1, NAN]:
		var bad: Dictionary = cp.duplicate(true)
		bad.simulation.aux[flight.gear_aux_index()] = bad_value
		check("invalid checkpoint deployment rejected", not flight.restore_checkpoint(bad))
	var invalid: Dictionary = cp.duplicate(true)
	invalid.simulation.inputs[5] = 2.0
	check("invalid checkpoint brake rejected", not flight.restore_checkpoint(invalid))
	flight.restore_checkpoint(cp)
	flight.sim.inputs[4] = 0
	for i in 240: flight.sim.step()
	check("reverse command retracts without reset", flight.gear_state().extension == 0)
	flight.reset()
	check("reset clears gear and brake", flight.gear_state().extension == 0 and flight.sim.inputs[5] == 0)
	var gear: Dictionary = flight.aircraft.model.landing_gear
	for fraction in [0.0, 0.4, 0.999]:
		var pose := Gear.pose(gear, fraction)
		for contact in pose.contacts:
			check("unlocked gear never supports weight", contact.stiffness == 0 and contact.damping == 0 and contact.max_compression == 0)
	check("downlock retains original calibrated contacts", var_to_bytes(Gear.pose(gear, 1)) == var_to_bytes(gear))
	flight.free()


func _initialize() -> void:
	actuator()
	input_kernel()
	contracts()
	session()
	print("AV-09 retractable gear: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
