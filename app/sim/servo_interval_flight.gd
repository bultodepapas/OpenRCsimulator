extends RefCounted
## First explicitly selected fixed-wing servo trajectory. No per-tick session scratch.
const Law := preload("res://physics/slew_trajectory.gd")
const Model := preload("res://sim/vehicle_model.gd")
const Step := preload("res://sim/electric_contact_step.gd")
const RB := preload("res://physics/rigid_body.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Wash := preload("res://physics/wash_transport.gd")
const CHECKPOINT_FORMAT := "openrc-flight-checkpoint v15"
const LAYOUT_PREFIX := Law.LAW+";"


static func selected(model: Variant) -> bool:
	return model is Dictionary and model.get("controls") is Dictionary and model.controls.has("servo_integration")


static func configured(session: Node) -> bool:
	var simulation: Node = session.get("sim")
	if simulation==null or simulation.get("model")==null:return false
	var vehicle: RefCounted = simulation.get("model")
	return vehicle.state_layout_identity.begins_with(LAYOUT_PREFIX)


static func admission(session: Node, model: Dictionary) -> Dictionary:
	if not selected(model): return {ok = true}
	# Derived sessions can override air_data/wind_at with nonautonomous forcing.
	# The first domain admits only the base provider, whose calm/reference laws
	# are independent of absolute stage time. Origin+offset remain separate in
	# the generic protocol for future providers that need the full clock.
	if session.get_script().resource_path != "res://sim/flight_session.gd":
		return _error("servo law v1 requires the base reference atmosphere provider")
	if model.controls.servo_integration != Law.LAW:
		return _error("unsupported servo integration law")
	var prop: Dictionary = model.get("propulsion", {})
	if not Propulsion.is_electric(prop) or not Propulsion.has_dynamic_battery(prop) or Propulsion.has_pack_ecm(prop) \
		or not model.get("landing_gear", {}).is_empty() or not model.get("flaps", {}).is_empty() \
		or model.controls.get("layout", "") == "elevon" or Wash.enabled(prop) or not prop.get("slipstream", {}).is_empty():
		return _error("servo law v1 requires conventional gearless finite OCV/resistance electric flight without flaps or propwash transport")
	if not session.call("servo_reference_selected") or session.call("stage_backend_identity").get("backend", "") != "gdscript_reference" or not str(session.get("stage_backend_error")).is_empty():
		return _error("servo law requires an explicit gdscript_reference backend selection")
	if not session.call("weather_is_calm") or not session.call("atmosphere_is_reference") \
		or session.get("_weather").is_spatial() or session.get("_failures") != null or session.get("soft_hull_contacts"):
		return _error("servo law v1 requires calm reference atmosphere without failures or soft hull contacts")
	for field: String in ["_collision_world", "_lake", "_rc_track"]:
		if not session.get(field).is_empty(): return _error("servo law v1 does not admit scenery, lake or RC-track contact contexts")
	for offset: float in session.get("_airframe_offset"):
		if offset != 0.0: return _error("servo law v1 does not admit out-of-trim practice offsets")
	if session.get("start_choice") not in ["airborne", "airborne_half_power", "hand_launch"]:
		return _error("servo law v1 requires an airborne or hand-launch start")
	if session.get("_shaft_explicit") and session.call("shaft_integrator") != "coupled-rk4":
		return _error("servo law requires coupled-rk4 shaft integration")
	return {ok = true}


static func install(vehicle: RefCounted, session: Node) -> void:
	var aux_count: int = 4 + (1 if int(session.call("downwash_index")) >= 0 else 0)
	vehicle.callback_protocol = Model.PROTOCOL_JOINT_INTERVAL_LOCAL
	vehicle.input_size = 4
	vehicle.aux_size = aux_count
	vehicle.modes_size = 1
	vehicle.continuous_size = 4
	vehicle.state_layout_identity = "%s;body13;aux%d;shaft-charge-energy-heat;modes1" % [Law.LAW, aux_count]
	vehicle.identity.servo_integration = Law.LAW
	vehicle.pre_tick = pre_tick.bind(session)
	vehicle.stage_interval = evaluate.bind(session)
	vehicle.step_policy_interval = advance.bind(session)
	for field: String in ["stage", "step_policy", "block_loads", "block_derivative", "stage_rotor_momentum", "substeps", "substeps_joint"]:
		vehicle.set(field, Callable())
	var events: Array[Dictionary] = []
	vehicle.events = events
	vehicle.block_aux = Callable(session, "_coupled_aux")


static func pre_tick(actual: PackedFloat64Array, input: PackedFloat64Array, dt: float, session: Node) -> PackedFloat64Array:
	var model: Dictionary = session.get("aircraft").get("model", {})
	if not admission(session, model).ok or not installed(session, model): return PackedFloat64Array()
	var plan := _plan(actual, input, dt, model)
	if not plan.ok: return PackedFloat64Array()
	var next: PackedFloat64Array = session.call("_kernel_pre_step", actual, input, dt)
	if next.size() != actual.size(): return PackedFloat64Array()
	for index: int in 3: next[index + 1] = plan.endpoint[index]
	return next


static func installed(session: Node, model: Dictionary) -> bool:
	var simulation: Node = session.get("sim")
	return selected(model) and simulation != null and simulation.model.callback_protocol == Model.PROTOCOL_JOINT_INTERVAL_LOCAL \
		and simulation.model.identity.get("servo_integration", "") == Law.LAW and session.call("shaft_is_coupled")


static func evaluate(body: PackedFloat64Array, continuous: PackedFloat64Array, at: float,
		context: Dictionary, session: Node) -> Dictionary:
	if not admission(session, session.get("aircraft").model).ok or not installed(session, session.get("aircraft").model): return {}
	var sampled := _sample(context, at, session.get("aircraft").model)
	if not sampled.ok: return {}
	var absolute_at: float = context.time_s + at
	var result: Dictionary = session.call("_coupled_response", body, continuous, absolute_at, {}, true, {}, false, sampled.aux)
	if not result.get("ok", false): return {}
	var extra := PackedFloat64Array([result.rpm_rate])
	session.call("_append_battery_rates", extra, result)
	if extra.size() != 4: return {}
	return {loads = result.loads, derivative = extra, rotor_momentum = session.call("_coupled_rotor", body, continuous, absolute_at)}


static func advance(combined: PackedFloat64Array, at: float, dt: float, derivative: Callable,
		first: PackedFloat64Array, context: Dictionary, session: Node) -> Variant:
	var admitted := admission(session, session.get("aircraft").model)
	if not admitted.ok: return _failure(admitted.message)
	var plan := _checked_plan(context, session.get("aircraft").model)
	if not plan.ok: return _failure(str(plan.get("message", "invalid servo interval")))
	var result := Step.advance_at_offsets(combined, at, dt, derivative, first, RB.SIZE, RB.SIZE + 1,
		Callable(session, "_project_electric_stop"), 1, plan.offsets, true)
	if not result.get("ok", false): return _failure(str(result.get("message", "servo partition failed")))
	# Preserve the checked local chronology; never sort events by rounded absolute
	# timestamps. Fail closed if distinct local events cannot retain that order.
	var previous_local := -INF
	var previous_absolute := -INF
	for event: Dictionary in result.events:
		var local_at: float = event.time_s
		var absolute_at: float = context.time_s + local_at
		if local_at < 0.0 or local_at > dt or local_at < previous_local \
			or (local_at > previous_local and absolute_at <= previous_absolute):
			return _failure("local event chronology cannot be represented on the public clock")
		event.time_s = absolute_at
		previous_local = local_at
		previous_absolute = absolute_at
	return {state = result.state, events = result.events}


static func _plan(actual: PackedFloat64Array, input: PackedFloat64Array, dt: float, model: Dictionary) -> Dictionary:
	if actual.size() < 4 or input.size() != 4: return _error("servo interval layout mismatch")
	var rate: float = model.controls.servo_rate
	return Law.prepare(actual.slice(1, 4), input.slice(0, 3), PackedFloat64Array([rate, rate, rate]), dt)


static func _checked_plan(context: Dictionary, model: Dictionary) -> Dictionary:
	if context.get("kind", "") != "interval": return _error("servo policy requires an interval")
	var plan := _plan(context.before_aux, context.inputs, context.dt, model)
	if not plan.ok: return plan
	if context.after_aux.slice(1, 4).to_byte_array() != plan.endpoint.to_byte_array():
		return _error("servo endpoints do not match the selected trajectory")
	return plan


static func _sample(context: Dictionary, at: float, model: Dictionary) -> Dictionary:
	var values: PackedFloat64Array = context.after_aux.duplicate()
	if context.kind == "boundary": return {ok = true, aux = values}
	var plan := _checked_plan(context, model)
	if not plan.ok: return plan
	var sample := Law.sample(plan, at)
	if sample.size() != 3: return _error("servo stage time outside interval")
	for index: int in 3: values[index + 1] = sample[index]
	return {ok = true, aux = values}


static func _error(message: String) -> Dictionary:
	return {ok = false, message = message}


static func _failure(message: String) -> Dictionary:
	return {failure = "servo integration: " + message}
