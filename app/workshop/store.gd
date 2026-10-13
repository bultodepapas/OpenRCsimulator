extends RefCounted
## Durable local storage for immutable aircraft variant snapshots.
## All writes stay under user:// so shipped aircraft resources remain read-only.

const WorkshopDescriptor = preload("res://workshop/descriptor.gd")
const WorkshopDependencies = preload("res://workshop/dependencies.gd")
const WorkshopCompiler = preload("res://workshop/compiler.gd")
const DEFAULT_ROOT: String = "user://aircraft_variants"
const VARIANT_FORMAT: String = "openrc-aircraft-variant"
const VARIANT_VERSION: int = 1
const INDEX_FORMAT: String = "openrc-aircraft-variant-index"
const INDEX_VERSION: int = 1
const MAX_BASE_BYTES: int = 16 * 1024 * 1024
const MAX_VARIANT_BYTES: int = 32 * 1024 * 1024
const MAX_JSON_DEPTH: int = 64
const MAX_JSON_NODES: int = 250000
const RECIPE_KEYS: PackedStringArray = [
	"scale",
	"mass_policy",
	"weight_multiplier",
	"power_multiplier",
	"control_multiplier",
	"id",
	"name",
]
const VARIANT_KEYS: PackedStringArray = [
	"format",
	"version",
	"id",
	"revision",
	"name",
	"compiler_version",
	"base_id",
	"recipe",
	"base_sha256",
	"recipe_sha256",
	"base_bytes_base64",
	"created_at_unix",
	"updated_at_unix",
	"workshop_descriptor",
	"dependencies",
]
const VARIANT_REQUIRED_KEYS: PackedStringArray = [
	"format",
	"version",
	"id",
	"revision",
	"name",
	"compiler_version",
	"base_id",
	"recipe",
	"base_sha256",
	"recipe_sha256",
	"base_bytes_base64",
	"created_at_unix",
	"updated_at_unix",
]
const INDEX_KEYS: PackedStringArray = ["format", "version", "id", "revision"]


static func list_variants(root: String = DEFAULT_ROOT) -> Array:
	var root_result: Dictionary = _resolve_root(root)
	if not bool(root_result["ok"]):
		return []
	var root_path: String = root_result["path"]
	if not DirAccess.dir_exists_absolute(root_path):
		return []
	var names: PackedStringArray = _directory_names(root_path, true)
	var variants: Array = []
	for entry: String in names:
		if not _valid_uuid(entry):
			continue
		var result: Dictionary = _load_from_directory(root_path.path_join(entry), entry)
		if bool(result["ok"]):
			variants.append(result["variant"])
	return variants


