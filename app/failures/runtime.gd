extends RefCounted

const Config := preload("res://failures/config.gd")
const Catalog := preload("res://failures/catalog.gd")

const PLAN_FORMAT_V1 := "openrc-failure-plan v1"
const PLAN_FORMAT_V2 := "openrc-failure-plan v2"
const PLAN_FORMAT_V3 := "openrc-failure-plan v3"
const PLAN_FORMAT := PLAN_FORMAT_V1
const SNAPSHOT_FORMAT := "openrc-failure-snapshot v1"
const RNG_VERSION := 1
const RNG_NAME := "xorshift32-v1"
const UINT32_MAX := 4294967295
const UINT32_MASK := 0xffffffff
const RNG_DOMAIN_TAG := 0x9e3779b9
const RNG_ZERO_REPLACEMENT := 0x6d2b79f5
const MIN_DT := 0.000001
const MAX_DT := 1.0

const PLAN_KEYS_V1: Array[String] = [
	"format", "rng_version", "rng_name", "catalog_version", "seed", "dt",
	"config", "selected", "id", "onset_airborne_seconds", "onset_airborne_ticks",
	"parameters", "identity",
]
const PLAN_KEYS_V2: Array[String] = [
	"format", "rng_version", "rng_name", "catalog_version", "seed", "dt",
	"config", "eligibility_profile", "selected", "id", "onset_airborne_seconds",
	"onset_airborne_ticks", "parameters", "identity",
]
## v3 keeps the v2 keys; its config adds severity, onset window and excluded types (EM-29).
const PLAN_KEYS_V3: Array[String] = PLAN_KEYS_V2
const PLAN_KEYS: Array[String] = PLAN_KEYS_V1
const NO_ELIGIBLE_MESSAGE := "No enabled failure type is available for this aircraft. Enable one in Failures or set the probability to 0."
## Training-policy bands in hundredths, not measured RC failure magnitudes. Standard
## reproduces the v1/v2 ranges and draw counts exactly.
const SEVERITY_BANDS := {
	"bias": {"mild": [4, 8], "standard": [8, 18], "severe": [18, 30]},
	"rate_factor": {"mild": [50, 75], "standard": [25, 50], "severe": [10, 25]},
	"throttle_ceiling": {"mild": [70, 85], "standard": [45, 70], "severe": [25, 45]},
	"throttle_high": {"mild": [55, 70], "standard": [70, 90], "severe": [90, 100]},
	"throttle_low": {"mild": [20, 30], "standard": [8, 20], "severe": [0, 8]},
	"travel_limit": {"mild": [60, 75], "standard": [40, 60], "severe": [20, 40]},
}
const JAM_AXES := {"roll_jam": 0, "pitch_jam": 1, "yaw_jam": 2}
const BIAS_AXES := {"roll_bias": 0, "pitch_bias": 1, "yaw_bias": 2}
const SLOW_AXES := {"roll_slow": 0, "pitch_slow": 1, "yaw_slow": 2}
const TRAVEL_AXES := {"roll_travel_limit": 0, "pitch_travel_limit": 1, "yaw_travel_limit": 2}
const SNAPSHOT_KEYS: Array[String] = [
	"format", "plan", "plan_identity", "event_id", "tick", "airborne_ticks",
	"active", "activation_tick", "last_inputs", "jam_mask", "jam_positions", "held_inputs",
]

var _started := false
var _plan: Dictionary = {}
var _config: Dictionary = {}
var _seed := 0
var _dt := 0.0
var _active := false
var _airborne_ticks := 0
var _activation_tick := -1
var _last_commit_tick := 0
var _last_inputs := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _jam_mask := 0
var _jam_positions := PackedFloat64Array([0.0, 0.0, 0.0])
var _held_inputs := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _pending: Dictionary = {}
## Reason for the last refused begin(); empty after success.
var last_error := ""


