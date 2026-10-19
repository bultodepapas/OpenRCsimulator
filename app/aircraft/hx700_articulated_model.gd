# HELI-25c: strict loader for the neutral HX-700 mechanical preview.
# This detached preview is deliberately separate from aircraft/flight registration.
extends RefCounted

const PROFILE_PATH := "res://assets/aircraft/hx-700/articulated/construction.json"
const ASSET_PATH := "res://assets/aircraft/hx-700/articulated/hx-700.glb"
const PROFILE_SHA256 := "0fc621542b5ed523f903518fdbb3508c4c98672de59f0cdeea089eeb6c469d23"
const ASSET_SHA256 := "f5f7de25a586b65b0f77ab17497665cc5f47cc409de6c531cadf490676159e47"
const SOURCE_PATH := "assets/source-deliveries/hx-700-articulated/HX-700_Helicoptero_RC_1.blend"
const SOURCE_SHA256 := "1919de349b74286bc36770ab2d7d08f743fd8a4062608d488c7e4e276103725f"
const SOURCE_BLENDER_VERSION := "5.2.2 LTS"
const SCHEMA := "openrc-rotorcraft-construction"
const PROFILE_ID := "hx-700-articulated-r1"
const PURPOSE := "neutral-mechanical-preview"
const COORDINATES := "gltf-y-up-metres"
const TRANSFORM_TOLERANCE := 2.0e-6
const LINK_TOLERANCE_M := 2.0e-6

const REQUIRED_ROLE_COUNTS := {
	"root": 1,
	"main_shaft": 1,
	"tail_shaft": 1,
	"fixed_swash": 1,
	"rotating_swash": 1,
	"actuator_output": 4,
	"main_blade": 2,
	"tail_blade": 2,
	"main_grip": 2,
	"tail_grip": 2,
	"tail_slider": 1,
	"tail_yoke": 1,
	"tail_bellcrank": 1,
	"link_endpoint": 18,
}

const REQUIRED_MESH_ROLES := {
	"mesh": true,
	"link_endpoint": true,
	"actuator_output": true,
	"main_blade": true,
	"tail_blade": true,
	"main_grip": true,
	"tail_grip": true,
	"fixed_swash": true,
	"rotating_swash": true,
	"tail_slider": true,
	"tail_yoke": true,
	"tail_bellcrank": true,
}

# These are the only authored texture slots in the hash-pinned GLB. Keeping
# them explicit means an import that drops a .ctex dependency cannot silently
# turn a textured material into an untextured one.
const REQUIRED_TEXTURE_SLOTS := {
	"visual.botalon_carbono": {0: ["albedo_texture"]},
	"visual.carenado": {0: ["albedo_texture", "metallic_texture", "roughness_texture"]},
}

const REQUIRED_SEMANTIC_ROLES := {
	"root": "root",
	"main.shaft": "main_shaft",
	"tail.shaft": "tail_shaft",
	"swash.fixed": "fixed_swash",
	"swash.rotating": "rotating_swash",
	"actuator.cyclic.front_left": "actuator_output",
	"actuator.cyclic.front_right": "actuator_output",
	"actuator.cyclic.rear": "actuator_output",
	"actuator.tail": "actuator_output",
	"main.blade.a": "main_blade",
	"main.blade.b": "main_blade",
	"main.grip.a": "main_grip",
	"main.grip.b": "main_grip",
	"tail.blade.a": "tail_blade",
	"tail.blade.b": "tail_blade",
	"tail.grip.a": "tail_grip",
	"tail.grip.b": "tail_grip",
	"tail.slider": "tail_slider",
	"tail.yoke": "tail_yoke",
	"tail.bellcrank": "tail_bellcrank",
}


## Loads a validated imported scene only when the raw source bytes are available
## and match the profile digest. Exported PCK remapping may omit those bytes;
## that case fails closed until a raw-buffer admission path is added.
static func load_preview(profile_path: String = PROFILE_PATH) -> Dictionary:
	return _load_preview_with_asset_bytes(profile_path, ASSET_PATH)


