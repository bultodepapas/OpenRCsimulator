# HELI-06c: joint aerodynamic stage, prescribed main-shaft speed.
# Source-style shaft-aligned wake closure is explicit and unvalidated.
# No drive, rotor momentum, controller, body integration or session dispatch.
extends RefCounted

const MainStage = preload("res://physics/rotorcraft/main_rotor_stage.gd")
const Tail = preload("res://physics/rotorcraft/tail_rotor.gd")
const Airframe = preload("res://physics/rotorcraft/airframe.gd")
const PerformanceContext = preload("res://physics/rotorcraft/performance_context.gd")
const M = preload("res://physics/math3d.gd")
const STATE_LAYOUT: Array = ["a1_rad", "b1_rad", "induced_velocity_mps"]
const WAKE_LAW: String = "openrc-xcell-shaft-airframe-wake-v1"


# Prepare immutable model/configuration values once per aircraft/atmosphere
# setup. No state or per-stage result is retained by this context.
static func prepare(main_model: Dictionary, tail_model: Dictionary, airframe_model: Dictionary,
		flow_floor: float, fin_tail_wake_fraction: float, height_over_radius: float = -1.0,
		loss: float = 1.0, instability: float = 1.0) -> Dictionary:
	return PerformanceContext.prepare(main_model, tail_model, airframe_model, flow_floor,
		fin_tail_wake_fraction, height_over_radius, loss, instability)


# Safe/reference API. This retains the full model validation performed by the
# original HELI-06c entry point and is still used by tests and authoring tools.
static func evaluate(main_model: Dictionary, tail_model: Dictionary, airframe_model: Dictionary,
		state: PackedFloat64Array, omega: float, cg_air: PackedFloat64Array, rates: PackedFloat64Array,
		collective: float, cyclic_forward: float, cyclic_right: float, tail_collective: float,
		flow_floor: float, fin_tail_wake_fraction: float, height_over_radius: float = -1.0,
		loss: float = 1.0, instability: float = 1.0, diagnostics: bool = false,
		thrust_axis_downworld_scalar: float = NAN) -> Dictionary:
	if state.size() != 3 or not _vector(cg_air) or not _vector(rates) \
		or not is_finite(fin_tail_wake_fraction) or fin_tail_wake_fraction < 0.0 or fin_tail_wake_fraction > 1.0:
		return {"ok": false}
	# Check needed interface scalars before using untrusted dictionaries. Each
	# component subsequently validates its complete immutable owner context.
	for key: String in ["rho_kg_m3", "rotor_radius_m", "hub_x_m", "hub_y_m", "hub_z_m"]:
		if not _scalar(main_model, key):
			return {"ok": false}
	for key: String in ["rho_kg_m3", "main_rotor_radius_m", "vertical_fin_area_m2"]:
		if not _scalar(tail_model, key):
			return {"ok": false}
	for key: String in ["rho_kg_m3", "vertical_fin_area_m2"]:
		if not _scalar(airframe_model, key):
			return {"ok": false}
	# A stage cannot combine different atmospheric conditions or a different
	# fin area for blockage and fin loading. No tolerance hides an authoring mismatch.
	if main_model.rho_kg_m3 != tail_model.rho_kg_m3 or main_model.rho_kg_m3 != airframe_model.rho_kg_m3 \
		or main_model.rotor_radius_m != tail_model.main_rotor_radius_m \
		or tail_model.vertical_fin_area_m2 != airframe_model.vertical_fin_area_m2:
		return {"ok": false}
	return _evaluate_models(main_model, tail_model, airframe_model, state, omega, cg_air, rates,
		collective, cyclic_forward, cyclic_right, tail_collective, flow_floor,
		fin_tail_wake_fraction, height_over_radius, loss, instability, diagnostics,
		false, thrust_axis_downworld_scalar)


# Repeated-evaluation entry. The immutable context must come from prepare();
# state, rates, flow vectors, commands and all computed loads still receive
# finite/domain guards on every stage.
static func fast_evaluate(context: Dictionary, state: PackedFloat64Array, omega: float,
		cg_air: PackedFloat64Array, rates: PackedFloat64Array, collective: float,
		cyclic_forward: float, cyclic_right: float, tail_collective: float,
		diagnostics: bool = false, height_over_radius_override: float = NAN,
		thrust_axis_downworld_scalar: float = NAN) -> Dictionary:
	if not PerformanceContext.has_valid_header(context) or state.size() != 3 \
		or not _vector(state) or not _vector(cg_air) or not _vector(rates) \
		or not _finite([omega, collective, cyclic_forward, cyclic_right, tail_collective]) \
		or (not is_nan(height_over_radius_override) and not is_finite(height_over_radius_override)) \
		or (not is_nan(height_over_radius_override) and height_over_radius_override < 0.0 \
			and height_over_radius_override != -1.0) \
		or (not is_nan(thrust_axis_downworld_scalar) and (not is_finite(thrust_axis_downworld_scalar) \
			or absf(thrust_axis_downworld_scalar) > 1.0 + 1.0e-10)):
		return {"ok": false}
	var stage_height_over_radius: float = context.height_over_radius
	if not is_nan(height_over_radius_override):
		stage_height_over_radius = height_over_radius_override
	return _evaluate_models(context.main_model, context.tail_model, context.airframe_model,
		state, omega, cg_air, rates, collective, cyclic_forward, cyclic_right, tail_collective,
		context.flow_floor_m_s, context.fin_tail_wake_fraction, stage_height_over_radius,
		context.loss, context.instability, diagnostics, true, thrust_axis_downworld_scalar)


