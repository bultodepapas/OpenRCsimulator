extends SceneTree

const DraftStore = preload("res://workshop/draft_store.gd")
const Store = preload("res://workshop/store.gd")
const Bundle = preload("res://workshop/bundle.gd")
const Compiler = preload("res://workshop/compiler.gd")
const Dependencies = preload("res://workshop/dependencies.gd")
const BASE_PATH: String = "res://data/aircraft/jensen_ugly_stik_60.json"

var _library_root: String = ""
var _draft_root: String = ""
var _stale_root: String = ""
var _fault_root: String = ""
var _fault_roots: Array[String] = []
var _collision_root: String = ""
var _cas_root: String = ""
var _cas_backup_root: String = ""
var _cas_artifact_root: String = ""
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	var suffix: String = "%d_%d" % [int(Time.get_unix_time_from_system()), int(Time.get_ticks_usec())]
	_library_root = "user://workshop_draft_library_%s" % suffix
	_draft_root = "user://workshop_draft_primary_%s" % suffix
	_stale_root = "user://workshop_draft_stale_%s" % suffix
	_fault_root = "user://workshop_draft_fault_%s" % suffix
	_collision_root = "user://workshop_draft_collision_%s" % suffix
	_cas_root = "user://workshop_draft_cas_%s" % suffix
	_cas_backup_root = "user://workshop_draft_cas_backup_%s" % suffix
	_cas_artifact_root = "user://workshop_draft_cas_artifact_%s" % suffix
	var base_bytes: PackedByteArray = FileAccess.get_file_as_bytes(BASE_PATH)
	_check("base fixture reads", not base_bytes.is_empty())
	if base_bytes.is_empty():
		_finish()
		return
	var recipe: Dictionary = Compiler.defaults()
	var saved: Dictionary = Store.save_variant("Recovery fixture", "jensen-das-ugly-stik-60",
		base_bytes, recipe, "", _library_root)
	_check("isolated library fixture saves", bool(saved.get("ok", false)), str(saved.get("errors", [])))
	if not bool(saved.get("ok", false)):
		_finish()
		return
	var variant: Dictionary = saved["variant"]
	var build: Dictionary = _ui_build(variant)
	var editor: Dictionary = _editor_state()
	_test_validation_bounds()
	_test_save_read_and_discard(build, editor, variant)
	_test_recipe_specific_compiler_pin(build, editor)
	_test_stale_dependencies(build, editor, variant)
	_test_fault_matrix(build, editor, variant)
	_test_discard_collision_preflight()
	_test_compare_and_swap(build, editor)
	_finish()


func _ui_build(variant: Dictionary) -> Dictionary:
	return {
		"base_id": variant.base_id,
		"base_bytes": variant.base_bytes.duplicate(),
		"recipe": variant.recipe.duplicate(true),
		"name": variant.name,
		"descriptor": variant.workshop_descriptor.duplicate(true),
		"dependencies": variant.dependencies.duplicate(true),
		"compiler": "",
		"presentation_profile": variant.presentation_profile.duplicate(true),
	}


func _editor_state() -> Dictionary:
	return {
		"page": "smoke",
		"name": "Unapplied build name",
		"numeric_buffers": {"scale": "1..25", "power_multiplier": "pending invalid text"},
		"presentation_buffers": {
			"appearance": {"slot": "", "palette_step": 0, "color_text": "#00GG00",
				"marking_slot": "", "marking_text": "RC-", "marking_color": 0},
			"smoke": {"slot": "", "palette_step": 1, "color_text": "#BAD",
				"marking_slot": "", "marking_text": "", "marking_color": 0},
		},
		"camera": {"mode": "inspect", "comparison_original": false, "yaw_deg": 35.0,
			"pitch_deg": -12.0, "zoom": 1.3, "standard_view": "custom"},
	}


func _test_validation_bounds() -> void:
	var good: Dictionary = DraftStore.validate_editor_state(_editor_state())
	_check("bounded raw editor text remains valid recovery data", bool(good.get("ok", false)), str(good.get("errors", [])))
	var too_long: Dictionary = _editor_state()
	too_long.name = "x".repeat(65)
	_check("oversized editor name is refused", not DraftStore.validate_editor_state(too_long).ok)
	var unknown: Dictionary = _editor_state()
	unknown.injected = "ignored?"
	_check("unknown recovery editor keys are refused", not DraftStore.validate_editor_state(unknown).ok)
	var bad_camera: Dictionary = _editor_state()
	bad_camera.camera.zoom = 100.0
	_check("out-of-range camera state is refused", not DraftStore.validate_editor_state(bad_camera).ok)


