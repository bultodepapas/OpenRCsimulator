# Audit observation probe for pinned cfb5acd5; see the README and checked-run evidence.
# Default mode checks baseline observations without intentionally raising an error.
# Set OPENRC_AUDIT_EXPECT_SCRIPT_ERROR=1 in an isolated checked run to invoke apply() with the accepted empty entry;
# that variant is expected to log SCRIPT ERROR for a missing dictionary key, so the checked runner should fail.
extends SceneTree

const Hud := preload("res://vehicles/multirotor/multirotor_hud.gd")
const Osd := preload("res://vehicles/multirotor/osd_model.gd")
const RaceRecords := preload("res://vehicles/multirotor/race_records.gd")
const PilotInput := preload("res://input/multirotor_input.gd")
const Profile := preload("res://input/controller_profile.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const DT := 1.0 / 240.0

var checks := 0
var failures := 0
var keys := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0, "arm": false, "mode": false}


func check(label: String, condition: bool) -> void:
	checks += 1
	print("%s %s" % ["ok  " if condition else "FAIL", label])
	if not condition: failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("en")
	var token := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	# The parent directory deliberately does not exist; no existing player setting can be overwritten.
	var unsavable := "user://quad_osd_audit_missing_" + token + "/settings.cfg"
	check("missing-directory path refuses a nonempty OSD save", not Osd.save_config(unsavable, Osd.DEFAULTS))
	var hud := Hud.new()
	root.add_child(hud)
	hud.set_prefs_path(unsavable)
	hud.cycle_layout()
	check("failed OSD save still changes the current layout", hud.osd_config.layout == "full")
	check("layout success message does not mention the failed save", "OSD layout: Full" in hud.message.text)
	check("next load falls back to prior default", Osd.load_config(unsavable).layout == "freestyle")
	check("help still advertises keyboard/gamepad toggles", "Arm or disarm: E, gamepad LB" in hud.help.text \
		and "Flight mode Acro/Angle: M or gamepad RB" in hud.help.text)

	var input := PilotInput.new()
	input.read_axis = func(_id: int, _axis: int) -> float: return 0.0
	input.read_button = func(_id: int, _button: int) -> bool: return false
	input.read_keys = func() -> Dictionary: return keys.duplicate()
	input.radio.confirmed_gamepad_connection = func(_id: int) -> bool: return true
	var profile := Profile.defaults("gamepad", "mode2")
	profile.aux = {"arm": {"type": "button", "button": 20, "mode": "level"},
		"flight_mode": {"type": "button", "button": 21, "mode": "level"}}
	check("explicit Arm and Flight mode profile validates", Profile.validate(profile).ok)
	input.connect_device(1, {"name": "Synthetic gamepad", "known": true}, profile)
	var off: Dictionary = input.sample(DT, true)
	keys.arm = true
	keys.mode = true
	var pressed: Dictionary = input.sample(DT, true)
	check("ready source uses both explicit switches", off.ready and input.arm_from_switch() and input.mode_from_switch())
	check("advertised E and M do not override the bound switches", pressed.pilot[FC.IN_ARM] == 0.0 \
		and pressed.pilot[FC.IN_MODE] == off.pilot[FC.IN_MODE])
	root.remove_child(hud)
	hud.free()

	# A syntactically valid but incomplete course entry in the record book.
	var path := "user://quad_audit_empty_record_" + token + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	check("isolated record fixture opened", file != null)
	var loaded := {}
	if file != null:
		file.store_string(JSON.stringify({"format": RaceRecords.FORMAT, "courses": {"course-a": {}}}))
		file.close()
		loaded = RaceRecords.load_file(path)
		check("loader accepts an empty course entry and reports no dropped record", loaded.ok \
			and int(loaded.dropped) == 0 and loaded.records.has("course-a") \
			and (loaded.records["course-a"] as Dictionary).is_empty())
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("quad minor findings probe: %d checks, %d failed" % [checks, failures])
	if OS.get_environment("OPENRC_AUDIT_EXPECT_SCRIPT_ERROR") == "1" and not loaded.is_empty():
		print("EXPECT INVALID KEY: applying a terminal result to the accepted empty entry")
		RaceRecords.apply(loaded.records, {"identity": "course-a"},
			{"valid": false, "phase": "ABORTED", "reason": "cancelled", "laps": []})
	quit(1 if failures else 0)
