# Static-audit counterexamples for baseline ad21070798bfb9658785576a9c0b8bfc9a71fc7f.
# Injected values establish software behavior only, not incidence on any physical device.
extends SceneTree

const RcInput = preload("res://input/rc_input.gd")
const Profile = preload("res://input/controller_profile.gd")
const Calibration = preload("res://input/rc_calibration.gd")
const DEVICE := 15
const DT := 1.0 / 240.0

var checks := 0
var failures := 0
var results: Array[Dictionary] = []


func check(name: String, passed: bool, details: Dictionary = {}) -> void:
	checks += 1
	if not passed:
		failures += 1
	results.append({"name": name, "passed": passed, "details": details})


func feed(cal: RefCounted, axes: PackedFloat64Array, count: int) -> void:
	for _index in count:
		cal.sample(axes)


# The only difference between the paired sequences is one hardware report at
# +1.0, repeated by three polls, during the opposite-end roll sweep. Each call to
# sample represents a poll, not an assertion that a new hardware report arrived.
func calibrate_roll(inject_repeated_report: bool) -> Dictionary:
	var cal = Calibration.new()
	var axes := PackedFloat64Array()
	axes.resize(RcInput.AXES)
	axes[2] = -1.0
	feed(cal, axes, 5)
	cal.advance(axes)
	if cal.step != 1:
		return {"ok": false, "where": "rest", "error": cal.error, "step": cal.step}

	axes[2] = 1.0
	feed(cal, axes, 3)
	axes[2] = -1.0
	feed(cal, axes, 5)
	cal.advance(axes)
	if cal.step != 2:
		return {"ok": false, "where": "throttle", "error": cal.error, "step": cal.step}

	axes[0] = 0.8
	feed(cal, axes, 5)
	cal.advance(axes)
	if cal.held_axis() != 0:
		return {"ok": false, "where": "held roll", "error": cal.error, "step": cal.step}
	if inject_repeated_report:
		axes[0] = 1.0
		feed(cal, axes, 3)
	axes[0] = -0.8
	feed(cal, axes, 3)
	axes[0] = 0.0
	feed(cal, axes, 5)
	cal.advance(axes)
	if cal.step != 3 or not cal.profile.has("roll"):
		return {"ok": false, "where": "roll", "error": cal.error, "step": cal.step}
	var roll: Dictionary = cal.profile.roll
	return {"ok": true, "minimum": roll.min, "center": roll.center, "maximum": roll.max,
		"command_at_true_positive_endpoint": Profile.normalize_signed_axis(0.8, roll)}


func _initialize() -> void:
	var profile: Dictionary = Profile.defaults("radio", "radio_custom")
	profile.roll.center = 0.2
	var valid: Dictionary = Profile.validate(profile)
	check("offset_center_profile_is_valid", bool(valid.ok), {"errors": valid.errors})
	var radio = RcInput.new()
	radio.connect_device(DEVICE, {"name": "Injected raw radio", "kind": "radio"}, profile)
	radio.on_motion(DEVICE, 2, -1.0)
	radio.poll(func(_id: int, axis: int) -> float: return -1.0 if axis == 2 else 0.0, DT)
	var sticks: Dictionary = radio.sticks()
	check("low_throttle_event_arms_without_roll_event", radio.armed and not radio.has_axis_sample(0),
		{"armed": radio.armed, "roll_event_seen": radio.has_axis_sample(0)})
	var expected := -1.0 / 6.0
	check("unseen_zero_poll_normalizes_to_nonzero_roll", absf(float(sticks.roll) - expected) < 1.0e-12,
		{"returned_roll": sticks.roll, "expected_roll": expected, "assumed_physical_center": 0.2,
		"polled_raw": 0.0, "min": -1.0, "max": 1.0})

	var clean := calibrate_roll(false)
	var repeated := calibrate_roll(true)
	check("clean_sweep_accepts_true_endpoint", bool(clean.get("ok", false)) \
		and absf(float(clean.get("maximum", 0.0)) - 0.8) < 1.0e-12 \
		and absf(float(clean.get("command_at_true_positive_endpoint", 0.0)) - 1.0) < 1.0e-12, clean)
	check("repeated_outlier_sets_accepted_endpoint", bool(repeated.get("ok", false)) \
		and absf(float(repeated.get("maximum", 0.0)) - 1.0) < 1.0e-12 \
		and absf(float(repeated.get("command_at_true_positive_endpoint", 0.0)) - 0.8) < 1.0e-12, repeated)

	print("CONTROLS_AUDIT_PROBE_JSON ", JSON.stringify({"baseline": "ad21070798bfb9658785576a9c0b8bfc9a71fc7f",
		"scope": "injected reader and repeated poll scenarios; no physical device or rendered evidence",
		"checks": checks, "failures": failures, "complete": true, "results": results}))
	quit(0 if failures == 0 else 1)
