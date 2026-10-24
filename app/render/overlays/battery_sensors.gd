# BAT-14: radio-style battery telemetry (docs/plans/battery-realism.md §6.1, §6.3). Pure and deterministic: fed once
# per overlay refresh with the session's electrical_state(), it returns what a transmitter would show (EdgeTX
# analogues: VFAS pack voltage, Curr, Fuel, Cels lowest cell, Tmp1). Readings are sampled and quantized; consumed mAh
# is integrated from the sensor's own current samples, so it is not the model's true charge; remaining % is mAh-based;
# alarms are debounced. True SOC is never read here: a radio cannot know it. No nodes, no session access.
extends RefCounted

## Presentation defaults, not hardware measurements: one telemetry frame per period at these resolutions.
const SAMPLE_PERIOD_S := 0.1
## The 10 Hz overlay refresh lands on 1/240 s physics ticks and frame boundaries: a sample is due this much early.
const SAMPLE_SLACK_S := 0.01
const VOLTAGE_STEP_V := 0.01
const CURRENT_STEP_A := 0.1
const TEMPERATURE_STEP_K := 1.0
## Sparkline memory: the last 60 s at the sample period.
const HISTORY_S := 60.0
const HISTORY_SIZE := 600

## Alarm defaults in the Betaflight documentation style: per cell, on the LOADED sensor voltage (the lowest cell when
## the pack reports one, otherwise the average). A sag alarm during a punch-out is realistic and intended (§6.3).
const CELL_WARNING_V := 3.5
const CELL_CRITICAL_V := 3.3
## An alarm sounds after the voltage stays below its threshold this long, and clears above threshold + release.
const ALARM_HOLD_S := 2.0
const ALARM_RELEASE_V := 0.05
const USED_WARNING_FRACTION := 0.8
## Estimated presentation threshold (60 °C), not a cited cell limit; clears one sensor step below it.
const HOT_K := 333.15
const HOT_RELEASE_K := 1.0
## Voltage alarms only where the loaded voltage tracks the charge. LiFePO4 and NiMH discharge curves are flat, so a
## voltage alarm (or a voltage-based %) would be unreliable: those packs get the used-mAh alarm only (plan §5.1).
const VOLTAGE_ALARM_CHEMISTRIES := ["lipo", "lihv", "liion"]
const LVC_STATES := ["soft_cut", "hard_cut"]
const ZERO_C_K := 273.15
const COULOMB_PER_MAH := 3.6
## Tolerance for comparing sums of float times and converted thresholds.
const EPS := 1e-9

var _has_sample := false
var _sample_t := 0.0
var _identity := ""
var _used_mah := 0.0
var _held_current_a := 0.0
var _capacity_mah := NAN
var _warning := { on = false, since = NAN }
var _critical := { on = false, since = NAN }
var _hot := false
var _history_v := PackedFloat64Array()
var _history_a := PackedFloat64Array()
var _reading := {}


func _init() -> void:
	reset()


## Forgets every sample, the consumed mAh and the alarms (a new pack, a restarted flight).
func reset() -> void:
	_has_sample = false
	_sample_t = 0.0
	_identity = ""
	_used_mah = 0.0
	_held_current_a = 0.0
	_capacity_mah = NAN
	_warning = { on = false, since = NAN }
	_critical = { on = false, since = NAN }
	_hot = false
	_history_v = PackedFloat64Array()
	_history_a = PackedFloat64Array()
	_reading = empty()


## time_s: simulation time of `state`; state: electrical_state() of a dynamic battery, or {}. Takes a sample when
## one is due and returns the radio's view (see empty() for the fields). Time running backwards or a different pack
## restarts the sensor. Between samples the last reading holds, as on a radio screen.
func update(time_s: float, state: Dictionary, include_history := true) -> Dictionary:
	if not state.get("ok", false) or not is_finite(time_s):
		return _export_reading(include_history)
	var identity := _identity_of(state)
	if _has_sample and (time_s < _sample_t or identity != _identity):
		reset()
	if not _has_sample or time_s - _sample_t >= SAMPLE_PERIOD_S - SAMPLE_SLACK_S:
		_identity = identity
		_sample(time_s, state)
	return _export_reading(include_history)


## Keep collecting history for later inspection, but only copy it for a visible detailed battery panel.
## Returned arrays/dictionaries remain caller-owned; scalar-only consumers receive empty history arrays.
func _export_reading(include_history: bool) -> Dictionary:
	var out := _reading.duplicate(true)
	if include_history:
		out.history_v = _history_v.duplicate()
		out.history_a = _history_a.duplicate()
	return out


## The reading before any sample: every number unknown (NAN), no alarms, empty history.
static func empty() -> Dictionary:
	var alarms: Array[String] = []
	return {
		valid = false, kind = "", display_name = "", chemistry = "", series = 0, parallel = 0, capacity_mah = NAN,
		time_s = NAN, pack_voltage_v = NAN, cell_avg_v = NAN, cell_min_v = NAN, current_a = NAN, power_w = NAN,
		used_mah = 0, used_mah_raw = 0.0, remaining_pct = NAN, temperature_c = NAN, esc_state = "",
		alarms = alarms, history_v = PackedFloat64Array(), history_a = PackedFloat64Array(),
	}


## A sensor reading: the nearest multiple of `step`; NAN stays NAN.
static func quantize(value: float, step: float) -> float:
	if not is_finite(value):
		return NAN
	return snappedf(value, step) + 0.0 # + 0.0 turns a rounded −0 into 0, so a display never reads "-0.0"


