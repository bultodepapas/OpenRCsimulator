# DR-05/06/07/18/19/20: the closed-loop multirotor on the shared kernel through the framed sampled protocol.
# Controller cases CTRL-01…06 run on the controlled laboratory law; PHY-02/05/06/07, pad contact, crash and
# depletion run on the electrical law with synthetic fixture numbers (tests/mr_fixtures.gd). Software checks on
# estimated data: no flight validation, no firmware equivalence.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const ActuatorMap := preload("res://physics/multirotor/actuator_map.gd")
const ElectricBus := preload("res://physics/multirotor/electric_bus.gd")
const Rotor := preload("res://physics/multirotor/rotor.gd")
const Airframe := preload("res://physics/multirotor/airframe.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _hover_throttle(plant: RefCounted, continuous: PackedFloat64Array) -> float:
	var map: Dictionary = plant.config.actuator
	var command: float = ActuatorMap.command_for_thrust(map, float(plant.prepared.mass_kg) * 9.80665 / 4.0, plant.supply_voltage(continuous))
	return (command - float(map.idle)) / (float(map.top) - float(map.idle))


## Armed and hovering at `altitude`: shafts start at the hover speed, the arm switch is cycled OFF then ON.
func _airborne(data: Dictionary, altitude := 20.0, attitude: PackedFloat64Array = M.q_identity(), mode := 0) -> Dictionary:
	var h: Dictionary = Fixtures.install(root, data)
	var frame: Dictionary = h.plant.initial_frame(Fixtures.body(altitude, attitude))
	var hover_speed: float = sqrt(float(data.mass_kg) * 9.80665 / (4.0 * float(data.rotor_law.thrust_coefficient_n_s2)))
	for i in 4:
		frame.continuous[i] = hover_speed
	var message: String = Fixtures.reset(h.sim, frame, FC.neutral_input())
	h.throttle = _hover_throttle(h.plant, frame.continuous)
	h.ok = h.ok and message.is_empty() and Fixtures.run(h.sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0, mode), 1) \
		and Fixtures.run(h.sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1, mode), 1)
	h.message = message + h.sim.fault_reason
	return h


func _rate(sim: Node, axis: int) -> float:
	return sim.state[RB.RATE + axis]


func _euler(sim: Node) -> PackedFloat64Array:
	return M.q_to_euler(M.quat(sim.state[RB.ATT], sim.state[RB.ATT + 1], sim.state[RB.ATT + 2], sim.state[RB.ATT + 3]))


