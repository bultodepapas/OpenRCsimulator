extends SceneTree

const Registry := preload("res://aircraft/model_registry.gd")
const PACKAGE_PROOF_PATH := "res://data/aircraft_models/package_proofs.json"
const PACKAGE_PROOF_FORMAT := "openrc-aircraft-model-package v1"
const TEMP_ROOT := "user://aircraft-package-proof-tests"

var _checks := 0
var _failures := 0
var _created_files: PackedStringArray = []
var _created_dir := ""


class SceneLoadSpy extends ResourceFormatLoader:
	var imported_path := ""
	var loads := 0
	func _get_recognized_extensions() -> PackedStringArray:
		return PackedStringArray(["scn", "glb"])
	func _recognize_path(path: String, _type: StringName) -> bool:
		return path == imported_path
	func _exists(path: String) -> bool:
		return path == imported_path
	func _get_resource_type(path: String) -> String:
		return "PackedScene" if path == imported_path else ""
	func _handles_type(type: StringName) -> bool:
		return type == &"PackedScene"
	func _load(_path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
		loads += 1
		return PackedScene.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var case_name := _argument_value(args, "--case=")
	if not case_name.is_empty():
		_run_case(case_name, _argument_value(args, "--pack="))
		print("Aircraft package proof child: %s, %d failures" % [case_name, _failures])
		quit(1 if _failures > 0 else 0)
		return
	_run_parent()


func _run_parent() -> void:
	var temp_dir := TEMP_ROOT + "-" + str(Time.get_ticks_usec())
	_created_dir = ProjectSettings.globalize_path(temp_dir)
	var cases: Array[Dictionary] = [
		{"name": "invalid_json", "marker": "{"},
		{"name": "empty_files", "marker": JSON.stringify({"format": PACKAGE_PROOF_FORMAT, "files": {}})},
		{"name": "unsafe_source", "marker": _marker({"../outside": "res://data/aircraft_models/proofs/unused.bin"})},
		{"name": "wrong_destination", "marker": _marker({"res://aircraft/model_registry.gd": "res://data/aircraft_models/proofs/wrong.bin"})},
		{"name": "missing_proof", "marker": _marker({"res://aircraft/model_registry.gd": _expected_proof_path("res://aircraft/model_registry.gd")})},
	]
	for test_case: Dictionary in cases:
		var pack_path := _build_pack(temp_dir, str(test_case.name), str(test_case.marker), true)
		_run_child(str(test_case.name), pack_path)
	var lazy_pack := _build_pack(temp_dir, "deferred_glb", "", true)
	_run_child("deferred_glb", lazy_pack)
	# Keep this last: it mounts an exported-project sentinel without a marker in a fresh process.
	var missing_pack := _build_pack(temp_dir, "missing_marker", "", true)
	_run_child("missing_marker", missing_pack)
	_cleanup()
	print("Aircraft package proofs: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run_child(case_name: String, pack_path: String) -> void:
	var output: Array = []
	var child_log_path := _created_dir.path_join("child-%s.log" % case_name)
	_created_files.append(child_log_path)
	var command := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--log-file",
		child_log_path,
		"--script",
		"res://tests/test_aircraft_package_proofs.gd",
		"--",
		"--case=" + case_name,
		"--pack=" + pack_path,
	])
	var exit_code := OS.execute(OS.get_executable_path(), command, output, true)
	var detail := "\n".join(output)
	if exit_code != 0 and FileAccess.file_exists(child_log_path):
		var log_file := FileAccess.open(child_log_path, FileAccess.READ)
		if log_file != null:
			detail += "\n" + log_file.get_as_text()
	_check("isolated marker case runs: " + case_name, exit_code == 0, detail)


func _run_case(case_name: String, pack_path: String) -> void:
	if pack_path.is_empty() or not ProjectSettings.load_resource_pack(pack_path, true):
		_check("test PCKPacker overlay mounts: " + case_name, false, pack_path)
		return
	_check("export sentinel exists in overlay: " + case_name, FileAccess.file_exists("res://project.binary"))
	if case_name == "deferred_glb":
		_check_deferred_glb()
		return
	var result: Dictionary = Registry._read_package_proofs()
	var expected_code := "MODEL_PACKAGE_PROOF_INVALID"
	if case_name in ["missing_marker", "missing_proof"]:
		expected_code = "MODEL_PACKAGE_PROOF_MISSING"
	_check("proof loader rejects " + case_name, not result.get("ok", true) and _has_code(result, expected_code), str(result))


