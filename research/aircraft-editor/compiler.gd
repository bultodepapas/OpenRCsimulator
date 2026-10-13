extends RefCounted
class_name WorkshopCompilerDraft

const AircraftData := preload("../../app/physics/aircraft_data.gd")
const WheelProfiles := preload("../../app/physics/wheel_profiles.gd")
const Parameters := preload("parameters.gd")
const COMPILER_VERSION := "openrc-aircraft-workshop-v1-generic-compiler-1"
const REFERENCE_DENSITY_KG_M3 := 1.225


## Compiles a detached v2 candidate from the pinned base on every call.
## data is the full AircraftData.validate_and_derive() result, with the selected base wheel profile inherited.
static func compile(base: Dictionary, recipe: Dictionary) -> Dictionary:
	var parsed: Dictionary = Parameters.validate(recipe)
	if not parsed.ok:
		return _failure(parsed.errors)
	var values: Dictionary = parsed.values
	var base_raw: Dictionary = base.duplicate(true)
	var base_data: Dictionary = AircraftData.validate_and_derive(base_raw)
	if not base_data.ok:
		return _failure(base_data.errors)
	var base_id := str(base_raw.get("id", ""))
	var effective_id: String = str(values.get("id", base_id))
	var support: Dictionary = _capabilities_for(base_raw, base_data.model)
	var scale: float = float(values.scale)
	var weight_multiplier: float = float(values.weight_multiplier)
	var power_multiplier: float = float(values.power_multiplier)
	var control_multiplier: float = float(values.control_multiplier)
	var scale_power: float = 2.0 if values.mass_policy == "constant_wing_loading" else 3.0
	var mass_ratio: float = pow(scale, scale_power) * weight_multiplier
	if scale != 1.0 and not support.scale:
		parsed.errors.append("scale: unsupported for this aircraft module combination. " + str(support.note))
	if weight_multiplier != 1.0 and not support.weight:
		parsed.errors.append("weight_multiplier: unsupported for this aircraft module combination. " + str(support.note))
	if power_multiplier != 1.0 and not support.power:
		parsed.errors.append("power_multiplier: unsupported; only the validated prescribed-RPM propeller adapter is available. " + str(support.note))
	if control_multiplier != 1.0 and not support.controls:
		parsed.errors.append("control_multiplier: unsupported because the aircraft has no declared conventional surface controls")
	if not parsed.errors.is_empty():
		return _failure(parsed.errors)

	var candidate_raw: Dictionary = base_raw.duplicate(true)
	if scale != 1.0 or mass_ratio != 1.0 or power_multiplier != 1.0 or control_multiplier != 1.0:
		_transform_candidate(candidate_raw, base_id, scale, mass_ratio, power_multiplier,
			control_multiplier, str(values.mass_policy))
	if values.has("id"):
		candidate_raw.id = effective_id

	var candidate_data: Dictionary = AircraftData.validate_and_derive(candidate_raw)
	if not candidate_data.ok:
		return {"ok": false, "errors": candidate_data.errors, "raw": {}, "data": candidate_data, "summary": {}}
	var profiled_base: Dictionary = WheelProfiles.apply_to_model(base_data.model)
	if not profiled_base.ok:
		return _failure(profiled_base.errors)
	var wheel_errors := _inherit_wheel_model(
		profiled_base.model, candidate_data.model, base_id, effective_id, scale, mass_ratio
	)
	if not wheel_errors.is_empty():
		return {"ok": false, "errors": wheel_errors, "raw": {}, "data": _invalid_data(wheel_errors), "summary": {}}
	var actual_mass: float = float(candidate_data.model.mass_kg)
	var expected_mass: float = float(base_data.model.mass_kg) * mass_ratio
	if absf(actual_mass - expected_mass) > maxf(1.0, expected_mass) * 1.0e-10:
		var mass_error := PackedStringArray([
			"inventory: compiled mass " + str(actual_mass) + " kg does not match target " + str(expected_mass) + " kg"
		])
		return {"ok": false, "errors": mass_error, "raw": {}, "data": _invalid_data(mass_error), "summary": {}}

	var summary := _summary(base_data.model, candidate_data.model, values, mass_ratio, support)
	return {"ok": true, "errors": PackedStringArray(), "raw": candidate_raw, "data": candidate_data, "summary": summary}