func _run() -> void:
	_arming()
	_acro()
	_angle()
	_saturation_and_airmode()
	_coupled_momentum_oracle()
	_stage_equivalence()
	_damped_bridge()
	_pad_and_crash()
	_energy_and_depletion()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _arming() -> void:
	var h: Dictionary = Fixtures.install(root, Fixtures.lab())
	var sim: Node = h.sim
	var message: String = Fixtures.reset(sim, h.plant.initial_frame(Fixtures.body(Fixtures.REST_HEIGHT_M)), FC.neutral_input())
	_check("the controlled laboratory plant installs and resets through the full-frame path", h.ok and message.is_empty(), message)
	_check("layout: nine pilot inputs, the 31-value controller block, eight discrete modes, four shafts",
		sim.model.input_size == 9 and sim.model.aux_size == 31 and sim.model.modes_size == 8 and sim.model.continuous_size == 4)
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), 20)
	_check("INPUT-04 an arm switch held high at entry never arms", sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED
		and sim.modes[FC.MODE_ARM_BLOCK] == FC.BLOCK_SWITCH and sim.aux[FC.AUX_COMMAND] == 0.0)
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.6, 0), 2)
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.6, 1), 5)
	_check("INPUT-04 an ON edge at high throttle is refused with its reason", sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED
		and sim.modes[FC.MODE_ARM_BLOCK] == FC.BLOCK_THROTTLE)
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), 20)
	_check("lowering the throttle under a refused, still-held switch does not arm", sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED)
	var not_ready: PackedFloat64Array = Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0)
	Fixtures.run(sim, not_ready, 1)
	not_ready[FC.IN_ARM] = 1.0
	not_ready[FC.IN_SOURCE_READY] = 0.0
	Fixtures.run(sim, not_ready, 2)
	_check("a source that is not ready cannot arm", sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and sim.modes[FC.MODE_ARM_BLOCK] == FC.BLOCK_SOURCE)
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), 1)
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), 1)
	var idle: float = h.plant.config.actuator.idle
	_check("OFF then a fresh ON at low throttle arms; the motors hold the idle command",
		sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED and sim.modes[FC.MODE_ARM_BLOCK] == FC.BLOCK_NONE
		and absf(sim.aux[FC.AUX_COMMAND] - idle) < 1e-9 and absf(sim.aux[FC.AUX_COMMAND + 3] - idle) < 1e-9, str(sim.aux[FC.AUX_COMMAND]))
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), 240)
	var spinning: float = sim.continuous[0]
	_check("CONTACT-03 armed idle on the pad spins the shafts without lifting off", spinning > 100.0
		and absf(-sim.state[RB.POS + 2] - Fixtures.REST_HEIGHT_M) < 0.004 and sim.last_events.is_empty(),
		"speed %.1f height %.4f" % [spinning, -sim.state[RB.POS + 2]])
	var reconnect: PackedFloat64Array = Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1, 0, 1)
	Fixtures.run(sim, reconnect, 1)
	_check("INPUT-06 a new source generation with the switch still high drops motor authority",
		sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and sim.modes[FC.MODE_SOURCE_GENERATION] == 1 and sim.aux[FC.AUX_COMMAND] == 0.0)
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0, 0, 1), 1)
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1, 0, 1), 1)
	var recovery: PackedFloat64Array = Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1, 0, 2)
	recovery[FC.IN_ACTIONS] = float(FC.ACTION_RECOVERY)
	Fixtures.run(sim, recovery, 1)
	_check("INPUT-07 an attested recovery at low throttle keeps authority across a reconnect",
		sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED and sim.modes[FC.MODE_SOURCE_GENERATION] == 2)
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0, 0, 2), 1)
	_check("arm OFF is zero drive from that sample", sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and sim.aux[FC.AUX_COMMAND] == 0.0
		and sim.aux[FC.AUX_COMMAND + 1] == 0.0 and sim.aux[FC.AUX_COMMAND + 2] == 0.0 and sim.aux[FC.AUX_COMMAND + 3] == 0.0)
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0, 0, 2), 480)
	_check("disarmed shafts coast down under the declared law", sim.continuous[0] < 0.01 * spinning and sim.continuous[0] >= 0.0,
		"%.4f" % sim.continuous[0])
	var bad: PackedFloat64Array = Fixtures.pilot(1.5, 0.0, 0.0, 0.0, 0, 0, 2)
	var tick_before: int = sim.tick
	sim.inputs = bad
	sim.step()
	_check("a pilot frame outside its domain refuses the tick", sim.tick == tick_before and not sim.fault_reason.is_empty(), sim.fault_reason)
	sim.free()
	var rate: Dictionary = Fixtures.install(root, Fixtures.lab(), FC.THROTTLE_RATE)
	Fixtures.reset(rate.sim, rate.plant.initial_frame(Fixtures.body(Fixtures.REST_HEIGHT_M)), FC.neutral_input())
	Fixtures.run(rate.sim, Fixtures.pilot(0.0, 0.0, 0.0, 1.0, 0), 60)
	_check("INPUT-03 the rate-throttle accumulator rests at zero while disarmed", rate.sim.aux[FC.AUX_VIRTUAL_THROTTLE] == 0.0)
	Fixtures.run(rate.sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), 1)
	Fixtures.run(rate.sim, Fixtures.pilot(0.0, 0.0, 0.0, 1.0, 1), 120)
	_check("INPUT-03 the armed rate throttle integrates at the declared fixed-tick rate",
		rate.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED and absf(rate.sim.aux[FC.AUX_VIRTUAL_THROTTLE] - 0.8 * 0.5) < 1e-9,
		"%.6f" % rate.sim.aux[FC.AUX_VIRTUAL_THROTTLE])
	var reset_action: PackedFloat64Array = Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1)
	reset_action[FC.IN_ACTIONS] = float(FC.ACTION_THROTTLE_RESET)
	Fixtures.run(rate.sim, reset_action, 1)
	_check("INPUT-08 the zero-throttle recovery action clears the accumulator in the same sample",
		rate.sim.aux[FC.AUX_VIRTUAL_THROTTLE] == 0.0 and rate.sim.aux[FC.AUX_COLLECTIVE] == 0.0)
	rate.sim.free()


