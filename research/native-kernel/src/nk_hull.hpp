// NK-3: soft crash-hull contacts, mirroring app/physics/hull_contact.gd loads(s, prepared) with default arguments
// (no precomputed lake samples, no diagnostics): touching count, LU-25-R4 hull-clear-of-lake early-out, the lake
// branch (_lake_sample, _lake_compression, _lake_load) and the flat-field branch with GP-07c airframe friction.
// Static coefficients come from HullContact.prepare; the separate live-mass
// entry point below accepts a prepared geometry-only hull and mass snapshot.
#pragma once

#include <array>
#include <vector>

#include "nk_terrain.hpp"
#include "nk_liquid_mass.hpp"

namespace nk {

constexpr double kHullOmega = 60.0;
constexpr double kHullDampingOnset = 0.004;
constexpr double kHullFrictionMu = 0.4;
constexpr double kHullFrictionRateMax = 120.0;
constexpr double kHullSlipRegularizationMin = 0.01;
constexpr int kAirframeStride = 5;

struct HullPrepared {
	bool present = false;
	std::vector<R> points;
	std::vector<R> stiffness;
	std::vector<R> damping;
	R reach = 0.0;
	std::vector<double> surfaces; // airframe friction table, stride 5
	LakeTerrain lake;
	bool has_bounds = false;
	double bounds[4] = {0.0, 0.0, 0.0, 0.0};
};

inline std::array<R, 3> q_rotate3(const R *q, const R *v) {
	const R tx = (q[2] * v[2] - q[3] * v[1]) * 2.0;
	const R ty = (q[3] * v[0] - q[1] * v[2]) * 2.0;
	const R tz = (q[1] * v[1] - q[2] * v[0]) * 2.0;
	return {(v[0] + tx * q[0]) + (q[2] * tz - q[3] * ty), (v[1] + ty * q[0]) + (q[3] * tx - q[1] * tz),
		(v[2] + tz * q[0]) + (q[1] * ty - q[2] * tx)};
}

inline R hull_friction_at(const std::vector<double> &surfaces, R north, R east) {
	if (surfaces.empty()) {
		return kHullFrictionMu;
	}
	int i = 0;
	const int size = static_cast<int>(surfaces.size());
	while (i + kAirframeStride < size) {
		if (north.v >= surfaces[i] && north.v <= surfaces[i + 1] && east.v >= surfaces[i + 2] && east.v <= surfaces[i + 3]) {
			return surfaces[i + 4];
		}
		i += kAirframeStride;
	}
	return surfaces[i + 4];
}

inline R hull_slip_regularization(R mu, R f_up, R m_min, int touching) {
	return maxf(kHullSlipRegularizationMin, R(static_cast<double>(touching)) * mu * f_up / (m_min * kHullFrictionRateMax));
}

inline bool hull_clear_of_lake(const R *s, const HullPrepared &h) {
	if (!h.has_bounds) {
		return false;
	}
	const R qq = s[6] * s[6] + s[7] * s[7] + s[8] * s[8] + s[9] * s[9];
	const R radius = h.reach * (1.0 + 4.0 * qq) + 0.001;
	return (s[0] + radius).v < h.bounds[0] || (s[0] - radius).v > h.bounds[1] || (s[1] + radius).v < h.bounds[2] ||
		(s[1] - radius).v > h.bounds[3];
}

// hull_contact.gd _lake_sample: bounds without margin, then the full lake sampler.
inline LakeCover hull_lake_sample(const HullPrepared &h, const std::array<R, 3> &point_ned) {
	if (h.has_bounds && ((point_ned[0]).v < h.bounds[0] || point_ned[0].v > h.bounds[1] || point_ned[1].v < h.bounds[2] ||
			point_ned[1].v > h.bounds[3])) {
		return LakeCover();
	}
	return lake_sample_terrain(h.lake, point_ned[0], point_ned[1]);
}

inline R hull_lake_compression(const std::array<R, 3> &point_ned, const LakeCover &terrain) {
	const R normal_length = sqrt_(terrain.down_north * terrain.down_north + terrain.down_east * terrain.down_east + R(1.0) * 1.0);
	return (point_ned[2] - terrain.down) / normal_length;
}

// hull_contact.gd _lake_load; returns false for the reference's empty result.
inline bool hull_lake_load(const R *s, const HullPrepared &h, int point, const R *body_point,
		const std::array<R, 3> &point_ned, const LakeCover &terrain, int touching, std::array<R, 6> &out) {
	if (!is_finite(terrain.down_north) || !is_finite(terrain.down_east)) {
		return false;
	}
	Vec3 normal;
	if (!normal_from_up_slopes(-terrain.down_north, -terrain.down_east, normal)) {
		return false;
	}
	const R normal_length = sqrt_(terrain.down_north * terrain.down_north + terrain.down_east * terrain.down_east + R(1.0) * 1.0);
	const R compression = (point_ned[2] - terrain.down) / normal_length;
	if (compression.v <= 0.0) {
		return false;
	}
	const R *q = s + 6;
	const R velocity_body[3] = {s[3] + (s[11] * body_point[2] - s[12] * body_point[1]),
		s[4] + (s[12] * body_point[0] - s[10] * body_point[2]), s[5] + (s[10] * body_point[1] - s[11] * body_point[0])};
	const std::array<R, 3> velocity_ned = q_rotate3(q, velocity_body);
	const R normal_rate = -(velocity_ned[0] * normal[0] + velocity_ned[1] * normal[1] + velocity_ned[2] * normal[2]);
	const R onset = minf(compression / kHullDampingOnset, 1.0);
	const R f_up = h.stiffness[point] * compression + h.damping[point] * onset * normal_rate;
	if (f_up.v <= 0.0) {
		return false;
	}
	const R normal_speed = velocity_ned[0] * normal[0] + velocity_ned[1] * normal[1] + velocity_ned[2] * normal[2];
	const R tangent[3] = {velocity_ned[0] - normal[0] * normal_speed, velocity_ned[1] - normal[1] * normal_speed,
		velocity_ned[2] - normal[2] * normal_speed};
	const R slip = sqrt_(tangent[0] * tangent[0] + tangent[1] * tangent[1] + tangent[2] * tangent[2]);
	const R m_min = h.stiffness[point] / (kHullOmega * kHullOmega);
	const R friction_scale = kHullFrictionMu * f_up /
		maxf(slip, hull_slip_regularization(kHullFrictionMu, f_up, m_min, touching));
	const R force_ned[3] = {normal[0] * f_up - tangent[0] * friction_scale, normal[1] * f_up - tangent[1] * friction_scale,
		normal[2] * f_up - tangent[2] * friction_scale};
	const R q_inverse[4] = {q[0], -q[1], -q[2], -q[3]};
	const std::array<R, 3> fb = q_rotate3(q_inverse, force_ned);
	out = {fb[0], fb[1], fb[2], body_point[1] * fb[2] - body_point[2] * fb[1], body_point[2] * fb[0] - body_point[0] * fb[2],
		body_point[0] * fb[1] - body_point[1] * fb[0]};
	return true;
}

// hull_contact.gd loads(s, prepared). `touched` false = the reference's empty array.
inline bool hull_loads(const R *s, const HullPrepared &h, std::array<R, 6> &out) {
	out = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	if (!h.present || (-s[2]).v > h.reach.v) {
		return false;
	}
	const int count = static_cast<int>(h.points.size()) / 3;
	const R w = s[6], x = s[7], y = s[8], z = s[9];
	const R north[3] = {1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - w * z), 2.0 * (x * z + w * y)};
	const R east[3] = {2.0 * (x * y + w * z), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - w * x)};
	const R down[3] = {2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)};
	bool touched = false;
	bool lake_sampled = h.lake.present;
	static thread_local std::vector<std::array<R, 3>> points_ned;
	static thread_local std::vector<LakeCover> samples;
	points_ned.clear();
	samples.clear();
	if (lake_sampled) {
		lake_sampled = !hull_clear_of_lake(s, h);
		for (int i = 0; lake_sampled && i < count; ++i) {
			const R *bp = &h.points[i * 3];
			const std::array<R, 3> rotated = q_rotate3(s + 6, bp);
			const std::array<R, 3> point_ned = {s[0] + rotated[0], s[1] + rotated[1], s[2] + rotated[2]};
			points_ned.push_back(point_ned);
			samples.push_back(hull_lake_sample(h, point_ned));
		}
	}
	int touching = 0;
	for (int i = 0; i < count; ++i) {
		const R *r = &h.points[i * 3];
		if (lake_sampled && samples[i].covered) {
			if (hull_lake_compression(points_ned[i], samples[i]).v > 0.0) {
				++touching;
			}
		} else if ((s[2] + down[0] * r[0] + down[1] * r[1] + down[2] * r[2]).v > 0.0) {
			++touching;
		}
	}
	for (int i = 0; i < count; ++i) {
		const R *body_point = &h.points[i * 3];
		if (lake_sampled && samples[i].covered) {
			std::array<R, 6> lake_load;
			if (hull_lake_load(s, h, i, body_point, points_ned[i], samples[i], touching, lake_load)) {
				for (int axis = 0; axis < 6; ++axis) {
					out[axis] += lake_load[axis];
				}
				touched = true;
			}
			continue;
		}
		const R rx = body_point[0];
		const R ry = body_point[1];
		const R rz = body_point[2];
		const R depth = s[2] + down[0] * rx + down[1] * ry + down[2] * rz;
		if (depth.v <= 0.0) {
			continue;
		}
#ifdef NK_MUTATION
		const R vx = s[3] + (s[11] * rz - s[12] * ry); // negative control: reassociated sum
#else
		const R vx = s[3] + s[11] * rz - s[12] * ry;
#endif
		const R vy = s[4] + s[12] * rx - s[10] * rz;
		const R vz = s[5] + s[10] * ry - s[11] * rx;
		const R rate = down[0] * vx + down[1] * vy + down[2] * vz;
		const R onset = minf(depth / kHullDampingOnset, 1.0);
		const R f_up = h.stiffness[i] * depth + h.damping[i] * onset * rate;
		if (f_up.v <= 0.0) {
			continue;
		}
		const R vn = north[0] * vx + north[1] * vy + north[2] * vz;
		const R ve = east[0] * vx + east[1] * vy + east[2] * vz;
		const R slip = sqrt_(vn * vn + ve * ve);
		R mu = kHullFrictionMu;
		if (!h.surfaces.empty()) {
			mu = hull_friction_at(h.surfaces, s[0] + north[0] * rx + north[1] * ry + north[2] * rz,
				s[1] + east[0] * rx + east[1] * ry + east[2] * rz);
		}
		const R m_min = h.stiffness[i] / (kHullOmega * kHullOmega);
		const R scale = mu * f_up / maxf(slip, hull_slip_regularization(mu, f_up, m_min, touching));
		const R f_n = -scale * vn;
		const R f_e = -scale * ve;
		const R fx = f_n * north[0] + f_e * east[0] - f_up * down[0];
		const R fy = f_n * north[1] + f_e * east[1] - f_up * down[1];
		const R fz = f_n * north[2] + f_e * east[2] - f_up * down[2];
		out[0] += fx;
		out[1] += fy;
		out[2] += fz;
		out[3] += ry * fz - rz * fy;
		out[4] += rz * fx - rx * fz;
		out[5] += rx * fy - ry * fx;
		touched = true;
	}
	return touched;
}

