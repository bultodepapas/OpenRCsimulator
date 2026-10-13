# Flight overlay units (HUD-01, docs/plans/flight-overlays.md §4). SI in, display value and unit label out.
# Exact definitions: 1 mph = 0.44704 m/s and 1 ft = 0.3048 m (international yard and pound, 1959).
extends RefCounted

const SYSTEMS := ["auto", "metric", "imperial", "si"]
const KMH_PER_MPS := 3.6
const MPS_PER_MPH := 0.44704
const M_PER_FT := 0.3048


## "auto" follows the interface language (D3): English reads imperial, every other language metric.
static func resolve(system: String, language: String) -> String:
	if system == "auto" or not SYSTEMS.has(system):
		return "imperial" if language == "en" else "metric"
	return system


## [value, unit] for a speed in m/s.
static func speed(mps: float, system: String) -> Array:
	match system:
		"imperial":
			return [mps / MPS_PER_MPH, "mph"]
		"si":
			return [mps, "m/s"]
	return [mps * KMH_PER_MPS, "km/h"]


## [value, unit] for a height or distance in m.
static func length(m: float, system: String) -> Array:
	if system == "imperial":
		return [m / M_PER_FT, "ft"]
	return [m, "m"]


## [value, unit] for a vertical speed in m/s (positive up). Imperial pilots read feet per minute.
static func vertical(mps: float, system: String) -> Array:
	if system == "imperial":
		return [mps / M_PER_FT * 60.0, "ft/min"]
	return [mps, "m/s"]


## Display text: whole numbers except slow SI/metric vertical speeds and short distances, which need one decimal.
static func format(pair: Array, signed := false) -> String:
	var value: float = pair[0]
	var unit: String = pair[1]
	if not is_finite(value):
		return "– " + unit # e.g. a terrain table that fails closed: unknown, never a made-up number
	var decimals := 1 if unit == "m/s" or (unit == "m" and absf(value) < 10.0) else 0
	var step := 10.0 if unit == "ft/min" else (0.1 if decimals == 1 else 1.0) # ft/min: a VSI's resolution
	var rounded := snappedf(value, step)
	var text := String.num(absf(rounded), decimals)
	if decimals > 0:
		text = text.pad_decimals(decimals)
	var sign := "-" if rounded < 0.0 else ("+" if signed and rounded > 0.0 else "")
	return "%s%s %s" % [sign, text, unit]