static func save_variant(
		name: String,
		base_id: String,
		base_bytes: PackedByteArray,
		recipe: Dictionary,
		id: String = "",
		root: String = DEFAULT_ROOT,
		workshop_descriptor: Dictionary = {},
		dependencies: Dictionary = {}
) -> Dictionary:
	var errors := PackedStringArray()
	var root_result: Dictionary = _resolve_root(root)
	if not bool(root_result["ok"]):
		errors.append_array(root_result["errors"])
		return _result(false, errors)
	if not _valid_name(name):
		errors.append("Variant name must be trimmed, non-empty, and at most 96 characters.")
	if not _valid_base_id(base_id):
		errors.append("Base aircraft ID is not a valid catalog identifier.")
	if base_bytes.is_empty() or base_bytes.size() > MAX_BASE_BYTES:
		errors.append("Base snapshot is empty or exceeds the %d-byte limit." % MAX_BASE_BYTES)
	var base_parsed: Dictionary = {}
	var base_hash: String = ""
	if base_bytes.size() > 0 and base_bytes.size() <= MAX_BASE_BYTES:
		var base_result: Dictionary = _parse_base_snapshot(base_id, base_bytes)
		if bool(base_result["ok"]):
			base_parsed = base_result["base"]
			base_hash = _sha256(base_bytes)
		else:
			errors.append_array(base_result["errors"])
	var recipe_result: Dictionary = _validate_recipe(recipe)
	if not bool(recipe_result["ok"]):
		errors.append_array(recipe_result["errors"])
	var safe_id: String = id
	if safe_id.is_empty() and recipe.has("id") and typeof(recipe["id"]) == TYPE_STRING:
		safe_id = str(recipe["id"])
	if not safe_id.is_empty() and not _valid_uuid(safe_id):
		errors.append("Variant ID must be a lowercase UUID.")
	if not safe_id.is_empty() and recipe.has("id") and recipe["id"] != safe_id:
		errors.append("Recipe ID must match the variant ID.")
	if recipe.has("name") and recipe["name"] != name:
		errors.append("Recipe name must match the variant name.")
	if not errors.is_empty():
		return _result(false, errors)
	if safe_id.is_empty():
		safe_id = _new_uuid()
		if safe_id.is_empty():
			errors.append("Could not generate a secure variant ID.")
			return _result(false, errors)
	var root_path: String = root_result["path"]
	var root_error: Error = _make_directory(root_path)
	if root_error != OK:
		errors.append("Could not create the variant store directory (%s)." % error_string(root_error))
		return _result(false, errors)
	var variant_dir: String = root_path.path_join(safe_id)
	var existing_variant: Dictionary = {}
	var stored_descriptor: Dictionary = {}
	var stored_dependencies: Dictionary = {}
	var stored_compiler_version: String = WorkshopCompiler.COMPILER_VERSION
	var revision: int = 1
	var created_at: int = int(Time.get_unix_time_from_system())
	var directory_exists: bool = DirAccess.dir_exists_absolute(variant_dir)
	if directory_exists:
		var existing_result: Dictionary = _load_from_directory(variant_dir, safe_id)
		if not bool(existing_result["ok"]):
			errors.append("Existing variant ID cannot be updated: %s" % "; ".join(existing_result["errors"]))
			return _result(false, errors)
		existing_variant = existing_result["variant"]
		var pinned_compiler_version: String = str(existing_variant.get("compiler_version", ""))
		if pinned_compiler_version != WorkshopCompiler.COMPILER_VERSION:
			errors.append("This variant is pinned to compiler %s; create a new variant to use compiler %s." % [pinned_compiler_version, WorkshopCompiler.COMPILER_VERSION])
			return _result(false, errors)
		stored_compiler_version = pinned_compiler_version
		if str(existing_variant["base_id"]) != base_id or str(existing_variant["base_sha256"]) != base_hash:
			errors.append("A saved variant's base ID and exact base snapshot are immutable.")
			return _result(false, errors)
		if (existing_variant["base_bytes"] as PackedByteArray) != base_bytes:
			errors.append("A saved variant's exact base snapshot is immutable.")
			return _result(false, errors)
		var pinned_descriptor: Dictionary = existing_variant.get("workshop_descriptor", {})
		if not pinned_descriptor.is_empty():
			if not workshop_descriptor.is_empty() and workshop_descriptor != pinned_descriptor:
				errors.append("A saved variant's Workshop descriptor is immutable.")
				return _result(false, errors)
			stored_descriptor = pinned_descriptor.duplicate(true)
		var pinned_dependencies: Dictionary = existing_variant.get("dependencies", {})
		if pinned_dependencies.is_empty():
			errors.append("This saved variant has no pinned dependencies; create a new variant to record the current dependencies.")
			return _result(false, errors)
		if not dependencies.is_empty() and dependencies != pinned_dependencies:
			errors.append("A saved variant's Workshop dependencies are immutable; create a new variant to use changed dependencies.")
			return _result(false, errors)
		stored_dependencies = pinned_dependencies.duplicate(true)
		created_at = int(existing_variant["created_at_unix"])
		revision = maxi(int(existing_variant["revision"]) + 1, _next_revision(variant_dir))
	elif FileAccess.file_exists(variant_dir):
		errors.append("Variant ID collides with a file in the local store.")
		return _result(false, errors)
	if stored_descriptor.is_empty():
		var descriptor_result: Dictionary = _resolve_workshop_descriptor(base_id, base_bytes, workshop_descriptor)
		if not bool(descriptor_result["ok"]):
			errors.append_array(descriptor_result["errors"])
			return _result(false, errors)
		stored_descriptor = descriptor_result["descriptor"]
	if stored_dependencies.is_empty():
		var dependencies_result: Dictionary = _resolve_workshop_dependencies(base_parsed, dependencies)
		if not bool(dependencies_result["ok"]):
			errors.append_array(dependencies_result["errors"])
			return _result(false, errors)
		stored_dependencies = dependencies_result["manifest"]
	var revisions_dir: String = variant_dir.path_join("revisions")
	root_error = _make_directory(revisions_dir)
	if root_error != OK:
		errors.append("Could not create the variant revisions directory (%s)." % error_string(root_error))
		return _result(false, errors)
	var now: int = maxi(created_at, int(Time.get_unix_time_from_system()))
	var stored_recipe: Dictionary = recipe.duplicate(true)
	var recipe_json: String = JSON.stringify(stored_recipe, "", true, true)
	var recipe_hash: String = _sha256(recipe_json.to_utf8_buffer())
	var record: Dictionary = {
		"format": VARIANT_FORMAT,
		"version": VARIANT_VERSION,
		"id": safe_id,
		"revision": revision,
		"name": name,
		"compiler_version": stored_compiler_version,
		"base_id": base_id,
		"recipe": stored_recipe,
		"base_sha256": base_hash,
		"recipe_sha256": recipe_hash,
		"base_bytes_base64": Marshalls.raw_to_base64(base_bytes),
		"created_at_unix": created_at,
		"updated_at_unix": now,
	}
	if not stored_descriptor.is_empty():
		record["workshop_descriptor"] = stored_descriptor.duplicate(true)
	if not stored_dependencies.is_empty():
		record["dependencies"] = stored_dependencies.duplicate(true)
	var record_validation: Dictionary = _validate_variant_record(record, safe_id)
	if not bool(record_validation["ok"]):
		errors.append_array(record_validation["errors"])
		return _result(false, errors)
	var revision_name: String = "%08d.json" % revision
	var revision_path: String = revisions_dir.path_join(revision_name)
	var record_bytes: PackedByteArray = (JSON.stringify(record, "\t", true, true) + "\n").to_utf8_buffer()
	var write_result: Dictionary = _write_new_file_atomic(revision_path, record_bytes)
	if not bool(write_result["ok"]):
		errors.append_array(write_result["errors"])
		return _result(false, errors)
	var index: Dictionary = {
		"format": INDEX_FORMAT,
		"version": INDEX_VERSION,
		"id": safe_id,
		"revision": revision,
	}
	var index_bytes: PackedByteArray = (JSON.stringify(index, "\t", true, true) + "\n").to_utf8_buffer()
	var index_result: Dictionary = _write_index_atomic(variant_dir, index_bytes)
	if not bool(index_result["ok"]):
		errors.append_array(index_result["errors"])
		return _result(false, errors)
	var loaded: Dictionary = _load_from_directory(variant_dir, safe_id)
	if not bool(loaded["ok"]):
		errors.append_array(loaded["errors"])
		return _result(false, errors)
	return _result(true, PackedStringArray(), loaded["variant"])


