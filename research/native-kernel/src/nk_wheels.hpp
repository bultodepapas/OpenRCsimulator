// NK-3: GP-02 wheel/terrain contact (app/physics/ground_wheels.gd evaluate / frame / coefficients / compressions,
// with diagnostics disabled as FlightSession._ground_evaluation calls it). The gear dictionary is decoded once into
// a PreparedGear; the per-stage call reads only packed scalars. Operation order mirrors the GDScript.
#pragma once

#include <vector>

#include "nk_terrain.hpp"

namespace nk {

constexpr double kReferenceRadius = 0.0381;
constexpr double kStickSpeed = 0.02;
constexpr double kSlipReferenceSpeed = 1.0;

struct WheelContact {
	R position[3] = {0.0, 0.0, 0.0};
	R stiffness = 0.0;
	R damping = 0.0;
	R damping_onset = 0.0;
	R max_steering = 0.0;
	R anchor_stiffness = 0.0;
	R anchor_damping = 0.0;
	R wheel_radius = kReferenceRadius;
	R wheel_inertia = 0.00003;
	R spin_relaxation = 0.03;
	R brake_torque = 0.0;
};

struct PreparedGear {
	bool empty = true;
	std::vector<WheelContact> contacts;
	R reach = 0.0;
	R side_friction = 0.0;
	R rolling_resistance = 0.0;
	R tan_peak_slip = 1.0;
	R breakaway_factor = 1.0;
	R rolling_reference_radius = kReferenceRadius;
};

struct GroundContext {
	PreparedGear gear;
	SurfaceTable surfaces;
	LakeTerrain lake;
	bool lake_valid = true;
};

using Rotation = std::array<R, 9>;

inline Rotation wheel_rotation(const R *s) {
	const R w = s[6];
	const R x = s[7];
	const R y = s[8];
	const R z = s[9];
	return {1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - w * z), 2.0 * (x * z + w * y),
		2.0 * (x * y + w * z), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - w * x),
		2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)};
}

inline R wheel_damping(const WheelContact &c, R compression) {
	const R onset = c.damping_onset;
	if (compression >= onset) {
		return c.damping;
	}
	const R x = compression / onset;
	return c.damping * x * (2.0 - x);
}

inline std::size_t wheel_surface_at(const std::vector<double> &table, R north, R east) {
	std::size_t at = 0;
	while (at + kSurfaceStride < table.size()) {
		if (north >= table[at] && north <= table[at + 1] && east >= table[at + 2] && east <= table[at + 3]) {
			return at;
		}
		at += kSurfaceStride;
	}
	return at;
}

struct WheelFrame {
	Vec3 position{};
	Vec3 normal{};
	Vec3 heading{};
	Vec3 side{};
	R compression = 0.0;
	R normal_load = 0.0;
	R long_speed = 0.0;
	R side_speed = 0.0;
	bool valid_heading = false;
};

inline Vec3 cross3(const Vec3 &a, const Vec3 &b) {
	return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]};
}

inline R dot3(const Vec3 &a, const Vec3 &b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }

