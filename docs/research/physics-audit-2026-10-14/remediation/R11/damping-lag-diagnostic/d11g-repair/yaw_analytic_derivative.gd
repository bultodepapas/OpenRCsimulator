extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")

const AIRCRAFT := "res://data/aircraft/jensen_ugly_stik_60.json"
const V := 15.0
const RHO := 1.225
const FD_STEPS := [0.2, 0.1, 0.05, 0.025, 0.0125, 0.00625, 0.003125, 0.0015625, 0.00078125]

var _model: Dictionary
var _area := 0.0
var _span := 0.0

func _initialize() -> void:
	var loaded: Dictionary = AD.load_file(AIRCRAFT)
	if not loaded.ok:
		printerr("aircraft load failed: %s" % [loaded.errors])
		quit(2)
		return
	_model = loaded.model
	_area = float(_model.reference.S)
	_span = float(_model.reference.b)
	if not _preconditions_hold():
		printerr("analytic derivation preconditions failed; see checks printed above")
		quit(3)
		return
	print("schema=d11g-yaw-analytic-derivative-v1 aircraft=%s law=%s input=%s V=%.3f rho=%.3f" % [
		_model.id, Aero.LOADS_LAW, JSON.stringify(loaded.input_identity), V, RHO])
	print("method=independent closed-form dMz/dr for current attached neutral symmetric section law; production calls are used only for the finite-difference convergence column")
	print("source derivative at r=0: one-sided max-speed branches differ; central derivative of symmetric normalized source weight is -y*cos(alpha)/V")
	print("columns=alpha_deg,analytic_fin_Cnr,analytic_profile_Cnr,analytic_induced_Cnr,analytic_lift_projection_Cnr,analytic_wing_Cnr,analytic_horizontal_Cnr,analytic_total_Cnr,fd_h0.05_Cnr,fd_h0.05_minus_analytic,max_abs_error_over_steps")
	for deg in [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 11.0]:
		var alpha := deg_to_rad(deg)
		var analytic: Dictionary = _analytic(alpha)
		if not analytic.ok:
			printerr("alpha %.1f derivation failed: %s" % [deg, analytic.reason])
			quit(4)
			return
		var errors: Array[float] = []
		var fd_005 := 0.0
		for step in FD_STEPS:
			var fd: float = _production_cnr(alpha, step)
			var err: float = fd - float(analytic.total_cnr)
			errors.append(err)
			if is_equal_approx(float(step), 0.05):
				fd_005 = fd
		var max_abs := 0.0
		for err in errors:
			max_abs = maxf(max_abs, absf(err))
		print("%.1f,%.12f,%.12f,%.12f,%.12f,%.12f,%.12f,%.12f,%.12f,%.12f,%.12f" % [
			deg, analytic.fin_cnr, analytic.profile_cnr, analytic.induced_cnr, analytic.lift_cnr,
			analytic.wing_cnr, 0.0, analytic.total_cnr, fd_005, fd_005-analytic.total_cnr, max_abs])
		print("alpha%.1f_fd_sweep=" % deg + JSON.stringify(FD_STEPS) + ":" + JSON.stringify(errors))
		if deg == 11.0:
			print("alpha11_strip_analytic=" + JSON.stringify(analytic.strips, "", true))
	quit(0)


func _preconditions_hold() -> bool:
	var ok := true
	var ys: PackedFloat64Array = _model.envelope.station_ys
	var cg_y: float = float(_model.reference.arp_le[1]) - float(_model.cg_le[1])
	var polar: Dictionary = _model.envelope.get("wing_polar", {})
	var twist: PackedFloat64Array = _model.surfaces.get("station_incidence", PackedFloat64Array())
	var fin: Dictionary = _model.surfaces.vertical
	var center_arm_y: float = cg_y
	if absf(center_arm_y) > 1e-12:
		print("FAIL symmetric wing/tail datum required; ARP-to-CG y arm=%.16g" % center_arm_y)
		ok = false
	for i in ys.size():
		if absf(float(ys[i]) + float(ys[ys.size() - 1 - i])) > 1e-12:
			print("FAIL mirrored strip positions required at index %d" % i)
			ok = false
	if not polar.is_empty():
		print("FAIL Stik wing polar must be empty for this attached-law analytic branch")
		ok = false
	if not twist.is_empty() and twist.size() != ys.size():
		print("FAIL station twist count differs from stations")
		ok = false
	if absf(float(fin.position[1]) - float(_model.cg_le[1])) > 1e-12:
		print("FAIL centered vertical fin required")
		ok = false
	if absf(float(fin.incidence)) > 1e-12:
		print("FAIL zero fin incidence required for the closed form")
		ok = false
	if _model.envelope.induced_map.size() != ys.size() * ys.size():
		print("FAIL current Stik induced map not available")
		ok = false
	if ok:
		print("preconditions=PASS mirrored equal-area wing stations; zero lateral datum; zero-incidence centered fin; no wing polar; induced map present")
	return ok


