# HELI-06c: fixed-body, prescribed-speed component stand, not helicopter flight.
extends SceneTree

const Stage = preload("res://physics/rotorcraft/aerodynamic_stage.gd")
const Main = preload("res://physics/rotorcraft/main_rotor.gd")
const Tail = preload("res://physics/rotorcraft/tail_rotor.gd")
const Airframe = preload("res://physics/rotorcraft/airframe.gd")
const MainFixture = preload("res://tests/test_heli_main_rotor.gd")
const TailFixture = preload("res://tests/test_heli_tail_rotor.gd")
const AirframeFixture = preload("res://tests/test_heli_airframe.gd")
const RK = preload("res://physics/integrator.gd")
const M = preload("res://physics/math3d.gd")
var checks: int = 0
var failures: int = 0
var main_model: Dictionary
var tail_model: Dictionary
var airframe_model: Dictionary


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func close(label: String, actual: float, expected: float, tolerance: float = 1e-12) -> void:
	check(label, is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


func _response(z: PackedFloat64Array, omega: float = 167.0,
		air: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]),
		rates: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]), diagnostics: bool = true,
		fraction: float = 0.2) -> Dictionary:
	return Stage.evaluate(main_model, tail_model, airframe_model, z, omega, air, rates,
		0.09624751257538011, 0.01, -0.01, 0.1, 0.1, fraction, -1.0, 1.0, 0.0, diagnostics)


