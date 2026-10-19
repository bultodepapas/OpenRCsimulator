extends RefCounted

## Standalone lifecycle around the mean-cycle glow source and thermal kernels.
## Cycle work stays averaged; accepted opportunity events are available to replay/audio.
const Source := preload("res://physics/glow/source.gd")
const Thermal := preload("res://physics/glow/thermal.gd")

const FAMILIES := ["glow_2t", "glow_4t"]
const CONTINUOUS_KEYS := [
	"fuel_kg",
	"temperature_k",
	"servo_fraction",
	"air_fraction",
	"fuel_transport_kg_s",
	"phase_revolutions",
]
const PHASE_TOLERANCE := 1.0e-12
const FIRE_TOLERANCE := 1.0e-12
const MAX_OPPORTUNITIES_PER_ACCEPT := 64
const LOW_FLOW := 1.0e-15


## Immutable installation snapshot for repeated RK stages. Dynamic lifecycle state
## remains in the caller's serialized Dictionary and is never stored here.
class PreparedEvaluator extends RefCounted:
	var _model: Dictionary
	var _settings: Dictionary
	var _source: Source.PreparedEvaluator

	func _init(model: Dictionary, settings: Dictionary, source: Source.PreparedEvaluator) -> void:
		_model = model.duplicate(true)
		_settings = settings.duplicate(true)
		_make_read_only(_model)
		_make_read_only(_settings)
		_source = source

	func _make_read_only(value: Variant) -> void:
		if value is Dictionary:
			var keys: Array = value.keys()
			for key: Variant in keys:
				_make_read_only(value[key])
			value.make_read_only()
		elif value is Array:
			for index: int in range(value.size()):
				_make_read_only(value[index])
			value.make_read_only()


## Explicit fixture values only. None are calibrated or suitable as an installation profile.
static func candidate_settings_for_tests(family: String) -> Dictionary:
	if family not in FAMILIES:
		return {}
	return {
		"evidence_kind": "estimated",
		"evidence_source": "synthetic software fixture only; not measured installation data",
		"idle_admission": 0.08,
		"servo_time_constant_s": 0.06,
		"air_time_constant_s": 0.10,
		"fuel_transport_time_constant_s": 0.15,
		"stall_rpm": 1200.0,
		"minimum_start_rpm": 1800.0,
		"temperature_firing_min_k": 280.0,
		"temperature_firing_full_k": 360.0,
		"temperature_firing_hot_full_k": 450.0,
		"temperature_firing_hot_zero_k": 560.0,
		"lean_misfire_zero_ratio": 0.20,
		"lean_misfire_start_ratio": 0.60,
		"rich_misfire_start_ratio": 1.25,
		"rich_misfire_zero_ratio": 1.80,
		"thermal": {
			"heat_capacity_j_k": 100.0,
			"head_heat_fraction": 0.25,
			"cooling_base_w_k": 2.0,
			"cooling_airflow_w_s_m_k": 0.10,
			"premix_evaporation_j_kg": 1000000.0,
			"evaporation_head_fraction": 0.10,
		},
	}


static func continuous_keys() -> Array[String]:
	var result: Array[String] = []
	for key: String in CONTINUOUS_KEYS:
		result.append(key)
	return result


## The parent RK integrator carries only these six continuous float64 values.
## Discrete fields stay in the detached Dictionary and are changed by accepted().
static func pack_state(state: Dictionary) -> PackedFloat64Array:
	if not _valid_state(state):
		return PackedFloat64Array()
	var result := PackedFloat64Array()
	for key: String in CONTINUOUS_KEYS:
		result.append(float(state[key]))
	return result


## Applies a stage vector without wrapping phase or clamping event-side fuel.
static func with_continuous_state(state: Dictionary, values: PackedFloat64Array) -> Dictionary:
	if not _valid_state(state) or values.size() != CONTINUOUS_KEYS.size():
		return {}
	var result: Dictionary = state.duplicate(true)
	for index: int in range(CONTINUOUS_KEYS.size()):
		if not is_finite(values[index]):
			return {}
		result[CONTINUOUS_KEYS[index]] = values[index]
	return result


