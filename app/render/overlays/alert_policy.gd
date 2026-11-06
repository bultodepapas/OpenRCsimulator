## HUD-09-R1: presentation-only alert catalog, priority and optional training cues.
## Reads accepted snapshots; thresholds are coaching cues, never aircraft operating limits.
extends RefCounted

const ORDER := ["controller_lost", "failsafe", "stall", "low", "battery_empty", "battery_critical", "battery_lvc", "fuel_empty", "battery_hot", "fuel_reserve", "fuel_reserve_estimated", "battery", "far", "sink_rate", "high_load", "steep_bank", "safe", "experimental"]
const DANGER := ["controller_lost", "failsafe", "stall", "low", "battery_empty", "battery_critical", "battery_lvc", "fuel_empty"]
const ENERGY := ["battery", "battery_hot", "fuel_reserve", "fuel_reserve_estimated"]
const TRAINING := ["sink_rate", "high_load", "steep_bank"]
const STATUS := ["safe", "experimental"]
const TRAINING_MIN_AGL_M := 10.0
const TRAINING_MIN_SPEED_MPS := 3.0
const SINK_RATE_MPS := 6.0
const STEEP_BANK_DEG := 75.0
const HIGH_LOAD_G := 4.0
const TRAINING_DWELL_S := 0.6
const TRAINING_CLEAR_S := 0.4

var _training_active := PackedStringArray()
var _training_pending := {}
var _last_time := -INF


func reset() -> void:
	_training_active = PackedStringArray()
	_training_pending.clear()
	_last_time = -INF


## Only the optional coaching cues have dwell/clear grace. Urgent source codes are never delayed.
## Uses accepted simulation time: pausing cannot advance a cue; rewind/reset starts a fresh window.
func update(snap: Dictionary, settings: Dictionary) -> PackedStringArray:
	var candidates := additional_codes(snap, settings)
	var out := PackedStringArray()
	if candidates.has("fuel_empty"): out.append("fuel_empty")
	var t: Dictionary = snap.get("telemetry", {})
	var time: Variant = t.get("time_s")
	if not settings.get("warning_training", false) or not _finite(time) \
			or not _finite(t.get("height_agl")) or float(t.height_agl) <= TRAINING_MIN_AGL_M \
			or not _finite(t.get("airspeed")) or float(t.airspeed) < TRAINING_MIN_SPEED_MPS:
		reset()
		return out
	var now := float(time)
	if now < _last_time: reset()
	_last_time = now
	for code: String in TRAINING:
		var wanted := candidates.has(code)
		if wanted == _training_active.has(code):
			_training_pending.erase(code)
			continue
		if not _training_pending.has(code): _training_pending[code] = now
		var dwell := TRAINING_DWELL_S if wanted else TRAINING_CLEAR_S
		if now - float(_training_pending[code]) + 0.000001 >= dwell:
			if wanted: _training_active.append(code)
			else: _training_active.remove_at(_training_active.find(code))
			_training_pending.erase(code)
	out.append_array(_training_active)
	return out


static func severity(code: String) -> String:
	if code in DANGER: return "danger"
	if code in STATUS: return "info"
	return "caution"


static func title_for(code: String) -> String:
	match code:
		"controller_lost": return "CONTROLLER LOST"
		"failsafe": return "RADIO LOST"
		"stall": return "STALL"
		"low": return "LOW ALTITUDE"
		"far": return "FAR FROM PILOT"
		"battery_empty": return "BATTERY EMPTY"
		"battery_critical": return "BATTERY CRITICAL"
		"battery_lvc": return "POWER LIMITED"
		"fuel_empty": return "NO USABLE FUEL"
		"battery_hot": return "BATTERY HOT"
		"fuel_reserve", "fuel_reserve_estimated": return "FUEL RESERVE"
		"battery": return "BATTERY LOW"
		"sink_rate": return "RAPID DESCENT"
		"high_load": return "HIGH G LOAD"
		"steep_bank": return "STEEP BANK"
		"safe": return "RADIO SAFE"
		"experimental": return "EXPERIMENTAL MODEL"
	return code.to_upper()


static func detail_for(code: String) -> String:
	match code:
		"controller_lost": return "Select controls to continue."
		"failsafe": return "Reconnect the radio to continue."
		"stall": return "Reduce angle of attack."
		"low": return "Fast sink near terrain."
		"far": return "Come closer for a clearer view."
		"battery_empty", "battery_critical", "battery_lvc": return "Land as soon as possible."
		"fuel_empty": return "Prepare for an unpowered landing."
		"battery_hot": return "Land and let the pack cool."
		"fuel_reserve": return "Reserve reached. Plan to land."
		"fuel_reserve_estimated": return "Estimated reserve reached. Plan to land."
		"battery": return "Low energy. Plan to land."
		"sink_rate": return "Descending faster than 6 m/s."
		"high_load": return "Body G magnitude above 4 g."
		"steep_bank": return "Bank angle beyond 75°."
		"safe": return "Lower throttle to arm."
		"experimental": return "Flight model under development."
	return ""


## No model truth for pack alarms is inferred here. Existing BatterySensors codes remain authoritative.
static func additional_codes(snap: Dictionary, settings: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var fuel: Dictionary = snap.get("mass_sample", {})
	var usable: Variant = fuel.get("fuel_usable_kg")
	if fuel.get("ok", false) and fuel.get("finite_fuel", false) and _finite(usable) and float(usable) == 0.0:
		out.append("fuel_empty")
	if not settings.get("warning_training", false): return out
	var t: Dictionary = snap.get("telemetry", {})
	if not _finite(t.get("height_agl")) or float(t.height_agl) <= TRAINING_MIN_AGL_M: return out
	if not _finite(t.get("airspeed")) or float(t.airspeed) < TRAINING_MIN_SPEED_MPS: return out
	if _finite(t.get("vertical_speed")) and float(t.vertical_speed) < -SINK_RATE_MPS:
		out.append("sink_rate")
	if _finite(t.get("load_factor")) and absf(float(t.load_factor)) > HIGH_LOAD_G:
		out.append("high_load")
	if _finite(t.get("bank_deg")) and absf(float(t.bank_deg)) > STEEP_BANK_DEG:
		out.append("steep_bank")
	return out


## Canonical priority, deduplication and category controls. Critical conditions bypass advisory switches.
## A stronger energy/terrain alert replaces redundant reminders without changing sampled alarm state.
static func select_codes(raw: PackedStringArray, settings: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for code: String in ORDER:
		if not raw.has(code): continue
		if code not in DANGER:
			if code in ENERGY and not settings.get("warning_energy", true): continue
			if code == "far" and not settings.get("warning_navigation", true): continue
			if code in STATUS and not settings.get("warning_status", true): continue
			if code in TRAINING and not settings.get("warning_training", false): continue
		if code == "failsafe" and raw.has("controller_lost"): continue
		if code == "safe" and (raw.has("controller_lost") or raw.has("failsafe")): continue
		if code in ["battery", "battery_critical", "battery_lvc"] and raw.has("battery_empty"): continue
		if code == "battery" and (raw.has("battery_critical") or raw.has("battery_lvc")): continue
		if code in ["fuel_reserve", "fuel_reserve_estimated"] and raw.has("fuel_empty"): continue
		if code == "fuel_reserve_estimated" and raw.has("fuel_reserve"): continue
		if code == "sink_rate" and raw.has("low"): continue
		out.append(code)
	return out


static func _finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