static func load_variant(id: String, root: String = DEFAULT_ROOT) -> Dictionary:
	var errors := PackedStringArray()
	var root_result: Dictionary = _resolve_root(root)
	if not bool(root_result["ok"]):
		errors.append_array(root_result["errors"])
		return _result(false, errors)
	if not _valid_uuid(id):
		errors.append("Variant ID must be a lowercase UUID.")
		return _result(false, errors)
	var variant_dir: String = str(root_result["path"]).path_join(id)
	if not DirAccess.dir_exists_absolute(variant_dir):
		errors.append("Variant does not exist in the local store.")
		return _result(false, errors)
	return _load_from_directory(variant_dir, id)


static func delete_variant(id: String, root: String = DEFAULT_ROOT) -> Dictionary:
	var errors := PackedStringArray()
	var root_result: Dictionary = _resolve_root(root)
	if not bool(root_result["ok"]):
		errors.append_array(root_result["errors"])
		return _result(false, errors)
	if not _valid_uuid(id):
		errors.append("Variant ID must be a lowercase UUID.")
		return _result(false, errors)
	var root_path: String = root_result["path"]
	var variant_dir: String = root_path.path_join(id)
	var loaded: Dictionary = _load_from_directory(variant_dir, id)
	if not bool(loaded["ok"]):
		errors.append_array(loaded["errors"])
		return _result(false, errors)
	var trash_root: String = root_path.path_join("_trash")
	var err: Error = _make_directory(trash_root)
	if err != OK:
		errors.append("Could not create the local trash directory (%s)." % error_string(err))
		return _result(false, errors)
	var trash_name: String = "%s-%010d-%s" % [id, int(Time.get_unix_time_from_system()), _new_uuid().substr(0, 8)]
	var trash_path: String = trash_root.path_join(trash_name)
	err = DirAccess.rename_absolute(variant_dir, trash_path)
	if err != OK:
		errors.append("Could not move the variant to local trash (%s)." % error_string(err))
		return _result(false, errors)
	return _result(true, PackedStringArray(), loaded["variant"])


static func restore_variant(id: String, root: String = DEFAULT_ROOT) -> Dictionary:
	var errors := PackedStringArray()
	var root_result: Dictionary = _resolve_root(root)
	if not bool(root_result["ok"]):
		errors.append_array(root_result["errors"])
		return _result(false, errors)
	if not _valid_uuid(id):
		errors.append("Variant ID must be a lowercase UUID.")
		return _result(false, errors)
	var root_path: String = root_result["path"]
	var live_path: String = root_path.path_join(id)
	if DirAccess.dir_exists_absolute(live_path) or FileAccess.file_exists(live_path):
		errors.append("A live variant with this ID already exists.")
		return _result(false, errors)
	var trash_root: String = root_path.path_join("_trash")
	var candidates: Array[String] = []
	for entry: String in _directory_names(trash_root, true):
		if entry == id or entry.begins_with(id + "-"):
			candidates.append(entry)
	candidates.sort()
	candidates.reverse()
	for entry: String in candidates:
		var candidate: String = trash_root.path_join(entry)
		var loaded: Dictionary = _load_from_directory(candidate, id)
		if not bool(loaded["ok"]):
			continue
		var err: Error = DirAccess.rename_absolute(candidate, live_path)
		if err != OK:
			errors.append("Could not restore the variant from local trash (%s)." % error_string(err))
			return _result(false, errors)
		return _load_from_directory(live_path, id)
	errors.append("No valid trashed variant with this ID was found.")
	return _result(false, errors)


