// BAT-06/07 pack ECM stage law. Mirrors app/physics/battery/pack_ecm.gd and
// FlightSession._battery_point; ESC supervision and resource events remain outside this evaluator.
#pragma once

#include <array>
#include <cstddef>
#include <utility>
#include <vector>

#include "nk_electric.hpp"

namespace nk {

struct PackEcmModel {
	int series = 0;
	int branches = 0;
	R group_capacity_c = 0.0;
	R initial_soc = 0.0;
	R weak_capacity_factor = 0.0;
	R weak_resistance_factor = 0.0;
	R weak_soc_offset = 0.0;
	R interconnect_ohm = 0.0;
	R auxiliary_current_a = 0.0;
	R cooling_airflow_fraction = 0.0;
	R thermal_capacity_j_per_k = 0.0;
	R h_still_w_per_k = 0.0;
	R h_forced_w_per_k_sqrt_mps = 0.0;
	R lvc_filter_s = 0.0;
	std::vector<double> soc_knots;
	std::vector<double> temperature_knots_k;
	std::vector<double> ocv;
	std::vector<double> r0;
	std::vector<std::vector<double>> rc_r;
	std::vector<std::vector<double>> rc_tau;
};

struct PackEcmPoint {
	bool ok = false;
	bool exhausted = false;
	ElectricMotorPoint motor;
	R motor_current_a = 0.0; // closed-form solution, as in PackEcm.evaluate
	R pack_current_a = 0.0;
	R bus_voltage_v = 0.0;
	std::vector<R> rates;
};

constexpr int kPackChargeIndex = 0;
constexpr int kPackEnergyIndex = 1;
constexpr int kPackLossIndex = 2;
constexpr int kPackRcIndex = 3;
constexpr int kPackMaxBranches = 2; // BatteryData.MAX_BRANCHES

inline int pack_ecm_block_size(const PackEcmModel &battery) { return 9 + 2 * battery.branches; }
inline int pack_ecm_temperature_index(const PackEcmModel &battery) { return kPackRcIndex + 2 * battery.branches; }
inline R pack_ecm_initial_charge(const PackEcmModel &battery) {
	return (battery.initial_soc - battery.weak_soc_offset) * battery.weak_capacity_factor * battery.group_capacity_c;
}

// Shapes are rechecked at the public scalar entry to prevent out-of-range indexing. Full model
// validation is performed once by the decoder; this shape check itself does not establish validity.
inline bool pack_ecm_shapes_valid(const PackEcmModel &battery) {
	if (battery.branches < 0 || battery.branches > kPackMaxBranches || battery.soc_knots.size() < 2 ||
			battery.temperature_knots_k.empty() || battery.rc_r.size() != static_cast<size_t>(battery.branches) ||
			battery.rc_tau.size() != static_cast<size_t>(battery.branches)) {
		return false;
	}
	const size_t nz = battery.soc_knots.size();
	const size_t nt = battery.temperature_knots_k.size();
	if (nz > static_cast<size_t>(-1) / nt) {
		return false;
	}
	const size_t count = nz * nt;
	if (battery.ocv.size() != count || battery.r0.size() != count) {
		return false;
	}
	for (int k = 0; k < battery.branches; ++k) {
		if (battery.rc_r[k].size() != count || battery.rc_tau[k].size() != count) {
			return false;
		}
	}
	return true;
}

// Decoder guard for the numeric model read by this law. Other identity/provenance fields are
// checked by the decoder/aircraft loader. The temperature table may have exactly one row.
inline bool pack_ecm_model_valid(const PackEcmModel &battery) {
	if (!pack_ecm_shapes_valid(battery) || battery.series < 1 || battery.series > 24 ||
			!is_finite(battery.group_capacity_c) || battery.group_capacity_c.v <= 0.0 ||
			!is_finite(battery.initial_soc) || battery.initial_soc.v <= 0.0 || battery.initial_soc.v > 1.0 ||
			!is_finite(battery.weak_soc_offset) || battery.weak_soc_offset.v < 0.0 || battery.weak_soc_offset.v >= 0.5 ||
			(battery.initial_soc - battery.weak_soc_offset).v <= 0.0 ||
			!is_finite(battery.weak_capacity_factor) || battery.weak_capacity_factor.v < 0.01 ||
			battery.weak_capacity_factor.v > 1.0 || !is_finite(battery.weak_resistance_factor) ||
			battery.weak_resistance_factor.v < 1.0 || battery.weak_resistance_factor.v > 10.0 ||
			!is_finite(battery.interconnect_ohm) || battery.interconnect_ohm.v < 0.0 ||
			!is_finite(battery.auxiliary_current_a) || battery.auxiliary_current_a.v < 0.0 ||
			battery.auxiliary_current_a.v > 100.0 || !is_finite(battery.cooling_airflow_fraction) ||
			battery.cooling_airflow_fraction.v < 0.0 || battery.cooling_airflow_fraction.v > 1.0 ||
			!is_finite(battery.thermal_capacity_j_per_k) || battery.thermal_capacity_j_per_k.v <= 0.0 ||
			!is_finite(battery.h_still_w_per_k) || battery.h_still_w_per_k.v < 0.0 ||
			!is_finite(battery.h_forced_w_per_k_sqrt_mps) || battery.h_forced_w_per_k_sqrt_mps.v < 0.0 ||
			!is_finite(battery.lvc_filter_s) || battery.lvc_filter_s.v <= 0.0) {
		return false;
	}
	if (!is_finite(pack_ecm_initial_charge(battery)) ||
			!is_finite(battery.weak_capacity_factor * battery.group_capacity_c)) {
		return false;
	}
	if (battery.soc_knots.front() != 0.0 || battery.soc_knots.back() != 1.0) {
		return false;
	}
	for (size_t i = 0; i < battery.soc_knots.size(); ++i) {
		if (!std::isfinite(battery.soc_knots[i]) || (i > 0 && battery.soc_knots[i] <= battery.soc_knots[i - 1])) {
			return false;
		}
	}
	for (size_t i = 0; i < battery.temperature_knots_k.size(); ++i) {
		if (!std::isfinite(battery.temperature_knots_k[i]) || battery.temperature_knots_k[i] <= 0.0 ||
				(i > 0 && battery.temperature_knots_k[i] <= battery.temperature_knots_k[i - 1])) {
			return false;
		}
	}
	const size_t nz = battery.soc_knots.size();
	for (size_t i = 0; i < battery.ocv.size(); ++i) {
		if (!std::isfinite(battery.ocv[i]) || battery.ocv[i] <= 0.0 || !std::isfinite(battery.r0[i]) ||
				battery.r0[i] <= 0.0 || (i % nz != 0 && battery.ocv[i] < battery.ocv[i - 1])) {
			return false;
		}
	}
	for (int k = 0; k < battery.branches; ++k) {
		for (size_t i = 0; i < battery.rc_r[k].size(); ++i) {
			if (!std::isfinite(battery.rc_r[k][i]) || battery.rc_r[k][i] <= 0.0 ||
					!std::isfinite(battery.rc_tau[k][i]) || battery.rc_tau[k][i] <= 0.0) {
				return false;
			}
		}
	}
	return true;
}

// Session trial validation. The caller checks the total continuous layout and passes the
// exact battery block. In particular the phase/cells slots are held discrete values, not rates.
inline bool pack_ecm_block_valid(const R *block, int size, const PackEcmModel &battery, bool trial) {
	if (block == nullptr || battery.branches < 0 || battery.branches > kPackMaxBranches ||
			size != pack_ecm_block_size(battery)) {
		return false;
	}
	for (int i = 0; i < size; ++i) {
		if (!is_finite(block[i])) {
			return false;
		}
	}
	const int at = pack_ecm_temperature_index(battery);
	const R temperature = block[at];
	const R limit = block[at + 2];
	const R phase = block[at + 3];
	const R timer = block[at + 4];
	const R cells = block[at + 5];
	if (temperature.v <= 0.0 || limit.v < 0.0 || limit.v > 1.0 || phase.v != std::floor(phase.v) ||
			phase.v < 0.0 || phase.v > 3.0 || cells.v != std::floor(cells.v) || cells.v < 1.0 || timer.v < 0.0) {
		return false;
	}
	return (trial || block[0].v >= 0.0) && block[0].v <= pack_ecm_initial_charge(battery).v &&
			block[1].v >= 0.0 && block[2].v >= 0.0;
}

struct PackEcmWeights {
	size_t zi = 0;
	R zf = 0.0;
	size_t ti = 0;
	R tf = 0.0;
};

// PackEcm._segment, _weights and _sample: preserve source interpolation order and the
// explicit zero-temperature-fraction early return (including a single-temperature table).
inline size_t pack_ecm_segment(const std::vector<double> &knots, R x) {
	size_t lo = 0;
	size_t hi = knots.size() - 2;
	if (x.v <= knots[0]) {
		return 0;
	}
	if (x.v >= knots[hi + 1]) {
		return hi;
	}
	while (lo < hi) {
		const size_t mid = (lo + hi + 1) >> 1;
		if (knots[mid] <= x.v) {
			lo = mid;
		} else {
			hi = mid - 1;
		}
	}
	return lo;
}

inline PackEcmWeights pack_ecm_weights(const PackEcmModel &battery, R z, R temperature) {
	PackEcmWeights out;
	out.zi = pack_ecm_segment(battery.soc_knots, z);
	out.zf = clampf((z - battery.soc_knots[out.zi]) /
			(R(battery.soc_knots[out.zi + 1]) - battery.soc_knots[out.zi]), 0.0, 1.0);
	if (battery.temperature_knots_k.size() < 2) {
		return out;
	}
	out.ti = pack_ecm_segment(battery.temperature_knots_k, temperature);
	out.tf = clampf((temperature - battery.temperature_knots_k[out.ti]) /
			(R(battery.temperature_knots_k[out.ti + 1]) - battery.temperature_knots_k[out.ti]), 0.0, 1.0);
	return out;
}

inline R pack_ecm_sample(const std::vector<double> &table, size_t nz, const PackEcmWeights &w) {
	size_t row = w.ti * nz;
	const R low = R(table[row + w.zi]) + w.zf * (R(table[row + w.zi + 1]) - table[row + w.zi]);
	if (w.tf.v == 0.0) {
		return low;
	}
	row += nz;
	const R high = R(table[row + w.zi]) + w.zf * (R(table[row + w.zi + 1]) - table[row + w.zi]);
	return low + w.tf * (high - low);
}

// PackEcm.evaluate's compact stage path. `block` is stage-local, and the caller supplies
// stage-local ambient temperature and cooling speed. Do not retain these results across stages.
inline PackEcmPoint pack_ecm_evaluate(R rpm, R duty, bool enabled, const R *block, int size,
		const PackEcmModel &battery, const ElectricMotorModel &motor, R ambient_k, R cooling_speed_mps,
		bool available_at_zero) {
	PackEcmPoint out;
	if (block == nullptr || !pack_ecm_shapes_valid(battery) || size != pack_ecm_block_size(battery)) {
		return out;
	}
	for (int i = 0; i < size; ++i) {
		if (!is_finite(block[i])) {
			return out;
		}
	}
	if (!is_finite(rpm) || rpm.v < 0.0 || !is_finite(duty) || duty.v < 0.0 || duty.v > 1.0 ||
			!is_finite(ambient_k) || ambient_k.v <= 0.0 || !is_finite(cooling_speed_mps)) {
		return out;
	}
	const int count = battery.branches;
	const int t_index = kPackRcIndex + 2 * count;
	const R temperature = block[t_index];
	const R limit = block[t_index + 2];
	if (temperature.v <= 0.0 || limit.v < 0.0 || limit.v > 1.0) {
		return out;
	}
	const R n = static_cast<double>(battery.series);
	const R q_group = battery.group_capacity_c;
	const R q_weak_capacity = battery.weak_capacity_factor * q_group;
	const R q_w = block[kPackChargeIndex];
	const R q_used = pack_ecm_initial_charge(battery) - q_w;
	const R z_w = q_w / q_weak_capacity;
	const R z_a = battery.initial_soc - q_used / q_group;
	const size_t nz = battery.soc_knots.size();
	const PackEcmWeights wa = pack_ecm_weights(battery, z_a, temperature);
	const PackEcmWeights ww = pack_ecm_weights(battery, z_w, temperature);
	const R ocv_a = pack_ecm_sample(battery.ocv, nz, wa);
	const R ocv_w = pack_ecm_sample(battery.ocv, nz, ww);
	const R r0_a = pack_ecm_sample(battery.r0, nz, wa);
	const R r0_w = battery.weak_resistance_factor * pack_ecm_sample(battery.r0, nz, ww);
	R sum_v_a = 0.0;
	R sum_v_w = 0.0;
	std::array<R, kPackMaxBranches> r_a{}, r_w{}, tau_a{}, tau_w{};
	for (int k = 0; k < count; ++k) {
		r_a[k] = pack_ecm_sample(battery.rc_r[k], nz, wa);
		r_w[k] = battery.weak_resistance_factor * pack_ecm_sample(battery.rc_r[k], nz, ww);
		tau_a[k] = pack_ecm_sample(battery.rc_tau[k], nz, wa);
		tau_w[k] = pack_ecm_sample(battery.rc_tau[k], nz, ww);
		sum_v_a += block[kPackRcIndex + k];
		sum_v_w += block[kPackRcIndex + count + k];
	}
	const R cells_r0 = (n - 1.0) * r0_a + r0_w;
	const R pack_r = cells_r0 + battery.interconnect_ohm;
	const R open_circuit = (n - 1.0) * ocv_a + ocv_w;
	const R polarization = (n - 1.0) * sum_v_a + sum_v_w;
	const R e_oc = open_circuit - polarization;
	if (!is_finite(e_oc) || !is_finite(pack_r) || pack_r.v < 0.0) {
		return out;
	}
	const bool exhausted = q_w.v <= 0.0 && !available_at_zero;
	if (q_w.v < 0.0 && !available_at_zero) {
		return out;
	}
	const R effective_duty = enabled && !exhausted ? minf(duty, limit) : R(0.0);
	const R aux_demand = battery.auxiliary_current_a;
	R motor_current = 0.0;
	R pack_current = 0.0;
	R bus_voltage = e_oc;
	ElectricMotorPoint source;
	if (exhausted) {
		source = electric_motor_evaluate(rpm, duty, 0.0, motor, false);
	} else {
		const R bus_without_motor = e_oc - pack_r * aux_demand;
		if (!is_finite(bus_without_motor) || bus_without_motor.v <= 0.0) {
			return out;
		}
		const R back_emf = rpm / motor.kv_rpm_per_volt;
		const R numerator = effective_duty * bus_without_motor - back_emf;
		const R denominator = motor.resistance_ohm + effective_duty * effective_duty * pack_r;
		motor_current = effective_duty.v > 0.0 && numerator.v > 0.0 ? numerator / denominator : R(0.0);
		pack_current = effective_duty * motor_current + aux_demand;
		bus_voltage = e_oc - pack_r * pack_current;
		if (!is_finite(motor_current) || !is_finite(bus_voltage) || bus_voltage.v <= 0.0) {
			return out;
		}
		source = electric_motor_evaluate(rpm, effective_duty, bus_voltage, motor, enabled);
		if (source.ok) {
			const R tolerance = 1e-11 * maxf(1.0, maxf(absf(motor_current), absf(source.motor_current_a)));
			if (absf(source.motor_current_a - motor_current).v > tolerance.v) {
				return out;
			}
		}
	}
	if (!source.ok) {
		return out;
	}
	std::vector<R> rates(static_cast<size_t>(size));
	R rc_dissipation = 0.0;
	for (int k = 0; k < count; ++k) {
		const R v_a = block[kPackRcIndex + k];
		const R v_w = block[kPackRcIndex + count + k];
		rates[kPackRcIndex + k] = (r_a[k] * pack_current - v_a) / tau_a[k];
		rates[kPackRcIndex + count + k] = (r_w[k] * pack_current - v_w) / tau_w[k];
		rc_dissipation += (n - 1.0) * v_a * v_a / r_a[k] + v_w * v_w / r_w[k];
	}
	const R cell_heat = pack_current * pack_current * cells_r0 + rc_dissipation;
	const R loss = pack_current * pack_current * pack_r + rc_dissipation;
	const R transfer = battery.h_still_w_per_k + battery.h_forced_w_per_k_sqrt_mps *
			sqrt_(maxf(cooling_speed_mps, 0.0));
	rates[kPackChargeIndex] = -pack_current;
	rates[kPackEnergyIndex] = bus_voltage * pack_current;
	rates[kPackLossIndex] = loss;
	rates[t_index] = (cell_heat - transfer * (temperature - ambient_k)) / battery.thermal_capacity_j_per_k;
	rates[t_index + 1] = (bus_voltage - block[t_index + 1]) / battery.lvc_filter_s;
	for (const R &value : rates) {
		if (!is_finite(value)) {
			return out;
		}
	}
	out.ok = true;
	out.exhausted = exhausted;
	out.motor = source;
	out.motor_current_a = motor_current;
	out.pack_current_a = pack_current;
	out.bus_voltage_v = bus_voltage;
	out.rates = std::move(rates);
	return out;
}

// FlightSession._battery_point for a pack. Trial charge below zero stays connected until
// the event boundary is projected; q == 0 takes the disconnected branch.
inline PackEcmPoint pack_ecm_stage(R rpm, R duty, const R *block, int size, const PackEcmModel &battery,
		const ElectricMotorModel &motor, bool enabled, R ambient_k, R cooling_speed_mps) {
	if (!pack_ecm_block_valid(block, size, battery, true)) {
		return {};
	}
	return pack_ecm_evaluate(rpm, duty, enabled, block, size, battery, motor, ambient_k, cooling_speed_mps,
			block[kPackChargeIndex].v < 0.0);
}

} // namespace nk
