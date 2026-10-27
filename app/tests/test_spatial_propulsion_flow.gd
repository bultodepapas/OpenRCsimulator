extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const AirData := preload("res://physics/air_data.gd")
const Blade := preload("res://physics/glow/propeller.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const GlowFlight := preload("res://physics/glow/flight.gd")
const LiquidFlight := preload("res://sim/liquid_fuel_flight.gd")
const M := preload("res://physics/math3d.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const RB := preload("res://physics/rigid_body.gd")
const Turbine := preload("res://physics/turbine.gd")
const WindFlow := preload("res://physics/wind_aircraft_flow.gd")


class SpatialWind extends RefCounted:
	const Math := preload("res://physics/math3d.gd")
	var origin_ned := PackedFloat64Array([0.0, 0.0, 0.0])
	var base_wind_ned := PackedFloat64Array([0.0, 0.0, 0.0])
	var gradient_ned := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

	func wind_world(position_ned: PackedFloat64Array, _time_s: float) -> PackedFloat64Array:
		var out: PackedFloat64Array = base_wind_ned.duplicate()
		var offset: PackedFloat64Array = Math.sub(position_ned, origin_ned)
		for component: int in 3:
			for coordinate: int in 3:
				out[component] += gradient_ned[component * 3 + coordinate] * offset[coordinate]
		return out


class GlowOwner extends Node:
	const AirData := preload("res://physics/air_data.gd")
	const WindAircraftFlow := preload("res://physics/wind_aircraft_flow.gd")
	var aircraft: Dictionary = {}
	var sim: Dictionary = {}
	var engine_running: bool = true
	var density: float = 1.225
	var wind_ned := PackedFloat64Array([0.0, 0.0, 0.0])
	var wind_gradient_ned := PackedFloat64Array([0.0, 0.0, 0.0])
	var use_spatial_stage: bool = false

	func start_fuel_kg() -> float:
		return float(aircraft.model.propulsion.glow.reference_fuel_kg)

	func air_data(body: PackedFloat64Array, time_s: float) -> Dictionary:
		if use_spatial_stage:
			var stage: Dictionary = WindAircraftFlow.stage_air(body, aircraft.model, self, time_s, density)
			return stage.air if stage.get("ok", false) else {}
		return AirData.compute(body, wind_ned, density)

	func wind_world(position_ned: PackedFloat64Array, _time_s: float) -> PackedFloat64Array:
		var wind: PackedFloat64Array = wind_ned.duplicate()
		for axis: int in 3:
			wind[axis] += wind_gradient_ned[axis] * position_ned[0]
		return wind

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
			_values: PackedFloat64Array, _stage_air: Dictionary = {}) -> Dictionary:
		return {ok = true, loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), derivative = PackedFloat64Array()}


class SpatialLiquidFlight extends "res://sim/flight_session.gd":
	const WindAircraftFlow := preload("res://physics/wind_aircraft_flow.gd")
	var use_spatial_stage: bool = false
	var stage_environment: Object

	func air_data(body: PackedFloat64Array, time_s: float = NAN) -> Dictionary:
		if use_spatial_stage:
			var stage: Dictionary = WindAircraftFlow.stage_air(body, aircraft.model, stage_environment,
				sim.time() if is_nan(time_s) else time_s, air_density(body))
			return stage.air if stage.get("ok", false) else {}
		return super.air_data(body, time_s)


var _checks: int = 0
var _failures: int = 0


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1


func _vector_near(label: String, actual: PackedFloat64Array, expected: PackedFloat64Array,
		tolerance: float = 1.0e-10) -> void:
	var passed: bool = actual.size() == expected.size()
	if passed:
		for i in actual.size():
			if not is_finite(actual[i]) or absf(actual[i] - expected[i]) > tolerance:
				passed = false
				break
	_check(label, passed, "got %s expected %s" % [actual, expected])


