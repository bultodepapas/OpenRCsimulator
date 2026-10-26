# BAT-06/07: Thevenin pack law with an average cell, one weakest cell and a lumped temperature.
# Normative text: docs/research/battery/BAT-04/specification.md §4–§5. Pure, float64, no stored state.
# RC voltages, temperature and the ESC filter are states, so the motor/bus solve keeps EL2a's closed form.
# One-quadrant (motoring) only: regeneration needs a bidirectional ESC and the BAT-08 charge boundary.
extends RefCounted

const Electric: Script = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/electric_motor.gd")
const Supervisor: Script = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/battery/esc_supervisor.gd")
const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/math3d.gd")

const Q: int = 0 # weak-cell remaining charge, C (the located exhaustion state)
const ENERGY: int = 1 # terminal energy, J
const LOSS: int = 2 # pack electrical loss, J
const RC: int = 3 # first average-cell RC voltage


## Battery block size after the shaft rpm slot: q, E, H, 2K RC voltages, T, v_sense, limit, phase, timer, cells.
static func block_size(battery: Dictionary) -> int:
	return 9 + 2 * int(battery.branches)


static func temperature_index(battery: Dictionary) -> int:
	return RC + 2 * int(battery.branches)


static func sense_index(battery: Dictionary) -> int:
	return temperature_index(battery) + 1


static func limit_index(battery: Dictionary) -> int:
	return temperature_index(battery) + 2


static func phase_index(battery: Dictionary) -> int:
	return temperature_index(battery) + 3


static func timer_index(battery: Dictionary) -> int:
	return temperature_index(battery) + 4


static func cells_index(battery: Dictionary) -> int:
	return temperature_index(battery) + 5


static func group_capacity_c(battery: Dictionary) -> float:
	return float(battery.group_capacity_c)


static func weak_initial_charge_c(battery: Dictionary) -> float:
	return (float(battery.initial_soc) - float(battery.weak_soc_offset)) \
		* float(battery.weak_capacity_factor) * float(battery.group_capacity_c)


## Rested, connected pack at the declared initial charge (the ESC "connection"). Cell detection and the
## sensed voltage start from the auxiliary-loaded rest voltage; RC voltages are zero and T is ambient.
static func initial_block(battery: Dictionary, motor: Dictionary, esc_profile: Dictionary, ambient_k: float) -> Dictionary:
	if not is_finite(ambient_k) or ambient_k <= 0.0:
		return _failure("ambient temperature must be finite and > 0 K")
	var block := PackedFloat64Array()
	block.resize(block_size(battery))
	block[Q] = weak_initial_charge_c(battery)
	block[temperature_index(battery)] = ambient_k
	block[limit_index(battery)] = 1.0
	var rest: Dictionary = evaluate(0.0, 0.0, false, block, battery, motor, ambient_k, 0.0)
	if not rest.ok:
		return rest
	block[sense_index(battery)] = float(rest.bus_voltage_v)
	block[cells_index(battery)] = float(Supervisor.detect_cells(esc_profile, float(rest.bus_voltage_v)))
	return {ok = true, block = block, rest_voltage_v = float(rest.bus_voltage_v)}