## Resolve occurrence, event, parameters, and onset once. Invalid input leaves this runtime untouched.
## No profile keeps the historical v1 event set; a profile writes the current v3 plan. An explicit
## plan_format recreates a historical v2 plan for replaying existing records.
func begin(config: Dictionary, seed: int, dt: float, eligibility_profile: String = "",
		plan_format: String = "") -> bool:
	var resolved: Dictionary
	if eligibility_profile.is_empty():
		resolved = _build_plan_v1(config, seed, dt) if plan_format in ["", PLAN_FORMAT_V1] \
			else {"ok": false, "message": "a v2 or v3 failure plan needs an eligibility profile"}
	elif plan_format == PLAN_FORMAT_V2:
		resolved = _build_plan_v2(config, seed, dt, eligibility_profile)
	elif plan_format in ["", PLAN_FORMAT_V3]:
		resolved = _build_plan_v3(config, seed, dt, eligibility_profile)
	else:
		resolved = {"ok": false, "message": "unknown failure plan format"}
	if not bool(resolved.get("ok", false)):
		last_error = str(resolved.get("message", "failure plan is invalid"))
		return false
	last_error = ""
	_plan = resolved.plan.duplicate(true)
	_config = _plan.config.duplicate(true)
	_seed = int(_plan.seed)
	_dt = float(_plan.dt)
	_started = true
	restart()
	return true


## Stage effects for the next accepted tick. Activation and airborne time remain private until commit().
func prepare(inputs: PackedFloat64Array, servo: PackedFloat64Array, airborne: bool) -> Dictionary:
	if not _started:
		return {"ok": false, "message": "failure runtime has not begun"}
	if not _pending.is_empty():
		return {"ok": false, "message": "a failure candidate is already prepared"}
	if not bool(_plan.selected):
		return {"ok": true, "activation_due": false, "candidate_tick": _last_commit_tick + 1}
	if inputs.size() < 4 or servo.size() < 4:
		return {"ok": false, "message": "failure inputs or servo state are incomplete"}
	if not _inputs_are_valid(inputs) or not _servos_are_valid(servo):
		return {"ok": false, "message": "failure inputs or servo state are outside finite normalized bounds"}

	var next_airborne_ticks := _airborne_ticks + (1 if airborne else 0)
	var activation_due := bool(_plan.selected) and not _active and airborne \
		and next_airborne_ticks >= int(_plan.onset_airborne_ticks)
	var candidate_jam_mask := _jam_mask
	var candidate_jam_positions: PackedFloat64Array = _jam_positions.duplicate()
	var candidate_held_inputs: PackedFloat64Array = _held_inputs.duplicate()
	if activation_due:
		var failure_id := str(_plan.id)
		if _is_jam_id(failure_id):
			var axis := int(_plan.parameters.axis)
			candidate_jam_mask = 1 << axis
			candidate_jam_positions[axis] = servo[axis + 1]
		elif failure_id == "throttle_stuck":
			var resolved_high := float(_plan.parameters.high_demand)
			candidate_held_inputs = PackedFloat64Array([0.0, 0.0, 0.0, maxf(inputs[3], resolved_high)])
		elif failure_id == "throttle_stuck_low":
			var resolved_low := float(_plan.parameters.low_demand)
			candidate_held_inputs = PackedFloat64Array([0.0, 0.0, 0.0, minf(inputs[3], resolved_low)])
		elif failure_id == "radio_loss":
			candidate_held_inputs = _last_inputs.duplicate()
			candidate_held_inputs[3] = 0.0

	_pending = {
		"tick": _last_commit_tick + 1,
		"airborne": airborne,
		"airborne_ticks": next_airborne_ticks,
		"activation_due": activation_due,
		"inputs": _control_inputs(inputs),
		"jam_mask": candidate_jam_mask,
		"jam_positions": candidate_jam_positions,
		"held_inputs": candidate_held_inputs,
	}
	return {
		"ok": true,
		"activation_due": activation_due,
		"candidate_tick": _last_commit_tick + 1,
		"candidate_airborne_ticks": next_airborne_ticks,
	}


## Apply the staged/committed logical control effects. Healthy input arrays are returned unchanged.
func effective_inputs(raw: PackedFloat64Array) -> PackedFloat64Array:
	if not _started or not _effect_is_active():
		return raw
	var result: PackedFloat64Array = raw.duplicate()
	for axis in 3:
		result[axis] = effective_axis(axis, raw[axis])
	result[3] = effective_throttle(raw[3])
	return result


## Scalar axis form for callers that already evaluate controls channel by channel.
## Axis order is roll, pitch, yaw, throttle; throttle is handled by effective_throttle().
func effective_axis(axis: int, raw: float) -> float:
	if not _started or not _effect_is_active() or axis < 0 or axis > 2:
		return raw
	var failure_id := str(_plan.id)
	if _is_jam_id(failure_id) and int(_plan.parameters.axis) == axis:
		var mask := _effect_jam_mask()
		if (mask & (1 << axis)) != 0:
			return _effect_jam_positions()[axis]
	if int(BIAS_AXES.get(failure_id, -1)) == axis:
		return clampf(raw + float(_plan.parameters.bias), -1.0, 1.0)
	if int(TRAVEL_AXES.get(failure_id, -1)) == axis:
		var limit := float(_plan.parameters.limit)
		return clampf(raw, -limit, limit)
	if failure_id == "radio_loss":
		return _effect_held_inputs()[axis]
	return raw


