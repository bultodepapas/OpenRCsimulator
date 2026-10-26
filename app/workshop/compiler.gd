extends RefCounted
class_name WorkshopCompiler

const AircraftData := preload("res://physics/aircraft_data.gd")
const AircraftModules := preload("res://physics/aircraft_modules.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const Parameters := preload("res://workshop/parameters.gd")
const COMPILER_VERSION := "openrc-aircraft-workshop-v1-generic-compiler-2"
const MEASURED_MASS_COMPILER_VERSION := "openrc-aircraft-workshop-v1-measured-mass-1"
const VIRTUAL_SIZE_COMPILER_VERSION := "openrc-aircraft-workshop-v1-virtual-size-1"
const SURFACE_CONTROLS_COMPILER_VERSION := "openrc-aircraft-workshop-v1-surface-controls-1"
const DOMAIN_TAG := "_workshop_quantity_domain"
const REFERENCE_DENSITY_KG_M3 := 1.225
## FUEL-11a: tank volume follows airframe scale and an independent estimated capacity ratio;
## fill and density stay fixed while weight policy acts on dry inventory only.
const TANK_POLICY := "FUEL-11a dry-only mass and independent tank-capacity policy"


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
	var classification: Dictionary = support.classification
	if not classification.ok:
		return {
			"ok": false,
			"errors": classification.errors,
			"diagnostics": classification.diagnostics,
			"modules": [],
			"laws": [],
			"raw": {},
			"data": _invalid_data(classification.errors),
			"summary": {},
		}
	var scale: float = float(values.scale)
	var virtual_size := uses_virtual_size(values)
	var weight_multiplier: float = float(values.weight_multiplier)
	var power_multiplier: float = float(values.power_multiplier)
	var control_multiplier: float = float(values.control_multiplier)
	var surface_control_multipliers := {}
	var any_control_change: bool = control_multiplier != 1.0
	for surface: String in Parameters.CONTROL_SURFACES:
		var key := "control_multiplier_" + surface
		var multiplier: float = float(values.get(key, control_multiplier))
		surface_control_multipliers[surface] = multiplier
		if values.has(key) and not bool(support.get("control_" + surface, false)):
			parsed.errors.append("%s: unsupported because this aircraft has no declared %s surface throw" % [key, surface])
		if multiplier != 1.0:
			any_control_change = true
	var tank_capacity_multiplier: float = float(values.tank_capacity_multiplier)
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
	if tank_capacity_multiplier != 1.0 and not support.tank_capacity:
		parsed.errors.append("tank_capacity_multiplier: unsupported because this aircraft has no declared fuel tanks")
	var mass_edits: Array = values.get("mass_edits", [])
	if not mass_edits.is_empty() and (scale != 1.0 or weight_multiplier != 1.0 or tank_capacity_multiplier != 1.0):
		parsed.errors.append("mass_edits: measured components require original scale, weight and tank capacity")
	if not parsed.errors.is_empty():
		return _failure(parsed.errors)

	var candidate_raw: Dictionary = base_raw.duplicate(true)
	if not mass_edits.is_empty():
		var measured: Dictionary = load("res://workshop/mass_edit.gd").apply_to_validated_base(base_raw, mass_edits)
		if not measured.ok: return _failure(measured.errors)
		candidate_raw = measured.raw.duplicate(true)
	var mass_source: Dictionary = candidate_raw.duplicate(true) if not mass_edits.is_empty() else base_raw
	if scale != 1.0 or mass_ratio != 1.0 or power_multiplier != 1.0 or any_control_change \
			or tank_capacity_multiplier != 1.0:
		_transform_candidate(candidate_raw, base_id, scale, mass_ratio, power_multiplier,
			control_multiplier, surface_control_multipliers, tank_capacity_multiplier,
			str(values.mass_policy), virtual_size)
	if values.has("id"):
		candidate_raw.id = effective_id

	# Transform-emitted domains are private compiler metadata, removed before the
	# v2 contract or serialization. Ordinary imports keep their stock numeric bounds.
	var domain := {}
	_collect_domains(candidate_raw, "", domain)
	var candidate_data: Dictionary = AircraftData.validate_virtual_scale(candidate_raw, domain) \
		if virtual_size else AircraftData.validate_and_derive(candidate_raw)
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
	var expected_mass: float = _expected_mass(mass_source, mass_ratio, scale, tank_capacity_multiplier)
	if absf(actual_mass - expected_mass) > maxf(1.0, expected_mass) * 1.0e-10:
		var mass_error := PackedStringArray([
			"inventory: compiled mass " + str(actual_mass) + " kg does not match target " + str(expected_mass) + " kg"
		])
		return {"ok": false, "errors": mass_error, "raw": {}, "data": _invalid_data(mass_error), "summary": {}}

	var summary := _summary(base_data.model, candidate_data.model, values, mass_ratio, support)
	if not mass_edits.is_empty():
		summary.mass_ratio = actual_mass / float(base_data.model.mass_kg)
		summary.measured_components = mass_edits.size()
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
			"control_aileron": false,
			"control_elevator": false,
			"control_rudder": false,
			"tank_capacity": false,
			"note": "Base data fails openrc-aircraft v2 validation: %s" % "; ".join(checked.errors),
		}
	return _capabilities_for(base, checked.model)