func _initialize() -> void:
	_test_shaft_flow_projection()
	_test_turbine_intake_flow()
	_test_glow_point_uses_supplied_complete_flow()
	_test_finite_liquid_session_uses_stage_flow()
	print("spatial propulsion flow: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_shaft_flow_projection() -> void:
	var loaded: Dictionary = AircraftData.load_file("res://data/aircraft/p51d_mustang_120.json")
	_check("P-51 shaft fixture loads", loaded.get("ok", false), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		return
	var prop: Dictionary = loaded.model.propulsion
	var body: PackedFloat64Array = RB.make_state(PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([13.0, -2.0, 1.0]), PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.15, -0.2, 0.3]))
	var datum_air := PackedFloat64Array([12.0, -1.0, 0.5])
	var air: Dictionary = {v_air = datum_air}
	var fallback: Dictionary = Propulsion.stage_air_velocity(body, air, prop)
	_check("legacy shaft fallback resolves", fallback.get("ok", false))
	if not fallback.get("ok", false):
		return
	_vector_near("legacy RPM shaft path retains its datum inflow convention", fallback.velocity_body, datum_air, 0.0)
	var explicit := PackedFloat64Array([29.0, -4.0, 2.0])
	air[Propulsion.STAGE_PROPULSION_AIR_KEY] = explicit
	var sampled: Dictionary = Propulsion.stage_air_velocity(body, air, prop)
	_check("explicit hub field resolves", sampled.get("ok", false), str(sampled.get("message", "")))
	if not sampled.get("ok", false):
		return
	_vector_near("shaft inflow uses explicit complete hub flow without adding omega again", sampled.velocity_body, explicit, 0.0)
	var u: float = M.dot(sampled.velocity_body, Propulsion.axis(prop))
	var fallback_u: float = M.dot(fallback.velocity_body, Propulsion.axis(prop))
	var rpm: float = 4200.0
	var rho: float = 1.225
	var explicit_torque: float = Propulsion.prop_torque(rpm, u, prop, rho)
	var expected_torque: float = Propulsion.prop_torque(rpm, M.dot(explicit, Propulsion.axis(prop)), prop, rho)
	var fallback_torque: float = Propulsion.prop_torque(rpm, fallback_u, prop, rho)
	_check("prop torque consumes the explicit point's projected axial inflow",
		is_finite(explicit_torque) and absf(explicit_torque - expected_torque) <= 1.0e-12)
	_check("explicit stage flow changes the sampled shaft load from the legacy datum",
		is_finite(fallback_torque) and absf(explicit_torque - fallback_torque) > 1.0e-5,
		"explicit=%s legacy=%s" % [explicit_torque, fallback_torque])
	var explicit_rate: float = Propulsion.shaft_rate(rpm, 0.75, u, prop, rho, 1.0, true)
	var fallback_rate: float = Propulsion.shaft_rate(rpm, 0.75, fallback_u, prop, rho, 1.0, true)
	_check("sampled shaft derivative follows the selected point inflow", is_finite(explicit_rate)
		and is_finite(fallback_rate) and absf(explicit_rate - fallback_rate) > 1.0e-4,
		"explicit=%s legacy=%s" % [explicit_rate, fallback_rate])


