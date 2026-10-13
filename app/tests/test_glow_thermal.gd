extends SceneTree

const Thermal := preload("res://physics/glow/thermal.gd")
var failures := 0
var checks := 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL: " + label)


func _initialize() -> void:
	var source: Dictionary = {ok = true, chemical_power_w = 1000.0, indicated_power_w = 200.0,
		mechanical_loss_w = 20.0, pumping_loss_w = 10.0, valve_loss_w = 5.0, delivered_fuel_kg_s = .001}
	var parameters: Dictionary = {heat_capacity_j_k = 100.0, head_heat_fraction = .25,
		cooling_base_w_k = 2.0, cooling_airflow_w_s_m_k = .1, premix_evaporation_j_kg = 1e6, evaporation_head_fraction = .1}
	var result: Dictionary = Thermal.evaluate(source, 350.0, 300.0, 10.0, parameters)
	check("known head heat rate", result.ok and absf(result.temperature_rate_k_s - (-.15)) < 1e-14)
	check("chemical and shaft energy closure", absf(source.chemical_power_w - (source.indicated_power_w - 35.0) - result.stored_heat_w - result.exhaust_heat_w - result.evaporation_heat_w - result.cooling_heat_w) < 1e-12)
	var fast: Dictionary = Thermal.evaluate(source, 350.0, 300.0, 20.0, parameters)
	check("increasing airflow increases heat rejection", fast.temperature_rate_k_s < result.temperature_rate_k_s)
	var below_ambient: Dictionary = Thermal.evaluate(source, 250.0, 300.0, 10.0, parameters)
	check("ambient can warm a cold head", below_ambient.cooling_heat_w < 0.0)
	var quiet: Dictionary = source.duplicate(true)
	for key: String in quiet:
		if key != "ok":
			quiet[key] = 0.0
	var cool: Dictionary = Thermal.evaluate(quiet, 350.0, 300.0, 0.0, parameters)
	check("cut engine cools with zero artificial heat", absf(cool.temperature_rate_k_s + 1.0) < 1e-12)
	for key: String in parameters:
		var bad: Dictionary = parameters.duplicate(true)
		bad[key] = NAN
		check("nonfinite parameter rejected " + key, not Thermal.evaluate(source, 350.0, 300.0, 10.0, bad).ok)
	var bad: Dictionary = source.duplicate(true)
	bad.indicated_power_w = 2000.0
	check("energy creation rejected", not Thermal.evaluate(bad, 350.0, 300.0, 10.0, parameters).ok)
	check("invalid source rejected", not Thermal.evaluate({ok = false}, 350.0, 300.0, 10.0, parameters).ok)
	check("negative airflow rejected", not Thermal.evaluate(source, 350.0, 300.0, -1.0, parameters).ok)
	check("nonphysical temperature rejected", not Thermal.evaluate(source, 0.0, 300.0, 10.0, parameters).ok)
	print("NITRO thermal: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
