extends SceneTree
## AE-03a: real transaction prefixes, with optional abrupt writer termination.
## Default runs are bounded unit checks. --process-cuts starts disposable writers.

const Store := preload("res://workshop/store.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Profile := preload("res://workshop/presentation.gd")
const BASE_ID: String = "jensen-das-ugly-stik-60"
const BASE_PATH: String = "res://data/aircraft/jensen_ugly_stik_60.json"
const ROOT_PREFIX: String = "user://workshop_store_cuts_"
const COMMON_STAGES: Array[String] = [
	"after_revisions_create", "after_revision_temp_write", "after_revision_temp_readback",
	"after_revision_commit", "after_manifest_temp_write", "after_manifest_temp_readback",
]

var _checks: int = 0
var _failures: int = 0
var _cases: int = 0
var _roots: Array[String] = []
var _cut_at: String = ""
var _cut_reached: bool = false
var _worker_root: String = ""


func _initialize() -> void:
	var options: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			options[argument.get_slice("=", 0)] = argument.get_slice("=", 1)
	if options.has("--worker-root"):
		_run_worker(options)
		return
	var process_cuts: bool = OS.get_cmdline_user_args().has("--process-cuts")
	for scenario: String in ["first", "update", "rotate", "recovered"]:
		var stages: Array[String] = COMMON_STAGES.duplicate()
		match scenario:
			"first":
				stages.push_front("after_staging_create")
				stages.append_array(["after_manifest_commit", "before_first_publish", "after_first_publish"])
			"update": stages.append_array(["after_backup_rotate", "after_manifest_commit"])
			"rotate": stages.append_array(["after_backup_remove", "after_backup_rotate", "after_manifest_commit"])
			"recovered": stages.append_array(["after_invalid_manifest_remove", "after_manifest_commit"])
		for stage: String in stages:
			_run_case(scenario, stage, process_cuts)
	for fixture_root: String in _roots:
		_remove_fixture(fixture_root)
	print("Workshop store interruptions: %d cases, %d checks, %d failed (process_cuts=%s)" % [
		_cases, _checks, _failures, str(process_cuts)])
	quit(1 if _failures else 0)


func _run_case(scenario: String, stage: String, process_cuts: bool) -> void:
	_cases += 1
	var fixture_root: String = ROOT_PREFIX + "%d_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec(), _cases]
	_roots.append(fixture_root)
	var id: String = Store._new_uuid()
	var label: String = scenario + "/" + stage
	var base_bytes: PackedByteArray = FileAccess.get_file_as_bytes(BASE_PATH)
	var prior: Dictionary = {}
	if scenario != "first":
		var first: Dictionary = Store.save_variant("Previous build", BASE_ID, base_bytes,
			Compiler.defaults(), id, fixture_root, {}, {}, 0, _profile(1))
		_check(label + " seed revision 1", first.ok, str(first.errors))
		if not first.ok: return
		prior = first.variant
		if scenario in ["rotate", "recovered"]:
			var second_recipe: Dictionary = Compiler.defaults()
			second_recipe.scale = 1.1
			var second: Dictionary = Store.save_variant("Second build", BASE_ID, base_bytes,
				second_recipe, id, fixture_root, {}, {}, 1, _profile(2))
			_check(label + " seed revision 2", second.ok, str(second.errors))
			if not second.ok: return
			prior = second.variant
			if scenario == "recovered":
				_check(label + " corrupt primary fixture", Store._write_bytes(
					ProjectSettings.globalize_path(fixture_root.path_join(id).path_join("manifest.json")),
					"{".to_utf8_buffer()).ok)
				var recovered: Dictionary = Store.load_variant(id, fixture_root)
				_check(label + " recover old committed build", recovered.ok
					and recovered.variant.revision == 1 and recovered.variant.recovered_from_manifest_backup)
				if not recovered.ok: return
				prior = recovered.variant
	var old_revision: int = int(prior.get("revision", 0))
	var candidate_revision: int = 1 if scenario == "first" else (2 if scenario == "update" else 3)
	var original_revisions: Dictionary = _revision_bytes(fixture_root, id)
	_cut_at = stage
	_cut_reached = false
	if process_cuts:
		var output: Array = []
		var exit_code: int = OS.execute(OS.get_executable_path(), PackedStringArray([
			"--headless", "--path", ProjectSettings.globalize_path("res://"), "--audio-driver", "Dummy",
			"--script", get_script().resource_path, "--", "--worker-root=" + fixture_root,
			"--worker-id=" + id, "--cut-at=" + stage, "--expected=" + str(old_revision),
		]), output, true)
		var marker_path: String = ProjectSettings.globalize_path(fixture_root.path_join("cut.txt"))
		_cut_reached = FileAccess.file_exists(marker_path) and FileAccess.get_file_as_string(marker_path) == stage
		# Godot's Windows OS.kill uses TerminateProcess(..., 0); exit code alone is not proof.
		_check(label + " abrupt writer exit", exit_code != -1 and _cut_reached
			and not "\n".join(output).contains("worker returned"), str(output))
		var log_text: String = "\n".join(output)
		_check(label + " worker has no engine errors", not log_text.contains("ERROR:")
			and not log_text.contains("SCRIPT ERROR:"), log_text)
	else:
		var interrupted: Dictionary = _candidate(fixture_root, id, old_revision, Callable(self, "_checkpoint"))
		_check(label + " injected failure is explicit", not interrupted.ok
			and str(interrupted.errors).contains(stage), str(interrupted.errors))
	_check(label + " exact cut reached", _cut_reached)
	if not _cut_reached: return
	var absolute_root: String = ProjectSettings.globalize_path(fixture_root)
	if scenario == "first":
		var staging: DirAccess = DirAccess.open(absolute_root.path_join("_staging"))
		_check(label + " only abrupt pre-publication exits retain staging", staging != null
			and staging.get_directories().size() == (1 if process_cuts and stage != "after_first_publish" else 0))
	var lock_path: String = absolute_root.path_join("_locks").path_join(id)
	_check(label + " lock lifecycle", DirAccess.dir_exists_absolute(lock_path) == process_cuts)
	var disk_prefix: Dictionary = _tree_bytes(absolute_root)
	var loaded: Dictionary = Store.load_variant(id, fixture_root)
	var listed: Array = Store.list_variants(fixture_root)
	var candidate_committed: bool = stage == "after_first_publish" if scenario == "first" else stage == "after_manifest_commit"
	var expected_revision: int = candidate_revision if candidate_committed else old_revision
	_check(label + " visible committed revision", loaded.ok == (expected_revision > 0)
		and int(loaded.get("variant", {}).get("revision", 0)) == expected_revision, str(loaded.errors))
	_check(label + " library never promotes staging or orphan revisions", listed.size() == (1 if expected_revision > 0 else 0)
		and (listed.is_empty() or int(listed[0].revision) == expected_revision))
	if expected_revision > 0 and loaded.ok:
		var visible: Dictionary = loaded.variant
		_check(label + " complete physical and visual payload", visible.base_bytes == base_bytes
			and visible.name == ("Candidate build" if candidate_committed else prior.name)
			and visible.recipe == (_candidate_recipe() if candidate_committed else prior.recipe)
			and visible.presentation_profile == (_profile(3) if candidate_committed else prior.presentation_profile),
			"recipe=%s profile=%s" % [str(visible.recipe), str(visible.presentation_profile)])
		if not prior.is_empty():
			_check(label + " source and compiler pins survive", visible.workshop_descriptor == prior.workshop_descriptor
				and visible.dependencies == prior.dependencies and visible.compiler_version == prior.compiler_version)
	_check(label + " reading preserves every prefix byte", _tree_bytes(absolute_root) == disk_prefix)
	_check(label + " immutable revisions survive", _contains_bytes(_revision_bytes(fixture_root, id), original_revisions))
	if process_cuts:
		var refused: Dictionary = _candidate(fixture_root, id, expected_revision)
		_check(label + " orphan reservation blocks overwrite", not refused.ok and str(refused.errors).contains("busy"))
		_check(label + " orphan reservation blocks delete", not Store.delete_variant(id, fixture_root).ok)
		var copy: Dictionary = _candidate(fixture_root, "", 0)
		_check(label + " Save a copy remains available", copy.ok and copy.variant.id != id, str(copy.errors))
		_check(label + " Save a copy preserves reserved build", _tree_bytes(absolute_root.path_join(id))
			== _subtree_bytes(disk_prefix, id + "/"))
		# OS.execute has reaped our only writer; release only this disposable fixture's lock.
		_check(label + " explicit fixture-only orphan release", DirAccess.remove_absolute(lock_path) == OK)
	var revisions_before_retry: Dictionary = _revision_bytes(fixture_root, id)
	var max_revision: int = 0
	for filename: String in revisions_before_retry:
		max_revision = maxi(max_revision, int(filename.trim_suffix(".json")))
	var retried: Dictionary = _candidate(fixture_root, id, expected_revision)
	_check(label + " retry publishes a new revision", retried.ok
		and int(retried.variant.revision) == max_revision + 1, str(retried.errors))
	_check(label + " retry never overwrites an orphan revision", _contains_bytes(
		_revision_bytes(fixture_root, id), revisions_before_retry))
	if retried.ok:
		_check(label + " retry rereads exactly", Store.load_variant(id, fixture_root).variant == retried.variant)
		var stale: Dictionary = _candidate(fixture_root, id, expected_revision)
		_check(label + " stale editor cannot repeat the save", not stale.ok and str(stale.errors).contains("expected revision"))


func _candidate(fixture_root: String, id: String, expected: int, checkpoint: Callable = Callable()) -> Dictionary:
	return Store._save_variant("Candidate build", BASE_ID, FileAccess.get_file_as_bytes(BASE_PATH),
		_candidate_recipe(), id, fixture_root, {}, {}, expected, _profile(3), checkpoint)


func _candidate_recipe() -> Dictionary:
	var recipe: Dictionary = Compiler.defaults()
	recipe.scale = 1.25
	return recipe


func _profile(seed_value: int) -> Dictionary:
	var descriptor: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/workshop/" + BASE_ID + ".json"))
	var binding_result: Dictionary = Store._resolve_customization_bindings(BASE_ID, descriptor)
	_check("paint fixture resolves pinned bindings", binding_result.ok, str(binding_result.errors))
	if not binding_result.ok: return {}
	var profile: Dictionary = Profile.defaults(binding_result.bindings)
	profile.visual_seed = seed_value
	profile.paint = [{"slot": binding_result.bindings.paint_slots[0].id,
		"color": "#123456FF" if seed_value == 3 else "#ABCDEFFF", "pattern": "solid", "accent": "none"}]
	var checked: Dictionary = Profile.validate(profile, binding_result.bindings)
	_check("paint fixture is valid and nonempty", checked.ok and not checked.profile.paint.is_empty(), str(checked.errors))
	return checked.profile


func _checkpoint(stage: String) -> bool:
	if stage != _cut_at: return true
	_cut_reached = true
	if not _worker_root.is_empty():
		var marker: Dictionary = Store._write_bytes(ProjectSettings.globalize_path(
			_worker_root.path_join("cut.txt")), stage.to_utf8_buffer())
		if marker.ok:
			OS.kill(OS.get_process_id())
	return false


func _run_worker(options: Dictionary) -> void:
	_worker_root = str(options["--worker-root"])
	if not _valid_fixture_root(_worker_root):
		printerr("Refused unsafe interruption fixture root")
		quit(1)
		return
	_cut_at = str(options.get("--cut-at", ""))
	var result: Dictionary = _candidate(_worker_root, str(options.get("--worker-id", "")),
		int(options.get("--expected", "-1")), Callable(self, "_checkpoint"))
	# Reaching here means the kill failed or the requested boundary was never reached.
	printerr("Interruption worker returned without abrupt termination: ", result.errors)
	quit(1)


func _revision_bytes(fixture_root: String, id: String) -> Dictionary:
	var all_files: Dictionary = _tree_bytes(ProjectSettings.globalize_path(fixture_root.path_join(id).path_join("revisions")))
	var committed: Dictionary = {}
	for filename: String in all_files:
		if filename.ends_with(".json"): committed[filename] = all_files[filename]
	return committed


func _tree_bytes(path: String) -> Dictionary:
	var files: Dictionary = {}
	var directory: DirAccess = DirAccess.open(path)
	if directory == null: return files
	for filename: String in directory.get_files():
		files[filename] = FileAccess.get_file_as_bytes(path.path_join(filename))
	for child: String in directory.get_directories():
		var nested: Dictionary = _tree_bytes(path.path_join(child))
		for filename: String in nested: files[child + "/" + filename] = nested[filename]
	return files


func _subtree_bytes(files: Dictionary, prefix: String) -> Dictionary:
	var subtree: Dictionary = {}
	for filename: String in files:
		if filename.begins_with(prefix): subtree[filename.trim_prefix(prefix)] = files[filename]
	return subtree


func _contains_bytes(actual: Dictionary, expected: Dictionary) -> bool:
	for filename: String in expected:
		if not actual.has(filename) or actual[filename] != expected[filename]: return false
	return true


func _valid_fixture_root(fixture_root: String) -> bool:
	if not fixture_root.begins_with(ROOT_PREFIX): return false
	var suffix: String = fixture_root.trim_prefix(ROOT_PREFIX)
	return not suffix.is_empty() and suffix.replace("_", "").is_valid_int()


func _remove_fixture(fixture_root: String) -> void:
	if not _valid_fixture_root(fixture_root):
		_check("refuse unsafe fixture cleanup", false)
		return
	var absolute_root: String = ProjectSettings.globalize_path(fixture_root).replace("\\", "/")
	var user_root: String = ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/")
	if absolute_root.get_base_dir() != user_root:
		_check("cleanup stays in a direct user-data fixture", false)
		return
	_remove_tree(absolute_root)


func _remove_tree(path: String) -> void:
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
