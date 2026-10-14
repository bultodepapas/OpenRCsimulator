# NITRO-05: fuel feed pressure at the carburetor of a glow installation (optional `fuel_feed` installation block).
# A glow carburetor meters premix through its needle by the pressure difference that drives fuel to the spray bar:
# the carburetor's own suction plus the tank pressurization (muffler or crankcase), plus the hydrostatic head of the
# fuel column between the tank's free surface and the spray bar. That head follows the apparent gravity the fuel
# feels, g_eff = −(non-gravitational force)/mass: gravity itself accelerates fuel and airframe alike. A steady
# up-line (thrust minus drag holding the airplane against gravity) or a full-throttle acceleration sends it aft,
# so the carburetor ahead of the tank must lift fuel; a dive that drag is slowing sends it forward and richens; a
# hard pull with a low tank sinks the surface away from a carburetor above it; an emptying tank lowers the surface. Orifice flow scales with the square root of the driving pressure; the engine was needled in
# level 1 g flight with a full tank, so the delivered flow is the needled flow times
#   k = sqrt((p_drive + Δp_head) / (p_drive + Δp_head,needled)),   0 ≤ k ≤ MAX_FACTOR.
# The driving pressure rises with the admitted flow squared from an idle floor to its full-throttle value:
#   p_drive = p_idle + (p_wot − p_idle)·(admission·rpm/rated_rpm)²   (capped at p_wot).
# The free surface of a box tank lies perpendicular to g_eff at a depth set by the fill fraction (exact for a
# surface parallel to a tank face, an estimate otherwise). Rotational (centripetal) terms at the tank, slosh, clunk
# blockage and fuel-line inertia beyond the existing transport lag are not modelled.
# Pure functions of float64 body-frame (FRD) arrays; transcendental calls go through math3d.
extends RefCounted

const M := preload("res://physics/math3d.gd")

## Flooding bound: a carburetor cannot pass more than twice its needled flow through the same needle setting.
const MAX_FACTOR := 2.0
## Below this apparent gravity (m/s²) the fuel has no defined free surface; the head is taken as zero.
const MIN_G := 1e-6


## Hydrostatic pressure (Pa) at the carburetor relative to the tank's free surface, for apparent gravity `g_eff`
## (body FRD, m/s²), tank `fill` 0..1, carburetor and tank centre positions and tank size (m), premix density.
static func head_pa(g_eff: PackedFloat64Array, fill: float, carburetor: PackedFloat64Array,
		tank_center: PackedFloat64Array, tank_size: PackedFloat64Array, density: float) -> float:
	var g := M.norm(g_eff)
	if g < MIN_G:
		return 0.0
	var down := M.scale(g_eff, 1.0 / g)
	# Depth of the box along `down`, and the surface level along `down` (points beyond it are submerged).
	var depth := absf(down[0]) * tank_size[0] + absf(down[1]) * tank_size[1] + absf(down[2]) * tank_size[2]
	var surface := M.dot(down, tank_center) + (0.5 - clampf(fill, 0.0, 1.0)) * depth
	return density * g * (M.dot(down, carburetor) - surface)


## Driving pressure (Pa) of the carburetor and tank pressurization at a throttle admission and rpm.
static func drive_pa(admission: float, rpm: float, feed: Dictionary) -> float:
	var flow_share := clampf(admission, 0.0, 1.0) * maxf(0.0, rpm) / float(feed.rated_rpm)
	var idle: float = feed.idle_drive_pressure_pa
	var wot: float = feed.wot_drive_pressure_pa
	return minf(wot, idle + (wot - idle) * flow_share * flow_share)


## Delivered-flow multiplier k for a driving pressure and head, against the needled head.
static func factor(drive: float, head: float, needled_head: float) -> float:
	var needled := drive + needled_head
	if needled <= 0.0:
		return 0.0
	return clampf(M.sqrt_(maxf(0.0, drive + head) / needled), 0.0, MAX_FACTOR)


## The needled condition: level 1 g flight (g_eff straight down the body z axis) with a full tank.
static func needled_head_pa(feed: Dictionary, tank_center: PackedFloat64Array, tank_size: PackedFloat64Array,
		gravity: float) -> float:
	return head_pa(PackedFloat64Array([0.0, 0.0, gravity]), 1.0, feed.carburetor_body_m, tank_center, tank_size,
		float(feed.density_kg_m3))


## Everything at once for a stage: apparent gravity from the non-gravitational body force and the instantaneous
## mass, the head at the current fill, the driving pressure and k against the needled head at the simulation's
## `gravity`. Returns {factor, head_pa, needled_head_pa, drive_pa, g_eff}.
static func evaluate(feed: Dictionary, force_body: PackedFloat64Array, mass_kg: float, fill: float,
		admission: float, rpm: float, tank_center: PackedFloat64Array, tank_size: PackedFloat64Array,
		gravity: float) -> Dictionary:
	var g_eff := M.scale(force_body, -1.0 / mass_kg)
	var head := head_pa(g_eff, fill, feed.carburetor_body_m, tank_center, tank_size, float(feed.density_kg_m3))
	var needled := needled_head_pa(feed, tank_center, tank_size, gravity)
	var drive := drive_pa(admission, rpm, feed)
	return {factor = factor(drive, head, needled), head_pa = head, needled_head_pa = needled, drive_pa = drive, g_eff = g_eff}
