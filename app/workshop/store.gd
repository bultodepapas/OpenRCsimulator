extends RefCounted
## Durable local storage for immutable aircraft variant snapshots.
## All writes stay under user:// so shipped aircraft resources remain read-only.

const WorkshopDescriptor = preload("res://workshop/descriptor.gd")
const WorkshopDependencies = preload("res://workshop/dependencies.gd")
const WorkshopCompiler = preload("res://workshop/compiler.gd")
const WorkshopParameters = preload("res://workshop/parameters.gd")
const PresentationProfile = preload("res://workshop/presentation.gd")
const DEFAULT_ROOT: String = "user://aircraft_variants"
const VARIANT_FORMAT: String = "openrc-aircraft-variant"
const LEGACY_VARIANT_VERSION: int = 1
const VARIANT_VERSION: int = 2
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
	"tank_capacity_multiplier",
	"mass_edits",
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
	"presentation_profile",
]
const LEGACY_VARIANT_REQUIRED_KEYS: PackedStringArray = [
	"format",
	"version", "id", "revision", "name", "compiler_version", "base_id", "recipe",
	"base_sha256", "recipe_sha256", "base_bytes_base64", "created_at_unix", "updated_at_unix",
]
const VARIANT_REQUIRED_KEYS: PackedStringArray = [
	"format", "version",
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
	"presentation_profile",
]
const INDEX_KEYS: PackedStringArray = ["format", "version", "id", "revision"]


class VariantWriteGuard extends RefCounted:
	var directory: String
	var acquired := false

	func _init(root_path: String, id: String) -> void:
		var locks_root := root_path.path_join("_locks")
		if DirAccess.make_dir_recursive_absolute(locks_root) != OK:
			return
		directory = locks_root.path_join(id)
		# Unlike check-then-rename, directory creation exclusively reserves this ID.
		acquired = DirAccess.make_dir_absolute(directory) == OK

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and acquired:
			DirAccess.remove_absolute(directory)


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
		dependencies: Dictionary = {},
		expected_revision: int = -1,
		presentation_profile: Dictionary = {}
) -> Dictionary:
	return _save_variant(name, base_id, base_bytes, recipe, id, root,
		workshop_descriptor, dependencies, expected_revision, presentation_profile)