func _test_save_read_and_discard(build: Dictionary, editor: Dictionary, variant: Dictionary) -> void:
	var absent: Dictionary = DraftStore.load_snapshot(_draft_root)
	_check("reading an absent draft does not create its root", absent.ok and not absent.exists
		and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_draft_root)))
	var saved: Dictionary = DraftStore.save_snapshot(_draft_root, build, editor)
	_check("accepted build plus invalid pending text saves as a detached snapshot", bool(saved.get("ok", false)), str(saved.get("errors", [])))
	if not bool(saved.get("ok", false)):
		return
	var primary_path: String = _snapshot_path(_draft_root)
	var exact_bytes: PackedByteArray = FileAccess.get_file_as_bytes(primary_path)
	var loaded: Dictionary = DraftStore.load_snapshot(_draft_root)
	_check("fresh compatible snapshot loads but is never directly launchable", loaded.ok and loaded.exists
		and loaded.compatible and not loaded.stale and not loaded.launchable)
	_check("invalid raw text, page, name and camera round-trip unchanged",
		_editor_matches(editor, loaded.get("editor", {})),
		"expected=%s got=%s" % [str(editor), str(loaded.get("editor", {}))])
	_check("recovery compiler pin follows the recipe-specific compiler identity",
		loaded.get("payload", {}).get("compiler_version", "") == Compiler.version_for_recipe(build.recipe))
	_check("recovery bundle is detached from local variant identity",
		str(loaded.get("payload", {}).get("variant_id", "not-empty")) == ""
		and int(loaded.get("payload", {}).get("variant_revision", -1)) == 0)
	var library_before: Dictionary = Store.load_variant(str(variant.id), _library_root)
	var again: Dictionary = DraftStore.load_snapshot(_draft_root)
	_check("read-only load leaves exact snapshot bytes unchanged",
		FileAccess.get_file_as_bytes(primary_path) == exact_bytes and again.ok)
	_check("recovery never changes the saved library revision",
		library_before.ok and int(Store.load_variant(str(variant.id), _library_root).variant.revision) == int(variant.revision))
	var discarded: Dictionary = DraftStore.discard_snapshot(_draft_root)
	_check("explicit discard removes only recovery files", discarded.ok and discarded.discarded
		and not DraftStore.load_snapshot(_draft_root).exists)
	_check("discard leaves the original library entry intact",
		Store.load_variant(str(variant.id), _library_root).ok)


func _test_stale_dependencies(build: Dictionary, editor: Dictionary, variant: Dictionary) -> void:
	var stale_build: Dictionary = build.duplicate(true)
	var stale_manifest: Dictionary = stale_build.dependencies.duplicate(true)
	var files: Dictionary = stale_manifest.files.duplicate(true)
	var dependency_path: String = str(files.keys()[0])
	files[dependency_path] = "0".repeat(64)
	stale_manifest.files = files
	stale_build.dependencies = stale_manifest
	var saved: Dictionary = DraftStore.save_snapshot(_stale_root, stale_build, editor)
	_check("well-formed stale pins remain snapshot-readable", saved.ok, str(saved.get("errors", [])))
	if not saved.ok:
		return
	var loaded: Dictionary = DraftStore.load_snapshot(_stale_root)
	_check("stale dependency snapshot stays readable and explicitly noncompatible",
		loaded.ok and loaded.exists and loaded.stale and not loaded.compatible and not loaded.launchable
		and not loaded.compatibility_errors.is_empty())
	_check("stale snapshot retains its original dependency pin",
		loaded.payload.dependencies.files.get(dependency_path, "") == "0".repeat(64))
	var before: Dictionary = Store.load_variant(str(variant.id), _library_root)
	var discarded: Dictionary = DraftStore.discard_snapshot(_stale_root)
	_check("stale recovery can be explicitly discarded", discarded.ok and discarded.discarded)
	_check("stale recovery handling does not rebind or rewrite library dependencies",
		before.ok and Store.load_variant(str(variant.id), _library_root).variant.dependencies == variant.dependencies)


