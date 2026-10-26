extends RefCounted
## Portable, strict-JSON aircraft build envelope. The envelope contains data only;
## imported identifiers are validated before any registered model can be resolved.

const Store := preload("res://workshop/store.gd")
const Descriptor := preload("res://workshop/descriptor.gd")
const Dependencies := preload("res://workshop/dependencies.gd")
const Compiler := preload("res://workshop/compiler.gd")
const PresentationProfile := preload("res://workshop/presentation.gd")
const StrictJSON := preload("res://workshop/strict_json.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

const FORMAT: String = "openrc-aircraft-variant-bundle"
const VERSION: int = 1
const MAX_BUNDLE_BYTES: int = 24 * 1024 * 1024
const MAX_BUNDLE_DEPTH: int = 64
const MAX_BUNDLE_NODES: int = 250000
const BUNDLE_KEYS: PackedStringArray = [
	"format", "version", "name", "compiler_version", "base_id", "base_sha256",
	"recipe_sha256", "base_bytes_base64", "recipe", "workshop_descriptor", "dependencies",
	"presentation_profile",
]


static func export_variant(variant: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	if not _has_only_variant_fields(variant):
		errors.append("Saved variant has missing or unsupported fields for portable export.")
		return _result(false, errors)
	var base_bytes_value: Variant = variant.get("base_bytes", null)
	if typeof(base_bytes_value) != TYPE_PACKED_BYTE_ARRAY:
		errors.append("Saved variant has no exact base snapshot bytes.")
		return _result(false, errors)
	var base_bytes: PackedByteArray = base_bytes_value
	var base_id: String = str(variant.get("base_id", ""))
	var recipe: Dictionary = variant.get("recipe", {})
	var descriptor: Dictionary = variant.get("workshop_descriptor", {})
	var dependencies: Dictionary = variant.get("dependencies", {})
	var profile: Dictionary = variant.get("presentation_profile", PresentationProfile.defaults())
	var content: Dictionary = _validate_content(
		str(variant.get("name", "")), str(variant.get("compiler_version", "")), base_id,
		str(variant.get("base_sha256", "")), str(variant.get("recipe_sha256", "")),
		Marshalls.raw_to_base64(base_bytes), recipe, descriptor, dependencies, profile
	)
	if not bool(content.get("ok", false)):
		return content
	var payload: Dictionary = _bundle_payload(
		str(variant["name"]), str(variant["compiler_version"]), base_id,
		str(variant["base_sha256"]), str(variant["recipe_sha256"]),
		Marshalls.raw_to_base64(base_bytes), recipe, descriptor, dependencies, profile
	)
	var bytes: PackedByteArray = (JSON.stringify(payload, "\t", true, true) + "\n").to_utf8_buffer()
	if bytes.size() > MAX_BUNDLE_BYTES:
		errors.append("Portable variant exceeds the %d-byte limit." % MAX_BUNDLE_BYTES)
		return _result(false, errors)
	return {"ok": true, "errors": errors, "bytes": bytes}


## Decode and validate without writing to the library, changing preferences or resolving
## any bundle-selected path. Suitable for a CLI trial path that remains detached.
static func decode(bytes: PackedByteArray) -> Dictionary:
	var parsed: Dictionary = StrictJSON.parse(bytes, MAX_BUNDLE_BYTES, MAX_BUNDLE_DEPTH, MAX_BUNDLE_NODES)
	if not bool(parsed.get("ok", false)):
		return _result(false, parsed.get("errors", PackedStringArray()))
	var value: Variant = parsed.get("data", null)
	if typeof(value) != TYPE_DICTIONARY or not _exact_keys(value, BUNDLE_KEYS):
		return _failure("Portable variant bundle has missing or unsupported fields.")
	for key: String in ["name", "compiler_version", "base_id", "base_sha256", "recipe_sha256", "base_bytes_base64"]:
		if typeof(value.get(key, null)) != TYPE_STRING:
			return _failure("Portable variant bundle field '%s' must be a string." % key)
	for key: String in ["recipe", "workshop_descriptor", "dependencies", "presentation_profile"]:
		if typeof(value.get(key, null)) != TYPE_DICTIONARY:
			return _failure("Portable variant bundle field '%s' must be an object." % key)
	if value.get("format", null) != FORMAT or not _integer_number(value.get("version", null)) \
			or int(value["version"]) != VERSION:
		return _failure("Portable variant bundle format or version is unsupported.")
	var content: Dictionary = _validate_content(
		str(value.get("name", "")), str(value.get("compiler_version", "")), str(value.get("base_id", "")),
		str(value.get("base_sha256", "")), str(value.get("recipe_sha256", "")),
		str(value.get("base_bytes_base64", "")), value.get("recipe", null),
		value.get("workshop_descriptor", null), value.get("dependencies", null),
		value.get("presentation_profile", null)
	)
	if not bool(content.get("ok", false)):
		return content
	var payload: Dictionary = {
		"format": FORMAT,
		"version": VERSION,
		"name": str(value["name"]),
		"compiler_version": str(value["compiler_version"]),
		"base_id": str(value["base_id"]),
		"base_bytes": content["base_bytes"],
		"base_sha256": str(value["base_sha256"]),
		"recipe": _physical_recipe(value["recipe"]),
		"recipe_sha256": str(value["recipe_sha256"]),
		"base": content["base"],
		"workshop_descriptor": (value["workshop_descriptor"] as Dictionary).duplicate(true),
		"dependencies": (value["dependencies"] as Dictionary).duplicate(true),
		"presentation_profile": content["profile"].duplicate(true),
		"presentation_profile_available": bool(content.get("profile_available", false)),
		"variant_id": "",
		"variant_revision": 0,
	}
	return {"ok": true, "errors": PackedStringArray(), "payload": payload,
		"compiler_compatible": str(value["compiler_version"]) == Compiler.version_for_recipe(value["recipe"]),
		"presentation_profile_available": bool(content.get("profile_available", false))}


## Read a user-selected local file through FileAccess only. Resource URI schemes are
## deliberately rejected; bundle contents never become ResourceLoader paths.
static func read_file(path: String) -> Dictionary:
	if path.is_empty() or path.contains("://") or path.to_utf8_buffer().has(0):
		return _failure("Portable bundle path must be a local filesystem path.")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Portable bundle could not be opened: %s." % error_string(FileAccess.get_open_error()))
	var length: int = file.get_length()
	if length <= 0 or length > MAX_BUNDLE_BYTES:
		file.close()
		return _failure("Portable bundle is empty or exceeds the %d-byte limit." % MAX_BUNDLE_BYTES)
	var bytes: PackedByteArray = file.get_buffer(length)
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK or bytes.size() != length:
		return _failure("Portable bundle could not be read completely.")
	var decoded: Dictionary = decode(bytes)
	if bool(decoded.get("ok", false)):
		decoded["bundle_bytes"] = bytes
	return decoded


static func import_variant(bytes: PackedByteArray, store_root: String = Store.DEFAULT_ROOT) -> Dictionary:
	var decoded: Dictionary = decode(bytes)
	if not bool(decoded.get("ok", false)):
		return decoded
	var payload: Dictionary = decoded["payload"]
	if str(payload.get("compiler_version", "")) != Compiler.version_for_recipe(payload.recipe):
		return _failure("This bundle is pinned to a different Workshop compiler version and cannot be imported without migration.")
	var profile_check: Dictionary = PresentationProfile.validate_stored(payload.get("presentation_profile", null))
	if not bool(profile_check.get("ok", false)) or bool(profile_check.get("newer_version", false)):
		return _failure("This bundle uses an unsupported presentation profile version and cannot be imported by this app.")
	var current_profile: Dictionary = _resolve_current_profile(payload)
	if not bool(current_profile.get("ok", false)):
		return current_profile
	# Complete candidate validation precedes publication, including stable component IDs.
	var candidate := payload.duplicate(true)
	candidate["presentation_profile"] = current_profile["profile"].duplicate(true)
	var frozen: Dictionary = load("res://workshop/trial.gd").freeze(candidate)
	if not bool(frozen.get("ok", false)):
		return _result(false, frozen.get("errors", PackedStringArray()))
	var recipe: Dictionary = payload["recipe"].duplicate(true)
	recipe.erase("id")
	if recipe.has("name"):
		recipe["name"] = str(payload["name"])
	var saved: Dictionary = Store.save_variant(
		str(payload["name"]), str(payload["base_id"]), payload["base_bytes"], recipe,
		"", store_root, payload["workshop_descriptor"], payload["dependencies"], -1,
		current_profile["profile"]
	)
	if not bool(saved.get("ok", false)):
		return saved
	return {"ok": true, "errors": PackedStringArray(), "variant": saved["variant"],
		"source_format": FORMAT}


static func import_file(path: String, store_root: String = Store.DEFAULT_ROOT) -> Dictionary:
	var read: Dictionary = read_file(path)
	if not bool(read.get("ok", false)):
		return read
	var bytes: PackedByteArray = read["bundle_bytes"]
	return import_variant(bytes, store_root)


static func _resolve_current_profile(payload: Dictionary) -> Dictionary:
	var physical: Dictionary = Descriptor.verify_presentation(payload["workshop_descriptor"])
	if not bool(physical.get("ok", false)):
		return physical
	if not ResourceLoader.exists("res://render/aircraft_customization.gd"):
		var legacy: Dictionary = PresentationProfile.validate(payload["presentation_profile"])
		if not bool(legacy.get("ok", false)) or not bool(legacy.get("available", false)):
			return _failure("The current customization companion is required for this profile.")
		if not _is_unbound_stock_profile(legacy["profile"]):
			return _failure("The current customization companion is required for this pinned profile.")
		return {"ok": true, "errors": PackedStringArray(), "profile": legacy["profile"]}
	var customization: Script = load("res://render/aircraft_customization.gd")
	var described: Dictionary = customization.describe(str(payload["base_id"]))
	if not bool(described.get("ok", false)) or typeof(described.get("bindings", null)) != TYPE_DICTIONARY:
		var unavailable: Dictionary = PresentationProfile.validate(payload["presentation_profile"])
		if not bool(unavailable.get("ok", false)) or not bool(unavailable.get("available", false)) \
				or not _is_unbound_stock_profile(unavailable["profile"]):
			return _failure("The registered customization companion is unavailable for this bundle.")
		return {"ok": true, "errors": PackedStringArray(), "profile": unavailable["profile"]}
	var bindings: Dictionary = described["bindings"]
	if str(physical["manifest"].get("family_id", "")) != str(bindings.get("visual_family", "")) \
			or str(physical.get("manifest_sha256", "")) != str(bindings.get("model_manifest_sha256", "")):
		return _failure("The bundle's model manifest no longer matches the registered customization slots.")
	var checked: Dictionary = PresentationProfile.validate(payload["presentation_profile"], bindings)
	if not bool(checked.get("ok", false)):
		return checked
	if not bool(checked.get("available", false)):
		return _failure("The bundle's presentation profile is unavailable for the current aircraft.")
	return {"ok": true, "errors": PackedStringArray(), "profile": checked["profile"]}


static func _validate_content(name: String, compiler_version: String, base_id: String,
		base_sha256: String, recipe_sha256: String, base_bytes_base64: String,
		recipe_value: Variant, descriptor_value: Variant, dependencies_value: Variant,
		profile_value: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if not _valid_name(name):
		errors.append("Bundle build name is invalid.")
	if compiler_version.strip_edges().is_empty() or compiler_version.length() > 128:
		errors.append("Bundle compiler version is malformed.")
	if not Catalog.has(base_id) or Catalog.is_rotorcraft(base_id):
		errors.append("Bundle base ID is not a registered fixed-wing aircraft.")
	if not _valid_sha256(base_sha256) or not _valid_sha256(recipe_sha256):
		errors.append("Bundle source or recipe SHA-256 is malformed.")
	if base_bytes_base64.is_empty() or base_bytes_base64.length() > Store.MAX_BASE_BYTES * 2:
		errors.append("Bundle base snapshot is missing or exceeds its encoded size limit.")
	if typeof(recipe_value) != TYPE_DICTIONARY:
		errors.append("Bundle physical recipe must be an object.")
	if typeof(descriptor_value) != TYPE_DICTIONARY or (descriptor_value as Dictionary).is_empty():
		errors.append("Portable bundle requires its exact Workshop descriptor pins.")
	if typeof(dependencies_value) != TYPE_DICTIONARY or (dependencies_value as Dictionary).is_empty():
		errors.append("Portable bundle requires its exact Workshop dependency pins.")
	if not errors.is_empty():
		return _result(false, errors)
	var base_bytes: PackedByteArray = Marshalls.base64_to_raw(base_bytes_base64)
	if base_bytes.is_empty() or base_bytes.size() > Store.MAX_BASE_BYTES \
			or Marshalls.raw_to_base64(base_bytes) != base_bytes_base64:
		errors.append("Bundle base snapshot encoding is malformed or exceeds the byte limit.")
		return _result(false, errors)
	var base_hash: String = _sha256(base_bytes)
	if base_hash != base_sha256:
		errors.append("Bundle base SHA-256 does not match the exact embedded bytes.")
	var strict_base: Dictionary = StrictJSON.parse(base_bytes, Store.MAX_BASE_BYTES, Store.MAX_JSON_DEPTH, Store.MAX_JSON_NODES)
	if not bool(strict_base.get("ok", false)) or typeof(strict_base.get("data", null)) != TYPE_DICTIONARY:
		errors.append_array(strict_base.get("errors", PackedStringArray(["Embedded base snapshot is invalid JSON."])))
		return _result(false, errors)
	var base: Dictionary = strict_base["data"]
	var parsed_base: Dictionary = Store._parse_base_snapshot(base_id, base_bytes)
	if not bool(parsed_base.get("ok", false)):
		errors.append_array(parsed_base.get("errors", PackedStringArray()))
	var aircraft_check: Dictionary = AircraftData.validate_and_derive(base)
	if not bool(aircraft_check.get("ok", false)):
		errors.append_array(aircraft_check.get("errors", PackedStringArray()))
	var recipe: Dictionary = recipe_value
	var recipe_check: Dictionary = Store._validate_recipe(recipe)
	if not bool(recipe_check.get("ok", false)):
		errors.append_array(recipe_check.get("errors", PackedStringArray()))
	if recipe.has("name") and recipe["name"] != name:
		errors.append("Bundle recipe display name does not match the build name.")
	if _sha256(JSON.stringify(recipe, "", true, true).to_utf8_buffer()) != recipe_sha256:
		errors.append("Bundle recipe SHA-256 does not match the canonical stored recipe.")
	var descriptor: Dictionary = descriptor_value
	var descriptor_check: Dictionary = Descriptor.validate(descriptor, base_id, base_bytes)
	if not bool(descriptor_check.get("ok", false)):
		errors.append_array(descriptor_check.get("errors", PackedStringArray()))
	var dependencies: Dictionary = dependencies_value
	var dependencies_check: Dictionary = Dependencies.validate_manifest(base, dependencies)
	if not bool(dependencies_check.get("ok", false)):
		errors.append_array(dependencies_check.get("errors", PackedStringArray()))
	var profile_check: Dictionary = PresentationProfile.validate_stored(profile_value)
	if not bool(profile_check.get("ok", false)):
		errors.append_array(profile_check.get("errors", PackedStringArray()))
	if not errors.is_empty():
		return _result(false, errors)
	return {"ok": true, "errors": errors, "base": base.duplicate(true), "base_bytes": base_bytes,
		"profile": profile_check["profile"].duplicate(true),
		"profile_available": bool(profile_check.get("available", false))}


static func _bundle_payload(name: String, compiler_version: String, base_id: String,
		base_sha256: String, recipe_sha256: String, base_bytes_base64: String,
		recipe: Dictionary, descriptor: Dictionary, dependencies: Dictionary,
		profile: Dictionary) -> Dictionary:
	return {
		"format": FORMAT,
		"version": VERSION,
		"name": name,
		"compiler_version": compiler_version,
		"base_id": base_id,
		"base_sha256": base_sha256,
		"recipe_sha256": recipe_sha256,
		"base_bytes_base64": base_bytes_base64,
		"recipe": recipe.duplicate(true),
		"workshop_descriptor": descriptor.duplicate(true),
		"dependencies": dependencies.duplicate(true),
		"presentation_profile": profile.duplicate(true),
	}


static func _physical_recipe(value: Dictionary) -> Dictionary:
	var recipe: Dictionary = value.duplicate(true)
	# Variant UUID and display name are local metadata. Excluding them keeps the
	# detached physical trial identity equal across a new local UUID import.
	recipe.erase("id")
	recipe.erase("name")
	return recipe


static func _has_only_variant_fields(variant: Dictionary) -> bool:
	var allowed: PackedStringArray = [
		"id", "revision", "name", "compiler_version", "base_id", "recipe", "base", "base_bytes",
		"base_sha256", "recipe_sha256", "created_at_unix", "updated_at_unix",
		"recovered_from_manifest_backup", "presentation_profile", "presentation_profile_available",
		"workshop_descriptor", "dependencies",
	]
	var required: PackedStringArray = [
		"id", "revision", "name", "compiler_version", "base_id", "recipe", "base", "base_bytes",
		"base_sha256", "recipe_sha256",
	]
	if not variant.has_all(required):
		return false
	for key: Variant in variant.keys():
		if typeof(key) != TYPE_STRING or not allowed.has(str(key)):
			return false
	return true


static func _is_unbound_stock_profile(profile: Dictionary) -> bool:
	var binding: Dictionary = profile.get("binding", {})
	return binding.get("visual_family", "") == "" and binding.get("model_manifest_sha256", "") == "" \
		and binding.get("slots_sha256", "") == "" \
		and (profile.get("paint", []) as Array).is_empty() \
		and (profile.get("markings", []) as Array).is_empty() \
		and (profile.get("smoke", []) as Array).is_empty() \
		and profile.get("lighting", {}).get("selection", "inherit") == "inherit" \
		and profile.get("mechanical_audio", PresentationProfile.MechanicalProfile.defaults()) == PresentationProfile.MechanicalProfile.defaults() \
		and int(profile.get("visual_seed", 0)) == 0


static func _valid_name(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and value.length() <= 96 \
		and not value.contains("\n") and not value.contains("\r")


static func _valid_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	return floor(float(value)) == float(value) and abs(float(value)) <= 9007199254740991.0


static func _exact_keys(value: Dictionary, expected: PackedStringArray) -> bool:
	if value.size() != expected.size() or not value.has_all(expected):
		return false
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or not expected.has(str(key)):
			return false
	return true


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


static func _failure(message: String) -> Dictionary:
	return _result(false, PackedStringArray([message]))


static func _result(ok: bool, errors: PackedStringArray) -> Dictionary:
	return {"ok": ok, "errors": errors}
