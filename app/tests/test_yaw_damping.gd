# D11f: yaw damping through the oracle/local transition. The local fin's velocity, force and moment arm are consistent:
# its yaw-rate damping equals the invariant −2·(l_v/b)·Cnβ_fin of the same fin data (the data's Cnβ is derived from it
# and checked by the loader). The wing's physical yaw damping is profile drag, −CD0/3·(1 − 1/(4n²)) for n equal strips per
# side (independent Weissinger reference with Kutta–Joukowski forces: the lift-induced part is +0.0004·CL²,
# research/aero/d11f/wing_yaw_damping.py). Acceptance: across α 0–11° the local Cnr is within 7 % of that
# Stik-consistent value (fin invariant + wing profile). The borrowed oracle Cnr (UltraStick 25e, −0.1833) was
# inconsistent with the oracle's own fin-derived Cnβ; D11g replaced it with the Stik's own, checked here too.
# Run: godot --headless --path . --script res://tests/test_yaw_damping.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")

const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const V := 15.0
const RHO := 1.225

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	var model: Dictionary = AD.load_file(PATH).model
	var no_fin := model.duplicate(true)
	no_fin.surfaces.vertical.area = 0.0
	var S: float = model.reference.S
	var b: float = model.reference.b
	var fin: Dictionary = model.surfaces.vertical
	var arm: float = float(fin.position[0]) - float(model.cg_le[0])
	var cnb_fin: float = float(fin.lift_slope) * float(fin.area) / S * arm / b
	var fin_invariant := -2.0 * arm / b * cnb_fin
	var n: int = model.envelope.station_ys.size() / 2
	var wing_profile: float = -float(model.aero.CD0) / 3.0 * (1.0 - 1.0 / (4.0 * n * n))
	var consistent := fin_invariant + wing_profile
	# D6e-R1: the data's Cnr is about the ARP, ahead of the CG; the oracle's r × F adds CYr's side-force arm.
	var r_x: float = -(float(model.reference.arp_le[0]) - float(model.cg_le[0]))
	var oracle_cnr: float = float(model.aero.Cnr) + float(model.aero.CYr) * r_x / b
	print("info Stik-consistent Cnr: fin −2(l_v/b)·Cnβ_fin %.4f + wing profile %.4f = %.4f; oracle Cnr %.4f (%.4f about the CG)"
		% [fin_invariant, wing_profile, consistent, model.aero.Cnr, oracle_cnr])
	_check("D11g: the oracle's Cnr about the CG %.4f within 2 %% of the Stik-consistent value" % oracle_cnr,
		absf(oracle_cnr / consistent - 1.0) < 0.02)
	var analytic_inputs_ok := _analytic_preconditions(model)
	_check("independent Cnr derivative preconditions: symmetric attached strips, centered datums, no polar or ground effect",
		analytic_inputs_ok)
	if not analytic_inputs_ok:
		print("%d checks, %d failed" % [_count, _failures])
		quit(1)
		return
	var worst_fin := 0.0
	var worst_cnb := 0.0
	var worst_analytic_h005 := 0.0
	var worst_analytic_h00125 := 0.0
	var every_refinement_converged := true
	var alpha0_local_cnr := NAN
	for deg in [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 11.0]:
		var a := deg_to_rad(deg)
		var total := _cnr(model, a, 0.05)
		var refined := _cnr(model, a, 0.0125)
		var analytic: Dictionary = _analytic_cnr(model, a)
		if not bool(analytic.get("ok", false)):
			_check("independent Cnr derivative exists at α %.1f°" % deg, false, str(analytic.get("reason", "unknown")))
			continue
		var error_h005 := absf(total - float(analytic.total_cnr))
		var error_h00125 := absf(refined - float(analytic.total_cnr))
		worst_analytic_h005 = maxf(worst_analytic_h005, error_h005)
		worst_analytic_h00125 = maxf(worst_analytic_h00125, error_h00125)
		if error_h00125 >= error_h005:
			every_refinement_converged = false
		var fin_part := total - _cnr(no_fin, a)
		var cnb := _cnb(model, a)
		print("info α %4.1f: Cnr h=.05 %.9f, h=.0125 %.9f, analytic %.9f; fin lift %.9f + fin profile %.9f + wing profile %.9f + induced %.9f + lift projection %.9f; Cnβ %.4f" % [
			deg, total, refined, analytic.total_cnr, analytic.fin_lift_cnr, analytic.fin_profile_cnr,
			analytic.wing_profile_cnr, analytic.wing_induced_cnr, analytic.wing_lift_cnr, cnb])
		if deg == 0.0:
			alpha0_local_cnr = total
		worst_fin = maxf(worst_fin, absf(fin_part / fin_invariant - 1.0))
		worst_cnb = maxf(worst_cnb, absf(cnb / cnb_fin - 1.0))
	_check("fin: local yaw-rate damping = −2·(l_v/b)·Cnβ_fin = %.4f within 2 %% at α 0–11° (consistent velocity, force, arm)" % fin_invariant,
		worst_fin < 0.02, "worst %.2f %%" % (100.0 * worst_fin))
	# The data's Cnb uses the fin arm from the ARP (loader contract); the local fin acts about the CG.
	_check("local Cnβ within 3 %% of the fin-derived Cnβ about the CG %.4f at α 0–11°" % cnb_fin, worst_cnb < 0.03,
		"worst %.2f %%" % (100.0 * worst_cnb))
	_check("α=0 local Cnr within 7 %% of the fin-plus-wing-profile approximation %.4f" % consistent,
		absf(alpha0_local_cnr / consistent - 1.0) < 0.07, "local %.6f" % alpha0_local_cnr)
	_check("local Cnr h=0.05 matches the complete independent attached-law derivative over α 0–11°",
		worst_analytic_h005 < 1.0e-5, "worst absolute Cnr error %.9f" % worst_analytic_h005)
	_check("local Cnr h=0.0125 converges to the complete independent derivative over α 0–11°",
		worst_analytic_h00125 < 2.0e-6, "worst absolute Cnr error %.9f" % worst_analytic_h00125)
	_check("fourfold central-difference step refinement reduces analytic error at every α",
		every_refinement_converged)
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _cnr(model: Dictionary, a: float, h := 0.05) -> float:
	return (_loads(model, a, 0.0, h)[5] - _loads(model, a, 0.0, -h)[5]) / (2.0 * h) \
		/ (0.5 * RHO * V * V * float(model.reference.S) * pow(float(model.reference.b), 2) / (2.0 * V))


