extends SceneTree

const PresentationSources := preload("res://render/presentation_sources.gd")
const PACKAGE_PROOF_PATH := "res://data/aircraft_customization_package.json"
const TEMP_ROOT := "user://presentation-source-tests"

var _checks := 0
var _failures := 0
var _created_files: PackedStringArray = []
var _created_dir := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var case_name := _argument_value(args, "--case=")
	if not case_name.is_empty():
		_run_case(case_name, _argument_value(args, "--pack="), int(_argument_value(args, "--proof-version=")))
		print("Presentation source proof child: %s, %d failures" % [case_name, _failures])
		quit(1 if _failures > 0 else 0)
		return
	_run_parent()


func _run_parent() -> void:
	_test_development_records()
	var temp_dir := TEMP_ROOT + "-" + str(Time.get_ticks_usec())
	_created_dir = ProjectSettings.globalize_path(temp_dir)
	var valid_pack := _build_pack(temp_dir, "valid", "")
	_run_child("valid", valid_pack)
	var bad_proof_pack := _build_pack(temp_dir, "bad_proof", "corrupt_proof")
	_run_child("bad_proof", bad_proof_pack)
	var extra_source_pack := _build_pack(temp_dir, "extra_source", "extra_source")
	_run_child("extra_source", extra_source_pack)
	var wrong_destination_pack := _build_pack(temp_dir, "wrong_destination", "wrong_destination")
	_run_child("wrong_destination", wrong_destination_pack)
	var missing_proof_pack := _build_pack(temp_dir, "missing_proof", "missing_proof")
	_run_child("missing_proof", missing_proof_pack)
	var missing_marker_pack := _build_pack(temp_dir, "missing_marker", "missing_marker")
	_run_child("missing_marker", missing_marker_pack)
	var legacy_v1_pack := _build_pack(temp_dir, "legacy_v1", "", 1)
	_run_child("legacy_v1", legacy_v1_pack, 1)
	var legacy_v2_pack := _build_pack(temp_dir, "legacy_v2", "", 2)
	_run_child("legacy_v2", legacy_v2_pack, 2)
	_cleanup()
	print("Presentation source proofs: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_development_records() -> void:
	var records := PresentationSources.current_records()
	var record_paths: Array[String] = []
	for record: Dictionary in records:
		record_paths.append(str(record.get("path", "")))
	_check("the v3 closed source set has twenty-three ordered records", records.size() == PresentationSources.SOURCE_PATHS_V3.size()
		and records.size() == 23 and record_paths == PresentationSources.SOURCE_PATHS_V3, str(record_paths))
	var legacy_records := PresentationSources.current_records(1)
	_check("v1 seven-path source reader remains available", legacy_records.size() == 7
		and PresentationSources.validate(legacy_records, PresentationSources.ENGINE_VERSION_PIN, 1).get("ok", false))
	var v2_records := PresentationSources.current_records(2)
	_check("v2 ten-path source reader remains available", v2_records.size() == 10
		and PresentationSources.validate(v2_records, PresentationSources.ENGINE_VERSION_PIN, 2).get("ok", false))
	_check("proof version cannot silently select another inventory", not PresentationSources.validate(records, PresentationSources.ENGINE_VERSION_PIN, 2).get("ok", true))
	_check("unknown proof versions reject", not PresentationSources.validate(records, PresentationSources.ENGINE_VERSION_PIN, 4).get("ok", true))
	var valid: Dictionary = PresentationSources.validate(records, PresentationSources.ENGINE_VERSION_PIN, 3)
	_check("current LF-normalized source pins validate in development", bool(valid.get("ok", false)), str(valid))
	var stale := records.duplicate(true)
	var stale_hash := str(stale[0].sha256)
	stale[0].sha256 = ("0" if stale_hash.substr(0, 1) != "0" else "1") + stale_hash.substr(1)
	var rejected: Dictionary = PresentationSources.validate(stale, PresentationSources.ENGINE_VERSION_PIN, 3)
	_check("stale source hash is refused", not bool(rejected.get("ok", true)) and _has_code(rejected, "PRESENTATION_SOURCE_HASH_MISMATCH"), str(rejected))
	rejected = PresentationSources.validate(records, "4.7.3", 3)
	_check("changed presentation engine pin is refused", not bool(rejected.get("ok", true)), str(rejected))
	var wrong_order := records.duplicate(true)
	wrong_order[0].path = "res://render/not-registered.gd"
	rejected = PresentationSources.validate(wrong_order, PresentationSources.ENGINE_VERSION_PIN, 3)
	_check("unregistered presentation source is refused", not bool(rejected.get("ok", true)), str(rejected))
	var extra_record := records.duplicate(true)
	extra_record.append(records[0].duplicate(true))
	rejected = PresentationSources.validate(extra_record, PresentationSources.ENGINE_VERSION_PIN, 3)
	_check("extra presentation sources are refused", not bool(rejected.get("ok", true)), str(rejected))


func _build_pack(temp_dir: String, case_name: String, fault: String, proof_version: int = 3) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(temp_dir))
	var pack_path := temp_dir.path_join(case_name + ".pck")
	var packer := PCKPacker.new()
	var error: Error = packer.pck_start(ProjectSettings.globalize_path(pack_path))
	_check("PCKPacker starts " + case_name, error == OK, error_string(error))
	if error != OK:
		return ""
	var sentinel := _write_source(temp_dir, case_name + "-project-binary", "test sentinel".to_utf8_buffer())
	error = packer.add_file("res://project.binary", sentinel)
	_check("PCKPacker adds export sentinel: " + case_name, error == OK, error_string(error))
	if error != OK:
		return ""
	var files: Dictionary = {}
	var source_paths: Array = PresentationSources.paths_for_version(proof_version)
	for index in source_paths.size():
		var source_path := str(source_paths[index])
		var proof_path: String = PresentationSources.expected_proof_path(source_path)
		var absolute_source := ProjectSettings.globalize_path(source_path)
		var proof_source := absolute_source
		if fault == "corrupt_proof" and index == 0:
			proof_source = _write_source(temp_dir, case_name + "-corrupt-proof", "wrong authoring bytes".to_utf8_buffer())
		if not (fault == "missing_proof" and index == 0):
			error = packer.add_file(proof_path, proof_source)
			_check("PCKPacker adds proof for " + source_path, error == OK, error_string(error))
			if error != OK:
				return ""
		files[source_path] = proof_path
	if fault == "extra_source":
		files["res://render/unregistered.gd"] = "res://data/aircraft_customization_proofs/unregistered.bin"
	elif fault == "wrong_destination":
		files[str(source_paths[0])] = "res://data/aircraft_customization_proofs/wrong.bin"
	if fault != "missing_marker":
		var marker_text := JSON.stringify({"format": PresentationSources.package_format_for_version(proof_version), "files": files}, "\t", true) + "\n"
		var marker_source := _write_source(temp_dir, case_name + "-marker", marker_text.to_utf8_buffer())
		error = packer.add_file(PACKAGE_PROOF_PATH, marker_source)
		_check("PCKPacker adds proof marker: " + case_name, error == OK, error_string(error))
		if error != OK:
			return ""
	error = packer.flush()
	_check("PCKPacker flushes " + case_name, error == OK, error_string(error))
	if error != OK:
		return ""
	var absolute_pack_path := ProjectSettings.globalize_path(pack_path)
	_created_files.append(absolute_pack_path)
	return absolute_pack_path