## Reports the V1 operations exposed by the shared compiler registry for this validated base.
static func capabilities(base: Dictionary) -> Dictionary:
	var checked: Dictionary = AircraftData.validate_and_derive(base.duplicate(true))
	if not checked.ok:
		return {
			"scale": false,
			"weight": false,
			"power": false,
			"controls": false,
			"note": "Base data fails openrc-aircraft v2 validation: %s" % "; ".join(checked.errors),
		}
	return _capabilities_for(base, checked.model)


static func defaults() -> Dictionary:
	return Parameters.defaults()


static func _capabilities_for(raw: Dictionary, model: Dictionary) -> Dictionary:
	var propulsion: Dictionary = raw.get("propulsion", {})
	var engine: Dictionary = propulsion.get("engine", {})
	var propeller: Dictionary = propulsion.get("propeller", {})
	var family_is_legacy_rpm: bool = str(propulsion.get("kind", "glow_prop")) == "glow_prop"
	var complex_power: bool = engine.has("shaft") or engine.has("glow_installation") or propeller.has("normal_force")
	var scale_supported: bool = family_is_legacy_rpm and not complex_power
	var weight_supported: bool = scale_supported
	var power_supported: bool = family_is_legacy_rpm and not complex_power
	var raw_controls: Dictionary = raw.get("controls", {})
	var control_shape_ok: bool = raw_controls.get("max_throw", {}) is Dictionary
	var controls_supported: bool = str(raw.get("capabilities", {}).get("controls", "")) == "conventional" \
		and control_shape_ok and model.get("controls", {}).has("throw_deg")
	var reasons := PackedStringArray()
	if not family_is_legacy_rpm:
		reasons.append("the propulsion family is '%s'" % str(propulsion.get("kind", "glow_prop")))
	if engine.has("shaft"):
		reasons.append("coupled shaft propulsion has no V1 virtual scale/power transform")
	if engine.has("glow_installation"):
		reasons.append("finite-glow installation data must remain fixed until its module transform is qualified")
	if propeller.has("normal_force"):
		reasons.append("normal-force propeller coupling has no V1 virtual transform")
	var note := "V1 supports virtual scale, uniform mass, prescribed-RPM power and conventional controls; copied aerodynamic similarity is an estimate."
	if not scale_supported:
		note = "No-op compilation remains available. " + "; ".join(reasons)
	elif not controls_supported:
		note += " Conventional control travel is not declared for this aircraft."
	return {
		"scale": scale_supported,
		"weight": weight_supported,
		"power": power_supported,
		"controls": controls_supported,
		"note": note,
	}


