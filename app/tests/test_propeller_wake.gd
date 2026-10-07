# E0b1: ideal actuator-disc wake, checked by conservation laws rather than a second wake implementation.
# Scope: nonnegative axial inflow/thrust, positive density/diameter; no real-tail calibration or reverse-flow claim.
extends SceneTree

const Slipstream = preload("res://physics/slipstream.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const Propulsion = preload("res://physics/propulsion.gd")
var _count: int = 0
var _failures: int = 0


func _initialize() -> void:
	_static_limit()
	_conservation()
	_zero_thrust()
	_shaft_projection()
	_operating_points()
	print("E0b1 wake: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _ideal_prop(diameter: float) -> Dictionary:
	# A test-only ideal wake: k_w = 2 means no axial decay. Not a Stik configuration.
	return {diameter = diameter, slipstream = {wash_factor = PackedFloat64Array([2.0, 2.0]), swirl_factor = 0.0}}


func _check(label: String, ok: bool, detail: String = "") -> void:
	_count += 1
	print("%s %s %s" % ["ok" if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _near(a: float, b: float) -> bool:
	return is_finite(a) and is_finite(b) and absf(a - b) <= 1e-12 * maxf(1.0, absf(b))


func _static_limit() -> void:
	var rho: float = 1.225
	var diameter: float = 0.3048
	var thrust: float = 41.25 # N, rounded historical operating point; not measured Stik thrust.
	var area: float = PI * diameter * diameter / 4.0
	var prop: Dictionary = _ideal_prop(diameter)
	var v: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
	var before: PackedByteArray = var_to_bytes([v, prop])
	var w: Dictionary = Slipstream.wake(v, thrust, 0.0, prop, rho)
	_check("static far speed sqrt(2T/rhoA)", _near(w.vs, sqrt(2.0 * thrust / (rho * area))))
	_check("static contraction R/sqrt(2)", _near(w.rs, diameter / (2.0 * sqrt(2.0))))
	_check("static dynamic pressure T/A", _near(0.5 * rho * w.dv * w.dv, thrust / area))
	_check("static disc speed is half far speed", _near(2.0 * w.w, w.vs))
	_check("wake leaves inputs unchanged", before == var_to_bytes([v, prop]))
	_check("wake repeats exactly", var_to_bytes(w) == var_to_bytes(Slipstream.wake(v, thrust, 0.0, prop, rho)))


func _conservation() -> void:
	var momentum: bool = true
	var pressure: bool = true
	var continuity: bool = true
	var ratio: bool = true
	var bounds: bool = true
	var cases: int = 0
	for rho: float in [0.8, 1.225]:
		for diameter: float in [0.15, 0.3048, 0.66]:
			var area: float = PI * diameter * diameter / 4.0
			var prop: Dictionary = _ideal_prop(diameter)
			for u: float in [0.0, 0.01, 1.0, 5.0, 15.0, 40.0]:
				for thrust: float in [0.01, 3.0, 41.25, 320.0]:
					var w: Dictionary = Slipstream.wake(PackedFloat64Array([u, 0.0, 0.0]), thrust, 0.0, prop, rho)
					var disc_speed: float = u + w.w
					var far_speed: float = u + w.dv
					momentum = momentum and _near(rho * area * disc_speed * (far_speed - u), thrust)
					pressure = pressure and _near(0.5 * rho * (far_speed * far_speed - u * u), thrust / area)
					continuity = continuity and _near(PI * w.rs * w.rs * far_speed, area * disc_speed)
					bounds = bounds and w.w >= 0.0 and w.rs >= diameter / (2.0 * sqrt(2.0)) - 1e-14 and w.rs <= diameter / 2.0
					if u > 0.0:
						# Independent nondimensional identity, using a nominal n only to define Ct and J.
						var n: float = 150.0
						var ct: float = thrust / (rho * n * n * pow(diameter, 4))
						var j: float = u / (n * diameter)
						ratio = ratio and _near(pow(far_speed / u, 2), 1.0 + 8.0 * ct / (PI * j * j))
					cases += 1
	_check("momentum T = mass flow times velocity gain", momentum, "%d cases" % cases)
	_check("pressure gain = disc loading", pressure)
	_check("contracted wake conserves volume flow", continuity)
	_check("q_far/q_inf = 1 + 8Ct/(pi J^2)", ratio)
	_check("positive induction and physical contraction bounds", bounds)


func _zero_thrust() -> void:
	var prop: Dictionary = _ideal_prop(0.3048)
	var at_rest: Dictionary = Slipstream.wake(PackedFloat64Array([0.0, 0.0, 0.0]), 0.0, 0.0, prop, 1.225)
	var finite: bool = true
	for value: float in at_rest.values():
		finite = finite and is_finite(value)
	_check("zero thrust at rest is finite and adds no flow", finite and at_rest.w == 0.0 and at_rest.dv == 0.0 and at_rest.swirl == 0.0)
	var moving: Dictionary = Slipstream.wake(PackedFloat64Array([15.0, 0.0, 0.0]), 0.0, 0.0, prop, 1.225)
	_check("zero thrust in forward flow has no contraction or induction", moving.w == 0.0 and moving.dv == 0.0 and _near(moving.rs, 0.1524))


func _shaft_projection() -> void:
	var axial: Dictionary = _ideal_prop(0.3048)
	var tilted: Dictionary = axial.duplicate(true)
	tilted.axis = PackedFloat64Array([0.8, 0.6, 0.0])
	var a: Dictionary = Slipstream.wake(PackedFloat64Array([5.0, 7.0, 3.0]), 38.37, 0.0, axial, 1.225)
	# Rotate [5, 7, 3] and the shaft together: the same 5 m/s axial flow.
	var b: Dictionary = Slipstream.wake(PackedFloat64Array([-0.2, 8.6, 3.0]), 38.37, 0.0, tilted, 1.225)
	_check("wake uses shaft projection, not body x or total speed", _near(a.u, 5.0) and _near(b.u, 5.0) and _near(a.dv, b.dv) and _near(a.rs, b.rs))


func _operating_points() -> void:
	var loaded: Dictionary = AircraftData.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	_check("Stik fixture loads", loaded.ok, str(loaded.errors))
	if not loaded.ok:
		return
	var model: Dictionary = loaded.model
	var prop: Dictionary = model.propulsion.duplicate(true)
	_check("Stik remains opted out of wash pending E0b2 onward", prop.get("slipstream", {}).is_empty())
	prop.slipstream = _ideal_prop(prop.diameter).slipstream
	var rho: float = 1.225
	for u: float in [5.0, 15.0]:
		var velocity: PackedFloat64Array = PackedFloat64Array([u, 0.0, 0.0])
		var tq: PackedFloat64Array = Propulsion.thrust_torque(velocity, prop.max_rpm, prop, rho)
		var full: Dictionary = Slipstream.wake(velocity, tq[0], 0.0, prop, rho)
		var full_ratio: float = pow((u + full.dv) / u, 2)
		_check("full fixed rpm at %.0f m/s" % u, absf(full_ratio - (35.3 if u == 5.0 else 4.24)) < 0.1,
			"T=%.5f N; ideal pressure ratio=%.5f" % [tq[0], full_ratio])
	# Level-flight polar estimate, not a powered six-DOF trim or measured performance.
	var q: float = 0.5 * rho * 15.0 * 15.0
	var cl: float = model.mass_kg * 9.80665 / (q * model.reference.S)
	var drag: float = q * model.reference.S * (model.aero.CD0 + model.aero.k_induced * pow(cl - model.aero.CL_minD, 2))
	var level: Dictionary = Slipstream.wake(PackedFloat64Array([15.0, 0.0, 0.0]), drag, 0.0, prop, rho)
	var level_ratio: float = pow((15.0 + level.dv) / 15.0, 2)
	_check("15 m/s level-flight thrust gives about 1.30, not full power", absf(level_ratio - 1.30) < 0.01,
		"T=D=%.5f N; ideal pressure ratio=%.5f" % [drag, level_ratio])
