## NITRO-01: explicit family dispatch; legacy glow_prop is not a family selector.
extends RefCounted

const TwoStroke := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/glow/two_stroke.gd")
const FourStroke := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/glow/four_stroke.gd")
const Profile := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/glow/profile.gd")


## Detached, validated engine data for repeated RK stages. The object contains no
## physical state; callers create a new one whenever an installation is replaced.
class PreparedEvaluator extends RefCounted:
	var _model: Dictionary
	var _family: String
	var _parameters: Dictionary
	var _operation: Dictionary
	var _identity: Dictionary

	func _init(model: Dictionary) -> void:
		_model = model.duplicate(true)
		_make_read_only(_model)
		_family = str(_model.family)
		_parameters = _model.parameters
		_operation = _model.operation
		_identity = _model.identity

	func _make_read_only(value: Variant) -> void:
		if value is Dictionary:
			var keys: Array = value.keys()
			for key: Variant in keys:
				_make_read_only(value[key])
			value.make_read_only()
		elif value is Array:
			for index: int in range(value.size()):
				_make_read_only(value[index])
			value.make_read_only()


static func evaluate(model: Dictionary, rpm: float, admission: float, mixture: float,
		dry_density_kg_m3: float, running: bool = true, firing_fraction: float = 1.0) -> Dictionary:
	var family: Variant = model.get("family")
	var parameters: Variant = model.get("parameters")
	var operation: Variant = model.get("operation")
	var identity: Variant = model.get("identity")
	if family not in ["glow_2t", "glow_4t"] or not parameters is Dictionary or not operation is Dictionary or not identity is Dictionary:
		return {ok = false, message = "Missing or unsupported explicit glow family/model"}
	if identity.get("status") != "candidate" or typeof(identity.get("cycle_revolutions")) != TYPE_INT or identity.cycle_revolutions != (1 if family == "glow_2t" else 2):
		return {ok = false, message = "Invalid profile identity or mechanical cycle"}
	var maximum: Variant = operation.get("max_rpm")
	if typeof(maximum) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(maximum)) or float(maximum) <= 0.0:
		return {ok = false, message = "Invalid model RPM support"}
	if not is_finite(rpm) or rpm < 0.0 or rpm > float(maximum):
		return {ok = false, message = "RPM query outside the declared profile envelope"}
	var result: Dictionary = TwoStroke.evaluate(rpm, admission, mixture, dry_density_kg_m3, parameters, running, firing_fraction) if family == "glow_2t" else FourStroke.evaluate(rpm, admission, mixture, dry_density_kg_m3, parameters, running, firing_fraction)
	if result.ok:
		result.family = family
		result.cycle_revolutions = 1 if family == "glow_2t" else 2
		result.profile_identity = identity.duplicate(true)
		result.brake_power_w = result.shaft_torque_nm * rpm * TAU / 60.0
		result.unburned_chemical_power_w = result.fuel_input_power_w - result.chemical_power_w
		if not is_finite(result.brake_power_w) or not is_finite(result.unburned_chemical_power_w) or result.unburned_chemical_power_w < -1e-10 * maxf(1.0, result.fuel_input_power_w):
			return {ok = false, message = "Invalid derived glow power balance"}
	return result


## NITRO-06: the wide-open breathing of the engine at this speed, the delivery ratio (2T) or volumetric efficiency
## (4T) that the carburettor's flow restriction scales. Tables are clamped outside their support.
static func breathing(model: Dictionary, rpm: float) -> float:
	var parameters: Dictionary = model.parameters
	if str(model.family) == "glow_2t":
		return TwoStroke._sample(parameters.delivery_ratio, rpm)
	return FourStroke._sample(parameters.volumetric_efficiency, rpm)


static func breathing_prepared(evaluator: PreparedEvaluator, rpm: float) -> float:
	if evaluator._family == "glow_2t":
		return TwoStroke._sample(evaluator._parameters.delivery_ratio, rpm)
	return FourStroke._sample(evaluator._parameters.volumetric_efficiency, rpm)


## Validates a normalized model against its provenance once and returns an
## evaluator over a detached snapshot. This stays outside Profile.model so model
## serialization and deterministic comparisons remain data-only.
static func prepare_evaluator(model: Dictionary) -> Dictionary:
	if not model is Dictionary or not model.get("provenance") is Dictionary:
		return {ok = false, message = "Prepared glow evaluator requires normalized profile provenance"}
	var normalized: Dictionary = Profile.prepare(model.provenance)
	if not normalized.get("ok", false):
		return {ok = false, message = "Glow profile provenance is invalid: " + str(normalized.errors[0])}
	var expected: Dictionary = normalized.model
	var model_identity: Variant = model.get("identity")
	if not model_identity is Dictionary:
		return {ok = false, message = "Glow normalized model identity is malformed"}
	var input_hash: Variant = model_identity.get("input_sha256")
	if input_hash != null:
		if typeof(input_hash) != TYPE_STRING or not _is_sha256(str(input_hash)):
			return {ok = false, message = "Glow profile input identity is malformed"}
		expected.identity.input_sha256 = input_hash
	if expected != model:
		return {ok = false, message = "Normalized glow model differs from its validated provenance"}
	return {ok = true, message = "", evaluator = PreparedEvaluator.new(expected)}


