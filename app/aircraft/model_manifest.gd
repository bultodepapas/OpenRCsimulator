extends RefCounted

const ADAPTERS := ["euler_hinges", "axis_hinges", "imported_glb"]
const CONTROL_ROLES := ["aileron_left", "aileron_right", "elevator", "rudder", "flap_left", "flap_right"]
const GEAR_ROLES := ["left", "right", "tail", "steering", "nose"]
const DEPENDENCY_ROLES := ["builder", "generated_geometry", "imported_asset", "crash_metadata", "script_dependency", "resource_dependency"]


static func validate(manifest: Dictionary, expected_family_id := "") -> Dictionary:
	var errors := PackedStringArray()
	var diagnostics: Array[Dictionary] = []
	_check_fields(manifest, ["schema", "version", "family_id", "builder", "surface_method", "datum", "coordinates", "root_node", "source_registry", "geometry", "asset", "bindings", "authoring_sources", "dependencies"], "$", errors, diagnostics)
	if manifest.get("schema") != "openrc-aircraft-model": _fail(errors, diagnostics, "MODEL_SCHEMA_UNKNOWN", "$.schema", "expected openrc-aircraft-model")
	if typeof(manifest.get("version")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(manifest.get("version", -1))) or float(manifest.get("version", -1)) != 1.0: _fail(errors, diagnostics, "MODEL_VERSION_UNSUPPORTED", "$.version", "only model manifest version 1 is supported")
	var family_id := str(manifest.get("family_id", ""))
	if not _is_slug(family_id): _fail(errors, diagnostics, "MODEL_FAMILY_INVALID", "$.family_id", "family_id must be a lowercase stable slug")
	if not expected_family_id.is_empty() and family_id != expected_family_id: _fail(errors, diagnostics, "MODEL_FAMILY_MISMATCH", "$.family_id", "manifest family does not match requested visual family")
	if manifest.get("surface_method") != "apply_surfaces": _fail(errors, diagnostics, "MODEL_SURFACE_METHOD_UNSUPPORTED", "$.surface_method", "only apply_surfaces is supported")
	if manifest.get("root_node") != "airplane": _fail(errors, diagnostics, "MODEL_ROOT_UNSUPPORTED", "$.root_node", "public model root must be named airplane")

	var builder: Variant = manifest.get("builder", {})
	if _check_fields(builder, ["script", "adapter"], "$.builder", errors, diagnostics):
		var builder_path := str(builder.get("script", ""))
		if not _resource_path(builder_path, ["aircraft"]): _fail(errors, diagnostics, "MODEL_BUILDER_PATH_INVALID", "$.builder.script", "builder must be a safe bundled res://aircraft path")
		elif not builder_path.ends_with("_model.gd"): _fail(errors, diagnostics, "MODEL_BUILDER_UNTRUSTED", "$.builder.script", "builder must be a registered bundled model script")
		if not ADAPTERS.has(builder.get("adapter")): _fail(errors, diagnostics, "MODEL_ADAPTER_UNKNOWN", "$.builder.adapter", "unknown model adapter")

	var datum: Variant = manifest.get("datum", {})
	if _check_fields(datum, ["model_z_le", "model_y_thrust"], "$.datum", errors, diagnostics):
		for key in ["model_z_le", "model_y_thrust"]: _check_finite(datum.get(key), "$.datum." + key, errors, diagnostics)
	var coordinates: Variant = manifest.get("coordinates", {})
	if _check_fields(coordinates, ["units", "nose", "right", "up"], "$.coordinates", errors, diagnostics):
		if coordinates.get("units") != "m" or coordinates.get("nose") != "-Z" or coordinates.get("right") != "+X" or coordinates.get("up") != "+Y":
			_fail(errors, diagnostics, "MODEL_COORDINATES_UNSUPPORTED", "$.coordinates", "model coordinates must be metres, +X right, +Y up, -Z nose")

	var source_registry: Variant = manifest.get("source_registry", {})
	_check_source(source_registry, "$.source_registry", errors, diagnostics)
	var geometry: Variant = manifest.get("geometry", {})
	if _check_fields(geometry, ["script", "source", "revision", "datum_source"], "$.geometry", errors, diagnostics):
		var geometry_path := str(geometry.get("script", ""))
		if not _resource_path(geometry_path, ["aircraft"]) or not geometry_path.ends_with("_geometry.gd"):
			_fail(errors, diagnostics, "MODEL_GEOMETRY_PATH_INVALID", "$.geometry.script", "geometry must be a safe generated res://aircraft/*_geometry.gd resource")
		_check_source(geometry.get("source", {}), "$.geometry.source", errors, diagnostics)
		if not _nonempty(geometry.get("revision")): _fail(errors, diagnostics, "MODEL_REVISION_INVALID", "$.geometry.revision", "geometry revision must be non-empty")
		var datum_source: Variant = geometry.get("datum_source", {})
		if _check_fields(datum_source, ["model_z_le", "model_y_thrust"], "$.geometry.datum_source", errors, diagnostics):
			for key in ["model_z_le", "model_y_thrust"]: _check_selector(datum_source.get(key), "$.geometry.datum_source." + key, errors, diagnostics)

	var asset: Variant = manifest.get("asset", {})
	var asset_kind := ""
	if typeof(asset) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_ASSET_INVALID", "$.asset", "asset must be an object")
	else:
		asset_kind = str(asset.get("kind", ""))
		if asset_kind == "procedural":
			_check_fields(asset, ["kind", "identity", "revision"], "$.asset", errors, diagnostics)
		elif asset_kind == "imported_glb":
			_check_fields(asset, ["kind", "identity", "revision", "path", "sha256"], "$.asset", errors, diagnostics)
			var asset_path := str(asset.get("path", ""))
			if not _resource_path(asset_path, ["assets", "aircraft"]) or not asset_path.ends_with(".glb"):
				_fail(errors, diagnostics, "MODEL_ASSET_PATH_INVALID", "$.asset.path", "imported asset must be a safe aircraft GLB resource")
			_check_sha(asset.get("sha256"), "$.asset.sha256", errors, diagnostics)
		else:
			_fail(errors, diagnostics, "MODEL_ASSET_KIND_UNKNOWN", "$.asset.kind", "asset kind must be procedural or imported_glb")
		if typeof(asset) == TYPE_DICTIONARY:
			if not _nonempty(asset.get("identity")): _fail(errors, diagnostics, "MODEL_ASSET_IDENTITY_INVALID", "$.asset.identity", "asset identity must be non-empty")
			if not _nonempty(asset.get("revision")): _fail(errors, diagnostics, "MODEL_REVISION_INVALID", "$.asset.revision", "asset revision must be non-empty")
	var adapter := str(builder.get("adapter", "")) if typeof(builder) == TYPE_DICTIONARY else ""
	if asset_kind == "imported_glb" and adapter != "imported_glb": _fail(errors, diagnostics, "MODEL_ADAPTER_ASSET_MISMATCH", "$.builder.adapter", "imported GLB assets require imported_glb adapter")
	if asset_kind == "procedural" and adapter == "imported_glb": _fail(errors, diagnostics, "MODEL_ADAPTER_ASSET_MISMATCH", "$.builder.adapter", "imported_glb adapter requires an imported asset")

	var bindings: Variant = manifest.get("bindings", {})
	if _check_fields(bindings, ["controls", "rotor", "gear", "crash"], "$.bindings", errors, diagnostics):
		_check_controls(bindings.get("controls", {}), errors, diagnostics)
		_check_rotor(bindings.get("rotor", {}), errors, diagnostics)
		_check_gear(bindings.get("gear", {}), errors, diagnostics)
		_check_crash(bindings.get("crash", {}), errors, diagnostics)

	_check_sources(manifest.get("authoring_sources", []), "$.authoring_sources", errors, diagnostics)
	_check_dependencies(manifest.get("dependencies", []), manifest, errors, diagnostics)
	var ok := errors.is_empty()
	return {"ok": ok, "errors": errors, "diagnostics": diagnostics, "manifest": manifest.duplicate(true) if ok else {}}