## Scalar throttle form avoids allocating a packed array in each RK stage.
func effective_throttle(raw: float) -> float:
	if not _started or not _effect_is_active():
		return raw
	var failure_id := str(_plan.id)
	if failure_id == "throttle_limit":
		return minf(raw, float(_plan.parameters.maximum_demand))
	if failure_id in ["throttle_stuck", "throttle_stuck_low", "radio_loss"]:
		return _effect_held_inputs()[3]
	return raw


## Power-source loss is a separate adapter from receiver or logical-control faults.
## A just-due event is visible during RK evaluation but remains private until commit().
func propulsion_cut_active() -> bool:
	if not _started or not _effect_is_active():
		return false
	return str(_plan.id) in ["glow_fuel_cut", "electric_drive_loss"]


## Legacy v1 plans contain only model-independent control faults. A v2 plan is
## bound to the exact physical eligibility profile that created it.
func accepts_profile(profile: String) -> bool:
	if not _started or profile not in Catalog.PROFILES:
		return false
	if str(_plan.format) == PLAN_FORMAT_V1:
		return true
	return str(_plan.get("eligibility_profile", "")) == profile


## Rate multiplier for roll, pitch, or yaw. A jam freezes actual position at its onset value.
func servo_rate_factor(axis: int) -> float:
	if not _started or not _effect_is_active() or axis < 0 or axis > 2:
		return 1.0
	var failure_id := str(_plan.id)
	if _is_jam_id(failure_id) and int(_plan.parameters.axis) == axis:
		return 0.0
	if int(SLOW_AXES.get(failure_id, -1)) == axis:
		return float(_plan.parameters.rate_factor)
	return 1.0


## Commit the prepared candidate after the simulation accepts this tick.
## Returns true only for the tick that first activates the selected event.
func commit(tick: int) -> bool:
	if not _started:
		return false
	if _pending.is_empty():
		if bool(_plan.selected) or tick != _last_commit_tick + 1:
			return false
		_last_commit_tick = tick
		return false
	if tick != int(_pending.tick) or tick != _last_commit_tick + 1:
		_pending.clear()
		return false

	var newly_activated := bool(_pending.activation_due)
	var accepted_inputs := _control_inputs(effective_inputs(_pending.inputs))
	if newly_activated:
		_active = true
		_activation_tick = tick
		_jam_mask = int(_pending.jam_mask)
		_jam_positions = _pending.jam_positions.duplicate()
		_held_inputs = _pending.held_inputs.duplicate()
	else:
		_jam_mask = int(_pending.jam_mask)
		_jam_positions = _pending.jam_positions.duplicate()
		_held_inputs = _pending.held_inputs.duplicate()
	_airborne_ticks = int(_pending.airborne_ticks)
	_last_inputs = accepted_inputs
	_last_commit_tick = tick
	_pending.clear()
	return newly_activated


## Discard the unaccepted candidate without advancing the clock or publishing an event.
func rollback() -> void:
	_pending.clear()


## Return to the beginning of this exact resolved plan without drawing again.
func restart() -> void:
	if not _started:
		return
	_active = false
	_airborne_ticks = 0
	_activation_tick = -1
	_last_commit_tick = 0
	_last_inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	_jam_mask = 0
	_jam_positions = PackedFloat64Array([0.0, 0.0, 0.0])
	_held_inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	_pending.clear()


## Immutable, detached resolved plan. Mutating the returned dictionary cannot alter this runtime.
func plan() -> Dictionary:
	return _plan.duplicate(true) if _started else {}


## Self-contained checkpoint payload; it can be restored into a new Runtime instance.
func snapshot() -> Dictionary:
	if not _started or not _pending.is_empty():
		return {}
	return {
		"format": SNAPSHOT_FORMAT,
		"plan": _plan.duplicate(true),
		"plan_identity": str(_plan.identity),
		"event_id": str(_plan.id),
		"tick": _last_commit_tick,
		"airborne_ticks": _airborne_ticks,
		"active": _active,
		"activation_tick": _activation_tick,
		"last_inputs": _last_inputs.duplicate(),
		"jam_mask": _jam_mask,
		"jam_positions": _jam_positions.duplicate(),
		"held_inputs": _held_inputs.duplicate(),
	}