static func _load_from_directory(variant_dir: String, expected_id: String) -> Dictionary:
	var errors := PackedStringArray()
	var manifest_path: String = variant_dir.path_join("manifest.json")
	var manifest_backup: String = manifest_path + ".bak"
	var manifest_source: String = manifest_path
	var recovered: bool = false
	if not FileAccess.file_exists(manifest_path):
		if not FileAccess.file_exists(manifest_backup):
			errors.append("Variant manifest is missing.")
			return _result(false, errors)
		manifest_source = manifest_backup
		recovered = true
	var manifest_result: Dictionary = _read_json_file(manifest_source)
	if not bool(manifest_result["ok"]):
		errors.append_array(manifest_result["errors"])
		return _result(false, errors)
	var manifest: Variant = manifest_result["data"]
	var manifest_validation: Dictionary = _validate_manifest(manifest, expected_id)
	if not bool(manifest_validation["ok"]):
		errors.append_array(manifest_validation["errors"])
		return _result(false, errors)
	var revision: int = int(manifest["revision"])
	var revision_name: String = "%08d.json" % revision
	var revision_path: String = variant_dir.path_join("revisions").path_join(revision_name)
	var record_result: Dictionary = _read_json_file(revision_path)
	if not bool(record_result["ok"]):
		errors.append_array(record_result["errors"])
		return _result(false, errors)
	var record: Variant = record_result["data"]
	var record_validation: Dictionary = _validate_variant_record(record, expected_id)
	if not bool(record_validation["ok"]):
		errors.append_array(record_validation["errors"])
		return _result(false, errors)
	if int(record["revision"]) != revision:
		errors.append("Variant manifest points to a different saved revision.")
		return _result(false, errors)
	var base_bytes: PackedByteArray = Marshalls.base64_to_raw(str(record["base_bytes_base64"]))
	var base_text: String = base_bytes.get_string_from_utf8()
	var parser := JSON.new()
	var parse_error: Error = parser.parse(base_text)
	if parse_error != OK:
		errors.append("Base snapshot JSON could not be parsed.")
		return _result(false, errors)
	var base_value: Variant = parser.data
	var base_validation: Dictionary = _validate_json_tree(base_value)
	if not bool(base_validation["ok"]) or typeof(base_value) != TYPE_DICTIONARY:
		errors.append("Base snapshot must be a finite JSON object.")
		return _result(false, errors)
	var base: Dictionary = base_value
	if str(base.get("format", "")) != "openrc-aircraft v2":
		errors.append("Base snapshot must use the openrc-aircraft v2 schema.")
		return _result(false, errors)
	if str(base.get("id", "")) != str(record["base_id"]):
		errors.append("Base snapshot ID does not match the pinned base ID.")
		return _result(false, errors)
	if base_text.to_utf8_buffer() != base_bytes:
		errors.append("Base snapshot is not valid canonical UTF-8.")
		return _result(false, errors)
	var recipe: Dictionary = (record["recipe"] as Dictionary).duplicate(true)
	var variant: Dictionary = {
		"id": expected_id,
		"revision": revision,
		"name": str(record["name"]),
		"compiler_version": str(record["compiler_version"]),
		"base_id": str(record["base_id"]),
		"recipe": recipe,
		"base": base,
		"base_bytes": base_bytes,
		"base_sha256": str(record["base_sha256"]),
		"recipe_sha256": str(record["recipe_sha256"]),
		"created_at_unix": int(record["created_at_unix"]),
		"updated_at_unix": int(record["updated_at_unix"]),
		"recovered_from_manifest_backup": recovered,
	}
	if record.has("workshop_descriptor"):
		variant["workshop_descriptor"] = (record["workshop_descriptor"] as Dictionary).duplicate(true)
	if record.has("dependencies"):
		variant["dependencies"] = (record["dependencies"] as Dictionary).duplicate(true)
	if recovered:
		errors.append("Recovered the last committed revision from its manifest backup.")
	return _result(true, errors, variant)


static func _validate_manifest(value: Variant, expected_id: String) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("Variant manifest must be a JSON object.")
		return _result(false, errors)
	var manifest: Dictionary = value
	if manifest.size() != INDEX_KEYS.size() or not manifest.has_all(INDEX_KEYS):
		errors.append("Variant manifest has missing or unknown fields.")
		return _result(false, errors)
	if manifest["format"] != INDEX_FORMAT or not _integer_number(manifest["version"]) or int(manifest["version"]) != INDEX_VERSION:
		errors.append("Variant manifest format or version is unsupported.")
	if manifest["id"] != expected_id or not _valid_uuid(str(manifest["id"])):
		errors.append("Variant manifest ID does not match its directory.")
	if not _integer_number(manifest["revision"]) or int(manifest["revision"]) < 1:
		errors.append("Variant manifest revision must be a positive integer.")
	return _result(errors.is_empty(), errors)