## Creates an accepted state. Initial air is at idle admission; a running state is
## primed at the profile's reference density so its first step has no artificial lag.
static func create(
		profile: Dictionary,
		settings: Dictionary,
		fuel_kg: float,
		temperature_k: float,
		rpm: float,
		running: bool,
		unusable_fuel_kg: float = 0.0
) -> Dictionary:
	var configuration_error: String = _configuration_error(profile, settings)
	if not configuration_error.is_empty():
		return _fail(configuration_error)
	var model: Dictionary = _model(profile)
	var operation: Dictionary = model.operation
	if not is_finite(fuel_kg) or fuel_kg < 0.0 or not _finite_number(unusable_fuel_kg) or unusable_fuel_kg < 0.0 \
			or not is_finite(temperature_k) or temperature_k <= 0.0:
		return _fail("Initial fuel and temperature must be finite and physically bounded")
	if not is_finite(rpm) or rpm < 0.0 or rpm > float(operation.max_rpm):
		return _fail("Initial RPM is outside the profile envelope")
	var family: String = str(model.family)
	var cycle_revolutions: float = 1.0 if family == "glow_2t" else 2.0
	var active: bool = running and fuel_kg > unusable_fuel_kg
	var admission: float = float(settings.idle_admission)
	var initial_flow: float = 0.0
	if active:
		var reference_density: float = float(operation.reference_dry_density_kg_m3)
		var initial_source: Dictionary = Source.evaluate(
			model, rpm, admission, float(operation.nominal_mixture), reference_density, true, 1.0
		)
		if not initial_source.get("ok", false):
			return _fail("Initial fuel transport failed: " + str(initial_source.get("message", "unknown source error")))
		initial_flow = float(initial_source.delivered_fuel_kg_s)
	var state: Dictionary = {
		"family": family,
		"cycle_revolutions": int(cycle_revolutions),
		"fuel_kg": fuel_kg,
		"temperature_k": temperature_k,
		"servo_fraction": 0.0,
		"air_fraction": admission,
		"fuel_transport_kg_s": initial_flow,
		"phase_revolutions": 0.0,
		"running": active,
		"stop_reason": "" if active else ("fuel_exhausted" if fuel_kg <= unusable_fuel_kg else "not_started"),
		"opportunity_count": 0,
		"fire_count": 0,
		"firing_accumulator": 0.0,
	}
	return {"ok": true, "message": "", "state": state}


## Evaluates one RK stage. `mixture` is the requested equivalence ratio phi;
## fuel transport creates the actual equivalence ratio from
## delivered premix mass flow divided by the admitted-air flow. NITRO-05:
## `feed_factor` scales the needled flow by the stage's feed pressure
## (physics/glow/fuel_feed.gd); 1 is the needled condition and the default.
static func evaluate(
		profile: Dictionary,
		settings: Dictionary,
		state: Dictionary,
		rpm: float,
		throttle: float,
		mixture: float,
		dry_density_kg_m3: float,
		ambient_k: float,
		cooling_airspeed_mps: float,
		feed_factor: float = 1.0,
		unusable_fuel_kg: float = 0.0
) -> Dictionary:
	var configuration_error: String = _configuration_error(profile, settings)
	if not configuration_error.is_empty():
		return _fail(configuration_error)
	var state_error: String = _state_error(state, true)
	if not state_error.is_empty():
		return _fail(state_error)
	var model: Dictionary = _model(profile)
	return _evaluate_validated(model, settings, state, rpm, throttle, mixture,
		dry_density_kg_m3, ambient_k, cooling_airspeed_mps, null, feed_factor, unusable_fuel_kg)


## Performs one-time validation and detaches immutable profile/settings data for a
## simulation owner. Runtime state is intentionally not captured in this object.
static func prepare_evaluator(profile: Dictionary, settings: Dictionary) -> Dictionary:
	var configuration_error: String = _configuration_error(profile, settings)
	if not configuration_error.is_empty():
		return _fail(configuration_error)
	var model: Dictionary = _model(profile)
	var source_result: Dictionary = Source.prepare_evaluator(model)
	if not source_result.get("ok", false):
		return _fail("Glow source preparation failed: " + str(source_result.get("message", "unknown profile error")))
	var evaluator := PreparedEvaluator.new(model, settings, source_result.evaluator)
	return {ok = true, message = "", evaluator = evaluator}