func _test_recipe_specific_compiler_pin(build: Dictionary, editor: Dictionary) -> void:
	var measured_build: Dictionary = build.duplicate(true)
	measured_build.recipe.mass_edits = [{"id": "battery_test", "mass_kg": 0.2, "source": "recovery fixture"}]
	measured_build.compiler = ""
	var saved: Dictionary = DraftStore.save_snapshot(_draft_root, measured_build, editor)
	_check("measured-mass recovery snapshot writes using its recipe evaluator", saved.ok, str(saved.get("errors", [])))
	if not saved.ok:
		return
	var loaded: Dictionary = DraftStore.load_snapshot(_draft_root)
	_check("measured-mass compiler pin is recipe-specific and still not launchable",
		loaded.ok and loaded.compatible and not loaded.launchable
		and loaded.payload.compiler_version == Compiler.version_for_recipe(measured_build.recipe)
		and loaded.payload.compiler_version == Compiler.MEASURED_MASS_COMPILER_VERSION)
	var discarded: Dictionary = DraftStore.discard_snapshot(_draft_root)
	_check("measured-mass recovery fixture can be explicitly discarded", discarded.ok and discarded.discarded)


func _test_fault_matrix(build: Dictionary, editor: Dictionary, variant: Dictionary) -> void:
	var stages: PackedStringArray = ["after_temp_write", "after_temp_readback", "after_backup_rotate", "after_primary_commit"]
	for stage: String in stages:
		_test_fault_case(stage, false, build, editor, variant)
		_test_fault_case(stage, true, build, editor, variant)


func _test_fault_case(stage: String, updating: bool, build: Dictionary, editor: Dictionary, variant: Dictionary) -> void:
	var root: String = "%s_%s_%s" % [_fault_root, "update" if updating else "first", stage]
	_fault_roots.append(root)
	var initial: Dictionary = build.duplicate(true)
	initial.name = "Initially accepted build"
	initial.recipe.scale = 1.0
	if updating:
		var seed: Dictionary = DraftStore.save_snapshot(root, initial, editor)
		_check("%s update fixture exists before fault" % stage, seed.ok, str(seed.get("errors", [])))
	var candidate: Dictionary = initial.duplicate(true)
	candidate.name = "Candidate at %s" % stage
	candidate.recipe.scale = 1.1
	var candidate_editor: Dictionary = editor.duplicate(true)
	candidate_editor.name = "Candidate editor at %s" % stage
	var faulted: Dictionary = DraftStore.save_snapshot(root, candidate, candidate_editor, stage)
	_check("%s %s fault stops at the requested boundary" % ["update" if updating else "first publication", stage],
		not faulted.ok and DirAccess.dir_exists_absolute(_lock_path(root)))
	var primary: String = _snapshot_path(root)
	var backup_path: String = primary + ".bak"
	var temporary_path: String = primary + ".tmp"
	var primary_before: PackedByteArray = FileAccess.get_file_as_bytes(primary) if FileAccess.file_exists(primary) else PackedByteArray()
	var backup_before: PackedByteArray = FileAccess.get_file_as_bytes(backup_path) if FileAccess.file_exists(backup_path) else PackedByteArray()
	var temporary_before: PackedByteArray = FileAccess.get_file_as_bytes(temporary_path) if FileAccess.file_exists(temporary_path) else PackedByteArray()
	var loaded: Dictionary = DraftStore.load_snapshot(root)
	var expected_scale: float = 1.1 if stage == "after_primary_commit" else 1.0 if updating else -1.0
	if expected_scale >= 0.0:
		_check("%s %s exposes only the last complete accepted snapshot" % ["update" if updating else "first publication", stage],
			loaded.ok and loaded.exists and loaded.writer_active and not loaded.launchable
			and is_equal_approx(float(loaded.payload.recipe.scale), expected_scale)
			and loaded.recovered_from_backup == (updating and stage == "after_backup_rotate"))
	else:
		_check("%s first publication never promotes a temporary" % stage,
			not loaded.ok and loaded.exists and loaded.writer_active and loaded.payload.is_empty())
	var expected_primary: bool = stage == "after_primary_commit" or (updating and stage != "after_backup_rotate")
	var expected_backup: bool = updating and stage in ["after_backup_rotate", "after_primary_commit"]
	var expected_temp: bool = stage != "after_primary_commit"
	_check("%s %s leaves only expected current/previous/temp files" % ["update" if updating else "first publication", stage],
		FileAccess.file_exists(primary) == expected_primary
		and FileAccess.file_exists(backup_path) == expected_backup
		and FileAccess.file_exists(temporary_path) == expected_temp)
	var again: Dictionary = DraftStore.load_snapshot(root)
	_check("%s %s restart-style read does not promote or rewrite bytes" % ["update" if updating else "first publication", stage],
		FileAccess.get_file_as_bytes(primary) == primary_before
		and FileAccess.get_file_as_bytes(backup_path) == backup_before
		and FileAccess.get_file_as_bytes(temporary_path) == temporary_before
		and again.writer_active == loaded.writer_active)
	var blocked_save: Dictionary = DraftStore.save_snapshot(root, candidate, editor)
	var blocked_discard: Dictionary = DraftStore.discard_snapshot(root)
	_check("%s %s lock refuses another write and explicit discard" % ["update" if updating else "first publication", stage],
		not blocked_save.ok and not blocked_discard.ok)
	var library_after: Dictionary = Store.load_variant(str(variant.id), _library_root)
	_check("%s %s fault leaves library revision untouched" % ["update" if updating else "first publication", stage],
		library_after.ok and int(library_after.variant.revision) == int(variant.revision))