static func defaults() -> Dictionary:
	return Parameters.defaults()


## Extensions select their own evaluator identity; legacy recipes retain compiler-2.
static func version_for_recipe(recipe: Dictionary) -> String:
	for surface: String in Parameters.CONTROL_SURFACES:
		if recipe.has("control_multiplier_" + surface):
			return SURFACE_CONTROLS_COMPILER_VERSION
	var edits: Variant = recipe.get("mass_edits", [])
	if edits is Array and not edits.is_empty(): return MEASURED_MASS_COMPILER_VERSION
	return VIRTUAL_SIZE_COMPILER_VERSION if uses_virtual_size(recipe) else COMPILER_VERSION


static func uses_virtual_size(recipe: Dictionary) -> bool:
	var scale: float = float(recipe.get("scale", 1.0))
	return recipe.get("size_model", "") == Parameters.VIRTUAL_SIZE_MODEL or scale < 0.35 or scale > 2.25


static func _capabilities_for(raw: Dictionary, model: Dictionary) -> Dictionary:
	var classification: Dictionary = AircraftModules.classify(raw)
	if not classification.ok:
		return {
			"scale": false,
			"weight": false,
			"power": false,
			"controls": false,
			"control_aileron": false,
			"control_elevator": false,
			"control_rudder": false,
			"tank_capacity": false,
			"note": "Aircraft modules could not be classified: %s" % "; ".join(classification.errors),
			"classification": classification,
		}
	var transform_support: Dictionary = classification.compiler_transforms
	var scale_supported: bool = bool(transform_support.get("scale", false))
	var weight_supported: bool = bool(transform_support.get("weight", false))
	var power_supported: bool = bool(transform_support.get("power", false))
	var raw_controls: Dictionary = raw.get("controls", {})
	var control_shape_ok: bool = raw_controls.get("max_throw", {}) is Dictionary
	var controls_supported: bool = bool(transform_support.get("controls", false)) \
		and control_shape_ok and model.get("controls", {}).has("throw_deg")
	var declared_throws: Variant = raw_controls.get("max_throw", {})
	var model_controls: Dictionary = model.get("controls", {})
	var model_throws: Variant = model_controls.get("throw_deg", {})
	var surface_support := {}
	for surface: String in Parameters.CONTROL_SURFACES:
		surface_support[surface] = controls_supported and declared_throws is Dictionary \
			and declared_throws.has(surface) and model_throws is Dictionary and model_throws.has(surface)
	var fuel_system: Variant = raw.get("fuel_system", {})
	var tank_capacity_supported: bool = fuel_system is Dictionary and fuel_system.get("tanks") is Array \
		and not fuel_system.tanks.is_empty() and model.get("fuel_system", {}).get("tanks", []).size() == fuel_system.tanks.size()
	var reasons := PackedStringArray()
	for reason_variant: Variant in classification.compiler_transform_reasons:
		reasons.append(str(reason_variant))
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
		"control_aileron": bool(surface_support.get("aileron", false)),
		"control_elevator": bool(surface_support.get("elevator", false)),
		"control_rudder": bool(surface_support.get("rudder", false)),
		"tank_capacity": tank_capacity_supported,
		"note": note,
		"classification": classification,
	}


