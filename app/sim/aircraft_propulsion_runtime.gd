extends RefCounted

const Propulsion: Script = preload("res://physics/propulsion.gd")
const Turbine: Script = preload("res://physics/turbine.gd")
const GlowFlight: Script = preload("res://physics/glow/flight.gd")

const CALLBACK_FIELDS: PackedStringArray = [
	"continuous_step",
	"continuous_evaluate",
	"continuous_loads",
	"continuous_derivative",
	"continuous_rotor_momentum",
	"continuous_aux",
]


## The adapter reports the current fixed-wing single-installation route. It does not
## create propulsion instances or select a different physics law.
static func prepare_callbacks(session: Node) -> Dictionary:
	var context: Dictionary = _context(session)
	if not context.ok:
		return context
	var result: Dictionary = _base_description(context)
	for field: String in CALLBACK_FIELDS:
		result[field] = Callable()

	# Match FlightSession._configure_continuous_callbacks selection and early-return order.
	if context.glow_active:
		result.continuous_step = GlowFlight.step.bind(session)
		result.continuous_evaluate = GlowFlight.evaluate.bind(session)
		result.continuous_aux = Callable(session, "_coupled_aux")
		return result
	if context.turbine_continuous:
		result.continuous_evaluate = Callable(session, "_turbine_evaluate")
		result.continuous_aux = Callable(session, "_turbine_aux")
		return result

	var coupled: bool = bool(session.call("shaft_is_coupled"))
	var has_wheels: bool = int(session.call("wheel_count")) > 0
	if context.electric:
		result.continuous_step = Callable(session, "_electric_step")
	result.continuous_evaluate = Callable(session, "_coupled_evaluate") if coupled else (
		Callable(session, "_wheel_evaluate") if has_wheels else Callable())
	result.continuous_loads = Callable(session, "_coupled_loads") if coupled else Callable(session, "_wash_loads")
	result.continuous_derivative = Callable(session, "_coupled_derivative") if coupled else Callable(session, "_wash_derivative")
	result.continuous_rotor_momentum = Callable(session, "_coupled_rotor") if coupled else Callable()
	result.continuous_aux = Callable(session, "_coupled_aux") if coupled else Callable()
	return result


## Read-only accepted-endpoint observation using the session's established family accessors.
static func observe(session: Node) -> Dictionary:
	var context: Dictionary = _context(session)
	if not context.ok:
		return context
	if not session.has_method("trace_meta"):
		return _error("the session is missing trace_meta")
	var simulation_value: Variant = session.get("sim")
	if not simulation_value is Node:
		return _error("the flight session has no simulation node")
	var metadata_value: Variant = session.call("trace_meta")
	if typeof(metadata_value) != TYPE_DICTIONARY:
		return _error("the session did not provide trace metadata")
	context.trace_meta = metadata_value
	context.law_identity = str(context.trace_meta.get("propulsion_model", ""))
	if str(context.law_identity).is_empty():
		return _error("trace metadata did not name the active propulsion law")
	var result: Dictionary = _base_description(context)
	var metadata: Dictionary = context.trace_meta
	var simulation: Node = simulation_value
	var family_state: Dictionary = {}
	if context.glow_active:
		family_state = session.call("glow_state")
	elif context.turbine:
		family_state = session.call("turbine_state")
	elif context.electric:
		family_state = session.call("electrical_state")
	if not family_state.is_empty() and not bool(family_state.get("ok", false)):
		result.ok = false
		result.errors = PackedStringArray(["family telemetry is unavailable at this session boundary"])
		result.telemetry = family_state
		result.state_layout = _state_layout(metadata, simulation)
		return result

	var auxiliary_layout: Variant = _decode_array(metadata.get("aux_layout", ""))
	if typeof(auxiliary_layout) != TYPE_ARRAY:
		return _fail(result, "trace metadata does not expose an auxiliary state layout")
	var rpm_index: int = auxiliary_layout.find("engine_rpm")
	var auxiliary_value: Variant = simulation.get("aux")
	if rpm_index < 0 or typeof(auxiliary_value) != TYPE_PACKED_FLOAT64_ARRAY \
			or rpm_index >= auxiliary_value.size():
		return _fail(result, "the declared auxiliary layout has no engine RPM value")

	var rpm: float
	var rpm_source: String
	if family_state.has("rpm"):
		rpm = float(family_state.rpm)
		rpm_source = "family_telemetry"
	else:
		rpm = float(auxiliary_value[rpm_index])
		rpm_source = "aux_layout:engine_rpm"
	if not is_finite(rpm) or rpm < 0.0:
		return _fail(result, "the accepted-endpoint RPM is not finite and nonnegative")

	result.actual_rpm = rpm
	result.rpm_source = rpm_source
	result.telemetry = family_state
	result.state_layout = _state_layout(metadata, simulation)
	return result