## RK-stage API over a prepared, typed installation evaluator. State and all
## dynamic queries are validated at each call just like the public Dictionary API.
static func evaluate_prepared(
		evaluator: PreparedEvaluator,
		state: Dictionary,
		rpm: float,
		throttle: float,
		mixture: float,
		dry_density_kg_m3: float,
		ambient_k: float,
		cooling_airspeed_mps: float,
		feed_factor: float = 1.0,
		unusable_fuel_kg: float = 0.0
) -> Dictionary:
	if not evaluator is PreparedEvaluator:
		return _fail("A prepared lifecycle evaluator is required")
	var state_error: String = _state_error(state, true)
	if not state_error.is_empty():
		return _fail(state_error)
	return _evaluate_validated(evaluator._model, evaluator._settings, state, rpm,
		throttle, mixture, dry_density_kg_m3, ambient_k, cooling_airspeed_mps,
		evaluator._source, feed_factor, unusable_fuel_kg)


static func _evaluate_validated(
		model: Dictionary,
		settings: Dictionary,
		state: Dictionary,
		rpm: float,
		throttle: float,
		mixture: float,
		dry_density_kg_m3: float,
		ambient_k: float,
		cooling_airspeed_mps: float,
		prepared_source: Variant = null,
		feed_factor: float = 1.0,
		unusable_fuel_kg: float = 0.0
) -> Dictionary:
	if str(state.family) != str(model.family):
		return _fail("Profile family does not match lifecycle state")
	var operation: Dictionary = model.operation
	if not _finite_number(rpm) or rpm < 0.0 or rpm > float(operation.max_rpm):
		return _fail("RPM is outside the profile envelope")
	if not _finite_number(throttle) or throttle < 0.0 or throttle > 1.0:
		return _fail("Throttle must be finite and in [0, 1]")
	if not _finite_number(mixture) or mixture < 0.0:
		return _fail("Mixture command must be finite and nonnegative")
	if not _finite_number(dry_density_kg_m3) or dry_density_kg_m3 <= 0.0:
		return _fail("Dry-air density must be finite and positive")
	if not _finite_number(ambient_k) or ambient_k <= 0.0:
		return _fail("Ambient temperature must be finite and positive")
	if not _finite_number(cooling_airspeed_mps) or cooling_airspeed_mps < 0.0:
		return _fail("Cooling airspeed must be finite and nonnegative")
	if not _finite_number(feed_factor) or feed_factor < 0.0:
		return _fail("Fuel feed factor must be finite and nonnegative")
	if not _finite_number(unusable_fuel_kg) or unusable_fuel_kg < 0.0:
		return _fail("Unusable fuel mass must be finite and nonnegative")

	var raw_servo: float = float(state.servo_fraction)
	var raw_air: float = float(state.air_fraction)
	var servo: float = clampf(raw_servo, 0.0, 1.0)
	var admission: float = clampf(raw_air, 0.0, 1.0)
	var air_target: float = float(settings.idle_admission) + servo * (1.0 - float(settings.idle_admission))
	var servo_rate: float = (throttle - raw_servo) / float(settings.servo_time_constant_s)
	var air_rate: float = (air_target - raw_air) / float(settings.air_time_constant_s)

	var active: bool = bool(state.running) and float(state.fuel_kg) > unusable_fuel_kg
	var target_fuel_flow: float = 0.0
	var actual_mixture: float = mixture
	var current_transport: float = maxf(0.0, float(state.fuel_transport_kg_s))
	if active and admission > 0.0:
		var baseline_mixture: float = mixture if mixture > 0.0 else float(operation.nominal_mixture)
		var unit_flow: float
		if prepared_source is Source.PreparedEvaluator:
			var flow_result: Dictionary = Source.unit_fuel_flow_prepared(
				prepared_source, rpm, admission, baseline_mixture, dry_density_kg_m3
			)
			if not flow_result.get("ok", false):
				return _fail("Fuel-flow target failed: " + str(flow_result.get("message", "unknown source error")))
			unit_flow = float(flow_result.unit_fuel_flow_kg_s_per_mixture)
		else:
			var baseline: Dictionary = Source.evaluate(
				model, rpm, admission, baseline_mixture, dry_density_kg_m3, true, 1.0
			)
			if not baseline.get("ok", false):
				return _fail("Fuel-flow target failed: " + str(baseline.get("message", "unknown source error")))
			unit_flow = float(baseline.delivered_fuel_kg_s) / baseline_mixture
		target_fuel_flow = unit_flow * mixture * feed_factor
		if unit_flow > LOW_FLOW:
			actual_mixture = current_transport / unit_flow
		else:
			actual_mixture = mixture

	var firing_fraction: float = 0.0
	if active:
		firing_fraction = _firing_fraction(
			settings, float(operation.nominal_mixture), actual_mixture, float(state.temperature_k)
		)
	var source: Dictionary
	if prepared_source is Source.PreparedEvaluator:
		source = Source.evaluate_prepared(
			prepared_source, rpm, admission, actual_mixture, dry_density_kg_m3, active, firing_fraction
		)
	else:
		source = Source.evaluate(
			model, rpm, admission, actual_mixture, dry_density_kg_m3, active, firing_fraction
		)
	if not source.get("ok", false):
		return _fail("Glow source failed: " + str(source.get("message", "unknown source error")))
	var thermal: Dictionary
	if prepared_source is Source.PreparedEvaluator:
		thermal = Thermal._evaluate_prepared(
			source, float(state.temperature_k), ambient_k, cooling_airspeed_mps, settings.thermal
		)
	else:
		thermal = Thermal.evaluate(
			source, float(state.temperature_k), ambient_k, cooling_airspeed_mps, settings.thermal
		)
	if not thermal.get("ok", false):
		return _fail("Glow thermal balance failed: " + str(thermal.get("message", "unknown thermal error")))
	var fuel_transport_rate: float = 0.0
	if active:
		fuel_transport_rate = (target_fuel_flow - current_transport) / float(settings.fuel_transport_time_constant_s)
	else:
		fuel_transport_rate = -current_transport / float(settings.fuel_transport_time_constant_s)
	var fuel_rate: float = -float(source.delivered_fuel_kg_s)
	var temperature_rate: float = float(thermal.temperature_rate_k_s)
	var phase_rate: float = rpm / 60.0
	# Same CONTINUOUS_KEYS order and messages as the former per-key loop.
	if not is_finite(fuel_rate):
		return _fail("Lifecycle rate is nonfinite: fuel_kg")
	if not is_finite(temperature_rate):
		return _fail("Lifecycle rate is nonfinite: temperature_k")
	if not is_finite(servo_rate):
		return _fail("Lifecycle rate is nonfinite: servo_fraction")
	if not is_finite(air_rate):
		return _fail("Lifecycle rate is nonfinite: air_fraction")
	if not is_finite(fuel_transport_rate):
		return _fail("Lifecycle rate is nonfinite: fuel_transport_kg_s")
	if not is_finite(phase_rate):
		return _fail("Lifecycle rate is nonfinite: phase_revolutions")
	var rates := {
		"fuel_kg": fuel_rate,
		"temperature_k": temperature_rate,
		"servo_fraction": servo_rate,
		"air_fraction": air_rate,
		"fuel_transport_kg_s": fuel_transport_rate,
		"phase_revolutions": phase_rate,
	}
	return {
		"ok": true,
		"message": "",
		"rates": rates,
		"source": source,
		"thermal": thermal,
		"firing_fraction": firing_fraction,
		"telemetry": {
			"family": model.family,
			"cycle_revolutions": int(state.cycle_revolutions),
			"admission": admission,
			"air_target": air_target,
			"commanded_throttle": throttle,
			"servo_fraction": servo,
			"mixture_command": mixture,
			"actual_mixture": actual_mixture,
			"fuel_target_kg_s": target_fuel_flow,
			"fuel_feed_factor": feed_factor,
			"fuel_transport_kg_s": float(source.delivered_fuel_kg_s),
			"firing_fraction": firing_fraction,
			"phase_revolutions": float(state.phase_revolutions),
		},
	}


