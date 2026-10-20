extends SceneTree
## AE-03a: bounded cleanup of the first-save directory owned by a live transaction.

const Store := preload("res://workshop/store.gd")
const Compiler := preload("res://workshop/compiler.gd")
const BASE_PATH: String = "res://data/aircraft/jensen_ugly_stik_60.json"

var _root: String = ""
var _checks: int = 0
var _failures: int = 0
var _active_fixture: Dictionary = {}
var _saved_prefix: Dictionary = {}
var _fault: String = ""


func _initialize() -> void:
	_root = "user://workshop_staging_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_test_known_layouts()
	_test_unknown_layouts()
	_test_target_and_reservation()
	_test_links()
	_test_remove_failure()
	_test_save_failures()
	var absolute_root: String = ProjectSettings.globalize_path(_root)
	var user_root: String = ProjectSettings.globalize_path("user://").trim_suffix("/")
	var valid_root: bool = absolute_root.get_base_dir() == user_root \
		and absolute_root.get_file().begins_with("workshop_staging_test_")
	_check("cleanup is restricted to a direct test fixture", valid_root)
	if valid_root: _remove_tree(absolute_root)
	print("Workshop staging: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _fixture(name: String) -> Dictionary:
	var root_path: String = ProjectSettings.globalize_path(_root.path_join(name))
	var id: String = Store._new_uuid()
	var reservation := Store.VariantWriteGuard.new(root_path, id)
	_check(name + " reserves its own UUID", reservation.acquired)
	var stage: String = root_path.path_join("_staging").path_join(id + "-" + Store._new_uuid())
	_check(name + " creates its own staging directory", DirAccess.make_dir_recursive_absolute(stage) == OK)
	return {"root": root_path, "stage": stage, "id": id, "reservation": reservation}


func _discard(fixture: Dictionary) -> Dictionary:
	return Store._discard_first_save_stage(fixture.root, fixture.stage, fixture.id, fixture.reservation)


func _write(path: String, text: String = "partial owned bytes") -> void:
	_check("fixture writes " + path.get_file(), Store._write_bytes(path, text.to_utf8_buffer()).ok)


func _test_known_layouts() -> void:
	for layout: String in ["empty", "revision_temp", "manifest_temp", "complete", "entry_limit"]:
		var fixture: Dictionary = _fixture(layout)
		if layout != "empty":
			var revisions: String = fixture.stage.path_join("revisions")
			_check(layout + " creates revisions", DirAccess.make_dir_absolute(revisions) == OK)
			var record_name: String = "00000001.json"
			if layout == "revision_temp": record_name += ".tmp-" + Store._new_uuid()
			_write(revisions.path_join(record_name))
			if layout != "revision_temp":
				var manifest_name: String = "manifest.json"
				if layout == "manifest_temp": manifest_name += ".tmp-" + Store._new_uuid()
				_write(fixture.stage.path_join(manifest_name))
			if layout == "entry_limit":
				for index: int in range(5): _write(fixture.stage.path_join("manifest.json.tmp-" + Store._new_uuid()))
		var result: Dictionary = _discard(fixture)
		_check(layout + " removes only its known layout", result.ok
			and not DirAccess.dir_exists_absolute(fixture.stage), str(result.errors))
		_check(layout + " retains its write reservation during cleanup", DirAccess.dir_exists_absolute(fixture.reservation.directory))
		_check(layout + " repeated cleanup is harmless", _discard(fixture).ok)


func _test_unknown_layouts() -> void:
	for layout: String in ["unknown_root", "hidden_file", "unknown_revision", "nested", "bad_temp", "too_many"]:
		var fixture: Dictionary = _fixture(layout)
		var revisions: String = fixture.stage.path_join("revisions")
		_check(layout + " creates revisions", DirAccess.make_dir_absolute(revisions) == OK)
		_write(fixture.stage.path_join("manifest.json"))
		_write(revisions.path_join("00000001.json"))
		match layout:
			"unknown_root": _write(fixture.stage.path_join("notes.txt"))
			"hidden_file": _write(fixture.stage.path_join(".keep"))
			"unknown_revision": _write(revisions.path_join("00000002.json"))
			"nested":
				_check("nested fixture creates a child", DirAccess.make_dir_absolute(revisions.path_join("unexpected")) == OK)
				_write(revisions.path_join("unexpected/manifest.json"))
			"bad_temp": _write(fixture.stage.path_join("manifest.json.tmp-not-a-uuid"))
			"too_many":
				for index: int in range(6): _write(fixture.stage.path_join("manifest.json.tmp-" + Store._new_uuid()))
		var before: Dictionary = _tree_bytes(fixture.stage)
		var result: Dictionary = _discard(fixture)
		_check(layout + " refuses before deleting any file", not result.ok and not result.errors.is_empty()
			and _tree_bytes(fixture.stage) == before, str(result.errors))


func _test_target_and_reservation() -> void:
	var fixture: Dictionary = _fixture("target_guard")
	_write(fixture.stage.path_join("manifest.json"))
	var before: Dictionary = _tree_bytes(fixture.root)
	_check("missing reservation refuses cleanup", not Store._discard_first_save_stage(
		fixture.root, fixture.stage, fixture.id, null).ok)
	var competing := Store.VariantWriteGuard.new(fixture.root, fixture.id)
	_check("busy reservation cannot authorize cleanup", not competing.acquired and not Store._discard_first_save_stage(
		fixture.root, fixture.stage, fixture.id, competing).ok)
	_check("another UUID cannot authorize cleanup", not Store._discard_first_save_stage(
		fixture.root, fixture.stage, Store._new_uuid(), fixture.reservation).ok)
	_check("another store root cannot authorize cleanup", not Store._discard_first_save_stage(
		fixture.root.get_base_dir(), fixture.stage, fixture.id, fixture.reservation).ok)
	_check("unsafe roots refuse cleanup", not Store._discard_first_save_stage(
		"res://data", fixture.stage, fixture.id, fixture.reservation).ok)
	_check("refused targets preserve all bytes", _tree_bytes(fixture.root) == before)
	var live_path: String = fixture.root.path_join(fixture.id)
	_check("published-path fixture moves", DirAccess.rename_absolute(fixture.stage, live_path) == OK)
	_check("a published UUID is never a cleanup target", not Store._discard_first_save_stage(
		fixture.root, live_path, fixture.id, fixture.reservation).ok
		and FileAccess.get_file_as_string(live_path.path_join("manifest.json")) == "partial owned bytes")


func _test_links() -> void:
	for location: String in ["stage", "revisions", "staging_parent", "store_ancestor"]:
		var fixture: Dictionary = _fixture("link_" + location)
		var target: String = ProjectSettings.globalize_path(_root.path_join("protected_" + location))
		_check(location + " protected target creates", DirAccess.make_dir_recursive_absolute(target) == OK)
		_write(target.path_join("manifest.json"), "must survive")
		var link_path: String = fixture.stage
		match location:
			"stage": _check("empty stage removed before link", DirAccess.remove_absolute(fixture.stage) == OK)
			"revisions": link_path = fixture.stage.path_join("revisions")
			"staging_parent":
				link_path = fixture.stage.get_base_dir()
				_check("empty stage removed before parent link", DirAccess.remove_absolute(fixture.stage) == OK)
				_check("empty staging parent removed before link", DirAccess.remove_absolute(link_path) == OK)
			"store_ancestor":
				# Create an alias above a second valid store, so the reservation itself is real.
				link_path = fixture.root.path_join("alias")
		if not _make_directory_link(target, link_path):
			_check(location + " link fixture is available", false)
			continue
		if location == "store_ancestor":
			fixture = _fixture("link_store_ancestor/alias/nested")
		var before: Dictionary = _tree_bytes(target)
		var result: Dictionary = _discard(fixture)
		_check(location + " link prevents cleanup", not result.ok and _tree_bytes(target) == before, str(result.errors))
		_check(location + " link remains intact", DirAccess.open(link_path.get_base_dir()).is_link(link_path))


func _make_directory_link(target: String, link_path: String) -> bool:
	if DirAccess.open(target).create_link(target, link_path) == OK: return true
	if OS.get_name() != "Windows": return false
	# Directory junctions do not require Windows Developer Mode. Both paths belong
	# to this isolated fixture; escape PowerShell string literals explicitly.
	var command: String = "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path '%s' -Target '%s' | Out-Null" % [
		link_path.replace("'", "''"), target.replace("'", "''")]
	var output: Array = []
	return OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", command]), output, true) == 0


func _test_remove_failure() -> void:
	if OS.get_name() != "Windows":
		print("Windows open-file removal refusal is not applicable on this host")
		return
	var fixture: Dictionary = _fixture("remove_failure")
	var manifest_path: String = fixture.stage.path_join("manifest.json")
	_write(manifest_path, "held file must survive")
	var held_file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	_check("open-file fixture acquires a real handle", held_file != null)
	if held_file == null: return
	var refused: Dictionary = _discard(fixture)
	_check("filesystem removal error retains the staging data", not refused.ok
		and str(refused.errors).contains("Could not remove")
		and FileAccess.get_file_as_string(manifest_path) == "held file must survive", str(refused.errors))
	held_file.close()
	_check("cleanup can retry after handle release", _discard(fixture).ok
		and not DirAccess.dir_exists_absolute(fixture.stage))


func _test_save_failures() -> void:
	for fault: String in ["revision_readback", "manifest_readback", "unknown_retained"]:
		_active_fixture = _fixture("save_" + fault)
		# Let the actual save acquire its own reservation and unique staging directory.
		_active_fixture.reservation = null
		_fault = fault
		var result: Dictionary = Store._save_variant("Failed save", "jensen-das-ugly-stik-60",
			FileAccess.get_file_as_bytes(BASE_PATH), Compiler.defaults(), _active_fixture.id,
			_root.path_join("save_" + fault), {}, {}, 0, {}, Callable(self, "_save_checkpoint"))
		_check(fault + " actual save fails explicitly", not result.ok and not result.errors.is_empty(), str(result.errors))
		var stages: PackedStringArray = DirAccess.open(_active_fixture.root.path_join("_staging")).get_directories()
		# _fixture's earlier empty stage is unrelated and must remain untouched.
		_check(fault + " preserves earlier unrelated stage", stages.has(_active_fixture.stage.get_file()))
		if fault == "unknown_retained":
			_check("unknown live-save content retains every byte", stages.size() == 2
				and _tree_bytes(_active_fixture.root) == _saved_prefix)
		else:
			_check(fault + " removes only this failed save's stage", stages.size() == 1
				and str(result.errors).contains("exact-byte readback"))
		_check(fault + " failure releases reservation", not DirAccess.dir_exists_absolute(
			_active_fixture.root.path_join("_locks").path_join(_active_fixture.id)))


func _save_checkpoint(stage: String) -> bool:
	var wanted: String = "after_revision_temp_write" if _fault == "revision_readback" else "after_manifest_temp_write"
	if _fault == "unknown_retained": wanted = "after_revision_commit"
	if stage != wanted: return true
	var staging_root: String = _active_fixture.root.path_join("_staging")
	for entry: String in DirAccess.open(staging_root).get_directories():
		var stage_path: String = staging_root.path_join(entry)
		if stage_path == _active_fixture.stage: continue
		if _fault == "unknown_retained":
			_write(stage_path.path_join("notes.txt"), "unexpected data must survive")
			_saved_prefix = _tree_bytes(_active_fixture.root)
			return false
		var directory_path: String = stage_path.path_join("revisions") if _fault == "revision_readback" else stage_path
		for filename: String in DirAccess.open(directory_path).get_files():
			if filename.contains(".tmp-"): _write(directory_path.path_join(filename), "cut")
	return true


func _tree_bytes(path: String) -> Dictionary:
	var files: Dictionary = {}
	var directory: DirAccess = DirAccess.open(path)
	if directory == null: return files
	for filename: String in directory.get_files(): files[filename] = FileAccess.get_file_as_bytes(path.path_join(filename))
	for child: String in directory.get_directories():
		if directory.is_link(child): continue
		var nested: Dictionary = _tree_bytes(path.path_join(child))
		for filename: String in nested: files[child + "/" + filename] = nested[filename]
	return files


func _remove_tree(path: String) -> void:
	var parent: DirAccess = DirAccess.open(path.get_base_dir())
	if parent != null and parent.is_link(path):
		DirAccess.remove_absolute(path)
		return
	var directory: DirAccess = DirAccess.open(path)
	if directory == null: return
	for child: String in directory.get_directories(): _remove_tree(path.path_join(child))
	for filename: String in directory.get_files(): DirAccess.remove_absolute(path.path_join(filename))
	directory = null
	DirAccess.remove_absolute(path)


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
