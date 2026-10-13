extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Flight := preload("res://physics/glow/flight.gd")
const FuelMass := preload("res://physics/glow/fuel_mass.gd")
const Blade := preload("res://physics/glow/propeller.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const RHO := 1.225
const TOL := 2.0e-9


class FlightOwner extends Node:
	const Air := preload("res://physics/air_data.gd")
	var aircraft: Dictionary = {}
	var sim: Dictionary = {}
	var engine_running: bool = true
	var density: float = 1.225
	var wind_ned := PackedFloat64Array([0.0, 0.0, 0.0])

	func air_data(body: PackedFloat64Array, _time_s: float) -> Dictionary:
		return Air.compute(body, wind_ned, density)

	func air_density() -> float:
		return density

	func engine_charge_ratio() -> float:
		return 1.0

	func atmosphere_configuration() -> Dictionary:
		return {"temperature_k": 288.15}

	func downwash_index() -> int:
		return -1

	func wheel_count() -> int:
		return 0

	func _deflections(_aux: PackedFloat64Array) -> Dictionary:
		return {aileron_right = 0.0, aileron_left = 0.0, elevator = 0.0, rudder = 0.0}

	func _ground_up(_body: PackedFloat64Array) -> float:
		return NAN

	func _ground_evaluation(_body: PackedFloat64Array, _aux: PackedFloat64Array,
			_values: PackedFloat64Array) -> Dictionary:
		return {ok = true, loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), derivative = PackedFloat64Array()}


var _checks: int = 0
var _failures: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not condition:
		_failures += 1


