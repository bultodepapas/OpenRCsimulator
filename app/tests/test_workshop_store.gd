extends SceneTree

const Store = preload("res://workshop/store.gd")
const Dependencies = preload("res://workshop/dependencies.gd")
const WorkshopCompiler = preload("res://workshop/compiler.gd")
const BASE_PATH: String = "res://data/aircraft/jensen_ugly_stik_60.json"

var _checks: int = 0
var _failures: int = 0
var _root: String = ""


func _initialize() -> void:
	_root = "user://workshop_store_test_%d_%d" % [int(Time.get_unix_time_from_system()), int(Time.get_ticks_usec())]
	_test_root_guard()
	var base_bytes: PackedByteArray = FileAccess.get_file_as_bytes(BASE_PATH)
	var recipe: Dictionary = _recipe()
	_check("base fixture read", not base_bytes.is_empty())
	_test_dependency_manifests()
	_test_first_publication_recovery(base_bytes)
	_test_interrupted_first_save_retry(base_bytes)
	var integer_recipe: Dictionary = _recipe()
	for key: String in ["scale", "weight_multiplier", "power_multiplier", "control_multiplier", "tank_capacity_multiplier"]:
		integer_recipe[key] = 1
	var integer_saved: Dictionary = Store.save_variant("Integer recipe", "jensen-das-ugly-stik-60", base_bytes, integer_recipe, "", _root)
	_check("integer-valued recipes survive their own disk round-trip", bool(integer_saved["ok"]), str(integer_saved["errors"]))
	if integer_saved["ok"]:
		_check("integer recipe remains loadable", Store.load_variant(integer_saved.variant.id, _root).ok)
		_check("saving does not normalize the caller's recipe in place", typeof(integer_recipe["scale"]) == TYPE_INT)
		integer_recipe["power_multiplier"] = 1.25
		var mixed_saved: Dictionary = Store.save_variant("Mixed numeric recipe", "jensen-das-ugly-stik-60",
			base_bytes, integer_recipe, integer_saved.variant.id, _root, {}, {}, 1)
		_check("mixed numeric recipe update remains readable", mixed_saved.ok
			and Store.load_variant(integer_saved.variant.id, _root).variant.revision == 2,
			str(mixed_saved.errors))
		Store.delete_variant(integer_saved.variant.id, _root)
	var saved: Dictionary = Store.save_variant("Store test Stik", "jensen-das-ugly-stik-60", base_bytes, recipe, "", _root)
	_check("first variant save succeeds", bool(saved["ok"]), str(saved["errors"]))
	if not bool(saved["ok"]):
		_finish()
		return
	var first: Dictionary = saved["variant"]
	var id: String = str(first["id"])
	var legacy_recipe: Dictionary = _recipe()
	legacy_recipe.erase("tank_capacity_multiplier")
	var legacy_saved: Dictionary = Store.save_variant("Optional tank capacity compatibility", "jensen-das-ugly-stik-60",
		base_bytes, legacy_recipe, "", _root)
	_check("historical recipe may omit the new optional tank-size field", legacy_saved.get("ok", false), str(legacy_saved.get("errors", [])))
	if legacy_saved.get("ok", false):
		var legacy_loaded: Dictionary = Store.load_variant(legacy_saved.variant.id, _root)
		_check("omitted tank-size field survives variant load without rewriting history",
			legacy_loaded.get("ok", false) and not legacy_loaded.variant.recipe.has("tank_capacity_multiplier"))
		Store.delete_variant(legacy_saved.variant.id, _root)
	_check("generated ID is a lowercase UUID", id.length() == 36 and id[14] == "4")
	_check("revision starts at one", int(first["revision"]) == 1)
	_check("new variants pin the current compiler version", str(first.get("compiler_version", "")) == WorkshopCompiler.COMPILER_VERSION)
	_check("exact base bytes are returned", first["base_bytes"] == base_bytes)
	_check("base SHA-256 covers exact source bytes", str(first["base_sha256"]) == _sha256(base_bytes))
	_check("parsed base retains its aircraft identity", str(first["base"].get("id", "")) == "jensen-das-ugly-stik-60")
	_check("catalog descriptor is pinned with the exact source snapshot", typeof(first.get("workshop_descriptor", null)) == TYPE_DICTIONARY and str(first["workshop_descriptor"].get("base_sha256", "")) == _sha256(base_bytes))
	_check("dependency manifest is pinned with the variant", typeof(first.get("dependencies", null)) == TYPE_DICTIONARY and str(first["dependencies"].get("format", "")) == "openrc-aircraft-workshop-dependencies v1")
	_check("variant list discovers the saved item", _contains_variant(Store.list_variants(_root), id))
	_test_exclusive_lock(id, first, base_bytes)

	var renamed_recipe: Dictionary = _recipe()
	renamed_recipe["scale"] = 1.25
	renamed_recipe["name"] = "Renamed Stik"
	var renamed: Dictionary = Store.save_variant("Renamed Stik", "jensen-das-ugly-stik-60", base_bytes, renamed_recipe, id, _root, first["workshop_descriptor"], first["dependencies"], 1)
	_check("same-base save creates a new revision", bool(renamed["ok"]), str(renamed["errors"]))
	if bool(renamed["ok"]):
		_check("revision increments monotonically", int(renamed["variant"]["revision"]) == 2)
		_check("same-ID revisions retain the pinned compiler version", str(renamed["variant"].get("compiler_version", "")) == str(first["compiler_version"]))
		_check("rename changes display metadata", str(renamed["variant"]["name"]) == "Renamed Stik")
		_check("revision still pins original base bytes", renamed["variant"]["base_bytes"] == base_bytes)
		_check("later revisions retain the original Workshop descriptor", renamed["variant"].get("workshop_descriptor", {}) == first.get("workshop_descriptor", {}))
		_check("later revisions retain the original dependency manifest", renamed["variant"].get("dependencies", {}) == first.get("dependencies", {}))
		_check("load returns latest saved revision", int(Store.load_variant(id, _root)["variant"]["revision"]) == 2)
		var unversioned_save: Dictionary = Store.save_variant("Renamed Stik", "jensen-das-ugly-stik-60", base_bytes, renamed_recipe, id, _root, first["workshop_descriptor"], first["dependencies"])
		_check("same-ID save requires an expected revision", not bool(unversioned_save["ok"]) and _has_error(unversioned_save["errors"], "Expected revision is required"), str(unversioned_save["errors"]))
		var stale_recipe: Dictionary = renamed_recipe.duplicate(true)
		stale_recipe["power_multiplier"] = 1.1
		var stale_save: Dictionary = Store.save_variant("Renamed Stik", "jensen-das-ugly-stik-60", base_bytes, stale_recipe, id, _root, first["workshop_descriptor"], first["dependencies"], 1)
		_check("stale same-ID save is refused", not bool(stale_save["ok"]) and _has_error(stale_save["errors"], "expected revision"), str(stale_save["errors"]))
		_check("stale save leaves the latest revision and history untouched", int(Store.load_variant(id, _root)["variant"]["revision"]) == 2 and not FileAccess.file_exists(ProjectSettings.globalize_path(_root + "/" + id + "/revisions/00000003.json")))
		var changed_dependencies: Dictionary = first["dependencies"].duplicate(true)
		changed_dependencies["files"][Dependencies.WHEEL_PROFILES_PATH] = "0".repeat(64)
		var rebased: Dictionary = Store.save_variant("Renamed Stik", "jensen-das-ugly-stik-60", base_bytes, renamed_recipe, id, _root, first["workshop_descriptor"], changed_dependencies, 2)
		_check("a same-ID revision cannot silently replace dependency hashes", not bool(rebased["ok"]) and _has_error(rebased["errors"], "dependencies are immutable"), str(rebased["errors"]))
		_check("rejected dependency replacement leaves saved revision untouched", int(Store.load_variant(id, _root)["variant"]["revision"]) == 2)

	_test_unpinned_descriptor_is_immutable(base_bytes)
	_test_save_after_manifest_recovery(base_bytes)

	var edited_base: Dictionary = first["base"].duplicate(true)
	edited_base["description"] = str(edited_base["description"]) + " changed"
	var changed_base_bytes: PackedByteArray = (JSON.stringify(edited_base, "\t", true, true) + "\n").to_utf8_buffer()
	var changed_base_save: Dictionary = Store.save_variant("Renamed Stik", "jensen-das-ugly-stik-60", changed_base_bytes, renamed_recipe, id, _root, first["workshop_descriptor"], first["dependencies"], 2)
	_check("an existing variant cannot replace its base snapshot", not bool(changed_base_save["ok"]) and _has_error(changed_base_save["errors"], "immutable"), str(changed_base_save["errors"]))
	_check("rejected base change leaves saved revision untouched", int(Store.load_variant(id, _root)["variant"]["revision"]) == 2)

	var bad_recipe: Dictionary = _recipe()
	bad_recipe["power_multiplier"] = INF
	var bad_recipe_save: Dictionary = Store.save_variant("Bad recipe", "jensen-das-ugly-stik-60", base_bytes, bad_recipe, "", _root)
	_check("non-finite recipe numbers are rejected", not bool(bad_recipe_save["ok"]) and _has_error(bad_recipe_save["errors"], "finite"), str(bad_recipe_save["errors"]))
	var oversized_tank_recipe: Dictionary = _recipe()
	oversized_tank_recipe["tank_capacity_multiplier"] = 2.01
	var oversized_tank: Dictionary = Store.save_variant("Bad tank capacity", "jensen-das-ugly-stik-60",
		base_bytes, oversized_tank_recipe, "", _root)
	_check("variant store enforces the bounded independent tank-size ratio",
		not oversized_tank.get("ok", false) and _has_error(oversized_tank.get("errors", []), "tank_capacity_multiplier"),
		str(oversized_tank.get("errors", [])))
	var malformed_base: Dictionary = Store.save_variant("Bad base", "jensen-das-ugly-stik-60", "{".to_utf8_buffer(), _recipe(), "", _root)
	_check("malformed base JSON is rejected", not bool(malformed_base["ok"]), str(malformed_base["errors"]))
	var wrong_schema_bytes: PackedByteArray = "{\"format\":\"other\",\"version\":1,\"id\":\"jensen-das-ugly-stik-60\"}".to_utf8_buffer()
	var wrong_schema: Dictionary = Store.save_variant("Wrong schema", "jensen-das-ugly-stik-60", wrong_schema_bytes, _recipe(), "", _root)
	_check("wrong aircraft schema is rejected", not bool(wrong_schema["ok"]) and _has_error(wrong_schema["errors"], "openrc-aircraft v2"), str(wrong_schema["errors"]))
	var bad_id_load: Dictionary = Store.load_variant("../escape", _root)
	_check("path-like variant IDs are rejected", not bool(bad_id_load["ok"]) and _has_error(bad_id_load["errors"], "UUID"), str(bad_id_load["errors"]))
	var bad_id_save: Dictionary = Store.save_variant("Bad ID", "jensen-das-ugly-stik-60", base_bytes, _recipe(), "../escape", _root)
	_check("path-like IDs cannot create files", not bool(bad_id_save["ok"]) and not FileAccess.file_exists(ProjectSettings.globalize_path(_root + "/../escape.json")))
	var unsafe_root: Array = Store.list_variants("user://../escape")
	_check("path traversal roots cannot enumerate or write outside user data", unsafe_root.is_empty())

	_test_manifest_recovery(id)
	_test_persisted_integrity(id)
	var stale_delete: Dictionary = Store.delete_variant(id, _root, 1)
	_check("delete refuses a stale confirmation revision", not bool(stale_delete["ok"]) and _has_error(stale_delete["errors"], "expected revision"), str(stale_delete["errors"]))
	_check("stale delete keeps the current variant in the library", int(Store.load_variant(id, _root).get("variant", {}).get("revision", 0)) == 2)
	var deleted: Dictionary = Store.delete_variant(id, _root, 2)
	_check("delete moves a valid item to local trash", bool(deleted["ok"]), str(deleted["errors"]))
	var first_generation: String = str(deleted.get("trash_generation", ""))
	_check("delete returns an exact UUID trash generation", first_generation.length() == 36 and first_generation[14] == "4")
	_check("trashed variant leaves the active library", Store.list_variants(_root).is_empty())
	var trash_root: String = ProjectSettings.globalize_path(_root + "/_trash")
	var modern_trash_path: String = trash_root.path_join(id + "-" + first_generation)
	var legacy_trash_path: String = trash_root.path_join(id + "-0000000001-deadbeef")
	var legacy_move: Error = DirAccess.rename_absolute(modern_trash_path, legacy_trash_path)
	_check("legacy v1 trash-generation fixture moves", legacy_move == OK)
	var restored: Dictionary = Store.restore_variant(id, _root)
	_check("single legacy trash generation remains restorable by old callers", bool(restored["ok"]), str(restored["errors"]))
	if bool(restored["ok"]):
		_check("restored item retains its latest revision", int(restored["variant"]["revision"]) == 2)
		_check("restored item retains exact base bytes", restored["variant"]["base_bytes"] == base_bytes)
	var original_deleted: Dictionary = Store.delete_variant(id, _root, 2)
	var original_generation: String = str(original_deleted.get("trash_generation", ""))
	_check("second delete creates another exact generation", bool(original_deleted["ok"]) and original_generation != first_generation, str(original_deleted["errors"]))
	var reused: Dictionary = Store.save_variant("Reused store ID", "jensen-das-ugly-stik-60", base_bytes, _recipe(), id, _root, first["workshop_descriptor"], first["dependencies"], 0)
	_check("deleted UUID can be reused for a new build", bool(reused["ok"]) and int(reused.get("variant", {}).get("revision", 0)) == 1, str(reused["errors"]))
	var reused_deleted: Dictionary = Store.delete_variant(id, _root, 1)
	var reused_generation: String = str(reused_deleted.get("trash_generation", ""))
	_check("reused UUID deletion gets a distinct generation", bool(reused_deleted["ok"]) and reused_generation != original_generation and reused_generation != first_generation, str(reused_deleted["errors"]))
	var corrupt_generation: String = Store._new_uuid()
	var corrupt_path: String = trash_root.path_join(id + "-" + corrupt_generation)
	_check("corrupt generation fixture directory is created", DirAccess.make_dir_recursive_absolute(corrupt_path) == OK)
	_check("tokenless restore refuses multiple generations, including corrupt trash", not bool(Store.restore_variant(id, _root)["ok"]))
	var exact_original: Dictionary = Store.restore_variant(id, _root, original_generation)
	_check("exact generation restores the requested older build", bool(exact_original["ok"]) and int(exact_original["variant"]["revision"]) == 2 and str(exact_original["variant"]["name"]) == "Renamed Stik", str(exact_original["errors"]))
	var blocked_reuse_restore: Dictionary = Store.restore_variant(id, _root, reused_generation)
	_check("UUID reuse cannot replace a live build from another trash generation", not bool(blocked_reuse_restore["ok"]) and int(Store.load_variant(id, _root).get("variant", {}).get("revision", 0)) == 2)
	var old_deleted_again: Dictionary = Store.delete_variant(id, _root, 2)
	_check("restored old build can be deleted again", bool(old_deleted_again["ok"]), str(old_deleted_again["errors"]))
	var exact_reused: Dictionary = Store.restore_variant(id, _root, reused_generation)
	_check("exact reused-ID generation restores its own revision", bool(exact_reused["ok"]) and int(exact_reused["variant"]["revision"]) == 1 and str(exact_reused["variant"]["name"]) == "Reused store ID", str(exact_reused["errors"]))
	var reused_live_deleted: Dictionary = Store.delete_variant(id, _root, 1)
	_check("reused build cleanup succeeds", bool(reused_live_deleted["ok"]), str(reused_live_deleted["errors"]))
	var corrupt_restore: Dictionary = Store.restore_variant(id, _root, corrupt_generation)
	_check("exact corrupt generation fails closed without selecting another build", not bool(corrupt_restore["ok"]) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_root + "/" + id)))
	_finish()


