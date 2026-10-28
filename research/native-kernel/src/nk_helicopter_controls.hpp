// Experimental X-Cell trainer electronics and 120-degree swash stage. The FBL body-rate laboratory-only law is not
// represented; a caller must verify the prepared trainer law and curves before using this component.
#pragma once

#include <array>

#include "nk_helicopter_inflow.hpp"

namespace nk {

struct HeliTrainerModel {
	// Five-point curves are copied from the selected mode. Decoder must validate and freeze both mode sets.
	std::array<R, 5> normal_pitch{}, normal_throttle{}, idle_pitch{}, idle_throttle{};
	R collective_rad_per_unit = 0.0, longitudinal_rad_per_unit = 0.0, lateral_rad_per_unit = 0.0;
	R collective_min_rad = 0.0, collective_max_rad = 0.0, cyclic_max_rad = 0.0;
	R tail_collective_trim_rad = 0.0, tail_collective_min_rad = 0.0, tail_collective_max_rad = 0.0;
	R yaw_control_sign = 0.0, yaw_deadzone = 0.0, yaw_max_rate_rad_s = 0.0, yaw_heading_gain_per_s = 0.0;
	R yaw_rate_kp_rad_per_rad_s = 0.0, yaw_rate_ki_rad_per_rad = 0.0, yaw_integrator_limit_rad = 0.0;
	R trainer_max_tilt_rad = 0.0, trainer_roll_attitude_gain_per_s = 0.0, trainer_pitch_attitude_gain_per_s = 0.0;
	R trainer_roll_rate_limit_rad_s = 0.0, trainer_pitch_rate_limit_rad_s = 0.0;
	R trainer_roll_cyclic_gain_rad_per_rad_s = 0.0, trainer_pitch_cyclic_gain_rad_per_rad_s = 0.0;
};

struct HeliTrim {
	R roll_reference_rad = 0.0, pitch_reference_rad = 0.0;
	R cyclic_forward_bias_rad = 0.0, cyclic_right_bias_rad = 0.0, tail_collective_bias_rad = 0.0;
	bool ground_precomp = false;
	R ground_yaw_precomp_tail_bias_rad = 0.0, ground_yaw_precomp_collective_rad = 0.0;
};

inline bool heli_trainer_trim_valid(const HeliTrim &trim, const HeliTrainerModel &m) {
	if (!heli_inflow_finite({trim.roll_reference_rad, trim.pitch_reference_rad, trim.cyclic_forward_bias_rad,
			trim.cyclic_right_bias_rad, trim.tail_collective_bias_rad})) {
		return false;
	}
	if (trim.ground_precomp) {
		if (!heli_inflow_finite({trim.ground_yaw_precomp_tail_bias_rad, trim.ground_yaw_precomp_collective_rad})
				|| trim.ground_yaw_precomp_collective_rad <= 0.0 || trim.ground_yaw_precomp_collective_rad > m.collective_max_rad) {
			return false;
		}
		const R baseline_tail = m.tail_collective_trim_rad + trim.tail_collective_bias_rad;
		const R reference_tail = baseline_tail + trim.ground_yaw_precomp_tail_bias_rad;
		if (baseline_tail < m.tail_collective_min_rad || baseline_tail > m.tail_collective_max_rad
				|| reference_tail < m.tail_collective_min_rad || reference_tail > m.tail_collective_max_rad) {
			return false;
		}
	}
	if (absf(trim.roll_reference_rad) >= kPi / 2.0 || absf(trim.pitch_reference_rad) >= kPi / 2.0
			|| absf(trim.cyclic_forward_bias_rad) > m.cyclic_max_rad
			|| absf(trim.cyclic_right_bias_rad) > m.cyclic_max_rad) {
		return false;
	}
	return absf(trim.tail_collective_bias_rad) <= m.tail_collective_max_rad - m.tail_collective_min_rad;
}

inline R heli_curve(const std::array<R, 5> &points, R input) {
	const R position = (input + 1.0) * 2.0;
	if (position >= 4.0) {
		return points[4];
	}
	const int lower_index = static_cast<int>(position.v);
	const R fraction = position - static_cast<double>(lower_index);
	const R lower = points[lower_index];
	const R upper = points[lower_index + 1];
	return lower + fraction * (upper - lower);
}

struct HeliControlResult {
	bool ok = false;
	R collective = 0.0, cyclic_forward = 0.0, cyclic_right = 0.0, tail_collective = 0.0, drive_fraction = 0.0;
	std::array<R, 2> controller_derivative{};
	const char *message = "";
};

inline HeliControlResult heli_control_failure(const char *message) {
	HeliControlResult result;
	result.message = message;
	return result;
}

inline HeliControlResult heli_trainer_electronics(const HeliTrainerModel &m, const R *state,
		const std::array<R, 4> &sticks, bool idle_up, bool trainer_enabled, const HeliTrim &trim) {
	if (!heli_trainer_trim_valid(trim, m)) {
		return heli_control_failure("invalid electronics context, state, mode or stick layout");
	}
	for (int i = 0; i < 19; ++i) {
		if (!is_finite(state[i])) {
			return heli_control_failure("electronics state is nonfinite");
		}
	}
	for (const R value : sticks) {
		if (!is_finite(value) || value < -1.0 || value > 1.0) {
			return heli_control_failure("pilot sticks must be finite and in [-1, 1]");
		}
	}
	if (absf(state[17]) > 1.0e12 || absf(state[18]) > 1.0e12) {
		return heli_control_failure("controller state is outside its finite operating range");
	}
	const R pitch_value = heli_curve(idle_up ? m.idle_pitch : m.normal_pitch, sticks[3]);
	const R throttle_value = heli_curve(idle_up ? m.idle_throttle : m.normal_throttle, sticks[3]);
	if (!is_finite(pitch_value) || pitch_value < -1.0 || pitch_value > 1.0
			|| !is_finite(throttle_value) || throttle_value < 0.0 || throttle_value > 1.0) {
		return heli_control_failure("prepared curve output is outside its finite domain");
	}
	R cyclic_longitudinal = sticks[0];
	R cyclic_lateral = sticks[1];
	const R w = state[6], x = state[7], y = state[8], z = state[9];
	const R yaw = atan2_(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z));
	const R pitch = asin_(2.0 * (w * y - z * x));
	const R roll = atan2_(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y));
	if (trainer_enabled) {
		const R desired_roll = clampf(trim.roll_reference_rad + cyclic_lateral * m.trainer_max_tilt_rad,
			-m.trainer_max_tilt_rad, m.trainer_max_tilt_rad);
		const R desired_pitch = clampf(trim.pitch_reference_rad - cyclic_longitudinal * m.trainer_max_tilt_rad,
			-m.trainer_max_tilt_rad, m.trainer_max_tilt_rad);
		const R desired_roll_rate = clampf(m.trainer_roll_attitude_gain_per_s * (desired_roll - roll),
			-m.trainer_roll_rate_limit_rad_s, m.trainer_roll_rate_limit_rad_s);
		const R desired_pitch_rate = clampf(m.trainer_pitch_attitude_gain_per_s * (desired_pitch - pitch),
			-m.trainer_pitch_rate_limit_rad_s, m.trainer_pitch_rate_limit_rad_s);
		const R lateral_command = m.trainer_roll_cyclic_gain_rad_per_rad_s * (desired_roll_rate - state[10]);
		const R longitudinal_command = -m.trainer_pitch_cyclic_gain_rad_per_rad_s * (desired_pitch_rate - state[11]);
		cyclic_lateral = clampf(lateral_command / m.lateral_rad_per_unit, -1.0, 1.0);
		cyclic_longitudinal = clampf(longitudinal_command / m.longitudinal_rad_per_unit, -1.0, 1.0);
	}
	if (!heli_inflow_finite({pitch_value, cyclic_longitudinal, cyclic_lateral})
			|| cyclic_longitudinal < -1.0 || cyclic_longitudinal > 1.0
			|| cyclic_lateral < -1.0 || cyclic_lateral > 1.0) {
		return heli_control_failure("swash mix refused the physical stick commands");
	}
	const R root_three = sqrt_(3.0);
	const R front = clampf(pitch_value + cyclic_longitudinal, -1.0, 1.0);
	const R rear_right = clampf(pitch_value - 0.5 * cyclic_longitudinal + 0.5 * root_three * cyclic_lateral, -1.0, 1.0);
	const R rear_left = clampf(pitch_value - 0.5 * cyclic_longitudinal - 0.5 * root_three * cyclic_lateral, -1.0, 1.0);
	const R collective_axis = (front + rear_right + rear_left) / 3.0;
	const R longitudinal_axis = (2.0 * front - rear_right - rear_left) / 3.0;
	const R lateral_axis = (rear_right - rear_left) / root_three;
	const R collective_raw = collective_axis * m.collective_rad_per_unit;
	const R longitudinal_raw = longitudinal_axis * m.longitudinal_rad_per_unit;
	const R lateral_raw = lateral_axis * m.lateral_rad_per_unit;
	if (!heli_inflow_finite({collective_raw, longitudinal_raw, lateral_raw})) {
		return heli_control_failure("swash linkage refused the mixed commands");
	}
	const R theta0 = clampf(collective_raw, m.collective_min_rad, m.collective_max_rad);
	const R swash_long = clampf(longitudinal_raw, -m.cyclic_max_rad, m.cyclic_max_rad);
	const R swash_lateral = clampf(lateral_raw, -m.cyclic_max_rad, m.cyclic_max_rad);
	const R cyclic_forward = clampf(swash_long + trim.cyclic_forward_bias_rad, -m.cyclic_max_rad, m.cyclic_max_rad);
	const R cyclic_right = clampf(swash_lateral + trim.cyclic_right_bias_rad, -m.cyclic_max_rad, m.cyclic_max_rad);
	const R yaw_stick = sticks[2];
	const R manual_yaw_rate = absf(yaw_stick) > m.yaw_deadzone ? yaw_stick * m.yaw_max_rate_rad_s : R(0.0);
	const R difference = state[17] - yaw;
	const R heading_error = atan2_(sin_(difference), cos_(difference));
	const R target_yaw_rate = clampf(manual_yaw_rate + m.yaw_heading_gain_per_s * heading_error,
		-m.yaw_max_rate_rad_s, m.yaw_max_rate_rad_s);
	const R yaw_rate_error = target_yaw_rate - state[12];
	const R integrator = clampf(state[18], -m.yaw_integrator_limit_rad, m.yaw_integrator_limit_rad);
	R ground_precomp = 0.0;
	if (trim.ground_precomp) {
		ground_precomp = trim.ground_yaw_precomp_tail_bias_rad
			* clampf(theta0 / trim.ground_yaw_precomp_collective_rad, 0.0, 1.0);
	}
	const R tail_unsaturated = m.tail_collective_trim_rad + trim.tail_collective_bias_rad + ground_precomp
		+ m.yaw_control_sign * (m.yaw_rate_kp_rad_per_rad_s * yaw_rate_error + m.yaw_rate_ki_rad_per_rad * integrator);
	const R tail_collective = clampf(tail_unsaturated, m.tail_collective_min_rad, m.tail_collective_max_rad);
	R integral_rate = yaw_rate_error;
	const R integral_output_rate = m.yaw_control_sign * m.yaw_rate_ki_rad_per_rad * integral_rate;
	if ((tail_unsaturated > m.tail_collective_max_rad && integral_output_rate > 0.0)
			|| (tail_unsaturated < m.tail_collective_min_rad && integral_output_rate < 0.0)
			|| (integrator >= m.yaw_integrator_limit_rad && integral_rate > 0.0)
			|| (integrator <= -m.yaw_integrator_limit_rad && integral_rate < 0.0)) {
		integral_rate = 0.0;
	}
	const R heading_rate = absf(yaw_stick) > m.yaw_deadzone ? manual_yaw_rate : R(0.0);
	return {true, theta0, cyclic_forward, cyclic_right, tail_collective, throttle_value, {heading_rate, integral_rate}};
}

} // namespace nk
