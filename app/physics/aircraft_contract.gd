extends RefCounted
class_name AircraftContract

const SPEC_PATH := "res://data/schema/aircraft-contract-v2.json"
const PhysicalIdentity := preload("res://physics/physical_identity.gd")
const EVIDENCE_FIELDS := ["value", "unit", "kind", "source"]
const EVIDENCE_KINDS := ["manual", "measured", "borrowed", "estimated", "derived"]
static var _spec_cache: Dictionary = {}
static var _path_class_cache: Dictionary = {}

static func validate(raw: Variant) -> PackedStringArray:
	var issues := PackedStringArray()
	var spec := _load_spec()
	if spec.is_empty():
		issues.append("Aircraft v2 contract: cannot read %s" % SPEC_PATH)
		return issues
	if not raw is Dictionary:
		issues.append("/: root must be an object")
		return issues
	var root: Dictionary = raw
	_visit(root, PackedStringArray(), spec, root, issues)
	if not issues.is_empty():
		return issues
	_validate_relations(root, spec, issues)
	issues.append_array(PhysicalIdentity.validate(root))
	return issues

static func _load_spec() -> Dictionary:
	if not _spec_cache.is_empty():
		return _spec_cache
	if not FileAccess.file_exists(SPEC_PATH):
		return {}
	var file := FileAccess.open(SPEC_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_spec_cache = parsed
	return _spec_cache

static func _visit(value: Variant, parts: PackedStringArray, spec: Dictionary, root: Dictionary, issues: PackedStringArray) -> void:
	var path := _path_for(parts)
	if value == null:
		_issue(issues, path, "null values are not supported")
		return

	var classification := _classify_path(path, spec)
	if classification["enum_path"]:
		var allowed: Array = classification["enum_values"]
		if not allowed.has(value):
			_issue(issues, path, "must be one of %s" % str(allowed))
			return
		return
	if classification["string_path"]:
		if not value is String:
			_issue(issues, path, "must be a string")
			return
		if classification["string_nonempty"] and String(value).strip_edges().is_empty():
			_issue(issues, path, "must not be empty")
		return
	if classification["literal_path"]:
		var literal: Variant = classification["literal_value"]
		if value != literal:
			_issue(issues, path, "must equal %s" % str(literal))
		return

	if value is Dictionary:
		var object_rules: Array = classification["object_rules"]
		if not object_rules.is_empty():
			var rule := _select_object_rule(object_rules, root)
			if rule.is_empty():
				_issue(issues, path, "has no supported object branch for its selector")
				return
			var prior_issue_count := issues.size()
			_validate_object_shape(value, path, rule, issues)
			if issues.size() > prior_issue_count:
				return
			for key in value.keys():
				var child_parts := parts.duplicate()
				child_parts.append(String(key))
				_visit(value[key], child_parts, spec, root, issues)
			return
		if classification["quantity_path"]:
			_validate_quantity(value, path, issues)
			return
		_issue(issues, path, "object is not declared by the v2 contract")
		return

	if value is Array:
		var array_rule: Dictionary = classification["array_rule"]
		if array_rule.is_empty():
			_issue(issues, path, "array is not declared by the v2 contract")
			return
		var minimum := int(array_rule.get("min_items", 0))
		if value.size() < minimum:
			_issue(issues, path, "must contain at least %d item(s)" % minimum)
		for index in value.size():
			var child_parts := parts.duplicate()
			child_parts.append(str(index))
			_visit(value[index], child_parts, spec, root, issues)
		return

	# Wrong primitive types at object, array or quantity paths need a useful
	# structural error here instead of relying only on the offline schema.
	if not classification["object_rules"].is_empty():
		_issue(issues, path, "must be an object")
	elif not classification["array_rule"].is_empty():
		_issue(issues, path, "must be an array")
	elif classification["quantity_path"]:
		_issue(issues, path, "must be a quantity object")

static func _validate_object_shape(value: Dictionary, path: String, rule: Dictionary, issues: PackedStringArray) -> void:
	var allowed: Array = rule.get("allowed", [])
	var required: Array = rule.get("required", [])
	for key in required:
		if not value.has(key):
			_issue(issues, path, "missing required field '%s'" % str(key))
	for key in value.keys():
		if not allowed.has(key):
			_issue(issues, _append_path(path, String(key)), "unknown field")

static func _validate_quantity(value: Dictionary, path: String, issues: PackedStringArray) -> void:
	for key in EVIDENCE_FIELDS:
		if not value.has(key):
			_issue(issues, path, "quantity is missing '%s'" % key)
	for key in value.keys():
		if not EVIDENCE_FIELDS.has(key):
			_issue(issues, _append_path(path, String(key)), "unknown quantity field")
	if value.has("value") and value["value"] == null:
		_issue(issues, _append_path(path, "value"), "null quantity values are not supported")
	if value.has("unit") and (not value["unit"] is String or String(value["unit"]).strip_edges().is_empty()):
		_issue(issues, _append_path(path, "unit"), "must be a nonempty string")
	if value.has("source") and (not value["source"] is String or String(value["source"]).strip_edges().is_empty()):
		_issue(issues, _append_path(path, "source"), "must be a nonempty string")
	if value.has("kind") and (not value["kind"] is String or not EVIDENCE_KINDS.has(value["kind"])):
		_issue(issues, _append_path(path, "kind"), "must be a supported evidence kind")

# Coupled invariants: capability/propulsion compatibility, gear presence and
# deployed support/steering topology, positive inertia references, and mutually exclusive
# legacy/smooth slipstream fields. Numeric ranges remain with AircraftData.
static func _validate_relations(root: Dictionary, spec: Dictionary, issues: PackedStringArray) -> void:
	var capabilities: Variant = root.get("capabilities", {})
	var propulsion: Variant = root.get("propulsion", {})
	if not capabilities is Dictionary or not propulsion is Dictionary:
		return
	var gear_kind := String(capabilities.get("gear", ""))
	var propulsion_kind := String(propulsion.get("kind", ""))
	var layout_expected := "single_centerline_jet" if propulsion_kind == "turbine" else "single_tractor"
	if capabilities.get("propulsion_layout", "") != layout_expected:
		_issue(issues, "/capabilities/propulsion_layout", "does not match propulsion.kind")
	var energy_expected := "prescribed_fuel"
	if propulsion_kind == "glow_prop" and propulsion.get("engine", {}).has("glow_installation"):
		energy_expected = "finite_glow_fuel"
		if propulsion.engine.has("shaft"):
			_issue(issues, "/propulsion/engine", "glow_installation and legacy shaft are mutually exclusive")
	if propulsion_kind == "electric_prop":
		var battery: Variant = propulsion.get("battery", {})
		if battery is Dictionary:
			energy_expected = String(battery.get("kind", ""))
	if capabilities.get("energy", "") != energy_expected:
		_issue(issues, "/capabilities/energy", "does not match the propulsion energy model")
	if propulsion_kind == "turbine" and energy_expected != "prescribed_fuel":
		_issue(issues, "/capabilities/energy", "turbines require prescribed_fuel")

	_validate_gear_relations(root, gear_kind, issues)

	_validate_inertia_reference(root, issues)
	_validate_slipstream_relations(propulsion, issues)

static func _validate_gear_relations(root: Dictionary, gear_kind: String, issues: PackedStringArray) -> void:
	var has_gear := root.has("landing_gear")
	if gear_kind == "locked_up":
		if has_gear:
			_issue(issues, "/landing_gear", "must be absent when capabilities.gear is locked_up")
		return
	if not has_gear:
		_issue(issues, "/landing_gear", "is required for the declared gear capability")
		return
	var gear: Variant = root.get("landing_gear")
	if not gear is Dictionary:
		return
	var contacts: Variant = gear.get("contacts", [])
	if not contacts is Array:
		return
	var balance: Variant = root.get("balance", {})
	if not balance is Dictionary:
		return
	var plan_cg: Variant = balance.get("plan_cg", {})
	if not plan_cg is Dictionary or not plan_cg.get("value", null) is Array:
		return
	var cg_value: Array = plan_cg["value"]
	if cg_value.is_empty() or not _is_number(cg_value[0]):
		return
	var cg_x := float(cg_value[0])
	var names := {}
	var ahead_count := 0
	var aft_count := 0
	for index in contacts.size():
		var contact: Variant = contacts[index]
		if not contact is Dictionary:
			continue
		var name_value: Variant = contact.get("name", null)
		if name_value is String:
			var contact_name := String(name_value).strip_edges()
			if names.has(contact_name):
				_issue(issues, "/landing_gear/contacts/%d/name" % index, "contact names must be unique")
			names[contact_name] = true
		var steering: Variant = contact.get("max_steering", {})
		var position: Variant = contact.get("position", {})
		if not steering is Dictionary or not position is Dictionary:
			continue
		var steering_value: Variant = steering.get("value", null)
		var position_value: Variant = position.get("value", null)
		if not _is_number(steering_value) or not position_value is Array or position_value.is_empty() or not _is_number(position_value[0]):
			continue
		var steering_angle := float(steering_value)
		var contact_x := float(position_value[0])
		if contact_x < cg_x:
			ahead_count += 1
		elif contact_x > cg_x:
			aft_count += 1
		if absf(steering_angle) <= 0.000001:
			continue
		if gear_kind == "fixed_tricycle":
			if contact_x >= cg_x or steering_angle <= 0.0:
				_issue(issues, "/landing_gear/contacts/%d" % index, "fixed_tricycle steering contact must be ahead of plan CG with positive steering")
		else:
			if contact_x <= cg_x or steering_angle >= 0.0:
				_issue(issues, "/landing_gear/contacts/%d" % index, "taildragger steering contact must be aft of plan CG with negative steering")
	if gear_kind == "fixed_tricycle":
		if ahead_count < 1 or aft_count < 2:
			_issue(issues, "/landing_gear/contacts", "fixed_tricycle requires at least one contact ahead and two aft of plan CG")
	else:
		if ahead_count < 2 or aft_count < 1:
			_issue(issues, "/landing_gear/contacts", "taildragger requires at least two contacts ahead and one aft of plan CG")

static func _validate_inertia_reference(root: Dictionary, issues: PackedStringArray) -> void:
	var plausibility: Variant = root.get("plausibility", {})
	if not plausibility is Dictionary:
		return
	var inertia: Variant = plausibility.get("inertia_reference", {})
	if not inertia is Dictionary:
		return
	var inertia_value: Variant = inertia.get("value", null)
	if inertia_value is Array:
		for index in inertia_value.size():
			if _is_number(inertia_value[index]) and float(inertia_value[index]) <= 0.0:
				_issue(issues, "/plausibility/inertia_reference/value/%d" % index, "must be greater than zero")

static func _validate_slipstream_relations(propulsion: Dictionary, issues: PackedStringArray) -> void:
	var propeller: Variant = propulsion.get("propeller", {})
	if not propeller is Dictionary:
		return
	var slipstream: Variant = propeller.get("slipstream", null)
	if not slipstream is Dictionary:
		return
	var edge_active: bool = slipstream.has("edge_fraction")
	if slipstream.has("transport_speed_floor") and not edge_active:
		_issue(issues, "/propulsion/propeller/slipstream/transport_speed_floor", "requires edge_fraction")
	if edge_active and not slipstream.has("reverse_fade"):
		_issue(issues, "/propulsion/propeller/slipstream/reverse_fade", "is required when edge_fraction is present")
	if not edge_active and slipstream.has("reverse_fade"):
		_issue(issues, "/propulsion/propeller/slipstream/reverse_fade", "requires edge_fraction")
	var pieces: Variant = slipstream.get("pieces", [])
	if not pieces is Array:
		return
	for index in pieces.size():
		var piece: Variant = pieces[index]
		if not piece is Dictionary:
			continue
		var item_path := "/propulsion/propeller/slipstream/pieces/%d" % index
		if edge_active:
			if not piece.has("profile"):
				_issue(issues, item_path + "/profile", "is required for an edge_fraction profile")
			if piece.has("chords"):
				_issue(issues, item_path + "/chords", "must be absent when profile is used")
		else:
			if not piece.has("chords"):
				_issue(issues, item_path + "/chords", "is required for the legacy piece model")
			if piece.has("profile"):
				_issue(issues, item_path + "/profile", "requires edge_fraction")

static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

static func _classify_path(path: String, spec: Dictionary) -> Dictionary:
	if _path_class_cache.has(path):
		return _path_class_cache[path]
	var classification := {
		"object_rules": [],
		"array_rule": {},
		"quantity_path": false,
		"string_path": false,
		"string_nonempty": false,
		"enum_path": false,
		"enum_values": [],
		"literal_path": false,
		"literal_value": null,
	}
	for rule in spec.get("object_rules", []):
		if _path_matches(String(rule.get("path", "")), path):
			classification["object_rules"].append(rule)
	for rule in spec.get("array_rules", []):
		if _path_matches(String(rule.get("path", "")), path):
			classification["array_rule"] = rule
			break
	classification["quantity_path"] = _matches_any(path, spec.get("quantity_paths", []))
	for rule in spec.get("string_rules", []):
		if _path_matches(String(rule.get("path", "")), path):
			classification["string_path"] = true
			classification["string_nonempty"] = classification["string_nonempty"] or bool(rule.get("nonempty", false))
	for rule in spec.get("enum_paths", []):
		if _path_matches(String(rule.get("path", "")), path):
			classification["enum_path"] = true
			classification["enum_values"] = rule.get("values", [])
			break
	for rule in spec.get("literal_paths", []):
		if _path_matches(String(rule.get("path", "")), path):
			classification["literal_path"] = true
			classification["literal_value"] = rule.get("value", null)
			break
	_path_class_cache[path] = classification
	return classification

static func _select_object_rule(rules: Array, root: Dictionary) -> Dictionary:
	for rule in rules:
		var selector: Variant = rule.get("when", null)
		if selector is Dictionary:
			var found := _lookup_pointer(root, String(selector.get("path", "")))
			if not found[0] or found[1] != selector.get("equals", null):
				continue
		return rule
	return {}

static func _matches_any(path: String, patterns: Array) -> bool:
	for pattern in patterns:
		if _path_matches(String(pattern), path):
			return true
	return false

static func _path_matches(pattern: String, path: String) -> bool:
	var wanted := _pointer_parts(pattern)
	var actual := _pointer_parts(path)
	if wanted.size() != actual.size():
		return false
	for index in wanted.size():
		if wanted[index] != "*" and wanted[index] != actual[index]:
			return false
	return true

static func _pointer_parts(pointer: String) -> PackedStringArray:
	if pointer.is_empty() or pointer == "/":
		return PackedStringArray()
	var raw_parts := pointer.trim_prefix("/").split("/", false)
	var result := PackedStringArray()
	for part in raw_parts:
		result.append(String(part).replace("~1", "/").replace("~0", "~"))
	return result

static func _path_for(parts: PackedStringArray) -> String:
	if parts.is_empty():
		return "/"
	var result := ""
	for part in parts:
		result += "/" + String(part).replace("~", "~0").replace("/", "~1")
	return result

static func _append_path(path: String, key: String) -> String:
	var escaped := key.replace("~", "~0").replace("/", "~1")
	return ("" if path == "/" else path) + "/" + escaped

static func _lookup_pointer(root: Dictionary, pointer: String) -> Array:
	var current: Variant = root
	for segment in _pointer_parts(pointer):
		if not current is Dictionary or not current.has(segment):
			return [false, null]
		current = current[segment]
	return [true, current]

static func _issue(issues: PackedStringArray, path: String, message: String) -> void:
	issues.append("%s: %s" % [path, message])