func _test_discard_collision_preflight() -> void:
	var directory: String = ProjectSettings.globalize_path(_collision_root.path_join("_workshop_recovery"))
	var primary: String = directory.path_join("snapshot.json")
	var backup_folder: String = directory.path_join("snapshot.json.bak")
	var sentinel: PackedByteArray = "preserve primary".to_utf8_buffer()
	_check("collision fixture directory creates", DirAccess.make_dir_recursive_absolute(directory) == OK)
	var file: FileAccess = FileAccess.open(primary, FileAccess.WRITE)
	if file != null:
		file.store_buffer(sentinel)
		file.flush()
		file.close()
	_check("collision fixture primary writes", FileAccess.file_exists(primary))
	_check("collision fixture backup folder creates", DirAccess.make_dir_absolute(backup_folder) == OK)
	var refused: Dictionary = DraftStore.discard_snapshot(_collision_root)
	_check("discard refuses the complete set of fixed-path folder collisions before deletion",
		not refused.ok and FileAccess.get_file_as_bytes(primary) == sentinel and DirAccess.dir_exists_absolute(backup_folder))


func _test_compare_and_swap(build: Dictionary, editor: Dictionary) -> void:
	var absent: Dictionary = DraftStore.load_snapshot(_cas_root)
	_check("CAS load reports a missing digest before first publication",
		absent.ok and not absent.exists and absent.get("digest", "") == "missing")
	var first_build: Dictionary = build.duplicate(true)
	first_build.name = "First concurrent writer"
	var first: Dictionary = DraftStore.save_snapshot(_cas_root, first_build, editor, "", "missing")
	var primary_path: String = _snapshot_path(_cas_root)
	var first_bytes: PackedByteArray = FileAccess.get_file_as_bytes(primary_path) if FileAccess.file_exists(primary_path) else PackedByteArray()
	_check("first fresh writer publishes against missing state and receives exact-byte digest",
		first.ok and not first.get("conflict", false) and not first_bytes.is_empty()
		and first.get("digest", "") == _sha256(first_bytes))
	var loaded_first: Dictionary = DraftStore.load_snapshot(_cas_root)
	_check("load digest is the exact selected primary record", loaded_first.ok
		and loaded_first.get("digest", "") == first.get("digest", ""))
	var before_second: Dictionary = _fixed_state(_cas_root)
	var second_build: Dictionary = build.duplicate(true)
	second_build.name = "Second fresh writer"
	var second: Dictionary = DraftStore.save_snapshot(_cas_root, second_build, editor, "", "missing")
	_check("second writer that started from missing state gets an explicit CAS conflict",
		not second.ok and second.get("conflict", false) and _fixed_state(_cas_root) == before_second)
	_check("CAS conflict releases its temporary lock without changing committed bytes",
		not DirAccess.dir_exists_absolute(_lock_path(_cas_root)))

	var next_build: Dictionary = build.duplicate(true)
	next_build.name = "Matching digest update"
	next_build.recipe.scale = float(next_build.recipe.scale) + 0.01
	var updated: Dictionary = DraftStore.save_snapshot(_cas_root, next_build, editor, "", str(first.get("digest", "")))
	var updated_bytes: PackedByteArray = FileAccess.get_file_as_bytes(primary_path) if FileAccess.file_exists(primary_path) else PackedByteArray()
	_check("matching selected digest allows update and returns digest for committed envelope",
		updated.ok and not updated.get("conflict", false) and not updated_bytes.is_empty()
		and updated.get("digest", "") == _sha256(updated_bytes))
	_check("updated snapshot digest matches a fresh load", DraftStore.load_snapshot(_cas_root).get("digest", "") == updated.get("digest", ""))
	var before_stale_update: Dictionary = _fixed_state(_cas_root)
	var stale_update: Dictionary = DraftStore.save_snapshot(_cas_root, second_build, editor, "", str(first.get("digest", "")))
	_check("stale writer cannot replace the newer snapshot", not stale_update.ok
		and stale_update.get("conflict", false) and _fixed_state(_cas_root) == before_stale_update)
	var stale_discard: Dictionary = DraftStore.discard_snapshot(_cas_root, str(first.get("digest", "")))
	_check("stale explicit discard refuses without changing either committed record",
		not stale_discard.ok and stale_discard.get("conflict", false)
		and _fixed_state(_cas_root) == before_stale_update)
	var current_digest: String = str(updated.get("digest", ""))
	var current_discard: Dictionary = DraftStore.discard_snapshot(_cas_root, current_digest)
	_check("discard against the selected current digest succeeds", current_discard.ok
		and current_discard.discarded and current_discard.get("digest", "") == "missing")

	var backup_seed_build: Dictionary = build.duplicate(true)
	backup_seed_build.name = "Backup-selected seed"
	var backup_seed: Dictionary = DraftStore.save_snapshot(_cas_backup_root, backup_seed_build, editor, "", "missing")
	var backup_primary: String = _snapshot_path(_cas_backup_root)
	var backup_path: String = backup_primary + ".bak"
	if backup_seed.ok:
		var move_error: Error = DirAccess.rename_absolute(backup_primary, backup_path)
		_check("backup-only fixture moves the committed record without rewriting it", move_error == OK)
	else:
		_check("backup-only fixture seed saves", false, str(backup_seed.get("errors", [])))
	var selected_backup: Dictionary = DraftStore.load_snapshot(_cas_backup_root)
	_check("load exposes the digest of the selected backup record",
		selected_backup.ok and selected_backup.recovered_from_backup
		and selected_backup.get("digest", "") == backup_seed.get("digest", ""))
	var backup_update_build: Dictionary = build.duplicate(true)
	backup_update_build.name = "Backup-selected update"
	var backup_update: Dictionary = DraftStore.save_snapshot(_cas_backup_root, backup_update_build,
		editor, "", str(selected_backup.get("digest", "")))
	_check("matching backup-selected digest permits a fresh primary update",
		backup_update.ok and not backup_update.get("conflict", false)
		and DraftStore.load_snapshot(_cas_backup_root).get("payload", {}).get("name", "") == "Backup-selected update")

	var artifact_directory: String = ProjectSettings.globalize_path(_cas_artifact_root.path_join("_workshop_recovery"))
	_check("CAS artifact fixture directory creates", DirAccess.make_dir_recursive_absolute(artifact_directory) == OK)
	var orphan_temp: String = artifact_directory.path_join("snapshot.json.tmp")
	var orphan_bytes: PackedByteArray = "uncommitted temporary".to_utf8_buffer()
	_write_file(orphan_temp, orphan_bytes)
	var orphan_before: Dictionary = _fixed_state(_cas_artifact_root)
	var orphan_save: Dictionary = DraftStore.save_snapshot(_cas_artifact_root, build, editor, "", "missing")
	_check("missing-state CAS refuses an orphan temporary without deleting it",
		not orphan_save.ok and orphan_save.get("conflict", false) and _fixed_state(_cas_artifact_root) == orphan_before)
	DirAccess.remove_absolute(orphan_temp)
	var invalid_primary: String = _snapshot_path(_cas_artifact_root)
	var corrupt_bytes: PackedByteArray = "corrupt committed bytes".to_utf8_buffer()
	_write_file(invalid_primary, corrupt_bytes)
	var corrupt_before: Dictionary = _fixed_state(_cas_artifact_root)
	var corrupt_save: Dictionary = DraftStore.save_snapshot(_cas_artifact_root, build, editor, "", "missing")
	var invalid_load: Dictionary = DraftStore.load_snapshot(_cas_artifact_root)
	_check("missing-state CAS refuses a corrupt committed file without changing it",
		not corrupt_save.ok and corrupt_save.get("conflict", false)
		and _fixed_state(_cas_artifact_root) == corrupt_before
		and invalid_load.get("digest", "") == _sha256(corrupt_bytes))
	var healthy_replacement: PackedByteArray = FileAccess.get_file_as_bytes(_snapshot_path(_cas_backup_root))
	_write_file(invalid_primary, healthy_replacement)
	var replacement_before: Dictionary = _fixed_state(_cas_artifact_root)
	var stale_corrupt_discard: Dictionary = DraftStore.discard_snapshot(_cas_artifact_root, _sha256(corrupt_bytes))
	_check("captured corrupt digest cannot discard a later healthy replacement",
		not stale_corrupt_discard.ok and stale_corrupt_discard.get("conflict", false)
		and _fixed_state(_cas_artifact_root) == replacement_before)
	_write_file(invalid_primary, corrupt_bytes)
	var corrupt_discard: Dictionary = DraftStore.discard_snapshot(_cas_artifact_root, _sha256(corrupt_bytes))
	_check("explicit discard against the captured bounded corrupt-record digest succeeds",
		corrupt_discard.ok and corrupt_discard.discarded
		and DraftStore.load_snapshot(_cas_artifact_root).get("digest", "") == "missing")