## Validate a self-contained checkpoint before changing any live state.
func can_restore(snapshot_value: Variant, tick: int) -> bool:
	if tick < 0 or typeof(snapshot_value) != TYPE_DICTIONARY:
		return false
	var source: Dictionary = snapshot_value
	if not _has_exact_keys(source, SNAPSHOT_KEYS):
		return false
	if typeof(source.format) != TYPE_STRING or source.format != SNAPSHOT_FORMAT:
		return false
	if typeof(source.tick) != TYPE_INT or int(source.tick) != tick:
		return false
	if typeof(source.plan_identity) != TYPE_STRING or typeof(source.event_id) != TYPE_STRING:
		return false
	if typeof(source.airborne_ticks) != TYPE_INT or typeof(source.active) != TYPE_BOOL:
		return false
	if typeof(source.activation_tick) != TYPE_INT or typeof(source.jam_mask) != TYPE_INT:
		return false
	if typeof(source.plan) != TYPE_DICTIONARY:
		return false
	if typeof(source.last_inputs) != TYPE_PACKED_FLOAT64_ARRAY \
		or typeof(source.jam_positions) != TYPE_PACKED_FLOAT64_ARRAY \
		or typeof(source.held_inputs) != TYPE_PACKED_FLOAT64_ARRAY:
		return false

	var rebuilt := _validated_plan(source.plan)
	if not bool(rebuilt.get("ok", false)):
		return false
	var resolved: Dictionary = rebuilt.plan
	if str(source.plan_identity) != str(resolved.identity) or str(source.event_id) != str(resolved.id):
		return false
	return _snapshot_state_is_valid(source, resolved, tick)


## Validate everything first, then atomically replace plan and runtime state.
func restore(snapshot_value: Variant, tick: int) -> bool:
	if not can_restore(snapshot_value, tick):
		return false
	var source: Dictionary = snapshot_value
	var resolved: Dictionary = _validated_plan(source.plan).plan
	_plan = resolved.duplicate(true)
	_config = _plan.config.duplicate(true)
	_seed = int(_plan.seed)
	_dt = float(_plan.dt)
	_started = true
	_last_commit_tick = int(source.tick)
	_airborne_ticks = int(source.airborne_ticks)
	_active = bool(source.active)
	_activation_tick = int(source.activation_tick)
	_last_inputs = source.last_inputs.duplicate()
	_jam_mask = int(source.jam_mask)
	_jam_positions = source.jam_positions.duplicate()
	_held_inputs = source.held_inputs.duplicate()
	_pending.clear()
	return true


## Stable public status for the HUD, pause screen, and debrief.
func status() -> Dictionary:
	if not _started:
		return {
			"active": false, "selected": false, "event_id": "", "label": "", "hint": "",
			"source_label": "", "activation_tick": -1, "airborne_ticks": 0,
			"onset_airborne_ticks": 0, "notify": true,
		}
	var failure_id := str(_plan.id)
	var definition: Dictionary = Catalog.definition(failure_id)
	var label_text := ""
	var hint_text := ""
	var source_label := ""
	if _active and not definition.is_empty():
		label_text = _status_label(failure_id)
		hint_text = str(definition.get("hint", ""))
		source_label = str(definition.get("source_label", ""))
	return {
		"active": _active,
		# A configured episode exists, so a healthy draw can be reported honestly after End.
		"enabled": true,
		"selected": bool(_plan.selected),
		"event_id": failure_id,
		"label": label_text,
		"hint": hint_text,
		"source_label": source_label,
		"eligibility_profile": str(_plan.get("eligibility_profile", "")),
		"activation_tick": _activation_tick,
		"airborne_ticks": _airborne_ticks,
		"onset_airborne_ticks": int(_plan.onset_airborne_ticks),
		"airborne_seconds": float(_airborne_ticks) * _dt,
		"notify": bool(_config.notify),
		"parameters": _plan.parameters.duplicate(true),
	}


func _status_label(failure_id: String) -> String:
	return str(Catalog.definition(failure_id).get("label", ""))


func _effect_is_active() -> bool:
	return _active or (not _pending.is_empty() and bool(_pending.get("activation_due", false)))


func _effect_jam_mask() -> int:
	if not _pending.is_empty() and bool(_pending.get("activation_due", false)):
		return int(_pending.jam_mask)
	return _jam_mask


func _effect_jam_positions() -> PackedFloat64Array:
	if not _pending.is_empty() and bool(_pending.get("activation_due", false)):
		return _pending.jam_positions
	return _jam_positions