## Private transaction seam for interruption tests. Production saves have no observer,
## global failpoint or persisted setting; false leaves the on-disk prefix for rereading.
static func _save_variant(
		name: String,
		base_id: String,
		base_bytes: PackedByteArray,
		recipe: Dictionary,
		id: String,
		root: String,
		workshop_descriptor: Dictionary,
		dependencies: Dictionary,
		expected_revision: int,
		presentation_profile: Dictionary,
		checkpoint: Callable = Callable()
) -> Dictionary:
	var errors := PackedStringArray()
	if expected_revision < -1:
		errors.append("Expected revision must be -1 or a non-negative integer.")
		return _result(false, errors)
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
	if errors.is_empty() and recipe.has("mass_edits") and not recipe.mass_edits.is_empty():
		var measured_candidate: Dictionary = WorkshopCompiler.compile(base_parsed, recipe)
		if not measured_candidate.ok: errors.append_array(measured_candidate.errors)
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
	var write_guard := VariantWriteGuard.new(root_path, safe_id)
	if not write_guard.acquired:
		return _result(false, PackedStringArray(["This variant is busy or its write lock is unavailable. Retry or save a copy; the saved variant is unchanged."]))
	var existing_variant: Dictionary = {}
	var stored_descriptor: Dictionary = {}
	var stored_dependencies: Dictionary = {}
	var stored_compiler_version: String = WorkshopCompiler.version_for_recipe(recipe)
	var revision: int = 1
	var previous_revision: int = 0
	var is_existing_variant: bool = false
	var created_at: int = int(Time.get_unix_time_from_system())
	var directory_exists: bool = DirAccess.dir_exists_absolute(variant_dir)
	var file_exists: bool = FileAccess.file_exists(variant_dir)
	if directory_exists:
		var existing_result: Dictionary = _load_from_directory(variant_dir, safe_id)
		if not bool(existing_result["ok"]):
			errors.append("Existing variant ID cannot be updated: %s" % "; ".join(existing_result["errors"]))
			return _result(false, errors)
		existing_variant = existing_result["variant"]
		is_existing_variant = true
		previous_revision = int(existing_variant["revision"])
		if expected_revision < 0:
			errors.append("Expected revision is required when updating a saved variant.")
			return _result(false, errors)
		if previous_revision != expected_revision:
			errors.append("Saved variant changed from expected revision %d to revision %d; reload before saving." % [expected_revision, previous_revision])
			return _result(false, errors)
		var pinned_compiler_version: String = str(existing_variant.get("compiler_version", ""))
		if pinned_compiler_version != WorkshopCompiler.version_for_recipe(recipe):
			errors.append("This variant is pinned to compiler %s; create a new variant with Save a copy to use compiler %s." % [pinned_compiler_version, WorkshopCompiler.version_for_recipe(recipe)])
			return _result(false, errors)
		stored_compiler_version = pinned_compiler_version
		if str(existing_variant["base_id"]) != base_id or str(existing_variant["base_sha256"]) != base_hash:
			errors.append("A saved variant's base ID and exact base snapshot are immutable.")
			return _result(false, errors)
		if (existing_variant["base_bytes"] as PackedByteArray) != base_bytes:
			errors.append("A saved variant's exact base snapshot is immutable.")
			return _result(false, errors)
		var has_pinned_descriptor: bool = existing_variant.has("workshop_descriptor")
		var pinned_descriptor: Dictionary = existing_variant.get("workshop_descriptor", {})
		if has_pinned_descriptor:
			if not workshop_descriptor.is_empty() and workshop_descriptor != pinned_descriptor:
				errors.append("A saved variant's Workshop descriptor is immutable.")
				return _result(false, errors)
			stored_descriptor = pinned_descriptor.duplicate(true)
		elif not workshop_descriptor.is_empty():
			errors.append("A saved variant without a pinned Workshop descriptor cannot add one; create a new variant to change its pins.")
			return _result(false, errors)
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
	elif file_exists:
		errors.append("Variant ID collides with a file in the local store.")
		return _result(false, errors)
	elif expected_revision > 0:
		errors.append("Expected saved revision %d, but this variant ID no longer exists; reload before saving." % expected_revision)
		return _result(false, errors)
	if stored_descriptor.is_empty() and not is_existing_variant:
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
	var profile_for_save: Dictionary = {}
	if is_existing_variant and presentation_profile.is_empty():
		profile_for_save = (existing_variant.get("presentation_profile", PresentationProfile.defaults()) as Dictionary).duplicate(true)
	else:
		var companion_result: Dictionary = _resolve_customization_bindings(base_id, stored_descriptor)
		if bool(companion_result.get("ok", false)):
			var profile_result: Dictionary = PresentationProfile.validate(presentation_profile, companion_result["bindings"])
			if not bool(profile_result.get("ok", false)):
				errors.append_array(profile_result.get("errors", PackedStringArray()))
				return _result(false, errors)
			profile_for_save = profile_result["profile"]
			if is_existing_variant:
				var existing_profile: Dictionary = existing_variant.get("presentation_profile", PresentationProfile.defaults())
				var existing_checked: Dictionary = PresentationProfile.validate_stored(existing_profile)
				if not bool(existing_checked.get("ok", false)):
					errors.append_array(existing_checked.get("errors", PackedStringArray()))
					return _result(false, errors)
				if bool(existing_checked.get("newer_version", false)):
					errors.append("This variant uses a newer presentation profile version; this app cannot edit or replace it.")
					return _result(false, errors)
				var old_profile: Dictionary = existing_checked.get("profile", PresentationProfile.defaults())
				var old_pins: Dictionary = old_profile.get("binding", {})
				var new_pins: Dictionary = profile_for_save.get("binding", {})
				if (not _presentation_is_empty(old_profile) or not _presentation_pins_are_empty(old_pins)) \
						and old_pins != new_pins:
					errors.append("A customized presentation cannot be rebound to a different model or slot contract; save a copy instead.")
					return _result(false, errors)
		else:
			if not bool(companion_result.get("missing", false)):
				errors.append_array(companion_result.get("errors", PackedStringArray()))
				return _result(false, errors)
			var profile_result: Dictionary = PresentationProfile.validate(presentation_profile)
			if not bool(profile_result.get("ok", false)) or not bool(profile_result.get("available", false)):
				errors.append_array(profile_result.get("errors", PackedStringArray()))
				if errors.is_empty():
					errors.append("The registered customization companion is unavailable; only the legacy empty appearance can be saved.")
				return _result(false, errors)
			profile_for_save = profile_result["profile"]
	var write_dir: String = variant_dir
	if not is_existing_variant:
		var staging_root: String = root_path.path_join("_staging")
		root_error = _make_directory(staging_root)
		if root_error != OK:
			errors.append("Could not create the first-save staging directory (%s)." % error_string(root_error))
			return _result(false, errors)
		var staging_dir: String = ""
		for attempt: int in range(4):
			var staging_nonce: String = _new_uuid()
			if staging_nonce.is_empty():
				break
			var candidate: String = staging_root.path_join(safe_id + "-" + staging_nonce)
			if DirAccess.make_dir_absolute(candidate) == OK:
				staging_dir = candidate
				break
		if staging_dir.is_empty():
			errors.append("Could not reserve a unique first-save staging directory.")
			return _result(false, errors)
		write_dir = staging_dir
		if not _continue_save(checkpoint, "after_staging_create"):
			return _interrupted_save("after_staging_create")
	var revisions_dir: String = write_dir.path_join("revisions")
	root_error = _make_directory(revisions_dir)
	if root_error != OK:
		errors.append("Could not create the variant revisions directory (%s)." % error_string(root_error))
		return _result(false, errors)
	if not _continue_save(checkpoint, "after_revisions_create"):
		return _interrupted_save("after_revisions_create")
	var now: int = maxi(created_at, int(Time.get_unix_time_from_system()))
	var stored_recipe: Dictionary = recipe.duplicate(true)
	# JSON parses every number as float. Hash the representation that will be
	# read back, while retaining optional metadata and historical recipe ranges.
	for key: String in ["scale", "weight_multiplier", "power_multiplier", "control_multiplier", "tank_capacity_multiplier"]:
		if stored_recipe.has(key):
			stored_recipe[key] = float(stored_recipe[key])
	if stored_recipe.has("mass_edits"):
		var normalized: Dictionary = WorkshopParameters.validate(stored_recipe)
		if normalized.values.has("mass_edits"): stored_recipe["mass_edits"] = normalized.values.mass_edits.duplicate(true)
		else: stored_recipe.erase("mass_edits")
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
		"presentation_profile": profile_for_save.duplicate(true),
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
	var write_result: Dictionary = _write_new_file_atomic(revision_path, record_bytes, checkpoint)
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
	var index_result: Dictionary = _write_index_atomic(write_dir, index_bytes, safe_id, previous_revision, checkpoint)
	if not bool(index_result["ok"]):
		errors.append_array(index_result["errors"])
		return _result(false, errors)
	var loaded: Dictionary = _load_from_directory(write_dir, safe_id)
	if not bool(loaded["ok"]):
		errors.append_array(loaded["errors"])
		return _result(false, errors)
	if int(loaded.variant.get("revision", 0)) != revision or str(loaded.variant.get("recipe_sha256", "")) != recipe_hash \
			or bool(loaded.variant.get("recovered_from_manifest_backup", false)):
		return _result(false, PackedStringArray(["New variant revision failed exact readback; the previous record remains recoverable."]))
	if not is_existing_variant:
		if not _continue_save(checkpoint, "before_first_publish"):
			return _interrupted_save("before_first_publish")
		var publication: Dictionary = _publish_staged_variant(write_dir, variant_dir, safe_id)
		if not bool(publication["ok"]):
			errors.append_array(publication["errors"])
			return _result(false, errors)
		loaded = publication
		if not _continue_save(checkpoint, "after_first_publish"):
			return _interrupted_save("after_first_publish")
	return _result(true, PackedStringArray(), loaded["variant"])


