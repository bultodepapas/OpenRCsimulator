extends RefCounted

## Reduced, cycle-averaged two-stroke glow engine model with no manufacturer calibration.
## Tables are interleaved PackedFloat64Array pairs [x0, y0, x1, y1, ...] and must cover queries.
## Mixture scales stoichiometric fuel; oil is inert premix mass. Loss torques are positive.
## One combustion opportunity occurs per crankshaft revolution.
const CYCLE_ANGLE_RAD := 2.0 * PI


static func evaluate(
		rpm: float,
		admission: float,
		mixture: float,
		dry_density_kg_m3: float,
		parameters: Dictionary,
		running: bool = true,
		firing_fraction: float = 1.0
	) -> Dictionary:
	var result := _empty_result("")

	if not is_finite(rpm) or rpm < 0.0:
		return _empty_result("rpm must be finite and nonnegative")
	if not is_finite(admission) or admission < 0.0 or admission > 1.0:
		return _empty_result("admission must be finite and in [0, 1]")
	if not is_finite(mixture) or mixture < 0.0:
		return _empty_result("mixture must be finite and nonnegative")
	if not is_finite(dry_density_kg_m3) or dry_density_kg_m3 <= 0.0:
		return _empty_result("dry_density_kg_m3 must be finite and positive")
	if not is_finite(firing_fraction) or firing_fraction < 0.0 or firing_fraction > 1.0:
		return _empty_result("firing_fraction must be finite and in [0, 1]")

	var scalar_result: Dictionary = _read_number(parameters, "displacement_m3", 0.0, false, INF, true)
	if not scalar_result["ok"]:
		return _empty_result(str(scalar_result["message"]))
	var displacement_m3: float = float(scalar_result["value"])

	scalar_result = _read_number(parameters, "oil_fraction", 0.0, true, 1.0, false)
	if not scalar_result["ok"]:
		return _empty_result(str(scalar_result["message"]))
	var oil_fraction: float = float(scalar_result["value"])

	scalar_result = _read_number(parameters, "stoich_air_fuel_ratio", 0.0, false, INF, true)
	if not scalar_result["ok"]:
		return _empty_result(str(scalar_result["message"]))
	var stoich_air_fuel_ratio: float = float(scalar_result["value"])

	scalar_result = _read_number(parameters, "fuel_lhv_j_kg", 0.0, false, INF, true)
	if not scalar_result["ok"]:
		return _empty_result(str(scalar_result["message"]))
	var fuel_lhv_j_kg: float = float(scalar_result["value"])

	var delivery_result: Dictionary = _read_table(parameters, "delivery_ratio", rpm, 0.0, true, INF, true)
	if not delivery_result["ok"]:
		return _empty_result(str(delivery_result["message"]))
	var delivery_table: PackedFloat64Array = delivery_result["values"]

	var trapping_result: Dictionary = _read_table(parameters, "trapping_efficiency", rpm, 0.0, true, 1.0, true)
	if not trapping_result["ok"]:
		return _empty_result(str(trapping_result["message"]))
	var trapping_table: PackedFloat64Array = trapping_result["values"]

	var scavenge_result: Dictionary = _read_table(parameters, "scavenge_pressure_pa", rpm, 0.0, true, INF, true)
	if not scavenge_result["ok"]:
		return _empty_result(str(scavenge_result["message"]))
	var scavenge_table: PackedFloat64Array = scavenge_result["values"]

	var mechanical_result: Dictionary = _read_table(parameters, "mechanical_torque_nm", rpm, 0.0, true, INF, true)
	if not mechanical_result["ok"]:
		return _empty_result(str(mechanical_result["message"]))
	var mechanical_table: PackedFloat64Array = mechanical_result["values"]

	var combustion_result: Dictionary = _read_table(parameters, "combustion_efficiency", mixture, 0.0, true, 1.0, true)
	if not combustion_result["ok"]:
		return _empty_result(str(combustion_result["message"]))
	var combustion_table: PackedFloat64Array = combustion_result["values"]

	var indicated_result: Dictionary = _read_table(parameters, "indicated_efficiency", rpm, 0.0, true, 1.0, true)
	if not indicated_result["ok"]:
		return _empty_result(str(indicated_result["message"]))
	var indicated_table: PackedFloat64Array = indicated_result["values"]

	var cycle_frequency_hz: float = rpm / 60.0
	var opportunity_frequency_hz: float = cycle_frequency_hz
	var omega_rad_s: float = 2.0 * PI * rpm / 60.0
	var delivery_ratio: float = _sample(delivery_table, rpm)
	var trapping_efficiency: float = _sample(trapping_table, rpm)
	var air_delivered_kg_cycle: float = (
		dry_density_kg_m3 * displacement_m3 * admission * delivery_ratio
	)
	var air_charge_kg_cycle: float = air_delivered_kg_cycle * trapping_efficiency

	var indicated_torque_nm: float = 0.0
	var mechanical_torque_nm: float = 0.0
	var pumping_torque_nm: float = 0.0
	var delivered_fuel_kg_s: float = 0.0
	var burned_fuel_kg_s: float = 0.0
	var fuel_input_power_w: float = 0.0
	var chemical_power_w: float = 0.0
	var indicated_power_w: float = 0.0
	var cycle_work_j: float = 0.0
	var firing_frequency_hz: float = 0.0

	if rpm > 0.0:
		mechanical_torque_nm = _sample(mechanical_table, rpm)
		var scavenge_pressure_pa: float = _sample(scavenge_table, rpm)
		var scavenge_work_j: float = (
			scavenge_pressure_pa * displacement_m3 * delivery_ratio * admission
		)
		pumping_torque_nm = scavenge_work_j / CYCLE_ANGLE_RAD

		if running:
			var gross_premix_kg_cycle: float = (
				air_delivered_kg_cycle * mixture
				/ stoich_air_fuel_ratio
				/ (1.0 - oil_fraction)
			)
			var gross_combustible_kg_cycle: float = gross_premix_kg_cycle * (1.0 - oil_fraction)
			var combustible_trapped_kg_cycle: float = gross_combustible_kg_cycle * trapping_efficiency
			var oxygen_limited_fuel_kg_cycle: float = air_charge_kg_cycle / stoich_air_fuel_ratio
			var combustion_efficiency: float = _sample(combustion_table, mixture)
			var burned_kg_cycle: float = minf(
				combustible_trapped_kg_cycle, oxygen_limited_fuel_kg_cycle
			) * combustion_efficiency * firing_fraction
			var indicated_efficiency: float = _sample(indicated_table, rpm)

			delivered_fuel_kg_s = gross_premix_kg_cycle * opportunity_frequency_hz
			burned_fuel_kg_s = burned_kg_cycle * opportunity_frequency_hz
			if burned_kg_cycle > 0.0:
				firing_frequency_hz = opportunity_frequency_hz * firing_fraction
			fuel_input_power_w = gross_combustible_kg_cycle * opportunity_frequency_hz * fuel_lhv_j_kg
			chemical_power_w = burned_fuel_kg_s * fuel_lhv_j_kg
			cycle_work_j = burned_kg_cycle * fuel_lhv_j_kg * indicated_efficiency
			indicated_torque_nm = cycle_work_j / CYCLE_ANGLE_RAD
			indicated_power_w = indicated_torque_nm * omega_rad_s

	var mechanical_loss_w: float = mechanical_torque_nm * omega_rad_s
	var pumping_loss_w: float = pumping_torque_nm * omega_rad_s
	var valve_loss_w: float = 0.0
	var unburned_fuel_kg_s: float = delivered_fuel_kg_s - burned_fuel_kg_s
	var shaft_torque_nm: float = indicated_torque_nm - mechanical_torque_nm - pumping_torque_nm

	result["ok"] = true
	result["message"] = ""
	result["indicated_torque_nm"] = indicated_torque_nm
	result["mechanical_torque_nm"] = mechanical_torque_nm
	result["pumping_torque_nm"] = pumping_torque_nm
	result["valve_torque_nm"] = 0.0
	result["shaft_torque_nm"] = shaft_torque_nm
	result["delivered_fuel_kg_s"] = delivered_fuel_kg_s
	result["burned_fuel_kg_s"] = burned_fuel_kg_s
	result["unburned_fuel_kg_s"] = unburned_fuel_kg_s
	result["fuel_input_power_w"] = fuel_input_power_w
	result["chemical_power_w"] = chemical_power_w
	result["indicated_power_w"] = indicated_power_w
	result["mechanical_loss_w"] = mechanical_loss_w
	result["pumping_loss_w"] = pumping_loss_w
	result["valve_loss_w"] = valve_loss_w
	result["cycle_work_j"] = cycle_work_j
	result["air_charge_kg_cycle"] = air_charge_kg_cycle
	result["cycle_frequency_hz"] = cycle_frequency_hz
	result["opportunity_frequency_hz"] = opportunity_frequency_hz
	result["firing_frequency_hz"] = firing_frequency_hz

	if not _finite_outputs(result):
		return _empty_result("calculation produced a nonfinite output")
	return result


