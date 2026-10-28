## Research-only bridge for X-Cell's actual VehicleModel.stage. The accepted
## tick, lifecycle, stop-event policy, contact observers and input owner remain
## in the helicopter session and Simulation; native RK stages sample weather.
extends RefCounted

const WeatherAdapter := preload("weather_adapter.gd")
const WeatherField := preload("res://physics/wind_field.gd")
const WeatherConfig := preload("res://physics/wind_config.gd")
const SimEnvironment := preload("res://sim/environment.gd")


static func snapshot(session: Node) -> Dictionary:
	return {format = "openrc-nk3-helicopter-snapshot-v1", context = session.aircraft.context,
		skids = session.aircraft.skids, surfaces = session.ground_surfaces.duplicate()}


## Helicopter currently supports only the built-in uniform provider, without
## turbulence or a vertical atmosphere. The cached field is rederived once at
## preparation, so a changed provider is not silently replaced with its config.
static func weather_snapshot(session: Node) -> Dictionary:
	var environment: Variant = session.environment
	if not is_instance_valid(environment) or environment.get_script() != SimEnvironment:
		return {}
	var field: Variant = environment.weather
	if not is_instance_valid(field) or field.get_script() != WeatherField or field != session._weather \
			or environment.turbulence.is_valid() or field.is_spatial() or field.has_turbulence() \
			or field.has_vertical_atmosphere():
		return {}
	var configuration: Dictionary = field.configuration()
	var validated: Dictionary = WeatherConfig.validate(configuration)
	if not validated.get("ok", false) or validated.config != configuration:
		return {}
	var rebuilt: Dictionary = WeatherField.build(configuration)
	if not rebuilt.get("ok", false) or var_to_bytes(WeatherAdapter._field_inputs(field)) \
			!= var_to_bytes(WeatherAdapter._field_inputs(rebuilt.field)):
		return {}
	var actual: Dictionary = WeatherAdapter.snapshot(field)
	if var_to_bytes(actual) != var_to_bytes(WeatherAdapter.snapshot(rebuilt.field)):
		return {}
	return actual


static func tick(session: Node, inputs: PackedFloat64Array) -> Dictionary:
	return {inputs = inputs.duplicate(), mode = session.flight_mode, trainer = session.trainer_enabled,
		hold = session.zero_drive_hold, armed = session.power.armed, ground_start = session.start_choice == "ground",
		spool_start_s = float(session.power.spool_start_s), trim = session._trim.duplicate(true)}


static func prepare(session: Node, native: Object) -> Dictionary:
	var weather := weather_snapshot(session)
	if weather.is_empty(): return {ok = false, error = "helicopter weather provider differs from the supported session"}
	return native.prepare_heli_stage(snapshot(session), weather)


## Explicit research installation; an actual application install also needs
## owner-side configuration invalidation and fault-message handoff.
static func install(session: Node, native: Object) -> Dictionary:
	var prepared := prepare(session, native)
	if not prepared.get("ok", false): return prepared
	var model: RefCounted = session.sim.model
	var previous_stage: Callable = model.stage
	var previous_pre_tick: Callable = model.pre_tick
	if not previous_stage.is_valid() or previous_stage != Callable(session, "_stage"):
		return {ok = false, error = "helicopter model stage is not the built-in session evaluator"}
	var context_state := {ok = true}
	var wrapped := func(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> Variant:
		var next: Variant = previous_pre_tick.call(aux, inputs, dt) if previous_pre_tick.is_valid() else aux
		if next is PackedFloat64Array and next.size() == aux.size():
			context_state.ok = bool(context_state.ok) and native.set_heli_tick_context(tick(session, inputs))
			if not context_state.ok: return PackedFloat64Array()
		return next
	if not native.set_heli_tick_context(tick(session, session.sim.inputs)):
		return {ok = false, error = str(native.heli_last_failure())}
	model.pre_tick = wrapped
	model.stage = Callable(native, "stage")
	var restore := func() -> void:
		model.stage = previous_stage
		model.pre_tick = previous_pre_tick
	return {ok = true, error = "", context = context_state, wrapped = wrapped, restore = restore}