## One stage evaluation. `enabled` is the source-enabled mode; `duty` is the commanded throttle in [0,1].
## The ESC limit is read from the block (sampled at the previous endpoint). `available_at_zero` is the connected
## left limit used only while locating exhaustion. `dynamics_only` skips telemetry fields.
static func evaluate(rpm: float, duty: float, enabled: bool, block: PackedFloat64Array, battery: Dictionary,
		motor: Dictionary, ambient_k: float, cooling_speed_mps: float, available_at_zero: bool = false,
		dynamics_only: bool = false) -> Dictionary:
	var size: int = block_size(battery)
	if block.size() != size:
		return _failure("battery block has %d values, expected %d" % [block.size(), size])
	for value: float in block:
		if not is_finite(value):
			return _failure("battery block is nonfinite")
	if not is_finite(rpm) or rpm < 0.0 or not is_finite(duty) or duty < 0.0 or duty > 1.0:
		return _failure("rpm must be finite >= 0 and duty in [0,1]")
	if not is_finite(ambient_k) or ambient_k <= 0.0 or not is_finite(cooling_speed_mps):
		return _failure("ambient temperature and cooling speed must be finite")
	var k_count: int = int(battery.branches)
	var t_index: int = RC + 2 * k_count
	var temperature: float = block[t_index]
	var limit: float = block[t_index + 2]
	if temperature <= 0.0 or limit < 0.0 or limit > 1.0:
		return _failure("battery temperature must be > 0 K and ESC limit in [0,1]")
	var kv: float = float(motor.kv_rpm_per_volt)
	var rm: float = float(motor.resistance_ohm)
	var idle: float = float(motor.no_load_current_a)

	var n: float = float(battery.series)
	var q_group: float = float(battery.group_capacity_c)
	var q_weak_capacity: float = float(battery.weak_capacity_factor) * q_group
	var q_w: float = block[Q]
	var q_used: float = weak_initial_charge_c(battery) - q_w
	var z_w: float = q_w / q_weak_capacity
	var z_a: float = float(battery.initial_soc) - q_used / q_group
	var knots_z: PackedFloat64Array = battery.soc_knots
	var knots_t: PackedFloat64Array = battery.temperature_knots_k
	var nz: int = knots_z.size()
	var wa: PackedFloat64Array = _weights(knots_z, knots_t, z_a, temperature)
	var ww: PackedFloat64Array = _weights(knots_z, knots_t, z_w, temperature)
	var ocv_table: PackedFloat64Array = battery.ocv
	var r0_table: PackedFloat64Array = battery.r0
	var f_r: float = float(battery.weak_resistance_factor)
	var ocv_a: float = _sample(ocv_table, nz, wa)
	var ocv_w: float = _sample(ocv_table, nz, ww)
	var r0_a: float = _sample(r0_table, nz, wa)
	var r0_w: float = f_r * _sample(r0_table, nz, ww)
	var rc_r: Array = battery.rc_r
	var rc_tau: Array = battery.rc_tau
	var sum_v_a: float = 0.0
	var sum_v_w: float = 0.0
	var r_a := PackedFloat64Array()
	var r_w := PackedFloat64Array()
	var tau_a := PackedFloat64Array()
	var tau_w := PackedFloat64Array()
	r_a.resize(k_count)
	r_w.resize(k_count)
	tau_a.resize(k_count)
	tau_w.resize(k_count)
	for k: int in k_count:
		var r_table: PackedFloat64Array = rc_r[k]
		var tau_table: PackedFloat64Array = rc_tau[k]
		r_a[k] = _sample(r_table, nz, wa)
		r_w[k] = f_r * _sample(r_table, nz, ww)
		tau_a[k] = _sample(tau_table, nz, wa)
		tau_w[k] = _sample(tau_table, nz, ww)
		sum_v_a += block[RC + k]
		sum_v_w += block[RC + k_count + k]
	var cells_r0: float = (n - 1.0) * r0_a + r0_w
	var pack_r: float = cells_r0 + float(battery.interconnect_ohm)
	var open_circuit: float = (n - 1.0) * ocv_a + ocv_w
	var polarization: float = (n - 1.0) * sum_v_a + sum_v_w
	var e_oc: float = open_circuit - polarization
	if not is_finite(e_oc) or not is_finite(pack_r) or pack_r < 0.0:
		return _failure("pack open-circuit voltage or resistance is invalid")

	var exhausted: bool = q_w <= 0.0 and not available_at_zero
	if q_w < 0.0 and not available_at_zero:
		return _failure("negative remaining charge outside exhaustion localization")
	var effective_duty: float = minf(duty, limit) if enabled and not exhausted else 0.0
	var aux_demand: float = float(battery.auxiliary_current_a)
	var motor_current: float = 0.0
	var pack_current: float = 0.0
	var bus_voltage: float = e_oc
	var source: Dictionary
	if exhausted:
		source = Electric._evaluate_validated(rpm, duty, 0.0, kv, rm, idle, false, dynamics_only)
	else:
		var bus_without_motor: float = e_oc - pack_r * aux_demand
		if not is_finite(bus_without_motor) or bus_without_motor <= 0.0:
			return _failure("auxiliary load leaves no positive feasible bus voltage")
		var back_emf: float = rpm / kv
		var numerator: float = effective_duty * bus_without_motor - back_emf
		var denominator: float = rm + effective_duty * effective_duty * pack_r
		motor_current = numerator / denominator if effective_duty > 0.0 and numerator > 0.0 else 0.0
		pack_current = effective_duty * motor_current + aux_demand
		bus_voltage = e_oc - pack_r * pack_current
		if not is_finite(motor_current) or not is_finite(bus_voltage) or bus_voltage <= 0.0:
			return _failure("battery sag leaves no positive feasible bus voltage")
		source = Electric._evaluate_validated(rpm, effective_duty, bus_voltage, kv, rm, idle, enabled, dynamics_only)
		if source.get("ok", false):
			var tolerance: float = 1e-11 * maxf(1.0, maxf(absf(motor_current), absf(float(source.motor_current_a))))
			if absf(float(source.motor_current_a) - motor_current) > tolerance:
				return _failure("closed-form pack solution disagrees with the motor current")
	if not source.get("ok", false):
		return _failure("source evaluation failed: " + str(source.get("message", "")))

	var rates := PackedFloat64Array()
	rates.resize(block.size())
	var rc_dissipation: float = 0.0
	for k: int in k_count:
		var v_a: float = block[RC + k]
		var v_w: float = block[RC + k_count + k]
		rates[RC + k] = (r_a[k] * pack_current - v_a) / tau_a[k]
		rates[RC + k_count + k] = (r_w[k] * pack_current - v_w) / tau_w[k]
		rc_dissipation += (n - 1.0) * v_a * v_a / r_a[k] + v_w * v_w / r_w[k]
	var cell_heat: float = pack_current * pack_current * cells_r0 + rc_dissipation
	var loss: float = pack_current * pack_current * pack_r + rc_dissipation
	var transfer: float = float(battery.h_still_w_per_k) + float(battery.h_forced_w_per_k_sqrt_mps) \
		* M.sqrt_(maxf(cooling_speed_mps, 0.0))
	rates[Q] = -pack_current
	rates[ENERGY] = bus_voltage * pack_current
	rates[LOSS] = loss
	rates[t_index] = (cell_heat - transfer * (temperature - ambient_k)) / float(battery.thermal_capacity_j_per_k)
	rates[t_index + 1] = (bus_voltage - block[t_index + 1]) / float(battery.lvc_filter_s)
	for value: float in rates:
		if not is_finite(value):
			return _failure("battery rate overflow")
	if dynamics_only:
		return {ok = true, shaft_torque_nm = float(source.shaft_torque_nm), motor_current_a = motor_current,
			pack_current_a = pack_current, rates = rates}

	var cell_avg: float = ocv_a - sum_v_a - r0_a * pack_current
	var cell_weak: float = ocv_w - sum_v_w - r0_w * pack_current
	var result: Dictionary = source.duplicate()
	result.merge({
		ok = true,
		mode = "exhausted" if exhausted else str(source.mode),
		battery_kind = "pack_ecm",
		rpm = rpm,
		requested_duty = duty,
		effective_duty = effective_duty,
		esc_limit = limit,
		soc = clampf(z_a, 0.0, 1.0),
		soc_weak = clampf(z_w, 0.0, 1.0),
		ocv_v = open_circuit,
		polarization_v = polarization,
		bus_voltage_v = bus_voltage,
		cell_voltage_avg_v = cell_avg,
		cell_voltage_min_v = minf(cell_avg, cell_weak),
		motor_current_a = motor_current,
		motor_bus_current_a = effective_duty * motor_current,
		auxiliary_demand_a = aux_demand,
		auxiliary_current_a = 0.0 if exhausted else aux_demand,
		pack_current_a = pack_current,
		pack_resistance_ohm = pack_r,
		pack_terminal_power_w = bus_voltage * pack_current,
		pack_open_circuit_power_w = open_circuit * pack_current,
		pack_loss_w = loss,
		cell_heat_w = cell_heat,
		heat_transfer_w_per_k = transfer,
		temperature_k = temperature,
		ambient_k = ambient_k,
		motor_bus_power_w = float(source.bus_power_w),
		motor_copper_loss_w = float(source.copper_loss_w),
		motor_rotational_loss_w = float(source.rotational_loss_w),
		rates = rates,
		source = source,
	}, true)
	return result


