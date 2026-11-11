# DR-08 / DR-15: the versioned stick-to-rate mapping (app/physics/multirotor/rates.gd) against the computed reference
# vectors of FPV/03 §1 (Betaflight 4.5.2, commit 024f8e13d4e642eb6a380308685b9ea3aa3ef1a2), the frozen oracle values
# of research/drone-racing/DR-03, and independent re-derivations written here with plain arithmetic. Also covers
# strict validation, profile identity and the bounded CLI importer (CTRL-07…09). Curve math only; no firmware
# flight-feel equivalence and no physical validation is claimed.
extends SceneTree

const R := preload("res://physics/multirotor/rates.gd")

const DOC_TOL := 1e-6  # against the document's 9-decimal (or 6-decimal BETAFLIGHT) vectors
const REF_TOL := 1e-9  # against values recomputed independently in this test

## Two distinct rate profiles for importer fixtures: [rc_rate, srate, expo, rate_limit] for roll, pitch, yaw.
const P0 := [[20, 67, 58, 1998], [21, 68, 57, 1990], [22, 69, 56, 1980]]
const P1 := [[100, 70, 0, 1998], [110, 71, 10, 1000], [120, 72, 20, 900]]

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_actual_reference_vectors()
	_actual_properties()
	_axis_independence()
	_betaflight_family()
	_validation_refusals()
	_invalid_sticks()
	_identity()
	_importer()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


# --- fixtures and independent references -------------------------------------------------------------------------

func _profile(family: String, values: Array) -> Dictionary:
	var axes := {}
	for i in 3:
		axes[R.AXIS_NAMES[i]] = {rc_rate = values[i][0], srate = values[i][1], expo = values[i][2], rate_limit = values[i][3]}
	return {format = R.FORMAT, family = family,
		source = {firmware = "betaflight", version = "4.5.2", commit = "024f8e13d4e642eb6a380308685b9ea3aa3ef1a2", profile_index = 0},
		axes = axes}


func _uniform(family: String, axis_values: Array) -> Dictionary:
	return _profile(family, [axis_values, axis_values, axis_values])


func _prepared(profile: Dictionary) -> Dictionary:
	var result: Dictionary = R.prepare(profile)
	if not result.ok:
		_check("fixture prepares", false, str(result.errors))
	return result.prepared


## ACTUAL re-derived with |x|*x^5 = sign(x)*|x|^6 and |x|*x = sign(x)*x^2.
func _actual_ref(x: float, c: float, m: float, e: float, cap: float) -> float:
	var a: float = maxf(0.0, m - c)
	var s: float = signf(x)
	var b: float = absf(x)
	var v: float = c * x + a * (e * s * pow(b, 6.0) + (1.0 - e) * s * b * b)
	return minf(cap, maxf(-cap, v))


## BETAFLIGHT re-derived: r_eff = 15.54*r - 29.08 above 2; x*(1 - e + e*|x|^3); the denominator bound applied by hand.
func _bf_ref(x: float, rc_rate: int, srate: int, expo: int, cap: float) -> float:
	var r: float = float(rc_rate) / 100.0
	if r > 2.0:
		r = 15.54 * r - 29.08
	var e: float = float(expo) / 100.0
	var b: float = absf(x)
	var shaped: float = x * (1.0 - e + e * pow(b, 3.0))
	var d: float = 1.0 - b * float(srate) / 100.0
	if d < 0.01:
		d = 0.01
	if d > 1.0:
		d = 1.0
	return minf(cap, maxf(-cap, 200.0 * r * shaped / d))


func _close_all(prepared: Dictionary, axis: int, sticks: Array, expected: Array, tol: float) -> Array:
	var worst := 0.0
	var got := []
	for i in sticks.size():
		var v: float = R.setpoint_dps(prepared, axis, sticks[i])
		got.append(v)
		var err: float = absf(v - float(expected[i])) if is_finite(v) else INF
		worst = maxf(worst, err)
	return [worst <= tol, "max err %.15f, got %s" % [worst, str(got)] if worst > tol else "max err %.12f" % worst]


# --- ACTUAL ------------------------------------------------------------------------------------------------------