## Internal seam for testing raw-file rejection with disposable user:// copies.
static func _load_preview_with_asset_bytes(profile_path: String, raw_asset_path: String) -> Dictionary:
	var errors: Array[String] = []
	var result := {"ok": false, "errors": errors, "root": null, "bindings": {}}
	if not FileAccess.file_exists(profile_path):
		errors.append("construction profile is unavailable: " + profile_path)
		return result
	var profile_bytes := FileAccess.get_file_as_bytes(profile_path)
	if profile_bytes.is_empty():
		errors.append("construction profile bytes could not be read: " + profile_path)
		return result
	if _sha256(profile_bytes) != PROFILE_SHA256:
		errors.append("construction profile SHA-256 does not match the reviewed HX-700 revision")
		return result
	var profile_text := profile_bytes.get_string_from_utf8()
	var parsed := JSON.new()
	var parse_error := parsed.parse(profile_text)
	if parse_error != OK:
		errors.append("construction profile JSON is invalid: %s at line %d" % [parsed.get_error_message(), parsed.get_error_line()])
		return result
	if not parsed.data is Dictionary:
		errors.append("construction profile top level must be an object")
		return result
	var data: Dictionary = parsed.data
	_validate_profile_shape(data, errors)
	if not errors.is_empty():
		return result
	var asset_sha256: String = data.asset.sha256
	if not FileAccess.file_exists(raw_asset_path):
		errors.append("raw HX-700 GLB bytes are unavailable for SHA-256 admission: " + raw_asset_path)
		return result
	var asset_bytes := FileAccess.get_file_as_bytes(raw_asset_path)
	if asset_bytes.is_empty():
		errors.append("raw HX-700 GLB bytes could not be read: " + raw_asset_path)
		return result
	if _sha256(asset_bytes) != asset_sha256:
		errors.append("HX-700 GLB SHA-256 does not match the construction profile")
		return result
	var scene := ResourceLoader.load(ASSET_PATH) as PackedScene
	if scene == null:
		errors.append("HX-700 GLB did not import as a PackedScene: " + ASSET_PATH)
		return result
	var instance := scene.instantiate() as Node3D
	if instance == null:
		errors.append("HX-700 imported scene root must be Node3D")
		return result
	result = validate(data, instance)
	if not result.ok:
		instance.free()
		return result
	var preview_root := Node3D.new()
	preview_root.name = "hx700_mechanical_preview"
	preview_root.add_child(instance)
	result.root = preview_root
	return result


