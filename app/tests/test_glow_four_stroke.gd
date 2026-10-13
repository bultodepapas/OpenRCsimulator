extends SceneTree

const FourStroke := preload("res://physics/glow/four_stroke.gd")

var _checks: int = 0
var _failures: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _near(label: String, actual: float, expected: float, tolerance: float = 1.0e-12) -> void:
	_check(label, is_finite(actual) and absf(actual - expected) <= tolerance, "actual=%s expected=%s" % [actual, expected])


func _initialize() -> void:
	_test_analytic_cycle_and_energy()
	_test_closed_throttle_pumping()
	_test_nonburning_has_no_fires()
	_test_stopped_and_coasting_states()
	_test_rejects_invalid_inputs()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_analytic_cycle_and_energy() -> void:
	var result: Dictionary = FourStroke.evaluate(
		6000.0, 0.8, 1.0, 1.0, _parameters(), true, 0.5
	)
	_check("analytic operating point accepted", bool(result["ok"]), str(result["message"]))

	var volume_m3: float = 1.0e-4
	var air_kg_cycle: float = 1.0 * volume_m3 * 0.8
	var premix_kg_cycle: float = air_kg_cycle / 10.0 / 0.9
	var combustible_kg_cycle: float = premix_kg_cycle * 0.9
	var burned_kg_cycle: float = minf(combustible_kg_cycle, air_kg_cycle / 10.0) * 0.5 * 0.5
	var cycle_hz: float = 6000.0 / 120.0
	var omega_rad_s: float = 2.0 * PI * 6000.0 / 60.0
	var indicated_work_j: float = burned_kg_cycle * 1000.0 * 0.25
	var indicated_torque_nm: float = indicated_work_j / (4.0 * PI)
	var pumping_torque_nm: float = (100.0 + 50.0 * (1.0 - 0.8)) * volume_m3 / (4.0 * PI)

	_near("one opportunity per 720 degrees", float(result["opportunity_frequency_hz"]), cycle_hz)
	_near("four-stroke cycle cadence", float(result["cycle_frequency_hz"]), 50.0)
	_near("firing cadence includes missing fires", float(result["firing_frequency_hz"]), 25.0)
	_near("air charge follows density, displacement, admission and VE", float(result["air_charge_kg_cycle"]), air_kg_cycle)
	_near("cycle work is per 720-degree cycle", float(result["cycle_work_j"]), indicated_work_j)
	_near("indicated torque divides work by four pi", float(result["indicated_torque_nm"]), indicated_torque_nm)
	_near("indicated power agrees with torque and angular speed", float(result["indicated_power_w"]), indicated_torque_nm * omega_rad_s)
	_near("delivered fuel includes oil premix", float(result["delivered_fuel_kg_s"]), premix_kg_cycle * cycle_hz)
	_near("burned fuel includes combustion and firing fractions", float(result["burned_fuel_kg_s"]), burned_kg_cycle * cycle_hz)
	_near("unburned flow is delivered mass minus burned mass", float(result["unburned_fuel_kg_s"]), (premix_kg_cycle - burned_kg_cycle) * cycle_hz)
	_near("fuel input power counts gross combustible fuel", float(result["fuel_input_power_w"]), combustible_kg_cycle * cycle_hz * 1000.0)
	_near("chemical power counts burned fuel", float(result["chemical_power_w"]), burned_kg_cycle * cycle_hz * 1000.0)
	_near("mechanical loss power", float(result["mechanical_loss_w"]), 0.01 * omega_rad_s)
	_near("720-degree pumping work becomes pumping torque", float(result["pumping_torque_nm"]), pumping_torque_nm)
	_near("pumping loss power", float(result["pumping_loss_w"]), pumping_torque_nm * omega_rad_s)
	_near("valve loss power", float(result["valve_loss_w"]), 0.001 * omega_rad_s)
	_near(
		"shaft torque subtracts mechanical, pumping and valve losses",
		float(result["shaft_torque_nm"]),
		indicated_torque_nm - 0.01 - pumping_torque_nm - 0.001
	)


