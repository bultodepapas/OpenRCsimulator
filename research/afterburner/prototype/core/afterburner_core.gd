# SPDX-License-Identifier: MIT
# Original integration starter, 2026-11-14. NOT an OpenRC production adapter.
# All tuning below is invented. No P100-RX afterburner data is asserted.
# Pure scalar/float64-array operations only: no tick owner, inventory writer,
# rendering API, RNG, audio event emission, or Godot rigid-body force application.
extends RefCounted

enum EffectMode { DISABLED, COSMETIC, AUGMENTED }
enum Phase { DISABLED, READY, IGNITING, LIT, EXTINGUISHING, INHIBITED }

const LAW_ID := "experimental-afterburner-scalar-starter-v1"
const MAX_STEP_OVER_TAU := 0.25
const CONFIG_SCALARS := [
	"rise_tau_s", "fall_tau_s", "ignition_delay_s", "throttle_on", "throttle_off",
	"rpm_on", "rpm_off", "additional_gross_thrust_n", "additional_fuel_kg_s", "tail_epsilon"
]


## One-condition, invented tuning. Replace through a versioned, validated data
## pipeline before production. axis/arm already use body FRD and ONE common datum.
static func example_config(effect_mode: int = EffectMode.AUGMENTED) -> Dictionary:
	return {
		"effect_mode": effect_mode,
		"rise_tau_s": 0.25,
		"fall_tau_s": 0.12,
		"ignition_delay_s": 0.20,
		"throttle_on": 0.92,
		"throttle_off": 0.88,
		"rpm_on": 0.80,
		"rpm_off": 0.75,
		"additional_gross_thrust_n": 30.0,
		"additional_fuel_kg_s": 0.005,
		"tail_epsilon": 1.0e-8,
		"axis_frd": PackedFloat64Array([1.0, 0.0, 0.0]),
		"nozzle_arm_frd_m": PackedFloat64Array([0.0, 0.0, 0.0]),
	}


static func validate_config(config: Dictionary) -> Dictionary:
	if not _enum_valid(config.get("effect_mode"), EffectMode.DISABLED, EffectMode.AUGMENTED):
		return _failure("invalid effect_mode")
	for field: String in CONFIG_SCALARS:
		if not _finite_number(config.get(field)):
			return _failure("missing or nonfinite config scalar: " + field)
	if config.rise_tau_s <= 0.0 or config.fall_tau_s <= 0.0 or config.ignition_delay_s < 0.0:
		return _failure("response times must be positive; ignition delay may be zero")
	if not _ordered_thresholds(float(config.throttle_off), float(config.throttle_on)) \
			or not _ordered_thresholds(float(config.rpm_off), float(config.rpm_on)):
		return _failure("hysteresis requires 0 <= off < on <= 1")
	if config.additional_gross_thrust_n < 0.0 or config.additional_fuel_kg_s < 0.0:
		return _failure("added gross thrust and fuel demand must be nonnegative")
	if config.effect_mode == EffectMode.AUGMENTED and config.additional_gross_thrust_n > 0.0 \
			and config.additional_fuel_kg_s <= 0.0:
		return _failure("augmented thrust requires positive additional fuel demand")
	if config.tail_epsilon <= 0.0 or config.tail_epsilon > 1.0e-3:
		return _failure("tail_epsilon must be in (0, 0.001]")
	if not _finite_vector(config.get("axis_frd")) or not _finite_vector(config.get("nozzle_arm_frd_m")):
		return _failure("axis and nozzle arm must be finite float64 triples")
	var axis: PackedFloat64Array = config.axis_frd
	var norm_squared: float = axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]
	if absf(norm_squared - 1.0) > 1.0e-12:
		return _failure("axis_frd must be a unit vector; do not silently normalize geometry")
	return {"ok": true}


static func step_supported(config: Dictionary, dt: float) -> bool:
	return validate_config(config).ok and is_finite(dt) and dt > 0.0 \
		and dt / minf(float(config.rise_tau_s), float(config.fall_tau_s)) <= MAX_STEP_OVER_TAU


