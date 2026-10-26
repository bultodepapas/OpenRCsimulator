# BAT-11: sampled ESC battery supervisor (cell detection and low-voltage cutoff).
# Pure, float64 and deterministic. The session calls step() once per accepted endpoint and holds the
# returned output limit for the next tick (zero-order hold, docs/research/battery/BAT-04/specification.md §6).
# Startup ramp, brake, freewheel and signal loss belong to the ESC power stage (EL3), not to this module.
extends RefCounted

const PHASE_NORMAL: int = 0
const PHASE_DEBOUNCE: int = 1
const PHASE_SOFT_CUT: int = 2
const PHASE_HARD_CUT: int = 3
const MODES: Array[String] = ["soft", "hard", "off"]
const DETECTIONS: Array[String] = ["auto", "fixed"]
const RECOVERIES: Array[String] = ["throttle_reset", "latched"]
const MIN_FILTER_S: float = 0.02
## Sample timers accumulate dt; a 1 ns tolerance keeps "after 0.5 s" at sample 120 of 1/240 s despite rounding.
const TIME_TOL_S: float = 1e-9
const MAX_CELLS: int = 24


## Validate a normalized profile (plain floats, already unit-checked by the loader).
static func validate(profile: Variant) -> String:
	if not profile is Dictionary:
		return "low_voltage_cutoff must be a dictionary"
	var p: Dictionary = profile
	if p.get("mode") not in MODES:
		return "low_voltage_cutoff.mode must be soft, hard or off"
	if p.get("cell_detection") not in DETECTIONS:
		return "low_voltage_cutoff.cell_detection must be auto or fixed"
	if p.get("recovery") not in RECOVERIES:
		return "low_voltage_cutoff.recovery must be throttle_reset or latched"
	if p.cell_detection == "fixed":
		if typeof(p.get("fixed_cells")) != TYPE_INT or int(p.fixed_cells) < 1 or int(p.fixed_cells) > MAX_CELLS:
			return "low_voltage_cutoff.fixed_cells must be an integer in [1, %d]" % MAX_CELLS
	elif not _positive(p.get("detection_max_cell_v")):
		return "low_voltage_cutoff.detection_max_cell_v must be finite and > 0"
	for key: String in ["cutoff_per_cell_v", "soft_ramp_s", "voltage_filter_s"]:
		if not _positive(p.get(key)):
			return "low_voltage_cutoff.%s must be finite and > 0" % key
	if float(p.voltage_filter_s) < MIN_FILTER_S:
		return "low_voltage_cutoff.voltage_filter_s must be >= %.2f s" % MIN_FILTER_S
	if not _finite(p.get("debounce_s")) or float(p.debounce_s) < 0.0:
		return "low_voltage_cutoff.debounce_s must be finite and >= 0"
	if not _finite(p.get("soft_limit")) or float(p.soft_limit) < 0.0 or float(p.soft_limit) >= 1.0:
		return "low_voltage_cutoff.soft_limit must be in [0, 1)"
	if not _finite(p.get("reset_throttle_max")) or float(p.reset_throttle_max) < 0.0 or float(p.reset_throttle_max) > 0.2:
		return "low_voltage_cutoff.reset_throttle_max must be in [0, 0.2]"
	return ""


## Cells counted once at connection. A deeply discharged pack can be misdetected; that is modeled behaviour.
static func detect_cells(profile: Dictionary, rest_voltage_v: float) -> int:
	if profile.cell_detection == "fixed":
		return int(profile.fixed_cells)
	if not is_finite(rest_voltage_v) or rest_voltage_v <= 0.0:
		return 1
	var count: int = int(ceil(rest_voltage_v / float(profile.detection_max_cell_v) - 1e-9))
	return clampi(count, 1, MAX_CELLS)


static func cutoff_voltage(profile: Dictionary, cells: int) -> float:
	return float(cells) * float(profile.cutoff_per_cell_v)


## One sampled decision. Returns [limit, phase, timer_s]; the limit applies to the next tick.
static func step(profile: Dictionary, limit: float, phase: int, timer_s: float, cells: int,
		sensed_voltage_v: float, throttle: float, dt: float) -> PackedFloat64Array:
	if profile.mode == "off":
		return PackedFloat64Array([1.0, float(PHASE_NORMAL), 0.0])
	var threshold: float = cutoff_voltage(profile, cells)
	var below: bool = sensed_voltage_v < threshold
	var next_phase: int = phase
	var timer: float = timer_s
	var out_limit: float = limit
	if phase == PHASE_SOFT_CUT or phase == PHASE_HARD_CUT:
		if profile.recovery == "throttle_reset" and throttle <= float(profile.reset_throttle_max) and not below:
			return PackedFloat64Array([1.0, float(PHASE_NORMAL), 0.0])
		if phase == PHASE_HARD_CUT:
			return PackedFloat64Array([0.0, float(PHASE_HARD_CUT), timer])
		timer += dt
		var soft_limit: float = float(profile.soft_limit)
		var ramp: float = 1.0 if timer >= float(profile.soft_ramp_s) - TIME_TOL_S else timer / float(profile.soft_ramp_s)
		out_limit = maxf(soft_limit, 1.0 - (1.0 - soft_limit) * ramp)
		return PackedFloat64Array([out_limit, float(PHASE_SOFT_CUT), timer])
	if not below:
		return PackedFloat64Array([1.0, float(PHASE_NORMAL), 0.0])
	timer = dt if phase == PHASE_NORMAL else timer + dt
	next_phase = PHASE_DEBOUNCE
	if timer >= float(profile.debounce_s) - TIME_TOL_S:
		if profile.mode == "hard":
			return PackedFloat64Array([0.0, float(PHASE_HARD_CUT), 0.0])
		return PackedFloat64Array([1.0, float(PHASE_SOFT_CUT), 0.0])
	return PackedFloat64Array([1.0, float(next_phase), timer])


static func state_name(profile: Dictionary, phase: int) -> String:
	if profile.get("mode") == "off":
		return "off"
	match phase:
		PHASE_DEBOUNCE:
			return "debounce"
		PHASE_SOFT_CUT:
			return "soft_cut"
		PHASE_HARD_CUT:
			return "hard_cut"
	return "normal"


static func _finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _positive(value: Variant) -> bool:
	return _finite(value) and float(value) > 0.0
