extends SceneTree
## Focused AE-19 strict data-only bundle, import-copy and no-write refusal tests.

const Bundle := preload("res://workshop/bundle.gd")
const Store := preload("res://workshop/store.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Trial := preload("res://workshop/trial.gd")
const Profile := preload("res://workshop/presentation.gd")

var _checks: int = 0
var _failures: int = 0
var _root: String = ""


func _initialize() -> void:
	_root = "user://workshop_bundle_test_%d_%d" % [int(Time.get_unix_time_from_system()), int(Time.get_ticks_usec())]
	var base_id: String = Catalog.DEFAULT_ID
	var base_bytes: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(base_id).data)
	var recipe: Dictionary = Compiler.defaults()
	var saved: Dictionary = Store.save_variant("Bundle fixture", base_id, base_bytes, recipe, "", _root)
	_check("source variant fixture saves", saved.get("ok", false), str(saved.get("errors", [])))
	if not saved.get("ok", false):
		_finish()
		return
	var original: Dictionary = saved["variant"]
	var exported: Dictionary = Bundle.export_variant(original)
	_check("validated variant exports to a bounded data-only bundle", exported.get("ok", false), str(exported.get("errors", [])))
	if not exported.get("ok", false):
		_finish()
		return
	var bytes: PackedByteArray = exported["bytes"]
	var decoded: Dictionary = Bundle.decode(bytes)
	_check("exported bundle strictly decodes", decoded.get("ok", false), str(decoded.get("errors", [])))
	if not decoded.get("ok", false):
		_finish()
		return
	var payload: Dictionary = decoded["payload"]
	_check("bundle preserves exact source snapshot and physical pins",
		payload.base_bytes == base_bytes and payload.workshop_descriptor == original.workshop_descriptor
		and payload.dependencies == original.dependencies)
	_check("bundle recipe is detached from local UUID and display metadata",
		not payload.recipe.has("id") and not payload.recipe.has("name"))
	var original_trial: Dictionary = Trial.freeze({
		"base_id": original.base_id,
		"base_bytes": original.base_bytes,
		"recipe": original.recipe,
		"workshop_descriptor": original.workshop_descriptor,
		"dependencies": original.dependencies,
		"compiler_version": original.compiler_version,
		"variant_id": original.id,
		"variant_revision": original.revision,
		"presentation_profile": original.presentation_profile,
	})
	var portable_trial: Dictionary = Trial.freeze(payload)
	_check("bundle can prepare a detached frozen trial", original_trial.get("ok", false) and portable_trial.get("ok", false),
		str(portable_trial.get("errors", [])))
	if original_trial.get("ok", false) and portable_trial.get("ok", false):
		_check("bundle trial preserves exact physical trial ID and resolved bytes",
			original_trial.identity.trial_id == portable_trial.identity.trial_id
			and original_trial.raw_bytes == portable_trial.raw_bytes
			and original_trial.data == portable_trial.data)
	_test_strict_rejections(bytes, payload)
	_test_import_copy(bytes, original, base_bytes)
	_test_file_read(bytes)
	_finish()


func _test_strict_rejections(bytes: PackedByteArray, payload: Dictionary) -> void:
	_check("empty bundle bytes reject", not Bundle.decode(PackedByteArray()).get("ok", false))
	var oversize := PackedByteArray()
	oversize.resize(Bundle.MAX_BUNDLE_BYTES + 1)
	_check("oversized bundle refuses before JSON parsing", not Bundle.decode(oversize).get("ok", false))
	_check("invalid UTF-8 refuses", not Bundle.decode(PackedByteArray([0xFF])).get("ok", false))
	_check("duplicate JSON keys refuse before Godot decoding",
		not Bundle.decode("{\"format\":\"a\",\"format\":\"b\"}".to_utf8_buffer()).get("ok", false))
	_check("trailing comma refuses", not Bundle.decode("{\"format\":\"openrc-aircraft-variant-bundle\",}".to_utf8_buffer()).get("ok", false))
	_check("unpaired Unicode surrogate refuses", not Bundle.decode("{\"x\":\"\\uD800\"}".to_utf8_buffer()).get("ok", false))
	var deep: String = "[".repeat(Bundle.MAX_BUNDLE_DEPTH + 2) + "0" + "]".repeat(Bundle.MAX_BUNDLE_DEPTH + 2)
	_check("excessively nested JSON refuses", not Bundle.decode(deep.to_utf8_buffer()).get("ok", false))
	var unknown: Dictionary = _copy_bundle_payload(bytes)
	unknown["resource_path"] = "res://scripts/run_me.gd"
	_check("unknown executable/resource fields refuse", not Bundle.decode(_encode(unknown)).get("ok", false))
	var unsafe_dependency: Dictionary = _copy_bundle_payload(bytes)
	var dependency_key: String = unsafe_dependency.dependencies.files.keys()[0]
	var dependency_hash: String = str(unsafe_dependency.dependencies.files[dependency_key])
	unsafe_dependency.dependencies.files.erase(dependency_key)
	unsafe_dependency.dependencies.files["res://scripts/run_me.gd"] = dependency_hash
	_check("resource or script dependency paths refuse", not Bundle.decode(_encode(unsafe_dependency)).get("ok", false))
	var unsafe_descriptor: Dictionary = _copy_bundle_payload(bytes)
	unsafe_descriptor.workshop_descriptor.presentation.scale_root = "res://scripts/run_me.gd"
	_check("unsafe descriptor resource paths refuse", not Bundle.decode(_encode(unsafe_descriptor)).get("ok", false))
	var future_profile: Dictionary = _copy_bundle_payload(bytes)
	future_profile.presentation_profile.version = 2
	future_profile.presentation_profile.future_resource = "res://scripts/run_me.gd"
	var future_bytes: PackedByteArray = _encode(future_profile)
	var future_decoded: Dictionary = Bundle.decode(future_bytes)
	_check("newer profile remains readable as unavailable bundle data",
		future_decoded.get("ok", false) and not future_decoded.get("presentation_profile_available", true), str(future_decoded.get("errors", [])))
	var future_root: String = _root + "/future-import"
	_check("newer profile import refuses without creating a variant store",
		not Bundle.import_variant(future_bytes, future_root).get("ok", false)
		and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(future_root)))
	var unknown_slot: Dictionary = _copy_bundle_payload(bytes)
	unknown_slot.presentation_profile.paint = [{"slot": "unregistered_slot", "color": "#123456FF",
		"pattern": "solid", "accent": "none"}]
	var unknown_slot_bytes: PackedByteArray = _encode(unknown_slot)
	_check("unknown slot may decode structurally but cannot import or write",
		Bundle.decode(unknown_slot_bytes).get("ok", false)
		and not Bundle.import_variant(unknown_slot_bytes, _root + "/unknown-slot-import").get("ok", false)
		and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_root + "/unknown-slot-import")), str(Bundle.decode(unknown_slot_bytes).get("errors", [])))
	var wrong_compiler: Dictionary = _copy_bundle_payload(bytes)
	wrong_compiler.compiler_version = "future-compiler"
	_check("compiler-mismatched import refuses without writes",
		not Bundle.import_variant(_encode(wrong_compiler), _root + "/wrong-compiler-import").get("ok", false)
		and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_root + "/wrong-compiler-import")))


