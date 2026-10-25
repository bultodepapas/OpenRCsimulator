## Bounded level-flight trim search for a caller-selected throttle.
## This chooses a launch operating point; it does not change in-flight trim behavior.
class_name CruiseTrim
extends RefCounted

const Trim := preload("res://physics/trim.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")

const MAX_SEARCH_SPEED_MPS := 80.0
const MAX_ATTACHED_ALPHA_RAD := 0.2617993877991494 # 15 degrees
const DEFAULT_MAX_ALPHA_RAD := 0.13962634015954636 # 8 degrees
const THROTTLE_TOLERANCE := 1.0e-8
const MONOTONIC_TOLERANCE := 2.0e-3
const BRACKET_STEP_MPS := 2.0
## Cap on the bracketed false-position (Illinois) steps; it converges in about six from a 2 m/s bracket.
const MAX_SEARCH_STEPS := 32


static func solve_level_at_throttle(reference_speed_mps: float, target_throttle: float,
		max_speed_mps: float, model: Dictionary, g: float, throws: Dictionary,
		rho: float = Air.RHO_SEA_LEVEL, engine_charge_ratio: float = 1.0,
		max_alpha_rad: float = DEFAULT_MAX_ALPHA_RAD) -> Dictionary:
	if not is_finite(reference_speed_mps) or reference_speed_mps <= 0.0:
		return _failure("reference speed must be finite and positive", reference_speed_mps, target_throttle, max_speed_mps)
	if not is_finite(target_throttle) or target_throttle < 0.0 or target_throttle > 1.0:
		return _failure("target throttle must be finite and within 0..1", reference_speed_mps, target_throttle, max_speed_mps)
	if not is_finite(max_speed_mps) or max_speed_mps < reference_speed_mps or max_speed_mps > MAX_SEARCH_SPEED_MPS:
		return _failure("maximum speed must be at least the reference and no greater than %.1f m/s" % MAX_SEARCH_SPEED_MPS, reference_speed_mps, target_throttle, max_speed_mps)
	if not is_finite(g) or g <= 0.0:
		return _failure("gravity must be finite and positive", reference_speed_mps, target_throttle, max_speed_mps)
	if not is_finite(rho) or rho <= 0.0:
		return _failure("air density must be finite and positive", reference_speed_mps, target_throttle, max_speed_mps)
	if not is_finite(engine_charge_ratio) or engine_charge_ratio < 0.0:
		return _failure("engine charge ratio must be finite and nonnegative", reference_speed_mps, target_throttle, max_speed_mps)
	if not is_finite(max_alpha_rad) or max_alpha_rad <= 0.0 or max_alpha_rad > MAX_ATTACHED_ALPHA_RAD:
		return _failure("maximum attached angle of attack must be finite, positive, and no greater than 15 degrees", reference_speed_mps, target_throttle, max_speed_mps)
	if model.is_empty():
		return _failure("aircraft model must be a structurally valid loader model", reference_speed_mps, target_throttle, max_speed_mps)
	if not _valid_throws(throws):
		return _failure("control throws must contain finite positive elevator, aileron, and rudder (or elevon) limits", reference_speed_mps, target_throttle, max_speed_mps)

	var search_iterations := 0
	var low := _solve_candidate(reference_speed_mps, model, g, throws, rho, engine_charge_ratio, max_alpha_rad)
	search_iterations += 1
	if not low.ok:
		return _failure(low.message, reference_speed_mps, target_throttle, max_speed_mps, search_iterations)
	if low.throttle > target_throttle + THROTTLE_TOLERANCE:
		return _failure("reference-speed trim already requires more than the requested throttle", reference_speed_mps, target_throttle, max_speed_mps, search_iterations)
	if absf(low.throttle - target_throttle) <= THROTTLE_TOLERANCE:
		return _success(low, reference_speed_mps, target_throttle, max_speed_mps, search_iterations)

	var high: Dictionary = {}
	var speed := reference_speed_mps
	while speed < max_speed_mps:
		var next_speed := minf(max_speed_mps, speed + BRACKET_STEP_MPS)
		var candidate := _solve_candidate(next_speed, model, g, throws, rho, engine_charge_ratio, max_alpha_rad, _guess(low))
		search_iterations += 1
		if not candidate.ok:
			return _failure(candidate.message, reference_speed_mps, target_throttle, max_speed_mps, search_iterations)
		if candidate.throttle + MONOTONIC_TOLERANCE < low.throttle:
			return _failure("trim throttle is not monotonic on the upward attached branch", reference_speed_mps, target_throttle, max_speed_mps, search_iterations)
		if absf(candidate.throttle - target_throttle) <= THROTTLE_TOLERANCE:
			return _success(candidate, reference_speed_mps, target_throttle, max_speed_mps, search_iterations)
		if candidate.throttle > target_throttle:
			high = candidate
			break
		low = candidate
		speed = next_speed
	if high.is_empty():
		return _failure("requested throttle was not bracketed by the maximum speed %.2f m/s" % max_speed_mps, reference_speed_mps, target_throttle, max_speed_mps, search_iterations)

	# D6e-R3: Illinois false position on the throttle-against-speed curve inside the bracket (the curve is smooth and
	# monotone there), each solve warm-started from the nearer bracket end; a bisection step guards a degenerate secant.
	var f_low: float = low.throttle - target_throttle
	var f_high: float = high.throttle - target_throttle
	var side := 0
	for _i in MAX_SEARCH_STEPS:
		var span: float = float(high.V) - float(low.V)
		var mid_speed: float = (f_high * float(low.V) - f_low * float(high.V)) / (f_high - f_low) if f_high != f_low else NAN
		if not is_finite(mid_speed) or mid_speed <= float(low.V) or mid_speed >= float(high.V):
			mid_speed = 0.5 * (float(low.V) + float(high.V))
		mid_speed = clampf(mid_speed, float(low.V) + 0.01 * span, float(high.V) - 0.01 * span)
		var nearer: Dictionary = low if mid_speed - float(low.V) <= float(high.V) - mid_speed else high
		var candidate := _solve_candidate(mid_speed, model, g, throws, rho, engine_charge_ratio, max_alpha_rad, _guess(nearer))
		search_iterations += 1
		if not candidate.ok:
			return _failure(candidate.message, reference_speed_mps, target_throttle, max_speed_mps, search_iterations)
		if candidate.throttle < low.throttle - MONOTONIC_TOLERANCE or candidate.throttle > high.throttle + MONOTONIC_TOLERANCE:
			return _failure("trim throttle is not monotonic inside the requested bracket", reference_speed_mps, target_throttle, max_speed_mps, search_iterations)
		if absf(candidate.throttle - target_throttle) <= THROTTLE_TOLERANCE:
			return _success(candidate, reference_speed_mps, target_throttle, max_speed_mps, search_iterations)
		var f_mid: float = candidate.throttle - target_throttle
		if f_mid < 0.0:
			low = candidate
			f_low = f_mid
			if side == -1:
				f_high *= 0.5
			side = -1
		else:
			high = candidate
			f_high = f_mid
			if side == 1:
				f_low *= 0.5
			side = 1

	return _failure("the bracketed search did not reach the requested throttle tolerance", reference_speed_mps, target_throttle, max_speed_mps, search_iterations)