func _acro() -> void:
	var h: Dictionary = _airborne(Fixtures.lab())
	var sim: Node = h.sim
	_check("an armed hover starts in the air", h.ok and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED, h.message)
	var hover: PackedFloat64Array = Fixtures.pilot(0.0, 0.0, 0.0, h.throttle, 1)
	var ok: bool = Fixtures.run(sim, hover, 480)
	_check("CTRL-01 centred sticks hold zero rate and the hover throttle holds altitude",
		ok and absf(_rate(sim, 0)) < 1e-3 and absf(_rate(sim, 1)) < 1e-3 and absf(_rate(sim, 2)) < 1e-3
		and absf(-sim.state[RB.POS + 2] - 20.0) < 0.6 and absf(sim.state[RB.VEL + 2]) < 0.3,
		"h %.3f w %.4f" % [-sim.state[RB.POS + 2], sim.state[RB.VEL + 2]])
	sim.free()
	var rates_prepared: Dictionary = Rates.prepare(Rates.default_profile()).prepared
	for axis in 3:
		for direction: float in [1.0, -1.0]:
			var a: Dictionary = _airborne(Fixtures.lab())
			var sticks := PackedFloat64Array([0.0, 0.0, 0.0])
			sticks[axis] = 0.3 * direction
			var target: float = Rates.setpoints_rad_s(rates_prepared, sticks)[axis]
			Fixtures.run(a.sim, Fixtures.pilot(sticks[0], sticks[1], sticks[2], a.throttle, 1), 96)
			var others := 0.0
			for other in 3:
				if other != axis:
					others = maxf(others, absf(_rate(a.sim, other)))
			_check("CTRL-01 %s stick %s tracks its rate target in direction and size" % [Rates.AXIS_NAMES[axis], "+" if direction > 0.0 else "-"],
				a.sim.fault_reason.is_empty() and absf(_rate(a.sim, axis) - target) < 0.08 * absf(target) and others < 0.12 * absf(target)
				and absf(a.sim.aux[FC.AUX_SETPOINT + axis] - target) < 1e-12,
				"target %.3f rate %.3f others %.3f" % [target, _rate(a.sim, axis), others])
			a.sim.free()
	var first: Dictionary = _airborne(Fixtures.lab())
	var second: Dictionary = _airborne(Fixtures.lab())
	var same := true
	for tick in 240:
		var input: PackedFloat64Array = Fixtures.pilot(0.4 * sin(0.05 * tick), 0.3 * cos(0.03 * tick), 0.2, first.throttle, 1)
		first.sim.inputs = input
		second.sim.inputs = input.duplicate()
		first.sim.step()
		second.sim.step()
		same = same and first.sim.state.to_byte_array() == second.sim.state.to_byte_array() \
			and first.sim.aux.to_byte_array() == second.sim.aux.to_byte_array()
	_check("two closed-loop kernels fed the same pilot tape stay byte-identical", same and first.sim.fault_reason.is_empty())
	first.sim.free()
	second.sim.free()


func _angle() -> void:
	var h: Dictionary = _airborne(Fixtures.lab(), 40.0, M.q_identity(), 1)
	var sim: Node = h.sim
	Fixtures.run(sim, Fixtures.pilot(0.5, 0.0, 0.0, h.throttle, 1, 1), 360)
	var tilted: PackedFloat64Array = _euler(sim)
	_check("CTRL-05 Angle mode holds half stick at half the declared tilt limit", sim.fault_reason.is_empty()
		and absf(rad_to_deg(tilted[2]) - 27.5) < 2.0 and absf(rad_to_deg(tilted[1])) < 2.0,
		"roll %.2f pitch %.2f" % [rad_to_deg(tilted[2]), rad_to_deg(tilted[1])])
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, h.throttle, 1, 1), 360)
	var level: PackedFloat64Array = _euler(sim)
	_check("CTRL-05 centred sticks return to level in Angle mode", absf(rad_to_deg(level[2])) < 1.0 and absf(rad_to_deg(level[1])) < 1.0,
		"roll %.2f pitch %.2f" % [rad_to_deg(level[2]), rad_to_deg(level[1])])
	var before: float = sim.aux[FC.AUX_TAU_REQUEST + 2]
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, h.throttle, 1, 0), 1)
	_check("CTRL-05 switching Angle to Acro at level creates no yaw target and no torque kick",
		sim.aux[FC.AUX_SETPOINT + 2] == 0.0 and absf(sim.aux[FC.AUX_TAU_REQUEST + 2] - before) < 1e-3
		and absf(sim.aux[FC.AUX_TAU_REQUEST]) < 0.02 and sim.modes[FC.MODE_FLIGHT] == FC.FLIGHT_ACRO)
	sim.free()
	var inverted: Dictionary = _airborne(Fixtures.lab(), 60.0, M.q_from_euler(0.7, 0.0, PI), 1)
	Fixtures.run(inverted.sim, Fixtures.pilot(0.0, 0.0, 0.0, inverted.throttle, 1, 1), 480)
	var recovered: PackedFloat64Array = _euler(inverted.sim)
	_check("CTRL-05 Angle mode recovers from inverted by the shortest rotation", inverted.sim.fault_reason.is_empty()
		and absf(rad_to_deg(recovered[2])) < 3.0 and absf(rad_to_deg(recovered[1])) < 3.0,
		"roll %.2f pitch %.2f" % [rad_to_deg(recovered[2]), rad_to_deg(recovered[1])])
	inverted.sim.free()
	var nose_up: PackedFloat64Array = M.q_from_euler(0.4, PI / 2.0, 0.0)
	_check("the heading is defined with the nose vertical", absf(FC.heading(nose_up) - 0.4) < 1e-6
		and absf(FC.heading(M.q_from_euler(-1.1, 0.1, 0.3)) + 1.1) < 1e-9)


