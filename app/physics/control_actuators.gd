extends RefCounted

const M := preload("res://physics/math3d.gd")
const Quantities := preload("res://physics/wheel_profiles.gd")
const PRESCRIBED_ANGLE_FORMAT := "openrc-prescribed-angle-actuator v1"
const PRESCRIBED_ANGLE_LAW := "bounded-critical-prescribed-angle-v1"
const PRESCRIBED_ANGLE_SPECS := {
	"angle_limit": ["rad", 1.0e-9, PI],
	"signed_full_scale_angle": ["rad", -PI, PI],
	"lag_time": ["s", 1.0e-6, 1.0e6],
	"max_rate": ["rad/s", 1.0e-9, 1.0e12],
	"max_acceleration": ["rad/s^2", 1.0e-9, 1.0e15],
}
const ANGLE_ROUNDOFF_RELATIVE := 64.0 * 2.220446049250313e-16


## Existing sampled servo law, with the original arithmetic order. Callers of this
## hot scalar path own validation. Zero rate holds the actual position, not demand.
static func rate_limit(value: float, target: float, rate: float, dt: float) -> float:
	var max_step := rate * dt
	return value + clampf(target - value, -max_step, max_step)


## Prepare detached normalized actuator positions. This kernel does not establish
## installed hardware, mixing, a clock or a checkpoint layout. The owner commits
## the returned candidate only after its complete simulation step is accepted.
## Nominal rates are neutral-to-full travel per second; optional factors in [0,1]
## represent reduced rate or a jam (0). An empty result rejects the entire input.
static func step_normalized(actual: PackedFloat64Array, demand: PackedFloat64Array,
		rates: PackedFloat64Array, dt: float,
		rate_factors := PackedFloat64Array()) -> PackedFloat64Array:
	var count := actual.size()
	if count == 0 or demand.size() != count or rates.size() != count \
			or (not rate_factors.is_empty() and rate_factors.size() != count) \
			or not is_finite(dt) or dt < 0.0:
		return PackedFloat64Array()
	for index in count:
		var factor: float = 1.0 if rate_factors.is_empty() else rate_factors[index]
		if not is_finite(actual[index]) or absf(actual[index]) > 1.0 \
				or not is_finite(demand[index]) or absf(demand[index]) > 1.0 \
				or not is_finite(rates[index]) or rates[index] <= 0.0 \
				or not is_finite(factor) or factor < 0.0 or factor > 1.0 \
				or not is_finite((rates[index] * factor) * dt):
			return PackedFloat64Array()
	var candidate := PackedFloat64Array()
	candidate.resize(count)
	for index in count:
		var rate: float = rates[index] if rate_factors.is_empty() else rates[index] * rate_factors[index]
		candidate[index] = rate_limit(actual[index], demand[index], rate, dt)
	return candidate


