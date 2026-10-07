# E0b3a: one E0a2 tail law for free and washed flow, using the session's held wing CL.
# Manufactured rectangular wash pieces exercise compatibility, NOT a Stik geometry or wash calibration.
extends SceneTree
const AD = preload("res://physics/aircraft_data.gd")
const Aero = preload("res://physics/aero.gd")
const Air = preload("res://physics/air_data.gd")
const Slipstream = preload("res://physics/slipstream.gd")
const Dynamics = preload("res://physics/dynamics.gd")
const Propulsion = preload("res://physics/propulsion.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const Flight = preload("res://sim/flight_session.gd")
const RHO: float = 1.225
var _checks: int = 0
var _failed: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print("%s %s %s" % ["ok" if condition else "FAIL", label, detail])
	if not condition:
		_failed += 1


static func _q(value: Variant, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "estimated", source = "E0b3a manufactured test geometry; not a Stik wash calibration"}


static func combined_raw() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/jensen_ugly_stik_60.json"))
	var prop: Dictionary = raw.propulsion.propeller
	prop.thrust_angles = _q([0.0, 0.0], "deg")
	var pieces: Array = []
	for entry: Array in [["horizontal", 1.0], ["horizontal", -1.0], ["vertical", 1.0]]:
		var vertical: bool = entry[0] == "vertical"
		var tail: Dictionary = raw.aero.surfaces[entry[0]]
		pieces.append({surface = entry[0], area = _q(0.016, "m2"),
			root = _q([tail.position.value[0], 0.0, 0.0 if vertical else -0.04064], "m"),
			span_dir = _q([0.0, 0.0, 1.0] if vertical else [0.0, entry[1], 0.0], "1"),
			span = _q(0.08, "m"), chords = _q([0.2, 0.2], "m")})
	prop.slipstream = {hub = _q([-0.293276, 0.0, 0.0], "m"),
		wash_factor = _q([1.0, 1.0], "1"), swirl_factor = _q(0.0, "1"),
		vertical_drift = _q(0.0, "1"), pieces = pieces}
	return raw


func _initialize() -> void:
	var loaded: Dictionary = AD.validate_and_derive(combined_raw())
	_check("loader accepts explicit downwash + slipstream", loaded.ok, str(loaded.errors))
	if not loaded.ok:
		quit(1)
		return
	var model: Dictionary = loaded.model
	_local_agreement(model)
	_authority(model)
	_scalar_agreement(model)
	_session_lag(model)
	_check("production Stik remains unconfigured", AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json").model.propulsion.get("slipstream", {}).is_empty())
	print("E0b3a: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)


func _state(speed: float, alpha: float) -> PackedFloat64Array:
	return PackedFloat64Array([0, 0, -100, speed*cos(alpha), 0, speed*sin(alpha), 1, 0, 0, 0, 0, 0, 0])


func _deflections() -> Dictionary:
	return {elevator = 0.0, rudder = 0.0, aileron_left = 0.0, aileron_right = 0.0}


func _error(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var worst: float = 0.0
	for i in a.size():
		if not is_finite(a[i]) or not is_finite(b[i]):
			return INF
		worst = maxf(worst, absf(a[i] - b[i]))
	return worst


func _local_agreement(model: Dictionary) -> void:
	var without_tail: Dictionary = model.duplicate(true)
	without_tail.surfaces.horizontal.area = 0.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 300301
	var worst: float = 0.0
	var zero: bool = true
	var passive: bool = true
	for i in 300:
		var s: PackedFloat64Array = _state(rng.randf_range(0.0, 35.0), rng.randf_range(-0.4, 0.5))
		s[RB.VEL+1] = rng.randf_range(-4.0, 4.0)
		for axis in 3:
			s[RB.RATE+axis] = rng.randf_range(-2.0, 2.0)
		var d: Dictionary = _deflections()
		d.elevator = rng.randf_range(-0.4, 0.4)
		var air: Dictionary = Air.compute(s, M.v3(0, 0, 0), RHO)
		var lag: float = rng.randf_range(-0.6, 1.2)
		var expected: PackedFloat64Array = Aero._local_loads(s, air, d, model, RHO, lag)
		var no_tail: PackedFloat64Array = Aero._local_loads(s, air, d, without_tail, RHO, lag)
		for k in 6:
			expected[k] -= no_tail[k]
		var v: PackedFloat64Array = air.v_air
		var rates: PackedFloat64Array = s.slice(RB.RATE, RB.RATE+3)
		var load: PackedFloat64Array = Aero.tail_surface_load(v, rates, d, model, "horizontal",
			model.surfaces.horizontal.area, M.v3(0, 0, 0), M.v3(0, 0, 0), RHO, lag)
		worst = maxf(worst, _error(load, expected))
		var delta: PackedFloat64Array = Aero.tail_surface_increment(v, rates, d, model, "horizontal",
			0.02, M.v3(0.01, 0.02, 0.005), M.v3(0, 0, 0), RHO, lag)
		zero = zero and delta == PackedFloat64Array([0, 0, 0, 0, 0, 0])
		var power: float = 0.0
		for k in 3:
			power += load[k]*v[k] + load[k+3]*rates[k]
		passive = passive and is_finite(power) and power <= 1e-10
	_check("tail helper matches existing local tail in 300 held-lag/rate/stall cases", worst < 1e-10, "worst " + String.num_scientific(worst))
	_check("zero added velocity gives exactly zero increment", zero)
	_check("free tail removes energy including rotational work", passive)


func _authority(model: Dictionary) -> void:
	var d: Dictionary = _deflections()
	var tail: Dictionary = model.surfaces.horizontal
	var v: PackedFloat64Array = M.v3(15, 0, 0)
	var lag: float = float(tail.free_incidence) / float(tail.downwash_per_cl)
	var h: float = 1e-6
	d.elevator = h
	var plus: PackedFloat64Array = Aero.tail_surface_load(v, M.v3(0, 0, 0), d, model, "horizontal", tail.area, M.v3(0, 0, 0), M.v3(0, 0, 0), RHO, lag)
	d.elevator = -h
	var minus: PackedFloat64Array = Aero.tail_surface_load(v, M.v3(0, 0, 0), d, model, "horizontal", tail.area, M.v3(0, 0, 0), M.v3(0, 0, 0), RHO, lag)
	var derivative: float = -(plus[2] - minus[2]) / (2*h)
	var expected: float = 0.5*RHO*225*float(tail.area)*float(tail.free_slope)*float(tail.elevator_tau)
	_check("elevator derivative uses free slope times elevator tau", absf(derivative/expected - 1.0) < 1e-9)
	# A stationary aircraft gets control authority from a powered, manufactured wash fixture.
	var s: PackedFloat64Array = _state(0.0, 0.0)
	var air: Dictionary = Air.compute(s, M.v3(0, 0, 0), RHO)
	d.elevator = -0.05
	var up: PackedFloat64Array = Slipstream.loads(s, air, d, model, model.propulsion.max_rpm, RHO, 0.0)
	d.elevator = 0.05
	var down: PackedFloat64Array = Slipstream.loads(s, air, d, model, model.propulsion.max_rpm, RHO, 0.0)
	_check("static powered elevator has nose-up/nose-down differential authority", up[4] > down[4] + 0.1)
	d.rudder = 0.05
	var right: PackedFloat64Array = Slipstream.loads(s, air, d, model, model.propulsion.max_rpm, RHO, 0.0)
	d.rudder = -0.05
	var left: PackedFloat64Array = Slipstream.loads(s, air, d, model, model.propulsion.max_rpm, RHO, 0.0)
	_check("static powered rudder retains opposite signed yaw authority", right[5]*left[5] < 0 and absf(right[5]-left[5]) > 0.1)


func _scalar_agreement(model: Dictionary) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 300302
	var worst: float = 0.0
	var immersed: int = 0
	var quasi_same: bool = true
	for i in 300:
		var s: PackedFloat64Array = _state(rng.randf_range(0.0, 25.0), rng.randf_range(-0.1, 0.1))
		for axis in 3:
			s[RB.RATE+axis] = rng.randf_range(-1.0, 1.0)
		var d: Dictionary = _deflections()
		d.elevator = rng.randf_range(-0.15, 0.15)
		d.rudder = rng.randf_range(-0.15, 0.15)
		var air: Dictionary = Air.compute(s, M.v3(0, 0, 0), RHO)
		var lag: float = rng.randf_range(-0.4, 0.8)
		var prop: Dictionary = model.propulsion
		var tq: PackedFloat64Array = Propulsion.thrust_torque(air.v_air, prop.max_rpm, prop, RHO)
		var w: Dictionary = Slipstream.wake(air.v_air, tq[0], tq[1], prop, RHO)
		var expected: PackedFloat64Array = PackedFloat64Array([0, 0, 0, 0, 0, 0])
		for piece: Dictionary in prop.slipstream.pieces:
			var im: Dictionary = Slipstream.immersion(piece, w, prop.slipstream.hub, prop, air.v_air, air.V, model)
			if im.area <= 0:
				continue
			immersed += 1
			var extra: PackedFloat64Array = M.sub(M.scale(Propulsion.axis(prop), w.dv), im.swirl)
			var inc: PackedFloat64Array = Aero.tail_surface_increment(air.v_air, s.slice(RB.RATE, RB.RATE+3), d, model,
				piece.surface, im.area, im.shift, extra, RHO, lag)
			for k in 6:
				expected[k] += inc[k]
		worst = maxf(worst, _error(Slipstream.loads(s, air, d, model, prop.max_rpm, RHO, lag), expected))
		var cl: float = Aero.wing_lift_coefficient(s, air, d, model)
		quasi_same = quasi_same and Slipstream.loads(s, air, d, model, prop.max_rpm, RHO).to_byte_array() == Slipstream.loads(s, air, d, model, prop.max_rpm, RHO, cl).to_byte_array()
	_check("scalar washed-minus-free loads match the tested tail law", worst < 1e-10 and immersed > 500, "worst %s; %d immersed pieces" % [String.num_scientific(worst), immersed])
	_check("NAN solves instantaneous wing CL exactly", quasi_same)


func _session_lag(model: Dictionary) -> void:
	var flight: Node = Flight.new()
	flight.setup()
	root.add_child(flight)
	flight.input_enabled = false
	# Inject validated synthetic wash into an already settled session: no aircraft/configuration is shipped.
	flight.aircraft.model = model
	var s: PackedFloat64Array = _state(15.0, 0.03)
	var aux: PackedFloat64Array = flight.sim.aux.duplicate()
	var index: int = flight.downwash_index()
	aux[index] = 0.8
	flight.sim.aux = aux
	var d: Dictionary = flight._deflections(aux)
	var air: Dictionary = Air.compute(s, M.v3(0, 0, 0), RHO)
	var expected: PackedFloat64Array = Aero.loads(s, air, d, model, RHO, aux[index])
	var propulsion: PackedFloat64Array = Propulsion.loads(air.v_air, aux[0], model.propulsion, RHO)
	var wash: PackedFloat64Array = Slipstream.loads(s, air, d, model, aux[0], RHO, aux[index])
	for k in 6:
		expected[k] += propulsion[k]
		expected[k] += wash[k]
	_check("real session feeds held lag to both aero and wash", _error(flight._loads(s, 0.0), expected) < 1e-12)
	var quasi: PackedFloat64Array = Slipstream.loads(s, air, d, model, aux[0], RHO)
	_check("lag plumbing test is not vacuous", _error(wash, quasi) > 0.01)
	var disabled: Dictionary = model.duplicate(true)
	disabled.propulsion.erase("slipstream")
	var baseline: PackedFloat64Array = Aero.loads(s, air, d, disabled, RHO, aux[index])
	for k in 6:
		baseline[k] += propulsion[k]
	_check("absent configuration leaves Dynamics byte-identical", Dynamics.loads(s, disabled, d, aux[0], RHO, M.v3(0, 0, 0), aux[index]).to_byte_array() == baseline.to_byte_array())
	_check("standalone absent/stopped wash returns exactly zero", Slipstream.loads(s, air, d, disabled, aux[0], RHO) == PackedFloat64Array([0, 0, 0, 0, 0, 0]) and Slipstream.loads(s, air, d, model, 0.0, RHO, aux[index]) == PackedFloat64Array([0, 0, 0, 0, 0, 0]))
	var no_wake: Dictionary = model.duplicate(true)
	no_wake.propulsion.slipstream.wash_factor = PackedFloat64Array([0.0, 0.0])
	_check("zero wash factors give exactly zero increment despite held lag", Slipstream.loads(s, air, d, no_wake, aux[0], RHO, aux[index]) == PackedFloat64Array([0, 0, 0, 0, 0, 0]))
	flight.free()
