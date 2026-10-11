# EL2a-P2: independent time-polynomial integrals, event order and bounded work.
# Synthetic numerical fixtures; no motor, pack or aircraft calibration.
extends SceneTree

const Battery: Script = preload("res://physics/electric_battery_step.gd")
const Stop: Script = preload("res://physics/electric_stop.gd")
const Bracket: Script = preload("res://physics/event_bracket.gd")
const RPM: int = 13
const CHARGE: int = 14
const ENERGY: int = 15
const SIZE: int = 16

var checks: int = 0
var failures: int = 0
var calls: int = 0
var origin: float = 0.0
var current: float = 1.0
var rotor_rate: float = 0.0
var degree: int = 1
var projected_rpm: float = NAN
var max_linear_calls: int = 0
var max_nonlinear_calls: int = 0


func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)


func _initialize() -> void:
	_proposals()
	_analytic_battery_sweep()
	_analytic_rotor_sweep()
	_event_composition()
	_post_disconnect_tie()
	_large_clock()
	_unresolved_residual()
	_invalid_inputs()
	print("EL2a-P2 event localization: %d checks, %d failed; max linear calls=%d, nonlinear=%d" % [checks, failures, max_linear_calls, max_nonlinear_calls])
	quit(1 if failures else 0)


func _state(rpm: float, charge: float) -> PackedFloat64Array:
	var state := PackedFloat64Array()
	state.resize(SIZE)
	state[6] = 1.0
	state[RPM] = rpm
	state[CHARGE] = charge
	return state


func _rate(state: PackedFloat64Array, at: float) -> PackedFloat64Array:
	calls += 1
	var rate := PackedFloat64Array()
	rate.resize(SIZE)
	# Integral from origin to t is current * t^degree (degree <= 4: RK4 integrates exactly).
	var demand: float = current * float(degree) * pow(at - origin, degree - 1)
	if state[CHARGE] != 0.0:
		rate[CHARGE] = -demand
		rate[ENERGY] = 12.0 * demand
	if state[RPM] != 0.0:
		rate[RPM] = -rotor_rate * float(degree) * pow(at - origin, degree - 1)
	return rate


func _project(state: PackedFloat64Array, index: int) -> PackedFloat64Array:
	projected_rpm = state[index]
	var projected: PackedFloat64Array = state.duplicate()
	projected[index] = 0.0
	return projected


func _battery(state: PackedFloat64Array, dt: float) -> Dictionary:
	calls = 0
	return Battery.advance(state, origin, dt, _rate, _rate(state, origin), RPM, CHARGE, _project)


func _proposals() -> void:
	for values: Array in [[1e308, -1e308], [1e-300, -1e300], [1e300, -1e-300], [1.0, 0.0]]:
		var proposal: float = Bracket.propose(0.0, 1.0, values[0], values[1], 1e-12, false)
		check("extreme residual proposal stays finite and interior", is_finite(proposal) and proposal > 0.0 and proposal < 1.0)
	check("forced subdivision halves the bracket", Bracket.propose(0.0, 1.0, 1e308, -1.0, 1e-12, true) == 0.5)
	check("adjacent floating offsets cannot pretend to contain an interior trial", is_nan(Bracket.propose(1.0, 1.0 + 2.220446049250313e-16, 1.0, -1.0, 1e-12, false)))
	for values: Array in [[NAN, -1.0], [1.0, INF], [0.0, -1.0], [-1.0, -1.0], [1.0, 1.0]]:
		check("invalid sign or finite bracket is refused", is_nan(Bracket.propose(0.0, 1.0, values[0], values[1], 1e-12, false)))