func _build_pack(temp_dir: String, case_name: String, marker: String, include_sentinel: bool) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(temp_dir))
	var pack_path := temp_dir.path_join(case_name + ".pck")
	var packer := PCKPacker.new()
	var error: Error = packer.pck_start(ProjectSettings.globalize_path(pack_path))
	_check("PCKPacker starts " + case_name, error == OK, error_string(error))
	if error != OK:
		return ""
	if include_sentinel:
		var sentinel_source := _write_source(temp_dir, case_name + "-project-binary", "test sentinel")
		if sentinel_source.is_empty():
			return ""
		error = packer.add_file("res://project.binary", sentinel_source)
		_check("PCKPacker adds export sentinel: " + case_name, error == OK, error_string(error))
		if error != OK:
			return ""
	if not marker.is_empty():
		var marker_source := _write_source(temp_dir, case_name + "-marker", marker)
		if marker_source.is_empty():
			return ""
		error = packer.add_file(PACKAGE_PROOF_PATH, marker_source)
		_check("PCKPacker adds marker: " + case_name, error == OK, error_string(error))
		if error != OK:
			return ""
	if case_name == "deferred_glb":
		var asset: Dictionary = _corsair_asset()
		error = packer.add_file(_expected_proof_path(asset.path), ProjectSettings.globalize_path(asset.path))
		_check("PCKPacker adds actual Corsair GLB proof", error == OK, error_string(error))
		if error != OK: return ""
	error = packer.flush()
	_check("PCKPacker flushes " + case_name, error == OK, error_string(error))
	if error != OK:
		return ""
	var absolute_pack_path := ProjectSettings.globalize_path(pack_path)
	_created_files.append(absolute_pack_path)
	return absolute_pack_path


func _corsair_asset() -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft_models/f4u-corsair-250.json"))
	return {path = manifest.asset.path, sha256 = manifest.asset.sha256, hash_mode = "raw"}


func _check_deferred_glb() -> void:
	var asset := _corsair_asset()
	_check("default Corsair scene starts unloaded", not ResourceLoader.has_cached(asset.path))
	var sidecar := ConfigFile.new()
	_check("Corsair import sidecar opens", sidecar.load(asset.path + ".import") == OK)
	var spy := SceneLoadSpy.new()
	spy.imported_path = str(sidecar.get_value("remap", "path", ""))
	ResourceLoader.add_resource_format_loader(spy, true)
	var proofs := {str(asset.path): _expected_proof_path(asset.path)}
	var errors := PackedStringArray()
	var diagnostics: Array[Dictionary] = []
	Registry._check_resource_record(asset, "$.asset", proofs, errors, diagnostics)
	_check("packaged GLB proof verifies", errors.is_empty(), str(errors))
	_check("checking provenance does not load an unselected paint", spy.loads == 0)
	asset.sha256 = "0".repeat(64)
	Registry._check_resource_record(asset, "$.asset", proofs, errors, diagnostics)
	_check("deferred GLB still rejects a mismatched hash", _has_code({diagnostics = diagnostics}, "MODEL_HASH_MISMATCH"))
	var intercepted := ResourceLoader.load(asset.path)
	_check("the load spy observes an actual scene request", intercepted != null and spy.loads == 1)
	intercepted = null
	ResourceLoader.remove_resource_format_loader(spy)
	var scene := ResourceLoader.load(asset.path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_check("the real verified scene loads when selected", scene != null and scene.get_state().get_node_count() > 0)


func _write_source(temp_dir: String, name: String, contents: String) -> String:
	var path := temp_dir.path_join(name + ".txt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("scratch source opens: " + name, false, error_string(FileAccess.get_open_error()))
		return ""
	file.store_string(contents)
	file.close()
	_created_files.append(ProjectSettings.globalize_path(path))
	return ProjectSettings.globalize_path(path)


func _marker(files: Dictionary) -> String:
	return JSON.stringify({"format": PACKAGE_PROOF_FORMAT, "files": files})


func _expected_proof_path(source_path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(source_path.to_utf8_buffer())
	return "res://data/aircraft_models/proofs/" + context.finish().hex_encode() + ".bin"


func _argument_value(args: PackedStringArray, prefix: String) -> String:
	for arg: String in args:
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""


func _has_code(result: Dictionary, code: String) -> bool:
	for diagnostic: Dictionary in result.get("diagnostics", []):
		if diagnostic.get("code") == code:
			return true
	return false


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	printerr("FAIL: ", label, " ", detail)


func _cleanup() -> void:
	for path: String in _created_files:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_created_files.clear()
	if not _created_dir.is_empty() and DirAccess.dir_exists_absolute(_created_dir):
		DirAccess.remove_absolute(_created_dir)
	_created_dir = ""
