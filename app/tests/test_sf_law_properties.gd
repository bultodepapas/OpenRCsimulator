# SF-06: every load law runs the property harness (tests/law_properties.gd). A law passes each registered
# property or is listed with the ID of the open work that explains it; an unexplained failure fails the run.
# Laws: each flyable airplane's aerodynamics and propulsion, its landing gear, the rotorcraft airframe and the
# RC ground vehicle's state derivative. Scales come from each law's own forward-flight magnitude.
extends SceneTree

const LP := preload("res://tests/law_properties.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Ground := preload("res://physics/ground_contact.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const GroundSession := preload("res://sim/ground_vehicle/session.gd")
const Airframe := preload("res://physics/rotorcraft/airframe.gd")
const RotorData := preload("res://physics/rotorcraft_data.gd")

const RHO := 1.225
const V := 20.0
const ZERO_D := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
const X := [1.0, 0.0, 0.0]
const Y := [0.0, 1.0, 0.0]
const Z := [0.0, 0.0, 1.0]

## "law|property": "open ID — why". A listed failure is reported as EXEMPT, not as a failure.
const EXEMPT: Dictionary = {}

var _checks := 0
var _failures := 0
var _exempt := 0
var _rows: PackedStringArray = PackedStringArray()
var _zero_wind := PackedFloat64Array([0.0, 0.0, 0.0])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var samples: Array = LP.samples(2026, 24, V, 3.0)
	var winds: Array = [PackedFloat64Array([5.0, 0.0, 0.0]), PackedFloat64Array([0.0, -4.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 3.0]), PackedFloat64Array([3.0, -2.0, 1.0])]
	for id in Catalog.airplane_flyable_ids():
		var loaded: Dictionary = AD.load_file(str(Catalog.entry(id).data))
		if not loaded.get("ok", false):
			_record(id + " data", "load", false, INF, str(loaded.get("errors", [])))
			continue
		var model: Dictionary = loaded.model
		_register_aero(id, model, samples, winds)
		_register_propulsion(id, model, samples)
		if model.has("landing_gear"):
			_register_ground(id, model, samples)
	_register_truck(samples)
	_register_rotorcraft_airframe(samples)
	for row in _rows:
		print(row)
	print("SF-06 law properties: %d checks, %d failed, %d exempt" % [_checks, _failures, _exempt])
	quit(1 if _failures > 0 else 0)


func _record(law: String, property: String, ok: bool, worst: float, detail: String) -> void:
	_checks += 1
	var key: String = law + "|" + property
	var status: String = "PASS"
	if not ok:
		if EXEMPT.has(key):
			_exempt += 1
			status = "EXEMPT(" + str(EXEMPT[key]) + ")"
		else:
			_failures += 1
			status = "FAIL"
	_rows.append("%-6s %-44s %-22s worst=%s %s" % [status, law, property, LP.sci(worst), detail])


func _state(v: PackedFloat64Array, rates: PackedFloat64Array, down: float = -100.0) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, down), v, M.q_identity(), rates)


