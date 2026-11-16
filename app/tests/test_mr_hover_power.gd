# DR-05/10 loaded-hover and raw/prepared power admission regressions.
# Oracles are invented constants and independent hand calculations, not measurements of a real drone.
extends SceneTree

const Hover := preload("res://physics/multirotor/hover_power.gd")
const Bus := preload("res://physics/multirotor/electric_bus.gd")
const Data := preload("res://physics/multirotor_data.gd")
const Session := preload("res://sim/multirotor/session.gd")
const DATA_PATH := "res://data/multirotors/openrc-fpv5-x1.json"

var _count := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_equal_low_speed_oracle()
	_asymmetric_oracle()
	_power_limit()
	_polarization_and_auxiliary()
	_limits_and_invalid_inputs()
	_high_speed_friction()
	_raw_and_prepared_admission()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _close(a: float, b: float, tolerance: float = 1.0e-10) -> bool:
	return is_finite(a) and is_finite(b) and absf(a - b) <= tolerance


func _base() -> Dictionary:
	return {
		rotor_law = {thrust_coefficient_n_s2 = 1.0, torque_coefficient_n_m_s2 = 1.0e-4,
			max_speed_rad_s = 100.0},
		powertrain = {law = "el-one-quadrant-bus-v1", braking = "none", kv_rad_s_per_v = 10.0,
			resistance_ohm = 0.1, no_load_current_a = 2.0, idle_command = 0.0, max_command = 0.9},
		battery = {resistance_ohm = 0.1, auxiliary_current_a = 0.1},
	}


func _equal_thrusts() -> PackedFloat64Array:
	# kT = 1 and thrust = 225 N, so the four required speeds are 15 rad/s.
	return PackedFloat64Array([225.0, 225.0, 225.0, 225.0])


func _equal_low_speed_oracle() -> void:
	var data := _base()
	var before: PackedByteArray = var_to_bytes(data)
	var result: Dictionary = Hover.solve(data, _equal_thrusts(), 12.0)
	_check("15 rad/s regularized-friction point is admitted", result.ok, str(result.message))
	_check("the solver does not mutate normalized data", before == var_to_bytes(data))
	if not result.ok:
		return
	# I = 10*0.0001*15² + 2*(15/30) = 1.225 A per motor.
	# U = 15/10 + 0.1*1.225 = 1.6225 V; sum(U*I) = 7.95025 W.
	# A = 12 - 0.1*0.1 = 11.99 V; discriminant = 140.58 V².
	_check("chooses high-voltage root, 11.923321853610851 V and 0.7667814638914869 A",
		_close(result.v_bus, 11.923321853610851) and _close(result.i_pack, 0.7667814638914869)
		and result.v_bus > 11.99 / 2.0)
	var all_ok := true
	for i in 4:
		all_ok = all_ok and _close(result.speeds[i], 15.0) and _close(result.currents[i], 1.225) \
			and _close(result.duty[i], 0.13607784977377282)
	_check("every motor has the expected speed, regularized current and duty", all_ok)
	# Independently ask the running one-quadrant bus law to solve the returned duty at the same frozen shaft speeds.
	var bus: Dictionary = Bus.solve(12.0, 0.1, 0.1, result.duty, PackedFloat64Array([1.5, 1.5, 1.5, 1.5]),
		PackedFloat64Array([0.1, 0.1, 0.1, 0.1]), PackedInt64Array([1, 1, 1, 1]))
	var bus_ok: bool = bus.ok and _close(bus.v_bus, result.v_bus) and _close(bus.i_pack, result.i_pack)
	if bus.ok:
		for i in 4:
			bus_ok = bus_ok and _close(bus.i_motor[i], result.currents[i])
	_check("returned point agrees with the production active-set bus", bus_ok, str(bus.get("message", "")))
	data.powertrain.braking = "damped_nonregenerative"
	var damped: Dictionary = Hover.solve(data, _equal_thrusts(), 12.0)
	_check("the non-regenerative bridge has the same all-positive-current hover solution", damped.ok \
		and _close(damped.v_bus, result.v_bus) and damped.duty == result.duty and damped.currents == result.currents)


