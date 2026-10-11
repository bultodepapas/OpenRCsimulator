# EL2a synthetic battery algebra checks. Values here are hand fixtures, not Timber calibration.
extends SceneTree

const Supply: Script = preload("res://physics/electric_supply.gd")
const Electric: Script = preload("res://physics/electric_motor.gd")

var checks: int = 0
var failures: int = 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL: " + label)


func near(label: String, actual: float, expected: float, tolerance: float = 1e-10) -> void:
	check(label + " actual=" + str(actual) + " expected=" + str(expected),
		is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


static func motor_fixture(kv: float = 600.0, resistance: float = 0.2, no_load: float = 1.0) -> Dictionary:
	return {"kv_rpm_per_volt": kv, "resistance_ohm": resistance, "no_load_current_a": no_load}


static func pack_fixture(resistance: float = 0.1, auxiliary: float = 0.5,
		capacity: float = 2.0) -> Dictionary:
	return {
		"ocv_points": PackedFloat64Array([0.0, 10.0, 0.5, 12.0, 1.0, 14.0]),
		"capacity_ah": capacity,
		"resistance_ohm": resistance,
		"auxiliary_current_a": auxiliary,
	}


func _initialize() -> void:
	_hand_algebra_and_energy()
	_zero_pack_resistance_and_auxiliary_case()
	_boundaries_and_exhaustion()
	_invalid_inputs()
	_overflow_and_input_immutability()
	print("EL2a electric supply: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _hand_algebra_and_energy() -> void:
	# At SOC=.5, OCV=12 V; E=3 V; d=.5; Rm=.2 ohm; Rpack=.1 ohm; Iaux=.5 A.
	# Im=(.5*(12-.1*.5)-3)/(.2+.5^2*.1)=119/9 A.
	# Ibus=119/18 A; Ipack=64/9 A; Vbus=508/45 V.
	var pack: Dictionary = pack_fixture()
	var motor: Dictionary = motor_fixture()
	var pack_before: Dictionary = pack.duplicate(true)
	var motor_before: Dictionary = motor.duplicate(true)
	var point: Dictionary = Supply.evaluate(1800.0, 0.5, 0.5, pack, motor)
	check("hand point accepted", point.ok)
	near("linear OCV", point.ocv_v, 12.0)
	near("motor current from d-squared sag", point.motor_current_a, 119.0 / 9.0)
	near("motor bus current", point.motor_bus_current_a, 119.0 / 18.0)
	near("pack current includes pack-side auxiliary", point.pack_current_a, 64.0 / 9.0)
	near("terminal bus voltage", point.bus_voltage_v, 508.0 / 45.0)
	near("charge rate is pack current", point.charge_rate_coulombs_per_s, 64.0 / 9.0)
	near("SOC depletion uses Ah and seconds", point.soc_rate_per_s, -(64.0 / 9.0) / 7200.0)
	near("pack energy rate includes auxiliary load", point.energy_rate_j_per_s, (508.0 / 45.0) * (64.0 / 9.0))
	near("pack internal loss", point.pack_loss_w, 0.1 * (64.0 / 9.0) * (64.0 / 9.0))
	near("pack chemical power balance", point.pack_open_circuit_power_w,
		point.pack_terminal_power_w + point.pack_loss_w)
	near("pack balance residual", point.pack_power_balance_residual_w, 0.0)
	near("motor port power balance", point.motor_bus_power_w,
		point.shaft_power_w + point.motor_copper_loss_w + point.motor_rotational_loss_w)
	near("motor port equals terminal voltage times bus current", point.motor_bus_power_w,
		point.bus_voltage_v * point.motor_bus_current_a)
	check("source kernel result is included", point.source.ok and point.source.mode == "drive")
	check("configuration inputs are not mutated", pack == pack_before and motor == motor_before)
	check("repeat evaluation is deterministic", point == Supply.evaluate(1800.0, 0.5, 0.5, pack, motor))


func _zero_pack_resistance_and_auxiliary_case() -> void:
	var pack: Dictionary = pack_fixture(0.0, 0.5)
	var motor: Dictionary = motor_fixture()
	var fixed: Dictionary = Supply.evaluate(1800.0, 0.5, 0.5, pack, motor)
	var source: Dictionary = Electric.evaluate(1800.0, 0.5, 12.0, motor)
	check("zero pack resistance accepted", fixed.ok)
	near("zero resistance is prescribed OCV", fixed.bus_voltage_v, 12.0)
	near("zero resistance source matches EL1a", fixed.motor_current_a, source.motor_current_a)
	near("zero resistance pack current adds auxiliary", fixed.pack_current_a, source.battery_current_a + 0.5)
	near("zero resistance pack loss", fixed.pack_loss_w, 0.0)
	near("zero resistance energy rate", fixed.energy_rate_j_per_s, 12.0 * fixed.pack_current_a)

	pack = pack_fixture(0.1, 0.0)
	var no_aux: Dictionary = Supply.evaluate(1800.0, 0.5, 0.5, pack, motor)
	near("no auxiliary pack current equals motor bus current", no_aux.pack_current_a, no_aux.motor_bus_current_a)
	near("no auxiliary SOC rate uses motor bus current", no_aux.soc_rate_per_s,
		-no_aux.motor_bus_current_a / 7200.0)


func _boundaries_and_exhaustion() -> void:
	var pack: Dictionary = pack_fixture()
	var motor: Dictionary = motor_fixture()
	var zero_duty: Dictionary = Supply.evaluate(1800.0, 0.0, 0.5, pack, motor)
	check("zero duty accepted", zero_duty.ok and zero_duty.mode == "coast")
	near("zero duty has no drive current", zero_duty.motor_bus_current_a, 0.0)
	near("zero duty still draws auxiliary current", zero_duty.pack_current_a, 0.5)
	near("zero duty bus sag is auxiliary only", zero_duty.bus_voltage_v, 11.95)
	near("zero duty motor terminal is open-circuit EMF", zero_duty.source.motor_voltage_v, 3.0)

	var disabled: Dictionary = Supply.evaluate(1800.0, 1.0, 0.5, pack, motor, false)
	check("disabled source coasts", disabled.ok and disabled.mode == "coast")
	near("disabled motor draws no bus current", disabled.motor_bus_current_a, 0.0)
	near("disabled source retains auxiliary pack draw", disabled.pack_current_a, 0.5)
	near("disabled source still depletes SOC", disabled.soc_rate_per_s, -0.5 / 7200.0)
	near("disabled source still supplies auxiliary energy", disabled.energy_rate_j_per_s, 11.95 * 0.5)
	near("disabled source keeps mechanical coast loss", disabled.shaft_power_w + disabled.motor_rotational_loss_w, 0.0)

	var full_duty: Dictionary = Supply.evaluate(1800.0, 1.0, 0.5, pack, motor)
	check("full duty accepted", full_duty.ok and full_duty.motor_current_a > zero_duty.motor_current_a)
	near("full duty uses d-squared pack sag", full_duty.motor_current_a, 8.95 / 0.3)
	near("full duty terminal voltage", full_duty.bus_voltage_v, 12.0 - 0.1 * (8.95 / 0.3 + 0.5))
	var overrun: Dictionary = Supply.evaluate(8000.0, 1.0, 0.5, pack, motor)
	check("back EMF branch returns no motor draw", overrun.ok and overrun.motor_current_a == 0.0)
	near("overrun still powers auxiliary load", overrun.pack_current_a, 0.5)

	var exhausted: Dictionary = Supply.evaluate(1800.0, 1.0, 0.0, pack, motor)
	check("empty SOC is explicitly exhausted", exhausted.ok and exhausted.mode == "exhausted")
	near("exhausted point retains diagnostic OCV", exhausted.ocv_v, 10.0)
	near("exhausted pack has zero bus voltage", exhausted.bus_voltage_v, 0.0)
	near("exhausted motor is disconnected", exhausted.motor_bus_current_a, 0.0)
	near("exhausted pack current is zero", exhausted.pack_current_a, 0.0)
	near("exhausted auxiliary delivery is zero", exhausted.auxiliary_current_a, 0.0)
	near("exhausted auxiliary demand is reported", exhausted.auxiliary_demand_a, 0.5)
	near("exhausted SOC rate does not overdraw", exhausted.soc_rate_per_s, 0.0)
	check("exhausted source is coasting", exhausted.source.mode == "coast")


func _invalid_inputs() -> void:
	var pack: Dictionary = pack_fixture()
	var motor: Dictionary = motor_fixture()
	for bad: Variant in [NAN, INF, -INF, -0.01, 1.01, true, "0.5", null]:
		check("invalid SOC rejected " + str(bad), not Supply.evaluate(1800.0, 0.5, bad, pack, motor).ok)
	for bad: Variant in [NAN, INF, -INF, -1.0, true, "0", null]:
		check("invalid RPM rejected " + str(bad), not Supply.evaluate(bad, 0.5, 0.5, pack, motor).ok)
	for bad: Variant in [NAN, INF, -INF, -0.01, 1.01, true, "0.5", null]:
		check("invalid duty rejected " + str(bad), not Supply.evaluate(1800.0, bad, 0.5, pack, motor).ok)
	check("nonboolean enabled rejected", not Supply.evaluate(1800.0, 0.5, 0.5, pack, motor, 1).ok)

	var invalid: Dictionary = pack.duplicate(true)
	invalid.ocv_points = PackedFloat64Array([0.1, 10.0, 1.0, 14.0])
	check("OCV must cover zero SOC", not Supply.evaluate(1800.0, 0.5, 0.5, invalid, motor).ok)
	invalid = pack.duplicate(true)
	invalid.ocv_points = PackedFloat64Array([0.0, 10.0, 0.5, 12.0, 0.9, 14.0])
	check("OCV must cover full SOC", not Supply.evaluate(1800.0, 0.5, 0.5, invalid, motor).ok)
	invalid = pack.duplicate(true)
	invalid.ocv_points = PackedFloat64Array([0.0, 10.0, 0.5, 12.0, 0.5, 13.0, 1.0, 14.0])
	check("duplicate SOC knot rejected", not Supply.evaluate(1800.0, 0.5, 0.5, invalid, motor).ok)
	invalid = pack.duplicate(true)
	invalid.ocv_points = PackedFloat64Array([0.0, 10.0, 0.5, 13.0, 1.0, 12.0])
	check("nonmonotonic OCV rejected", not Supply.evaluate(1800.0, 0.5, 0.5, invalid, motor).ok)
	invalid = pack.duplicate(true)
	invalid.ocv_points = PackedFloat64Array([0.0, 10.0, 0.5, 0.0, 1.0, 14.0])
	check("nonpositive OCV rejected", not Supply.evaluate(1800.0, 0.5, 0.5, invalid, motor).ok)
	invalid = pack.duplicate(true)
	invalid.ocv_points = PackedFloat64Array([0.0, 10.0, NAN, 12.0, 1.0, 14.0])
	check("nonfinite OCV knot rejected", not Supply.evaluate(1800.0, 0.5, 0.5, invalid, motor).ok)
	invalid = pack.duplicate(true)
	invalid.capacity_ah = 0.0
	check("zero capacity rejected", not Supply.evaluate(1800.0, 0.5, 0.5, invalid, motor).ok)
	invalid = pack.duplicate(true)
	invalid.resistance_ohm = -0.1
	check("negative pack resistance rejected", not Supply.evaluate(1800.0, 0.5, 0.5, invalid, motor).ok)
	invalid = pack.duplicate(true)
	invalid.auxiliary_current_a = -0.1
	check("negative auxiliary current rejected", not Supply.evaluate(1800.0, 0.5, 0.5, invalid, motor).ok)
	invalid = pack.duplicate(true)
	invalid.unmodeled_rc_voltage = 0.3
	check("unsupported battery state field rejected", not Supply.evaluate(1800.0, 0.5, 0.5, invalid, motor).ok)
	invalid = pack.duplicate(true)
	invalid.ocv_points = [0.0, 10.0, 1.0, 14.0]
	check("wrong OCV point representation rejected", not Supply.evaluate(1800.0, 0.5, 0.5, invalid, motor).ok)
	check("non-dictionary pack rejected", not Supply.evaluate(1800.0, 0.5, 0.5, null, motor).ok)
	check("non-dictionary motor rejected", not Supply.evaluate(1800.0, 0.5, 0.5, pack, null).ok)
	var invalid_motor: Dictionary = motor.duplicate(true)
	invalid_motor.phase_current_a = 12.0
	check("unmodeled motor current convention rejected",
		not Supply.evaluate(1800.0, 0.5, 0.5, pack, invalid_motor).ok)


func _overflow_and_input_immutability() -> void:
	var pack: Dictionary = pack_fixture()
	var motor: Dictionary = motor_fixture()
	var huge_capacity: Dictionary = pack.duplicate(true)
	huge_capacity.capacity_ah = 1e308
	check("finite capacity overflowing coulombs rejected", not Supply.evaluate(1800.0, 0.5, 0.5, huge_capacity, motor).ok)
	check("connected boundary also rejects capacity overflow", not Supply.evaluate_available(1800.0, 0.5, 0.0, huge_capacity, motor).ok)
	var tiny_capacity: Dictionary = pack.duplicate(true)
	tiny_capacity.capacity_ah = 1e-320
	check("finite inputs overflowing SOC rate fail closed",
		not Supply.evaluate(1800.0, 0.5, 0.5, tiny_capacity, motor).ok)

	var huge_pack: Dictionary = {
		"ocv_points": PackedFloat64Array([0.0, 1e308, 1.0, 1e308]),
		"capacity_ah": 1.0,
		"resistance_ohm": 0.0,
		"auxiliary_current_a": 1e308,
	}
	check("finite inputs overflowing pack energy fail closed",
		not Supply.evaluate(0.0, 0.0, 0.5, huge_pack, motor).ok)

	var pack_before: Dictionary = pack.duplicate(true)
	var motor_before: Dictionary = motor.duplicate(true)
	var point: Dictionary = Supply.evaluate(2500.0, 0.4, 0.7, pack, motor)
	check("normal evaluation accepted after overflow cases", point.ok)
	check("overflow paths do not mutate pack input", pack == pack_before)
	check("overflow paths do not mutate motor input", motor == motor_before)
