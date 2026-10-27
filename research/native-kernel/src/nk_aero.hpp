// NK-3: aerodynamic loads about the CG for a prepared fixed-wing model, mirroring the current GDScript
// operation by operation: app/physics/air_data.gd compute, app/physics/ground_effect.gd factors/law and
// app/physics/aero.gd loads (_global_loads, _local_loads, _wing_flow, local_flow_weight,
// _wing_lift_coefficient_with, _tail_surface_from_flow, _surface_with_flow, _tail_curve, downwash_angle).
// Supported law: Aero.LOADS_LAW "section-plane-source-weighted-wake-velocity-v2" without flaps, tailless elevons,
// tabulated wing polar or spatial (station-delta) air; prepare_aero refuses those models (D6) so the caller keeps
// the GDScript reference.
#pragma once

#include <array>
#include <vector>

#include "nk_math.hpp"

namespace nk {

constexpr double kGroundEffectFade = 2.0;

struct Air {
	R v[3] = {0.0, 0.0, 0.0};
	R V = 0.0;
	R alpha = 0.0;
	R beta = 0.0;
	R qbar = 0.0;
};

struct Tail {
	bool present = false;
	bool free = false; // has free_slope: E0a2 downwash law (horizontal only)
	R area = 0.0;
	R position[3] = {0.0, 0.0, 0.0};
	R lift_slope = 0.0;
	R control_effectiveness = 0.0;
	R incidence = 0.0;
	R free_slope = 0.0;
	R elevator_tau = 0.0;
	R downwash_per_cl = 0.0;
	R free_incidence = 0.0;
};

struct AeroModel {
	// reference / mass datum
	R S = 0.0, b = 0.0, c = 0.0;
	R arp[3] = {0.0, 0.0, 0.0};
	R cg[3] = {0.0, 0.0, 0.0};
	// aero (empirical oracle)
	R CL0 = 0, CLa = 0, CLq = 0, CLde = 0, CLda_each = 0, CD0 = 0, CL_minD = 0, k_induced = 0;
	R CDda_each = 0, CDdr = 0, CDde = 0, CYb = 0, CYp = 0, CYr = 0, CYdr = 0;
	R Clb = 0, Clp = 0, Clr = 0, Clda_right = 0, Clda_left = 0, Cldr = 0;
	R Cm0 = 0, Cma = 0, Cmq = 0, Cmde = 0, Cmda_each = 0;
	R Cnb = 0, Cnp = 0, Cnr = 0, Cnda_right = 0, Cnda_left = 0, Cndr = 0;
	// envelope (always present in the supported law)
	R a1 = 0, a2 = 0, n1 = 0, n2 = 0, b1 = 0, b2 = 0, CD90 = 0;
	std::vector<R> ys;
	R strip_slope = 0.0; // env.get("strip_slope", CLa)
	std::vector<R> strip_cl0;
	std::vector<R> induced_map;
	bool has_strip_alpha_zero = false;
	R strip_alpha_zero = 0.0;
	std::vector<R> strip_row_sum;
	std::vector<R> station_chords;
	bool ground_effect = false;
	R ge_induced_coefficient = 0, ge_induced_exponent = 0, ge_downwash_coefficient = 0, ge_downwash_exponent = 0;
	// surfaces
	R wing_aileron_effectiveness = 0, attached_limit = 0, tail_local_limit = 0, tail_stall_end = 0;
	R tail_CD0 = 0, tail_k = 0, tail_CD90 = 0;
	R body_cn_beta = 0, wing_body_cl_beta = 0, body_cy_beta = 0, body_crossflow_area = 0, wing_cm_ac = 0;
	std::vector<R> station_incidence;
	Tail horizontal;
	Tail vertical;
};

// Aerospace deflections in the data convention (radians).
struct Deflections {
	R elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0;
};

using Loads = std::array<R, 6>;

// air_data.gd compute.
inline Air air_compute(const R *s, const R *wind_ned, R rho) {
	const R qw = s[6];
	const R ux = -s[7];
	const R uy = -s[8];
	const R uz = -s[9];
	const R wx = wind_ned[0];
	const R wy = wind_ned[1];
	const R wz = wind_ned[2];
	const R tx = (uy * wz - uz * wy) * 2.0;
	const R ty = (uz * wx - ux * wz) * 2.0;
	const R tz = (ux * wy - uy * wx) * 2.0;
	const R u = s[3] - ((wx + tx * qw) + (uy * tz - uz * ty));
	const R v = s[4] - ((wy + ty * qw) + (uz * tx - ux * tz));
	const R w = s[5] - ((wz + tz * qw) + (ux * ty - uy * tx));
	const R speed = sqrt_(u * u + v * v + w * w);
	Air air;
	air.v[0] = u;
	air.v[1] = v;
	air.v[2] = w;
	air.V = speed;
	air.alpha = atan2_(w, u);
	air.beta = atan2_(v, sqrt_(u * u + w * w));
	air.qbar = 0.5 * rho * speed * speed;
	return air;
}

// ground_effect.gd law.
inline R ge_law(R x, R coefficient, R exponent) {
	if (x >= kGroundEffectFade) {
		return 1.0;
	}
	const R clamped = maxf(x, 0.0);
	const R t = coefficient * pow_(clamped, exponent);
	const R sigma = t / (1.0 + t);
	const R u = clamped / kGroundEffectFade;
	const R keep = 1.0 - u * u * (3.0 - 2.0 * u);
	return 1.0 - (1.0 - sigma) * keep;
}

// ground_effect.gd factors: empty (out.size() == 0) = legacy path.
inline void ge_factors(const R *s, const AeroModel &m, R ground_up, std::vector<R> &out) {
	out.clear();
	if (is_nan(ground_up) || !m.ground_effect) {
		return;
	}
	const int n = static_cast<int>(m.ys.size());
	const R b = m.b;
	const R ax = -(m.arp[0] - m.cg[0]);
	const R ay = m.arp[1] - m.cg[1];
	const R az = -(m.arp[2] - m.cg[2]);
	const R qw = s[6];
	const R qx = s[7];
	const R qy = s[8];
	const R qz = s[9];
	const R d0 = 2.0 * (qx * qz - qw * qy);
	const R d1 = 2.0 * (qy * qz + qw * qx);
	const R d2 = 1.0 - 2.0 * (qx * qx + qy * qy);
	out.assign(static_cast<size_t>(n + 2), 0.0);
	R sum = 0.0;
	R x_sum = 0.0;
	bool active = false;
	for (int i = 0; i < n; ++i) {
		const R height = -(s[2] + d0 * ax + d1 * (ay + m.ys[i]) + d2 * az) - ground_up;
		const R x = maxf(height, 0.0) / b;
		const R f = ge_law(x, m.ge_induced_coefficient, m.ge_induced_exponent);
		out[i] = f;
		sum += f;
		x_sum += x;
		if (f != 1.0) {
			active = true;
		}
	}
	if (!active) {
		out.clear();
		return;
	}
	out[n] = sum / static_cast<double>(n);
	out[n + 1] = ge_law(x_sum / static_cast<double>(n), m.ge_downwash_coefficient, m.ge_downwash_exponent);
}

// aero.gd _smoothstep (branching form; distinct from the lake's clamped one).
inline R aero_smoothstep(R x) {
	if (x <= 0.0) {
		return 0.0;
	}
	if (x >= 1.0) {
		return 1.0;
	}
	return x * x * (3.0 - 2.0 * x);
}

inline R stall_weight(R alpha, const AeroModel &m) {
	if (alpha >= 0.0) {
		return aero_smoothstep((alpha - m.a1) / (m.a2 - m.a1));
	}
	return aero_smoothstep((-alpha - m.n1) / (m.n2 - m.n1));
}

inline R sideslip_weight(R beta, const AeroModel &m) {
	return aero_smoothstep((absf(beta) - m.b1) / (m.b2 - m.b1));
}

inline R downwash_angle(R wake_velocity, R gain, R plane_speed) {
	return wake_velocity != 0.0 ? atan2_(gain * wake_velocity, plane_speed) : R(0.0);
}

// M.add(air.v_air, M.cross(rates, _arm(position, cg))) then sqrt(f0^2 + f2^2): aero.gd _tail_plane_speed.
inline R tail_plane_speed(const R *s, const Air &air, const AeroModel &m, const Tail &tail) {
	const R arm0 = -(tail.position[0] - m.cg[0]);
	const R arm1 = tail.position[1] - m.cg[1];
	const R arm2 = -(tail.position[2] - m.cg[2]);
	const R p = s[10], q = s[11], r = s[12];
	const R c0 = q * arm2 - r * arm1;
	const R c2 = p * arm1 - q * arm0;
	const R f0 = air.v[0] + c0;
	const R f2 = air.v[2] + c2;
	return sqrt_(f0 * f0 + f2 * f2);
}

struct WingFlow {
	R angles[16];
	R speeds[16];
	R sources[16];
	R reference_speed = 0.0;
};

// aero.gd _wing_flow without station deltas, flaps or tailless stations.
inline void wing_flow(const R *s, const Air &air, const Deflections &d, const AeroModel &m, WingFlow &out) {
	const R arm0 = -(m.arp[0] - m.cg[0]);
	const R arm1 = m.arp[1] - m.cg[1];
	const R arm2 = -(m.arp[2] - m.cg[2]);
	const R *v = air.v;
	const R p = s[10];
	const R q = s[11];
	const R r = s[12];
	const int n = static_cast<int>(m.ys.size());
	const bool has_twist = !m.station_incidence.empty();
	R reference_speed = 0.0;
	R aileron_effect = 0.0;
	if (n > 0) {
		aileron_effect = m.wing_aileron_effectiveness;
	}
	for (int i = 0; i < n; ++i) {
		const R y = arm1 + m.ys[i];
		const R arm_x = arm0;
		const R f0 = v[0] + (q * arm2 - r * y);
		const R f1 = v[1] + (r * arm_x - p * arm2);
		const R f2 = v[2] + (p * y - q * arm_x);
		const R vp = sqrt_(f0 * f0 + f2 * f2);
		const R control = m.ys[i] > 0.0 ? d.aileron_right : d.aileron_left;
		R angle = wrapf(atan2_(f2, f0) + aileron_effect * control, -kPi, kPi);
		if (has_twist) {
			angle = wrapf(angle + m.station_incidence[i], -kPi, kPi);
		}
		out.angles[i] = angle;
		out.speeds[i] = vp;
		reference_speed = maxf(reference_speed, sqrt_(f0 * f0 + f1 * f1 + f2 * f2));
	}
	if (reference_speed > 0.0 && n > 0) {
		const R a1 = m.a1;
		const R a_span = m.a2 - m.a1;
		const R n1 = m.n1;
		const R n_span = m.n2 - m.n1;
		for (int i = 0; i < n; ++i) {
			const R source_angle = out.angles[i];
			const R stall = source_angle >= 0.0 ? aero_smoothstep((source_angle - a1) / a_span)
				: aero_smoothstep((-source_angle - n1) / n_span);
			out.sources[i] = (out.speeds[i] / reference_speed) * (1.0 - stall);
		}
	} else {
		for (int i = 0; i < n; ++i) {
			out.sources[i] = 0.0;
		}
	}
	out.reference_speed = reference_speed;
}

// aero.gd _wing_lift_coefficient_with (no flaps, no polar).
inline R wing_lift_coefficient_with(const R *s, const Air &air, const Deflections &d, const AeroModel &m,
		const std::vector<R> &ge, bool dimensional) {
	const bool ge_active = !ge.empty();
	const int stations = static_cast<int>(m.ys.size());
	WingFlow flow;
	wing_flow(s, air, d, m, flow);
	const bool coupled = static_cast<int>(m.induced_map.size()) == stations * stations;
	const R strip_slope = m.strip_slope;
	const R cd90 = m.CD90;
	const R a1 = m.a1;
	const R a_span = m.a2 - m.a1;
	const R n1 = m.n1;
	const R n_span = m.n2 - m.n1;
	R wing_cl = 0.0;
	for (int i = 0; i < stations; ++i) {
		const R effective = flow.angles[i];
		const R stall_angle = effective;
		const R weight = stall_angle >= 0.0 ? aero_smoothstep((stall_angle - a1) / a_span)
			: aero_smoothstep((-stall_angle - n1) / n_span);
		R base;
		if (coupled) {
			R mapped = 0.0;
			for (int k = 0; k < stations; ++k) {
				mapped += m.induced_map[i * stations + k] * flow.angles[k] * (k == i ? R(1.0) : flow.sources[k]);
			}
			base = m.strip_cl0[i] + strip_slope * mapped;
		} else {
			base = m.CL0 + m.CLa * effective;
		}
		if (ge_active) {
			base += (1.0 - ge[i]) * (strip_slope * (effective + m.strip_alpha_zero) - base);
		}
		const R cl = weight == 0.0 ? base : (1.0 - weight) * base + weight * 0.5 * cd90 * sin_(2.0 * effective);
		wing_cl += (dimensional ? flow.speeds[i] * cl : cl) / static_cast<double>(stations);
	}
	return wing_cl;
}

// aero.gd _tail_curve.
inline R tail_curve(R alpha, R slope, const AeroModel &m) {
	const R blend = aero_smoothstep((absf(alpha) - m.tail_local_limit) / (m.tail_stall_end - m.tail_local_limit));
	return (1.0 - blend) * slope * alpha + blend * 0.5 * m.tail_CD90 * sin_(2.0 * alpha);
}

// aero.gd _surface_with_flow.
inline Loads surface_with_flow(const R *flow, const R *arm, R area, R cl, R cd,
		bool vertical, R rho) {
	const R normal = flow[vertical ? 1 : 2];
	const R plane_speed = sqrt_(flow[0] * flow[0] + normal * normal);
	if (plane_speed == 0.0) {
		return {0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	}
	const R force_scale = -0.5 * rho * plane_speed * area * cd;
	R fx = flow[0] * force_scale;
	R fy = vertical ? normal * force_scale : R(0.0);
	R fz = vertical ? R(0.0) : normal * force_scale;
	const R lift = 0.5 * rho * plane_speed * plane_speed * area * cl;
	fx += lift * normal / plane_speed;
	if (vertical) {
		fy -= lift * flow[0] / plane_speed;
	} else {
		fz -= lift * flow[0] / plane_speed;
	}
	return {fx, fy, fz, arm[1] * fz - arm[2] * fy, arm[2] * fx - arm[0] * fz, arm[0] * fy - arm[1] * fx};
}

// aero.gd _tail_surface_from_flow.
inline Loads tail_surface_from_flow(const R *flow, const R *arm, const Deflections &d, const Tail &tail,
		const AeroModel &m, R area, bool vertical, R rho, R downwash_cl) {
	const R control = vertical ? -d.rudder : d.elevator;
	R effective;
	R slope;
	if (!vertical && tail.free) {
		effective = wrapf(atan2_(flow[2], flow[0]) -
				downwash_angle(downwash_cl, tail.downwash_per_cl, sqrt_(flow[0] * flow[0] + flow[2] * flow[2])) +
				tail.elevator_tau * control + tail.free_incidence, -kPi, kPi);
		slope = tail.free_slope;
	} else {
		effective = wrapf(atan2_(flow[vertical ? 1 : 2], flow[0]) + tail.control_effectiveness * control +
				tail.incidence, -kPi, kPi);
		slope = tail.lift_slope;
	}
	const R cl = tail_curve(effective, slope, m);
	const R cd = m.tail_CD0 + m.tail_k * cl * cl + m.tail_CD90 * pow_(sin_(effective), 2.0);
	return surface_with_flow(flow, arm, area, cl, cd, vertical, rho);
}

// aero.gd local_flow_weight.
inline R local_flow_weight(const R *s, const Air &air, const Deflections &d, const AeroModel &m,
		R downwash_cl, const std::vector<R> &ge) {
	const R limit = m.attached_limit;
	const R *v = air.v;
	const R p = s[10];
	const R q = s[11];
	const R r = s[12];
	const R a1 = m.a1;
	const R a1_span = a1 - limit;
	R blend = maxf(aero_smoothstep((absf(air.alpha) - limit) / a1_span), sideslip_weight(air.beta, m));
	if (blend == 1.0) {
		return blend;
	}
	const R v0 = v[0];
	const R v1 = v[1];
	const R v2 = v[2];
	const R n1_span = m.n1 - limit;
	const R arm_x = -(m.arp[0] - m.cg[0]) + 0.0;
	const R arm_y = m.arp[1] - m.cg[1];
	const R arm_z = -(m.arp[2] - m.cg[2]) + 0.0;
	const bool has_twist = !m.station_incidence.empty();
	const R aileron_effect = m.wing_aileron_effectiveness;
	const R da_right = d.aileron_right;
	const R da_left = d.aileron_left;
	const int n = static_cast<int>(m.ys.size());
	for (int i = 0; i < n; ++i) {
		const R y = m.ys[i];
		const R station_y = arm_y + y;
		const R station_arm_x = arm_x;
		const R flow_x = v0 + (q * arm_z - r * station_y);
		const R flow_z = v2 + (p * station_y - q * station_arm_x);
		const R da = y > 0 ? da_right : da_left;
		const R rate_x = q * arm_z - r * station_y;
		const R rate_y = r * station_arm_x - p * arm_z;
		const R rate_z = p * station_y - q * station_arm_x;
		const R rate_speed = sqrt_(rate_x * rate_x + rate_y * rate_y + rate_z * rate_z);
		blend = maxf(blend, aero_smoothstep((atan2_(rate_speed, air.V) - limit) / a1_span));
		if (blend == 1.0) {
			return blend;
		}
		R angle = wrapf(atan2_(flow_z, flow_x) + aileron_effect * da, -kPi, kPi);
		if (has_twist) {
			angle = wrapf(angle + m.station_incidence[i], -kPi, kPi);
		}
		blend = maxf(blend, aero_smoothstep((absf(angle) - limit) / (angle >= 0.0 ? a1_span : n1_span)));
		if (blend == 1.0) {
			return blend;
		}
	}
	const R tail_span = m.tail_local_limit - limit;
	for (int tail_index = 0; tail_index < 2; ++tail_index) {
		const bool vertical = tail_index == 1;
		if (!vertical && !m.horizontal.present) {
			continue;
		}
		const Tail &tail = vertical ? m.vertical : m.horizontal;
		const R tx = -(tail.position[0] - m.cg[0]);
		const R ty = tail.position[1] - m.cg[1];
		const R tz = -(tail.position[2] - m.cg[2]);
		const R flow_x = v0 + (q * tz - r * ty);
		const R component = vertical ? v1 + (r * tx - p * tz) : v2 + (p * ty - q * tx);
		const R rate_x = q * tz - r * ty;
		const R rate_y = r * tx - p * tz;
		const R rate_z = p * ty - q * tx;
		const R rate_speed = sqrt_(rate_x * rate_x + rate_y * rate_y + rate_z * rate_z);
		blend = maxf(blend, aero_smoothstep((atan2_(rate_speed, air.V) - limit) / a1_span));
		if (blend == 1.0) {
			return blend;
		}
		const R control = vertical ? -d.rudder : d.elevator;
		R angle;
		if (!vertical && tail.free) {
			R wake = downwash_cl;
			if (is_nan(wake)) {
				wake = wing_lift_coefficient_with(s, air, d, m, ge, true);
			}
			const R scale = !ge.empty() ? ge[n + 1] : R(1.0);
			angle = wrapf(atan2_(component, flow_x) -
					downwash_angle(wake * scale, tail.downwash_per_cl, sqrt_(flow_x * flow_x + component * component)) +
					tail.elevator_tau * control + tail.free_incidence, -kPi, kPi);
		} else {
			angle = wrapf(atan2_(component, flow_x) + tail.control_effectiveness * control + tail.incidence, -kPi, kPi);
		}
		blend = maxf(blend, aero_smoothstep((absf(angle) - limit) / tail_span));
	}
	return blend;
}

// aero.gd _global_loads (envelope present).
inline Loads global_loads(const R *s, const Air &air, const Deflections &d, const AeroModel &m, R rho,
		R downwash_cl, const std::vector<R> &ge) {
	const R S = m.S;
	const R b = m.b;
	const R c = m.c;
	const R qbar = air.qbar;
	const R p = s[10];
	const R q = s[11];
	const R r = s[12];
	const R alpha = air.alpha;
	const R beta = air.beta;
	const R de = d.elevator;
	const R dar = d.aileron_right;
	const R dal = d.aileron_left;
	const R dr = d.rudder;
	const R w = stall_weight(alpha, m);
	const R wb = sideslip_weight(beta, m);
	const R beta_eff = wb == 0.0 ? beta : (1.0 - wb) * beta + wb * sin_(beta);
	const R cl_controls = m.CLde * de + m.CLda_each * (dar + dal);
	const R cl0 = m.CL0;
	const R cla = m.CLa;
	const R cd0 = m.CD0;
	R co_cl = cl0 + cla * alpha + cl_controls;
	R cd_aero = cd0 + m.k_induced * pow_(co_cl - m.CL_minD, 2.0);
	{
		const R base = cl0 + cla * alpha;
		const R cd90 = m.CD90;
		co_cl = (w == 0.0 ? base : (1.0 - w) * base + w * 0.5 * cd90 * sin_(2.0 * alpha)) + cl_controls;
		const R sin_alpha = sin_(alpha);
		cd_aero = (1.0 - w) * cd_aero + w * (cd0 + cd90 * sin_alpha * sin_alpha);
	}
	R co_cd = cd_aero + absf(m.CDda_each * dar) + absf(m.CDda_each * dal) + absf(m.CDdr * dr) + absf(m.CDde * de);
	const R cm0 = m.Cm0;
	const R cma = m.Cma;
	R cm_alpha = cm0 + cma * alpha;
	if (w != 0.0) {
		cm_alpha = (1.0 - w) * cm_alpha + w * (cm0 + cma * sin_(alpha));
	}
	const R co_cy = m.CYb * beta_eff + m.CYdr * dr;
	R co_roll = m.Clb * beta_eff + m.Clda_right * dar + m.Clda_left * dal + m.Cldr * dr;
	R co_pitch = cm_alpha + m.Cmde * de + m.Cmda_each * (dar + dal);
	const R co_yaw = m.Cnb * beta_eff + m.Cnda_right * dar + m.Cnda_left * dal + m.Cndr * dr;
	R wake_ge = kNan;
	bool wake_ge_known = false;
	if (!ge.empty()) {
		const int stations = static_cast<int>(m.ys.size());
		const R a0 = m.strip_slope;
		const R alpha_zero = m.strip_alpha_zero;
		const R attached = 1.0 - w;
		R wing_gain = 0.0;
		R roll_gain = 0.0;
		for (int i = 0; i < stations; ++i) {
			const R dcl = a0 * (alpha + alpha_zero) * (1.0 - ge[i]) * (1.0 - m.strip_row_sum[i]);
			wing_gain += dcl / static_cast<double>(stations);
			roll_gain -= dcl * m.ys[i] / static_cast<double>(stations) / b;
		}
		co_cl += attached * wing_gain;
		co_roll += attached * roll_gain;
		R cd_ge = cd0 + ge[stations] * m.k_induced * pow_(co_cl - m.CL_minD, 2.0);
		if (w != 0.0) {
			const R sin_ge = sin_(alpha);
			cd_ge = (1.0 - w) * cd_ge + w * (cd0 + m.CD90 * sin_ge * sin_ge);
		}
		co_cd = cd_ge + absf(m.CDda_each * dar) + absf(m.CDda_each * dal) + absf(m.CDdr * dr) + absf(m.CDde * de);
		const Tail &ge_tail = m.horizontal;
		static const std::vector<R> kNoGround;
		const R wake_free = wing_lift_coefficient_with(s, air, d, m, kNoGround, true);
		wake_ge = wing_lift_coefficient_with(s, air, d, m, ge, true);
		wake_ge_known = true;
		const R tail_speed = tail_plane_speed(s, air, m, ge_tail);
		const R tail_cl = ge_tail.free_slope * ge_tail.area / S *
			(downwash_angle(wake_free, ge_tail.downwash_per_cl, tail_speed) -
			 downwash_angle(wake_ge * ge[stations + 1], ge_tail.downwash_per_cl, tail_speed));
		co_cl += tail_cl;
		co_pitch -= tail_cl * (ge_tail.position[0] - m.arp[0]) / c;
	}
	if (!is_nan(downwash_cl)) {
		const Tail &tail = m.horizontal;
		const R source = wake_ge_known ? wake_ge : wing_lift_coefficient_with(s, air, d, m, ge, true);
		const R scale = ge.empty() ? R(1.0) : ge[ge.size() - 1];
		const R tail_speed = tail_plane_speed(s, air, m, tail);
		const R lag_cl = tail.free_slope * tail.area / S *
			(downwash_angle(source * scale, tail.downwash_per_cl, tail_speed) -
			 downwash_angle(downwash_cl * scale, tail.downwash_per_cl, tail_speed));
		co_cl += lag_cl;
		co_pitch -= lag_cl * (tail.position[0] - m.arp[0]) / c;
	}
	const R k = 0.25 * rho * air.V;
	const R cl_rate = k * c * m.CLq * q;
	const R cy_rate = k * b * (m.CYp * p + m.CYr * r);
	const R roll_rate = k * b * (m.Clp * p + m.Clr * r);
	const R pitch_rate = k * c * m.Cmq * q;
	const R yaw_rate = k * b * (m.Cnp * p + m.Cnr * r);
	const R lift = (qbar * co_cl + cl_rate) * S;
	const R drag = qbar * co_cd * S;
	const R side = (qbar * co_cy + cy_rate) * S;
	const R ca = cos_(alpha);
	const R sa = sin_(alpha);
	const R cb = cos_(beta);
	const R sb = sin_(beta);
	const R fx = ca * cb * (-drag) - ca * sb * side + sa * lift;
	const R fy = sb * (-drag) + cb * side;
	const R fz = sa * cb * (-drag) - sa * sb * side - ca * lift;
	const R mx = (qbar * co_roll + roll_rate) * S * b;
	const R my = (qbar * co_pitch + pitch_rate) * S * c;
	const R mz = (qbar * co_yaw + yaw_rate) * S * b;
	const R rx = -(m.arp[0] - m.cg[0]);
	const R ry = m.arp[1] - m.cg[1];
	const R rz = -(m.arp[2] - m.cg[2]);
	return {fx, fy, fz, mx + (ry * fz - rz * fy), my + (rz * fx - rx * fz), mz + (rx * fy - ry * fx)};
}

// aero.gd _local_loads (include_body = true, no diagnostics, no station deltas, no flaps/polar/tailless).
inline Loads local_loads(const R *s, const Air &air, const Deflections &d, const AeroModel &m, R rho,
		R downwash_cl, const std::vector<R> &ge) {
	const bool ge_active = !ge.empty();
	const R p = s[10];
	const R q = s[11];
	const R r = s[12];
	const R *v = air.v;
	const R v0 = v[0];
	const R v1 = v[1];
	const R v2 = v[2];
	const R ax = -(m.arp[0] - m.cg[0]) + 0.0;
	const R ay = m.arp[1] - m.cg[1];
	const R az = -(m.arp[2] - m.cg[2]) + 0.0;
	const int stations = static_cast<int>(m.ys.size());
	const R station_area = m.S / static_cast<double>(stations);
	const R cl0 = m.CL0;
	const R cla = m.CLa;
	const R cd0 = m.CD0;
	const R k_induced = m.k_induced;
	const R cl_min_d = m.CL_minD;
	const R cd90 = m.CD90;
	const R a1 = m.a1;
	const R a_span = m.a2 - m.a1;
	const R n1 = m.n1;
	const R n_span = m.n2 - m.n1;
	const R lift_q = 0.5 * rho;
	const R drag_q = -0.5 * rho;
	R fx_sum = 0.0, fy_sum = 0.0, fz_sum = 0.0, mx_sum = 0.0, my_sum = 0.0, mz_sum = 0.0;
	R wing_cl = 0.0;
	WingFlow flow;
	wing_flow(s, air, d, m, flow);
	const bool coupled = static_cast<int>(m.induced_map.size()) == stations * stations;
	const R strip_slope = m.strip_slope;
	const R cm_ac = m.wing_cm_ac;
	for (int i = 0; i < stations; ++i) {
		const R y = m.ys[i];
		const R arm_y = ay + y;
		const R ax_i = ax;
		const R f0 = v0 + (q * az - r * arm_y);
		const R f1 = v1 + (r * ax_i - p * az);
		const R f2 = v2 + (p * arm_y - q * ax_i);
		(void)f1;
		const R effective = flow.angles[i];
		const R stall_angle = effective;
		const R weight = stall_angle >= 0.0 ? aero_smoothstep((stall_angle - a1) / a_span)
			: aero_smoothstep((-stall_angle - n1) / n_span);
		R base;
		if (coupled) {
			R mapped = 0.0;
			for (int k = 0; k < stations; ++k) {
				mapped += m.induced_map[i * stations + k] * flow.angles[k] * (k == i ? R(1.0) : flow.sources[k]);
			}
			base = m.strip_cl0[i] + strip_slope * mapped;
		} else {
			base = cl0 + cla * effective;
		}
		R cl;
		R cd;
		if (ge_active) {
			base += (1.0 - ge[i]) * (strip_slope * (effective + m.strip_alpha_zero) - base);
			cl = weight == 0.0 ? base : (1.0 - weight) * base + weight * 0.5 * cd90 * sin_(2.0 * effective);
			cd = cd0 + (1.0 - weight) * ge[i] * k_induced * pow_(cl - cl_min_d, 2.0) +
				weight * cd90 * pow_(sin_(effective), 2.0);
		} else {
			cl = weight == 0.0 ? base : (1.0 - weight) * base + weight * 0.5 * cd90 * sin_(2.0 * effective);
			cd = cd0 + (1.0 - weight) * k_induced * pow_(cl - cl_min_d, 2.0) + weight * cd90 * pow_(sin_(effective), 2.0);
		}
		wing_cl += (flow.speeds[i] * cl) / static_cast<double>(stations);
		if (flow.speeds[i] == 0.0) {
			continue;
		}
		const R plane_speed = sqrt_(f0 * f0 + f2 * f2);
		const R force_scale = drag_q * plane_speed * station_area * cd;
		R fx = f0 * force_scale;
		const R fy = 0.0;
		R fz = f2 * force_scale;
		if (plane_speed > 0.0) {
			const R lift = lift_q * plane_speed * plane_speed * station_area * cl;
			fx += lift * f2 / plane_speed;
			fz -= lift * f0 / plane_speed;
		}
		fx_sum += fx;
		fy_sum += fy;
		fz_sum += fz;
		mx_sum += arm_y * fz - az * fy;
		my_sum += az * fx - ax_i * fz;
		mz_sum += ax_i * fy - arm_y * fx;
		if (cm_ac != 0.0 && plane_speed > 0.0) {
			const R section_my = lift_q * plane_speed * plane_speed * station_area * m.station_chords[i] * cm_ac;
			my_sum += section_my;
		}
	}
	R wake = is_nan(downwash_cl) ? wing_cl : downwash_cl;
	if (ge_active) {
		wake *= ge[stations + 1];
	}
	for (int tail_index = 0; tail_index < 2; ++tail_index) {
		const bool vertical = tail_index == 1;
		if (!vertical && !m.horizontal.present) {
			continue;
		}
		const Tail &tail = vertical ? m.vertical : m.horizontal;
		const R arm[3] = {-(tail.position[0] - m.cg[0]), tail.position[1] - m.cg[1], -(tail.position[2] - m.cg[2])};
		const R tail_flow[3] = {v[0] + (q * arm[2] - r * arm[1]), v[1] + (r * arm[0] - p * arm[2]),
			v[2] + (p * arm[1] - q * arm[0])};
		const Loads result = tail_surface_from_flow(tail_flow, arm, d, tail, m, tail.area, vertical, rho, wake);
		fx_sum += result[0];
		fy_sum += result[1];
		fz_sum += result[2];
		mx_sum += result[3];
		my_sum += result[4];
		mz_sum += result[5];
	}
	const R body_cn = m.body_cn_beta;
	if (body_cn != 0.0) {
		mz_sum += 0.5 * rho * m.S * m.b * body_cn * v0 * v1 * (1.0 - sideslip_weight(air.beta, m));
	}
	const R wing_body_cl = m.wing_body_cl_beta;
	if (wing_body_cl != 0.0) {
		mx_sum += 0.5 * rho * m.S * m.b * wing_body_cl * v0 * v1 * (1.0 - sideslip_weight(air.beta, m));
	}
	const R body_cy = m.body_cy_beta;
	const R body_cda = m.body_crossflow_area;
	if (body_cy != 0.0 || body_cda != 0.0) {
		const R fy_body = 0.5 * rho * (m.S * body_cy * maxf(v0, 0.0) * v1 - body_cda * sqrt_(v1 * v1 + v2 * v2) * v1);
		fy_sum += fy_body;
		mx_sum += -az * fy_body;
		mz_sum += ax * fy_body;
	}
	return {fx_sum, fy_sum, fz_sum, mx_sum, my_sum, mz_sum};
}

// aero.gd loads for a supported (envelope, no flaps) model.
inline Loads aero_loads(const R *s, const Air &air, const Deflections &d, const AeroModel &m, R rho,
		R downwash_cl, R ground_up) {
	std::vector<R> ge;
	ge_factors(s, m, ground_up, ge);
	const R blend = local_flow_weight(s, air, d, m, downwash_cl, ge);
	if (blend == 0.0) {
		return global_loads(s, air, d, m, rho, downwash_cl, ge);
	}
	const Loads local = local_loads(s, air, d, m, rho, downwash_cl, ge);
	if (blend == 1.0) {
		return local;
	}
	Loads global = global_loads(s, air, d, m, rho, downwash_cl, ge);
	for (int k = 0; k < 6; ++k) {
		global[k] = lerpf(global[k], local[k], blend);
	}
	return global;
}

} // namespace nk