static func _transform_candidate(raw: Dictionary, base_id: String, scale: float, mass_ratio: float,
		power_multiplier: float, control_multiplier: float, surface_control_multipliers: Dictionary,
		tank_capacity_multiplier: float,
		mass_policy: String, virtual_size := false) -> void:
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
	if raw.balance.get("cg_range") is Dictionary:
		_transform_q(raw.balance.cg_range, "forward", scale, base_id, geometry_policy + ": CG range × s")
		_transform_q(raw.balance.cg_range, "aft", scale, base_id, geometry_policy + ": CG range × s")
	var liquid := _tank_liquid_ids(raw)
	var tank_inventory := _tank_inventory_ids(raw)
	var tank_ratio: float = pow(scale, 3.0) * tank_capacity_multiplier
	var tank_dimension_ratio: float = scale * pow(tank_capacity_multiplier, 1.0 / 3.0)
	var hub_le: Variant = _hub_le(raw)
	# The gear and the flight speed carry the whole airplane, the dry build and its tank liquid.
	var total_ratio: float = mass_ratio
	if not liquid.is_empty() and tank_ratio != mass_ratio:
		total_ratio = _expected_mass(raw, mass_ratio, scale, tank_capacity_multiplier) / _expected_mass(raw, 1.0, 1.0, 1.0)
	for component_variant: Variant in raw.inventory:
		if not component_variant is Dictionary:
			continue
		var component: Dictionary = component_variant
		if liquid.has(str(component.get("id", ""))):
			_transform_q(component, "mass", tank_ratio, base_id,
				TANK_POLICY + ": tank liquid mass follows volume × s³ × capacity ratio at fixed fill and density")
		else:
			_transform_q(component, "mass", mass_ratio, base_id, "uniform inventory mass × " + str(mass_ratio))
		_transform_q(component, "position", scale, base_id, geometry_policy + ": inventory position × s")
		var dimension_ratio: float = tank_dimension_ratio if tank_inventory.has(str(component.get("id", ""))) else scale
		var size_policy: String = TANK_POLICY + ": tank box dimensions × s × cbrt(capacity ratio)" \
			if dimension_ratio != scale else geometry_policy + ": inventory box dimensions × s"
		_transform_q(component, "size", dimension_ratio, base_id, size_policy)
	for tank_variant: Variant in raw.get("fuel_system", {}).get("tanks", []):
		if tank_variant is Dictionary:
			_transform_q(tank_variant, "capacity", tank_ratio, base_id, TANK_POLICY + ": capacity × s³ × capacity ratio")
			_transform_q(tank_variant, "unusable", tank_ratio, base_id, TANK_POLICY + ": unusable volume × s³ × capacity ratio")
			_transform_q(tank_variant, "reserve", tank_ratio, base_id, TANK_POLICY + ": reserve volume × s³ × capacity ratio")
	var plausibility_ratio := total_ratio if virtual_size else mass_ratio
	_transform_q(raw.plausibility, "mass_range", plausibility_ratio, base_id,
		"virtual consistency band × target mass ratio " + str(plausibility_ratio) + "; original range retained in base evidence")
	# inertia_reference is donor evidence used by AircraftData's plausibility comparison.
	# The loader derives its expected scale from the compiled model, so mutating this
	# source quantity would scale the comparison twice and misrepresent the donor.
	if raw.has("start") and raw.start is Dictionary:
		_transform_q(raw.start, "level_speed", sqrt(total_ratio) / scale, base_id,
			"similarity reference speed × sqrt(mass_ratio)/s, with the total mass ratio including tank liquid")

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
		var spring_factor: float = total_ratio / small_scale_anchor
		var damping_factor: float = total_ratio / sqrt(small_scale_anchor)
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
	if liquid.is_empty() or tank_ratio == mass_ratio or not hub_le is PackedFloat64Array:
		_transform_q(propeller, "thrust_line_offset", scale, base_id, geometry_policy + ": fixed structural hub transformed with CG")
	else:
		# The liquid and the dry build scale differently, so the datum (inventory CG) no longer scales with s:
		# keep the structural hub and re-reference it to the compiled datum.
		var datum: Variant = _inventory_cg(raw.inventory)
		var offset: Dictionary = propeller.thrust_line_offset
		offset.value = [scale * hub_le[0] - datum[0], scale * hub_le[1] - datum[1], scale * hub_le[2] - datum[2]]
		offset.kind = "derived"
		offset[DOMAIN_TAG] = scale
		offset.source = "%s; Workshop compiler v2: %s: structural hub × s about the compiled inventory CG from %s" % [
			str(offset.get("source", "unspecified base evidence")), TANK_POLICY, base_id]
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
		var key_str := str(throw_key)
		var factor: float = float(surface_control_multipliers.get(key_str, control_multiplier))
		_transform_q(throws, key_str, factor, base_id,
			"virtual surface travel × " + str(factor) + "; normalized servo timing retained")


## FUEL-11a: liquid inventory ids of the declared tanks.
static func _tank_inventory_ids(raw: Dictionary) -> Dictionary:
	var ids := {}
	var system: Variant = raw.get("fuel_system")
	if system is Dictionary and system.get("tanks") is Array:
		for tank: Variant in system.tanks:
			if not tank is Dictionary:
				continue
			for key: String in ["liquid_inventory_id", "shell_inventory_id"]:
				if tank.has(key):
					ids[str(tank[key])] = true
	return ids


## FUEL-11a: liquid inventory ids of the declared tanks.
static func _tank_liquid_ids(raw: Dictionary) -> Dictionary:
	var ids := {}
	var system: Variant = raw.get("fuel_system")
	if system is Dictionary and system.get("tanks") is Array:
		for tank: Variant in system.tanks:
			if tank is Dictionary and tank.has("liquid_inventory_id"):
				ids[str(tank.liquid_inventory_id)] = true
	return ids


