# G2a/G2b experimental shaft integration contract: stage-local RPM, locked-body coupling,
# exact checkpoint identity, and unchanged split/no-shaft paths.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const SimKernel := preload("res://sim/simulation.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AD := preload("res://physics/aircraft_data.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const Prop := preload("res://physics/propulsion.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Wind := preload("res://physics/wind_config.gd")
const WashFixture := preload("res://tests/test_wash_profile.gd")
const Trace := preload("res://sim/trace.gd")
const LiquidFlight := preload("res://sim/liquid_fuel_flight.gd")

const P51_ID := "p51d-mustang-120"
const P51_PATH := "res://data/aircraft/p51d_mustang_120.json"
const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"

var checks := 0
var failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print(("ok " if ok else "FAIL ") + label + (" — " + detail if not detail.is_empty() else ""))
	if not ok:
		failures += 1


func _new_flight(mode: String = "auto", path: String = P51_PATH, weather: Dictionary = {}) -> Node:
	var flight: Node = Flight.new()
	if not weather.is_empty():
		if not flight.setup_weather(weather):
			flight.free()
			return null
	if mode != "auto" and not flight.setup_shaft_integrator(mode):
		flight.free()
		return null
	flight.setup(path)
	flight.input_enabled = false
	return flight


## Rebuild the pre-FUEL-08 prescribed-fuel P-51 contract in memory from the accepted v11 aircraft input.
## The structure and wet aircraft balance stay intact; only the dynamic consumption adapter is disabled.
func _legacy_static_fuel_p51(mode: String = "auto") -> Node:
	var raw_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(P51_PATH))
	if not raw_value is Dictionary:
		return null
	var raw: Dictionary = raw_value
	raw.propulsion.erase("fuel_consumption")
	raw.capabilities.energy = "prescribed_fuel"
	var checked: Dictionary = AD.validate_and_derive(raw)
	if not checked.get("ok", false):
		return null
	var profiled: Dictionary = WheelProfiles.apply_to_model(checked.model)
	if not profiled.get("ok", false):
		return null
	checked.model = profiled.model
	checked.wheel_profile_identity = profiled.identity
	var flight: Node = Flight.new()
	# setup() creates the simulation before _apply() refits the in-memory legacy contract.
	flight.setup(P51_PATH)
	if not flight._apply(checked):
		flight.free()
		return null
	if mode != "auto" and not flight.setup_shaft_integrator(mode):
		flight.free()
		return null
	flight.input_enabled = false
	flight.reset()
	return flight


## The standalone shaft helpers accept the propulsion/wheel prefix. FUEL-08 appends its two owned slots afterward.
func _shaft_values(flight: Node, values: PackedFloat64Array) -> PackedFloat64Array:
	return values.slice(0, flight._liquid_index()) if flight.liquid_fuel_is_active() else values.duplicate()


func _coupled_fixture(transport: bool = false, weather: Dictionary = {}) -> Node:
	var flight: Node = _new_flight("coupled-rk4", P51_PATH, weather)
	if flight == null or not flight.is_flyable():
		return flight
	if transport:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(P51_PATH))
		var wash_raw: Dictionary = WashFixture.combined_raw().propulsion.propeller.slipstream
		wash_raw.transport_speed_floor = WashFixture.quantity(1.0, "m/s")
		raw.propulsion.propeller.thrust_angles = WashFixture.quantity([0.0, 0.0], "deg")
		raw.propulsion.propeller.slipstream = wash_raw
		var checked: Dictionary = AD.validate_and_derive(raw)
		_check("P-51 test-only transported wash fixture validates", checked.ok, str(checked.errors))
		if not checked.ok:
			flight.free()
			return null
		var profiled: Dictionary = WheelProfiles.apply_to_model(checked.model)
		if not profiled.ok:
			_check("P-51 test-only transported wash fixture applies current wheel profile", false, str(profiled.errors))
			flight.free()
			return null
		checked.model = profiled.model
		checked.wheel_profile_identity = profiled.identity
		var wheel_profile: Dictionary = profiled.model.get("wheel_profile", {})
		_check("P-51 transported-wash fixture retains the applied wheel profile",
			wheel_profile.get("status", "") == "applied" and wheel_profile.get("aircraft_id", "") == P51_ID)
		if not flight._apply(checked):
			flight.free()
			return null
		flight.reset()
	return flight


func _advance(flight: Node, count: int, throttle: float = 0.68) -> void:
	for i: int in count:
		flight.sim.inputs[0] = 0.08 if i % 30 < 15 else -0.04
		flight.sim.inputs[1] = -0.03
		flight.sim.inputs[2] = 0.02
		flight.sim.inputs[3] = throttle
		flight.sim.step()


func _dynamic_bits(sim: Node) -> PackedByteArray:
	var dynamic: Dictionary = {
		"state": sim.state,
		"previous": sim.previous,
		"continuous": sim.continuous,
		"aux": sim.aux,
		"inputs": sim.inputs,
		"modes": sim.modes,
		"last_loads": sim.last_loads,
		"tick": sim.tick,
		"stop_at_tick": sim.stop_at_tick,
		"mass": sim.mass,
		"inertia": sim.inertia,
		"gravity": sim.gravity,
		"fixed_dt": sim._fixed_dt,
	}
	return var_to_bytes(dynamic)


