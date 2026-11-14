extends SceneTree

const Admission := preload("res://sim/native_macos_admission.gd")
var failed := 0
var checks := 0


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed += 1
		printerr("MAC_ADMISSION failed: " + label)


func _initialize() -> void:
	_read_documents()
	var sha := "a".repeat(64)
	var row := {binary_sha256 = sha, source_sha256 = sha, lock_sha256 = sha, engine_sha256 = sha,
		runtime_os_version = "27.0.1", runtime_os_build = "26A434"}
	var selection := {ok = true, profile = "production", aircraft = "jensen-das-ugly-stik-60",
		battery = "ideal", start = "airborne", weather = "calm", start_sha256 = sha}
	var allowed := {aircraft = selection.aircraft, battery = "ideal", start = "airborne", weather = "calm",
		soft_hull = false, trim_profile = "production", start_sha256 = sha}
	var marker := {format = Admission.FORMAT, scope = Admission.SCOPE, receipt_sha256 = sha,
		domain_sha256 = sha, cpu = "Apple M1", hardware_model = "MacBookAir10,1", binary_sha256 = sha,
		source_sha256 = sha, lock_sha256 = sha, engine_sha256 = sha, os_version = "27.0.1", os_build = "26A434",
		allowed_selections = [allowed]}
	check(Admission.identity_error(marker, sha, row, sha, "Apple M1").is_empty(), "matching identity")
	check(Admission.loaded_identity_error(marker, sha, row).is_empty(), "loaded identity matches")
	check(not Admission.loaded_identity_error(marker, "b".repeat(64), row).is_empty(), "replaced loaded receipt refused")
	var other_loaded := row.duplicate(true)
	other_loaded.binary_sha256 = "b".repeat(64)
	check(not Admission.loaded_identity_error(marker, sha, other_loaded).is_empty(), "other cached binary refused")
	for key: String in marker:
		var changed := marker.duplicate(true)
		changed[key] = [] if key == "allowed_selections" else "changed"
		check(not Admission.identity_error(changed, sha, row, sha, "Apple M1").is_empty(), "changed " + key)
	check(not Admission.identity_error(marker, sha, row, sha, "Apple M2").is_empty(), "other chip")
	check(Admission.selection_allowed(marker, selection, false), "exact selection")
	var json_marker: Variant = JSON.parse_string(JSON.stringify(marker))
	check(json_marker is Dictionary and Admission.identity_error(json_marker, sha, row, sha, "Apple M1").is_empty(),
		"JSON marker identity round-trip")
	check(json_marker is Dictionary and Admission.selection_allowed(json_marker, selection, false),
		"JSON marker selection round-trip")
	check(not Admission.selection_allowed(marker, selection, true), "other hull")
	for key: String in ["aircraft", "battery", "start", "weather", "profile", "start_sha256"]:
		var changed := selection.duplicate(true)
		changed[key] = "other"
		check(not Admission.selection_allowed(marker, changed, false), "other " + key)
	marker.allowed_selections[0].extra = true
	check(not Admission.selection_allowed(marker, selection, false), "extra selection fields")
	print("MAC_ADMISSION checks=%d failures=%d" % [checks, failed])
	quit(0 if failed == 0 else 1)


func _read_documents() -> void:
	var path := "user://mac-admission-document-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(not FileAccess.file_exists(path), "fresh document fixture")
	if FileAccess.file_exists(path): return
	check(Admission._read_document(path).is_empty(), "absent document refused quietly")
	for content: String in ["", "{", "{\"format\":", "null", "[]", "\"text\"", "123"]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		check(file != null, "fixture writable")
		if file == null: return
		file.store_string(content)
		file.close()
		check(Admission._read_document(path).is_empty(), "invalid or non-object document: " + content)
	var valid := "{\"format\":\"document-probe\"}"
	for length: int in [valid.length(), Admission.MAX_BYTES, Admission.MAX_BYTES + 1]:
		var content := valid + " ".repeat(length - valid.length())
		var file := FileAccess.open(path, FileAccess.WRITE)
		check(file != null, "bounded fixture writable")
		if file == null: return
		file.store_string(content)
		file.close()
		var document := Admission._read_document(path)
		if length > Admission.MAX_BYTES:
			check(document.is_empty(), "oversized document refused")
		else:
			check(document.get("data") == {format = "document-probe"}, "valid bounded object")
			check(document.get("sha256") == FileAccess.get_sha256(path), "digest binds parsed bytes")
	check(DirAccess.remove_absolute(path) == OK, "fixture removed")
	check(Admission._read_document(path).is_empty(), "removed document refused quietly")
	var prefix := "{\"format\":\"".to_utf8_buffer()
	var suffix := "\"}".to_utf8_buffer()
	for invalid: PackedByteArray in [PackedByteArray([0xff]), PackedByteArray([0xe2, 0x82]),
			PackedByteArray([0xc0, 0xaf]), PackedByteArray([0xed, 0xa0, 0x80]),
			PackedByteArray([0xf4, 0x90, 0x80, 0x80]), PackedByteArray([0x80])]:
		var bytes := prefix + invalid + suffix
		var file := FileAccess.open(path, FileAccess.WRITE)
		check(file != null, "malformed UTF-8 fixture writable")
		if file == null: return
		file.store_buffer(bytes)
		file.close()
		check(not Admission._valid_utf8(bytes), "malformed UTF-8 refused before decode")
		check(Admission._read_document(path).is_empty(), "malformed UTF-8 document refused quietly")
	var unicode := "{\"format\":\"é€🚁\"}".to_utf8_buffer()
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Unicode fixture writable")
	if file == null: return
	file.store_buffer(unicode)
	file.close()
	var document := Admission._read_document(path)
	check(Admission._valid_utf8(unicode), "valid two, three and four byte UTF-8")
	check(document.get("data") == {format = "é€🚁"}, "valid Unicode preserved")
	check(document.get("sha256") == FileAccess.get_sha256(path), "Unicode digest binds actual bytes")
	check(DirAccess.remove_absolute(path) == OK, "Unicode fixture removed")