static func _publish_staged_variant(
		staging_dir: String,
		variant_dir: String,
		expected_id: String,
		before_publish: Callable = Callable()
) -> Dictionary:
	var errors := PackedStringArray()
	if not DirAccess.dir_exists_absolute(staging_dir):
		errors.append("The complete first-save staging directory is unavailable.")
		return _result(false, errors)
	var staged: Dictionary = _load_from_directory(staging_dir, expected_id)
	if not bool(staged["ok"]):
		errors.append("First-save staging failed validation: " + "; ".join(staged["errors"]))
		return _result(false, errors)
	if DirAccess.dir_exists_absolute(variant_dir) or FileAccess.file_exists(variant_dir):
		errors.append("Variant ID became occupied before first-save publication; staged data was not promoted.")
		return _result(false, errors)
	# Tests can inject a one-shot interruption at the publication boundary without
	# mutating a global failpoint or exposing a switch on the public save API.
	if before_publish.is_valid() and not bool(before_publish.call()):
		errors.append("First-save publication was interrupted before the directory rename.")
		return _result(false, errors)
	if DirAccess.dir_exists_absolute(variant_dir) or FileAccess.file_exists(variant_dir):
		errors.append("Variant ID became occupied before first-save publication; staged data was not promoted.")
		return _result(false, errors)
	var rename_error: Error = DirAccess.rename_absolute(staging_dir, variant_dir)
	if rename_error != OK:
		errors.append("Could not publish the complete first-save directory (%s)." % error_string(rename_error))
		return _result(false, errors)
	var published: Dictionary = _load_from_directory(variant_dir, expected_id)
	if not bool(published["ok"]):
		var rollback_error: Error = DirAccess.rename_absolute(variant_dir, staging_dir)
		if rollback_error != OK:
			errors.append("Published directory failed readback and could not return to staging (%s)." % error_string(rollback_error))
		errors.append_array(published["errors"])
		return _result(false, errors)
	return published


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