func _near(label: String, actual: float, expected: float, tolerance: float = TOL) -> void:
	_check(label, is_finite(actual) and absf(actual - expected) <= tolerance,
		"got %s, expected %s (tol %s)" % [actual, expected, tolerance])


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_test_fuel_properties_and_co_moving_flux()
	for entry: Dictionary in [
		{"path": "res://data/aircraft/stik_glow_55ax_2t.json", "family": "2T"},
		{"path": "res://data/aircraft/stik_glow_fs64v_4t.json", "family": "4T"},
	]:
		var loaded: Dictionary = AircraftData.load_file(str(entry.path))
		_check("%s installed aircraft loads" % entry.family, loaded.get("ok", false), str(loaded.get("errors", [])))
		if not loaded.get("ok", false):
			continue
		var model: Dictionary = loaded.model
		_test_propeller_passivity(str(entry.family), model.propulsion.glow.propeller)
		_test_flight_stage_balance(str(entry.family), model)
		_test_one_way_rotor_stop(str(entry.family), model)
	print("glow flight physics: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_propeller_passivity(family: String, propeller: Dictionary) -> void:
	var cases: Array[Dictionary] = [
		{"label": "static", "rpm": 6000.0, "u": 0.0},
		{"label": "forward", "rpm": 6000.0, "u": 12.0},
		{"label": "reverse airflow", "rpm": 6000.0, "u": -12.0},
		{"label": "windmilling", "rpm": 600.0, "u": 30.0},
		{"label": "stopped in airflow", "rpm": 0.0, "u": 30.0},
		{"label": "stopped in reverse airflow", "rpm": 0.0, "u": -30.0},
		{"label": "rest", "rpm": 0.0, "u": 0.0},
	]
	for item: Dictionary in cases:
		var result: Dictionary = Blade.evaluate(float(item.rpm), float(item.u), RHO, propeller)
		var label: String = "%s %s propeller" % [family, item.label]
		_check(label + " evaluates", result.get("ok", false))
		if not result.get("ok", false):
			continue
		var shaft_power: float = float(result.shaft_power_w)
		var thrust_power: float = float(result.thrust_power_w)
		var dissipated_power: float = float(result.dissipation_w)
		var margin: float = shaft_power - thrust_power
		_check(label + " cannot create mechanical power", margin >= -1.0e-10 * maxf(1.0, dissipated_power)
			and dissipated_power >= 0.0,
			"QΩ − Tu=%s W, blade drag dissipation=%s W" % [margin, dissipated_power])
		_check(label + " closes to section drag dissipation",
			absf(margin - dissipated_power) <= 1.0e-10 * maxf(1.0, dissipated_power),
			"power gap=%s W" % (margin - dissipated_power))
		if item.label == "windmilling":
			_check(family + " windmilling air drives the shaft", float(result.torque_nm) < 0.0 and shaft_power < 0.0)
		if item.label == "rest":
			_check(family + " stationary propeller at rest has zero flow power",
				shaft_power == 0.0 and thrust_power == 0.0 and dissipated_power == 0.0)


func _test_fuel_properties_and_co_moving_flux() -> void:
	# Build a wet aircraft from a dry body and a uniform off-centre tank, with its wet CG at the fixed origin.
	var wet_mass: float = 2.4
	var fuel_mass: float = 0.2
	var dry_mass: float = wet_mass - fuel_mass
	var tank_position := PackedFloat64Array([0.20, 0.0, 0.0])
	var tank_size := PackedFloat64Array([0.18, 0.06, 0.04])
	var dry_cg := M.scale(tank_position, -fuel_mass / dry_mass)
	var dry_centroidal := PackedFloat64Array([0.08, 0.12, 0.14, 0.0, 0.0, 0.0])
	var wet_inertia: PackedFloat64Array = dry_centroidal.duplicate()
	_add_scaled(wet_inertia, _point_tensor(dry_cg), dry_mass)
	_add_scaled(wet_inertia, _box_tensor(tank_position, tank_size), fuel_mass)

	var full: Dictionary = FuelMass.evaluate(wet_mass, wet_inertia, fuel_mass, fuel_mass, tank_position, tank_size)
	var remaining: float = 0.08
	var removed: float = fuel_mass - remaining
	var partial_mass: float = dry_mass + remaining
	var partial_cg: PackedFloat64Array = M.scale(tank_position, -removed / partial_mass)
	var expected_partial: PackedFloat64Array = dry_centroidal.duplicate()
	_add_scaled(expected_partial, _point_tensor(M.sub(dry_cg, partial_cg)), dry_mass)
	_add_scaled(expected_partial, _box_tensor(M.sub(tank_position, partial_cg), tank_size), remaining)
	var partial: Dictionary = FuelMass.evaluate(wet_mass, wet_inertia, fuel_mass, remaining, tank_position, tank_size)
	var dry: Dictionary = FuelMass.evaluate(wet_mass, wet_inertia, fuel_mass, 0.0, tank_position, tank_size)
	_check("fuel mass model accepts full, partial and dry inventories", full.ok and partial.ok and dry.ok)
	if not full.ok or not partial.ok or not dry.ok:
		return
	_near("wet fuel mass retains the source mass", full.mass_kg, wet_mass)
	_near("partial-fuel aircraft mass removes only burned fuel", partial.mass_kg, partial_mass)
	_near("dry aircraft mass equals the dry structure", dry.mass_kg, dry_mass)
	_near("wet CG is at the chosen datum", M.norm(full.cg_body_m), 0.0)
	_near("partial tank moves CG away from its side of the datum", partial.cg_body_m[0], partial_cg[0])
	_near("dry CG settles at the dry structure centre", dry.cg_body_m[0], dry_cg[0])
	_check_tensor("wet tensor agrees with dry body plus tank geometry", full.inertia, wet_inertia)
	_check_tensor("partial tensor follows the independent mass distribution", partial.inertia, expected_partial)
	_check_tensor("dry tensor returns to dry-body centroidal inertia", dry.inertia, dry_centroidal)
	_check("fuel removal changes the aircraft's inertia tensor", _tensor_distance(full.inertia, partial.inertia) > 1.0e-5)
	_check("negative or excess remaining fuel is rejected",
		not FuelMass.evaluate(wet_mass, wet_inertia, fuel_mass, -1.0e-6, tank_position, tank_size).ok
		and not FuelMass.evaluate(wet_mass, wet_inertia, fuel_mass, fuel_mass + 1.0e-6, tank_position, tank_size).ok)

	# With a principal-axis body rate and no external wrench, co-moving outflow does not spin the aircraft up.
	# The wet datum is offset from the instantaneous CM, so the inertial acceleration of the datum is observable too.
	var spinning: PackedFloat64Array = RB.make_state(
		PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 5.0, 0.0]))
	var no_force := PackedFloat64Array([0.0, 0.0, 0.0])
	var no_moment := PackedFloat64Array([0.0, 0.0, 0.0])
	for pair: Array in [["full", full], ["partial", partial], ["dry", dry]]:
		var properties: Dictionary = pair[1]
		var rates: PackedFloat64Array = FuelMass.datum_derivative(spinning, properties, no_force, no_moment, 0.0, PackedFloat64Array())
		_check("%s co-moving mass flux produces no angular spin-up" % pair[0],
			M.norm(rates.slice(RB.RATE, RB.RATE + 3)) < 1.0e-10,
			"angular acceleration=%s rad/s²" % rates.slice(RB.RATE, RB.RATE + 3))
		_near("%s fixed datum follows CM centripetal geometry" % pair[0], rates[RB.VEL],
			25.0 * float(properties.cg_body_m[0]), 1.0e-10)