func _run_child(case_name: String, pack_path: String, proof_version: int = 3) -> void:
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
		"res://tests/test_presentation_sources.gd",
		"--",
		"--case=" + case_name,
		"--pack=" + pack_path,
		"--proof-version=" + str(proof_version),
	])
	var exit_code := OS.execute(OS.get_executable_path(), command, output, true)
	var detail := "\n".join(output)
	if exit_code != 0 and FileAccess.file_exists(child_log_path):
		var log_file := FileAccess.open(child_log_path, FileAccess.READ)
		if log_file != null:
			detail += "\n" + log_file.get_as_text()
	_check("isolated PCK presentation proof case runs: " + case_name, exit_code == 0, detail)


func _run_case(case_name: String, pack_path: String, proof_version: int) -> void:
	if pack_path.is_empty() or not ProjectSettings.load_resource_pack(pack_path, true):
		_check("test PCKPacker overlay mounts: " + case_name, false, pack_path)
		return
	_check("export sentinel exists in overlay: " + case_name, FileAccess.file_exists("res://project.binary"))
	var records := PresentationSources.current_records(proof_version)
	var result: Dictionary = PresentationSources.validate(records, PresentationSources.ENGINE_VERSION_PIN, proof_version)
	if case_name in ["valid", "legacy_v1", "legacy_v2"]:
		_check("source proof validator accepts PCK authoring bytes", bool(result.get("ok", false)), str(result))
	elif case_name == "bad_proof":
		_check("source proof validator rejects changed PCK authoring bytes", not bool(result.get("ok", true)) and _has_code(result, "PRESENTATION_SOURCE_HASH_MISMATCH"), str(result))
	else:
		var expected_code := "PRESENTATION_PACKAGE_INVALID"
		if case_name == "missing_proof":
			expected_code = "PRESENTATION_PACKAGE_PROOF_MISSING"
		elif case_name == "missing_marker":
			expected_code = "PRESENTATION_PACKAGE_MISSING"
		_check("source proof validator refuses closed package failure: " + case_name, not bool(result.get("ok", true)) and _has_code(result, expected_code), str(result))


func _write_source(temp_dir: String, name: String, contents: PackedByteArray) -> String:
	var path := temp_dir.path_join(name + ".bin")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("scratch source opens: " + name, false, error_string(FileAccess.get_open_error()))
		return ""
	file.store_buffer(contents)
	file.close()
	var absolute := ProjectSettings.globalize_path(path)
	_created_files.append(absolute)
	return absolute


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
