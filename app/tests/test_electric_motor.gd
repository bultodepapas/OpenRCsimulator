# EL1a verification only. Every motor/prop number below is synthetic, not Lumber calibration.
extends SceneTree

const Electric: Script = preload("res://physics/electric_motor.gd")
const Propulsion: Script = preload("res://physics/propulsion.gd")
const Coupling: Script = preload("res://physics/rotor_coupling.gd")
const RB: Script = preload("res://physics/rigid_body.gd")

var checks: int = 0
var failures: int = 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL: " + label)


func near(label: String, actual: float, expected: float, tolerance: float = 1e-11) -> void:
	check(label + " actual=" + str(actual), is_finite(actual) and absf(actual - expected) <= tolerance)


static func motor_fixture(kv: float = 600.0, resistance: float = 0.2, i0: float = 1.0) -> Dictionary:
	return {kv_rpm_per_volt = kv, resistance_ohm = resistance, no_load_current_a = i0}


func _initialize() -> void:
	_hand_calculation()
	_boundaries()
	_invalid_inputs()
	_power_sweep()
	_propeller_matching()
	_transient()
	_coupling()
	print("EL1a electric source: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _hand_calculation() -> void:
	# Kv=600 rpm/V, rpm=1800 -> E=3 V. Half of 12 V -> 6 V, (6-3)/.2=15 A.
	# Bus current 7.5 A -> 90 W. Copper 45 W, rotational loss 3 W, shaft 42 W.
	var motor: Dictionary = motor_fixture()
	var before: Dictionary = motor.duplicate(true)
	var point: Dictionary = Electric.evaluate(1800.0, 0.5, 12.0, motor)
	check("hand point accepted", point.ok)
	near("EMF in rpm/V", point.back_emf_v, 3.0)
	near("terminal voltage", point.motor_voltage_v, 6.0)
	near("equivalent motor current", point.motor_current_a, 15.0)
	near("battery current includes duty", point.battery_current_a, 7.5)
	near("shaft torque uses SI conversion", point.shaft_torque_nm, 0.22281692032865347)
	near("shaft power", point.shaft_power_w, 42.0)
	near("bus power", point.bus_power_w, 90.0)
	near("copper loss", point.copper_loss_w, 45.0)
	near("rotational loss", point.rotational_loss_w, 3.0)
	check("no mutation of configuration", motor == before)
	check("deterministic and history independent", point == Electric.evaluate(1800.0, 0.5, 12.0, motor))
	var no_load: Dictionary = Electric.evaluate(3480.0, 0.5, 12.0, motor)
	near("no-load torque root includes I0*R", no_load.shaft_torque_nm, 0.0)
	near("no-load electrical current is I0", no_load.motor_current_a, 1.0)


func _boundaries() -> void:
	var motor: Dictionary = motor_fixture()
	for enabled: bool in [false, true]:
		var stopped: Dictionary = Electric.evaluate(0.0, 0.0, 12.0, motor, enabled)
		check("off rest stays stopped", stopped.ok and stopped.mode == "stopped")
		near("rest no torque", stopped.shaft_torque_nm, 0.0)
		near("rest no battery drain", stopped.battery_current_a, 0.0)
	var off: Dictionary = Electric.evaluate(1800.0, 1.0, 12.0, motor, false)
	var zero: Dictionary = Electric.evaluate(1800.0, 0.0, 12.0, motor)
	check("disabled equals duty zero", off == zero)
	check("spinning source coasts", off.mode == "coast")
	near("off consumes no battery power", off.bus_power_w, 0.0)
	near("open motor terminal voltage is back EMF", off.motor_voltage_v, 3.0)
	near("coasting keeps mechanical loss", off.shaft_torque_nm, -0.015915494309189534)
	near("coasting energy dissipates", off.shaft_power_w + off.rotational_loss_w, 0.0)
	var overrun: Dictionary = Electric.evaluate(8000.0, 1.0, 12.0, motor)
	near("no invented regeneration", overrun.battery_current_a, 0.0)
	check("overrun open terminal exceeds commanded bus voltage", overrun.motor_voltage_v > overrun.command_voltage_v)
	var below_friction: Dictionary = Electric.evaluate(0.0, 0.01, 12.0, motor)
	near("small standstill command cannot rotate backwards", below_friction.shaft_torque_nm, 0.0)
	near("blocked motor still heats", below_friction.copper_loss_w, below_friction.bus_power_w)
	var spinning: Dictionary = Electric.evaluate(1.0, 0.01, 12.0, motor)
	check("rotating small command can decelerate", spinning.shaft_torque_nm < 0.0)
	var start: Dictionary = Electric.evaluate(0.0, 1.0, 12.0, motor)
	check("startup has finite positive torque without P/omega", start.ok and start.shaft_torque_nm > 0.0)
	near("stall power becomes copper loss", start.bus_power_w, start.copper_loss_w)
	var no_voltage: Dictionary = Electric.evaluate(0.0, 1.0, 0.0, motor)
	check("zero supply at rest", no_voltage.ok and no_voltage.shaft_torque_nm == 0.0)
	var large_current: Dictionary = Electric.evaluate(0.0, 1.0, 16.0, motor_fixture(800.0, 0.05, 1.0))
	near("no guessed ESC current limiter", large_current.motor_current_a, 320.0)


func _invalid_inputs() -> void:
	for key: String in motor_fixture():
		var absent: Dictionary = motor_fixture()
		absent.erase(key)
		check("missing " + key, not Electric.evaluate(1.0, 0.5, 12.0, absent).ok)
		for bad: Variant in [NAN, INF, -INF, -1.0, true, "1", null, []]:
			var motor: Dictionary = motor_fixture()
			motor[key] = bad
			var rejected: Dictionary = Electric.evaluate(1.0, 0.5, 12.0, motor)
			check("bad " + key + " " + str(bad), not rejected.ok and rejected.has("message") and rejected.size() == 2)
	for key: String in ["kv_rpm_per_volt", "resistance_ohm"]:
		var zero: Dictionary = motor_fixture()
		zero[key] = 0.0
		check("zero " + key, not Electric.evaluate(0.0, 0.0, 12.0, zero).ok)
	for bad: float in [NAN, INF, -INF, -1.0]:
		check("bad rpm", not Electric.evaluate(bad, 0.5, 12.0, motor_fixture()).ok)
		check("bad duty", not Electric.evaluate(1.0, bad, 12.0, motor_fixture()).ok)
		check("bad bus voltage", not Electric.evaluate(1.0, 0.5, bad, motor_fixture()).ok)
	check("duty above one", not Electric.evaluate(1.0, 1.01, 12.0, motor_fixture()).ok)
	check("finite inputs overflowing current", not Electric.evaluate(0.0, 1.0, 1e308, motor_fixture()).ok)
	check("finite inputs overflowing EMF", not Electric.evaluate(1e308, 0.0, 12.0, motor_fixture(1e-300)).ok)
	check("overflow loss cannot hide at rest", not Electric.evaluate(0.0, 0.0, 12.0, motor_fixture(1e-300, 0.2, 1e308)).ok)
	check("overflow copper power", not Electric.evaluate(0.0, 1.0, 1e160, motor_fixture(600.0, 1.0, 0.0)).ok)


func _power_sweep() -> void:
	# Three materially different synthetic drive sizes. No electrical density multiplier exists.
	for motor: Dictionary in [motor_fixture(400.0, 0.08, 0.7), motor_fixture(800.0, 0.06, 1.0), motor_fixture(1400.0, 0.09, 0.5)]:
		for voltage: float in [0.0, 11.1, 14.8, 22.2]:
			for duty: float in [0.0, 0.1, 0.5, 1.0]:
				for rpm: float in [0.0, 1.0, 3000.0, 10000.0, 35000.0]:
					var point: Dictionary = Electric.evaluate(rpm, duty, voltage, motor)
					check("sweep accepted", point.ok)
					near("power conservation including coast", point.bus_power_w,
						point.shaft_power_w + point.copper_loss_w + point.rotational_loss_w,
						1e-11 * maxf(1.0, point.bus_power_w))
					check("loss and input signs", point.copper_loss_w >= 0.0 and point.rotational_loss_w >= 0.0 and point.battery_current_a >= 0.0)
					near("ideal ESC terminal power", point.motor_voltage_v * point.motor_current_a, point.bus_power_w,
						1e-11 * maxf(1.0, point.bus_power_w))


func _propeller_matching() -> void:
	# Independent positive quadratic root for constant Cp static load, then existing prop_torque.
	var motor: Dictionary = motor_fixture(800.0, 0.06, 1.0)
	var prop: Dictionary = {diameter = 0.3, cp = PackedFloat64Array([0.0, 0.06, 1.0, 0.06])}
	var previous_rpm: float = INF
	for rho: float in [0.8, 1.225, 1.6]:
		var a: float = 0.06 * rho * pow(0.3, 5) / (TAU * 3600.0)
		var kt: float = 60.0 / (TAU * 800.0)
		var b: float = kt / (0.06 * 800.0)
		var c: float = kt * (0.6 * 14.8 / 0.06 - 1.0)
		var rpm: float = 2.0 * c / (b + sqrt(b * b + 4.0 * a * c))
		var point: Dictionary = Electric.evaluate(rpm, 0.6, 14.8, motor)
		near("static motor-prop torque balance", point.shaft_torque_nm, Propulsion.prop_torque(rpm, 0.0, prop, rho))
		check("denser air lowers loaded rpm via propeller", rpm < previous_rpm)
		previous_rpm = rpm
		print("EL1a synthetic static: rho=%.3f rpm=%.6f battery_A=%.6f" % [rho, rpm, point.battery_current_a])


static func _rate(rpm: float, motor: Dictionary) -> float:
	return float(Electric.evaluate(rpm, 0.5, 12.0, motor).shaft_torque_nm) / 0.0001 * 60.0 / TAU


static func _rk4(rpm: float, dt: float, motor: Dictionary) -> float:
	var k1: float = _rate(rpm, motor)
	var k2: float = _rate(rpm + dt * k1 / 2.0, motor)
	var k3: float = _rate(rpm + dt * k2 / 2.0, motor)
	var k4: float = _rate(rpm + dt * k3, motor)
	return rpm + dt / 6.0 * (k1 + 2.0 * k2 + 2.0 * k3 + k4)


func _transient() -> void:
	# Clamped carrier and no propeller: an exact linear ODE with I0 losses on its positive-speed branch.
	# This validates a source used at RK stages, not the unimplemented full flight-session integration.
	var motor: Dictionary = motor_fixture(800.0, 0.06, 1.0)
	var kt: float = 60.0 / (TAU * 800.0)
	var tau_s: float = 0.0001 * 0.06 / (kt * kt)
	var exact: float = 4752.0 * (1.0 - exp(-0.1 / tau_s))
	var previous_error: float = INF
	for hz: int in [120, 240, 480, 960]:
		var rpm: float = 0.0
		for _i: int in hz / 10:
			rpm = _rk4(rpm, 1.0 / hz, motor)
		var error: float = absf(rpm - exact)
		check("no-load transient agrees with exact exponential", error < 0.02)
		if is_finite(previous_error):
			check("smooth RK4 refinement approaches factor 16", previous_error / error > 14.0 and previous_error / error < 19.0)
		previous_error = error
		print("EL1a no-load: Hz=%d rpm_error=%.12f" % [hz, error])


func _coupling() -> void:
	# Source torque exchanges momentum internally. At rest with zero prop load, Jcarrier=.099.
	var source: Dictionary = Electric.evaluate(0.0, 0.5, 12.0, motor_fixture())
	var inertia: PackedFloat64Array = PackedFloat64Array([0.1, 0.2, 0.3, 0.0, 0.0, 0.0])
	var result: Dictionary = Coupling.response(PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]), inertia, RB.inertia_inverse(inertia),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.001, 0.0, source.shaft_torque_nm)
	check("existing rotor coupling accepts electric source", result.ok)
	var body_acceleration: float = result.reaction[0] / 0.1
	near("stator accelerates carrier in opposite direction", body_acceleration, -float(source.shaft_torque_nm) / 0.099)
	near("internal torque conserves angular momentum", 0.1 * body_acceleration + 0.001 * float(result.spin_acceleration), 0.0)