func _actual_reference_vectors() -> void:
	var p: Dictionary = _prepared(_uniform("ACTUAL", [20, 67, 58, 1998]))
	var sticks := [-1.0, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75, 1.0]
	var doc := [-670.0, -309.554443359, -153.609375, -62.404052734, 0.0, 62.404052734, 153.609375, 309.554443359, 670.0]
	var oracle := [-670.0, -309.554443359375, -153.609375, -62.404052734375, 0.0, 62.404052734375, 153.609375, 309.554443359375, 670.0]
	for axis in 3:
		var r: Array = _close_all(p, axis, sticks, doc, DOC_TOL)
		_check("ACTUAL C=200 M=670 e=0.58: FPV/03 §1 nine-point vector, axis %d" % axis, r[0], r[1])
	var o: Array = _close_all(p, 0, sticks, oracle, REF_TOL)
	_check("ACTUAL nine-point vector matches the DR-03 oracle constants", o[0], o[1])
	var expo0: Dictionary = _prepared(_uniform("ACTUAL", [20, 67, 0, 1998]))
	var v0: float = R.setpoint_dps(expo0, 0, 0.5)
	_check("ACTUAL expo=0 is not linear: x=0.5 gives 217.5, not 335", absf(v0 - 217.5) <= DOC_TOL, "%.9f" % v0)
	var low_m: Dictionary = _prepared(_uniform("ACTUAL", [20, 10, 58, 1998]))
	var vm: float = R.setpoint_dps(low_m, 0, 0.5)
	_check("ACTUAL M<C (C=200, M=100): x=0.5 gives 100", absf(vm - 100.0) <= DOC_TOL, "%.9f" % vm)
	var rm: Array = _close_all(low_m, 0, [-1.0, -0.5, 0.5, 1.0], [-200.0, -100.0, 100.0, 200.0], REF_TOL)
	_check("ACTUAL M<C floors max-minus-centre at zero; uncapped endpoint is C", rm[0], rm[1])
	var capped: Dictionary = _prepared(_uniform("ACTUAL", [20, 67, 58, 500]))
	var rc: Array = _close_all(capped, 0, [-1.0, 1.0, 0.75], [-500.0, 500.0, 309.554443359375], REF_TOL)
	_check("ACTUAL cap below M: L=500 clips the 670 endpoint to 500 and leaves 0.75 unclipped", rc[0], rc[1])
	var e1: Dictionary = _prepared(_uniform("ACTUAL", [20, 67, 100, 1998]))
	var v1: float = R.setpoint_dps(e1, 0, 0.5)
	_check("ACTUAL expo=1 at x=0.5 gives 107.34375 (oracle)", absf(v1 - 107.34375) <= REF_TOL, "%.12f" % v1)
	var rad: PackedFloat64Array = R.setpoints_rad_s(p, PackedFloat64Array([0.5, 0.5, 0.5]))
	_check("deg/s to rad/s at the boundary: x=0.5 gives 2.6809893556806648 rad/s (oracle)",
		rad.size() == 3 and absf(rad[0] - 2.6809893556806648) < 1e-12 and absf(rad[2] - 2.6809893556806648) < 1e-12, str(rad))


func _actual_properties() -> void:
	var cases := [[20, 67, 58, 1998], [20, 67, 0, 1998], [20, 67, 100, 1998], [20, 10, 58, 1998], [20, 67, 58, 500],
		[0, 200, 30, 1998], [200, 200, 100, 1998], [5, 120, 75, 650]]
	for values in cases:
		var q: Dictionary = _prepared(_uniform("ACTUAL", values))
		var odd_err := 0.0
		var ref_err := 0.0
		for i in range(-200, 201):
			var x: float = float(i) / 200.0
			var plus: float = R.setpoint_dps(q, 0, x)
			odd_err = maxf(odd_err, absf(plus + R.setpoint_dps(q, 0, -x)))
			ref_err = maxf(ref_err, absf(plus - _actual_ref(x, 10.0 * values[0], 10.0 * values[1], values[2] / 100.0, float(values[3]))))
		_check("ACTUAL %s: exact odd symmetry over 401 sticks" % str(values), odd_err == 0.0, "%.15f" % odd_err)
		_check("ACTUAL %s: matches the independent re-derivation over 401 sticks" % str(values), ref_err <= REF_TOL, "%.15f" % ref_err)
	var p: Dictionary = _prepared(_uniform("ACTUAL", [20, 67, 58, 1998]))
	var h := 1e-7
	var slope: float = (R.setpoint_dps(p, 0, h) - R.setpoint_dps(p, 0, -h)) / (2.0 * h)
	_check("ACTUAL centre slope: numerical derivative at 0 equals C = 200 deg/s", absf(slope - 200.0) < 1e-4, "%.9f" % slope)
	var eq: Dictionary = _prepared(_uniform("ACTUAL", [20, 20, 58, 1998]))
	var lin_err := 0.0
	for i in range(-100, 101):
		var x: float = float(i) / 100.0
		lin_err = maxf(lin_err, absf(R.setpoint_dps(eq, 0, x) - 200.0 * x))
	_check("ACTUAL M=C is linear 200*x for any expo", lin_err <= REF_TOL, "%.15f" % lin_err)


