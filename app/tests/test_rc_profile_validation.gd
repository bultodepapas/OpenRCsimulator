# D6b-R1: malformed persisted profiles must never become a partial control mapping.
extends SceneTree

const Calibration = preload("res://input/rc_calibration.gd")
const Radio = preload("res://input/rc_input.gd")
const PATH: String = "user://test_rc_profile_validation.cfg"
const KEY: String = "fake|1209:4f54|EdgeTX [test]"

var _count: int = 0
var _failures: int = 0


func _check(label: String, ok: bool) -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)


# Bypass the writer to model a hand-edited/stale file, including values the writer now refuses.
func _write(profile: Variant, identity: Variant = KEY) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(KEY.md5_text(), "device_key", identity)
	cfg.set_value(KEY.md5_text(), "profile", profile)
	_check("fixture saved", cfg.save(PATH) == OK)


func _reject(label: String, profile: Variant) -> void:
	_check(label + ": validator", not Calibration.valid(profile))
	_write(profile)
	_check(label + ": load rejects entire profile", Calibration.load_profile(PATH, KEY).is_empty())


func _initialize() -> void:
	var base: Dictionary = Radio.DEFAULT_PROFILE.duplicate(true)
	_check("default radio accepted", Calibration.valid(base))
	for value: Variant in [null, false, 2, "radio", [], {}]:
		_reject("wrong profile shape %s" % [value], value)
	for kind: Variant in [null, 1, "unknown", "gamepad"]:
		var p: Dictionary = base.duplicate(true)
		p.kind = kind
		_reject("unsupported kind %s" % [kind], p)
	var missing_kind: Dictionary = base.duplicate(true)
	missing_kind.erase("kind")
	_reject("missing kind", missing_kind)
	_reject("built-in gamepad is not a saved radio calibration", Radio.GAMEPAD_PROFILE)
	var gamepad: Radio = Radio.new()
	gamepad.connect_device(15, {name = "Known gamepad", known = true}, Calibration.load_profile(PATH, KEY))
	_check("rejected saved kind preserves built-in gamepad mapping", gamepad.profile == Radio.GAMEPAD_PROFILE and gamepad.profile_source == "gamepad")
	gamepad.poll(func(_device: int, _axis: int) -> float: return 0.0, 1.0 / 240.0)
	_check("built-in gamepad still starts at idle", gamepad.sticks().throttle == 0.0)

	for channel: String in ["throttle", "roll", "pitch", "yaw"]:
		var missing: Dictionary = base.duplicate(true)
		missing.erase(channel)
		_reject("missing " + channel, missing)
		for bad_channel: Variant in [null, [], 1]:
			var p: Dictionary = base.duplicate(true)
			p[channel] = bad_channel
			_reject("wrong channel shape " + channel, p)
		for field: String in ["axis", "invert", "min", "center", "max"]:
			var p: Dictionary = base.duplicate(true)
			p[channel].erase(field)
			_reject("missing " + channel + "." + field, p)
		for axis: Variant in [-1, 10, 999999999999, 0.5, 0.0, NAN, INF, true, "0"]:
			var p: Dictionary = base.duplicate(true)
			p[channel].axis = axis
			_reject("invalid axis " + channel + " %s" % [axis], p)
		for other: String in ["throttle", "roll", "pitch", "yaw"]:
			if other == channel:
				continue
			var p: Dictionary = base.duplicate(true)
			p[channel].axis = p[other].axis
			_reject("duplicate axes " + channel + "/" + other, p)
		for invert: Variant in [null, 0, 1, "false"]:
			var p: Dictionary = base.duplicate(true)
			p[channel].invert = invert
			_reject("non-boolean inversion " + channel, p)
		for field: String in ["min", "center", "max"]:
			for value: Variant in [NAN, INF, -INF, -1.01, 1.01, "0", true, null]:
				var p: Dictionary = base.duplicate(true)
				p[channel][field] = value
				_reject("invalid endpoint " + channel + "." + field + " %s" % [value], p)
		for limits: Array in [[0.0, 0.0, 0.0], [0.5, 0.0, -0.5], [-0.5, -0.6, 0.5], [-0.5, 0.6, 0.5]]:
			var p: Dictionary = base.duplicate(true)
			p[channel].min = limits[0]
			p[channel].center = limits[1]
			p[channel].max = limits[2]
			_reject("unordered endpoints " + channel + " %s" % [limits], p)
		for endpoint: float in [-1.0, 1.0]:
			var p: Dictionary = base.duplicate(true)
			p[channel].center = endpoint
			if channel == "throttle":
				_write(p)
				_check("radio throttle center may equal an endpoint", Calibration.load_profile(PATH, KEY) == p)
			else:
				_reject("centred stick must travel on both sides " + channel, p)

	# Short asymmetric travel, integer endpoints, axis 9 and reversed throttle remain supported.
	var good: Dictionary = base.duplicate(true)
	good.roll = {axis = 9, invert = true, min = -0.8, center = 0.05, max = 0.9}
	good.throttle = {axis = 8, invert = true, min = 0, center = 0, max = 1}
	_write(good)
	_check("valid calibration round trip", Calibration.load_profile(PATH, KEY) == good)
	for identity: Variant in ["", "other|1209:4f54|EdgeTX [test]", 42, null]:
		_write(good, identity)
		_check("device identity must match exactly", Calibration.load_profile(PATH, KEY).is_empty())
	_write(good)
	_check("empty lookup key rejected", Calibration.load_profile(PATH, "").is_empty())
	_check("different device has no profile", Calibration.load_profile(PATH, "other").is_empty())

	# Refusing a save must leave every device's existing calibration intact, byte for byte.
	_check("save second device", Calibration.save_profile(PATH, "other", base) == OK)
	var before: PackedByteArray = FileAccess.get_file_as_bytes(PATH)
	var broken: Dictionary = good.duplicate(true)
	broken.yaw.axis = broken.roll.axis
	_check("invalid save reports failure", Calibration.save_profile(PATH, KEY, broken) == ERR_INVALID_DATA)
	_check("empty device key reports failure", Calibration.save_profile(PATH, "", good) == ERR_INVALID_DATA)
	_check("rejected saves preserve file bytes", FileAccess.get_file_as_bytes(PATH) == before)
	_check("first device unchanged", Calibration.load_profile(PATH, KEY) == good)
	_check("second device unchanged", Calibration.load_profile(PATH, "other") == base)
	_check("valid overwrite succeeds", Calibration.save_profile(PATH, KEY, base) == OK)
	_check("valid overwrite preserves other device", Calibration.load_profile(PATH, "other") == base)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	_check("missing file returns no profile", Calibration.load_profile(PATH, KEY).is_empty())
	_check("invalid save cannot create a file", Calibration.save_profile(PATH, KEY, broken) == ERR_INVALID_DATA and not FileAccess.file_exists(PATH))
	print("D6b-R1: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)