func _saturation_and_airmode() -> void:
	var h: Dictionary = _airborne(Fixtures.lab(), 80.0)
	var sim: Node = h.sim
	var worst_integral := 0.0
	var ok := true
	for tick in 240:
		ok = ok and Fixtures.run(sim, Fixtures.pilot(1.0, 0.0, 0.0, 1.0, 1), 1)
		for axis in 3:
			worst_integral = maxf(worst_integral, absf(sim.aux[FC.AUX_INTEGRAL + axis]) - float(h.plant.config.i_max[axis]))
	_check("CTRL-04 a full-stick roll at full throttle saturates the allocation with a bounded integral",
		ok and worst_integral <= 1e-12 and absf(sim.aux[FC.AUX_TAU_ALLOCATED]) < absf(sim.aux[FC.AUX_TAU_REQUEST]) + 1e-9,
		"integral excess %s" % String.num_scientific(worst_integral))
	ok = Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, h.throttle, 1), 240)
	_check("CTRL-04 release after saturation settles without a wound-up overshoot", ok and absf(_rate(sim, 0)) < 0.05
		and absf(_rate(sim, 1)) < 0.05 and absf(_rate(sim, 2)) < 0.05, "p %.4f q %.4f r %.4f" % [_rate(sim, 0), _rate(sim, 1), _rate(sim, 2)])
	sim.free()
	var a: Dictionary = _airborne(Fixtures.lab(), 80.0)
	Fixtures.run(a.sim, Fixtures.pilot(0.3, 0.0, 0.0, 0.0, 1), 12)
	var idle: float = a.plant.config.actuator.idle
	var low: float = INF
	var high: float = 0.0
	for i in 4:
		low = minf(low, a.sim.aux[FC.AUX_COMMAND + i])
		high = maxf(high, a.sim.aux[FC.AUX_COMMAND + i])
	_check("CTRL-03 Airmode keeps the requested moment at zero throttle by raising collective above idle",
		low >= idle - 1e-12 and high > idle + 0.01 and absf(a.sim.aux[FC.AUX_TAU_ALLOCATED] - a.sim.aux[FC.AUX_TAU_REQUEST]) < 0.05 * absf(a.sim.aux[FC.AUX_TAU_REQUEST]),
		"commands %.3f…%.3f tau %.4f of %.4f" % [low, high, a.sim.aux[FC.AUX_TAU_ALLOCATED], a.sim.aux[FC.AUX_TAU_REQUEST]])
	Fixtures.run(a.sim, Fixtures.pilot(0.3, 0.0, 0.0, 0.0, 0), 1)
	var zero := true
	for i in 4:
		zero = zero and a.sim.aux[FC.AUX_COMMAND + i] == 0.0 and a.sim.aux[FC.AUX_THRUST_TARGET + i] == 0.0
	_check("CTRL-03 disarm overrides idle and Airmode: every command and integral is zero", zero
		and a.sim.aux[FC.AUX_INTEGRAL] == 0.0 and a.sim.aux[FC.AUX_TAU_REQUEST] == 0.0)
	a.sim.free()


func _coupled_momentum_oracle() -> void:
	# FPV flight dynamics §4 oracle: one driven rotor, spin +1, I_L,zz = 0.002, J = 1e-5, speed 1000 rad/s,
	# motor torque 0.1 N·m, no aerodynamic torque: alpha_z = +50.2512562814, shaft 10050.2512563, power 100 W.
	var data: Dictionary = Fixtures.electric()
	data.inertia_kg_m2 = PackedFloat64Array([0.002, 0.002, 0.002, 0.0, 0.0, 0.0])
	data.rotor_law.thrust_coefficient_n_s2 = 1.0e-12
	data.rotor_law.torque_coefficient_n_m_s2 = 1.0e-19 # 1e-13 N·m at this speed: far below the oracle's tolerance
	data.rotor_law.rotor_drag_n_s2_per_m = 0.0
	data.powertrain.kv_rad_s_per_v = 100.0 # Kt = 0.01 N·m/A; back-EMF 10 V at 1000 rad/s
	data.powertrain.resistance_ohm = 1.52 # (25.2 − 10) / 1.52 = 10 A
	data.powertrain.no_load_current_a = 0.0
	data.battery.resistance_ohm = 0.0
	data.battery.auxiliary_current_a = 0.0
	for i in 4:
		data.rotors[i].inertia_kg_m2 = 1.0e-5 if i == 1 else 1.0e-13
	var created: Dictionary = Plant.create(data, Rates.default_profile(), FC.THROTTLE_ABSOLUTE)
	_check("the oracle configuration prepares", created.ok, str(created.errors))
	if not created.ok:
		return
	var plant: RefCounted = created.plant
	var frame: Dictionary = plant.initial_frame(Fixtures.body(100.0))
	frame.continuous[1] = 1000.0
	frame.aux[FC.AUX_COMMAND + 1] = 1.0
	frame.modes[FC.MODE_MOTOR] = FC.MOTOR_ARMED
	var result: Dictionary = plant._evaluate(frame.body, frame.continuous, 0.0, frame.aux, frame.modes)
	var alpha_z: float = result.loads[5] / 0.002 # body at rest: the kernel's alpha is moment over I_L
	var shaft: float = result.derivative[1]
	var momentum_rate: float = 0.002 * alpha_z
	var power: float = alpha_z * result.rotor_momentum[2]
	for i in 4:
		momentum_rate -= float(data.rotors[i].spin) * float(data.rotors[i].inertia_kg_m2) * result.derivative[i]
		power += float(data.rotors[i].inertia_kg_m2) * frame.continuous[i] * result.derivative[i]
	_check("PHY-02 coupled shaft/body acceleration matches the independent oracle",
		absf(alpha_z - 50.2512562814) < 1e-6 and absf(shaft - 10050.2512563) < 1e-4, "alpha %.10f shaft %.7f" % [alpha_z, shaft])
	_check("PHY-02 a motor torque is internal: the total angular momentum rate is zero", absf(momentum_rate) < 1e-12,
		String.num_scientific(momentum_rate))
	_check("PHY-02 rotational energy grows at exactly the motor's shaft power, cross term included", absf(power - 100.0) < 1e-6,
		"%.9f W" % power)
	_check("PHY-05 the one-load bus current matches the hand calculation", absf(float(result.bus.i_motor[1]) - 10.0) < 1e-9
		and absf(float(result.bus.i_pack) - 10.0) < 1e-9 and float(result.bus.i_motor[0]) == 0.0)