func _analytic_preconditions(model: Dictionary) -> bool:
	var ys: PackedFloat64Array = model.envelope.station_ys
	var n := ys.size()
	if n < 2 or n % 2 != 0:
		return false
	var lateral_arp_cg := float(model.reference.arp_le[1]) - float(model.cg_le[1])
	if absf(lateral_arp_cg) > 1.0e-12:
		return false
	for i in n:
		if absf(float(ys[i]) + float(ys[n - 1 - i])) > 1.0e-12:
			return false
	var polar: Dictionary = model.envelope.get("wing_polar", {})
	if not polar.is_empty() or model.aero.has("ground_effect"):
		return false
	var twist: PackedFloat64Array = model.surfaces.get("station_incidence", PackedFloat64Array())
	if not twist.is_empty():
		if twist.size() != n:
			return false
		for incidence in twist:
			if absf(float(incidence)) > 1.0e-12:
				return false
	if model.envelope.get("induced_map", PackedFloat64Array()).size() != n * n:
		return false
	if model.envelope.get("strip_cl0", PackedFloat64Array()).size() != n:
		return false
	var fin: Dictionary = model.surfaces.vertical
	var horizontal: Dictionary = model.surfaces.horizontal
	if absf(float(fin.position[1]) - float(model.cg_le[1])) > 1.0e-12:
		return false
	if absf(float(horizontal.position[1]) - float(model.cg_le[1])) > 1.0e-12:
		return false
	if absf(float(fin.incidence)) > 1.0e-12:
		return false
	return true


