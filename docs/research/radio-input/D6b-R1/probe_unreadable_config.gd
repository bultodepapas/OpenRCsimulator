# D6b-R1: ConfigFile logs an expected engine parse error here; run separately from app/test.sh.
extends SceneTree

const Calibration = preload("res://input/rc_calibration.gd")
const Radio = preload("res://input/rc_input.gd")
const PATH: String = "user://test_d6br1_unreadable.cfg"


func _initialize() -> void:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string("[unfinished section\n")
	file.close()
	var before: PackedByteArray = FileAccess.get_file_as_bytes(PATH)
	var rejected: bool = Calibration.load_profile(PATH, "device").is_empty()
	var err: Error = Calibration.save_profile(PATH, "device", Radio.DEFAULT_PROFILE)
	var preserved: bool = FileAccess.get_file_as_bytes(PATH) == before
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("D6b-R1 unreadable config: load_rejected=%s error=%d bytes_preserved=%s" % [rejected, err, preserved])
	quit(0 if rejected and err == ERR_PARSE_ERROR and preserved else 1)
