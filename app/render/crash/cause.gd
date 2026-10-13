## CR-01e: why the airplane crashed, from the last seconds of flight. Pure: samples in, a cause out. Rules are
## ordered from the most specific trigger to the most general flight condition; thresholds come from aircraft data
## (stall-blend α, start speed) and the HUD's STALL margin, never per-aircraft tuning. Presentation only.
extends RefCounted
class_name CrashCause

const Telemetry := preload("res://render/overlays/telemetry.gd")

## Sampling and history the director keeps (sim time).
const SAMPLE_INTERVAL_S := 0.05
const HISTORY_S := 5.0
## Rule windows and thresholds (presentation estimates, documented in CR-01e).
const STALL_WINDOW_S := 2.5
const MIN_STALL_S := 0.25
const SPIN_YAW_DPS := 90.0
const SPIN_MIN_S := 0.5
const TIP_ROLL_DPS := 120.0
const TIP_BANK_CHANGE_DEG := 45.0
const DIVE_PITCH_DEG := -45.0
const DIVE_SPEED_FACTOR := 1.3
const HARD_SINK_MPS := 2.0
const LEVEL_PITCH_DEG := 20.0
const LEVEL_BANK_DEG := 30.0
const STEEP_BANK_DEG := 60.0
const GROUND_HEIGHT_M := 0.5
const GROUND_TIME_S := 1.0
const DEAD_STICK_S := 2.0
const LOW_SPEED_FACTOR := 0.8


## samples: oldest first, each {t, airspeed, alpha_deg, pitch_deg, bank_deg, roll_rate_dps, yaw_rate_dps,
## height_agl, vertical_speed, throttle, engine_running}. impact: {trigger, obstacle_kind, component_group, speed_mps}.
## reference: {stall_alpha_deg, start_speed}. Returns {id, label, detail, factors (Array of String)}.
static func classify(samples: Array, impact: Dictionary, reference: Dictionary) -> Dictionary:
	var last: Dictionary = samples.back() if not samples.is_empty() else {}
	var t_end := float(last.get("t", 0.0))
	var stall_alpha := float(reference.get("stall_alpha_deg", INF)) - Telemetry.STALL_MARGIN_DEG
	var start_speed := maxf(float(reference.get("start_speed", 15.0)), 1.0)
	var factors := _factors(last, start_speed)
	var trigger := str(impact.get("trigger", ""))
	var group := str(impact.get("component_group", ""))
	if trigger == "scenery":
		var obstacle := str(impact.get("obstacle_kind", "obstacle")).replace("_", " ")
		return _cause("obstacle", "Hit a %s" % obstacle, "%.1f m/s" % float(impact.get("speed_mps", 0.0)), factors)
	if trigger == "gear_limit":
		return _cause("gear_collapse", "Hard landing: landing gear collapsed", _state_text(last), factors)
	if samples.is_empty():
		return _cause("unknown", "Crash", "no flight history", factors)
	if _all_within(samples, t_end - GROUND_TIME_S, func(s: Dictionary) -> bool: return float(s.height_agl) < GROUND_HEIGHT_M):
		if group == "propeller":
			return _cause("prop_strike", "Prop strike on the ground", _state_text(last), factors)
		return _cause("ground_handling", "Nose-over or ground loop on the ground", _state_text(last), factors)
	if _all_within(samples, t_end - DEAD_STICK_S, func(s: Dictionary) -> bool: return not bool(s.engine_running)):
		return _cause("dead_stick", "Engine stopped: dead-stick landing failed", _state_text(last), factors)
	var window := samples.filter(func(s: Dictionary) -> bool: return float(s.t) >= t_end - STALL_WINDOW_S)
	var stalled := window.filter(func(s: Dictionary) -> bool: return float(s.alpha_deg) >= stall_alpha and float(s.airspeed) >= Telemetry.STALL_MIN_SPEED)
	if _duration(stalled) >= MIN_STALL_S:
		var first: Dictionary = stalled[0]
		var after := window.filter(func(s: Dictionary) -> bool: return float(s.t) >= float(first.t))
		var spinning := after.filter(func(s: Dictionary) -> bool: return absf(float(s.yaw_rate_dps)) >= SPIN_YAW_DPS)
		var stall_text := "at %.0f m: α %.0f°, %.1f m/s, bank %.0f°" % [float(first.height_agl), float(first.alpha_deg), float(first.airspeed), float(first.bank_deg)]
		if _duration(spinning) >= SPIN_MIN_S:
			return _cause("spin", "Spin", stall_text, factors)
		var max_roll := 0.0
		var bank_change := 0.0
		for s: Dictionary in after:
			max_roll = maxf(max_roll, absf(float(s.roll_rate_dps)))
			if float(s.t) <= float(first.t) + 1.0:
				bank_change = maxf(bank_change, absf(_wrap(float(s.bank_deg) - float(first.bank_deg))))
		if max_roll >= TIP_ROLL_DPS or bank_change >= TIP_BANK_CHANGE_DEG:
			return _cause("tip_stall", "Tip stall", stall_text, factors)
		return _cause("stall", "Stall", stall_text, factors)
	if float(last.pitch_deg) <= DIVE_PITCH_DEG and float(last.airspeed) >= DIVE_SPEED_FACTOR * start_speed:
		return _cause("dive", "Steep high-speed dive into the ground", _state_text(last), factors)
	if absf(float(last.pitch_deg)) <= LEVEL_PITCH_DEG and absf(float(last.bank_deg)) <= LEVEL_BANK_DEG and float(last.vertical_speed) <= -HARD_SINK_MPS:
		return _cause("hard_landing", "Landed too hard", "sink %.1f m/s, %.1f m/s" % [-float(last.vertical_speed), float(last.airspeed)], factors)
	if absf(float(last.bank_deg)) >= STEEP_BANK_DEG:
		return _cause("steep_bank", "Steep bank too close to the ground", _state_text(last), factors)
	return _cause("flew_into_ground", "Flew into the ground", _state_text(last), factors)


