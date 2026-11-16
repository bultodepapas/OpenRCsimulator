# DR-05/18 battery-power regression: independent numerical oracles, not hardware validation.
extends SceneTree

const Bus := preload("res://physics/multirotor/power_bus.gd")
const Battery := preload("res://physics/multirotor/battery_pack.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const Session := preload("res://sim/multirotor/session.gd")
const Rates := preload("res://physics/multirotor/rates.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s %s" % ["ok" if ok else "FAIL", label, detail])

func _close(a: float, b: float, tolerance := 1e-10) -> bool:
	return is_finite(a) and absf(a - b) <= tolerance * maxf(1.0, absf(b))

func _four(value: float) -> PackedFloat64Array:
	return PackedFloat64Array([value, value, value, value])

func _solve(emf: PackedFloat64Array, duty := 0.5, auxiliary := 0.5, resistance := 0.05) -> Dictionary:
	return Bus.solve(24.0, resistance, auxiliary, _four(duty), emf, _four(0.1), PackedInt64Array([1, 1, 1, 1]))

func _balance(bus: Dictionary, source: float, pack_r: float) -> bool:
	if not bus.ok:
		return false
	var motor_power := 0.0
	for i in 4:
		motor_power += bus.p_motor_bus_w[i]
		if not _close(bus.p_motor_bus_w[i], bus.p_em_w[i] + bus.p_motor_resistive_w[i]) \
				or not _close(bus.p_motor_resistive_w[i], 0.1 * bus.i_motor_rms[i] * bus.i_motor_rms[i]):
			return false
	return _close(source * bus.i_pack, bus.p_terminal_w + pack_r * bus.i_pack * bus.i_pack) \
		and _close(bus.p_terminal_w, motor_power + bus.p_aux_w)

func _run() -> void:
	_bus_oracles()
	_brake_integral()
	_pack_pulse()
	_boundaries()
	_full_charge_air_start()
	print("%d power checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _bus_oracles() -> void:
	var brake := _solve(_four(16.0))
	_check("surplus brake preserves signed mean torque with zero pack charge", brake.ok and brake.charge_limited
		and brake.i_pack == 0.0 and brake.v_bus == 24.0 and brake.i_motor == _four(-40.0)
		and _close(brake.regeneration_fraction, 0.00625))
	_check("independent equivalent RMS/brake loss oracle: 637 W per motor, 12 W auxiliaries", brake.ok
		and brake.p_motor_bus_w == _four(-3.0) and brake.p_motor_resistive_w == _four(637.0)
		and _close(brake.i_motor_rms[0] * brake.i_motor_rms[0], 6370.0) and brake.p_aux_w == 12.0)
	_check("whole bus and each motor path conserve power, without counting brake excess twice", _balance(brake, 24.0, 0.05))
	var mixed := _solve(PackedFloat64Array([16.0, 8.0, 12.0, 12.0]))
	_check("mixed motors share regeneration with a drawing pack", mixed.ok and not mixed.charge_limited
		and _close(mixed.i_pack, 1.0 / 3.0) and _close(mixed.v_bus, 23.983333333333333)
		and mixed.p_brake_loss_w == 0.0 and mixed.i_motor[0] < 0.0 and mixed.i_motor[1] > 0.0
		and _balance(mixed, 24.0, 0.05))
	var no_aux := _solve(_four(16.0), 0.5, 0.0, 0.0)
	_check("zero pack resistance and zero auxiliary draw still conserve braking energy", no_aux.ok
		and no_aux.i_pack == 0.0 and no_aux.regeneration_fraction == 0.0 and _balance(no_aux, 24.0, 0.0))
	var reversed := _solve(_four(-4.0), 0.5, 0.0, 0.0)
	_check("signed reverse shaft opposes rotation and has exact power accounting", reversed.ok
		and reversed.i_motor == _four(160.0) and reversed.p_motor_resistive_w == _four(2560.0)
		and reversed.p_em_w == _four(-640.0) and _balance(reversed, 24.0, 0.0))
	var shorted := _solve(_four(-4.0), 0.0, 0.0, 0.0)
	_check("enabled zero duty is an active short, distinct from disarm", shorted.ok and shorted.i_motor == _four(40.0)
		and shorted.i_pack == 0.0 and shorted.p_motor_resistive_w == _four(160.0) and _balance(shorted, 24.0, 0.0))
	var disabled := Bus.solve(24.0, 0.0, 0.0, _four(0.5), _four(-4.0), _four(0.1), PackedInt64Array([0, 0, 0, 0]))
	_check("disabled motors carry neither current nor heat", disabled.ok and disabled.i_motor == _four(0.0)
		and disabled.p_motor_resistive_w == _four(0.0) and disabled.i_pack == 0.0)
	_check("coast is refused above effective bus voltage", not _solve(_four(25.0)).ok)
	var tiny := Bus.solve(1e-12, 0.0, 0.0, _four(0.5), _four(5e-11), _four(0.1), PackedInt64Array([1, 1, 1, 1]))
	_check("the coast domain guard is relative to the actual voltage, including tiny sources", not tiny.ok)
	var boundary_ok := true
	var boundary_currents := PackedFloat64Array()
	for adjacent: float in [26.883400566739283, 26.883400566739287, 26.88340056673929]:
		var out := Bus.solve(28.191742396790914, 0.05, 0.35134969967261753,
			PackedFloat64Array([0.8358856102236664, 0.10439334790712687, 0.0, 0.0]),
			PackedFloat64Array([17.28853647958276, adjacent, 0.0, 0.0]),
			PackedFloat64Array([0.17070920515410162, 0.08040018116690785, 1.0, 1.0]), PackedInt64Array([1, 1, 0, 0]))
		boundary_ok = boundary_ok and out.ok
		if out.ok:
			boundary_ok = boundary_ok and out.i_pack >= 0.0 and out.i_pack < 1e-12 \
				and out.regeneration_fraction >= 0.0 and out.regeneration_fraction <= 1.0
			boundary_currents.append(out.i_pack)
	_check("adjacent-ULP load/generation cancellation neither faults nor charges", boundary_ok, str(boundary_currents))
	var random := RandomNumberGenerator.new()
	random.seed = 16112026
	var grid_ok := true
	for _i in 1000:
		var duties := PackedFloat64Array()
		var emf := PackedFloat64Array()
		for _motor in 4:
			duties.append(random.randf_range(0.0, 1.0))
			emf.append(random.randf_range(-3.0, 23.9))
		var out := Bus.solve(24.0, 0.02, 0.6, duties, emf, _four(0.1), PackedInt64Array([1, 1, 1, 1]))
		grid_ok = grid_ok and out.ok and out.i_pack >= 0.0 and _balance(out, 24.0, 0.02)
	_check("1000 mixed signed-shaft states conserve power without net pack charging", grid_ok)

# Independent exponential shaft oracle with 4 symmetric rotors: w=1200+400 exp(-t), J=0.001, Kv=100.
# Integrate the actual bus current and effective path heat, not the closed-form expected trajectory.
func _brake_rate(x: PackedFloat64Array) -> PackedFloat64Array:
	var bus := _solve(_four(x[0] / 100.0), 0.5, 0.5, 0.0)
	if not bus.ok:
		return PackedFloat64Array([NAN, NAN, NAN])
	return PackedFloat64Array([bus.i_motor[0] / (100.0 * 0.001),
		bus.p_motor_resistive_w[0] + bus.p_motor_resistive_w[1] + bus.p_motor_resistive_w[2] + bus.p_motor_resistive_w[3], bus.p_aux_w])

func _plus(x: PackedFloat64Array, k: PackedFloat64Array, h: float) -> PackedFloat64Array:
	var out := x.duplicate()
	for i in out.size():
		out[i] += h * k[i]
	return out

func _brake_integral() -> void:
	var errors := []
	for hz in [60, 120, 240]:
		var x := PackedFloat64Array([1600.0, 0.0, 0.0])
		var dt := 1.0 / float(hz)
		for _i in hz:
			var k1 := _brake_rate(x)
			var k2 := _brake_rate(_plus(x, k1, 0.5 * dt))
			var k3 := _brake_rate(_plus(x, k2, 0.5 * dt))
			var k4 := _brake_rate(_plus(x, k3, dt))
			for j in x.size():
				x[j] += dt * (k1[j] + 2.0 * k2[j] + 2.0 * k3[j] + k4[j]) / 6.0
		var expected := 1200.0 + 400.0 * exp(-1.0)
		var released := 0.5 * 4.0 * 0.001 * (1600.0 * 1600.0 - expected * expected)
		errors.append(absf(x[1] + x[2] - released))
		_check("braking trajectory and kinetic-to-heat/auxiliary integral at %d Hz" % hz,
			_close(x[0], expected, 1e-9) and _close(x[1] + x[2], released, 1e-9)
			and _close(x[2], 12.0), "energy error %s J" % String.num_scientific(errors[-1]))
	_check("braking energy refinement converges (60 to 120 to 240 Hz)", errors[1] < errors[0] / 10.0
		and errors[2] < errors[1] / 8.0, str(errors))

func _pack_pulse() -> void:
	var data := Fixtures.electric()
	data.battery.ocv_points = PackedFloat64Array([0.0, 24.0, 1.0, 24.0])
	data.battery.resistance_ohm = 0.02
	data.battery.polarization_resistance_ohm = 0.01
	data.battery.polarization_time_s = 1.0
	data.battery.auxiliary_current_a = 10.0
	var h := Fixtures.install(root, data)
	if not h.ok:
		_check("RC plant installs", false, str(h.errors))
		return
	var sim: Node = h.sim
	var initial: Dictionary = h.plant.initial_frame(Fixtures.body(Fixtures.REST_HEIGHT_M))
	var reset: String = Fixtures.reset(sim, initial, FC.neutral_input())
	var ran: bool = reset.is_empty() and Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), 240)
	var frame := {body = sim.state, continuous = sim.continuous, aux = sim.aux, modes = sim.modes}
	var telemetry: Dictionary = h.plant.telemetry(frame)
	var expected_vp := 0.1 * (1.0 - exp(-1.0))
	var expected_heat := 2.0 + 1.0 - 2.0 * (1.0 - exp(-1.0)) + 0.5 * (1.0 - exp(-2.0))
	_check("actual plant: one-second 10 A pulse integrates charge and delayed sag", ran
		and _close(sim.continuous[Plant.C_POLARIZATION], expected_vp, 1e-11)
		and _close(initial.continuous[Plant.C_CHARGE] - sim.continuous[Plant.C_CHARGE], 10.0, 1e-9)
		and _close(telemetry.bus_voltage_v, 24.0 - 0.2 - expected_vp, 1e-11), sim.fault_reason)
	_check("RC heat and stored energy close chemical-to-terminal accounting", ran
		and _close(sim.continuous[Plant.C_PACK_LOSS], expected_heat, 1e-9)
		and _close(sim.continuous[Plant.C_TERMINAL_ENERGY] + sim.continuous[Plant.C_PACK_LOSS]
			+ telemetry.polarization_energy_j, 240.0, 1e-9))
	# A depleted checkpoint isolates pack current but keeps its existing polarization memory.
	var depleted: Dictionary = frame.duplicate(true)
	depleted.continuous[Plant.C_CHARGE] = 0.0
	depleted.continuous[Plant.C_CUT_LATCH] = 1.0
	depleted.modes[FC.MODE_MOTOR] = FC.MOTOR_DEPLETED
	var stored_before: float = telemetry.polarization_energy_j
	var heat_before: float = sim.continuous[Plant.C_PACK_LOSS]
	var terminal_before: float = sim.continuous[Plant.C_TERMINAL_ENERGY]
	reset = Fixtures.reset(sim, depleted, FC.neutral_input())
	ran = reset.is_empty() and Fixtures.run(sim, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), 240)
	var recovered := Battery.branch(data.battery, sim.continuous[Plant.C_POLARIZATION], 0.0)
	_check("depleted pack still relaxes over one second without drawing charge", ran and sim.continuous[Plant.C_CHARGE] == 0.0
		and _close(sim.continuous[Plant.C_POLARIZATION], expected_vp * exp(-1.0), 1e-11)
		and sim.continuous[Plant.C_TERMINAL_ENERGY] == terminal_before, sim.fault_reason)
	_check("disconnected polarization energy becomes pack heat", _close(sim.continuous[Plant.C_PACK_LOSS]
		- heat_before + recovered.stored_j, stored_before, 1e-10))
	sim.free()

