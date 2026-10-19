# D8b-R2d analog candidate (2026-10-19): the D8b-R2 fixture recipe with one change. The positive post-peak lift knots
# follow the measured whole-aircraft retention CL(alpha)/CLmax of NASA FASER (Hangar 9 Ultra Stick 120, Owens, Cox,
# Morelli AIAA 2006-3306 Fig. 2a, digitized in faser_cl.csv) instead of an arbitrary retention at 25 deg. Strip knot
# angles map to FASER angles aligned at the two peaks (strip peak knot 14 deg, FASER peak 15 deg).
# Everything else is the fixture's estimate, kept so the comparison isolates the post-peak lift shape: pre-peak knots and
# the strip peak at 14 deg, profile-CD and attached-fraction schedules, and the negative branch (retention 0.9). Beyond
# the last measured angle (FASER 30 deg, strip knot 29 deg) the positive branch continues by Viterna from that knot, with CDmax = CD0 + CD90.
# The post-peak strip knots are solved by fixed-point iteration until the whole-aircraft static retention (Aero.loads,
# 25 m/s, controls neutral, zero rates) matches FASER aligned at its peak; the report prints the residuals.
# This is an analog-matched EXPERIMENTAL candidate, not a Jensen measurement or a production selection.
# Run from the repository root (writes candidates/faser-analog.json beside the D8b-R2 fixtures; --check verifies it):
#   godot --headless --path app --script "$PWD/research/flight-robustness/d8b-r2/analog/make_analog.gd" [-- --check]
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
const CSV := "res://../research/flight-robustness/d8b-r2/analog/faser_cl.csv"
const OUT := "res://../research/flight-robustness/d8b-r2/candidates/faser-analog.json"
const FASER_PEAK_DEG := 15.0
const FASER_LAST_DEG := 30.0
const STRIP_PEAK_DEG := 14.0
const POST_PEAK_DEG := [16.0, 18.0, 20.0, 22.0, 25.0, 27.0, 29.0] # strip knots; peak-aligned FASER angles 17-30 deg
const VITERNA_DEG := [40.0, 50.0, 60.0, 75.0]
const ITERATIONS := 40
const TOLERANCE := 0.002 # retention units at the knots
const ZERO := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}


func _initialize() -> void:
	var check_only := "--check" in OS.get_cmdline_user_args()
	var faser := _faser_retention()
	if faser.is_empty():
		printerr("cannot read ", CSV)
		quit(1)
		return
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STIK))
	var model: Dictionary = AD.validate_and_derive(raw).model
	var env: Dictionary = model.envelope
	var slope: float = float(env.strip_slope) * AD._row_mean(env.induced_map, env.station_ys.size())
	var offset := 0.0
	for value: float in env.strip_cl0:
		offset += value / float(env.strip_cl0.size())
	var cd0: float = model.aero.CD0
	var cd90: float = env.CD90
	var peak: float = offset + slope * deg_to_rad(STRIP_PEAK_DEG - 1.0) # the fixture's strip peak value at its 14 deg knot
	var post := PackedFloat64Array()
	for a: float in POST_PEAK_DEG:
		post.append(peak * _interp(faser, FASER_PEAK_DEG + (a - STRIP_PEAK_DEG)))
	var result := {}
	var report := []
	var worst := INF
	# The reference peak (angle and CL) comes from the first evaluation and stays fixed, so the targets are absolute:
	# raising a post-peak knot cannot raise its own normalizer. Damped multiplicative updates avoid overshoot.
	var ref_alpha := NAN
	var ref_cl := NAN
	var curve := {}
	for iteration in ITERATIONS:
		result = _candidate(raw, slope, offset, cd0, cd90, peak, post)
		var data := AD.validate_and_derive(result)
		if not data.ok:
			printerr("candidate invalid at iteration %d: %s" % [iteration, data.errors])
			quit(1)
			return
		curve = _whole_aircraft(data.model)
		if is_nan(ref_alpha):
			ref_alpha = curve.peak_alpha
			ref_cl = curve.peak
		worst = 0.0
		report = []
		for k in POST_PEAK_DEG.size():
			var a: float = POST_PEAK_DEG[k]
			var whole_alpha: float = ref_alpha + (a - STRIP_PEAK_DEG)
			var target := _interp(faser, FASER_PEAK_DEG + (a - STRIP_PEAK_DEG))
			var actual: float = _cl_at(curve, whole_alpha) / ref_cl
			worst = maxf(worst, absf(actual - target))
			report.append([whole_alpha, target, actual])
			post[k] *= pow(target / actual, 0.7)
		if worst < TOLERANCE:
			break
	if worst >= TOLERANCE:
		printerr("retention fit did not converge: worst knot error %.4f" % worst)
		quit(1)
		return
	var content := JSON.stringify(result, "  ", true, true) + "\n"
	var path := ProjectSettings.globalize_path(OUT)
	if check_only:
		if FileAccess.get_file_as_string(path) != content:
			printerr("stale or missing analog candidate: ", path)
			quit(1)
			return
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			quit(1)
			return
		file.store_string(content)
		file.close()
	print("whole-aircraft reference peak %.3f at %.1f deg (candidate's own peak %.3f at %.1f deg)" % [ref_cl, ref_alpha, curve.peak, curve.peak_alpha])
	print("| Whole-aircraft α (°) | FASER retention | Candidate retention |")
	print("| --- | --- | --- |")
	for row in report:
		print("| %.1f | %.3f | %.3f |" % [row[0], row[1], row[2]])
	print("faser-analog candidate %s; NOT selected for production" % ("verified" if check_only else "generated"))
	quit(0)


