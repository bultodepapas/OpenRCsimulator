# D6-TRIM-01: natural out-of-trim airframes. No built model flies straight with its controls at neutral: wing warps and
# panel incidence, stabiliser and fin offsets and linkage neutrals leave steady roll, pitch and yaw moments that the pilot
# trims out on the first flight. Each axis is drawn once per airframe as an equivalent trailing-edge angle. FlightSession
# adds it to the servo positions the aerodynamics read, so the trims, the servos and the start trim solver never contain
# it. Magnitudes and evidence: docs/research/radio-input/D6-TRIM-01/README.md.
extends RefCounted

const MODE_FIRST_FLIGHT := "first_flight"
const MODE_EVERY_FLIGHT := "every_flight"
const MODES: Array[String] = [MODE_FIRST_FLIGHT, MODE_EVERY_FLIGHT]
const CONFIG_KEYS: Array[String] = ["enabled", "intensity_percent", "mode"]
const DEFAULT_INTENSITY_PERCENT := 50

## Equivalent trailing-edge angle in degrees of the largest draw at 100 %: [roll (each aileron), pitch, yaw]. Chosen
## with research/flight-dynamics/out-of-trim/probe_out_of_trim.gd so the strongest airframe departs clearly but
## recoverably hands-off on every catalog airplane (pitch 1.2° dived several into the ground within 8 s).
const FULL_SCALE_DEG: Array[float] = [0.6, 0.8, 1.2]
## The smallest draw as a fraction of the full scale, so 100 % always needs some trim on every axis.
const MIN_FRACTION := 0.25
## Largest offset a checkpoint may restore, in maximum-throw units; anything larger is not a rigging error.
const MAX_OFFSET := 0.25


static func defaults() -> Dictionary:
	return {"enabled": false, "intensity_percent": DEFAULT_INTENSITY_PERCENT, "mode": MODE_FIRST_FLIGHT}


## Validate the exact player-facing configuration. Values are never coerced.
static func validate(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("out-of-trim config must be an object")
		return {"ok": false, "config": {}, "errors": errors}
	var source: Dictionary = raw
	for key: String in CONFIG_KEYS:
		if not source.has(key):
			errors.append("out-of-trim config is missing '%s'" % key)
	for key: Variant in source.keys():
		if not CONFIG_KEYS.has(str(key)):
			errors.append("out-of-trim config has unknown key '%s'" % str(key))
	if not errors.is_empty():
		return {"ok": false, "config": {}, "errors": errors}
	if typeof(source.enabled) != TYPE_BOOL:
		errors.append("out-of-trim config enabled must be a boolean")
	var intensity: Variant = source.intensity_percent
	if typeof(intensity) != TYPE_INT:
		errors.append("out-of-trim config intensity_percent must be an integer")
	elif intensity < 0 or intensity > 100:
		errors.append("out-of-trim config intensity_percent must be between 0 and 100")
	if typeof(source.mode) != TYPE_STRING or not MODES.has(source.mode):
		errors.append("out-of-trim config mode must be first_flight or every_flight")
	if not errors.is_empty():
		return {"ok": false, "config": {}, "errors": errors}
	return {
		"ok": true,
		"config": {"enabled": bool(source.enabled), "intensity_percent": int(intensity), "mode": str(source.mode)},
		"errors": errors,
	}


## One airframe: per axis a signed fraction of the full scale, |x| in [MIN_FRACTION, 1] and most often near the middle
## (the mean of two uniform draws), either sign equally. The same seed and index always give the same airframe.
static func draw(seed_value: int, airframe_index: int) -> PackedFloat64Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 65537 + airframe_index
	var unit := PackedFloat64Array()
	for axis in 3:
		var magnitude: float = MIN_FRACTION + (1.0 - MIN_FRACTION) * 0.5 * (rng.randf() + rng.randf())
		unit.append(magnitude if rng.randf() < 0.5 else -magnitude)
	return unit


## Offsets [roll, pitch, yaw] in maximum-throw units (the trims' units) of one airframe on an aircraft with these throws.
## An axis without its own surface (no rudder; elevons have no yaw) gets none, because the pilot could not trim it.
static func offsets(unit: PackedFloat64Array, intensity_percent: int, throw_deg: Dictionary) -> PackedFloat64Array:
	var out := PackedFloat64Array([0.0, 0.0, 0.0])
	if unit.size() != 3:
		return out
	var throws: Array[float] = [float(throw_deg.get("aileron", 0.0)), float(throw_deg.get("elevator", 0.0)),
		0.0 if throw_deg.has("elevon") else float(throw_deg.get("rudder", 0.0))]
	var scale: float = clampi(intensity_percent, 0, 100) / 100.0
	for axis in 3:
		if throws[axis] > 0.0:
			# Bounded like a restored checkpoint, so an aircraft with tiny throws stays replayable.
			out[axis] = clampf(unit[axis] * scale * FULL_SCALE_DEG[axis] / throws[axis], -MAX_OFFSET, MAX_OFFSET)
	return out


## True for offsets a flight can carry: three finite values within MAX_OFFSET, not all zero.
static func valid_offsets(values: Variant) -> bool:
	if not values is PackedFloat64Array or values.size() != 3:
		return false
	var any := false
	for value: float in values:
		if not is_finite(value) or absf(value) > MAX_OFFSET:
			return false
		any = any or value != 0.0
	return any


static func is_zero(values: PackedFloat64Array) -> bool:
	return values.size() == 3 and values[0] == 0.0 and values[1] == 0.0 and values[2] == 0.0


## The first-flight-only record kept for one airframe ({unit, intensity_percent, pilot_trim}), or {} when it is malformed
## or belongs to another intensity: a changed intensity rigs a new airframe.
static func carried_record(raw: Variant, config: Dictionary) -> Dictionary:
	if not raw is Dictionary or raw.get("intensity_percent") != config.get("intensity_percent"):
		return {}
	var unit: Variant = raw.get("unit")
	var pilot_trim: Variant = raw.get("pilot_trim")
	if not unit is PackedFloat64Array or unit.size() != 3 or not pilot_trim is PackedFloat64Array or pilot_trim.size() != 3:
		return {}
	for axis in 3:
		if not is_finite(unit[axis]) or absf(unit[axis]) > 1.0 or not is_finite(pilot_trim[axis]) or absf(pilot_trim[axis]) > 2.0:
			return {}
	return {unit = unit.duplicate(), intensity_percent = int(raw.intensity_percent), pilot_trim = pilot_trim.duplicate()}
