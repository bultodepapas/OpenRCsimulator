// Experimental compact prepared tail-rotor mirror of rotorcraft/tail_rotor.gd. No runtime admission is implied.
#pragma once

#include <array>

#include "nk_helicopter_inflow.hpp"

namespace nk {

struct HeliTailRotorModel {
	R rho_kg_m3 = 0.0, tail_rotor_radius_m = 0.0, blade_lift_curve_slope_per_rad = 0.0;
	R blade_section_cd0 = 0.0, thrust_coefficient_max = 0.0, tail_to_main_speed_ratio = 0.0;
	R hub_distance_aft_m = 0.0, hub_height_above_cg_m = 0.0, trim_collective_rad = 0.0;
	R wake_efficiency = 0.0, rotation_sense = 0.0, solidity = 0.0, blockage_factor = 0.0;
	R wake_gi = 0.0, wake_gf = 0.0;
};

struct HeliTailTrim {
	bool ok = false;
	R lambda0 = 0.0, ct = 0.0;
};

inline HeliTailTrim heli_tail_trim(R mu, R k, R pitch_factor, R collective, R eta) {
	const R drive = k * collective * pitch_factor;
	const R b = k / 2.0;
	if (!heli_inflow_finite({drive, b}) || drive <= 0.0 || b <= 0.0) {
		return {};
	}
	R lo = 0.0;
	R hi = minf(drive / (b + 2.0 * eta * mu), sqrt_(drive / (2.0 * eta)));
	R root = hi * 0.5;
	if (mu == 0.0) {
		root = 2.0 * drive / (b + sqrt_(b * b + 8.0 * eta * drive));
	} else {
		for (int iteration = 0; iteration < 60; ++iteration) {
			const R s = sqrt_(mu * mu + root * root);
			const R residual = root * (b + 2.0 * eta * s) - drive;
			if (absf(residual) <= 1e-13 * drive) {
				break;
			}
			if (residual > 0.0) {
				hi = root;
			} else {
				lo = root;
			}
			const R derivative = b + 2.0 * eta * (mu * mu + 2.0 * root * root) / s;
			const R proposal = root - residual / derivative;
			root = iteration < 12 && proposal > lo && proposal < hi ? proposal : (lo + hi) / 2.0;
		}
	}
	const R s = sqrt_(mu * mu + root * root);
	const R ct = 2.0 * eta * root * s;
	const R residual = root * (b + 2.0 * eta * s) - drive;
	if (!heli_inflow_finite({root, ct, residual}) || root <= 0.0 || absf(residual) > 1e-12 * drive) {
		return {};
	}
	return {true, root, ct};
}

struct HeliTailRotorResult {
	bool ok = false;
	R thrust = 0.0, torque = 0.0, induced_velocity = 0.0, wake_factor = 0.0;
	std::array<R, 6> loads{};
};

inline HeliTailRotorResult heli_tail_low_rpm(const HeliTailRotorModel &m, R tip, R in_plane, R normal,
		R wake, R collective) {
	const R mu = minf(in_plane / tip, 0.15);
	const R mu_z = clampf(normal / tip, -1.0, 1.0);
	const R a_sigma = m.blade_lift_curve_slope_per_rad * m.solidity;
	const R k = a_sigma / 2.0;
	const R pitch_factor = R(1.0) / 3.0 + mu * mu / 2.0;
	const HeliTailTrim trim = heli_tail_trim(mu, k, pitch_factor, m.trim_collective_rad, m.wake_efficiency);
	if (!trim.ok) {
		return {};
	}
	const R s = sqrt_(mu * mu + trim.lambda0 * trim.lambda0);
	const R momentum_slope = 2.0 * m.wake_efficiency * (mu * mu + 2.0 * trim.lambda0 * trim.lambda0) / s;
	const R slope_collective = k * pitch_factor * momentum_slope / (momentum_slope + k / 2.0);
	const R slope_normal = k / 2.0 * (2.0 * m.wake_efficiency * s) / (momentum_slope + k / 2.0);
	const R ct_ideal = slope_collective * collective + slope_normal * mu_z;
	const R ct = clampf(ct_ideal, -m.thrust_coefficient_max, m.thrust_coefficient_max);
	const R radius = m.tail_rotor_radius_m;
	const R scale = m.rho_kg_m3 * tip * tip * kPi * radius * radius;
	R speed_activity = 1.0;
	if (in_plane > 0.0 || absf(normal) > 0.0) {
		const R flow = sqrt_(in_plane * in_plane + normal * normal);
		speed_activity = tip * tip / (tip * tip + flow * flow);
	}
	const R thrust = m.blockage_factor * scale * ct * speed_activity;
	const R lambda0 = mu_z - 2.0 * (2.0 * ct / a_sigma - collective * pitch_factor);
	const R induced_cq = maxf(0.0, ct * (lambda0 - mu_z));
	const R profile_cq = m.blade_section_cd0 * m.solidity / 8.0 * (1.0 + 7.0 * mu * mu / 3.0);
	const R torque = scale * radius * (induced_cq + profile_cq) * speed_activity;
	const R induced_velocity = lambda0 * tip * speed_activity;
	const R fy = -thrust;
	const R mx = m.hub_height_above_cg_m * fy;
	const R my = -m.rotation_sense * torque;
	const R mz = -m.hub_distance_aft_m * fy;
	if (!heli_inflow_finite({mu, mu_z, s, momentum_slope, slope_collective, slope_normal, ct_ideal, ct, scale,
			speed_activity, thrust, torque, induced_velocity, mx, my, mz})) {
		return {};
	}
	return {true, thrust, torque, induced_velocity, wake, {0.0, fy, 0.0, mx, my, mz}};
}

inline HeliTailRotorResult heli_tail_rotor(const HeliTailRotorModel &m, R omega_main, R main_vi,
		const std::array<R, 3> &air, const std::array<R, 3> &rates, R collective, R main_nominal_omega) {
	if (!heli_inflow_finite({air[0], air[1], air[2], rates[0], rates[1], rates[2], omega_main, main_vi,
			collective, main_nominal_omega}) || omega_main < 0.0 || main_nominal_omega < 0.0
			|| absf(collective) > kPi / 2.0) {
		return {};
	}
	const R u = air[0], v = air[1], w = air[2];
	R wake = 0.0;
	if (main_vi > w) {
		const R tangent = u / (main_vi - w);
		wake = 1.5 * clampf((tangent - m.wake_gi) / (m.wake_gf - m.wake_gi), 0.0, 1.0);
	}
	const R w_tail = w + m.hub_distance_aft_m * rates[1] - wake * main_vi;
	const R normal = v - m.hub_distance_aft_m * rates[2] + m.hub_height_above_cg_m * rates[0];
	const R in_plane = sqrt_(u * u + w_tail * w_tail);
	const R omega = m.tail_to_main_speed_ratio * omega_main;
	const R tip = omega * m.tail_rotor_radius_m;
	if (!heli_inflow_finite({wake, normal, in_plane, omega, tip})) {
		return {};
	}
	if (omega_main == 0.0) {
		return {true, 0.0, 0.0, 0.0, wake, {0.0, 0.0, 0.0, 0.0, 0.0, 0.0}};
	}
	if (tip <= 0.0) {
		return {};
	}
	const R low_speed = sqrt_(in_plane * in_plane + normal * normal);
	R low_weight = 0.0;
	if (main_nominal_omega > 0.0) {
		const R nominal_tail_omega = main_nominal_omega * m.tail_to_main_speed_ratio;
		R upper = maxf(0.08 * nominal_tail_omega, low_speed / (0.15 * m.tail_rotor_radius_m));
		upper = minf(0.20 * nominal_tail_omega, upper);
		const R lower = 0.5 * upper;
		if (omega <= lower) {
			low_weight = 1.0;
		} else if (omega < upper) {
			const R blend = (omega - lower) / (upper - lower);
			low_weight = 1.0 - blend * blend * (3.0 - 2.0 * blend);
		}
	}
	HeliTailRotorResult low;
	if (low_weight > 0.0) {
		low = heli_tail_low_rpm(m, tip, in_plane, normal, wake, collective);
		if (!low.ok) {
			return {};
		}
		if (low_weight >= 1.0) {
			return low;
		}
	}
	const R mu = in_plane / tip;
	const R mu_z = normal / tip;
	if (!heli_inflow_finite({mu, mu_z}) || mu > 1e6 || absf(mu_z) > 1e6) {
		return {};
	}
	const R a_sigma = m.blade_lift_curve_slope_per_rad * m.solidity;
	const R k = a_sigma / 2.0;
	const R pitch_factor = R(1.0) / 3.0 + mu * mu / 2.0;
	const HeliTailTrim trim = heli_tail_trim(mu, k, pitch_factor, m.trim_collective_rad, m.wake_efficiency);
	if (!trim.ok || trim.ct >= m.thrust_coefficient_max) {
		return {};
	}
	const R s = sqrt_(mu * mu + trim.lambda0 * trim.lambda0);
	const R momentum_slope = 2.0 * m.wake_efficiency * (mu * mu + 2.0 * trim.lambda0 * trim.lambda0) / s;
	const R slope_collective = k * pitch_factor * momentum_slope / (momentum_slope + k / 2.0);
	const R slope_normal = k / 2.0 * (2.0 * m.wake_efficiency * s) / (momentum_slope + k / 2.0);
	const R ct_ideal = slope_collective * collective + slope_normal * mu_z;
	const R ct = clampf(ct_ideal, -m.thrust_coefficient_max, m.thrust_coefficient_max);
	const R scale = m.rho_kg_m3 * tip * tip * kPi * m.tail_rotor_radius_m * m.tail_rotor_radius_m;
	const R thrust = m.blockage_factor * scale * ct;
	const R lambda0 = mu_z - 2.0 * (2.0 * ct / a_sigma - collective * pitch_factor);
	const R vi = lambda0 * tip;
	const R cq = ct * (lambda0 - mu_z) + m.blade_section_cd0 * m.solidity / 8.0 * (1.0 + 7.0 * mu * mu / 3.0);
	const R torque = scale * m.tail_rotor_radius_m * cq;
	const R fy = -thrust;
	const R mx = m.hub_height_above_cg_m * fy;
	const R my = -m.rotation_sense * torque;
	const R mz = -m.hub_distance_aft_m * fy;
	if (!heli_inflow_finite({slope_collective, slope_normal, ct_ideal, ct, scale, thrust, vi, cq, torque, mx, my, mz})) {
		return {};
	}
	HeliTailRotorResult result = {true, thrust, torque, vi, wake, {0.0, fy, 0.0, mx, my, mz}};
	if (low_weight > 0.0) {
		result.thrust = lerpf(result.thrust, low.thrust, low_weight);
		result.torque = lerpf(result.torque, low.torque, low_weight);
		result.induced_velocity = lerpf(result.induced_velocity, low.induced_velocity, low_weight);
		for (int i = 0; i < 6; ++i) {
			result.loads[i] = lerpf(result.loads[i], low.loads[i], low_weight);
		}
	}
	return result;
}

} // namespace nk