## Inventory CG, the body datum, summed left to right as AircraftData does; null without mass.
static func _inventory_cg(inventory: Array) -> Variant:
	var mass := 0.0
	var first := PackedFloat64Array([0.0, 0.0, 0.0])
	for item: Variant in inventory:
		if not item is Dictionary:
			return null
		var m: float = float(item.mass.value)
		mass += m
		for k in 3:
			first[k] += m * float(item.position.value[k])
	if mass <= 0.0:
		return null
	return PackedFloat64Array([first[0] / mass, first[1] / mass, first[2] / mass])


## The propeller hub in LE coordinates (datum + datum-relative offset), or null when it is not declared.
static func _hub_le(raw: Dictionary) -> Variant:
	var offset: Variant = raw.get("propulsion", {}).get("propeller", {}).get("thrust_line_offset")
	var datum: Variant = _inventory_cg(raw.get("inventory", []))
	if not offset is Dictionary or not offset.get("value") is Array or offset.value.size() != 3 or datum == null:
		return null
	return PackedFloat64Array([datum[0] + float(offset.value[0]), datum[1] + float(offset.value[1]),
		datum[2] + float(offset.value[2])])


## Target mass: the dry build × mass_ratio plus tank liquid × s³ × the independent capacity ratio (FUEL-11a).
static func _expected_mass(base_raw: Dictionary, mass_ratio: float, scale: float,
		tank_capacity_multiplier: float) -> float:
	var liquid := _tank_liquid_ids(base_raw)
	var dry := 0.0
	var fuel := 0.0
	for item: Variant in base_raw.get("inventory", []):
		if item is Dictionary:
			if liquid.has(str(item.get("id", ""))):
				fuel += float(item.mass.value)
			else:
				dry += float(item.mass.value)
	return dry * mass_ratio + fuel * pow(scale, 3.0) * tank_capacity_multiplier


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
	quantity[DOMAIN_TAG] = factor
	quantity.source = "%s; Workshop compiler v2: %s from %s" % [original_source, operation, base_id]
	parent[key] = quantity


## Keep the dimensional domain emitted by each actual transform; never infer a
## wider bound from an arbitrary imported value. Dimensionless/control limits stay fixed.
static func _collect_domains(node: Variant, path: String, domain: Dictionary) -> void:
	if node is Dictionary:
		if node.has(DOMAIN_TAG):
			if str(node.get("unit", "")) in ["m", "m2", "kg", "kg·m2", "l", "N/m", "N·s/m", "rpm", "m/s"]:
				domain[path] = float(node[DOMAIN_TAG])
			node.erase(DOMAIN_TAG)
		for key: String in node:
			_collect_domains(node[key], key if path.is_empty() else path + "." + key, domain)
	elif node is Array:
		for index: int in node.size():
			var child_path := "%s[%d]" % [path, index]
			if path == "inventory" and node[index] is Dictionary:
				child_path += " " + str(node[index].get("name", "?"))
			_collect_domains(node[index], child_path, domain)


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
			target_contact.brake_availability = str(source_contact.get("brake_availability", "none"))
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
						+ "; Workshop compiler v2 wheel transform from " + base_id + " (factor " + str(factor) + ")"
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
				"source": "maximum inherited wheel radius transformed from base %s by Workshop compiler v2" % base_id,
			}
			candidate_model.landing_gear = candidate_gear
	var inherited_identity: Dictionary = source_identity.duplicate(true)
	inherited_identity.aircraft_id = effective_id
	inherited_identity.base_aircraft_id = base_id
	# Runtime wheel dynamics are selected by status == "applied". Keep that physical
	# capability marker while recording that the profile came from the selected base.
	inherited_identity.status = source_status
	inherited_identity.inheritance = "base_profile" if source_status == "applied" else "base_fallback"
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
		"tank_capacity_multiplier": float(values.tank_capacity_multiplier),
		"capabilities": support.duplicate(true),
		"compiler_version": version_for_recipe(values),
	}
	for surface: String in Parameters.CONTROL_SURFACES:
		var key := "control_multiplier_" + surface
		summary[key] = float(values.get(key, values.control_multiplier))
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
	var tank_capacity_l := 0.0
	for tank: Variant in model.get("fuel_system", {}).get("tanks", []):
		if tank is Dictionary:
			tank_capacity_l += maxf(0.0, float(tank.get("capacity_m3", 0.0))) * 1000.0
	if tank_capacity_l > 0.0:
		summary["fuel_capacity_l"] = tank_capacity_l
	return summary


static func _failure(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "errors": errors, "raw": {}, "data": _invalid_data(errors), "summary": {}}


static func _invalid_data(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "errors": errors.duplicate(), "warnings": PackedStringArray(), "model": {}}