## Commits an already integrated candidate. It never integrates continuous rates;
## fuel below zero is rejected so the caller can split at exact tank exhaustion.
static func accepted(
		profile: Dictionary,
		settings: Dictionary,
		before: Dictionary,
		candidate: Dictionary,
		dt: float,
		rpm_before: float,
		rpm_after: float,
		firing_fraction: float,
		unusable_fuel_kg: float = 0.0
) -> Dictionary:
	var configuration_error: String = _configuration_error(profile, settings)
	if not configuration_error.is_empty():
		return _fail(configuration_error)
	return _accepted_validated(_model(profile), settings, before, candidate, dt,
		rpm_before, rpm_after, firing_fraction, unusable_fuel_kg)


## Accepted-step API over a prepared evaluator. Its installation snapshot was
## validated once by prepare_evaluator() and is read-only; states and dynamic
## arguments are still checked exactly as in accepted().
static func accepted_prepared(
		evaluator: PreparedEvaluator,
		before: Dictionary,
		candidate: Dictionary,
		dt: float,
		rpm_before: float,
		rpm_after: float,
		firing_fraction: float,
		unusable_fuel_kg: float = 0.0
) -> Dictionary:
	if not evaluator is PreparedEvaluator:
		return _fail("A prepared lifecycle evaluator is required")
	return _accepted_validated(evaluator._model, evaluator._settings, before, candidate, dt,
		rpm_before, rpm_after, firing_fraction, unusable_fuel_kg)


