## NITRO-06: the glow carburettor as a flow restriction. 64-bit floats only.
##
## The transmitter throttle positions a barrel; the open area admits air through a nozzle. At a small opening the
## nozzle chokes, so the air mass flow is fixed by the opening alone and the charge per cycle falls as 1/rpm; at a
## large opening the engine's own breathing sets the flow and the manifold pressure stays near ambient. The mean
## cycle kernels (two_stroke.gd, four_stroke.gd) take `admission`, the charge per cycle relative to the wide-open
## throttle at the same rpm, and this module supplies it from the opening and the engine speed.
##
## Nozzle flow (Heywood, Internal Combustion Engine Fundamentals, 1988, §7.6.2, eqs. 7.26–7.28): with upstream
## stagnation p0, T0 and downstream (manifold) pressure p_m, r = p_m/p0,
##   ṁ = Cd·A·p0/√(R·T0) · Ψ(r),  Ψ(r) = r^(1/γ)·√(2γ/(γ−1)·(1 − r^((γ−1)/γ))) for r > r_c,  Ψ = Ψ_c for r ≤ r_c,
##   r_c = (2/(γ+1))^(γ/(γ−1)) = 0.5283,  Ψ_c = √γ·(2/(γ+1))^((γ+1)/(2(γ−1))) = 0.6847 (γ = 1.4).
## Engine demand (isothermal manifold, density r·ρ0): ṁ = r·ρ0·V_d·η_b(n)·n/(60·revs_per_cycle). With the choked
## volumetric capacity Q_c = Cd·A·Ψ_c·√(R·T0) of the fully open path and the demand Q_e = V_d·η_b·n/(60·revs), the
## balance is r·x = a·g(r), x = Q_e/Q_c, a = A/A_open, g = Ψ/Ψ_c. Its root depends only on y = a/x: r = y when
## y ≤ r_c (choked), else the unique root of r = y·g(r) in (r_c, 1).
## Admission = r(a, n)/r(1, n): the kernels' delivery ratio / volumetric efficiency already describe wide-open
## breathing through this carburettor, so the fully open throttle admits exactly 1 at every speed.
## Barrel geometry: the hole slides across the bore; the open area is the lens common to two equal circles whose
## centres are offset by d, a(u) = (2/π)(acos u − u√(1−u²)) with u = d/(2R), from the idle stop (u_idle, where the
## lens equals the idle opening) to u = 0 at full throttle along u = u_idle·(1 − servo)^p. The travel exponent p
## stands for the barrel kinematics and linkage that no drawing gives: p = 1 is a hole sliding linearly with the
## servo; p < 1 keeps the barrel more closed through mid travel. The installation calibrates p to the measured
## half-barrel operating point of an O.S. barrel carburettor (NITRO-06 evidence).
## Temperature enters only through √(R·T0) at the ISA reference; density cancels from the ratio.
extends RefCounted

const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/math3d.gd")

const GAMMA := 1.4
const R_AIR := 287.05
const T_REFERENCE_K := 288.15
## (2/(γ+1))^(γ/(γ−1)) and √γ·(2/(γ+1))^((γ+1)/(2(γ−1))) for γ = 1.4.
const CRITICAL_RATIO := 0.5282817877171742
const PSI_CHOKED := 0.6847314563772704
const ROOT_ITERATIONS := 64
const ROOT_TOLERANCE := 1.0e-15
const LENS_ITERATIONS := 64


## Normalised nozzle flow function g(r) = Ψ(r)/Ψ_c: 1 when choked (r ≤ r_c), 0 at r = 1, decreasing between.
static func flow_function(r: float) -> float:
	if not is_finite(r) or r <= CRITICAL_RATIO:
		return 1.0
	if r >= 1.0:
		return 0.0
	var k: float = (GAMMA - 1.0) / GAMMA
	var inner: float = 2.0 * GAMMA / (GAMMA - 1.0) * (1.0 - M.pow_(r, k))
	return M.pow_(r, 1.0 / GAMMA) * M.sqrt_(maxf(inner, 0.0)) / PSI_CHOKED


## Manifold pressure ratio r for the demand/capacity ratio y = a/x: y below r_c (choked), else the root of
## r = y·g(r) in (r_c, 1). Monotone in y; 1 as y → ∞. NAN for a nonfinite or negative y.
static func charge_ratio(y: float) -> float:
	if not is_finite(y) or y < 0.0:
		return NAN
	if y <= CRITICAL_RATIO:
		return y
	# h(r) = r − y·g(r) rises from r_c − y < 0 to 1 at r = 1 (g falls monotonically). Newton on the bracket,
	# with a bisection step whenever the Newton step leaves it; a few iterations per RK stage.
	var lo: float = CRITICAL_RATIO
	var hi: float = 1.0
	var r: float = 0.5 * (lo + hi)
	for _i in ROOT_ITERATIONS:
		var h: float = r - y * flow_function(r)
		if h > 0.0:
			hi = r
		else:
			lo = r
		if absf(h) <= ROOT_TOLERANCE or hi - lo <= ROOT_TOLERANCE:
			break
		var slope: float = 1.0 - y * _flow_function_slope(r)
		var next: float = r - h / slope if slope > 0.0 and is_finite(slope) else NAN
		if not is_finite(next) or next <= lo or next >= hi:
			next = 0.5 * (lo + hi)
		r = next
	return r