## Validates an in-memory profile against an independent imported scene instance.
## This entry point supports detached negative-control tests without asset edits.
static func validate(data: Dictionary, instance: Node3D) -> Dictionary:
	var errors: Array[String] = []
	var result := {"ok": false, "errors": errors, "root": instance, "bindings": {}}
	_validate_profile_shape(data, errors)
	if instance == null:
		errors.append("imported scene instance is null")
		return result
	var scene_nodes: Array[Node] = []
	_collect_scene_nodes(instance, scene_nodes, errors)
	var scene_by_name: Dictionary = {}
	for node: Node in scene_nodes:
		var node_name := String(node.name)
		if scene_by_name.has(node_name):
			errors.append("imported scene contains duplicate node name: " + node_name)
		else:
			scene_by_name[node_name] = node
	if not data.has("bindings") or not data.bindings is Array:
		if not errors.has("bindings must be an array"):
			errors.append("bindings must be an array")
		return result
	var binding_by_id: Dictionary = {}
	var binding_by_node: Dictionary = {}
	var role_counts: Dictionary = {}
	for index in range(data.bindings.size()):
		var binding_value: Variant = data.bindings[index]
		if not binding_value is Dictionary:
			errors.append("binding %d must be an object" % index)
			continue
		var binding: Dictionary = binding_value
		if not _has_exact_keys(binding, ["id", "role", "node", "parent_id", "rest_transform"]):
			errors.append("binding %d has missing or unknown fields" % index)
		var id_value: Variant = binding.get("id", null)
		var role_value: Variant = binding.get("role", null)
		var node_value: Variant = binding.get("node", null)
		var parent_value: Variant = binding.get("parent_id", null)
		if not id_value is String or String(id_value).is_empty():
			errors.append("binding %d id must be a non-empty string" % index)
			continue
		var binding_id := String(id_value)
		if binding_by_id.has(binding_id):
			errors.append("binding IDs must be unique: " + binding_id)
			continue
		if not role_value is String or String(role_value).is_empty():
			errors.append("binding %s role must be a non-empty string" % binding_id)
			continue
		var role := String(role_value)
		if not node_value is String or String(node_value).is_empty():
			errors.append("binding %s node must be a non-empty string" % binding_id)
			continue
		var node_name := String(node_value)
		if binding_by_node.has(node_name):
			errors.append("binding node names must be unique: " + node_name)
		else:
			binding_by_node[node_name] = binding_id
		if not parent_value is String:
			errors.append("binding %s parent_id must be a string" % binding_id)
			continue
		var parent_id := String(parent_value)
		var binding_record := {
			"id": binding_id,
			"role": role,
			"node": node_name,
			"parent_id": parent_id,
			"rest_transform": binding.get("rest_transform", null),
		}
		binding_by_id[binding_id] = binding_record
		role_counts[role] = int(role_counts.get(role, 0)) + 1
		if role not in REQUIRED_ROLE_COUNTS and role not in ["mesh", "frame"]:
			errors.append("binding %s has unsupported role: %s" % [binding_id, role])
		if REQUIRED_SEMANTIC_ROLES.has(binding_id) and REQUIRED_SEMANTIC_ROLES[binding_id] != role:
			errors.append("binding %s has role %s, expected %s" % [binding_id, role, REQUIRED_SEMANTIC_ROLES[binding_id]])
		if role == "link_endpoint" and not _valid_link_endpoint_id(binding_id):
			errors.append("link endpoint ID must be linkage.<slug>.a or linkage.<slug>.b: " + binding_id)
		if role == "mesh" and not binding_id.begins_with("visual."):
			errors.append("mesh binding ID must begin with visual.: " + binding_id)
		if role == "frame" and not binding_id.begins_with("anchor."):
			errors.append("frame binding ID must begin with anchor.: " + binding_id)
		var parsed_transform := _parse_transform(binding.get("rest_transform", null))
		if not parsed_transform.ok:
			errors.append("binding %s rest_transform %s" % [binding_id, parsed_transform.error])
	for required_id: String in REQUIRED_SEMANTIC_ROLES:
		if not binding_by_id.has(required_id):
			errors.append("required semantic binding is missing: " + required_id)
	for required_role: String in REQUIRED_ROLE_COUNTS:
		if int(role_counts.get(required_role, 0)) != int(REQUIRED_ROLE_COUNTS[required_role]):
			errors.append("role %s has cardinality %d, expected %d" % [required_role, int(role_counts.get(required_role, 0)), int(REQUIRED_ROLE_COUNTS[required_role])])
	_validate_binding_graph(binding_by_id, errors)
	if binding_by_id.size() != data.bindings.size():
		errors.append("every binding must have a valid, unique ID")
	var profile_root_id := "root"
	var root_record: Dictionary = binding_by_id.get(profile_root_id, {})
	if not root_record.is_empty() and root_record.get("role") == "root":
		if String(root_record.get("parent_id", "")) != "":
			errors.append("root binding parent_id must be blank")
	else:
		errors.append("construction profile must have the stable root binding")
	var resolved_bindings: Dictionary = {}
	for binding_id: String in binding_by_id:
		var record: Dictionary = binding_by_id[binding_id]
		var node_name := String(record.node)
		if not scene_by_name.has(node_name):
			errors.append("bound native node is missing: " + node_name)
			continue
		var native_node: Node = scene_by_name[node_name]
		if not native_node is Node3D:
			errors.append("bound native node is not Node3D: " + node_name)
			continue
		resolved_bindings[binding_id] = native_node
		_validate_node_metadata(native_node, binding_id, String(record.role), errors)
		if REQUIRED_MESH_ROLES.has(String(record.role)):
			_validate_native_mesh(native_node, binding_id, String(record.role), errors)
		var parsed_transform := _parse_transform(record.rest_transform)
		if parsed_transform.ok:
			_compare_transform(native_node.transform, parsed_transform.transform, binding_id, errors)
	var extra_nodes := scene_nodes.size() - binding_by_id.size()
	var has_wrapper: bool = extra_nodes == 1 and instance.get_child_count() == 1 \
		and instance.get_child(0) == resolved_bindings.get(profile_root_id, null) \
		and resolved_bindings.get(profile_root_id, null) != instance
	if extra_nodes < 0 or (extra_nodes > 0 and not has_wrapper):
		errors.append("imported scene must contain exactly the bound nodes, with at most one generated root wrapper")
	if has_wrapper:
		_compare_transform(instance.transform, Transform3D.IDENTITY, "generated root wrapper", errors)
	for scene_node: Node in scene_nodes:
		if not binding_by_node.has(String(scene_node.name)) and not (has_wrapper and scene_node == instance):
			errors.append("imported scene contains an unbound node: " + String(scene_node.name))
	if extra_nodes == 0 and resolved_bindings.get(profile_root_id, null) != instance:
		errors.append("profile root binding must name the imported scene root")
	for binding_id: String in binding_by_id:
		var record: Dictionary = binding_by_id[binding_id]
		var node: Node = resolved_bindings.get(binding_id, null) as Node
		if node == null:
			continue
		var parent_id := String(record.parent_id)
		if parent_id.is_empty():
			if binding_id == profile_root_id and has_wrapper and node.get_parent() != instance:
				errors.append("generated import wrapper must directly contain the profile root")
			elif binding_id == profile_root_id and not has_wrapper and node != instance:
				errors.append("profile root binding must be the imported root node")
			continue
		if not binding_by_id.has(parent_id):
			continue
		var expected_parent: Node = resolved_bindings.get(parent_id, null) as Node
		if expected_parent == null:
			continue
		if node.get_parent() != expected_parent:
			errors.append("native parent for %s does not match binding parent %s" % [record.node, binding_by_id[parent_id].node])
	_validate_linkages(data, binding_by_id, resolved_bindings, instance, errors)
	result.errors = errors
	result.bindings = resolved_bindings
	result.ok = errors.is_empty()
	return result