## The adapter must map intensity into its continuous block and the remaining
## values into explicit sampled/discrete/checkpoint fields. This dictionary is
## a detached convenience envelope, not a proposed replacement for VehicleModel.
static func initial_state(config: Dictionary) -> Dictionary:
	if not validate_config(config).ok:
		return {}
	return {
		"intensity": 0.0,
		"phase": Phase.DISABLED if config.effect_mode == EffectMode.DISABLED else Phase.READY,
		"ignition_elapsed_s": 0.0,
		"latched": false,
		"rearm_required": false,
		"transition_sequence": 0,
	}


static func valid_state(state: Dictionary, config: Dictionary) -> bool:
	if not validate_config(config).ok or not _unit_number(state.get("intensity")) \
			or not _enum_valid(state.get("phase"), Phase.DISABLED, Phase.INHIBITED) \
			or not _finite_number(state.get("ignition_elapsed_s")) \
			or typeof(state.get("latched")) != TYPE_BOOL \
			or typeof(state.get("rearm_required")) != TYPE_BOOL \
			or typeof(state.get("transition_sequence")) != TYPE_INT \
			or int(state.transition_sequence) < 0:
		return false
	if state.ignition_elapsed_s < 0.0 or state.ignition_elapsed_s > config.ignition_delay_s:
		return false
	if state.phase != Phase.IGNITING and state.ignition_elapsed_s != 0.0:
		return false
	if bool(state.latched) != (state.phase in [Phase.IGNITING, Phase.LIT]):
		return false
	if bool(state.rearm_required) and state.phase != Phase.INHIBITED:
		return false
	if state.phase in [Phase.DISABLED, Phase.READY, Phase.INHIBITED] and state.intensity != 0.0:
		return false
	if (config.effect_mode == EffectMode.DISABLED) != (state.phase == Phase.DISABLED):
		return false
	return true


## Pure once-per-interval sampling. Neither state nor input dictionaries change.
## command: request [0,1], throttle [0,1]. permits: armed/input_valid/engine_running/
## source_available bools, rpm_ratio >= 0. request is independent of dry throttle.
## The returned dictionary contains only scalars and is read-only. Keep exactly
## this sample for all RK stages, retries and subdivisions of this interval.
static func freeze_sample(state: Dictionary, command: Dictionary, permits: Dictionary,
		config: Dictionary) -> Dictionary:
	if not valid_state(state, config):
		return _failure("invalid configuration or accepted state")
	if not _unit_number(command.get("request")) or not _unit_number(command.get("throttle")):
		return _failure("request and throttle must be finite in [0,1]")
	for field: String in ["armed", "input_valid", "engine_running", "source_available"]:
		if typeof(permits.get(field)) != TYPE_BOOL:
			return _failure("missing boolean permit: " + field)
	if not _finite_number(permits.get("rpm_ratio")) or permits.rpm_ratio < 0.0:
		return _failure("rpm_ratio must be finite and nonnegative")
	var phase: int = int(state.phase)
	var latched: bool = bool(state.latched)
	var rearm: bool = bool(state.rearm_required)
	var elapsed: float = float(state.ignition_elapsed_s)
	var reason: String = ""
	var permitted: bool = false
	var target: float = 0.0
	if config.effect_mode == EffectMode.DISABLED:
		phase = Phase.DISABLED
		latched = false
		rearm = false
		elapsed = 0.0
		reason = "disabled"
	else:
		if command.request == 0.0:
			rearm = false
		if not permits.input_valid:
			reason = "input_unavailable"
		elif not permits.armed:
			reason = "disarmed"
		elif not permits.engine_running:
			reason = "engine_off"
		elif not permits.source_available:
			reason = "fuel_unavailable"
		if not reason.is_empty():
			rearm = true
		elif rearm:
			reason = "release_required"
		if not reason.is_empty():
			phase = Phase.INHIBITED
			latched = false
			elapsed = 0.0
		else:
			permitted = true
			if command.request <= 0.0:
				latched = false
			elif latched:
				latched = command.throttle > config.throttle_off and permits.rpm_ratio > config.rpm_off
			else:
				latched = command.throttle >= config.throttle_on and permits.rpm_ratio >= config.rpm_on
			if latched:
				# The soft tail still consumes fuel and produces thrust: it is an
				# existing burn. Resume continuously, without muting/reigniting it.
				if phase == Phase.EXTINGUISHING and state.intensity > config.tail_epsilon:
					phase = Phase.LIT
					elapsed = 0.0
					reason = "resume_existing_burn"
				elif phase not in [Phase.IGNITING, Phase.LIT]:
					phase = Phase.IGNITING
					elapsed = 0.0
				if phase == Phase.LIT:
					target = float(command.request)
			else:
				phase = Phase.EXTINGUISHING if state.intensity > config.tail_epsilon \
					and state.phase in [Phase.LIT, Phase.EXTINGUISHING] else Phase.READY
				elapsed = 0.0
				if command.request > 0.0:
					reason = "throttle_below_gate" if command.throttle < config.throttle_on else "rpm_below_gate"
	var sample: Dictionary = {
		"ok": true, "effect_mode": int(config.effect_mode), "phase": phase,
		"latched": latched, "rearm_required": rearm, "ignition_elapsed_s": elapsed,
		"permitted": permitted, "target": target, "inhibit_reason": reason,
	}
	sample.make_read_only()
	return sample


