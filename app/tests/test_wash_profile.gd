# E0b3b: bounded geometry and opt-in regularization. The fixture is NOT an aircraft calibration.
extends SceneTree
const AD = preload("res://physics/aircraft_data.gd")
const S = preload("res://physics/slipstream.gd")
const Aero = preload("res://physics/aero.gd")
const Air = preload("res://physics/air_data.gd")
const Prop = preload("res://physics/propulsion.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
var checks: int = 0
var failed: int = 0

static func quantity(value: Variant, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "estimated", source = "E0b3b test regularization; uncalibrated, not production aircraft data"}

static func geometry_quantity(value: Variant, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "derived", source = "research/propwash/e0b3b/derive_profile.py: neutral E0b2 polygons from estimated visual installation"}

static func combined_raw() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/jensen_ugly_stik_60.json"))
	var geometry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/stik_wash_profile.json"))
	geometry.hub = geometry_quantity(geometry.hub, "m")
	for piece: Dictionary in geometry.pieces:
		for field: String in ["root", "span_dir", "span", "area", "profile"]:
			var unit: String = "m2" if field == "area" else ("1" if field == "span_dir" else "m")
			piece[field] = geometry_quantity(piece[field], unit)
	raw.propulsion.propeller.thrust_angles = quantity([0.0, 0.0], "deg")
	geometry.wash_factor = quantity([1.0, 1.4], "1")
	geometry.swirl_factor = quantity(0.0, "1")
	geometry.vertical_drift = quantity(0.543, "1")
	geometry.edge_fraction = quantity(0.15, "1")
	geometry.reverse_fade = quantity([0.1, 0.2], "1")
	raw.propulsion.propeller.slipstream = geometry
	return raw

func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print("%s %s %s" % ["ok" if ok else "FAIL", label, detail])
	if not ok:
		failed += 1

func state(speed: float, alpha: float = 0.0) -> PackedFloat64Array:
	return PackedFloat64Array([0, 0, -100, speed*cos(alpha), 0, speed*sin(alpha), 1, 0, 0, 0, 0, 0, 0])

func deflections() -> Dictionary:
	return {elevator = 0.0, rudder = 0.0, aileron_left = 0.0, aileron_right = 0.0}

func load_at(model: Dictionary, s: PackedFloat64Array, d: Dictionary, rpm: float = -1.0) -> PackedFloat64Array:
	return S.loads(s, Air.compute(s, M.v3(0, 0, 0), 1.225), d, model, model.propulsion.max_rpm if rpm < 0 else rpm, 1.225, 0.3)

func error(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var worst: float = 0.0
	for i in a.size():
		if not is_finite(a[i]) or not is_finite(b[i]):
			return INF
		worst = maxf(worst, absf(a[i]-b[i]))
	return worst

func _initialize() -> void:
	var loaded: Dictionary = AD.validate_and_derive(combined_raw())
	check("profile fixture passes provenance and geometry validation", loaded.ok, str(loaded.errors))
	if not loaded.ok:
		quit(1)
		return
	var model: Dictionary = loaded.model
	validation()
	integrals(model)
	load_checks(model)
	print("E0b3b: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)

func validation() -> void:
	var rejected: bool = true
	for mutation in 13:
		var raw: Dictionary = combined_raw()
		var ss: Dictionary = raw.propulsion.propeller.slipstream
		match mutation:
			0: ss.edge_fraction.value = 0
			1: ss.reverse_fade.value = [0.2, 0.1]
			2: ss.reverse_fade.erase("source")
			3: ss.pieces[0].profile.value[0][1] = 0
			4:
				# Preserve area while overlapping the preceding interval: isolate the ordering check.
				ss.pieces[0].profile.value[1][0] -= 0.001
				ss.pieces[0].profile.value[1][1] -= 0.001
			5: ss.pieces[0].area.value *= 1.01
			6: ss.pieces[0].profile.value[0][2] = NAN
			7: ss.pieces[0].span_dir.value = [1.0, 0.0, 0.0]
			8: raw.propulsion.propeller.thrust_angles.value = [0.1, 0.0]
			9: ss.pieces[0].chords = quantity([0.1, 0.1], "m")
			10: ss.pieces[0].profile.value = []
			11: ss.pieces[0].root.value[0] = ss.hub.value[0]
			12: ss.erase("edge_fraction")
		var result: Dictionary = AD.validate_and_derive(raw)
		rejected = rejected and not result.ok
		if result.ok:
			print("accepted bad fixture ", mutation)
	check("13 invalid profiles/mode combinations are refused", rejected)

# Independent composite midpoint integration; no clipping or production quadrature is reused.
func dense(profile: PackedFloat64Array, along: float, d2: float, radius: float, edge: float) -> PackedFloat64Array:
	var sum_area: float = 0.0
	var sum_moment: float = 0.0
	var ri2: float = pow(radius*(1-edge), 2)
	var ro2: float = pow(radius*(1+edge), 2)
	for i in range(0, profile.size(), 4):
		var h: float = (profile[i+1]-profile[i])/1024.0
		for j in 1024:
			var f: float = (j+0.5)/1024.0
			var x: float = lerpf(profile[i], profile[i+1], f)
			var t: float = clampf((d2+pow(x+along, 2)-ri2)/(ro2-ri2), 0, 1)
			var weight: float = 1-t*t*(3-2*t)
			var area: float = h*lerpf(profile[i+2], profile[i+3], f)*weight
			sum_area += area
			sum_moment += x*area
	return PackedFloat64Array([sum_area, sum_moment])

func integrals(model: Dictionary) -> void:
	var worst: float = 0.0
	var bounds: bool = true
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 30302
	for piece: Dictionary in model.propulsion.slipstream.pieces:
		for i in 24:
			var along: float = rng.randf_range(-0.35, 0.15)
			var d2: float = pow(rng.randf_range(0.0, 0.17), 2)
			var radius: float = rng.randf_range(0.08, 0.19)
			var moments: PackedFloat64Array = S.profile_moments(piece.profile, along, d2, radius, 0.15)
			worst = maxf(worst, error(moments, dense(piece.profile, along, d2, radius, 0.15)))
			bounds = bounds and moments[0] >= 0 and moments[0] <= piece.area+1e-12
			if moments[0] > 0:
				bounds = bounds and moments[1]/moments[0] >= 0 and moments[1]/moments[0] <= piece.span
		var full: PackedFloat64Array = S.profile_moments(piece.profile, 0.0, 0.0, 2.0, 0.15)
		check("full coverage preserves polygon area: "+piece.surface, absf(full[0]-piece.area) < 1e-12)
	check("72 weighted integrals agree with independent dense integration", worst < 2e-8, str(worst))
	check("weighted area and centroid stay within geometry bounds", bounds)
	# A rectangle tangent at an interior span point exercises the strongest hard-circle singularity.
	var rectangle: PackedFloat64Array = PackedFloat64Array([0.0, 0.4, 0.2, 0.2])
	var radius: float = 0.1
	var edge: float = 0.15
	var boundary: float = radius*(1+edge)
	var values: Array[float] = []
	for h: float in [1e-4, 5e-5]:
		var area: float = S.profile_moments(rectangle, -0.2, pow(boundary-h, 2), radius, edge)[0]
		values.append(area/h)
	check("outer tangency has vanishing load derivative", values[1] < values[0]*0.4 and values[1] < 1e-3, str(values))
	check("outer boundary returns exact zero", S.profile_moments(rectangle, -0.2, boundary*boundary, radius, edge) == PackedFloat64Array([0, 0]))

func load_checks(model: Dictionary) -> void:
	var d: Dictionary = deflections()
	var prop: Dictionary = model.propulsion
	var vi0: float = prop.max_rpm/60.0*prop.diameter*sqrt(2*prop.ct[1]/PI)
	var zero: PackedFloat64Array = PackedFloat64Array([0, 0, 0, 0, 0, 0])
	check("reverse cutoff removes every load component", load_at(model, state(-0.3*vi0), d) == zero)
	check("stopped propeller is exact zero", load_at(model, state(15), d, 0.0) == zero)
	var no_wash: Dictionary = model.duplicate(true)
	no_wash.propulsion.slipstream.wash_factor = PackedFloat64Array([0, 0])
	check("zero wash coefficients preserve exact zero", load_at(no_wash, state(15), d) == zero)
	var reverse_ok: bool = true
	for ratio: float in [0.1, 0.2]:
		var speed: float = -ratio*vi0
		var h: float = 1e-5*vi0
		var centre: PackedFloat64Array = load_at(model, state(speed), d)
		var left: PackedFloat64Array = load_at(model, state(speed-h), d)
		var right: PackedFloat64Array = load_at(model, state(speed+h), d)
		reverse_ok = reverse_ok and error(left, right) < 0.01
		for i in 6:
			reverse_ok = reverse_ok and absf((right[i]-2*centre[i]+left[i])/h) < 0.02
	check("reverse fade endpoints have continuous loads and matching slopes", reverse_ok)
	d.elevator = -0.1
	var up: PackedFloat64Array = load_at(model, state(0), d)
	d.elevator = 0.1
	var down: PackedFloat64Array = load_at(model, state(0), d)
	check("static elevator produces differential pitch", up[4] > down[4]+0.1)
	d.elevator = 0.0
	d.rudder = -0.1
	var left: PackedFloat64Array = load_at(model, state(0), d)
	d.rudder = 0.1
	var right: PackedFloat64Array = load_at(model, state(0), d)
	check("static rudder produces opposite yaw signs", left[5]*right[5] < 0)
	d.rudder = 0.0
	check("mirrored horizontal profiles cancel roll in axial wash", absf(load_at(model, state(0), d)[3]) < 1e-12)
	var finite: bool = true
	var equivalent: float = 0.0
	for i in 181:
		var s: PackedFloat64Array = state(20, deg_to_rad(-180+2*i))
		s[RB.RATE] = 0.4
		s[RB.RATE+1] = -0.2
		var air: Dictionary = Air.compute(s, M.v3(0, 0, 0), 1.225)
		var actual: PackedFloat64Array = load_at(model, s, d)
		for x in actual:
			finite = finite and is_finite(x)
		var expected: PackedFloat64Array = zero.duplicate()
		var tq: PackedFloat64Array = Prop.thrust_torque(air.v_air, prop.max_rpm, prop, 1.225)
		var w: Dictionary = S.wake(air.v_air, tq[0], tq[1], prop, 1.225)
		if S.reverse_weight(air.v_air, prop.max_rpm, prop) == 0.0:
			continue
		for piece: Dictionary in prop.slipstream.pieces:
			var im: Dictionary = S.immersion(piece, w, prop.slipstream.hub, prop, air.v_air, air.V, model)
			var extra: PackedFloat64Array = M.sub(M.scale(Prop.axis(prop), w.dv), im.swirl)
			var inc: PackedFloat64Array = Aero.tail_surface_increment(air.v_air, s.slice(RB.RATE, RB.RATE+3), d, model, piece.surface, im.area, im.shift, extra, 1.225, 0.3)
			for j in 6:
				expected[j] += inc[j]
			if piece.surface == "horizontal":
				check_height = check_height and im.shift[2] == 0.0
		var fade: float = S.reverse_weight(air.v_air, prop.max_rpm, prop)
		for j in 6:
			expected[j] *= fade
		equivalent = maxf(equivalent, error(actual, expected))
	check("full-angle/rate sweep is finite", finite)
	check("scalar loads agree with independent helper composition", equivalent < 1e-10, str(equivalent))
	check("horizontal coverage height does not move aerodynamic pressure arm", check_height)
	check("default Stik remains unconfigured", AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json").model.propulsion.get("slipstream", {}).is_empty())

var check_height: bool = true