static func delete_variant(id: String, root: String = DEFAULT_ROOT, expected_revision: int = -1) -> Dictionary:
	var errors := PackedStringArray()
	if expected_revision < -1:
		errors.append("Expected revision must be -1 or a non-negative integer.")
		return _result(false, errors)
	var root_result: Dictionary = _resolve_root(root)
	if not bool(root_result["ok"]):
		errors.append_array(root_result["errors"])
		return _result(false, errors)
	if not _valid_uuid(id):
		errors.append("Variant ID must be a lowercase UUID.")
		return _result(false, errors)
	var root_path: String = root_result["path"]
	var write_guard := VariantWriteGuard.new(root_path, id)
	if not write_guard.acquired:
		return _result(false, PackedStringArray(["This variant is busy or its write lock is unavailable. Retry after the other operation finishes."]))
	var variant_dir: String = root_path.path_join(id)
	var loaded: Dictionary = _load_from_directory(variant_dir, id)
	if not bool(loaded["ok"]):
		errors.append_array(loaded["errors"])
		return _result(false, errors)
	var current_revision: int = int(loaded["variant"]["revision"])
	if expected_revision >= 0 and current_revision != expected_revision:
		errors.append("Saved variant changed from expected revision %d to revision %d; reload before deleting." % [expected_revision, current_revision])
		return _result(false, errors)
	var trash_root: String = root_path.path_join("_trash")
	var err: Error = _make_directory(trash_root)
	if err != OK:
		errors.append("Could not create the local trash directory (%s)." % error_string(err))
		return _result(false, errors)
	var generation: String = ""
	var trash_path: String = ""
	for attempt: int in range(4):
		generation = _new_uuid()
		if generation.is_empty():
			break
		trash_path = trash_root.path_join(id + "-" + generation)
		if not DirAccess.dir_exists_absolute(trash_path) and not FileAccess.file_exists(trash_path):
			break
		trash_path = ""
	if generation.is_empty() or trash_path.is_empty():
		errors.append("Could not reserve a unique local trash generation.")
		return _result(false, errors)
	err = DirAccess.rename_absolute(variant_dir, trash_path)
	if err != OK:
		errors.append("Could not move the variant to local trash (%s)." % error_string(err))
		return _result(false, errors)
	return _result(true, PackedStringArray(), loaded["variant"], generation)