static func _validate_profile_shape(data: Dictionary, errors: Array[String]) -> void:
	if not _has_exact_keys(data, ["schema", "version", "profile_id", "purpose", "source", "asset", "coordinates", "bindings", "linkages"]):
		errors.append("construction profile has missing or unknown top-level fields")
	if data.get("schema") != SCHEMA:
		errors.append("construction profile schema is not supported")
	var version_value: Variant = data.get("version", null)
	if not _is_finite_number(version_value) or float(version_value) != 1.0:
		errors.append("construction profile version must be numeric 1")
	if data.get("profile_id") != PROFILE_ID:
		errors.append("construction profile ID is not supported")
	if data.get("purpose") != PURPOSE:
		errors.append("construction profile purpose must be neutral-mechanical-preview")
	if data.get("coordinates") != COORDINATES:
		errors.append("construction profile coordinates must be gltf-y-up-metres")
	var source_value: Variant = data.get("source", null)
	if not source_value is Dictionary:
		errors.append("construction profile source must be an object")
	else:
		var source: Dictionary = source_value
		if not _has_exact_keys(source, ["path", "sha256", "blender_version"]):
			errors.append("construction source has missing or unknown fields")
		if source.get("path") != SOURCE_PATH or source.get("sha256") != SOURCE_SHA256:
			errors.append("construction source identity does not match the inspected HX-700 source")
		if source.get("blender_version") != SOURCE_BLENDER_VERSION:
			errors.append("construction source Blender version does not match the inspected source")
	var asset_value: Variant = data.get("asset", null)
	if not asset_value is Dictionary:
		errors.append("construction profile asset must be an object")
	else:
		var asset: Dictionary = asset_value
		if not _has_exact_keys(asset, ["path", "sha256"]):
			errors.append("construction asset has missing or unknown fields")
		if asset.get("path") != ASSET_PATH:
			errors.append("construction asset path does not match the HX-700 articulated runtime asset")
		if not _is_sha256(asset.get("sha256", null)):
			errors.append("construction asset sha256 must be 64 lowercase hexadecimal characters")
		elif asset.get("sha256") != ASSET_SHA256:
			errors.append("construction asset SHA-256 does not match the reviewed HX-700 revision")
	if not data.get("bindings", null) is Array:
		errors.append("bindings must be an array")
	if not data.get("linkages", null) is Array:
		errors.append("linkages must be an array")