func _sample(time_s: float, state: Dictionary) -> void:
	var ecm := str(state.get("battery_kind", "")) == "pack_ecm"
	var volts := quantize(_number(state, "bus_voltage_v"), VOLTAGE_STEP_V)
	var amps := quantize(_number(state, "pack_current_a"), CURRENT_STEP_A)
	# Fuel: the held current sample over the time since it was taken (zero-order hold), never the true charge.
	if _has_sample:
		_used_mah += _held_current_a * (time_s - _sample_t) / COULOMB_PER_MAH
	else:
		_capacity_mah = _capacity_of(state, ecm)
	_held_current_a = amps if is_finite(amps) else 0.0
	_has_sample = true
	_sample_t = time_s
	var used := roundi(_used_mah)
	var series: int = int(state.get("series", 0)) if ecm else 0
	var cell_avg := NAN
	var cell_min := NAN
	var temperature_c := NAN
	if ecm:
		cell_avg = quantize(_number(state, "cell_voltage_avg_v"), VOLTAGE_STEP_V)
		if not is_finite(cell_avg) and series > 0 and is_finite(volts):
			cell_avg = quantize(volts / series, VOLTAGE_STEP_V)
		cell_min = quantize(_number(state, "cell_voltage_min_v"), VOLTAGE_STEP_V)
		temperature_c = quantize(_number(state, "temperature_k") - ZERO_C_K, TEMPERATURE_STEP_K)
	var remaining := NAN
	if is_finite(_capacity_mah) and _capacity_mah > 0.0:
		remaining = clampf(100.0 * (1.0 - used / _capacity_mah), 0.0, 100.0)
	var esc := str(state.get("esc_state", "")) if ecm else ""
	var alarms: Array[String] = []
	if ecm:
		alarms = _alarms(time_s, state, cell_min if is_finite(cell_min) else cell_avg, used, temperature_c, esc)
	_record(volts, amps)
	_reading = {
		valid = true, kind = "pack_ecm" if ecm else "legacy",
		display_name = str(state.get("display_name", "")) if ecm else "",
		chemistry = str(state.get("chemistry", "")) if ecm else "",
		series = series, parallel = int(state.get("parallel", 0)) if ecm else 0, capacity_mah = _capacity_mah,
		time_s = time_s, pack_voltage_v = volts, cell_avg_v = cell_avg, cell_min_v = cell_min, current_a = amps,
		power_w = volts * amps, used_mah = used, used_mah_raw = _used_mah, remaining_pct = remaining,
		temperature_c = temperature_c, esc_state = esc, alarms = alarms,
		history_v = PackedFloat64Array(), history_a = PackedFloat64Array(),
	}


## Alarm names, most urgent first: exhausted, cell_critical, lvc, cell_warning, used_capacity, hot.
func _alarms(time_s: float, state: Dictionary, cell_v: float, used: int, temperature_c: float, esc: String) -> Array[String]:
	var out: Array[String] = []
	if str(state.get("chemistry", "")) in VOLTAGE_ALARM_CHEMISTRIES and is_finite(cell_v):
		_debounce(_critical, cell_v, CELL_CRITICAL_V, time_s)
		_debounce(_warning, cell_v, CELL_WARNING_V, time_s)
	else:
		_critical = { on = false, since = NAN }
		_warning = { on = false, since = NAN }
	var hot_c := HOT_K - ZERO_C_K
	if not is_finite(temperature_c):
		_hot = false
	elif _hot:
		_hot = temperature_c >= hot_c - HOT_RELEASE_K
	else:
		_hot = temperature_c >= hot_c - EPS
	if bool(state.get("exhausted", false)):
		out.append("exhausted")
	if _critical.on:
		out.append("cell_critical")
	if esc in LVC_STATES:
		out.append("lvc")
	if _warning.on:
		out.append("cell_warning")
	if is_finite(_capacity_mah) and _capacity_mah > 0.0 and used >= USED_WARNING_FRACTION * _capacity_mah:
		out.append("used_capacity")
	if _hot:
		out.append("hot")
	return out


## One voltage alarm: on after ALARM_HOLD_S continuously below `threshold`; off above threshold + ALARM_RELEASE_V.
static func _debounce(alarm: Dictionary, value: float, threshold: float, time_s: float) -> void:
	if alarm.on:
		if value > threshold + ALARM_RELEASE_V:
			alarm.on = false
			alarm.since = NAN
		return
	if value >= threshold:
		alarm.since = NAN
		return
	if is_nan(alarm.since):
		alarm.since = time_s
	if time_s - float(alarm.since) >= ALARM_HOLD_S - EPS:
		alarm.on = true


func _record(volts: float, amps: float) -> void:
	_history_v.append(volts)
	_history_a.append(amps)
	while _history_v.size() > HISTORY_SIZE:
		_history_v.remove_at(0)
		_history_a.remove_at(0)


## The capacity a pilot sets on the radio: the pack's rated capacity, or for the older synthetic packs (no rating)
## the charge they start the flight with.
static func _capacity_of(state: Dictionary, ecm: bool) -> float:
	if ecm:
		var rated := _number(state, "rated_capacity_ah")
		return rated * 1000.0 if is_finite(rated) and rated > 0.0 else NAN
	var total := _number(state, "consumed_charge_c") + _number(state, "remaining_charge_c")
	return total / COULOMB_PER_MAH if is_finite(total) and total > 0.0 else NAN


static func _identity_of(state: Dictionary) -> String:
	if str(state.get("battery_kind", "")) != "pack_ecm":
		return "legacy"
	return "%s|%s|%s|%s" % [state.get("pack_id", ""), state.get("series", 0), state.get("parallel", 0), state.get("rated_capacity_ah", 0.0)]


## A finite float field, or NAN when absent or not a number.
static func _number(state: Dictionary, key: String) -> float:
	var value: Variant = state.get(key)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return NAN
	return float(value)
