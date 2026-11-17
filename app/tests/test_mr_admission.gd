# DR-10/18 (FPV audit 2026-11-16, A08, A09): physical admission. The loader solves hover on the LOADED shared pack
# (an impossible custom pack is refused with the power it needs and can deliver), and a prepared in-memory document
# meets the same physical bounds as the strict loader, refused transactionally. Expected values are independent: the
# Thevenin power bound Voc^2/(4R) and the audit's 77.37 W hover power; the plant's own bus evaluated at the solved
# operating point. Software checks on estimated data: no physical pack or ESC validation.
extends SceneTree

const MD := preload("res://physics/multirotor_data.gd")
const Session := preload("res://sim/multirotor/session.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Catalog := preload("res://vehicles/multirotor/multirotor_catalog.gd")
## The audit's independent hover power at the motor terminals (repros/physics.gd).
const AUDIT_POWER_W := 77.365259

var _count := 0
var _failures := 0
var _raw: Dictionary = {}
var _prepared: Dictionary = {}
var _field: Dictionary = {}


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var loaded: Dictionary = MD.load_file(Catalog.DATA_PATH)
	_check("shipped document admits", loaded.ok, str(loaded.errors))
	var made: Dictionary = MD.prepare(loaded.data, loaded.sha256) if loaded.ok else {ok = false}
	_check("shipped document prepares", made.ok)
	_field = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	if made.ok:
		_raw = loaded.data
		_prepared = made.prepared
		_check("the loader's friction speed is the plant's", MD.FRICTION_SPEED == Plant.FRICTION_SPEED)
		_shipped_operating_point()
		_loaded_pack()
		_prepared_parity()
		_transaction()
	print("multirotor admission: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _hit(errors: PackedStringArray, needle: String) -> bool:
	for error: String in errors:
		if needle in error:
			return true
	return false


func _thrusts() -> PackedFloat64Array:
	return PackedFloat64Array(_raw.provenance.derived_diagnostics.hover_thrusts_n)


func _low_voc() -> float:
	var ocv: PackedFloat64Array = _prepared.battery.ocv_points
	for i in range(0, ocv.size(), 2):
		if ocv[i] > MD.LOW_CHARGE_SOC:
			return ocv[i + 1]
	return NAN


func _admit(mutate: Callable) -> Dictionary:
	var copy: Dictionary = _raw.duplicate(true)
	mutate.call(copy)
	return MD.load_document(copy, "mutated")


## A08 positive control: the shipped document's loaded operating point matches the audit power and the plant's bus.
func _shipped_operating_point() -> void:
	var voc := _low_voc()
	var s: Dictionary = MD.hover_bus_solution(_prepared.powertrain, _prepared.battery, _prepared.rotor_law.thrust_coefficient_n_s2,
		_prepared.rotor_law.torque_coefficient_n_m_s2, _thrusts(), voc)
	_check("shipped hover closes on the loaded pack at the screening point", s.ok, str(s.get("message", "")))
	if not s.ok:
		return
	_check("hover power at the motor terminals equals the audit's independent 77.365 W", absf(s.power_w - AUDIT_POWER_W) < 1.0e-3,
		"%.6f W" % s.power_w)
	_check("the high-voltage root: a small sag under the load, duties far below max_command",
		s.v_bus_v < voc and s.v_bus_v > voc - 1.0 and s.duties[0] < 0.3 and s.duties[1] < 0.3, "%.4f V %s" % [s.v_bus_v, s.duties])
	var made: Dictionary = Plant.create(_prepared, Rates.default_profile(), FC.THROTTLE_ABSOLUTE)
	if not made.ok:
		_check("plant for the cross-check", false)
		return
	var p: RefCounted = made.plant
	var body := RB.make_state(M.v3(0.0, 0.0, -20.0), M.v3(0.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))
	var soc := 0.0
	var ocv: PackedFloat64Array = _prepared.battery.ocv_points
	for i in range(0, ocv.size(), 2):
		if ocv[i] > MD.LOW_CHARGE_SOC:
			soc = ocv[i]
			break
	var frame: Dictionary = p.initial_frame(body, 0, soc)
	_check("the plant's open-circuit voltage at that charge is the screening voltage", absf(p.supply_voltage(frame.continuous) - voc) < 1.0e-9)
	for i in 4:
		frame.continuous[i] = s.speeds_rad_s[i]
		frame.aux[FC.AUX_COMMAND + i] = s.duties[i]
	frame.modes[FC.MODE_MOTOR] = FC.MOTOR_ARMED
	var ev: Dictionary = p._evaluate(frame.body, frame.continuous, 0.0, frame.aux, frame.modes)
	_check("the plant's own bus agrees at the solved point (voltage, pack and motor current)", ev.bus.ok
		and absf(ev.bus.v_bus - s.v_bus_v) < 1.0e-9 and absf(ev.bus.i_pack - s.pack_current_a) < 1.0e-9
		and absf(ev.bus.i_motor[0] - s.currents_a[0]) < 1.0e-9, "%s V" % ev.bus.get("v_bus", NAN))
	var weight := float(_prepared.mass_kg) * 9.80665
	_check("the plant holds the shafts and the weight there", absf(ev.derivative[0]) < 1.0e-6 and absf(ev.derivative[1]) < 1.0e-6
		and absf(ev.loads[2] + weight) < 1.0e-9, "%s %s" % [ev.derivative[0], ev.loads[2] + weight])


## A08: a pack that cannot deliver the hover power is refused with an explanation; boundaries and Rp = 0 behave.
func _loaded_pack() -> void:
	var voc := _low_voc()
	var aux := float(_prepared.battery.auxiliary_current_a)
	var ten := _admit(func(d: Dictionary) -> void: d.battery.resistance.value = 10.0)
	var bound := (voc - 10.0 * aux) * (voc - 10.0 * aux) / 40.0
	_check("audit A08: the 10 ohm pack is refused, naming the loaded pack (bound %.2f W < 77.37 W)" % bound,
		not ten.ok and _hit(ten.errors, "loaded pack cannot carry"), str(ten.errors))
	var two := _admit(func(d: Dictionary) -> void: d.battery.resistance.value = 2.0)
	_check("a 2 ohm pack is refused too", not two.ok and _hit(two.errors, "loaded pack cannot carry"))
	var one := _admit(func(d: Dictionary) -> void: d.battery.resistance.value = 1.0)
	_check("a 1 ohm pack (sagging but able) is admitted", one.ok, str(one.errors))
	var zero := _admit(func(d: Dictionary) -> void: d.battery.resistance.value = 0.0)
	_check("a zero-resistance pack is admitted", zero.ok, str(zero.errors))
	if zero.ok:
		var prepared: Dictionary = MD.prepare(zero.data, zero.sha256).prepared
		var s: Dictionary = MD.hover_bus_solution(prepared.powertrain, prepared.battery, prepared.rotor_law.thrust_coefficient_n_s2,
			prepared.rotor_law.torque_coefficient_n_m_s2, _thrusts(), voc)
		_check("Rp = 0: the bus is exactly the open-circuit voltage", s.ok and s.v_bus_v == voc)
	var limited := _admit(func(d: Dictionary) -> void:
		d.powertrain.max_command.value = 0.3
		d.battery.resistance.value = 1.3)
	_check("a duty above max_command on the sagging bus is refused (open-circuit screening would pass)",
		not limited.ok and _hit(limited.errors, "needs duty"), str(limited.errors))


func _with(values: PackedFloat64Array, index: int, value: float) -> PackedFloat64Array:
	var out := values.duplicate()
	out[index] = value
	return out


## A09: raw and prepared admission refuse the same physical violations.
func _prepared_parity() -> void:
	_check("the shipped prepared document meets the invariants", MD.physical_invariant_errors(_prepared).is_empty(),
		str(MD.physical_invariant_errors(_prepared)))
	_check("the electric and lab fixtures meet the invariants", MD.physical_invariant_errors(Fixtures.electric()).is_empty()
		and MD.physical_invariant_errors(Fixtures.lab()).is_empty(),
		str(MD.physical_invariant_errors(Fixtures.electric())) + str(MD.physical_invariant_errors(Fixtures.lab())))
	var cases: Array = [
		["negative airframe drag", func(d: Dictionary) -> void: d.airframe.drag_areas.value[0] = -1.0,
			func(m: Dictionary) -> void: m.airframe.drag_areas_m2 = _with(m.airframe.drag_areas_m2, 0, -1.0)],
		["negative pack resistance", func(d: Dictionary) -> void: d.battery.resistance.value = -0.01,
			func(m: Dictionary) -> void: m.battery.resistance_ohm = -0.01],
		["negative auxiliary current", func(d: Dictionary) -> void: d.battery.auxiliary_current.value = -0.1,
			func(m: Dictionary) -> void: m.battery.auxiliary_current_a = -0.1],
		["negative contact friction", func(d: Dictionary) -> void: d.contacts.friction.value = -0.1,
			func(m: Dictionary) -> void: m.contacts.friction = -0.1],
		["the same spin on three rotors", func(d: Dictionary) -> void: d.rotors[0].spin = -int(d.rotors[0].spin),
			func(m: Dictionary) -> void: m.rotors[0].spin = -float(m.rotors[0].spin)],
	]
	for item: Array in cases:
		var raw_result := _admit(item[1])
		var copy: Dictionary = _prepared.duplicate(true)
		item[2].call(copy)
		var prepared_errors := MD.physical_invariant_errors(copy)
		_check("parity, %s: the loader and the prepared invariants both refuse" % item[0], not raw_result.ok and not prepared_errors.is_empty(),
			"%s | %s" % [raw_result.errors, prepared_errors])
	var mass := _prepared.duplicate(true)
	mass.mass_kg = -0.5
	_check("a nonpositive mass is refused", _hit(MD.physical_invariant_errors(mass), "mass_kg"))
	var inertia := _prepared.duplicate(true)
	inertia.inertia_kg_m2 = _with(inertia.inertia_kg_m2, 0, -1.0e-3)
	_check("a negative inertia is refused", _hit(MD.physical_invariant_errors(inertia), "positive definite"))
	var weak := _prepared.duplicate(true)
	weak.battery.resistance_ohm = 10.0
	_check("the impossible pack is refused on the prepared path too", _hit(MD.physical_invariant_errors(weak), "loaded pack cannot carry"))


## A09: the audit's negative prepared drag is refused by the session without touching an accepted flight.
func _transaction() -> void:
	var s: Node = Session.new()
	root.add_child(s)
	var options := {prepared_data = _prepared.duplicate(true), start = "air", altitude_m = 20.0}
	_check("the session accepts the shipped prepared document", s.prepare(_field, options), str(s.load_error))
	s.resume()
	var flown := true
	for i in 10:
		flown = flown and s.tick_once(FC.neutral_input())
	var frame := var_to_bytes(s.frame())
	var tape: PackedFloat64Array = s.tape()
	var bad: Dictionary = _prepared.duplicate(true)
	bad.airframe.drag_areas_m2 = PackedFloat64Array([-1.0, 0.012, 0.020])
	var refused: bool = not s.prepare(_field, {prepared_data = bad, start = "air", altitude_m = 20.0})
	_check("audit A09: negative prepared drag is refused with its field path", refused
		and "airframe.drag_areas_m2[0]" in str(s.load_error), str(s.load_error).left(160))
	_check("the refusal leaves the accepted flight untouched and flying", flown and s.prepared and var_to_bytes(s.frame()) == frame
		and s.tape() == tape and s.tick_once(FC.neutral_input()))
	s.free()
