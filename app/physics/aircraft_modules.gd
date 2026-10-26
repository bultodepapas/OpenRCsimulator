extends RefCounted
class_name AircraftModules

const REGISTRY_PATH := "res://data/schema/aircraft-modules-v1.json"
const REGISTRY_FORMAT := "openrc-aircraft-modules v1"


## Classifies v2 capabilities and normalized laws from the shared JSON registry.
## Legacy Workshop module IDs are kept in `modules`; detailed law selections are separate.
static func classify(base: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var diagnostics: Array[Dictionary] = []
	var registry_result := _load_registry()
	if not registry_result.ok:
		_issue(errors, diagnostics, "module.registry.invalid", "", str(registry_result.message))
		return _result(errors, diagnostics)
	var registry: Dictionary = registry_result.registry
	if typeof(base.get("format", null)) != TYPE_STRING or base.get("format") != registry.get("aircraft_format"):
		_issue(errors, diagnostics, "module.source.version", "format",
			"must be exactly '%s'" % str(registry.get("aircraft_format", "")))
		return _result(errors, diagnostics)

	var modules: Array[String] = []
	var laws: Array[String] = []
	var parameters: Dictionary = {}
	var transform_reasons: Array[String] = []
	var selected_values: Dictionary = {}
	var control_transform_supported := false
	for module_variant: Variant in registry.get("always_modules", []):
		if typeof(module_variant) == TYPE_STRING:
			modules.append(module_variant)

	var capabilities_variant: Variant = base.get("capabilities", null)
	var capabilities: Dictionary = {}
	if typeof(capabilities_variant) != TYPE_DICTIONARY:
		_issue(errors, diagnostics, "module.capabilities.type", "capabilities", "must be an object")
	else:
		capabilities = capabilities_variant
	var capability_keys: Array = registry.get("capability_keys", [])
	for key_variant: Variant in capabilities.keys():
		var key := str(key_variant)
		if not capability_keys.has(key):
			_issue(errors, diagnostics, "module.capability.unknown_field", "capabilities." + key,
				"is not a registered capability field")
	var capability_registry: Dictionary = registry.get("capabilities", {})
	for key_variant: Variant in capability_keys:
		var key: String = str(key_variant)
		if not capabilities.has(key):
			_issue(errors, diagnostics, "module.capability.missing", "capabilities." + key, "is required")
			continue
		var value: Variant = capabilities[key]
		if typeof(value) != TYPE_STRING:
			_issue(errors, diagnostics, "module.capability.type", "capabilities." + key,
				"must be a string selector")
			continue
		var choices: Dictionary = capability_registry.get(key, {})
		if not choices.has(value):
			_issue(errors, diagnostics, "module.capability.unknown", "capabilities." + key,
				"has unregistered value '%s'" % value)
			continue
		var entry: Dictionary = choices[value]
		selected_values[key] = value
		parameters["capabilities." + key] = value
		var module_id: Variant = entry.get("module", null)
		if typeof(module_id) == TYPE_STRING and not module_id.is_empty():
			modules.append(module_id)
		var law_id: Variant = entry.get("law", null)
		if typeof(law_id) == TYPE_STRING and not law_id.is_empty():
			laws.append(law_id)
		for relation_variant: Variant in entry.get("presence_relations", []):
			if typeof(relation_variant) != TYPE_DICTIONARY:
				continue
			var relation: Dictionary = relation_variant
			var related_path: Variant = relation.get("path", null)
			var expected_presence: Variant = relation.get("present", null)
			if typeof(related_path) != TYPE_STRING or typeof(expected_presence) != TYPE_BOOL:
				continue
			var related_value: Dictionary = _at_path(base, related_path)
			if related_value.exists != expected_presence:
				var requirement := "present" if expected_presence else "absent"
				_issue(errors, diagnostics, "module.capability.relation", "capabilities." + key,
					"requires %s to be %s" % [related_path, requirement])
		var capability_transforms: Dictionary = entry.get("compiler_transforms", {})
		control_transform_supported = control_transform_supported or bool(capability_transforms.get("controls", false))

	var propulsion_variant: Variant = base.get("propulsion", null)
	if typeof(propulsion_variant) != TYPE_DICTIONARY:
		_issue(errors, diagnostics, "module.propulsion.type", "propulsion", "must be an object")
		return _result(errors, diagnostics)
	var propulsion: Dictionary = propulsion_variant
	var kind: Variant = propulsion.get("kind", null)
	if typeof(kind) != TYPE_STRING:
		_issue(errors, diagnostics, "module.propulsion.kind.type", "propulsion.kind", "must be a string selector")
		return _result(errors, diagnostics)
	var propulsion_registry: Dictionary = registry.get("propulsion", {})
	if not propulsion_registry.has(kind):
		_issue(errors, diagnostics, "module.propulsion.kind.unknown", "propulsion.kind",
			"has unregistered value '%s'" % kind)
		return _result(errors, diagnostics)
	var family: Dictionary = propulsion_registry[kind]

	var allowed_fields: Array = family.get("fields", [])
	for key_variant: Variant in propulsion.keys():
		var key := str(key_variant)
		if not allowed_fields.has(key):
			_issue(errors, diagnostics, "module.propulsion.unknown_field", "propulsion." + key,
				"is not registered for this propulsion family")
	for key_variant: Variant in family.get("required_fields", []):
		var key: String = str(key_variant)
		if not propulsion.has(key):
			_issue(errors, diagnostics, "module.propulsion.missing_field", "propulsion." + key,
				"is required for this propulsion family")

	var propulsion_module: Variant = family.get("module", null)
	if typeof(propulsion_module) == TYPE_STRING:
		modules.append(propulsion_module)
	parameters["propulsion.kind"] = kind
	var base_law: Variant = family.get("law", null)
	if typeof(base_law) == TYPE_STRING and not base_law.is_empty():
		laws.append(base_law)

	var allowed_capabilities: Dictionary = family.get("allowed_capabilities", {})
	for field_variant: Variant in allowed_capabilities.keys():
		var field: String = str(field_variant)
		if not selected_values.has(field):
			continue
		var allowed_values: Array = allowed_capabilities[field]
		if not allowed_values.has(selected_values[field]):
			_issue(errors, diagnostics, "module.relation.unsupported", "capabilities." + field,
				"'%s' is incompatible with propulsion family '%s'" % [selected_values[field], kind])

	var section_variants: Dictionary = family.get("section_variants", {})
	var sections: Dictionary = family.get("sections", {})
	for section_variant: Variant in sections.keys():
		var section_name: String = str(section_variant)
		if not propulsion.has(section_name):
			continue
		var section: Variant = propulsion[section_name]
		if typeof(section) != TYPE_DICTIONARY:
			_issue(errors, diagnostics, "module.section.type", "propulsion." + section_name, "must be an object")
			continue
		var section_fields: Array = sections[section_name]
		var selector_variant: Variant = section_variants.get(section_name, null)
		if typeof(selector_variant) == TYPE_DICTIONARY:
			var selector: Dictionary = selector_variant
			var selector_path: String = str(selector.get("selector_path", ""))
			var selected_field: Dictionary = _at_path(propulsion, selector_path)
			var per_value: Dictionary = selector.get("fields", {})
			var required_by_value: Dictionary = selector.get("required_fields_by_value", {})
			var selected_value: String = ""
			if not selected_field.exists:
				if bool(selector.get("selector_required", false)):
					_issue(errors, diagnostics, "module.section.selector.missing", "propulsion." + selector_path,
						"is required for this module section")
			elif typeof(selected_field.value) != TYPE_STRING:
				_issue(errors, diagnostics, "module.section.selector.type", "propulsion." + selector_path,
					"must be a string selector")
			else:
				selected_value = str(selected_field.value)
				if per_value.has(selected_value):
					section_fields = per_value[selected_value]
				elif bool(selector.get("reject_unknown_selector", false)):
					_issue(errors, diagnostics, "module.section.selector.unknown", "propulsion." + selector_path,
						"has unregistered value '%s'" % selected_value)
			var required_fields: Array = required_by_value.get(selected_value, selector.get("required_fields", []))
			for required_field_variant: Variant in required_fields:
				var required_field: String = str(required_field_variant)
				if not section.has(required_field):
					_issue(errors, diagnostics, "module.section.field.missing",
						"propulsion.%s.%s" % [section_name, required_field],
						"is required for this module section")
		for key_variant: Variant in section.keys():
			var key := str(key_variant)
			if not section_fields.has(key):
				_issue(errors, diagnostics, "module.field.unknown", "propulsion.%s.%s" % [section_name, key],
					"is not registered for this module section")

	var selected_variant: Dictionary = {}
	var family_transforms: Dictionary = family.get("compiler_transforms", {}).duplicate(true)
	if kind == "glow_prop":
		var matching: Array[Dictionary] = []
		for candidate_variant: Variant in family.get("variants", []):
			if typeof(candidate_variant) != TYPE_DICTIONARY:
				continue
			var candidate: Dictionary = candidate_variant
			var conditions_match := true
			var conditions: Dictionary = candidate.get("when", {})
			for relative_path_variant: Variant in conditions.keys():
				var relative_path: String = str(relative_path_variant)
				var actual: Dictionary = _at_path(base, "propulsion." + relative_path)
				if actual.exists != bool(conditions[relative_path]):
					conditions_match = false
					break
			if not conditions_match or selected_values.get("energy", "") != candidate.get("energy", ""):
				continue
			matching.append(candidate)
		if matching.size() != 1:
			_issue(errors, diagnostics, "module.relation.invalid", "propulsion.engine",
				"shaft, glow installation, and energy selections do not match a registered propulsion variant")
		else:
			selected_variant = matching[0]
			var variant_law: Variant = selected_variant.get("law", null)
			if typeof(variant_law) == TYPE_STRING:
				laws.append(variant_law)
				parameters["propulsion.law"] = variant_law
			for module_variant: Variant in selected_variant.get("modules", []):
				if typeof(module_variant) == TYPE_STRING:
					modules.append(module_variant)
			family_transforms = selected_variant.get("compiler_transforms", family_transforms).duplicate(true)
			var reason: Variant = selected_variant.get("compiler_reason", "")
			if typeof(reason) == TYPE_STRING and not reason.is_empty():
				transform_reasons.append(reason)
		var engine: Variant = propulsion.get("engine", {})
		if typeof(engine) == TYPE_DICTIONARY:
			if engine.has("shaft") and typeof(engine["shaft"]) != TYPE_DICTIONARY:
				_issue(errors, diagnostics, "module.field.type", "propulsion.engine.shaft", "must be an object")
			if engine.has("glow_installation") and (
				typeof(engine["glow_installation"]) != TYPE_STRING or str(engine["glow_installation"]).is_empty()
			):
				_issue(errors, diagnostics, "module.field.type", "propulsion.engine.glow_installation",
					"must be a non-empty resource path")
	elif kind == "electric_prop":
		var battery_variant: Variant = propulsion.get("battery", null)
		if typeof(battery_variant) != TYPE_DICTIONARY:
			_issue(errors, diagnostics, "module.section.type", "propulsion.battery", "must be an object")
		else:
			var battery: Dictionary = battery_variant
			var battery_kind: Variant = battery.get("kind", null)
			if typeof(battery_kind) != TYPE_STRING:
				_issue(errors, diagnostics, "module.battery.kind.type", "propulsion.battery.kind",
					"must be a string selector")
			else:
				var battery_laws: Dictionary = family.get("battery_laws", {})
				if not battery_laws.has(battery_kind):
					_issue(errors, diagnostics, "module.battery.kind.unknown", "propulsion.battery.kind",
						"has unregistered value '%s'" % battery_kind)
				else:
					laws.append(battery_laws[battery_kind])
					parameters["propulsion.battery.kind"] = battery_kind
				if selected_values.has("energy") and selected_values["energy"] != battery_kind:
					_issue(errors, diagnostics, "module.relation.battery_energy", "capabilities.energy",
						"must match propulsion.battery.kind")
	elif kind == "turbine":
		var engine_variant: Variant = propulsion.get("engine", {})
		var engine: Dictionary = engine_variant if typeof(engine_variant) == TYPE_DICTIONARY else {}
		var integrator_path: String = str(family.get("integrator_path", "engine.spool_integrator"))
		var relative_integrator_path: String = integrator_path.trim_prefix("engine.")
		var integrator: Variant = engine.get(relative_integrator_path, family.get("integrator_default", "sampled"))
		if typeof(integrator) != TYPE_STRING:
			_issue(errors, diagnostics, "module.turbine.integrator.type", "propulsion." + integrator_path,
				"must be a string selector")
		else:
			var integrator_laws: Dictionary = family.get("integrator_laws", {})
			if not integrator_laws.has(integrator):
				_issue(errors, diagnostics, "module.turbine.integrator.unknown", "propulsion." + integrator_path,
					"has unregistered value '%s'" % integrator)
			else:
				laws.append(integrator_laws[integrator])
				parameters["propulsion." + integrator_path] = integrator

	var family_reason: Variant = family.get("compiler_family_transform_reason", "")
	if typeof(family_reason) == TYPE_STRING and not family_reason.is_empty() and not _all_transforms_enabled(family_transforms):
		transform_reasons.insert(0, family_reason.replace("{kind}", kind))

	for conditional_variant: Variant in registry.get("conditional_laws", []):
		if typeof(conditional_variant) != TYPE_DICTIONARY:
			continue
		var conditional: Dictionary = conditional_variant
		if conditional.get("family") != kind:
			continue
		var conditional_path: String = str(conditional.get("path", ""))
		var conditional_value: Dictionary = _at_path(base, "propulsion." + conditional_path)
		if not conditional_value.exists:
			continue
		var law: Variant = conditional.get("law", null)
		if typeof(law) == TYPE_STRING:
			laws.append(law)
		var conditional_reason: Variant = conditional.get("compiler_transform_reason", "")
		if typeof(conditional_reason) == TYPE_STRING and not conditional_reason.is_empty():
			transform_reasons.append(conditional_reason)
		var overrides: Dictionary = conditional.get("compiler_transforms", {})
		for key: String in ["scale", "weight", "power"]:
			if overrides.has(key):
				family_transforms[key] = bool(family_transforms.get(key, false)) and bool(overrides[key])

	for optional_value: Variant in registry.get("optional_modules", []):
		var definition: Dictionary = optional_value
		var path: String = definition.path
		var found := _at_path(base, path)
		if not found.exists: continue
		if typeof(found.value) != TYPE_DICTIONARY or found.value.get("format") != definition.format:
			_issue(errors, diagnostics, "module.optional.format", path, "unsupported optional module format")
			continue
		var selector: String = definition.selector
		var selected: Variant = found.value.get(selector)
		var choices: Dictionary = definition.choices
		if typeof(selected) != TYPE_STRING or not choices.has(selected):
			_issue(errors, diagnostics, "module.optional.selector", path + "." + selector, "unsupported optional module law")
			continue
		var choice: Dictionary = choices[selected]
		for required_path: String in choice.get("required_paths", []):
			if not _at_path(base, required_path).exists:
				_issue(errors, diagnostics, "module.optional.relation", path, "requires " + required_path)
		for capability: String in choice.get("allowed_capabilities", {}):
			if not choice.allowed_capabilities[capability].has(capabilities.get(capability)):
				_issue(errors, diagnostics, "module.optional.capability", path, "incompatible capability: " + capability)
		modules.append(choice.module)
		parameters[path + "." + selector] = selected
		for replaced: String in choice.get("replaces_laws", []): laws.erase(replaced)
		if choice.has("law"): laws.append(choice.law)
		var overrides: Dictionary = choice.get("compiler_transforms", {})
		for key: String in ["scale", "weight", "power"]:
			if overrides.has(key): family_transforms[key] = bool(family_transforms.get(key, false)) and bool(overrides[key])
		if overrides.has("controls"): control_transform_supported = control_transform_supported and bool(overrides.controls)
		if choice.has("compiler_transform_reason"): transform_reasons.append(choice.compiler_transform_reason)

	if not errors.is_empty():
		return _result(errors, diagnostics)
	var transform_result := {
		"scale": bool(family_transforms.get("scale", false)),
		"weight": bool(family_transforms.get("weight", false)),
		"power": bool(family_transforms.get("power", false)),
		"controls": control_transform_supported,
	}
	return _result(errors, diagnostics, modules, laws, parameters, transform_result, transform_reasons)


static func _load_registry() -> Dictionary:
	var file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "could not open %s" % REGISTRY_PATH}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("format") != REGISTRY_FORMAT:
		return {"ok": false, "message": "registry format must be exactly '%s'" % REGISTRY_FORMAT}
	return {"ok": true, "registry": parsed}