func _torque_closure(flight: Node, label: String) -> void:
	var prop: Dictionary = flight.aircraft.model.propulsion
	var sim: Node = flight.sim
	var state: PackedFloat64Array = sim.state.duplicate()
	var continuous: PackedFloat64Array = _shaft_values(flight, sim.continuous)
	var shaft_index: int = flight._rotor_index()
	var rpm: float = continuous[shaft_index]
	var time_s: float = sim.time()
	var loads: PackedFloat64Array = flight._coupled_loads(state, continuous, time_s)
	var h: PackedFloat64Array = flight._coupled_rotor(state, continuous, time_s)
	var derivative: PackedFloat64Array = RB.derivative(state, sim.mass, sim.inertia,
		RB.inertia_inverse(sim.inertia), M.v3(loads[0], loads[1], loads[2]),
		M.v3(loads[3], loads[4], loads[5]), sim.gravity, h)
	var shaft: PackedFloat64Array = flight._coupled_derivative(state, continuous, time_s)
	var air: Dictionary = flight.air_data(state, time_s)
	var axis: PackedFloat64Array = Prop.axis(prop)
	var axial_speed: float = M.dot(air.v_air, axis)
	var engine: float
	if flight.engine_running:
		engine = Prop.engine_torque(rpm, sim.inputs[3], prop, flight.engine_charge_ratio())
	else:
		var friction: PackedFloat64Array = prop.shaft.friction
		engine = -float(friction[0]) - float(friction[1]) * rpm / 1000.0
	var prop_torque: float = Prop.prop_torque(rpm, axial_speed, prop, flight.air_density())
	var applied_shaft_torque: float = engine - prop_torque
	var body_alpha: PackedFloat64Array = derivative.slice(RB.RATE, RB.RATE + 3)
	var lhs: float = float(prop.rotor_inertia) * (shaft[shaft_index] * TAU / 60.0 + M.dot(axis, body_alpha))
	var error: float = absf(lhs - applied_shaft_torque)
	_check(label, is_finite(lhs) and is_finite(applied_shaft_torque) and error < 2e-7 * maxf(1.0, absf(applied_shaft_torque)),
		"I*(Omega_dot + axis·body_alpha)=Q_engine-Q_prop; residual " + String.num_scientific(error) + " N·m")


func _mode_and_legacy_paths() -> void:
	var finite_p51: Node = _new_flight("auto")
	var explicit_coupled: Node = _new_flight("coupled-rk4")
	_check("finite-fuel P-51 v11 selects coupled RK4 by default",
		finite_p51 != null and finite_p51.liquid_fuel_is_active() and finite_p51.shaft_integrator() == "coupled-rk4")
	_check("finite-fuel P-51 accepts explicit coupled RK4",
		explicit_coupled != null and explicit_coupled.liquid_fuel_is_active() and explicit_coupled.shaft_is_coupled())
	if finite_p51 != null and explicit_coupled != null:
		_advance(finite_p51, 80)
		_advance(explicit_coupled, 80)
		_check("default and explicit v11 coupled trajectories stay byte-identical",
			var_to_bytes(finite_p51.sim.checkpoint()) == var_to_bytes(explicit_coupled.sim.checkpoint()))
	var split_candidate: Node = _new_flight("auto")
	if split_candidate != null:
		var before_split: PackedByteArray = _dynamic_bits(split_candidate.sim)
		var rejected_split: bool = split_candidate.setup_shaft_integrator("split")
		_check("finite-fuel P-51 rejects split mode without mutation",
			not rejected_split and split_candidate.shaft_integrator() == "coupled-rk4"
			and before_split == _dynamic_bits(split_candidate.sim), split_candidate.shaft_error)
		split_candidate.free()
	var legacy_default: Node = _legacy_static_fuel_p51("auto")
	var legacy_split: Node = _legacy_static_fuel_p51("split")
	_check("legacy static-fuel P-51 keeps split default and accepts explicit split",
		legacy_default != null and not legacy_default.liquid_fuel_is_active()
		and legacy_default.shaft_integrator() == "split" and legacy_split != null
		and not legacy_split.liquid_fuel_is_active() and legacy_split.shaft_integrator() == "split")
	if legacy_default != null and legacy_split != null:
		_advance(legacy_default, 80)
		_advance(legacy_split, 80)
		_check("legacy default and explicit split trajectories stay byte-identical",
			var_to_bytes(legacy_default.sim.checkpoint()) == var_to_bytes(legacy_split.sim.checkpoint()))
	var stik: Node = _new_flight("split", STIK_PATH)
	var stik_before: PackedByteArray = _dynamic_bits(stik.sim)
	_check("no-shaft Stik refuses coupled-rk4", not stik.setup_shaft_integrator("coupled-rk4")
		and stik.shaft_integrator() == "split" and _dynamic_bits(stik.sim) == stik_before)
	var stik_reference: Node = _new_flight("split", STIK_PATH)
	_advance(stik, 35)
	_advance(stik_reference, 35)
	_check("rejected mode leaves no-shaft flight trajectory unchanged",
		var_to_bytes(stik.sim.checkpoint()) == var_to_bytes(stik_reference.sim.checkpoint()))
	for flight: Node in [finite_p51, explicit_coupled, legacy_default, legacy_split, stik, stik_reference]:
		if flight != null:
			flight.free()