// Live-mass counterpart of HullContact.loads_at_properties. A geometry-only
// HullPrepared uses present/points/reach/surfaces/lake/bounds; its stiffness
// and damping arrays are deliberately empty until an active contact exists.
struct LiveHullResult {
	bool ok = false, touched = false;
	const char *reason = "";
	std::array<R, 6> loads{};
};

inline LiveHullResult live_hull_failure(const char *reason) {
	LiveHullResult result;
	result.reason = reason;
	return result;
}

inline bool live_hull_psd(const std::array<R, 6> &v) {
	if (!liquid_finite6(v)) return false;
	const R scale = maxf(maxf(absf(v[0]), absf(v[1])), maxf(absf(v[2]), maxf(absf(v[3]), maxf(absf(v[4]), absf(v[5])))));
	if (scale == 0.0) return true;
	const R a = v[0] / scale, b = v[1] / scale, c = v[2] / scale;
	const R d = v[3] / scale, e = v[4] / scale, f = v[5] / scale;
	if (a < -1.0e-12 || b < -1.0e-12 || c < -1.0e-12) return false;
	if (a * b - d * d < -1.0e-12 || a * c - e * e < -1.0e-12 || b * c - f * f < -1.0e-12) return false;
	return a * (b * c - f * f) + d * (e * f - d * c) + e * (d * f - b * e) >= -1.0e-12;
}

