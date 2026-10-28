## NK-3 research-only fixed-wing stage configuration and ownership boundary.
## The selected built-in adapter creates the native config once; its detached
## result and source identity belong to the same preparation transaction.
## Per-tick comparison is owned by nk::ConfigurationGuard, not this script.
extends RefCounted

const NativeWeather := preload("native_weather.gd")
const WeatherAdapter := preload("weather_adapter.gd")
const ElectricAdapter := preload("electric_stage_adapter.gd")
const LiquidAdapter := preload("liquid_stage_adapter.gd")
const GlowAdapter := preload("glow_stage_adapter.gd")
const PrescribedAdapter := preload("prescribed_stage_adapter.gd")
const HelicopterAdapter := preload("helicopter_stage_adapter.gd")
const LiquidFlight := preload("res://sim/liquid_fuel_flight.gd")
const GlowFlight := preload("res://physics/glow/flight.gd")

const SESSION_FIELDS := ["aircraft", "_hull_contact", "_airframe_surfaces", "_ground_effect_reach",
	"soft_hull_contacts", "_shaft_integrator", "_shaft_explicit", "_shaft_pending_reset"]
const HELICOPTER_SESSION_FIELDS := ["aircraft", "_trim", "start_choice", "_ready_to_fly"]
const ENVIRONMENT_FIELDS := ["surfaces", "lake"]
const SIM_FIELDS := ["mass", "inertia", "gravity"]
# Stage is intentionally excluded: NativeStage installs and verifies it itself.
const VEHICLE_FIELDS := ["input_size", "aux_size", "modes_size", "continuous_size", "identity", "state_layout_identity",
	"loads", "block_loads", "block_derivative", "stage_rotor_momentum", "rotor_momentum", "pre_tick", "post_tick",
	"post_tick_joint", "block_aux", "step_policy", "events", "substeps", "substeps_joint", "endpoint_transition", "state_validator"]


class Identity:
	extends RefCounted
	var owner_kind: String = "fixed_wing"
	var session: Node
	var session_script: Script
	var sim: Node
	var sim_script: Script
	var environment: RefCounted
	var environment_script: Script
	var vehicle: RefCounted
	var vehicle_script: Script
	var reference_stage: Callable
	var input_size: int
	var aux_size: int
	var continuous_size: int
	var modes_size: int
	var session_values: Dictionary
	var environment_values: Dictionary
	var sim_values: Dictionary
	var vehicle_values: Dictionary


## Only registered stage adapters can define a native config. Call the chosen
## builder once, check its common source fields and weather snapshot exactly,
## and freeze a detached copy before returning it to the native decoder.
static func prepare(session: Node, builder: Callable) -> Dictionary:
	var expected_stage := Callable()
	if builder == WeatherAdapter.config_for:
		expected_stage = Callable(session, "_wheel_evaluate") if session.wheel_count() > 0 else Callable()
	elif builder == PrescribedAdapter.config_for:
		match PrescribedAdapter.kind_for(session):
			"shaft-split", "turbine-sampled":
				expected_stage = Callable(session, "_wheel_evaluate") if session.wheel_count() > 0 else Callable()
			"shaft-coupled": expected_stage = Callable(session, "_coupled_evaluate")
			"turbine-continuous": expected_stage = Callable(session, "_turbine_evaluate")
			_: return {ok = false, reason = "unsupported prescribed source"}
	elif builder == ElectricAdapter.config_for:
		expected_stage = Callable(session, "_coupled_evaluate")
	elif builder == LiquidAdapter.config_for:
		expected_stage = LiquidFlight.evaluate.bind(session)
	elif builder == GlowAdapter.config_for:
		expected_stage = GlowFlight.evaluate.bind(session)
	else:
		return {ok = false, reason = "unregistered native stage config builder"}
	var weather: Dictionary = NativeWeather.prepare(session)
	if not weather.get("ok", false):
		return {ok = false, reason = str(weather.get("reason", "weather refused"))}
	if session._shaft_pending_reset or session.sim.model.stage != expected_stage:
		return {ok = false, reason = "pending shaft or mismatched reference stage owner"}
	if not expected_stage.is_valid() and (session.sim.model.loads != Callable(session, "_loads") \
			or session.sim.model.rotor_momentum != Callable(session, "rotor_momentum") \
			or session.sim.model.block_loads != Callable(session, "_wash_loads") \
			or session.sim.model.block_derivative != Callable(session, "_wash_derivative")):
		return {ok = false, reason = "mismatched reference split callback owner"}
	var config: Variant = builder.call(session)
	if not config is Dictionary or config.is_empty() or not config.has_all(["model", "hull", "surfaces", "lake",
			"soft_hull", "ground_effect_reach", "weather", "dt", "layout"]) or not config.layout is Dictionary:
		return {ok = false, reason = "native stage builder returned an incomplete config"}
	if var_to_bytes(config.model) != var_to_bytes(session.aircraft.model) \
			or var_to_bytes(config.hull) != var_to_bytes(session._hull_contact) \
			or var_to_bytes(config.surfaces) != var_to_bytes(session.environment.surfaces) \
			or var_to_bytes(config.lake) != var_to_bytes(session.environment.lake) \
			or var_to_bytes(config.soft_hull) != var_to_bytes(session.soft_hull_contacts) \
			or var_to_bytes(config.ground_effect_reach) != var_to_bytes(session._ground_effect_reach) \
			or var_to_bytes(config.weather) != var_to_bytes(weather.snapshot) \
			or var_to_bytes(config.dt) != var_to_bytes(weather.identity.dt) \
			or config.layout.get("turbulence") != weather.identity.turbulence_index \
			or config.layout.get("aux_size") != session.sim.aux.size() \
			or config.layout.get("input_count") != session.sim.inputs.size():
		return {ok = false, reason = "native stage config differs from its live source identity"}
	if config.has("gravity") and var_to_bytes(config.gravity) != var_to_bytes(session.sim.gravity):
		return {ok = false, reason = "native stage gravity differs from its live source"}
	if config.has("inertia") and var_to_bytes(config.inertia) != var_to_bytes(session.sim.inertia):
		return {ok = false, reason = "native stage inertia differs from its live source"}
	var identity := _capture_identity(session, expected_stage, "fixed_wing", SESSION_FIELDS)
	var detached: Dictionary = config.duplicate(true)
	NativeWeather._freeze_containers(detached)
	return {ok = true, config = detached, identity = identity, weather_identity = weather.identity}