## dg/dr of the normalised nozzle flow for r_c < r < 1 (negative; unbounded as r → 1).
static func _flow_function_slope(r: float) -> float:
	var k: float = (GAMMA - 1.0) / GAMMA
	var c: float = 2.0 * GAMMA / (GAMMA - 1.0)
	var s: float = M.sqrt_(maxf(c * (1.0 - M.pow_(r, k)), 0.0))
	if s <= 0.0:
		return -INF
	return (M.pow_(r, 1.0 / GAMMA - 1.0) * s / GAMMA - M.pow_(r, 1.0 / GAMMA) * c * k * M.pow_(r, k - 1.0) / (2.0 * s)) / PSI_CHOKED


## Open-area fraction of the barrel: the lens common to two equal circles offset by u = d/(2R), u in [0, 1].
static func lens_fraction(u: float) -> float:
	if not is_finite(u):
		return NAN
	if u <= 0.0:
		return 1.0
	if u >= 1.0:
		return 0.0
	return 2.0 / PI * (M.acos_(u) - u * M.sqrt_(1.0 - u * u))


## Barrel offset u_idle at which the lens equals the idle opening (0 < idle_opening < 1). NAN outside that range.
static func idle_offset(idle_opening: float) -> float:
	if not is_finite(idle_opening) or idle_opening <= 0.0 or idle_opening >= 1.0:
		return NAN
	var lo: float = 0.0
	var hi: float = 1.0
	for _i in LENS_ITERATIONS:
		var mid: float = 0.5 * (lo + hi)
		if lens_fraction(mid) > idle_opening:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


## Open-area fraction for a servo (throttle) fraction in [0, 1]: the barrel moves from the idle stop to fully open
## along u = u_idle·(1 − servo)^travel_exponent.
static func opening(servo: float, idle_offset_u: float, travel_exponent: float = 1.0) -> float:
	if not is_finite(servo) or not is_finite(idle_offset_u) or idle_offset_u < 0.0 or idle_offset_u > 1.0 \
			or not is_finite(travel_exponent) or travel_exponent <= 0.0:
		return NAN
	var closed: float = 1.0 - clampf(servo, 0.0, 1.0)
	return lens_fraction(idle_offset_u * (M.pow_(closed, travel_exponent) if closed > 0.0 else 0.0))


## Choked volumetric capacity (m³/s of ambient-density air) of the fully open path with effective area Cd·A (m²).
static func capacity_m3_s(effective_area_m2: float) -> float:
	if not is_finite(effective_area_m2) or effective_area_m2 <= 0.0:
		return NAN
	return effective_area_m2 * PSI_CHOKED * M.sqrt_(R_AIR * T_REFERENCE_K)


## Wide-open volumetric demand (m³/s at ambient density) of an engine breathing η_b of its displacement per cycle.
static func demand_m3_s(rpm: float, breathing: float, displacement_m3: float, cycle_revolutions: float) -> float:
	if not is_finite(rpm) or not is_finite(breathing) or not is_finite(displacement_m3) or not is_finite(cycle_revolutions) \
			or rpm < 0.0 or breathing < 0.0 or displacement_m3 <= 0.0 or cycle_revolutions <= 0.0:
		return NAN
	return displacement_m3 * breathing * rpm / (60.0 * cycle_revolutions)


## Charge per cycle relative to the wide-open throttle at the same speed, for an open-area fraction a in (0, 1].
## 1 at rest or without breathing (no flow, no restriction). NAN for invalid inputs.
static func admission(open_fraction: float, rpm: float, breathing: float, displacement_m3: float,
		cycle_revolutions: float, capacity: float) -> float:
	if not is_finite(open_fraction) or open_fraction <= 0.0 or open_fraction > 1.0 or not is_finite(capacity) or capacity <= 0.0:
		return NAN
	var demand: float = demand_m3_s(rpm, breathing, displacement_m3, cycle_revolutions)
	if not is_finite(demand):
		return NAN
	if demand <= 0.0:
		return 1.0
	var x: float = demand / capacity
	var restricted: float = charge_ratio(open_fraction / x)
	var wide_open: float = charge_ratio(1.0 / x)
	if not is_finite(restricted) or not is_finite(wide_open) or wide_open <= 0.0:
		return NAN
	return minf(restricted / wide_open, 1.0)