func _test_exclusive_lock(id: String, saved: Dictionary, base_bytes: PackedByteArray) -> void:
	var root_path := ProjectSettings.globalize_path(_root)
	var guard: RefCounted = Store.VariantWriteGuard.new(root_path, id)
	_check("completed saves release the per-variant reservation", guard.acquired)
	var competing: RefCounted = Store.VariantWriteGuard.new(root_path, id)
	_check("another writer cannot reserve the same variant", not competing.acquired)
	competing = null
	_check("failed reservation cannot release another writer's lock", DirAccess.dir_exists_absolute(guard.directory))
	var refused: Dictionary = Store.save_variant("Locked variant", saved.base_id, base_bytes, _recipe(), id,
		_root, saved.workshop_descriptor, saved.dependencies, int(saved.revision))
	_check("busy saves are refused before changing any revision", not refused.ok and _has_error(refused.errors, "busy")
		and Store.load_variant(id, _root).variant.revision == saved.revision)
	_check("delete cannot race an active save", not Store.delete_variant(id, _root).ok)
	_check("restore cannot race an active save", not Store.restore_variant(id, _root).ok)
	var lock_path: String = guard.directory
	guard = null
	_check("scope exit releases the exclusive reservation", not DirAccess.dir_exists_absolute(lock_path))


