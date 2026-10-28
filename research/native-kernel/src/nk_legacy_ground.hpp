// NK-3: legacy no-wheel-state contact in app/physics/ground_contact.gd.
// The flat path deliberately does not sample terrain relief; the lake path
// uses its sampled tangent plane. PreparedGear is shared with the modern path.
#pragma once

#include "nk_wheels.hpp"

namespace nk {

// Returns the reference's empty, six-load or one-NaN shape in `loads`.
// `false` denotes the one-NaN invalid geometry shape. The owner already
// validates body, surfaces and anchor layouts before ordinary stage calls.
inline bool legacy_ground_loads(const R *s, const GroundContext &ctx, R steer,
		const double *anchors, int anchor_count, std::vector<R> &loads) {
	loads.clear();
	const PreparedGear &gear = ctx.gear;
	const bool lake = ctx.lake.present;
	if (lake && (!ctx.lake_valid || !ctx.surfaces.valid)) {
		loads.assign(1, kNan);
		return false;
	}
	if (gear.empty || -s[2] > (lake ? gear.reach + max_height_validated(ctx.surfaces) : gear.reach)) {
		return true;
	}
	const Rotation rotation = wheel_rotation(s);
	const R *north = &rotation[0];
	const R *east = &rotation[3];
	const R *down = &rotation[6];
	const R mu = gear.side_friction;
	const R c_rr = gear.rolling_resistance;
	const R tan_peak = gear.tan_peak_slip;
	const R breakaway = gear.breakaway_factor;
	const int contact_count = static_cast<int>(gear.contacts.size());
	R out[6] = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	bool touched = false;
	for (int index = 0; index < contact_count; ++index) {
		const WheelContact &contact = gear.contacts[index];
		const R *r = contact.position;
		if (!lake) {
			const R compression = s[2] + down[0] * r[0] + down[1] * r[1] + down[2] * r[2];
			if (compression <= 0.0) continue;
			const R vx = s[3] + s[11] * r[2] - s[12] * r[1];
			const R vy = s[4] + s[12] * r[0] - s[10] * r[2];
			const R vz = s[5] + s[10] * r[1] - s[11] * r[0];
			const R rate = down[0] * vx + down[1] * vy + down[2] * vz;
			const R f_up = contact.stiffness * compression + wheel_damping(contact, compression) * rate;
			if (f_up <= 0.0) continue;
			const R delta = steer * contact.max_steering;
			const R hx = cos_(delta);
			const R hy = sin_(delta);
			R hn = north[0] * hx + north[1] * hy;
			R he = east[0] * hx + east[1] * hy;
			const R h_len = sqrt_(hn * hn + he * he);
			R f_n = 0.0;
			R f_e = 0.0;
			if (mu > 0.0 && h_len > 1e-6) {
				hn /= h_len;
				he /= h_len;
				const R vn = north[0] * vx + north[1] * vy + north[2] * vz;
				const R ve = east[0] * vx + east[1] * vy + east[2] * vz;
				const R v_long = vn * hn + ve * he;
				const R v_lat = -vn * he + ve * hn;
				R mu_n = mu * f_up;
				R c = c_rr;
				if (!ctx.surfaces.values.empty()) {
					const int i = wheel_surface_at(ctx.surfaces.values,
						s[0] + north[0] * r[0] + north[1] * r[1] + north[2] * r[2],
						s[1] + east[0] * r[0] + east[1] * r[1] + east[2] * r[2]);
					if (i + 5 >= static_cast<int>(ctx.surfaces.values.size())) {
						loads.assign(1, kNan);
						return false;
					}
					mu_n *= ctx.surfaces.values[i + 4];
					c *= ctx.surfaces.values[i + 5];
				}
				R f_long;
				R f_lat;
				if (anchor_count > 0) {
					if (!anchors || anchor_count < contact_count * 3) {
						loads.assign(1, kNan);
						return false;
					}
				}
				if (anchor_count > 0 && anchors[index * 3 + 2] == 1.0) {
					const R dn = s[0] + north[0] * r[0] + north[1] * r[1] + north[2] * r[2] - anchors[index * 3];
					const R de = s[1] + east[0] * r[0] + east[1] * r[1] + east[2] * r[2] - anchors[index * 3 + 1];
					const R hold_long = breakaway * c * f_up;
					f_long = clampf(-contact.anchor_stiffness * (dn * hn + de * he) - contact.anchor_damping * v_long,
						-hold_long, hold_long);
					f_lat = clampf(-contact.anchor_stiffness * (-dn * he + de * hn) - contact.anchor_damping * v_lat,
						-mu_n, mu_n);
				} else {
					f_long = -c * f_up * clampf(v_long / maxf(0.01, c * 0.1), -1.0, 1.0);
					f_lat = -mu_n * clampf(v_lat / (tan_peak * maxf(absf(v_long), 1.0)), -1.0, 1.0);
				}
				const R f_t = sqrt_(f_long * f_long + f_lat * f_lat);
				if (f_t > mu_n) {
					f_long *= mu_n / f_t;
					f_lat *= mu_n / f_t;
				}
				f_n = f_long * hn - f_lat * he;
				f_e = f_long * he + f_lat * hn;
			}
			const R fx = f_n * north[0] + f_e * east[0] - f_up * down[0];
			const R fy = f_n * north[1] + f_e * east[1] - f_up * down[1];
			const R fz = f_n * north[2] + f_e * east[2] - f_up * down[2];
			out[0] += fx;
			out[1] += fy;
			out[2] += fz;
			out[3] += r[1] * fz - r[2] * fy;
			out[4] += r[2] * fx - r[0] * fz;
			out[5] += r[0] * fy - r[1] * fx;
			touched = true;
			continue;
		}
		const R p_n = s[0] + north[0] * r[0] + north[1] * r[1] + north[2] * r[2];
		const R p_e = s[1] + east[0] * r[0] + east[1] * r[1] + east[2] * r[2];
		const R p_d = s[2] + down[0] * r[0] + down[1] * r[1] + down[2] * r[2];
		const Vec3 terrain = terrain_sample_validated(p_n, p_e, ctx.surfaces, ctx.lake);
		if (!is_finite(terrain[0]) || !is_finite(terrain[1]) || !is_finite(terrain[2])) {
			loads.assign(1, kNan);
			return false;
		}
		const R norm = sqrt_(1.0 + terrain[1] * terrain[1] + terrain[2] * terrain[2]);
		Vec3 normal;
		if (!normal_from_up_slopes(terrain[1], terrain[2], normal)) {
			loads.assign(1, kNan);
			return false;
		}
		const R up_n = normal[0];
		const R up_e = normal[1];
		const R up_d = normal[2];
		const Vec3 up_body = {north[0] * up_n + east[0] * up_e + down[0] * up_d,
			north[1] * up_n + east[1] * up_e + down[1] * up_d,
			north[2] * up_n + east[2] * up_e + down[2] * up_d};
		const R compression = (p_d + terrain[0]) / norm;
		if (compression <= 0.0) continue;
		const R vx = s[3] + s[11] * r[2] - s[12] * r[1];
		const R vy = s[4] + s[12] * r[0] - s[10] * r[2];
		const R vz = s[5] + s[10] * r[1] - s[11] * r[0];
		const Vec3 velocity = {vx, vy, vz};
		const R rate = -dot3(up_body, velocity);
		const R normal_load = contact.stiffness * compression + wheel_damping(contact, compression) * rate;
		if (normal_load <= 0.0) continue;
		const R delta = steer * contact.max_steering;
		Vec3 heading = {cos_(delta), sin_(delta), 0.0};
		const R heading_projection = dot3(heading, up_body);
		heading[0] -= up_body[0] * heading_projection;
		heading[1] -= up_body[1] * heading_projection;
		heading[2] -= up_body[2] * heading_projection;
		const R heading_length = sqrt_(dot3(heading, heading));
		if (heading_length > 1e-6) {
			heading[0] /= heading_length;
			heading[1] /= heading_length;
			heading[2] /= heading_length;
		}
		const Vec3 side = cross3(heading, up_body);
		R f_long = 0.0;
		R f_side = 0.0;
		if (mu > 0.0 && heading_length > 1e-6) {
			const R v_long = dot3(velocity, heading);
			const R v_lat = dot3(velocity, side);
			R mu_n = mu * normal_load;
			R rolling = c_rr;
			if (!ctx.surfaces.values.empty()) {
				const int i = wheel_surface_at(ctx.surfaces.values, p_n, p_e);
				if (i + 5 >= static_cast<int>(ctx.surfaces.values.size())) {
					loads.assign(1, kNan);
					return false;
				}
				mu_n *= ctx.surfaces.values[i + 4];
				rolling *= ctx.surfaces.values[i + 5];
			}
			const int anchor_at = index * 3;
			const bool anchored = anchor_count == contact_count * 3 && anchors && anchors[anchor_at + 2] == 1.0;
			if (anchored) {
				const R delta_n = p_n - anchors[anchor_at];
				const R delta_e = p_e - anchors[anchor_at + 1];
				const Vec3 delta_body = {north[0] * delta_n + east[0] * delta_e,
					north[1] * delta_n + east[1] * delta_e,
					north[2] * delta_n + east[2] * delta_e};
				const R hold_long = breakaway * rolling * normal_load;
				f_long = clampf(-contact.anchor_stiffness * dot3(delta_body, heading) - contact.anchor_damping * v_long,
					-hold_long, hold_long);
				f_side = clampf(-contact.anchor_stiffness * dot3(delta_body, side) - contact.anchor_damping * v_lat,
					-mu_n, mu_n);
			} else {
				f_long = -rolling * normal_load * clampf(v_long / maxf(0.01, rolling * 0.1), -1.0, 1.0);
				f_side = -mu_n * clampf(v_lat / (tan_peak * maxf(absf(v_long), 1.0)), -1.0, 1.0);
			}
			const R tangent_force = sqrt_(f_long * f_long + f_side * f_side);
			if (tangent_force > mu_n) {
				f_long *= mu_n / tangent_force;
				f_side *= mu_n / tangent_force;
			}
		}
		const Vec3 force = {up_body[0] * normal_load + heading[0] * f_long + side[0] * f_side,
			up_body[1] * normal_load + heading[1] * f_long + side[1] * f_side,
			up_body[2] * normal_load + heading[2] * f_long + side[2] * f_side};
		out[0] += force[0];
		out[1] += force[1];
		out[2] += force[2];
		out[3] += r[1] * force[2] - r[2] * force[1];
		out[4] += r[2] * force[0] - r[0] * force[2];
		out[5] += r[0] * force[1] - r[1] * force[0];
		touched = true;
	}
	if (touched) loads.assign(out, out + 6);
	return true;
}

} // namespace nk