func _analytic_battery_sweep() -> void:
	rotor_rate = 0.0
	for exponent: int in [1, 2, 3, 4]:
		degree = exponent
		for scale: float in [1e-12, 0.2, 30.0, 1000.0]:
			current = scale
			for duration: float in [1.0 / 960.0, 1.0 / 240.0, 0.1, 2.0]:
				for fraction: float in [0.00001, 0.03125, 0.37, 0.8, 0.99999]:
					origin = 0.0
					var root: float = fraction * duration
					var charge: float = current * pow(root, degree)
					var state: PackedFloat64Array = _state(40.0, charge)
					var original: PackedByteArray = var_to_bytes(state)
					var result: Dictionary = _battery(state, duration)
					var label: String = "battery d=%d I=%s dt=%s root=%s" % [degree, current, duration, root]
					check(label + " completes", result.ok)
					if not result.ok:
						continue
					var evaluations: int = calls
					if degree == 1:
						max_linear_calls = maxi(max_linear_calls, evaluations)
					else:
						max_nonlinear_calls = maxi(max_nonlinear_calls, evaluations)
					check(label + " one battery event", result.events.size() == 1 and result.events[0].type == "battery_exhausted")
					var event: Dictionary = result.events[0]
					# The polynomial integral is exact in real arithmetic; allow float64 cancellation
					# at high polynomial degree near zero, separate from the retained numeric bracket.
					check(label + " analytic event time", absf(event.time_s - root) <= 2e-12)
					check(label + " upper residual and time both bounded", event.charge_residual_c <= 0.0 and absf(event.charge_residual_c) <= Battery.CHARGE_TOL_C and event.time_error_bound_s <= Battery.TIME_TOL)
					check(label + " correct disconnected endpoint", result.state[CHARGE] == 0.0 and result.state[RPM] == 40.0)
					check(label + " analytic charge-energy integral", absf(result.state[ENERGY] - 12.0 * charge) <= maxf(2e-9, absf(12.0 * charge) * 2e-14))
					check(label + " caller state preserved", var_to_bytes(state) == original)
					var replay: Dictionary = _battery(state, duration)
					check(label + " deterministic replay", var_to_bytes(replay) == var_to_bytes(result))
	check("linear battery crossings avoid dozens of RK restarts", max_linear_calls <= 60)
	check("nonlinear crossings retain a bounded evaluation budget", max_nonlinear_calls <= 400)


func _analytic_rotor_sweep() -> void:
	current = 0.0
	for exponent: int in [1, 2, 3, 4]:
		degree = exponent
		for rate: float in [1e-9, 1.0, 3000.0]:
			rotor_rate = rate
			for root: float in [0.000001, 0.03, 0.37, 0.8, 0.99999]:
				origin = 0.0
				var state: PackedFloat64Array = _state(rate * pow(root, degree), 0.0)
				var result: Dictionary = Stop.advance(state, origin, 1.0, _rate, _rate(state, origin), RPM, _project)
				var label: String = "rotor d=%d rate=%s root=%s" % [degree, rate, root]
				check(label + " completes", result.ok)
				if not result.ok:
					continue
				check(label + " exactly one stop", result.events.size() == 1)
				if result.events.size() != 1:
					continue
				check(label + " analytic event time even at tiny residual", absf(result.events[0] - root) <= 2e-12)
				check(label + " bounded nonpositive projection", projected_rpm <= 0.0 and absf(projected_rpm) <= Stop.RPM_TOL)
				check(label + " stopped endpoint", result.state[RPM] == 0.0)


func _event_composition() -> void:
	degree = 1
	current = 0.75
	rotor_rate = 1700.0
	for clock_origin: float in [0.0, 12.5, 3600.0]:
		origin = clock_origin
		for pair: Array in [[0.2, 0.7], [0.7, 0.2], [0.37, 0.37]]:
			var result: Dictionary = _battery(_state(rotor_rate * pair[0], current * pair[1]), 1.0)
			check("two boundary events complete", result.ok and result.events.size() == 2)
			if not result.ok or result.events.size() != 2:
				continue
			var first_type: String = "rotor_stop" if pair[0] <= pair[1] else "battery_exhausted"
			check("chronological event order with rotor-first tie", result.events[0].type == first_type and result.events[0].time_s <= result.events[1].time_s)
			for event: Dictionary in result.events:
				var expected: float = origin + (pair[0] if event.type == "rotor_stop" else pair[1])
				check("event time includes absolute origin", absf(event.time_s - expected) <= 2e-12)
			if pair[0] == pair[1]:
				check("shared events use one canonical timestamp", result.events[0].time_s == result.events[1].time_s)
			check("both boundaries remain at zero", result.state[RPM] == 0.0 and result.state[CHARGE] == 0.0)
			check("discarded root trials do not leak energy", absf(result.state[ENERGY] - 12.0 * current * pair[1]) <= 2e-10)