func _axis_independence() -> void:
	var values := [[20, 67, 58, 1998], [10, 50, 0, 1998], [30, 30, 100, 250]]
	var p: Dictionary = _prepared(_profile("ACTUAL", values))
	var worst := 0.0
	for i in range(-20, 21):
		var x: float = float(i) / 20.0
		var out: PackedFloat64Array = R.setpoints_rad_s(p, PackedFloat64Array([x, x, x]))
		for axis in 3:
			var v: Array = values[axis]
			var ref: float = _actual_ref(x, 10.0 * v[0], 10.0 * v[1], v[2] / 100.0, float(v[3]))
			worst = maxf(worst, absf(R.setpoint_dps(p, axis, x) - ref))
			worst = maxf(worst, absf(out[axis] - ref * PI / 180.0) * 180.0 / PI)
	_check("three different axis settings: each axis follows only its own fields (deg/s and rad/s)", worst <= REF_TOL, "%.15f" % worst)
	var mixed: PackedFloat64Array = R.setpoints_rad_s(p, PackedFloat64Array([1.0, 0.0, -1.0]))
	_check("per-axis caps and endpoints: roll 670, pitch 0, yaw capped at -250 deg/s",
		absf(mixed[0] * 180.0 / PI - 670.0) < REF_TOL and mixed[1] == 0.0 and absf(mixed[2] * 180.0 / PI + 250.0) < REF_TOL, str(mixed))


# --- BETAFLIGHT ----------------------------------------------------------------------------------------------------