func _test_first_publication_recovery(base_bytes: PackedByteArray) -> void:
	var saved: Dictionary = Store.save_variant("Publication cut Stik", "jensen-das-ugly-stik-60", base_bytes, _recipe(), "", _root)
	_check("publication-cut fixture saves", bool(saved["ok"]), str(saved["errors"]))
	if not bool(saved["ok"]):
		return
	var id: String = str(saved["variant"]["id"])
	var root_path: String = ProjectSettings.globalize_path(_root)
	var live_path: String = root_path.path_join(id)
	var staging_root: String = root_path.path_join("_staging")
	var staging_path: String = staging_root.path_join(id + "-publication-cut")
	_check("publication staging root exists", DirAccess.make_dir_recursive_absolute(staging_root) == OK)
	var move_error: Error = DirAccess.rename_absolute(live_path, staging_path)
	_check("simulate complete first-save staging before publication", move_error == OK)
	if move_error != OK:
		Store.delete_variant(id, _root, 1)
		return
	var interrupted: Dictionary = Store._publish_staged_variant(staging_path, live_path, id, Callable(self, "_deny_publication"))
	_check("publication cut leaves no visible UUID", not bool(interrupted["ok"]) and not DirAccess.dir_exists_absolute(live_path), str(interrupted["errors"]))
	_check("publication cut retains the complete validated staging directory", DirAccess.dir_exists_absolute(staging_path) and FileAccess.file_exists(staging_path.path_join("manifest.json")))
	var retried: Dictionary = Store._publish_staged_variant(staging_path, live_path, id)
	_check("retry atomically publishes the complete staged UUID", bool(retried["ok"]) and int(retried.get("variant", {}).get("revision", 0)) == 1, str(retried["errors"]))
	_check("published first save passes full readback", bool(Store.load_variant(id, _root)["ok"]))
	var deleted: Dictionary = Store.delete_variant(id, _root, 1)
	_check("publication-cut fixture cleans up", bool(deleted["ok"]), str(deleted["errors"]))