func _coupling_physics() -> void:
	var flight: Node = _coupled_fixture()
	_check("P-51 coupled state keeps RPM before appended wheel speeds", flight != null and flight.is_flyable()
		and flight.liquid_fuel_is_active() and flight.shaft_is_coupled()
		and flight.sim.continuous.size() == flight._rotor_index() + 1 + flight.wheel_count() + 2
		and flight.sim.continuous[flight._rotor_index()] == flight.sim.aux[0])
	if flight == null:
		return
	var prop: Dictionary = flight.aircraft.model.propulsion
	var rpm: float = maxf(float(prop.idle_rpm) + 25.0, 1000.0)
	var shaft_values: PackedFloat64Array = _shaft_values(flight, flight.sim.continuous)
	shaft_values[flight._rotor_index()] = rpm
	flight.sim.continuous[flight._rotor_index()] = rpm
	flight.sim.aux[0] = rpm
	flight.sim.inputs[3] = 1.0
	flight.engine_running = true
	_check("high-throttle punch starts the relative rotor accelerating",
		flight._coupled_response(flight.sim.state, shaft_values, 0.0).get("rpm_rate", NAN) > 0.0)
	var z: PackedFloat64Array = shaft_values
	var body: PackedFloat64Array = flight.sim.state.duplicate()
	var at_time: float = flight.sim.time()
	var coupled_loads: PackedFloat64Array = flight._coupled_loads(body, z, at_time)
	var prefix: PackedFloat64Array = z.slice(0, flight._rotor_index())
	var lag: int = flight.downwash_index()
	var downwash: float = flight.sim.aux[lag] if lag >= 0 and lag < flight.sim.aux.size() else NAN
	var external: PackedFloat64Array = Dynamics.loads(body, flight.aircraft.model, flight._deflections(flight.sim.aux),
		rpm, flight.air_density(), flight.wind_at(at_time), downwash, prefix)
	var ground_result: Dictionary = Ground.evaluate(body, flight.aircraft.model.landing_gear,
		flight.sim.aux[Flight.AUX_SERVO + 2], flight.ground_surfaces,
		flight.sim.aux.slice(Flight.AUX_ANCHORS, Flight.AUX_ANCHORS + flight.anchor_count() * Ground.ANCHOR_STRIDE),
		z.slice(flight.wheel_index(), flight.wheel_index() + flight.wheel_count()), 0.0, false)
	var ground: PackedFloat64Array = ground_result.get("loads", PackedFloat64Array())
	for i: int in ground.size():
		external[i] += ground[i]
	var response: PackedFloat64Array = flight._coupled_derivative(body, z, at_time)
	var axis: PackedFloat64Array = Prop.axis(prop)
	var relative_spin_accel: float = response[flight._rotor_index()] * TAU / 60.0
	var added_moment: PackedFloat64Array = M.sub(coupled_loads.slice(3, 6), external.slice(3, 6))
	var expected_reaction: PackedFloat64Array = M.scale(axis, -float(prop.rotor_inertia) * relative_spin_accel)
	var reaction_error: float = 0.0
	for i: int in 3:
		reaction_error = maxf(reaction_error, absf(added_moment[i] - expected_reaction[i]))
	_check("first-punch relative-spin reaction is added once over external loads",
		relative_spin_accel > 0.0 and M.dot(axis, added_moment) < 0.0
		and reaction_error < 2e-7, "reaction residual " + String.num_scientific(reaction_error) + " N·m")
	_torque_closure(flight, "running torque, body coupling and friction close algebraically")
	flight.engine_running = false
	_torque_closure(flight, "engine-off closure includes mechanical friction once")
	flight.free()