func _effect_held_inputs() -> PackedFloat64Array:
	if not _pending.is_empty() and bool(_pending.get("activation_due", false)):
		return _pending.held_inputs
	return _held_inputs


func _snapshot_state_is_valid(source: Dictionary, resolved: Dictionary, tick: int) -> bool:
	var airborne_ticks := int(source.airborne_ticks)
	var activation_tick := int(source.activation_tick)
	var active := bool(source.active)
	var selected := bool(resolved.selected)
	var onset_ticks := int(resolved.onset_airborne_ticks)
	if airborne_ticks < 0 or airborne_ticks > tick:
		return false
	if source.last_inputs.size() != 4 or not _inputs_are_valid(source.last_inputs):
		return false
	# An unselected plan uses the fast path and never tracks airborne time or input.
	if not selected and (airborne_ticks != 0 or not _float_array_is_zero(source.last_inputs)):
		return false
	if not _held_inputs_are_valid(source.held_inputs) or not _jam_positions_are_valid(source.jam_positions):
		return false
	if int(source.jam_mask) < 0 or int(source.jam_mask) > 7:
		return false
	if active:
		if not selected or activation_tick < onset_ticks or activation_tick > tick or airborne_ticks < onset_ticks:
			return false
		# The event fires on the onset-th airborne tick. Each later airborne tick must fit
		# in the committed ticks after activation, including any grounded intervals.
		if airborne_ticks - onset_ticks > tick - activation_tick:
			return false
	else:
		if activation_tick != -1 or int(source.jam_mask) != 0:
			return false
		if not _float_array_is_zero(source.jam_positions) or not _float_array_is_zero(source.held_inputs):
			return false
		if selected and airborne_ticks >= onset_ticks:
			return false

	var failure_id := str(resolved.id)
	if not active:
		return true
	if _is_jam_id(failure_id):
		var axis := int(resolved.parameters.axis)
		if int(source.jam_mask) != (1 << axis):
			return false
		for position_index in 3:
			if position_index != axis and float(source.jam_positions[position_index]) != 0.0:
				return false
		if float(source.last_inputs[axis]) != float(source.jam_positions[axis]):
			return false
		return _float_array_is_zero(source.held_inputs)
	if int(source.jam_mask) != 0 or not _float_array_is_zero(source.jam_positions):
		return false
	if failure_id == "radio_loss":
		for axis in 3:
			if float(source.held_inputs[axis]) != float(source.last_inputs[axis]):
				return false
		if float(source.held_inputs[3]) != 0.0 or float(source.last_inputs[3]) != 0.0:
			return false
		return true
	if failure_id == "throttle_stuck":
		if float(source.held_inputs[0]) != 0.0 or float(source.held_inputs[1]) != 0.0 \
			or float(source.held_inputs[2]) != 0.0:
			return false
		var floor := float(resolved.parameters.high_demand)
		var held_throttle := float(source.held_inputs[3])
		return held_throttle >= floor and held_throttle <= 1.0 \
			and float(source.last_inputs[3]) == held_throttle
	if failure_id == "throttle_stuck_low":
		if float(source.held_inputs[0]) != 0.0 or float(source.held_inputs[1]) != 0.0 \
			or float(source.held_inputs[2]) != 0.0:
			return false
		var ceiling := float(resolved.parameters.low_demand)
		var held_low := float(source.held_inputs[3])
		return held_low >= 0.0 and held_low <= ceiling and float(source.last_inputs[3]) == held_low
	if failure_id == "throttle_limit":
		return _float_array_is_zero(source.held_inputs) \
			and float(source.last_inputs[3]) <= float(resolved.parameters.maximum_demand)
	if TRAVEL_AXES.has(failure_id):
		var travel_limit := float(resolved.parameters.limit)
		var travel_axis := int(TRAVEL_AXES[failure_id])
		return _float_array_is_zero(source.held_inputs) \
			and absf(float(source.last_inputs[travel_axis])) <= travel_limit
	return _float_array_is_zero(source.held_inputs)