func _test_interrupted_first_save_retry(base_bytes: PackedByteArray) -> void:
	var id: String = Store._new_uuid()
	var root_path: String = ProjectSettings.globalize_path(_root)
	var orphan_path: String = root_path.path_join("_staging").path_join(id + "-interrupted-before-manifest")
	var revisions_path: String = orphan_path.path_join("revisions")
	_check("interrupted-save revision fixture directory is created", DirAccess.make_dir_recursive_absolute(revisions_path) == OK)
	_check("uncommitted revision bytes are retained for the fixture", _write_file(revisions_path.path_join("00000001.json"), "uncommitted revision".to_utf8_buffer()))
	var retry: Dictionary = Store.save_variant("Retry after first save", "jensen-das-ugly-stik-60", base_bytes, _recipe(), id, _root, {}, {}, 0)
	_check("retry creates a complete committed build beside uncommitted staging", bool(retry["ok"]) and int(retry.get("variant", {}).get("revision", 0)) == 1, str(retry["errors"]))
	var loaded: Dictionary = Store.load_variant(id, _root)
	_check("retry does not promote the uncommitted staged record", bool(loaded["ok"]) and str(loaded.get("variant", {}).get("name", "")) == "Retry after first save")
	_check("retry publishes only one visible UUID record", _contains_variant(Store.list_variants(_root), id))
	var deleted: Dictionary = Store.delete_variant(id, _root, 1)
	_check("interrupted-save retry fixture cleans up", bool(deleted["ok"]), str(deleted["errors"]))


