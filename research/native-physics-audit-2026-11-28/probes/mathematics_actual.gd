# Standalone Godot witness against the application's actual authored-data loader, coupled stage and RK4.
# All checks describe the inspected baseline. A repaired baseline should invalidate the defect checks.
extends SceneTree

const Fixture := preload("res://tests/test_airship_dynamics.gd")
const Data := preload("res://physics/airship/airship_data.gd")
const Dynamics := preload("res://physics/airship/airship_dynamics.gd")
const RK := preload("res://physics/integrator.gd")
const RHO := 1.225
const GRAVITY := 9.80665

var checks := 0
var failures := 0
var records: Dictionary = {}


func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("MATH_ACTUAL_FAIL " + label)


func _model(label: String, raw: Dictionary, heaviness: float) -> Dictionary:
	var loaded := Data.load_document(raw, label)
	_check(label + " authoring document accepted", loaded.ok)
	if not loaded.ok:
		print(label, " load errors ", loaded.errors)
		return {}
	var derived := Data.derive(loaded.data, RHO, GRAVITY, heaviness)
	_check(label + " model admitted", derived.ok)
	if not derived.ok:
		print(label, " derive errors ", derived.errors)
		return {}
	return derived.model


func _body(down: float, downward_speed: float) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, down, 0.0, 0.0, downward_speed, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


func _continuous(soc: float, axial_speed: float = 0.0) -> PackedFloat64Array:
	var state := PackedFloat64Array()
	state.resize(Data.CONTINUOUS_SIZE)
	state[Data.MOTOR] = axial_speed
	state[Data.MOTOR + 1] = axial_speed
	state[Data.MOTOR + 2] = 0.7 * axial_speed
	state[Data.SOC] = soc
	return state


func _rhs(model: Dictionary, inputs: PackedFloat64Array, ground: Callable) -> Callable:
	var wind := PackedFloat64Array([0.0, 0.0, 0.0])
	return func(state: PackedFloat64Array, _time: float) -> PackedFloat64Array:
		var stage := Dynamics.stage(model, state.slice(0, 13), state.slice(13), inputs, wind, ground)
		var rates: PackedFloat64Array = stage.body_derivative
		rates.append_array(stage.derivative)
		return rates


func _battery(stock_raw: Dictionary) -> void:
	var stock_model := _model("stock blimp", stock_raw, 0.08)
	var limited_raw := stock_raw.duplicate(true)
	limited_raw.battery.cutoff_cell_voltage.value = 3.2
	limited_raw.battery.initial_soc.value = 0.05
	var model := _model("altered cutoff and initial charge", limited_raw, 0.08)
	if model.is_empty() or stock_model.is_empty():
		return
	var inputs := PackedFloat64Array([0.0, 0.0, 0.0, 1.0])
	var wind := PackedFloat64Array([0.0, 0.0, 0.0])
	var body := _body(-10.0, 0.0)
	var stock := Dynamics.evaluate(stock_model, body, _continuous(0.0), inputs, wind, Callable(), true)
	var at_rest := Dynamics.evaluate(model, body, _continuous(0.0), inputs, wind, Callable(), true)
	var equilibrium_speed := 0.38936031926911396  # Independent equilibrium from the charge-law oracle.
	var equilibrium := Dynamics.evaluate(model, body, _continuous(0.0, equilibrium_speed), inputs, wind, Callable(), true)
	var total_thrust := 0.0
	for thrust: float in equilibrium.info.thrust_n:
		total_thrust += thrust
	var stock_acceleration: float = stock.derivative[Data.MOTOR]
	var current: float = equilibrium.info.battery.current_a
	var power: float = equilibrium.info.battery.power_w
	_check("stock empty stopped rotor current and drive vanish", absf(stock_acceleration) < 1e-10 and absf(stock.info.battery.current_a) < 1e-10)
	_check("empty authored pack starts stopped motors", at_rest.derivative[Data.MOTOR] > 1.0)
	_check("empty equilibrium supplies power at frozen SOC", absf(current - 0.46572584578561627) < 1e-8 and absf(power - 4.600925347923128) < 1e-8 and equilibrium.derivative[Data.SOC] == 0.0)
	_check("empty equilibrium matches independent thrust and is stationary", absf(total_thrust - 0.9071831259965366) < 1e-8 and absf(equilibrium.derivative[Data.MOTOR]) < 1e-8)
	var joined := body.duplicate()
	joined.append_array(_continuous(1e-8, equilibrium_speed))
	var rhs := _rhs(model, inputs, Callable())
	var next := RK.rk4_step_at(joined, 0.0, 1.0 / 240.0, rhs)
	var after := Dynamics.evaluate(model, next.slice(0, 13), next.slice(13), inputs, wind, Callable(), true)
	_check("one coupled tick crosses below zero and current persists", next[13 + Data.SOC] < 0.0 and after.info.battery.current_a > 0.46 and after.derivative[Data.SOC] == 0.0)
	records.battery = {stock_rest_acceleration = stock_acceleration, stock_rest_current_a = stock.info.battery.current_a,
		custom_rest_acceleration = at_rest.derivative[Data.MOTOR], equilibrium_current_a = current,
		equilibrium_power_w = power, equilibrium_thrust_n = total_thrust, one_tick_soc = next[13 + Data.SOC],
		current_after_crossing_a = after.info.battery.current_a}


