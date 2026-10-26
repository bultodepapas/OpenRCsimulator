# NITRO-05: fuel feed pressure at the carburetor of a glow installation (optional `fuel_feed` installation block).
# A glow carburetor meters premix through its needle by the pressure difference that drives fuel to the spray bar:
# the carburetor's own suction plus the tank pressurization (muffler or crankcase), plus the hydrostatic head of the
# fuel column between the tank's free surface and the spray bar. That head follows the apparent gravity the fuel
# feels, g_eff = −(non-gravitational force)/mass: gravity itself accelerates fuel and airframe alike. A steady
# up-line (thrust minus drag holding the airplane against gravity) or a full-throttle acceleration sends it aft,
# so the carburetor ahead of the tank must lift fuel; a dive that drag is slowing sends it forward and richens; a
# hard pull with a low tank sinks the surface away from a carburetor above it; an emptying tank lowers the surface.
# An optional authored pickup is available only while submerged below this same free surface. Orifice flow scales
# with the square root of the driving pressure; the engine was needled in
# level 1 g flight with a full tank, so the delivered flow is the needled flow times
#   k = sqrt((p_drive + Δp_head) / (p_drive + Δp_head,needled)),   0 ≤ k ≤ MAX_FACTOR.
# The driving pressure rises with the admitted flow squared from an idle floor to its full-throttle value:
#   p_drive = p_idle + (p_wot − p_idle)·(admission·rpm/rated_rpm)²   (capped at p_wot).
# The free surface of a box tank lies perpendicular to g_eff at a depth set by the fill fraction (exact for a
# surface parallel to a tank face, an estimate otherwise). Apparent gravity includes point acceleration from
# translational force, angular acceleration and centripetal acceleration. Slosh, clunk blockage, and within-tick
# line pressure or reprime are not modelled. A separately authored pre-primed line is another finite inventory.
# Pure functions of float64 body-frame (FRD) arrays; transcendental calls go through math3d.
extends RefCounted
const Timing:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/metrics.gd")

const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/math3d.gd")

## Flooding bound: a carburetor cannot pass more than twice its needled flow through the same needle setting.
const MAX_FACTOR := 2.0
## The carburetor's needled flow is a fixed installation reference at standard 1 g,
## independent of the current simulator gravity (which may be zero or another value).
const STANDARD_GRAVITY := 9.80665
## Below this apparent gravity (m/s²) the fuel has no defined free surface; the head is taken as zero.
const MIN_G := 1e-6
const MAX_SOLVE_ITERATIONS := 32
const SOLVE_RESIDUAL_TOLERANCE := 1e-8


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


## Signed distance below the free surface in the apparent-down direction. Positive means submerged. A near-zero
## apparent gravity has no defined surface and returns NaN so an authored pickup fails closed.
static func pickup_margin_m(g_eff: PackedFloat64Array, fill: float, pickup: PackedFloat64Array,
		tank_center: PackedFloat64Array, tank_size: PackedFloat64Array) -> float:
	if g_eff.size() != 3 or pickup.size() != 3 or tank_center.size() != 3 or tank_size.size() != 3 \
			or not is_finite(fill) or fill < 0.0 or fill > 1.0:
		return NAN
	for values: PackedFloat64Array in [g_eff, pickup, tank_center, tank_size]:
		for value: float in values:
			if not is_finite(value):
				return NAN
	var gravity: float = M.norm(g_eff)
	if not is_finite(gravity) or gravity < MIN_G:
		return NAN
	var down: PackedFloat64Array = M.scale(g_eff, 1.0 / gravity)
	var depth: float = absf(down[0]) * tank_size[0] + absf(down[1]) * tank_size[1] + absf(down[2]) * tank_size[2]
	var surface: float = M.dot(down, tank_center) + (0.5 - fill) * depth
	return M.dot(down, pickup) - surface


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


## Apparent gravity at a tank point relative to the live CG, in body FRD axes.
## Gravity cancels against the CG's translational response: g_app = -F/m - α×r - ω×(ω×r).
static func apparent_gravity(force_body: PackedFloat64Array, mass_kg: float,
		tank_arm_from_cg_body_m: PackedFloat64Array, alpha_body: PackedFloat64Array,
		omega_body: PackedFloat64Array) -> PackedFloat64Array:
	if force_body.size() != 3 or tank_arm_from_cg_body_m.size() != 3 or alpha_body.size() != 3 or omega_body.size() != 3 \
			or not is_finite(mass_kg) or mass_kg <= 0.0:
		return PackedFloat64Array()
	for values: PackedFloat64Array in [force_body, tank_arm_from_cg_body_m, alpha_body, omega_body]:
		for value: float in values:
			if not is_finite(value):
				return PackedFloat64Array()
	var translational: PackedFloat64Array = M.scale(force_body, -1.0 / mass_kg)
	var rotational: PackedFloat64Array = M.add(M.cross(alpha_body, tank_arm_from_cg_body_m),
		M.cross(omega_body, M.cross(omega_body, tank_arm_from_cg_body_m)))
	return M.sub(translational, rotational)