## Repeated-stage counterpart to evaluate(). Its only accepted evaluator is the
## typed snapshot returned by prepare_evaluator(); query and table coverage are
## still checked for each stage.
static func evaluate_prepared(evaluator: PreparedEvaluator, rpm: float, admission: float,
		mixture: float, dry_density_kg_m3: float, running: bool = true,
		firing_fraction: float = 1.0) -> Dictionary:
	if not evaluator is PreparedEvaluator:
		return {ok = false, message = "A prepared glow evaluator is required"}
	var family: String = evaluator._family
	if not is_finite(rpm) or rpm < 0.0 or rpm > float(evaluator._operation.max_rpm):
		return {ok = false, message = "RPM query outside the declared profile envelope"}
	var result: Dictionary = TwoStroke._evaluate_prevalidated(rpm, admission, mixture,
		dry_density_kg_m3, evaluator._parameters, running, firing_fraction) if family == "glow_2t" else FourStroke._evaluate_prevalidated(rpm, admission, mixture,
		dry_density_kg_m3, evaluator._parameters, running, firing_fraction)
	if result.ok:
		result.family = family
		result.cycle_revolutions = 1 if family == "glow_2t" else 2
		result.profile_identity = evaluator._identity.duplicate(true)
		result.brake_power_w = result.shaft_torque_nm * rpm * TAU / 60.0
		result.unburned_chemical_power_w = result.fuel_input_power_w - result.chemical_power_w
		if not is_finite(result.brake_power_w) or not is_finite(result.unburned_chemical_power_w) or result.unburned_chemical_power_w < -1e-10 * maxf(1.0, result.fuel_input_power_w):
			return {ok = false, message = "Invalid derived glow power balance"}
	return result


## Computes the same delivered-premix-flow scale as a full source evaluation,
## without calculating torque, heat and power that are discarded by lifecycle.
static func unit_fuel_flow_prepared(evaluator: PreparedEvaluator, rpm: float,
		admission: float, mixture: float, dry_density_kg_m3: float) -> Dictionary:
	if not evaluator is PreparedEvaluator:
		return {ok = false, message = "A prepared glow evaluator is required"}
	if not is_finite(rpm) or rpm < 0.0 or rpm > float(evaluator._operation.max_rpm):
		return {ok = false, message = "RPM query outside the declared profile envelope"}
	if not is_finite(admission) or admission < 0.0 or admission > 1.0:
		return {ok = false, message = "admission must be finite and in [0, 1]"}
	if not is_finite(mixture) or mixture < 0.0:
		return {ok = false, message = "mixture must be finite and nonnegative"}
	if not is_finite(dry_density_kg_m3) or dry_density_kg_m3 <= 0.0:
		return {ok = false, message = "dry_density_kg_m3 must be finite and positive"}
	var parameters: Dictionary = evaluator._parameters
	var combustion: PackedFloat64Array = parameters.combustion_efficiency
	if mixture < combustion[0] or mixture > combustion[combustion.size() - 2]:
		return {ok = false, message = "combustion_efficiency does not cover the query"}
	var unit_flow: float = 0.0
	if rpm > 0.0:
		var air_per_cycle: float
		var cycle_frequency_hz: float
		if evaluator._family == "glow_2t":
			var delivery: float = TwoStroke._sample(parameters.delivery_ratio, rpm)
			air_per_cycle = dry_density_kg_m3 * float(parameters.displacement_m3) * admission * delivery
			cycle_frequency_hz = rpm / 60.0
		else:
			var volumetric_efficiency: float = FourStroke._sample(parameters.volumetric_efficiency, rpm)
			air_per_cycle = dry_density_kg_m3 * float(parameters.displacement_m3) * admission * volumetric_efficiency
			cycle_frequency_hz = rpm / 120.0
		var gross_premix_kg_cycle: float = air_per_cycle * mixture / float(parameters.stoich_air_fuel_ratio) / (1.0 - float(parameters.oil_fraction))
		var delivered_fuel_kg_s: float = gross_premix_kg_cycle * cycle_frequency_hz
		unit_flow = delivered_fuel_kg_s / mixture if mixture > 0.0 else 0.0
	if not is_finite(unit_flow) or unit_flow < 0.0:
		return {ok = false, message = "Fuel-flow scale is nonfinite"}
	return {"ok": true, "message": "", "unit_fuel_flow_kg_s_per_mixture": unit_flow}


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true