static func _transform_candidate(raw: Dictionary, base_id: String, scale: float, mass_ratio: float,
		power_multiplier: float, control_multiplier: float, mass_policy: String) -> void:
	var geometry_policy := "uniform " + mass_policy + " virtual scale s=" + str(scale)
	_transform_q(raw.reference, "wing_area", scale * scale, base_id, geometry_policy + ": area × s²")
	_transform_q(raw.reference, "wing_span", scale, base_id, geometry_policy + ": length × s")
	_transform_q(raw.reference, "mean_chord", scale, base_id, geometry_policy + ": length × s")
	_transform_q(raw.reference, "root_chord", scale, base_id, geometry_policy + ": root chord × s")
	_transform_q(raw.reference, "tip_chord", scale, base_id, geometry_policy + ": tip chord × s")
	_transform_q(raw.reference, "aero_reference_point", scale, base_id, geometry_policy + ": position × s")
	_transform_q(raw.balance, "plan_cg", scale, base_id, geometry_policy + ": CG position × s")
	_transform_q(raw.balance, "firewall", scale, base_id, geometry_policy + ": firewall position × s")
	_transform_q(raw.balance, "cg_tolerance", scale, base_id, geometry_policy + ": CG tolerance × s")
	for component_variant: Variant in raw.inventory:
		if not component_variant is Dictionary:
			continue
		var component: Dictionary = component_variant
		_transform_q(component, "mass", mass_ratio, base_id, "uniform inventory mass × " + str(mass_ratio))
		_transform_q(component, "position", scale, base_id, geometry_policy + ": inventory position × s")
		_transform_q(component, "size", scale, base_id, geometry_policy + ": inventory box dimensions × s")
	_transform_q(raw.plausibility, "mass_range", mass_ratio, base_id,
		"virtual consistency band × target mass ratio " + str(mass_ratio) + "; original range retained in base evidence")
	# inertia_reference is donor evidence used by AircraftData's plausibility comparison.
	# The loader derives its expected scale from the compiled model, so mutating this
	# source quantity would scale the comparison twice and misrepresent the donor.
	if raw.has("start") and raw.start is Dictionary:
		_transform_q(raw.start, "level_speed", sqrt(mass_ratio) / scale, base_id,
			"similarity reference speed × sqrt(mass_ratio)/s")

	var aero: Dictionary = raw.get("aero", {})
	var surfaces: Dictionary = aero.get("surfaces", {})
	for surface_key: String in ["horizontal", "vertical"]:
		var surface_variant: Variant = surfaces.get(surface_key)
		if not surface_variant is Dictionary:
			continue
		var surface: Dictionary = surface_variant
		_transform_q(surface, "area", scale * scale, base_id, geometry_policy + ": surface area × s²")
		_transform_q(surface, "position", scale, base_id, geometry_policy + ": surface position × s")

	if raw.has("crash_hull"):
		_transform_q(raw, "crash_hull", scale, base_id, geometry_policy + ": crash-hull points × s")
	if raw.has("landing_gear"):
		var gear: Dictionary = raw.landing_gear
		var small_scale_anchor: float = maxf(scale, 1.0)
		var spring_factor: float = mass_ratio / small_scale_anchor
		var damping_factor: float = mass_ratio / sqrt(small_scale_anchor)
		for contact_variant: Variant in gear.contacts:
			if not contact_variant is Dictionary:
				continue
			var contact: Dictionary = contact_variant
			_transform_q(contact, "position", scale, base_id, geometry_policy + ": wheel contact position × s")
			_transform_q(contact, "stiffness", spring_factor, base_id,
				"virtual suspension retain small-model response: stiffness × mass_ratio/max(s,1)")
			_transform_q(contact, "damping", damping_factor, base_id,
				"virtual suspension retain small-model response: damping × mass_ratio/sqrt(max(s,1))")
			_transform_q(contact, "max_compression", small_scale_anchor, base_id,
				"virtual suspension retain small-model response: travel × max(s,1)")

	var propulsion: Dictionary = raw.get("propulsion", {})
	var engine: Dictionary = propulsion.get("engine", {})
	var propeller: Dictionary = propulsion.get("propeller", {})
	var rotor_factor: float = mass_ratio * scale * scale
	_transform_q(propeller, "diameter", scale, base_id, geometry_policy + ": virtual propeller diameter × s")
	_transform_q(propeller, "thrust_line_offset", scale, base_id, geometry_policy + ": fixed structural hub transformed with CG")
	_transform_q(propeller, "rotating_inertia", rotor_factor, base_id,
		"virtual rotor distribution: J × mass_ratio × s²; no manufacturer hardware claim")
	_transform_slipstream(propeller.get("slipstream"), base_id, scale)
	var similar_rpm_factor: float = sqrt(mass_ratio) / (scale * scale)
	_transform_q(engine, "max_rpm_static", similar_rpm_factor * pow(power_multiplier, 1.0 / 3.0), base_id,
		"prescribed-RPM virtual power: similar-scale RPM × power_multiplier^(1/3); static Cp/D law")
	_transform_q(engine, "idle_rpm", similar_rpm_factor, base_id,
		"prescribed-RPM virtual scale: retain base idle/max RPM ratio")

	var controls: Dictionary = raw.get("controls", {})
	var throws: Dictionary = controls.get("max_throw", {})
	for throw_key: Variant in throws.keys():
		_transform_q(throws, str(throw_key), control_multiplier, base_id,
			"virtual surface travel × " + str(control_multiplier) + "; normalized servo timing retained")


