# M5 kernel verification: exact OU recurrence, deterministic state replay, and statistical invariants.
# This verifies the sampler implementation; it is not atmospheric validation.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const Wind := preload("res://physics/wind_turbulence.gd")

const SAMPLE_COUNT_PER_SEED := 20000
const SAMPLE_SEEDS := [101, 2027, 4294967295]
var _sigma := M.v3(1.0, 1.0, 1.0)
const TAU_S := 0.5
const DT_S := 0.02

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s%s" % [label, " — " + detail if not detail.is_empty() else ""])


func _near(actual: PackedFloat64Array, expected: PackedFloat64Array, tolerance := 1e-13) -> bool:
	if actual.size() != expected.size():
		return false
	for axis in actual.size():
		if not is_finite(actual[axis]) or absf(actual[axis] - expected[axis]) > tolerance:
			return false
	return true


func _same(actual: Dictionary, expected: Dictionary) -> bool:
	return actual.ok == expected.ok and actual.rng_state == expected.rng_state \
		and actual.values.to_byte_array() == expected.values.to_byte_array()


func _check_known_answers() -> void:
	var seeded: Dictionary = Wind.initial(M.v3(0.0, 0.0, 0.0), 12345)
	_check("zero-sigma initialization consumes no RNG output",
		seeded.ok and seeded.values == M.v3(0.0, 0.0, 0.0)
		and seeded.rng_state == -7751912382566491497)

	var initial: Dictionary = Wind.initial(M.v3(1.0, 2.0, 0.0), 12345)
	_check("stationary initial draw matches pinned PCG/Box-Muller answer",
		initial.ok and _near(initial.values, M.v3(0.28473044520054, -3.01749330630478, 0.0))
		and initial.rng_state == 4665899913361710971, str(initial))

	var previous := M.v3(1.25, -2.0, 0.5)
	var sigma := M.v3(0.8, 0.0, 1.2)
	var step: Dictionary = Wind.step(previous, sigma, 0.5, 0.1, 12345, seeded.rng_state)
	_check("exact-discrete decay and stochastic innovation match known answer",
		step.ok and _near(step.values, M.v3(1.15420212374793, -1.63746150615596, -0.63018092155486))
		and step.rng_state == 4665899913361710971, str(step))
	var decay := M.exp_(-0.1 / 0.5)
	_check("zero-sigma axis has exact deterministic decay", step.values[1] == decay * previous[1])

	var all_zero: Dictionary = Wind.step(previous, M.v3(0.0, 0.0, 0.0), 0.5, 0.1, 12345, -1)
	_check("all-zero step preserves raw state bits and draws nothing",
		all_zero.ok and all_zero.rng_state == -1
		and _near(all_zero.values, M.v3(decay * previous[0], decay * previous[1], decay * previous[2])))


func _check_deterministic_replay() -> void:
	var sigma := M.v3(0.7, 0.4, 0.9)
	var first: Dictionary = Wind.initial(sigma, 987654321)
	var repeated: Dictionary = Wind.initial(sigma, 987654321)
	_check("same seed repeats initial values and PCG state bit-for-bit", _same(first, repeated))
	if not first.ok:
		return

	var one_pass: Dictionary = first
	for _tick in 31:
		one_pass = Wind.step(one_pass.values, sigma, TAU_S, DT_S, 987654321, one_pass.rng_state)
	var split_pass: Dictionary = first
	for _tick in 11:
		split_pass = Wind.step(split_pass.values, sigma, TAU_S, DT_S, 987654321, split_pass.rng_state)
	var checkpoint := { values = split_pass.values.duplicate(), rng_state = split_pass.rng_state }
	for _tick in 20:
		split_pass = Wind.step(split_pass.values, sigma, TAU_S, DT_S, 987654321, split_pass.rng_state)
	var replayed := checkpoint
	for _tick in 20:
		replayed = Wind.step(replayed.values, sigma, TAU_S, DT_S, 987654321, replayed.rng_state)
	_check("checkpoint continuation reproduces the uninterrupted stream bit-for-bit",
		_same(one_pass, split_pass) and _same(split_pass, replayed))

	var isolated: Dictionary = first
	var interleaved: Dictionary = first
	for _tick in 40:
		isolated = Wind.step(isolated.values, sigma, TAU_S, DT_S, 987654321, isolated.rng_state)
		Wind.step(M.v3(0.0, 0.0, 0.0), M.v3(2.0, 0.0, 0.0), 0.3, 0.01, 77, -1)
		interleaved = Wind.step(interleaved.values, sigma, TAU_S, DT_S, 987654321, interleaved.rng_state)
	_check("unrelated caller queries cannot perturb a stream", _same(isolated, interleaved))

	var negative_state: Dictionary = Wind.step(M.v3(0.0, 0.0, 0.0), M.v3(0.2, 0.0, 0.0),
		0.5, 0.02, 42, -1)
	_check("negative signed state restores the same PCG bits on repeated calls",
		negative_state.ok and negative_state.rng_state == -7073763901869339805
		and _same(negative_state, Wind.step(M.v3(0.0, 0.0, 0.0), M.v3(0.2, 0.0, 0.0),
			0.5, 0.02, 42, -1)), str(negative_state))