func _boundaries() -> void:
	var data := Fixtures.electric()
	var made := Plant.create(data, Rates.default_profile(), FC.THROTTLE_ABSOLUTE)
	_check("resistive limiting pack remains available", made.ok)
	if not made.ok:
		return
	var frame: Dictionary = made.plant.initial_frame(Fixtures.body(2.0))
	frame.continuous[Plant.C_CHARGE] += 0.01
	_check("overcharged checkpoint state is refused instead of SOC-clamped", not made.plant.state_validator(frame, {}))
	frame = made.plant.initial_frame(Fixtures.body(2.0))
	frame.continuous[Plant.C_POLARIZATION] = 0.01
	_check("R1=0 cannot conceal stored polarization", not made.plant.state_validator(frame, {}))
	data.powertrain.braking = "damped"
	_check("unbounded legacy regeneration is explicitly retired", not Plant.create(data, Rates.default_profile(), FC.THROTTLE_ABSOLUTE).ok)

# Original A06 product witness: research air start pre-spins shafts before arming at full charge.
func _full_charge_air_start() -> void:
	for soc: float in [1.0, 0.999]:
		var session := Session.new()
		root.add_child(session)
		var ok: bool = session.prepare({}, {start = "air", altitude_m = 20.0, initial_soc = soc}) and session.resume()
		var capacity: float = 3600.0 * float(session.data.battery.capacity_ah) if ok else NAN
		var initial_charge: float = session.sim.continuous[Plant.C_CHARGE] if ok else NAN
		var max_charge := initial_charge
		var lowest_current := INF
		var saw_brake := false
		for phase: Array in [[1, 0.0, 0], [24, 0.0, 1], [96, 0.8, 1], [96, 0.0, 1]]:
			for _tick in int(phase[0]):
				if not ok or not session.tick_once(Fixtures.pilot(0.0, 0.0, 0.0, float(phase[1]), int(phase[2]))):
					ok = false
					break
				var telemetry: Dictionary = session.telemetry()
				max_charge = maxf(max_charge, session.sim.continuous[Plant.C_CHARGE])
				lowest_current = minf(lowest_current, telemetry.pack_current_a)
				saw_brake = saw_brake or telemetry.brake_heat_w > 0.0
		var current_tick: int = session.sim.tick if session.prepared else 0
		_check("product air start at SOC %.3f: arm, punch and chop never overcharge or fault" % soc,
			ok and current_tick == 217 and session.crash.is_empty() and session.fault_reason.is_empty()
			and max_charge <= capacity and max_charge <= initial_charge and lowest_current >= 0.0 and saw_brake,
			"tick %d, max Q %.12f C, minimum current %.12f A %s" % [current_tick, max_charge, lowest_current, session.fault_reason])
		session.free()
