# D8b-R2d/e: synthetic spline, boundary, passive-load, map/lag and loader contracts.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Polar := preload("res://physics/wing_polar.gd")
const Fixture := preload("res://tests/wing_polar_fixture.gd")
const ZERO := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
var count := 0
var failures := 0


func check(label: String, ok: bool) -> void:
	count += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func sample(alpha: float, polar: Dictionary) -> PackedFloat64Array:
	return Polar.evaluate(alpha, polar.offset+polar.slope*alpha, polar)


func reject(label: String, edit: Callable) -> void:
	var raw := Fixture.raw()
	edit.call(raw.aero.wing_polar)
	var result := AD.validate_and_derive(raw)
	check(label, not result.ok and "wing_polar" in str(result.errors) and result.model.is_empty())


func _initialize() -> void:
	var raw := Fixture.raw()
	var data := AD.validate_and_derive(raw)
	check("valid synthetic table accepted with explicit warning", data.ok and "Experimental" in str(data.warnings))
	if not data.ok:
		printerr(data.errors)
		quit(1)
		return
	var model: Dictionary = data.model
	var polar: Dictionary = model.envelope.wing_polar
	var reference: Dictionary = AD.load_file(Fixture.PATH).model
	var attached := true
	var finite := true
	var periodic := true
	var no_overshoot := true
	for side in [1.0, -1.0]:
		var branch: Dictionary = polar.positive if side > 0.0 else polar.negative
		for i in branch.angles.size():
			var at: float = side*branch.angles[i]
			var value := sample(at, polar)
			for component in 3:
				check("knot %s/%s/%s" % [side,i,component], absf(value[component]-(side if component == 0 else 1.0)*branch.values[i*3+component]) < 1e-12)
			var eps := 1e-7
			var left := sample(at-eps, polar)
			var right := sample(at+eps, polar)
			for component in 3:
				check("C1 knot %s/%s/%s" % [side,i,component], absf((value[component]-left[component])/eps-(right[component]-value[component])/eps) < 2e-4)
		for i in range(branch.angles.size()-1):
			for k in 101:
				var at := lerpf(branch.angles[i],branch.angles[i+1],float(k)/100.0)
				var value := sample(side*at,polar)
				for c in 3:
					var x: float = value[c]*side if c == 0 else value[c]
					no_overshoot = no_overshoot and x >= minf(branch.values[3*i+c],branch.values[3*(i+1)+c])-1e-12 \
						and x <= maxf(branch.values[3*i+c],branch.values[3*(i+1)+c])+1e-12
	for k in range(-1800,1801):
		var angle := deg_to_rad(k/10.0)
		var value := sample(angle, polar)
		for v in value:
			finite = finite and is_finite(v)
		finite = finite and value[1] >= 0.0 and value[2] >= 0.0 and value[2] <= 1.0
	check("all table intervals preserve sample bounds", no_overshoot)
	check("full angle range finite, nonnegative drag and bounded retention", finite)
	for c in 3:
		periodic = periodic and absf(sample(-PI,polar)[c]-sample(PI,polar)[c]) < 1e-12
	check("reverse-flow seam periodic", periodic)
	var power_ok := true
	var lag_ok := true
	var telemetry_ok := true
	for k in range(-170,171,5):
		var alpha := deg_to_rad(float(k))
		var state := RB.make_state(M.v3(0,0,-300),M.v3(25*cos(alpha),1.1,25*sin(alpha)),M.q_identity(),M.v3(0.13,-0.2,0.1))
		var air := Air.compute(state,M.v3(0,0,0))
		var rows := Aero.wing_strip_loads(state,air,ZERO,model,1.225)
		var cl_mean := 0.0
		var loads := PackedFloat64Array([0.,0.,0.,0.,0.,0.])
		for row in rows:
			cl_mean += float(row.cl)/rows.size()
			for c in 3:
				loads[c] += row.force_body_n[c]
				loads[c+3] += row.moment_body_nm[c]
		lag_ok = lag_ok and absf(cl_mean-Aero.wing_lift_coefficient(state,air,ZERO,model)) < 1e-12
		var wing_only: Dictionary = model.duplicate(true)
		wing_only.surfaces.horizontal.area = 0.0
		wing_only.surfaces.vertical.area = 0.0
		wing_only.surfaces.erase("body_cn_beta") # D10-R2: the fuselage couple is not a wing load
		telemetry_ok = telemetry_ok and loads == Aero._local_loads(state,air,ZERO,wing_only,1.225)
		var power := M.dot(loads.slice(0,3),air.v_air)+M.dot(loads.slice(3,6),state.slice(RB.RATE,RB.RATE+3))
		power_ok = power_ok and power <= 1e-10
	for k in range(-30,31):
		var alpha := deg_to_rad(k/10.0)
		var state := RB.make_state(M.v3(0,0,-300),M.v3(25*cos(alpha),0,25*sin(alpha)),M.q_identity(),M.v3(0,0,0))
		var air := Air.compute(state,M.v3(0,0,0))
		attached = attached and Aero.loads(state,air,ZERO,model,1.225) == Aero.loads(state,air,ZERO,reference,1.225)
	check("small-angle loads remain byte identical", attached)
	check("summed strip telemetry is the actual wing load", telemetry_ok)
	check("wing downwash input equals the same strip law", lag_ok)
	check("wing force+moment power passive with fixed surfaces", power_ok)
	var zero_state := RB.make_state(M.v3(0,0,-300),M.v3(0,0,0),M.q_identity(),M.v3(0,0,0))
	var zero_rows := Aero.wing_strip_loads(zero_state,Air.compute(zero_state,M.v3(0,0,0)),ZERO,model,1.225)
	check("zero-flow diagnostics retain every station", zero_rows.size() == model.envelope.station_ys.size() and zero_rows[0].lift_n == 0.0)
	_spanwise_progression(model, reference)
	reject("null branch",func(p): p.positive = null)
	reject("unknown method",func(p): p.method = "viterna")
	reject("wrong section basis",func(p): p.basis = "2d-section")
	reject("unknown field",func(p): p.typo = 1)
	reject("empty source",func(p): p.positive.source = "")
	reject("unknown quantity field",func(p): p.positive.extra = 1)
	reject("wrong unit",func(p): p.positive.unit = "rad")
	reject("truncated row",func(p): p.positive.value.pop_back())
	reject("numeric string",func(p): p.positive.value[0] = "8")
	reject("nonfinite",func(p): p.positive.value[5] = NAN)
	reject("duplicate angles",func(p): p.positive.value[4] = 8.0)
	reject("increasing retention",func(p): p.positive.value[19] = 0.9)
	reject("negative drag",func(p): p.positive.value[10] = -0.1)
	reject("attached value discontinuity",func(p): p.positive.value[1] += 0.1)
	reject("invalid terminal angle",func(p): p.positive.value[24] = 89.0)
	reject("invalid terminal lift",func(p): p.positive.value[25] = 0.1)
	reject("invalid terminal drag",func(p): p.positive.value[26] = 0.5)
	reject("unsupported end slope",func(p): p.positive.value[21] = 0.00001)
	reject("progression above 1",func(p): p.spanwise_progression = {value = 1.5, unit = "1", kind = "derived", source = "test"})
	reject("negative progression",func(p): p.spanwise_progression = {value = -0.1, unit = "1", kind = "derived", source = "test"})
	reject("progression unit",func(p): p.spanwise_progression = {value = 1.0, unit = "deg", kind = "derived", source = "test"})
	reject("progression without source",func(p): p.spanwise_progression = {value = 1.0, unit = "1", kind = "derived", source = ""})
	reject("progression as bare number",func(p): p.spanwise_progression = 1.0)
	print("D8b-R2 polar: %d checks, %d failed" % [count,failures])
	quit(1 if failures else 0)