## Retention CL/CLmax by whole-aircraft angle (deg) from the digitized FASER curve.
func _faser_retention() -> Dictionary:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(CSV))
	var table := {}
	var peak := 0.0
	for line in text.split("\n"):
		if line.is_empty() or line.begins_with("#") or line.begins_with("alpha"):
			continue
		var parts := line.split(",")
		table[float(parts[0])] = float(parts[1])
		peak = maxf(peak, float(parts[1]))
	if table.is_empty() or not table.has(FASER_LAST_DEG):
		return {}
	for k in table.keys():
		table[k] = float(table[k]) / peak
	return table


## Linear interpolation in a {deg: value} table at integer-degree keys.
static func _interp(table: Dictionary, deg: float) -> float:
	var lo := floorf(deg)
	var hi := lo + 1.0
	if not table.has(lo) or not table.has(hi):
		return float(table[clampf(roundf(deg), 15.0, FASER_LAST_DEG)])
	return lerpf(float(table[lo]), float(table[hi]), deg - lo)


func _candidate(raw: Dictionary, slope: float, offset: float, cd0: float, cd90: float, peak: float,
		post: PackedFloat64Array) -> Dictionary:
	var result: Dictionary = raw.duplicate(true)
	var positive := [
		8.0, offset + slope * deg_to_rad(8.0), cd0, 1.0,
		10.0, offset + slope * deg_to_rad(10.0), cd0, 1.0,
		STRIP_PEAK_DEG, peak, cd0 + 0.04, 0.85,
	]
	for k in POST_PEAK_DEG.size():
		var a: float = POST_PEAK_DEG[k]
		positive.append_array([a, post[k], _fixture_cd(a, cd0, cd90), _fixture_fraction(a)])
	# Viterna continuation from the last measured knot to 90 deg (CDmax = CD0 + CD90 meets the required last row).
	var a_s := deg_to_rad(POST_PEAK_DEG[-1])
	var cl_s: float = post[post.size() - 1]
	var cd_s := _fixture_cd(POST_PEAK_DEG[-1], cd0, cd90)
	var cd_max := cd0 + cd90
	var a2 := (cl_s - cd_max * sin(a_s) * cos(a_s)) * sin(a_s) / (cos(a_s) * cos(a_s))
	var b2 := (cd_s - cd_max * sin(a_s) * sin(a_s)) / cos(a_s)
	for d: float in VITERNA_DEG:
		var a := deg_to_rad(d)
		positive.append_array([d, 0.5 * cd_max * sin(2.0 * a) + a2 * cos(a) * cos(a) / sin(a),
			cd_max * sin(a) * sin(a) + b2 * cos(a), _fixture_fraction(d)])
	positive.append_array([90.0, 0.0, cd0 + cd90, 0.0])
	var negative_peak: float = -offset + slope * deg_to_rad(13.0)
	var negative := [
		8.0, -offset + slope * deg_to_rad(8.0), cd0, 1.0,
		10.0, -offset + slope * deg_to_rad(10.0), cd0, 1.0,
		14.0, negative_peak, cd0 + 0.04, 0.85,
		25.0, negative_peak * 0.9, cd0 + 0.22, 0.4,
		45.0, cd90 * 0.5, cd0 + cd90 * 0.5, 0.0,
		70.0, cd90 * 0.32, cd0 + cd90 * 0.88, 0.0,
		90.0, 0.0, cd0 + cd90, 0.0,
	]
	result.aero.wing_polar = {method = "tabulated-wing-v1", basis = "finite-wing-strip-reference",
		positive = {value = positive, unit = "deg, 1, 1, 1", kind = "estimated",
			source = "D8b-R2d analog candidate: post-peak lift knots 16-29 deg solved to the measured whole-aircraft retention of NASA FASER (Ultra Stick 120; Owens, Cox, Morelli AIAA 2006-3306 Fig. 2a; research/flight-robustness/d8b-r2/analog/faser_cl.csv) aligned at its peak; pre-peak knots, profile CD and attached fraction from the D8b-R2 fixture recipe; Viterna continuation beyond 29 deg. Analog airframe, NOT a Jensen measurement"},
		negative = {value = negative, unit = "deg, 1, 1, 1", kind = "estimated",
			source = "D8b-R2 fixture recipe, retention 0.90 (no measured negative branch); NOT a Jensen measurement"}}
	return result