func _invalid_inputs() -> void:
	var state: PackedFloat64Array = _state(1.0, 1.0)
	check("outer battery step refuses clock with no representable advance", not Battery.advance(state, 1e20, 1.0, _rate, PackedFloat64Array(), RPM, CHARGE, _project).ok)
	check("rotor refuses missing derivative", not Stop.advance(state, 0.0, 1.0, Callable(), PackedFloat64Array(), RPM, _project).ok)
	check("rotor refuses missing projection", not Stop.advance(state, 0.0, 1.0, _rate, PackedFloat64Array(), RPM, Callable()).ok)
	check("rotor refuses a timestep beyond its bounded search domain", not Stop.advance(state, 0.0, 61.0, _rate, PackedFloat64Array(), RPM, _project).ok)


func _post_disconnect_tie() -> void:
	origin = 0.0
	degree = 1
	current = 1.0
	rotor_rate = 1.0
	# The physical rotor root is strictly later, but inside the declared coincident-event
	# window. It is discovered only after disconnect; the public order must still be stable.
	var result: Dictionary = _battery(_state(0.37 + 0.25e-12, 0.37), 1.0)
	check("post-disconnect near-coincident roots complete", result.ok and result.events.size() == 2)
	if result.ok and result.events.size() == 2:
		check("post-disconnect near-coincident rotor is ordered first", result.events[0].type == "rotor_stop" and result.events[1].type == "battery_exhausted")
		check("post-disconnect near-coincident roots share timestamp", result.events[0].time_s == result.events[1].time_s)
	var separated: Dictionary = _battery(_state(0.37 + 1e-8, 0.37), 1.0)
	check("resolved later rotor remains distinct", separated.ok and separated.events.size() == 2 and separated.events[0].type == "battery_exhausted" and separated.events[1].type == "rotor_stop" and separated.events[1].time_s > separated.events[0].time_s)


func _large_clock() -> void:
	origin = 1e6
	degree = 1
	current = 1.0
	rotor_rate = 0.0
	var result: Dictionary = _battery(_state(40.0, 0.37), 1.0)
	check("large absolute clock retains a valid local root", result.ok and result.events.size() == 1)
	if result.ok and result.events.size() == 1:
		check("large clock rounds only the timestamp", absf(result.events[0].time_s - (origin + 0.37)) <= 2e-10)
		check("reported local bracket stays bounded", result.events[0].time_error_bound_s <= Battery.TIME_TOL)
	origin = 3600.0
	current = 1e4
	var near_endpoint: Dictionary = _battery(_state(40.0, current * (1.0 - 0.125e-12)), 1.0)
	check("positive sub-clock-ULP exhausted remainder still completes", near_endpoint.ok)


func _unresolved_residual() -> void:
	origin = 0.0
	degree = 2
	rotor_rate = 0.0
	current = 1000.0
	var good: Dictionary = _battery(_state(40.0, current * pow(1.6, 2)), 2.0)
	check("scaled quadratic residual control succeeds", good.ok)
	# At this deliberately extreme scale, adjacent RK endpoint charges straddle zero
	# with residual magnitudes above 1e-10 C on the pinned float64 runtime.
	current = 1e6
	var failed: Dictionary = _battery(_state(40.0, current * pow(1.6, 2)), 2.0)
	check("unresolved residual never becomes an accepted battery event", not failed.ok)
	check("unresolved residual fails for the localization bound", not failed.ok and "localization bounds" in str(failed.get("message", "")))
	check("unresolved residual uses bounded work", calls < 800)