static func _check_controls(value: Variant, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_CONTROLS_INVALID", "$.bindings.controls", "controls must be an object")
		return
	var controls: Dictionary = value
	var seen_keys: Dictionary = {}
	var seen_nodes: Dictionary = {}
	for required in ["aileron_left", "aileron_right", "elevator", "rudder"]:
		if not controls.has(required): _fail(errors, diagnostics, "MODEL_CONTROL_MISSING", "$.bindings.controls." + required, "required stable control role is missing")
	for role_variant in controls.keys():
		var role := str(role_variant)
		var path := "$.bindings.controls." + role
		if not CONTROL_ROLES.has(role):
			_fail(errors, diagnostics, "MODEL_CONTROL_ROLE_UNKNOWN", path, "unknown stable control role")
			continue
		var binding: Variant = controls[role_variant]
		if not _check_fields(binding, ["visual_only", "hinges"], path, errors, diagnostics): continue
		if typeof(binding.get("visual_only")) != TYPE_BOOL: _fail(errors, diagnostics, "MODEL_CONTROL_VISUAL_ONLY_INVALID", path + ".visual_only", "visual_only must be boolean")
		var hinges: Variant = binding.get("hinges")
		if typeof(hinges) != TYPE_ARRAY or hinges.is_empty():
			_fail(errors, diagnostics, "MODEL_CONTROL_HINGES_INVALID", path + ".hinges", "control role must bind at least one hinge")
			continue
		for index in hinges.size():
			var hinge_path := "%s.hinges[%d]" % [path, index]
			var hinge: Variant = hinges[index]
			if not _check_fields(hinge, ["key", "node", "source", "geometry_ref"], hinge_path, errors, diagnostics): continue
			var hinge_key := str(hinge.get("key", ""))
			var node_name := str(hinge.get("node", ""))
			if not _is_key(hinge_key): _fail(errors, diagnostics, "MODEL_CONTROL_KEY_INVALID", hinge_path + ".key", "hinge key must be a stable lowercase identifier")
			if not node_name.ends_with("_hinge") or not _is_node_name(node_name): _fail(errors, diagnostics, "MODEL_CONTROL_NODE_INVALID", hinge_path + ".node", "control node must retain a safe public *_hinge name")
			if seen_keys.has(hinge_key): _fail(errors, diagnostics, "MODEL_CONTROL_KEY_DUPLICATE", hinge_path + ".key", "hinge key may be bound only once")
			if seen_nodes.has(node_name): _fail(errors, diagnostics, "MODEL_CONTROL_NODE_DUPLICATE", hinge_path + ".node", "hinge node may be bound only once")
			seen_keys[hinge_key] = true
			seen_nodes[node_name] = true
			if hinge.get("source") not in ["builder", "geometry_articulation"]: _fail(errors, diagnostics, "MODEL_CONTROL_SOURCE_UNKNOWN", hinge_path + ".source", "unknown control binding source")
			var ref := str(hinge.get("geometry_ref", ""))
			if hinge.get("source") == "geometry_articulation":
				if not _dotted_ref(ref): _fail(errors, diagnostics, "MODEL_GEOMETRY_REF_INVALID", hinge_path + ".geometry_ref", "source articulation reference is invalid")
			elif not ref.is_empty():
				_fail(errors, diagnostics, "MODEL_GEOMETRY_REF_INVALID", hinge_path + ".geometry_ref", "builder-sourced controls must not duplicate geometry refs")


static func _check_rotor(value: Variant, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	var path := "$.bindings.rotor"
	if not _check_fields(value, ["present", "node", "spin_node", "authored_diameter_m", "source", "geometry_ref"], path, errors, diagnostics): return
	if typeof(value.get("present")) != TYPE_BOOL: _fail(errors, diagnostics, "MODEL_ROTOR_INVALID", path + ".present", "present must be boolean")
	if value.get("node") != "propeller": _fail(errors, diagnostics, "MODEL_ROTOR_NODE_INVALID", path + ".node", "the stable propeller node name must be propeller")
	if not (value.get("spin_node") is String): _fail(errors, diagnostics, "MODEL_ROTOR_INVALID", path + ".spin_node", "spin_node must be a string")
	var present := bool(value.get("present", false))
	var diameter: Variant = value.get("authored_diameter_m")
	_check_finite(diameter, path + ".authored_diameter_m", errors, diagnostics)
	if typeof(diameter) == TYPE_FLOAT or typeof(diameter) == TYPE_INT:
		if float(diameter) < 0.0 or (present and float(diameter) <= 0.0) or (not present and float(diameter) != 0.0):
			_fail(errors, diagnostics, "MODEL_ROTOR_DIAMETER_INVALID", path + ".authored_diameter_m", "diameter must be positive for a rotor and exactly zero when absent")
	var source := str(value.get("source", ""))
	var ref := str(value.get("geometry_ref", ""))
	if present and source not in ["builder", "geometry_articulation"]: _fail(errors, diagnostics, "MODEL_ROTOR_SOURCE_INVALID", path + ".source", "present rotor needs a supported diameter source")
	if not present and source != "none": _fail(errors, diagnostics, "MODEL_ROTOR_SOURCE_INVALID", path + ".source", "absent rotor must use source none")
	if (source == "geometry_articulation") != _dotted_ref(ref): _fail(errors, diagnostics, "MODEL_GEOMETRY_REF_INVALID", path + ".geometry_ref", "geometry articulation rotor needs exactly one valid source reference")
	if source != "geometry_articulation" and not ref.is_empty(): _fail(errors, diagnostics, "MODEL_GEOMETRY_REF_INVALID", path + ".geometry_ref", "non-geometry rotor must not duplicate geometry refs")


static func _check_gear(value: Variant, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	var path := "$.bindings.gear"
	if not _check_fields(value, ["keys"], path, errors, diagnostics): return
	var keys: Variant = value.get("keys", {})
	if typeof(keys) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_GEAR_INVALID", path + ".keys", "gear keys must be an object")
		return
	var values: Array[String] = []
	for role_variant in keys.keys():
		var role := str(role_variant)
		var key := str(keys[role_variant])
		if not GEAR_ROLES.has(role): _fail(errors, diagnostics, "MODEL_GEAR_ROLE_UNKNOWN", path + ".keys." + role, "unknown stable gear role")
		if not _nonempty(key): _fail(errors, diagnostics, "MODEL_GEAR_KEY_INVALID", path + ".keys." + role, "gear builder key must be non-empty")
		if values.has(key): _fail(errors, diagnostics, "MODEL_GEAR_KEY_DUPLICATE", path + ".keys." + role, "gear roles must bind distinct builder keys")
		values.append(key)


static func _check_crash(value: Variant, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	var path := "$.bindings.crash"
	if typeof(value) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_CRASH_INVALID", path, "crash binding must be an object")
		return
	var provider := str(value.get("provider", ""))
	if provider in ["none", "gltf_extras"]:
		_check_fields(value, ["provider", "metadata_script", "asset_node"], path, errors, diagnostics)
		if value.get("metadata_script") != "" or value.get("asset_node") != "": _fail(errors, diagnostics, "MODEL_CRASH_INVALID", path, "provider %s must not declare separate crash references" % provider)
	elif provider == "generated_triangle_map":
		_check_fields(value, ["provider", "metadata_script", "asset_node"], path, errors, diagnostics)
		if not _resource_path(str(value.get("metadata_script", "")), ["aircraft"]): _fail(errors, diagnostics, "MODEL_CRASH_PATH_INVALID", path + ".metadata_script", "crash metadata must be a safe bundled aircraft script")
		if not _nonempty(value.get("asset_node")): _fail(errors, diagnostics, "MODEL_CRASH_NODE_INVALID", path + ".asset_node", "crash asset node must be non-empty")
	else:
		_fail(errors, diagnostics, "MODEL_CRASH_PROVIDER_UNKNOWN", path + ".provider", "unsupported crash metadata provider")


static func _check_source(value: Variant, path: String, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	if not _check_fields(value, ["path", "sha256", "hash_mode"], path, errors, diagnostics): return
	if not _authoring_path(str(value.get("path", ""))): _fail(errors, diagnostics, "MODEL_SOURCE_PATH_INVALID", path + ".path", "authoring source must be under assets/aircraft with a safe relative path")
	_check_sha(value.get("sha256"), path + ".sha256", errors, diagnostics)
	if value.get("hash_mode") not in ["lf_text", "raw"]: _fail(errors, diagnostics, "MODEL_HASH_MODE_UNKNOWN", path + ".hash_mode", "hash_mode must be lf_text or raw")


static func _check_sources(value: Variant, path: String, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_ARRAY:
		_fail(errors, diagnostics, "MODEL_SOURCES_INVALID", path, "authoring_sources must be an array")
		return
	if value.is_empty(): _fail(errors, diagnostics, "MODEL_SOURCES_EMPTY", path, "at least the generated geometry source must be recorded")
	var seen := {}
	for index in value.size():
		var entry: Variant = value[index]
		var item_path := "%s[%d]" % [path, index]
		if not _check_fields(entry, ["path", "sha256", "hash_mode", "role"], item_path, errors, diagnostics): continue
		_check_source({"path": entry.get("path"), "sha256": entry.get("sha256"), "hash_mode": entry.get("hash_mode")}, item_path, errors, diagnostics)
		if not _nonempty(entry.get("role")): _fail(errors, diagnostics, "MODEL_SOURCE_ROLE_INVALID", item_path + ".role", "authoring source role must be non-empty")
		var source_path := str(entry.get("path", ""))
		if seen.has(source_path): _fail(errors, diagnostics, "MODEL_SOURCE_DUPLICATE", item_path + ".path", "authoring source paths must be unique")
		seen[source_path] = true
	var geometry: Dictionary = value[0] if not value.is_empty() and typeof(value[0]) == TYPE_DICTIONARY else {}
	if not geometry.is_empty() and geometry.get("role") != "geometry": _fail(errors, diagnostics, "MODEL_GEOMETRY_SOURCE_ROLE_INVALID", path + "[0].role", "first authoring source must be the geometry source")


static func _check_dependencies(value: Variant, manifest: Dictionary, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	var path := "$.dependencies"
	if typeof(value) != TYPE_ARRAY:
		_fail(errors, diagnostics, "MODEL_DEPENDENCIES_INVALID", path, "dependencies must be an array")
		return
	if value.size() < 2: _fail(errors, diagnostics, "MODEL_DEPENDENCIES_EMPTY", path, "builder and generated geometry dependencies are required")
	var paths := {}
	var roles := {}
	for index in value.size():
		var entry: Variant = value[index]
		var item_path := "%s[%d]" % [path, index]
		if not _check_fields(entry, ["path", "sha256", "hash_mode", "role"], item_path, errors, diagnostics): continue
		var dependency_path := str(entry.get("path", ""))
		if not _resource_path(dependency_path, ["aircraft", "assets", "render"]): _fail(errors, diagnostics, "MODEL_DEPENDENCY_PATH_INVALID", item_path + ".path", "dependency must be a safe bundled res:// path")
		_check_sha(entry.get("sha256"), item_path + ".sha256", errors, diagnostics)
		if entry.get("hash_mode") not in ["lf_text", "raw"]: _fail(errors, diagnostics, "MODEL_HASH_MODE_UNKNOWN", item_path + ".hash_mode", "hash_mode must be lf_text or raw")
		var role := str(entry.get("role", ""))
		if not DEPENDENCY_ROLES.has(role): _fail(errors, diagnostics, "MODEL_DEPENDENCY_ROLE_UNKNOWN", item_path + ".role", "unknown dependency role")
		if paths.has(dependency_path): _fail(errors, diagnostics, "MODEL_DEPENDENCY_DUPLICATE", item_path + ".path", "dependency paths must be unique")
		paths[dependency_path] = true
		roles[dependency_path] = role
	var builder: Dictionary = manifest.get("builder", {})
	var geometry: Dictionary = manifest.get("geometry", {})
	_expect_dependency(roles, str(builder.get("script", "")), "builder", errors, diagnostics)
	_expect_dependency(roles, str(geometry.get("script", "")), "generated_geometry", errors, diagnostics)
	var asset: Dictionary = manifest.get("asset", {})
	if asset.get("kind") == "imported_glb": _expect_dependency(roles, str(asset.get("path", "")), "imported_asset", errors, diagnostics)
	var crash: Dictionary = {}
	var manifest_bindings: Variant = manifest.get("bindings", {})
	if typeof(manifest_bindings) == TYPE_DICTIONARY and typeof(manifest_bindings.get("crash", {})) == TYPE_DICTIONARY:
		crash = manifest_bindings.get("crash", {})
	if crash.get("provider") == "generated_triangle_map": _expect_dependency(roles, str(crash.get("metadata_script", "")), "crash_metadata", errors, diagnostics)
	if crash.get("provider") == "gltf_extras" and asset.get("kind") != "imported_glb":
		_fail(errors, diagnostics, "MODEL_CRASH_ASSET_INVALID", "$.bindings.crash.provider", "gltf_extras requires an imported_glb asset")


static func _expect_dependency(roles: Dictionary, path: String, role: String, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	if not roles.has(path): _fail(errors, diagnostics, "MODEL_DEPENDENCY_MISSING", "$.dependencies", "missing required %s dependency %s" % [role, path])
	elif roles[path] != role: _fail(errors, diagnostics, "MODEL_DEPENDENCY_ROLE_MISMATCH", "$.dependencies", "dependency %s must have role %s" % [path, role])


static func _check_selector(value: Variant, path: String, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_SELECTOR_INVALID", path, "datum selector must be an object")
		return
	var has_path: bool = value.has("path")
	var has_value: bool = value.has("value")
	if has_path == has_value:
		_fail(errors, diagnostics, "MODEL_SELECTOR_INVALID", path, "selector needs exactly one of path or value")
		return
	if has_path:
		_check_fields(value, ["path"] if not value.has("scale") else ["path", "scale"], path, errors, diagnostics)
		if not _dotted_ref(str(value.get("path", ""))): _fail(errors, diagnostics, "MODEL_SELECTOR_INVALID", path + ".path", "selector path must be a dotted source reference")
		if value.has("scale"): _check_finite(value.get("scale"), path + ".scale", errors, diagnostics)
	else:
		_check_fields(value, ["value"], path, errors, diagnostics)
		_check_finite(value.get("value"), path + ".value", errors, diagnostics)


static func _check_fields(value: Variant, fields: Array, path: String, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_OBJECT_INVALID", path, "expected object")
		return false
	var object: Dictionary = value
	for field in fields:
		if not object.has(field): _fail(errors, diagnostics, "MODEL_FIELD_MISSING", path + "." + field, "required field is missing")
	for field_variant in object.keys():
		var field := str(field_variant)
		if not fields.has(field): _fail(errors, diagnostics, "MODEL_FIELD_UNKNOWN", path + "." + field, "unknown field is not supported")
	return true


static func _check_finite(value: Variant, path: String, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)):
		_fail(errors, diagnostics, "MODEL_NUMBER_INVALID", path, "expected a finite number")


static func _check_sha(value: Variant, path: String, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_STRING or str(value).length() != 64:
		_fail(errors, diagnostics, "MODEL_HASH_INVALID", path, "expected lowercase SHA-256")
		return
	for character in str(value):
		if not "0123456789abcdef".contains(character):
			_fail(errors, diagnostics, "MODEL_HASH_INVALID", path, "expected lowercase SHA-256")
			return


static func _resource_path(value: String, roots: Array[String]) -> bool:
	if not value.begins_with("res://") or value.contains("\\") or value.substr(6).contains(":") or value.contains(" "):
		return false
	var tail := value.substr(6)
	var parts := tail.split("/", false)
	if parts.is_empty() or parts.size() != tail.split("/", true).size(): return false
	for part in parts:
		if part.is_empty() or part == "." or part == "..": return false
		for character in part:
			if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.@+-".contains(character): return false
	if not roots.has(parts[0]): return false
	if parts[0] == "assets" and (parts.size() < 3 or parts[1] != "aircraft"): return false
	if parts[0] == "render" and (parts.size() < 3 or parts[1] != "crash"): return false
	return true


static func _authoring_path(value: String) -> bool:
	if value.contains("\\") or value.contains(":") or value.begins_with("/"): return false
	var parts := value.split("/", false)
	if parts.size() < 3 or parts.size() != value.split("/", true).size() or parts[0] != "assets" or parts[1] != "aircraft": return false
	for part in parts:
		if part.is_empty() or part == "." or part == "..": return false
		for character in part:
			if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-".contains(character): return false
	return true


static func _dotted_ref(value: String) -> bool:
	if value.is_empty() or value.contains("/") or value.contains("\\"): return false
	for part in value.split(".", true):
		if part.is_empty(): return false
		for character in part:
			if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".contains(character): return false
	return true


static func _is_slug(value: String) -> bool:
	if value.is_empty() or value.begins_with("-") or value.ends_with("-") or value.contains("--"): return false
	for character in value:
		if not "abcdefghijklmnopqrstuvwxyz0123456789-".contains(character): return false
	return true


static func _is_key(value: String) -> bool:
	if value.is_empty() or not "abcdefghijklmnopqrstuvwxyz".contains(value.substr(0, 1)): return false
	for character in value:
		if not "abcdefghijklmnopqrstuvwxyz0123456789_".contains(character): return false
	return true


static func _is_node_name(value: String) -> bool:
	if value.is_empty(): return false
	for character in value:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".contains(character): return false
	return true


static func _nonempty(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not str(value).strip_edges().is_empty()


static func _fail(errors: PackedStringArray, diagnostics: Array[Dictionary], code: String, path: String, message: String) -> void:
	errors.append(message)
	diagnostics.append({"code": code, "path": path, "message": message})