## The D8b-R2 fixture's profile-CD and attached-fraction schedules, linearly interpolated between its knots.
static func _fixture_cd(deg: float, cd0: float, cd90: float) -> float:
	return _piecewise(deg, [14.0, 25.0, 45.0, 70.0, 90.0], [cd0 + 0.04, cd0 + 0.22, cd0 + cd90 * 0.5, cd0 + cd90 * 0.88, cd0 + cd90])


static func _fixture_fraction(deg: float) -> float:
	return _piecewise(deg, [14.0, 25.0, 45.0, 90.0], [0.85, 0.4, 0.0, 0.0])


static func _piecewise(x: float, xs: Array, ys: Array) -> float:
	if x <= float(xs[0]):
		return float(ys[0])
	for i in range(1, xs.size()):
		if x <= float(xs[i]):
			return lerpf(float(ys[i - 1]), float(ys[i]), (x - float(xs[i - 1])) / (float(xs[i]) - float(xs[i - 1])))
	return float(ys[-1])


## Whole-aircraft static CL at 0.1 deg steps from 0 to 40 deg, as in screen_candidates.gd.
static func _whole_aircraft(model: Dictionary) -> Dictionary:
	var cls := PackedFloat64Array()
	var peak := -INF
	var peak_alpha := 0.0
	for k in 401:
		var alpha := deg_to_rad(k / 10.0)
		var s := RB.make_state(M.v3(0, 0, -300), M.v3(25.0 * cos(alpha), 0, 25.0 * sin(alpha)), M.q_identity(), M.v3(0, 0, 0))
		var f := Aero.loads(s, Air.compute(s, M.v3(0, 0, 0)), ZERO, model, 1.225)
		var cl: float = (f[0] * sin(alpha) - f[2] * cos(alpha)) / (0.5 * 1.225 * 625.0 * float(model.reference.S))
		cls.append(cl)
		if cl > peak:
			peak = cl
			peak_alpha = k / 10.0
	return {cls = cls, peak = peak, peak_alpha = peak_alpha}


static func _cl_at(curve: Dictionary, deg: float) -> float:
	var x := clampf(deg * 10.0, 0.0, 400.0)
	var i := mini(int(floorf(x)), 399)
	var cls: PackedFloat64Array = curve.cls
	return lerpf(cls[i], cls[i + 1], x - i)