static func _accepted_validated(
		model: Dictionary,
		settings: Dictionary,
		before: Dictionary,
		candidate: Dictionary,
		dt: float,
		rpm_before: float,
		rpm_after: float,
		firing_fraction: float,
		unusable_fuel_kg: float = 0.0
) -> Dictionary:
	var before_error: String = _state_error(before, false)
	var candidate_error: String = _state_error(candidate, true)
	if not before_error.is_empty() or not candidate_error.is_empty():
		return _fail(before_error if not before_error.is_empty() else candidate_error)
	if str(before.family) != str(model.family) or str(candidate.family) != str(model.family):
		return _fail("Profile family does not match accepted lifecycle state")
	if not _finite_number(dt) or dt < 0.0:
		return _fail("Accepted duration must be finite and nonnegative")
	var maximum_rpm: float = float(model.operation.max_rpm)
	if not _finite_number(rpm_before) or not _finite_number(rpm_after) or rpm_before < 0.0 or rpm_after < 0.0 or rpm_before > maximum_rpm or rpm_after > maximum_rpm:
		return _fail("Accepted RPM values must be finite and inside the profile envelope")
	if not _finite_number(firing_fraction) or firing_fraction < 0.0 or firing_fraction > 1.0:
		return _fail("Firing fraction must be finite and in [0, 1]")
	if not _finite_number(unusable_fuel_kg) or unusable_fuel_kg < 0.0:
		return _fail("Unusable fuel mass must be finite and nonnegative")
	var effective_floor: float=minf(unusable_fuel_kg,float(before.fuel_kg))
	if float(candidate.fuel_kg) < effective_floor:
		return _fail("Fuel crossed unusable mass; split the step at exact tank exhaustion instead of clamping mass")
	if float(candidate.fuel_kg) > float(before.fuel_kg) + 1.0e-14:
		return _fail("Fuel mass cannot increase during an accepted lifecycle step")
	if float(candidate.temperature_k) <= 0.0:
		return _fail("Accepted temperature must remain positive")
	if float(candidate.fuel_transport_kg_s) < 0.0:
		return _fail("Fuel transport crossed zero; reduce or split the accepted step")
	for key: String in ["servo_fraction", "air_fraction"]:
		var value: float = float(candidate[key])
		if value < -1.0e-12 or value > 1.0 + 1.0e-12:
			return _fail("Accepted %s left [0, 1]; reduce or split the step" % key)
	if float(candidate.phase_revolutions) < float(before.phase_revolutions) - PHASE_TOLERANCE:
		return _fail("Mechanical phase moved backward")

	var cycle_revolutions: float = 1.0 if model.family == "glow_2t" else 2.0
	var phase_start: float = float(before.phase_revolutions)
	var phase_end: float = float(candidate.phase_revolutions)
	var start_turn: int = int(floor((phase_start + PHASE_TOLERANCE) / cycle_revolutions))
	var end_turn: int = int(floor((phase_end + PHASE_TOLERANCE) / cycle_revolutions))
	var opportunity_delta: int = end_turn - start_turn
	if opportunity_delta < 0 or opportunity_delta > MAX_OPPORTUNITIES_PER_ACCEPT:
		return _fail("Accepted phase crosses an unsupported number of opportunities; reduce the step")
	var next: Dictionary = candidate.duplicate(true)
	for key: String in ["running", "stop_reason", "opportunity_count", "fire_count", "firing_accumulator"]:
		next[key] = before[key]
	next["servo_fraction"] = clampf(float(next.servo_fraction), 0.0, 1.0)
	next["air_fraction"] = clampf(float(next.air_fraction), 0.0, 1.0)
	next["phase_revolutions"] = fposmod(phase_end, cycle_revolutions)
	var acc: float = float(before.firing_accumulator)
	var opportunities: Array[Dictionary] = []
	var event_list: Array[Dictionary] = []
	var phase_delta: float = phase_end - phase_start
	for offset: int in range(opportunity_delta):
		var boundary: float = float(start_turn + offset + 1) * cycle_revolutions
		var fraction_of_step: float = 1.0
		if phase_delta > 0.0:
			fraction_of_step = clampf((boundary - phase_start) / phase_delta, 0.0, 1.0)
		var active_probability: float = firing_fraction if bool(before.running) and float(before.fuel_kg) > unusable_fuel_kg else 0.0
		acc += active_probability
		var fired: bool = acc >= 1.0 - FIRE_TOLERANCE
		if fired:
			acc = maxf(0.0, acc - 1.0)
			next["fire_count"] = int(next.fire_count) + 1
		var opportunity: Dictionary = {
			"kind": "combustion_opportunity",
			"family": model.family,
			"cycle_revolutions": int(cycle_revolutions),
			"time_s": dt * fraction_of_step,
			"fraction_of_step": fraction_of_step,
			"fired": fired,
			"firing_fraction": active_probability,
		}
		opportunities.append(opportunity)
		event_list.append(opportunity.duplicate(true))
	next["firing_accumulator"] = acc
	next["opportunity_count"] = int(before.opportunity_count) + opportunity_delta

	if bool(before.running) and float(before.fuel_kg) <= unusable_fuel_kg:
		next["running"] = false
		next["stop_reason"] = "fuel_exhausted"
		next["fuel_transport_kg_s"] = 0.0
		event_list.append({"kind": "fuel_exhausted", "time_s": 0.0})
	elif bool(before.running) and float(before.fuel_kg) > unusable_fuel_kg \
			and float(candidate.fuel_kg) == unusable_fuel_kg:
		next["running"] = false
		next["stop_reason"] = "fuel_exhausted"
		next["fuel_transport_kg_s"] = 0.0
		event_list.append({"kind": "fuel_exhausted", "time_s": dt})
	elif bool(before.running) and float(candidate.temperature_k) >= float(settings.temperature_firing_hot_zero_k):
		next["running"] = false
		next["stop_reason"] = "overheat"
		next["fuel_transport_kg_s"] = 0.0
		event_list.append({
			"kind": "overheat",
			"time_s": dt,
			"temperature_k": float(candidate.temperature_k),
		})
	elif bool(before.running) and rpm_after <= float(settings.stall_rpm):
		next["running"] = false
		next["stop_reason"] = "stall"
		next["fuel_transport_kg_s"] = 0.0
		event_list.append({"kind": "stall", "time_s": dt, "rpm": rpm_after})
	return {
		"ok": true,
		"message": "",
		"state": next,
		"events": event_list,
		"opportunities": opportunities,
	}


