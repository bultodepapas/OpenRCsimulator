## Authored visual customization bindings. Materials are copied per mesh instance; physics and shared model resources stay immutable.
extends RefCounted

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const ModelRegistry := preload("res://aircraft/model_registry.gd")
const REGISTRY_PATH := "res://data/aircraft_customization.json"
const REGISTRY_FORMAT := "openrc-aircraft-customization-registry"
const COMPANION_FORMAT := "openrc-aircraft-customization-bindings"
const SHA256_RE := "^[0-9a-f]{64}$"
const SLOT_ID_RE := "^[a-z][a-z0-9_]{0,79}$"
const LABEL_RE := "^[ -~]{1,32}$"
const NODE_PATH_RE := "^[A-Za-z0-9_]+(/[A-Za-z0-9_]+)*$"
const PARAM_RE := "^[A-Za-z_][A-Za-z0-9_]{0,63}$"
const PAINT_KINDS := ["standard_albedo", "shader_color"]
const SMOKE_ROLES := ["wing_tip_left", "wing_tip_right", "tail", "exhaust"]


## Public resolver: the sidecar must match the current, independently validated physical model manifest.
static func describe(aircraft_id: String) -> Dictionary:
	var family := Catalog.visual_family(aircraft_id)
	if family.is_empty():
		return _failure("unknown aircraft has no customization family")
	var resolved: Dictionary = ModelRegistry.describe(family)
	if not resolved.get("ok", false):
		return _failure("physical model manifest is unavailable or invalid: " + str(resolved.get("errors", [])))
	return _describe_for_model(aircraft_id, str(resolved.get("manifest_sha256", "")))


## Build-path helper. The caller has just resolved and validated this exact manifest hash.
static func describe_for_model(aircraft_id: String, model_manifest_sha256: String) -> Dictionary:
	return _describe_for_model(aircraft_id, model_manifest_sha256)


static func _describe_for_model(aircraft_id: String, model_manifest_sha256: String) -> Dictionary:
	var family := Catalog.visual_family(aircraft_id)
	if family.is_empty() or not _matches(SHA256_RE, model_manifest_sha256):
		return _failure("aircraft family or physical model manifest hash is malformed")
	if not FileAccess.file_exists(REGISTRY_PATH):
		return _failure("customization registry is missing")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH))
	if not (parsed is Dictionary) or not _exact_keys(parsed, ["format", "version", "families"]):
		return _failure("customization registry is malformed")
	if str(parsed.get("format", "")) != REGISTRY_FORMAT or typeof(parsed.get("version")) != TYPE_INT or int(parsed.version) != 1 or not (parsed.get("families") is Array):
		return _failure("customization registry format or version is unsupported")
	var selected: Dictionary = {}
	var found := false
	for item in parsed.families:
		if not (item is Dictionary):
			return _failure("customization registry contains a malformed family companion")
		if str(item.get("visual_family", "")) == family:
			if found:
				return _failure("customization registry repeats a visual family")
			selected = item
			found = true
	if not found:
		return _failure("customization companion is missing for " + family)
	var checked := validate_bindings(selected, family, model_manifest_sha256)
	if not checked.ok:
		return checked
	return {"ok": true, "visual_family": family, "model_manifest_sha256": model_manifest_sha256,
		"bindings": selected.duplicate(true), "slots_sha256": str(selected.slots_sha256), "errors": []}