## One crash-card / log line: "Tip stall at 4 m: α 17°, 8.2 m/s, bank 35° (throttle closed)".
static func line(cause: Dictionary) -> String:
	var text := "%s %s" % [str(cause.get("label", "Crash")), str(cause.get("detail", ""))]
	var factors: Array = cause.get("factors", [])
	if not factors.is_empty():
		text += " (%s)" % ", ".join(factors)
	return text.strip_edges()


## A sample from 64-bit telemetry (Telemetry.compute) and the body rates of `state`.
static func sample(t: float, telemetry: Dictionary, roll_rate_rad_s: float, yaw_rate_rad_s: float, engine_running: bool) -> Dictionary:
	return {t = t, airspeed = float(telemetry.airspeed), alpha_deg = float(telemetry.alpha_deg),
		pitch_deg = float(telemetry.pitch_deg), bank_deg = float(telemetry.bank_deg),
		roll_rate_dps = rad_to_deg(roll_rate_rad_s), yaw_rate_dps = rad_to_deg(yaw_rate_rad_s),
		height_agl = float(telemetry.height_agl), vertical_speed = float(telemetry.vertical_speed),
		throttle = float(telemetry.throttle), engine_running = engine_running}


static func _factors(last: Dictionary, start_speed: float) -> Array:
	var out: Array = []
	if last.is_empty():
		return out
	if float(last.get("throttle", 1.0)) < 0.05:
		out.append("throttle closed")
	if float(last.get("airspeed", start_speed)) < LOW_SPEED_FACTOR * start_speed:
		out.append("low airspeed")
	if absf(float(last.get("bank_deg", 0.0))) >= 45.0:
		out.append("steep bank")
	return out


static func _state_text(s: Dictionary) -> String:
	if s.is_empty():
		return ""
	return "at %.1f m/s, pitch %.0f°, bank %.0f°" % [float(s.get("airspeed", 0.0)), float(s.get("pitch_deg", 0.0)), float(s.get("bank_deg", 0.0))]


static func _cause(id: String, label: String, detail: String, factors: Array) -> Dictionary:
	return {id = id, label = label, detail = detail, factors = factors}


## True when every sample from `since` on satisfies `test` and that span really covers the window.
static func _all_within(samples: Array, since: float, test: Callable) -> bool:
	var span := samples.filter(func(s: Dictionary) -> bool: return float(s.t) >= since)
	if span.is_empty() or float(samples[0].t) > since + SAMPLE_INTERVAL_S:
		return false
	return span.all(test)


## Time covered by a run of samples (one sample counts as one interval).
static func _duration(samples: Array) -> float:
	return float(samples.size()) * SAMPLE_INTERVAL_S


static func _wrap(degrees: float) -> float:
	return fposmod(degrees + 180.0, 360.0) - 180.0
