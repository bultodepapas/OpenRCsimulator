extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const M := preload("res://physics/math3d.gd")

const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const SPEED := 15.0
const RHO := 1.225
const RATE_STEP := 0.05

var _reference_area := 0.0
var _reference_span := 0.0
var _aircraft_path := PATH

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--data":
		_aircraft_path = args[1]
	elif not args.is_empty():
		printerr("usage: -- [--data <aircraft-json-path>]")
		quit(64)
		return
	var result: Dictionary = AD.load_file(_aircraft_path)
	if not result.ok:
		printerr("aircraft load failed: %s" % [result.errors])
		quit(2)
		return
	var model: Dictionary = result.model
	_reference_area = float(model.reference.S)
	_reference_span = float(model.reference.b)
	var wing_only: Dictionary = model.duplicate(true)
	wing_only.surfaces.horizontal.area = 0.0
	wing_only.surfaces.vertical.area = 0.0
	var no_fin: Dictionary = model.duplicate(true)
	no_fin.surfaces.vertical.area = 0.0
	var no_induced_wing: Dictionary = wing_only.duplicate(true)
	no_induced_wing.aero.k_induced = 0.0
	var stations: int = model.envelope.station_ys.size()
	var has_polar: bool = not model.envelope.get("wing_polar", {}).is_empty()
	if has_polar:
		printerr("this diagnostic's CD term split assumes no wing_polar; Stik unexpectedly has one")
		quit(3)
		return
	print("schema=d11g-yaw-decomposition-v1 aircraft=%s law=%s V=%.3f rho=%.3f h=%.3f stations=%d polar=%s input=%s" % [
		model.id, Aero.LOADS_LAW, SPEED, RHO, RATE_STEP, stations, str(has_polar), str(result.get("input_identity", {}))])
	print("columns=alpha_deg,total_Cnr,wing_Cnr,horizontal_tail_Cnr,fin_Cnr,wing_profile_Cnr,wing_induced_Cnr,wing_separated_Cnr,wing_lift_projection_Cnr,wing_reconstruction_residual_Cnr,profile_reference_Cnr,source_weight_min_minus,source_weight_max_minus,source_weight_min_plus,source_weight_max_plus,stall_weight_min,stall_weight_max,alpha_min_deg,alpha_max_deg")
	var fin: Dictionary = model.surfaces.vertical
	var fin_arm: float = float(fin.position[0]) - float(model.cg_le[0])
	var cnb_fin: float = float(fin.lift_slope) * float(fin.area) / _reference_area * fin_arm / _reference_span
	var fin_invariant: float = -2.0 * fin_arm / _reference_span * cnb_fin
	var profile_reference: float = -float(model.aero.CD0) / 3.0 * (1.0 - 1.0 / (4.0 * pow(float(stations / 2), 2)))
	print("invariants=fin_yaw_rate_Cnr:%.12f profile_drag_Cnr:%.12f expected_sum:%.12f" % [fin_invariant, profile_reference, fin_invariant + profile_reference])
	for deg in [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 11.0]:
		var alpha := deg_to_rad(deg)
		var total := _cnr(model, alpha)
		var wing := _cnr(wing_only, alpha)
		var no_fin_cnr := _cnr(no_fin, alpha)
		var profile_induced_model := _cnr(no_induced_wing, alpha)
		var vertical_fin := total - no_fin_cnr
		var horizontal_tail := no_fin_cnr - wing
		var wing_terms_minus: Dictionary = _wing_force_moment_terms(model, alpha, -RATE_STEP)
		var wing_terms_plus: Dictionary = _wing_force_moment_terms(model, alpha, RATE_STEP)
		var profile_cnr := _cnr_from_moment_delta(float(wing_terms_plus.profile_moment_nm), float(wing_terms_minus.profile_moment_nm))
		var induced_cnr := _cnr_from_moment_delta(float(wing_terms_plus.induced_moment_nm), float(wing_terms_minus.induced_moment_nm))
		var separated_cnr := _cnr_from_moment_delta(float(wing_terms_plus.separated_moment_nm), float(wing_terms_minus.separated_moment_nm))
		var lift_cnr := _cnr_from_moment_delta(float(wing_terms_plus.lift_moment_nm), float(wing_terms_minus.lift_moment_nm))
		var reconstructed := profile_cnr + induced_cnr + separated_cnr + lift_cnr
		var residual := wing - reconstructed
		var reference_profile: float = profile_reference
		var flow_minus: Dictionary = _flow_summary(model, alpha, -RATE_STEP)
		var flow_plus: Dictionary = _flow_summary(model, alpha, RATE_STEP)
		print("%.1f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.8f,%.8f,%.8f,%.8f,%.6f,%.6f,%.6f,%.6f" % [
			deg, total, wing, horizontal_tail, vertical_fin, profile_cnr, induced_cnr, separated_cnr, lift_cnr,
			residual, reference_profile, flow_minus.source_min, flow_minus.source_max,
			flow_plus.source_min, flow_plus.source_max, minf(float(flow_minus.stall_min), float(flow_plus.stall_min)),
			maxf(float(flow_minus.stall_max), float(flow_plus.stall_max)), minf(float(flow_minus.alpha_min), float(flow_plus.alpha_min)),
			maxf(float(flow_minus.alpha_max), float(flow_plus.alpha_max))])
		if deg == 11.0:
			print("alpha11_rate_minus_rows=" + JSON.stringify(wing_terms_minus.rows, "", true))
			print("alpha11_rate_plus_rows=" + JSON.stringify(wing_terms_plus.rows, "", true))
			print("alpha11_source_weights_minus=" + JSON.stringify(flow_minus.source_weights))
			print("alpha11_source_weights_plus=" + JSON.stringify(flow_plus.source_weights))
			print("alpha11_no_induced_wing_Cnr=%.10f current_wing_Cnr=%.10f (diagnostic coefficient ablation only)" % [profile_induced_model, wing])
			print("alpha11_error_decomposition=fin_delta:%.10f profile_delta:%.10f induced:%.10f separated:%.10f lift_projection:%.10f horizontal_tail:%.10f total_minus_reference:%.10f" % [
				vertical_fin - fin_invariant, profile_cnr - profile_reference, induced_cnr, separated_cnr, lift_cnr,
				horizontal_tail, total - (fin_invariant + profile_reference)])
	print("decomposition uses direct current-law wing strip forces; profile/induced/separated drag terms follow `_local_loads`; lift projection is the chord-axis component. Horizontal and vertical tails are isolated by duplicate models with only corresponding tail area set to zero. Test law is direct `_local_loads`; no global/local selector blend is applied. No production model/data modified.")
	quit(0)