static func _transform_slipstream(node: Variant, base_id: String, scale: float) -> void:
	if not node is Dictionary:
		return
	var slipstream: Dictionary = node
	_transform_q(slipstream, "hub", scale, base_id, "slipstream hub position × s")
	for piece_variant: Variant in slipstream.get("pieces", []):
		if not piece_variant is Dictionary:
			continue
		var piece: Dictionary = piece_variant
		_transform_q(piece, "area", scale * scale, base_id, "slipstream piece area × s²")
		_transform_q(piece, "root", scale, base_id, "slipstream piece root position × s")
		_transform_q(piece, "span", scale, base_id, "slipstream piece span × s")
		_transform_q(piece, "chords", scale, base_id, "slipstream chord lengths × s")
		_transform_q(piece, "profile", scale, base_id, "slipstream profile coordinates/chords × s")


static func _transform_q(parent: Dictionary, key: String, factor: float, base_id: String, operation: String) -> void:
	if factor == 1.0 or not parent.has(key):
		return
	var candidate: Variant = parent[key]
	if not candidate is Dictionary or not candidate.has("value"):
		return
	var quantity: Dictionary = candidate
	var original_source := str(quantity.get("source", "unspecified base evidence"))
	quantity.value = _multiply_tree(quantity.value, factor)
	quantity.kind = "derived"
	quantity.source = "%s; Workshop compiler v1: %s from %s" % [original_source, operation, base_id]
	parent[key] = quantity


static func _multiply_tree(value: Variant, factor: float) -> Variant:
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return float(value) * factor
	if value is Array:
		var result: Array = []
		for element: Variant in value:
			result.append(_multiply_tree(element, factor))
		return result
	return value


static func _inherit_wheel_model(profiled_base: Dictionary, candidate_model: Dictionary, base_id: String,
		effective_id: String, scale: float, mass_ratio: float) -> PackedStringArray:
	var errors := PackedStringArray()
	var source_identity: Dictionary = profiled_base.get("wheel_profile", {}).duplicate(true)
	var source_status := str(source_identity.get("status", "legacy_fallback"))
	var candidate_gear: Dictionary = candidate_model.get("landing_gear", {})
	if source_status == "applied":
		var source_gear: Dictionary = profiled_base.get("landing_gear", {})
		var source_contacts: Array = source_gear.get("contacts", [])
		var target_contacts: Array = candidate_gear.get("contacts", [])
		if source_contacts.size() != target_contacts.size():
			errors.append("wheel profile: inherited base contact count differs from compiled landing gear")
			return errors
		var source_by_name: Dictionary = {}
		for source_variant: Variant in source_contacts:
			if source_variant is Dictionary:
				var source_contact: Dictionary = source_variant
				source_by_name[str(source_contact.get("name", ""))] = source_contact
		var wheel_effective_mass := 0.0
		var largest_radius := 0.0
		for index: int in target_contacts.size():
			if not target_contacts[index] is Dictionary:
				continue
			var target_contact: Dictionary = target_contacts[index]
			var contact_name := str(target_contact.get("name", ""))
			if not source_by_name.has(contact_name):
				errors.append("wheel profile: base has no profile for compiled contact '%s'" % contact_name)
				continue
			var source_contact: Dictionary = source_by_name[contact_name]
			var source_provenance: Dictionary = source_contact.get("wheel_provenance", {}).duplicate(true)
			var factors := {
				"wheel_radius": scale,
				"wheel_inertia": mass_ratio * scale * scale,
				"spin_relaxation": 1.0,
				"brake_torque": mass_ratio * scale if source_contact.get("brake_availability") == "available" else 1.0,
			}
			for field_variant: Variant in factors.keys():
				var field := str(field_variant)
				var base_value: float = float(source_contact.get(field, 0.0))
				var factor: float = float(factors[field])
				var new_value := base_value * factor
				target_contact[field] = new_value
				if source_provenance.has(field) and factor != 1.0:
					var quantity: Dictionary = source_provenance[field]
					quantity.value = new_value
					quantity.kind = "derived"
					quantity.source = str(quantity.get("source", "base wheel profile evidence")) \
						+ "; Workshop compiler v1 wheel transform from " + base_id + " (factor " + str(factor) + ")"
					source_provenance[field] = quantity
			target_contact.wheel_provenance = source_provenance
			var radius := float(target_contact.get("wheel_radius", 0.0))
			var inertia := float(target_contact.get("wheel_inertia", 0.0))
			var relaxation := float(target_contact.get("spin_relaxation", 0.0))
			if radius <= 0.0 or inertia < 0.0 or relaxation <= 0.0:
				errors.append("wheel profile '%s' contact '%s': inherited values are not physically valid" % [effective_id, contact_name])
			else:
				wheel_effective_mass += inertia / (radius * radius)
				largest_radius = maxf(largest_radius, radius)
				var dt := 1.0 / float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 240.0))
				if dt / relaxation > 0.25:
					errors.append("wheel profile '%s' contact '%s': physics_dt / spin_relaxation exceeds 0.25" % [effective_id, contact_name])
			target_contacts[index] = target_contact
		if wheel_effective_mass > float(candidate_model.get("mass_kg", 0.0)) * 0.1:
			errors.append("wheel profile '" + effective_id + "': wheel effective mass exceeds 10 percent of compiled aircraft mass")
		if errors.is_empty():
			candidate_gear.contacts = target_contacts
			candidate_gear.rolling_reference_radius = largest_radius
			candidate_gear.rolling_reference_radius_provenance = {
				"value": largest_radius,
				"unit": "m",
				"kind": "derived",
				"source": "maximum inherited wheel radius transformed from base %s by Workshop compiler v1" % base_id,
			}
			candidate_model.landing_gear = candidate_gear
	var inherited_identity: Dictionary = source_identity.duplicate(true)
	inherited_identity.aircraft_id = effective_id
	inherited_identity.base_aircraft_id = base_id
	inherited_identity.status = "inherited" if source_status == "applied" else source_status
	candidate_model.wheel_profile = inherited_identity
	return errors