// ground_wheels.gd frame(), surfaces_validated = true.
inline WheelFrame wheel_frame(const R *s, const WheelContact &c, R steer, const GroundContext &ctx,
		const Rotation &a) {
	WheelFrame f;
	const R *r = c.position;
	f.position = {s[0] + a[0] * r[0] + a[1] * r[1] + a[2] * r[2], s[1] + a[3] * r[0] + a[4] * r[1] + a[5] * r[2],
		s[2] + a[6] * r[0] + a[7] * r[1] + a[8] * r[2]};
	const Vec3 terrain = terrain_sample_validated(f.position[0], f.position[1], ctx.surfaces, ctx.lake);
	const R norm = sqrt_(1.0 + terrain[1] * terrain[1] + terrain[2] * terrain[2]);
	if (!normal_from_up_slopes(terrain[1], terrain[2], f.normal)) {
		f.normal = {kNan, kNan, kNan};
	}
	const Vec3 &normal = f.normal;
	f.compression = (f.position[2] + terrain[0]) / norm;
#ifdef NK_MUTATION
	const R vx = s[3] + (s[11] * r[2] - s[12] * r[1]); // negative control: reassociated sum
#else
	const R vx = s[3] + s[11] * r[2] - s[12] * r[1];
#endif
	const R vy = s[4] + s[12] * r[0] - s[10] * r[2];
	const R vz = s[5] + s[10] * r[1] - s[11] * r[0];
	const R vn = a[0] * vx + a[1] * vy + a[2] * vz;
	const R ve = a[3] * vx + a[4] * vy + a[5] * vz;
	const R vd = a[6] * vx + a[7] * vy + a[8] * vz;
	const R rate = -(normal[0] * vn + normal[1] * ve + normal[2] * vd);
	f.normal_load = f.compression > 0.0
		? maxf(0.0, c.stiffness * f.compression + wheel_damping(c, f.compression) * rate)
		: R(0.0);
	const R delta = steer * c.max_steering;
	const R cosine = cos_(delta);
	const R sine = sin_(delta);
	R hn = a[0] * cosine + a[1] * sine;
	R he = a[3] * cosine + a[4] * sine;
	R hd = a[6] * cosine + a[7] * sine;
	const R projection = hn * normal[0] + he * normal[1] + hd * normal[2];
	hn -= normal[0] * projection;
	he -= normal[1] * projection;
	hd -= normal[2] * projection;
	const R length = sqrt_(hn * hn + he * he + hd * hd);
	f.heading = {0.0, 0.0, 0.0};
	if (length > 1e-6) {
		f.heading[0] = hn / length;
		f.heading[1] = he / length;
		f.heading[2] = hd / length;
	}
	f.side = cross3(f.heading, normal);
	f.long_speed = vn * f.heading[0] + ve * f.heading[1] + vd * f.heading[2];
	f.side_speed = vn * f.side[0] + ve * f.side[1] + vd * f.side[2];
	f.valid_heading = length > 1e-6;
	return f;
}

// ground_wheels.gd coefficients(): [mu, rolling, surface index].
inline void wheel_coefficients(const PreparedGear &gear, const WheelContact &c, const std::vector<double> &surfaces,
		const Vec3 &p, R &mu, R &rolling, R &index) {
	mu = gear.side_friction;
	rolling = gear.rolling_resistance;
	std::size_t at = 0;
	if (!surfaces.empty()) {
		at = wheel_surface_at(surfaces, p[0], p[1]);
		mu *= surfaces[at + 4];
		const R radius = c.wheel_radius;
		const R factor = surfaces[at + 5];
		rolling *= factor < 1.0 ? factor : 1.0 + (factor - 1.0) * sqrt_(gear.rolling_reference_radius / radius);
	}
	index = surfaces.empty() ? -1.0 : static_cast<double>(at);
}