static func _read_number(
		parameters: Dictionary,
		key: String,
		minimum: float,
		minimum_inclusive: bool,
		maximum: float,
		maximum_inclusive: bool
	) -> Dictionary:
	if not parameters.has(key):
		return {"ok": false, "message": "%s is required" % key}
	var raw: Variant = parameters[key]
	if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
		return {"ok": false, "message": "%s must be numeric" % key}
	var value: float = float(raw)
	if not is_finite(value):
		return {"ok": false, "message": "%s must be finite" % key}
	if minimum_inclusive and value < minimum:
		return {"ok": false, "message": "%s is below its allowed range" % key}
	if not minimum_inclusive and value <= minimum:
		return {"ok": false, "message": "%s must be positive" % key}
	if maximum_inclusive and value > maximum:
		return {"ok": false, "message": "%s is above its allowed range" % key}
	if not maximum_inclusive and value >= maximum:
		return {"ok": false, "message": "%s must be below its allowed range" % key}
	return {"ok": true, "message": "", "value": value}


static func _read_table(
		parameters: Dictionary,
		key: String,
		query: float,
		minimum_y: float,
		minimum_y_inclusive: bool,
		maximum_y: float,
		maximum_y_inclusive: bool
	) -> Dictionary:
	if not parameters.has(key):
		return {"ok": false, "message": "%s is required" % key}
	var raw: Variant = parameters[key]
	if not (raw is PackedFloat64Array):
		return {"ok": false, "message": "%s must be a PackedFloat64Array" % key}
	var table: PackedFloat64Array = raw
	if table.size() < 4 or table.size() % 2 != 0:
		return {"ok": false, "message": "%s must contain at least two x/y pairs" % key}
	var previous_x: float = -1.0
	for i in range(0, table.size(), 2):
		var x: float = table[i]
		var y: float = table[i + 1]
		if not is_finite(x) or x < 0.0:
			return {"ok": false, "message": "%s x values must be finite and nonnegative" % key}
		if i > 0 and x <= previous_x:
			return {"ok": false, "message": "%s x values must increase strictly" % key}
		if not is_finite(y):
			return {"ok": false, "message": "%s y values must be finite" % key}
		if minimum_y_inclusive and y < minimum_y:
			return {"ok": false, "message": "%s y value is below its allowed range" % key}
		if not minimum_y_inclusive and y <= minimum_y:
			return {"ok": false, "message": "%s y values must be positive" % key}
		if maximum_y_inclusive and y > maximum_y:
			return {"ok": false, "message": "%s y value is above its allowed range" % key}
		if not maximum_y_inclusive and y >= maximum_y:
			return {"ok": false, "message": "%s y value is above its allowed range" % key}
		previous_x = x
	if not is_finite(query) or query < 0.0:
		return {"ok": false, "message": "%s query must be finite and nonnegative" % key}
	if query < table[0] or query > table[table.size() - 2]:
		return {"ok": false, "message": "%s does not cover the query" % key}
	return {"ok": true, "message": "", "values": table}