func _betaflight_family() -> void:
	var p: Dictionary = _prepared(_uniform("BETAFLIGHT", [100, 70, 0, 1998]))
	var r: Array = _close_all(p, 0, [0.25, 0.5, 0.75, 1.0], [60.606061, 153.846154, 315.789474, 666.666667], DOC_TOL)
	_check("BETAFLIGHT r=1 s=0.7 e=0: FPV/03 §1 vector 60.606061/153.846154/315.789474/666.666667", r[0], r[1])
	var signed := [-1.0, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75, 1.0]
	var expected := []
	for x in signed:
		expected.append(200.0 * x / (1.0 - 0.7 * absf(x)))
	var rs: Array = _close_all(p, 0, signed, expected, REF_TOL)
	_check("BETAFLIGHT full signed vector equals 200*x/(1 - 0.7|x|)", rs[0], rs[1])
	var r2: Dictionary = _prepared(_uniform("BETAFLIGHT", [200, 0, 0, 1998]))
	var v2: float = R.setpoint_dps(r2, 0, 0.5)
	_check("BETAFLIGHT r=2 has no incremental term: x=0.5 gives 200", absf(v2 - 200.0) <= REF_TOL, "%.12f" % v2)
	var above: Dictionary = _prepared(_uniform("BETAFLIGHT", [250, 0, 0, 1998]))
	var va: float = R.setpoint_dps(above, 0, 0.1)
	var ra: float = 200.0 * (2.5 + 14.54 * 0.5) * 0.1
	_check("BETAFLIGHT r=2.5 > 2: r_eff = 9.77, x=0.1 gives 195.4", absf(va - ra) <= REF_TOL and absf(va - 195.4) <= REF_TOL, "%.12f" % va)
	var big: Dictionary = _prepared(_uniform("BETAFLIGHT", [100, 120, 0, 100000]))
	var vb: float = R.setpoint_dps(big, 0, 0.9)
	var denominator: float = 1.0 - 0.9 * 1.2
	var bound: float = 0.01 if denominator < 0.01 else denominator
	_check("BETAFLIGHT denominator bound: 1 - 0.9*1.2 = -0.08 is held at 0.01, giving 18000 uncapped",
		absf(vb - 200.0 * 0.9 / bound) <= REF_TOL and absf(vb - 18000.0) <= 1e-7, "%.9f" % vb)
	var full: Dictionary = _prepared(_uniform("BETAFLIGHT", [100, 100, 0, 100000]))
	var vf: float = R.setpoint_dps(full, 0, 1.0)
	_check("BETAFLIGHT s=1 at full stick: zero denominator held at 0.01 (20000 deg/s, finite)", absf(vf - 20000.0) <= 1e-7, "%.9f" % vf)
	var shaped: Dictionary = _prepared(_uniform("BETAFLIGHT", [100, 50, 50, 1998]))
	var vs: float = R.setpoint_dps(shaped, 0, 0.8)
	_check("BETAFLIGHT denominator uses the unshaped |x|: e=0.5 s=0.5 x=0.8 gives 201.6 (not 173.39)",
		absf(vs - 201.6) <= REF_TOL, "%.12f" % vs)
	var capped: Dictionary = _prepared(_uniform("BETAFLIGHT", [100, 70, 0, 500]))
	var rcap: Array = _close_all(capped, 0, [-1.0, 1.0, 0.5], [-500.0, 500.0, 200.0 * 0.5 / 0.65], REF_TOL)
	_check("BETAFLIGHT cap: 666.67 endpoint clipped to 500, 0.5 unclipped", rcap[0], rcap[1])
	var cases := [[100, 70, 0, 1998], [250, 0, 0, 1998], [100, 50, 50, 1998], [180, 85, 30, 1500], [100, 120, 0, 100000], [300, 99, 100, 1998]]
	for values in cases:
		var q: Dictionary = _prepared(_uniform("BETAFLIGHT", values))
		var odd_err := 0.0
		var ref_err := 0.0
		for i in range(-200, 201):
			var x: float = float(i) / 200.0
			var plus: float = R.setpoint_dps(q, 1, x)
			odd_err = maxf(odd_err, absf(plus + R.setpoint_dps(q, 1, -x)))
			var ref: float = _bf_ref(x, values[0], values[1], values[2], float(values[3]))
			ref_err = maxf(ref_err, absf(plus - ref) / maxf(1.0, absf(ref)))
		_check("BETAFLIGHT %s: odd symmetry and independent re-derivation over 401 sticks" % str(values),
			odd_err == 0.0 and ref_err <= REF_TOL, "odd %.15f rel %.15f" % [odd_err, ref_err])


# --- validation ---------------------------------------------------------------------------------------------------

func _refuses(label: String, profile: Variant, needle: String) -> void:
	var v: Dictionary = R.validate(profile)
	var found := false
	for message in v.errors:
		if message.contains(needle):
			found = true
	_check("validate refuses %s" % label, not v.ok and found, str(v.errors))