## Starter rotation is owned by the caller. This command only opens the lifecycle
## after the starter has reached the profile-specific minimum speed.
static func request_start(
		profile: Dictionary,
		settings: Dictionary,
		state: Dictionary,
		rpm: float,
		starter_available: bool = true,
		unusable_fuel_kg: float = 0.0
) -> Dictionary:
	var configuration_error: String = _configuration_error(profile, settings)
	if not configuration_error.is_empty():
		return _fail(configuration_error)
	var state_error: String = _state_error(state, false)
	if not state_error.is_empty():
		return _fail(state_error)
	if str(_model(profile).family) != str(state.family):
		return _fail("Profile family does not match lifecycle state")
	var next: Dictionary = state.duplicate(true)
	var reason: String = ""
	if bool(state.running):
		reason = "already_running"
	elif not starter_available:
		reason = "starter_unavailable"
	elif not _finite_number(rpm):
		reason = "starter_speed_invalid"
	elif rpm < float(settings.minimum_start_rpm):
		reason = "starter_speed_too_low"
	elif rpm > float(_model(profile).operation.max_rpm):
		reason = "starter_speed_outside_envelope"
	elif not _finite_number(unusable_fuel_kg) or unusable_fuel_kg < 0.0:
		reason = "fuel_reserve_invalid"
	elif float(state.fuel_kg) <= unusable_fuel_kg:
		reason = "fuel_exhausted"
	elif float(state.temperature_k) >= float(settings.temperature_firing_hot_zero_k):
		reason = "overheated"
	if not reason.is_empty():
		return {"ok": true, "started": false, "reason": reason, "state": next, "events": []}
	next["running"] = true
	next["stop_reason"] = ""
	# No tank flow is consumed while stopped. Fuel transport starts from zero.
	next["fuel_transport_kg_s"] = 0.0
	return {
		"ok": true,
		"started": true,
		"reason": "",
		"state": next,
		"events": [{"kind": "start", "rpm": rpm}],
	}


