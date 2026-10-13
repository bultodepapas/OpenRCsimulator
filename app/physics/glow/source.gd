## NITRO-01: explicit family dispatch; legacy glow_prop is not a family selector.
extends RefCounted

const TwoStroke := preload("res://physics/glow/two_stroke.gd")
const FourStroke := preload("res://physics/glow/four_stroke.gd")


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