func _scale(law: Callable) -> float:
	var out: PackedFloat64Array = law.call(PackedFloat64Array([V, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var worst := 1.0
	for x in out:
		if is_finite(x):
			worst = maxf(worst, absf(x))
	return worst


func _continuity_set(name: String, law: Callable, scale: float, rates: PackedFloat64Array, cases: Array) -> void:
	for item: Array in cases:
		var limit: PackedFloat64Array = PackedFloat64Array(item[1])
		var a: PackedFloat64Array = PackedFloat64Array(item[2])
		var b: PackedFloat64Array = PackedFloat64Array(item[3])
		var r: Dictionary = LP.continuity(law, limit, a, b, rates, scale)
		_record(name, "continuity " + str(item[0]), r.ok, r.worst, r.detail)


func _register_aero(id: String, model: Dictionary, samples: Array, winds: Array) -> void:
	var name := id + " aero"
	var law := func(v: PackedFloat64Array, rates: PackedFloat64Array) -> PackedFloat64Array:
		var s := _state(v, rates)
		return Aero.loads(s, Air.compute(s, _zero_wind, RHO), ZERO_D, model, RHO)
	var law_wind := func(v: PackedFloat64Array, rates: PackedFloat64Array, wind: PackedFloat64Array) -> PackedFloat64Array:
		var s := _state(v, rates)
		return Aero.loads(s, Air.compute(s, wind, RHO), ZERO_D, model, RHO)
	var scale := _scale(law)
	var zero := PackedFloat64Array([0.0, 0.0, 0.0])
	_continuity_set(name, law, scale, zero, [
		["spanwise +x/+z", [0.0, V, 0.0], X, Z], ["spanwise +x/-x", [0.0, V, 0.0], X, [-1.0, 0.0, 0.0]],
		["spanwise +z/-z", [0.0, V, 0.0], Z, [0.0, 0.0, -1.0]], ["vertical +x/+y", [0.0, 0.0, V], X, Y],
		["vertical +y/-y", [0.0, 0.0, V], Y, [0.0, -1.0, 0.0]], ["rest +x/+y", [0.0, 0.0, 0.0], X, Y],
		["forward +y/+z", [V, 0.0, 0.0], Y, Z]])
	var r: Dictionary = LP.finite(law, samples)
	_record(name, "finite", r.ok, r.worst, r.detail)
	r = LP.rest(law, scale)
	_record(name, "rest", r.ok, r.worst, r.detail)
	r = LP.galilean(law_wind, samples, winds, scale)
	_record(name, "galilean", r.ok, r.worst, r.detail)
	r = LP.mirror(law, samples, scale)
	_record(name, "mirror", r.ok, r.worst, r.detail)
	r = LP.passive_translational(law, samples, scale)
	_record(name, "passive_translational", r.ok, r.worst, r.detail)


func _register_propulsion(id: String, model: Dictionary, samples: Array) -> void:
	var prop: Dictionary = model.propulsion
	var rpm: float = 0.7 * float(prop.get("max_rpm", 0.0))
	if rpm <= 0.0:
		_record(id + " propulsion", "registered", true, 0.0, "no max_rpm in this installation; not registered")
		return
	var name := id + " propulsion"
	var law := func(v: PackedFloat64Array, _rates: PackedFloat64Array) -> PackedFloat64Array:
		return Propulsion.loads(v, rpm, prop, RHO)
	var scale := _scale(law)
	var zero := PackedFloat64Array([0.0, 0.0, 0.0])
	_continuity_set(name, law, scale, zero, [
		["forward +y/+z", [V, 0.0, 0.0], Y, Z], ["rest +x/-x", [0.0, 0.0, 0.0], X, [-1.0, 0.0, 0.0]],
		["crossflow +x/-x", [0.0, 5.0, 0.0], X, [-1.0, 0.0, 0.0]], ["rest +y/+z", [0.0, 0.0, 0.0], Y, Z]])
	var r: Dictionary = LP.finite(law, samples)
	_record(name, "finite", r.ok, r.worst, r.detail)


func _register_ground(id: String, model: Dictionary, samples: Array) -> void:
	var name := id + " landing gear"
	var gear: Dictionary = model.landing_gear
	var probe := _state(PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]), 0.0)
	var compressions: PackedFloat64Array = Ground.compressions(probe, gear)
	if compressions.is_empty():
		_record(name, "registered", true, 0.0, "no contacts; not registered")
		return
	var deepest := -1e30
	for c in compressions:
		deepest = maxf(deepest, c)
	var down: float = -deepest + 0.02 # every wheel touching, the deepest compressed by 2 cm
	var law := func(v: PackedFloat64Array, rates: PackedFloat64Array) -> PackedFloat64Array:
		return Ground.loads(_state(v, rates, down), gear)
	var scale := _scale(law)
	var zero := PackedFloat64Array([0.0, 0.0, 0.0])
	_continuity_set(name, law, scale, zero, [
		["rest +x/+y", [0.0, 0.0, 0.0], X, Y], ["rest +x/-x", [0.0, 0.0, 0.0], X, [-1.0, 0.0, 0.0]],
		["rest +y/-y", [0.0, 0.0, 0.0], Y, [0.0, -1.0, 0.0]], ["rolling +y/-y", [5.0, 0.0, 0.0], Y, [0.0, -1.0, 0.0]]])
	var ground_samples: Array = []
	for sample: Array in samples:
		var v: PackedFloat64Array = sample[0].duplicate()
		v[2] = 0.0 # stay on the ground plane for the ground-only properties
		ground_samples.append([v, sample[1]])
	var r: Dictionary = LP.finite(law, ground_samples)
	_record(name, "finite", r.ok, r.worst, r.detail)
	r = LP.mirror(law, ground_samples, scale)
	_record(name, "mirror", r.ok, r.worst, r.detail)
	# Friction opposes the wheel's own velocity. Under body rates that differs from the CG velocity by ω × r, so
	# per-axis passivity at the CG is a pure-translation property.
	var translation_samples: Array = []
	for sample: Array in ground_samples:
		translation_samples.append([sample[0], PackedFloat64Array([0.0, 0.0, 0.0])])
	r = LP.passive(law, translation_samples, PackedInt64Array([0, 1]), scale)
	_record(name, "passive x,y translation", r.ok, r.worst, r.detail)


func _register_truck(samples: Array) -> void:
	var name := "ground-vehicle derivative"
	var session: Node = GroundSession.new()
	root.add_child(session)
	if not session.prepare_default():
		_record(name, "registered", false, INF, session.load_error)
		session.free()
		return
	var spawn: PackedFloat64Array = session.state_snapshot()
	var model: Dictionary = session._model
	var road: Callable = session._road
	var law := func(v: PackedFloat64Array, rates: PackedFloat64Array) -> PackedFloat64Array:
		var s := spawn.duplicate()
		for i in 3:
			s[RB.VEL + i] = v[i]
			s[RB.RATE + i] = rates[i]
		return VehicleDynamics.derivative(s, model, VehicleDynamics.DEFAULT_CONTROLS, road)
	var scale := 9.80665 # an acceleration scale for a state derivative
	var zero := PackedFloat64Array([0.0, 0.0, 0.0])
	_continuity_set(name, law, scale, zero, [
		["rest +x/+y", [0.0, 0.0, 0.0], X, Y], ["rest +x/-x", [0.0, 0.0, 0.0], X, [-1.0, 0.0, 0.0]],
		["rolling +y/-y", [3.0, 0.0, 0.0], Y, [0.0, -1.0, 0.0]]])
	var truck_samples: Array = []
	for sample: Array in samples:
		var v: PackedFloat64Array = sample[0].duplicate()
		v[2] = 0.0
		truck_samples.append([PackedFloat64Array([0.3 * v[0], 0.3 * v[1], 0.0]), PackedFloat64Array([0.3 * sample[1][0], 0.3 * sample[1][1], 0.3 * sample[1][2]])])
	var r: Dictionary = LP.finite(law, truck_samples)
	_record(name, "finite", r.ok, r.worst, r.detail)
	session.free()


func _register_rotorcraft_airframe(samples: Array) -> void:
	var name := "rotorcraft airframe"
	var loaded: Dictionary = RotorData.load_file("res://data/aircraft/xcell_60_research.json", RHO)
	if not loaded.get("ok", false):
		_record(name, "registered", false, INF, str(loaded.get("errors", [])))
		return
	var airframe: Dictionary = loaded.context.airframe_model
	var zero := PackedFloat64Array([0.0, 0.0, 0.0])
	var law := func(v: PackedFloat64Array, rates: PackedFloat64Array) -> PackedFloat64Array:
		var r: Dictionary = Airframe.evaluate(airframe, v, rates, zero, zero, zero, false)
		return r.loads if r.get("ok", false) else PackedFloat64Array()
	var probe: PackedFloat64Array = law.call(PackedFloat64Array([V, 0.0, 0.0]), zero)
	if probe.is_empty():
		_record(name, "registered", false, INF, "airframe model did not evaluate")
		return
	var scale := _scale(law)
	_continuity_set(name, law, scale, zero, [
		["spanwise +x/-x", [0.0, V, 0.0], X, [-1.0, 0.0, 0.0]], ["rest +x/+y", [0.0, 0.0, 0.0], X, Y],
		["vertical +x/+y", [0.0, 0.0, V], X, Y]])
	var r: Dictionary = LP.finite(law, samples)
	_record(name, "finite", r.ok, r.worst, r.detail)
	r = LP.rest(law, scale)
	_record(name, "rest", r.ok, r.worst, r.detail)
	r = LP.mirror(law, samples, scale)
	_record(name, "mirror", r.ok, r.worst, r.detail)
	r = LP.passive_translational(law, samples, scale)
	_record(name, "passive_translational", r.ok, r.worst, r.detail)