func _stopped_combustion_lock_and_cutoff() -> void:
	var glide: Node = _coupled_fixture()
	if glide == null or not glide.trim_at(18.0, "glide").get("ok", false):
		_check("engine-off glide trim fixture starts", false)
		if glide != null:
			glide.free()
		return
	glide.reset()
	var shaft_index: int = glide._rotor_index()
	_check("power-off trim resets at zero relative shaft RPM", not glide.engine_running
		and glide.sim.modes[0] == 0 and glide.sim.continuous[shaft_index] == 0.0)
	glide.sim.inputs[1] = 0.21906288707026 # Match the P-51 pitch command at the failing first RK tick.
	var direct: Dictionary = glide._coupled_response(glide.sim.state, _shaft_values(glide, glide.sim.continuous), glide.sim.time())
	var direct_rate: float = float(direct.get("rpm_rate", NAN))
	var axis: PackedFloat64Array = Prop.axis(glide.aircraft.model.propulsion)
	var shaft_values: PackedFloat64Array = _shaft_values(glide, glide.sim.continuous)
	var loads: PackedFloat64Array = direct.get("loads", PackedFloat64Array())
	var required: float = NAN
	if direct.get("ok", false) and loads.size() == 6:
		var momentum: PackedFloat64Array = glide._coupled_rotor(glide.sim.state, shaft_values, glide.sim.time())
		var body_derivative: PackedFloat64Array = RB.derivative(glide.sim.state, glide.sim.mass, glide.sim.inertia,
			RB.inertia_inverse(glide.sim.inertia), M.v3(loads[0], loads[1], loads[2]),
			M.v3(loads[3], loads[4], loads[5]), glide.sim.gravity, momentum)
		required = float(glide.aircraft.model.propulsion.rotor_inertia) * (direct_rate * TAU / 60.0
			+ M.dot(axis, body_derivative.slice(RB.RATE, RB.RATE + 3)))
	var static_bound: float = float(glide.aircraft.model.propulsion.shaft.friction[0])
	_check("resting engine-off coupling uses only bounded zero-speed shaft friction",
		direct.get("ok", false) and absf(direct_rate) < 1e-10 and is_finite(required)
		and absf(required) <= static_bound + 1e-9,
		"required %s N·m; authored bound %s N·m" % [String.num_scientific(required), String.num_scientific(static_bound)])
	var reverse_state: PackedFloat64Array = glide.sim.state.duplicate()
	reverse_state[RB.RATE + 1] = 100.0
	reverse_state[RB.RATE + 2] = -100.0
	var before_reverse: PackedByteArray = _dynamic_bits(glide.sim)
	var reverse_demand: Dictionary = glide._coupled_response(reverse_state, shaft_values, glide.sim.time())
	_check("stopped engine-off shaft refuses reverse breakaway beyond authored friction",
		not reverse_demand.get("ok", false) and before_reverse == _dynamic_bits(glide.sim), str(reverse_demand))
	var stages: Array[float] = []
	var real_stage: Callable = glide.sim.model.stage
	glide.sim.model.stage = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
		stages.append(z[shaft_index])
		return real_stage.call(s, z, t)
	glide.sim.step()
	glide.sim.model.stage = real_stage
	_check("zero-RPM power-off glide accepts all four coupled RK stages",
		glide.sim.tick == 1 and glide.sim.fault_reason.is_empty() and stages.size() == 4
		and stages.all(func(rpm: float) -> bool: return is_finite(rpm) and rpm >= 0.0),
		"stages %s; fault '%s'" % [str(stages), glide.sim.fault_reason])
	glide.free()

	var rundown: Node = _coupled_fixture()
	if rundown == null or not rundown.trim_at(18.0, "glide").get("ok", false):
		_check("positive-RPM engine-off cutoff fixture starts", false)
		if rundown != null:
			rundown.free()
		return
	rundown.reset()
	var cutoff_index: int = rundown._rotor_index()
	var liquid_index: int = rundown._liquid_index()
	var fuel_config: Dictionary = rundown.aircraft.model.propulsion.liquid_fuel
	var full_usable_fuel: float = float(fuel_config.capacity_kg) - float(fuel_config.unusable_kg)
	_check("engine-off cutoff sweep starts with full usable finite fuel",
		absf(rundown.sim.continuous[liquid_index] - full_usable_fuel) < 1e-12,
		"state %s kg; full usable %s kg" % [String.num_scientific(rundown.sim.continuous[liquid_index]), String.num_scientific(full_usable_fuel)])
	var initial_body: PackedFloat64Array = rundown.sim.state.duplicate()
	var original_hz: int = Engine.physics_ticks_per_second
	for test_hz: int in [120, 240, 480]:
		Engine.physics_ticks_per_second = test_hz
		for initial_rpm: float in [1.000001, 1.001, 1.01, 1.02, 1.05, 2.0]:
			rundown.sim.continuous[cutoff_index] = initial_rpm
			rundown.sim.aux[0] = initial_rpm
			var reset_ok: bool = rundown.sim.reset(initial_body)
			var planned_substeps: int = rundown.sim.model.substeps.call(rundown.sim.state,
				rundown.sim.continuous, rundown.sim.time())
			var fuel_before: float = rundown.sim.continuous[liquid_index]
			var fuel_event_declared: bool = rundown.sim.model.events.size() == 1 \
				and rundown.sim.model.events[0].get("type") == "fuel_exhausted"
			var cutoff_stages: Array[float] = []
			var cutoff_stage: Callable = rundown.sim.model.stage
			rundown.sim.model.stage = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
				cutoff_stages.append(z[cutoff_index])
				return cutoff_stage.call(s, z, t)
			rundown.sim.step()
			rundown.sim.model.stage = cutoff_stage
			var after_rundown: float = rundown.sim.continuous[cutoff_index]
			var complete_tick: bool = reset_ok and rundown.sim.tick == 1 and rundown.sim.fault_reason.is_empty()
			var finite_nonnegative_stages: bool = cutoff_stages.size() == 4 * planned_substeps \
				and cutoff_stages.all(func(rpm: float) -> bool: return is_finite(rpm) and rpm >= 0.0)
			_check("engine-off rundown %s RPM at %d Hz stays in the nonnegative RK domain" % [str(initial_rpm), test_hz],
				complete_tick and not rundown.engine_running and finite_nonnegative_stages
				and fuel_event_declared and fuel_before == full_usable_fuel
				and rundown.sim.continuous[liquid_index] == fuel_before and rundown.sim.last_events.is_empty(),
				"substeps=%d; stages %s; endpoint %s RPM; fault '%s'" % [planned_substeps, str(cutoff_stages), String.num_scientific(after_rundown), rundown.sim.fault_reason])
			if complete_tick and after_rundown < Prop.STOPPED_RPM:
				var stopped_endpoint: float = after_rundown
				rundown.sim.step()
				_check("sub-cutoff combustion RPM remains finite without a fabricated stop event (%s RPM at %d Hz)" % [str(initial_rpm), test_hz],
					rundown.sim.tick == 2 and rundown.sim.fault_reason.is_empty()
					and rundown.sim.continuous[cutoff_index] == stopped_endpoint
					and rundown.sim.continuous[cutoff_index] >= 0.0)
	Engine.physics_ticks_per_second = 240
	rundown.engine_running = true
	rundown.sim.continuous[cutoff_index] = Prop.STOPPED_RPM + 0.000001
	rundown.sim.aux[0] = Prop.STOPPED_RPM + 0.000001
	rundown.sim.continuous[liquid_index] = 1e-8
	rundown.sim.continuous[liquid_index + 1] = 1.0
	_check("same-tick fuel-exhaustion fixture resets with source latched on", rundown.sim.reset(initial_body))
	var exhaustion_substeps: int = rundown.sim.model.substeps.call(rundown.sim.state,
		rundown.sim.continuous, rundown.sim.time())
	var exhaustion_stages: Array[float] = []
	var exhaustion_stage: Callable = rundown.sim.model.stage
	rundown.sim.model.stage = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
		exhaustion_stages.append(z[cutoff_index])
		return exhaustion_stage.call(s, z, t)
	rundown.sim.step()
	rundown.sim.model.stage = exhaustion_stage
	var fuel_exhausted_event: bool = rundown.sim.last_events.any(
		func(event: Dictionary) -> bool: return event.get("type") == "fuel_exhausted")
	_check("near-cutoff refinement composes with same-tick finite-fuel exhaustion",
		exhaustion_substeps > 1 and rundown.sim.tick == 1 and rundown.sim.fault_reason.is_empty()
		and fuel_exhausted_event and rundown.sim.continuous[liquid_index] == 0.0
		and rundown.sim.continuous[liquid_index + 1] == 0.0
		and exhaustion_stages.size() >= 4 * exhaustion_substeps
		and exhaustion_stages.all(func(rpm: float) -> bool: return is_finite(rpm) and rpm >= 0.0),
		"substeps=%d; events=%s; RPM stages=%s; fault '%s'" % [exhaustion_substeps,
		str(rundown.sim.last_events), str(exhaustion_stages), rundown.sim.fault_reason])
	rundown.sim.continuous[cutoff_index] = Prop.STOPPED_RPM + 0.000001
	rundown.sim.aux[0] = Prop.STOPPED_RPM + 0.000001
	_check("depleted finite source resets with legacy engine mode still running", rundown.sim.reset(rundown.sim.state))
	var depleted_substeps: int = rundown.sim.model.substeps.call(rundown.sim.state,
		rundown.sim.continuous, rundown.sim.time())
	var depleted_stages: Array[float] = []
	var depleted_stage: Callable = rundown.sim.model.stage
	rundown.sim.model.stage = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
		depleted_stages.append(z[cutoff_index])
		return depleted_stage.call(s, z, t)
	rundown.sim.step()
	rundown.sim.model.stage = depleted_stage
	_check("zero-fuel source latch selects off-shaft refinement even when engine_running is true",
		depleted_substeps > 1 and rundown.engine_running and rundown.sim.tick == 1
		and rundown.sim.fault_reason.is_empty() and rundown.sim.continuous[liquid_index] == 0.0
		and rundown.sim.continuous[liquid_index + 1] == 0.0
		and depleted_stages.size() == 4 * depleted_substeps
		and depleted_stages.all(func(rpm: float) -> bool: return is_finite(rpm) and rpm >= 0.0),
		"substeps=%d; RPM stages=%s; fault '%s'" % [depleted_substeps, str(depleted_stages), rundown.sim.fault_reason])

	Engine.physics_ticks_per_second = 16
	rundown.engine_running = false
	rundown.sim.continuous[cutoff_index] = Prop.STOPPED_RPM + 0.000001
	rundown.sim.aux[0] = Prop.STOPPED_RPM + 0.000001
	rundown.sim.continuous[liquid_index] = full_usable_fuel
	rundown.sim.continuous[liquid_index + 1] = 0.0
	_check("substep-cap fixture resets at supported 16 Hz", rundown.sim.reset(initial_body))
	var excessive_substeps: int = rundown.sim.model.substeps.call(rundown.sim.state,
		rundown.sim.continuous, rundown.sim.time())
	var before_excessive_step: PackedByteArray = _dynamic_bits(rundown.sim)
	rundown.sim.step()
	_check("refinement above the kernel substep cap fails closed without clipping the requested count",
		excessive_substeps > SimKernel.MAX_SUBSTEPS and rundown.sim.tick == 0
		and rundown.sim.fault_reason.contains("substep count is not an integer within 1..%d" % SimKernel.MAX_SUBSTEPS)
		and before_excessive_step == _dynamic_bits(rundown.sim),
		"requested %d; cap %d; fault '%s'" % [excessive_substeps, SimKernel.MAX_SUBSTEPS, rundown.sim.fault_reason])
	Engine.physics_ticks_per_second = original_hz
	rundown.free()