static func restore_variant(id: String, root: String = DEFAULT_ROOT, generation: String = "") -> Dictionary:
	var errors := PackedStringArray()
	var root_result: Dictionary = _resolve_root(root)
	if not bool(root_result["ok"]):
		errors.append_array(root_result["errors"])
		return _result(false, errors)
	if not _valid_uuid(id):
		errors.append("Variant ID must be a lowercase UUID.")
		return _result(false, errors)
	if not generation.is_empty() and not _valid_uuid(generation):
		errors.append("Trash generation must be a lowercase UUID returned by delete.")
		return _result(false, errors)
	var root_path: String = root_result["path"]
	var write_guard := VariantWriteGuard.new(root_path, id)
	if not write_guard.acquired:
		return _result(false, PackedStringArray(["This variant is busy or its write lock is unavailable. Retry after the other operation finishes."]))
	var live_path: String = root_path.path_join(id)
	if DirAccess.dir_exists_absolute(live_path) or FileAccess.file_exists(live_path):
		errors.append("A live variant with this ID already exists.")
		return _result(false, errors)
	var trash_root: String = root_path.path_join("_trash")
	var candidate_name: String = ""
	if not generation.is_empty():
		candidate_name = id + "-" + generation
		if not DirAccess.dir_exists_absolute(trash_root.path_join(candidate_name)):
			errors.append("The requested trash generation does not exist.")
			return _result(false, errors)
	else:
		var candidates: Array[String] = []
		for entry: String in _directory_names(trash_root, true):
			if _is_trash_generation_entry(entry, id):
				candidates.append(entry)
		if candidates.is_empty():
			errors.append("No trash generation with this ID was found.")
			return _result(false, errors)
		if candidates.size() != 1:
			errors.append("Multiple trash generations exist for this ID; supply the exact generation returned by delete.")
			return _result(false, errors)
		candidate_name = candidates[0]
	var candidate: String = trash_root.path_join(candidate_name)
	var loaded: Dictionary = _load_from_directory(candidate, id)
	if not bool(loaded["ok"]):
		errors.append_array(loaded["errors"])
		return _result(false, errors)
	var err: Error = DirAccess.rename_absolute(candidate, live_path)
	if err != OK:
		errors.append("Could not restore the variant from local trash (%s)." % error_string(err))
		return _result(false, errors)
	return _load_from_directory(live_path, id)


static func _is_trash_generation_entry(entry: String, id: String) -> bool:
	if entry == id:
		return true
	if not entry.begins_with(id + "-"):
		return false
	var suffix: String = entry.substr(id.length() + 1)
	if _valid_uuid(suffix):
		return true
	# Retain compatibility with generation folders written by variant store v1.
	if suffix.length() != 19 or suffix[10] != "-":
		return false
	for index: int in range(10):
		var code: int = suffix.unicode_at(index)
		if code < 48 or code > 57:
			return false
	for index: int in range(11, 19):
		var code: int = suffix.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _load_from_directory(variant_dir: String, expected_id: String) -> Dictionary:
	var manifest_path: String = variant_dir.path_join("manifest.json")
	var current: Dictionary = _load_from_manifest_source(variant_dir, expected_id, manifest_path, false)
	if bool(current["ok"]):
		return current
	var backup_path: String = manifest_path + ".bak"
	if not FileAccess.file_exists(backup_path):
		return current
	var backup: Dictionary = _load_from_manifest_source(variant_dir, expected_id, backup_path, true)
	if bool(backup["ok"]):
		return backup
	var errors: PackedStringArray = current["errors"]
	errors.append("Manifest backup recovery also failed: " + "; ".join(backup["errors"]))
	return _result(false, errors)