## Validate and hash the exact companion object. This is also useful to profile validators and focused tests.
static func validate_bindings(bindings: Dictionary, expected_family := "", expected_model_hash := "") -> Dictionary:
	var errors := PackedStringArray()
	if not _exact_keys(bindings, ["format", "version", "visual_family", "model_manifest_sha256", "paint_slots", "marking_slots", "smoke_slots", "slots_sha256"]):
		errors.append("customization companion has unknown or missing keys")
		return {"ok": false, "errors": errors}
	if bindings.get("format") != COMPANION_FORMAT or typeof(bindings.get("version")) != TYPE_INT or int(bindings.version) != 1:
		errors.append("customization companion format or version is unsupported")
	if not _matches("^[a-z0-9]+(-[a-z0-9]+)*$", str(bindings.get("visual_family", ""))):
		errors.append("customization companion visual family is malformed")
	if not expected_family.is_empty() and str(bindings.get("visual_family", "")) != expected_family:
		errors.append("customization companion family does not match the aircraft")
	if not _matches(SHA256_RE, str(bindings.get("model_manifest_sha256", ""))):
		errors.append("customization companion model hash is malformed")
	if not expected_model_hash.is_empty() and str(bindings.get("model_manifest_sha256", "")) != expected_model_hash:
		errors.append("customization companion is pinned to a different physical model manifest")
	if not _matches(SHA256_RE, str(bindings.get("slots_sha256", ""))):
		errors.append("customization companion slot hash is malformed")
	for key in ["paint_slots", "marking_slots", "smoke_slots"]:
		if not (bindings.get(key) is Array):
			errors.append("customization companion " + key + " must be an array")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	if not _validate_slot_group(bindings.paint_slots, "paint", errors):
		pass
	if not bindings.marking_slots.is_empty():
		errors.append("marking slots are unavailable until bounded marking bindings are implemented")
	if not _validate_slot_group(bindings.smoke_slots, "smoke", errors):
		pass
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var base := bindings.duplicate(true)
	base.erase("slots_sha256")
	var actual := _sha256(_canonical_json(base))
	if actual != str(bindings.slots_sha256):
		errors.append("customization companion slot hash does not match its contents")
	return {"ok": errors.is_empty(), "errors": errors}


## Apply paint to a single built instance. Passing an empty legacy profile restores stock colors.
static func apply(airplane: Dictionary, profile: Dictionary) -> Dictionary:
	var root: Node3D = airplane.get("root") as Node3D
	if root == null:
		return _failure("airplane instance has no render root")
	var bindings: Dictionary = airplane.get("customization_bindings", {})
	var identity := validate_bindings(bindings, str(airplane.get("visual_family", "")), str(airplane.get("model_manifest_sha256", "")))
	if not identity.ok:
		return {"ok": false, "errors": identity.errors}
	if not (profile is Dictionary):
		return _failure("presentation profile must be an object")
	if not profile.is_empty():
		var profile_binding: Variant = profile.get("binding", {})
		if not (profile_binding is Dictionary):
			return _failure("presentation profile binding is malformed")
		if not profile_binding.is_empty():
			if str(profile_binding.get("visual_family", "")) != str(bindings.visual_family) \
				or str(profile_binding.get("model_manifest_sha256", "")) != str(bindings.model_manifest_sha256) \
				or str(profile_binding.get("slots_sha256", "")) != str(bindings.slots_sha256):
				return _failure("presentation profile is bound to different aircraft slots")
	var paint: Variant = profile.get("paint", [])
	var markings: Variant = profile.get("markings", [])
	if not (paint is Array) or not (markings is Array) or not markings.is_empty():
		return _failure("presentation profile paint or marking selections are unsupported")
	var slots_by_id := {}
	for slot: Dictionary in bindings.paint_slots:
		slots_by_id[str(slot.id)] = slot
	var selected: Array[Dictionary] = []
	var seen := {}
	for item in paint:
		if not (item is Dictionary) or not _exact_keys(item, ["slot", "color", "pattern", "accent"]):
			return _failure("paint entry has unknown or missing keys")
		var slot_id := str(item.get("slot", ""))
		if not slots_by_id.has(slot_id) or seen.has(slot_id):
			return _failure("paint selection is missing a registered slot or repeats one")
		if str(item.get("pattern", "")) != "solid" or str(item.get("accent", "")) != "none":
			return _failure("paint selection requests an unsupported pattern or accent")
		var color_text := str(item.get("color", ""))
		if not _matches("^#[0-9A-Fa-f]{8}$", color_text):
			return _failure("paint color must be a canonical #RRGGBBAA swatch")
		var slot: Dictionary = slots_by_id[slot_id]
		for target: Dictionary in slot.targets:
			var checked := _resolve_target(root, target)
			if not checked.ok:
				return _failure("paint target is unavailable: " + str(checked.error))
		selected.append({"slot": slot, "color": Color(color_text)})
		seen[slot_id] = true
	var state: Dictionary = airplane.get("_customization_material_state", {})
	var staged := _stage_targets(root, selected, state)
	if not staged.ok:
		return {"ok": false, "errors": staged.errors}
	# Install all material copies only after every requested target has passed validation.
	for key in staged.new_state:
		var record: Dictionary = staged.new_state[key]
		(record.mesh as MeshInstance3D).set_surface_override_material(int(record.surface), record.material)
		state[key] = record
	# Reset every owned target first; omitted slots return to the authored source finish.
	for key in state:
		var record: Dictionary = state[key]
		_set_target_color(record.material, str(record.kind), str(record.parameter), record.original)
	for entry: Dictionary in selected:
		for target: Dictionary in entry.slot.targets:
			var key := _target_key(target)
			var record: Dictionary = state[key]
			_set_target_color(record.material, str(record.kind), str(record.parameter), entry.color)
	airplane["_customization_material_state"] = state
	return {"ok": true, "errors": []}


