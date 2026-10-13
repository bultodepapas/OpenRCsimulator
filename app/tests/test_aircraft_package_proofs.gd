extends SceneTree

const Registry := preload("res://aircraft/model_registry.gd")
const PACKAGE_PROOF_PATH := "res://data/aircraft_models/package_proofs.json"
const PACKAGE_PROOF_FORMAT := "openrc-aircraft-model-package v1"
const TEMP_ROOT := "user://aircraft-package-proof-tests"

var _checks := 0
var _failures := 0
var _created_files: PackedStringArray = []
var _created_dir := ""


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
	# Keep this last: it mounts an exported-project sentinel without a marker in a fresh process.
	var missing_pack := _build_pack(temp_dir, "missing_marker", "", true)
	_run_child("missing_marker", missing_pack)
	_cleanup()
	print("Aircraft package proofs: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run_child(case_name: String, pack_path: String) -> void:
	var output: Array = []
	var command := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--script",
		"res://tests/test_aircraft_package_proofs.gd",
		"--",
		"--case=" + case_name,
		"--pack=" + pack_path,
	])
	var exit_code := OS.execute(OS.get_executable_path(), command, output, true)
	_check("isolated marker case runs: " + case_name, exit_code == 0, "\n".join(output))


func _run_case(case_name: String, pack_path: String) -> void:
	if pack_path.is_empty() or not ProjectSettings.load_resource_pack(pack_path, true):
		_check("test PCKPacker overlay mounts: " + case_name, false, pack_path)
		return
	_check("export sentinel exists in overlay: " + case_name, FileAccess.file_exists("res://project.binary"))
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
	error = packer.flush()
	_check("PCKPacker flushes " + case_name, error == OK, error_string(error))
	if error != OK:
		return ""
	var absolute_pack_path := ProjectSettings.globalize_path(pack_path)
	_created_files.append(absolute_pack_path)
	return absolute_pack_path


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