func _check_invalid_inputs() -> void:
	for bad_sigma: Variant in [M.v3(1.0, 2.0, -0.1), M.v3(1.0, NAN, 1.0), M.v3(1.0, 2.0, 3.0).slice(0, 2)]:
		var result: Dictionary = Wind.initial(bad_sigma, 0)
		_check("invalid initial sigma fails closed", not result.ok and result.values.size() == 3
			and not is_finite(result.values[0]) and not result.error.is_empty())
	for bad_seed: Variant in [-1, 4294967296, 1.5]:
		var result: Dictionary = Wind.initial(M.v3(1.0, 1.0, 1.0), bad_seed)
		_check("invalid seed fails closed", not result.ok and not is_finite(result.values[0]))
	for invalid: Dictionary in [
		{ previous = M.v3(1.0, 2.0, 3.0).slice(0, 2), sigma = _sigma, tau = TAU_S, dt = DT_S, seed = 1, state = 0 },
		{ previous = M.v3(1.0, 2.0, 3.0), sigma = _sigma, tau = 0.0, dt = DT_S, seed = 1, state = 0 },
		{ previous = M.v3(1.0, 2.0, 3.0), sigma = _sigma, tau = TAU_S, dt = INF, seed = 1, state = 0 },
		{ previous = M.v3(1.0, 2.0, 3.0), sigma = _sigma, tau = TAU_S, dt = DT_S, seed = 1, state = 0.0 },
	]:
		var result: Dictionary = Wind.step(invalid.previous, invalid.sigma, invalid.tau, invalid.dt,
			invalid.seed, invalid.state)
		_check("invalid step input fails closed", not result.ok and not is_finite(result.values[0])
			and not result.error.is_empty())


func _check_stationarity_and_autocorrelation() -> void:
	var count := 0
	var sums := M.v3(0.0, 0.0, 0.0)
	var squares := M.v3(0.0, 0.0, 0.0)
	var lag_previous := M.v3(0.0, 0.0, 0.0)
	var lag_current := M.v3(0.0, 0.0, 0.0)
	var lag_previous_squared := M.v3(0.0, 0.0, 0.0)
	var lag_current_squared := M.v3(0.0, 0.0, 0.0)
	var lag_products := M.v3(0.0, 0.0, 0.0)
	var cross_products := M.v3(0.0, 0.0, 0.0)

	for seed: int in SAMPLE_SEEDS:
		var state: Dictionary = Wind.initial(_sigma, seed)
		if not state.ok:
			_check("statistical stream initializes", false, str(state))
			return
		for _sample in SAMPLE_COUNT_PER_SEED:
			var previous: PackedFloat64Array = state.values
			var next: Dictionary = Wind.step(previous, _sigma, TAU_S, DT_S, seed, state.rng_state)
			if not next.ok:
				_check("statistical stream remains finite", false, str(next))
				return
			count += 1
			for axis in 3:
				sums[axis] += next.values[axis]
				squares[axis] += next.values[axis] * next.values[axis]
				lag_previous[axis] += previous[axis]
				lag_current[axis] += next.values[axis]
				lag_previous_squared[axis] += previous[axis] * previous[axis]
				lag_current_squared[axis] += next.values[axis] * next.values[axis]
				lag_products[axis] += previous[axis] * next.values[axis]
			cross_products[0] += next.values[0] * next.values[1]
			cross_products[1] += next.values[0] * next.values[2]
			cross_products[2] += next.values[1] * next.values[2]
			state = next

	var expected_ac1 := M.exp_(-DT_S / TAU_S)
	for axis in 3:
		var mean: float = sums[axis] / count
		var rms: float = M.sqrt_(squares[axis] / count)
		var lag_n: float = float(count)
		var covariance: float = (lag_products[axis] - lag_previous[axis] * lag_current[axis] / lag_n) / lag_n
		var previous_variance: float = (lag_previous_squared[axis]
			- lag_previous[axis] * lag_previous[axis] / lag_n) / lag_n
		var current_variance: float = (lag_current_squared[axis]
			- lag_current[axis] * lag_current[axis] / lag_n) / lag_n
		var ac1: float = covariance / M.sqrt_(previous_variance * current_variance)
		print("OU axis %d: mean %.8f RMS %.8f ac1 %.8f expected %.8f" % [axis, mean, rms, ac1, expected_ac1])
		_check("axis %d stationary mean lies within 0.12 sigma" % axis, absf(mean) < 0.12, "mean %.5f" % mean)
		_check("axis %d stationary RMS lies within 8%%" % axis, absf(rms - 1.0) < 0.08, "RMS %.5f" % rms)
		_check("axis %d lag-one correlation matches exact decay" % axis,
			absf(ac1 - expected_ac1) < 0.015, "measured %.5f expected %.5f" % [ac1, expected_ac1])
	var mean_north: float = sums[0] / count
	var mean_east: float = sums[1] / count
	var mean_down: float = sums[2] / count
	var covariance_ne: float = cross_products[0] / count - mean_north * mean_east
	var covariance_nd: float = cross_products[1] / count - mean_north * mean_down
	var covariance_ed: float = cross_products[2] / count - mean_east * mean_down
	print("OU cross covariances: NE %.8f ND %.8f ED %.8f" % [covariance_ne, covariance_nd, covariance_ed])
	_check("cross-axis sample covariances stay within 0.07",
		absf(covariance_ne) < 0.07 and absf(covariance_nd) < 0.07 and absf(covariance_ed) < 0.07,
		"covariances %.5f, %.5f, %.5f" % [covariance_ne, covariance_nd, covariance_ed])


func _initialize() -> void:
	_check_known_answers()
	_check_deterministic_replay()
	_check_invalid_inputs()
	_check_stationarity_and_autocorrelation()
	print("wind turbulence kernel: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
