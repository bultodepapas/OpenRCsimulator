# BAT-06/07: pack_ecm law checks against EL2a parity, analytic RC/thermal answers and energy closure.
# Fixtures are hand-authored test inputs, not battery data; shipped templates come from the BAT-05 generator.
extends SceneTree

const PackEcm: Script = preload("res://physics/battery/pack_ecm.gd")
const BatteryData: Script = preload("res://physics/battery/battery_data.gd")
const Supply: Script = preload("res://physics/electric_supply.gd")

var checks: int = 0
var failures: int = 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL: " + label)


func near(label: String, actual: float, expected: float, tolerance: float = 1e-10) -> void:
	check(label + " actual=" + str(actual) + " expected=" + str(expected),
		is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


static func q(value: Variant, unit: String) -> Dictionary:
	return {"value": value, "unit": unit, "kind": "estimated", "source": "test fixture"}


## Template with two temperature rows and one RC branch unless told otherwise.
static func template_fixture(branches: int = 1, rows: int = 2, flat: bool = false) -> Dictionary:
	var t_knots: Array = [273.15, 298.15] if rows == 2 else [298.15]
	var ocv: Array = []
	var r0: Array = []
	var r1: Array = []
	var tau1: Array = []
	for row: int in rows:
		ocv.append([3.0, 3.7, 4.2])
		if flat:
			r0.append([0.02, 0.02, 0.02])
		else:
			r0.append([0.04, 0.02, 0.02] if row == rows - 1 else [0.08, 0.04, 0.04])
		r1.append([0.02, 0.01, 0.01] if row == rows - 1 else [0.04, 0.02, 0.02])
		tau1.append([20.0, 20.0, 20.0])
	var rc: Array = []
	for _k: int in branches:
		rc.append({"r_ohm": q(r1, "ohm"), "tau_s": q(tau1, "s")})
	return {
		"format": "openrc-cell-template v1", "id": "test-cell", "display_name": "test cell", "chemistry": "lipo",
		"tier": "C", "generator": "test", "provenance": {"note": "fixture"},
		"reference_capacity_ah": q(1.0, "Ah"),
		"soc_knots": q([0.0, 0.5, 1.0], "1"),
		"temperature_knots_k": q(t_knots, "K"),
		"ocv_v": q(ocv, "V"), "r0_ohm": q(r0, "ohm"), "rc_branches": rc,
		"specific_heat_j_per_kg_k": q(1000.0, "J/(kg·K)"),
		"limits": {"v_max": q(4.2, "V"), "v_cutoff": q(3.0, "V"), "v_damage_floor": q(2.5, "V"),
			"t_min_k": q(253.15, "K"), "t_max_k": q(333.15, "K")},
	}


static func pack_fixture(series: int = 4, capacity_ah: float = 2.0, wiring: float = 0.002) -> Dictionary:
	return {
		"format": "openrc-battery v1", "id": "test-pack", "display_name": "test pack", "class_note": "fixture",
		"chemistry": "lipo", "cell_template": {"id": "test-cell", "sha256": "0".repeat(64)},
		"series": series, "parallel": 1,
		"rated_capacity_ah": q(capacity_ah, "Ah"), "resistance_scale": q(1.0, "1"),
		"interconnect_resistance_ohm": q(wiring, "ohm"), "mass_kg": q(0.2, "kg"),
		"dimensions_m": q([0.1, 0.04, 0.03], "m"),
		"heat_transfer": {"still_air_w_per_k": q(0.1, "W/K"), "forced_w_per_k_per_sqrt_mps": q(0.05, "W/(K·(m/s)^0.5)")},
		"label": {"c_rating_continuous": 30, "c_rating_burst": null, "source": "fixture"},
	}


## Normalized battery as the aircraft loader produces it.
## Template resistances are given for 1 Ah; the default 2 Ah pack halves them (capacity normalization).
func battery_fixture(series: int = 4, branches: int = 1, rows: int = 2, capacity_ah: float = 2.0,
		wiring: float = 0.002, auxiliary: float = 0.3, flat: bool = false) -> Dictionary:
	var errors := PackedStringArray()
	var battery: Dictionary = BatteryData.normalize(errors, "fixture", pack_fixture(series, capacity_ah, wiring),
		template_fixture(branches, rows, flat))
	check("fixture normalizes: " + ", ".join(errors), errors.is_empty())
	battery.merge({"kind": "pack_ecm", "initial_soc": 1.0, "auxiliary_current_a": auxiliary,
		"cooling_airflow_fraction": 0.2, "weak_capacity_factor": 1.0, "weak_resistance_factor": 1.0,
		"weak_soc_offset": 0.0, "lvc_filter_s": 0.1}, true)
	return battery


static func motor_fixture() -> Dictionary:
	return {"kv_rpm_per_volt": 800.0, "resistance_ohm": 0.08, "no_load_current_a": 1.2}


static func lvc_fixture() -> Dictionary:
	return {"mode": "soft", "cell_detection": "auto", "detection_max_cell_v": 4.3, "cutoff_per_cell_v": 3.2,
		"soft_limit": 0.5, "soft_ramp_s": 3.0, "debounce_s": 0.5, "recovery": "throttle_reset",
		"reset_throttle_max": 0.05, "voltage_filter_s": 0.1}


func _initialize() -> void:
	_parity_with_el2a()
	_initial_block_and_detection()
	_energy_closure_and_rates()
	_analytic_rc_response()
	_thermal_steady_state()
	_interpolation_and_clamping()
	_weak_cell_and_limit()
	_exhaustion_branch()
	_invalid_inputs()
	print("BAT-06 pack_ecm law: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _block(battery: Dictionary, charge_fraction: float = 1.0) -> PackedFloat64Array:
	var block := PackedFloat64Array()
	block.resize(PackEcm.block_size(battery))
	block[PackEcm.Q] = charge_fraction * PackEcm.weak_initial_charge_c(battery)
	block[PackEcm.temperature_index(battery)] = 298.15
	block[PackEcm.limit_index(battery)] = 1.0
	block[PackEcm.cells_index(battery)] = float(battery.series)
	return block


func _parity_with_el2a() -> void:
	# No RC, one temperature row, balanced: identical to the OCV/resistance pack with n·OCV and n·R0 + R_w.
	var battery: Dictionary = battery_fixture(4, 0, 1, 2.0, 0.002, 0.3, true)
	var motor: Dictionary = motor_fixture()
	var ocv_points := PackedFloat64Array([0.0, 12.0, 0.5, 14.8, 1.0, 16.8])
	var pack: Dictionary = {"ocv_points": ocv_points, "capacity_ah": 2.0,
		"resistance_ohm": 4.0 * 0.01 + 0.002, "auxiliary_current_a": 0.3}
	for case: Array in [[0.0, 0.0, 1.0], [6000.0, 0.6, 0.8], [9000.0, 1.0, 0.43], [11000.0, 0.95, 0.12], [2000.0, 0.3, 0.5]]:
		var soc: float = case[2]
		var ours: Dictionary = PackEcm.evaluate(case[0], case[1], true, _block(battery, soc), battery, motor, 298.15, 0.0)
		var theirs: Dictionary = Supply.evaluate(case[0], case[1], soc, pack, motor)
		check("parity case accepted " + str(case), ours.ok and theirs.ok)
		if ours.ok and theirs.ok:
			near("parity bus voltage " + str(case), ours.bus_voltage_v, theirs.bus_voltage_v, 1e-12)
			near("parity motor current " + str(case), ours.motor_current_a, theirs.motor_current_a, 1e-12)
			near("parity pack current " + str(case), ours.pack_current_a, theirs.pack_current_a, 1e-12)
			near("parity shaft torque " + str(case), ours.shaft_torque_nm, theirs.shaft_torque_nm, 1e-12)
			near("parity loss " + str(case), ours.pack_loss_w, theirs.pack_loss_w, 1e-12)
			near("parity charge rate " + str(case), ours.rates[PackEcm.Q], -theirs.pack_current_a, 1e-12)
	var compact: Dictionary = PackEcm.evaluate(6000.0, 0.6, true, _block(battery, 0.8), battery, motor, 298.15, 0.0, false, true)
	var full: Dictionary = PackEcm.evaluate(6000.0, 0.6, true, _block(battery, 0.8), battery, motor, 298.15, 0.0)
	check("compact path matches full torque and rates", compact.ok and compact.shaft_torque_nm == full.shaft_torque_nm
		and compact.rates == full.rates and not compact.has("bus_voltage_v"))


func _initial_block_and_detection() -> void:
	var battery: Dictionary = battery_fixture()
	var made: Dictionary = PackEcm.initial_block(battery, motor_fixture(), lvc_fixture(), 288.15)
	check("initial block built", made.ok)
	if not made.ok:
		return
	var block: PackedFloat64Array = made.block
	check("initial block size 9 + 2K", block.size() == 11)
	near("initial weak charge is full capacity", block[PackEcm.Q], 7200.0)
	near("initial temperature is ambient", block[PackEcm.temperature_index(battery)], 288.15)
	near("initial limit is open", block[PackEcm.limit_index(battery)], 1.0)
	check("4S auto-detected from rest voltage", block[PackEcm.cells_index(battery)] == 4.0)
	# Rest voltage includes auxiliary sag at 288.15 K (interpolated R0 between the two rows).
	var r0: float = 0.5 * (0.04 + (0.02 - 0.04) * (288.15 - 273.15) / 25.0)
	near("sensed voltage starts at the loaded rest voltage", block[PackEcm.sense_index(battery)],
		16.8 - (4.0 * r0 + 0.002) * 0.3, 1e-12)


func _energy_closure_and_rates() -> void:
	var battery: Dictionary = battery_fixture(4, 2, 2)
	var block: PackedFloat64Array = _block(battery, 0.7)
	block[PackEcm.RC] = 0.03
	block[PackEcm.RC + 1] = 0.01
	block[PackEcm.RC + 2] = 0.05
	block[PackEcm.RC + 3] = 0.02
	block[PackEcm.temperature_index(battery)] = 290.0
	var point: Dictionary = PackEcm.evaluate(7000.0, 0.8, true, block, battery, motor_fixture(), 285.0, 6.0)
	check("two-branch point accepted", point.ok)
	if not point.ok:
		return
	var current: float = point.pack_current_a
	var chemical: float = point.ocv_v * current
	# d/dt of capacitor energy: sum C v dv/dt with C = tau/R; recompute R and tau at the same lookup.
	var stored_rate: float = 0.0
	var k_count: int = 2
	for k: int in k_count:
		var v_a: float = block[PackEcm.RC + k]
		var v_w: float = block[PackEcm.RC + k_count + k]
		# dv/dt = (R I - v)/tau, so C v dv/dt = v (I - v/R): use R from the rate identity R = (tau dv/dt + v)/I.
		stored_rate += 3.0 * v_a * (current - v_a / _branch_r(point, block, battery, k, false)) \
			+ v_w * (current - v_w / _branch_r(point, block, battery, k, true))
	near("energy closure: chemical = terminal + loss + stored", chemical,
		point.pack_terminal_power_w + point.pack_loss_w + stored_rate, 1e-11)
	near("terminal energy rate", point.rates[PackEcm.ENERGY], point.bus_voltage_v * current, 1e-12)
	near("charge rate is minus pack current", point.rates[PackEcm.Q], -current, 1e-15)
	check("sampled ESC slots have zero rate", point.rates[PackEcm.limit_index(battery)] == 0.0
		and point.rates[PackEcm.phase_index(battery)] == 0.0 and point.rates[PackEcm.timer_index(battery)] == 0.0
		and point.rates[PackEcm.cells_index(battery)] == 0.0)
	near("filter rate", point.rates[PackEcm.sense_index(battery)], (point.bus_voltage_v - 0.0) / 0.1, 1e-12)


## Branch resistance at the evaluated lookup, recovered from the tables the way the law samples them.
func _branch_r(_point: Dictionary, block: PackedFloat64Array, battery: Dictionary, k: int, weak: bool) -> float:
	var q_group: float = battery.group_capacity_c
	var q_used: float = PackEcm.weak_initial_charge_c(battery) - block[PackEcm.Q]
	var z: float = block[PackEcm.Q] / q_group if weak else battery.initial_soc - q_used / q_group
	var w: PackedFloat64Array = PackEcm._weights(battery.soc_knots, battery.temperature_knots_k, z,
		block[PackEcm.temperature_index(battery)])
	return PackEcm._sample(battery.rc_r[k], battery.soc_knots.size(), w)


func _analytic_rc_response() -> void:
	# Auxiliary current only (motor off) on a flat-OCV single-row cell: v1(t) = I R1 (1 - exp(-t/tau)).
	var battery: Dictionary = battery_fixture(1, 1, 1, 100.0, 0.0, 2.0)
	var motor: Dictionary = motor_fixture()
	var block: PackedFloat64Array = _block(battery)
	var dt: float = 1.0 / 240.0
	var t: float = 0.0
	for _i: int in 2400:
		block = _rk4(block, battery, motor, dt)
		t += dt
	var r1: float = 0.01 * 1.0 / 100.0
	var current: float = 2.0
	near("RK4 RC branch follows the analytic charge-up", block[PackEcm.RC], current * r1 * (1.0 - exp(-t / 20.0)), 1e-9)
	near("charge falls linearly with auxiliary current", block[PackEcm.Q], PackEcm.weak_initial_charge_c(battery) - current * t, 1e-12)


func _rk4(block: PackedFloat64Array, battery: Dictionary, motor: Dictionary, dt: float) -> PackedFloat64Array:
	var k1: PackedFloat64Array = PackEcm.evaluate(0.0, 0.0, false, block, battery, motor, 298.15, 0.0, false, true).rates
	var k2: PackedFloat64Array = PackEcm.evaluate(0.0, 0.0, false, _axpy(block, k1, 0.5 * dt), battery, motor, 298.15, 0.0, false, true).rates
	var k3: PackedFloat64Array = PackEcm.evaluate(0.0, 0.0, false, _axpy(block, k2, 0.5 * dt), battery, motor, 298.15, 0.0, false, true).rates
	var k4: PackedFloat64Array = PackEcm.evaluate(0.0, 0.0, false, _axpy(block, k3, dt), battery, motor, 298.15, 0.0, false, true).rates
	var out: PackedFloat64Array = block.duplicate()
	for i: int in out.size():
		out[i] += dt / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
	return out


static func _axpy(x: PackedFloat64Array, y: PackedFloat64Array, a: float) -> PackedFloat64Array:
	var out: PackedFloat64Array = x.duplicate()
	for i: int in out.size():
		out[i] += a * y[i]
	return out


func _thermal_steady_state() -> void:
	# Zero branches, constant auxiliary current: dT/dt = 0 at T = T_amb + I²R0_cells / hA(v).
	var battery: Dictionary = battery_fixture(4, 0, 1, 2.0, 0.002, 5.0)
	var block: PackedFloat64Array = _block(battery)
	var r_cells: float = 4.0 * 0.01
	var transfer: float = 0.1 + 0.05 * sqrt(9.0)
	block[PackEcm.temperature_index(battery)] = 290.0 + 25.0 * r_cells / transfer
	var point: Dictionary = PackEcm.evaluate(0.0, 0.0, false, block, battery, motor_fixture(), 290.0, 9.0)
	near("thermal rate vanishes at the analytic steady state", point.rates[PackEcm.temperature_index(battery)], 0.0, 1e-12)
	near("forced convection uses sqrt(cooling speed)", point.heat_transfer_w_per_k, transfer, 1e-14)
	near("thermal capacity is mass times specific heat", battery.thermal_capacity_j_per_k, 200.0, 1e-14)


func _interpolation_and_clamping() -> void:
	var knots_z := PackedFloat64Array([0.0, 0.5, 1.0])
	var knots_t := PackedFloat64Array([273.15, 298.15])
	var table := PackedFloat64Array([1.0, 2.0, 4.0, 3.0, 4.0, 8.0])
	near("bilinear interior", PackEcm._sample(table, 3, PackEcm._weights(knots_z, knots_t, 0.75, 285.65)), 4.5, 1e-15)
	near("clamped below both ranges", PackEcm._sample(table, 3, PackEcm._weights(knots_z, knots_t, -0.2, 200.0)), 1.0, 1e-15)
	near("clamped above both ranges", PackEcm._sample(table, 3, PackEcm._weights(knots_z, knots_t, 1.3, 400.0)), 8.0, 1e-15)
	near("exact knot", PackEcm._sample(table, 3, PackEcm._weights(knots_z, knots_t, 0.5, 298.15)), 4.0, 1e-15)
	near("single temperature row ignores T", PackEcm._sample(PackedFloat64Array([1.0, 2.0, 4.0]), 3,
		PackEcm._weights(knots_z, PackedFloat64Array([298.15]), 0.25, 400.0)), 1.5, 1e-15)


func _weak_cell_and_limit() -> void:
	var battery: Dictionary = battery_fixture()
	battery.weak_capacity_factor = 0.9
	battery.weak_resistance_factor = 1.5
	battery.weak_soc_offset = 0.05
	var block: PackedFloat64Array = _block(battery)
	near("weak initial charge", block[PackEcm.Q], (1.0 - 0.05) * 0.9 * 7200.0, 1e-12)
	block[PackEcm.Q] -= 3000.0
	var point: Dictionary = PackEcm.evaluate(5000.0, 1.0, true, block, battery, motor_fixture(), 298.15, 0.0)
	check("weak point accepted", point.ok)
	check("weak cell is the lowest cell", point.ok and point.soc_weak < point.soc and point.cell_voltage_min_v < point.cell_voltage_avg_v)
	block[PackEcm.limit_index(battery)] = 0.5
	var limited: Dictionary = PackEcm.evaluate(5000.0, 1.0, true, block, battery, motor_fixture(), 298.15, 0.0)
	near("ESC limit bounds the effective duty", limited.effective_duty, 0.5)
	var commanded: Dictionary = PackEcm.evaluate(5000.0, 0.3, true, block, battery, motor_fixture(), 298.15, 0.0)
	near("commanded duty below the limit is unchanged", commanded.effective_duty, 0.3)
	var disabled: Dictionary = PackEcm.evaluate(5000.0, 1.0, false, block, battery, motor_fixture(), 298.15, 0.0)
	near("source disabled keeps only auxiliary current", disabled.pack_current_a, 0.3, 1e-15)


func _exhaustion_branch() -> void:
	var battery: Dictionary = battery_fixture()
	var block: PackedFloat64Array = _block(battery, 0.0)
	block[PackEcm.RC] = 0.02
	var point: Dictionary = PackEcm.evaluate(4000.0, 1.0, true, block, battery, motor_fixture(), 298.15, 0.0)
	check("exhausted pack disconnects every load", point.ok and point.mode == "exhausted" and point.pack_current_a == 0.0
		and point.rates[PackEcm.Q] == 0.0 and point.auxiliary_current_a == 0.0)
	check("exhausted rotor only loses bearing torque", point.ok and point.shaft_torque_nm < 0.0)
	near("RC relaxes after disconnect", point.rates[PackEcm.RC], -0.02 / 20.0, 1e-12)
	block[PackEcm.Q] = -1e-30
	var left: Dictionary = PackEcm.evaluate(4000.0, 1.0, true, block, battery, motor_fixture(), 298.15, 0.0, true)
	check("connected left limit still drives the motor", left.ok and left.pack_current_a > 0.3)
	var refused: Dictionary = PackEcm.evaluate(4000.0, 1.0, true, block, battery, motor_fixture(), 298.15, 0.0)
	check("negative charge refused outside localization", not refused.ok)


func _invalid_inputs() -> void:
	var battery: Dictionary = battery_fixture()
	var block: PackedFloat64Array = _block(battery)
	check("wrong block size refused", not PackEcm.evaluate(0.0, 0.0, true, block.slice(1), battery, motor_fixture(), 298.15, 0.0).ok)
	var bad: PackedFloat64Array = block.duplicate()
	bad[PackEcm.RC] = NAN
	check("nonfinite block refused", not PackEcm.evaluate(0.0, 0.0, true, bad, battery, motor_fixture(), 298.15, 0.0).ok)
	check("duty above one refused", not PackEcm.evaluate(0.0, 1.1, true, block, battery, motor_fixture(), 298.15, 0.0).ok)
	check("nonpositive ambient refused", not PackEcm.evaluate(0.0, 0.5, true, block, battery, motor_fixture(), 0.0, 0.0).ok)
	var hot: Dictionary = battery_fixture(4, 1, 2, 2.0, 0.002, 400.0)
	check("auxiliary load beyond the pack refused", not PackEcm.evaluate(0.0, 0.0, true, _block(hot), hot, motor_fixture(), 298.15, 0.0).ok)