## Rotorcraft provide separate prepared helicopter and weather inputs. Their
## reference stage and lifecycle/layout are distinct from fixed-wing sessions.
static func prepare_helicopter(session: Node) -> Dictionary:
	var weather: Dictionary = NativeWeather.prepare_helicopter(session)
	if not weather.get("ok", false):
		return {ok = false, reason = str(weather.get("reason", "helicopter weather refused"))}
	var expected_stage := Callable(session, "_stage")
	if session.sim.model.stage != expected_stage:
		return {ok = false, reason = "mismatched helicopter reference stage owner"}
	var snapshot: Dictionary = HelicopterAdapter.snapshot(session)
	if snapshot.get("format") != "openrc-nk3-helicopter-snapshot-v1" \
			or var_to_bytes(snapshot.get("context")) != var_to_bytes(session.aircraft.context) \
			or var_to_bytes(snapshot.get("skids")) != var_to_bytes(session.aircraft.skids) \
			or var_to_bytes(snapshot.get("surfaces")) != var_to_bytes(session.environment.surfaces):
		return {ok = false, reason = "helicopter stage config differs from its live source identity"}
	var identity := _capture_identity(session, expected_stage, "helicopter", HELICOPTER_SESSION_FIELDS)
	var detached: Dictionary = snapshot.duplicate(true)
	NativeWeather._freeze_containers(detached)
	return {ok = true, snapshot = detached, weather = weather.snapshot,
		identity = identity, weather_identity = weather.identity}


static func _capture_identity(session: Node, expected_stage: Callable, owner_kind: String, fields: Array) -> Identity:
	var identity := Identity.new()
	identity.owner_kind = owner_kind
	identity.session = session
	identity.session_script = session.get_script()
	identity.sim = session.sim
	identity.sim_script = identity.sim.get_script()
	identity.environment = session.environment
	identity.environment_script = identity.environment.get_script()
	identity.vehicle = session.sim.model
	identity.vehicle_script = identity.vehicle.get_script()
	identity.reference_stage = expected_stage
	identity.input_size = session.sim.inputs.size()
	identity.aux_size = session.sim.aux.size()
	identity.continuous_size = session.sim.continuous.size()
	identity.modes_size = session.sim.modes.size()
	identity.session_values = _capture(session, fields)
	identity.environment_values = _capture(identity.environment, ENVIRONMENT_FIELDS)
	identity.sim_values = _capture(identity.sim, SIM_FIELDS)
	identity.vehicle_values = _capture(identity.vehicle, VEHICLE_FIELDS)
	return identity


static func _capture(provider: Object, fields: Array) -> Dictionary:
	var out := {}
	for key: String in fields:
		var value: Variant = provider.get(key)
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		elif typeof(value) in [TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT64_ARRAY,
				TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
			value = value.duplicate()
		out[key] = value
	NativeWeather._freeze_containers(out)
	return out