## D8b-R2d: optional spanwise stall progression on the same table. g = 0 must be the shared table bit for bit; g = 1
## must separate the more heavily loaded strips first, stay symmetric, passive and consistent with the wake input.
func _spanwise_progression(model: Dictionary, reference: Dictionary) -> void:
	var models := {}
	for gain in [0.0, 1.0]:
		var raw := Fixture.raw()
		raw.aero.wing_polar.spanwise_progression = {value = gain, unit = "1", kind = "derived",
			source = "test: spanwise progression %s" % gain}
		var data := AD.validate_and_derive(raw)
		check("spanwise progression %s accepted" % gain, data.ok)
		if not data.ok:
			printerr(data.errors)
			return
		models[gain] = data.model
	var full: Dictionary = models[1.0]
	var factors: PackedFloat64Array = full.envelope.wing_polar.strip_factor
	var rows: PackedFloat64Array = full.envelope.strip_row_sum
	var n := factors.size()
	var mean := 0.0
	var row_mean := 0.0
	for i in n:
		mean += factors[i] / n
		row_mean += rows[i] / n
	var follows := n == rows.size()
	for i in n:
		follows = follows and absf(factors[i] - rows[i] / row_mean) < 1e-12
	check("progression factors average 1 and equal the relative loading", absf(mean - 1.0) < 1e-12 and follows)
	check("rectangular Stik wing: root strips loaded above the tips", factors[n / 2] > 1.0 and factors[0] < 1.0
		and absf(factors[0] - factors[n - 1]) < 1e-12 and absf(factors[n / 2] - factors[n / 2 - 1]) < 1e-12)
	var identical := true
	var symmetric := true
	var passive := true
	var wake := true
	var attached := true
	for k in range(-170, 171, 5):
		var alpha := deg_to_rad(float(k))
		for rates in [M.v3(0, 0, 0), M.v3(0.13, -0.2, 0.1)]:
			var state := RB.make_state(M.v3(0, 0, -300), M.v3(25 * cos(alpha), 1.1 if rates[0] != 0.0 else 0.0, 25 * sin(alpha)),
				M.q_identity(), rates)
			var air := Air.compute(state, M.v3(0, 0, 0))
			identical = identical and Aero.loads(state, air, ZERO, models[0.0], 1.225) == Aero.loads(state, air, ZERO, model, 1.225)
			var loads := Aero.loads(state, air, ZERO, full, 1.225)
			if rates[0] == 0.0:
				symmetric = symmetric and absf(loads[3]) < 1e-9 and absf(loads[5]) < 1e-9 and absf(loads[1]) < 1e-9
			var strips := Aero.wing_strip_loads(state, air, ZERO, full, 1.225)
			var cl_mean := 0.0
			var wing := PackedFloat64Array([0., 0., 0., 0., 0., 0.])
			for row in strips:
				cl_mean += float(row.cl) / strips.size()
				for c in 3:
					wing[c] += row.force_body_n[c]
					wing[c + 3] += row.moment_body_nm[c]
			wake = wake and absf(cl_mean - Aero.wing_lift_coefficient(state, air, ZERO, full)) < 1e-12
			passive = passive and M.dot(wing.slice(0, 3), air.v_air) + M.dot(wing.slice(3, 6), state.slice(RB.RATE, RB.RATE + 3)) <= 1e-10
	for k in range(-30, 31):
		var alpha := deg_to_rad(k / 10.0)
		var state := RB.make_state(M.v3(0, 0, -300), M.v3(25 * cos(alpha), 0, 25 * sin(alpha)), M.q_identity(), M.v3(0, 0, 0))
		var air := Air.compute(state, M.v3(0, 0, 0))
		attached = attached and Aero.loads(state, air, ZERO, full, 1.225) == Aero.loads(state, air, ZERO, reference, 1.225)
	check("progression g = 0 is the shared table bit for bit", identical)
	check("progression symmetric without sideslip or rates", symmetric)
	check("progression wing loads passive with fixed surfaces", passive)
	check("progression wake input equals the same strip law", wake)
	check("progression leaves small-angle loads byte identical", attached)
	var onset := RB.make_state(M.v3(0, 0, -300), M.v3(25 * cos(deg_to_rad(14.0)), 0, 25 * sin(deg_to_rad(14.0))), M.q_identity(),
		M.v3(0, 0, 0))
	var onset_rows := Aero.wing_strip_loads(onset, Air.compute(onset, M.v3(0, 0, 0)), ZERO, full, 1.225)
	var shared_rows := Aero.wing_strip_loads(onset, Air.compute(onset, M.v3(0, 0, 0)), ZERO, model, 1.225)
	check("progression: at 14 deg the root strips are more separated than the tips, unlike the shared table",
		float(onset_rows[n / 2].stall_weight) > float(onset_rows[0].stall_weight) + 0.05
		and absf(float(shared_rows[n / 2].stall_weight) - float(shared_rows[0].stall_weight)) < 1e-12)