static func _validate_binding_graph(binding_by_id: Dictionary, errors: Array[String]) -> void:
	var roots: Array[String] = []
	var cycle_reported := false
	for binding_id: String in binding_by_id:
		var record: Dictionary = binding_by_id[binding_id]
		var parent_id := String(record.get("parent_id", ""))
		if parent_id.is_empty():
			roots.append(binding_id)
		elif not binding_by_id.has(parent_id):
			errors.append("binding %s references missing parent ID %s" % [binding_id, parent_id])
		var visited: Dictionary = {}
		var cursor := binding_id
		while not cursor.is_empty() and binding_by_id.has(cursor):
			if visited.has(cursor):
				if not cycle_reported:
					errors.append("binding parent graph contains a cycle through %s" % cursor)
					cycle_reported = true
				break
			visited[cursor] = true
			cursor = String(binding_by_id[cursor].get("parent_id", ""))
		if not visited.has("root"):
			errors.append("binding is disconnected from the root: " + binding_id)
	if roots.size() != 1 or (roots.size() == 1 and roots[0] != "root"):
		errors.append("binding graph must have exactly one root named root")


static func _validate_linkages(data: Dictionary, binding_by_id: Dictionary, resolved_bindings: Dictionary,
		instance: Node3D, errors: Array[String]) -> void:
	var values: Variant = data.get("linkages", null)
	if not values is Array:
		return
	if values.size() != 9:
		errors.append("construction profile must contain exactly nine rigid linkages")
	var linkage_ids: Dictionary = {}
	var endpoint_ids: Dictionary = {}
	for index in range(values.size()):
		var value: Variant = values[index]
		if not value is Dictionary:
			errors.append("linkage %d must be an object" % index)
			continue
		var linkage: Dictionary = value
		if not _has_exact_keys(linkage, ["id", "endpoint_a", "endpoint_b", "length_m"]):
			errors.append("linkage %d has missing or unknown fields" % index)
		var id_value: Variant = linkage.get("id", null)
		if not id_value is String or String(id_value).is_empty():
			errors.append("linkage %d ID must be a non-empty string" % index)
			continue
		var linkage_id := String(id_value)
		if linkage_ids.has(linkage_id):
			errors.append("linkage IDs must be unique: " + linkage_id)
		linkage_ids[linkage_id] = true
		var endpoint_a_value: Variant = linkage.get("endpoint_a", null)
		var endpoint_b_value: Variant = linkage.get("endpoint_b", null)
		if not endpoint_a_value is String or not endpoint_b_value is String:
			errors.append("linkage %s endpoints must be string IDs" % linkage_id)
			continue
		var endpoint_a := String(endpoint_a_value)
		var endpoint_b := String(endpoint_b_value)
		if endpoint_a == endpoint_b:
			errors.append("linkage %s endpoint IDs must be distinct" % linkage_id)
		if endpoint_a != linkage_id + ".a" or endpoint_b != linkage_id + ".b":
			errors.append("linkage %s must use its matching .a and .b endpoint IDs" % linkage_id)
		if not binding_by_id.has(endpoint_a) or not binding_by_id.has(endpoint_b):
			errors.append("linkage %s references a missing endpoint binding" % linkage_id)
			continue
		if String(binding_by_id[endpoint_a].role) != "link_endpoint" or String(binding_by_id[endpoint_b].role) != "link_endpoint":
			errors.append("linkage %s endpoints must have link_endpoint role" % linkage_id)
		for endpoint_id: String in [endpoint_a, endpoint_b]:
			if endpoint_ids.has(endpoint_id):
				errors.append("link endpoint is reused by multiple linkages: " + endpoint_id)
			endpoint_ids[endpoint_id] = true
		var length_value: Variant = linkage.get("length_m", null)
		if not _is_finite_number(length_value) or float(length_value) <= 0.0:
			errors.append("linkage %s length_m must be finite and positive" % linkage_id)
			continue
		var node_a: Node3D = resolved_bindings.get(endpoint_a, null) as Node3D
		var node_b: Node3D = resolved_bindings.get(endpoint_b, null) as Node3D
		if node_a == null or node_b == null:
			continue
		var position_a := _scene_position(instance, node_a)
		var position_b := _scene_position(instance, node_b)
		var actual_length := position_a.distance_to(position_b)
		if not is_finite(actual_length) or absf(actual_length - float(length_value)) > LINK_TOLERANCE_M:
			errors.append("linkage %s endpoint distance differs from its rigid length by more than %.1f micrometres" % [linkage_id, LINK_TOLERANCE_M * 1.0e6])
	var link_endpoint_count := 0
	for binding_id: String in binding_by_id:
		if String(binding_by_id[binding_id].role) == "link_endpoint":
			link_endpoint_count += 1
	if endpoint_ids.size() != 18 or endpoint_ids.size() != link_endpoint_count:
		errors.append("all 18 link_endpoint bindings must appear exactly once across the nine linkages")


