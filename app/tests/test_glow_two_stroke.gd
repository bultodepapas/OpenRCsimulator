extends SceneTree

const Kernel := preload("res://physics/glow/two_stroke.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _near(label: String, actual: float, expected: float) -> void:
	var tolerance := maxf(1e-15, absf(expected) * 1e-10)
	_check(label, is_finite(actual) and absf(actual - expected) <= tolerance,
		"got %s, expected %s" % [String.num_scientific(actual), String.num_scientific(expected)])


func _table(x_values: PackedFloat64Array, y_values: PackedFloat64Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for index in range(x_values.size()):
		result.append(x_values[index])
		result.append(y_values[index])
	return result


func _parameters() -> Dictionary:
	var rpm_knots := PackedFloat64Array([0.0, 12000.0])
	return {
		"displacement_m3": 1e-5,
		"oil_fraction": 0.1,
		"stoich_air_fuel_ratio": 10.0,
		"fuel_lhv_j_kg": 1e6,
		"mechanical_torque_nm": _table(rpm_knots, PackedFloat64Array([0.01, 0.01])),
		"combustion_efficiency": _table(PackedFloat64Array([0.0, 2.0]), PackedFloat64Array([0.8, 0.8])),
		"indicated_efficiency": _table(rpm_knots, PackedFloat64Array([0.5, 0.5])),
		"delivery_ratio": _table(rpm_knots, PackedFloat64Array([2.0, 2.0])),
		"trapping_efficiency": _table(rpm_knots, PackedFloat64Array([0.5, 0.5])),
		"scavenge_pressure_pa": _table(rpm_knots, PackedFloat64Array([1000.0, 1000.0])),
	}


func _initialize() -> void:
	var rpm := 6000.0
	var parameters := _parameters()
	var result: Dictionary = Kernel.evaluate(rpm, 0.5, 0.8, 1.0, parameters)
	_check("hand fixture is accepted", result.ok, str(result.message))

	# Hand values: 10 mg air is delivered per revolution, 5 mg is trapped;
	# premix is 0.8888889 mg/rev, 0.4 mg combustible is trapped, and 0.32 mg burns.
	# That gives 0.16 J indicated work/rev, 0.02546479 Nm, and 16 W at 100 rev/s.
	_near("trapped charge follows delivery and trapping", result.air_charge_kg_cycle, 5e-6)
	_near("gross premix flow includes the oil fraction", result.delivered_fuel_kg_s, 8.888888888888889e-5)
	_near("burned flow follows the trapped combustible mass", result.burned_fuel_kg_s, 3.2e-5)
	_near("unburned flow is gross premix less burned fuel", result.unburned_fuel_kg_s, 5.688888888888889e-5)
	_near("gross combustible energy input", result.fuel_input_power_w, 80.0)
	_near("burned chemical power", result.chemical_power_w, 32.0)
	_near("cycle work is burned fuel energy times indicated efficiency", result.cycle_work_j, 0.16)
	_near("indicated torque is cycle work divided by 2 pi", result.indicated_torque_nm, 0.16 / TAU)
	_near("indicated power is cycle work times opportunities per second", result.indicated_power_w, 16.0)
	_near("mechanical loss uses the independent Qm table", result.mechanical_torque_nm, 0.01)
	_near("scavenging work sets pumping torque", result.pumping_torque_nm, 0.01 / TAU)
	_near("mechanical loss power closes at shaft speed", result.mechanical_loss_w, 0.01 * TAU * 100.0)
	_near("pumping loss power closes at shaft speed", result.pumping_loss_w, 1.0)
	_near("shaft torque subtracts both moving losses", result.shaft_torque_nm,
		0.16 / TAU - 0.01 - 0.01 / TAU)
	_check("two-stroke has one opportunity per revolution", result.cycle_frequency_hz == 100.0 \
		and result.opportunity_frequency_hz == 100.0 and result.firing_frequency_hz == 100.0)
	_check("valve path is explicitly zero", result.valve_torque_nm == 0.0 and result.valve_loss_w == 0.0)
	_check("every reported numeric field is finite", _reported_values_are_finite(result))
	var rich: Dictionary = Kernel.evaluate(rpm, 0.5, 1.5, 1.0, parameters)
	_near("rich mixture burning is capped by trapped oxygen", rich.burned_fuel_kg_s, 4e-5)
	_near("rich premix still counts all combustible energy delivered", rich.fuel_input_power_w, 150.0)

	var less_delivery := _parameters()
	less_delivery["delivery_ratio"] = _table(PackedFloat64Array([0.0, 12000.0]),
		PackedFloat64Array([1.0, 1.0]))
	var delivery_result: Dictionary = Kernel.evaluate(rpm, 0.5, 0.8, 1.0, less_delivery)
	_near("delivery ratio halves trapped air", delivery_result.air_charge_kg_cycle, 2.5e-6)
	_near("delivery ratio halves gross fuel flow", delivery_result.delivered_fuel_kg_s, 4.444444444444444e-5)
	_near("delivery ratio halves scavenging torque", delivery_result.pumping_torque_nm, 0.005 / TAU)

	var less_trapping := _parameters()
	less_trapping["trapping_efficiency"] = _table(PackedFloat64Array([0.0, 12000.0]),
		PackedFloat64Array([0.25, 0.25]))
	var trapping_result: Dictionary = Kernel.evaluate(rpm, 0.5, 0.8, 1.0, less_trapping)
	_near("trapping ratio halves trapped charge", trapping_result.air_charge_kg_cycle, 2.5e-6)
	_near("trapping ratio halves burned fuel", trapping_result.burned_fuel_kg_s, 1.6e-5)
	_near("trapping does not change fuel already delivered", trapping_result.delivered_fuel_kg_s,
		result.delivered_fuel_kg_s)

	var skipped: Dictionary = Kernel.evaluate(rpm, 0.5, 0.8, 1.0, parameters, true, 0.5)
	_near("half the firing opportunities halves indicated torque", skipped.indicated_torque_nm,
		result.indicated_torque_nm * 0.5)
	_near("skipped firing retains the two-stroke cycle frequency", skipped.cycle_frequency_hz, 100.0)
	_near("skipped firing retains opportunity frequency", skipped.opportunity_frequency_hz, 100.0)
	_near("firing frequency reflects actual successful opportunities", skipped.firing_frequency_hz, 50.0)
	_near("skipped firing retains mechanical loss", skipped.mechanical_torque_nm, result.mechanical_torque_nm)
	_near("skipped firing retains pumping loss", skipped.pumping_torque_nm, result.pumping_torque_nm)

	var cut: Dictionary = Kernel.evaluate(rpm, 0.5, 0.8, 1.0, parameters, false)
	_check("fuel cut has no fuel, burn, or indicated work", cut.delivered_fuel_kg_s == 0.0 \
		and cut.burned_fuel_kg_s == 0.0 and cut.unburned_fuel_kg_s == 0.0 \
		and cut.fuel_input_power_w == 0.0 and cut.chemical_power_w == 0.0 \
		and cut.indicated_power_w == 0.0 and cut.indicated_torque_nm == 0.0)
	_near("fuel cut keeps mechanical loss", cut.mechanical_torque_nm, result.mechanical_torque_nm)
	_near("fuel cut keeps scavenging loss while turning", cut.pumping_torque_nm, result.pumping_torque_nm)
	_near("fuel cut still reports crank opportunities", cut.opportunity_frequency_hz, 100.0)

	var stopped: Dictionary = Kernel.evaluate(0.0, 0.5, 0.8, 1.0, parameters)
	_check("stopped rpm has no combustion or moving losses", stopped.indicated_torque_nm == 0.0 \
		and stopped.mechanical_torque_nm == 0.0 and stopped.pumping_torque_nm == 0.0 \
		and stopped.mechanical_loss_w == 0.0 and stopped.pumping_loss_w == 0.0 \
		and stopped.delivered_fuel_kg_s == 0.0 and stopped.burned_fuel_kg_s == 0.0)
	_check("stopped rpm has no cycle or firing frequency", stopped.cycle_frequency_hz == 0.0 \
		and stopped.opportunity_frequency_hz == 0.0 and stopped.firing_frequency_hz == 0.0)
	_check("zero dry density is rejected", not Kernel.evaluate(rpm, 0.5, 0.8, 0.0, parameters).ok)
	var no_admission: Dictionary = Kernel.evaluate(rpm, 0.0, 0.8, 1.0, parameters)
	_check("zero admission has no charge, fuel, or actual firing", no_admission.air_charge_kg_cycle == 0.0 \
		and no_admission.delivered_fuel_kg_s == 0.0 and no_admission.burned_fuel_kg_s == 0.0 \
		and no_admission.firing_frequency_hz == 0.0)
	var no_mixture: Dictionary = Kernel.evaluate(rpm, 0.5, 0.0, 1.0, parameters)
	_check("zero mixture has no fuel or actual firing", no_mixture.delivered_fuel_kg_s == 0.0 \
		and no_mixture.burned_fuel_kg_s == 0.0 and no_mixture.firing_frequency_hz == 0.0)
	var no_completion := _parameters()
	no_completion["combustion_efficiency"] = _table(PackedFloat64Array([0.0, 2.0]),
		PackedFloat64Array([0.0, 0.0]))
	var misfire: Dictionary = Kernel.evaluate(rpm, 0.5, 0.8, 1.0, no_completion)
	_check("zero combustion completion keeps delivered fuel but has no fire", misfire.delivered_fuel_kg_s > 0.0 \
		and misfire.burned_fuel_kg_s == 0.0 and misfire.firing_frequency_hz == 0.0)
	_check("zero combustion completion produces no indicated work", misfire.cycle_work_j == 0.0 \
		and misfire.indicated_torque_nm == 0.0 and misfire.indicated_power_w == 0.0)

	_check("negative rpm is refused", not Kernel.evaluate(-1.0, 0.5, 0.8, 1.0, parameters).ok)
	_check("nonfinite rpm is refused", not Kernel.evaluate(INF, 0.5, 0.8, 1.0, parameters).ok)
	_check("unsupported RPM extrapolation is refused", not Kernel.evaluate(13000.0, 0.5, 0.8, 1.0, parameters).ok)
	_check("mixture outside the efficiency table is refused",
		not Kernel.evaluate(rpm, 0.5, 2.1, 1.0, parameters).ok)
	var malformed := _parameters()
	malformed["delivery_ratio"] = PackedFloat32Array([0.0, 2.0, 12000.0, 2.0])
	_check("malformed curve storage is refused", not Kernel.evaluate(rpm, 0.5, 0.8, 1.0, malformed).ok)
	var bad_scalar := _parameters()
	bad_scalar["stoich_air_fuel_ratio"] = 0.0
	_check("zero AFR is refused before division", not Kernel.evaluate(rpm, 0.5, 0.8, 1.0, bad_scalar).ok)
	var failure: Dictionary = Kernel.evaluate(-1.0, 0.5, 0.8, 1.0, parameters)
	_check("failure results expose a message and finite zero outputs", not failure.ok \
		and not str(failure.message).is_empty() and _failure_outputs_are_zero(failure))

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _reported_values_are_finite(result: Dictionary) -> bool:
	for key in result:
		if key == "ok" or key == "message":
			continue
		if not is_finite(float(result[key])):
			return false
	return true


func _failure_outputs_are_zero(result: Dictionary) -> bool:
	for key in result:
		if key == "ok" or key == "message":
			continue
		if float(result[key]) != 0.0:
			return false
	return true
