## NITRO-02c: scalar head-temperature accounting, independent of combustion family.
## Parameters are calibration inputs, never inferred from a 2T/4T selector.
extends RefCounted


static func evaluate(source: Dictionary, temperature_k: float, ambient_k: float,
		cooling_airspeed_mps: float, parameters: Dictionary) -> Dictionary:
	if not source.get("ok", false) or not is_finite(temperature_k) or temperature_k <= 0.0 or not is_finite(ambient_k) or ambient_k <= 0.0 or not is_finite(cooling_airspeed_mps) or cooling_airspeed_mps < 0.0:
		return {ok = false, message = "Invalid thermal source, temperatures or airflow"}
	for name: String in ["heat_capacity_j_k", "head_heat_fraction", "cooling_base_w_k", "cooling_airflow_w_s_m_k", "premix_evaporation_j_kg", "evaporation_head_fraction"]:
		var value: Variant = parameters.get(name)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
			return {ok = false, message = "Invalid thermal parameter: " + name}
	if parameters.heat_capacity_j_k <= 0.0 or parameters.head_heat_fraction > 1.0 or parameters.evaporation_head_fraction > 1.0:
		return {ok = false, message = "Invalid thermal capacity or heat fraction"}
	for name: String in ["chemical_power_w", "indicated_power_w", "mechanical_loss_w", "pumping_loss_w", "valve_loss_w", "delivered_fuel_kg_s"]:
		var value: Variant = source.get(name)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
			return {ok = false, message = "Invalid thermal power/flow: " + name}
	var rejected_combustion: float = source.chemical_power_w - source.indicated_power_w
	if rejected_combustion < 0.0:
		return {ok = false, message = "Indicated work exceeds released chemical heat"}
	var mechanical_heat: float = source.mechanical_loss_w + source.pumping_loss_w + source.valve_loss_w
	var combustion_to_head: float = rejected_combustion * parameters.head_heat_fraction
	var exhaust_heat: float = rejected_combustion - combustion_to_head
	# Effective latent heat per kg of delivered PREMIX: its calibration must include
	# nonvolatile oil and the evaporating fraction. Do not pass a pure-methanol L_v.
	var evaporation: float = source.delivered_fuel_kg_s * parameters.premix_evaporation_j_kg * parameters.evaporation_head_fraction
	var conductance: float = parameters.cooling_base_w_k + parameters.cooling_airflow_w_s_m_k * cooling_airspeed_mps
	var cooling: float = conductance * (temperature_k - ambient_k)
	var stored_heat: float = combustion_to_head + mechanical_heat - evaporation - cooling
	var rate: float = stored_heat / parameters.heat_capacity_j_k
	for value: float in [exhaust_heat, evaporation, cooling, stored_heat, rate]:
		if not is_finite(value):
			return {ok = false, message = "Nonfinite thermal balance"}
	# Pumping dissipation is lumped into the head/case proxy here. This partition is
	# an explicit reduced-model assumption, not a measured head-only heat transfer.
	return {ok = true, temperature_rate_k_s = rate, stored_heat_w = stored_heat,
		exhaust_heat_w = exhaust_heat, evaporation_heat_w = evaporation, cooling_heat_w = cooling,
		combustion_head_heat_w = combustion_to_head, mechanical_heat_w = mechanical_heat}


## Internal repeated-stage path. `source` must be a successful prepared-source
## result and `parameters` must be the detached settings snapshot validated by
## Lifecycle.prepare_evaluator(); the public evaluate() keeps full guards.
static func _evaluate_prepared(source: Dictionary, temperature_k: float, ambient_k: float,
		cooling_airspeed_mps: float, parameters: Dictionary) -> Dictionary:
	if not source.get("ok", false) or not is_finite(temperature_k) or temperature_k <= 0.0 or not is_finite(ambient_k) or ambient_k <= 0.0 or not is_finite(cooling_airspeed_mps) or cooling_airspeed_mps < 0.0:
		return {ok = false, message = "Invalid thermal source, temperatures or airflow"}
	var rejected_combustion: float = source.chemical_power_w - source.indicated_power_w
	if rejected_combustion < 0.0:
		return {ok = false, message = "Indicated work exceeds released chemical heat"}
	var mechanical_heat: float = source.mechanical_loss_w + source.pumping_loss_w + source.valve_loss_w
	var combustion_to_head: float = rejected_combustion * parameters.head_heat_fraction
	var exhaust_heat: float = rejected_combustion - combustion_to_head
	var evaporation: float = source.delivered_fuel_kg_s * parameters.premix_evaporation_j_kg * parameters.evaporation_head_fraction
	var conductance: float = parameters.cooling_base_w_k + parameters.cooling_airflow_w_s_m_k * cooling_airspeed_mps
	var cooling: float = conductance * (temperature_k - ambient_k)
	var stored_heat: float = combustion_to_head + mechanical_heat - evaporation - cooling
	var rate: float = stored_heat / parameters.heat_capacity_j_k
	if not is_finite(exhaust_heat) or not is_finite(evaporation) or not is_finite(cooling) \
			or not is_finite(stored_heat) or not is_finite(rate):
		return {ok = false, message = "Nonfinite thermal balance"}
	return {ok = true, temperature_rate_k_s = rate, stored_heat_w = stored_heat,
		exhaust_heat_w = exhaust_heat, evaporation_heat_w = evaporation, cooling_heat_w = cooling,
		combustion_head_heat_w = combustion_to_head, mechanical_heat_w = mechanical_heat}
