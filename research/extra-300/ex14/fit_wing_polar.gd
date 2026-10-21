# EX-14h: the Extra's post-stall wing polar (aero.wing_polar, tabulated-wing-v1 with full spanwise stall progression),
# fitted by the D8b-R2d post-stall v2 method (research/flight-robustness/d8b-r2/analog/make_v2.gd) to the measured
# static lift retention and stall-onset roll damping of NASA FASER (Hangar 9 Ultra Stick 120, Re about 3.6e5, the Extra's
# Reynolds class): faser_cl.csv and faser_clp.csv, scored with the bench's own definitions (make_v2.gd's static curve
# helpers, as post_stall_sweep.gd). The recipe is v2's: knots on the Extra's own calibrated attached line to 10 deg, the
# strip peak at 13 deg, attached fraction 0.85 at 14 and 0.3 at 17 deg, monotone post-peak knots at 18/24/30/36 deg (the
# fitted parameters), Viterna beyond and the CD90 flat plate at 90 deg; the negative branch is v2's (retention 0.90,
# unmeasured). Only the aircraft differs from make_v2.gd. FASER is an analog airframe (rectangular high wing), not the
# Extra; the fit transfers RC-class whole-aircraft behaviour, not an Extra measurement.
# The base model is the Extra data with aero.wing_polar removed, so the fit is the same before and after the generator
# embeds it. Writes research/extra-300/ex14/wing_polar_fit.json, which research/extra-300/ex05/derive_physics.py embeds.
# Run from the repository root (--check refits and compares):
#   godot --headless --path app --script "$PWD/research/extra-300/ex14/fit_wing_polar.gd" [-- --check]
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Bench := preload("../../flight-robustness/d8b-r2/analog/make_v2.gd")

const EXTRA := "res://data/aircraft/gp_extra_300s_60.json"
const ANALOG := "res://../research/flight-robustness/d8b-r2/analog/"
const OUT := "res://../research/extra-300/ex14/wing_polar_fit.json"
const KNOT_DEG := [18.0, 24.0, 30.0, 36.0]
## Post-peak lift knots (fractions of the strip peak).
const START := [0.94, 0.90, 0.86, 0.82]
const STEPS := [0.04, 0.02, 0.01, 0.005]
const LIMITS := [0.40, 1.00]
const RETENTION_DEG := [15.0, 16.0, 17.0, 18.0, 20.0, 22.0, 25.0, 28.0, 30.0]
const CLP_DEG := [10.0, 12.0, 13.5, 15.0, 16.0, 17.5]

var raw: Dictionary
var faser_cl := {}
var faser_clp := {}
var faser_peak := 0.0
var faser_peak_alpha := 0.0
var slope := 0.0
var offset := 0.0
var cd0 := 0.0
var cd90 := 0.0
var evaluations := 0


func _initialize() -> void:
	var check_only := "--check" in OS.get_cmdline_user_args()
	faser_cl = Bench._csv(ANALOG + "faser_cl.csv")
	faser_clp = Bench._csv(ANALOG + "faser_clp.csv")
	if faser_cl.is_empty() or faser_clp.is_empty():
		printerr("needs faser_cl.csv and faser_clp.csv")
		quit(1)
		return
	for a: float in faser_cl:
		if float(faser_cl[a]) > faser_peak:
			faser_peak = faser_cl[a]
			faser_peak_alpha = a
	raw = JSON.parse_string(FileAccess.get_file_as_string(EXTRA))
	raw.aero.erase("wing_polar")
	var base := AD.validate_and_derive(raw)
	if not base.ok:
		printerr("Extra data without its wing polar is invalid: ", base.errors)
		quit(1)
		return
	var env: Dictionary = base.model.envelope
	slope = float(env.strip_slope) * AD._row_mean(env.induced_map, env.station_ys.size())
	for value: float in env.strip_cl0:
		offset += value / float(env.strip_cl0.size())
	cd0 = base.model.aero.CD0
	cd90 = env.CD90
	var best: Array = START.duplicate()
	var best_score := _score(best)
	for step: float in STEPS:
		var improved := true
		while improved:
			improved = false
			for k in best.size():
				for direction in [1.0, -1.0]:
					var trial: Array = best.duplicate()
					trial[k] = clampf(float(trial[k]) + direction * step, LIMITS[0], LIMITS[1])
					var score := _score(trial)
					if score.j < best_score.j - 1e-9:
						best = trial
						best_score = score
						improved = true
	var polar := _polar(best)
	var result := {
		generator = "research/extra-300/ex14/fit_wing_polar.gd",
		method = "D8b-R2d post-stall v2 recipe (research/flight-robustness/d8b-r2/analog/make_v2.gd) on the Extra (EX-14h)",
		measured = ["research/flight-robustness/d8b-r2/analog/faser_cl.csv", "research/flight-robustness/d8b-r2/analog/faser_clp.csv"],
		knot_angles_deg = KNOT_DEG, knot_fractions_of_peak = best,
		rms_retention_error_15_30_deg = best_score.retention, rms_clp_error_10_17_5_deg = best_score.clp,
		whole_aircraft_cl_max = best_score.peak, whole_aircraft_cl_max_alpha_deg = best_score.peak_alpha,
		spanwise_progression = 1.0, positive = polar.positive, negative = polar.negative}
	var content := JSON.stringify(result, "  ", true, true) + "\n"
	var path := ProjectSettings.globalize_path(OUT)
	if check_only:
		if FileAccess.get_file_as_string(path) != content:
			printerr("stale or missing Extra wing polar fit: ", path)
			quit(1)
			return
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			quit(1)
			return
		file.store_string(content)
		file.close()
	print("knots %s deg: %s; %d evaluations" % [KNOT_DEG, best, evaluations])
	print("J %.3f: RMS retention error %.4f, RMS Clp error %.4f; whole-aircraft CLmax %.3f at %.1f deg; %s" % [best_score.j,
		best_score.retention, best_score.clp, best_score.peak, best_score.peak_alpha, "verified" if check_only else "written"])
	quit(0)


