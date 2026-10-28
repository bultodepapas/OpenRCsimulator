// Experimental helicopter main-rotor and dimensional-inflow stage. This mirrors the compact, prepared,
// diagnostics-off paths in rotorcraft/main_rotor.gd and main_rotor_stage.gd; it is not an admitted backend.
#pragma once

#include <array>

#include "nk_helicopter_inflow.hpp"

namespace nk {

// These are copied from MainRotor.prepare's validated, immutable result; do not rederive solidity at a stage.
struct HeliMainRotorModel {
	R rho_kg_m3 = 0.0, rotor_radius_m = 0.0, blade_lift_curve_slope_per_rad = 0.0;
	R blade_section_cd0 = 0.0, thrust_coefficient_max = 0.0, solidity = 0.0;
	R gamma_flybar = 0.0, flapback_k_mu = 0.0, omega_nominal_rad_s = 0.0;
	R cyclic_longitudinal_gain_nominal_rad_per_rad = 0.0, cyclic_lateral_gain_nominal_rad_per_rad = 0.0;
	R hub_spring_stiffness_nm_per_rad = 0.0, rotation_sense = 0.0;
	R hub_x_m = 0.0, hub_y_m = 0.0, hub_z_m = 0.0;
};

struct HeliMainRotorResult {
	bool ok = false;
	bool estimated_regime = false; // the reference contains estimated_regime for low or blended RPM
	R low_weight = 0.0;
	R thrust = 0.0, torque = 0.0;
	R flap_a_rate = 0.0, flap_b_rate = 0.0;
	std::array<R, 6> loads{};
};

inline std::array<R, 2> heli_main_low_rpm_transition(const HeliMainRotorModel &m, R crossflow) {
	R upper = maxf(0.08 * m.omega_nominal_rad_s, crossflow / (0.15 * m.rotor_radius_m));
	upper = minf(0.20 * m.omega_nominal_rad_s, upper);
	return {0.5 * upper, upper};
}

inline HeliMainRotorResult heli_main_low_rpm(const HeliMainRotorModel &m, R omega, R induced_velocity,
		const std::array<R, 3> &air, const std::array<R, 3> &body_rates, R collective, R cyclic_forward,
		R cyclic_right, R a1, R b1, R lower_transition, R crossflow) {
	const R radius = m.rotor_radius_m;
	const R tip = omega * radius;
	const R disk_area = R(kPi) * radius * radius;
	R activity = 1.0;
	if (crossflow > 0.0) {
		activity = tip * tip / (tip * tip + crossflow * crossflow);
	}
	const R angle_activity = omega * omega / (omega * omega + lower_transition * lower_transition);
	const R a_sigma = m.blade_lift_curve_slope_per_rad * m.solidity;
	const R ct = clampf(a_sigma * collective / 6.0, -m.thrust_coefficient_max, m.thrust_coefficient_max);
	const R scale = m.rho_kg_m3 * disk_area * tip * tip;
	const R thrust = ct * scale * activity;
	const R profile_cq = m.blade_section_cd0 * m.solidity / 8.0;
	const R profile_torque = profile_cq * scale * radius * activity;
	const R induced_torque = absf(ct) * absf(induced_velocity) * m.rho_kg_m3 * disk_area * tip * radius * activity;
	const R torque = profile_torque + induced_torque;
	R nx = -sin_(a1);
	R ny = sin_(b1);
	R nz = -cos_(a1) * cos_(b1);
	const R inverse_length = 1.0 / sqrt_(nx * nx + ny * ny + nz * nz);
	nx *= inverse_length;
	ny *= inverse_length;
	nz *= inverse_length;
	const R q = 0.5 * m.rho_kg_m3 * crossflow * crossflow;
	const R drag = q * m.solidity * disk_area * m.blade_section_cd0 * activity;
	R fx = nx * thrust;
	R fy = ny * thrust;
	const R fz = nz * thrust;
	if (crossflow > 0.0) {
		fx -= drag * air[0] / crossflow;
		fy -= drag * air[1] / crossflow;
	}
	const R arm_x = m.hub_y_m * fz - m.hub_z_m * fy;
	const R arm_y = m.hub_z_m * fx - m.hub_x_m * fz;
	const R arm_z = m.hub_x_m * fy - m.hub_y_m * fx;
	const R spring_x = m.hub_spring_stiffness_nm_per_rad * b1 * angle_activity;
	const R spring_y = m.hub_spring_stiffness_nm_per_rad * a1 * angle_activity;
	const R reaction_z = -m.rotation_sense * torque;
	const R mx = arm_x + spring_x;
	const R my = arm_y + spring_y;
	const R mz = arm_z + reaction_z;
	const R tau_rate = m.gamma_flybar * omega / 16.0;
	const R speed_ratio = omega / m.omega_nominal_rad_s;
	const R gain_scale = speed_ratio * speed_ratio;
	const R a_rate = angle_activity * (-body_rates[1]
		+ (-a1 - m.cyclic_longitudinal_gain_nominal_rad_per_rad * gain_scale * cyclic_forward) * tau_rate);
	const R b_rate = angle_activity * (-body_rates[0]
		+ (-b1 + m.cyclic_lateral_gain_nominal_rad_per_rad * gain_scale * cyclic_right) * tau_rate);
	if (!heli_inflow_finite({activity, angle_activity, ct, scale, thrust, torque, drag, fx, fy, fz,
			mx, my, mz, a_rate, b_rate, induced_velocity})) {
		return {};
	}
	return {true, true, 1.0, thrust, torque, a_rate, b_rate, {fx, fy, fz, mx, my, mz}};
}

inline HeliMainRotorResult heli_main_rotor(const HeliMainRotorModel &m, R omega, R induced_velocity,
		const std::array<R, 3> &air, const std::array<R, 3> &body_rates, R collective,
		R cyclic_forward, R cyclic_right, R a1, R b1) {
	if (!heli_inflow_finite({air[0], air[1], air[2], body_rates[0], body_rates[1], body_rates[2], omega,
			induced_velocity, collective, cyclic_forward, cyclic_right, a1, b1}) || omega < 0.0) {
		return {};
	}
	for (const R angle : {collective, cyclic_forward, cyclic_right, a1, b1}) {
		if (absf(angle) > kPi / 2.0) {
			return {};
		}
	}
	if (omega == 0.0) {
		return {true, false, 0.0, 0.0, 0.0, 0.0, 0.0, {0.0, 0.0, 0.0, 0.0, 0.0, 0.0}};
	}
	const R crossflow = sqrt_(air[0] * air[0] + air[1] * air[1]);
	const std::array<R, 2> transition = heli_main_low_rpm_transition(m, crossflow);
	HeliMainRotorResult low;
	R low_weight = 0.0;
	if (omega < transition[1]) {
		low = heli_main_low_rpm(m, omega, induced_velocity, air, body_rates, collective,
			cyclic_forward, cyclic_right, a1, b1, transition[0], crossflow);
		if (!low.ok) {
			return {};
		}
		if (omega <= transition[0]) {
			return low;
		}
		R blend = (omega - transition[0]) / (transition[1] - transition[0]);
		blend = clampf(blend, 0.0, 1.0);
		low_weight = 1.0 - blend * blend * (3.0 - 2.0 * blend);
	}
	const R radius = m.rotor_radius_m;
	const R tip = omega * radius;
	if (!is_finite(tip) || tip <= 0.0) {
		return {};
	}
	const R mu_x = air[0] / tip;
	const R mu_y = air[1] / tip;
	const R mu_z = air[2] / tip;
	const R lambda0 = induced_velocity / tip;
	const R mu2 = mu_x * mu_x + mu_y * mu_y;
	if (!heli_inflow_finite({mu_x, mu_y, mu_z, lambda0, mu2}) || mu2 >= 2.0) {
		return {};
	}
	const R mu = sqrt_(mu2);
	const R a_sigma = m.blade_lift_curve_slope_per_rad * m.solidity;
	const R ct_ideal = 0.5 * a_sigma * (collective * (R(1.0) / 3.0 + 0.5 * mu2) + 0.5 * (mu_z - lambda0));
	const R ct = clampf(ct_ideal, -m.thrust_coefficient_max, m.thrust_coefficient_max);
	const R scale = m.rho_kg_m3 * kPi * radius * radius * tip * tip;
	const R thrust = ct * scale;
	const R cq = ct * (lambda0 - mu_z) + m.blade_section_cd0 * m.solidity / 8.0 * (1.0 + (R(7.0) / 3.0) * mu2);
	const R torque = cq * scale * radius;
	R nx = -sin_(a1);
	R ny = sin_(b1);
	R nz = -cos_(a1) * cos_(b1);
	const R inverse_length = 1.0 / sqrt_(nx * nx + ny * ny + nz * nz);
	nx *= inverse_length;
	ny *= inverse_length;
	nz *= inverse_length;
	const R fx = nx * thrust;
	const R fy = ny * thrust;
	const R fz = nz * thrust;
	const R arm_x = m.hub_y_m * fz - m.hub_z_m * fy;
	const R arm_y = m.hub_z_m * fx - m.hub_x_m * fz;
	const R arm_z = m.hub_x_m * fy - m.hub_y_m * fx;
	const R spring_x = m.hub_spring_stiffness_nm_per_rad * b1;
	const R spring_y = m.hub_spring_stiffness_nm_per_rad * a1;
	const R reaction_z = -m.rotation_sense * torque;
	const R mx = arm_x + spring_x;
	const R my = arm_y + spring_y;
	const R mz = arm_z + reaction_z;
	const R tau = 16.0 / (m.gamma_flybar * omega);
	const R speed_ratio = omega / m.omega_nominal_rad_s;
	const R gain_scale = speed_ratio * speed_ratio;
	const R flapback = 2.0 * m.flapback_k_mu * (4.0 * collective / 3.0 - lambda0);
	const R sign_mu_x = mu_x < 0.0 ? R(-1.0) : (mu_x > 0.0 ? R(1.0) : R(0.0));
	const R axial_flap = m.flapback_k_mu * 16.0 * mu2 / ((1.0 - 0.5 * mu2) * (8.0 * mu + a_sigma)) * sign_mu_x;
	const R a_rate = -body_rates[1] + (-a1 + flapback * mu_x + axial_flap * mu_z
		- m.cyclic_longitudinal_gain_nominal_rad_per_rad * gain_scale * cyclic_forward) / tau;
	const R b_rate = -body_rates[0] + (-b1 + flapback * mu_y
		+ m.cyclic_lateral_gain_nominal_rad_per_rad * gain_scale * cyclic_right) / tau;
	if (!heli_inflow_finite({ct_ideal, ct, thrust, cq, torque, tau, a_rate, b_rate, fx, fy, fz, mx, my, mz})
			|| tau <= 0.0) {
		return {};
	}
	HeliMainRotorResult result = {true, false, 0.0, thrust, torque, a_rate, b_rate, {fx, fy, fz, mx, my, mz}};
	if (low_weight > 0.0) {
		result.estimated_regime = true;
		result.low_weight = low_weight;
		result.thrust = lerpf(result.thrust, low.thrust, low_weight);
		result.torque = lerpf(result.torque, low.torque, low_weight);
		result.flap_a_rate = lerpf(result.flap_a_rate, low.flap_a_rate, low_weight);
		result.flap_b_rate = lerpf(result.flap_b_rate, low.flap_b_rate, low_weight);
		for (int i = 0; i < 6; ++i) {
			result.loads[i] = lerpf(result.loads[i], low.loads[i], low_weight);
		}
	}
	return result;
}

struct HeliMainStageResult {
	bool ok = false;
	HeliMainRotorResult rotor;
	HeliDynamicInflow inflow;
	std::array<R, 3> derivative{};
};

inline HeliMainStageResult heli_main_stage(const HeliMainRotorModel &m, const std::array<R, 3> &state, R omega,
		const std::array<R, 3> &air, const std::array<R, 3> &body_rates, R collective, R cyclic_forward,
		R cyclic_right, R flow_floor, R height_over_radius, R loss, R instability, R thrust_axis_downworld_scalar) {
	const HeliMainRotorResult rotor = heli_main_rotor(m, omega, state[2], air, body_rates, collective,
		cyclic_forward, cyclic_right, state[0], state[1]);
	if (!rotor.ok) {
		return {};
	}
	R inflow_height = height_over_radius;
	if (!is_nan(thrust_axis_downworld_scalar)) {
		if (!is_finite(thrust_axis_downworld_scalar) || absf(thrust_axis_downworld_scalar) > 1.0 + 1.0e-10) {
			return {};
		}
		if (rotor.thrust * thrust_axis_downworld_scalar >= 0.0) {
			inflow_height = -1.0;
		}
	}
	const R crossflow = sqrt_(air[0] * air[0] + air[1] * air[1]);
	HeliDynamicInflow flow = heli_dynamic_inflow(state[2], rotor.thrust, m.rho_kg_m3, m.rotor_radius_m,
		-air[2], crossflow, flow_floor, inflow_height, loss, instability);
	if (!flow.ok && rotor.estimated_regime) {
		const R axial_flow = state[2] - air[2];
		const R effective_flow = sqrt_(crossflow * crossflow + axial_flow * axial_flow);
		const HeliInflowRate decay = heli_inflow_derivative(state[2], 0.0, m.rotor_radius_m, effective_flow, flow_floor);
		if (!decay.ok) {
			return {};
		}
		flow = {true, decay.rate, decay.tau, 0.0, effective_flow, 0.0, 1.0};
	} else if (!flow.ok) {
		return {};
	} else if (rotor.low_weight > 0.0) {
		const R faded_target = flow.target * (1.0 - rotor.low_weight);
		const HeliInflowRate response = heli_inflow_derivative(state[2], faded_target, m.rotor_radius_m,
			flow.effective_flow, flow_floor);
		if (!response.ok) {
			return {};
		}
		flow.rate = response.rate;
		flow.tau = response.tau;
		flow.target = faded_target;
	}
	return {true, rotor, flow, {rotor.flap_a_rate, rotor.flap_b_rate, flow.rate}};
}

} // namespace nk