## Chain rule for the current attached section-plane law, derived independently of Aero._local_loads.
## At r=0 the max full-speed source normalization has two one-sided branches; mirroring makes
## the central source derivative -y*cos(alpha)/V. The finite-difference caller checks this derivative.
func _analytic_cnr(model: Dictionary, alpha: float) -> Dictionary:
	var env: Dictionary = model.envelope
	var aero: Dictionary = model.aero
	var surfaces: Dictionary = model.surfaces
	var ys: PackedFloat64Array = env.station_ys
	var n := ys.size()
	var e: PackedFloat64Array = env.induced_map
	var strip_cl0: PackedFloat64Array = env.strip_cl0
	var twist: PackedFloat64Array = surfaces.get("station_incidence", PackedFloat64Array())
	var slope: float = float(env.get("strip_slope", aero.CLa))
	var strip_area := float(model.reference.S) / float(n)
	var angles := PackedFloat64Array()
	var angle_rates := PackedFloat64Array()
	var source_rates := PackedFloat64Array()
	angles.resize(n)
	angle_rates.resize(n)
	source_rates.resize(n)
	for k in n:
		var y: float = float(model.reference.arp_le[1]) - float(model.cg_le[1]) + float(ys[k])
		var incidence := float(twist[k]) if not twist.is_empty() else 0.0
		angles[k] = wrapf(alpha + incidence, -PI, PI)
		angle_rates[k] = y * sin(alpha) / V
		source_rates[k] = -y * cos(alpha) / V
	var wing_profile_moment_rate := 0.0
	var wing_induced_moment_rate := 0.0
	var wing_lift_moment_rate := 0.0
	for i in n:
		var cl := float(strip_cl0[i])
		var cl_rate := 0.0
		for k in n:
			var influence: float = float(e[i * n + k])
			cl += slope * influence * angles[k]
			cl_rate += slope * influence * angle_rates[k]
			if k != i:
				cl_rate += slope * influence * angles[k] * source_rates[k]
		var local_alpha: float = angles[i]
		var stall_limit: float = float(env.a1) if local_alpha >= 0.0 else float(env.n1)
		if absf(local_alpha) >= stall_limit:
			return {ok = false, reason = "strip %d is outside the attached branch" % i}
		var y: float = float(ys[i])
		var x := V * cos(alpha)
		var z := V * sin(alpha)
		var dx := -y
		var dvp := -y * cos(alpha)
		var cd0: float = float(aero.CD0)
		var cd_induced := float(aero.k_induced) * pow(cl - float(aero.CL_minD), 2)
		var cd_induced_rate := 2.0 * float(aero.k_induced) * (cl - float(aero.CL_minD)) * cl_rate
		var profile_fx_rate := -0.5 * RHO * strip_area * (dvp * cd0 * x + V * cd0 * dx)
		var induced_fx_rate := -0.5 * RHO * strip_area * (dvp * cd_induced * x
			+ V * cd_induced_rate * x + V * cd_induced * dx)
		var lift_fx_rate := 0.5 * RHO * strip_area * (dvp * cl * z + V * cl_rate * z)
		wing_profile_moment_rate += -y * profile_fx_rate
		wing_induced_moment_rate += -y * induced_fx_rate
		wing_lift_moment_rate += -y * lift_fx_rate
	var fin: Dictionary = surfaces.vertical
	var fin_arm_x := -(float(fin.position[0]) - float(model.cg_le[0]))
	var fin_dynamic_scale := -0.5 * RHO * float(fin.area) * V * cos(alpha) * fin_arm_x * fin_arm_x
	var fin_lift_moment_rate := fin_dynamic_scale * float(fin.lift_slope)
	var fin_profile_moment_rate := fin_dynamic_scale * float(surfaces.tail_CD0)
	var denominator := 0.5 * RHO * V * V * float(model.reference.S) * pow(float(model.reference.b), 2) / (2.0 * V)
	var fin_lift_cnr := fin_lift_moment_rate / denominator
	var fin_profile_cnr := fin_profile_moment_rate / denominator
	var wing_profile_cnr := wing_profile_moment_rate / denominator
	var wing_induced_cnr := wing_induced_moment_rate / denominator
	var wing_lift_cnr := wing_lift_moment_rate / denominator
	return {ok = true, fin_lift_cnr = fin_lift_cnr, fin_profile_cnr = fin_profile_cnr,
		wing_profile_cnr = wing_profile_cnr, wing_induced_cnr = wing_induced_cnr,
		wing_lift_cnr = wing_lift_cnr,
		total_cnr = fin_lift_cnr + fin_profile_cnr + wing_profile_cnr + wing_induced_cnr + wing_lift_cnr}


func _cnb(model: Dictionary, a: float) -> float:
	var db := 0.01
	return (_loads(model, a, db, 0.0)[5] - _loads(model, a, -db, 0.0)[5]) / (2.0 * db) \
		/ (0.5 * RHO * V * V * float(model.reference.S) * float(model.reference.b))


func _loads(model: Dictionary, a: float, beta: float, r: float) -> PackedFloat64Array:
	var s := PackedFloat64Array([0, 0, -100, V * cos(a) * cos(beta), V * sin(beta), V * sin(a) * cos(beta), 1, 0, 0, 0, 0, 0, r])
	var d := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	return Aero._local_loads(s, Air.compute(s, PackedFloat64Array([0, 0, 0]), RHO), d, model, RHO)