## Explicit NEW prescribed-angle law; the legacy sampled functions above retain
## their arithmetic and callers. Quantities describe the installed linkage's
## declared kinematic envelope, never inferred from legacy servo throw timing.
## tau is one repeated pole time, not full-throw or settling time. The ideal,
## fixed-center/massless carrier has no torque/power limit or separate energy.
static func prepare_prescribed_angle(raw: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	if raw.get("format", "") != PRESCRIBED_ANGLE_FORMAT:
		errors.append("prescribed angle: unsupported format")
	var identifier: Variant = raw.get("id")
	if typeof(identifier) != TYPE_STRING or identifier.is_empty() or identifier != identifier.strip_edges() or identifier.length() > 128:
		errors.append("prescribed angle: bounded nonempty ID required")
	for key: Variant in raw:
		if key not in ["format", "id"] and not PRESCRIBED_ANGLE_SPECS.has(key):
			errors.append("prescribed angle: unsupported field '%s'" % str(key))
	for key: String in PRESCRIBED_ANGLE_SPECS:
		Quantities._validate_quantity("prescribed angle." + key, raw.get(key), PRESCRIBED_ANGLE_SPECS[key], errors)
	if not errors.is_empty(): return {ok = false, errors = errors}
	var values := {}
	for key: String in PRESCRIBED_ANGLE_SPECS: values[key] = float(raw[key].value)
	if not _prescribed_values_valid(values):
		return _angle_failure("linkage target exceeds travel or declared rate/acceleration cannot certify this lag")
	return {ok = true, format = PRESCRIBED_ANGLE_FORMAT, law = PRESCRIBED_ANGLE_LAW,
		identity = (PRESCRIBED_ANGLE_LAW + JSON.stringify(raw, "", true, true)).sha256_text(),
		values = values, provenance = raw.duplicate(true),
		certified_rate_bound_radps = 2.0 * values.angle_limit / values.lag_time,
		certified_acceleration_bound_radps2 = 4.0 * values.angle_limit / (values.lag_time * values.lag_time),
		maximum_rk4_step_s = values.lag_time, errors = errors}


## State is [theta rad, v rad/s]. z=theta+tau*v is the latent first filter angle.
## theta_dot=(z-theta)/tau, z_dot=(u-z)/tau. The rectangle theta,z in [-A,A]
## is forward invariant for every bounded, piecewise held target. It implies
## |v|<=2A/tau and |a|<=4A/tau^2. Only float64 roundoff slack is admitted: no
## angle/velocity projection, stop impulse or per-tick restart is performed.
static func prescribed_angle_state_valid(prepared: Dictionary, state: PackedFloat64Array) -> bool:
	if not _prescribed_config_valid(prepared) or state.size() != 2 or not _angle_finite(state): return false
	var p: Dictionary = prepared.values
	var latent: float = state[0] + p.lag_time * state[1]
	var bound: float = p.angle_limit * (1.0 + ANGLE_ROUNDOFF_RELATIVE)
	return is_finite(latent) and absf(state[0]) <= bound and absf(latent) <= bound


## actual_normalized is the accepted actual upstream servo, held for this tick,
## never raw pilot demand. Target changes keep BOTH states continuous. Angle is
## C1; acceleration may have a finite jump at a sampled target boundary. This
## does not inject an impulse. RotorSystem owns the signed mechanism work from
## its demanded carrier torque; this scalar controller invents no servo heat.
static func prescribed_angle_response(prepared: Dictionary, state: PackedFloat64Array,
		actual_normalized: float) -> Dictionary:
	if not prescribed_angle_state_valid(prepared, state) or not is_finite(actual_normalized) or absf(actual_normalized) > 1.0:
		return _angle_failure("invalid prescribed-angle state or actual servo target")
	var p: Dictionary = prepared.values
	var target: float = p.signed_full_scale_angle * actual_normalized
	var acceleration: float = ((target - state[0]) - 2.0 * p.lag_time * state[1]) / (p.lag_time * p.lag_time)
	if not is_finite(acceleration): return _angle_failure("prescribed-angle derivative overflow")
	return {ok = true, law = PRESCRIBED_ANGLE_LAW, identity = prepared.identity,
		derivative = PackedFloat64Array([state[1], acceleration]), angle_rad = state[0], rate_radps = state[1],
		acceleration_radps2 = acceleration, target_rad = target, latent_angle_rad = state[0] + p.lag_time * state[1]}


## Compose this minimum into the EXISTING model substep owner. For r=h/tau<=1,
## every RK4 intermediate and endpoint (theta,z) is a convex combination of the
## initial theta,z and held target. E.g. k3 theta coefficients are
## [1-r/2+r^2/4, r/2-r^2/2, r^2/4]; endpoint coefficients are
## [1-r+r^2/2-r^3/6+r^4/24, r-r^2+r^3/2-r^4/6, r^2/2-r^3/3+r^4/8].
## No maximum rate is weakened to fit the budget; an unaffordable step rejects.
static func prescribed_angle_substeps(prepared: Dictionary, dt: float, budget := 16) -> Dictionary:
	if not _prescribed_config_valid(prepared) or not is_finite(dt) or dt <= 0.0 or budget < 1 or budget > 4096:
		return _angle_failure("invalid prescribed-angle step or budget")
	var ratio: float = dt / prepared.values.lag_time
	if not is_finite(ratio) or ratio > float(budget):
		return _angle_failure("prescribed-angle invariant step exceeds budget")
	var count := maxi(1, ceili(ratio))
	return {ok = true, substeps = count, max_step_ratio = ratio / float(count), maximum_step_s = prepared.values.lag_time}


## Rotation about ONE fixed body-coordinate hinge, with no translating hub.
## Full carrier nu is retained even when hinge and axle are parallel and the
## axle direction does not move. This is kinematics, not a load/torque model.
## nu_dot is the body-coordinate derivative, as consumed by RotorSystem.
static func fixed_axis_motion(reference_axis: PackedFloat64Array, hinge_axis: PackedFloat64Array,
		angle_rad: float, rate_radps: float, acceleration_radps2: float) -> Dictionary:
	if not _angle_unit(reference_axis) or not _angle_unit(hinge_axis) \
			or not _angle_finite(PackedFloat64Array([angle_rad, rate_radps, acceleration_radps2])):
		return _angle_failure("fixed-axis motion requires finite state and unit reference/hinge axes")
	var reference := M.scale(reference_axis, 1.0 / M.norm(reference_axis))
	var hinge := M.scale(hinge_axis, 1.0 / M.norm(hinge_axis))
	var cosine := M.cos_(angle_rad)
	var sine := M.sin_(angle_rad)
	var axis := M.add(M.add(M.scale(reference, cosine), M.scale(M.cross(hinge, reference), sine)),
		M.scale(hinge, M.dot(hinge, reference) * (1.0 - cosine)))
	var rate := M.scale(hinge, rate_radps)
	var acceleration := M.scale(hinge, acceleration_radps2)
	if not _angle_finite(axis) or not _angle_finite(rate) or not _angle_finite(acceleration):
		return _angle_failure("fixed-axis motion overflow")
	return {ok = true, axis_body = M.scale(axis, 1.0 / M.norm(axis)), carrier_rate_body = rate, carrier_accel_body = acceleration}


static func _prescribed_values_valid(values: Dictionary) -> bool:
	for key: String in PRESCRIBED_ANGLE_SPECS:
		var value: Variant = values.get(key)
		var spec: Array = PRESCRIBED_ANGLE_SPECS[key]
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)) or float(value) < spec[1] or float(value) > spec[2]: return false
	var angle: float = values.angle_limit
	var tau: float = values.lag_time
	return absf(values.signed_full_scale_angle) <= angle and 2.0 * angle / tau <= values.max_rate \
		and 4.0 * angle / (tau * tau) <= values.max_acceleration


static func _prescribed_config_valid(prepared: Dictionary) -> bool:
	return prepared.get("ok", false) and prepared.get("format", "") == PRESCRIBED_ANGLE_FORMAT \
		and prepared.get("law", "") == PRESCRIBED_ANGLE_LAW and typeof(prepared.get("identity")) == TYPE_STRING \
		and not str(prepared.identity).is_empty() and typeof(prepared.get("values")) == TYPE_DICTIONARY and _prescribed_values_valid(prepared.values)


static func _angle_unit(axis: PackedFloat64Array) -> bool:
	return axis.size() == 3 and _angle_finite(axis) and absf(M.dot(axis, axis) - 1.0) <= 1.0e-9


static func _angle_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value): return false
	return true


static func _angle_failure(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message])}