func _score(knots: Array) -> Dictionary:
	evaluations += 1
	var none := {j = INF, retention = INF, clp = INF, peak = NAN, peak_alpha = NAN}
	# Past the stall the section's lift does not grow again.
	for k in range(1, knots.size()):
		if float(knots[k]) > float(knots[k - 1]):
			return none
	var candidate: Dictionary = raw.duplicate(true)
	var polar := _polar(knots)
	candidate.aero.wing_polar = {method = "tabulated-wing-v1", basis = "finite-wing-strip-reference",
		spanwise_progression = {value = 1.0, unit = "1", kind = "derived", source = "fit"},
		positive = {value = polar.positive, unit = "deg, 1, 1, 1", kind = "estimated", source = "fit"},
		negative = {value = polar.negative, unit = "deg, 1, 1, 1", kind = "estimated", source = "fit"}}
	var data := AD.validate_and_derive(candidate)
	if not data.ok:
		return none
	var curve: Dictionary = Bench._curves(data.model)
	var sq := 0.0
	for a: float in RETENTION_DEG:
		var r: float = Bench._at(curve.alpha, curve.cl, curve.peak_alpha + (a - faser_peak_alpha)) / float(curve.peak)
		sq += pow(r - float(faser_cl[a]) / faser_peak, 2.0)
	var rms_ret := sqrt(sq / RETENTION_DEG.size())
	sq = 0.0
	for a: float in CLP_DEG:
		sq += pow(Bench._at(curve.alpha, curve.clp, a) - float(faser_clp[a]), 2.0)
	var rms_clp := sqrt(sq / CLP_DEG.size())
	return {j = pow(rms_ret / 0.03, 2.0) + pow(rms_clp / 0.10, 2.0), retention = rms_ret, clp = rms_clp,
		peak = curve.peak, peak_alpha = curve.peak_alpha}


## Both branches as flat [angle deg, CL, profile CD, attached fraction] rows (v2's recipe; see the header).
func _polar(knots: Array) -> Dictionary:
	var peak := offset + slope * deg_to_rad(13.0)
	var positive := [
		8.0, offset + slope * deg_to_rad(8.0), cd0, 1.0,
		10.0, offset + slope * deg_to_rad(10.0), cd0, 1.0,
		14.0, peak, cd0 + 0.04, 0.85,
		17.0, peak * lerpf(1.0, float(knots[0]), 0.75), _profile_cd(17.0), 0.3,
		20.0, peak * lerpf(float(knots[0]), float(knots[1]), 2.0 / 6.0), _profile_cd(20.0), 0.0,
	]
	for k in range(1, KNOT_DEG.size()):
		positive.append_array([KNOT_DEG[k], peak * float(knots[k]), _profile_cd(KNOT_DEG[k]), 0.0])
	var a_s := deg_to_rad(KNOT_DEG[-1])
	var cl_s: float = peak * float(knots[-1])
	var cd_s := _profile_cd(KNOT_DEG[-1])
	var cd_max := cd0 + cd90
	var a2 := (cl_s - cd_max * sin(a_s) * cos(a_s)) * sin(a_s) / (cos(a_s) * cos(a_s))
	var b2 := (cd_s - cd_max * sin(a_s) * sin(a_s)) / cos(a_s)
	for d: float in [45.0, 55.0, 65.0, 77.0]:
		var a := deg_to_rad(d)
		positive.append_array([d, 0.5 * cd_max * sin(2.0 * a) + a2 * cos(a) * cos(a) / sin(a),
			cd_max * sin(a) * sin(a) + b2 * cos(a), 0.0])
	positive.append_array([90.0, 0.0, cd0 + cd90, 0.0])
	var negative_peak := -offset + slope * deg_to_rad(13.0)
	var negative := [
		8.0, -offset + slope * deg_to_rad(8.0), cd0, 1.0,
		10.0, -offset + slope * deg_to_rad(10.0), cd0, 1.0,
		14.0, negative_peak, cd0 + 0.04, 0.85,
		25.0, negative_peak * 0.9, cd0 + 0.22, 0.4,
		45.0, cd90 * 0.5, cd0 + cd90 * 0.5, 0.0,
		70.0, cd90 * 0.32, cd0 + cd90 * 0.88, 0.0,
		90.0, 0.0, cd0 + cd90, 0.0,
	]
	return {positive = positive, negative = negative}


## v2's profile-drag schedule (the D8b-R2 fixture recipe) on the Extra's CD0 and CD90.
func _profile_cd(deg: float) -> float:
	var xs := [14.0, 25.0, 45.0, 70.0, 90.0]
	var ys := [cd0 + 0.04, cd0 + 0.22, cd0 + cd90 * 0.5, cd0 + cd90 * 0.88, cd0 + cd90]
	if deg <= xs[0]:
		return ys[0]
	for i in range(1, xs.size()):
		if deg <= xs[i]:
			return lerpf(ys[i - 1], ys[i], (deg - xs[i - 1]) / (xs[i] - xs[i - 1]))
	return ys[-1]