func _stage_equivalence() -> void:
	# The electrical stage writes the rotor law out in scalars and takes closed-form bus shortcuts: hold both
	# equal to the reference laws (rotor.gd, airframe.gd, the exhaustive bus solve) at awkward states.
	var data: Dictionary = Fixtures.electric()
	var plant: RefCounted = Plant.create(data, Rates.default_profile(), FC.THROTTLE_ABSOLUTE).plant
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	var worst := 0.0
	var worst_bus := 0.0
	var shortcuts := 0
	for _case in 300:
		var body: PackedFloat64Array = RB.make_state(M.v3(0.0, 0.0, -80.0),
			M.v3(rng.randf_range(-30.0, 30.0), rng.randf_range(-30.0, 30.0), rng.randf_range(-15.0, 15.0)),
			M.q_from_euler(rng.randf_range(-3.0, 3.0), rng.randf_range(-1.4, 1.4), rng.randf_range(-3.0, 3.0)),
			M.v3(rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0), rng.randf_range(-10.0, 10.0)))
		var frame: Dictionary = plant.initial_frame(body)
		frame.modes[FC.MODE_MOTOR] = FC.MOTOR_ARMED
		for i in 4:
			frame.continuous[i] = rng.randf_range(-20.0, 3500.0)
			frame.aux[FC.AUX_COMMAND + i] = rng.randf_range(0.0, 1.0)
		var result: Dictionary = plant._evaluate(frame.body, frame.continuous, 0.0, frame.aux, frame.modes)
		var v_air: PackedFloat64Array = M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2])
		var rates: PackedFloat64Array = M.v3(body[RB.RATE], body[RB.RATE + 1], body[RB.RATE + 2])
		var force: PackedFloat64Array = Airframe.loads(v_air, plant.rho, data.airframe)
		var moment: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
		for i in 4:
			var rotor: Dictionary = data.rotors[i]
			var law := {thrust_coefficient_n_s2 = data.rotor_law.thrust_coefficient_n_s2,
				torque_coefficient_n_m_s2 = data.rotor_law.torque_coefficient_n_m_s2,
				rotor_drag_n_s2_per_m = data.rotor_law.rotor_drag_n_s2_per_m, inertia_kg_m2 = rotor.inertia_kg_m2}
			var loads: Dictionary = Rotor.loads(maxf(frame.continuous[i], 0.0), float(rotor.spin), rotor.hub_frd, v_air, rates,
				result.derivative[i], law)
			force = M.add(force, loads.force)
			moment = M.add(moment, loads.moment)
		for i in 3:
			worst = maxf(worst, absf(result.loads[i] - force[i]) / maxf(1.0, absf(force[i])))
			worst = maxf(worst, absf(result.loads[3 + i] - moment[i]) / maxf(1.0, absf(moment[i])))
		var duty := PackedFloat64Array()
		var emf := PackedFloat64Array()
		for i in 4:
			duty.append(frame.aux[FC.AUX_COMMAND + i])
			emf.append(maxf(frame.continuous[i], 0.0) / float(data.powertrain.kv_rad_s_per_v))
		var resistance: float = data.powertrain.resistance_ohm
		var reference: Dictionary = ElectricBus.solve(plant._ocv(1.0), float(data.battery.resistance_ohm),
			float(data.battery.auxiliary_current_a), duty, emf, PackedFloat64Array([resistance, resistance, resistance, resistance]),
			PackedInt64Array([1, 1, 1, 1]))
		worst_bus = maxf(worst_bus, absf(float(result.bus.v_bus) - float(reference.v_bus)))
		worst_bus = maxf(worst_bus, absf(float(result.bus.i_pack) - float(reference.i_pack)))
		for i in 4:
			worst_bus = maxf(worst_bus, absf(float(result.bus.i_motor[i]) - float(reference.i_motor[i])))
		if not result.bus.has("active"):
			shortcuts += 1
	_check("the scalar electrical stage equals the reference rotor and airframe laws (300 random states)", worst < 1e-12,
		String.num_scientific(worst))
	_check("the closed-form bus shortcut equals the exhaustive active-set solve wherever it is taken", worst_bus < 1e-9
		and shortcuts > 20 and shortcuts < 300, "%s over %d shortcuts" % [String.num_scientific(worst_bus), shortcuts])