func _deny_publication() -> bool:
	return false


func _test_root_guard() -> void:
	_check("unsafe resource roots are rejected", Store.list_variants("res://aircraft_variants").is_empty())
	var rejected: Dictionary = Store.save_variant("Unsafe root", "jensen-das-ugly-stik-60", PackedByteArray(), _recipe(), "", "res://data/aircraft")
	_check("store writes are limited to user data", not bool(rejected["ok"]) and not rejected["errors"].is_empty())


func _test_dependency_manifests() -> void:
	var base_bytes: PackedByteArray = FileAccess.get_file_as_bytes(BASE_PATH)
	var base: Dictionary = JSON.parse_string(base_bytes.get_string_from_utf8())
	var captured: Dictionary = Dependencies.capture(base)
	_check("dependency capture succeeds for a non-glow catalog aircraft", bool(captured["ok"]), str(captured["errors"]))
	if bool(captured["ok"]):
		var files: Dictionary = captured["manifest"]["files"]
		var wheel_bytes: PackedByteArray = FileAccess.get_file_as_bytes(Dependencies.WHEEL_PROFILES_PATH)
		_check("wheel-profile manifest hashes the exact bundled bytes", str(files.get(Dependencies.WHEEL_PROFILES_PATH, "")) == _sha256(wheel_bytes))
		_check("captured manifest verifies unchanged source bytes", bool(Dependencies.verify(base, captured["manifest"])["ok"]))
		var altered: Dictionary = captured["manifest"].duplicate(true)
		altered["files"][Dependencies.WHEEL_PROFILES_PATH] = "0".repeat(64)
		var stale: Dictionary = Dependencies.verify(base, altered)
		_check("changed dependency hash refuses use with create-new guidance", not bool(stale["ok"]) and _has_error(stale["errors"], "create a new variant"), str(stale["errors"]))
	var glow_path: String = "res://data/aircraft/stik_glow_55ax_2t.json"
	var glow_bytes: PackedByteArray = FileAccess.get_file_as_bytes(glow_path)
	var glow_base: Dictionary = JSON.parse_string(glow_bytes.get_string_from_utf8())
	var glow_capture: Dictionary = Dependencies.capture(glow_base)
	_check("glow dependency capture succeeds", bool(glow_capture["ok"]), str(glow_capture["errors"]))
	if bool(glow_capture["ok"]):
		var glow_files: Dictionary = glow_capture["manifest"]["files"]
		_check("glow manifest pins wheel, installation and profile files", glow_files.size() == 3 and glow_files.has(Dependencies.WHEEL_PROFILES_PATH) and glow_files.has("res://data/glow/stik_55ax_2t.json") and glow_files.has("res://data/glow/os_max_55ax_candidate.json"), str(glow_files.keys()))
	var unsafe_base: Dictionary = glow_base.duplicate(true)
	unsafe_base["propulsion"]["engine"]["glow_installation"] = "res://data/glow/../stik_55ax_2t.json"
	var unsafe: Dictionary = Dependencies.capture(unsafe_base)
	_check("glow dependency path traversal is rejected", not bool(unsafe["ok"]) and _has_error(unsafe["errors"], "flat bundled"), str(unsafe["errors"]))


