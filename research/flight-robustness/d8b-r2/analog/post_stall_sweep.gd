# D8b-R2d (2026-10-19): score aircraft data against two measured post-stall curves of an analog airframe, NASA FASER
# (Hangar 9 Ultra Stick 120): its static whole-aircraft lift retention (faser_cl.csv, Owens et al. 2006 Fig. 2a) and its
# roll damping (faser_clp.csv, Hoe et al. 2012 Fig. 14, forced oscillation). Read-only; any aircraft JSON or candidate.
# Static whole-aircraft loads (Aero.loads at 25 m/s, controls neutral) at 0.5 deg steps; Clp = (dMx/dp)*2/(rho/2 V S b^2)
# at p = 0 by central difference. Retention CL/CLmax is compared with FASER aligned at the two stall peaks (the maximum
# between 8 and 18 deg; FASER's is 15 deg); Clp at the
# same angle of attack. The FASER Clp is a finite-frequency forced-oscillation value; a quasi-steady model is expected
# to differ where it depends on reduced frequency (above stall). Analog evidence, not a Jensen acceptance band.
# Run from the repository root, with absolute or res:// paths:
#   godot --headless --path app --script "$PWD/research/flight-robustness/d8b-r2/analog/post_stall_sweep.gd" \
#     -- res://data/aircraft/jensen_ugly_stik_60.json "$PWD/research/flight-robustness/d8b-r2/candidates/retained.json"
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const ANALOG := "res://../research/flight-robustness/d8b-r2/analog/"
const SPEED := 25.0
## Peak alignment uses the lift maximum inside the stall region, not a later post-stall plateau value.
const STALL_REGION_DEG := [8.0, 18.0]
const RHO := 1.225
const ZERO := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
const RETENTION_DEG := [15.0, 16.0, 17.0, 18.0, 20.0, 22.0, 25.0, 28.0, 30.0] # FASER angles, compared peak-aligned
const CLP_DEG := [10.0, 13.5, 15.0, 16.0, 17.5, 19.0, 20.0, 22.5, 25.0, 27.5, 30.0, 32.5, 35.0]


func _initialize() -> void:
	var paths := OS.get_cmdline_user_args()
	var faser_cl := _csv(ANALOG + "faser_cl.csv")
	var faser_clp := _csv(ANALOG + "faser_clp.csv")
	if paths.is_empty() or faser_cl.is_empty() or faser_clp.is_empty():
		printerr("usage: -- <aircraft json> [...]; needs faser_cl.csv and faser_clp.csv beside this script")
		quit(2)
		return
	var faser_peak := 0.0
	var faser_peak_alpha := 0.0
	for a: float in faser_cl:
		if float(faser_cl[a]) > faser_peak:
			faser_peak = faser_cl[a]
			faser_peak_alpha = a
	var header := "| Data | CLmax at α | RMS retention error (15–30°) | RMS Clp error (10–35°) | Clp > 0 below 17.5° | Clp at 20 / 25 / 30 / 35° |"
	var rows := []
	var detail := []
	for path in paths:
		var data := AD.load_file(path)
		if not data.ok:
			printerr(path, ": ", data.errors)
			quit(1)
			return
		var model: Dictionary = data.model
		var curve := _curves(model)
		var sq := 0.0
		for a: float in RETENTION_DEG:
			var r: float = _at(curve.alpha, curve.cl, curve.peak_alpha + (a - faser_peak_alpha)) / float(curve.peak)
			sq += pow(r - float(faser_cl[a]) / faser_peak, 2.0)
		var rms_ret := sqrt(sq / RETENTION_DEG.size())
		sq = 0.0
		var early_unstable := 0
		for a: float in CLP_DEG:
			var value := _at(curve.alpha, curve.clp, a)
			sq += pow(value - float(faser_clp[a]), 2.0)
			if a < 17.5 and value > 0.0:
				early_unstable += 1
		var rms_clp := sqrt(sq / CLP_DEG.size())
		rows.append("| %s | %.3f at %.1f° | %.3f | %.3f | %d of %d | %+.2f / %+.2f / %+.2f / %+.2f |" % [path.get_file(),
			curve.peak, curve.peak_alpha, rms_ret, rms_clp, early_unstable, 4,
			_at(curve.alpha, curve.clp, 20.0), _at(curve.alpha, curve.clp, 25.0), _at(curve.alpha, curve.clp, 30.0),
			_at(curve.alpha, curve.clp, 35.0)])
		var line := "%s Clp:" % path.get_file()
		for a in [12.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 22.0, 25.0, 30.0, 35.0, 40.0]:
			line += " %.0f:%+.2f" % [a, _at(curve.alpha, curve.clp, a)]
		detail.append(line)
	print("FASER: CLmax %.3f at %.1f°; Clp 20 / 25 / 30 / 35°: %+.2f / %+.2f / %+.2f / %+.2f" % [faser_peak, faser_peak_alpha,
		faser_clp[20.0], faser_clp[25.0], faser_clp[30.0], faser_clp[35.0]])
	print(header)
	print("| --- | --- | --- | --- | --- | --- |")
	for r in rows:
		print(r)
	for line in detail:
		print(line)
	quit(0)


## {alpha_deg: value} from a two-column CSV with # comments and a header row.
static func _csv(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(path))
	var table := {}
	for line in text.split("\n"):
		if line.is_empty() or line.begins_with("#") or line.begins_with("alpha"):
			continue
		var parts := line.split(",")
		table[float(parts[0])] = float(parts[1])
	return table


static func _loads(model: Dictionary, alpha: float, p: float) -> PackedFloat64Array:
	var s := RB.make_state(M.v3(0, 0, -300), M.v3(SPEED * cos(alpha), 0, SPEED * sin(alpha)), M.q_identity(), M.v3(p, 0, 0))
	return Aero.loads(s, Air.compute(s, M.v3(0, 0, 0)), ZERO, model, RHO)


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