// ground_wheels.gd evaluate(..., diagnostics_enabled = false, lake). loads is empty (size 0) when nothing touches.
// Returns false only for the reference's [NAN]/[NAN] failure shape.
inline bool wheels_evaluate(const R *s, const GroundContext &ctx, R steer, const double *anchors,
		int anchor_count, const double *speeds, int speed_count, R brake, std::vector<R> &loads,
		std::vector<R> &rates) {
	const PreparedGear &gear = ctx.gear;
	rates.assign(static_cast<size_t>(speed_count), 0.0);
	loads.clear();
	if (gear.empty) {
		return true;
	}
	const int contacts = static_cast<int>(gear.contacts.size());
	if (speed_count != contacts || !ctx.surfaces.valid || !ctx.lake_valid) {
		loads.assign(1, kNan);
		rates.assign(1, kNan);
		return false;
	}
	if (-s[2] > gear.reach + max_height_validated(ctx.surfaces)) {
		return true;
	}
	const Rotation rotation = wheel_rotation(s);
	for (int i = 0; i < contacts; ++i) {
		const WheelContact &c = gear.contacts[i];
		const WheelFrame f = wheel_frame(s, c, steer, ctx, rotation);
		R cf0, cf1, cf2;
		wheel_coefficients(gear, c, ctx.surfaces.values, f.position, cf0, cf1, cf2);
		const R n = f.normal_load;
		const R rim = speeds[i];
		const R slip = f.long_speed - rim;
		R rr = 0.0;
		R tire = 0.0;
		R lateral = 0.0;
		R brake_torque = 0.0;
		const R radius = c.wheel_radius;
		const R inertia = c.wheel_inertia;
		const R mass = inertia / (radius * radius);
		const R relaxation = c.spin_relaxation;
		if (n > 0.0 && f.valid_heading && cf0 > 0.0) {
			const R limit = cf0 * n;
			const std::size_t anchor_at = static_cast<std::size_t>(i) * 3;
			const bool stuck = static_cast<int64_t>(anchor_count) == static_cast<int64_t>(contacts) * 3 &&
				anchors[anchor_at + 2] == 1.0 && absf(slip) < kStickSpeed;
			if (stuck) {
				const Vec3 displacement = {f.position[0] - anchors[anchor_at], f.position[1] - anchors[anchor_at + 1], 0.0};
				const R hold = gear.breakaway_factor * cf1 * n;
				rr = clampf(-c.anchor_stiffness * dot3(displacement, f.heading) - c.anchor_damping * f.long_speed,
					-hold, hold);
				lateral = clampf(-c.anchor_stiffness * dot3(displacement, f.side) - c.anchor_damping * f.side_speed,
					-limit, limit);
			} else {
				rr = -cf1 * n * clampf(f.long_speed / maxf(0.01, cf1 * 0.1), -1.0, 1.0);
				lateral = -limit * clampf(f.side_speed / (gear.tan_peak_slip * maxf(absf(f.long_speed), 1.0)), -1.0, 1.0);
			}
			tire = -minf(limit / kSlipReferenceSpeed, mass / relaxation) * slip;
			const R total = sqrt_((rr + tire) * (rr + tire) + lateral * lateral);
			if (total > limit) {
				const R scale = limit / total;
				rr *= scale;
				tire *= scale;
				lateral *= scale;
			}
			const R maximum = clampf(brake, 0.0, 1.0) * c.brake_torque;
			brake_torque = clampf(minf(maximum / 0.25, mass * radius / relaxation) * rim, -maximum, maximum);
			rates[i] = (-tire - brake_torque / radius) / mass;
		}
		const R long_force = rr + tire;
		if (n <= 0.0) {
			continue;
		}
		if (loads.empty()) {
			loads.assign(6, 0.0);
		}
		const R fn = f.normal[0] * n + f.heading[0] * long_force + f.side[0] * lateral;
		const R fe = f.normal[1] * n + f.heading[1] * long_force + f.side[1] * lateral;
		const R fd = f.normal[2] * n + f.heading[2] * long_force + f.side[2] * lateral;
		const R fx = rotation[0] * fn + rotation[3] * fe + rotation[6] * fd;
		const R fy = rotation[1] * fn + rotation[4] * fe + rotation[7] * fd;
		const R fz = rotation[2] * fn + rotation[5] * fe + rotation[8] * fd;
		const R spin = inertia / radius * rates[i];
		const R *r = c.position;
		loads[0] += fx;
		loads[1] += fy;
		loads[2] += fz;
#ifdef NK_MUTATION
		// negative control: commuted sum (finite-identical; differs only in NaN priority)
		loads[3] += spin * (rotation[0] * f.side[0] + rotation[3] * f.side[1] + rotation[6] * f.side[2]) + (r[1] * fz - r[2] * fy);
#else
		loads[3] += r[1] * fz - r[2] * fy + spin * (rotation[0] * f.side[0] + rotation[3] * f.side[1] + rotation[6] * f.side[2]);
#endif
		loads[4] += r[2] * fx - r[0] * fz + spin * (rotation[1] * f.side[0] + rotation[4] * f.side[1] + rotation[7] * f.side[2]);
		loads[5] += r[0] * fy - r[1] * fx + spin * (rotation[2] * f.side[0] + rotation[5] * f.side[1] + rotation[8] * f.side[2]);
	}
	return true;
}

// ground_wheels.gd compressions(); false = the reference's [NAN] for an invalid table or lake.
inline bool wheels_compressions(const R *s, const GroundContext &ctx, std::vector<R> &out) {
	out.clear();
	if (ctx.gear.empty) {
		return true;
	}
	if (!ctx.surfaces.valid || !ctx.lake_valid) {
		out.assign(1, kNan);
		return false;
	}
	const Rotation a = wheel_rotation(s);
	for (const WheelContact &contact : ctx.gear.contacts) {
		const R *r = contact.position;
		const R north = s[0] + a[0] * r[0] + a[1] * r[1] + a[2] * r[2];
		const R east = s[1] + a[3] * r[0] + a[4] * r[1] + a[5] * r[2];
		const R down = s[2] + a[6] * r[0] + a[7] * r[1] + a[8] * r[2];
		const Vec3 terrain = terrain_sample_validated(north, east, ctx.surfaces, ctx.lake);
		out.push_back((down + terrain[0]) / sqrt_(1.0 + terrain[1] * terrain[1] + terrain[2] * terrain[2]));
	}
	return true;
}

} // namespace nk
