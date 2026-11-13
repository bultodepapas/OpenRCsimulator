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
	check(not Admission.selection_allowed(marker, selection, true), "other hull")
	for key: String in ["aircraft", "battery", "start", "weather", "profile", "start_sha256"]:
		var changed := selection.duplicate(true)
		changed[key] = "other"
		check(not Admission.selection_allowed(marker, changed, false), "other " + key)
	marker.allowed_selections[0].extra = true
	check(not Admission.selection_allowed(marker, selection, false), "extra selection fields")
	print("MAC_ADMISSION checks=%d failures=%d" % [checks, failed])
	quit(0 if failed == 0 else 1)