func _stage_local_integration() -> void:
	var flight: Node = _coupled_fixture()
	if flight == null or not flight.is_flyable():
		_check("stage-local fixture starts", false)
		return
	var prop: Dictionary = flight.aircraft.model.propulsion
	var start_rpm: float = float(prop.idle_rpm) + 40.0
	var shaft_index: int = flight._rotor_index()
	flight.sim.continuous[shaft_index] = start_rpm
	flight.sim.aux[0] = start_rpm
	flight.sim.inputs[3] = 1.0
	flight.engine_running = true
	_check("stage-local fixture resets cleanly", flight.sim.reset(flight.sim.state))
	var stages: Array = []
	var legacy_calls := { loads = 0, derivative = 0, rotor = 0 }
	var real_evaluate: Callable = flight.sim.model.stage
	var real_loads: Callable = flight.sim.model.block_loads
	var real_derivative: Callable = flight.sim.model.block_derivative
	var real_rotor: Callable = flight.sim.model.stage_rotor_momentum
	flight.sim.model.stage = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
		var result: Dictionary = real_evaluate.call(s, z, t)
		stages.append({rpm = z[shaft_index], time = t, z = z.duplicate(), loads = result.get("loads", null)})
		return result
	flight.sim.model.block_loads = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		legacy_calls.loads += 1
		return real_loads.call(s, z, t)
	flight.sim.model.block_derivative = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		legacy_calls.derivative += 1
		return real_derivative.call(s, z, t)
	flight.sim.model.stage_rotor_momentum = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		legacy_calls.rotor += 1
		return real_rotor.call(s, z, t)
	flight.sim.step()
	flight.sim.model.stage = real_evaluate
	flight.sim.model.block_loads = real_loads
	flight.sim.model.block_derivative = real_derivative
	flight.sim.model.stage_rotor_momentum = real_rotor
	var dt: float = flight.sim.dt()
	var times_ok: bool = stages.size() == 4
	if times_ok:
		var expected: Array[float] = [0.0, dt * 0.5, dt * 0.5, dt]
		for i: int in 4:
			times_ok = times_ok and absf(float(stages[i].time) - expected[i]) < 1e-14
	var rpms: Array[float] = []
	for stage: Dictionary in stages:
		rpms.append(float(stage.rpm))
	var loads_ok: bool = stages.size() == 4
	for stage: Dictionary in stages:
		var stage_loads: Variant = stage.loads
		loads_ok = loads_ok and typeof(stage_loads) == TYPE_PACKED_FLOAT64_ARRAY and stage_loads.size() == 6
	if stages.size() == 4:
		loads_ok = loads_ok and flight.sim.last_loads == stages[0].loads
	_check("coupled RK4 performs four joint evaluations with stage loads at k1–k4 times and RPM", times_ok
		and loads_ok and rpms.size() == 4 and rpms.max() > rpms.min() + 1e-8
		and legacy_calls.loads == 0 and legacy_calls.derivative == 0 and legacy_calls.rotor == 0,
		"stage rpm %s; times %s; legacy calls %s" % [str(rpms),
		str(stages.map(func(stage: Dictionary) -> float: return float(stage.time))), str(legacy_calls)])
	_check("endpoint projection mirrors continuous RPM into sampled telemetry",
		flight.sim.continuous[shaft_index] > start_rpm and flight.sim.aux[0] == flight.sim.continuous[shaft_index])
	flight.free()