## A converged trim as the next solve's warm start (Trim.solve's unknown order); empty when there is none.
static func _guess(trim: Dictionary) -> PackedFloat64Array:
	if trim.is_empty() or not trim.get("ok", false):
		return PackedFloat64Array()
	# X8-03: a rudderless trim's sixth unknown is its bank angle.
	return PackedFloat64Array([float(trim.alpha), float(trim.elevator), float(trim.throttle), float(trim.beta), float(trim.aileron),
		float(trim.get("bank", trim.rudder))])


static func _solve_candidate(speed_mps: float, model: Dictionary, g: float, throws: Dictionary,
		rho: float, engine_charge_ratio: float, max_alpha_rad: float, initial: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	var result := Trim.solve("level", speed_mps, model, g, throws, rho, engine_charge_ratio, initial)
	if not result.get("ok", false):
		return { ok = false, message = "level trim failed at %.2f m/s: %s" % [speed_mps, str(result.get("message", "no trim result"))] }
	if not _finite_trim(result):
		return { ok = false, message = "level trim returned unavailable or nonfinite values at %.2f m/s" % speed_mps }
	if result.throttle < 0.0 or result.throttle > 1.0:
		return { ok = false, message = "level trim throttle is outside 0..1 at %.2f m/s" % speed_mps }
	if absf(result.alpha) > max_alpha_rad:
		return { ok = false, message = "level trim exceeds the attached-flow angle limit at %.2f m/s" % speed_mps }
	if result.residual > 1.0e-8:
		return { ok = false, message = "level trim residual is too large at %.2f m/s" % speed_mps }
	return result


static func _finite_trim(result: Dictionary) -> bool:
	for key in ["V", "alpha", "beta", "gamma", "throttle", "thrust", "rpm", "elevator", "aileron", "rudder", "pitch_command", "roll_command", "yaw_command", "residual"]:
		if not result.has(key) or not _finite_number(result[key]):
			return false
	var state: Variant = result.get("state")
	if typeof(state) != TYPE_PACKED_FLOAT64_ARRAY or state.size() != RB.SIZE:
		return false
	for value in state:
		if not is_finite(value):
			return false
	return true


static func _valid_throws(throws: Dictionary) -> bool:
	# X8-03: elevon throws carry the elevon end point instead of a rudder (whose throw is exactly 0).
	for axis in (["elevator", "aileron", "elevon"] if throws.has("elevon") else ["elevator", "aileron", "rudder"]):
		if not throws.has(axis) or not _finite_number(throws[axis]) or throws[axis] <= 0.0:
			return false
	return true


static func _finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	return is_finite(float(value))


static func _success(trim: Dictionary, reference_speed_mps: float, target_throttle: float,
		max_speed_mps: float, search_iterations: int) -> Dictionary:
	var result: Dictionary = trim.duplicate(true)
	result["requested_throttle"] = target_throttle
	result["reference_speed_mps"] = reference_speed_mps
	result["max_speed_mps"] = max_speed_mps
	result["search_iterations"] = search_iterations
	return result


static func _failure(message: String, reference_speed_mps: float, target_throttle: float,
		max_speed_mps: float, search_iterations := 0) -> Dictionary:
	return {
		ok = false, message = message, mode = "level", V = reference_speed_mps,
		alpha = NAN, beta = NAN, gamma = NAN, throttle = NAN, thrust = NAN, rpm = NAN,
		elevator = NAN, aileron = NAN, rudder = NAN,
		pitch_command = NAN, roll_command = NAN, yaw_command = NAN,
		state = PackedFloat64Array(), residual = NAN, iterations = 0,
		requested_throttle = target_throttle, reference_speed_mps = reference_speed_mps,
		max_speed_mps = max_speed_mps, search_iterations = search_iterations,
	}
