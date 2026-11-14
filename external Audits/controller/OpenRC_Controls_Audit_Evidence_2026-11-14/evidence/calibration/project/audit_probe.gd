extends SceneTree

const Calibration := preload("res://input/rc_calibration.gd")
const RcInput := preload("res://input/rc_input.gd")
const Profile := preload("res://input/controller_profile.gd")
const Menu := preload("res://input/radio_menu.gd")
var checks := 0
var failures := 0

func check(label: String, condition: bool, detail: Variant = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL ", label, " ", detail)

func _initialize() -> void:
	_run()
	print("Calibration audit: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _run() -> void:
	var original := Profile.defaults("radio", "radio_custom")
	original.throttle.center = -1.0 # the wizard stores center = low endpoint
	original.actions.accept = {"type": "button", "button": 10}
	original.actions.back = {"type": "button", "button": 11}
	original.actions.pause = {"type": "button", "button": 12}
	original.association = {"guid": "fixture", "vendor_id": 1209, "product_id": 500, "serial_number": "fixture"}
	var verified := Menu.verified_profile(original)
	check("menu fixture verified", not verified.is_empty() and Profile.validate(verified).ok and Menu.is_verified(verified))
	var measured: Dictionary = RcInput.DEFAULT_PROFILE.duplicate(true)
	measured.throttle.center = -1.0
	var unchanged := Profile.merge_radio_calibration(verified, measured)
	check("identical recalibration retains menu proof", not unchanged.is_empty() and unchanged.has("ui_navigation") and Menu.is_verified(unchanged))
	var changed: Dictionary = measured.duplicate(true)
	changed.roll.max = 0.9
	var changed_result := Profile.merge_radio_calibration(verified, changed)
	check("changed range invalidates menu proof control", not changed_result.is_empty() and not changed_result.has("ui_navigation") and not Menu.is_verified(changed_result))
	print("IDENTICAL_RECALIBRATION menu_verified=", Menu.is_verified(unchanged), " ui_navigation_present=", unchanged.has("ui_navigation"))
	
	var old := Profile.defaults("radio", "radio_custom")
	old.actions.camera_cycle = {"type": "axis", "axis": 5, "sign": 1, "threshold": 0.65}
	check("axis action on unused axis valid", Profile.validate(old).ok, Profile.validate(old).errors)
	var reassigned: Dictionary = measured.duplicate(true)
	reassigned.roll.axis = 5
	check("measured new mapping valid alone", Calibration.valid(reassigned))
	var simulated := old.duplicate(true)
	simulated.roll.axis = 5
	var report := Profile.validate(simulated)
	var rejected := Profile.merge_radio_calibration(old, reassigned)
	check("axis action conflict makes merge fail", not report.ok and rejected.is_empty(), report.errors)
	print("ACTION_AXIS_CONFLICT merge_empty=", rejected.is_empty(), " reason=", report.errors)
	
	var wiz := Calibration.new()
	var resting := PackedFloat64Array([0.05, 0.0, -0.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	wiz.advance(resting)
	var a := resting.duplicate()
	a[2] = -0.87
	wiz.sample(a)
	a[2] = 0.8
	wiz.sample(a)
	a[2] = -0.8
	wiz.sample(a)
	wiz.advance(a)
	check("throttle sweep with one low outlier accepted", wiz.step == 2 and wiz.error.is_empty(), [wiz.step, wiz.error])
	for index in [0, 1, 3]:
		a[index] = 0.8
		wiz.sample(a)
		wiz.advance(a)
		a[index] = -0.8
		wiz.sample(a)
		a[index] = 0.0
		wiz.sample(a)
		wiz.advance(a)
	check("noisy rest and low endpoint complete wizard", wiz.done() and Calibration.valid(wiz.profile), [wiz.step, wiz.error, wiz.profile])
	var radio := RcInput.new()
	radio.connect_device(7, {"name": "synthetic fixture", "kind": "radio"}, wiz.profile)
	radio.on_motion(7, 2, -0.8)
	radio.poll(func(_device: int, axis: int) -> float: return a[axis], 1.0 / 60.0)
	var sticks := radio.sticks()
	check("real idle arms with nonzero throttle", radio.armed and sticks.throttle > 0.04 and sticks.throttle < 0.05, sticks)
	check("real centered roll is nonzero", sticks.roll < -0.05, sticks)
	print("NOISY_CALIBRATION throttle_range=", [wiz.profile.throttle.min, wiz.profile.throttle.max], " saved_roll_center=", wiz.profile.roll.center, " idle_throttle=", sticks.throttle, " center_roll=", sticks.roll, " armed=", radio.armed)

	var prior := Profile.defaults("radio", "radio_custom")
	prior.aux = {
		"gear": {"type": "axis", "axis": 5, "off": -1.0, "on": 1.0, "invert": false},
		"smoke": {"type": "axis", "axis": 6, "off": -1.0, "on": 1.0, "invert": false}
	}
	check("two distinct AUX sources valid before recalibration", Profile.validate(prior).ok, Profile.validate(prior).errors)
	var aux_wiz := Calibration.new(prior)
	var b := PackedFloat64Array([0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	aux_wiz.advance(b)
	b[2] = 1.0
	aux_wiz.sample(b)
	b[2] = -1.0
	aux_wiz.advance(b)
	for axis in [5, 6, 3]:
		b[axis] = 1.0
		aux_wiz.advance(b)
		b[axis] = -1.0
		aux_wiz.sample(b)
		b[axis] = 0.0
		aux_wiz.advance(b)
	var aux_merged := Profile.merge_radio_calibration(prior, aux_wiz.profile)
	check("both conflicting AUX controls are removed on merge", aux_wiz.done() and not aux_merged.is_empty() and not aux_merged.aux.has("gear") and not aux_merged.aux.has("smoke"), aux_merged)
	check("only smoke is named in returned warning", "smoke" in aux_wiz.aux_warning and not "gear" in aux_wiz.aux_warning, aux_wiz.aux_warning)
	print("MULTIPLE_AUX_COLLISION saved_aux=", aux_merged.aux, " warning=", aux_wiz.aux_warning)

	var absolute_roll := Profile.defaults("radio", "radio_custom")
	absolute_roll.roll.range_kind = "absolute"
	check("radio absolute roll is accepted as valid", Profile.validate(absolute_roll).ok, Profile.validate(absolute_roll).errors)
	var still_absolute := Profile.merge_radio_calibration(absolute_roll, measured)
	check("wizard merge preserves absolute range kind", not still_absolute.is_empty() and still_absolute.roll.range_kind == "absolute")
	var centered_output := Profile.channel_value(0.0, "roll", still_absolute)
	var left_output := Profile.channel_value(-1.0, "roll", still_absolute)
	check("center maps to positive half roll", is_equal_approx(centered_output, 0.5) and is_equal_approx(left_output, 0.0), [centered_output, left_output])
	print("ABSOLUTE_ROLL existing_valid=", Profile.validate(absolute_roll).ok, " post_calibration_kind=", still_absolute.roll.range_kind, " centered_roll=", centered_output, " left_roll=", left_output)