func _joint_callback_falls_back_to_legacy() -> void:
	var fallback: Node = _legacy_static_fuel_p51("coupled-rk4")
	var reference: Node = _legacy_static_fuel_p51("coupled-rk4")
	if fallback == null or reference == null or not fallback.is_flyable() or not reference.is_flyable():
		_check("legacy callback fallback fixtures start", false)
		return
	var calls := { loads = 0, derivative = 0, rotor = 0 }
	var original_joint: Callable = fallback.sim.model.stage
	fallback.sim.model.stage = Callable()
	fallback.sim.model.block_loads = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		calls.loads += 1
		return original_joint.call(s, z, t).loads
	fallback.sim.model.block_derivative = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		calls.derivative += 1
		return original_joint.call(s, z, t).derivative
	fallback.sim.model.stage_rotor_momentum = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		calls.rotor += 1
		return original_joint.call(s, z, t).rotor_momentum
	fallback.sim.step()
	reference.sim.step()
	_check("unset joint callback uses each legacy stage callback four times without fault",
		fallback.sim.tick == 1 and fallback.sim.fault_reason.is_empty()
		and calls.loads == 4 and calls.derivative == 4 and calls.rotor == 4,
		str(calls))
	var fallback_checkpoint: Dictionary = fallback.sim.checkpoint()
	var reference_checkpoint: Dictionary = reference.sim.checkpoint()
	_check("legacy callback fallback remains bit-identical to joint evaluation",
		var_to_bytes(fallback_checkpoint) == var_to_bytes(reference_checkpoint))
	fallback.free()
	reference.free()


func _wind_time_purity() -> void:
	var weather: Dictionary = Wind.defaults()
	weather.speed_mps = 3.0
	weather.from_deg = 180.0
	weather.gust_mps = 4.0
	weather.gust_duration_s = 1.5
	weather.gust_period_s = 4.0
	weather.gust_delay_s = 0.3
	var flight: Node = _coupled_fixture(false, weather)
	if flight == null or not flight.is_flyable():
		_check("wind purity fixture starts", false)
		return
	var before: PackedByteArray = _dynamic_bits(flight.sim)
	var rpm: float = flight.sim.continuous[flight._rotor_index()]
	var shaft_values: PackedFloat64Array = _shaft_values(flight, flight.sim.continuous)
	var state: PackedFloat64Array = flight.sim.state.duplicate()
	var during: float = flight._coupled_response(state, shaft_values, 1.05).get("rpm_rate", NAN)
	var repeat: float = flight._coupled_response(state, shaft_values, 1.05).get("rpm_rate", NAN)
	var after_gust: float = flight._coupled_response(state, shaft_values, 2.0).get("rpm_rate", NAN)
	_check("stage shaft rate uses explicit wind time and remains pure",
		is_finite(during) and during == repeat and is_finite(after_gust) and absf(during - after_gust) > 1e-8
		and before == _dynamic_bits(flight.sim))
	flight.free()


