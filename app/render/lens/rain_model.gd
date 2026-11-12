## LENS-08 (docs/plans/lens-screen-effects.md §2.3, §6.3): the rain drivers of the lens effects, float64 and
## engine-free so tests can hold them. Presentation only: no aerodynamic, electrical or friction effect of rain.
##
## Drop sizes follow Marshall & Palmer (1948): N(D) = N0·exp(−Λ·D), N0 = 8000 m⁻³ mm⁻¹, Λ = 4.1·R^−0.21 mm⁻¹ with R in
## mm/h. Fall speed is the Atlas–Ulbrich power law v(D) ≈ 3.78·D^0.67 m/s (D in mm). Arrivals on a lens are the drops
## swept by the lens area moving through the rain, times an explicit art gain per view (a documented estimate, not
## measured lens physics). Exact flux integrates N(D)·v_rel(D); this uses the number density and the mean fall speed.
extends RefCounted

const N0_PER_M3_MM := 8000.0
const SLOPE_COEFFICIENT := 4.1
const SLOPE_EXPONENT := -0.21
const FALL_COEFFICIENT := 3.78
const FALL_EXPONENT := 0.67
const GAMMA_1_67 := 0.903296 # Γ(1 + FALL_EXPONENT): mean of D^0.67 under the exponential.
const MIN_DIAMETER_MM := 0.5
const MAX_DIAMETER_MM := 4.0
## Front glass of a small FPV/action camera (≈ 12 mm across): the swept area.
const LENS_AREA_M2 := 1.13e-4
## A share of the fall speed that still reaches a lens facing sideways at rest (splash, eddies, gusts).
const REST_DEPOSITION := 0.35
const BURST_PERIOD_S := 28.0

## Interim LENS-owned mapping until the Field World precipitation channel (LENS-06) lands: local rain rate (mm/h) per
## sky preset. Distant storms stay dry at the field; the electrical storm rains on it.
const PRESET_RATE_MMPH := {
	"classic": 0.0, "clear": 0.0, "cirrus": 0.0, "fair_cumulus": 0.0, "broken": 0.0, "overcast": 0.0,
	"prestorm": 1.6, "distant_storm": 0.0, "electrical_storm": 14.0, "tornado_challenge": 28.0,
}


static func rate_for_preset(preset: String) -> float:
	return float(PRESET_RATE_MMPH.get(preset, 0.0))


## Λ in mm⁻¹ (zero rain has no distribution: returns INF).
static func slope_per_mm(rate_mmph: float) -> float:
	if not (rate_mmph > 0.0) or not is_finite(rate_mmph):
		return INF
	return SLOPE_COEFFICIENT * pow(rate_mmph, SLOPE_EXPONENT)


## Drops per cubic metre of air.
static func number_density(rate_mmph: float) -> float:
	var slope := slope_per_mm(rate_mmph)
	return 0.0 if is_inf(slope) else N0_PER_M3_MM / slope


static func fall_speed(diameter_mm: float) -> float:
	return FALL_COEFFICIENT * pow(maxf(diameter_mm, 0.0), FALL_EXPONENT)


## Number-weighted mean fall speed (m/s): ∫N·v dD / ∫N dD.
static func mean_fall_speed(rate_mmph: float) -> float:
	var slope := slope_per_mm(rate_mmph)
	if is_inf(slope):
		return 0.0
	return FALL_COEFFICIENT * GAMMA_1_67 / pow(slope, FALL_EXPONENT)


## Drops per second reaching a lens. `closing_speed_mps` is the rain's speed toward the lens face along its normal
## (−u·n̂, u = v_rain − v_camera); negative values mean the lens faces away from the rain.
static func arrival_rate(rate_mmph: float, closing_speed_mps: float, gain: float, area_m2: float = LENS_AREA_M2) -> float:
	var density := number_density(rate_mmph)
	if density <= 0.0 or not is_finite(closing_speed_mps) or not (gain > 0.0):
		return 0.0
	var flux_speed := maxf(closing_speed_mps, 0.0) + REST_DEPOSITION * mean_fall_speed(rate_mmph)
	return gain * area_m2 * density * flux_speed


## A diameter (mm) drawn from the exponential distribution truncated to [MIN, MAX]; `u` is uniform in [0, 1).
static func sample_diameter(rate_mmph: float, u: float) -> float:
	var slope := slope_per_mm(rate_mmph)
	if is_inf(slope):
		return MIN_DIAMETER_MM
	var low := exp(-slope * MIN_DIAMETER_MM)
	var high := exp(-slope * MAX_DIAMETER_MM)
	var x := low - clampf(u, 0.0, 0.999999) * (low - high)
	return clampf(-log(x) / slope, MIN_DIAMETER_MM, MAX_DIAMETER_MM)


## Rain is bursty: a smooth seeded modulation (0.45…1.55) of the nominal rate over tens of seconds of visual time.
static func burst(clock_s: float, stream: int) -> float:
	var x := clock_s / BURST_PERIOD_S + float(posmod(stream, 997)) * 0.37
	var i := floorf(x)
	var f := x - i
	var a := _hash01(int(i), stream)
	var b := _hash01(int(i) + 1, stream)
	var s := f * f * (3.0 - 2.0 * f)
	return 0.45 + 1.1 * lerpf(a, b, s)


static func _hash01(n: int, stream: int) -> float:
	var h := (n * 374761393 + stream * 668265263) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return float(h & 0xFFFF) / 65535.0
