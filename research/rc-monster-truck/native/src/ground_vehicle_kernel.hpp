// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenRCsimulator contributors
#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <string>
#include <vector>

namespace openrc::ground_vehicle {

static_assert(sizeof(double) == 8, "ground vehicle kernel requires float64");
static_assert(std::numeric_limits<double>::is_iec559, "ground vehicle kernel requires IEEE-754");

inline constexpr std::size_t kStateSize = 31;
inline constexpr std::size_t kGeneralizedSize = 14;
inline constexpr std::size_t kCornerCount = 4;
inline constexpr std::size_t kMaximumHullProbes = 64;
inline constexpr std::size_t kMaximumContacts = 8;
inline constexpr std::size_t kMaximumContactRows = 12;
inline constexpr std::size_t kFrictionSweeps = 6;
inline constexpr double kMinSlipSpeed = 0.05;
inline constexpr double kMatrixPivotRelativeTolerance = 1.0e-12;
inline constexpr double kFrictionConvergenceForceToleranceN = 0.001;
inline constexpr double kBrakeConvergenceTorqueToleranceNm = 0.001;

using Vec3 = std::array<double, 3>;
using Quat = std::array<double, 4>;
using Vec14 = std::array<double, kGeneralizedSize>;
using Mat14 = std::array<double, kGeneralizedSize * kGeneralizedSize>;
using Mat6 = std::array<double, 36>;

struct Model {
	double sprung_mass_kg = 0.0;
	double unsprung_mass_kg = 0.0;
	double wheel_spin_inertia_kg_m2 = 0.0;
	double gravity_m_per_s2 = 0.0;
	double arm_inner_offset_m = 0.0;
	double arm_length_m = 0.0;
	double cg_height_above_chassis_datum_m = 0.0;
	double wheel_center_rest_below_chassis_datum_m = 0.0;
	double tire_radius_m = 0.0;
	double suspension_stiffness_n_per_m = 0.0;
	double suspension_damping_n_s_per_m = 0.0;
	double tire_stiffness_n_per_m = 0.0;
	double tire_damping_n_s_per_m = 0.0;
	double tire_slip_relaxation_s = 0.0;
	double travel_droop_m = 0.0;
	double travel_bump_m = 0.0;
	double bump_stop_stiffness_n_per_m = 0.0;
	double bump_stop_damping_n_s_per_m = 0.0;
	double droop_stop_stiffness_n_per_m = 0.0;
	double droop_stop_damping_n_s_per_m = 0.0;
	double drive_torque_per_wheel_nm = 0.0;
	double brake_torque_per_wheel_nm = 0.0;
	double reverse_torque_fraction = 0.0;
	double drive_torque_fade_rad_s = 0.0;
	double rolling_resistance_coefficient = 0.0;
	double tire_friction_scale = 0.0;
	double max_steer_angle_rad = 0.0;
	double steer_servo_natural_frequency_rad_s = 0.0;
	double steer_servo_damping_ratio = 0.0;
	double hull_contact_stiffness_n_per_m = 0.0;
	double hull_contact_damping_n_s_per_m = 0.0;
	double hull_contact_friction_scale = 0.0;
	std::array<double, 6> sprung_inertia_kg_m2{};
	std::array<double, 4> corner_x_m{};
	std::array<double, 4> corner_y_m{};
	std::vector<Vec3> hull_probe_centers_frd_m;
	std::vector<double> hull_probe_radii_m;
};

struct Controls {
	double throttle = 0.0;
	double steering = 0.0;
	double brake = 0.0;
	bool reverse = false;
};

struct Surface {
	double height_m = 0.0;
	Vec3 normal_ned{};
	double mu = 0.0;
	double rolling = 0.0;
};

struct CornerGeometry {
	std::array<Vec3, 4> hub_position_body{};
	std::array<Vec3, 4> hub_position_derivative_body{};
	std::array<Vec3, 4> hub_position_second_derivative_body{};
	std::array<Vec3, 4> hub_speed_body{};
	std::array<Vec3, 4> hub_bias_body{};
	std::array<Vec3, 4> spin_axis_body{};
	std::array<Vec3, 4> spin_axis_rate_body{};
	std::array<double, 4> steering_acceleration_body{};
};

struct EvalResult {
	bool ok = false;
	std::string error;
	Vec14 generalized_acceleration{};
	double steering_acceleration_rad_per_s2 = 0.0;
	std::array<double, 4> suspension_force_n{};
	std::array<double, 4> wheel_load_n{};
	std::array<double, 4> wheel_longitudinal_force_n{};
	std::array<double, 4> wheel_lateral_force_n{};
	std::array<double, 4> wheel_brake_torque_n_m{};
	std::array<double, 4> wheel_slip_ratio{};
	std::array<double, 4> wheel_slip_angle_rad{};
	std::array<double, 4> wheel_slip_speed_m_per_s{};
	std::array<bool, 4> wheel_in_contact{};
	std::vector<bool> hull_in_contact;
	bool airborne = true;
	std::size_t friction_sweeps_used = 0;
	double energy_j = 0.0;
};

struct Contact {
	bool brake = false;
	std::size_t corner = 0;
	std::array<Vec14, 2> rows{};
	std::array<double, 2> slip{};
	std::array<double, 2> bias{};
	double mu_load = 0.0;
	double tau = 0.0;
};

struct Factor {
	Mat6 body_lower{};
	std::array<double, 48> coupling{};
	std::array<double, 8> local_mass{};
};

inline double maxf(double a, double b) { return a > b ? a : b; }
inline double minf(double a, double b) { return a < b ? a : b; }
inline double clampf(double value, double low, double high) {
	return value < low ? low : (value > high ? high : value);
}
inline double signf(double value) { return value > 0.0 ? 1.0 : (value < 0.0 ? -1.0 : 0.0); }
inline double dot(const Vec3 &a, const Vec3 &b) {
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
inline Vec3 add(const Vec3 &a, const Vec3 &b) {
	return {a[0] + b[0], a[1] + b[1], a[2] + b[2]};
}
inline Vec3 sub(const Vec3 &a, const Vec3 &b) {
	return {a[0] - b[0], a[1] - b[1], a[2] - b[2]};
}
inline Vec3 scale(const Vec3 &a, double s) { return {a[0] * s, a[1] * s, a[2] * s}; }
inline Vec3 cross(const Vec3 &a, const Vec3 &b) {
	return {
		a[1] * b[2] - a[2] * b[1],
		a[2] * b[0] - a[0] * b[2],
		a[0] * b[1] - a[1] * b[0],
	};
}
inline double norm(const Vec3 &a) { return std::sqrt(dot(a, a)); }
inline Quat quaternion(const std::array<double, kStateSize> &state) {
	return {state[6], state[7], state[8], state[9]};
}
inline Quat normalized(const Quat &q) {
	const double n = std::sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
	return {q[0] / n, q[1] / n, q[2] / n, q[3] / n};
}
inline Quat conjugate(const Quat &q) { return {q[0], -q[1], -q[2], -q[3]}; }
inline Vec3 rotate(const Quat &q, const Vec3 &v) {
	const Vec3 u{q[1], q[2], q[3]};
	const Vec3 t = scale(cross(u, v), 2.0);
	return add(add(v, scale(t, q[0])), cross(u, t));
}
inline bool finite(const Vec3 &a) {
	return std::isfinite(a[0]) && std::isfinite(a[1]) && std::isfinite(a[2]);
}
inline bool finite(const Vec14 &a) {
	for (double value : a) {
		if (!std::isfinite(value)) return false;
	}
	return true;
}

inline bool valid_model(const Model &m, std::string &error) {
	const std::array<double, 32> scalars{
		m.sprung_mass_kg, m.unsprung_mass_kg, m.wheel_spin_inertia_kg_m2, m.gravity_m_per_s2,
		m.arm_inner_offset_m, m.arm_length_m, m.cg_height_above_chassis_datum_m, m.wheel_center_rest_below_chassis_datum_m,
		m.tire_radius_m, m.suspension_stiffness_n_per_m, m.suspension_damping_n_s_per_m,
		m.tire_stiffness_n_per_m, m.tire_damping_n_s_per_m, m.tire_slip_relaxation_s,
		m.travel_droop_m, m.travel_bump_m, m.bump_stop_stiffness_n_per_m, m.bump_stop_damping_n_s_per_m,
		m.droop_stop_stiffness_n_per_m, m.droop_stop_damping_n_s_per_m, m.drive_torque_per_wheel_nm,
		m.brake_torque_per_wheel_nm, m.reverse_torque_fraction, m.drive_torque_fade_rad_s,
		m.rolling_resistance_coefficient, m.tire_friction_scale, m.max_steer_angle_rad,
		m.steer_servo_natural_frequency_rad_s, m.steer_servo_damping_ratio,
		m.hull_contact_stiffness_n_per_m, m.hull_contact_damping_n_s_per_m, m.hull_contact_friction_scale,
	};
	for (double value : scalars) {
		if (!std::isfinite(value)) {
			error = "Model contains a non-finite scalar";
			return false;
		}
	}
	const std::array<double, 12> positive{
		m.sprung_mass_kg, m.unsprung_mass_kg, m.wheel_spin_inertia_kg_m2, m.arm_length_m,
		m.tire_radius_m, m.suspension_stiffness_n_per_m, m.tire_stiffness_n_per_m,
		m.tire_slip_relaxation_s, m.travel_droop_m, m.travel_bump_m,
		m.bump_stop_stiffness_n_per_m, m.droop_stop_stiffness_n_per_m,
	};
	for (double value : positive) {
		if (value <= 0.0) {
			error = "Model positive scalar must be greater than zero";
			return false;
		}
	}
	if (m.max_steer_angle_rad <= 0.0 || m.steer_servo_natural_frequency_rad_s <= 0.0 ||
			m.hull_contact_stiffness_n_per_m <= 0.0) {
		error = "Model positive scalar must be greater than zero";
		return false;
	}
	const std::array<double, 17> nonnegative{
		m.gravity_m_per_s2, m.arm_inner_offset_m, m.cg_height_above_chassis_datum_m, m.wheel_center_rest_below_chassis_datum_m,
		m.suspension_damping_n_s_per_m, m.tire_damping_n_s_per_m, m.bump_stop_damping_n_s_per_m,
		m.droop_stop_damping_n_s_per_m, m.drive_torque_per_wheel_nm, m.brake_torque_per_wheel_nm,
		m.reverse_torque_fraction, m.drive_torque_fade_rad_s, m.rolling_resistance_coefficient,
		m.tire_friction_scale, m.steer_servo_damping_ratio, m.hull_contact_damping_n_s_per_m,
		m.hull_contact_friction_scale,
	};
	for (double value : nonnegative) {
		if (value < 0.0) {
			error = "Model nonnegative scalar must be nonnegative";
			return false;
		}
	}
	for (double value : m.sprung_inertia_kg_m2) {
		if (!std::isfinite(value)) {
			error = "Model inertia contains a non-finite value";
			return false;
		}
	}
	if (m.sprung_inertia_kg_m2[0] <= 0.0 || m.sprung_inertia_kg_m2[1] <= 0.0 || m.sprung_inertia_kg_m2[2] <= 0.0) {
		error = "Model inertia diagonal must be positive";
		return false;
	}
	for (std::size_t i = 0; i < 4; ++i) {
		if (!std::isfinite(m.corner_x_m[i]) || !std::isfinite(m.corner_y_m[i])) {
			error = "Model corner geometry is invalid";
			return false;
		}
	}
	if (m.hull_probe_radii_m.empty() || m.hull_probe_radii_m.size() != m.hull_probe_centers_frd_m.size() ||
			m.hull_probe_radii_m.size() > kMaximumHullProbes) {
		error = "Model hull probe dimensions are invalid";
		return false;
	}
	for (std::size_t i = 0; i < m.hull_probe_radii_m.size(); ++i) {
		if (!finite(m.hull_probe_centers_frd_m[i]) || !std::isfinite(m.hull_probe_radii_m[i]) || m.hull_probe_radii_m[i] <= 0.0) {
			error = "Model hull probe values are invalid";
			return false;
		}
	}
	return true;
}

inline bool valid_controls(const Controls &c, std::string &error) {
	if (!std::isfinite(c.throttle) || c.throttle < 0.0 || c.throttle > 1.0 ||
			!std::isfinite(c.steering) || c.steering < -1.0 || c.steering > 1.0 ||
			!std::isfinite(c.brake) || c.brake < 0.0 || c.brake > 1.0) {
		error = "Invalid controls";
		return false;
	}
	return true;
}

inline bool corner_geometry(const std::array<double, kStateSize> &state, const Model &m,
		double steer_right, double steer_rate_right, double steer_accel_right,
		CornerGeometry &out, std::string &error) {
	const Vec3 body_rate{state[10], state[11], state[12]};
	for (std::size_t corner = 0; corner < 4; ++corner) {
		const double travel = state[13 + corner];
		if (std::abs(travel) >= m.arm_length_m) {
			error = "Suspension travel reaches the A-arm geometric singularity";
			return false;
		}
		const double lateral_offset = std::sqrt(m.arm_length_m * m.arm_length_m - travel * travel);
		const double side = signf(m.corner_y_m[corner]);
		const double y = m.corner_y_m[corner] + side * (lateral_offset - m.arm_length_m);
		const double y_prime = -side * travel / lateral_offset;
		const double y_second = -side * m.arm_length_m * m.arm_length_m /
			(lateral_offset * lateral_offset * lateral_offset);
		const Vec3 r{m.corner_x_m[corner], y,
			m.cg_height_above_chassis_datum_m + m.wheel_center_rest_below_chassis_datum_m - travel};
		const Vec3 r_prime{0.0, y_prime, -1.0};
		const Vec3 r_second{0.0, y_second, 0.0};
		const double rate = state[17 + corner];
		const Vec3 hub_v = add(Vec3{state[3], state[4], state[5]},
			add(cross(body_rate, r), scale(r_prime, rate)));
		const Vec3 hub_b = add(cross(body_rate, cross(body_rate, r)),
			add(scale(cross(body_rate, r_prime), 2.0 * rate), scale(r_second, rate * rate)));
		const double left_angle = corner < 2 ? -steer_right : 0.0;
		const double left_rate = corner < 2 ? -steer_rate_right : 0.0;
		const double left_accel = corner < 2 ? -steer_accel_right : 0.0;
		const Vec3 forward{std::cos(left_angle), -std::sin(left_angle), 0.0};
		const Vec3 axis = cross(Vec3{0.0, 0.0, -1.0}, forward);
		const Vec3 axis_rate = scale(cross(Vec3{0.0, 0.0, 1.0}, axis), -left_rate);
		out.hub_position_body[corner] = r;
		out.hub_position_derivative_body[corner] = r_prime;
		out.hub_position_second_derivative_body[corner] = r_second;
		out.hub_speed_body[corner] = hub_v;
		out.hub_bias_body[corner] = hub_b;
		out.spin_axis_body[corner] = axis;
		out.spin_axis_rate_body[corner] = axis_rate;
		out.steering_acceleration_body[corner] = left_accel;
	}
	return true;
}

inline Mat14 generalized_mass_matrix(const Model &m, const CornerGeometry &g) {
	Mat14 matrix{};
	for (std::size_t axis = 0; axis < 3; ++axis) matrix[axis * 14 + axis] += m.sprung_mass_kg;
	const auto &inertia = m.sprung_inertia_kg_m2;
	matrix[3 * 14 + 3] += inertia[0];
	matrix[4 * 14 + 4] += inertia[1];
	matrix[5 * 14 + 5] += inertia[2];
	matrix[3 * 14 + 4] += inertia[3]; matrix[4 * 14 + 3] += inertia[3];
	matrix[3 * 14 + 5] += inertia[4]; matrix[5 * 14 + 3] += inertia[4];
	matrix[4 * 14 + 5] += inertia[5]; matrix[5 * 14 + 4] += inertia[5];
	const double mass = m.unsprung_mass_kg;
	for (std::size_t corner = 0; corner < 4; ++corner) {
		const Vec3 &r = g.hub_position_body[corner];
		const Vec3 &rp = g.hub_position_derivative_body[corner];
		std::array<double, 42> jacobian{};
		for (std::size_t axis = 0; axis < 3; ++axis) jacobian[axis * 14 + axis] = 1.0;
		jacobian[0 * 14 + 4] = r[2]; jacobian[0 * 14 + 5] = -r[1];
		jacobian[1 * 14 + 3] = -r[2]; jacobian[1 * 14 + 5] = r[0];
		jacobian[2 * 14 + 3] = r[1]; jacobian[2 * 14 + 4] = -r[0];
		for (std::size_t axis = 0; axis < 3; ++axis) jacobian[axis * 14 + 6 + corner] = rp[axis];
		const std::size_t travel_dof = 6 + corner;
		for (std::size_t row_local = 0; row_local < 7; ++row_local) {
			const std::size_t row = row_local < 6 ? row_local : travel_dof;
			for (std::size_t column_local = 0; column_local < 7; ++column_local) {
				const std::size_t column = column_local < 6 ? column_local : travel_dof;
				const double value = jacobian[row] * jacobian[column]
					+ jacobian[14 + row] * jacobian[14 + column]
					+ jacobian[28 + row] * jacobian[28 + column];
				matrix[row * 14 + column] += mass * value;
			}
		}
	}
	for (std::size_t corner = 0; corner < 4; ++corner) {
		const Vec3 &axis = g.spin_axis_body[corner];
		const double inertia_value = m.wheel_spin_inertia_kg_m2;
		const std::size_t spin_dof = 10 + corner;
		for (std::size_t row = 0; row < 3; ++row) {
			const std::size_t body_row = 3 + row;
			for (std::size_t column = 0; column < 3; ++column) {
				const std::size_t body_column = 3 + column;
				matrix[body_row * 14 + body_column] += inertia_value * axis[row] * axis[column];
			}
			matrix[body_row * 14 + spin_dof] += inertia_value * axis[row];
			matrix[spin_dof * 14 + body_row] += inertia_value * axis[row];
		}
		matrix[spin_dof * 14 + spin_dof] += inertia_value;
	}
	return matrix;
}

inline Vec14 hub_generalized(const Vec3 &r, const Vec3 &r_prime, std::size_t corner,
		double mass, const Vec3 &value) {
	Vec14 result{};
	for (std::size_t axis = 0; axis < 3; ++axis) result[axis] = mass * value[axis];
	const Vec3 moment = cross(r, value);
	for (std::size_t axis = 0; axis < 3; ++axis) result[3 + axis] = mass * moment[axis];
	result[6 + corner] = mass * dot(r_prime, value);
	return result;
}

inline void add_scaled(Vec14 &target, const Vec14 &value, double factor) {
	for (std::size_t i = 0; i < 14; ++i) target[i] += factor * value[i];
}

inline void add_contact_force(Vec14 &rhs, const Vec3 &r, const Vec3 &force_body,
		const Vec3 &r_prime, std::size_t corner, const Vec3 &spin_axis, const Vec3 &rho_body) {
	for (std::size_t axis = 0; axis < 3; ++axis) rhs[axis] += force_body[axis];
	const Vec3 moment = cross(add(r, rho_body), force_body);
	for (std::size_t axis = 0; axis < 3; ++axis) rhs[3 + axis] += moment[axis];
	rhs[6 + corner] += dot(r_prime, force_body);
	rhs[10 + corner] += dot(spin_axis, cross(rho_body, force_body));
}

inline void add_body_force(Vec14 &rhs, const Vec3 &point_body, const Vec3 &force_body) {
	for (std::size_t axis = 0; axis < 3; ++axis) rhs[axis] += force_body[axis];
	const Vec3 moment = cross(point_body, force_body);
	for (std::size_t axis = 0; axis < 3; ++axis) rhs[3 + axis] += moment[axis];
}

inline double travel_stop_force(double travel, double travel_rate, const Model &m) {
	if (travel > m.travel_bump_m) {
		return -(m.bump_stop_stiffness_n_per_m * (travel - m.travel_bump_m)
			+ m.bump_stop_damping_n_s_per_m * maxf(travel_rate, 0.0));
	}
	if (travel < -m.travel_droop_m) {
		return m.droop_stop_stiffness_n_per_m * (-m.travel_droop_m - travel)
			+ m.droop_stop_damping_n_s_per_m * maxf(-travel_rate, 0.0);
	}
	return 0.0;
}

inline bool is_quiescent_level_state(const std::array<double, kStateSize> &s, const Controls &c) {
	if (c.throttle != 0.0 || c.steering != 0.0 || c.brake != 0.0) return false;
	const Quat q{ s[6], s[7], s[8], s[9] };
	if (std::abs(std::abs(q[0]) - 1.0) > 1.0e-12 || std::abs(q[1]) > 1.0e-12 ||
			std::abs(q[2]) > 1.0e-12 || std::abs(q[3]) > 1.0e-12) return false;
	for (std::size_t index = 0; index < 3; ++index) {
		if (s[3 + index] != 0.0 || s[10 + index] != 0.0) return false;
	}
	for (std::size_t corner = 0; corner < 4; ++corner) {
		if (s[17 + corner] != 0.0 || s[21 + corner] != 0.0) return false;
	}
	return s[29] == 0.0 && s[30] == 0.0;
}

inline bool cholesky6(const Mat6 &matrix, Mat6 &lower, std::string &error) {
	double scale_value = 0.0;
	for (std::size_t i = 0; i < 6; ++i) scale_value = maxf(scale_value, std::abs(matrix[i * 6 + i]));
	if (!std::isfinite(scale_value) || scale_value <= 0.0) {
		error = "nonpositive matrix scale";
		return false;
	}
	for (std::size_t row = 0; row < 6; ++row) {
		for (std::size_t column = 0; column <= row; ++column) {
			double value = matrix[row * 6 + column];
			if (!std::isfinite(value)) {
				error = "non-finite matrix entry";
				return false;
			}
			for (std::size_t k = 0; k < column; ++k) value -= lower[row * 6 + k] * lower[column * 6 + k];
			if (row == column) {
				if (value <= scale_value * kMatrixPivotRelativeTolerance) {
					error = "nonpositive Cholesky pivot";
					return false;
				}
				lower[row * 6 + column] = std::sqrt(value);
			} else {
				lower[row * 6 + column] = value / lower[column * 6 + column];
			}
		}
	}
	return true;
}

inline bool factor_generalized_mass(const Mat14 &matrix, Factor &factor, std::string &error) {
	for (std::size_t local = 0; local < 8; ++local) {
		const std::size_t dof = 6 + local;
		const double mass = matrix[dof * 14 + dof];
		if (!std::isfinite(mass) || mass <= 0.0) {
			error = "nonpositive local generalized mass";
			return false;
		}
		factor.local_mass[local] = mass;
		for (std::size_t body = 0; body < 6; ++body) {
			const double value = matrix[body * 14 + dof];
			if (!std::isfinite(value)) {
				error = "non-finite generalized coupling";
				return false;
			}
			factor.coupling[body * 8 + local] = value;
		}
	}
	Mat6 schur{};
	for (std::size_t row = 0; row < 6; ++row) {
		for (std::size_t column = 0; column < 6; ++column) {
			double value = matrix[row * 14 + column];
			if (!std::isfinite(value)) {
				error = "non-finite sprung-body mass entry";
				return false;
			}
			for (std::size_t local = 0; local < 8; ++local) {
				value -= factor.coupling[row * 8 + local] * factor.coupling[column * 8 + local] /
					factor.local_mass[local];
			}
			schur[row * 6 + column] = value;
		}
	}
	return cholesky6(schur, factor.body_lower, error);
}

inline bool solve_cholesky6(const Mat6 &lower, const std::array<double, 6> &rhs,
		std::array<double, 6> &solution) {
	std::array<double, 6> forward{};
	for (std::size_t row = 0; row < 6; ++row) {
		double value = rhs[row];
		for (std::size_t column = 0; column < row; ++column) value -= lower[row * 6 + column] * forward[column];
		const double diagonal = lower[row * 6 + row];
		if (!std::isfinite(value) || !std::isfinite(diagonal) || diagonal <= 0.0) return false;
		forward[row] = value / diagonal;
	}
	for (int row = 5; row >= 0; --row) {
		double value = forward[static_cast<std::size_t>(row)];
		for (std::size_t column = static_cast<std::size_t>(row) + 1; column < 6; ++column) {
			value -= lower[column * 6 + static_cast<std::size_t>(row)] * solution[column];
		}
		const double diagonal = lower[static_cast<std::size_t>(row) * 6 + static_cast<std::size_t>(row)];
		if (!std::isfinite(value) || !std::isfinite(diagonal) || diagonal <= 0.0) return false;
		solution[static_cast<std::size_t>(row)] = value / diagonal;
	}
	return true;
}

inline bool solve_generalized(const Factor &factor, const Vec14 &rhs, Vec14 &result) {
	std::array<double, 6> adjusted_body{};
	for (std::size_t body = 0; body < 6; ++body) adjusted_body[body] = rhs[body];
	for (std::size_t local = 0; local < 8; ++local) {
		const double adjusted_local = rhs[6 + local] / factor.local_mass[local];
		for (std::size_t body = 0; body < 6; ++body) {
			adjusted_body[body] -= factor.coupling[body * 8 + local] * adjusted_local;
		}
	}
	std::array<double, 6> body_solution{};
	if (!solve_cholesky6(factor.body_lower, adjusted_body, body_solution)) return false;
	for (std::size_t body = 0; body < 6; ++body) result[body] = body_solution[body];
	for (std::size_t local = 0; local < 8; ++local) {
		double value = rhs[6 + local];
		for (std::size_t body = 0; body < 6; ++body) {
			value -= factor.coupling[body * 8 + local] * body_solution[body];
		}
		result[6 + local] = value / factor.local_mass[local];
	}
	return finite(result);
}

inline double dot14(const Vec14 &a, const Vec14 &b) {
	double result = 0.0;
	for (std::size_t i = 0; i < 14; ++i) result += a[i] * b[i];
	return result;
}

inline Vec14 contact_row(const Quat &q_conjugate, const Vec3 &direction_world,
		const Vec3 &lever_body, const Vec3 &r_prime, const Vec3 &spin_axis,
		const Vec3 &rho, std::size_t corner) {
	const Vec3 direction_body = rotate(q_conjugate, direction_world);
	Vec14 row{};
	for (std::size_t axis = 0; axis < 3; ++axis) row[axis] = direction_body[axis];
	const Vec3 moment = cross(lever_body, direction_body);
	for (std::size_t axis = 0; axis < 3; ++axis) row[3 + axis] = moment[axis];
	row[6 + corner] = dot(r_prime, direction_body);
	row[10 + corner] = dot(spin_axis, cross(rho, direction_body));
	return row;
}

inline bool solve_tangent_friction(const Factor &factor, Vec14 &acceleration,
		const std::array<Contact, kMaximumContacts> &contacts, std::size_t contact_count,
		bool adaptive, EvalResult &result, std::string &error) {
	if (contact_count == 0) return true;
	std::array<Vec14, kMaximumContactRows> rows{};
	std::array<Vec14, kMaximumContactRows> columns{};
	std::array<std::array<std::size_t, 2>, kMaximumContacts> row_indexes{};
	std::array<double, kMaximumContactRows> forces{};
	std::size_t row_count = 0;
	for (std::size_t c = 0; c < contact_count; ++c) {
		const std::size_t count = contacts[c].brake ? 1 : 2;
		for (std::size_t i = 0; i < count; ++i) {
			if (row_count >= kMaximumContactRows) {
				error = "Too many tangent contact rows";
				return false;
			}
			row_indexes[c][i] = row_count;
			rows[row_count] = contacts[c].rows[i];
			if (!solve_generalized(factor, rows[row_count], columns[row_count])) {
				error = "Could not solve generalized contact mobility";
				return false;
			}
			++row_count;
		}
	}
	for (std::size_t sweep = 0; sweep < kFrictionSweeps; ++sweep) {
		double max_force_delta = 0.0;
		double max_brake_torque_delta = 0.0;
		for (std::size_t contact_index = 0; contact_index < contact_count; ++contact_index) {
			const Contact &contact = contacts[contact_index];
			const std::size_t i0 = row_indexes[contact_index][0];
			if (contact.brake) {
				const double brake_mobility = dot14(rows[i0], columns[i0]);
				if (!std::isfinite(brake_mobility) || brake_mobility <= 1.0e-18) {
					error = "Wheel brake mobility is singular";
					return false;
				}
				const double brake_tau = maxf(contact.tau, 1.0e-5);
				const double current_brake = dot14(rows[i0], acceleration);
				const double target_brake = -contact.slip[0] / brake_tau;
				double delta_brake = (target_brake - current_brake) / brake_mobility;
				const double brake_limit = maxf(0.0, contact.mu_load);
				const double trial_brake = clampf(forces[i0] + delta_brake, -brake_limit, brake_limit);
				delta_brake = trial_brake - forces[i0];
				max_brake_torque_delta = maxf(max_brake_torque_delta, std::abs(delta_brake));
				forces[i0] = trial_brake;
				for (std::size_t degree = 0; degree < 14; ++degree) acceleration[degree] += columns[i0][degree] * delta_brake;
				result.wheel_brake_torque_n_m[contact.corner] = trial_brake;
				continue;
			}
			const std::size_t i1 = row_indexes[contact_index][1];
			const double w00 = dot14(rows[i0], columns[i0]);
			const double w01 = dot14(rows[i0], columns[i1]);
			const double w10 = dot14(rows[i1], columns[i0]);
			const double w11 = dot14(rows[i1], columns[i1]);
			const double determinant = w00 * w11 - w01 * w10;
			if (!std::isfinite(determinant) || determinant <= 1.0e-18) {
				error = "Tangent contact mobility is singular";
				return false;
			}
			const double current_long = dot14(rows[i0], acceleration) + contact.bias[0];
			const double current_lateral = dot14(rows[i1], acceleration) + contact.bias[1];
			const double tau = maxf(contact.tau, 1.0e-5);
			const double target_long = -contact.slip[0] / tau;
			const double target_lateral = -contact.slip[1] / tau;
			const double error_long = target_long - current_long;
			const double error_lateral = target_lateral - current_lateral;
			double delta_long = (w11 * error_long - w01 * error_lateral) / determinant;
			double delta_lateral = (-w10 * error_long + w00 * error_lateral) / determinant;
			double trial_long = forces[i0] + delta_long;
		double trial_lateral = forces[i1] + delta_lateral;
			const double trial_norm = std::sqrt(trial_long * trial_long + trial_lateral * trial_lateral);
			const double force_limit = maxf(0.0, contact.mu_load);
			if (trial_norm > force_limit && trial_norm > 0.0) {
				const double ratio = force_limit / trial_norm;
				trial_long *= ratio;
				trial_lateral *= ratio;
			}
			delta_long = trial_long - forces[i0];
			delta_lateral = trial_lateral - forces[i1];
			max_force_delta = maxf(max_force_delta, maxf(std::abs(delta_long), std::abs(delta_lateral)));
			forces[i0] = trial_long;
			forces[i1] = trial_lateral;
			for (std::size_t degree = 0; degree < 14; ++degree) {
				acceleration[degree] += columns[i0][degree] * delta_long + columns[i1][degree] * delta_lateral;
			}
			result.wheel_longitudinal_force_n[contact.corner] = trial_long;
			result.wheel_lateral_force_n[contact.corner] = trial_lateral;
		}
		result.friction_sweeps_used = sweep + 1;
		if (adaptive && max_force_delta <= kFrictionConvergenceForceToleranceN &&
				max_brake_torque_delta <= kBrakeConvergenceTorqueToleranceNm) break;
	}
	if (!finite(acceleration)) {
		error = "Contact solve produced non-finite generalized acceleration";
		return false;
	}
	return true;
}

inline double symmetric_inertia_dot(const std::array<double, 6> &inertia, const Vec3 &v,
		const Vec3 &w) {
		return w[0] * (inertia[0] * v[0] + inertia[3] * v[1] + inertia[4] * v[2])
			+ w[1] * (inertia[3] * v[0] + inertia[1] * v[1] + inertia[5] * v[2])
			+ w[2] * (inertia[4] * v[0] + inertia[5] * v[1] + inertia[2] * v[2]);
}

inline double energy(const std::array<double, kStateSize> &state, const Model &m,
		double hub_kinetic, double rotor_kinetic, double gravity_potential,
		double spring_energy, double tire_energy, double hull_energy) {
	const Vec3 body_velocity{state[3], state[4], state[5]};
	const Vec3 body_rate{state[10], state[11], state[12]};
	return 0.5 * m.sprung_mass_kg * dot(body_velocity, body_velocity)
		+ 0.5 * symmetric_inertia_dot(m.sprung_inertia_kg_m2, body_rate, body_rate)
		+ hub_kinetic + rotor_kinetic + gravity_potential + spring_energy + tire_energy + hull_energy;
}

inline std::vector<Vec3> query_positions(const std::array<double, kStateSize> &state,
		const Model &m, const CornerGeometry &g) {
	const Quat q = normalized(quaternion(state));
	const Vec3 position{state[0], state[1], state[2]};
	std::vector<Vec3> points;
	points.reserve(4 + m.hull_probe_centers_frd_m.size());
	for (std::size_t corner = 0; corner < 4; ++corner) {
		const Vec3 hub_world = add(position, rotate(q, g.hub_position_body[corner]));
		points.push_back({hub_world[0], hub_world[1], 0.0});
	}
	for (const Vec3 &center : m.hull_probe_centers_frd_m) {
		const Vec3 center_world = add(position, rotate(q, center));
		points.push_back({center_world[0], center_world[1], 0.0});
	}
	return points;
}

inline bool evaluate(const std::array<double, kStateSize> &state, const Model &m,
		const Controls &controls, const std::vector<Surface> &surfaces,
		bool calculate_energy, bool adaptive_friction, EvalResult &result) {
	result = EvalResult{};
	std::string error;
	if (!valid_model(m, error)) { result.error = error; return false; }
	if (!valid_controls(controls, error)) { result.error = error; return false; }
	for (double value : state) {
		if (!std::isfinite(value)) { result.error = "State contains a non-finite value"; return false; }
	}
	const Quat q_raw = quaternion(state);
	const double q_len = std::sqrt(q_raw[0] * q_raw[0] + q_raw[1] * q_raw[1] + q_raw[2] * q_raw[2] + q_raw[3] * q_raw[3]);
	if (!std::isfinite(q_len) || q_len <= 1.0e-10) { result.error = "Invalid vehicle attitude"; return false; }
	const Quat q = normalized(q_raw);
	const Quat q_conjugate = conjugate(q);
	const Vec3 body_rate{state[10], state[11], state[12]};
	const double servo_angle = state[29];
	const double servo_rate = state[30];
	const double servo_target = controls.steering * m.max_steer_angle_rad;
	const double servo_frequency = m.steer_servo_natural_frequency_rad_s;
	const double servo_acceleration = servo_frequency * servo_frequency * (servo_target - servo_angle)
		- 2.0 * m.steer_servo_damping_ratio * servo_frequency * servo_rate;
	if (!std::isfinite(servo_acceleration)) {
		result.error = "Steering servo acceleration is non-finite";
		return false;
	}
	CornerGeometry geometry;
	if (!corner_geometry(state, m, servo_angle, servo_rate, servo_acceleration, geometry, error)) {
		result.error = error;
		return false;
	}
	if (surfaces.size() != 4 + m.hull_probe_radii_m.size()) {
		result.error = "Road batch sample count does not match the wheel and hull queries";
		return false;
	}
	for (const Surface &surface : surfaces) {
		const double normal_length = norm(surface.normal_ned);
		if (!std::isfinite(surface.height_m) || !finite(surface.normal_ned) ||
				!std::isfinite(surface.mu) || !std::isfinite(surface.rolling) || surface.mu < 0.0 ||
				surface.rolling < 0.0 || !std::isfinite(normal_length) || std::abs(normal_length - 1.0) > 1.0e-5) {
			result.error = "Road sample height/friction/rolling or unit normal is invalid";
			return false;
		}
	}
	const Mat14 matrix = generalized_mass_matrix(m, geometry);
	Vec14 rhs{};
	const Vec3 position_world{state[0], state[1], state[2]};
	const Vec3 body_velocity{state[3], state[4], state[5]};
	const Vec3 gravity_body = rotate(q_conjugate, Vec3{0.0, 0.0, m.gravity_m_per_s2});
	for (std::size_t axis = 0; axis < 3; ++axis) rhs[axis] += m.sprung_mass_kg * gravity_body[axis];
	const Vec3 angular_momentum{
		m.sprung_inertia_kg_m2[0] * body_rate[0] + m.sprung_inertia_kg_m2[3] * body_rate[1] + m.sprung_inertia_kg_m2[4] * body_rate[2],
		m.sprung_inertia_kg_m2[3] * body_rate[0] + m.sprung_inertia_kg_m2[1] * body_rate[1] + m.sprung_inertia_kg_m2[5] * body_rate[2],
		m.sprung_inertia_kg_m2[4] * body_rate[0] + m.sprung_inertia_kg_m2[5] * body_rate[1] + m.sprung_inertia_kg_m2[2] * body_rate[2],
	};
	const Vec3 body_gyro = cross(body_rate, angular_momentum);
	for (std::size_t axis = 0; axis < 3; ++axis) rhs[3 + axis] -= body_gyro[axis];

	const bool skip_static_friction = is_quiescent_level_state(state, controls);
	const double drive_reverse_factor = controls.reverse ? -m.reverse_torque_fraction : 1.0;
	const double drive_base = controls.throttle * m.drive_torque_per_wheel_nm * drive_reverse_factor;
	const double brake_base = controls.brake * m.brake_torque_per_wheel_nm;
	double spring_energy = 0.0;
	double tire_energy = 0.0;
	double hull_energy = 0.0;
	double total_rotor_kinetic = 0.0;
	double hub_kinetic = 0.0;
	double gravity_potential = calculate_energy ? -m.sprung_mass_kg * m.gravity_m_per_s2 * position_world[2] : 0.0;
	std::array<Contact, kMaximumContacts> contacts{};
	std::size_t contact_count = 0;
	std::array<Vec3, 4> tire_rho_body{};
	std::array<Vec3, 4> tire_normal_world{};
	std::array<Vec3, 4> tire_forward_world{};
	std::array<Vec3, 4> tire_lateral_world{};
	std::array<double, 4> tire_slip_long{};
	std::array<double, 4> tire_slip_lateral{};
	std::array<double, 4> tire_mu_normal{};

	for (std::size_t corner = 0; corner < 4; ++corner) {
		const double travel = state[13 + corner];
		const double travel_rate = state[17 + corner];
		const double stop_force = travel_stop_force(travel, travel_rate, m);
		const double suspension_force = m.suspension_stiffness_n_per_m * travel + m.suspension_damping_n_s_per_m * travel_rate;
		result.suspension_force_n[corner] = suspension_force;
		rhs[6 + corner] -= suspension_force;
		rhs[6 + corner] += stop_force;
		if (calculate_energy) {
			spring_energy += 0.5 * m.suspension_stiffness_n_per_m * travel * travel;
			if (travel > m.travel_bump_m) {
				const double compression = travel - m.travel_bump_m;
				spring_energy += 0.5 * m.bump_stop_stiffness_n_per_m * compression * compression;
			} else if (travel < -m.travel_droop_m) {
				const double extension = -m.travel_droop_m - travel;
				spring_energy += 0.5 * m.droop_stop_stiffness_n_per_m * extension * extension;
			}
		}
		const Vec3 &r = geometry.hub_position_body[corner];
		const Vec3 &r_prime = geometry.hub_position_derivative_body[corner];
		const Vec3 hub_world = add(position_world, rotate(q, r));
		const Vec3 hub_velocity = add(body_velocity,
			add(cross(body_rate, r), scale(r_prime, travel_rate)));
		const Vec3 hub_velocity_ned = rotate(q, hub_velocity);
		const Surface &sample = surfaces[corner];
		const Vec3 surface_point{hub_world[0], hub_world[1], -sample.height_m};
		const double signed_distance = dot(sample.normal_ned, sub(hub_world, surface_point));
		const double penetration = maxf(m.tire_radius_m - signed_distance, 0.0);
		const double hub_normal_speed = dot(hub_velocity_ned, sample.normal_ned);
		const double normal_load = penetration > 0.0
			? maxf(0.0, m.tire_stiffness_n_per_m * penetration - m.tire_damping_n_s_per_m * hub_normal_speed)
			: 0.0;
		result.wheel_load_n[corner] = normal_load;
		result.wheel_in_contact[corner] = normal_load > 0.0;
		tire_mu_normal[corner] = maxf(0.0, sample.mu * m.tire_friction_scale * normal_load);
		if (calculate_energy) tire_energy += 0.5 * m.tire_stiffness_n_per_m * penetration * penetration;
		const Vec3 force_world = scale(sample.normal_ned, normal_load);
		const Vec3 force_body = rotate(q_conjugate, force_world);
		const Vec3 rho_world = scale(sample.normal_ned, -m.tire_radius_m);
		const Vec3 rho_body = rotate(q_conjugate, rho_world);
		tire_rho_body[corner] = rho_body;
		tire_normal_world[corner] = sample.normal_ned;
		add_contact_force(rhs, r, force_body, r_prime, corner, geometry.spin_axis_body[corner], rho_body);

		const double left_steer_angle = corner < 2 ? -servo_angle : 0.0;
		const double left_steer_rate = corner < 2 ? -servo_rate : 0.0;
		const Vec3 &wheel_axis = geometry.spin_axis_body[corner];
		const double wheel_spin = state[21 + corner];
		const Vec3 wheel_omega = add(body_rate, add(Vec3{0.0, 0.0, -left_steer_rate}, scale(wheel_axis, wheel_spin)));
		const Vec3 contact_velocity_ned = add(hub_velocity_ned, rotate(q, cross(wheel_omega, rho_body)));
		const Vec3 forward_body{std::cos(left_steer_angle), -std::sin(left_steer_angle), 0.0};
		Vec3 forward_world = rotate(q, forward_body);
		forward_world = sub(forward_world, scale(sample.normal_ned, dot(forward_world, sample.normal_ned)));
		const double forward_norm = norm(forward_world);
		if (forward_norm <= 1.0e-10) {
			result.error = "Tire forward axis is degenerate on the sampled surface";
			return false;
		}
		forward_world = scale(forward_world, 1.0 / forward_norm);
		Vec3 lateral_world = cross(forward_world, sample.normal_ned);
		const double lateral_norm = norm(lateral_world);
		if (lateral_norm <= 1.0e-10) {
			result.error = "Tire lateral axis is degenerate on the sampled surface";
			return false;
		}
		lateral_world = scale(lateral_world, 1.0 / lateral_norm);
		tire_forward_world[corner] = forward_world;
		tire_lateral_world[corner] = lateral_world;
		const double slip_long = dot(contact_velocity_ned, forward_world);
		const double slip_lateral = dot(contact_velocity_ned, lateral_world);
		tire_slip_long[corner] = slip_long;
		tire_slip_lateral[corner] = slip_lateral;
		result.wheel_slip_speed_m_per_s[corner] = std::sqrt(slip_long * slip_long + slip_lateral * slip_lateral);
		const double wheel_circumference_speed = wheel_spin * m.tire_radius_m;
		const double hub_forward_speed = dot(hub_velocity_ned, forward_world);
		const double ratio_denominator = maxf(kMinSlipSpeed, maxf(std::abs(hub_forward_speed), std::abs(wheel_circumference_speed)));
		result.wheel_slip_ratio[corner] = (wheel_circumference_speed - hub_forward_speed) / ratio_denominator;
		result.wheel_slip_angle_rad[corner] = std::atan2(slip_lateral, maxf(std::abs(slip_long), kMinSlipSpeed));
		const bool level_surface = std::abs(sample.normal_ned[0]) <= 1.0e-12 &&
			std::abs(sample.normal_ned[1]) <= 1.0e-12 && sample.normal_ned[2] <= -1.0 + 1.0e-12;
		if (normal_load > 0.0 && !(skip_static_friction && level_surface)) {
			if (contact_count >= kMaximumContacts) {
				result.error = "Too many tire/brake contacts";
				return false;
			}
			Contact &contact = contacts[contact_count++];
			contact.brake = false;
			contact.corner = corner;
			const Vec3 lever = add(r, rho_body);
			contact.rows[0] = contact_row(q_conjugate, forward_world, lever, r_prime, wheel_axis, rho_body, corner);
			contact.rows[1] = contact_row(q_conjugate, lateral_world, lever, r_prime, wheel_axis, rho_body, corner);
			contact.slip = {slip_long, slip_lateral};
			const Vec3 angular_convective = add(cross(body_rate, wheel_omega),
				add(scale(Vec3{0.0, 0.0, -1.0}, geometry.steering_acceleration_body[corner]),
					scale(geometry.spin_axis_rate_body[corner], wheel_spin)));
			const Vec3 point_bias_body = add(geometry.hub_bias_body[corner], cross(angular_convective, rho_body));
			const Vec3 point_bias_world = rotate(q, point_bias_body);
			if (!finite(point_bias_world) || !finite(hub_velocity)) {
				result.error = "Tire contact bias became non-finite";
				return false;
			}
			contact.bias = {dot(forward_world, point_bias_world), dot(lateral_world, point_bias_world)};
			contact.mu_load = tire_mu_normal[corner];
			contact.tau = m.tire_slip_relaxation_s;
		}
		if (brake_base > 0.0) {
			if (contact_count >= kMaximumContacts) {
				result.error = "Too many tire/brake contacts";
				return false;
			}
			Contact &contact = contacts[contact_count++];
			contact.brake = true;
			contact.corner = corner;
			contact.rows[0][10 + corner] = 1.0;
			contact.slip[0] = wheel_spin;
			contact.mu_load = brake_base;
			contact.tau = m.tire_slip_relaxation_s;
		}
		double torque = drive_base;
		if (m.drive_torque_fade_rad_s > 0.0) torque *= maxf(0.0, 1.0 - std::abs(wheel_spin) / m.drive_torque_fade_rad_s);
		rhs[10 + corner] += torque;
		if (normal_load > 0.0) {
			const double rolling_torque = m.rolling_resistance_coefficient * sample.rolling * normal_load * m.tire_radius_m
				* wheel_spin / std::sqrt(wheel_spin * wheel_spin + 1.0e-6);
			rhs[10 + corner] -= rolling_torque;
		}
		const double rotor_rate = dot(body_rate, wheel_axis) + wheel_spin;
		if (calculate_energy) total_rotor_kinetic += 0.5 * m.wheel_spin_inertia_kg_m2 * rotor_rate * rotor_rate;
		const Vec14 hub_bias_generalized = hub_generalized(r, r_prime, corner, m.unsprung_mass_kg, geometry.hub_bias_body[corner]);
		add_scaled(rhs, hub_bias_generalized, -1.0);
		const Vec14 gravity_generalized = hub_generalized(r, r_prime, corner, m.unsprung_mass_kg, gravity_body);
		add_scaled(rhs, gravity_generalized, 1.0);
		if (calculate_energy) {
			hub_kinetic += 0.5 * m.unsprung_mass_kg * dot(geometry.hub_speed_body[corner], geometry.hub_speed_body[corner]);
			gravity_potential -= m.unsprung_mass_kg * m.gravity_m_per_s2 * hub_world[2];
		}
	}

	for (std::size_t corner = 0; corner < 4; ++corner) {
		const Vec3 &axis = geometry.spin_axis_body[corner];
		const Vec3 &axis_rate = geometry.spin_axis_rate_body[corner];
		const double spin = state[21 + corner];
		const double axial_rate = dot(body_rate, axis) + spin;
		const Vec3 rotor_bias = add(scale(axis, dot(body_rate, axis_rate)),
			scale(add(axis_rate, cross(body_rate, axis)), axial_rate));
		for (std::size_t axis_index = 0; axis_index < 3; ++axis_index) rhs[3 + axis_index] -= m.wheel_spin_inertia_kg_m2 * rotor_bias[axis_index];
		rhs[10 + corner] -= m.wheel_spin_inertia_kg_m2 * dot(body_rate, axis_rate);
	}

	result.hull_in_contact.assign(m.hull_probe_radii_m.size(), false);
	for (std::size_t probe = 0; probe < m.hull_probe_radii_m.size(); ++probe) {
		const Vec3 &center = m.hull_probe_centers_frd_m[probe];
		const Vec3 center_world = add(position_world, rotate(q, center));
		const Surface &sample = surfaces[4 + probe];
		const Vec3 ground_point{center_world[0], center_world[1], -sample.height_m};
		const double signed_distance = dot(sample.normal_ned, sub(center_world, ground_point));
		const double penetration = maxf(m.hull_probe_radii_m[probe] - signed_distance, 0.0);
		const Vec3 center_velocity_body = add(body_velocity, cross(body_rate, center));
		const Vec3 center_velocity_world = rotate(q, center_velocity_body);
		const double normal_speed = dot(center_velocity_world, sample.normal_ned);
		const double hull_load = penetration > 0.0
			? maxf(0.0, m.hull_contact_stiffness_n_per_m * penetration - m.hull_contact_damping_n_s_per_m * normal_speed)
			: 0.0;
		result.hull_in_contact[probe] = hull_load > 0.0;
		if (calculate_energy) hull_energy += 0.5 * m.hull_contact_stiffness_n_per_m * penetration * penetration;
		if (hull_load <= 0.0) continue;
		const Vec3 hull_force_world = scale(sample.normal_ned, hull_load);
		const Vec3 hull_force_body = rotate(q_conjugate, hull_force_world);
		add_body_force(rhs, center, hull_force_body);
		const Vec3 rho_world_hull = scale(sample.normal_ned, -m.hull_probe_radii_m[probe]);
		const Vec3 rho_body_hull = rotate(q_conjugate, rho_world_hull);
		const Vec3 hull_contact_point_velocity = add(center_velocity_world,
			rotate(q, cross(body_rate, rho_body_hull)));
		const Vec3 hull_tangent = sub(hull_contact_point_velocity,
			scale(sample.normal_ned, dot(hull_contact_point_velocity, sample.normal_ned)));
		const double hull_tangent_speed = norm(hull_tangent);
		const double hull_friction_limit = maxf(0.0, sample.mu * m.hull_contact_friction_scale * hull_load);
		if (hull_tangent_speed > 1.0e-10 && hull_friction_limit > 0.0) {
			const Vec3 tangent_direction = scale(hull_tangent, -1.0 / hull_tangent_speed);
			const Vec3 tangent_force = scale(tangent_direction, hull_friction_limit * std::tanh(hull_tangent_speed / 0.02));
			add_body_force(rhs, add(center, rho_body_hull), rotate(q_conjugate, tangent_force));
		}
	}

	Factor factor;
	if (!factor_generalized_mass(matrix, factor, error)) {
		result.error = "Coupled generalized mass matrix is singular: " + error;
		return false;
	}
	if (!solve_generalized(factor, rhs, result.generalized_acceleration)) {
		result.error = "Unconstrained generalized acceleration is non-finite";
		return false;
	}
	if (!solve_tangent_friction(factor, result.generalized_acceleration, contacts, contact_count,
			adaptive_friction, result, error)) {
		result.error = error;
		return false;
	}
	std::size_t wheel_contact_count = 0;
	std::size_t hull_contact_count = 0;
	for (bool in_contact : result.wheel_in_contact) wheel_contact_count += in_contact ? 1 : 0;
	for (bool in_contact : result.hull_in_contact) hull_contact_count += in_contact ? 1 : 0;
	result.airborne = wheel_contact_count == 0 && hull_contact_count == 0;
	result.steering_acceleration_rad_per_s2 = servo_acceleration;
	result.energy_j = calculate_energy
		? energy(state, m, hub_kinetic, total_rotor_kinetic, gravity_potential, spring_energy, tire_energy, hull_energy)
		: 0.0;
	if (!std::isfinite(result.energy_j) || !finite(result.generalized_acceleration)) {
		result.error = "Evaluation result became non-finite";
		return false;
	}
	result.ok = true;
	return true;
}

} // namespace openrc::ground_vehicle