## Pure RK-stage evaluation. stage_combustion_available MUST be read from the
## current stage's engine/source state, not cached at interval start: a located
## fuel cutoff overrides even a frozen sample that originally permitted burn.
## Output loads are ADDITIVE gross-nozzle loads. Existing inlet momentum and
## rotor momentum stay untouched. The caller owns the existing fuel derivative.
static func evaluate(intensity: float, sample: Dictionary, stage_combustion_available: bool,
		config: Dictionary) -> Dictionary:
	if not validate_config(config).ok or not _valid_sample(sample, config) or not _unit_number(intensity):
		return _failure("invalid stage intensity, sample or configuration")
	var allowed: bool = bool(sample.permitted) and stage_combustion_available
	var target: float = float(sample.target) if allowed else 0.0
	var tau: float = float(config.rise_tau_s) if target > intensity else float(config.fall_tau_s)
	var rate: float = (target - intensity) / tau
	if not is_finite(rate):
		return _failure("nonfinite intensity derivative")
	var visible: float = intensity if allowed and sample.phase in [Phase.LIT, Phase.EXTINGUISHING] else 0.0
	var result: Dictionary = {
		"ok": true, "intensity_derivative": rate, "flame_intensity": visible,
		"additional_gross_thrust_n": 0.0, "additional_fuel_flow_kg_s": 0.0,
		"additional_loads_frd": PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
	}
	# Canonical +0.0 outputs, including bytes, in disabled/cosmetic/inhibited states.
	if config.effect_mode != EffectMode.AUGMENTED or visible == 0.0:
		return result
	var gross: float = visible * float(config.additional_gross_thrust_n)
	var axis: PackedFloat64Array = config.axis_frd
	var arm: PackedFloat64Array = config.nozzle_arm_frd_m
	var fx: float = axis[0] * gross
	var fy: float = axis[1] * gross
	var fz: float = axis[2] * gross
	result.additional_gross_thrust_n = gross
	result.additional_fuel_flow_kg_s = visible * float(config.additional_fuel_kg_s)
	result.additional_loads_frd = PackedFloat64Array([
		fx, fy, fz,
		arm[1] * fz - arm[2] * fy,
		arm[2] * fx - arm[0] * fz,
		arm[0] * fy - arm[1] * fx,
	])
	for component: float in result.additional_loads_frd:
		if not is_finite(component):
			return _failure("nonfinite added load; installation/tuning outside numeric domain")
	if not is_finite(float(result.additional_fuel_flow_kg_s)):
		return _failure("nonfinite added fuel demand")
	return result


