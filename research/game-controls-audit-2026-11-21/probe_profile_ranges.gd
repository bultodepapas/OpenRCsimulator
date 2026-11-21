# Diagnostic of schema-admitted, externally authored tiny endpoint spans.
# The production calibration wizard cannot normally generate these spans.
extends SceneTree

const Profile := preload("res://input/controller_profile.gd")
const Store := preload("res://input/controller_profile_store.gd")
const Reader := preload("res://input/rc_input.gd")
const Calibration := preload("res://input/rc_calibration.gd")

var checks := 0
var failures := 0


func check(label: String, condition: bool) -> void:
	checks += 1
	print("%s %s" % ["ok" if condition else "FAIL", label])
	if not condition: failures += 1


func _initialize() -> void:
	var profile := Profile.defaults("gamepad", "trigger_absolute")
	profile.throttle.min = 0.0
	profile.throttle.center = 0.0
	profile.throttle.max = 0.0000005
	check("tiny absolute profile passes public validation", Profile.validate(profile).ok)
	var full: float = Profile.channel_value(0.0000005, "throttle", profile)
	check("witness: declared full endpoint produces half throttle", is_equal_approx(full, 0.5))
	profile.throttle.invert = true
	var idle: float = Profile.channel_value(0.0000005, "throttle", profile)
	check("witness: inverted declared idle also produces half throttle", Profile.validate(profile).ok and is_equal_approx(idle, 0.5))
	var store := Store.new("user://tiny_ranges_%d.cfg" % OS.get_process_id(), "user://unused_legacy_%d.cfg" % OS.get_process_id())
	var saved: Dictionary = store.save_profile(profile)
	var loaded: Dictionary = store.load_all()
	check("schema-admitted tiny span survives actual V2 persistence", saved.ok and loaded.ok and loaded.profiles.size() == 1
		and is_equal_approx(Profile.channel_value(0.0000005, "throttle", loaded.profiles[0]), 0.5))
	var reader := Reader.new()
	reader.connect_device(7, {name = "Synthetic gamepad", known = true, kind = "gamepad"}, profile)
	reader.confirmed_gamepad_connection = func(_id: int) -> bool: return true
	var throttle_axis := int(profile.throttle.axis)
	reader.poll(func(_id: int, axis: int) -> float: return 0.0000005 if axis == throttle_axis else 0.0,
		1.0 / 240.0, func(_id: int, _button: int) -> bool: return false)
	var runtime: Dictionary = reader.sticks()
	check("witness: actual ready gamepad reader returns half throttle at declared idle", reader.armed and is_equal_approx(runtime.throttle, 0.5))
	var radio := Profile.defaults("radio", "radio_custom")
	radio.throttle.min = 0.0
	radio.throttle.center = 0.0
	radio.throttle.max = 0.0000005
	radio.throttle.invert = true
	var radio_reader := Reader.new()
	radio_reader.connect_device(8, {name = "Synthetic radio", known = false, kind = "radio"}, radio)
	radio_reader.on_motion(8, int(radio.throttle.axis), 0.0000005)
	radio_reader.poll(func(_id: int, axis: int) -> float: return 0.0000005 if axis == int(radio.throttle.axis) else 0.0, 1.0 / 240.0)
	check("witness: actual radio reader cannot arm at declared idle", Profile.validate(radio).ok and not radio_reader.armed)
	var normal := Profile.defaults("gamepad", "trigger_absolute")
	check("control: ordinary trigger endpoints remain zero and one", Profile.channel_value(0.0, "throttle", normal) == 0.0
		and Profile.channel_value(1.0, "throttle", normal) == 1.0)
	check("scope: wizard minimum sweep exceeds the injected span", Calibration.MIN_SWEEP > 0.0000005)
	print("AUDIT_OBSERVATIONS ", JSON.stringify({id = "GCA-05", validated = true, declared_span = 0.0000005,
		full_output = full, inverted_idle_output = idle, runtime_ready = reader.armed, runtime_throttle = runtime.throttle,
		radio_armed = radio_reader.armed, wizard_min_sweep = Calibration.MIN_SWEEP}))
	print("PROFILE_RANGES_AUDIT_COMPLETE %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