## Interpolation weights [z index, z fraction, T index, T fraction] with clamping at both table ends.
static func _weights(knots_z: PackedFloat64Array, knots_t: PackedFloat64Array, z: float, t: float) -> PackedFloat64Array:
	var zi: int = _segment(knots_z, z)
	var zf: float = clampf((z - knots_z[zi]) / (knots_z[zi + 1] - knots_z[zi]), 0.0, 1.0)
	if knots_t.size() < 2:
		return PackedFloat64Array([zi, zf, 0.0, 0.0])
	var ti: int = _segment(knots_t, t)
	var tf: float = clampf((t - knots_t[ti]) / (knots_t[ti + 1] - knots_t[ti]), 0.0, 1.0)
	return PackedFloat64Array([zi, zf, ti, tf])


## Lower knot of the segment containing x, clamped to [0, size - 2]. Knots are strictly increasing.
static func _segment(knots: PackedFloat64Array, x: float) -> int:
	var lo: int = 0
	var hi: int = knots.size() - 2
	if x <= knots[0]:
		return 0
	if x >= knots[hi + 1]:
		return hi
	while lo < hi:
		var mid: int = (lo + hi + 1) >> 1
		if knots[mid] <= x:
			lo = mid
		else:
			hi = mid - 1
	return lo


## Bilinear sample of a row-major [nT][nZ] table.
static func _sample(table: PackedFloat64Array, nz: int, w: PackedFloat64Array) -> float:
	var zi: int = int(w[0])
	var row: int = int(w[2]) * nz
	var low: float = table[row + zi] + w[1] * (table[row + zi + 1] - table[row + zi])
	if w[3] == 0.0:
		return low
	row += nz
	var high: float = table[row + zi] + w[1] * (table[row + zi + 1] - table[row + zi])
	return low + w[3] * (high - low)


static func _failure(message: String) -> Dictionary:
	return {ok = false, message = message}
