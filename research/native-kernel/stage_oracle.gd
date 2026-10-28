## NK-3 milestone 2 stage oracle: byte comparison of the native joint stage and its new parts against the live
## reference session (FlightSession._wheel_evaluate and the functions it calls), loaded from app/ at run time.
## Components: legacy propeller (stage inflow + loads), soft hull contacts (flat and lake branches),
## _ground_evaluation, _ground_up and the complete stage dictionary, on random tick contexts and states including
## malformed ones; plus D6 refusals of unported session capabilities and data.
## Usage: godot --headless --path app --script <abs>/stage_oracle.gd -- --extension=<abs .gdextension>
##        --output=<new json> [--seed=20261027] [--states=12000]
extends "oracle.gd"

const Adapter := preload("stage_adapter.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")


func _checks() -> void:
	_report.format = "openrc-nk3-stage-oracle v1"
	var session := _build_session(AIRCRAFT, "runway", false)
	if session == null:
		return
	var prepared: Dictionary = _native.prepare_stage(Adapter.config_for(session))
	_report.prepare = {ok = prepared.ok, error = prepared.error}
	if not prepared.ok:
		_failures.append("prepare_stage refused the Stik: " + str(prepared.error))
		session.free()
		return
	_check_stage(session)
	_check_stage_refusals(session)
	session.free()


## A detached session as research/performance/session_probe.gd builds it: Stik, default field, near_runway lake,
## soft hull contacts; `case` runway | trim | lake. `world` installs the full scenery collision world.
var _world_cache: Dictionary = {}


func _build_session(aircraft_id: String, case: String, world: bool, weather: Dictionary = {}, soft_hull := true) -> Node:
	var session: Node = Session.new()
	session.input_enabled = true
	session.physics_enabled = true
	session.crash_auto_restart = false
	session.soft_hull_contacts = soft_hull
	session.setup(str(Catalog.entry(aircraft_id).data), aircraft_id)
	if not session.is_flyable():
		_failures.append("%s setup failed: %s" % [aircraft_id, session.pause_reason])
		session.free()
		return null
	if not weather.is_empty() and not session.setup_weather(weather):
		_failures.append("%s weather refused: %s" % [aircraft_id, session.weather_error])
		session.free()
		return null
	var field: Dictionary = FieldLoader.load_from()
	var lake_load: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field.ok or not lake_load.ok or not session.set_field(field.field):
		_failures.append("field/lake load failed")
		session.free()
		return null
	if world:
		if _world_cache.is_empty():
			_world_cache = CollisionSetup.build(field.field)
		var built: Dictionary = _world_cache
		if not built.get("ok", false) or not session.set_collision_world(built.world):
			_failures.append("collision world failed")
			session.free()
			return null
	if not session.set_lake_context(lake_load.lake):
		_failures.append("lake install failed")
		session.free()
		return null
	if case == "runway":
		session.start_choice = Session.START_RUNWAY
	elif case == "lake":
		var state: PackedFloat64Array = session.start.state.duplicate()
		state[RB.POS] = 110.0
		state[RB.POS + 1] = 125.0
		state[RB.POS + 2] = -10.0
		session.start.state = state
	session.reset()
	if not session.sim.fault_reason.is_empty() or session.sim.paused or not session.crash.is_empty():
		_failures.append("%s/%s reset unhealthy: %s" % [aircraft_id, case, session.pause_reason])
		session.free()
		return null
	return session


func _stage_state(context: Dictionary, surfaces: PackedFloat64Array, lake: Dictionary) -> Dictionary:
	var pick := _rng.randf()
	var malformed := _rng.randf() < 0.08
	var s: PackedFloat64Array
	var kind: String
	if pick < 0.4:
		s = _ground_state(context, surfaces, lake, false)
		kind = "ground"
	elif pick < 0.65:
		# Hull-heavy: CG from 0.1 m below to 0.6 m above the ground, any attitude (wingtip, tail, belly, inverted).
		s = _ground_state(context, surfaces, lake, false)
		var attitude := _random_unit_quaternion()
		for k in 4:
			s[RB.ATT + k] = attitude[k]
		s[RB.POS + 2] = -Terrain.sample_validated(s[0], s[1], surfaces, lake)[0] - _rng.randf_range(-0.1, 0.6)
		kind = "hull"
	else:
		s = _aero_inputs(context, context.surfaces).s
		kind = "air"
	if malformed:
		for _k in _rng.randi_range(1, 2):
			s[_rng.randi_range(0, 12)] = _special() if _rng.randf() < 0.8 else _rng.randf_range(-1e6, 1e6)
	return {s = s, kind = kind, malformed = malformed}


