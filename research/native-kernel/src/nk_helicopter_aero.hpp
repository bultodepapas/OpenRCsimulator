// Experimental compact helicopter aerodynamic stage. Mirrors the prepared, diagnostics-off paths in
// rotorcraft/aerodynamic_stage.gd and airframe.gd, including same-stage main/tail wake coupling.
#pragma once

#include <array>

#include "nk_helicopter_main_rotor.hpp"
#include "nk_helicopter_tail_rotor.hpp"

namespace nk {

struct HeliAirframeModel {
	R rho_kg_m3 = 0.0;
	std::array<R, 3> fuselage_area{};
	std::array<R, 3> fuselage_arm{}, vertical_fin_arm{}, horizontal_tail_arm{};
	R vertical_fin_area = 0.0, vertical_fin_lift_slope = 0.0;
	R horizontal_tail_area = 0.0, horizontal_tail_lift_slope = 0.0;
};

struct HeliAirframeResult {
	bool ok = false;
	std::array<R, 6> loads{};
	R relative_power = 0.0, body_power = 0.0, wake_power = 0.0;
};

inline HeliAirframeResult heli_airframe(const HeliAirframeModel &m, const std::array<R, 3> &cg_air,
		const std::array<R, 3> &rates, const std::array<R, 3> &fuselage_wake,
		const std::array<R, 3> &fin_wake, const std::array<R, 3> &tail_wake) {
	const R density_scale = 0.5 * m.rho_kg_m3;
	std::array<R, 27> pieces{};
	for (int index = 0; index < 3; ++index) {
		const std::array<R, 3> &arm = index == 0 ? m.fuselage_arm
			: (index == 1 ? m.vertical_fin_arm : m.horizontal_tail_arm);
		const std::array<R, 3> &wake = index == 0 ? fuselage_wake : (index == 1 ? fin_wake : tail_wake);
		const R area_x = index == 0 ? m.fuselage_area[0] : (index == 1 ? m.vertical_fin_area : m.horizontal_tail_area);
		const R area_y = index == 0 ? m.fuselage_area[1] : R(0.0);
		const R area_z = index == 0 ? m.fuselage_area[2] : R(0.0);
		const R lift_slope = index == 0 ? R(0.0) : (index == 1 ? m.vertical_fin_lift_slope : m.horizontal_tail_lift_slope);
		const R rx = arm[0], ry = arm[1], rz = arm[2];
		const R point_x = cg_air[0] + rates[1] * rz - rates[2] * ry;
		const R point_y = cg_air[1] + rates[2] * rx - rates[0] * rz;
		const R point_z = cg_air[2] + rates[0] * ry - rates[1] * rx;
		const R ux = point_x - wake[0];
		const R uy = point_y - wake[1];
		const R uz = point_z - wake[2];
		const R speed_squared = ux * ux + uy * uy + uz * uz;
		if (!heli_inflow_finite({point_x, point_y, point_z, ux, uy, uz, speed_squared})) {
			return {};
		}
		R fx = 0.0, fy = 0.0, fz = 0.0, ideal = 0.0, normal_force = 0.0;
		if (index == 0) {
			const R speed = sqrt_(speed_squared);
			fx = -density_scale * area_x * ux * speed;
			fy = -density_scale * area_y * uy * speed;
			fz = -density_scale * area_z * uz * speed;
		} else {
			const R scale = density_scale * area_x;
			if (index == 1) {
				const R in_plane = sqrt_(ux * ux + uz * uz);
				ideal = -scale * (lift_slope * in_plane + absf(uy)) * uy;
				const R cap = scale * speed_squared;
				if (!heli_inflow_finite({scale, in_plane, cap})) {
					return {};
				}
				fy = clampf(ideal, -cap, cap);
				normal_force = fy;
			} else {
				ideal = -scale * (lift_slope * absf(ux) + absf(uz)) * uz;
				const R cap = scale * (ux * ux + uz * uz);
				if (!heli_inflow_finite({scale, cap})) {
					return {};
				}
				fz = clampf(ideal, -cap, cap);
				normal_force = fz;
			}
		}
		const R mx = ry * fz - rz * fy;
		const R my = rz * fx - rx * fz;
		const R mz = rx * fy - ry * fx;
		const R relative_power = fx * ux + fy * uy + fz * uz;
		const R body_power = fx * point_x + fy * point_y + fz * point_z;
		const R wake_power = fx * wake[0] + fy * wake[1] + fz * wake[2];
		if (!heli_inflow_finite({fx, fy, fz, ideal, normal_force, mx, my, mz, relative_power, body_power, wake_power})) {
			return {};
		}
		const int base = index * 9;
		pieces[base] = fx;
		pieces[base + 1] = fy;
		pieces[base + 2] = fz;
		pieces[base + 3] = mx;
		pieces[base + 4] = my;
		pieces[base + 5] = mz;
		pieces[base + 6] = relative_power;
		pieces[base + 7] = body_power;
		pieces[base + 8] = wake_power;
	}
	HeliAirframeResult result;
	for (int i = 0; i < 6; ++i) {
		result.loads[i] = pieces[i] + pieces[i + 9] + pieces[i + 18];
		if (!is_finite(result.loads[i])) {
			return {};
		}
	}
	result.relative_power = pieces[6] + pieces[15] + pieces[24];
	result.body_power = pieces[7] + pieces[16] + pieces[25];
	result.wake_power = pieces[8] + pieces[17] + pieces[26];
	if (!heli_inflow_finite({result.relative_power, result.body_power, result.wake_power})) {
		return {};
	}
	result.ok = true;
	return result;
}

struct HeliAeroModel {
	HeliMainRotorModel main;
	HeliTailRotorModel tail;
	HeliAirframeModel airframe;
	R flow_floor_m_s = 0.0, fin_tail_wake_fraction = 0.0, height_over_radius = -1.0;
	R inflow_loss = 1.0, inflow_instability = 1.0;
};

struct HeliAeroResult {
	bool ok = false;
	std::array<R, 6> loads{};
	std::array<R, 3> derivative{};
	HeliMainRotorResult main;
	HeliTailRotorResult tail;
};

inline HeliAeroResult heli_aero_stage(const HeliAeroModel &m, const std::array<R, 3> &state, R omega,
		const std::array<R, 3> &cg_air, const std::array<R, 3> &rates, R collective, R cyclic_forward,
		R cyclic_right, R tail_collective, R height_over_radius, R thrust_axis_downworld_scalar) {
	if (!heli_inflow_finite({state[0], state[1], state[2], cg_air[0], cg_air[1], cg_air[2],
			rates[0], rates[1], rates[2], omega, collective, cyclic_forward, cyclic_right, tail_collective})
			|| (!is_nan(height_over_radius) && (!is_finite(height_over_radius)
				|| (height_over_radius < 0.0 && height_over_radius != -1.0)))
			|| (!is_nan(thrust_axis_downworld_scalar) && (!is_finite(thrust_axis_downworld_scalar)
				|| absf(thrust_axis_downworld_scalar) > 1.0 + 1.0e-10))) {
		return {};
	}
	const R stage_height = is_nan(height_over_radius) ? m.height_over_radius : height_over_radius;
	const std::array<R, 3> hub_air = {
		cg_air[0] + rates[1] * m.main.hub_z_m - rates[2] * m.main.hub_y_m,
		cg_air[1] + rates[2] * m.main.hub_x_m - rates[0] * m.main.hub_z_m,
		cg_air[2] + rates[0] * m.main.hub_y_m - rates[1] * m.main.hub_x_m};
	const HeliMainStageResult main = heli_main_stage(m.main, state, omega, hub_air, rates, collective,
		cyclic_forward, cyclic_right, m.flow_floor_m_s, stage_height, m.inflow_loss, m.inflow_instability,
		thrust_axis_downworld_scalar);
	if (!main.ok) {
		return {};
	}
	const HeliTailRotorResult tail = heli_tail_rotor(m.tail, omega, state[2], cg_air, rates, tail_collective,
		m.main.omega_nominal_rad_s);
	if (!tail.ok) {
		return {};
	}
	const std::array<R, 3> fuselage_wake = {0.0, 0.0, state[2]};
	const R vertical_wake = tail.wake_factor * state[2];
	const std::array<R, 3> fin_wake = {0.0, m.fin_tail_wake_fraction * tail.induced_velocity, vertical_wake};
	const std::array<R, 3> horizontal_wake = {0.0, 0.0, vertical_wake};
	const HeliAirframeResult airframe = heli_airframe(m.airframe, cg_air, rates, fuselage_wake, fin_wake, horizontal_wake);
	if (!airframe.ok) {
		return {};
	}
	HeliAeroResult result;
	for (int i = 0; i < 6; ++i) {
		result.loads[i] = main.rotor.loads[i] + tail.loads[i] + airframe.loads[i];
		if (!is_finite(result.loads[i])) {
			return {};
		}
	}
	result.derivative = main.derivative;
	result.main = main.rotor;
	result.tail = tail;
	result.ok = true;
	return result;
}

} // namespace nk
