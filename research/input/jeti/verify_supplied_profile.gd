extends SceneTree
## D6-JETI-01: read the original supplier CFG, modifying only a disposable copy.

const Service := preload("res://input/controller_service.gd")
const Profile := preload("res://input/controller_profile.gd")
const SOURCE := "../docs/research/radio-input/D6-JETI-00/sources/controller_profiles.cfg"

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	var source_path := ProjectSettings.globalize_path("res://").path_join(SOURCE).simplify_path()
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	_check("original supplier CFG is present", not source_bytes.is_empty())
	if source_bytes.is_empty():
		quit(1)
		return
	var path := "user://jeti_supplier_check_%d.cfg" % OS.get_process_id()
	var output := FileAccess.open(path, FileAccess.WRITE)
	_check("disposable CFG copy opens", output != null)
	if output == null:
		quit(1)
		return
	output.store_buffer(source_bytes)
	output.close()
	var service := Service.new()
	service.store = Service.Store.new(path, path + ".legacy")
	var info := {"id": 42, "name": "model s.r.o. JETI DC/DS Mass Storage",
		"raw_name": "model s.r.o. JETI DC/DS Mass Storage", "manufacturer": "JETI model s.r.o.",
		"guid": "0300567e830400007ca0000000000000", "vendor_id": 1155, "product_id": 41084,
		"known": true, "backend": "SDL3"}
	service.registry.update_devices([info])
	var loaded: Dictionary = service.profile_for_device(42)
	_check("original supplied CFG is admitted", not loaded.is_empty() and Profile.validate(loaded).ok)
	if not loaded.is_empty():
		_check("supplied joystick kind and preset take precedence", loaded.kind == "joystick" and loaded.preset == "radio_custom")
		_check("supplied UUID and axes are preserved", loaded.profile_id == "a8ff3dcd-0281-4e5a-b6bd-83f63153d8c9"
			and [loaded.roll.axis, loaded.pitch.axis, loaded.throttle.axis, loaded.yaw.axis] == [0, 1, 2, 3]
			and loaded.pitch.invert and loaded.throttle_mode == "radio_absolute")
		_check("reading does not rewrite the supplied copy", FileAccess.get_file_as_bytes(path) == source_bytes)
		var clean := Profile.clean_radio_actions(loaded)
		_check("explicit cleanup preserves kind, UUID and calibration", not clean.is_empty() and clean.kind == loaded.kind
			and clean.profile_id == loaded.profile_id and clean.roll == loaded.roll and clean.pitch == loaded.pitch
			and clean.throttle == loaded.throttle and clean.yaw == loaded.yaw and clean.association == loaded.association)
		var saved: Dictionary = service.store.save_profile(clean)
		var reread: Dictionary = service.store.load_all()
		_check("cleaned supplier copy round-trips through V2 storage", saved.ok and reread.ok
			and reread.profiles.size() == 1 and reread.profiles[0] == clean)
	_check("original supplier CFG bytes remain unchanged", FileAccess.get_file_as_bytes(source_path) == source_bytes)
	print("Supplier CFG SHA-256: ", FileAccess.get_sha256(source_path))
	service.free()
	for suffix in ["", ".tmp", ".rollback", ".legacy"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("JETI supplied profile: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)
