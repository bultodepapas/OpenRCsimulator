## GP-11: effective leg+tire compliance, in the contact's declared scalar gap.
## No collision detection, body integration, damage thresholds or restitution kicks.
extends RefCounted
const Timing:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/metrics.gd")

const Quantities := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/wheel_profiles.gd")
const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/math3d.gd")
const FORMAT := "openrc-normal-compliance v1"
const LAW := "unilateral-asymmetric-damping-progressive-stop-v1"
const SPECS := {
	"stiffness": ["N/m", 1.0e-9, 1.0e12],
	"compression_damping": ["N·s/m", 0.0, 1.0e12],
	"rebound_damping": ["N·s/m", 0.0, 1.0e12],
	"damping_onset": ["m", 0.0, 1.0e4],
	"stroke": ["m", 1.0e-9, 1.0e4],
	"stop_stiffness": ["N/m", 0.0, 1.0e12],
	"stop_scale": ["m", 1.0e-9, 1.0e4],
	"stop_exponent": ["1", 1.0, 3.0],
	"stop_damping": ["N·s/m", 0.0, 1.0e12],
}


## Bounds above are supported numerical input ranges, not measured aircraft limits.
## All physical inputs retain provenance; stop scale makes k_stop stay in N/m for
## every supported integer exponent. Zero damping onset is an explicit ideal fixture.
static func _profiled_prepare(raw: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	if raw.get("format") != FORMAT:
		errors.append("normal compliance: unsupported format")
	for key: Variant in raw:
		if key != "format" and not SPECS.has(key):
			errors.append("normal compliance: unsupported field '%s'" % str(key))
	for key: String in SPECS:
		Quantities._validate_quantity("normal compliance." + key, raw.get(key), SPECS[key], errors)
	if not errors.is_empty():
		return {ok = false, errors = errors}
	var values := {}
	for key: String in SPECS:
		values[key] = float(raw[key].value)
	if values.stop_exponent != floorf(values.stop_exponent):
		return _failure("stop exponent must be 1, 2 or 3")
	return {ok = true, format = FORMAT, law = LAW, values = values,
		identity = (LAW + JSON.stringify(raw, "", true, true)).sha256_text(),
		provenance = raw.duplicate(true), errors = errors}


## Positive compression and rate mean penetration/closing. Caller keeps the
## successful prepared result unchanged. Returned energy is the EXACT integral of
## this scalar elastic force; geometry must supply its matching gap Jacobian.
static func _profiled_evaluate(prepared: Dictionary, compression_m: float, rate_mps: float) -> Dictionary:
	if not prepared.get("ok", false) or prepared.get("law") != LAW \
		or not is_finite(compression_m) or not is_finite(rate_mps):
		return _failure("invalid normal-compliance query")
	if compression_m <= 0.0:
		return {ok = true, normal_load_n = 0.0, elastic_force_n = 0.0,
			potential_j = 0.0, dissipation_w = 0.0, damping_nsm = 0.0,
			elastic_tangent_npm = 0.0, load_position_derivative_npm = 0.0,
			load_rate_derivative_nsm = 0.0, stop_force_n = 0.0, stop_potential_j = 0.0,
			stop_deflection_m = 0.0, clipped = false}
	var p: Dictionary = prepared.values
	var excess: float = maxf(0.0, compression_m - p.stroke)
	var y: float = excess / p.stop_scale
	var stop_force: float = p.stop_stiffness * p.stop_scale * M.pow_(y, p.stop_exponent)
	var stop_energy: float = p.stop_stiffness * p.stop_scale * p.stop_scale \
		* M.pow_(y, p.stop_exponent + 1.0) / (p.stop_exponent + 1.0)
	var tangent: float = p.stiffness
	if excess > 0.0:
		tangent += p.stop_exponent * p.stop_stiffness * M.pow_(y, p.stop_exponent - 1.0)
	var elastic: float = p.stiffness * compression_m + stop_force
	var potential: float = 0.5 * p.stiffness * compression_m * compression_m + stop_energy
	var c0: float = p.compression_damping if rate_mps >= 0.0 else p.rebound_damping
	var base_ramp := _ramp(compression_m, p.damping_onset)
	var stop_ramp := _ramp(excess, p.stop_scale)
	var damping: float = c0 * base_ramp[0] + p.stop_damping * stop_ramp[0]
	var damping_slope: float = c0 * base_ramp[1] + p.stop_damping * stop_ramp[1]
	var trial: float = elastic + damping * rate_mps
	var normal: float = maxf(0.0, trial)
	# When rebound clips the force, c*v^2 would OVERCOUNT loss. Actual work is
	# (N-F_el)*xdot; with N=0 and xdot<0 this remains nonnegative.
	var loss: float = (normal - elastic) * rate_mps
	var position_derivative: float = tangent + damping_slope * rate_mps if trial > 0.0 else 0.0
	for value: float in [normal, elastic, potential, loss, damping, tangent, position_derivative, stop_force, stop_energy]:
		if not is_finite(value):
			return _failure("normal compliance overflow")
	return {ok = true, normal_load_n = normal, elastic_force_n = elastic,
		potential_j = potential, dissipation_w = loss, damping_nsm = damping,
		elastic_tangent_npm = tangent, load_position_derivative_npm = position_derivative,
		load_rate_derivative_nsm = damping if trial > 0.0 else 0.0,
		stop_force_n = stop_force, stop_potential_j = stop_energy,
		stop_deflection_m = excess, clipped = trial < 0.0}


## Conservative scalar force derivative bounds over x in [0,x_max], |xdot|<=v_max.
## A multibody caller still owns geometric stiffness and coupled mobility bounds.
static func _profiled_bounds(prepared: Dictionary, maximum_compression_m: float, maximum_speed_mps: float) -> Dictionary:
	if not prepared.get("ok", false) or prepared.get("law") != LAW \
		or not is_finite(maximum_compression_m) or maximum_compression_m < 0.0 \
		or not is_finite(maximum_speed_mps) or maximum_speed_mps < 0.0:
		return _failure("invalid normal-compliance envelope")
	var p: Dictionary = prepared.values
	var y: float = maxf(0.0, maximum_compression_m - p.stroke) / p.stop_scale
	var tangent: float = p.stiffness
	if maximum_compression_m > p.stroke:
		tangent += p.stop_exponent * p.stop_stiffness * M.pow_(y, p.stop_exponent - 1.0)
	var c0: float = maxf(p.compression_damping, p.rebound_damping)
	var dc: float = 2.0 * c0 / p.damping_onset if p.damping_onset > 0.0 else 0.0
	if maximum_compression_m > p.stroke:
		dc += 2.0 * p.stop_damping / p.stop_scale
	var damping: float = c0 + p.stop_damping if maximum_compression_m > p.stroke else c0
	var position_bound: float = tangent + dc * maximum_speed_mps
	if not is_finite(position_bound) or not is_finite(damping):
		return _failure("normal-compliance envelope overflow")
	return {ok = true, elastic_tangent_bound_npm = tangent,
		position_derivative_bound_npm = position_bound, rate_derivative_bound_nsm = damping,
		continuous_onset = p.damping_onset > 0.0 or c0 == 0.0}


## Conservative scalar force Lipschitz bounds over the CLOSED compression
## interval [x_min,x_max], |xdot|<=v_max. Existing elastic/damping upper bounds
## are retained; a damping-ramp slope is omitted only when the ENTIRE interval
## is past that ramp. max(0,trial) preserves these bounds where onset is
## continuous. Zero-onset damping is smooth locally only with x_min>0 (or no
## base damping); touching x=0 still requires event-aware integration.
## The caller owns proof that its entire motion remains in this interval,
## geometric stiffness and common multibody mobility. This is no new force law.
static func _profiled_bounds_interval(prepared: Dictionary, minimum_compression_m: float,
		maximum_compression_m: float, maximum_speed_mps: float) -> Dictionary:
	if typeof(prepared.get("ok")) != TYPE_BOOL or not prepared.ok \
		or typeof(prepared.get("law")) != TYPE_STRING or prepared.law != LAW \
		or not prepared.get("values") is Dictionary \
		or not is_finite(minimum_compression_m) or minimum_compression_m < 0.0 \
		or not is_finite(maximum_compression_m) or maximum_compression_m < minimum_compression_m \
		or not is_finite(maximum_speed_mps) or maximum_speed_mps < 0.0:
		return _failure("invalid normal-compliance interval envelope")
	var p: Dictionary = prepared.values
	var y: float = maxf(0.0, maximum_compression_m - p.stroke) / p.stop_scale
	var tangent: float = p.stiffness
	if maximum_compression_m > p.stroke:
		tangent += p.stop_exponent * p.stop_stiffness * M.pow_(y, p.stop_exponent - 1.0)
	var c0: float = maxf(p.compression_damping, p.rebound_damping)
	var dc := 0.0
	if p.damping_onset > 0.0 and minimum_compression_m < p.damping_onset:
		dc = 2.0 * c0 / p.damping_onset
	var minimum_excess: float = maxf(0.0, minimum_compression_m - p.stroke)
	if maximum_compression_m > p.stroke and minimum_excess < p.stop_scale:
		dc += 2.0 * p.stop_damping / p.stop_scale
	var damping: float = c0 + p.stop_damping if maximum_compression_m > p.stroke else c0
	var position_bound: float = tangent + dc * maximum_speed_mps
	if not is_finite(position_bound) or not is_finite(damping):
		return _failure("normal-compliance interval envelope overflow")
	return {ok = true, elastic_tangent_bound_npm = tangent,
		position_derivative_bound_npm = position_bound, rate_derivative_bound_nsm = damping,
		continuous_onset = p.damping_onset > 0.0 or c0 == 0.0 or minimum_compression_m > 0.0}


## Integration admission for ONE isolated scalar mode, not a whole-aircraft bound.
## The rate/frequency targets are accuracy margins for RK4, not physical tuning.
## Reject an unaffordable envelope; never lower the supplied stiffness or damping.
static func scalar_substeps(prepared: Dictionary, maximum_compression_m: float,
		maximum_speed_mps: float, effective_mass_kg: float, dt: float, budget := 64) -> Dictionary:
	if not is_finite(effective_mass_kg) or effective_mass_kg <= 0.0 \
		or not is_finite(dt) or dt <= 0.0 or budget < 1 or budget > 4096:
		return _failure("invalid scalar integration admission")
	var envelope := bounds(prepared, maximum_compression_m, maximum_speed_mps)
	if not envelope.ok:
		return envelope
	if not envelope.continuous_onset:
		return _failure("zero-onset damping needs event-aware integration; no smooth scalar bound")
	var frequency: float = M.sqrt_(envelope.position_derivative_bound_npm / effective_mass_kg)
	var rate: float = envelope.rate_derivative_bound_nsm / effective_mass_kg
	var count: float = maxf(1.0, maxf(dt * frequency / 0.1, dt * rate / 0.25))
	if not is_finite(count) or count > budget:
		return _failure("normal-compliance envelope exceeds integration budget")
	return {ok = true, substeps = ceili(count), angular_frequency_bound = frequency,
		damping_rate_bound = rate, envelope = envelope}


static func _ramp(x: float, scale: float) -> PackedFloat64Array:
	if x <= 0.0:
		return PackedFloat64Array([0.0, 0.0])
	if scale <= 0.0 or x >= scale:
		return PackedFloat64Array([1.0, 0.0])
	var z := x / scale
	return PackedFloat64Array([z * (2.0 - z), 2.0 * (1.0 - z) / scale])


static func _failure(reason: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([reason])}

static func prepare(raw: Dictionary) -> Dictionary:
	Timing.enter("normal_compliance.prepare")
	var measured:=_profiled_prepare(raw)
	Timing.leave()
	return measured

static func evaluate(prepared: Dictionary, compression_m: float, rate_mps: float) -> Dictionary:
	Timing.enter("normal_compliance.evaluate")
	var measured:=_profiled_evaluate(prepared,compression_m,rate_mps)
	Timing.leave()
	return measured

static func bounds(prepared: Dictionary, maximum_compression_m: float, maximum_speed_mps: float) -> Dictionary:
	Timing.enter("normal_compliance.bounds")
	var measured:=_profiled_bounds(prepared,maximum_compression_m,maximum_speed_mps)
	Timing.leave()
	return measured

static func bounds_interval(prepared: Dictionary, minimum_compression_m: float,
		maximum_compression_m: float, maximum_speed_mps: float) -> Dictionary:
	Timing.enter("normal_compliance.bounds_interval")
	var measured:=_profiled_bounds_interval(prepared,minimum_compression_m,maximum_compression_m,maximum_speed_mps)
	Timing.leave()
	return measured