func _test_turbine_intake_flow() -> void:
	var loaded: Dictionary = AircraftData.load_file("res://data/aircraft/sebart_avanti_s_a200.json")
	_check("Vantage Jet turbine fixture loads", loaded.get("ok", false), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		return
	var prop: Dictionary = loaded.model.propulsion
	var body: PackedFloat64Array = RB.make_state(PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([20.0, 1.0, -0.5]), PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([-0.12, 0.18, 0.25]))
	var datum_air := PackedFloat64Array([18.0, -1.0, 0.25])
	var air: Dictionary = {v_air = datum_air}
	var fallback: Dictionary = Propulsion.stage_air_velocity(body, air, prop)
	_check("turbine intake fallback resolves", fallback.get("ok", false))
	if not fallback.get("ok", false):
		return
	var expected: PackedFloat64Array = Turbine.local_intake_velocity(datum_air,
		body.slice(RB.RATE, RB.RATE + 3), prop)
	_vector_near("legacy turbine intake retains its existing omega-cross-r conversion",
		fallback.velocity_body, expected, 0.0)
	var explicit := PackedFloat64Array([22.0, -2.0, 1.0])
	air[Propulsion.STAGE_PROPULSION_AIR_KEY] = explicit
	var sampled: Dictionary = Propulsion.stage_air_velocity(body, air, prop)
	_check("turbine explicit intake flow resolves", sampled.get("ok", false))
	if sampled.get("ok", false):
		_vector_near("turbine receives complete sampled intake flow without a second rotation term",
			sampled.velocity_body, explicit, 0.0)


func _test_glow_point_uses_supplied_complete_flow() -> void:
	var loaded: Dictionary = AircraftData.load_file("res://data/aircraft/stik_glow_55ax_2t.json")
	_check("Stik Glow fixture loads", loaded.get("ok", false), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		return
	var owner := GlowOwner.new()
	owner.aircraft = {model = loaded.model}
	owner.sim = {inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.75]), aux = PackedFloat64Array([6000.0]), gravity = 0.0}
	owner.wind_ned = PackedFloat64Array([1.5, -0.5, 0.0])
	owner.wind_gradient_ned = PackedFloat64Array([0.7, -0.25, 0.1])
	var body: PackedFloat64Array = RB.make_state(PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([15.0, -2.0, 0.8]), PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.18, -0.14, 0.23]))
	var values: PackedFloat64Array = GlowFlight.initial(owner, PackedFloat64Array([6000.0]), body)
	_check("Glow fixture initial lifecycle state is valid", GlowFlight.valid(values, loaded.model.propulsion.glow), str(values))
	if not GlowFlight.valid(values, loaded.model.propulsion.glow):
		owner.free()
		return
	var stage: Dictionary = WindFlow.stage_air(body, loaded.model, owner, 0.0, owner.density)
	_check("Glow stage adapter obtains a complete sampler receipt", stage.get("ok", false)
		and WindFlow.matches_stage(stage.air, body, owner.density), str(stage.get("errors", [])))
	if not stage.get("ok", false):
		owner.free()
		return
	var explicit: PackedFloat64Array = stage.air.propulsion_air_body
	owner.use_spatial_stage = true
	var sampled: Dictionary = GlowFlight.point(owner, body, values, 0.0)
	_check("Glow point evaluates with complete spatial stage flow", sampled.get("ok", false), str(sampled.get("message", "")))
	if sampled.get("ok", false):
		_vector_near("Glow hub load/cooling sees sampler point flow once",
			sampled.hub_air_velocity_body_m_s, explicit, 0.0)
		var legacy_air: PackedFloat64Array = AirData.compute(body, owner.wind_ned, owner.density).v_air
		var legacy_hub: PackedFloat64Array = Propulsion.hub_air_velocity(body, legacy_air, loaded.model.propulsion.offset)
		_check("spatial field changes the sampled Glow hub flow", M.norm(M.sub(explicit, legacy_hub)) > 1.0e-4)
		var expected_load: Dictionary = Blade.evaluate(6000.0,
			M.dot(explicit, loaded.model.propulsion.axis), owner.density, loaded.model.propulsion.glow.propeller)
		_check("Glow propeller load uses explicit point axial speed",
			expected_load.get("ok", false) and absf(float(sampled.propeller.torque_nm) - float(expected_load.torque_nm)) < 1.0e-8,
			"got=%s expected=%s" % [sampled.propeller.get("torque_nm", NAN), expected_load.get("torque_nm", NAN)])
	owner.use_spatial_stage = false
	var absent_air: Dictionary = owner.air_data(body, 0.0)
	var legacy_expected: PackedFloat64Array = Propulsion.hub_air_velocity(body, absent_air.v_air,
		loaded.model.propulsion.offset)
	var legacy: Dictionary = GlowFlight.point(owner, body, values, 0.0)
	_check("Glow point still evaluates without the optional stage field", legacy.get("ok", false), str(legacy.get("message", "")))
	if legacy.get("ok", false):
		_vector_near("Glow absent-field path preserves its historic hub conversion",
			legacy.hub_air_velocity_body_m_s, legacy_expected, 0.0)
	owner.free()


