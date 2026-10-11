# EL2a battery/rotor event checks. Pack and rate values are synthetic numerical fixtures.
extends SceneTree

const BatteryStep: Script = preload("res://physics/electric_battery_step.gd")
const Supply: Script = preload("res://physics/electric_supply.gd")

const RPM_INDEX: int = 13
const CHARGE_INDEX: int = 14
const ENERGY_INDEX: int = 15
const HEAT_INDEX: int = 16
const STATE_SIZE: int = 17

var checks: int = 0
var failures: int = 0
var current_a: float = 0.0
var voltage_v: float = 0.0
var pack_resistance_ohm: float = 0.0
var bearing_deceleration_rpm_s: float = 0.0
var saw_negative_charge_trial: bool = false
var saw_boundary_left_limit: bool = false
var saw_negative_rpm_trial: bool = false
var minimum_trial_charge_c: float = INF
var projection_calls: int = 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL: " + label)


func near(label: String, actual: float, expected: float, tolerance: float = 1e-10) -> void:
	check(label + " actual=" + str(actual) + " expected=" + str(expected),
		is_finite(actual) and absf(actual - expected) <= tolerance)


func _initialize() -> void:
	_supply_boundary_api()
	_constant_current_energy_and_exact_endpoint()
	_positive_rpm_coast_after_exhaustion()
	_rotor_before_battery_and_shared_endpoint()
	_starting_exhausted_and_no_event()
	_invalid_and_unsupported_trials()
	print("EL2a electric battery step: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _reset_observations() -> void:
	saw_negative_charge_trial = false
	saw_boundary_left_limit = false
	saw_negative_rpm_trial = false
	minimum_trial_charge_c = INF
	projection_calls = 0


func _state(rpm: float, charge_c: float) -> PackedFloat64Array:
	var values: PackedFloat64Array = PackedFloat64Array()
	values.resize(STATE_SIZE)
	values[6] = 1.0 # RK4 attitude normalization needs a unit quaternion.
	values[RPM_INDEX] = rpm
	values[CHARGE_INDEX] = charge_c
	return values


func _synthetic_derivative(values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(STATE_SIZE)
	minimum_trial_charge_c = minf(minimum_trial_charge_c, values[CHARGE_INDEX])
	if values[CHARGE_INDEX] < -1e-20:
		saw_negative_charge_trial = true
	elif values[CHARGE_INDEX] < 0.0:
		saw_boundary_left_limit = true
	if values[RPM_INDEX] < 0.0:
		saw_negative_rpm_trial = true

	# The synthetic pack is connected for Q>0 and for negative event-location trials.
	# The ordinary Q=0 branch models the production exhausted-source disconnect.
	if values[CHARGE_INDEX] != 0.0:
		out[CHARGE_INDEX] = -current_a
		out[ENERGY_INDEX] = voltage_v * current_a
		out[HEAT_INDEX] = pack_resistance_ohm * current_a * current_a
	if values[RPM_INDEX] != 0.0:
		out[RPM_INDEX] = -bearing_deceleration_rpm_s
	return out


func _project_rotor(values: PackedFloat64Array, index: int) -> PackedFloat64Array:
	projection_calls += 1
	var out: PackedFloat64Array = values.duplicate()
	out[index] = 0.0
	return out


func _projection_mutates_charge(values: PackedFloat64Array, index: int) -> PackedFloat64Array:
	var out: PackedFloat64Array = values.duplicate()
	out[index] = 0.0
	out[CHARGE_INDEX] += 1.0
	return out


func _run(values: PackedFloat64Array, dt: float, derivative: Callable = Callable(),
		first: PackedFloat64Array = PackedFloat64Array(), project: Callable = Callable()) -> Dictionary:
	var actual_derivative: Callable = derivative if derivative.is_valid() else Callable(self, "_synthetic_derivative")
	var actual_project: Callable = project if project.is_valid() else Callable(self, "_project_rotor")
	return BatteryStep.advance(values, 0.0, dt, actual_derivative, first,
		RPM_INDEX, CHARGE_INDEX, actual_project)


func _event(result: Dictionary, index: int) -> Dictionary:
	return result.events[index] if result.get("ok", false) and result.events.size() > index else {}


func _supply_boundary_api() -> void:
	var pack: Dictionary = {
		"ocv_points": PackedFloat64Array([0.0, 10.0, 0.5, 12.0, 1.0, 14.0]),
		"capacity_ah": 2.0,
		"resistance_ohm": 0.1,
		"auxiliary_current_a": 0.5,
	}
	var motor: Dictionary = {"kv_rpm_per_volt": 600.0, "resistance_ohm": 0.2, "no_load_current_a": 1.0}
	var ordinary: Dictionary = Supply.evaluate(1800.0, 1.0, 0.0, pack, motor)
	var connected: Dictionary = Supply.evaluate_available(1800.0, 1.0, 0.0, pack, motor)
	check("ordinary zero-SOC supply remains exhausted", ordinary.ok and ordinary.mode == "exhausted")
	check("ordinary zero-SOC output disconnects every pack load",
		ordinary.pack_current_a == 0.0 and ordinary.auxiliary_current_a == 0.0
			and ordinary.bus_voltage_v == 0.0)
	check("available zero-SOC branch remains connected", connected.ok and connected.mode == "drive")
	check("available zero-SOC branch supplies motor and auxiliary loads",
		connected.motor_bus_current_a > 0.0 and connected.auxiliary_current_a == 0.5
			and connected.pack_current_a > connected.motor_bus_current_a)
	check("positive-SOC available API is exactly the existing evaluation",
		Supply.evaluate_available(1800.0, 0.5, 0.5, pack, motor)
			== Supply.evaluate(1800.0, 0.5, 0.5, pack, motor))
	check("disabled available source still supplies pack-side auxiliary load",
		Supply.evaluate_available(1800.0, 1.0, 0.0, pack, motor, false).pack_current_a == 0.5)
	check("available API still rejects SOC outside its range",
		not Supply.evaluate_available(1800.0, 1.0, -0.01, pack, motor).ok)


func _constant_current_energy_and_exact_endpoint() -> void:
	current_a = 0.5
	voltage_v = 12.0
	pack_resistance_ohm = 0.1
	bearing_deceleration_rpm_s = 0.0
	_reset_observations()
	var result: Dictionary = _run(_state(0.0, 2.0), 6.0)
	check("constant-current exhaustion succeeds", result.ok)
	if result.ok:
		near("analytic exhaustion time", _event(result, 0).time_s, 4.0, 2e-12)
		near("charge projects exactly to zero", result.state[CHARGE_INDEX], 0.0)
		near("terminal energy integrates only connected time", result.state[ENERGY_INDEX], 24.0, 1e-10)
		near("pack loss integrates only connected time", result.state[HEAT_INDEX], 0.1, 1e-10)
		check("exhaustion event carries bounded charge residual",
			absf(float(_event(result, 0).charge_residual_c)) <= BatteryStep.CHARGE_TOL_C)
		check("exhaustion event carries bounded time bracket",
			float(_event(result, 0).time_error_bound_s) <= BatteryStep.TIME_TOL)
	check("event locator observed negative-Q trial values", saw_negative_charge_trial)
	check("accepted charge did not inherit a negative trial", result.ok and result.state[CHARGE_INDEX] >= 0.0)

	current_a = 1.0
	_reset_observations()
	var endpoint: Dictionary = _run(_state(0.0, 1.0), 1.0)
	check("exact endpoint exhaustion succeeds", endpoint.ok and endpoint.events.size() == 1)
	if endpoint.ok:
		near("exact endpoint event time", _event(endpoint, 0).time_s, 1.0, 1e-14)
		near("exact endpoint charge", endpoint.state[CHARGE_INDEX], 0.0)
		near("exact endpoint terminal energy", endpoint.state[ENERGY_INDEX], 12.0)
	check("exact-zero RK stage uses the connected left-limit query", saw_boundary_left_limit)


func _positive_rpm_coast_after_exhaustion() -> void:
	current_a = 1.0
	voltage_v = 12.0
	pack_resistance_ohm = 0.05
	bearing_deceleration_rpm_s = 100.0
	_reset_observations()
	var result: Dictionary = _run(_state(500.0, 1.0), 6.0)
	check("battery crossing followed by positive-RPM coast succeeds", result.ok)
	if not result.ok:
		return
	check("battery event is first", result.events.size() == 2 and _event(result, 0).type == "battery_exhausted")
	check("rotor stop follows exhaustion", result.events.size() == 2 and _event(result, 1).type == "rotor_stop")
	near("battery event time", _event(result, 0).time_s, 1.0, 2e-12)
	near("bearing coast stop time", _event(result, 1).time_s, 5.0, 2e-12)
	near("rotor remains nonnegative after stop projection", result.state[RPM_INDEX], 0.0)
	near("terminal energy stops at exhaustion", result.state[ENERGY_INDEX], 12.0)
	near("pack loss stops at exhaustion", result.state[HEAT_INDEX], 0.05)
	check("negative RPM trial endpoint was visible to the derivative", saw_negative_rpm_trial)
	check("rotor projection ran during event composition", projection_calls > 0)


func _rotor_before_battery_and_shared_endpoint() -> void:
	current_a = 1.0
	voltage_v = 12.0
	pack_resistance_ohm = 0.0
	bearing_deceleration_rpm_s = 100.0
	_reset_observations()
	var rotor_first: Dictionary = _run(_state(100.0, 2.0), 3.0)
	check("rotor-first event composition succeeds", rotor_first.ok and rotor_first.events.size() == 2)
	if rotor_first.ok:
		check("rotor stop precedes battery event",
			_event(rotor_first, 0).type == "rotor_stop" and _event(rotor_first, 1).type == "battery_exhausted")
		near("rotor-first stop timestamp", _event(rotor_first, 0).time_s, 1.0, 2e-12)
		near("rotor-first battery timestamp", _event(rotor_first, 1).time_s, 2.0, 2e-12)

	_reset_observations()
	var shared: Dictionary = _run(_state(100.0, 1.0), 2.0)
	check("simultaneous battery and rotor events both survive", shared.ok and shared.events.size() == 2)
	if shared.ok:
		check("shared endpoint uses deterministic rotor-first ordering",
			_event(shared, 0).type == "rotor_stop" and _event(shared, 1).type == "battery_exhausted")
		near("shared rotor event timestamp", _event(shared, 0).time_s, 1.0, 2e-12)
		near("shared battery event timestamp", _event(shared, 1).time_s, 1.0, 2e-12)
		check("simultaneous event timestamps are canonicalized",
			_event(shared, 0).time_s == _event(shared, 1).time_s)
		near("shared endpoint terminal energy has no post-event load", shared.state[ENERGY_INDEX], 12.0)


func _starting_exhausted_and_no_event() -> void:
	current_a = 1.0
	voltage_v = 12.0
	pack_resistance_ohm = 0.0
	bearing_deceleration_rpm_s = 100.0
	_reset_observations()
	var exhausted: Dictionary = _run(_state(200.0, 0.0), 3.0)
	check("starting exhausted battery coasts successfully", exhausted.ok)
	if exhausted.ok:
		check("starting exhausted state emits no duplicate battery event",
			exhausted.events.size() == 1 and _event(exhausted, 0).type == "rotor_stop")
		near("starting exhausted charge stays at zero", exhausted.state[CHARGE_INDEX], 0.0)
		near("starting exhausted source adds no terminal energy", exhausted.state[ENERGY_INDEX], 0.0)
		near("starting exhausted bearing stop time", _event(exhausted, 0).time_s, 2.0, 2e-12)

	current_a = 0.0
	bearing_deceleration_rpm_s = 0.0
	_reset_observations()
	var remaining: Dictionary = _run(_state(0.0, 7.0), 0.2)
	check("positive charge with zero draw has no exhaustion event",
		remaining.ok and remaining.events.is_empty() and remaining.state[CHARGE_INDEX] == 7.0)


func _invalid_and_unsupported_trials() -> void:
	current_a = 0.0
	voltage_v = 12.0
	pack_resistance_ohm = 0.0
	bearing_deceleration_rpm_s = 0.0
	var state: PackedFloat64Array = _state(10.0, 1.0)
	var valid_derivative: Callable = Callable(self, "_synthetic_derivative")
	var valid_first: PackedFloat64Array = valid_derivative.call(state, 0.0)
	check("negative initial charge rejected", not BatteryStep.advance(_with_value(state, CHARGE_INDEX, -1.0),
		0.0, 0.1, valid_derivative, valid_first, RPM_INDEX, CHARGE_INDEX,
		Callable(self, "_project_rotor")).ok)
	check("negative initial RPM rejected", not BatteryStep.advance(_with_value(state, RPM_INDEX, -1.0),
		0.0, 0.1, valid_derivative, valid_first, RPM_INDEX, CHARGE_INDEX,
		Callable(self, "_project_rotor")).ok)
	var overlapping: Dictionary = BatteryStep.advance(state, 0.0, 0.1, valid_derivative,
		valid_first, RPM_INDEX, RPM_INDEX, Callable(self, "_project_rotor"))
	var body_charge: Dictionary = BatteryStep.advance(state, 0.0, 0.1, valid_derivative,
		valid_first, RPM_INDEX, 12, Callable(self, "_project_rotor"))
	check("charge index must follow body state and differ from RPM", not overlapping.ok and not body_charge.ok)
	check("short derivative vector rejected", not BatteryStep.advance(state, 0.0, 0.1,
		valid_derivative, PackedFloat64Array([0.0]), RPM_INDEX, CHARGE_INDEX,
		Callable(self, "_project_rotor")).ok)
	for bad_dt: float in [0.0, -0.1, NAN, INF, BatteryStep.MAX_DT_S + 1.0]:
		check("invalid or unbounded dt rejected " + str(bad_dt),
			not BatteryStep.advance(state, 0.0, bad_dt, valid_derivative, valid_first,
				RPM_INDEX, CHARGE_INDEX, Callable(self, "_project_rotor")).ok)
	check("invalid RPM index rejected", not BatteryStep.advance(state, 0.0, 0.1,
		valid_derivative, valid_first, 12, CHARGE_INDEX, Callable(self, "_project_rotor")).ok)

	var positive_charge_rate: Callable = func(values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		var out: PackedFloat64Array = PackedFloat64Array()
		out.resize(values.size())
		out[CHARGE_INDEX] = 0.01
		return out
	check("unsupported positive charge derivative rejected", not BatteryStep.advance(state, 0.0, 0.1,
		positive_charge_rate, positive_charge_rate.call(state, 0.0), RPM_INDEX, CHARGE_INDEX,
		Callable(self, "_project_rotor")).ok)

	var malformed: Callable = func(_values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0])
	check("malformed derivative rejected", not BatteryStep.advance(state, 0.0, 0.1,
		malformed, PackedFloat64Array(), RPM_INDEX, CHARGE_INDEX,
		Callable(self, "_project_rotor")).ok)

	var nonfinite: Callable = func(values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		var out: PackedFloat64Array = PackedFloat64Array()
		out.resize(values.size())
		out[RPM_INDEX] = NAN
		return out
	check("nonfinite derivative rejected", not BatteryStep.advance(state, 0.0, 0.1,
		nonfinite, PackedFloat64Array(), RPM_INDEX, CHARGE_INDEX,
		Callable(self, "_project_rotor")).ok)
	bearing_deceleration_rpm_s = 100.0
	var projection_state: PackedFloat64Array = _state(1.0, 1.0)
	var projection_first: PackedFloat64Array = valid_derivative.call(projection_state, 0.0)
	check("rotor projection that changes charge rejected", not BatteryStep.advance(projection_state, 0.0, 0.1,
		valid_derivative, projection_first, RPM_INDEX, CHARGE_INDEX,
		Callable(self, "_projection_mutates_charge")).ok)

	var reverse: Callable = func(values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		var out: PackedFloat64Array = PackedFloat64Array()
		out.resize(values.size())
		if values[RPM_INDEX] == 0.0:
			out[RPM_INDEX] = -1.0
		return out
	var stopped: PackedFloat64Array = _state(0.0, 1.0)
	check("unsupported reverse departure fails boundedly", not BatteryStep.advance(stopped, 0.0, 0.01,
		reverse, reverse.call(stopped, 0.0), RPM_INDEX, CHARGE_INDEX,
		Callable(self, "_project_rotor")).ok)

	var exhausted_reverse: Callable = func(values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		var out: PackedFloat64Array = PackedFloat64Array()
		out.resize(values.size())
		out[CHARGE_INDEX] = -0.1
		return out
	var empty: PackedFloat64Array = _state(1.0, 0.0)
	check("exhausted source cannot continue consuming charge", not BatteryStep.advance(empty, 0.0, 0.1,
		exhausted_reverse, PackedFloat64Array(), RPM_INDEX, CHARGE_INDEX,
		Callable(self, "_project_rotor")).ok)


static func _with_value(values: PackedFloat64Array, index: int, value: float) -> PackedFloat64Array:
	var out: PackedFloat64Array = values.duplicate()
	out[index] = value
	return out