## Everything at once for a stage using absolute on-board mass (including unusable residue).
## The tank surface uses total liquid fill; no flow is admitted once only unusable mass remains.
static func evaluate(feed: Dictionary, force_body: PackedFloat64Array, mass_kg: float,
		remaining_fuel_kg: float, capacity_fuel_kg: float, unusable_fuel_kg: float,
		admission: float, rpm: float, tank_center: PackedFloat64Array, tank_size: PackedFloat64Array,
		tank_arm_from_cg_body_m: PackedFloat64Array,
		alpha_body: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]),
		omega_body: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]),
		pickup_position_body_m: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	if not is_finite(remaining_fuel_kg) or not is_finite(capacity_fuel_kg) or capacity_fuel_kg <= 0.0 \
			or not is_finite(unusable_fuel_kg) or unusable_fuel_kg < 0.0 or unusable_fuel_kg >= capacity_fuel_kg \
			or not is_finite(admission) or not is_finite(rpm) or rpm < 0.0:
		return {ok = false, message = "Glow feed tank mass, admission or RPM is outside its domain"}
	var g_eff: PackedFloat64Array = apparent_gravity(force_body, mass_kg, tank_arm_from_cg_body_m, alpha_body, omega_body)
	if g_eff.size() != 3:
		return {ok = false, message = "Glow feed apparent gravity inputs are malformed"}
	var fill: float = clampf(remaining_fuel_kg / capacity_fuel_kg, 0.0, 1.0)
	var head: float = head_pa(g_eff, fill, feed.carburetor_body_m, tank_center, tank_size, float(feed.density_kg_m3))
	var pickup_margin: float = 0.0
	var pickup_wet: bool = true
	if not pickup_position_body_m.is_empty():
		pickup_margin = pickup_margin_m(g_eff, fill, pickup_position_body_m, tank_center, tank_size)
		if not is_finite(pickup_margin):
			return {ok = false, message = "Authored Glow pickup has no defined free surface at current apparent gravity"}
		pickup_wet = pickup_margin >= 0.0
	var needled: float = needled_head_pa(feed, tank_center, tank_size, STANDARD_GRAVITY)
	var drive: float = drive_pa(admission, rpm, feed)
	var flow_factor: float = 0.0 if remaining_fuel_kg <= unusable_fuel_kg \
		else (factor(drive, head, needled) if pickup_wet else 0.0)
	return {ok = true, factor = flow_factor, head_pa = head, needled_head_pa = needled,
		drive_pa = drive, g_eff = g_eff, fill_fraction = fill,
		usable_fuel_kg = maxf(0.0, remaining_fuel_kg - unusable_fuel_kg),
		pickup_margin_m = pickup_margin, pickup_surface_defined = not pickup_position_body_m.is_empty(),
		pickup_wet = pickup_wet,
		alpha_body_rad_s2 = alpha_body.duplicate(), omega_body_rad_s = omega_body.duplicate()}


## Candidate-independent terms for the same-stage closure. The live force and angular acceleration still determine
## apparent gravity for each candidate; tank fill, the needled reference head, and carburetor drive do not.
static func prepare_factor_context(feed: Dictionary, remaining_fuel_kg: float, capacity_fuel_kg: float,
		unusable_fuel_kg: float, admission: float, rpm: float, tank_center: PackedFloat64Array,
		tank_size: PackedFloat64Array) -> Dictionary:
	if not is_finite(remaining_fuel_kg) or not is_finite(capacity_fuel_kg) or capacity_fuel_kg <= 0.0 \
			or not is_finite(unusable_fuel_kg) or unusable_fuel_kg < 0.0 or unusable_fuel_kg >= capacity_fuel_kg \
			or not is_finite(admission) or not is_finite(rpm) or rpm < 0.0:
		return {ok = false}
	return {ok = true, feed = feed, fill_fraction = clampf(remaining_fuel_kg / capacity_fuel_kg, 0.0, 1.0),
		remaining_fuel_kg = remaining_fuel_kg, unusable_fuel_kg = unusable_fuel_kg,
		drive_pa = drive_pa(admission, rpm, feed),
		needled_head_pa = needled_head_pa(feed, tank_center, tank_size, STANDARD_GRAVITY),
		tank_center = tank_center, tank_size = tank_size}