static func cut(state: Dictionary) -> Dictionary:
	var state_error: String = _state_error(state, false)
	if not state_error.is_empty():
		return _fail(state_error)
	var next: Dictionary = state.duplicate(true)
	var was_running: bool = bool(next.running)
	next["running"] = false
	next["stop_reason"] = "cut"
	next["fuel_transport_kg_s"] = 0.0
	var events: Array[Dictionary] = []
	if was_running:
		events.append({"kind": "cut"})
	return {"ok": true, "state": next, "events": events}


static func _firing_fraction(settings: Dictionary, nominal_mixture: float,
		actual_mixture: float, temperature_k: float) -> float:
	if actual_mixture <= 0.0:
		return 0.0
	var relative_mixture: float = actual_mixture / nominal_mixture
	var mixture_factor: float = 1.0
	if relative_mixture <= float(settings.lean_misfire_zero_ratio):
		mixture_factor = 0.0
	elif relative_mixture < float(settings.lean_misfire_start_ratio):
		var lean_x: float = (relative_mixture - float(settings.lean_misfire_zero_ratio)) / (float(settings.lean_misfire_start_ratio) - float(settings.lean_misfire_zero_ratio))
		mixture_factor = _smoothstep(lean_x)
	elif relative_mixture > float(settings.rich_misfire_start_ratio):
		var rich_x: float = (float(settings.rich_misfire_zero_ratio) - relative_mixture) / (float(settings.rich_misfire_zero_ratio) - float(settings.rich_misfire_start_ratio))
		mixture_factor = _smoothstep(rich_x)
	var cold_x: float = (temperature_k - float(settings.temperature_firing_min_k)) / (float(settings.temperature_firing_full_k) - float(settings.temperature_firing_min_k))
	var hot_x: float = (float(settings.temperature_firing_hot_zero_k) - temperature_k) / (float(settings.temperature_firing_hot_zero_k) - float(settings.temperature_firing_hot_full_k))
	return clampf(mixture_factor * _smoothstep(cold_x) * _smoothstep(hot_x), 0.0, 1.0)


