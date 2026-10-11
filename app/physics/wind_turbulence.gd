# Exact-discrete, stationary Ornstein–Uhlenbeck turbulence in world NED axes.
# Stateless API: the caller owns and persists the private Godot RNG state.
class_name WindTurbulence
extends RefCounted

const M := preload("res://physics/math3d.gd")

const MAX_SEED := 4294967295
const UINT53_DENOMINATOR := 9007199254740992.0
const MAX_OPEN_UNIFORM := 0.9999999999999999


## Draw a stationary three-axis initial turbulence vector and return the advanced RNG state.
## sigma is the per-axis stationary standard deviation in m/s; seed selects the initial state within Godot's fixed PCG stream.
static func initial(sigma: Variant, seed: Variant) -> Dictionary:
	var sigma_error := _validate_sigma(sigma)
	if not sigma_error.is_empty():
		return _failure(sigma_error)
	var seed_error := _validate_seed(seed)
	if not seed_error.is_empty():
		return _failure(seed_error)

	var checked_sigma: PackedFloat64Array = sigma
	var rng := _new_rng(int(seed))
	var normals := _active_normals(rng, checked_sigma)
	var values := M.v3(
		checked_sigma[0] * normals[0],
		checked_sigma[1] * normals[1],
		checked_sigma[2] * normals[2],
	)
	if not _is_finite_vector(values):
		return _failure("initial draw overflowed to a nonfinite value", int(rng.state))
	return _success(values, int(rng.state))


## Advance exact-discrete OU turbulence by dt seconds in the supplied world NED axes.
## rng_state is the signed int64 representation returned by the previous call.
static func step(previous: Variant, sigma: Variant, tau: Variant, dt: Variant,
		seed: Variant, rng_state: Variant) -> Dictionary:
	var previous_error := _validate_vector(previous, "previous")
	if not previous_error.is_empty():
		return _failure(previous_error, rng_state)
	var sigma_error := _validate_sigma(sigma)
	if not sigma_error.is_empty():
		return _failure(sigma_error, rng_state)
	var scalar_error := _validate_positive_scalar(tau, "tau")
	if not scalar_error.is_empty():
		return _failure(scalar_error, rng_state)
	scalar_error = _validate_positive_scalar(dt, "dt")
	if not scalar_error.is_empty():
		return _failure(scalar_error, rng_state)
	var seed_error := _validate_seed(seed)
	if not seed_error.is_empty():
		return _failure(seed_error, rng_state)
	if typeof(rng_state) != TYPE_INT:
		return _failure("rng_state must be a signed int64", 0)

	var checked_previous: PackedFloat64Array = previous
	var checked_sigma: PackedFloat64Array = sigma
	var interval: float = float(dt)
	var correlation_time: float = float(tau)
	var rng := _new_rng(int(seed), int(rng_state))
	var normals := _active_normals(rng, checked_sigma)
	var a: float = M.exp_(-interval / correlation_time)
	var innovation_gain: float = M.sqrt_(maxf(0.0, 1.0 - a * a))
	var values := M.v3(
		a * checked_previous[0] + checked_sigma[0] * innovation_gain * normals[0],
		a * checked_previous[1] + checked_sigma[1] * innovation_gain * normals[1],
		a * checked_previous[2] + checked_sigma[2] * innovation_gain * normals[2],
	)
	if not _is_finite_vector(values):
		return _failure("OU update produced a nonfinite value", int(rng.state))
	return _success(values, int(rng.state))


static func _new_rng(seed: int, restored_state: Variant = null) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	# In Godot 4.7.2, assigning seed initializes PCG32 from the seed and its default stream.
	rng.seed = seed
	if restored_state != null:
		# State is a signed int64 view of the raw 64-bit PCG state; preserve its bits as-is.
		rng.state = int(restored_state)
	return rng


## Build only as many normal pairs as there are nonzero sigma components.
## A zero-sigma component is exactly zero in this draw and consumes no uniforms.
static func _active_normals(rng: RandomNumberGenerator, sigma: PackedFloat64Array) -> PackedFloat64Array:
	var normals := M.v3(0.0, 0.0, 0.0)
	var pair := PackedFloat64Array()
	var pair_index := 2
	for axis in 3:
		if sigma[axis] == 0.0:
			continue
		if pair_index >= 2:
			pair = _normal_pair(rng)
			pair_index = 0
		normals[axis] = pair[pair_index]
		pair_index += 1
	return normals


static func _normal_pair(rng: RandomNumberGenerator) -> PackedFloat64Array:
	var u1 := _uniform_open(rng)
	var u2 := _uniform_open(rng)
	var radius := M.sqrt_(-2.0 * M.log_(u1))
	var angle := TAU * u2
	return PackedFloat64Array([radius * M.cos_(angle), radius * M.sin_(angle)])


## Combine two raw 32-bit outputs into an open 53-bit uniform using their high bits.
## The upper clamp handles the one top-end midpoint that rounds to 1.0 in binary64.
static func _uniform_open(rng: RandomNumberGenerator) -> float:
	var high_bits: int = rng.randi() >> 5
	var low_bits: int = rng.randi() >> 6
	var mantissa: int = high_bits * 67108864 + low_bits
	var value: float = (float(mantissa) + 0.5) / UINT53_DENOMINATOR
	return minf(value, MAX_OPEN_UNIFORM)


static func _validate_sigma(value: Variant) -> String:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY:
		return "sigma must be a PackedFloat64Array"
	if value.size() != 3:
		return "sigma must have exactly three world NED components"
	for component: float in value:
		if not is_finite(component) or component < 0.0:
			return "sigma components must be finite and nonnegative"
	return ""


static func _validate_vector(value: Variant, label: String) -> String:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY:
		return "%s must be a PackedFloat64Array" % label
	if value.size() != 3:
		return "%s must have exactly three world NED components" % label
	for component: float in value:
		if not is_finite(component):
			return "%s components must be finite" % label
	return ""


static func _validate_positive_scalar(value: Variant, label: String) -> String:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) <= 0.0:
		return "%s must be finite and positive" % label
	return ""


static func _validate_seed(value: Variant) -> String:
	if typeof(value) != TYPE_INT or value < 0 or value > MAX_SEED:
		return "seed must be an integer in [0, 4294967295]"
	return ""


static func _is_finite_vector(value: PackedFloat64Array) -> bool:
	return value.size() == 3 and is_finite(value[0]) and is_finite(value[1]) and is_finite(value[2])


static func _success(values: PackedFloat64Array, rng_state: int) -> Dictionary:
	return { ok = true, values = values, rng_state = rng_state, error = "" }


static func _failure(message: String, rng_state: Variant = 0) -> Dictionary:
	var returned_state: int = int(rng_state) if typeof(rng_state) == TYPE_INT else 0
	return {
		ok = false,
		values = M.v3(NAN, NAN, NAN),
		rng_state = returned_state,
		error = message,
	}
