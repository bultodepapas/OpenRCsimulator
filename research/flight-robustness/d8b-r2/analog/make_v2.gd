# D8b-R2d post-stall law v2 candidate (2026-10-19): a shared section table read with full spanwise stall progression
# (aero.wing_polar.spanwise_progression = 1), fitted to BOTH measured curves of the analog NASA FASER airframe (Ultra Stick
# 120): static whole-aircraft lift retention (faser_cl.csv) and roll damping (faser_clp.csv). Pre-peak knots and the strip
# peak at 14 deg follow the D8b-R2 fixture recipe; the attached fraction falls to 0 at 20 deg (fully separated), so deep-
# stall damping comes from the table alone; profile CD keeps the fixture schedule; the negative branch is the fixture's
# (retention 0.90, unmeasured). Four post-peak knots (strip angles 18, 24, 30, 36 deg, as fractions of the peak) are fitted
# by deterministic coordinate search on J = (RMS retention error / 0.03)^2 + (RMS Clp error / 0.10)^2, with the bench's
# definitions (post_stall_sweep.gd): retention aligned at the stall peaks over FASER 15-30 deg, Clp at FASER angles
# 10-17.5 deg only (the measured term is Clp + Clbetadot*sin(alpha); deeper values are not like-for-like). Viterna
# continues beyond 36 deg. The knots are constrained non-increasing (no post-stall lift recovery), which removes the
# oscillating shapes an unconstrained fit chases in the digitized curve. Analog-fitted EXPERIMENTAL candidate, not a Jensen measurement or a production selection.
# Run from the repository root (writes candidates/post-stall-v2.json; --check refits and compares):
#   godot --headless --path app --script "$PWD/research/flight-robustness/d8b-r2/analog/make_v2.gd" [-- --check]
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
const ANALOG := "res://../research/flight-robustness/d8b-r2/analog/"
const OUT := "res://../research/flight-robustness/d8b-r2/candidates/post-stall-v2.json"
const KNOT_DEG := [18.0, 24.0, 30.0, 36.0]
const START := [0.94, 0.90, 0.86, 0.82]
const STEPS := [0.04, 0.02, 0.01, 0.005]
const LIMITS := [0.40, 1.00]
const RETENTION_DEG := [15.0, 16.0, 17.0, 18.0, 20.0, 22.0, 25.0, 28.0, 30.0]
const CLP_DEG := [10.0, 12.0, 13.5, 15.0, 16.0, 17.5] # like-for-like range, as post_stall_sweep.gd
const SPEED := 25.0
## Peak alignment uses the lift maximum inside the stall region, not a later post-stall plateau value.
const STALL_REGION_DEG := [8.0, 18.0]
const RHO := 1.225
const ZERO := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}

var raw_stik: Dictionary
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
	faser_cl = _csv(ANALOG + "faser_cl.csv")
	faser_clp = _csv(ANALOG + "faser_clp.csv")
	if faser_cl.is_empty() or faser_clp.is_empty():
		printerr("needs faser_cl.csv and faser_clp.csv")
		quit(1)
		return
	for a: float in faser_cl:
		if float(faser_cl[a]) > faser_peak:
			faser_peak = faser_cl[a]
			faser_peak_alpha = a
	raw_stik = JSON.parse_string(FileAccess.get_file_as_string(STIK))
	var model: Dictionary = AD.validate_and_derive(raw_stik).model
	var env: Dictionary = model.envelope
	slope = float(env.strip_slope) * AD._row_mean(env.induced_map, env.station_ys.size())
	for value: float in env.strip_cl0:
		offset += value / float(env.strip_cl0.size())
	cd0 = model.aero.CD0
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
	var result := _candidate(best)
	var content := JSON.stringify(result, "  ", true, true) + "\n"
	var path := ProjectSettings.globalize_path(OUT)
	if check_only:
		if FileAccess.get_file_as_string(path) != content:
			printerr("stale or missing post-stall v2 candidate: ", path)
			quit(1)
			return
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			quit(1)
			return
		file.store_string(content)
		file.close()
	print("fitted knots (fraction of the strip peak) at %s deg: %s after %d evaluations" % [KNOT_DEG, best, evaluations])
	print("J %.3f: RMS retention error %.4f, RMS Clp error %.4f; whole-aircraft CLmax %.3f at %.1f deg" % [best_score.j,
		best_score.retention, best_score.clp, best_score.peak, best_score.peak_alpha])
	print("post-stall v2 candidate %s; NOT selected for production" % ("verified" if check_only else "generated"))
	quit(0)


func _score(knots: Array) -> Dictionary:
	evaluations += 1
	# Physical shape constraint: past the stall the section's lift does not grow again (non-increasing knots).
	for k in range(1, knots.size()):
		if float(knots[k]) > float(knots[k - 1]):
			return {j = INF, retention = INF, clp = INF, peak = NAN, peak_alpha = NAN}
	var data := AD.validate_and_derive(_candidate(knots))
	if not data.ok:
		return {j = INF, retention = INF, clp = INF, peak = NAN, peak_alpha = NAN}
	var curve := _curves(data.model)
	var sq := 0.0
	for a: float in RETENTION_DEG:
		var r: float = _at(curve.alpha, curve.cl, curve.peak_alpha + (a - faser_peak_alpha)) / float(curve.peak)
		sq += pow(r - float(faser_cl[a]) / faser_peak, 2.0)
	var rms_ret := sqrt(sq / RETENTION_DEG.size())
	sq = 0.0
	for a: float in CLP_DEG:
		sq += pow(_at(curve.alpha, curve.clp, a) - float(faser_clp[a]), 2.0)
	var rms_clp := sqrt(sq / CLP_DEG.size())
	return {j = pow(rms_ret / 0.03, 2.0) + pow(rms_clp / 0.10, 2.0), retention = rms_ret, clp = rms_clp,
		peak = curve.peak, peak_alpha = curve.peak_alpha}