func _initialize() -> void:
	main_model = Main.prepare(MainFixture.PARAMS).model
	tail_model = Tail.prepare(TailFixture.PARAMS).model
	airframe_model = Airframe.prepare(AirframeFixture.PARAMS).model
	var z: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 1.0])
	var before: PackedByteArray = z.to_byte_array()
	var first: Dictionary = _response(z)
	var high: Dictionary = _response(PackedFloat64Array([0.0, 0.0, 4.0]))
	var again: Dictionary = _response(z)
	check("joint component evaluation valid", first.ok and high.ok and again.ok)
	check("input state unchanged by load queries", z.to_byte_array() == before)
	check("no cached previous-stage loads or derivatives", first.loads.to_byte_array() == again.loads.to_byte_array() and first.derivative.to_byte_array() == again.derivative.to_byte_array())
	var compact: Dictionary = _response(z, 167.0, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), false)
	check("compact and diagnostic load bytes agree", compact.ok and compact.loads.to_byte_array() == first.loads.to_byte_array())
	check("compact and diagnostic derivative bytes agree", compact.derivative.to_byte_array() == first.derivative.to_byte_array())
	for i: int in range(6):
		close("each component counted once " + str(i), first.loads[i], first.main_rotor.loads[i] + first.tail_rotor.loads[i] + first.airframe.loads[i])
	close("shaft-aligned fuselage wake from actual stage vi", first.fuselage_wake_velocity_body_frd_m_s[2], 1.0)
	close("download follows actual stage vi squared", high.airframe.fuselage_loads[2], 16.0 * first.airframe.fuselage_loads[2])
	check("actual stage vi changes main thrust", first.main_rotor.thrust_n > high.main_rotor.thrust_n)
	var moving: Dictionary = _response(PackedFloat64Array([0.0, 0.0, 4.2]), 167.0, M.v3(3.0, 2.0, 1.0), M.v3(0.2, -0.3, 0.4))
	close("main hub full pitch point-velocity term", moving.hub_air_velocity_body_frd_m_s[0], 3.0 + (-0.3) * (-0.235))
	close("main hub full roll point-velocity term", moving.hub_air_velocity_body_frd_m_s[1], 2.0 - 0.2 * (-0.235))
	close("main hub vertical flow at centered mast", moving.hub_air_velocity_body_frd_m_s[2], 1.0)
	close("fin uses this stage's reconstructed tail vi", moving.vertical_fin_wake_velocity_body_frd_m_s[1], 0.2 * moving.tail_rotor.induced_velocity_m_s)
	close("tail surfaces use this stage's main wake factor", moving.horizontal_tail_wake_velocity_body_frd_m_s[2], moving.tail_rotor.wake_factor * 4.2)
	close("full fin point flow subtracts wake", moving.airframe.vertical_fin_relative_air_m_s[1], 2.0 - 0.91 * 0.4 + 0.08 * 0.2 - moving.vertical_fin_wake_velocity_body_frd_m_s[1])
	check("local flow work remains passive in joint query", moving.airframe.relative_power_w <= 0.0)
	var stopped: Dictionary = _response(z, 0.0)
	check("stopped rotors inactive but main wake continues decay", stopped.ok and not stopped.main_rotor.rotor_active and not stopped.tail_rotor.rotor_active and stopped.derivative[2] < 0.0)
	check("residual main wake still loads fuselage", stopped.airframe.fuselage_loads[2] > 0.0)
	check("invalid wake fraction refused", not _response(z, 167.0, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), true, 1.1).ok)
	check("nonfinite wake fraction refused", not _response(z, 167.0, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), true, NAN).ok)
	check("malformed state refused", not _response(PackedFloat64Array([1.0])).ok)
	check("nonfinite state refused", not _response(PackedFloat64Array([0.0, 0.0, NAN])).ok)
	var air_parameters: Dictionary = AirframeFixture.PARAMS.duplicate(true)
	air_parameters.rho_kg_m3 = 1.2
	var original_airframe: Dictionary = airframe_model
	airframe_model = Airframe.prepare(air_parameters).model
	check("inconsistent stage density refused", not _response(z).ok)
	air_parameters.rho_kg_m3 = 1.225
	air_parameters.vertical_fin_area_m2 = 0.013
	airframe_model = Airframe.prepare(air_parameters).model
	check("different blockage and fin-loading areas refused", not _response(z).ok)
	airframe_model = original_airframe
	var original_main: Dictionary = main_model
	main_model = {}
	check("missing prepared interface context refused", not _response(z).ok)
	main_model = original_main
	var original_tail: Dictionary = tail_model
	var tail_parameters: Dictionary = TailFixture.PARAMS.duplicate(true)
	tail_parameters.main_rotor_radius_m = 0.776
	tail_model = Tail.prepare(tail_parameters).model
	check("different main-radius wake geometry refused", not _response(z).ok)
	tail_model = original_tail
	_hover_stand()
	print("HELI-06c aerodynamic stage: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _hover_stand() -> void:
	# Same independently derived main-disc/wake equilibrium as HELI-05a;
	# body remains clamped while the complete aerodynamic payload is queried.
	var tip: float = 167.0 * 0.775
	var disk: float = PI * 0.775 * 0.775
	var k: float = 0.5 * 5.5 * (2.0 * 0.058 / (PI * 0.775)) * 1.225 * disk
	var a: float = k * tip * tip * 0.09624751257538011 / 3.0
	var b: float = 0.5 * k * tip
	var exact_vi: float = 2.0 * a / (b + M.sqrt_(b * b + 8.0 * 1.225 * disk * a))
	for divisor: int in [1, 2, 4]:
		var state: PackedFloat64Array = PackedFloat64Array()
		state.resize(16)
		state[6] = 1.0
		state[15] = 1.0
		var dt: float = 1.0 / (240.0 * float(divisor))
		var derivative := func(stage_state: PackedFloat64Array, _t: float) -> PackedFloat64Array:
			var response: Dictionary = _response(stage_state.slice(13, 16), 167.0, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), false)
			var result: PackedFloat64Array = PackedFloat64Array()
			result.resize(16)
			for i: int in range(3):
				result[13 + i] = response.derivative[i]
			return result
		for tick: int in range(480 * divisor):
			state = RK.rk4_step_at(state, float(tick) * dt, dt, derivative)
		var settled: Dictionary = _response(state.slice(13, 16))
		close("wake stand h/h2/h4 settles to analytic root", state[15], exact_vi, 1e-8)
		close("longitudinal flap settles on held cyclic", state[13], -4.2 * 0.01, 1e-8)
		close("lateral flap settles on held cyclic", state[14], -4.2 * 0.01, 1e-8)
		close("stand download settles on actual vi", settled.airframe.fuselage_loads[2], 0.5 * 1.225 * 0.15 * exact_vi * exact_vi, 1e-8)
		close("settled vi matches actual-thrust inflow target", settled.inflow.target, state[15], 1e-8)
		check("clamped body state stays unchanged", state[6] == 1.0 and state[0] == 0.0 and state[10] == 0.0)