func _validation_refusals() -> void:
	var d: Dictionary = R.default_profile()
	_check("default profile validates", R.validate(d).ok, str(R.validate(d).errors))
	var d_axes_ok := true
	for axis_name in R.AXIS_NAMES:
		var a: Dictionary = d.axes[axis_name]
		d_axes_ok = d_axes_ok and a.rc_rate == 20 and a.srate == 67 and a.expo == 58 and a.rate_limit == 1998
	_check("default profile is ACTUAL 20/67/58/1998 on every axis, not taken from a firmware profile",
		d_axes_ok and d.family == "ACTUAL" and d.source.profile_index == R.PROFILE_INDEX_NONE)
	_check("default profile prepares as an OpenRC product default", R.prepare(d).prepared.origin == "openrc_product_default")
	_check("default profile is a fresh copy each call", not is_same(R.default_profile().axes, R.default_profile().axes))

	var p := R.default_profile()
	p["extra"] = 1
	_refuses("an unknown top-level key", p, "unknown key 'extra'")
	p = R.default_profile()
	p.axes.roll["rate"] = 1
	_refuses("an unknown axis key", p, "axes.roll: unknown key 'rate'")
	p = R.default_profile()
	p.erase("axes")
	_refuses("a missing key", p, "missing key 'axes'")
	p = R.default_profile()
	p.axes.pitch.rc_rate = 20.0
	_refuses("a float where an int is required (even 20.0)", p, "axes.pitch.rc_rate: expected an int")
	p = R.default_profile()
	p.axes.yaw.expo = NAN
	_refuses("a NaN field", p, "axes.yaw.expo: expected an int")
	p = R.default_profile()
	p.axes.roll.rc_rate = 201
	_refuses("ACTUAL rc_rate 201 (> 200)", p, "axes.roll.rc_rate: 201 outside")
	_check("refusal never clamps the caller's data", p.axes.roll.rc_rate == 201 and not R.prepare(p).ok and R.prepare(p).prepared.is_empty())
	p = R.default_profile()
	p.axes.roll.srate = 201
	_refuses("ACTUAL srate 201 (> 200)", p, "axes.roll.srate: 201 outside")
	p = R.default_profile()
	p.axes.roll.expo = 101
	_refuses("ACTUAL expo 101 (> 100)", p, "axes.roll.expo: 101 outside")
	p = R.default_profile()
	p.axes.roll.srate = -1
	_refuses("a negative raw field", p, "axes.roll.srate: -1 outside")
	p = R.default_profile()
	p.axes.yaw.rate_limit = 0
	_refuses("rate_limit 0", p, "axes.yaw.rate_limit: 0 outside")
	p = R.default_profile()
	p.family = "KISS"
	_refuses("an unknown family", p, "unknown rate family 'KISS'")
	p = R.default_profile()
	p.source.version = "4.5.1"
	_refuses("an unknown firmware version", p, "unsupported firmware version '4.5.1'")
	p = R.default_profile()
	p.source.commit = "0000000000000000000000000000000000000000"
	_refuses("a different source commit", p, "pinned commit")
	p = R.default_profile()
	p.format = "openrc-rates v2"
	_refuses("an unknown format", p, "format: expected")
	p = R.default_profile()
	p.axes.roll = [20, 67, 58, 1998]
	_refuses("an axis that is not a Dictionary", p, "axes.roll: expected a Dictionary")
	_refuses("a non-Dictionary profile", 42, "expected a Dictionary")
	var bf := _uniform("BETAFLIGHT", [250, 70, 0, 1998])
	_check("BETAFLIGHT admits rc_rate 250 (r > 2) while ACTUAL refuses it",
		R.validate(bf).ok and not R.validate(_uniform("ACTUAL", [250, 70, 0, 1998])).ok)
	_check("prepared dictionary is read-only", R.prepare(d).prepared.is_read_only())


func _invalid_sticks() -> void:
	var p: Dictionary = _prepared(R.default_profile())
	var bad := [1.0000001, -1.0000001, 2.0, INF, -INF, NAN]
	var all_nan := true
	for x in bad:
		all_nan = all_nan and is_nan(R.setpoint_dps(p, 0, x))
	_check("x outside [-1, 1] or non-finite returns NAN, never a clamped value", all_nan)
	_check("x = ±1 exactly is valid", absf(R.setpoint_dps(p, 0, 1.0) - 670.0) < REF_TOL and absf(R.setpoint_dps(p, 0, -1.0) + 670.0) < REF_TOL)
	_check("unknown axis returns NAN", is_nan(R.setpoint_dps(p, 3, 0.5)) and is_nan(R.setpoint_dps(p, -1, 0.5)))
	_check("an unprepared dictionary returns NAN", is_nan(R.setpoint_dps({}, 0, 0.5)))
	var out: PackedFloat64Array = R.setpoints_rad_s(p, PackedFloat64Array([0.5, NAN, 0.5]))
	_check("setpoints_rad_s marks only the invalid stick NAN", out.size() == 3 and not is_nan(out[0]) and is_nan(out[1]) and not is_nan(out[2]), str(out))
	var short: PackedFloat64Array = R.setpoints_rad_s(p, PackedFloat64Array([0.5, 0.5]))
	_check("setpoints_rad_s with two sticks returns three NANs", short.size() == 3 and is_nan(short[0]) and is_nan(short[1]) and is_nan(short[2]), str(short))


func _identity() -> void:
	var a: String = R.prepare(R.default_profile()).prepared.identity
	var b: String = R.prepare(R.default_profile()).prepared.identity
	_check("identity is a 64-hex SHA-256", a.length() == 64 and a.is_valid_hex_number(), a)
	_check("same profile, same identity", a == b)
	_check("deep copy, same identity", R.prepare(R.default_profile().duplicate(true)).prepared.identity == a)
	var p := R.default_profile()
	p.axes.yaw.rate_limit = 1997
	_check("changing one field changes the identity", R.prepare(p).prepared.identity != a)
	p = R.default_profile()
	p.source.profile_index = 0
	_check("changing the source profile index changes the identity", R.prepare(p).prepared.identity != a)
	p = R.default_profile()
	p.family = "BETAFLIGHT"
	_check("changing the family changes the identity", R.prepare(p).prepared.identity != a)
	var reordered := {axes = R.default_profile().axes, source = R.default_profile().source, family = "ACTUAL", format = R.FORMAT}
	_check("key insertion order does not change the identity", R.prepare(reordered).prepared.identity == a)