func _test_import_copy(bytes: PackedByteArray, original: Dictionary, base_bytes: PackedByteArray) -> void:
	var imported_root: String = _root + "/imports"
	var imported: Dictionary = Bundle.import_variant(bytes, imported_root)
	_check("portable bundle imports as a new local build", imported.get("ok", false), str(imported.get("errors", [])))
	if not imported.get("ok", false):
		return
	var copy: Dictionary = imported["variant"]
	_check("import allocates a new UUID and retains the exact source bytes",
		copy.id != original.id and copy.base_bytes == base_bytes and copy.revision == 1)
	_check("import retains model, dependency and presentation pins",
		copy.workshop_descriptor == original.workshop_descriptor
		and copy.dependencies == original.dependencies
		and copy.presentation_profile == original.presentation_profile)
	var original_after: Dictionary = Store.load_variant(original.id, _root)
	_check("import leaves the original immutable record untouched",
		original_after.get("ok", false) and original_after.variant.revision == 1
		and original_after.variant.base_bytes == original.base_bytes)
	var imported_trial: Dictionary = Trial.freeze({
		"base_id": copy.base_id, "base_bytes": copy.base_bytes, "recipe": copy.recipe,
		"workshop_descriptor": copy.workshop_descriptor, "dependencies": copy.dependencies,
		"compiler_version": copy.compiler_version, "variant_id": copy.id,
		"variant_revision": copy.revision, "presentation_profile": copy.presentation_profile,
	})
	var source_trial: Dictionary = Trial.freeze({
		"base_id": original.base_id, "base_bytes": original.base_bytes, "recipe": original.recipe,
		"workshop_descriptor": original.workshop_descriptor, "dependencies": original.dependencies,
		"compiler_version": original.compiler_version, "variant_id": original.id,
		"variant_revision": original.revision, "presentation_profile": original.presentation_profile,
	})
	_check("imported copy retains the physical trial ID", imported_trial.get("ok", false)
		and source_trial.get("ok", false) and imported_trial.identity.trial_id == source_trial.identity.trial_id)


func _test_file_read(bytes: PackedByteArray) -> void:
	var path: String = ProjectSettings.globalize_path(_root + "/fixture.orv")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("bundle file fixture opens", false)
		return
	file.store_buffer(bytes)
	file.close()
	var read: Dictionary = Bundle.read_file(path)
	_check("local bundle file reads through FileAccess and strict decode", read.get("ok", false), str(read.get("errors", [])))
	_check("resource URI cannot be used as a bundle file path", not Bundle.read_file("res://data/aircraft/jensen_ugly_stik_60.json").get("ok", false))


func _copy_bundle_payload(bytes: PackedByteArray) -> Dictionary:
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return parsed.duplicate(true) if typeof(parsed) == TYPE_DICTIONARY else {}


func _encode(value: Dictionary) -> PackedByteArray:
	return (JSON.stringify(value, "", true, true) + "\n").to_utf8_buffer()


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _finish() -> void:
	_remove_tree(ProjectSettings.globalize_path(_root))
	print("Workshop bundle: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _remove_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		var child: String = path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