func _transported_wash_and_replay() -> void:
	var flight: Node = _coupled_fixture(true)
	if flight == null or not flight.is_flyable():
		_check("coupled transported-wash fixture starts", false)
		return
	var pieces: int = flight.aircraft.model.propulsion.slipstream.pieces.size()
	var rotor_index: int = flight._rotor_index()
	var wheel_count: int = flight.wheel_count()
	var initial: PackedFloat64Array = flight.sim.continuous.duplicate()
	var liquid_index: int = flight._liquid_index()
	_check("transported wash precedes RPM and appended wheel speeds in the continuous layout",
		rotor_index == pieces and wheel_count == flight.aircraft.model.landing_gear.contacts.size()
		and flight.liquid_fuel_is_active() and liquid_index == pieces + 1 + wheel_count
		and initial.size() == pieces + 1 + wheel_count + 2 and LiquidFlight.valid(flight, initial)
		and initial[rotor_index] == flight.sim.aux[0]
		and initial.slice(0, pieces) == flight._settled_wash(flight.sim.state, flight.sim.aux))
	flight.sim.inputs[3] = 1.0
	flight.engine_running = true
	var stages: Array[PackedFloat64Array] = []
	var real_evaluate: Callable = flight.sim.model.stage
	flight.sim.model.stage = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
		var result: Dictionary = real_evaluate.call(s, z, t)
		stages.append(z.duplicate())
		return result
	flight.sim.step()
	flight.sim.model.stage = real_evaluate
	var wash_changed: bool = false
	var rpm_changed: bool = false
	if stages.size() == 4:
		for i: int in range(1, 4):
			wash_changed = wash_changed or stages[i].slice(0, pieces) != stages[0].slice(0, pieces)
			rpm_changed = rpm_changed or stages[i][rotor_index] != stages[0][rotor_index]
	_check("RK stages transport wash and solve RPM together", wash_changed and rpm_changed
		and flight.sim.continuous[rotor_index] == flight.sim.aux[0])
	var metadata: Dictionary = flight.trace_meta()
	_check("coupled traces retain schema and identify the shaft integrator",
		metadata.metadata_schema == "openrc-flight-meta v9"
		and metadata.flap_base_metadata_schema == "openrc-flight-meta v8"
		and metadata.wheel_profile_status == "applied"
		and metadata.gear_law == "retractable-point-gear-v1"
		and metadata.flap_law == "controls.flaps.hinged_trailing_edge.v1"
		and metadata.propulsion_model == "propeller-shaft-coupled-rk4-v1"
		and metadata.shaft_integrator == "coupled-rk4"
		and metadata.rotor_coupling == "relative-spin-locked-inertia-reaction-v1"
		and metadata.continuous_layout == "axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm; RK4 coupled; wheel rim speeds in m/s, landing-gear contact order, appended continuous tail; " + LiquidFlight.LAYOUT
		and metadata.liquid_fuel_model == LiquidFlight.LAW and metadata.fuel_state_index == liquid_index)
	var boundary: Dictionary = flight.checkpoint()
	_check("coupled finite-fuel checkpoint v11 retains its v4 shaft identity",
		boundary.format == "openrc-flight-checkpoint v11"
		and boundary.get("liquid_physics_format", "") == "openrc-flight-checkpoint v4"
		and boundary.get("liquid_law", "") == LiquidFlight.LAW
		and boundary.get("shaft_integrator", "") == "coupled-rk4"
		and boundary.simulation.continuous.size() == pieces + 1 + wheel_count + 2)
	if boundary.is_empty():
		flight.free()
		return
	var captured: Dictionary = bytes_to_var(var_to_bytes(boundary))
	_advance(flight, 40, 0.74)
	var expected: PackedByteArray = var_to_bytes(flight.sim.checkpoint())
	_check("coupled transported-wash checkpoint restores exactly", flight.restore_checkpoint(captured))
	_advance(flight, 40, 0.74)
	_check("coupled transported-wash replay is bit-exact", expected == var_to_bytes(flight.sim.checkpoint()))
	var before_bad_restore: PackedByteArray = _dynamic_bits(flight.sim)
	var bad_cases: Array[Dictionary] = []
	var bad_mirror: Dictionary = captured.duplicate(true)
	bad_mirror.simulation.aux[0] += 1.0
	bad_cases.append(bad_mirror)
	var bad_layout: Dictionary = captured.duplicate(true)
	bad_layout.simulation.continuous = bad_layout.simulation.continuous.slice(0, pieces)
	bad_cases.append(bad_layout)
	var bad_rpm: Dictionary = captured.duplicate(true)
	bad_rpm.simulation.continuous[rotor_index] = -1.0
	bad_rpm.simulation.aux[0] = -1.0
	bad_cases.append(bad_rpm)
	var names: Array[String] = ["RPM mirror", "continuous layout", "negative RPM"]
	for i: int in bad_cases.size():
		_check("bad checkpoint " + names[i] + " is rejected atomically",
			not flight.restore_checkpoint(bad_cases[i]) and before_bad_restore == _dynamic_bits(flight.sim))
	var split: Node = _legacy_static_fuel_p51("split")
	var split_before: PackedByteArray = _dynamic_bits(split.sim)
	_check("split session refuses coupled checkpoint without mutation",
		not split.restore_checkpoint(captured) and split_before == _dynamic_bits(split.sim))
	split.free()
	flight.free()