func _test_closed_throttle_pumping() -> void:
	var closed: Dictionary = FourStroke.evaluate(6000.0, 0.0, 1.0, 1.0, _parameters())
	var open: Dictionary = FourStroke.evaluate(6000.0, 1.0, 1.0, 1.0, _parameters())
	_check("closed-throttle point accepted", bool(closed["ok"]), str(closed["message"]))
	_check("open-throttle point accepted", bool(open["ok"]), str(open["message"]))
	_near("closed throttle traps no air charge", float(closed["air_charge_kg_cycle"]), 0.0)
	_near("closed throttle delivers no fuel", float(closed["delivered_fuel_kg_s"]), 0.0)
	_near("closed throttle reports no successful fires", float(closed["firing_frequency_hz"]), 0.0)
	_near("closed throttle has no combustion torque", float(closed["indicated_torque_nm"]), 0.0)
	_near(
		"closed throttle still pumps against base pressure plus intake depression",
		float(closed["pumping_torque_nm"]),
		(100.0 + 50.0) * 1.0e-4 / (4.0 * PI)
	)
	_near(
		"fully open throttle retains base gas-exchange pressure",
		float(open["pumping_torque_nm"]),
		100.0 * 1.0e-4 / (4.0 * PI)
	)
	_check(
		"closed throttle pumping exceeds open-throttle pumping",
		float(closed["pumping_torque_nm"]) > float(open["pumping_torque_nm"])
	)


func _test_nonburning_has_no_fires() -> void:
	var no_mixture: Dictionary = FourStroke.evaluate(6000.0, 0.8, 0.0, 1.0, _parameters())
	_check("zero-mixture point accepted", bool(no_mixture["ok"]), str(no_mixture["message"]))
	_near("zero mixture keeps nominal opportunities", float(no_mixture["opportunity_frequency_hz"]), 50.0)
	_near("zero mixture has zero successful fires", float(no_mixture["firing_frequency_hz"]), 0.0)

	var no_completion_parameters: Dictionary = _parameters()
	no_completion_parameters["combustion_efficiency"] = PackedFloat64Array([0.0, 0.0, 2.0, 0.0])
	var no_completion: Dictionary = FourStroke.evaluate(
		6000.0, 0.8, 1.0, 1.0, no_completion_parameters
	)
	_check("zero-completion point accepted", bool(no_completion["ok"]), str(no_completion["message"]))
	_check("zero-completion still delivers premix", float(no_completion["delivered_fuel_kg_s"]) > 0.0)
	_near("zero completion has no burned fuel", float(no_completion["burned_fuel_kg_s"]), 0.0)
	_near("zero completion has zero successful fires", float(no_completion["firing_frequency_hz"]), 0.0)

func _test_stopped_and_coasting_states() -> void:
	var stopped: Dictionary = FourStroke.evaluate(0.0, 0.8, 1.0, 1.0, _parameters())
	_check("zero-RPM point accepted", bool(stopped["ok"]), str(stopped["message"]))
	for key: String in [
		"indicated_torque_nm",
		"mechanical_torque_nm",
		"pumping_torque_nm",
		"valve_torque_nm",
		"shaft_torque_nm",
		"delivered_fuel_kg_s",
		"burned_fuel_kg_s",
		"fuel_input_power_w",
		"chemical_power_w",
		"indicated_power_w",
		"mechanical_loss_w",
		"pumping_loss_w",
		"valve_loss_w",
		"cycle_work_j",
		"cycle_frequency_hz",
		"opportunity_frequency_hz",
		"firing_frequency_hz",
	]:
		_near("stopped engine has zero " + key, float(stopped[key]), 0.0)

	var running: Dictionary = FourStroke.evaluate(6000.0, 0.8, 1.0, 1.0, _parameters())
	var coasting: Dictionary = FourStroke.evaluate(6000.0, 0.8, 1.0, 1.0, _parameters(), false)
	_check("running point accepted", bool(running["ok"]), str(running["message"]))
	_check("coasting point accepted", bool(coasting["ok"]), str(coasting["message"]))
	_near("coasting delivers no fuel", float(coasting["delivered_fuel_kg_s"]), 0.0)
	_near("coasting burns no fuel", float(coasting["burned_fuel_kg_s"]), 0.0)
	_near("coasting has no chemical input", float(coasting["fuel_input_power_w"]), 0.0)
	_near("coasting has no chemical output", float(coasting["chemical_power_w"]), 0.0)
	_near("coasting has no indicated work", float(coasting["cycle_work_j"]), 0.0)
	_near("coasting keeps mechanical loss", float(coasting["mechanical_torque_nm"]), 0.01)
	_near("coasting keeps pumping loss", float(coasting["pumping_torque_nm"]), float(running["pumping_torque_nm"]))
	_near("coasting keeps valve loss", float(coasting["valve_torque_nm"]), 0.001)
	_near("coasting keeps cycle opportunities", float(coasting["opportunity_frequency_hz"]), 50.0)
	_near("coasting has no fires", float(coasting["firing_frequency_hz"]), 0.0)