static func _summary(base_model: Dictionary, model: Dictionary, values: Dictionary,
		mass_ratio: float, support: Dictionary) -> Dictionary:
	var summary := {
		"base_aircraft_id": str(base_model.get("id", "")),
		"effective_model_id": str(model.get("id", "")),
		"name": str(values.get("name", model.get("id", ""))),
		"scale": float(values.scale),
		"mass_policy": str(values.mass_policy),
		"weight_multiplier": float(values.weight_multiplier),
		"mass_ratio": mass_ratio,
		"mass_kg": float(model.mass_kg),
		"wing_area_m2": float(model.reference.S),
		"wing_span_m": float(model.reference.b),
		"wing_loading_kg_m2": float(model.mass_kg) / float(model.reference.S),
		"power_multiplier": float(values.power_multiplier),
		"control_multiplier": float(values.control_multiplier),
		"capabilities": support.duplicate(true),
		"compiler_version": COMPILER_VERSION,
	}
	var propulsion: Dictionary = model.get("propulsion", {})
	if support.power and propulsion.has("max_rpm") and propulsion.has("idle_rpm") and propulsion.has("diameter") \
			and propulsion.has("ct") and propulsion.has("cp"):
		var rpm := float(propulsion.max_rpm)
		var diameter := float(propulsion.diameter)
		var ct: PackedFloat64Array = propulsion.ct
		var cp: PackedFloat64Array = propulsion.cp
		var rev_per_second := rpm / 60.0
		var static_thrust := float(ct[1]) * REFERENCE_DENSITY_KG_M3 * rev_per_second * rev_per_second * pow(diameter, 4.0)
		var static_power := float(cp[1]) * REFERENCE_DENSITY_KG_M3 * pow(rev_per_second, 3.0) * pow(diameter, 5.0)
		summary["propulsion_family"] = "prescribed_rpm_propeller"
		summary["idle_rpm"] = float(propulsion.idle_rpm)
		summary["max_rpm"] = rpm
		summary["static_thrust_n"] = static_thrust
		summary["static_power_w"] = static_power
		summary["power_reference_note"] = "Static coefficient-law estimate at 1.225 kg/m³; virtual RPM/propeller proposal, not a measured engine rating."
	else:
		summary["propulsion_family"] = str(propulsion.get("kind", "unknown"))
	return summary


static func _failure(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "errors": errors, "raw": {}, "data": _invalid_data(errors), "summary": {}}


static func _invalid_data(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "errors": errors.duplicate(), "warnings": PackedStringArray(), "model": {}}