func _fault_rollback(kind: String) -> void:
	var flight: Node = _coupled_fixture()
	if flight == null or not flight.is_flyable():
		_check(kind + " rollback fixture starts", false)
		return
	var sim: Node = flight.sim
	var before: PackedByteArray = _dynamic_bits(sim)
	var stepped := [0]
	sim.stepped.connect(func(_tick: int, _time: float, _state: PackedFloat64Array, _loads: PackedFloat64Array,
			_inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void: stepped[0] += 1)
	var real_evaluate: Callable = sim.model.stage
	match kind:
		"stage":
			var calls := [0]
			sim.model.stage = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
				calls[0] += 1
				var result: Dictionary = real_evaluate.call(s, z, t)
				if calls[0] == 2:
					var bad_loads: PackedFloat64Array = result.loads.duplicate()
					bad_loads[0] = NAN
					result.loads = bad_loads
				return result
		"gyro":
			sim.model.stage = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
				var result: Dictionary = real_evaluate.call(s, z, t)
				result.rotor_momentum = PackedFloat64Array([NAN, 0, 0])
				return result
		"derivative":
			sim.model.stage = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
				var result: Dictionary = real_evaluate.call(s, z, t)
				result.derivative = PackedFloat64Array([NAN])
				return result
		"missing_field":
			sim.model.stage = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
				var result: Dictionary = real_evaluate.call(s, z, t)
				result.erase("derivative")
				return result
		"wrong_float32":
			sim.model.stage = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
				var result: Dictionary = real_evaluate.call(s, z, t)
				result.derivative = PackedFloat32Array([0.0])
				return result
		"wrong_width":
			sim.model.stage = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
				var result: Dictionary = real_evaluate.call(s, z, t)
				result.derivative = PackedFloat64Array([0.0, 0.0])
				return result
		"wrong_type":
			sim.model.stage = func(_s: PackedFloat64Array, _z: PackedFloat64Array, _t: float):
				return "invalid joint payload"
		"projection":
			sim.model.block_aux = func(_z: PackedFloat64Array, sampled: PackedFloat64Array) -> PackedFloat64Array:
				var invalid: PackedFloat64Array = sampled.duplicate()
				invalid[0] = NAN
				return invalid
	sim.step()
	_check(kind + " failure rolls every committed dynamic field back and emits no tick",
		not sim.fault_reason.is_empty() and sim.paused and stepped[0] == 0 and before == _dynamic_bits(sim), sim.fault_reason)
	flight.free()


func _reset_joint_payload_rollback() -> void:
	var flight: Node = _coupled_fixture()
	if flight == null or not flight.is_flyable():
		_check("malformed joint reset fixture starts", false)
		return
	var sim: Node = flight.sim
	var before: PackedByteArray = _dynamic_bits(sim)
	var stepped := [0]
	sim.stepped.connect(func(_tick: int, _time: float, _state: PackedFloat64Array, _loads: PackedFloat64Array,
			_inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void: stepped[0] += 1)
	var real_evaluate: Callable = sim.model.stage
	sim.model.stage = func(s: PackedFloat64Array, z: PackedFloat64Array, t: float) -> Dictionary:
		var result: Dictionary = real_evaluate.call(s, z, t)
		result.derivative = PackedFloat32Array([0.0])
		return result
	var reset_ok: bool = sim.reset(sim.state)
	_check("malformed float32 joint payload rejects reset atomically and emits no tick",
		not reset_ok and sim.paused and not sim.fault_reason.is_empty() and stepped[0] == 0
		and before == _dynamic_bits(sim), sim.fault_reason)
	flight.free()


func _trace_integrity() -> void:
	var flight: Node = _coupled_fixture()
	var trace: Trace = Trace.new()
	trace.meta = flight.trace_meta()
	trace.meta.mass_trace_schema = Trace.MASS_TRACE_SCHEMA
	trace.record(0, 0.0, flight.sim.state, flight.sim.last_loads, flight.sim.inputs, flight.sim.aux,
		flight.sim.continuous, flight.mass_properties())
	trace.meta.shaft_integrator = "split"
	flight.sim.step()
	trace.record(1, flight.sim.time(), flight.sim.state, flight.sim.last_loads, flight.sim.inputs, flight.sim.aux,
		flight.sim.continuous, flight.mass_properties())
	_check("coupled recording freezes its integration identity", trace.row_count() == 2 \
		and trace.to_csv().contains("# shaft_integrator: coupled-rk4\n"))
	var malformed: Trace = Trace.new()
	malformed.meta = flight.trace_meta()
	malformed.meta.mass_trace_schema = Trace.MASS_TRACE_SCHEMA
	malformed.meta.recording_start_continuous = "[123.0]"
	malformed.record(flight.sim.tick, flight.sim.time(), flight.sim.state, flight.sim.last_loads, flight.sim.inputs, flight.sim.aux,
		flight.sim.continuous, flight.mass_properties())
	_check("trace refuses a false initial continuous RPM mirror", malformed.to_csv().is_empty())
	flight.free()
	var wash: Node = _coupled_fixture(true)
	wash.sim.continuous[0] = -0.25 # a transported induced-velocity deficit is signed; RPM stays positive
	var signed_trace: Trace = Trace.new()
	signed_trace.meta = wash.trace_meta()
	signed_trace.meta.mass_trace_schema = Trace.MASS_TRACE_SCHEMA
	signed_trace.record(wash.sim.tick, wash.sim.time(), wash.sim.state, wash.sim.last_loads, wash.sim.inputs, wash.sim.aux,
		wash.sim.continuous, wash.mass_properties())
	_check("coupled trace accepts finite negative wash increments with positive RPM", not signed_trace.to_csv().is_empty())
	wash.free()


func _pending_restore() -> void:
	var source: Node = _legacy_static_fuel_p51("coupled-rk4")
	var destination: Node = _legacy_static_fuel_p51("split")
	if source == null or destination == null:
		_check("legacy static-fuel checkpoint fixtures start", false)
		if source != null:
			source.free()
		if destination != null:
			destination.free()
		return
	var saved: Dictionary = source.checkpoint()
	var switched: bool = destination.setup_shaft_integrator("coupled-rk4")
	var pending_state: PackedByteArray = _dynamic_bits(destination.sim)
	var pending_restore_rejected: bool = not destination.restore_checkpoint(saved) \
		and pending_state == _dynamic_bits(destination.sim)
	_check("pending shaft-layout draft rejects an incompatible checkpoint atomically", switched and pending_restore_rejected)
	destination.reset() # A mode selection takes effect only after this owner-controlled layout boundary.
	var restored: bool = switched and destination.shaft_is_coupled() and destination.restore_checkpoint(saved)
	_check("legacy static-fuel split-to-coupled reset accepts an exact checkpoint", restored)
	if restored:
		destination.sim.step()
	_check("restored coupled checkpoint advances without a fault",
		destination.sim.tick == 1 and destination.sim.fault_reason.is_empty())
	source.free()
	destination.free()


func _initialize() -> void:
	var p51_data: Dictionary = AD.load_file(P51_PATH)
	_check("coupled target is the positive-inertia P-51 shaft model", p51_data.ok
		and p51_data.model.id == P51_ID and Prop.has_shaft(p51_data.model.propulsion)
		and p51_data.model.propulsion.rotor_inertia > 0.0)
	_mode_and_legacy_paths()
	_coupling_physics()
	_stopped_combustion_lock_and_cutoff()
	_stage_local_integration()
	_joint_callback_falls_back_to_legacy()
	_wind_time_purity()
	_transported_wash_and_replay()
	_fault_rollback("stage")
	_fault_rollback("gyro")
	_fault_rollback("derivative")
	_fault_rollback("missing_field")
	_fault_rollback("wrong_float32")
	_fault_rollback("wrong_width")
	_fault_rollback("wrong_type")
	_fault_rollback("projection")
	_reset_joint_payload_rollback()
	_trace_integrity()
	_pending_restore()
	print("G2 coupled shaft: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