inline bool live_hull_physical_tensor(const std::array<R, 6> &v) {
	if (!live_hull_psd(v)) return false;
	const R scale = liquid_tensor_scale(v);
	if (scale == 0.0) return true;
	const auto n = liquid_normalized_tensor(v, scale);
	const R half_trace = (n[0] + n[1] + n[2]) * 0.5;
	return live_hull_psd({half_trace - n[0], half_trace - n[1], half_trace - n[2], -n[3], -n[4], -n[5]});
}

inline Vec3 live_hull_inertia_mul(const std::array<R, 6> &j, const Vec3 &v) {
	return {j[0] * v[0] + j[3] * v[1] + j[4] * v[2], j[3] * v[0] + j[1] * v[1] + j[5] * v[2],
		j[4] * v[0] + j[5] * v[1] + j[2] * v[2]};
}

inline const char *live_hull_properties_error(const LiquidMassProperties &p) {
	if (!p.ok) return "mass_properties_not_ok";
	if (!is_finite(p.mass_kg) || p.mass_kg <= 0.0 || !is_finite(p.cg[0]) || !is_finite(p.cg[1]) ||
		!is_finite(p.cg[2]) || !live_hull_physical_tensor(p.inertia) || !liquid_finite6(p.inverse)) {
		return "mass_properties_invalid_value";
	}
	const Vec3 columns[3] = {{p.inverse[0], p.inverse[3], p.inverse[4]},
		{p.inverse[3], p.inverse[1], p.inverse[5]}, {p.inverse[4], p.inverse[5], p.inverse[2]}};
	for (int column = 0; column < 3; ++column) {
		const Vec3 product = live_hull_inertia_mul(p.inertia, columns[column]);
		for (int row = 0; row < 3; ++row) {
			const R expected = row == column ? R(1.0) : R(0.0);
			if (!is_finite(product[row]) || absf(product[row] - expected) > 1.0e-8) return "mass_properties_inverse_mismatch";
		}
	}
	return "";
}