## Scalar-only form of `evaluate()` for solver candidates. Returns NaN on the same malformed apparent-gravity or
## authored-pickup conditions; the accepted candidate is evaluated once with `evaluate()` for full telemetry.
static func factor_for_stage(context: Dictionary, force_body: PackedFloat64Array, mass_kg: float,
		tank_arm_from_cg_body_m: PackedFloat64Array, alpha_body: PackedFloat64Array,
		omega_body: PackedFloat64Array, pickup_position_body_m: PackedFloat64Array = PackedFloat64Array()) -> float:
	if not context.get("ok", false):
		return NAN
	var feed: Dictionary = context.feed
	var g_eff: PackedFloat64Array = apparent_gravity(force_body, mass_kg, tank_arm_from_cg_body_m,
		alpha_body, omega_body)
	if g_eff.size() != 3:
		return NAN
	var head: float = head_pa(g_eff, float(context.fill_fraction), feed.carburetor_body_m,
		context.tank_center, context.tank_size, float(feed.density_kg_m3))
	var pickup_wet: bool = true
	if not pickup_position_body_m.is_empty():
		var pickup_margin: float = pickup_margin_m(g_eff, float(context.fill_fraction), pickup_position_body_m,
			context.tank_center, context.tank_size)
		if not is_finite(pickup_margin):
			return NAN
		pickup_wet = pickup_margin >= 0.0
	if float(context.remaining_fuel_kg) <= float(context.unusable_fuel_kg):
		return 0.0
	return factor(float(context.drive_pa), head, float(context.needled_head_pa)) if pickup_wet else 0.0


## Solve the same-stage fuel/torque/feed closure. The callback returns
## {ok, target_factor, ...payload}; accepted roots satisfy f - target_factor = 0.
## A narrow bracket without a small residual is rejected (discontinuous callbacks can have no root).
static func solve_factor(evaluate_factor: Callable, seed: float = 1.0) -> Dictionary:
	if not evaluate_factor.is_valid() or not is_finite(seed):
		return {ok = false, message = "Glow feed factor solver needs a valid callback and finite seed"}
	var low: float = 0.0
	var high: float = MAX_FACTOR
	var low_sample: Dictionary = _factor_sample(evaluate_factor, low)
	var high_sample: Dictionary = _factor_sample(evaluate_factor, high)
	if not low_sample.get("ok", false) or not high_sample.get("ok", false):
		return {ok = false, message = "Glow feed factor endpoint evaluation failed"}
	var low_residual: float = float(low_sample.residual)
	var high_residual: float = float(high_sample.residual)
	var evaluations: int = 2
	if low_residual > 0.0 or high_residual < 0.0:
		return {ok = false, message = "Glow feed factor endpoints do not bracket a finite root", evaluations = evaluations}
	if absf(low_residual) <= SOLVE_RESIDUAL_TOLERANCE:
		return _factor_solution(low_sample, evaluations, 0)
	if absf(high_residual) <= SOLVE_RESIDUAL_TOLERANCE:
		return _factor_solution(high_sample, evaluations, 0)
	var candidate: float = clampf(seed, low, high)
	if candidate <= low or candidate >= high:
		candidate = 0.5 * (low + high)
	var sample: Dictionary = _factor_sample(evaluate_factor, candidate)
	evaluations += 1
	if not sample.get("ok", false):
		return {ok = false, message = "Glow feed factor seed evaluation failed", evaluations = evaluations}
	if absf(float(sample.residual)) <= SOLVE_RESIDUAL_TOLERANCE:
		return _factor_solution(sample, evaluations, 0)
	if float(sample.residual) < 0.0:
		low = candidate
		low_residual = float(sample.residual)
		low_sample = sample
	else:
		high = candidate
		high_residual = float(sample.residual)
		high_sample = sample
	var iterations: int = 0
	for iteration: int in MAX_SOLVE_ITERATIONS:
		iterations = iteration + 1
		var width: float = high - low
		var denominator: float = high_residual - low_residual
		var next: float = high - high_residual * width / denominator if denominator != 0.0 else NAN
		# Permit a real root near an endpoint (common for the needled factor) while
		# still forcing a midpoint when secant rounding collapses onto either end.
		var guard: float = width * 1.0e-6
		if not is_finite(next) or next <= low + guard or next >= high - guard:
			next = low + 0.5 * width
		sample = _factor_sample(evaluate_factor, next)
		evaluations += 1
		if not sample.get("ok", false):
			return {ok = false, message = "Glow feed factor refinement evaluation failed", evaluations = evaluations}
		var residual: float = float(sample.residual)
		if absf(residual) <= SOLVE_RESIDUAL_TOLERANCE:
			return _factor_solution(sample, evaluations, iterations)
		if residual < 0.0:
			low = next
			low_residual = residual
			low_sample = sample
		else:
			high = next
			high_residual = residual
			high_sample = sample
	return {ok = false, message = "Glow feed factor solve did not meet residual tolerance",
		evaluations = evaluations, iterations = iterations,
		residual = minf(absf(low_residual), absf(high_residual))}


static func _factor_sample(evaluate_factor: Callable, value: float) -> Dictionary:
	var raw: Variant = evaluate_factor.call(value)
	if not raw is Dictionary or not raw.get("ok", false):
		return {ok = false}
	var target: Variant = raw.get("target_factor", NAN)
	if typeof(target) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(target)) \
			or float(target) < 0.0 or float(target) > MAX_FACTOR:
		return {ok = false}
	return {ok = true, factor = value, target_factor = float(target), residual = value - float(target), payload = raw}


static func _factor_solution(sample: Dictionary, evaluations: int, iterations: int) -> Dictionary:
	return {ok = true, factor = sample.factor, target_factor = sample.target_factor,
		residual = sample.residual, evaluations = evaluations, iterations = iterations,
		payload = sample.payload}
