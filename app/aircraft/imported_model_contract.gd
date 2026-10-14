extends RefCounted

const Retraction := preload("res://aircraft/retractable_model.gd")

const GEAR_ROLES := ["left", "right", "tail", "steering", "nose"]
const AXES := ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]


static func validate(construction: Variant, bindings: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var diagnostics: Array[Dictionary] = []
	if typeof(construction) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_CONSTRUCTION_INVALID", "$.construction", "construction must be an object")
		return _result(errors, diagnostics)
	if not _check_fields(construction, ["version", "hinge_axis", "rotor", "gear", "material_grow"], "$.construction", errors, diagnostics, ["retraction"]):
		return _result(errors, diagnostics)

	var version: Variant = construction.get("version")
	if not _is_finite_number(version) or float(version) != 1.0:
		_fail(errors, diagnostics, "MODEL_CONSTRUCTION_VERSION_UNSUPPORTED", "$.construction.version", "construction version must be numeric 1")
	if construction.get("hinge_axis") != "+X":
		_fail(errors, diagnostics, "MODEL_CONSTRUCTION_HINGE_AXIS_INVALID", "$.construction.hinge_axis", "hinge_axis must be +X")

	var rotor_binding: Variant = bindings.get("rotor", {})
	var rotor_present := false
	if typeof(rotor_binding) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_CONSTRUCTION_BINDINGS_INVALID", "$.bindings.rotor", "rotor binding must be an object")
	else:
		if typeof(rotor_binding.get("present")) != TYPE_BOOL:
			_fail(errors, diagnostics, "MODEL_CONSTRUCTION_BINDINGS_INVALID", "$.bindings.rotor.present", "rotor presence must be boolean")
		else:
			rotor_present = bool(rotor_binding.get("present"))
	var rotor: Variant = construction.get("rotor", {})
	if typeof(rotor) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_CONSTRUCTION_ROTOR_INVALID", "$.construction.rotor", "rotor must be an object")
	elif not rotor_present:
		if not rotor.is_empty():
			_fail(errors, diagnostics, "MODEL_CONSTRUCTION_ROTOR_INVALID", "$.construction.rotor", "absent rotor construction must be an empty object")
	else:
		if _check_fields(rotor, ["frame_node", "geometry_ref", "axis"], "$.construction.rotor", errors, diagnostics):
			if not _is_node_name(rotor.get("frame_node")):
				_fail(errors, diagnostics, "MODEL_CONSTRUCTION_NODE_INVALID", "$.construction.rotor.frame_node", "frame_node must be a safe node name")
			if not _dotted_ref(rotor.get("geometry_ref")):
				_fail(errors, diagnostics, "MODEL_CONSTRUCTION_REF_INVALID", "$.construction.rotor.geometry_ref", "geometry_ref must be a dotted source reference")
			if typeof(rotor.get("axis")) != TYPE_STRING or not AXES.has(rotor.get("axis")):
				_fail(errors, diagnostics, "MODEL_CONSTRUCTION_AXIS_INVALID", "$.construction.rotor.axis", "rotor axis must be a signed X, Y or Z axis")

	var controls: Variant = bindings.get("controls", {})
	var gear_bindings: Variant = bindings.get("gear", {})
	var expected_roles: Dictionary = {}
	if typeof(gear_bindings) != TYPE_DICTIONARY or typeof(gear_bindings.get("keys", {})) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_CONSTRUCTION_BINDINGS_INVALID", "$.bindings.gear.keys", "gear keys must be an object")
	else:
		for role_variant in gear_bindings.get("keys", {}).keys():
			expected_roles[str(role_variant)] = true

	var used_names: Dictionary = {}
	if construction.has("retraction"):
		var retract: Variant = construction.retraction
		if _check_fields(retract, ["geometry_ref"], "$.construction.retraction", errors, diagnostics) and not _dotted_ref(retract.get("geometry_ref")):
			_fail(errors, diagnostics, "MODEL_CONSTRUCTION_REF_INVALID", "$.construction.retraction", "retraction needs a dotted geometry reference")
		if expected_roles.size() != 4 or not expected_roles.has_all(["left", "right", "nose", "steering"]) or construction.get("gear") != []:
			_fail(errors, diagnostics, "MODEL_CONSTRUCTION_GEAR_INVALID", "$.construction.retraction", "retraction needs left/right/nose/steering bindings and no static gear wrappers")
		expected_roles = {}
	_claim_name("propeller", "$.construction.generated.propeller", used_names, errors, diagnostics)
	_claim_name("propeller_mount", "$.construction.generated.propeller_mount", used_names, errors, diagnostics)
	_claim_control_names(controls, used_names, errors, diagnostics)
	if typeof(controls) == TYPE_DICTIONARY:
		for role_variant in controls.keys():
			var control: Variant = controls[role_variant]
			if typeof(control) != TYPE_DICTIONARY or typeof(control.get("hinges", [])) != TYPE_ARRAY:
				continue
			for index in control.get("hinges", []).size():
				var hinge: Variant = control.get("hinges", [])[index]
				if typeof(hinge) == TYPE_DICTIONARY and hinge.get("source") != "geometry_articulation":
					_fail(errors, diagnostics, "MODEL_CONSTRUCTION_CONTROL_SOURCE_INVALID", "$.bindings.controls.%s.hinges[%d].source" % [str(role_variant), index], "shared imported construction requires geometry_articulation controls")
	if typeof(rotor_binding) == TYPE_DICTIONARY:
		var public_node: Variant = rotor_binding.get("node", "")
		if public_node != "propeller": _claim_name(public_node, "$.bindings.rotor.node", used_names, errors, diagnostics)
		var spin_node: Variant = rotor_binding.get("spin_node", "")
		if not str(spin_node).is_empty(): _claim_name(spin_node, "$.bindings.rotor.spin_node", used_names, errors, diagnostics)
	if typeof(rotor) == TYPE_DICTIONARY and rotor_present:
		_claim_name(rotor.get("frame_node", ""), "$.construction.rotor.frame_node", used_names, errors, diagnostics)

	var gear: Variant = construction.get("gear", [])
	var seen_roles: Dictionary = {}
	if typeof(gear) != TYPE_ARRAY:
		_fail(errors, diagnostics, "MODEL_CONSTRUCTION_GEAR_INVALID", "$.construction.gear", "gear must be an array")
	else:
		for index in gear.size():
			var path := "$.construction.gear[%d]" % index
			var entry: Variant = gear[index]
			if not _check_fields(entry, ["role", "node", "geometry_ref", "wrapper"], path, errors, diagnostics):
				continue
			var role_variant: Variant = entry.get("role")
			var role := str(role_variant)
			if typeof(role_variant) != TYPE_STRING or not GEAR_ROLES.has(role):
				_fail(errors, diagnostics, "MODEL_CONSTRUCTION_GEAR_ROLE_INVALID", path + ".role", "gear role is unsupported")
			if seen_roles.has(role):
				_fail(errors, diagnostics, "MODEL_CONSTRUCTION_GEAR_ROLE_DUPLICATE", path + ".role", "each gear role may be declared once")
			seen_roles[role] = true
			if not expected_roles.has(role):
				_fail(errors, diagnostics, "MODEL_CONSTRUCTION_GEAR_ROLE_MISMATCH", path + ".role", "construction gear role is not declared by bindings.gear.keys")
			if not _is_node_name(entry.get("node")):
				_fail(errors, diagnostics, "MODEL_CONSTRUCTION_NODE_INVALID", path + ".node", "gear node must be a safe node name")
			if not _dotted_ref(entry.get("geometry_ref")):
				_fail(errors, diagnostics, "MODEL_CONSTRUCTION_REF_INVALID", path + ".geometry_ref", "geometry_ref must be a dotted source reference")
			if not _is_node_name(entry.get("wrapper")):
				_fail(errors, diagnostics, "MODEL_CONSTRUCTION_WRAPPER_INVALID", path + ".wrapper", "wrapper must be a safe node name")
			_claim_name(entry.get("node", ""), path + ".node", used_names, errors, diagnostics)
			_claim_name(entry.get("wrapper", ""), path + ".wrapper", used_names, errors, diagnostics)
			if _is_node_name(entry.get("wrapper")):
				_claim_name(str(entry.wrapper) + "_mount", path + ".wrapper_mount", used_names, errors, diagnostics)
		for expected_role in expected_roles.keys():
			if not seen_roles.has(expected_role):
				_fail(errors, diagnostics, "MODEL_CONSTRUCTION_GEAR_ROLE_MISSING", "$.construction.gear", "construction must declare gear role %s" % expected_role)

	var material_grow: Variant = construction.get("material_grow", [])
	var seen_material_pairs: Dictionary = {}
	if typeof(material_grow) != TYPE_ARRAY:
		_fail(errors, diagnostics, "MODEL_CONSTRUCTION_MATERIAL_GROW_INVALID", "$.construction.material_grow", "material_grow must be an array")
	else:
		for index in material_grow.size():
			var path := "$.construction.material_grow[%d]" % index
			var entry: Variant = material_grow[index]
			if not _check_fields(entry, ["node", "materials", "amount_m"], path, errors, diagnostics):
				continue
			if not _is_node_name(entry.get("node")):
				_fail(errors, diagnostics, "MODEL_CONSTRUCTION_NODE_INVALID", path + ".node", "material node must be a safe node name")
			var materials: Variant = entry.get("materials")
			if typeof(materials) != TYPE_ARRAY or materials.is_empty():
				_fail(errors, diagnostics, "MODEL_CONSTRUCTION_MATERIALS_INVALID", path + ".materials", "materials must be a non-empty array")
			else:
				var seen_in_entry: Dictionary = {}
				for material_index in materials.size():
					var material: Variant = materials[material_index]
					if typeof(material) != TYPE_STRING or str(material).strip_edges().is_empty():
						_fail(errors, diagnostics, "MODEL_CONSTRUCTION_MATERIALS_INVALID", "%s.materials[%d]" % [path, material_index], "material names must be non-empty strings")
						continue
					if seen_in_entry.has(material):
						_fail(errors, diagnostics, "MODEL_CONSTRUCTION_MATERIAL_DUPLICATE", "%s.materials[%d]" % [path, material_index], "material name repeats for this node")
					seen_in_entry[material] = true
					var pair := str(entry.get("node", "")) + "\u001f" + str(material)
					if seen_material_pairs.has(pair):
						_fail(errors, diagnostics, "MODEL_CONSTRUCTION_MATERIAL_DUPLICATE", "%s.materials[%d]" % [path, material_index], "node/material pair may be declared only once")
					seen_material_pairs[pair] = true
			var amount: Variant = entry.get("amount_m")
			if not _is_finite_number(amount) or float(amount) <= 0.0 or float(amount) > 0.01:
				_fail(errors, diagnostics, "MODEL_CONSTRUCTION_GROW_INVALID", path + ".amount_m", "amount_m must be finite and greater than 0 and at most 0.01 m")

	return _result(errors, diagnostics)


static func validate_geometry(geometry: Variant, construction: Dictionary, bindings: Dictionary) -> Dictionary:
	var schema_result: Dictionary = validate(construction, bindings)
	var errors: PackedStringArray = schema_result.errors.duplicate()
	var diagnostics: Array[Dictionary] = schema_result.diagnostics.duplicate(true)
	if not schema_result.ok:
		return _result(errors, diagnostics)
	if typeof(geometry) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_GEOMETRY_SOURCE_INVALID", "$.geometry", "geometry data must be an object")
		return _result(errors, diagnostics)
	if construction.has("retraction"):
		var rig: Variant = _resolve_ref(geometry, construction.retraction.geometry_ref, "$.construction.retraction.geometry_ref", errors, diagnostics)
		for message in Retraction.validate(rig):
			_fail(errors, diagnostics, "MODEL_RETRACTION_INVALID", "$.construction.retraction.geometry_ref", message)

	var controls: Variant = bindings.get("controls", {})
	if typeof(controls) == TYPE_DICTIONARY:
		for role_variant in controls.keys():
			var role := str(role_variant)
			var control: Variant = controls[role_variant]
			if typeof(control) != TYPE_DICTIONARY or typeof(control.get("hinges", [])) != TYPE_ARRAY:
				continue
			for index in control.get("hinges", []).size():
				var hinge: Variant = control.get("hinges", [])[index]
				if typeof(hinge) != TYPE_DICTIONARY or hinge.get("source") != "geometry_articulation":
					continue
				var path := "$.bindings.controls.%s.hinges[%d]" % [role, index]
				var articulation: Variant = _resolve_ref(geometry, str(hinge.get("geometry_ref", "")), path + ".geometry_ref", errors, diagnostics)
				_check_control_articulation(articulation, str(hinge.get("node", "")), path, errors, diagnostics)

	var rotor_binding: Variant = bindings.get("rotor", {})
	var rotor_construction: Variant = construction.get("rotor", {})
	if typeof(rotor_binding) == TYPE_DICTIONARY and bool(rotor_binding.get("present", false)):
		if typeof(rotor_construction) == TYPE_DICTIONARY:
			var thrust: Variant = _resolve_ref(geometry, str(rotor_construction.get("geometry_ref", "")), "$.construction.rotor.geometry_ref", errors, diagnostics)
			if typeof(thrust) != TYPE_DICTIONARY:
				_fail(errors, diagnostics, "MODEL_GEOMETRY_REF_OBJECT_INVALID", "$.construction.rotor.geometry_ref", "rotor reference must resolve to an object")
			else:
				if thrust.get("node") != rotor_construction.get("frame_node"):
					_fail(errors, diagnostics, "MODEL_GEOMETRY_NODE_MISMATCH", "$.construction.rotor.frame_node", "declared frame node does not match the referenced geometry node")
				if thrust.get("spin_node") != rotor_binding.get("spin_node"):
					_fail(errors, diagnostics, "MODEL_GEOMETRY_SPIN_NODE_MISMATCH", "$.bindings.rotor.spin_node", "rotor spin_node does not match the referenced thrust frame")
		var rotor_ref: String = str(rotor_binding.get("geometry_ref", ""))
		if rotor_binding.get("source") == "geometry_articulation":
			var spin_articulation: Variant = _resolve_ref(geometry, rotor_ref, "$.bindings.rotor.geometry_ref", errors, diagnostics)
			_check_rotor_articulation(spin_articulation, str(rotor_binding.get("spin_node", "")), errors, diagnostics)

	var gear: Variant = construction.get("gear", [])
	if typeof(gear) == TYPE_ARRAY:
		for index in gear.size():
			var entry: Variant = gear[index]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var path := "$.construction.gear[%d]" % index
			var articulation: Variant = _resolve_ref(geometry, str(entry.get("geometry_ref", "")), path + ".geometry_ref", errors, diagnostics)
			if typeof(articulation) != TYPE_DICTIONARY:
				_fail(errors, diagnostics, "MODEL_GEOMETRY_REF_OBJECT_INVALID", path + ".geometry_ref", "gear reference must resolve to an object")
			elif articulation.get("node") != entry.get("node"):
				_fail(errors, diagnostics, "MODEL_GEOMETRY_NODE_MISMATCH", path + ".node", "declared gear node does not match the referenced geometry node")

	return _result(errors, diagnostics)


static func _check_control_articulation(value: Variant, node_name: String, path: String, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_GEOMETRY_REF_OBJECT_INVALID", path + ".geometry_ref", "control reference must resolve to an articulation object")
		return
	if value.get("node") != node_name:
		_fail(errors, diagnostics, "MODEL_GEOMETRY_NODE_MISMATCH", path + ".node", "declared control node does not match the referenced articulation node")
	if typeof(value.get("positive")) != TYPE_STRING or str(value.get("positive", "")).strip_edges().is_empty():
		_fail(errors, diagnostics, "MODEL_GEOMETRY_ARTICULATION_INVALID", path + ".geometry_ref", "control articulation needs a declared positive direction")
	var travel: Variant = value.get("range_deg")
	if typeof(travel) != TYPE_ARRAY or travel.size() != 2 or not _is_finite_number(travel[0]) or not _is_finite_number(travel[1]):
		_fail(errors, diagnostics, "MODEL_GEOMETRY_ARTICULATION_INVALID", path + ".geometry_ref", "control articulation needs a finite rest-to-travel range")
	elif float(travel[0]) >= float(travel[1]):
		_fail(errors, diagnostics, "MODEL_GEOMETRY_ARTICULATION_INVALID", path + ".geometry_ref", "control articulation range must be increasing")
	var sign: Variant = value.get("app_sign")
	if not _is_finite_number(sign) or absf(float(sign)) != 1.0:
		_fail(errors, diagnostics, "MODEL_GEOMETRY_ARTICULATION_INVALID", path + ".geometry_ref", "control articulation needs a signed presentation conversion")


static func _check_rotor_articulation(value: Variant, node_name: String, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_GEOMETRY_REF_OBJECT_INVALID", "$.bindings.rotor.geometry_ref", "rotor reference must resolve to an articulation object")
		return
	if value.get("node") != node_name:
		_fail(errors, diagnostics, "MODEL_GEOMETRY_NODE_MISMATCH", "$.bindings.rotor.spin_node", "rotor spin node does not match the referenced articulation node")
	if typeof(value.get("positive")) != TYPE_STRING or str(value.get("positive", "")).strip_edges().is_empty():
		_fail(errors, diagnostics, "MODEL_GEOMETRY_ARTICULATION_INVALID", "$.bindings.rotor.geometry_ref", "rotor articulation needs a declared positive rotation sense")


static func _resolve_ref(data: Dictionary, reference: String, path: String, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> Variant:
	if not _dotted_ref(reference):
		_fail(errors, diagnostics, "MODEL_CONSTRUCTION_REF_INVALID", path, "reference must be a dotted source reference")
		return null
	var current: Variant = data
	for segment in reference.split(".", true):
		if typeof(current) != TYPE_DICTIONARY or not current.has(segment):
			_fail(errors, diagnostics, "MODEL_GEOMETRY_REF_MISSING", path, "source reference does not resolve: %s" % reference)
			return null
		current = current[segment]
	return current


static func _claim_control_names(controls: Variant, used_names: Dictionary, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	if typeof(controls) != TYPE_DICTIONARY:
		return
	for role_variant in controls.keys():
		var control: Variant = controls[role_variant]
		if typeof(control) != TYPE_DICTIONARY or typeof(control.get("hinges", [])) != TYPE_ARRAY:
			continue
		for index in control.get("hinges", []).size():
			var hinge: Variant = control.get("hinges", [])[index]
			if typeof(hinge) != TYPE_DICTIONARY:
				continue
			_claim_name(hinge.get("node", ""), "$.bindings.controls.%s.hinges[%d].node" % [str(role_variant), index], used_names, errors, diagnostics)


static func _claim_name(value: Variant, path: String, used_names: Dictionary, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	if not _is_node_name(value):
		if not str(value).is_empty():
			_fail(errors, diagnostics, "MODEL_CONSTRUCTION_NODE_INVALID", path, "node name is not safe")
		return
	var node_name := str(value)
	if used_names.has(node_name):
		_fail(errors, diagnostics, "MODEL_CONSTRUCTION_NODE_COLLISION", path, "node name collides with %s" % used_names[node_name])
	else:
		used_names[node_name] = path


static func _check_fields(value: Variant, fields: Array, path: String, errors: PackedStringArray, diagnostics: Array[Dictionary], optional: Array = []) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_CONSTRUCTION_OBJECT_INVALID", path, "expected object")
		return false
	var object: Dictionary = value
	for field in fields:
		if not object.has(field):
			_fail(errors, diagnostics, "MODEL_CONSTRUCTION_FIELD_MISSING", path + "." + field, "required field is missing")
	for field_variant in object.keys():
		var field := str(field_variant)
		if not fields.has(field) and not optional.has(field):
			_fail(errors, diagnostics, "MODEL_CONSTRUCTION_FIELD_UNKNOWN", path + "." + field, "unknown field is not supported")
	return true


static func _is_node_name(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or str(value).is_empty():
		return false
	for character in str(value):
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".contains(character):
			return false
	return true


static func _dotted_ref(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or str(value).is_empty() or str(value).contains("/") or str(value).contains("\\"):
		return false
	for part in str(value).split(".", true):
		if part.is_empty():
			return false
		for character in part:
			if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".contains(character):
				return false
	return true


static func _is_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _fail(errors: PackedStringArray, diagnostics: Array[Dictionary], code: String, path: String, message: String) -> void:
	errors.append("%s: %s" % [path, message])
	diagnostics.append({"code": code, "path": path, "message": message})


static func _result(errors: PackedStringArray, diagnostics: Array[Dictionary]) -> Dictionary:
	return {"ok": errors.is_empty(), "errors": errors, "diagnostics": diagnostics}