inline LiveHullResult hull_loads_at_properties(const R *s, const HullPrepared &geometry, const LiquidMassProperties &p) {
	const char *property_error = live_hull_properties_error(p);
	if (property_error[0] != '\0') return live_hull_failure(property_error);
	if (!geometry.present || geometry.points.empty() || geometry.points.size() % 3 != 0 || !is_finite(geometry.reach)) {
		return live_hull_failure("invalid_contact_geometry");
	}
	for (int i = 0; i < 13; ++i) if (!is_finite(s[i])) return live_hull_failure("invalid_rigid_body_state");
	if (-s[2] > geometry.reach) return {true, false, "", {}};
	const int count = static_cast<int>(geometry.points.size() / 3);
	const R w = s[6], x = s[7], y = s[8], z = s[9];
	const R down[3] = {2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)};
	// Lake's conservative datum test precedes every individual coverage sample.
	if (geometry.lake.present) {
		bool may_contact = false;
		for (int i = 0; i < count; ++i) {
			const R *arm = &geometry.points[3 * i];
			const R depth = s[2] + down[0] * arm[0] + down[1] * arm[1] + down[2] * arm[2];
			if (!is_finite(depth)) return live_hull_failure("invalid_contact_geometry");
			const auto rotated = q_rotate3(s + 6, arm);
			const R point[3] = {s[0] + rotated[0], s[1] + rotated[1], s[2] + rotated[2]};
			if (!is_finite(point[0]) || !is_finite(point[1]) || !is_finite(point[2])) return live_hull_failure("invalid_contact_geometry");
			if (depth > 0.0 || point[2] > 0.0) { may_contact = true; break; }
		}
		if (!may_contact) return {true, false, "", {}};
	}
	std::vector<unsigned char> active(static_cast<std::size_t>(count), 0);
	bool any_active = false;
	const bool lake_clear = geometry.lake.present && hull_clear_of_lake(s, geometry);
	for (int i = 0; i < count; ++i) {
		const R *arm = &geometry.points[3 * i];
		const R depth = s[2] + down[0] * arm[0] + down[1] * arm[1] + down[2] * arm[2];
		if (!is_finite(depth)) return live_hull_failure("invalid_contact_geometry");
		bool may_touch = depth > 0.0;
		if (geometry.lake.present) {
			const auto rotated = q_rotate3(s + 6, arm);
			const std::array<R, 3> point = {s[0] + rotated[0], s[1] + rotated[1], s[2] + rotated[2]};
			if (!is_finite(point[0]) || !is_finite(point[1]) || !is_finite(point[2])) return live_hull_failure("invalid_contact_geometry");
			if (depth <= 0.0 && point[2] <= 0.0) continue;
			const LakeCover terrain = lake_clear ? LakeCover() : hull_lake_sample(geometry, point);
			if (terrain.covered) {
				if (!is_finite(terrain.down)) return live_hull_failure("invalid_lake_terrain");
				may_touch = point[2] > terrain.down;
			}
		}
		active[static_cast<std::size_t>(i)] = may_touch ? 1 : 0;
		any_active = any_active || may_touch;
	}
	if (!any_active) return {true, false, "", {}};
	static constexpr int directions[26][3] = {
		{1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1},
		{1,1,0}, {1,-1,0}, {-1,1,0}, {-1,-1,0}, {1,0,1}, {1,0,-1}, {-1,0,1}, {-1,0,-1},
		{0,1,1}, {0,1,-1}, {0,-1,1}, {0,-1,-1}, {1,1,1}, {1,1,-1}, {1,-1,1}, {1,-1,-1},
		{-1,1,1}, {-1,1,-1}, {-1,-1,1}, {-1,-1,-1}};
	HullPrepared prepared = geometry;
	prepared.stiffness.assign(static_cast<std::size_t>(count), 0.0);
	prepared.damping.assign(static_cast<std::size_t>(count), 0.0);
	const R inverse_identity[4] = {1.0, -R(0.0), -R(0.0), -R(0.0)};
	for (int i = 0; i < count; ++i) {
		if (!active[static_cast<std::size_t>(i)]) continue;
		const R *arm = &geometry.points[3 * i];
		const Vec3 center_arm = {arm[0] - p.cg[0], arm[1] - p.cg[1], arm[2] - p.cg[2]};
		R smallest = p.mass_kg;
		for (const auto &direction : directions) {
			const Vec3 normal = {static_cast<double>(direction[0]), static_cast<double>(direction[1]), static_cast<double>(direction[2])};
			const R length = sqrt_(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2]);
			const R inv_length = 1.0 / length;
			const Vec3 scaled = {normal[0] * inv_length, normal[1] * inv_length, normal[2] * inv_length};
			const Vec3 normal_body = q_rotate3(inverse_identity, scaled.data());
			const Vec3 angular = {center_arm[1] * normal_body[2] - center_arm[2] * normal_body[1],
				center_arm[2] * normal_body[0] - center_arm[0] * normal_body[2], center_arm[0] * normal_body[1] - center_arm[1] * normal_body[0]};
			const Vec3 product = live_hull_inertia_mul(p.inverse, angular);
			const R rotational_inverse = angular[0] * product[0] + angular[1] * product[1] + angular[2] * product[2];
			const R inverse_effective = 1.0 / p.mass_kg + rotational_inverse;
			if (!is_finite(inverse_effective) || inverse_effective <= 0.0) return live_hull_failure("invalid_inverse_effective_mass");
			const R effective = 1.0 / inverse_effective;
			if (!is_finite(effective) || effective <= 0.0 || effective > p.mass_kg * (R(1.0) + R(1.0e-10))) {
				return live_hull_failure("effective_mass_out_of_bounds");
			}
			smallest = minf(smallest, minf(effective, p.mass_kg));
		}
		prepared.stiffness[i] = smallest * kHullOmega * kHullOmega;
		prepared.damping[i] = R(2.0) * R(0.7) * smallest * kHullOmega;
	}
	LiveHullResult result;
	result.ok = true;
	result.touched = hull_loads(s, prepared, result.loads);
	return result;
}

} // namespace nk