# --- importer -----------------------------------------------------------------------------------------------------

func _block(index: int, family: String, values: Array, skip := []) -> String:
	var text := "\nrateprofile %d\n\n# rateprofile %d\nset rateprofile_name = P%d\n" % [index, index, index]
	if not family.is_empty():
		text += "set rates_type = %s\n" % family
	for i in 3:
		for j in 4:
			var key: String = "%s_%s" % [R.AXIS_NAMES[i], R.FIELD_NAMES[j]]
			if not skip.has(key):
				text += "set %s = %d\n" % [key, values[i][j]]
	text += "set thr_mid = 50\nset thr_expo = 0\n"
	return text


func _dump(blocks: String, restore := -1, version := "4.5.2") -> String:
	var text := "# diff all\n\n# version\n# Betaflight / STM32F7X2 (S7X2) %s Jan  1 2025 / 00:00:00 (024f8e13d) MSP API: 1.46\n" % version
	text += "\n# start the command batch\nbatch start\n\n# reset configuration to default settings\ndefaults nosave\n\nboard_name MATEKF722\n"
	text += "feature -AIRMODE\n\n# master\nset gyro_lpf1_static_hz = 250\n\nprofile 0\n\n# profile 0\nset p_roll = 45\n"
	text += blocks
	if restore >= 0:
		text += "\n# restore original profile selection\nprofile 0\n\n# restore original rateprofile selection\nrateprofile %d\n" % restore
	text += "\n# save configuration\nsave\n"
	return text


func _has(lines: PackedStringArray, needle: String) -> bool:
	for line in lines:
		if line.contains(needle):
			return true
	return false


func _axes_equal(profile: Dictionary, values: Array) -> bool:
	if profile.is_empty():
		return false
	for i in 3:
		var a: Dictionary = profile.axes[R.AXIS_NAMES[i]]
		for j in 4:
			if typeof(a[R.FIELD_NAMES[j]]) != TYPE_INT or a[R.FIELD_NAMES[j]] != values[i][j]:
				return false
	return true