func _test_manifest_recovery(id: String) -> void:
	var manifest_path: String = ProjectSettings.globalize_path(_root + "/" + id + "/manifest.json")
	var backup_path: String = manifest_path + ".bak"
	_check("prior manifest is retained as a backup", FileAccess.file_exists(backup_path))
	if not FileAccess.file_exists(manifest_path) or not FileAccess.file_exists(backup_path):
		return
	var current_bytes: PackedByteArray = FileAccess.get_file_as_bytes(manifest_path)
	var move_error: Error = DirAccess.rename_absolute(manifest_path, manifest_path + ".interrupted")
	_check("simulate interrupted manifest commit", move_error == OK)
	if move_error != OK:
		return
	var recovered: Dictionary = Store.load_variant(id, _root)
	_check("missing current manifest recovers from backup", bool(recovered["ok"]) and bool(recovered["variant"].get("recovered_from_manifest_backup", false)), str(recovered["errors"]))
	_check("backup recovers the last committed revision", bool(recovered["ok"]) and int(recovered["variant"]["revision"]) == 1)
	var restore_error: Error = DirAccess.rename_absolute(manifest_path + ".interrupted", manifest_path)
	_check("restore interrupted-write fixture", restore_error == OK)
	if restore_error != OK:
		return
	_check("corrupt current-manifest fixture writes", _write_file(manifest_path, "{".to_utf8_buffer()))
	var recovered_corrupt: Dictionary = Store.load_variant(id, _root)
	_check("corrupt current manifest recovers from its valid backup", bool(recovered_corrupt["ok"]) and bool(recovered_corrupt["variant"].get("recovered_from_manifest_backup", false)) and int(recovered_corrupt["variant"]["revision"]) == 1, str(recovered_corrupt["errors"]))
	_check("restore valid current-manifest fixture", _write_file(manifest_path, current_bytes))
	var missing_revision_manifest: Dictionary = JSON.parse_string(current_bytes.get_string_from_utf8())
	missing_revision_manifest["revision"] = 999
	var missing_revision_bytes: PackedByteArray = (JSON.stringify(missing_revision_manifest, "\t", true, true) + "\n").to_utf8_buffer()
	_check("missing-revision manifest fixture writes", _write_file(manifest_path, missing_revision_bytes))
	var recovered_missing_revision: Dictionary = Store.load_variant(id, _root)
	_check("manifest pointing at a missing revision recovers its backup", bool(recovered_missing_revision["ok"]) and bool(recovered_missing_revision["variant"].get("recovered_from_manifest_backup", false)) and int(recovered_missing_revision["variant"]["revision"]) == 1, str(recovered_missing_revision["errors"]))
	_check("restore valid manifest after missing-revision fixture", _write_file(manifest_path, current_bytes))