func _shape(label: String, raw: Dictionary, case: String) -> void:
	var loaded := Data.load_document(raw, label)
	_check(label + " authoring document accepted", loaded.ok)
	if not loaded.ok:
		return
	var derived := Data.derive(loaded.data, RHO, GRAVITY, 0.0)
	var a := 0.5 * float(loaded.data.envelope.length)
	var volume: float = loaded.data.envelope.volume
	var b := sqrt(3.0 * volume / (4.0 * PI * a))
	var coeff := Data.spheroid_coefficients(a, b)
	var row := {a = a, b = b, k1 = coeff.k1, k2 = coeff.k2, k_rot = coeff.k_rot, model_admitted = derived.ok, errors = derived.errors}
	if derived.ok:
		row.model_k1 = float(derived.model.m_a[0]) / (RHO * volume)
	var k1: float = coeff.k1
	var k2: float = coeff.k2
	match case:
		"stock":
			_check(label + " elongated-hull control", derived.ok and absf(k1 - 0.05719486485590408) < 1e-10 and absf(k2 - 0.8973521321473499) < 1e-10)
		"moderate":
			_check(label + " well-conditioned sphere control", derived.ok and absf(k1 - 0.5) < 0.001 and absf(k2 - 0.5) < 0.001)
		"biased":
			_check(label + " admitted model violates sphere limit", derived.ok and absf(k1 - 0.49999999994) > 0.005 and absf(float(row.get("model_k1", 1e6)) - k1) < 1e-9)
		"negative":
			_check(label + " negative added-fluid translation", k1 < 0.0 or k2 < 0.0)
	records[label] = row


func _flat(_north: float, _east: float) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0])


func _contact_model(stiffness: float) -> Dictionary:
	var raw := Fixture.fixture(2.0, 1.0, {hull_scale = 0.0, fin_am = 0.0})
	raw.contacts.gear[0].point.value = [0.0, 0.0, 0.7]
	raw.contacts.gear[0].stiffness.value = stiffness
	raw.contacts.gear[0].damping.value = 0.0
	var model := _model("centered undamped gear %.0f N/m" % stiffness, raw, 0.0)
	if not model.is_empty():
		model.ground_ceiling = 0.0
		_check("neutral heave mass at %.0f N/m" % stiffness, absf(float(model.mass) - RHO * PI / 3.0) < 1e-10)
	return model


func _rebound(model: Dictionary, hz: int) -> float:
	var state := _body(-0.7, 1.0)
	state.append_array(_continuous(1.0))
	var dt := 1.0 / hz
	var rhs := _rhs(model, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), _flat)
	for i in ceili(0.3 * hz):
		state = RK.rk4_step_at(state, dt * i, dt, rhs)
		if state[2] < -0.7 and state[5] < 0.0:
			return -state[5]
	return -1.0


func _contact() -> void:
	var stiff := _contact_model(1000000.0)
	var soft := _contact_model(400.0)
	if stiff.is_empty() or soft.is_empty():
		return
	var rates: Array[int] = [120, 240, 480, 3840]
	var references: Array[float] = [17.04478, 3.51119, 0.83139, 0.99992]
	var result: Dictionary = {}
	for i in rates.size():
		var speed := _rebound(stiff, rates[i])
		result[str(rates[i])] = {rebound_m_s = speed, energy_ratio = speed * speed}
		_check("stiff coupled rebound matches independent header at %d Hz" % rates[i], absf(speed - references[i]) < 1e-5)
	var soft_speed := _rebound(soft, 240)
	_check("resolved compliant control preserves analytic 1 m/s rebound", absf(soft_speed - 1.0) < 0.001)
	result.soft_240_m_s = soft_speed
	result.exact_speed_m_s = 1.0
	records.contact = result


func _initialize() -> void:
	var stock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/airships/rc-blimp-5m.json"))
	_battery(stock)
	_shape("stock_shape", stock, "stock")
	_shape("shape_1e_4", Fixture.fixture(2.0, 2.0 * (1.0 - 1e-4)), "moderate")
	_shape("shape_1e_10", Fixture.fixture(2.0, 2.0 * (1.0 - 1e-10)), "biased")
	_shape("shape_1e_12", Fixture.fixture(2.0, 2.0 * (1.0 - 1e-12)), "negative")
	_contact()
	print("MATH_ACTUAL_JSON ", JSON.stringify(records, "", true, true))
	print("MATH_ACTUAL_CHECKS %d/%d" % [checks - failures, checks])
	if failures == 0:
		print("MATH_ACTUAL_OK")
	quit(1 if failures > 0 else 0)
