// Draft prepared port of app/physics/retractable_gear.gd. The caller supplies
// normalized source geometry and a tick-held extension; no actuator state is
// advanced from an RK stage. Until the component and stage oracles pass this
// remains research-only and is not an aircraft admission decision.
#pragma once

#include <array>
#include <vector>

#include "nk_wheels.hpp"

namespace nk {

struct RetractableModel {
	bool enabled = false;
	R extension_time = 0.0, retraction_time = 0.0, drag_area = 0.0;
	std::array<R, 3> drag_center{};
	std::vector<std::vector<R>> paths; // one flat XYZ path per prepared wheel, authored order
};

inline bool retractable_valid_fraction(R x) { return is_finite(x) && x >= 0.0 && x <= 1.0; }

inline R retractable_advance(R extension, R target, R dt, const RetractableModel &m) {
	if (!retractable_valid_fraction(extension) || (target != 0.0 && target != 1.0) ||
		!is_finite(dt) || dt <= 0.0 || !m.enabled) return kNan;
	const R duration = target > extension ? m.extension_time : m.retraction_time;
	if (!is_finite(duration) || duration <= 0.0) return kNan;
	const R step = dt / duration;
	if (absf(target - extension) <= step + 1.0e-12) return target;
	const R difference = target - extension;
	const R sign = difference > 0.0 ? R(1.0) : (difference < 0.0 ? R(-1.0) : R(0.0));
	return extension + step * sign;
}

inline Vec3 retractable_path_point(const std::vector<R> &path, R extension) {
	const int count = static_cast<int>(path.size() / 3);
	if (count < 2 || path.size() % 3 != 0 || !retractable_valid_fraction(extension)) return {kNan, kNan, kNan};
	const R at = extension * static_cast<double>(count - 1);
	const int left = std::min(static_cast<int>(::floor(at.v)), count - 2);
	const R fraction = at - static_cast<double>(left);
	Vec3 point;
	for (int axis = 0; axis < 3; ++axis) {
		point[axis] = path[left * 3 + axis] + fraction * (path[(left + 1) * 3 + axis] - path[left * 3 + axis]);
	}
	return point;
}

// False = the reference's empty pose for an invalid partial extension. A
// full-down/disabled call retains the original gear and all its coefficients.
inline bool retractable_pose(const PreparedGear &base, const RetractableModel &m, R extension, PreparedGear &out) {
	if (!m.enabled || extension == 1.0) { out = base; return true; }
	if (!retractable_valid_fraction(extension) || m.paths.size() != base.contacts.size()) return false;
	out = base;
	for (std::size_t i = 0; i < out.contacts.size(); ++i) {
		WheelContact &contact = out.contacts[i];
		const Vec3 point = retractable_path_point(m.paths[i], extension);
		for (int axis = 0; axis < 3; ++axis) contact.position[axis] = point[axis];
		contact.stiffness = 0.0;
		contact.damping = 0.0;
		contact.max_steering = 0.0;
		contact.anchor_stiffness = 0.0;
		contact.anchor_damping = 0.0;
	}
	return true;
}

inline bool retractable_finite3(const R *v) {
	return is_finite(v[0]) && is_finite(v[1]) && is_finite(v[2]);
}

// The delta contains only R^T(W_O-W_drag), never omega x r. An explicit all-zero
// vector validates like the reference but preserves the original no-delta arithmetic.
inline std::vector<R> retractable_drag(const R *s, const R *air, const RetractableModel &m, R extension, R density,
		const R *ambient_delta = nullptr, int ambient_delta_size = 0) {
	if (!m.enabled || extension == 0.0) return {};
	if (!retractable_valid_fraction(extension) || !is_finite(density) || density <= 0.0) return {kNan};
	const bool has_spatial = ambient_delta != nullptr || ambient_delta_size != 0;
	bool has_local_delta = false;
	if (has_spatial) {
		if (ambient_delta == nullptr || ambient_delta_size != 3 || !retractable_finite3(ambient_delta) ||
			!retractable_finite3(air) || !retractable_finite3(m.drag_center.data()) || !is_finite(m.drag_area) ||
			m.drag_area < 0.0 || !is_finite(s[10]) || !is_finite(s[11]) || !is_finite(s[12])) return {kNan};
		has_local_delta = ambient_delta[0] != 0.0 || ambient_delta[1] != 0.0 || ambient_delta[2] != 0.0;
	}
	R local_air[3] = {air[0], air[1], air[2]};
	if (has_local_delta) {
		for (int axis = 0; axis < 3; ++axis) {
			local_air[axis] += ambient_delta[axis];
			if (!is_finite(local_air[axis])) return {kNan};
		}
	}
	const auto &arm = m.drag_center;
	const R rates[3] = {s[10], s[11], s[12]};
	const R rotation[3] = {rates[1] * arm[2] - rates[2] * arm[1], rates[2] * arm[0] - rates[0] * arm[2],
		rates[0] * arm[1] - rates[1] * arm[0]};
	const R velocity[3] = {local_air[0] + rotation[0], local_air[1] + rotation[1], local_air[2] + rotation[2]};
	if (has_spatial && !retractable_finite3(velocity)) return {kNan};
	const R speed = sqrt_(velocity[0] * velocity[0] + velocity[1] * velocity[1] + velocity[2] * velocity[2]);
	if (has_spatial && !is_finite(speed)) return {kNan};
	const R scale = -0.5 * density * m.drag_area * extension * speed;
	const R force[3] = {velocity[0] * scale, velocity[1] * scale, velocity[2] * scale};
	const R moment[3] = {arm[1] * force[2] - arm[2] * force[1], arm[2] * force[0] - arm[0] * force[2],
		arm[0] * force[1] - arm[1] * force[0]};
	if (has_spatial && (!retractable_finite3(force) || !retractable_finite3(moment))) return {kNan};
	return {force[0], force[1], force[2], moment[0], moment[1], moment[2]};
}

} // namespace nk