func _candidate(knots: Array) -> Dictionary:
	var result: Dictionary = raw_stik.duplicate(true)
	var peak := offset + slope * deg_to_rad(13.0)
	var positive := [
		8.0, offset + slope * deg_to_rad(8.0), cd0, 1.0,
		10.0, offset + slope * deg_to_rad(10.0), cd0, 1.0,
		14.0, peak, cd0 + 0.04, 0.85,
		17.0, peak * lerpf(1.0, float(knots[0]), 0.75), _fixture_cd(17.0), 0.3,
		20.0, peak * lerpf(float(knots[0]), float(knots[1]), 2.0 / 6.0), _fixture_cd(20.0), 0.0,
	]
	for k in range(1, KNOT_DEG.size()):
		positive.append_array([KNOT_DEG[k], peak * float(knots[k]), _fixture_cd(KNOT_DEG[k]), 0.0])
	var a_s := deg_to_rad(KNOT_DEG[-1])
	var cl_s: float = peak * float(knots[-1])
	var cd_s := _fixture_cd(KNOT_DEG[-1])
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
	result.aero.wing_polar = {method = "tabulated-wing-v1", basis = "finite-wing-strip-reference",
		spanwise_progression = {value = 1.0, unit = "1", kind = "derived",
			source = "D8b-R2d post-stall v2: full spanwise stall progression from the calibrated induced map (strip loading relative to the wing mean)"},
		positive = {value = positive, unit = "deg, 1, 1, 1", kind = "estimated",
			source = "D8b-R2d post-stall v2 (research/flight-robustness/d8b-r2/analog/make_v2.gd): post-peak knots 18/24/30/36 deg fitted with spanwise progression to the measured static lift retention and roll damping of NASA FASER (Ultra Stick 120; Owens et al. AIAA 2006-3306 Fig. 2a, Hoe et al. AIAA 2012-4645 Fig. 14); pre-peak knots and profile CD from the D8b-R2 fixture recipe; separated from 20 deg; Viterna beyond 36 deg. Analog airframe, NOT a Jensen measurement"},
		negative = {value = negative, unit = "deg, 1, 1, 1", kind = "estimated",
			source = "D8b-R2 fixture recipe, retention 0.90 (no measured negative branch); NOT a Jensen measurement"}}
	return result


func _fixture_cd(deg: float) -> float:
	var xs := [14.0, 25.0, 45.0, 70.0, 90.0]
	var ys := [cd0 + 0.04, cd0 + 0.22, cd0 + cd90 * 0.5, cd0 + cd90 * 0.88, cd0 + cd90]
	if deg <= xs[0]:
		return ys[0]
	for i in range(1, xs.size()):
		if deg <= xs[i]:
			return lerpf(ys[i - 1], ys[i], (deg - xs[i - 1]) / (xs[i] - xs[i - 1]))
	return ys[-1]


static func _csv(path: String) -> Dictionary:
	var table := {}
	for line in FileAccess.get_file_as_string(ProjectSettings.globalize_path(path)).split("\n"):
		if line.is_empty() or line.begins_with("#") or line.begins_with("alpha"):
			continue
		var parts := line.split(",")
		table[float(parts[0])] = float(parts[1])
	return table


static func _loads(model: Dictionary, alpha: float, p: float) -> PackedFloat64Array:
	var s := RB.make_state(M.v3(0, 0, -300), M.v3(SPEED * cos(alpha), 0, SPEED * sin(alpha)), M.q_identity(), M.v3(p, 0, 0))
	return Aero.loads(s, Air.compute(s, M.v3(0, 0, 0)), ZERO, model, RHO)


## Static whole-aircraft CL and Clp at 0.5 deg steps, 0-40 deg (the bench's definitions).
static func _curves(model: Dictionary) -> Dictionary:
	var S: float = model.reference.S
	var b: float = model.reference.b
	var alpha := PackedFloat64Array()
	var cl := PackedFloat64Array()
	var clp := PackedFloat64Array()
	var peak := -INF
	var peak_alpha := 0.0
	for k in 81:
		var deg := k * 0.5
		var a := deg_to_rad(deg)
		var f := _loads(model, a, 0.0)
		var value: float = (f[0] * sin(a) - f[2] * cos(a)) / (0.5 * RHO * SPEED * SPEED * S)
		var d: float = (_loads(model, a, 1e-5)[3] - _loads(model, a, -1e-5)[3]) / 2e-5
		alpha.append(deg)
		cl.append(value)
		clp.append(d * 2.0 / (0.5 * RHO * SPEED * S * b * b))
		if value > peak and deg >= STALL_REGION_DEG[0] and deg <= STALL_REGION_DEG[1]:
			peak = value
			peak_alpha = deg
	return {alpha = alpha, cl = cl, clp = clp, peak = peak, peak_alpha = peak_alpha}


static func _at(x: PackedFloat64Array, y: PackedFloat64Array, value: float) -> float:
	if value <= x[0]:
		return y[0]
	for i in range(1, x.size()):
		if value <= x[i]:
			return lerpf(y[i - 1], y[i], (value - x[i - 1]) / (x[i] - x[i - 1]))
	return y[y.size() - 1]