func _test_flight_stage_balance(family: String, model: Dictionary) -> void:
	var owner: FlightOwner = _owner(model, 6000.0, true, 0.75)
	var values: PackedFloat64Array = Flight.initial(owner, PackedFloat64Array([6000.0]))
	var body: PackedFloat64Array = _body(PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var driven: Dictionary = Flight.evaluate(body, values, 0.0, owner)
	_check(family + " running flight stage evaluates", not driven.is_empty())
	if not driven.is_empty():
		_check_angular_balance(family + " running", owner, model, body, values, driven)
	owner.free()

	# Exercise the gyroscopic term with a stopped engine and nonzero carrier rates; fuel mass is constant here.
	var coast_owner: FlightOwner = _owner(model, 5000.0, false, 0.0)
	var coast_values: PackedFloat64Array = Flight.initial(coast_owner, PackedFloat64Array([5000.0]))
	var moving_body: PackedFloat64Array = _body(
		PackedFloat64Array([12.0, -3.0, 1.0]), PackedFloat64Array([0.2, -0.15, 0.1]))
	var coasting: Dictionary = Flight.evaluate(moving_body, coast_values, 0.1, coast_owner)
	_check(family + " rotating coast stage evaluates", not coasting.is_empty())
	if not coasting.is_empty():
		_check_angular_balance(family + " rotating coast", coast_owner, model, moving_body, coast_values, coasting)
		_near(family + " stopped coast consumes no tank fuel", coasting.derivative[1], 0.0)
	coast_owner.free()


func _check_angular_balance(label: String, owner: FlightOwner, model: Dictionary,
		body: PackedFloat64Array, values: PackedFloat64Array, result: Dictionary) -> void:
	var properties: Dictionary = Flight.properties(owner, values[1])
	var prop: Dictionary = model.propulsion
	var axis: PackedFloat64Array = prop.axis
	var rotor_inertia: float = float(prop.rotor_inertia)
	var spin_acceleration: float = float(result.derivative[0]) * TAU / 60.0
	var body_rate: PackedFloat64Array = body.slice(RB.RATE, RB.RATE + 3)
	var body_acceleration: PackedFloat64Array = result.body_derivative.slice(RB.RATE, RB.RATE + 3)
	var body_momentum: PackedFloat64Array = RB.inertia_mul(properties.inertia, body_rate)
	var total_momentum: PackedFloat64Array = M.add(body_momentum, result.rotor_momentum)
	var lhs: PackedFloat64Array = RB.inertia_mul(properties.inertia, body_acceleration)
	var rotor_acceleration_momentum: PackedFloat64Array = M.scale(axis, rotor_inertia * spin_acceleration)
	for i: int in 3:
		lhs[i] += rotor_acceleration_momentum[i]
	lhs = M.add(lhs, M.cross(body_rate, total_momentum))

	# Flight returns external body moments with the shaft reaction already applied. Remove that
	# internal exchange and shift the aerodynamic/ground moment from fixed datum to current CM.
	var shaft_reaction: PackedFloat64Array = M.scale(axis, -rotor_inertia * spin_acceleration)
	var force: PackedFloat64Array = result.loads.slice(0, 3)
	var external_moment_datum: PackedFloat64Array = M.sub(result.loads.slice(3, 6), shaft_reaction)
	var external_moment_cm: PackedFloat64Array = M.sub(external_moment_datum, M.cross(properties.cg_body_m, force))
	_check_vector(label + " body and rotor angular momentum balance", lhs, external_moment_cm, 3.0e-8)


func _test_one_way_rotor_stop(family: String, model: Dictionary) -> void:
	var owner: FlightOwner = _owner(model, 6000.0, true, 0.5)
	var values: PackedFloat64Array = Flight.initial(owner, PackedFloat64Array([6000.0]))
	values[0] = 0.0
	var still_body: PackedFloat64Array = _body(PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var held: Dictionary = Flight.evaluate(still_body, values, 0.0, owner)
	_check(family + " static stop holds the rotor at rest", not held.is_empty() and absf(float(held.derivative[0])) < 1.0e-12,
		str(held.get("derivative", PackedFloat64Array())))

	var forward_body: PackedFloat64Array = _body(PackedFloat64Array([30.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var windmilling: Dictionary = Flight.evaluate(forward_body, values, 0.0, owner)
	_check(family + " forward windmill breaks the stop into positive RPM", not windmilling.is_empty()
		and float(windmilling.derivative[0]) > 0.0,
		str(windmilling.get("derivative", PackedFloat64Array())))

	var reverse_body: PackedFloat64Array = _body(PackedFloat64Array([-30.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var reverse: Dictionary = Flight.evaluate(reverse_body, values, 0.0, owner)
	_check(family + " reverse airflow cannot drive the rotor through zero", not reverse.is_empty()
		and absf(float(reverse.derivative[0])) < 1.0e-12,
		str(reverse.get("derivative", PackedFloat64Array())))
	owner.free()


func _owner(model: Dictionary, rpm: float, engine_on: bool, throttle: float) -> FlightOwner:
	var owner: FlightOwner = FlightOwner.new()
	owner.aircraft = {"model": model}
	owner.engine_running = engine_on
	owner.sim = {
		"inputs": PackedFloat64Array([0.0, 0.0, 0.0, throttle]),
		"aux": PackedFloat64Array([rpm]),
		"gravity": 0.0,
	}
	return owner


func _body(velocity: PackedFloat64Array, angular_rate: PackedFloat64Array) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([0.0, 0.0, 0.0]), velocity,
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), angular_rate)


func _point_tensor(position: PackedFloat64Array) -> PackedFloat64Array:
	var x: float = position[0]
	var y: float = position[1]
	var z: float = position[2]
	return PackedFloat64Array([y * y + z * z, x * x + z * z, x * x + y * y, -x * y, -x * z, -y * z])


func _box_tensor(position: PackedFloat64Array, size: PackedFloat64Array) -> PackedFloat64Array:
	var x: float = position[0]
	var y: float = position[1]
	var z: float = position[2]
	return PackedFloat64Array([
		(size[1] * size[1] + size[2] * size[2]) / 12.0 + y * y + z * z,
		(size[0] * size[0] + size[2] * size[2]) / 12.0 + x * x + z * z,
		(size[0] * size[0] + size[1] * size[1]) / 12.0 + x * x + y * y,
		-x * y, -x * z, -y * z,
	])


func _add_scaled(target: PackedFloat64Array, other: PackedFloat64Array, scale: float) -> void:
	for i: int in 6:
		target[i] += other[i] * scale


func _check_tensor(label: String, actual: PackedFloat64Array, expected: PackedFloat64Array) -> void:
	_check_vector(label, actual, expected, 1.0e-11)


func _check_vector(label: String, actual: PackedFloat64Array, expected: PackedFloat64Array,
		tolerance: float = TOL) -> void:
	var error: float = INF
	if actual.size() == expected.size():
		error = 0.0
		for i: int in actual.size():
			error = maxf(error, absf(actual[i] - expected[i]))
	_check(label, error <= tolerance, "max component error=%s" % String.num_scientific(error))


func _tensor_distance(left: PackedFloat64Array, right: PackedFloat64Array) -> float:
	var error: float = 0.0
	for i: int in 6:
		error = maxf(error, absf(left[i] - right[i]))
	return error