func _fixed_state(root: String) -> Dictionary:
	var state: Dictionary = {"lock": DirAccess.dir_exists_absolute(_lock_path(root))}
	var primary: String = _snapshot_path(root)
	for filename: String in ["snapshot.json", "snapshot.json.bak", "snapshot.json.tmp"]:
		var path: String = primary if filename == "snapshot.json" else primary + filename.trim_prefix("snapshot.json")
		state[filename] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return state


func _write_file(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(bytes)
	file.flush()
	file.close()


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


func _snapshot_path(root: String) -> String:
	return ProjectSettings.globalize_path(root.path_join("_workshop_recovery/snapshot.json"))


func _lock_path(root: String) -> String:
	return ProjectSettings.globalize_path(root.path_join("_workshop_recovery/write.lock"))


func _editor_matches(expected: Dictionary, actual: Dictionary) -> bool:
	if actual.get("page", null) != expected.page or actual.get("name", null) != expected.name:
		return false
	if actual.get("numeric_buffers", {}) != expected.numeric_buffers:
		return false
	var actual_presentations: Dictionary = actual.get("presentation_buffers", {})
	for page: String in ["appearance", "smoke"]:
		var left: Dictionary = actual_presentations.get(page, {})
		var right: Dictionary = expected.presentation_buffers[page]
		for key: String in ["slot", "color_text", "marking_slot", "marking_text"]:
			if left.get(key, null) != right[key]: return false
		for key: String in ["palette_step", "marking_color"]:
			if float(left.get(key, -1)) != float(right[key]): return false
	var actual_camera: Dictionary = actual.get("camera", {})
	for key: String in ["mode", "comparison_original", "standard_view"]:
		if actual_camera.get(key, null) != expected.camera[key]: return false
	for key: String in ["yaw_deg", "pitch_deg", "zoom"]:
		if float(actual_camera.get(key, INF)) != float(expected.camera[key]): return false
	return true


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _finish() -> void:
	for root: String in [_library_root, _draft_root, _stale_root, _fault_root, _collision_root,
			_cas_root, _cas_backup_root, _cas_artifact_root] + _fault_roots:
		_remove_tree(ProjectSettings.globalize_path(root))
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