## Shaft speed after a throttle chop from `speed`, the roll rate a stick input reaches after the chop, and the
## energy books of the whole manoeuvre, for one bridge variant.
func _chop(braking: String) -> Dictionary:
	var data: Dictionary = Fixtures.electric()
	data.powertrain.braking = braking
	var h: Dictionary = _airborne(data, 60.0)
	var sim: Node = h.sim
	var capacity: float = 3600.0 * float(data.battery.capacity_ah)
	var ok: bool = h.ok and Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.9, 1), 96)
	var fast: float = sim.continuous[0]
	var lowest_pack := INF
	var charge_rose := false
	var rate_at_8 := 0.0
	var speed_at_12 := 0.0
	for tick in 96:
		var before: float = sim.continuous[Plant.C_CHARGE]
		ok = ok and Fixtures.run(sim, Fixtures.pilot(0.5, 0.0, 0.0, 0.0, 1), 1)
		charge_rose = charge_rose or sim.continuous[Plant.C_CHARGE] > before
		var telemetry: Dictionary = h.plant.telemetry({body = sim.state, continuous = sim.continuous, aux = sim.aux, modes = sim.modes})
		lowest_pack = minf(lowest_pack, telemetry.pack_current_a)
		if tick == 7:
			rate_at_8 = _rate(sim, 0)
		if tick == 11:
			speed_at_12 = sim.continuous[2]
	var chemical := 0.0
	var steps := 4000
	var charge_end: float = sim.continuous[Plant.C_CHARGE]
	for i in steps:
		var q0: float = charge_end + (capacity - charge_end) * float(i) / float(steps)
		var q1: float = charge_end + (capacity - charge_end) * float(i + 1) / float(steps)
		chemical += 0.5 * (h.plant._ocv(q0 / capacity) + h.plant._ocv(q1 / capacity)) * (q1 - q0)
	var result := {ok = ok and sim.fault_reason.is_empty(), fast = fast, speed_at_12 = speed_at_12, rate_at_8 = rate_at_8,
		target = sim.aux[FC.AUX_SETPOINT], lowest_pack = lowest_pack, charge_rose = charge_rose, chemical = chemical,
		accounted = sim.continuous[Plant.C_TERMINAL_ENERGY] + sim.continuous[Plant.C_PACK_LOSS],
		bus = str(sim.model.identity.bus), fault = sim.fault_reason}
	sim.free()
	return result


func _damped_bridge() -> void:
	var coast: Dictionary = _chop("none")
	var damped: Dictionary = _chop("damped")
	_check("both bridge variants fly the chop manoeuvre and carry their own bus identity", coast.ok and damped.ok
		and coast.bus == ElectricBus.LAW and damped.bus == Plant.BUS_DAMPED, coast.fault + damped.fault)
	_check("PHY-08 the one-quadrant bridge never returns current to the pack", coast.lowest_pack >= 0.0 and not coast.charge_rose,
		"%.3f A" % coast.lowest_pack)
	_check("the damped bridge brakes: fifty milliseconds after a chop the shaft is far slower than a coasting one",
		damped.speed_at_12 < 0.6 * coast.speed_at_12 and damped.speed_at_12 >= 0.0 and coast.speed_at_12 < coast.fast,
		"damped %.0f rad/s, coasting %.0f rad/s, from %.0f" % [damped.speed_at_12, coast.speed_at_12, coast.fast])
	_check("the damped bridge regenerates: the pack current goes negative and the charge rises during the chop",
		damped.lowest_pack < 0.0 and damped.charge_rose, "%.2f A" % damped.lowest_pack)
	_check("PHY-06 the energy books close with signed pack current", damped.chemical > 50.0
		and absf(damped.accounted - damped.chemical) < 1e-5 * damped.chemical and absf(coast.accounted - coast.chemical) < 1e-5 * coast.chemical,
		"damped %.5f of %.5f J; coasting %.5f of %.5f J" % [damped.accounted, damped.chemical, coast.accounted, coast.chemical])
	_check("attitude authority survives a throttle chop only with braking", damped.rate_at_8 > 0.3 * damped.target
		and coast.rate_at_8 < 0.05 * damped.target, "damped %.2f, coasting %.2f of %.2f rad/s after eight ticks" % [damped.rate_at_8, coast.rate_at_8, damped.target])