func _importer() -> void:
	var two := _dump(_block(0, "ACTUAL", P0) + _block(1, "BETAFLIGHT", P1), 1)
	var auto: Dictionary = R.import_cli(two)
	_check("diff all, two rateprofiles, final selector 1: imports profile 1 as BETAFLIGHT",
		auto.ok and auto.report.selected_profile == 1 and auto.profile.family == "BETAFLIGHT" and _axes_equal(auto.profile, P1), str(auto.errors))
	_check("imported profile records version, commit and profile index",
		auto.ok and auto.report.firmware_version == "4.5.2" and auto.profile.source.commit == R.SOURCE_COMMIT and auto.profile.source.profile_index == 1)
	var pick0: Dictionary = R.import_cli(two, 0)
	_check("requested_profile 0 selects block 0 (ACTUAL) with no field from block 1",
		pick0.ok and pick0.profile.family == "ACTUAL" and _axes_equal(pick0.profile, P0) and pick0.report.selected_profile == 0, str(pick0.errors))
	var pick1: Dictionary = R.import_cli(two, 1)
	_check("requested_profile 1 selects block 1 (BETAFLIGHT) with no field from block 0",
		pick1.ok and pick1.profile.family == "BETAFLIGHT" and _axes_equal(pick1.profile, P1), str(pick1.errors))
	_check("imported profiles validate", R.validate(pick0.profile).ok and R.validate(pick1.profile).ok)
	var bf_prep: Dictionary = _prepared(pick1.profile)
	_check("imported BETAFLIGHT roll (r=1, s=0.7, e=0) gives 153.846154 at x=0.5",
		absf(R.setpoint_dps(bf_prep, 0, 0.5) - 153.846154) <= DOC_TOL)
	_check("accepted lists the 13 applied rate fields of the selected block plus the header",
		pick0.report.accepted.size() == 14 and _has(pick0.report.accepted, "rateprofile 0 roll_rc_rate = 20")
		and _has(pick0.report.accepted, "revision 024f8e13d"), str(pick0.report.accepted))
	_check("unrelated set lines and commands are listed as ignored, never applied",
		_has(pick0.report.ignored, "set gyro_lpf1_static_hz") and _has(pick0.report.ignored, "set thr_mid")
		and _has(pick0.report.ignored, "set rateprofile_name") and _has(pick0.report.ignored, "set p_roll")
		and _has(pick0.report.ignored, "feature -AIRMODE (not executed)") and _has(pick0.report.ignored, "save (not executed)")
		and _has(pick0.report.ignored, "batch start (not executed)") and _has(pick0.report.ignored, "defaults nosave"))
	_check("the other block's rate fields are reported as not applied",
		_has(pick0.report.ignored, "rateprofile 1 roll_rc_rate (not the selected profile") and not _has(pick0.report.ignored, "rateprofile 0 roll_rc_rate"))
	_check("same text imports to the same identity", _prepared(R.import_cli(two, 0).profile).identity == _prepared(pick0.profile).identity)
	_check("imported profile 0 differs in identity from the product default", _prepared(pick0.profile).identity != _prepared(R.default_profile()).identity)

	var leaky := _dump(_block(0, "ACTUAL", P0) + _block(1, "BETAFLIGHT", P1, ["yaw_rate_limit"]), 1)
	var leak: Dictionary = R.import_cli(leaky)
	_check("no cross-profile leakage: block 1 missing yaw_rate_limit fails instead of borrowing block 0's",
		not leak.ok and leak.profile.is_empty() and _has(leak.errors, "missing yaw_rate_limit"), str(leak.errors))
	_check("the same text still imports block 0 when requested", R.import_cli(leaky, 0).ok)

	var unresolved: Dictionary = R.import_cli(_dump(_block(0, "ACTUAL", P0) + _block(1, "BETAFLIGHT", P1)))
	_check("two blocks without a final restoration selector are unresolved, not 'last block wins'",
		not unresolved.ok and _has(unresolved.errors, "unresolved"), str(unresolved.errors))
	var single: Dictionary = R.import_cli(_dump(_block(2, "ACTUAL", P0)))
	_check("a single block is selected without a restoration selector", single.ok and single.report.selected_profile == 2, str(single.errors))
	var absent: Dictionary = R.import_cli(two, 3)
	_check("requesting an absent rateprofile fails", not absent.ok and _has(absent.errors, "rateprofile 3 has no settings"), str(absent.errors))

	var old: Dictionary = R.import_cli(_dump(_block(0, "ACTUAL", P0), 0, "4.4.0"))
	_check("firmware 4.4.0 is refused as an unsupported firmware version",
		not old.ok and _has(old.errors, "unsupported firmware version: 4.4.0") and old.report.firmware_version == "4.4.0", str(old.errors))
	var headerless: Dictionary = R.import_cli("rateprofile 0\nset rates_type = ACTUAL\n")
	_check("missing version header is refused as an unsupported firmware version",
		not headerless.ok and _has(headerless.errors, "unsupported firmware version"), str(headerless.errors))
	var conflict: Dictionary = R.import_cli(_dump(_block(0, "ACTUAL", P0), 0).replace("# master", "# Betaflight / STM32F7X2 (S7X2) 4.5.1 x / y (abc) MSP API: 1.46"))
	_check("conflicting version headers are refused", not conflict.ok and _has(conflict.errors, "conflicting firmware version"), str(conflict.errors))

	var kiss: Dictionary = R.import_cli(_dump(_block(0, "KISS", P0), 0))
	_check("rates_type KISS is reported unsupported", not kiss.ok and _has(kiss.errors, "unsupported rates_type KISS"), str(kiss.errors))
	var quick: Dictionary = R.import_cli(_dump(_block(0, "QUICK", P0), 0))
	_check("rates_type QUICK is reported unsupported", not quick.ok and _has(quick.errors, "unsupported rates_type QUICK"))
	var other_kiss: Dictionary = R.import_cli(_dump(_block(0, "ACTUAL", P0) + _block(1, "RACEFLIGHT", P1), 0))
	_check("an unsupported family in a non-selected block does not block the selected one", other_kiss.ok, str(other_kiss.errors))

	var malformed: Dictionary = R.import_cli(_dump(_block(0, "ACTUAL", P0), 0).replace("set roll_rc_rate = 20", "set roll_rc_rate = 2O"))
	_check("a malformed value is refused and fails the import",
		not malformed.ok and _has(malformed.report.refused, "roll_rc_rate has malformed value '2O'"), str(malformed.report.refused))
	var fractional: Dictionary = R.import_cli(_dump(_block(0, "ACTUAL", P0), 0).replace("set pitch_expo = 57", "set pitch_expo = 57.5"))
	_check("a fractional value for an integer field is refused", not fractional.ok and _has(fractional.report.refused, "pitch_expo"))
	var range_text := _dump(_block(0, "ACTUAL", P0), 0).replace("set roll_srate = 67", "set roll_srate = 250")
	var ranged: Dictionary = R.import_cli(range_text)
	_check("an out-of-range ACTUAL srate is refused, not clamped",
		not ranged.ok and _has(ranged.report.refused, "axes.roll.srate: 250 outside"), str(ranged.report.refused))
	var outside: Dictionary = R.import_cli(_dump("set roll_rc_rate = 20\n" + _block(0, "ACTUAL", P0), 0))
	_check("a rate field outside any rateprofile block is refused", not outside.ok and _has(outside.report.refused, "outside any rateprofile block"))
	var hostile: Dictionary = R.import_cli(_dump(_block(0, "ACTUAL", P0), 0).replace("board_name MATEKF722", "exec rm -rf /\nflash"))
	_check("command-like lines are inert data, listed as not executed", hostile.ok and _has(hostile.report.ignored, "exec rm -rf / (not executed)"))

	var diff := "# diff\n# version\n# Betaflight / STM32F7X2 (S7X2) 4.5.2 Jan  1 2025 / 00:00:00 (024f8e13d) MSP API: 1.46\n"
	diff += "\nrateprofile 0\n\n# rateprofile 0\nset roll_rc_rate = 25\nset roll_srate = 80\n"
	var partial: Dictionary = R.import_cli(diff)
	_check("a diff that omits fields is refused as incomplete (no 4.5.2 default is pinned), naming the missing fields",
		not partial.ok and _has(partial.errors, "incomplete rateprofile 0") and _has(partial.errors, "rates_type")
		and _has(partial.errors, "yaw_rate_limit") and not _has(partial.errors, "roll_rc_rate,") and partial.report.defaults_used.is_empty(),
		str(partial.errors))
	_check("no Betaflight 4.5.2 defaults are pinned", R.PINNED_DEFAULTS.is_empty())

	var reset_after: Dictionary = R.import_cli(_dump(_block(0, "ACTUAL", P0), 0).replace("\n# save configuration", "\ndefaults nosave\n# save configuration"))
	_check("a defaults marker after assignments discards them (unpinned baseline)",
		not reset_after.ok and _has(reset_after.report.ignored, "earlier rate-profile assignments and selections discarded"), str(reset_after.errors))

	var huge := _dump(_block(0, "ACTUAL", P0), 0) + "#".repeat(R.IMPORT_MAX_BYTES)
	var oversize: Dictionary = R.import_cli(huge)
	_check("input over 256 KiB is refused before parsing", not oversize.ok and _has(oversize.errors, "bytes; the limit is 262144")
		and oversize.report.accepted.is_empty(), str(oversize.errors))
	var many := _dump(_block(0, "ACTUAL", P0), 0) + "#\n".repeat(R.IMPORT_MAX_LINES)
	var too_long: Dictionary = R.import_cli(many)
	_check("input over 20000 lines is refused", not too_long.ok and _has(too_long.errors, "lines; the limit is 20000"), str(too_long.errors))
	var exact := _dump(_block(0, "ACTUAL", P0), 0)
	var padded := exact + "#\n".repeat(R.IMPORT_MAX_LINES - exact.count("\n"))
	_check("input of exactly 20000 lines is accepted", R.import_cli(padded).ok, str(R.import_cli(padded).errors))
	var wide: Dictionary = R.import_cli(_dump(_block(0, "ACTUAL", P0), 0) + "# " + "x".repeat(R.IMPORT_MAX_LINE_BYTES) + "\n")
	_check("a line over 4096 bytes is refused", not wide.ok and _has(wide.errors, "longer than 4096 bytes"))
	var bad_request: Dictionary = R.import_cli(two, -2)
	_check("requested_profile below -1 is refused", not bad_request.ok)