## Pure accepted-boundary proposal. The owner commits this returned state and
## events ONCE if the entire simulation transaction is accepted. Calling this
## twice only reproduces the same proposal: it never dispatches sound/signals.
## Ignition is boundary-quantized by at most one interval in this starter.
## Returned events are LOCAL PROPOSALS, not VehicleModel events: the adapter must
## assign a type/engine identity and convert time_offset_s to absolute time_s.
static func finish_interval(previous: Dictionary, sample: Dictionary, candidate_intensity: float,
		dt: float, endpoint_combustion_available: bool, config: Dictionary) -> Dictionary:
	if not valid_state(previous, config) or not _valid_sample(sample, config) \
			or not _unit_number(candidate_intensity) or not step_supported(config, dt):
		return _failure("invalid endpoint inputs or unsupported integration interval")
	var phase: int = int(sample.phase)
	var latched: bool = bool(sample.latched)
	var rearm: bool = bool(sample.rearm_required)
	var elapsed: float = 0.0
	var intensity: float = candidate_intensity
	var reason: String = str(sample.inhibit_reason)
	if phase == Phase.DISABLED:
		intensity = 0.0
	elif not endpoint_combustion_available:
		phase = Phase.INHIBITED
		intensity = 0.0
		latched = false
		rearm = true
		reason = "combustion_unavailable_at_endpoint"
	elif not sample.permitted:
		intensity = 0.0
	elif phase == Phase.IGNITING:
		elapsed = float(sample.ignition_elapsed_s) + dt
		if elapsed >= config.ignition_delay_s:
			phase = Phase.LIT
			elapsed = 0.0
	elif phase == Phase.EXTINGUISHING and intensity <= config.tail_epsilon:
		phase = Phase.READY
		intensity = 0.0
	elif phase == Phase.READY:
		intensity = 0.0
	var sequence: int = int(previous.transition_sequence)
	var events: Array[Dictionary] = []
	if phase != previous.phase:
		sequence += 1
		events.append({"sequence": sequence, "from": int(previous.phase), "to": phase,
			"time_offset_s": dt, "reason": reason})
	var state: Dictionary = {"intensity": intensity, "phase": phase,
		"ignition_elapsed_s": elapsed, "latched": latched, "rearm_required": rearm,
		"transition_sequence": sequence}
	if not valid_state(state, config):
		return _failure("endpoint proposal violates state invariants")
	return {"ok": true, "state": state, "events": events}


static func _valid_sample(sample: Dictionary, config: Dictionary) -> bool:
	if sample.get("ok", false) != true or sample.get("effect_mode", -1) != config.effect_mode \
			or not _enum_valid(sample.get("phase"), Phase.DISABLED, Phase.INHIBITED) \
			or not _unit_number(sample.get("target")) \
			or not _finite_number(sample.get("ignition_elapsed_s")) \
			or typeof(sample.get("inhibit_reason")) != TYPE_STRING:
		return false
	for field: String in ["latched", "rearm_required", "permitted"]:
		if typeof(sample.get(field)) != TYPE_BOOL:
			return false
	if sample.ignition_elapsed_s < 0.0 or sample.ignition_elapsed_s > config.ignition_delay_s:
		return false
	if sample.phase != Phase.IGNITING and sample.ignition_elapsed_s != 0.0:
		return false
	if bool(sample.latched) != (sample.phase in [Phase.IGNITING, Phase.LIT]):
		return false
	if bool(sample.rearm_required) and sample.phase != Phase.INHIBITED:
		return false
	if sample.phase != Phase.LIT and sample.target != 0.0:
		return false
	if sample.phase in [Phase.DISABLED, Phase.INHIBITED] and sample.permitted:
		return false
	return (config.effect_mode == EffectMode.DISABLED) == (sample.phase == Phase.DISABLED)


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))


static func _unit_number(value: Variant) -> bool:
	return _finite_number(value) and float(value) >= 0.0 and float(value) <= 1.0


static func _enum_valid(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum


static func _ordered_thresholds(off: float, on: float) -> bool:
	return off >= 0.0 and off < on and on <= 1.0


static func _finite_vector(value: Variant) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != 3:
		return false
	for component: float in value:
		if not is_finite(component):
			return false
	return true


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