static func _collect_scene_nodes(node: Node, nodes: Array[Node], errors: Array[String]) -> void:
	nodes.append(node)
	if node is Node3D:
		for component: float in _transform_values((node as Node3D).transform):
			if not is_finite(component):
				errors.append("imported node has a non-finite native transform: " + String(node.name))
				break
	if node.get_script() != null:
		errors.append("imported scene contains a scripted node: " + String(node.name))
	if node is Camera3D or node is Light3D:
		errors.append("imported scene contains a camera or light: " + String(node.name))
	if node is AnimationPlayer or node is AnimationTree:
		errors.append("imported scene contains an animation node: " + String(node.name))
	if not node is Node3D:
		errors.append("imported scene contains a non-Node3D node: " + String(node.name))
	for child: Node in node.get_children():
		_collect_scene_nodes(child, nodes, errors)


static func _validate_node_metadata(node: Node3D, binding_id: String, role: String,
		errors: Array[String]) -> void:
	var extras_value: Variant = node.get_meta("extras", null)
	if not extras_value is Dictionary:
		errors.append("native node lacks its glTF binding extras: " + String(node.name))
		return
	var extras: Dictionary = extras_value
	if not _has_exact_keys(extras, ["openrc_binding_id", "openrc_binding_role"]):
		errors.append("native node has missing or unknown glTF binding extras: " + String(node.name))
	if extras.get("openrc_binding_id") != binding_id:
		errors.append("native node metadata ID does not match binding: " + binding_id)
	if extras.get("openrc_binding_role") != role:
		errors.append("native node metadata role does not match binding: " + binding_id)


static func _validate_native_mesh(node: Node3D, binding_id: String, role: String,
		errors: Array[String]) -> void:
	if not node is MeshInstance3D:
		errors.append("binding role %s must resolve to MeshInstance3D: %s" % [role, binding_id])
		return
	var mesh_node := node as MeshInstance3D
	if mesh_node.mesh == null:
		errors.append("mesh binding has no Mesh resource: " + binding_id)
		return
	var mesh: Mesh = mesh_node.mesh
	if mesh.get_surface_count() <= 0:
		errors.append("mesh binding has no surfaces: " + binding_id)
		return
	for surface_index in range(mesh.get_surface_count()):
		var material := mesh_node.get_active_material(surface_index)
		if material == null:
			errors.append("mesh surface has no active material: %s[%d]" % [binding_id, surface_index])
			continue
		if not material is BaseMaterial3D:
			errors.append("mesh surface material must be BaseMaterial3D: %s[%d]" % [binding_id, surface_index])
			continue
		_validate_material_textures(material as BaseMaterial3D, binding_id, surface_index, errors)