func _test_persisted_integrity(id: String) -> void:
	var record_path: String = ProjectSettings.globalize_path(_root + "/" + id + "/revisions/00000002.json")
	if not FileAccess.file_exists(record_path):
		_check("latest revision record exists for integrity fixture", false)
		return
	var original: PackedByteArray = FileAccess.get_file_as_bytes(record_path)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(original.get_string_from_utf8())
	_check("integrity fixture parses", parse_error == OK and typeof(parser.data) == TYPE_DICTIONARY)
	if parse_error != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return
	var record: Dictionary = parser.data
	record["base_sha256"] = "0".repeat(64)
	var tampered: PackedByteArray = (JSON.stringify(record, "\t", true, true) + "\n").to_utf8_buffer()
	_check("tampered revision fixture writes", _write_file(record_path, tampered))
	var rejected_hash: Dictionary = Store.load_variant(id, _root)
	_check("tampered latest revision is rejected in favor of the prior committed revision", bool(rejected_hash["ok"]) and bool(rejected_hash["variant"].get("recovered_from_manifest_backup", false)) and int(rejected_hash["variant"]["revision"]) == 1, str(rejected_hash["errors"]))
	_check("the prior committed revision remains available in the library", _contains_variant(Store.list_variants(_root), id))
	_check("restore valid hash fixture", _write_file(record_path, original))
	var restored_hash: Dictionary = Store.load_variant(id, _root)
	_check("restored hash loads again", bool(restored_hash["ok"]), str(restored_hash["errors"]))
	_check("loaded variant exposes its pinned compiler version", str(restored_hash.get("variant", {}).get("compiler_version", "")) == WorkshopCompiler.COMPILER_VERSION)
	var restored_record: Dictionary = JSON.parse_string(original.get_string_from_utf8())
	restored_record["version"] = 99
	var unknown_version: PackedByteArray = (JSON.stringify(restored_record, "\t", true, true) + "\n").to_utf8_buffer()
	_check("tampered schema fixture writes", _write_file(record_path, unknown_version))
	var rejected_version: Dictionary = Store.load_variant(id, _root)
	_check("unknown latest schema version recovers the prior committed revision", bool(rejected_version["ok"]) and bool(rejected_version["variant"].get("recovered_from_manifest_backup", false)) and int(rejected_version["variant"]["revision"]) == 1, str(rejected_version["errors"]))
	_check("restore valid schema fixture", _write_file(record_path, original))
	var fractional_revision: Dictionary = JSON.parse_string(original.get_string_from_utf8())
	fractional_revision["revision"] = 2.5
	var fractional_revision_bytes: PackedByteArray = (JSON.stringify(fractional_revision, "\t", true, true) + "\n").to_utf8_buffer()
	_check("fractional revision fixture writes", _write_file(record_path, fractional_revision_bytes))
	var rejected_fractional_revision: Dictionary = Store.load_variant(id, _root)
	_check("fractional persisted revisions are rejected and recovered", bool(rejected_fractional_revision["ok"]) and bool(rejected_fractional_revision["variant"].get("recovered_from_manifest_backup", false)) and int(rejected_fractional_revision["variant"]["revision"]) == 1, str(rejected_fractional_revision["errors"]))
	_check("restore valid revision fixture", _write_file(record_path, original))
	var old_compiler_record: Dictionary = JSON.parse_string(original.get_string_from_utf8())
	old_compiler_record["compiler_version"] = "openrc-aircraft-workshop-legacy-compiler-0"
	var old_compiler_bytes: PackedByteArray = (JSON.stringify(old_compiler_record, "\t", true, true) + "\n").to_utf8_buffer()
	_check("older compiler-version fixture writes", _write_file(record_path, old_compiler_bytes))
	var old_compiler_load: Dictionary = Store.load_variant(id, _root)
	_check("older pinned compiler version remains loadable", bool(old_compiler_load["ok"]) and str(old_compiler_load["variant"].get("compiler_version", "")) == "openrc-aircraft-workshop-legacy-compiler-0", str(old_compiler_load["errors"]))
	if bool(old_compiler_load["ok"]):
		var old_variant: Dictionary = old_compiler_load["variant"]
		var old_compiler_save: Dictionary = Store.save_variant(str(old_variant["name"]), str(old_variant["base_id"]), old_variant["base_bytes"], old_variant["recipe"], id, _root, old_variant.get("workshop_descriptor", {}), old_variant.get("dependencies", {}), 2)
		_check("same-ID save refuses to change an older compiler pin", not bool(old_compiler_save["ok"]) and _has_error(old_compiler_save["errors"], "create a new variant"), str(old_compiler_save["errors"]))
		_check("refused compiler change leaves the stored revision untouched", int(Store.load_variant(id, _root)["variant"]["revision"]) == 2)
	var empty_compiler_record: Dictionary = JSON.parse_string(original.get_string_from_utf8())
	empty_compiler_record["compiler_version"] = ""
	var empty_compiler_bytes: PackedByteArray = (JSON.stringify(empty_compiler_record, "\t", true, true) + "\n").to_utf8_buffer()
	_check("empty compiler-version fixture writes", _write_file(record_path, empty_compiler_bytes))
	var empty_compiler_load: Dictionary = Store.load_variant(id, _root)
	_check("empty compiler version in the latest record recovers the prior committed revision", bool(empty_compiler_load["ok"]) and bool(empty_compiler_load["variant"].get("recovered_from_manifest_backup", false)) and int(empty_compiler_load["variant"]["revision"]) == 1, str(empty_compiler_load["errors"]))
	_check("restore valid compiler-version fixture", _write_file(record_path, original))
	var descriptor_tamper: Dictionary = JSON.parse_string(original.get_string_from_utf8())
	if typeof(descriptor_tamper.get("workshop_descriptor", null)) == TYPE_DICTIONARY:
		descriptor_tamper["workshop_descriptor"]["base_sha256"] = "0".repeat(64)
		var bad_descriptor: PackedByteArray = (JSON.stringify(descriptor_tamper, "\t", true, true) + "\n").to_utf8_buffer()
		_check("tampered descriptor fixture writes", _write_file(record_path, bad_descriptor))
		var rejected_descriptor: Dictionary = Store.load_variant(id, _root)
		_check("tampered pinned descriptor recovers the prior committed revision", bool(rejected_descriptor["ok"]) and bool(rejected_descriptor["variant"].get("recovered_from_manifest_backup", false)) and int(rejected_descriptor["variant"]["revision"]) == 1, str(rejected_descriptor["errors"]))
		_check("restore valid descriptor fixture", _write_file(record_path, original))


