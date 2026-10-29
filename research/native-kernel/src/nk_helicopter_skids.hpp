// Experimental diagnostics-off mirror of rotorcraft/skid_contact.gd evaluate. Collision/strike detection remains
// outside this pure stage helper. The surface table is prepared/validated by the owning session.
#pragma once

#include <array>

#include "nk_hull.hpp"
#include "nk_wheels.hpp"

namespace nk {

struct HeliSkidModel {
	std::array<R, 12> points_body_frd_m{};
	R reach_m = 0.0, spring_n_m = 0.0, damping_n_s_m = 0.0, friction = 0.0, slip_m_s = 0.0;
};

struct HeliSkidResult {
	bool ok = false;
	std::array<R, 6> loads{};
	R max_depth = 0.0;
	std::array<R, 8> bristle_derivative{};
};

inline HeliSkidResult heli_skids(const R *state, const HeliSkidModel &cfg, const SurfaceTable &surfaces,
		const std::array<R, 8> *bristles) {
	HeliSkidResult out;
	if (bristles != nullptr) {
		for (const R value : *bristles) {
			if (!is_finite(value)) {
				return out;
			}
		}
	}
	if (-state[2] > cfg.reach_m + max_height_validated(surfaces)) {
		if (bristles != nullptr) {
			for (int i = 0; i < 8; ++i) {
				out.bristle_derivative[i] = -(*bristles)[i] / 0.2;
			}
		}
		out.ok = true;
		return out;
	}
	const R norm_q = sqrt_(state[6] * state[6] + state[7] * state[7] + state[8] * state[8] + state[9] * state[9]);
	const R q[4] = {state[6] / norm_q, state[7] / norm_q, state[8] / norm_q, state[9] / norm_q};
	const R inverse[4] = {q[0], -q[1], -q[2], -q[3]};
	static const LakeTerrain no_lake;
	for (int point_index = 0; point_index < 4; ++point_index) {
		const int i = point_index * 3;
		const Vec3 arm = {cfg.points_body_frd_m[i], cfg.points_body_frd_m[i + 1], cfg.points_body_frd_m[i + 2]};
		const Vec3 offset = q_rotate3(q, arm.data());
		const Vec3 terrain = terrain_sample_validated(state[0] + offset[0], state[1] + offset[1], surfaces, no_lake);
		const R norm = sqrt_(1.0 + terrain[1] * terrain[1] + terrain[2] * terrain[2]);
		const Vec3 up = {-terrain[1] / norm, -terrain[2] / norm, -1.0 / norm};
		const Vec3 normal = q_rotate3(inverse, up.data());
		const R depth = (state[2] + offset[2] + terrain[0]) / norm;
		out.max_depth = maxf(out.max_depth, depth);
		const int memory = point_index * 2;
		if (depth <= 0.0) {
			if (bristles != nullptr) {
				out.bristle_derivative[memory] = -(*bristles)[memory] / 0.2;
				out.bristle_derivative[memory + 1] = -(*bristles)[memory + 1] / 0.2;
			}
			continue;
		}
		const Vec3 rates = {state[10], state[11], state[12]};
		Vec3 point_velocity = cross3(rates, arm);
		for (int axis = 0; axis < 3; ++axis) {
			point_velocity[axis] += state[3 + axis];
		}
		const R v_up = normal[0] * point_velocity[0] + normal[1] * point_velocity[1] + normal[2] * point_velocity[2];
		const R force_n = maxf(0.0, cfg.spring_n_m * depth - cfg.damping_n_s_m * v_up);
		const R world_north = state[0] + offset[0];
		const R world_east = state[1] + offset[1];
		bool flat_rotorpad = false;
		std::size_t surface_index = 0;
		if (bristles != nullptr && !surfaces.values.empty()) {
			surface_index = wheel_surface_at(surfaces.values, world_north, world_east);
			flat_rotorpad = surface_index + 5 < surfaces.values.size()
				&& surfaces.values[surface_index + 5] == kRollingRotorpad
				&& absf(terrain[1]) <= 1.0e-12 && absf(terrain[2]) <= 1.0e-12;
		}
		Vec3 tangent_force_body = {0.0, 0.0, 0.0};
		if (flat_rotorpad && force_n > 1.0e-8) {
			const R friction_factor = surfaces.values[surface_index + 4];
			const R mu = cfg.friction * friction_factor;
			const R stiffness = cfg.spring_n_m;
			const R damping = cfg.damping_n_s_m;
			const Vec3 world_velocity = q_rotate3(q, point_velocity.data());
			const R speed = sqrt_(world_velocity[0] * world_velocity[0] + world_velocity[1] * world_velocity[1]);
			const R capacity = mu * force_n;
			const R z_max = stiffness > 0.0 ? capacity / stiffness : R(0.0);
			const R z_north = (*bristles)[memory];
			const R z_east = (*bristles)[memory + 1];
			if (is_finite(mu) && mu > 0.0 && is_finite(damping) && damping >= 0.0 && z_max > 0.0) {
				const R raw_north = -stiffness * z_north - damping * world_velocity[0];
				const R raw_east = -stiffness * z_east - damping * world_velocity[1];
				const R raw_magnitude = sqrt_(raw_north * raw_north + raw_east * raw_east);
				const R scale = raw_magnitude > 0.0 ? minf(1.0, capacity / raw_magnitude) : R(1.0);
				const R force_north = scale * raw_north;
				const R force_east = scale * raw_east;
				const R relaxation_rate = minf(speed / z_max, 100.0);
				out.bristle_derivative[memory] = scale * world_velocity[0] - relaxation_rate * z_north;
				out.bristle_derivative[memory + 1] = scale * world_velocity[1] - relaxation_rate * z_east;
				const Vec3 world_tangent = {force_north, force_east, 0.0};
				tangent_force_body = q_rotate3(inverse, world_tangent.data());
			} else {
				out.bristle_derivative[memory] = -(*bristles)[memory] / 0.2;
				out.bristle_derivative[memory + 1] = -(*bristles)[memory + 1] / 0.2;
			}
		} else {
			if (bristles != nullptr) {
				out.bristle_derivative[memory] = -(*bristles)[memory] / 0.2;
				out.bristle_derivative[memory + 1] = -(*bristles)[memory + 1] / 0.2;
			}
			const Vec3 tangent = {point_velocity[0] - v_up * normal[0], point_velocity[1] - v_up * normal[1],
				point_velocity[2] - v_up * normal[2]};
			const R slip = sqrt_(tangent[0] * tangent[0] + tangent[1] * tangent[1] + tangent[2] * tangent[2]);
			const R drag = cfg.friction * force_n / maxf(cfg.slip_m_s, slip);
			tangent_force_body = {tangent[0] * -drag, tangent[1] * -drag, tangent[2] * -drag};
		}
		const Vec3 force = {force_n * normal[0] + tangent_force_body[0], force_n * normal[1] + tangent_force_body[1],
			force_n * normal[2] + tangent_force_body[2]};
		const Vec3 moment = cross3(arm, force);
		for (int axis = 0; axis < 3; ++axis) {
			out.loads[axis] += force[axis];
			out.loads[axis + 3] += moment[axis];
		}
	}
	for (const R value : out.loads) {
		if (!is_finite(value)) {
			return {};
		}
	}
	if (bristles != nullptr) {
		for (const R value : out.bristle_derivative) {
			if (!is_finite(value)) {
				return {};
			}
		}
	}
	out.ok = true;
	return out;
}

} // namespace nk