func _stage_aux(context: Dictionary, session: Node, s: PackedFloat64Array) -> PackedFloat64Array:
	var aux: PackedFloat64Array = context.aux.duplicate()
	var max_rpm: float = context.model.propulsion.max_rpm
	var rpm_pick := _rng.randf()
	aux[Session.AUX_RPM] = 0.0 if rpm_pick < 0.05 else (0.5 if rpm_pick < 0.08 else _rng.randf_range(0.0, 1.1 * max_rpm))
	for k in 3:
		aux[Session.AUX_SERVO + k] = _rng.randf_range(-1.0, 1.0) if _rng.randf() < 0.85 else 0.0
	var gear: Dictionary = context.gear
	for k in gear.contacts.size():
		var f: Dictionary = Wheels.frame(s, gear.contacts[k], aux[Session.AUX_SERVO + 2], context.surfaces,
			PackedFloat64Array(), true, context.lake)
		var at: int = Session.AUX_ANCHORS + 3 * k
		var stuck := _rng.randf()
		aux[at] = f.position[0] + _rng.randf_range(-0.02, 0.02)
		aux[at + 1] = f.position[1] + _rng.randf_range(-0.02, 0.02)
		aux[at + 2] = 1.0 if stuck < 0.5 else 0.0
	var lag: int = session.downwash_index()
	if lag >= 0:
		aux[lag] = _rng.randf_range(-5.0, 30.0)
	return aux


func _check_stage(session: Node) -> void:
	var context := {
		model = session.aircraft.model, gear = session.current_landing_gear(session.sim.aux),
		surfaces = session.ground_surfaces, lake = session._lake, rest = session.sim.state.duplicate(),
		aux = session.sim.aux.duplicate(), deflections = session._deflections(session.sim.aux).duplicate(),
	}
	var prop: Dictionary = context.model.propulsion
	var hull: Dictionary = session._hull_contact
	var dt: float = session.sim.dt()
	for i in _states:
		var drawn := _stage_state(context, context.surfaces, context.lake)
		var s: PackedFloat64Array = drawn.s
		var aux := _stage_aux(context, session, s)
		session.sim.aux = aux
		var time_now: float = dt * _rng.randi_range(0, 240 * 120)
		_native.set_tick_context(aux, session.sim.inputs, Adapter.deflection_array(session._deflections(aux)), time_now)
		var values := PackedFloat64Array()
		for k in 3:
			values.append(_rng.randf_range(-25.0, 25.0) if _rng.randf() < 0.7 else _rng.randf_range(-0.05, 0.05))
		if drawn.malformed and _rng.randf() < 0.3:
			values[_rng.randi_range(0, 2)] = _special()
		if _rng.randf() < 0.02:
			values.resize(_rng.randi_range(0, 4))
		var stage_t: float = time_now + dt * [0.0, 0.5, 0.5, 1.0][_rng.randi_range(0, 3)]
		if drawn.malformed and _rng.randf() < 0.2:
			stage_t = [NAN, -dt, INF, -INF][_rng.randi_range(0, 3)]
		var wind := M.v3(0.0, 0.0, 0.0) if _rng.randf() < 0.5 else M.v3(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 6.0), _rng.randf_range(-1.0, 1.0))
		var rho: float = 1.225 if _rng.randf() < 0.6 else _rng.randf_range(0.9, 1.3)
		var rpm: float = aux[Session.AUX_RPM]
		var inputs := [s, aux, values, stage_t]
		# Propeller: Dynamics' stage inflow then Propulsion.loads.
		var air: Dictionary = Air.compute(s, wind, rho)
		var point: Dictionary = Propulsion.stage_air_velocity(s, air, prop)
		var prop_reference: PackedFloat64Array = Propulsion.loads(point.velocity_body, rpm, prop, rho) if point.ok \
			else PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN])
		_compare("prop_loads", prop_reference, _native.prop_component(s, wind, rho, rpm), [s, wind, rho, rpm])
		var hull_reference: PackedFloat64Array = HullContact.loads(s, hull)
		_compare("hull_loads", hull_reference, _native.hull_component(s), s)
		var ground_reference: Dictionary = session._ground_evaluation(s, aux, values)
		var ground_native: Dictionary = _native.ground_component(s, values)
		_compare("ground_evaluation_ok", PackedFloat64Array([1.0 if ground_reference.ok else 0.0]),
			PackedFloat64Array([1.0 if ground_native.ok else 0.0]), inputs)
		if ground_reference.ok and ground_native.ok:
			_compare("ground_evaluation_loads", ground_reference.loads, ground_native.loads, inputs)
			_compare("ground_evaluation_derivative", ground_reference.derivative, ground_native.derivative, inputs)
		_compare("ground_up", PackedFloat64Array([session._ground_up(s)]), PackedFloat64Array([_native.ground_up_component(s)]), s)
		var stage_reference: Dictionary = session._wheel_evaluate(s, values, stage_t)
		var stage_native: Dictionary = _native.stage(s, values, stage_t)
		_compare_stage(stage_reference, stage_native, inputs)
		var group := "stage_" + str(drawn.kind)
		_tally(group, "states")
		if drawn.malformed: _tally(group, "malformed")
		if not hull_reference.is_empty(): _tally(group, "hull_loaded")
		if not stage_reference.is_empty():
			_tally(group, "stage_shaped")
			var finite := true
			for value: float in stage_reference.loads:
				finite = finite and is_finite(value)
			_tally(group, "stage_valid" if finite else "stage_nonfinite_loads")
		if bool(ground_reference.ok) and not ground_reference.loads.is_empty(): _tally(group, "ground_loaded")
		if rpm >= Propulsion.STOPPED_RPM and point.ok: _tally(group, "propeller_turning")
		if not context.lake.is_empty() and not hull.get("lake", {}).is_empty() \
				and not HullContact._hull_clear_of_lake(s, hull) and is_finite(s[0]):
			_tally(group, "hull_near_lake")
			var points: PackedFloat64Array = hull.points
			for k in range(0, points.size(), 3):
				var point_ned: PackedFloat64Array = HullContact._point_ned(s, points.slice(k, k + 3))
				if bool(HullContact._lake_sample(hull, point_ned).get("covered", false)):
					_tally(group, "hull_points_lake_covered")
	session.sim.aux = context.aux


