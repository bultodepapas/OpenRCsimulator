# M5-GE-1: wing-in-ground-effect correction, an opt-in v2 aircraft module (aero.ground_effect).
# The ground's image vortex system reduces the wing's induced downwash. One factor σ(h/b) = c·x^e / (1 + c·x^e),
# x = strip height / span, scales each wing strip's induced angle and its induced drag (Raymer's 33·x^1.5 fit of
# Wieselsberger's image theory; McCormick and Torenbeek forms are weaker; Phillips & Hunsaker 2013 show the ratio
# also depends on planform and CL, so c and e are aircraft data with their own provenance). A second factor
# σ_ε(h̄/b) of the same form scales the wing's downwash at the horizontal tail (nose-down trim change in the flare).
# Both fade smoothly (C¹) to exactly 1 at FADE_SPAN_RATIO spans, so an aircraft above that height takes the
# byte-identical legacy path. Separated flow is untouched: the strip law applies σ to attached lift only.
# Float64 only. Evidence and sources: docs/research/ground-effect/M5-GE-1/README.md.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

## Above this height-to-span ratio every factor is exactly 1 (numerical cutoff, not an aircraft parameter).
const FADE_SPAN_RATIO := 2.0


## True when the derived model carries the module (AircraftData stores it in envelope.ground_effect).
static func enabled(model: Dictionary) -> bool:
	return model.get("envelope", {}).has("ground_effect")


## σ(x) for x = h/b ≥ 0: c·x^e/(1 + c·x^e), faded to exactly 1.0 at FADE_SPAN_RATIO with a C¹ smoothstep.
## σ → 0 as x → 0 (full cancellation of the induced angle), σ(FADE_SPAN_RATIO) = 1 exactly.
static func law(x: float, coefficient: float, exponent: float) -> float:
	if x >= FADE_SPAN_RATIO:
		return 1.0
	var clamped := maxf(x, 0.0)
	var t := coefficient * M.pow_(clamped, exponent)
	var sigma := t / (1.0 + t)
	var u := clamped / FADE_SPAN_RATIO
	var keep := 1.0 - u * u * (3.0 - 2.0 * u) # 1 at the ground, 0 at the fade height
	return 1.0 - (1.0 - sigma) * keep


## Per-evaluation factors for state s with the ground `ground_up` metres above the NED datum under the CG:
## [σ_strip_1 … σ_strip_n (envelope.station_ys order), σ_mean, σ_tail]. Strip heights are the aero reference
## point's height at each station (the strips' force application point), so bank lowers one wing's strips.
## σ_tail uses the strips' mean height ratio (the wing wake's height), as the research table is parametrised.
## Returns an EMPTY array when the module is absent, ground_up is NAN or every strip is above the fade height:
## callers then take their unchanged legacy path.
static func factors(s: PackedFloat64Array, model: Dictionary, ground_up: float) -> PackedFloat64Array:
	if is_nan(ground_up) or not enabled(model):
		return PackedFloat64Array()
	var env: Dictionary = model.envelope
	var ge: Dictionary = env.ground_effect
	var ys: PackedFloat64Array = env.station_ys
	var n := ys.size()
	var b: float = model.reference.b
	var arp: PackedFloat64Array = model.reference.arp_le
	var cg: PackedFloat64Array = model.cg_le
	var ax: float = -(arp[0] - cg[0])
	var ay: float = arp[1] - cg[1]
	var az: float = -(arp[2] - cg[2])
	# Third row of the body→NED rotation: the NED down component of a body vector v is d0·v0 + d1·v1 + d2·v2.
	var qw := s[RB.ATT]
	var qx := s[RB.ATT + 1]
	var qy := s[RB.ATT + 2]
	var qz := s[RB.ATT + 3]
	var d0 := 2.0 * (qx * qz - qw * qy)
	var d1 := 2.0 * (qy * qz + qw * qx)
	var d2 := 1.0 - 2.0 * (qx * qx + qy * qy)
	var c_i: float = ge.induced_coefficient
	var e_i: float = ge.induced_exponent
	var out := PackedFloat64Array()
	out.resize(n + 2)
	var sum := 0.0
	var x_sum := 0.0
	var active := false
	for i in n:
		var height := -(s[RB.POS + 2] + d0 * ax + d1 * (ay + ys[i]) + d2 * az) - ground_up
		var x := maxf(height, 0.0) / b
		var f := law(x, c_i, e_i)
		out[i] = f
		sum += f
		x_sum += x
		if f != 1.0:
			active = true
	if not active:
		return PackedFloat64Array()
	out[n] = sum / n
	out[n + 1] = law(x_sum / n, ge.downwash_coefficient, ge.downwash_exponent)
	return out


## CG height above the local ground beyond which factors() is always empty: the fade height plus the farthest
## strip's distance from the CG. Sessions skip the terrain sample above reach() + the terrain's height bound.
static func reach(model: Dictionary) -> float:
	if not enabled(model):
		return 0.0
	var b: float = model.reference.b
	var arp: PackedFloat64Array = model.reference.arp_le
	var cg: PackedFloat64Array = model.cg_le
	var ax: float = arp[0] - cg[0]
	var ay: float = absf(arp[1] - cg[1]) + 0.5 * b
	var az: float = arp[2] - cg[2]
	return FADE_SPAN_RATIO * b + M.sqrt_(ax * ax + ay * ay + az * az)