func _validated_plan(plan_value: Variant) -> Dictionary:
	if typeof(plan_value) != TYPE_DICTIONARY:
		return {"ok": false}
	var source: Dictionary = plan_value
	if typeof(source.get("format")) != TYPE_STRING:
		return {"ok": false}
	var version := 3 if source.format == PLAN_FORMAT_V3 else (2 if source.format == PLAN_FORMAT_V2 else 1)
	var is_v2: bool = version >= 2
	if version == 1 and source.format != PLAN_FORMAT_V1:
		return {"ok": false}
	if not _has_exact_keys(source, PLAN_KEYS_V2 if is_v2 else PLAN_KEYS_V1):
		return {"ok": false}
	if typeof(source.rng_version) != TYPE_INT or typeof(source.catalog_version) != TYPE_INT:
		return {"ok": false}
	if typeof(source.rng_name) != TYPE_STRING or typeof(source.seed) != TYPE_INT:
		return {"ok": false}
	if typeof(source.dt) != TYPE_FLOAT or typeof(source.config) != TYPE_DICTIONARY:
		return {"ok": false}
	if is_v2 and typeof(source.eligibility_profile) != TYPE_STRING:
		return {"ok": false}
	if typeof(source.selected) != TYPE_BOOL or typeof(source.id) != TYPE_STRING:
		return {"ok": false}
	if typeof(source.onset_airborne_seconds) != TYPE_INT \
		or typeof(source.onset_airborne_ticks) != TYPE_INT \
		or typeof(source.parameters) != TYPE_DICTIONARY or typeof(source.identity) != TYPE_STRING:
		return {"ok": false}
	var rebuilt: Dictionary
	if version == 3:
		rebuilt = _build_plan_v3(source.config, int(source.seed), float(source.dt), source.eligibility_profile)
	elif version == 2:
		rebuilt = _build_plan_v2(source.config, int(source.seed), float(source.dt), source.eligibility_profile)
	else:
		rebuilt = _build_plan_v1(source.config, int(source.seed), float(source.dt))
	if not bool(rebuilt.get("ok", false)):
		return {"ok": false}
	var expected: Dictionary = rebuilt.plan
	if _canonical_json(source) != _canonical_json(expected):
		return {"ok": false}
	return {"ok": true, "plan": expected}


static func _build_plan_v1(config_value: Variant, seed_value: Variant, dt_value: Variant) -> Dictionary:
	return _build_plan_versioned(config_value, seed_value, dt_value, "", 1)


static func _build_plan_v2(config_value: Variant, seed_value: Variant, dt_value: Variant,
		eligibility_profile: String) -> Dictionary:
	if eligibility_profile not in Catalog.PROFILES:
		return {"ok": false, "message": "unknown failure eligibility profile"}
	return _build_plan_versioned(config_value, seed_value, dt_value, eligibility_profile, 2)


static func _build_plan_v3(config_value: Variant, seed_value: Variant, dt_value: Variant,
		eligibility_profile: String) -> Dictionary:
	if eligibility_profile not in Catalog.PROFILES:
		return {"ok": false, "message": "unknown failure eligibility profile"}
	return _build_plan_versioned(config_value, seed_value, dt_value, eligibility_profile, 3)