func _state(alpha: float, yaw_rate: float) -> PackedFloat64Array:
	return PackedFloat64Array([0, 0, -100, SPEED * cos(alpha), 0.0, SPEED * sin(alpha), 1, 0, 0, 0, 0, 0, yaw_rate])


func _controls() -> Dictionary:
	return {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}


func _loads(model: Dictionary, alpha: float, yaw_rate: float) -> PackedFloat64Array:
	var s := _state(alpha, yaw_rate)
	var air: Dictionary = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), RHO)
	return Aero._local_loads(s, air, _controls(), model, RHO)


func _cnr(model: Dictionary, alpha: float) -> float:
	var plus: PackedFloat64Array = _loads(model, alpha, RATE_STEP)
	var minus: PackedFloat64Array = _loads(model, alpha, -RATE_STEP)
	return _cnr_from_moment_delta(float(plus[5]), float(minus[5]))


func _cnr_from_moment_delta(plus_moment: float, minus_moment: float) -> float:
	var derivative := (plus_moment - minus_moment) / (2.0 * RATE_STEP)
	var denominator := 0.5 * RHO * SPEED * SPEED * _reference_area * pow(_reference_span, 2) / (2.0 * SPEED)
	return derivative / denominator


func _wing_force_moment_terms(model: Dictionary, alpha: float, yaw_rate: float) -> Dictionary:
	var s := _state(alpha, yaw_rate)
	var air: Dictionary = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), RHO)
	var rows: Array = Aero.wing_strip_loads(s, air, _controls(), model, RHO)
	var ys: PackedFloat64Array = model.envelope.station_ys
	var station_area := float(model.reference.S) / float(ys.size())
	var center_arm_y := float(model.reference.arp_le[1]) - float(model.cg_le[1])
	var profile_moment := 0.0
	var induced_moment := 0.0
	var separated_moment := 0.0
	var lift_moment := 0.0
	for i in rows.size():
		var row: Dictionary = rows[i]
		var y: float = center_arm_y + float(ys[i])
		var f0: float = float(air.v_air[0]) - yaw_rate * y
		var f2: float = float(air.v_air[2])
		var vp: float = float(row.plane_speed_mps)
		if vp == 0.0:
			continue
		var angle: float = float(row.alpha_geometric_rad)
		var cl: float = float(row.cl)
		var stall: float = float(row.stall_weight)
		var cd_profile: float = float(model.aero.CD0)
		var cd_induced: float = (1.0 - stall) * float(model.aero.k_induced) * pow(cl - float(model.aero.CL_minD), 2)
		var cd_separated: float = stall * float(model.envelope.CD90) * pow(sin(angle), 2)
		var common := 0.5 * RHO * vp * station_area * y * f0
		# Mz = -y*Fx. Drag Fx is -q*Vp*area*CD*f0; lift Fx = q*Vp*area*CL*f2.
		profile_moment += common * cd_profile
		induced_moment += common * cd_induced
		separated_moment += common * cd_separated
		lift_moment -= 0.5 * RHO * vp * station_area * cl * f2 * y
	return {profile_moment_nm = profile_moment, induced_moment_nm = induced_moment,
		separated_moment_nm = separated_moment, lift_moment_nm = lift_moment, rows = rows}


func _flow_summary(model: Dictionary, alpha: float, yaw_rate: float) -> Dictionary:
	var s := _state(alpha, yaw_rate)
	var air: Dictionary = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), RHO)
	var flow: Dictionary = Aero._wing_flow(s, air, _controls(), model)
	var weights: PackedFloat64Array = flow.sources
	var angles: PackedFloat64Array = flow.angles
	var min_source := INF
	var max_source := -INF
	var min_angle := INF
	var max_angle := -INF
	var min_stall := INF
	var max_stall := -INF
	for i in weights.size():
		min_source = minf(min_source, weights[i])
		max_source = maxf(max_source, weights[i])
		min_angle = minf(min_angle, rad_to_deg(angles[i]))
		max_angle = maxf(max_angle, rad_to_deg(angles[i]))
		var row := Aero.wing_strip_loads(s, air, _controls(), model, RHO)[i] as Dictionary
		min_stall = minf(min_stall, float(row.stall_weight))
		max_stall = maxf(max_stall, float(row.stall_weight))
	return {source_min = min_source, source_max = max_source, alpha_min = min_angle, alpha_max = max_angle,
		stall_min = min_stall, stall_max = max_stall, source_weights = weights}