## Stage dictionaries: same key set and order, then each array's bytes.
func _compare_stage(reference: Dictionary, native: Dictionary, inputs: Array) -> void:
	_compare("stage_shape", PackedFloat64Array([reference.size(), 1.0 if reference.keys() == native.keys() else 0.0]),
		PackedFloat64Array([native.size(), 1.0]), inputs)
	if reference.is_empty() or native.is_empty():
		return
	_compare("stage_loads", reference.loads, native.loads, inputs)
	_compare("stage_derivative", reference.derivative, native.derivative, inputs)
	_compare("stage_rotor_momentum", reference.rotor_momentum, native.rotor_momentum, inputs)
	_compare("stage_bytes", var_to_bytes(reference), var_to_bytes(native), inputs)


func _check_stage_refusals(session: Node) -> void:
	var base: Dictionary = Adapter.config_for(session)
	var cases := {}
	for flag: String in ["retractable", "glow", "coupled", "turbine", "liquid", "finite_fuel", "flaps",
			"spatial_weather", "turbulence", "vertical_atmosphere", "weather_pending_reset", "not_calm", "slipstream",
			"rotor_dynamics"]:
		var flagged := base.duplicate()
		flagged[flag] = true
		cases["session_" + flag] = flagged
	var tilted := base.duplicate(true)
	# Tilted axes are now qualified; malformed geometry must still refuse.
	tilted.model.propulsion.axis = PackedFloat64Array([0.999, 0.0447])
	cases["prop_axis_shape"] = tilted
	var electric := base.duplicate(true)
	electric.model.propulsion.kind = "electric_prop"
	cases["prop_electric_kind"] = electric
	var live_mass := base.duplicate(true)
	live_mass.hull.geometry_only = true
	cases["hull_geometry_only"] = live_mass
	var washed := base.duplicate(true)
	washed.layout.rotor_index = 2
	cases["layout_wash_pieces"] = washed
	for name: String in cases:
		var result: Dictionary = _native.prepare_stage(cases[name])
		_report.refusals[name] = {refused = not result.ok, error = result.error}
		if result.ok:
			_failures.append("D6: native stage accepted " + name)
	var again: Dictionary = _native.prepare_stage(base)
	if not again.ok:
		_failures.append("prepare_stage of the unmodified config failed after refusals")