func _pad_and_crash() -> void:
	var data: Dictionary = Fixtures.electric()
	var h: Dictionary = Fixtures.install(root, data)
	var sim: Node = h.sim
	var message: String = Fixtures.reset(sim, h.plant.initial_frame(Fixtures.body(Fixtures.REST_HEIGHT_M)), FC.neutral_input())
	_check("the electrical plant installs with eight continuous values", h.ok and message.is_empty() and sim.model.continuous_size == 8, message)
	var ok: bool = Fixtures.run(sim, FC.neutral_input(), 480)
	_check("CONTACT-01 the disarmed airframe rests on its feet at the solved static sag",
		ok and absf(-sim.state[RB.POS + 2] - Fixtures.REST_HEIGHT_M) < 5e-4 and absf(sim.state[RB.VEL + 2]) < 1e-4
		and absf(sim.state[RB.POS]) < 1e-6 and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED,
		"height %.5f w %s %s" % [-sim.state[RB.POS + 2], String.num_scientific(sim.state[RB.VEL + 2]), sim.fault_reason])
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), 480)
	_check("CONTACT-03 armed idle on the pack neither lifts off nor reports an event", sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED
		and absf(-sim.state[RB.POS + 2] - Fixtures.REST_HEIGHT_M) < 0.004 and sim.continuous[0] > 100.0 and sim.continuous[Plant.C_CUT_LATCH] == 0.0,
		"height %.5f speed %.1f" % [-sim.state[RB.POS + 2], sim.continuous[0]])
	var telemetry: Dictionary = h.plant.telemetry({body = sim.state, continuous = sim.continuous, aux = sim.aux, modes = sim.modes})
	_check("VIS-06 telemetry reports the modelled pack: sag under idle load, charge used", telemetry.has_battery
		and telemetry.bus_voltage_v < 25.2 and telemetry.bus_voltage_v > 24.0 and telemetry.pack_current_a > 0.6 and telemetry.consumed_mah > 0.0,
		"%.3f V %.2f A %.2f mAh" % [telemetry.bus_voltage_v, telemetry.pack_current_a, telemetry.consumed_mah])
	ok = Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.55, 1), 360)
	var climbed: float = -sim.state[RB.POS + 2]
	_check("takeoff: throttle above hover climbs off the pad under closed-loop control", ok and climbed > 2.0
		and absf(_rate(sim, 0)) < 0.05 and absf(_rate(sim, 1)) < 0.05, "height %.2f %s" % [climbed, sim.fault_reason])
	sim.free()
	h = _airborne(Fixtures.electric(), 6.0)
	sim = h.sim
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), 1)
	var events: Array = []
	sim.events_located.connect(func(_tick: int, located: Array[Dictionary]) -> void: events.append_array(located))
	var fell := true
	for _i in 2400:
		fell = fell and Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), 1)
		if not events.is_empty():
			break
	_check("EVENT a disarmed fall ends in one located hard-impact crash", fell and events.size() == 1 and events[0].type == "crash"
		and events[0].reason == "Hard impact" and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_CRASHED and sim.continuous[Plant.C_CUT_LATCH] == 1.0,
		str(events))
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), 2)
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), 240)
	_check("DR-20 a crash needs a pad reset: a fresh arm edge is refused and no second event is published",
		sim.modes[FC.MODE_MOTOR] == FC.MOTOR_CRASHED and sim.modes[FC.MODE_ARM_BLOCK] == FC.BLOCK_TERMINAL and events.size() == 1
		and sim.aux[FC.AUX_COMMAND] == 0.0 and sim.fault_reason.is_empty(), sim.fault_reason)
	var snapshot: Dictionary = sim.checkpoint()
	var restored: bool = not snapshot.is_empty() and sim.restore_checkpoint(snapshot)
	sim.set_paused(false)
	Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.9, 1), 5)
	_check("EVENT-06 a restore at the terminal endpoint still cuts drive", restored and sim.continuous[Plant.C_CUT_LATCH] == 1.0
		and sim.aux[FC.AUX_COMMAND] == 0.0 and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_CRASHED)
	message = Fixtures.reset(sim, h.plant.initial_frame(Fixtures.body(Fixtures.REST_HEIGHT_M)), FC.neutral_input())
	_check("DR-20 a prepared pad reset clears the latch with a disarmed frame", message.is_empty()
		and sim.continuous[Plant.C_CUT_LATCH] == 0.0 and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and sim.tick == 0, message)
	sim.free()
	# Tilted touchdown with spinning rotors: the disc rim reaches the ground first.
	var strike: Dictionary = _airborne(Fixtures.electric(), 0.20, M.q_from_euler(0.0, 0.0, deg_to_rad(70.0)))
	var struck: Array = []
	strike.sim.events_located.connect(func(_tick: int, located: Array[Dictionary]) -> void: struck.append_array(located))
	for _i in 240:
		Fixtures.run(strike.sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), 1)
		if not struck.is_empty():
			break
	_check("CONTACT-05 a spinning disc that reaches the ground is a propeller strike", struck.size() == 1
		and struck[0].reason == "Propeller strike", str(struck))
	strike.sim.free()
	# Obstacle sphere.
	var wall: Dictionary = _airborne(Fixtures.electric(), 20.0)
	wall.plant.obstacle = func(north: float, _east: float, _down: float) -> float: return 3.0 - north
	var hit: Array = []
	wall.sim.events_located.connect(func(_tick: int, located: Array[Dictionary]) -> void: hit.append_array(located))
	for _i in 1200:
		Fixtures.run(wall.sim, Fixtures.pilot(0.0, -0.4, 0.0, wall.throttle + 0.1, 1, 1), 1)
		if not hit.is_empty():
			break
	_check("DR-19 flying into a solid proxy is an obstacle strike before the centre reaches it", hit.size() == 1
		and hit[0].reason == "Obstacle strike" and wall.sim.state[RB.POS] < 3.0 and wall.sim.state[RB.POS] > 2.0,
		"north %.3f %s" % [wall.sim.state[RB.POS], str(hit)])
	wall.sim.free()