static func _validate_material_textures(material: BaseMaterial3D, binding_id: String,
		surface_index: int, errors: Array[String]) -> void:
	var required_surfaces: Dictionary = REQUIRED_TEXTURE_SLOTS.get(binding_id, {})
	var required_slots: Array = required_surfaces.get(surface_index, [])
	for slot_value: Variant in required_slots:
		var slot_name := String(slot_value)
		var required_texture: Variant = material.get(slot_name)
		if required_texture == null:
			errors.append("required material texture is missing: %s[%d].%s" % [binding_id, surface_index, slot_name])
		elif not required_texture is Texture2D:
			errors.append("required material texture is not Texture2D: %s[%d].%s" % [binding_id, surface_index, slot_name])
	for property_info: Dictionary in material.get_property_list():
		var property_name := String(property_info.get("name", ""))
		if not property_name.ends_with("_texture"):
			continue
		if int(property_info.get("type", TYPE_NIL)) != TYPE_OBJECT:
			continue
		var texture_value: Variant = material.get(property_name)
		if texture_value == null:
			continue
		if not texture_value is Texture2D:
			errors.append("material texture slot is not Texture2D: %s[%d].%s" % [binding_id, surface_index, property_name])
			continue
		var texture := texture_value as Texture2D
		if texture.get_width() <= 0 or texture.get_height() <= 0:
			errors.append("material texture has invalid dimensions: %s[%d].%s" % [binding_id, surface_index, property_name])


static func _compare_transform(actual: Transform3D, expected: Transform3D, binding_id: String,
		errors: Array[String]) -> void:
	var actual_values := _transform_values(actual)
	var expected_values := _transform_values(expected)
	for index in range(12):
		if not is_finite(actual_values[index]) or not is_finite(expected_values[index]):
			errors.append("native rest transform contains a non-finite component for binding %s" % binding_id)
			return
		if absf(actual_values[index] - expected_values[index]) > TRANSFORM_TOLERANCE:
			errors.append("native rest transform differs from binding %s by more than %s" % [binding_id, str(TRANSFORM_TOLERANCE)])
			return


static func _parse_transform(value: Variant) -> Dictionary:
	if not value is Array or value.size() != 12:
		return {"ok": false, "error": "must contain exactly twelve finite numbers"}
	var values: Array[float] = []
	for item: Variant in value:
		if not _is_finite_number(item):
			return {"ok": false, "error": "must contain exactly twelve finite numbers"}
		values.append(float(item))
	var basis := Basis(
		Vector3(values[0], values[1], values[2]),
		Vector3(values[3], values[4], values[5]),
		Vector3(values[6], values[7], values[8]))
	var determinant := basis.determinant()
	if not is_finite(determinant) or absf(determinant) <= 1.0e-12:
		return {"ok": false, "error": "must have an invertible basis"}
	var transform := Transform3D(basis, Vector3(values[9], values[10], values[11]))
	for component: float in _transform_values(transform):
		if not is_finite(component):
			return {"ok": false, "error": "must remain finite at native Vector3 precision"}
	return {"ok": true, "transform": transform}


static func _transform_values(value: Transform3D) -> Array[float]:
	return [
		value.basis.x.x, value.basis.x.y, value.basis.x.z,
		value.basis.y.x, value.basis.y.y, value.basis.y.z,
		value.basis.z.x, value.basis.z.y, value.basis.z.z,
		value.origin.x, value.origin.y, value.origin.z,
	]


static func _scene_position(scene_root: Node3D, node: Node3D) -> Vector3:
	var accumulated := Transform3D.IDENTITY
	var current: Node = node
	while current != null:
		if not current is Node3D:
			return Vector3(NAN, NAN, NAN)
		accumulated = (current as Node3D).transform * accumulated
		if current == scene_root:
			return accumulated.origin
		current = current.get_parent()
	return Vector3(NAN, NAN, NAN)


static func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in expected:
		if not value.has(String(key)):
			return false
	return true


static func _valid_link_endpoint_id(binding_id: String) -> bool:
	if not binding_id.begins_with("linkage."):
		return false
	if not binding_id.ends_with(".a") and not binding_id.ends_with(".b"):
		return false
	var slug_end := binding_id.rfind(".")
	return slug_end > "linkage.".length() and binding_id.count(".") == 2


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


static func _is_sha256(value: Variant) -> bool:
	if not value is String:
		return false
	var digest := String(value)
	if digest.length() != 64 or digest != digest.to_lower():
		return false
	for character: String in digest:
		if character not in "0123456789abcdef":
			return false
	return true


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode().to_lower()


