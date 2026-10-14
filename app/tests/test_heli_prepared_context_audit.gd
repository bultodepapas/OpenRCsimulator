extends SceneTree

const Aero = preload("res://physics/rotorcraft/aerodynamic_stage.gd")
const Main = preload("res://physics/rotorcraft/main_rotor.gd")
const Tail = preload("res://physics/rotorcraft/tail_rotor.gd")
const Airframe = preload("res://physics/rotorcraft/airframe.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const MainFixture = preload("res://tests/test_heli_main_rotor.gd")
const TailFixture = preload("res://tests/test_heli_tail_rotor.gd")
const AirframeFixture = preload("res://tests/test_heli_airframe.gd")
const FlightFixture = preload("res://tests/test_heli_flight.gd")

var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func make_models(density: float, main_radius: float) -> Dictionary:
	var main_parameters: Dictionary = MainFixture.PARAMS.duplicate(true)
	main_parameters["rho_kg_m3"] = density
	main_parameters["rotor_radius_m"] = main_radius
	var tail_parameters: Dictionary = TailFixture.PARAMS.duplicate(true)
	tail_parameters["rho_kg_m3"] = density
	tail_parameters["main_rotor_radius_m"] = main_radius
	var airframe_parameters: Dictionary = AirframeFixture.PARAMS.duplicate(true)
	airframe_parameters["rho_kg_m3"] = density
	var main_result: Dictionary = Main.prepare(main_parameters)
	var tail_result: Dictionary = Tail.prepare(tail_parameters)
	var airframe_result: Dictionary = Airframe.prepare(airframe_parameters)
	if not main_result.ok or not tail_result.ok or not airframe_result.ok:
		return {"ok": false}
	return {"ok": true, "main": main_result.model, "tail": tail_result.model,
		"airframe": airframe_result.model}


func make_configuration(models: Dictionary) -> Dictionary:
	return {
		"mass_kg": 8.2,
		"inertia_body_kg_m2": PackedFloat64Array([0.18, 0.34, 0.28, 0.0, 0.0, 0.0]),
		"gravity_m_s2": 9.80665,
		"main_model": models.main,
		"tail_model": models.tail,
		"airframe_model": models.airframe,
		"shaft_elements": [
			{"inertia_kg_m2": 0.076, "speed_ratio": 1.0,
				"spin_axis_body_frd": PackedFloat64Array([0.0, 0.0, 1.0])},
			{"inertia_kg_m2": 0.00017498940853579914, "speed_ratio": 4.66,
				"spin_axis_body_frd": PackedFloat64Array([0.0, 1.0, 0.0])},
		],
		"drive": FlightFixture.drive_parameters(),
		"electronics": FlightFixture.electronics_parameters(),
		"flow_floor_m_s": 0.1,
		"fin_tail_wake_fraction": 0.2,
		"height_over_radius": -1.0,
		"inflow_loss": 1.0,
		"inflow_instability": 1.0,
	}


func make_aero_context(density: float, main_radius: float, flow_floor: float) -> Dictionary:
	var models: Dictionary = make_models(density, main_radius)
	if not models.ok:
		return {"ok": false}
	return Aero.prepare(models.main, models.tail, models.airframe, flow_floor,
		0.2, -1.0, 1.0, 1.0)


func _initialize() -> void:
	var models: Dictionary = make_models(1.225, 0.775)
	check("fixture rotor and airframe models prepare", models.ok)
	if not models.ok:
		quit(1)
		return
	var config: Dictionary = make_configuration(models)
	var canonical: Dictionary = Flight.prepare(config)
	check("canonical flight context prepares", canonical.ok)
	if not canonical.ok:
		quit(1)
		return
	var matching: Dictionary = config.duplicate()
	matching["fast_aero_context"] = canonical.context.aero_context
	check("matching readonly fast aerodynamic context is accepted", Flight.prepare(matching).ok)

	var foreign_density: Dictionary = config.duplicate()
	foreign_density["fast_aero_context"] = make_aero_context(1.226, 0.775, 0.1).context
	check("foreign-density fast context is rejected", not Flight.prepare(foreign_density).ok)
	var foreign_radius: Dictionary = config.duplicate()
	foreign_radius["fast_aero_context"] = make_aero_context(1.225, 0.78, 0.1).context
	check("foreign-radius fast context is rejected", not Flight.prepare(foreign_radius).ok)
	var foreign_flow: Dictionary = config.duplicate()
	foreign_flow["fast_aero_context"] = make_aero_context(1.225, 0.775, 0.11).context
	check("foreign-flow fast context is rejected", not Flight.prepare(foreign_flow).ok)

	var mutable_fast: Dictionary = config.duplicate()
	mutable_fast["fast_aero_context"] = canonical.context.aero_context.duplicate()
	check("mutable outer fast context is rejected", not Flight.prepare(mutable_fast).ok)
	var mutable_main: Dictionary = config.duplicate()
	mutable_main["main_model"] = models.main.duplicate()
	mutable_main["fast_aero_context"] = canonical.context.aero_context
	check("mutable canonical model is rejected even with matching fast context",
		not Flight.prepare(mutable_main).ok)
	var wrong_type: Dictionary = config.duplicate()
	wrong_type["fast_aero_context"] = "not an aerodynamic context"
	check("wrong fast-context type is rejected", not Flight.prepare(wrong_type).ok)
	var missing_law: Dictionary = config.duplicate()
	var broken_context: Dictionary = canonical.context.aero_context.duplicate()
	broken_context.erase("law")
	broken_context.make_read_only()
	missing_law["fast_aero_context"] = broken_context
	check("readonly fast context with missing law is rejected", not Flight.prepare(missing_law).ok)
	var malformed_submodel: Dictionary = config.duplicate()
	malformed_submodel["electronics"] = "not an electronics model"
	check("malformed electronics submodel is rejected without a script error",
		not Flight.prepare(malformed_submodel).ok)
	var malformed_inertia_string: Dictionary = config.duplicate()
	malformed_inertia_string["inertia_body_kg_m2"] = [0.18, 0.34, 0.28, 0.0, "bad", 0.0]
	check("string inertia entry is rejected without a conversion error",
		not Flight.prepare(malformed_inertia_string).ok)
	var malformed_inertia_bool: Dictionary = config.duplicate()
	malformed_inertia_bool["inertia_body_kg_m2"] = [0.18, 0.34, 0.28, 0.0, true, 0.0]
	check("boolean inertia entry is rejected without a conversion error",
		not Flight.prepare(malformed_inertia_bool).ok)
	print("HELI prepared-context audit: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
