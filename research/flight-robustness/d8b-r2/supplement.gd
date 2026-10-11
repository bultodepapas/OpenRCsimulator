# D8b-R2 research extension: static sensitivities, no production mutations.
extends SceneTree
const AD = preload("res://physics/aircraft_data.gd")
const Aero = preload("res://physics/aero.gd")
const Air = preload("res://physics/air_data.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const ZERO = {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
const DATA = "res://data/aircraft/jensen_ugly_stik_60.json"

func state(degrees: float, p: float = 0.0) -> PackedFloat64Array:
	var a := deg_to_rad(degrees)
	return RB.make_state(M.v3(0,0,-300), M.v3(25*cos(a),0,25*sin(a)), M.q_from_euler(0,0,0), M.v3(p,0,0))

func derivative(model: Dictionary, degrees: float, dp: float = 0.00001) -> float:
	var minus := state(degrees, -dp)
	var plus := state(degrees, dp)
	var air := Air.compute(state(degrees), M.v3(0,0,0), 1.225)
	return (Aero.loads(plus,air,ZERO,model,1.225)[3] - Aero.loads(minus,air,ZERO,model,1.225)[3]) / (2*dp)

func scan(model: Dictionary) -> Dictionary:
	var peak_cl := -INF
	var peak_alpha := 0.0
	var peak_roll := -INF
	var peak_roll_alpha := 0.0
	var helper_peak := -INF
	for i in range(501):
		var deg := i * 0.05
		var s := state(deg)
		var air := Air.compute(s, M.v3(0,0,0), 1.225)
		var f := Aero.loads(s,air,ZERO,model,1.225)
		var cl: float = (sin(air.alpha)*f[0] - cos(air.alpha)*f[2]) / (air.qbar * model.reference.S)
		if cl > peak_cl:
			peak_cl = cl
			peak_alpha = deg
		var feedback := derivative(model, deg)
		if feedback > peak_roll:
			peak_roll = feedback
			peak_roll_alpha = deg
		helper_peak = maxf(helper_peak, Aero.coefficients(air, M.v3(0,0,0), ZERO, model.aero, model.envelope).CL)
	return {peak_total_cl = peak_cl, peak_total_alpha_deg = peak_alpha, peak_helper_cl = helper_peak,
		peak_roll_nm_per_radps = peak_roll, peak_roll_alpha_deg = peak_roll_alpha,
		roll_at_11 = derivative(model,11), roll_at_15_5 = derivative(model,15.5)}

# Rebuild only the rectangular Stik's equal-area map, keeping the loader's attached
# wing lift target/offset. Three-per-side is verified against the original first.
func refined(original: Dictionary, per_side: int) -> Dictionary:
	var model := original.duplicate(true)
	var n := 2 * per_side
	var b: float = model.reference.b
	var area: float = model.reference.S
	var ys := PackedFloat64Array()
	var edges := PackedFloat64Array()
	var chord := PackedFloat64Array()
	for i in range(n+1): edges.append(-b/2.0 + b*i/n)
	for i in n:
		ys.append(-b/2.0 + b*(i+0.5)/n)
		chord.append(area/b)
	var kernel := AD.strip_influence(edges,ys,chord)
	var tail: Dictionary = model.surfaces.horizontal
	var tail_share: float = tail.area / area * tail.lift_slope
	var target: float = model.aero.CLa - tail_share
	var lo := 0.1
	var hi := 50.0
	var e := PackedFloat64Array()
	for i in 80:
		var a0 := (lo+hi)*0.5
		if a0 == lo or a0 == hi: break
		e = AD.effective_angle_map(kernel,a0,n)
		if a0 * AD._row_mean(e,n) < target: lo = a0
		else: hi = a0
	var slope := (lo+hi)*0.5
	e = AD.effective_angle_map(kernel,slope,n)
	var alpha_offset: float = (model.aero.CL0 - tail_share * tail.incidence)/(slope*AD._row_mean(e,n))
	var offsets := PackedFloat64Array()
	for i in n:
		var sum_row := 0.0
		for k in n: sum_row += e[i*n+k]
		offsets.append(slope*alpha_offset*sum_row)
	model.envelope.station_ys = ys
	model.envelope.strip_slope = slope
	model.envelope.strip_cl0 = offsets
	model.envelope.induced_map = e
	return model

func _initialize() -> void:
	var loaded := AD.load_file(DATA)
	if not loaded.ok:
		push_error(str(loaded.errors))
		quit(1)
		return
	var model: Dictionary = loaded.model
	var widths: Array = []
	for width in [4.0,6.0,8.0,10.0,12.0]:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		raw.aero.envelope.stall_blend_width.value = width
		var candidate := AD.validate_and_derive(raw)
		if not candidate.ok:
			widths.append({width_deg = width, accepted = false, errors = Array(candidate.errors)})
			continue
		var result := scan(candidate.model)
		result.width_deg = width
		result.accepted = true
		result.a1_deg = rad_to_deg(candidate.model.envelope.a1)
		result.a2_deg = rad_to_deg(candidate.model.envelope.a2)
		widths.append(result)
	var spatial: Array = []
	var baseline_error := 0.0
	for n in [3,6,12,24]:
		var changed := refined(model,n)
		if n == 3:
			for a in [0.0,6.0,11.0,15.5,18.0]:
				baseline_error = maxf(baseline_error,absf(derivative(changed,a)-derivative(model,a)))
		var result := scan(changed)
		result.per_side = n
		result.strip_slope = changed.envelope.strip_slope
		spatial.append(result)
	var epsilon: Array = []
	for dp in [0.01,0.001,0.0001,0.00001,0.000001]:
		epsilon.append({dp_radps = dp, derivative = derivative(model,15.5,dp)})
	var wing_only := model.duplicate(true)
	wing_only.surfaces.horizontal.area = 0.0
	wing_only.surfaces.vertical.area = 0.0
	var native_wing: Array = []
	for a in [11.0,13.0,14.0,15.5,18.0]:
		var air := Air.compute(state(a),M.v3(0,0,0),1.225)
		var minus := Aero._local_loads(state(a,-0.00001),air,ZERO,wing_only,1.225)
		var plus := Aero._local_loads(state(a,0.00001),air,ZERO,wing_only,1.225)
		native_wing.append({alpha_deg = a, derivative = (plus[3]-minus[3])/0.00002})
	var out := {width_sensitivity = widths, spatial_refinement = spatial, difference_step = epsilon,
		native_wing_derivative = native_wing,
		positive_control_derivative_error = baseline_error, reference = model.reference,
		inertia = Array(model.inertia), envelope = model.envelope, aero = model.aero, cg = Array(model.cg_le)}
	var file := FileAccess.open("res://../docs/research/flight-robustness/D8b-R2/supplement.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(out,"\t",true,true)+"\n")
	print(JSON.stringify({baseline_error = baseline_error, widths = widths, spatial = spatial, epsilon = epsilon}))
	quit(0 if baseline_error < 1e-7 else 1)
