## Authored visual customization bindings. Materials are copied per mesh instance; physics and shared model resources stay immutable.
extends RefCounted

const AircraftLights := preload("res://render/world/aircraft_lights.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const ModelRegistry := preload("res://aircraft/model_registry.gd")
const PresentationSources := preload("res://render/presentation_sources.gd")
const REGISTRY_PATH := "res://data/aircraft_customization.json"
const REGISTRY_FORMAT := "openrc-aircraft-customization-registry"
const COMPANION_FORMAT := "openrc-aircraft-customization-bindings"
const SHA256_RE := "^[0-9a-f]{64}$"
const SLOT_ID_RE := "^[a-z][a-z0-9_]{0,79}$"
const LABEL_RE := "^[ -~]{1,32}$"
const NODE_PATH_RE := "^[A-Za-z0-9_]+(/[A-Za-z0-9_]+)*$"
const PARAM_RE := "^[A-Za-z_][A-Za-z0-9_]{0,63}$"
const PAINT_KINDS := ["standard_albedo", "shader_color"]
const SMOKE_ROLES := ["wing_tip_left", "wing_tip_right", "tail", "tailpipe", "exhaust"]
const SKIN_ZONE_IDS := ["strip_left", "strip_right", "strip_top_left", "strip_top_right", "strip_belly"]
const SKIN_MASK_PROFILES_BY_FAMILY := {
	"jensen-das-ugly-stik-60": ["jensen_stik_film_bays_v1"],
}
const MAX_AUTHORED_SKINS := 5
const MAX_AUTHORED_SKIN_TARGETS := 12
const MARKING_TEXT_ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -ÁÉÍÓÚÜÑáéíóúüñ"
const MARKING_FONT_SIZE := 64
const MARKING_MIN_WIDTH_M := 0.01
const MARKING_MAX_WIDTH_M := 1.0
const MARKING_MIN_HEIGHT_M := 0.01
const MARKING_MAX_HEIGHT_M := 0.3


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
	if str(parsed.get("format", "")) != REGISTRY_FORMAT or not _integer_value(parsed.get("version")) or int(parsed.version) != 1 or not (parsed.get("families") is Array):
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
	if not _integer_value(bindings.get("version")):
		return {"ok": false, "errors": PackedStringArray(["customization companion version is unsupported"])}
	var binding_version := int(bindings.version)
	var expected_keys := ["format", "version", "visual_family", "model_manifest_sha256", "paint_slots", "marking_slots", "smoke_slots", "slots_sha256"]
	if binding_version >= 2:
		expected_keys.append_array(["presentation_engine_version", "presentation_sources"])
	if binding_version >= 3:
		expected_keys.append("source_proof_version")
	if binding_version == 4:
		expected_keys.append("lighting_layout")
	if not _exact_keys(bindings, expected_keys):
		errors.append("customization companion has unknown or missing keys")
		return {"ok": false, "errors": errors}
	if bindings.get("format") != COMPANION_FORMAT or binding_version not in [1, 2, 3, 4]:
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
	if not _validate_slot_group(bindings.marking_slots, "marking", errors):
		pass
	if binding_version >= 3:
		if bindings.smoke_slots.size() > 8:
			errors.append("customization supports at most eight authored smoke outlets")
		var seen_smoke := {}
		for slot: Variant in bindings.smoke_slots:
			var checked_slot: Dictionary = validate_smoke_slot(slot, 3)
			if not checked_slot.ok:
				errors.append_array(checked_slot.errors)
			elif seen_smoke.has(str(slot.id)):
				errors.append("smoke outlet id is duplicated")
			else:
				seen_smoke[str(slot.id)] = true
	elif not _validate_slot_group(bindings.smoke_slots, "smoke", errors):
		pass
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	if binding_version == 4:
		var lighting_check := _validate_authored_lighting_layout(bindings.lighting_layout, bindings.paint_slots,
			str(bindings.visual_family))
		if not lighting_check.ok:
			return lighting_check
	var base := bindings.duplicate(true)
	base.erase("slots_sha256")
	var actual := _sha256(_canonical_json(base))
	if actual != str(bindings.slots_sha256):
		errors.append("customization companion slot hash does not match its contents")
	if binding_version >= 2:
		var proof_version := 1
		if binding_version >= 3:
			if not _integer_value(bindings.get("source_proof_version")) or int(bindings.source_proof_version) not in [2, 3]:
				errors.append("customization source proof version is unsupported")
			proof_version = int(bindings.source_proof_version) if _integer_value(bindings.get("source_proof_version")) else 0
		var source_result: Dictionary = PresentationSources.validate(bindings.presentation_sources, bindings.presentation_engine_version, proof_version)
		if not source_result.get("ok", false):
			for message: Variant in source_result.get("errors", []):
				errors.append("presentation dependency validation failed: " + str(message))
	return {"ok": errors.is_empty(), "errors": errors}


## One strict descriptor reader shared by persistent profile validation and resolution.
static func validate_smoke_slot(value: Variant, version: int = 3) -> Dictionary:
	var errors := PackedStringArray()
	if not (value is Dictionary) or version != 3:
		return _failure("smoke outlet must use companion v3")
	var slot: Dictionary = value
	var kind := str(slot.get("kind", ""))
	var policy := str(slot.get("activation_policy", ""))
	var expected := ["id", "label", "kind", "pair", "role", "radius_m", "emissions_preset", "activation_policy", "provenance"]
	var anchored := slot.has("anchor_id")
	if kind == "source" or anchored:
		expected += ["source_id", "source_kind", "anchor_id"]
	elif kind == "show":
		expected += ["node_path", "position_m", "direction"]
		if policy == "source_and_request":
			expected += ["source_id", "source_kind"]
	if kind not in ["source", "show"] or not _exact_keys(slot, expected):
		return _failure("smoke outlet has unsupported or missing keys")
	for key: String in ["id", "label", "kind", "pair", "role", "emissions_preset", "activation_policy", "provenance"]:
		if not (slot[key] is String):
			return _failure("smoke outlet descriptor fields must be strings")
	if not _matches(SLOT_ID_RE, str(slot.id)) or not _matches(LABEL_RE, str(slot.label)):
		errors.append("smoke outlet id or label is malformed")
	if str(slot.role) not in SMOKE_ROLES or not (slot.pair is String) or (not str(slot.pair).is_empty() and not _matches(SLOT_ID_RE, str(slot.pair))):
		errors.append("smoke outlet role or pair is malformed")
	if str(slot.provenance) not in ["estimated", "authored", "measured"] or str(slot.emissions_preset) not in ["glow_two_stroke", "glow_four_stroke", "glow_installation", "gasoline_two_stroke", "turbine_show", "independent_show"]:
		errors.append("smoke outlet preset or provenance is unsupported")
	if not _bounded_dimension(slot.radius_m, 0.0001, 0.1):
		errors.append("smoke outlet radius must be in [0.0001, 0.1] metres")
	if kind == "source" and (policy != "source_running" or str(slot.role) != "exhaust" or not str(slot.pair).is_empty()):
		errors.append("source exhaust requires an unpaired exhaust and source_running policy")
	if kind == "show" and policy not in ["independent_request", "source_and_request"]:
		errors.append("show outlet activation policy is unsupported")
	if anchored and kind == "show" and policy != "source_and_request":
		errors.append("a source-anchored show outlet requires source_and_request policy")
	if kind == "show" and str(slot.role) == "exhaust" and not anchored:
		errors.append("an exhaust show outlet must use its physical source anchor")
	if slot.has("source_id"):
		if not (slot.source_id is String) or (str(slot.source_id) != "$propulsion" and not _matches("^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$", str(slot.source_id))) \
				or str(slot.source_kind) not in ["glow_prop", "electric_prop", "turbine"]:
			errors.append("smoke source identity or solver kind is unsupported")
	if anchored:
		if not _matches(SLOT_ID_RE, str(slot.anchor_id)):
			errors.append("smoke source anchor id is malformed")
	else:
		if str(slot.node_path) != "." and not _matches(NODE_PATH_RE, str(slot.node_path)):
			errors.append("smoke show node path is malformed")
		if not _valid_pose_vector(slot.position_m, false) or not _valid_pose_vector(slot.direction, true):
			errors.append("smoke show pose is invalid")
	if str(slot.role) in ["wing_tip_left", "wing_tip_right"] and (kind != "show" or str(slot.pair) != "wing_tips"):
		errors.append("wingtip outlet must be an explicit show pair")
	if str(slot.role) in ["tail", "tailpipe", "exhaust"] and not str(slot.pair).is_empty():
		errors.append("tail and exhaust outlets must be unpaired")
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
	if not (paint is Array) or not (markings is Array):
		return _failure("presentation profile paint and markings must be arrays")
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
	var marking_slots_by_id := {}
	for slot: Dictionary in bindings.marking_slots:
		marking_slots_by_id[str(slot.id)] = slot
	var selected_markings: Array[Dictionary] = []
	var seen_markings := {}
	for item in markings:
		if not (item is Dictionary) or not _exact_keys(item, ["slot", "text", "color"]):
			return _failure("marking entry has unknown or missing keys")
		var slot_id := str(item.get("slot", ""))
		if not marking_slots_by_id.has(slot_id) or seen_markings.has(slot_id):
			return _failure("marking selection requests an unavailable or repeated slot")
		var slot: Dictionary = marking_slots_by_id[slot_id]
		var text := str(item.get("text", ""))
		if not _valid_marking_text(text, int(slot.max_chars)):
			return _failure("marking text is empty, too long, unsupported, or missing a fallback-font glyph")
		var color_text := str(item.get("color", ""))
		if not _matches("^#[0-9A-Fa-f]{8}$", color_text):
			return _failure("marking color must be a canonical #RRGGBBAA swatch")
		var staged_labels: Array[Dictionary] = []
		for target: Dictionary in slot.targets:
			var parent := root.get_node_or_null(NodePath(str(target.node_path))) as MeshInstance3D
			if parent == null or parent.mesh == null:
				return _failure("marking target is unavailable: node_path does not resolve to a mesh instance")
			var label_result := _make_marking_label(text, Color(color_text), target)
			if not label_result.ok:
				return _failure("marking target is unavailable: " + str(label_result.error))
			staged_labels.append({"parent": parent, "node": label_result.node})
		selected_markings.append({"slot": slot_id, "labels": staged_labels})
		seen_markings[slot_id] = true
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
	_clear_marking_nodes(airplane)
	var installed_labels: Array[Label3D] = []
	for entry: Dictionary in selected_markings:
		for staged_label: Dictionary in entry.labels:
			var parent: MeshInstance3D = staged_label.parent
			var label: Label3D = staged_label.node
			parent.add_child(label)
			installed_labels.append(label)
	airplane["_customization_marking_nodes"] = installed_labels
	return {"ok": true, "errors": [], "marking_count": installed_labels.size()}


## Validate once at configuration, retaining node handles rather than repeated file hashes.
static func resolve_smoke_bindings(airplane: Dictionary) -> Dictionary:
	var root: Node3D = airplane.get("root") as Node3D
	if root == null or not is_instance_valid(root):
		return _failure("airplane instance has no render root")
	var bindings: Dictionary = airplane.get("customization_bindings", {})
	var checked := validate_bindings(bindings, str(airplane.get("visual_family", "")), str(airplane.get("model_manifest_sha256", "")))
	if not checked.ok:
		return checked
	var handles: Dictionary = {"root": root, "endpoints": [], "sources": {}}
	var errors := PackedStringArray()
	var sources: Dictionary = legacy_source_anchors(airplane)
	for endpoint: Dictionary in bindings.smoke_slots:
		var descriptor := endpoint.duplicate(true)
		if int(bindings.version) < 3:
			var legacy: Dictionary = _resolve_endpoint(root, airplane, endpoint)
			if not legacy.get("ok", false):
				errors.append("Unavailable legacy smoke outlet: " + str(endpoint.id))
				continue
			handles.endpoints.append({"id": str(endpoint.id), "node": root, "position": legacy.position, "direction": legacy.direction})
			continue
		var node: Node3D = root
		var position := Vector3.ZERO
		var direction := Vector3.ZERO
		if endpoint.has("source_id"):
			var source_id := str(airplane.get("physical_propulsion_id", "")) if str(endpoint.source_id) == "$propulsion" else str(endpoint.source_id)
			descriptor["source_id"] = source_id
			if source_id.is_empty() or not sources.has(source_id) or not (sources[source_id] is Dictionary) \
					or str(sources[source_id].get("kind", "")) != str(endpoint.source_kind):
				errors.append("Missing or mismatched smoke source: " + str(endpoint.id))
				continue
			handles.sources[str(endpoint.id)] = source_id
		if endpoint.has("anchor_id"):
			var anchors_value: Variant = sources[descriptor.source_id].get("anchors", {})
			if not (anchors_value is Dictionary):
				errors.append("Malformed smoke source anchors: " + str(endpoint.id))
				continue
			var anchors: Dictionary = anchors_value
			var anchor: Variant = anchors.get(str(endpoint.anchor_id))
			if not (anchor is Dictionary):
				errors.append("Missing smoke anchor: " + str(endpoint.id))
				continue
			var anchor_position: Variant = anchor.get("position")
			var anchor_direction: Variant = anchor.get("direction")
			if not (anchor_position is Vector3) or not (anchor_direction is Vector3):
				errors.append("Invalid smoke anchor pose: " + str(endpoint.id))
				continue
			position = anchor_position
			direction = anchor_direction
			if maxf(absf(position.x), maxf(absf(position.y), absf(position.z))) > 5.0 \
					or absf(direction.length() - 1.0) > 0.001:
				errors.append("Smoke anchor pose is outside authored bounds: " + str(endpoint.id))
				continue
			if anchor.has("node"):
				node = anchor.node as Node3D
		else:
			node = root if str(endpoint.node_path) == "." else root.get_node_or_null(NodePath(str(endpoint.node_path))) as Node3D
			position = _vector3(endpoint.position_m)
			direction = _vector3(endpoint.direction)
		if node == null or not position.is_finite() or not direction.is_finite() or direction.length_squared() < 1e-12:
			errors.append("Invalid smoke mount: " + str(endpoint.id))
			continue
		var relative: Dictionary = _node_to_root(root, node)
		if not relative.ok or not _rigid_uniform_basis(relative.transform.basis):
			errors.append("Unsupported smoke attachment transform: " + str(endpoint.id))
			continue
		handles.endpoints.append({"id": str(endpoint.id), "node": node, "position": position,
			"direction": direction.normalized(), "descriptor": descriptor})
	return {"ok": errors.is_empty(), "errors": errors, "handles": handles}


## Explicit compatibility adapter: only this function maps the old positional anchor.
## Authored source maps take priority and can contain several sources and anchors.
static func legacy_source_anchors(airplane: Dictionary) -> Dictionary:
	var authored: Variant = airplane.get("smoke_sources", {})
	var result: Dictionary = authored.duplicate(true) if authored is Dictionary else {}
	var root: Node3D = airplane.get("root") as Node3D
	var source_id := str(airplane.get("physical_propulsion_id", ""))
	var kind := str(airplane.get("physical_propulsion_kind", ""))
	if source_id.is_empty() or result.has(source_id):
		return result
	var anchors: Dictionary = {}
	var exhausts: Variant = airplane.get("exhausts", root.get_meta("exhausts", []) if root != null else [])
	if exhausts is Array and not exhausts.is_empty() and exhausts[0] is Dictionary:
		var anchor: Dictionary = exhausts[0]
		if str(anchor.get("kind", "")) == kind:
			anchors["physical_exit"] = anchor.duplicate(true)
	# A source with no authored outlet remains available only for locally mounted
	# source-gated show devices (for example a turbine smoke pump).
	result[source_id] = {"kind": kind, "anchors": anchors}
	return result


## Moving/articulated nodes update every call. No profile, registry or file validation.
static func update_smoke_transforms(handles: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if not is_instance_valid(handles.get("root")):
		return result
	var root: Node3D = handles.get("root") as Node3D
	if root == null or not is_instance_valid(root):
		return result
	var root_world := root.global_transform if root.is_inside_tree() else root.transform
	if not root_world.is_finite() or not _rigid_uniform_basis(root_world.basis):
		return result
	for endpoint: Dictionary in handles.get("endpoints", []):
		if not is_instance_valid(endpoint.get("node")):
			continue
		var node: Node3D = endpoint.get("node") as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var relative: Dictionary = _node_to_root(root, node)
		if not relative.ok or not _rigid_uniform_basis(relative.transform.basis):
			continue
		var world: Transform3D = root_world * relative.transform
		var direction: Vector3 = world.basis * endpoint.direction
		if not world.is_finite() or not direction.is_finite() or direction.length_squared() < 1e-12:
			continue
		direction = direction.normalized()
		var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.999 else Vector3.UP
		# Preserve admitted uniform scale for the authored physical bore. Consumers
		# normalize direction vectors and scale aperture radius separately.
		var outlet_basis := Basis.looking_at(direction, up).scaled(Vector3.ONE * world.basis.x.length())
		result[str(endpoint.id)] = Transform3D(outlet_basis, world * endpoint.position)
	return result


## Compatibility facade caches configuration on the aircraft instance.
static func smoke_transforms(airplane: Dictionary) -> Dictionary:
	if not airplane.has("_smoke_binding_cache"):
		var resolved := resolve_smoke_bindings(airplane)
		airplane["_smoke_binding_cache"] = resolved.get("handles", {})
		airplane["_smoke_binding_errors"] = resolved.get("errors", [])
	return update_smoke_transforms(airplane["_smoke_binding_cache"])


static func invalidate_smoke_bindings(airplane: Dictionary) -> void:
	airplane.erase("_smoke_binding_cache")
	airplane.erase("_smoke_binding_errors")


static func _rigid_uniform_basis(value: Basis) -> bool:
	if not value.is_finite():
		return false
	var x := value.x.length()
	var y := value.y.length()
	var z := value.z.length()
	if minf(x, minf(y, z)) < 1e-9 or value.determinant() <= 0.0:
		return false
	return absf(x - y) <= x * 0.0001 and absf(x - z) <= x * 0.0001 \
		and absf(value.x.dot(value.y)) <= x * y * 0.0001 \
		and absf(value.x.dot(value.z)) <= x * z * 0.0001 \
		and absf(value.y.dot(value.z)) <= y * z * 0.0001


static func _resolve_endpoint(root: Node3D, airplane: Dictionary, endpoint: Dictionary) -> Dictionary:
	if endpoint.kind == "show":
		var node: Node3D = root if str(endpoint.node_path) == "." else root.get_node_or_null(NodePath(str(endpoint.node_path))) as Node3D
		if node == null:
			return {"ok": false}
		var position := _vector3(endpoint.position_m)
		var direction := _vector3(endpoint.direction)
		if not position.is_finite() or not direction.is_finite() or direction.length_squared() < 1e-12:
			return {"ok": false}
		var node_to_root := _node_to_root(root, node)
		if not node_to_root.ok:
			return {"ok": false}
		return {"ok": true, "position": node_to_root.transform * position, "direction": node_to_root.transform.basis * direction}
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
	return {"ok": true, "position": position, "direction": direction}


static func _node_to_root(root: Node3D, node: Node3D) -> Dictionary:
	var relative := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != root:
		if cursor == null or not (cursor is Node3D):
			return {"ok": false}
		relative = (cursor as Node3D).transform * relative
		cursor = cursor.get_parent()
	return {"ok": true, "transform": relative}


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


static func _valid_marking_text(text: String, max_chars: int) -> bool:
	if text.is_empty() or text.length() > max_chars or text != text.strip_edges():
		return false
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return false
	for index in text.length():
		var character := text.substr(index, 1)
		if not MARKING_TEXT_ALPHABET.contains(character) or not font.has_char(text.unicode_at(index)):
			return false
	return true


static func _make_marking_label(text: String, color: Color, target: Dictionary) -> Dictionary:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return {"ok": false, "error": "bundled fallback font is unavailable"}
	var font_bounds := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, MARKING_FONT_SIZE)
	var font_height := font.get_height(MARKING_FONT_SIZE)
	if not font_bounds.is_finite() or font_bounds.x <= 0.0 or not is_finite(font_height) or font_height <= 0.0:
		return {"ok": false, "error": "fallback font returned invalid text bounds"}
	var width := float(target.width_m)
	var height := float(target.height_m)
	var pixel_size := minf(width / font_bounds.x, height / font_height) * 0.92
	if not is_finite(pixel_size) or pixel_size <= 0.0:
		return {"ok": false, "error": "marking text cannot be fitted to its authored panel"}
	var direction := _vector3(target.direction).normalized()
	var up := _vector3(target.up)
	up = (up - direction * up.dot(direction)).normalized()
	if direction.length_squared() < 1e-12 or up.length_squared() < 1e-12:
		return {"ok": false, "error": "marking mount orientation is degenerate"}
	var right := up.cross(direction).normalized()
	var label := Label3D.new()
	label.name = "AircraftRegistration"
	label.font = font
	label.font_size = MARKING_FONT_SIZE
	label.pixel_size = pixel_size
	label.text = text
	label.modulate = color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.double_sided = false
	label.no_depth_test = false
	label.fixed_size = false
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.shaded = true
	label.outline_size = 0
	label.position = _vector3(target.position_m)
	# Label3D's generated text faces local +Z; the authored outward vector owns that normal.
	label.basis = Basis(right, up, direction)
	return {"ok": true, "node": label, "error": ""}


static func _clear_marking_nodes(airplane: Dictionary) -> void:
	var previous: Variant = airplane.get("_customization_marking_nodes", [])
	if not (previous is Array):
		return
	for item in previous:
		if not (item is Label3D) or not is_instance_valid(item):
			continue
		var parent: Node = item.get_parent()
		if parent != null:
			parent.remove_child(item)
		item.free()


static func _target_key(target: Dictionary) -> String:
	return str(target.node_path) + "#" + str(target.surface)


static func _validate_authored_lighting_layout(raw: Variant, paint_slots: Array, family_id: String) -> Dictionary:
	if not (raw is Dictionary):
		return _failure("lighting layout must be an object")
	var version: Variant = raw.get("version")
	if not _integer_value(version) or int(version) not in [1, 2]:
		return _failure("lighting layout version is unsupported")
	var layout_version := int(version)
	var expected_keys := ["version", "anchors", "strips"]
	if layout_version == 2:
		expected_keys.append("skins")
	if not _exact_keys(raw, expected_keys):
		return _failure("lighting layout fields are missing or unsupported")
	# Anchor/strip rules remain owned by AircraftLights. Pass it the v1 projection so
	# a v2 skin extension does not change the established point/strip contract.
	var base_layout := {"version": 1, "anchors": raw.anchors, "strips": raw.strips}
	var checked := AircraftLights.validate_authored_layout(base_layout)
	if not checked.ok:
		return checked
	if layout_version == 1:
		return {"ok": true, "errors": PackedStringArray()}
	return _validate_authored_skin_bindings(raw.skins, paint_slots, family_id)


static func _validate_authored_skin_bindings(raw_skins: Variant, paint_slots: Array, family_id: String) -> Dictionary:
	var errors := PackedStringArray()
	if not (raw_skins is Array) or raw_skins.size() > MAX_AUTHORED_SKINS:
		return _failure("lighting skins must be an array of at most %d entries" % MAX_AUTHORED_SKINS)
	var paint_targets_by_slot := {}
	for slot: Dictionary in paint_slots:
		var targets_by_id := {}
		for target: Dictionary in slot.get("targets", []):
			if target.has("target_id"):
				targets_by_id[str(target.target_id)] = target
		paint_targets_by_slot[str(slot.id)] = targets_by_id
	var allowed_masks: Array = SKIN_MASK_PROFILES_BY_FAMILY.get(family_id, [])
	var seen_zones := {}
	var used_target_ids := {}
	var target_count := 0
	for skin: Variant in raw_skins:
		if not _exact_keys(skin, ["zone_id", "paint_slot_id", "target_ids", "mask_profile_id"]):
			errors.append("lighting skin row has unknown or missing keys")
			continue
		var zone_id: Variant = skin.get("zone_id")
		if typeof(zone_id) != TYPE_STRING or not SKIN_ZONE_IDS.has(str(zone_id)) or seen_zones.has(str(zone_id)):
			errors.append("lighting skin zone id is unsupported or duplicated")
			continue
		seen_zones[str(zone_id)] = true
		var paint_slot_id: Variant = skin.get("paint_slot_id")
		if typeof(paint_slot_id) != TYPE_STRING or not _matches(SLOT_ID_RE, str(paint_slot_id)) \
				or not paint_targets_by_slot.has(str(paint_slot_id)):
			errors.append("lighting skin paint slot is malformed or missing")
			continue
		var target_ids: Variant = skin.get("target_ids")
		if not (target_ids is Array) or target_ids.is_empty() or target_ids.size() > MAX_AUTHORED_SKIN_TARGETS:
			errors.append("lighting skin targets must contain 1 to %d ids" % MAX_AUTHORED_SKIN_TARGETS)
			continue
		var slot_targets: Dictionary = paint_targets_by_slot[str(paint_slot_id)]
		for target_id_value: Variant in target_ids:
			if typeof(target_id_value) != TYPE_STRING or not _matches(SLOT_ID_RE, str(target_id_value)):
				errors.append("lighting skin target id is malformed")
				continue
			var target_id := str(target_id_value)
			if used_target_ids.has(target_id):
				errors.append("lighting skin target is duplicated")
				continue
			if not slot_targets.has(target_id):
				errors.append("lighting skin target does not resolve inside its paint slot")
				continue
			var target: Dictionary = slot_targets[target_id]
			if str(target.get("kind", "")) != "standard_albedo":
				errors.append("lighting skin target must be a standard_albedo paint surface")
				continue
			used_target_ids[target_id] = true
			target_count += 1
			if target_count > MAX_AUTHORED_SKIN_TARGETS:
				errors.append("lighting skins may reference at most %d targets total" % MAX_AUTHORED_SKIN_TARGETS)
		var mask_profile_id: Variant = skin.get("mask_profile_id")
		if typeof(mask_profile_id) != TYPE_STRING or not allowed_masks.has(str(mask_profile_id)):
			errors.append("lighting skin mask profile is not registered for this aircraft")
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_slot_group(slots: Array, group: String, errors: PackedStringArray) -> bool:
	var seen := {}
	var seen_paint_target_ids := {}
	var previous := ""
	for slot: Variant in slots:
		if not (slot is Dictionary):
			errors.append(group + " slot must be an object")
			continue
		if group == "paint":
			if not _exact_keys(slot, ["id", "label", "targets"]):
				errors.append("paint slot has unknown or missing keys")
				continue
		elif group == "marking":
			if not _exact_keys(slot, ["id", "label", "max_chars", "targets"]):
				errors.append("marking slot has unknown or missing keys")
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
				if target.has("target_id"): expected.append("target_id")
				if not _exact_keys(target, expected) or kind not in PAINT_KINDS:
					errors.append("paint target keys or kind are invalid")
					continue
				var path := str(target.get("node_path", ""))
				if not _matches(NODE_PATH_RE, path) or not _integer_value(target.get("surface")) or int(target.surface) < 0 or int(target.surface) > 64:
					errors.append("paint target path or surface is invalid")
				if kind == "shader_color" and not _matches(PARAM_RE, str(target.get("parameter", ""))):
					errors.append("paint shader color parameter is malformed")
				if target.has("target_id"):
					var target_id := str(target.get("target_id", ""))
					if not _matches(SLOT_ID_RE, target_id) or seen_paint_target_ids.has(target_id):
						errors.append("paint target id is malformed or duplicated")
					else:
						seen_paint_target_ids[target_id] = true
		elif group == "marking":
			if not _integer_value(slot.get("max_chars")) or int(slot.max_chars) < 1 or int(slot.max_chars) > 12:
				errors.append("marking max_chars must be an integer in [1, 12]")
			var targets: Variant = slot.get("targets")
			if not (targets is Array) or targets.size() < 1 or targets.size() > 2:
				errors.append("marking targets must contain one or two authored mounts")
				continue
			var seen_mounts := {}
			for target: Variant in targets:
				if not (target is Dictionary) or not _exact_keys(target, ["node_path", "position_m", "direction", "up", "width_m", "height_m"]):
					errors.append("marking target has unknown or missing keys")
					continue
				var path := str(target.get("node_path", ""))
				var position: Variant = target.get("position_m")
				var direction: Variant = target.get("direction")
				var up: Variant = target.get("up")
				if not _matches(NODE_PATH_RE, path) or not _valid_pose_vector(position, false) \
					or not _valid_pose_vector(direction, true) or not _valid_pose_vector(up, true):
					errors.append("marking target path or pose vectors are invalid")
					continue
				if absf(_vector3(direction).dot(_vector3(up))) > 0.001:
					errors.append("marking target up must be perpendicular to direction")
				var width: Variant = target.get("width_m")
				var height: Variant = target.get("height_m")
				if not _bounded_dimension(width, MARKING_MIN_WIDTH_M, MARKING_MAX_WIDTH_M) \
					or not _bounded_dimension(height, MARKING_MIN_HEIGHT_M, MARKING_MAX_HEIGHT_M):
					errors.append("marking target dimensions are outside authored bounds")
				var mount_key := path + "#" + JSON.stringify(_canonical_value(position))
				if seen_mounts.has(mount_key):
					errors.append("marking target duplicates an authored mount")
				seen_mounts[mount_key] = true
		else:
			var role := str(slot.get("role", ""))
			if role not in SMOKE_ROLES:
				errors.append("smoke endpoint role is unsupported")
			if slot.kind == "show":
				var position: Variant = slot.get("position_m")
				var direction: Variant = slot.get("direction")
				if not _valid_pose_vector(position, false) or not _valid_pose_vector(direction, true):
					errors.append("smoke show pose must contain three-number vectors")
				if role in ["wing_tip_left", "wing_tip_right"] and str(slot.get("pair", "")) != "wing_tips":
					errors.append("smoke wingtip endpoint pair is missing")
				if role in ["tail", "tailpipe"] and not str(slot.get("pair", "")).is_empty():
					errors.append("smoke tail/tailpipe endpoint must be unpaired")
			else:
				if role != "exhaust" or str(slot.get("source_kind", "")) != "glow_prop" or str(slot.get("source_anchor_ref", "")) != "exhausts[0]" \
					or str(slot.get("physical_source_ref", "")) != "propulsion.id" or str(slot.get("physical_source_kind_ref", "")) != "propulsion.kind":
					errors.append("smoke source selectors are unsupported")
	return errors.is_empty()


static func _bounded_dimension(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) \
		and float(value) >= minimum and float(value) <= maximum


static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


static func _integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	return float(value) == floor(float(value))


static func _valid_pose_vector(value: Variant, unit: bool) -> bool:
	if not (value is Array) or value.size() != 3:
		return false
	var total := 0.0
	for item in value:
		if typeof(item) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(item)) or absf(float(item)) > 5.0:
			return false
		total += float(item) * float(item)
	if unit:
		return total > 1e-12 and absf(sqrt(total) - 1.0) <= 0.001
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