func _asymmetric() -> Dictionary:
	var data := _base()
	data.rotor_law.torque_coefficient_n_m_s2 = 0.01
	data.rotor_law.max_speed_rad_s = 10.0
	data.powertrain.no_load_current_a = 0.0
	data.powertrain.max_command = 1.0
	data.battery.resistance_ohm = 0.0
	data.battery.auxiliary_current_a = 0.2
	return data


func _asymmetric_thrusts() -> PackedFloat64Array:
	return PackedFloat64Array([1.0, 4.0, 9.0, 16.0])


func _asymmetric_oracle() -> void:
	var result: Dictionary = Hover.solve(_asymmetric(), _asymmetric_thrusts(), 10.0)
	_check("unequal four-rotor hover with Rpack=0 admits", result.ok, str(result.message))
	if not result.ok:
		return
	# Hand calculation: w = [1,2,3,4], I = 0.1*w² = [0.1,0.4,0.9,1.6].
	# Motor terminal voltages are [0.11,0.24,0.39,0.56] V and P = 1.354 W; pack I = 0.2 + 1.354/10.
	var expected_speeds := PackedFloat64Array([1.0, 2.0, 3.0, 4.0])
	var expected_currents := PackedFloat64Array([0.1, 0.4, 0.9, 1.6])
	var expected_duties := PackedFloat64Array([0.011, 0.024, 0.039, 0.056])
	var all_ok := true
	for i in 4:
		all_ok = all_ok and _close(result.speeds[i], expected_speeds[i]) \
			and _close(result.currents[i], expected_currents[i]) and _close(result.duty[i], expected_duties[i])
	_check("unequal motors retain their individual currents and commands", all_ok)
	_check("zero-resistance branch gives 10 V and 0.3354 A", _close(result.v_bus, 10.0) \
		and _close(result.i_pack, 0.3354))


func _fold_fixture() -> Dictionary:
	var data := _base()
	data.rotor_law.torque_coefficient_n_m_s2 = 0.5
	data.rotor_law.max_speed_rad_s = 3.0
	data.powertrain.kv_rad_s_per_v = 2.0
	data.powertrain.resistance_ohm = 0.5
	data.powertrain.no_load_current_a = 0.0
	data.battery.resistance_ohm = 1.0
	data.battery.auxiliary_current_a = 0.0
	return data


func _power_limit() -> void:
	# At w=1: each current=1 A, motor voltage=1 V; total P=4 W. Rp=1 and Voc=4 give exactly Δ=0.
	var data := _fold_fixture()
	var thrusts := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
	var fold: Dictionary = Hover.solve(data, thrusts, 4.0)
	_check("exact maximum-power fold is explicitly refused for zero margin", not fold.ok \
		and str(fold.message).contains("zero-margin"), str(fold.message))
	var below: Dictionary = Hover.solve(data, thrusts, 4.0 - 1.0e-8)
	_check("a pack below the power bound is refused", not below.ok \
		and str(below.message).contains("cannot supply"), str(below.message))
	var above: Dictionary = Hover.solve(data, thrusts, 4.0 + 1.0e-8)
	_check("a finite point just above the fold admits on the high-voltage branch", above.ok \
		and above.v_bus > (4.0 + 1.0e-8) / 2.0, str(above.message))


