extends SceneTree

const Flight = preload("res://sim/flight_session.gd")
const Field = preload("res://data/field_loader.gd")
const Lake = preload("res://data/lake_loader.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const LiquidFlight = preload("res://sim/liquid_fuel_flight.gd")
const Dynamics = preload("res://physics/dynamics.gd")
const Aero = preload("res://physics/aero.gd")
const Slipstream = preload("res://physics/slipstream.gd")
const Propulsion = preload("res://physics/propulsion.gd")
const LakeSurface = preload("res://physics/lake_surface.gd")
const Terrain = preload("res://physics/ground_terrain.gd")
const HullContact = preload("res://physics/hull_contact.gd")
const Ground = preload("res://physics/ground_contact.gd")

const CALLS := 180

func _initialize() -> void:
	call_deferred("_run")

func _measure(action: Callable) -> float:
	for i in 8:
		action.call()
	var start := Time.get_ticks_usec()
	for i in CALLS:
		action.call()
	return float(Time.get_ticks_usec() - start) / CALLS

func _run() -> void:
	for id in ["p51d-mustang-120"]:
		var session = Flight.new()
		session.input_enabled = false
		session.soft_hull_contacts = true
		session.setup(Catalog.entry(id).data, id)
		session.set_field(Field.load_from().field)
		session.set_lake_context(Lake.load_from().lake)
		session.start_choice = Flight.START_RUNWAY
		root.add_child(session)
		session.reset()
		var body: PackedFloat64Array = session.sim.state.duplicate()
		var values: PackedFloat64Array = session.sim.continuous.duplicate()
		var base: PackedFloat64Array = values.slice(0, session._liquid_index())
		var live: Dictionary = LiquidFlight.properties(session, values, true)
		var air: Dictionary = session.air_data(body, 0.0)
		var model: Dictionary = session.aircraft.model
		var aux: PackedFloat64Array = session.sim.aux
		var rpm: float = session._coupled_rpm(base)
		var deflections: Dictionary = session._deflections(aux)
		var density: float = session.air_density(body)
		var joint: Dictionary = session.sim.model.stage.call(body, values, 0.0)
		var ground_check: Dictionary = session._ground_evaluation(body, aux, base, air, live)
		var gear: Dictionary = session.current_landing_gear(aux)
		var anchors: PackedFloat64Array = aux.slice(session.AUX_ANCHORS,
			session.AUX_ANCHORS + session.anchor_count() * Ground.ANCHOR_STRIDE)
		var wheels: PackedFloat64Array = base.slice(session.wheel_index(),
			session.wheel_index() + session.wheel_count())
		var result := {
			"id": id,
			"substeps": session.sim.model.substeps_joint.call(body, values, 0.0, joint) if session.sim.model.substeps_joint.is_valid() else session.sim.model.substeps.call(body, values, 0.0),
			"ground_evaluation_ok": ground_check.get("ok", false),
			"step_policy": session.sim.model.step_policy.is_valid(),
			"events": session.sim.model.events.size(),
			"full_stage_us": _measure(func(): session.sim.model.stage.call(body, values, 0.0)),
			"coupled_response_us": _measure(func(): session._coupled_response(body, base, 0.0, live, true)),
			"ground_evaluation_us": _measure(func(): session._ground_evaluation(body, aux, base, air, live)),
			"hull_contact_us": _measure(func(): HullContact.loads_at_properties(body, session._hull_contact, live)),
			"wheel_ground_us": _measure(func(): Ground.evaluate(body, gear, aux[session.AUX_SERVO + 2],
				session.ground_surfaces, anchors, wheels, session.sim.inputs[5], false, session._lake)),
			"lake_validation_us": _measure(func(): LakeSurface.is_valid_definition(session._lake)),
			"surface_validation_us": _measure(func(): Terrain.is_valid_surface_table(session.ground_surfaces)),
			"dynamics_us": _measure(func(): Dynamics.loads_from_air(body, model, session._deflections(aux), rpm,
				session.air_density(body), air, NAN, base.slice(0, session._rotor_index()), session._ground_up(body))),
			"air_data_us": _measure(func(): session.air_data(body, 0.0)),
			"properties_us": _measure(func(): LiquidFlight.properties(session, values, true)),
			"aero_us": _measure(func(): Aero.loads(body, air, deflections, model, density, NAN, session._ground_up(body))),
			"slipstream_us": _measure(func(): Slipstream.stage_loads(body, air, deflections, model, rpm, density, NAN,
				base.slice(0, session._rotor_index()), 1, PackedFloat64Array())),
			"propulsion_us": _measure(func(): Propulsion.loads(air.v_air, rpm, model.propulsion, density)),
		}
		print(JSON.stringify(result))
		session.queue_free()
		await process_frame
	quit()