static func _context(session: Node) -> Dictionary:
	if session == null or not is_instance_valid(session):
		return _error("a live flight session is required")
	for method_name: String in [
		"glow_is_active", "turbine_is_continuous", "shaft_is_coupled", "wheel_count"
	]:
		if not session.has_method(method_name):
			return _error("the session is missing " + method_name)
	var aircraft_value: Variant = session.get("aircraft")
	if typeof(aircraft_value) != TYPE_DICTIONARY or not bool(aircraft_value.get("ok", false)):
		return _error("a validated aircraft is required")
	var model_value: Variant = aircraft_value.get("model", {})
	if typeof(model_value) != TYPE_DICTIONARY:
		return _error("the validated aircraft model is malformed")
	var propulsion_value: Variant = model_value.get("propulsion", null)
	if typeof(propulsion_value) != TYPE_DICTIONARY:
		return _error("the validated model has no propulsion dictionary")
	var model: Dictionary = model_value
	var propulsion: Dictionary = propulsion_value
	var model_id: String = str(model.get("id", "")).strip_edges()
	if model_id.is_empty():
		return _error("the validated aircraft model has no stable ID")
	var kind: String = Propulsion.source_kind(propulsion)
	if kind == "unsupported":
		return _error("the normalized propulsion source kind is unsupported")
	var glow_active: bool = bool(session.call("glow_is_active"))
	var turbine_continuous: bool = bool(session.call("turbine_is_continuous"))
	var turbine: bool = Turbine.is_turbine(propulsion)
	var electric: bool = Propulsion.is_electric(propulsion)
	var family: String
	if glow_active:
		var glow_value: Variant = propulsion.get("glow", {})
		var profile_value: Variant = glow_value.get("profile", {}) if typeof(glow_value) == TYPE_DICTIONARY else {}
		family = str(profile_value.get("family", "glow")) if typeof(profile_value) == TYPE_DICTIONARY else "glow"
	elif turbine:
		family = "turbine_continuous" if turbine_continuous else "turbine_sampled"
	elif electric:
		family = "electric_finite_battery" if Propulsion.has_dynamic_battery(propulsion) else "electric_fixed_voltage"
	elif bool(session.call("shaft_is_coupled")):
		family = "propeller_shaft_coupled"
	elif Propulsion.has_shaft(propulsion):
		family = "propeller_shaft_sampled"
	else:
		family = "legacy_propeller_rpm_lag"
	return {
		ok = true,
		session = session,
		model = model,
		propulsion = propulsion,
		model_id = model_id,
		kind = kind,
		family = family,
		glow_active = glow_active,
		turbine = turbine,
		turbine_continuous = turbine_continuous,
		electric = electric,
	}


static func _base_description(context: Dictionary) -> Dictionary:
	var result: Dictionary = {
		ok = true,
		installation_id = "aircraft/%s/propulsion/%s" % [str(context.model_id), str(context.propulsion.get("id", "single"))],
		installation_scope = "current_single_installation",
		kind = context.kind,
		family = context.family,
		contract_identity = "openrc-aircraft-propulsion-runtime-v1",
	}
	if context.has("law_identity"):
		result.law_identity = context.law_identity
	return result


static func _state_layout(metadata: Dictionary, simulation: Node) -> Dictionary:
	var continuous_value: Variant = simulation.get("continuous")
	var continuous_size: int = continuous_value.size() if typeof(continuous_value) == TYPE_PACKED_FLOAT64_ARRAY else -1
	var result: Dictionary = {
		"body": _decode_array(metadata.get("state_layout", "")),
		"aux": _decode_array(metadata.get("aux_layout", "")),
		"continuous_description": str(metadata.get("continuous_layout", "")),
		"continuous_size": continuous_size,
	}
	if metadata.has("wheel_state_layout"):
		result.wheels = _decode_array(metadata.wheel_state_layout)
	return result


static func _decode_array(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		return value.duplicate(true)
	if typeof(value) != TYPE_STRING:
		return null
	var parsed: Variant = JSON.parse_string(value)
	return parsed if typeof(parsed) == TYPE_ARRAY else null


static func _fail(result: Dictionary, message: String) -> Dictionary:
	result.ok = false
	result.errors = PackedStringArray([message])
	return result


static func _error(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message])}