func _test_finite_liquid_session_uses_stage_flow() -> void:
	var flight := SpatialLiquidFlight.new()
	flight.input_enabled = false
	flight.setup("res://data/aircraft/p51d_mustang_120.json")
	var admitted: bool = flight.is_flyable() and flight.liquid_fuel_is_active()
	_check("finite-liquid P-51 fixture admits", admitted, str(flight.start) if not admitted else "")
	if not admitted:
		flight.free()
		return
	var body: PackedFloat64Array = flight.sim.state.duplicate()
	body[RB.POS + 2] = -1000.0
	var values: PackedFloat64Array = flight.sim.continuous.duplicate()
	var time_s: float = flight.sim.time()
	var legacy_air: Dictionary = flight.air_data(body, time_s)
	var legacy: Dictionary = LiquidFlight.evaluate(body, values, flight.sim.time(), flight)
	var wind := SpatialWind.new()
	wind.origin_ned = body.slice(RB.POS, RB.POS + 3)
	wind.gradient_ned = PackedFloat64Array([0.15, 0.0, 0.0, 0.0, 0.15, 0.0, 0.0, 0.0, 0.15])
	flight.stage_environment = wind
	flight.use_spatial_stage = true
	var stage_air: Dictionary = flight.air_data(body, time_s)
	_check("finite-liquid adapter obtains a complete WindAircraftFlow receipt",
		stage_air.get("spatial_air_law", "") == WindFlow.STAGE_AIR_LAW
		and WindFlow.matches_stage(stage_air, body, flight.air_density(body)))
	if stage_air.is_empty() or not stage_air.has("propulsion_air_body"):
		flight.free()
		return
	var sampled_point: PackedFloat64Array = stage_air.propulsion_air_body
	_check("finite-liquid test field modifies local propulsion inflow",
		M.norm(M.sub(sampled_point, legacy_air.v_air)) > 1.0e-4,
		"point=%s datum=%s" % [sampled_point, legacy_air.v_air])
	var lag_index: int = flight.downwash_index()
	var downwash_cl: float = flight.sim.aux[lag_index] if lag_index >= 0 and lag_index < flight.sim.aux.size() else NAN
	var components: Dictionary = Dynamics._components_from_air(body, flight.aircraft.model,
		flight._deflections(flight.sim.aux), values[flight._rotor_index()], flight.air_density(body),
		stage_air, downwash_cl, PackedFloat64Array(), flight._ground_up(body))
	_check("finite-liquid Dynamics accepts receipt-backed propulsion flow",
		components.get("error", "").is_empty() and is_finite(M.norm(components.loads.slice(0, 3)))
		and is_finite(M.norm(components.loads.slice(3, 6))),
		str(components.get("error", "")))
	var stage_response: Dictionary = flight._coupled_response(body, values.slice(0, flight._liquid_index()), time_s)
	_check("finite-liquid coupled response accepts sampler-backed stage air",
		stage_response.get("ok", false), str(stage_response.get("message", "")))
	var point: Dictionary = LiquidFlight.evaluate(body, values, flight.sim.time(), flight)
	_check("finite-liquid adapter evaluates its powered stage with sampler flow",
		not point.is_empty(), str(point.get("message", "")) + " response=" + str(stage_response.get("message", "")))
	if not legacy.is_empty() and not point.is_empty():
		var rpm_index: int = flight._rotor_index()
		var legacy_rpm_rate: float = legacy.derivative[rpm_index]
		var point_rpm_rate: float = point.derivative[rpm_index]
		_check("finite-liquid shaft response changes with explicit hub inflow",
			is_finite(legacy_rpm_rate) and is_finite(point_rpm_rate)
			and absf(point_rpm_rate - legacy_rpm_rate) > 1.0e-5,
			"explicit=%s legacy=%s" % [point_rpm_rate, legacy_rpm_rate])
	flight.free()