static func _sample(table: PackedFloat64Array, query: float) -> float:
	for i in range(0, table.size() - 2, 2):
		var x0: float = table[i]
		var y0: float = table[i + 1]
		var x1: float = table[i + 2]
		var y1: float = table[i + 3]
		if query <= x1:
			var fraction: float = (query - x0) / (x1 - x0)
			return y0 + (y1 - y0) * fraction
	return table[table.size() - 1]


static func _finite_outputs(result: Dictionary) -> bool:
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
		if not is_finite(float(result[key])):
			return false
	return true


static func _empty_result(message: String) -> Dictionary:
	return {
		"ok": false,
		"message": message,
		"indicated_torque_nm": 0.0,
		"mechanical_torque_nm": 0.0,
		"pumping_torque_nm": 0.0,
		"valve_torque_nm": 0.0,
		"shaft_torque_nm": 0.0,
		"delivered_fuel_kg_s": 0.0,
		"burned_fuel_kg_s": 0.0,
		"unburned_fuel_kg_s": 0.0,
		"fuel_input_power_w": 0.0,
		"chemical_power_w": 0.0,
		"indicated_power_w": 0.0,
		"mechanical_loss_w": 0.0,
		"pumping_loss_w": 0.0,
		"valve_loss_w": 0.0,
		"cycle_work_j": 0.0,
		"air_charge_kg_cycle": 0.0,
		"cycle_frequency_hz": 0.0,
		"opportunity_frequency_hz": 0.0,
		"firing_frequency_hz": 0.0,
	}