## Resolve every registered endpoint each call so moving aircraft/root transforms and source anchors stay current.
## The returned basis maps Godot's local -Z forward axis to the authored direction.
static func smoke_transforms(airplane: Dictionary) -> Dictionary:
	var result := {}
	var root: Node3D = airplane.get("root") as Node3D
	if root == null:
		return result
	var bindings: Dictionary = airplane.get("customization_bindings", {})
	var checked := validate_bindings(bindings, str(airplane.get("visual_family", "")), str(airplane.get("model_manifest_sha256", "")))
	if not checked.ok:
		return result
	for endpoint: Dictionary in bindings.smoke_slots:
		var resolved: Dictionary = _resolve_endpoint(root, airplane, endpoint)
		if not resolved.ok:
			continue
		var world_direction: Vector3 = root.global_transform.basis * resolved.direction if resolved.get("root_relative", false) else resolved.direction
		if not world_direction.is_finite() or world_direction.length_squared() < 1e-12:
			continue
		var direction := world_direction.normalized()
		var up := Vector3.UP
		if absf(direction.dot(up)) > 0.999:
			up = Vector3.RIGHT
		var origin: Vector3 = resolved.position
		result[str(endpoint.id)] = Transform3D(Basis.looking_at(direction, up), origin)
	return result


static func _resolve_endpoint(root: Node3D, airplane: Dictionary, endpoint: Dictionary) -> Dictionary:
	if endpoint.kind == "show":
		var node: Node3D = root if str(endpoint.node_path) == "." else root.get_node_or_null(NodePath(str(endpoint.node_path))) as Node3D
		if node == null:
			return {"ok": false}
		var position := _vector3(endpoint.position_m)
		var direction := _vector3(endpoint.direction)
		if not position.is_finite() or not direction.is_finite() or direction.length_squared() < 1e-12:
			return {"ok": false}
		return {"ok": true, "position": node.to_global(position), "direction": node.global_transform.basis * direction, "root_relative": false}
	if endpoint.kind != "source":
		return {"ok": false}
	if str(endpoint.source_anchor_ref) != "exhausts[0]" or str(endpoint.physical_source_ref) != "propulsion.id" or str(endpoint.physical_source_kind_ref) != "propulsion.kind":
		return {"ok": false}
	var exhausts: Variant = airplane.get("exhausts", root.get_meta("exhausts", []))
	if not (exhausts is Array) or exhausts.is_empty() or not (exhausts[0] is Dictionary):
		return {"ok": false}
	var anchor: Dictionary = exhausts[0]
	var source_kind := str(endpoint.source_kind)
	var physical_id := str(airplane.get("physical_propulsion_id", ""))
	var physical_kind := str(airplane.get("physical_propulsion_kind", ""))
	if physical_id.is_empty() or physical_kind != source_kind or str(anchor.get("kind", "")) != source_kind:
		return {"ok": false}
	var position: Variant = anchor.get("position")
	var direction: Variant = anchor.get("direction")
	if not (position is Vector3) or not (direction is Vector3) or not position.is_finite() or not direction.is_finite() or direction.length_squared() < 1e-12:
		return {"ok": false}
	return {"ok": true, "position": root.to_global(position), "direction": root.global_transform.basis * direction, "root_relative": false}


