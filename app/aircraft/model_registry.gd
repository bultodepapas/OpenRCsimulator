extends RefCounted

const Manifest := preload("res://aircraft/model_manifest.gd")
const MANIFEST_ROOT := "res://data/aircraft_models/"
const PACKAGE_PROOF_PATH := "res://data/aircraft_models/package_proofs.json"
const PACKAGE_PROOF_FORMAT := "openrc-aircraft-model-package v1"
const PACKAGE_PROOF_ROOT := "res://data/aircraft_models/proofs/"
const TEXT_HASH := "lf_text"
const BINARY_HASH := "raw"
const CRASH_SECTIONS := ["core", "wing_left", "wing_right", "wing_center", "engine", "propeller",
	"horizontal_tail", "vertical_tail", "gear", "canopy"]


static func describe(family_id: String) -> Dictionary:
	if not Manifest._is_slug(family_id):
		return _failure("MODEL_FAMILY_INVALID", "$.family_id", "requested visual family must be a lowercase stable slug")
	var path := MANIFEST_ROOT + family_id + ".json"
	if not FileAccess.file_exists(path):
		return _failure("MODEL_MANIFEST_MISSING", path, "no checked-in model manifest exists for this visual family")
	var source_bytes := FileAccess.get_file_as_bytes(path)
	var parsed: Variant = JSON.parse_string(source_bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure("MODEL_MANIFEST_PARSE", path, "model manifest must contain a JSON object")
	var result: Dictionary = validate_manifest(parsed, family_id)
	if result.ok:
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(source_bytes)
		result.manifest_sha256 = context.finish().hex_encode()
	return result


static func validate_manifest(manifest: Dictionary, expected_family_id := "") -> Dictionary:
	var structural: Dictionary = Manifest.validate(manifest, expected_family_id)
	if not structural.ok:
		return structural
	var errors := PackedStringArray()
	var diagnostics: Array[Dictionary] = []
	var accepted: Dictionary = structural.manifest
	var package_result := _read_package_proofs()
	if not package_result.ok:
		return package_result
	var proofs: Dictionary = package_result.files
	_check_authoring_record(accepted.get("source_registry", {}), "$.source_registry", proofs, errors, diagnostics)
	var geometry: Dictionary = accepted.get("geometry", {})
	_check_authoring_record(geometry.get("source", {}), "$.geometry.source", proofs, errors, diagnostics)
	var geometry_source: Dictionary = geometry.get("source", {})
	for index in accepted.get("authoring_sources", []).size():
		var source: Dictionary = accepted.authoring_sources[index]
		_check_authoring_record(source, "$.authoring_sources[%d]" % index, proofs, errors, diagnostics)
		if index == 0 and (source.get("path") != geometry_source.get("path") or source.get("sha256") != geometry_source.get("sha256")):
			_fail(errors, diagnostics, "MODEL_GEOMETRY_SOURCE_MISMATCH", "$.authoring_sources[0]", "first authoring source must pin geometry.source")
	_validate_dependency_closure(accepted, proofs, errors, diagnostics)
	var ok := errors.is_empty()
	return {"ok": ok, "errors": errors, "diagnostics": diagnostics, "manifest": accepted if ok else {}}


## F4U-16: the livery a build will use, from a manifest describe() accepted. An empty id selects the default asset,
## which describe() verified; any other livery's GLB and import sidecar are verified here, on use, so describing a
## model never hashes every livery. Returns {ok, errors, diagnostics, livery = {id, label, path, sha256}}.
static func livery(manifest: Dictionary, livery_id := "") -> Dictionary:
	var asset: Dictionary = manifest.get("asset", {})
	var options: Array = manifest.get("liveries", [])
	if options.is_empty():
		if not livery_id.is_empty():
			return _failure("MODEL_LIVERY_UNKNOWN", "$.liveries", "this model has no selectable liveries")
		return {"ok": true, "errors": PackedStringArray(), "diagnostics": [], "livery": {
			"id": "", "label": "", "path": str(asset.get("path", "")), "sha256": str(asset.get("sha256", ""))}}
	var index := 0 if livery_id.is_empty() else -1
	for i in options.size():
		if options[i].get("id") == livery_id: index = i
	if index < 0:
		return _failure("MODEL_LIVERY_UNKNOWN", "$.liveries", "unknown livery: " + livery_id)
	var record: Dictionary = options[index]
	var selected := {"id": str(record.id), "label": str(record.label), "path": str(record.path), "sha256": str(record.sha256)}
	var errors := PackedStringArray()
	var diagnostics: Array[Dictionary] = []
	if index > 0:
		var package_result := _read_package_proofs()
		if not package_result.ok:
			return package_result
		var item := "$.liveries[%d]" % index
		_check_resource_record({"path": selected.path, "sha256": selected.sha256, "hash_mode": BINARY_HASH}, item, package_result.files, errors, diagnostics)
		_check_resource_record({"path": selected.path + ".import", "sha256": str(record.import_sha256), "hash_mode": TEXT_HASH}, item + ".import", package_result.files, errors, diagnostics)
	var ok := errors.is_empty()
	return {"ok": ok, "errors": errors, "diagnostics": diagnostics, "livery": selected if ok else {}}


static func validate_derived(manifest: Dictionary, built: Dictionary) -> Dictionary:
	var structural: Dictionary = Manifest.validate(manifest)
	if not structural.ok:
		return structural
	var accepted: Dictionary = structural.manifest
	var errors := PackedStringArray()
	var diagnostics: Array[Dictionary] = []
	var root: Variant = built.get("root")
	if not (root is Node3D):
		_fail(errors, diagnostics, "MODEL_BUILD_ROOT_MISSING", "$.root", "builder result must contain the public Node3D root")
		return _derived_result(false, errors, diagnostics, accepted)
	if root.name != accepted.root_node:
		_fail(errors, diagnostics, "MODEL_BUILD_ROOT_NAME", "$.root.name", "builder root does not use the public name airplane")
	var hinges: Variant = built.get("hinges", {})
	if typeof(hinges) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_BUILD_HINGES_MISSING", "$.hinges", "builder result must contain a hinge dictionary")
	else:
		_check_derived_hinges(accepted, hinges, root, errors, diagnostics)
	_check_derived_rotor(accepted, built, root, errors, diagnostics)
	_check_derived_gear(accepted, built, root, errors, diagnostics)
	_check_derived_asset(accepted, root, errors, diagnostics)
	_check_derived_crash(accepted, root, errors, diagnostics)
	return _derived_result(errors.is_empty(), errors, diagnostics, accepted)


static func _check_derived_hinges(manifest: Dictionary, hinges: Dictionary, root: Node3D, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	var adapter := str(manifest.builder.adapter)
	for role_variant in manifest.bindings.controls.keys():
		var role := str(role_variant)
		var binding: Dictionary = manifest.bindings.controls[role_variant]
		for hinge_binding_variant in binding.hinges:
			var hinge_binding: Dictionary = hinge_binding_variant
			var hinge_key := str(hinge_binding.key)
			var path := "$.hinges." + hinge_key
			if not hinges.has(hinge_key):
				_fail(errors, diagnostics, "MODEL_BUILD_HINGE_MISSING", path, "builder omitted the declared hinge")
				continue
			var entry: Variant = hinges[hinge_key]
			var hinge_node: Variant = null
			if entry is Node3D:
				hinge_node = entry
			elif typeof(entry) == TYPE_DICTIONARY:
				hinge_node = entry.get("node")
			else:
				_fail(errors, diagnostics, "MODEL_BUILD_HINGE_INVALID", path, "hinge must be a Node3D or a node/axis/rest binding")
				continue
			if not (hinge_node is Node3D):
				_fail(errors, diagnostics, "MODEL_BUILD_HINGE_NODE_MISSING", path + ".node", "hinge binding has no Node3D node")
				continue
			if hinge_node.name != hinge_binding.node: _fail(errors, diagnostics, "MODEL_BUILD_HINGE_NAME", path + ".node", "hinge node name does not match its stable binding")
			if hinge_node == root or not root.is_ancestor_of(hinge_node): _fail(errors, diagnostics, "MODEL_BUILD_HINGE_ORPHAN", path + ".node", "hinge node must remain under the public aircraft root")
			if entry is Node3D:
				if adapter != "euler_hinges": _fail(errors, diagnostics, "MODEL_BUILD_HINGE_SHAPE", path, "axis/imported adapters require explicit hinge axis and rest data")
			else:
				_check_axis_hinge(entry, path, hinge_binding, errors, diagnostics)
			if hinge_binding.source == "geometry_articulation": _check_authored_hinge(entry, path, errors, diagnostics)


static func _check_axis_hinge(entry: Dictionary, path: String, binding: Dictionary, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	for key in ["node", "axis", "rest"]:
		if not entry.has(key): _fail(errors, diagnostics, "MODEL_BUILD_HINGE_FIELD_MISSING", path + "." + key, "axis/rest hinge field is required")
	if entry.get("axis") is Vector3:
		var axis: Vector3 = entry.axis
		if not is_finite(axis.x) or not is_finite(axis.y) or not is_finite(axis.z) or absf(axis.length_squared() - 1.0) > 1.0e-5:
			_fail(errors, diagnostics, "MODEL_BUILD_HINGE_AXIS_INVALID", path + ".axis", "hinge axis must be finite and normalized")
	else:
		_fail(errors, diagnostics, "MODEL_BUILD_HINGE_AXIS_INVALID", path + ".axis", "hinge axis must be a Vector3")
	if not (entry.get("rest") is Basis):
		_fail(errors, diagnostics, "MODEL_BUILD_HINGE_REST_INVALID", path + ".rest", "hinge rest orientation must be a Basis")
	else:
		var rest: Basis = entry.rest
		if not rest.is_finite() or absf(rest.determinant()) < 1.0e-8:
			_fail(errors, diagnostics, "MODEL_BUILD_HINGE_REST_INVALID", path + ".rest", "hinge rest orientation must be finite and nonsingular")
	if binding.get("source") == "geometry_articulation":
		for field in ["range_deg", "positive", "app_sign"]:
			if not entry.has(field): _fail(errors, diagnostics, "MODEL_BUILD_HINGE_AUTHORED_FIELD_MISSING", path + "." + field, "geometry-backed hinge must preserve authored range and sign metadata")


static func _check_authored_hinge(entry: Variant, path: String, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	if typeof(entry) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_BUILD_HINGE_AUTHORED_INVALID", path, "geometry-backed hinge must expose its authoring metadata")
		return
	if not entry.has_all(["range_deg", "positive", "app_sign"]):
		_fail(errors, diagnostics, "MODEL_BUILD_HINGE_AUTHORED_FIELD_MISSING", path, "geometry-backed hinge is missing range/sign fields")
		return
	var range: Variant = entry.range_deg
	if typeof(range) != TYPE_ARRAY or range.size() != 2 or typeof(range[0]) not in [TYPE_FLOAT, TYPE_INT] or typeof(range[1]) not in [TYPE_FLOAT, TYPE_INT]:
		_fail(errors, diagnostics, "MODEL_BUILD_HINGE_RANGE_INVALID", path + ".range_deg", "authored hinge range must contain two numeric bounds")
	else:
		if not is_finite(float(range[0])) or not is_finite(float(range[1])) or float(range[0]) >= float(range[1]):
			_fail(errors, diagnostics, "MODEL_BUILD_HINGE_RANGE_INVALID", path + ".range_deg", "authored hinge range must be finite and increasing")
	if typeof(entry.positive) != TYPE_STRING or str(entry.positive).strip_edges().is_empty():
		_fail(errors, diagnostics, "MODEL_BUILD_HINGE_SIGN_INVALID", path + ".positive", "authored positive direction must be a non-empty string")
	if typeof(entry.app_sign) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(entry.app_sign)) or float(entry.app_sign) == 0.0:
		_fail(errors, diagnostics, "MODEL_BUILD_HINGE_SIGN_INVALID", path + ".app_sign", "application conversion sign must be finite and nonzero")


static func _check_derived_rotor(manifest: Dictionary, built: Dictionary, root: Node3D, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	var rotor: Dictionary = manifest.bindings.rotor
	var propeller: Variant = built.get("propeller")
	if not (propeller is Node3D):
		_fail(errors, diagnostics, "MODEL_BUILD_ROTOR_MISSING", "$.propeller", "builder must expose the public propeller Node3D, including a compatibility marker for jets")
	else:
		if propeller.name != rotor.node: _fail(errors, diagnostics, "MODEL_BUILD_ROTOR_NAME", "$.propeller.name", "propeller wrapper name does not match the stable binding")
		if propeller == root or not root.is_ancestor_of(propeller): _fail(errors, diagnostics, "MODEL_BUILD_ROTOR_ORPHAN", "$.propeller", "propeller wrapper must remain under the public aircraft root")
	if bool(built.get("has_propeller", rotor.present)) != bool(rotor.present):
		_fail(errors, diagnostics, "MODEL_BUILD_ROTOR_PRESENCE", "$.has_propeller", "builder propeller presence disagrees with the manifest")
	var spin_node_name := str(rotor.spin_node)
	if not spin_node_name.is_empty():
		var spin: Node = root.find_child(spin_node_name, true, false)
		if spin == null or not (spin is Node3D):
			_fail(errors, diagnostics, "MODEL_BUILD_ROTOR_SPIN_MISSING", "$.bindings.rotor.spin_node", "declared rotor spin node is missing from the built model")
		elif propeller is Node3D and not propeller.is_ancestor_of(spin):
			_fail(errors, diagnostics, "MODEL_BUILD_ROTOR_SPIN_PARENT", "$.bindings.rotor.spin_node", "rotor spin node must remain below the public propeller wrapper")


static func _check_derived_gear(manifest: Dictionary, built: Dictionary, root: Node3D, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	var bindings: Dictionary = manifest.bindings.gear.keys
	var gear: Variant = built.get("gear", {})
	if typeof(gear) != TYPE_DICTIONARY:
		_fail(errors, diagnostics, "MODEL_BUILD_GEAR_INVALID", "$.gear", "builder result must contain a gear dictionary")
		return
	for role_variant in bindings.keys():
		var role := str(role_variant)
		var key := str(bindings[role_variant])
		var path := "$.gear." + key
		if not gear.has(key):
			_fail(errors, diagnostics, "MODEL_BUILD_GEAR_MISSING", path, "builder omitted the declared gear role")
			continue
		var node: Variant = gear[key]
		if not (node is Node3D):
			_fail(errors, diagnostics, "MODEL_BUILD_GEAR_NODE_INVALID", path, "gear role must resolve to a Node3D wrapper")
		elif node == root or not root.is_ancestor_of(node):
			_fail(errors, diagnostics, "MODEL_BUILD_GEAR_ORPHAN", path, "gear node must remain under the public aircraft root")


static func _check_derived_crash(manifest: Dictionary, root: Node3D, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	var crash: Dictionary = manifest.bindings.crash
	if crash.provider == "gltf_extras":
		# Match the wreck collector: the public root is a wrapper, sections start at its children.
		for child in root.get_children():
			_check_gltf_section(child, "", errors, diagnostics)
	if crash.provider == "generated_triangle_map":
		var node := root.find_child(str(crash.asset_node), true, false)
		if node == null:
			_fail(errors, diagnostics, "MODEL_BUILD_CRASH_NODE_MISSING", "$.bindings.crash.asset_node", "declared crash asset node is missing from the built model")
		elif not node.has_meta("crash_section_map"):
			_fail(errors, diagnostics, "MODEL_BUILD_CRASH_MAP_MISSING", "$.bindings.crash.asset_node", "declared crash asset node has no generated section map")
		else:
			var section_map: Variant = node.get_meta("crash_section_map")
			if typeof(section_map) != TYPE_DICTIONARY or section_map.get("format") != "openrc-crash-sections v1" or not (section_map.get("sections", []) is Array) or section_map.get("sections", []).is_empty():
				_fail(errors, diagnostics, "MODEL_BUILD_CRASH_MAP_INVALID", "$.bindings.crash.asset_node", "generated crash section map has an unsupported format or no sections")


static func _check_gltf_section(node: Node, inherited: String, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	var extras: Variant = node.get_meta("extras", {})
	var section := ""
	var path := "$.scene." + str(node.name) + ".extras.openrc_section"
	if typeof(extras) == TYPE_DICTIONARY and extras.has("openrc_section"):
		var value: Variant = extras.openrc_section
		if typeof(value) != TYPE_STRING or not CRASH_SECTIONS.has(value):
			_fail(errors, diagnostics, "MODEL_BUILD_SECTION_INVALID", path, "section must be a supported string ID")
		else:
			section = value
	elif node is MeshInstance3D or (typeof(extras) == TYPE_DICTIONARY and extras.has("articulation")):
		_fail(errors, diagnostics, "MODEL_BUILD_SECTION_MISSING", path, "each imported mesh and articulated pivot must declare its crash section")
	if not inherited.is_empty() and not section.is_empty() and section != inherited:
		_fail(errors, diagnostics, "MODEL_BUILD_SECTION_CAPTURED", path, "detachable ancestor captures a different child section")
	var next_section := inherited
	if next_section.is_empty() and section != "core":
		next_section = section
	for child in node.get_children():
		_check_gltf_section(child, next_section, errors, diagnostics)


static func _check_derived_asset(manifest: Dictionary, root: Node3D, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	var asset: Dictionary = manifest.asset
	if asset.kind != "imported_glb": return
	# F4U-16: a livery build carries its own GLB identity; any other root must carry the default asset's.
	var expected := str(asset.sha256)
	var livery_id := str(root.get_meta("livery", ""))
	if not livery_id.is_empty():
		var matches: Array = manifest.get("liveries", []).filter(func(record: Dictionary) -> bool: return record.id == livery_id)
		if matches.is_empty(): _fail(errors, diagnostics, "MODEL_BUILD_LIVERY_UNKNOWN", "$.liveries", "builder root names an unknown livery")
		else: expected = str(matches[0].sha256)
	if str(root.get_meta("asset_sha256", "")) != expected:
		_fail(errors, diagnostics, "MODEL_BUILD_ASSET_HASH_MISMATCH", "$.asset.sha256", "builder root identity does not match the imported asset hash")
	if str(root.get_meta("visual_revision", "")) != str(asset.revision):
		_fail(errors, diagnostics, "MODEL_BUILD_ASSET_REVISION_MISMATCH", "$.asset.revision", "builder root revision does not match the imported asset revision")


static func _validate_dependency_closure(manifest: Dictionary, proofs: Dictionary, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	var expected: Dictionary = {}
	var pending: Array[String] = [str(manifest.builder.script), str(manifest.geometry.script)]
	if manifest.asset.kind == "imported_glb":
		pending.append(str(manifest.asset.path))
		var sidecar := str(manifest.asset.path) + ".import"
		if (proofs.has(sidecar) if not proofs.is_empty() else FileAccess.file_exists(sidecar)): pending.append(sidecar)
	var crash: Dictionary = manifest.bindings.crash
	if crash.provider == "generated_triangle_map": pending.append(str(crash.metadata_script))
	var listed: Dictionary = {}
	for dependency in manifest.dependencies: listed[dependency.path] = dependency
	var checked: Dictionary = {}
	var expression := RegEx.new()
	var compile_error := expression.compile("\\b(?:preload|load)\\s*\\(\\s*[\"']res://([^\"']+)[\"']\\s*\\)")
	if compile_error != OK:
		_fail(errors, diagnostics, "MODEL_DEPENDENCY_SCANNER", "$.dependencies", "internal bundled-resource scanner could not be initialized")
		return
	while not pending.is_empty():
		var resource: String = pending.pop_back()
		if expected.has(resource): continue
		expected[resource] = true
		var absolute := ""
		if proofs.is_empty():
			absolute = _resource_file(resource)
			if absolute.is_empty() or not FileAccess.file_exists(absolute):
				_fail(errors, diagnostics, "MODEL_DEPENDENCY_MISSING", resource, "bundled resource is missing")
				continue
		if not listed.has(resource):
			_fail(errors, diagnostics, "MODEL_DEPENDENCY_UNPINNED", "$.dependencies", "bundled dependency closure is missing " + resource)
			continue
		var item: Dictionary = listed[resource]
		var expected_role := _dependency_role(resource, manifest)
		if item.get("role") != expected_role: _fail(errors, diagnostics, "MODEL_DEPENDENCY_ROLE_MISMATCH", "$.dependencies", "dependency %s must have role %s" % [resource, expected_role])
		_check_resource_record(item, "$.dependencies[" + resource + "]", proofs, errors, diagnostics)
		checked[resource] = true
		if resource.ends_with(".gd"):
			var source := _resource_text(resource, absolute, proofs, errors, diagnostics)
			for match in expression.search_all(source): pending.append("res://" + match.get_string(1))
	for resource in listed.keys():
		if not expected.has(resource): _fail(errors, diagnostics, "MODEL_DEPENDENCY_UNUSED", "$.dependencies[" + str(resource) + "]", "dependency is not reachable from the registered builder")
	if not proofs.is_empty():
		for resource in expected.keys():
			_proof_for(str(resource), proofs, "$.dependencies", errors, diagnostics)


static func _resource_text(resource: String, absolute: String, proofs: Dictionary, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> String:
	if proofs.is_empty(): return FileAccess.get_file_as_string(absolute)
	var proof_path := _proof_for(resource, proofs, "$.dependencies", errors, diagnostics)
	if proof_path.is_empty(): return ""
	return FileAccess.get_file_as_bytes(proof_path).get_string_from_utf8()


static func _dependency_role(resource: String, manifest: Dictionary) -> String:
	if resource == manifest.builder.script: return "builder"
	if resource == manifest.geometry.script: return "generated_geometry"
	if manifest.asset.kind == "imported_glb" and resource == manifest.asset.path: return "imported_asset"
	if manifest.bindings.crash.provider == "generated_triangle_map" and resource == manifest.bindings.crash.metadata_script: return "crash_metadata"
	return "script_dependency" if resource.ends_with(".gd") else "resource_dependency"


static func _check_authoring_record(record: Dictionary, path: String, proofs: Dictionary, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	var source_path := str(record.get("path", ""))
	if not proofs.is_empty():
		var proof_path := _proof_for(source_path, proofs, path, errors, diagnostics)
		if proof_path.is_empty(): return
		_check_record_hash(proof_path, str(record.get("hash_mode", "")), str(record.get("sha256", "")), path, errors, diagnostics)
		return
	var absolute := _authoring_file(source_path)
	if absolute.is_empty() or not FileAccess.file_exists(absolute):
		_fail(errors, diagnostics, "MODEL_SOURCE_MISSING", path + ".path", "authoring source is missing: " + source_path)
		return
	_check_record_hash(absolute, str(record.get("hash_mode", "")), str(record.get("sha256", "")), path, errors, diagnostics)


static func _check_resource_record(record: Dictionary, path: String, proofs: Dictionary, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	var source_path := str(record.get("path", ""))
	if not proofs.is_empty():
		if not source_path.ends_with(".import"):
			if not ResourceLoader.exists(source_path):
				_fail(errors, diagnostics, "MODEL_PACKAGED_RESOURCE_MISSING", path + ".path", "packaged runtime resource does not resolve: " + source_path)
				return
			# F4U-20-R1: verify GLB provenance without uploading an unselected paint.
			# The importer loads the chosen scene and rejects a missing/invalid PackedScene.
			# Other dependencies retain their eager loadability check.
			if not source_path.ends_with(".glb") and ResourceLoader.load(source_path) == null:
				_fail(errors, diagnostics, "MODEL_PACKAGED_RESOURCE_LOAD", path + ".path", "packaged runtime resource failed to load: " + source_path)
				return
		var proof_path := _proof_for(source_path, proofs, path, errors, diagnostics)
		if proof_path.is_empty(): return
		_check_record_hash(proof_path, str(record.get("hash_mode", "")), str(record.get("sha256", "")), path, errors, diagnostics)
		return
	var absolute := _resource_file(source_path)
	if absolute.is_empty() or not FileAccess.file_exists(absolute):
		_fail(errors, diagnostics, "MODEL_DEPENDENCY_MISSING", path + ".path", "bundled dependency is missing: " + source_path)
		return
	_check_record_hash(absolute, str(record.get("hash_mode", "")), str(record.get("sha256", "")), path, errors, diagnostics)


static func _check_record_hash(absolute: String, hash_mode: String, expected: String, path: String, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> void:
	var bytes := FileAccess.get_file_as_bytes(absolute)
	if hash_mode == TEXT_HASH:
		var text := bytes.get_string_from_utf8().replace("\r\n", "\n").replace("\r", "\n")
		bytes = text.to_utf8_buffer()
	elif hash_mode != BINARY_HASH:
		_fail(errors, diagnostics, "MODEL_HASH_MODE_UNKNOWN", path + ".hash_mode", "unknown hash normalization mode")
		return
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		_fail(errors, diagnostics, "MODEL_HASH_READ_FAILED", path + ".sha256", "could not hash source bytes")
		return
	var actual := context.finish().hex_encode()
	if actual != expected: _fail(errors, diagnostics, "MODEL_HASH_MISMATCH", path + ".sha256", "SHA-256 mismatch for %s" % absolute)


static func _read_package_proofs() -> Dictionary:
	if not FileAccess.file_exists(PACKAGE_PROOF_PATH):
		if FileAccess.file_exists("res://project.binary") or OS.has_feature("template"):
			return _failure("MODEL_PACKAGE_PROOF_MISSING", PACKAGE_PROOF_PATH, "exported aircraft models require source proof metadata")
		return {"ok": true, "files": {}}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACKAGE_PROOF_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure("MODEL_PACKAGE_PROOF_INVALID", PACKAGE_PROOF_PATH, "package proof marker must be a JSON object")
	if parsed.keys().size() != 2 or not parsed.has("format") or not parsed.has("files"):
		return _failure("MODEL_PACKAGE_PROOF_INVALID", PACKAGE_PROOF_PATH, "package proof marker has unknown or missing fields")
	if parsed.get("format") != PACKAGE_PROOF_FORMAT or typeof(parsed.get("files")) != TYPE_DICTIONARY:
		return _failure("MODEL_PACKAGE_PROOF_INVALID", PACKAGE_PROOF_PATH, "package proof format or files map is unsupported")
	var files: Dictionary = parsed.files
	if files.is_empty():
		return _failure("MODEL_PACKAGE_PROOF_INVALID", PACKAGE_PROOF_PATH, "package proof map cannot be empty")
	var destinations: Dictionary = {}
	for source_variant in files.keys():
		var source_path := str(source_variant)
		var proof_path := str(files[source_variant])
		if source_path.begins_with("res://"):
			if not Manifest._resource_path(source_path, ["aircraft", "assets", "render"]):
				return _failure("MODEL_PACKAGE_PROOF_INVALID", PACKAGE_PROOF_PATH, "package proof source path is unsafe: " + source_path)
		elif not Manifest._authoring_path(source_path):
			return _failure("MODEL_PACKAGE_PROOF_INVALID", PACKAGE_PROOF_PATH, "package proof source path is unsafe: " + source_path)
		if proof_path != _expected_proof_path(source_path):
			return _failure("MODEL_PACKAGE_PROOF_INVALID", PACKAGE_PROOF_PATH, "package proof destination does not match deterministic path for " + source_path)
		if destinations.has(proof_path):
			return _failure("MODEL_PACKAGE_PROOF_INVALID", PACKAGE_PROOF_PATH, "multiple source paths map to the same package proof")
		destinations[proof_path] = true
		if not FileAccess.file_exists(proof_path):
			return _failure("MODEL_PACKAGE_PROOF_MISSING", proof_path, "package source proof bytes are missing")
	return {"ok": true, "files": files}


static func _proof_for(source_path: String, proofs: Dictionary, path: String, errors: PackedStringArray, diagnostics: Array[Dictionary]) -> String:
	if not proofs.has(source_path):
		_fail(errors, diagnostics, "MODEL_PACKAGE_PROOF_MISSING", path, "package proof table does not pin source " + source_path)
		return ""
	var proof_path := str(proofs[source_path])
	if proof_path != _expected_proof_path(source_path):
		_fail(errors, diagnostics, "MODEL_PACKAGE_PROOF_INVALID", path, "package proof path is not deterministic for source " + source_path)
		return ""
	if not FileAccess.file_exists(proof_path):
		_fail(errors, diagnostics, "MODEL_PACKAGE_PROOF_MISSING", proof_path, "package source proof bytes are missing")
		return ""
	return proof_path


static func _expected_proof_path(source_path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(source_path.to_utf8_buffer())
	return PACKAGE_PROOF_ROOT + context.finish().hex_encode() + ".bin"


static func _resource_file(resource_path: String) -> String:
	if not resource_path.begins_with("res://"): return ""
	return ProjectSettings.globalize_path(resource_path)


static func _authoring_file(source_path: String) -> String:
	if source_path.is_empty() or source_path.begins_with("/") or source_path.contains("\\") or source_path.contains(":"): return ""
	if source_path.contains("../") or source_path == "..": return ""
	return ProjectSettings.globalize_path("res://").path_join("../" + source_path)


static func _derived_result(ok: bool, errors: PackedStringArray, diagnostics: Array[Dictionary], manifest: Dictionary) -> Dictionary:
	return {"ok": ok, "errors": errors, "diagnostics": diagnostics, "manifest": manifest.duplicate(true) if ok else {}}


static func _failure(code: String, path: String, message: String) -> Dictionary:
	var errors := PackedStringArray([message])
	var diagnostics: Array[Dictionary] = [{"code": code, "path": path, "message": message}]
	return {"ok": false, "errors": errors, "diagnostics": diagnostics, "manifest": {}}


static func _fail(errors: PackedStringArray, diagnostics: Array[Dictionary], code: String, path: String, message: String) -> void:
	errors.append(message)
	diagnostics.append({"code": code, "path": path, "message": message})