func _polarization_and_auxiliary() -> void:
	var data := _base()
	var original: Dictionary = Hover.solve(data, _equal_thrusts(), 12.0)
	var split := _base()
	split.battery.resistance_ohm = 0.06
	split.battery.polarization_resistance_ohm = 0.04
	split.battery.polarization_time_s = 1.0
	var same_total: Dictionary = Hover.solve(split, _equal_thrusts(), 12.0)
	_check("steady R0 + R1 equals the old unsplit resistance", original.ok and same_total.ok \
		and _close(original.v_bus, same_total.v_bus) and _close(original.i_pack, same_total.i_pack))
	var slower := split.duplicate(true)
	slower.battery.polarization_time_s = 8.0
	var same_steady: Dictionary = Hover.solve(slower, _equal_thrusts(), 12.0)
	_check("polarization time does not alter the settled frozen-SOC operating point", same_steady.ok \
		and _close(same_steady.v_bus, same_total.v_bus))
	var higher := _base()
	higher.battery.polarization_resistance_ohm = 0.2
	higher.battery.polarization_time_s = 1.0
	var sagged: Dictionary = Hover.solve(higher, _equal_thrusts(), 12.0)
	_check("additional polarization resistance increases steady hover sag", sagged.ok and original.ok \
		and sagged.v_bus < original.v_bus and sagged.duty[0] > original.duty[0])
	var aux := _base()
	aux.battery.auxiliary_current_a = 1.0
	var auxiliary: Dictionary = Hover.solve(aux, _equal_thrusts(), 12.0)
	_check("auxiliary load lowers the loaded bus and raises motor duty", auxiliary.ok and original.ok \
		and auxiliary.v_bus < original.v_bus and auxiliary.duty[0] > original.duty[0])
	aux.battery.auxiliary_current_a = 200.0
	var impossible: Dictionary = Hover.solve(aux, _equal_thrusts(), 12.0)
	_check("an auxiliary load that consumes the whole bus is refused", not impossible.ok \
		and str(impossible.message).contains("auxiliary load"), str(impossible.message))


func _limits_and_invalid_inputs() -> void:
	var data := _asymmetric()
	data.powertrain.max_command = 0.05
	var high: Dictionary = Hover.solve(data, _asymmetric_thrusts(), 10.0)
	_check("adequate total power cannot hide rotor 4 exceeding maximum duty", not high.ok \
		and str(high.message).contains("rotor 4 duty"), str(high.message))
	data = _asymmetric()
	data.powertrain.idle_command = 0.02
	var low: Dictionary = Hover.solve(data, _asymmetric_thrusts(), 10.0)
	_check("individual rotor duty must exceed idle", not low.ok and str(low.message).contains("rotor 1 duty"), str(low.message))
	data = _asymmetric()
	data.rotor_law.max_speed_rad_s = 3.5
	var fast: Dictionary = Hover.solve(data, _asymmetric_thrusts(), 10.0)
	_check("individual rotor speed must respect its declared limit", not fast.ok \
		and str(fast.message).contains("rotor 4 speed"), str(fast.message))
	data = _asymmetric()
	data.rotor_law.max_speed_rad_s = 4.0
	var exact: Dictionary = Hover.solve(data, _asymmetric_thrusts(), 10.0)
	_check("declared speed limit is inclusive", exact.ok, str(exact.message))
	var bad_thrusts := PackedFloat64Array([1.0, 4.0, NAN, 16.0])
	var invalid: Dictionary = Hover.solve(_asymmetric(), bad_thrusts, 10.0)
	_check("nonfinite thrust is refused without a partial solution", not invalid.ok and invalid.duty.is_empty())
	data = _base()
	data.battery.polarization_resistance_ohm = -0.01
	invalid = Hover.solve(data, _equal_thrusts(), 12.0)
	_check("negative polarization resistance is refused", not invalid.ok \
		and str(invalid.message).contains("polarization_resistance"), str(invalid.message))
	data = _base()
	data.powertrain.no_load_current_a = -1.0
	invalid = Hover.solve(data, _equal_thrusts(), 12.0)
	_check("negative no-load current is refused", not invalid.ok, str(invalid.message))
	data = _base()
	data.powertrain.braking = "typo"
	invalid = Hover.solve(data, _equal_thrusts(), 12.0)
	_check("unsupported braking is refused instead of silently changed", not invalid.ok, str(invalid.message))
	data = _base()
	data.battery.resistance_ohm = "0.1"
	invalid = Hover.solve(data, _equal_thrusts(), 12.0)
	_check("a string that looks like resistance is refused", not invalid.ok, str(invalid.message))