func _test_rejects_invalid_inputs() -> void:
	_check_rejected("negative RPM", FourStroke.evaluate(-1.0, 0.8, 1.0, 1.0, _parameters()))
	_check_rejected("nonfinite RPM", FourStroke.evaluate(INF, 0.8, 1.0, 1.0, _parameters()))
	_check_rejected("admission above one", FourStroke.evaluate(6000.0, 1.01, 1.0, 1.0, _parameters()))
	_check_rejected("negative mixture", FourStroke.evaluate(6000.0, 0.8, -0.1, 1.0, _parameters()))
	_check_rejected("zero dry density", FourStroke.evaluate(6000.0, 0.8, 1.0, 0.0, _parameters()))
	_check_rejected("firing fraction above one", FourStroke.evaluate(6000.0, 0.8, 1.0, 1.0, _parameters(), true, 1.01))

	var invalid: Dictionary = _parameters()
	invalid["displacement_m3"] = 0.0
	_check_rejected("zero displacement", FourStroke.evaluate(6000.0, 0.8, 1.0, 1.0, invalid))

	invalid = _parameters()
	invalid["oil_fraction"] = 1.0
	_check_rejected("oil fraction consumes all premix", FourStroke.evaluate(6000.0, 0.8, 1.0, 1.0, invalid))

	invalid = _parameters()
	invalid["fuel_lhv_j_kg"] = INF
	_check_rejected("nonfinite fuel LHV", FourStroke.evaluate(6000.0, 0.8, 1.0, 1.0, invalid))

	invalid = _parameters()
	invalid["mechanical_torque_nm"] = PackedFloat64Array([0.0, 0.01, 9000.0, 0.01])
	_check_rejected("RPM outside table coverage", FourStroke.evaluate(10000.0, 0.8, 1.0, 1.0, invalid))

	invalid = _parameters()
	invalid["valve_torque_nm"] = PackedFloat64Array([0.0, 0.001, 5000.0, 0.001, 4000.0, 0.001])
	_check_rejected("nonincreasing table domain", FourStroke.evaluate(4000.0, 0.8, 1.0, 1.0, invalid))

	invalid = _parameters()
	invalid["volumetric_efficiency"] = [0.0, 1.0, 10000.0, 1.0]
	_check_rejected("table must be packed float64", FourStroke.evaluate(6000.0, 0.8, 1.0, 1.0, invalid))


func _check_rejected(label: String, result: Dictionary) -> void:
	_check(label, not bool(result["ok"]) and not str(result["message"]).is_empty(), str(result["message"]))
	for key: String in [
		"indicated_torque_nm",
		"mechanical_torque_nm",
		"pumping_torque_nm",
		"valve_torque_nm",
		"shaft_torque_nm",
		"delivered_fuel_kg_s",
		"burned_fuel_kg_s",
		"unburned_fuel_kg_s",
		"fuel_input_power_w",
		"chemical_power_w",
		"indicated_power_w",
		"mechanical_loss_w",
		"pumping_loss_w",
		"valve_loss_w",
		"cycle_work_j",
		"air_charge_kg_cycle",
		"cycle_frequency_hz",
		"opportunity_frequency_hz",
		"firing_frequency_hz",
	]:
		_check(label + " returns finite " + key, is_finite(float(result[key])))


func _parameters() -> Dictionary:
	return {
		"displacement_m3": 1.0e-4,
		"oil_fraction": 0.1,
		"stoich_air_fuel_ratio": 10.0,
		"fuel_lhv_j_kg": 1000.0,
		"mechanical_torque_nm": PackedFloat64Array([0.0, 0.01, 10000.0, 0.01]),
		"combustion_efficiency": PackedFloat64Array([0.0, 0.5, 2.0, 0.5]),
		"indicated_efficiency": PackedFloat64Array([0.0, 0.25, 10000.0, 0.25]),
		"volumetric_efficiency": PackedFloat64Array([0.0, 1.0, 10000.0, 1.0]),
		"pumping_pressure_pa": PackedFloat64Array([0.0, 100.0, 10000.0, 100.0]),
		"intake_pressure_drop_pa": 50.0,
		"valve_torque_nm": PackedFloat64Array([0.0, 0.001, 10000.0, 0.001]),
	}