func _test_unpinned_descriptor_is_immutable(base_bytes: PackedByteArray) -> void:
	var saved: Dictionary = Store.save_variant("Legacy descriptor pin", "jensen-das-ugly-stik-60", base_bytes, _recipe(), "", _root)
	_check("legacy descriptor-pin fixture saves", bool(saved["ok"]), str(saved["errors"]))
	if not bool(saved["ok"]):
		return
	var variant: Dictionary = saved["variant"]
	var id: String = str(variant["id"])
	var descriptor: Dictionary = variant.get("workshop_descriptor", {})
	_check("descriptor-pin fixture has a current descriptor", not descriptor.is_empty())
	if descriptor.is_empty():
		Store.delete_variant(id, _root)
		return
	var record_path: String = ProjectSettings.globalize_path(_root + "/" + id + "/revisions/00000001.json")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(record_path))
	record.erase("workshop_descriptor")
	var without_pin: PackedByteArray = (JSON.stringify(record, "\t", true, true) + "\n").to_utf8_buffer()
	_check("unpinned historical record fixture writes", _write_file(record_path, without_pin))
	var loaded: Dictionary = Store.load_variant(id, _root)
	_check("historical record without a descriptor remains readable", bool(loaded["ok"]) and not loaded["variant"].has("workshop_descriptor"), str(loaded["errors"]))
	var attempted: Dictionary = Store.save_variant("Legacy descriptor pin", "jensen-das-ugly-stik-60", base_bytes, _recipe(), id, _root, descriptor, variant.get("dependencies", {}), 1)
	_check("same-ID save cannot add a descriptor to an unpinned historical variant", not bool(attempted["ok"]) and _has_error(attempted["errors"], "without a pinned Workshop descriptor"), str(attempted["errors"]))
	_check("rejected descriptor pin change leaves the historical revision intact", int(Store.load_variant(id, _root)["variant"]["revision"]) == 1)
	var deleted: Dictionary = Store.delete_variant(id, _root)
	_check("descriptor-pin fixture is removed", bool(deleted["ok"]), str(deleted["errors"]))


func _test_save_after_manifest_recovery(base_bytes: PackedByteArray) -> void:
	var first: Dictionary = Store.save_variant("Recovery save Stik", "jensen-das-ugly-stik-60", base_bytes, _recipe(), "", _root)
	_check("recovery-save fixture starts", bool(first["ok"]), str(first["errors"]))
	if not bool(first["ok"]):
		return
	var variant: Dictionary = first["variant"]
	var id: String = str(variant["id"])
	var second_recipe: Dictionary = _recipe()
	second_recipe["scale"] = 1.2
	var second: Dictionary = Store.save_variant("Recovery save Stik", "jensen-das-ugly-stik-60", base_bytes, second_recipe, id, _root, variant.get("workshop_descriptor", {}), variant.get("dependencies", {}), 1)
	_check("recovery-save fixture has a previous manifest backup", bool(second["ok"]) and FileAccess.file_exists(ProjectSettings.globalize_path(_root + "/" + id + "/manifest.json.bak")), str(second["errors"]))
	if not bool(second["ok"]):
		Store.delete_variant(id, _root)
		return
	var manifest_path: String = ProjectSettings.globalize_path(_root + "/" + id + "/manifest.json")
	_check("recovery-save corrupt manifest fixture writes", _write_file(manifest_path, "{".to_utf8_buffer()))
	var before_save: Dictionary = Store.load_variant(id, _root)
	_check("recovery-save fixture reloads the last committed revision", bool(before_save["ok"]) and int(before_save["variant"]["revision"]) == 1, str(before_save["errors"]))
	var third_recipe: Dictionary = _recipe()
	third_recipe["scale"] = 1.3
	var third: Dictionary = Store.save_variant("Recovery save Stik", "jensen-das-ugly-stik-60", base_bytes, third_recipe, id, _root, {}, {}, 1)
	_check("save after backup recovery commits a new immutable revision", bool(third["ok"]) and int(third.get("variant", {}).get("revision", 0)) == 3, str(third["errors"]))
	_check("save after recovery keeps the valid prior backup", bool(third["ok"]) and FileAccess.file_exists(ProjectSettings.globalize_path(_root + "/" + id + "/manifest.json.bak")) and int(Store.load_variant(id, _root).get("variant", {}).get("revision", 0)) == 3)
	var deleted: Dictionary = Store.delete_variant(id, _root)
	_check("recovery-save fixture is removed", bool(deleted["ok"]), str(deleted["errors"]))


func _recipe() -> Dictionary:
	return {
		"scale": 1.0,
		"mass_policy": "constant_wing_loading",
		"weight_multiplier": 1.0,
		"power_multiplier": 1.0,
		"control_multiplier": 1.0,
		"tank_capacity_multiplier": 1.0,
	}


func _contains_variant(variants: Array, id: String) -> bool:
	for variant: Dictionary in variants:
		if str(variant.get("id", "")) == id:
			return true
	return false


func _has_error(errors: PackedStringArray, needle: String) -> bool:
	for message: String in errors:
		if needle in message:
			return true
	return false


func _write_file(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	return ok


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _finish() -> void:
	_remove_tree(ProjectSettings.globalize_path(_root))
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _remove_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		var child: String = path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	directory = null
	DirAccess.remove_absolute(path)