func _high_speed_friction() -> void:
	var thrusts := PackedFloat64Array([2025.0, 2025.0, 2025.0, 2025.0]) # w = 45 rad/s
	var result: Dictionary = Hover.solve(_base(), thrusts, 12.0)
	# Above 30 rad/s the friction factor is exactly 1, so I = 10*0.0001*45² + 2 = 4.025 A.
	_check("friction saturates at I0 above 30 rad/s", result.ok and _close(result.currents[0], 4.025), str(result.message))


# Raw source and prepared/session admission must refuse the same battery and power defects. Raw documents still
# have the quantity/provenance layer; a prepared dictionary intentionally does not contain the mass inventory.
func _quantity(value: float, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "estimated", source = "estimated: admission test fixture"}


func _raw_pack(data: Dictionary, r0: float, r1: float, auxiliary: float) -> void:
	data.battery.resistance.value = r0
	data.battery.polarization_resistance.value = r1
	data.battery.auxiliary_current.value = auxiliary


func _prepared_pack(data: Dictionary, r0: float, r1: float, auxiliary: float) -> void:
	data.battery.resistance_ohm = r0
	data.battery.polarization_resistance_ohm = r1
	data.battery.auxiliary_current_a = auxiliary


func _stiff_raw(data: Dictionary) -> void:
	_raw_pack(data, 0.0, 1.0, 0.6)
	data.battery.polarization_time.value = 0.02


func _stiff_prepared(data: Dictionary) -> void:
	_prepared_pack(data, 0.0, 1.0, 0.6)
	data.battery.polarization_time_s = 0.02


func _prepared_bad_soc_order(data: Dictionary) -> void:
	var points: PackedFloat64Array = data.battery.ocv_points.duplicate()
	points[2] = points[0]
	data.battery.ocv_points = points


func _prepared_bad_cell_voltage(data: Dictionary) -> void:
	var points: PackedFloat64Array = data.battery.ocv_points.duplicate()
	points[1] = 1.0
	data.battery.ocv_points = points


func _snapshot(session: Node) -> PackedByteArray:
	return var_to_bytes([session.sim.state, session.sim.continuous, session.sim.aux, session.sim.modes,
		session.sim.tick, session.tape(), session.identity(), session.paused])