func _energy_and_depletion() -> void:
	var h: Dictionary = _airborne(Fixtures.electric(), 30.0)
	var sim: Node = h.sim
	var charge_start: float = 3600.0 * float(h.plant.prepared.battery.capacity_ah) * float(h.plant.prepared.battery.initial_soc)
	var ok: bool = Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, h.throttle, 1), 720)
	var charge_end: float = sim.continuous[Plant.C_CHARGE]
	# Independent chemical-energy reference: the integral of the open-circuit voltage over the charge drawn.
	var chemical := 0.0
	var steps := 4000
	var capacity: float = 3600.0 * float(h.plant.prepared.battery.capacity_ah)
	for i in steps:
		var q0: float = charge_end + (charge_start - charge_end) * float(i) / float(steps)
		var q1: float = charge_end + (charge_start - charge_end) * float(i + 1) / float(steps)
		chemical += 0.5 * (h.plant._ocv(q0 / capacity) + h.plant._ocv(q1 / capacity)) * (q1 - q0)
	var accounted: float = sim.continuous[Plant.C_TERMINAL_ENERGY] + sim.continuous[Plant.C_PACK_LOSS]
	_check("the electrical hover holds altitude with fresh feedback", ok and absf(-sim.state[RB.POS + 2] - 30.0) < 1.0
		and absf(_rate(sim, 0)) < 1e-3, "h %.3f %s" % [-sim.state[RB.POS + 2], sim.fault_reason])
	_check("PHY-06 terminal energy plus pack loss equals the chemical energy drawn over three seconds",
		chemical > 100.0 and absf(accounted - chemical) < 1e-6 * chemical, "chem %.6f J accounted %.6f J" % [chemical, accounted])
	_check("PHY-06 the pack loss is positive and smaller than the terminal energy", sim.continuous[Plant.C_PACK_LOSS] > 0.0
		and sim.continuous[Plant.C_PACK_LOSS] < sim.continuous[Plant.C_TERMINAL_ENERGY])
	sim.free()
	var low: Dictionary = Fixtures.install(root, Fixtures.electric())
	var frame: Dictionary = low.plant.initial_frame(Fixtures.body(60.0), 0, 0.0015)
	var hover_speed: float = sqrt(0.65 * 9.80665 / (4.0 * 1.53e-6))
	for i in 4:
		frame.continuous[i] = hover_speed
	Fixtures.reset(low.sim, frame, FC.neutral_input())
	Fixtures.run(low.sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), 1)
	Fixtures.run(low.sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), 1)
	var depleted: Array = []
	low.sim.events_located.connect(func(_tick: int, located: Array[Dictionary]) -> void: depleted.append_array(located))
	var throttle: float = _hover_throttle(low.plant, frame.continuous)
	var running := true
	for _i in 2400:
		running = running and Fixtures.run(low.sim, Fixtures.pilot(0.0, 0.0, 0.0, throttle, 1), 1)
		if not depleted.is_empty():
			break
	var charge_at_event: float = low.sim.continuous[Plant.C_CHARGE]
	_check("EVENT-02 an exhausted pack is one accepted depletion event with the cut latched", running and depleted.size() == 1
		and depleted[0].type == "pack_depleted" and low.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DEPLETED
		and low.sim.continuous[Plant.C_CUT_LATCH] == 1.0 and charge_at_event <= 0.0 and charge_at_event > -Plant.CHARGE_TOLERANCE,
		"charge %.4f C %s %s" % [charge_at_event, str(depleted), low.sim.fault_reason])
	var coasting := true
	var lowest := INF
	for _i in 480:
		coasting = coasting and Fixtures.run(low.sim, Fixtures.pilot(0.0, 0.0, 0.0, throttle, 1), 1)
		for i in 4:
			lowest = minf(lowest, low.sim.continuous[i])
		if low.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_CRASHED:
			break
	_check("PHY-07 after disconnection no charge is drawn and the shafts coast inside the admitted domain",
		coasting and low.sim.continuous[Plant.C_CHARGE] == charge_at_event and lowest > -Plant.SPEED_TOLERANCE
		and low.sim.continuous[0] < 0.5 * hover_speed, "lowest %.3f now %.1f" % [lowest, low.sim.continuous[0]])
	low.sim.free()