static func _build_plan_versioned(config_value: Variant, seed_value: Variant, dt_value: Variant,
		eligibility_profile: String, version: int) -> Dictionary:
	if typeof(seed_value) != TYPE_INT or int(seed_value) < 0 or int(seed_value) > UINT32_MAX:
		return {"ok": false, "message": "failure seed must be an unsigned 32-bit integer"}
	if typeof(dt_value) != TYPE_FLOAT or not is_finite(float(dt_value)) \
		or float(dt_value) < MIN_DT or float(dt_value) > MAX_DT:
		return {"ok": false, "message": "failure timestep must be finite and between 0.000001 and 1 second"}
	var config_result: Dictionary = Config.validate(config_value)
	if not bool(config_result.get("ok", false)):
		return {"ok": false, "message": "failure config is invalid", "errors": config_result.get("errors", PackedStringArray())}
	var normalized: Dictionary = config_result.config
	var severity := Config.DEFAULT_SEVERITY
	var onset_window: Array = Config.onset_window(Config.DEFAULT_ONSET)
	var v3_ids: Array[String] = []
	if version < 3:
		if not Config.uses_default_selection(normalized):
			return {"ok": false, "message": "failure severity, onset window and type selection need a v3 plan"}
		normalized = Config.legacy_projection(normalized)
	else:
		severity = str(normalized.severity)
		onset_window = Config.onset_window(str(normalized.onset))
		v3_ids = Catalog.failure_ids_v3(bool(normalized.include_catastrophic), eligibility_profile,
			normalized.excluded_ids)
		# Refuse before drawing so the same request never launches only on lucky seeds.
		if int(normalized.probability_percent) > 0 and v3_ids.is_empty():
			return {"ok": false, "message": NO_ELIGIBLE_MESSAGE}
	var selected := false
	var failure_id := ""
	var onset_seconds := 0
	var onset_ticks := 0
	var parameters: Dictionary = {}
	var state := (int(seed_value) ^ RNG_DOMAIN_TAG ^ (RNG_VERSION << 24)) & UINT32_MASK
	if state == 0:
		state = RNG_ZERO_REPLACEMENT
	var occurrence_draw := _draw_bounded(state, 100)
	state = int(occurrence_draw[0])
	var occurrence_roll := int(occurrence_draw[1])
	selected = occurrence_roll < int(normalized.probability_percent)
	if selected:
		var ids: Array[String] = v3_ids if version == 3 \
			else Catalog.failure_ids(bool(normalized.include_catastrophic), eligibility_profile)
		if ids.is_empty():
			return {"ok": false, "message": "failure profile has no eligible events"}
		var event_draw := _draw_bounded(state, ids.size())
		state = int(event_draw[0])
		failure_id = ids[int(event_draw[1])]
		parameters = _resolve_parameters(failure_id, state, severity)
		state = int(parameters["_rng_state"])
		parameters.erase("_rng_state")
		var earliest := int(onset_window[0])
		var latest := int(onset_window[1])
		var onset_draw := _draw_bounded(state, latest - earliest + 1)
		state = int(onset_draw[0])
		onset_seconds = earliest + int(onset_draw[1])
		var first_tick := int(ceili(float(earliest) / float(dt_value)))
		var last_tick := int(floor(float(latest) / float(dt_value)))
		onset_ticks = mini(int(ceili(float(onset_seconds) / float(dt_value))), last_tick)
		onset_ticks = maxi(onset_ticks, first_tick)

	var plan_data: Dictionary = {
		"format": [PLAN_FORMAT_V1, PLAN_FORMAT_V2, PLAN_FORMAT_V3][version - 1],
		"rng_version": RNG_VERSION,
		"rng_name": RNG_NAME,
		"catalog_version": [Catalog.LEGACY_VERSION, Catalog.PROFILE_VERSION, Catalog.VERSION][version - 1],
		"seed": int(seed_value),
		"dt": float(dt_value),
		"config": normalized.duplicate(true),
		"selected": selected,
		"id": failure_id,
		"onset_airborne_seconds": onset_seconds,
		"onset_airborne_ticks": onset_ticks,
		"parameters": parameters,
		"identity": "",
	}
	if version >= 2:
		plan_data["eligibility_profile"] = eligibility_profile
	plan_data.identity = _identity_for(plan_data)
	return {"ok": true, "plan": plan_data}


static func _resolve_parameters(failure_id: String, initial_state: int, severity := "standard") -> Dictionary:
	var state := initial_state
	var parameters: Dictionary = {}
	if JAM_AXES.has(failure_id):
		parameters = {"mechanism": "logical_axis_position_hold", "axis": int(JAM_AXES[failure_id])}
	elif BIAS_AXES.has(failure_id):
		var bias_draw := _draw_band(state, "bias", severity)
		state = int(bias_draw[0])
		parameters = {"mechanism": "persistent_command_bias", "bias": float(bias_draw[1]) / 100.0}
		var sign_draw := _draw_bounded(state, 2)
		state = int(sign_draw[0])
		if int(sign_draw[1]) == 0:
			parameters.bias = -float(parameters.bias)
	elif SLOW_AXES.has(failure_id):
		var rate_draw := _draw_band(state, "rate_factor", severity)
		state = int(rate_draw[0])
		parameters = {
			"mechanism": "reduced_servo_rate",
			"rate_factor": float(rate_draw[1]) / 100.0,
		}
	elif TRAVEL_AXES.has(failure_id):
		var travel_draw := _draw_band(state, "travel_limit", severity)
		state = int(travel_draw[0])
		parameters = {
			"mechanism": "restricted_actuator_travel",
			"axis": int(TRAVEL_AXES[failure_id]),
			"limit": float(travel_draw[1]) / 100.0,
		}
	elif failure_id == "throttle_limit":
		var limit_draw := _draw_band(state, "throttle_ceiling", severity)
		state = int(limit_draw[0])
		parameters = {
			"mechanism": "throttle_demand_ceiling",
			"maximum_demand": float(limit_draw[1]) / 100.0,
		}
	elif failure_id == "throttle_stuck":
		var stuck_draw := _draw_band(state, "throttle_high", severity)
		state = int(stuck_draw[0])
		parameters = {
			"mechanism": "elevated_throttle_demand_hold",
			"high_demand": float(stuck_draw[1]) / 100.0,
			"capture_policy": "max_activation_demand_and_resolved_high_demand",
		}
	elif failure_id == "throttle_stuck_low":
		var low_draw := _draw_band(state, "throttle_low", severity)
		state = int(low_draw[0])
		parameters = {
			"mechanism": "reduced_throttle_demand_hold",
			"low_demand": float(low_draw[1]) / 100.0,
			"capture_policy": "min_activation_demand_and_resolved_low_demand",
		}
	elif failure_id == "radio_loss":
		parameters = {
			"mechanism": "sustained_receiver_link_loss",
			"surface_policy": "hold_last_valid_commands",
			"throttle_preset": 0.0,
		}
	elif failure_id == "glow_fuel_cut":
		parameters = {"mechanism": "finite_glow_combustion_cut"}
	elif failure_id == "electric_drive_loss":
		parameters = {"mechanism": "electric_motor_drive_disconnect"}
	parameters["_rng_state"] = state
	return parameters