func _analytic(alpha: float) -> Dictionary:
	var env: Dictionary = _model.envelope
	var aero: Dictionary = _model.aero
	var surfaces: Dictionary = _model.surfaces
	var ys: PackedFloat64Array = env.station_ys
	var n := ys.size()
	var strip_area := _area / float(n)
	var e: PackedFloat64Array = env.induced_map
	var slope: float = float(env.get("strip_slope", aero.CLa))
	var strip_zero: PackedFloat64Array = env.get("strip_cl0", PackedFloat64Array())
	var twist: PackedFloat64Array = surfaces.get("station_incidence", PackedFloat64Array())
	var angles := PackedFloat64Array()
	var angle_rates := PackedFloat64Array()
	var source_rates := PackedFloat64Array()
	angles.resize(n)
	angle_rates.resize(n)
	source_rates.resize(n)
	for k in n:
		var station_y: float = float(ys[k])
		var incidence := float(twist[k]) if not twist.is_empty() else 0.0
		angles[k] = wrapf(alpha + incidence, -PI, PI)
		angle_rates[k] = station_y * sin(alpha) / V
		# The max in the shared-speed normalizer has left/right derivatives at r=0.
		# Mirror symmetry makes their central mean exactly this expression.
		source_rates[k] = -station_y * cos(alpha) / V
	var profile_moment_rate := 0.0
	var induced_moment_rate := 0.0
	var lift_moment_rate := 0.0
	var strips: Array = []
	for i in n:
		var base := float(strip_zero[i])
		var base_rate := 0.0
		for k in n:
			var influence: float = float(e[i*n+k])
			base += slope * influence * angles[k]
			base_rate += slope * influence * angle_rates[k]
			if k != i:
				base_rate += slope * influence * angles[k] * source_rates[k]
		var local_alpha: float = angles[i]
		var stall_threshold: float = float(env.a1) if local_alpha >= 0.0 else float(env.n1)
		if absf(local_alpha) >= stall_threshold:
			return {ok = false, reason = "strip %d is not on the all-attached branch (alpha %.9f threshold %.9f)" % [i, local_alpha, stall_threshold]}
		var cl := base
		var cl_rate := base_rate
		var cd_profile: float = float(aero.CD0)
		var cd_induced := float(aero.k_induced) * pow(cl - float(aero.CL_minD), 2)
		var cd_induced_rate := 2.0 * float(aero.k_induced) * (cl - float(aero.CL_minD)) * cl_rate
		var y: float = float(ys[i])
		var x := V * cos(alpha)
		var z := V * sin(alpha)
		var dx := -y
		var dvp := -y * cos(alpha)
		var profile_fx_rate := -0.5 * RHO * strip_area * (dvp * cd_profile * x + V * 0.0 * x + V * cd_profile * dx)
		var induced_fx_rate := -0.5 * RHO * strip_area * (dvp * cd_induced * x + V * cd_induced_rate * x + V * cd_induced * dx)
		var lift_fx_rate := 0.5 * RHO * strip_area * (dvp * cl * z + V * cl_rate * z)
		profile_moment_rate += -y * profile_fx_rate
		induced_moment_rate += -y * induced_fx_rate
		lift_moment_rate += -y * lift_fx_rate
		strips.append({
			"index": i,
			"y_m": y,
			"alpha_rad": local_alpha,
			"alpha_rate_rad_per_s": angle_rates[i],
			"source_rate_per_s_central": source_rates[i],
			"cl": cl,
			"cl_rate_per_s_central": cl_rate,
			"cd_profile": cd_profile,
			"cd_induced": cd_induced,
			"cd_induced_rate_per_s_central": cd_induced_rate,
			"profile_dMz_dr_Nm_s": -y * profile_fx_rate,
			"induced_dMz_dr_Nm_s": -y * induced_fx_rate,
			"lift_projection_dMz_dr_Nm_s": -y * lift_fx_rate,
		})
	var denominator := 0.5 * RHO * V * V * _area * _span * _span / (2.0 * V)
	var profile_cnr := profile_moment_rate / denominator
	var induced_cnr := induced_moment_rate / denominator
	var lift_cnr := lift_moment_rate / denominator
	var fin: Dictionary = surfaces.vertical
	var fin_arm_x := -(float(fin.position[0]) - float(_model.cg_le[0]))
	var fin_area: float = float(fin.area)
	var tail_cd0: float = float(surfaces.get("tail_CD0", 0.0))
	var fin_slope: float = float(fin.lift_slope)
	var fin_moment_rate := -0.5 * RHO * fin_area * V * cos(alpha) * fin_arm_x * fin_arm_x * (tail_cd0 + fin_slope)
	var fin_cnr := fin_moment_rate / denominator
	return {ok = true, profile_cnr = profile_cnr, induced_cnr = induced_cnr, lift_cnr = lift_cnr,
		wing_cnr = profile_cnr + induced_cnr + lift_cnr, fin_cnr = fin_cnr,
		horizontal_cnr = 0.0, total_cnr = profile_cnr + induced_cnr + lift_cnr + fin_cnr, strips = strips}


func _production_cnr(alpha: float, h: float) -> float:
	var plus: PackedFloat64Array = _production_loads(alpha, h)
	var minus: PackedFloat64Array = _production_loads(alpha, -h)
	var denominator := 0.5 * RHO * V * V * _area * _span * _span / (2.0 * V)
	return ((float(plus[5]) - float(minus[5])) / (2.0 * h)) / denominator


func _production_loads(alpha: float, yaw_rate: float) -> PackedFloat64Array:
	var state := PackedFloat64Array([0, 0, -100, V*cos(alpha), 0.0, V*sin(alpha), 1, 0, 0, 0, 0, 0, yaw_rate])
	var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), RHO)
	var controls := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
	return Aero._local_loads(state, air, controls, _model, RHO)