static func _at_path(root: Variant, path: String) -> Dictionary:
	var current: Variant = root
	for part: String in path.split(".", false):
		if typeof(current) != TYPE_DICTIONARY or not current.has(part):
			return {"exists": false, "value": null}
		current = current[part]
	return {"exists": true, "value": current}


static func _all_transforms_enabled(transforms: Dictionary) -> bool:
	for key: String in ["scale", "weight", "power"]:
		if not bool(transforms.get(key, false)):
			return false
	return true


static func _issue(errors: PackedStringArray, diagnostics: Array[Dictionary], code: String, path: String,
		message: String) -> void:
	diagnostics.append({"code": code, "path": path, "message": message})
	errors.append("%s: %s" % [path, message] if not path.is_empty() else message)


static func _result(errors: PackedStringArray, diagnostics: Array[Dictionary], modules: Array[String] = [],
		laws: Array[String] = [], parameters: Dictionary = {}, transforms: Dictionary = {},
		reasons: Array[String] = []) -> Dictionary:
	if not errors.is_empty():
		return {
			"ok": false,
			"errors": errors,
			"diagnostics": diagnostics,
			"modules": [],
			"laws": [],
			"parameters": {},
			"compiler_transforms": {"scale": false, "weight": false, "power": false, "controls": false},
			"compiler_transform_reasons": [],
		}
	var sorted_modules := _sorted_unique(modules)
	var sorted_laws := _sorted_unique(laws)
	return {
		"ok": true,
		"errors": errors,
		"diagnostics": diagnostics,
		"modules": sorted_modules,
		"laws": sorted_laws,
		"parameters": parameters,
		"compiler_transforms": transforms,
		"compiler_transform_reasons": reasons,
	}


static func _sorted_unique(values: Array[String]) -> Array[String]:
	var seen: Dictionary = {}
	for value: String in values:
		seen[value] = true
	var result: Array[String] = []
	for value_variant: Variant in seen.keys():
		result.append(str(value_variant))
	result.sort()
	return result