static func _smoothstep(value: float) -> float:
	var x: float = clampf(value, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _configuration_error(profile: Dictionary, settings: Dictionary) -> String:
	if not profile is Dictionary or not settings is Dictionary:
		return "Profile and lifecycle settings must be Dictionaries"
	var model: Dictionary = _model(profile)
	if model.is_empty() or model.get("family") not in FAMILIES:
		return "Lifecycle requires an explicit glow_2t or glow_4t profile model"
	var operation: Variant = model.get("operation")
	var parameters: Variant = model.get("parameters")
	var identity: Variant = model.get("identity")
	if not operation is Dictionary or not parameters is Dictionary or not identity is Dictionary:
		return "Glow profile is missing operation, parameters or identity"
	var cycle_revolutions: int = 1 if model.family == "glow_2t" else 2
	if identity.get("status") != "candidate" or identity.get("cycle_revolutions") != cycle_revolutions:
		return "Glow profile family and mechanical cycle identity disagree"
	for name: String in ["max_rpm", "reference_dry_density_kg_m3", "nominal_mixture"]:
		if not _finite_number(operation.get(name)) or float(operation[name]) <= 0.0:
			return "Glow profile operation has an invalid " + name
	var required: Array[String] = [
		"idle_admission", "servo_time_constant_s", "air_time_constant_s",
		"fuel_transport_time_constant_s", "stall_rpm", "minimum_start_rpm",
		"temperature_firing_min_k", "temperature_firing_full_k",
		"temperature_firing_hot_full_k", "temperature_firing_hot_zero_k",
		"lean_misfire_zero_ratio", "lean_misfire_start_ratio",
		"rich_misfire_start_ratio", "rich_misfire_zero_ratio",
	]
	for name: String in required:
		if not _finite_number(settings.get(name)):
			return "Missing or nonfinite lifecycle setting: " + name
	for name: String in ["servo_time_constant_s", "air_time_constant_s", "fuel_transport_time_constant_s", "stall_rpm", "minimum_start_rpm", "temperature_firing_min_k"]:
		if float(settings[name]) <= 0.0:
			return "Lifecycle setting must be positive: " + name
	if float(settings.idle_admission) < 0.0 or float(settings.idle_admission) > 1.0:
		return "idle_admission must be in [0, 1]"
	if float(settings.minimum_start_rpm) <= float(settings.stall_rpm) or float(settings.minimum_start_rpm) >= float(operation.max_rpm):
		return "minimum_start_rpm must exceed stall_rpm and remain below max_rpm"
	if not (float(settings.temperature_firing_min_k) < float(settings.temperature_firing_full_k)
		and float(settings.temperature_firing_full_k) < float(settings.temperature_firing_hot_full_k)
		and float(settings.temperature_firing_hot_full_k) < float(settings.temperature_firing_hot_zero_k)):
		return "Firing temperature thresholds must satisfy cold minimum < cold full < hot full < hot zero"
	if float(settings.lean_misfire_zero_ratio) < 0.0 or float(settings.lean_misfire_zero_ratio) >= float(settings.lean_misfire_start_ratio) or float(settings.lean_misfire_start_ratio) >= 1.0:
		return "Lean misfire ratios must satisfy zero < start < nominal"
	if float(settings.rich_misfire_start_ratio) <= 1.0 or float(settings.rich_misfire_zero_ratio) <= float(settings.rich_misfire_start_ratio):
		return "Rich misfire ratios must satisfy nominal < start < zero"
	var thermal: Variant = settings.get("thermal")
	if not thermal is Dictionary:
		return "Lifecycle settings require the nested thermal parameter group"
	for name: String in ["heat_capacity_j_k", "head_heat_fraction", "cooling_base_w_k", "cooling_airflow_w_s_m_k", "premix_evaporation_j_kg", "evaporation_head_fraction"]:
		if not _finite_number(thermal.get(name)) or float(thermal[name]) < 0.0:
			return "Missing, nonfinite or negative thermal setting: " + name
	if float(thermal.heat_capacity_j_k) <= 0.0 or float(thermal.head_heat_fraction) > 1.0 or float(thermal.evaporation_head_fraction) > 1.0:
		return "Thermal capacity or heat fraction is outside its allowed range"
	return ""


static func _model(profile: Dictionary) -> Dictionary:
	var nested: Variant = profile.get("model")
	if nested is Dictionary:
		return nested
	return profile


static func _valid_state(state: Dictionary) -> bool:
	return _state_error(state, true).is_empty()


static func _state_error(state: Dictionary, allow_stage_phase: bool) -> String:
	if not state is Dictionary:
		return "Lifecycle state must be a Dictionary"
	for name: String in CONTINUOUS_KEYS:
		if not state.has(name) or not _finite_number(state[name]):
			return "Lifecycle state is missing a finite float64 field: " + name
	if state.get("family") not in FAMILIES:
		return "Lifecycle state has no supported family"
	var expected_cycle: int = 1 if state.family == "glow_2t" else 2
	if state.get("cycle_revolutions") != expected_cycle:
		return "Lifecycle state family and cycle length disagree"
	if typeof(state.get("running")) != TYPE_BOOL or typeof(state.get("stop_reason")) != TYPE_STRING:
		return "Lifecycle state discrete mode is malformed"
	for name: String in ["opportunity_count", "fire_count"]:
		if typeof(state.get(name)) != TYPE_INT or int(state[name]) < 0:
			return "Lifecycle event counter is malformed: " + name
	if int(state.fire_count) > int(state.opportunity_count):
		return "Lifecycle fire count exceeds mechanical opportunities"
	if not _finite_number(state.get("firing_accumulator")) or float(state.firing_accumulator) < 0.0 or float(state.firing_accumulator) >= 1.0:
		return "Lifecycle firing accumulator must be finite and in [0, 1)"
	if float(state.fuel_kg) < 0.0 and not allow_stage_phase:
		return "Accepted lifecycle state has negative fuel"
	if float(state.temperature_k) <= 0.0 or float(state.phase_revolutions) < 0.0:
		return "Lifecycle temperature and phase must be positive/nonnegative"
	if float(state.fuel_transport_kg_s) < 0.0 and not allow_stage_phase:
		return "Accepted lifecycle state has negative fuel transport"
	return ""


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}