static func _evaluate_models(main_model: Dictionary, tail_model: Dictionary, airframe_model: Dictionary,
		state: PackedFloat64Array, omega: float, cg_air: PackedFloat64Array, rates: PackedFloat64Array,
		collective: float, cyclic_forward: float, cyclic_right: float, tail_collective: float,
		flow_floor: float, fin_tail_wake_fraction: float, height_over_radius: float,
		loss: float, instability: float, diagnostics: bool, prepared: bool,
		thrust_axis_downworld_scalar: float) -> Dictionary:
	var hub_air: PackedFloat64Array = M.v3(
		cg_air[0] + rates[1] * main_model.hub_z_m - rates[2] * main_model.hub_y_m,
		cg_air[1] + rates[2] * main_model.hub_x_m - rates[0] * main_model.hub_z_m,
		cg_air[2] + rates[0] * main_model.hub_y_m - rates[1] * main_model.hub_x_m)
	var main_rotor: Dictionary
	var inflow: Dictionary
	var derivative: PackedFloat64Array
	if prepared:
		var parts: Array = MainStage._evaluate_prepared_parts(main_model, state, omega, hub_air, rates,
			collective, cyclic_forward, cyclic_right, flow_floor, height_over_radius, loss,
			instability, diagnostics, thrust_axis_downworld_scalar)
		if parts.size() != 3:
			return {"ok": false}
		main_rotor = parts[0]
		inflow = parts[1]
		derivative = parts[2]
	else:
		var main: Dictionary = MainStage.evaluate(main_model, state, omega, hub_air, rates,
			collective, cyclic_forward, cyclic_right, flow_floor, height_over_radius, loss,
			instability, diagnostics, thrust_axis_downworld_scalar)
		if not main.ok:
			return main
		main_rotor = main.rotor
		inflow = main.inflow
		derivative = main.derivative
	var tail: Dictionary = Tail._evaluate_prepared(tail_model, omega, state[2], cg_air, rates,
		tail_collective, diagnostics, main_model.omega_nominal_rad_s) if prepared else Tail.evaluate(
		tail_model, omega, state[2], cg_air, rates, tail_collective, diagnostics,
		main_model.omega_nominal_rad_s)
	if not tail.ok:
		return tail
	# Positive main vi is downward AIR motion in FRD. The tail's source Kλ
	# geometry supplies the common empirical ramp for both tail surfaces.
	# Tilted/convected/inverted spatial wakes are not qualified by this closure.
	var fuselage_wake: PackedFloat64Array = M.v3(0.0, 0.0, state[2])
	var vertical_wake: float = tail.wake_factor * state[2]
	var fin_wake: PackedFloat64Array = M.v3(0.0, fin_tail_wake_fraction * tail.induced_velocity_m_s, vertical_wake)
	var horizontal_wake: PackedFloat64Array = M.v3(0.0, 0.0, vertical_wake)
	var airframe: Dictionary
	if prepared and not diagnostics:
		airframe = Airframe._evaluate_compact_stage_prepared(airframe_model, cg_air, rates,
			fuselage_wake, fin_wake, horizontal_wake)
	elif prepared:
		airframe = Airframe._evaluate_prepared(airframe_model, cg_air, rates,
			fuselage_wake, fin_wake, horizontal_wake, diagnostics)
	else:
		airframe = Airframe.evaluate(airframe_model, cg_air, rates,
			fuselage_wake, fin_wake, horizontal_wake, diagnostics)
	if not airframe.ok:
		return airframe
	var loads: PackedFloat64Array = PackedFloat64Array()
	loads.resize(6)
	for i: int in range(6):
		loads[i] = main_rotor.loads[i] + tail.loads[i] + airframe.loads[i]
		if not is_finite(loads[i]):
			return {"ok": false}
	var effective_height_over_radius: float = height_over_radius
	var wake_intersects_ground: bool = true
	if not is_nan(thrust_axis_downworld_scalar):
		wake_intersects_ground = main_rotor.thrust_n * thrust_axis_downworld_scalar < 0.0
		if not wake_intersects_ground:
			effective_height_over_radius = -1.0
	var result: Dictionary = {"ok": true, "loads": loads, "derivative": derivative,
		"main_rotor": main_rotor, "inflow": inflow, "tail_rotor": tail, "airframe": airframe,
		"ground_effect_height_over_radius_used": effective_height_over_radius,
		"ground_effect_wake_intersects_ground": wake_intersects_ground}
	if diagnostics:
		result["wake_law"] = WAKE_LAW
		result["hub_air_velocity_body_frd_m_s"] = hub_air
		result["fuselage_wake_velocity_body_frd_m_s"] = fuselage_wake
		result["vertical_fin_wake_velocity_body_frd_m_s"] = fin_wake
		result["horizontal_tail_wake_velocity_body_frd_m_s"] = horizontal_wake
	return result


static func _vector(value: PackedFloat64Array) -> bool:
	if value.size() != 3:
		return false
	for entry: float in value:
		if not is_finite(entry):
			return false
	return true


static func _finite(values: Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


static func _scalar(model: Dictionary, key: String) -> bool:
	return model.has(key) and typeof(model[key]) == TYPE_FLOAT and is_finite(model[key])