## Uniform integer in an inclusive severity band (hundredths); returns [state, value].
static func _draw_band(state: int, band: String, severity: String) -> Array[int]:
	var bounds: Array = SEVERITY_BANDS[band][severity]
	var draw := _draw_bounded(state, int(bounds[1]) - int(bounds[0]) + 1)
	return [int(draw[0]), int(bounds[0]) + int(draw[1])]


static func _draw_u32(state: int) -> Array[int]:
	var value := state & UINT32_MASK
	value = (value ^ ((value << 13) & UINT32_MASK)) & UINT32_MASK
	value = (value ^ (value >> 17)) & UINT32_MASK
	value = (value ^ ((value << 5) & UINT32_MASK)) & UINT32_MASK
	return [value, value]


## Uniform bounded draw by rejection sampling over the nonzero xorshift32 period.
static func _draw_bounded(state: int, upper_bound: int) -> Array[int]:
	var accepted_range := UINT32_MAX - (UINT32_MAX % upper_bound)
	var cursor := state
	while true:
		var draw := _draw_u32(cursor)
		cursor = int(draw[0])
		if int(draw[1]) <= accepted_range:
			return [cursor, int(draw[1]) % upper_bound]
	return [cursor, 0]


static func _identity_for(plan_value: Dictionary) -> String:
	var canonical: Dictionary = plan_value.duplicate(true)
	canonical.erase("identity")
	# Notifications affect presentation only; the resolved physical failure plan stays identical.
	if typeof(canonical.get("config")) == TYPE_DICTIONARY:
		canonical["config"].erase("notify")
	return _canonical_json(canonical).sha256_text()


static func _canonical_json(value: Variant) -> String:
	return JSON.stringify(_sort_value(value), "", true, true)


static func _sort_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var source: Dictionary = value
		var sorted: Dictionary = {}
		var keys: Array = source.keys()
		keys.sort()
		for key: Variant in keys:
			sorted[key] = _sort_value(source[key])
		return sorted
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item: Variant in value:
			result.append(_sort_value(item))
		return result
	return value


static func _has_exact_keys(source: Dictionary, expected_keys: Array[String]) -> bool:
	if source.size() != expected_keys.size():
		return false
	for key: String in expected_keys:
		if not source.has(key):
			return false
	return true


func _inputs_are_valid(inputs: PackedFloat64Array) -> bool:
	if inputs.size() < 4:
		return false
	for axis in 3:
		if not is_finite(inputs[axis]) or inputs[axis] < -1.0 or inputs[axis] > 1.0:
			return false
	return is_finite(inputs[3]) and inputs[3] >= 0.0 and inputs[3] <= 1.0


func _control_inputs(inputs: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([inputs[0], inputs[1], inputs[2], inputs[3]])


func _servos_are_valid(servo: PackedFloat64Array) -> bool:
	if servo.size() < 4:
		return false
	for axis in 3:
		var value: float = servo[axis + 1]
		if not is_finite(value) or value < -1.0 or value > 1.0:
			return false
	return true


func _held_inputs_are_valid(inputs: PackedFloat64Array) -> bool:
	return inputs.size() == 4 and _inputs_are_valid(inputs)


func _jam_positions_are_valid(positions: PackedFloat64Array) -> bool:
	if positions.size() != 3:
		return false
	for value: float in positions:
		if not is_finite(value) or value < -1.0 or value > 1.0:
			return false
	return true


func _float_array_is_zero(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if value != 0.0:
			return false
	return true


func _is_jam_id(failure_id: String) -> bool:
	return JAM_AXES.has(failure_id)
