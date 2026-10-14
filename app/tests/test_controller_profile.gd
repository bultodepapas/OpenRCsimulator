extends SceneTree

const Profile := preload("res://input/controller_profile.gd")
const RcInput := preload("res://input/rc_input.gd")
const SmokeAux := preload("res://input/smoke_aux.gd")

var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	var mode2 := Profile.defaults()
	var mode1 := Profile.defaults("gamepad", "mode1")
	var trigger := Profile.defaults("gamepad", "trigger_absolute")
	var radio := Profile.defaults("radio", "custom")
	_check("default Mode 2 is complete V2", Profile.validate(mode2).ok)
	_check("Mode 2 axes", [mode2.roll.axis, mode2.pitch.axis, mode2.yaw.axis, mode2.throttle.axis] == [2, 3, 0, 1])
	_check("Mode 1 axes", [mode1.roll.axis, mode1.pitch.axis, mode1.yaw.axis, mode1.throttle.axis] == [2, 1, 0, 3])
	_check("trigger preset is absolute and gamepad kind", trigger.kind == "gamepad" and trigger.throttle_mode == "trigger_absolute" and trigger.throttle.range_kind == "absolute" and trigger.throttle.axis == 5)
	_check("radio custom uses absolute radio throttle", radio.kind == "radio" and radio.throttle_mode == "radio_absolute" and Profile.validate(radio).ok)
	_check("UUIDs are distinct", mode1.profile_id != mode2.profile_id)
	_check("unknown preset rejected", Profile.defaults("gamepad", "future") == {})

	var invalid := mode2.duplicate(true)
	invalid.schema_version = 3
	_check("unsupported schema rejected", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.profile_id = "not-a-uuid"
	_check("invalid UUID rejected", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.name = "   "
	_check("blank name rejected", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.pitch.axis = invalid.roll.axis
	_check("duplicate source axis rejected", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.yaw = null
	_check("missing required channel rejected", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.roll.deadzone = 1.0
	_check("deadzone at one rejected", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.pitch.expo = -0.01
	_check("negative expo rejected", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.throttle_rate = INF
	_check("non-finite rate rejected", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.throttle.center = invalid.throttle.min
	_check("rate throttle cannot place center at an endpoint", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.throttle.center = invalid.throttle.max
	_check("rate throttle needs travel on both sides", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.presentation.extension = NAN
	_check("nested non-finite extension rejected", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.roll.axis = 1.5
	_check("non-integer axis rejected", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.actions = []
	_check("wrong actions container rejected", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.actions = {"accept": {"type": "button", "button": 128}}
	_check("out-of-range semantic action button rejected", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.actions = {"pause": {"type": "axis", "axis": 0, "sign": 1, "threshold": NAN}}
	_check("non-finite action threshold rejected", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.actions = {"back": {"type": "button", "button": 7}, "pause": {"type": "button", "button": 7}}
	_check("conflicting recovery action bindings rejected", not Profile.validate(invalid).ok)
	var partial_actions: Dictionary = mode2.duplicate(true)
	partial_actions.actions = {"accept": {"type": "button", "button": 30}}
	_check("partial action overrides merge with validated defaults", Profile.validate(partial_actions).ok)
	partial_actions.actions = {"accept": {"type": "button", "button": 1}}
	_check("action overrides are checked against merged defaults", not Profile.validate(partial_actions).ok)
	invalid = mode2.duplicate(true)
	invalid.actions = {"mystery_action": {"type": "button", "button": 1}}
	_check("unknown semantic action rejected", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.throttle_mode = "radio_absolute"
	_check("gamepad cannot use radio throttle mode", not Profile.validate(invalid).ok)
	invalid = mode2.duplicate(true)
	invalid.aux = {"smoke": {"type": "axis", "axis": mode2.roll.axis, "invert": false, "off": -1.0, "on": 1.0}}
	_check("AUX cannot overlap a flight axis", not Profile.validate(invalid).ok)
	_check("valid distinct smoke AUX remains accepted", SmokeAux.valid_binding({"type": "axis", "axis": 9, "invert": false, "off": -1.0, "on": 1.0}, [0, 1, 2, 3]))

	var channel: Dictionary = mode2.roll
	var shaped := Profile.conditioned_axis(0.05, channel, "gamepad")
	_check("scalar inside deadzone is zero", shaped == 0.0)
	var dz: float = channel.deadzone
	var expo: float = channel.expo
	var scaled := (0.5 - dz) / (1.0 - dz)
	var expected := (1.0 - expo) * scaled + expo * scaled * scaled * scaled
	_check("positive conditioning follows deadzone then expo", absf(Profile.condition_axis(0.5, channel, "gamepad") - expected) < 1e-12)
	_check("negative endpoint remains full throw", Profile.condition_axis(-1.0, channel, "gamepad") == -1.0)
	_check("positive endpoint remains full throw", Profile.condition_axis(1.0, channel, "gamepad") == 1.0)
	_check("radio bypasses gamepad shaping", Profile.condition_axis(0.05, channel, "radio") == 0.05)
	var linear_channel := {"deadzone": 0.0, "expo": 0.0}
	_check("zero expo is linear", Profile.condition_axis(-0.4, linear_channel, "gamepad") == -0.4)
	var cubic_channel := {"deadzone": 0.0, "expo": 1.0}
	_check("full expo is cubic", absf(Profile.condition_axis(0.4, cubic_channel, "gamepad") - 0.064) < 1e-12)
	_check("non-finite conditioned input fails to neutral", Profile.condition_axis(NAN, channel, "gamepad") == 0.0)
	var absolute_channel: Dictionary = trigger.throttle
	_check("absolute trigger endpoints map directly", Profile.normalize_axis(0.0, absolute_channel) == 0.0 and Profile.normalize_axis(1.0, absolute_channel) == 1.0)
	absolute_channel.invert = true
	_check("absolute trigger inversion preserves endpoints", Profile.normalize_axis(0.0, absolute_channel) == 1.0 and Profile.normalize_axis(1.0, absolute_channel) == 0.0)

	var legacy: Dictionary = RcInput.DEFAULT_PROFILE.duplicate(true)
	legacy["throttle"]["axis"] = 2
	legacy["aux"] = {"smoke": {"type": "axis", "axis": 9, "invert": false, "off": -1.0, "on": 1.0}}
	var migrated := Profile.upgrade_legacy(legacy, {"legacy_device_key": "legacy-key"})
	_check("legacy radio profile upgrades", Profile.validate(migrated).ok and migrated.kind == "radio", str(migrated))
	_check("legacy mapping stays intact", [migrated.roll.axis, migrated.pitch.axis, migrated.throttle.axis, migrated.yaw.axis] == [0, 1, 2, 3])
	_check("legacy radio output matches prior scalar mapping", absf(Profile.normalize_axis(-0.4, migrated.pitch) - RcInput.normalize(-0.4, legacy.pitch)) < 1e-12)
	_check("legacy radio throttle mapping stays identical", Profile.normalize_axis(-1.0, migrated.throttle) == RcInput.normalize_throttle(-1.0, legacy.throttle) and Profile.normalize_axis(1.0, migrated.throttle) == RcInput.normalize_throttle(1.0, legacy.throttle))
	_check("legacy smoke AUX survives upgrade", migrated.get("aux", {}).get("smoke", {}).get("axis", -1) == 9)
	_check("migration does not mutate source", not legacy.has("schema_version") and not legacy.roll.has("range_kind"))
	var unknown_schema: Dictionary = mode2.duplicate(true)
	unknown_schema.schema_version = 1
	_check("unknown version is not mistaken for legacy", Profile.upgrade_legacy(unknown_schema).is_empty())
	var legacy_stringname: Dictionary = {
		kind = "radio",
		roll = {axis = 0, invert = false, min = -1.0, center = 0.0, max = 1.0},
		pitch = {axis = 1, invert = true, min = -1.0, center = 0.0, max = 1.0},
		throttle = {axis = 2, invert = false, min = -1.0, center = -1.0, max = 1.0},
		yaw = {axis = 3, invert = false, min = -1.0, center = 0.0, max = 1.0},
	}
	var normalized_legacy := Profile.upgrade_legacy(legacy_stringname)
	_check("old StringName dictionaries migrate to strict string-key V2", Profile.validate(normalized_legacy).ok and typeof(normalized_legacy.roll.get("axis")) == TYPE_INT)
	var invalid_current := mode2.duplicate(true)
	invalid_current[&"extra"] = true
	_check("schema V2 StringName key is rejected", not Profile.validate(invalid_current).ok)
	var runtime_v2 := Profile.defaults("radio", "radio_custom")
	runtime_v2.aux = {&"smoke": {&"type": "button", &"button": 7, &"mode": "level"}}
	var normalized_runtime_v2 := Profile.upgrade_legacy(runtime_v2)
	_check("V2 activation normalizes StringName binding keys", Profile.validate(normalized_runtime_v2).ok and normalized_runtime_v2.aux.smoke.button == 7, str(normalized_runtime_v2))

	print("Controller profile: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