static func _load_from_manifest_source(
		variant_dir: String,
		expected_id: String,
		manifest_source: String,
		recovered: bool
) -> Dictionary:
	var errors := PackedStringArray()
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
	var stored_profile: Dictionary = PresentationProfile.defaults()
	var stored_profile_available: bool = true
	if record.has("presentation_profile"):
		var profile_result: Dictionary = PresentationProfile.validate_stored(record["presentation_profile"])
		if not bool(profile_result.get("ok", false)):
			errors.append_array(profile_result.get("errors", PackedStringArray()))
			return _result(false, errors)
		stored_profile = profile_result.get("profile", {}).duplicate(true)
		stored_profile_available = bool(profile_result.get("available", false))
	variant["presentation_profile"] = stored_profile
	variant["presentation_profile_available"] = stored_profile_available
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
	var version_value: Variant = record.get("version", null)
	var version: int = int(version_value) if _integer_number(version_value) else -1
	var is_legacy: bool = version == LEGACY_VARIANT_VERSION
	var required_keys: PackedStringArray = LEGACY_VARIANT_REQUIRED_KEYS if is_legacy else VARIANT_REQUIRED_KEYS
	var has_descriptor: bool = record.has("workshop_descriptor")
	var has_dependencies: bool = record.has("dependencies")
	var allowed_record_size: int = required_keys.size() + (1 if has_descriptor else 0) + (1 if has_dependencies else 0)
	if record.size() != allowed_record_size or not record.has_all(required_keys):
		errors.append("Variant revision has missing or unknown fields.")
		return _result(false, errors)
	for key: Variant in record.keys():
		if typeof(key) != TYPE_STRING or not VARIANT_KEYS.has(str(key)):
			errors.append("Variant revision has missing or unknown fields.")
			return _result(false, errors)
	if record["format"] != VARIANT_FORMAT or not _integer_number(record["version"]) \
			or version not in [LEGACY_VARIANT_VERSION, VARIANT_VERSION]:
		errors.append("Variant format or version is unsupported.")
	if not is_legacy and record.has("presentation_profile"):
		var profile_result: Dictionary = PresentationProfile.validate_stored(record["presentation_profile"])
		if not bool(profile_result.get("ok", false)):
			errors.append_array(profile_result.get("errors", PackedStringArray()))
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
	if recipe.has("tank_capacity_multiplier"):
		var tank_capacity_multiplier: Variant = recipe["tank_capacity_multiplier"]
		if typeof(tank_capacity_multiplier) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(tank_capacity_multiplier)):
			errors.append("Recipe tank_capacity_multiplier must be a finite number.")
		elif float(tank_capacity_multiplier) < WorkshopParameters.MIN_TANK_CAPACITY_MULTIPLIER \
				or float(tank_capacity_multiplier) > WorkshopParameters.MAX_TANK_CAPACITY_MULTIPLIER:
			errors.append("Recipe tank_capacity_multiplier must be between %.2f and %.2f." % [
				WorkshopParameters.MIN_TANK_CAPACITY_MULTIPLIER, WorkshopParameters.MAX_TANK_CAPACITY_MULTIPLIER])
	if recipe.has("id") and (typeof(recipe["id"]) != TYPE_STRING or not _valid_uuid(str(recipe["id"]))):
		errors.append("Optional recipe ID must be a lowercase UUID.")
	if recipe.has("name") and not _valid_name(str(recipe["name"])):
		errors.append("Optional recipe name is invalid.")
	var tree_result: Dictionary = _validate_json_tree(recipe)
	if not bool(tree_result["ok"]):
		errors.append_array(tree_result["errors"])
	if recipe.has("mass_edits"):
		var extended: Dictionary = WorkshopParameters.validate(recipe)
		if not extended.ok: errors.append_array(extended.errors)
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


static func _resolve_customization_bindings(base_id: String, descriptor: Dictionary) -> Dictionary:
	if not ResourceLoader.exists("res://render/aircraft_customization.gd"):
		return {"ok": false, "missing": true, "errors": PackedStringArray(["Customization companion is unavailable."])}
	var customization_script: Script = load("res://render/aircraft_customization.gd")
	if customization_script == null:
		return {"ok": false, "missing": true, "errors": PackedStringArray(["Customization companion is unavailable."])}
	var described: Dictionary = customization_script.describe(base_id)
	if not bool(described.get("ok", false)) or typeof(described.get("bindings", null)) != TYPE_DICTIONARY:
		return {"ok": false, "missing": true,
			"errors": described.get("errors", PackedStringArray(["Customization companion could not describe this aircraft."]))}
	var bindings: Dictionary = described["bindings"]
	if not descriptor.is_empty() and typeof(descriptor.get("presentation", null)) == TYPE_DICTIONARY:
		var physical_presentation: Dictionary = descriptor["presentation"]
		if physical_presentation.has("visual_family") \
				and physical_presentation["visual_family"] != bindings.get("visual_family", ""):
			return {"ok": false, "missing": false,
				"errors": PackedStringArray(["Customization bindings do not match the pinned Workshop visual family."])}
		if physical_presentation.has("model_manifest_sha256") \
				and physical_presentation["model_manifest_sha256"] != bindings.get("model_manifest_sha256", ""):
			return {"ok": false, "missing": false,
				"errors": PackedStringArray(["Customization bindings do not match the pinned Workshop model manifest."])}
	return {"ok": true, "errors": PackedStringArray(), "bindings": bindings}