static func _stage_targets(root: Node3D, selected: Array[Dictionary], existing: Dictionary) -> Dictionary:
	var new_state := {}
	for entry: Dictionary in selected:
		for target: Dictionary in entry.slot.targets:
			var key := _target_key(target)
			if existing.has(key) or new_state.has(key):
				continue
			var checked := _resolve_target(root, target)
			if not checked.ok:
				return {"ok": false, "errors": PackedStringArray(["paint target is unavailable: " + str(checked.error)])}
		var source: Material = checked.material
		var copy := source.duplicate() as Material
		if copy == null:
			return {"ok": false, "errors": PackedStringArray(["paint material could not be isolated per instance"])}
		var original := _target_color(source, str(target.kind), str(target.get("parameter", "")))
		new_state[key] = {"mesh": checked.mesh, "surface": int(target.surface), "kind": str(target.kind),
			"parameter": str(target.get("parameter", "")), "original": original, "material": copy}
	return {"ok": true, "new_state": new_state, "errors": PackedStringArray()}


static func _resolve_target(root: Node3D, target: Dictionary) -> Dictionary:
	var node := root.get_node_or_null(NodePath(str(target.get("node_path", "")))) as MeshInstance3D
	if node == null or node.mesh == null:
		return {"ok": false, "error": "node_path does not resolve to a mesh instance"}
	var surface := int(target.get("surface", -1))
	if surface < 0 or surface >= node.mesh.get_surface_count():
		return {"ok": false, "error": "surface index is outside the mesh"}
	var material: Material = node.get_active_material(surface)
	var kind := str(target.get("kind", ""))
	var parameter := str(target.get("parameter", ""))
	if kind == "standard_albedo":
		if not (material is StandardMaterial3D):
			return {"ok": false, "error": "target material is not StandardMaterial3D"}
	elif kind == "shader_color":
		if not (material is ShaderMaterial):
			return {"ok": false, "error": "target material is not ShaderMaterial"}
		var shader_color: Variant = (material as ShaderMaterial).get_shader_parameter(parameter)
		if not (shader_color is Color):
			return {"ok": false, "error": "shader parameter is not a color uniform"}
	else:
		return {"ok": false, "error": "target kind is unsupported"}
	return {"ok": true, "mesh": node, "material": material}


static func _target_color(material: Material, kind: String, parameter: String) -> Color:
	if kind == "standard_albedo":
		return (material as StandardMaterial3D).albedo_color
	return (material as ShaderMaterial).get_shader_parameter(parameter) as Color


static func _set_target_color(material: Material, kind: String, parameter: String, color: Color) -> void:
	if kind == "standard_albedo":
		(material as StandardMaterial3D).albedo_color = color
	else:
		(material as ShaderMaterial).set_shader_parameter(parameter, color)


static func _target_key(target: Dictionary) -> String:
	return str(target.node_path) + "#" + str(target.surface)