func _raw_and_prepared_admission() -> void:
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(decoded) != TYPE_DICTIONARY:
		_check("read the generated source for raw/prepared admission checks", false)
		return
	var raw: Dictionary = decoded
	# Set explicit, estimated RC constants so the test also works if run against a historical R-only JSON.
	# The old 0.03-ohm steady resistance is split without touching any OCV-only generator diagnostics.
	raw.powertrain.braking = "none"
	raw.battery.resistance.value = 0.02
	raw.battery.polarization_resistance = _quantity(0.01, "ohm")
	raw.battery.polarization_time = _quantity(1.0, "s")
	var admitted: Dictionary = Data.load_document(raw, "stock admission fixture")
	var made: Dictionary = Data.prepare(raw, "0".repeat(64))
	_check("stock raw document and prepared candidate admit", admitted.ok and made.ok,
		"raw %s; prepare %s" % [str(admitted.errors), str(made.errors)])
	if not admitted.ok or not made.ok:
		return
	var prepared: Dictionary = made.prepared
	var session := Session.new()
	root.add_child(session)
	var started: bool = session.prepare({}, {prepared_data = prepared})
	_check("stock prepared candidate prepares in a session", started, str(session.load_error))
	if not started:
		session.queue_free()
		return

	# At Rp=1.4 ohm, no auxiliaries leaves positive power margin at the low OCV point. With the same pack and
	# 1.2 A of auxiliaries, the loaded low-point discriminant is negative while the full-charge one remains positive.
	var raw_control: Dictionary = raw.duplicate(true)
	_raw_pack(raw_control, 1.39, 0.01, 0.0)
	var loaded_control: Dictionary = Data.load_document(raw_control, "low-charge auxiliary control")
	var prepared_control: Dictionary = prepared.duplicate(true)
	_prepared_pack(prepared_control, 1.39, 0.01, 0.0)
	var session_control: bool = session.prepare({}, {prepared_data = prepared_control})
	_check("the 1.4-ohm pack with zero auxiliary load admits at both entry points", loaded_control.ok and session_control,
		"raw %s; session %s" % [str(loaded_control.errors), session.load_error])
	_check("restore the valid stock prepared session", session.prepare({}, {prepared_data = prepared}), session.load_error)

	# Optional RC fields omitted together are the pure resistance limiting model, not an invalid older document.
	var raw_resistive: Dictionary = raw.duplicate(true)
	raw_resistive.battery.erase("polarization_resistance")
	raw_resistive.battery.erase("polarization_time")
	var resistive_raw: Dictionary = Data.load_document(raw_resistive, "resistive-only")
	var prepared_resistive: Dictionary = prepared.duplicate(true)
	prepared_resistive.battery.erase("polarization_resistance_ohm")
	prepared_resistive.battery.erase("polarization_time_s")
	var resistive_session: bool = session.prepare({}, {prepared_data = prepared_resistive})
	_check("omitting both optional RC fields admits the resistive limiting law", resistive_raw.ok and resistive_session,
		"raw %s; session %s" % [str(resistive_raw.errors), session.load_error])
	_check("restore the stock candidate before transactional refusals", session.prepare({}, {prepared_data = prepared}), session.load_error)
	var before := _snapshot(session)
	var resets := [0]
	session.resetting.connect(func() -> void: resets[0] += 1)

	# Each row mutates raw and prepared representations separately, then checks both admission boundaries.
	var cases: Array = [
		["RC mode too fast under four-motor load", _stiff_raw, _stiff_prepared, "RC step slope", "RC step slope"],
		["zero capacity", func(d: Dictionary) -> void: d.battery.capacity.value = 0.0,
			func(d: Dictionary) -> void: d.battery.capacity_ah = 0.0, "capacity", "capacity"],
		["capacity above the raw limit", func(d: Dictionary) -> void: d.battery.capacity.value = 101.0,
			func(d: Dictionary) -> void: d.battery.capacity_ah = 101.0, "capacity", "capacity"],
		["negative instantaneous resistance", func(d: Dictionary) -> void: d.battery.resistance.value = -0.01,
			func(d: Dictionary) -> void: d.battery.resistance_ohm = -0.01, "resistance", "resistance"],
		["instantaneous resistance above the raw limit", func(d: Dictionary) -> void: d.battery.resistance.value = 10.1,
			func(d: Dictionary) -> void: d.battery.resistance_ohm = 10.1, "resistance", "resistance"],
		["negative auxiliary current", func(d: Dictionary) -> void: d.battery.auxiliary_current.value = -0.1,
			func(d: Dictionary) -> void: d.battery.auxiliary_current_a = -0.1, "auxiliary", "auxiliary"],
		["zero document initial charge", func(d: Dictionary) -> void: d.battery.initial_soc.value = 0.0,
			func(d: Dictionary) -> void: d.battery.initial_soc = 0.0, "initial_soc", "initial SOC"],
		["negative polarization resistance", func(d: Dictionary) -> void: d.battery.polarization_resistance.value = -0.01,
			func(d: Dictionary) -> void: d.battery.polarization_resistance_ohm = -0.01, "polarization", "polarization"],
		["positive RC resistance with zero time", func(d: Dictionary) -> void: d.battery.polarization_time.value = 0.0,
			func(d: Dictionary) -> void: d.battery.polarization_time_s = 0.0, "polarization", "polarization"],
		["positive RC resistance with missing time", func(d: Dictionary) -> void: d.battery.erase("polarization_time"),
			func(d: Dictionary) -> void: d.battery.erase("polarization_time_s"), "polarization", "polarization"],
		["positive RC time with missing resistance", func(d: Dictionary) -> void: d.battery.erase("polarization_resistance"),
			func(d: Dictionary) -> void: d.battery.erase("polarization_resistance_ohm"), "polarization", "polarization"],
		["zero RC resistance with positive time", func(d: Dictionary) -> void: d.battery.polarization_resistance.value = 0.0,
			func(d: Dictionary) -> void: d.battery.polarization_resistance_ohm = 0.0, "polarization", "polarization"],
		["an RC time below the integrator minimum", func(d: Dictionary) -> void: d.battery.polarization_time.value = 0.01,
			func(d: Dictionary) -> void: d.battery.polarization_time_s = 0.01, "polarization", "polarization"],
		["invalid cell count", func(d: Dictionary) -> void: d.battery.cells.value = 0,
			func(d: Dictionary) -> void: d.battery.cells = 0, "battery.cells", "battery.cells"],
		["non-increasing OCV charge points", func(d: Dictionary) -> void: d.battery.ocv_points.value[1][0] = 0.0,
			func(d: Dictionary) -> void: _prepared_bad_soc_order(d), "ocv_points", "ocv_points"],
		["OCV below the cell voltage domain", func(d: Dictionary) -> void: d.battery.ocv_points.value[0][1] = 1.0,
			func(d: Dictionary) -> void: _prepared_bad_cell_voltage(d), "ocv_points", "ocv_points"],
		["retired unbounded regenerative bridge", func(d: Dictionary) -> void: d.powertrain.braking = "damped",
			func(d: Dictionary) -> void: d.powertrain.braking = "damped", "braking", "braking"],
		# R1 is kept at 0.01 ohm. These values fail independently of the old no-sag diagnostics.
		["10-ohm pack fails the full-charge loaded hover", func(d: Dictionary) -> void: _raw_pack(d, 10.0, 0.01, 0.6),
			func(d: Dictionary) -> void: _prepared_pack(d, 10.0, 0.01, 0.6), "full charge", "full charge"],
		["1.5-ohm pack fails only the low-charge power bound", func(d: Dictionary) -> void: _raw_pack(d, 1.49, 0.01, 0.6),
			func(d: Dictionary) -> void: _prepared_pack(d, 1.49, 0.01, 0.6), "low charge", "low charge"],
		["polarization resistance contributes to steady hover sag", func(d: Dictionary) -> void: _raw_pack(d, 0.02, 1.48, 0.6),
			func(d: Dictionary) -> void: _prepared_pack(d, 0.02, 1.48, 0.6), "low charge", "low charge"],
		["auxiliaries make the low-charge hover fail", func(d: Dictionary) -> void: _raw_pack(d, 1.39, 0.01, 1.2),
			func(d: Dictionary) -> void: _prepared_pack(d, 1.39, 0.01, 1.2), "low charge", "low charge"],
		# The old OCV-only rotor calculation requires ~0.209374 duty at this point, while the loaded rotor needs
		# ~0.210518. The power discriminant remains positive, so this specifically tests per-motor limits.
		["loaded per-motor duty exceeds 0.210", func(d: Dictionary) -> void: d.powertrain.max_command.value = 0.210,
			func(d: Dictionary) -> void: d.powertrain.max_command = 0.210, "low charge", "low charge"],
	]
	for item: Array in cases:
		var raw_case: Dictionary = raw.duplicate(true)
		var prepared_case: Dictionary = prepared.duplicate(true)
		item[1].call(raw_case)
		item[2].call(prepared_case)
		var raw_result: Dictionary = Data.load_document(raw_case, str(item[0]))
		var direct_prepare: Dictionary = Data.prepare(raw_case, "0".repeat(64))
		var refused: bool = not session.prepare({}, {prepared_data = prepared_case})
		var raw_errors := "; ".join(raw_result.errors)
		_check("raw and prepared entry points refuse %s" % item[0], not raw_result.ok and not direct_prepare.ok and refused \
			and raw_errors.contains(str(item[3])) and session.load_error.contains(str(item[4])),
			"raw %s; session %s" % [raw_errors, session.load_error])
		_check("%s refusal leaves the accepted session untouched" % item[0], before == _snapshot(session) and resets[0] == 0)

	# The prepared dictionary's old derived hover values and embedded SHA are not authoritative after mutation.
	var changed_mass: Dictionary = prepared.duplicate(true)
	changed_mass.mass_kg = 30.0
	var rejected_mass: bool = not session.prepare({}, {prepared_data = changed_mass})
	_check("prepared hover recomputes geometry and mass instead of trusting cached diagnostics", rejected_mass \
		and session.load_error.contains("hover") and before == _snapshot(session) and resets[0] == 0, session.load_error)
	# Both coefficients are finite and positive, but kQ/kT underflows to zero. Before the normalized-solve
	# guard, the dimensional yaw row acquired a zero pivot and the prepared-data path could divide by zero.
	var pathological: Dictionary = prepared.duplicate(true)
	pathological.rotor_law.thrust_coefficient_n_s2 = 1.0e100
	pathological.rotor_law.torque_coefficient_n_m_s2 = 1.0e-300
	var rejected_coefficients: bool = not session.prepare({}, {prepared_data = pathological})
	_check("underflowing prepared kQ/kT is refused transactionally", rejected_coefficients \
		and before == _snapshot(session) and resets[0] == 0, session.load_error)
	# Restore must enforce the new electrical state domains transactionally, not only initial data admission.
	var checkpoint: Dictionary = session.checkpoint()
	for mutation: Array in [
		["one-ULP overcharge", func(c: Dictionary) -> void: c.kernel.continuous[4] += 9.094947017729282e-13],
		["overcharged pack", func(c: Dictionary) -> void: c.kernel.continuous[4] += 1.0],
		["negative terminal energy", func(c: Dictionary) -> void: c.kernel.continuous[5] = -1.0],
		["negative pack heat", func(c: Dictionary) -> void: c.kernel.continuous[6] = -1.0],
		["negative polarization", func(c: Dictionary) -> void: c.kernel.continuous[8] = -0.01],
		["nonfinite polarization", func(c: Dictionary) -> void: c.kernel.continuous[8] = NAN],
		["legacy battery layout", func(c: Dictionary) -> void:
			c.kernel.continuous = c.kernel.continuous.slice(0, 8)
			c.kernel.state_layout_identity = "openrc-multirotor-controlled-el-v1"],
	]:
		var invalid: Dictionary = checkpoint.duplicate(true)
		mutation[1].call(invalid)
		_check("restore refuses %s without replacing the flight" % mutation[0], not session.restore_checkpoint(invalid)
			and before == _snapshot(session) and resets[0] == 0)
	# Same extreme R1 just inside the additional-RC slope limit is a valid numerical-admission control.
	var safe_rc: Dictionary = prepared.duplicate(true)
	_prepared_pack(safe_rc, 0.0, 1.0, 0.6)
	var gain: float = 4.0 * float(safe_rc.powertrain.max_command) * float(safe_rc.powertrain.max_command)
	safe_rc.battery.polarization_time_s = (1.0 + gain / float(safe_rc.powertrain.resistance_ohm)) / 240.0 * 1.001
	_check("a loaded RC slope just inside the fixed-tick limit admits", session.prepare({}, {prepared_data = safe_rc}), session.load_error)
	# The session option is separate from document initial_soc and intentionally allows starting at zero charge.
	var zero_override: bool = session.prepare({}, {prepared_data = prepared, initial_soc = 0.0})
	_check("session start override can explicitly select zero charge", zero_override, session.load_error)
	session.queue_free()