static func _presentation_is_empty(profile: Dictionary) -> bool:
	return profile.get("paint", []) is Array and (profile.get("paint", []) as Array).is_empty() \
		and profile.get("markings", []) is Array and (profile.get("markings", []) as Array).is_empty() \
		and profile.get("smoke", []) is Array and (profile.get("smoke", []) as Array).is_empty() \
		and profile.get("visual_seed", 0) == 0


static func _presentation_pins_are_empty(pins: Dictionary) -> bool:
	return str(pins.get("visual_family", "")).is_empty() \
		and str(pins.get("model_manifest_sha256", "")).is_empty() \
		and str(pins.get("slots_sha256", "")).is_empty()


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


static func _write_new_file_atomic(path: String, bytes: PackedByteArray, checkpoint: Callable = Callable()) -> Dictionary:
	var errors := PackedStringArray()
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		errors.append("Refusing to overwrite an existing immutable revision file.")
		return {"ok": false, "errors": errors}
	var temporary_id: String = _new_uuid()
	if temporary_id.is_empty():
		errors.append("Could not generate a unique revision temporary filename.")
		return {"ok": false, "errors": errors}
	var temporary: String = path + ".tmp-" + temporary_id
	var write_result: Dictionary = _write_bytes(temporary, bytes)
	if not bool(write_result["ok"]):
		errors.append_array(write_result["errors"])
		return {"ok": false, "errors": errors}
	if not _continue_save(checkpoint, "after_revision_temp_write"):
		return _interrupted_save("after_revision_temp_write")
	var readback: Dictionary = _read_bytes(temporary, MAX_VARIANT_BYTES)
	if not bool(readback["ok"]) or (readback.get("bytes", PackedByteArray()) as PackedByteArray) != bytes:
		DirAccess.remove_absolute(temporary)
		errors.append("Temporary revision failed its exact-byte readback check.")
		return {"ok": false, "errors": errors}
	if not _continue_save(checkpoint, "after_revision_temp_readback"):
		return _interrupted_save("after_revision_temp_readback")
	var rename_error: Error = DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		errors.append("Could not commit immutable revision file (%s)." % error_string(rename_error))
		return {"ok": false, "errors": errors}
	if not _continue_save(checkpoint, "after_revision_commit"):
		return _interrupted_save("after_revision_commit")
	return {"ok": true, "errors": errors}