static func _validate_slot_group(slots: Array, group: String, errors: PackedStringArray) -> bool:
	var seen := {}
	var previous := ""
	for slot: Variant in slots:
		if not (slot is Dictionary):
			errors.append(group + " slot must be an object")
			continue
		if group == "paint":
			if not _exact_keys(slot, ["id", "label", "targets"]):
				errors.append("paint slot has unknown or missing keys")
				continue
		else:
			var kind := str(slot.get("kind", ""))
			var expected := ["id", "label", "kind", "pair", "role"]
			if kind == "show": expected += ["node_path", "position_m", "direction"]
			elif kind == "source": expected += ["source_kind", "source_anchor_ref", "physical_source_ref", "physical_source_kind_ref"]
			else:
				errors.append("smoke slot kind is unsupported")
				continue
			if not _exact_keys(slot, expected):
				errors.append("smoke slot has unknown or missing keys")
				continue
		var slot_id := str(slot.get("id", ""))
		if not _matches(SLOT_ID_RE, slot_id) or seen.has(slot_id):
			errors.append(group + " slot id is malformed or duplicated")
			continue
		if not previous.is_empty() and slot_id < previous:
			errors.append(group + " slots must be sorted by id")
		previous = slot_id
		seen[slot_id] = true
		if not _matches(LABEL_RE, str(slot.get("label", ""))):
			errors.append(group + " slot label is malformed")
		if group == "paint":
			var targets: Variant = slot.get("targets")
			if not (targets is Array) or targets.is_empty():
				errors.append("paint slot targets must be a non-empty array")
				continue
			for target: Variant in targets:
				if not (target is Dictionary):
					errors.append("paint target must be an object")
					continue
				var kind := str(target.get("kind", ""))
				var expected := ["node_path", "surface", "kind"]
				if kind == "shader_color": expected.append("parameter")
				if not _exact_keys(target, expected) or kind not in PAINT_KINDS:
					errors.append("paint target keys or kind are invalid")
					continue
				var path := str(target.get("node_path", ""))
				if not _matches(NODE_PATH_RE, path) or typeof(target.get("surface")) != TYPE_INT or int(target.surface) < 0 or int(target.surface) > 64:
					errors.append("paint target path or surface is invalid")
				if kind == "shader_color" and not _matches(PARAM_RE, str(target.get("parameter", ""))):
					errors.append("paint shader color parameter is malformed")
		else:
			var role := str(slot.get("role", ""))
			if role not in SMOKE_ROLES:
				errors.append("smoke endpoint role is unsupported")
			if slot.kind == "show":
				var position: Variant = slot.get("position_m")
				var direction: Variant = slot.get("direction")
				if not (position is Array) or position.size() != 3 or not (direction is Array) or direction.size() != 3:
					errors.append("smoke show pose must contain three-number vectors")
				if role in ["wing_tip_left", "wing_tip_right"] and str(slot.get("pair", "")) != "wing_tips":
					errors.append("smoke wingtip endpoint pair is missing")
				if role == "tail" and not str(slot.get("pair", "")).is_empty():
					errors.append("smoke tail endpoint must be unpaired")
			else:
				if role != "exhaust" or str(slot.get("source_kind", "")) != "glow_prop" or str(slot.get("source_anchor_ref", "")) != "exhausts[0]" \
					or str(slot.get("physical_source_ref", "")) != "propulsion.id" or str(slot.get("physical_source_kind_ref", "")) != "propulsion.kind":
					errors.append("smoke source selectors are unsupported")
	return errors.is_empty()


static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


static func _canonical_value(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		var keys: Array = value.keys()
		keys.sort()
		for key in keys:
			out[key] = _canonical_value(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(_canonical_value(item))
		return out
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		if not is_finite(number):
			return null
		if number == floor(number):
			return int(number)
	return value


static func _canonical_json(value: Variant) -> PackedByteArray:
	return JSON.stringify(_canonical_value(value), "", true, true).to_utf8_buffer()


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _matches(pattern: String, value: String) -> bool:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return false
	return regex.search(value) != null


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}