static func _validate_variant_record(value: Variant, expected_id: String) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("Variant revision must be a JSON object.")
		return _result(false, errors)
	var record: Dictionary = value
	var has_descriptor: bool = record.has("workshop_descriptor")
	var has_dependencies: bool = record.has("dependencies")
	var allowed_record_size: int = VARIANT_REQUIRED_KEYS.size() + (1 if has_descriptor else 0) + (1 if has_dependencies else 0)
	if record.size() != allowed_record_size or not record.has_all(VARIANT_REQUIRED_KEYS):
		errors.append("Variant revision has missing or unknown fields.")
		return _result(false, errors)
	for key: Variant in record.keys():
		if typeof(key) != TYPE_STRING or not VARIANT_KEYS.has(str(key)):
			errors.append("Variant revision has missing or unknown fields.")
			return _result(false, errors)
	if record["format"] != VARIANT_FORMAT or not _integer_number(record["version"]) or int(record["version"]) != VARIANT_VERSION:
		errors.append("Variant format or version is unsupported.")
	if record["id"] != expected_id or not _valid_uuid(str(record["id"])):
		errors.append("Variant revision ID does not match its directory.")
	if not _integer_number(record["revision"]) or int(record["revision"]) < 1:
		errors.append("Variant revision number must be a positive integer.")
	if not _valid_name(str(record["name"])) or typeof(record["name"]) != TYPE_STRING:
		errors.append("Variant name is invalid.")
	if typeof(record["compiler_version"]) != TYPE_STRING or str(record["compiler_version"]).strip_edges().is_empty():
		errors.append("Variant compiler version must be a non-empty string.")
	if typeof(record["base_id"]) != TYPE_STRING or not _valid_base_id(str(record["base_id"])):
		errors.append("Variant base ID is invalid.")
	if typeof(record["recipe"]) != TYPE_DICTIONARY:
		errors.append("Variant recipe must be a JSON object.")
	else:
		var recipe_result: Dictionary = _validate_recipe(record["recipe"])
		if not bool(recipe_result["ok"]):
			errors.append_array(recipe_result["errors"])
		if record["recipe"].has("id") and record["recipe"]["id"] != expected_id:
			errors.append("Recipe ID must match the variant ID.")
		if record["recipe"].has("name") and record["recipe"]["name"] != record["name"]:
			errors.append("Recipe name must match the variant name.")
	var base_hash: String = str(record["base_sha256"])
	var recipe_hash: String = str(record["recipe_sha256"])
	if typeof(record["base_sha256"]) != TYPE_STRING or not _valid_sha256(base_hash):
		errors.append("Base snapshot SHA-256 is malformed.")
	if typeof(record["recipe_sha256"]) != TYPE_STRING or not _valid_sha256(recipe_hash):
		errors.append("Recipe SHA-256 is malformed.")
	if typeof(record["base_bytes_base64"]) != TYPE_STRING or str(record["base_bytes_base64"]).is_empty():
		errors.append("Base snapshot bytes are missing.")
	else:
		var decoded: PackedByteArray = Marshalls.base64_to_raw(str(record["base_bytes_base64"]))
		if decoded.is_empty() or decoded.size() > MAX_BASE_BYTES or Marshalls.raw_to_base64(decoded) != record["base_bytes_base64"]:
			errors.append("Base snapshot bytes are malformed or exceed the size limit.")
		elif _sha256(decoded) != base_hash:
			errors.append("Base snapshot SHA-256 does not match its exact bytes.")
		elif has_descriptor:
			if typeof(record["workshop_descriptor"]) != TYPE_DICTIONARY:
				errors.append("Pinned Workshop descriptor must be a JSON object.")
			else:
				var descriptor_result: Dictionary = WorkshopDescriptor.validate(record["workshop_descriptor"], str(record["base_id"]), decoded)
				if not bool(descriptor_result["ok"]):
					errors.append_array(descriptor_result["errors"])
		if has_dependencies:
			if typeof(record["dependencies"]) != TYPE_DICTIONARY:
				errors.append("Pinned Workshop dependencies must be a JSON object.")
			else:
				var parsed_base: Dictionary = _parse_base_snapshot(str(record["base_id"]), decoded)
				if not bool(parsed_base["ok"]):
					errors.append_array(parsed_base["errors"])
				else:
					var dependencies_result: Dictionary = WorkshopDependencies.validate_manifest(parsed_base["base"], record["dependencies"])
					if not bool(dependencies_result["ok"]):
						errors.append_array(dependencies_result["errors"])
	var recipe_json: String = JSON.stringify(record.get("recipe", {}), "", true, true)
	if _valid_sha256(recipe_hash) and _sha256(recipe_json.to_utf8_buffer()) != recipe_hash:
		errors.append("Recipe SHA-256 does not match the saved recipe.")
	for field: String in ["created_at_unix", "updated_at_unix"]:
		if not _integer_number(record[field]) or int(record[field]) < 0:
			errors.append("Variant %s must be a non-negative integer." % field)
	if _integer_number(record["created_at_unix"]) and _integer_number(record["updated_at_unix"]) and int(record["updated_at_unix"]) < int(record["created_at_unix"]):
		errors.append("Variant update time cannot precede its creation time.")
	var tree_result: Dictionary = _validate_json_tree(record)
	if not bool(tree_result["ok"]):
		errors.append_array(tree_result["errors"])
	return _result(errors.is_empty(), errors)