static func _write_index_atomic(
		variant_dir: String,
		bytes: PackedByteArray,
		expected_id: String,
		expected_previous_revision: int,
		checkpoint: Callable = Callable()
) -> Dictionary:
	var errors := PackedStringArray()
	var index_path: String = variant_dir.path_join("manifest.json")
	var backup_path: String = index_path + ".bak"
	var temporary_id: String = _new_uuid()
	if temporary_id.is_empty():
		errors.append("Could not generate a unique manifest temporary filename.")
		return {"ok": false, "errors": errors}
	var temporary: String = index_path + ".tmp-" + temporary_id
	var write_result: Dictionary = _write_bytes(temporary, bytes)
	if not bool(write_result["ok"]):
		errors.append_array(write_result["errors"])
		return {"ok": false, "errors": errors}
	if not _continue_save(checkpoint, "after_manifest_temp_write"):
		return _interrupted_save("after_manifest_temp_write")
	var readback: Dictionary = _read_bytes(temporary, MAX_VARIANT_BYTES)
	if not bool(readback["ok"]) or (readback.get("bytes", PackedByteArray()) as PackedByteArray) != bytes:
		DirAccess.remove_absolute(temporary)
		errors.append("Temporary manifest failed its exact-byte readback check.")
		return {"ok": false, "errors": errors}
	if not _continue_save(checkpoint, "after_manifest_temp_readback"):
		return _interrupted_save("after_manifest_temp_readback")
	var moved_current: bool = false
	var current_result: Dictionary = _load_from_manifest_source(variant_dir, expected_id, index_path, false)
	var backup_result: Dictionary = {}
	if FileAccess.file_exists(backup_path):
		backup_result = _load_from_manifest_source(variant_dir, expected_id, backup_path, true)
	var current_matches: bool = bool(current_result["ok"]) and int(current_result["variant"]["revision"]) == expected_previous_revision
	var backup_matches: bool = not bool(backup_result.is_empty()) and bool(backup_result["ok"]) and int(backup_result["variant"]["revision"]) == expected_previous_revision
	var preserve_backup: bool = false
	if expected_previous_revision == 0:
		if FileAccess.file_exists(index_path) or DirAccess.dir_exists_absolute(index_path) or FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(temporary)
			errors.append("Variant store changed while it was being saved; reload before retrying.")
			return {"ok": false, "errors": errors}
	elif current_matches:
		if FileAccess.file_exists(backup_path):
			var remove_backup_error: Error = DirAccess.remove_absolute(backup_path)
			if remove_backup_error != OK:
				DirAccess.remove_absolute(temporary)
				errors.append("Could not rotate the prior manifest backup.")
				return {"ok": false, "errors": errors}
			if not _continue_save(checkpoint, "after_backup_remove"):
				return _interrupted_save("after_backup_remove")
		var backup_error: Error = DirAccess.rename_absolute(index_path, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			errors.append("Could not preserve the previous manifest (%s)." % error_string(backup_error))
			return {"ok": false, "errors": errors}
		moved_current = true
		if not _continue_save(checkpoint, "after_backup_rotate"):
			return _interrupted_save("after_backup_rotate")
	elif not bool(current_result["ok"]) and backup_matches:
		if DirAccess.dir_exists_absolute(index_path):
			DirAccess.remove_absolute(temporary)
			errors.append("Could not replace an invalid manifest directory.")
			return {"ok": false, "errors": errors}
		if FileAccess.file_exists(index_path):
			var remove_current_error: Error = DirAccess.remove_absolute(index_path)
			if remove_current_error != OK:
				DirAccess.remove_absolute(temporary)
				errors.append("Could not replace the invalid current manifest (%s)." % error_string(remove_current_error))
				return {"ok": false, "errors": errors}
			if not _continue_save(checkpoint, "after_invalid_manifest_remove"):
				return _interrupted_save("after_invalid_manifest_remove")
		preserve_backup = true
	else:
		DirAccess.remove_absolute(temporary)
		errors.append("Saved variant changed while it was being saved; reload before retrying.")
		return {"ok": false, "errors": errors}
	var commit_error: Error = DirAccess.rename_absolute(temporary, index_path)
	if commit_error != OK:
		if moved_current and not FileAccess.file_exists(index_path) and not preserve_backup:
			DirAccess.rename_absolute(backup_path, index_path)
		DirAccess.remove_absolute(temporary)
		errors.append("Could not atomically commit the manifest (%s)." % error_string(commit_error))
		return {"ok": false, "errors": errors}
	if not _continue_save(checkpoint, "after_manifest_commit"):
		return _interrupted_save("after_manifest_commit")
	return {"ok": true, "errors": errors}


static func _continue_save(checkpoint: Callable, stage: String) -> bool:
	return not checkpoint.is_valid() or bool(checkpoint.call(stage))


static func _interrupted_save(stage: String) -> Dictionary:
	return _result(false, PackedStringArray(["Variant save interrupted at %s; reload before retrying." % stage]))


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
	var number: float = float(value)
	return floor(number) == number and abs(number) <= 9007199254740991.0


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


static func _result(
		ok: bool,
		errors: PackedStringArray,
		variant: Dictionary = {},
		trash_generation: String = ""
) -> Dictionary:
	return {
		"ok": ok,
		"errors": errors,
		"variant": variant,
		"trash_generation": trash_generation,
	}