static func _validate_recipe(value: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("Recipe must be a JSON object.")
		return _result(false, errors)
	var recipe: Dictionary = value
	for key: Variant in recipe.keys():
		if typeof(key) != TYPE_STRING or not RECIPE_KEYS.has(str(key)):
			errors.append("Recipe contains an unsupported field: %s." % str(key))
	var required: PackedStringArray = ["scale", "mass_policy", "weight_multiplier", "power_multiplier", "control_multiplier"]
	for key: String in required:
		if not recipe.has(key):
			errors.append("Recipe is missing required field: %s." % key)
	if recipe.has("scale") and not _positive_number(recipe["scale"]):
		errors.append("Recipe scale must be a finite positive number.")
	if recipe.has("mass_policy") and (typeof(recipe["mass_policy"]) != TYPE_STRING or not ["constant_wing_loading", "geometric"].has(str(recipe["mass_policy"]))):
		errors.append("Recipe mass_policy must be constant_wing_loading or geometric.")
	for key: String in ["weight_multiplier", "power_multiplier", "control_multiplier"]:
		if recipe.has(key) and not _positive_number(recipe[key]):
			errors.append("Recipe %s must be a finite positive number." % key)
	if recipe.has("id") and (typeof(recipe["id"]) != TYPE_STRING or not _valid_uuid(str(recipe["id"]))):
		errors.append("Optional recipe ID must be a lowercase UUID.")
	if recipe.has("name") and not _valid_name(str(recipe["name"])):
		errors.append("Optional recipe name is invalid.")
	var tree_result: Dictionary = _validate_json_tree(recipe)
	if not bool(tree_result["ok"]):
		errors.append_array(tree_result["errors"])
	return _result(errors.is_empty(), errors)


static func _resolve_workshop_descriptor(
		base_id: String,
		base_bytes: PackedByteArray,
		provided: Dictionary
) -> Dictionary:
	if not provided.is_empty():
		var checked: Dictionary = WorkshopDescriptor.validate(provided, base_id, base_bytes)
		if not bool(checked["ok"]):
			return checked
		return {"ok": true, "errors": PackedStringArray(), "descriptor": checked["descriptor"]}
	var path: String = WorkshopDescriptor.DEFAULT_ROOT.path_join(base_id + ".json")
	if not FileAccess.file_exists(path):
		return {"ok": true, "errors": PackedStringArray(), "descriptor": {}}
	var loaded: Dictionary = WorkshopDescriptor.load_for(base_id, base_bytes)
	if not bool(loaded["ok"]):
		return loaded
	return {"ok": true, "errors": PackedStringArray(), "descriptor": loaded["descriptor"]}


static func _resolve_workshop_dependencies(base: Dictionary, provided: Dictionary) -> Dictionary:
	if provided.is_empty():
		return WorkshopDependencies.capture(base)
	return WorkshopDependencies.validate_manifest(base, provided)


static func _parse_base_snapshot(base_id: String, bytes: PackedByteArray) -> Dictionary:
	var errors := PackedStringArray()
	var text: String = bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes:
		errors.append("Base snapshot is not valid UTF-8.")
		return _result(false, errors)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(text)
	if parse_error != OK:
		errors.append("Base snapshot JSON could not be parsed: %s." % parser.get_error_message())
		return _result(false, errors)
	var value: Variant = parser.data
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("Base snapshot must be a JSON object.")
		return _result(false, errors)
	var tree_result: Dictionary = _validate_json_tree(value)
	if not bool(tree_result["ok"]):
		errors.append_array(tree_result["errors"])
		return _result(false, errors)
	var base: Dictionary = value
	if str(base.get("format", "")) != "openrc-aircraft v2":
		errors.append("Base snapshot must use the openrc-aircraft v2 schema.")
	if str(base.get("id", "")) != base_id:
		errors.append("Base snapshot ID does not match base_id.")
	return {"ok": errors.is_empty(), "errors": errors, "base": base}


static func _validate_json_tree(value: Variant, depth: int = 0, budget: Dictionary = {}) -> Dictionary:
	var errors := PackedStringArray()
	if budget.is_empty():
		budget["remaining"] = MAX_JSON_NODES
	if depth > MAX_JSON_DEPTH:
		errors.append("JSON document exceeds the maximum nesting depth.")
		return _result(false, errors)
	budget["remaining"] = int(budget["remaining"]) - 1
	if int(budget["remaining"]) < 0:
		errors.append("JSON document exceeds the maximum node count.")
		return _result(false, errors)
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return _result(true, errors)
		TYPE_FLOAT:
			if not is_finite(float(value)):
				errors.append("JSON document contains a non-finite number.")
		TYPE_ARRAY:
			for item: Variant in value:
				var nested: Dictionary = _validate_json_tree(item, depth + 1, budget)
				if not bool(nested["ok"]):
					errors.append_array(nested["errors"])
					break
		TYPE_DICTIONARY:
			for key: Variant in value.keys():
				if typeof(key) != TYPE_STRING:
					errors.append("JSON object keys must be strings.")
					break
				var nested: Dictionary = _validate_json_tree(value[key], depth + 1, budget)
				if not bool(nested["ok"]):
					errors.append_array(nested["errors"])
					break
		_:
			errors.append("JSON document contains a non-JSON value.")
	return _result(errors.is_empty(), errors)


static func _read_json_file(path: String) -> Dictionary:
	var errors := PackedStringArray()
	var bytes_result: Dictionary = _read_bytes(path, MAX_VARIANT_BYTES)
	if not bool(bytes_result["ok"]):
		errors.append_array(bytes_result["errors"])
		return _result(false, errors)
	var bytes: PackedByteArray = bytes_result["bytes"]
	var text: String = bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes:
		errors.append("Stored JSON is not valid UTF-8.")
		return _result(false, errors)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(text)
	if parse_error != OK:
		errors.append("Stored JSON could not be parsed: %s." % parser.get_error_message())
		return _result(false, errors)
	var tree_result: Dictionary = _validate_json_tree(parser.data)
	if not bool(tree_result["ok"]):
		errors.append_array(tree_result["errors"])
		return _result(false, errors)
	return {"ok": true, "errors": errors, "data": parser.data}


static func _read_bytes(path: String, max_bytes: int) -> Dictionary:
	var errors := PackedStringArray()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Could not open stored file: %s." % error_string(FileAccess.get_open_error()))
		return {"ok": false, "errors": errors}
	var length: int = file.get_length()
	if length <= 0 or length > max_bytes:
		file.close()
		errors.append("Stored file is empty or exceeds the %d-byte limit." % max_bytes)
		return {"ok": false, "errors": errors}
	var bytes: PackedByteArray = file.get_buffer(length)
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK or bytes.size() != length:
		errors.append("Could not read the complete stored file.")
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": errors, "bytes": bytes}


static func _write_new_file_atomic(path: String, bytes: PackedByteArray) -> Dictionary:
	var errors := PackedStringArray()
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		errors.append("Refusing to overwrite an existing immutable revision file.")
		return {"ok": false, "errors": errors}
	var temporary: String = path + ".tmp"
	if FileAccess.file_exists(temporary):
		var remove_error: Error = DirAccess.remove_absolute(temporary)
		if remove_error != OK:
			errors.append("Could not remove a stale revision temporary file.")
			return {"ok": false, "errors": errors}
	var write_result: Dictionary = _write_bytes(temporary, bytes)
	if not bool(write_result["ok"]):
		errors.append_array(write_result["errors"])
		return {"ok": false, "errors": errors}
	var readback: Dictionary = _read_bytes(temporary, MAX_VARIANT_BYTES)
	if not bool(readback["ok"]) or (readback.get("bytes", PackedByteArray()) as PackedByteArray) != bytes:
		DirAccess.remove_absolute(temporary)
		errors.append("Temporary revision failed its exact-byte readback check.")
		return {"ok": false, "errors": errors}
	var rename_error: Error = DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		errors.append("Could not commit immutable revision file (%s)." % error_string(rename_error))
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": errors}


static func _write_index_atomic(variant_dir: String, bytes: PackedByteArray) -> Dictionary:
	var errors := PackedStringArray()
	var index_path: String = variant_dir.path_join("manifest.json")
	var backup_path: String = index_path + ".bak"
	var temporary: String = index_path + ".tmp"
	if FileAccess.file_exists(temporary):
		var remove_error: Error = DirAccess.remove_absolute(temporary)
		if remove_error != OK:
			errors.append("Could not remove a stale manifest temporary file.")
			return {"ok": false, "errors": errors}
	var write_result: Dictionary = _write_bytes(temporary, bytes)
	if not bool(write_result["ok"]):
		errors.append_array(write_result["errors"])
		return {"ok": false, "errors": errors}
	var readback: Dictionary = _read_bytes(temporary, MAX_VARIANT_BYTES)
	if not bool(readback["ok"]) or (readback.get("bytes", PackedByteArray()) as PackedByteArray) != bytes:
		DirAccess.remove_absolute(temporary)
		errors.append("Temporary manifest failed its exact-byte readback check.")
		return {"ok": false, "errors": errors}
	var moved_current: bool = false
	if FileAccess.file_exists(index_path):
		if FileAccess.file_exists(backup_path):
			var remove_backup_error: Error = DirAccess.remove_absolute(backup_path)
			if remove_backup_error != OK:
				DirAccess.remove_absolute(temporary)
				errors.append("Could not rotate the prior manifest backup.")
				return {"ok": false, "errors": errors}
		var backup_error: Error = DirAccess.rename_absolute(index_path, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			errors.append("Could not preserve the previous manifest (%s)." % error_string(backup_error))
			return {"ok": false, "errors": errors}
		moved_current = true
	var commit_error: Error = DirAccess.rename_absolute(temporary, index_path)
	if commit_error != OK:
		if moved_current and not FileAccess.file_exists(index_path):
			DirAccess.rename_absolute(backup_path, index_path)
		DirAccess.remove_absolute(temporary)
		errors.append("Could not atomically commit the manifest (%s)." % error_string(commit_error))
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": errors}


static func _write_bytes(path: String, bytes: PackedByteArray) -> Dictionary:
	var errors := PackedStringArray()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("Could not open a temporary file for writing: %s." % error_string(FileAccess.get_open_error()))
		return {"ok": false, "errors": errors}
	file.store_buffer(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(path)
		errors.append("Could not flush the temporary file (%s)." % error_string(write_error))
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": errors}


static func _resolve_root(root: String) -> Dictionary:
	var errors := PackedStringArray()
	if not root.begins_with("user://") or root.contains("\\") or root.substr("user://".length()).contains(":"):
		errors.append("Variant store root must be a safe path under user://.")
		return {"ok": false, "errors": errors}
	var relative: String = root.substr("user://".length())
	while relative.ends_with("/"):
		relative = relative.substr(0, relative.length() - 1)
	if relative.is_empty():
		errors.append("Variant store root cannot be the user data directory itself.")
		return {"ok": false, "errors": errors}
	for segment: String in relative.split("/", false):
		if segment.is_empty() or segment == "." or segment == "..":
			errors.append("Variant store root contains an unsafe path segment.")
			return {"ok": false, "errors": errors}
		for index: int in range(segment.length()):
			var code: int = segment.unicode_at(index)
			var allowed: bool = (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 45 or code == 95 or code == 46
			if not allowed:
				errors.append("Variant store root contains an unsupported path character.")
				return {"ok": false, "errors": errors}
	var normalized: String = "user://" + relative
	var absolute: String = ProjectSettings.globalize_path(normalized)
	var user_absolute: String = ProjectSettings.globalize_path("user://")
	var normalized_lower: String = absolute.replace("\\", "/").to_lower()
	var user_lower: String = user_absolute.replace("\\", "/").trim_suffix("/").to_lower()
	if not normalized_lower.begins_with(user_lower + "/"):
		errors.append("Variant store root resolves outside user data.")
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": errors, "path": absolute.replace("\\", "/")}


static func _directory_names(path: String, directories_only: bool) -> PackedStringArray:
	var names := PackedStringArray()
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return names
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		if directory.current_is_dir() == directories_only:
			names.append(entry)
	directory.list_dir_end()
	return names


static func _next_revision(variant_dir: String) -> int:
	var maximum: int = 0
	var revisions_dir: String = variant_dir.path_join("revisions")
	for filename: String in _directory_names(revisions_dir, false):
		if not filename.ends_with(".json"):
			continue
		var prefix: String = filename.trim_suffix(".json")
		if prefix.is_valid_int():
			maximum = maxi(maximum, int(prefix))
	return maximum + 1


static func _make_directory(path: String) -> Error:
	if DirAccess.dir_exists_absolute(path):
		return OK
	return DirAccess.make_dir_recursive_absolute(path)


static func _valid_name(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and value.length() <= 96 and not value.contains("\n") and not value.contains("\r") and not value.contains("\t")


static func _valid_base_id(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	var first: int = value.unicode_at(0)
	if not ((first >= 48 and first <= 57) or (first >= 97 and first <= 122)):
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		var allowed: bool = (code >= 48 and code <= 57) or (code >= 97 and code <= 122) or code == 45 or code == 95 or code == 46
		if not allowed:
			return false
	return true


static func _valid_uuid(value: String) -> bool:
	if value.length() != 36:
		return false
	for index: int in range(36):
		var code: int = value.unicode_at(index)
		if index == 8 or index == 13 or index == 18 or index == 23:
			if code != 45:
				return false
		elif not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return value[14] == "4" and (value[19] == "8" or value[19] == "9" or value[19] == "a" or value[19] == "b")


static func _valid_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _positive_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and float(value) > 0.0


static func _integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	return floor(float(value)) == float(value)


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


static func _new_uuid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16:
		return ""
	bytes[6] = (int(bytes[6]) & 15) | 64
	bytes[8] = (int(bytes[8]) & 63) | 128
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


static func _result(ok: bool, errors: PackedStringArray, variant: Dictionary = {}) -> Dictionary:
	return {"ok": ok, "errors": errors, "variant": variant}
