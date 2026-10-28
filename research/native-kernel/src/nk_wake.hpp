// NK-3 draft: the prepared tail-slipstream laws from app/physics/slipstream.gd,
// swirl_loads.gd and wash_transport.gd. The caller validates model shapes, supplies
// the same-stage thrust/torque, and owns all state advancement. Not qualified for
// native admission until compared with those GDScript components and stage replays.
#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <vector>

#include "nk_aero.hpp"
#include "nk_prop.hpp"

namespace nk {

struct WakePiece {
	bool vertical = false;
	R area = 0.0;
	R root[3] = {0.0, 0.0, 0.0};
	R span_dir[3] = {0.0, 0.0, 0.0};
	R span = 0.0;
	R chords[2] = {0.0, 0.0};
	// Each interval is [start, end, chord_start, chord_end], in source order.
	std::vector<R> profile;
};

struct WakeModel {
	bool enabled = false, smooth = false, segmented = false, transport = false;
	R hub[3] = {0.0, 0.0, 0.0};
	R wash_factor[2] = {0.0, 0.0};
	R swirl_factor = 0.0, vertical_drift = 0.0, edge_fraction = 0.0;
	R reverse_fade[2] = {0.0, 0.0};
	R sidewash_gain = 0.0, transport_speed_floor = 0.0;
	std::vector<WakePiece> pieces;
};

// Return false or a nonfinite delta for invalid point sampling. The callback is
// entirely native and returns body-relative ambient deltas, excluding omega x r.
struct WakePointSampler {
	bool (*sample)(void *context, const R *arm, R *delta) = nullptr;
	void *context = nullptr;
};

struct WakeState {
	R u = 0.0, w = 0.0, vs = 0.0, dv = 0.0, rs = 0.0, swirl = 0.0, core = 0.0;
};

inline std::array<R, 3> wake_axis(const PropModel &prop) {
	return prop.has_axis ? std::array<R, 3>{prop.axis[0], prop.axis[1], prop.axis[2]}
		: std::array<R, 3>{1.0, 0.0, 0.0};
}

inline WakeState wake_state(const R *v, R thrust, R torque, const PropModel &prop, const WakeModel &ss, R rho) {
	const R radius = 0.5 * prop.diameter;
	const R area = kPi * radius * radius;
	const auto ax = wake_axis(prop);
	const R axial = v[0] * ax[0] + v[1] * ax[1] + v[2] * ax[2];
	const R u = ss.smooth ? axial : maxf(axial, 0.0);
	const R vs = sqrt_(maxf(u * u + 2.0 * thrust / (rho * area), 0.0));
	const R w = 0.5 * (vs - u);
	const R ratio = clampf((u + w) / maxf(u + 2.0 * w, 1e-6),
		ss.smooth ? R(0.25) : R(0.7071) * R(0.7071), R(1.5) * R(1.5));
	const R m = w > 0.0 ? u / maxf(u + w, 1e-6) : R(1.0);
	const R kw = lerpf(ss.wash_factor[0], ss.wash_factor[1], clampf(m / 0.75, 0.0, 1.0));
	const R swirl = ss.swirl_factor * 0.5 * kw * torque / (rho * area * maxf(u + w, 1.0));
	return {u, w, u + 2.0 * w, kw * w, radius * sqrt_(ratio), swirl, 0.3 * radius};
}

inline R wake_reverse_weight(const R *v, R rpm, const PropModel &prop, const WakeModel &ss) {
	if (rpm < kStoppedRpm) {
		return 0.0;
	}
	const R vi0 = rpm / 60.0 * prop.diameter * sqrt_(2.0 * R(prop.ct[1]) / kPi);
	const auto ax = wake_axis(prop);
	const R ratio = -(v[0] * ax[0] + v[1] * ax[1] + v[2] * ax[2]) / vi0;
	return 1.0 - aero_smoothstep((ratio - ss.reverse_fade[0]) / (ss.reverse_fade[1] - ss.reverse_fade[0]));
}

// The thrust/torque supplied here must be the values used by WashTransport's
// own Propulsion.thrust_torque call, not necessarily the glow stage wake values.
inline std::array<R, 2> wake_transport_target(const R *source, R rpm, R thrust, R torque,
		const PropModel &prop, const WakeModel &ss, R rho) {
	const WakeState w = wake_state(source, thrust, torque, prop, ss, rho);
	R equilibrium = w.dv;
	if (rpm < kStoppedRpm || wake_reverse_weight(source, rpm, prop, ss) == 0.0) {
		equilibrium = 0.0;
	}
	return {equilibrium, maxf(w.u + w.w, ss.transport_speed_floor)};
}

// Output has exactly pieces.size() entries. The caller validates lagged length.
inline void wake_transport_derivative(const std::array<R, 2> &target, const R *lagged,
		const WakeModel &ss, R *out) {
	for (std::size_t i = 0; i < ss.pieces.size(); ++i) {
		const R distance = ss.pieces[i].root[0] - ss.hub[0];
		out[i] = (target[0] - lagged[i]) * target[1] / distance;
	}
}

inline std::array<R, 2> wake_profile_moments(const std::vector<R> &profile, R along, R d2, R rs, R edge) {
	static constexpr double x[5] = {-0.906179845938664, -0.538469310105683, 0.0,
		0.538469310105683, 0.906179845938664};
	static constexpr double weight[5] = {0.236926885056189, 0.478628670499366, 0.568888888888889,
		0.478628670499366, 0.236926885056189};
	const R inner2 = rs * rs * (1.0 - edge) * (1.0 - edge);
	const R outer2 = rs * rs * (1.0 + edge) * (1.0 + edge);
	if (d2 >= outer2) {
		return {0.0, 0.0};
	}
	const R outer = sqrt_(outer2 - d2);
	const R inner = sqrt_(maxf(inner2 - d2, 0.0));
	R total = 0.0, moment = 0.0;
	for (std::size_t i = 0; i < profile.size(); i += 4) {
		const R start = profile[i], end = profile[i + 1];
		const R a = maxf(start, -along - outer);
		const R b = minf(end, -along + outer);
		if (b <= a) continue;
		const R slope = (profile[i + 3] - profile[i + 2]) / (end - start);
		for (int zone = 0; zone < 3; ++zone) {
			R lo = a, hi = b;
			if (zone == 0) hi = minf(b, -along - inner);
			else if (zone == 1) { lo = maxf(a, -along - inner); hi = minf(b, -along + inner); }
			else lo = maxf(a, -along + inner);
			if (hi <= lo) continue;
			const R middle = 0.5 * (lo + hi), half = 0.5 * (hi - lo);
			const R chord = profile[i + 2] + slope * (middle - start);
			if (zone == 1) {
				const R strip = 2.0 * half * chord;
				total += strip;
				moment += middle * strip + slope * 2.0 * half * half * half / 3.0;
			} else {
				for (int k = 0; k < 5; ++k) {
					const R offset = half * x[k], eta = middle + offset, radial = eta + along;
					const R t = clampf((d2 + radial * radial - inner2) / (outer2 - inner2), 0.0, 1.0);
					const R strip = half * weight[k] * (chord + slope * offset) * (1.0 - t * t * (3.0 - 2.0 * t));
					total += strip;
					moment += eta * strip;
				}
			}
		}
	}
	return {total, moment};
}

inline std::array<R, 3> wake_sidewash(const R *v, R rpm, const PropModel &prop,
		const WakeState &w, const R *ax, R rho, R gain) {
	const R inflow = w.w / maxf(w.u, 1e-6);
	const R k = 1.0 + 2.0 * inflow;
	const R denominator = 1.0 + k * k;
	const R g = 2.0 * (1.0 + inflow) * k / denominator;
	const R h = k * (2.0 + 2.0 * inflow) / denominator;
	const R mass_flow = rho * kPi * 0.25 * prop.diameter * prop.diameter * maxf(w.u + w.w, 1.0);
	const auto normal = prop_normal_force(v, rpm, prop, rho);
	const R along = v[0] * ax[0] + v[1] * ax[1] + v[2] * ax[2];
	std::array<R, 3> out{};
	for (int c = 0; c < 3; ++c) {
		out[c] = gain * (0.5 * g * normal[c] / mass_flow + (h - 1.0) * (v[c] - ax[c] * along));
	}
	return out;
}

inline bool wake_point_air(const R *v, const WakePointSampler *sampler, const R *arm, R *out) {
	for (int i = 0; i < 3; ++i) out[i] = v[i];
	if (sampler == nullptr) return true;
	if (sampler->sample == nullptr) return false;
	R delta[3];
	if (!sampler->sample(sampler->context, arm, delta)) return false;
	for (int i = 0; i < 3; ++i) {
		if (!is_finite(delta[i])) return false;
		if (delta[i] != 0.0) out[i] += delta[i];
		if (!is_finite(out[i])) return false;
	}
	return true;
}

inline Loads wake_invalid() { return {kNan, kNan, kNan, kNan, kNan, kNan}; }

// Cached scalar form of Slipstream._tail_law and _add_tail_load, used only by
// its legacy segmented path. Its operation order differs from surface_with_flow.
struct WakeTailLaw {
	bool vertical = false;
	R slope = 0.0, offset = 0.0, gain = 0.0, wake = 0.0;
	R limit = 0.0, span = 0.0, cd0 = 0.0, k = 0.0, cd90 = 0.0, lift_q = 0.0;
};

inline WakeTailLaw wake_tail_law(const Tail &tail, const AeroModel &m, const Deflections &d,
		bool vertical, R wing_cl, R rho) {
	const R control = vertical ? -d.rudder : d.elevator;
	const bool free_law = !vertical && tail.free;
	const R slope = free_law ? tail.free_slope : tail.lift_slope;
	const R offset = free_law ? tail.elevator_tau * control + tail.free_incidence
		: tail.control_effectiveness * control + tail.incidence;
	return {vertical, slope, offset, free_law ? tail.downwash_per_cl : R(0.0),
		free_law ? wing_cl : R(0.0), m.tail_local_limit, m.tail_stall_end - m.tail_local_limit,
		m.tail_CD0, m.tail_k, m.tail_CD90, 0.5 * rho};
}

inline void wake_add_tail_load(Loads &out, const WakeTailLaw &law, R sign,
		R f0, R f1, R f2, R a0, R a1, R a2, R area) {
	const R normal = law.vertical ? f1 : f2;
	const R plane = sqrt_(f0 * f0 + normal * normal);
	if (plane == 0.0) return;
	R angle = atan2_(normal, f0);
	if (law.gain != 0.0 && law.wake != 0.0) angle -= atan2_(law.gain * law.wake, plane);
	const R effective = wrapf(angle + law.offset, -kPi, kPi);
	R blend = clampf((absf(effective) - law.limit) / law.span, 0.0, 1.0);
	blend = blend * blend * (3.0 - 2.0 * blend);
	const R cl = (1.0 - blend) * law.slope * effective + blend * 0.5 * law.cd90 * sin_(2.0 * effective);
	const R cd = law.cd0 + law.k * cl * cl + law.cd90 * pow_(sin_(effective), 2.0);
	const R force_scale = -law.lift_q * plane * area * cd;
	const R lift = law.lift_q * plane * plane * area * cl;
	const R fx = f0 * force_scale + lift * normal / plane;
	R fy = 0.0, fz = 0.0;
	if (law.vertical) fy = normal * force_scale - lift * f0 / plane;
	else fz = normal * force_scale - lift * f0 / plane;
	out[0] += sign * fx;
	out[1] += sign * fy;
	out[2] += sign * fz;
	out[3] += sign * (a1 * fz - a2 * fy);
	out[4] += sign * (a2 * fx - a0 * fz);
	out[5] += sign * (a0 * fy - a1 * fx);
}

struct WakeGeometry {
	R centre[3] = {0.0, 0.0, 0.0};
	R along = 0.0, d2 = 0.0;
};

inline WakeGeometry wake_geometry(const WakePiece &piece, const WakeModel &ss,
		const WakeState &w, const R *ax, const R *source) {
	const R speed = sqrt_(source[0] * source[0] + source[1] * source[1] + source[2] * source[2]);
	const R ax_le_0 = -ax[0], ax_le_1 = ax[1], ax_le_2 = -ax[2];
	const R distance = piece.root[0] - ss.hub[0];
	const R shaft_scale = distance / ax_le_0;
	WakeGeometry geometry;
	geometry.centre[0] = ss.hub[0] + ax_le_0 * shaft_scale;
	geometry.centre[1] = ss.hub[1] + ax_le_1 * shaft_scale;
	geometry.centre[2] = ss.hub[2] + ax_le_2 * shaft_scale;
	if (speed > 1e-6 && w.vs > 1e-6) {
		const R lean = minf(speed / (w.u + w.w), 1.0) * distance / speed;
		geometry.centre[1] -= source[1] * lean;
		geometry.centre[2] += source[2] * lean * ss.vertical_drift;
	}
	const R r0 = piece.root[0] - geometry.centre[0], r1 = piece.root[1] - geometry.centre[1];
	const R r2 = piece.root[2] - geometry.centre[2];
	geometry.along = r0 * piece.span_dir[0] + r1 * piece.span_dir[1] + r2 * piece.span_dir[2];
	const R p0 = r0 - piece.span_dir[0] * geometry.along;
	const R p1 = r1 - piece.span_dir[1] * geometry.along;
	const R p2 = r2 - piece.span_dir[2] * geometry.along;
	geometry.d2 = p0 * p0 + p1 * p1 + p2 * p2;
	return geometry;
}

// Slipstream._segmented_increment at the production subdivision count (1).
// Its result is summed per piece, then into the outer stage in source order.
inline Loads wake_segmented_increment(const WakePiece &piece, const Tail &tail, R a, R b, R c0, R slope,
		const WakeGeometry &geo, const R *ax, R core, R swirl, const R *wash,
		const R *state, const R *v, const Deflections &d, const AeroModel &m, R rho, R wing_cl,
		const WakePointSampler *sampler) {
	static constexpr double x[5] = {-0.906179845938664, -0.538469310105683, 0.0,
		0.538469310105683, 0.906179845938664};
	static constexpr double weights[5] = {0.236926885056189, 0.478628670499366, 0.568888888888889,
		0.478628670499366, 0.236926885056189};
	std::array<R, 5> cuts{a, b};
	std::size_t count = 2;
	if (core * core > geo.d2) {
		const R core_half = sqrt_(core * core - geo.d2);
		for (R cut : {-geo.along - core_half, -geo.along + core_half}) {
			if (cut > a && cut < b) cuts[count++] = cut;
		}
	}
	if (-geo.along > a && -geo.along < b) cuts[count++] = -geo.along;
	std::sort(cuts.begin(), cuts.begin() + static_cast<std::ptrdiff_t>(count), [](R left, R right) { return left.v < right.v; });
	const R full = c0 * piece.span + 0.5 * slope * piece.span * piece.span;
	const WakeTailLaw law = wake_tail_law(tail, m, d, piece.vertical, wing_cl, rho);
	const R p = state[10], q = state[11], r = state[12];
	Loads out{};
	for (std::size_t j = 0; j + 1 < count; ++j) {
		const R lo = cuts[j], hi = cuts[j + 1];
		const R segment_area = (c0 * hi + 0.5 * slope * hi * hi) - (c0 * lo + 0.5 * slope * lo * lo);
		if (segment_area <= 0.0) continue;
		const R eta = ((0.5 * c0 * hi * hi + slope * hi * hi * hi / 3.0)
			- (0.5 * c0 * lo * lo + slope * lo * lo * lo / 3.0)) / segment_area;
		R s0 = 0.0, s1 = 0.0, s2 = 0.0, weight_sum = 0.0;
		const R middle = 0.5 * (lo + hi), half = 0.5 * (hi - lo);
		for (int k = 0; k < 5; ++k) {
			const R sample = middle + half * x[k];
			const R weight = (c0 + slope * sample) * weights[k];
			R rb0 = -(piece.root[0] + piece.span_dir[0] * sample - geo.centre[0]);
			R rb1 = piece.root[1] + piece.span_dir[1] * sample - geo.centre[1];
			R rb2 = -(piece.root[2] + piece.span_dir[2] * sample - geo.centre[2]);
			const R axial = rb0 * ax[0] + rb1 * ax[1] + rb2 * ax[2];
			rb0 -= ax[0] * axial;
			rb1 -= ax[1] * axial;
			rb2 -= ax[2] * axial;
			const R radius = maxf(sqrt_(rb0 * rb0 + rb1 * rb1 + rb2 * rb2), core);
			const R scale = swirl / (radius * radius) * weight;
			s0 += (ax[1] * rb2 - ax[2] * rb1) * scale;
			s1 += (ax[2] * rb0 - ax[0] * rb2) * scale;
			s2 += (ax[0] * rb1 - ax[1] * rb0) * scale;
			weight_sum += weight;
		}
		s0 /= weight_sum; s1 /= weight_sum; s2 /= weight_sum;
		const R arm[3] = {-(tail.position[0] - m.cg[0]),
			tail.position[1] - m.cg[1] + (piece.root[1] + piece.span_dir[1] * eta - tail.position[1]),
			-(tail.position[2] - m.cg[2]) - (piece.root[2] + piece.span_dir[2] * eta - tail.position[2])};
		const R rate0 = q * arm[2] - r * arm[1], rate1 = r * arm[0] - p * arm[2];
		const R rate2 = p * arm[1] - q * arm[0];
		const R area = piece.area * segment_area / full;
		R local_v[3];
		if (!wake_point_air(v, sampler, arm, local_v)) return wake_invalid();
		wake_add_tail_load(out, law, 1.0, local_v[0] + (wash[0] - s0) + rate0,
			local_v[1] + (wash[1] - s1) + rate1, local_v[2] + (wash[2] - s2) + rate2,
			arm[0], arm[1], arm[2], area);
		wake_add_tail_load(out, law, -1.0, local_v[0] + rate0, local_v[1] + rate1, local_v[2] + rate2,
			arm[0], arm[1], arm[2], area);
	}
	return out;
}

// swirl_loads.gd uses a separate scalar tail implementation whose arithmetic
// and three-dimensional zero-flow test differ from the segmented helper.
inline Loads wake_swirl_tail(const R *flow, const R *arm, R area, const Tail &tail,
		const AeroModel &m, const Deflections &d, bool vertical, R rho, R wing_cl) {
	const bool has_downwash = !vertical && tail.free;
	const R control = vertical ? -d.rudder : d.elevator;
	const R control_angle = tail.control_effectiveness * control;
	const R downwash_product = tail.downwash_per_cl * wing_cl;
	const R elevator_tau_control = tail.elevator_tau * control;
	const R slope = has_downwash ? tail.free_slope : tail.lift_slope;
	const R normal = flow[vertical ? 1 : 2];
	R effective;
	if (has_downwash) {
		effective = wrapf(atan2_(flow[2], flow[0]) - downwash_angle(downwash_product, 1.0,
			sqrt_(flow[0] * flow[0] + normal * normal)) + elevator_tau_control + tail.free_incidence, -kPi, kPi);
	} else {
		effective = wrapf(atan2_(normal, flow[0]) + control_angle + tail.incidence, -kPi, kPi);
	}
	const R blend_input = (absf(effective) - m.tail_local_limit) / (m.tail_stall_end - m.tail_local_limit);
	const R blend = aero_smoothstep(blend_input);
	const R cl = (1.0 - blend) * slope * effective + blend * 0.5 * m.tail_CD90 * sin_(2.0 * effective);
	const R sine = sin_(effective);
	const R cd = m.tail_CD0 + m.tail_k * cl * cl + m.tail_CD90 * pow_(sine, 2.0);
	const R flow_speed = sqrt_(flow[0] * flow[0] + flow[1] * flow[1] + flow[2] * flow[2]);
	Loads out{};
	if (flow_speed > 0.0) {
		const R plane = sqrt_(flow[0] * flow[0] + normal * normal);
		const R force_scale = -0.5 * rho * plane * area * cd;
		out[0] = flow[0] * force_scale;
		out[1] = vertical ? flow[1] * force_scale : R(0.0);
		out[2] = vertical ? R(0.0) : flow[2] * force_scale;
		if (plane > 0.0) {
			const R lift = 0.5 * rho * plane * plane * area * cl;
			out[0] += lift * normal / plane;
			if (vertical) out[1] -= lift * flow[0] / plane;
			else out[2] -= lift * flow[0] / plane;
		}
		out[3] = arm[1] * out[2] - arm[2] * out[1];
		out[4] = arm[2] * out[0] - arm[0] * out[2];
		out[5] = arm[0] * out[1] - arm[1] * out[0];
	}
	return out;
}

inline R wake_occupancy(R eta, R along, R d2, R inner2, R outer2) {
	const R radial = eta + along;
	const R radius2 = d2 + radial * radial;
	if (radius2 <= inner2) return 1.0;
	if (radius2 >= outer2) return 0.0;
	const R t = clampf((radius2 - inner2) / (outer2 - inner2), 0.0, 1.0);
	return 1.0 - t * t * (3.0 - 2.0 * t);
}

inline void wake_insert_circle_roots(std::array<R, 8> &splits, std::size_t &count,
		R along, R d2, R radius2, R start, R end) {
	const R radial2 = radius2 - d2;
	if (radial2 < 0.0) return;
	const R half = sqrt_(radial2);
	const R first = -along - half;
	if (first > start && first < end) splits[count++] = first;
	if (half > 1.0e-14) {
		const R second = -along + half;
		if (second > start && second < end) splits[count++] = second;
	}
}

inline Loads wake_swirl_interval(const R *state, const R *v, const Deflections &d, const AeroModel &m,
		const WakePiece &piece, const Tail &tail, const WakeGeometry &geo, const WakeState &w, const R *ax,
		R inner2, R outer2, R area_scale, R start, R end, R chord_start, R chord_end, R lo, R hi,
		R rho, R wing_cl, const WakePointSampler *sampler) {
	static constexpr double x[5] = {-0.9061798459386640, -0.5384693101056831, 0.0,
		0.5384693101056831, 0.9061798459386640};
	static constexpr double weights[5] = {0.2369268850561891, 0.4786286704993665, 0.5688888888888889,
		0.4786286704993665, 0.2369268850561891};
	const R middle = 0.5 * (lo + hi), half = 0.5 * (hi - lo);
	const R chord_slope = (chord_end - chord_start) / (end - start);
	const R arm_base_0 = -(tail.position[0] - m.cg[0]) + 0.0;
	const R arm_base_1 = tail.position[1] - m.cg[1];
	const R arm_base_2 = -(tail.position[2] - m.cg[2]);
	const R wash[3] = {ax[0] * w.dv, ax[1] * w.dv, ax[2] * w.dv};
	Loads result{};
	for (int node = 0; node < 5; ++node) {
		const R eta = middle + half * x[node];
		const R occupancy = wake_occupancy(eta, geo.along, geo.d2, inner2, outer2);
		if (occupancy <= 0.0) continue;
		const R chord = chord_start + chord_slope * (eta - start);
		const R sample_area = area_scale * half * weights[node] * chord * occupancy;
		if (sample_area <= 0.0) continue;
		const R point0 = piece.root[0] + piece.span_dir[0] * eta;
		const R point1 = piece.root[1] + piece.span_dir[1] * eta;
		const R point2 = piece.root[2] + piece.span_dir[2] * eta;
		const R shift1 = point1 - tail.position[1];
		const R shift2 = piece.vertical ? -(point2 - tail.position[2]) : R(0.0);
		const R arm[3] = {arm_base_0 + 0.0, arm_base_1 + shift1, arm_base_2 + shift2};
		const R rate0 = state[11] * arm[2] - state[12] * arm[1];
		const R rate1 = state[12] * arm[0] - state[10] * arm[2];
		const R rate2 = state[10] * arm[1] - state[11] * arm[0];
		R local_v[3];
		if (!wake_point_air(v, sampler, arm, local_v)) return wake_invalid();
		R rb0 = -(point0 - geo.centre[0]), rb1 = point1 - geo.centre[1], rb2 = -(point2 - geo.centre[2]);
		const R axial_projection = rb0 * ax[0] + rb1 * ax[1] + rb2 * ax[2];
		rb0 -= ax[0] * axial_projection; rb1 -= ax[1] * axial_projection; rb2 -= ax[2] * axial_projection;
		const R radius = maxf(sqrt_(rb0 * rb0 + rb1 * rb1 + rb2 * rb2), w.core);
		const R swirl_scale = w.swirl / (radius * radius);
		const R swirl0 = (ax[1] * rb2 - ax[2] * rb1) * swirl_scale;
		const R swirl1 = (ax[2] * rb0 - ax[0] * rb2) * swirl_scale;
		const R swirl2 = (ax[0] * rb1 - ax[1] * rb0) * swirl_scale;
		const R axial_flow[3] = {(local_v[0] + wash[0]) + rate0, (local_v[1] + wash[1]) + rate1,
			(local_v[2] + wash[2]) + rate2};
		const R swirl_flow[3] = {(local_v[0] + (wash[0] - swirl0)) + rate0,
			(local_v[1] + (wash[1] - swirl1)) + rate1, (local_v[2] + (wash[2] - swirl2)) + rate2};
		const Loads axial_load = wake_swirl_tail(axial_flow, arm, sample_area, tail, m, d, piece.vertical, rho, wing_cl);
		const Loads swirl_load = wake_swirl_tail(swirl_flow, arm, sample_area, tail, m, d, piece.vertical, rho, wing_cl);
		for (int c = 0; c < 6; ++c) result[c] += swirl_load[c] - axial_load[c];
	}
	return result;
}

inline Loads wake_swirl_correction(const R *state, const R *v, const Deflections &d, const AeroModel &m,
		const WakeModel &ss, const WakeState &w, const R *ax, const R *source, R fade, R rho, R wing_cl,
		const WakePointSampler *sampler) {
	Loads result{};
	if (fade == 0.0 || w.swirl == 0.0 || !ss.enabled || !ss.smooth) return result;
	for (const WakePiece &piece : ss.pieces) {
		Loads piece_result{};
		R profile_area = 0.0;
		for (std::size_t i = 0; i < piece.profile.size(); i += 4) {
			profile_area += 0.5 * (piece.profile[i + 2] + piece.profile[i + 3]) * (piece.profile[i + 1] - piece.profile[i]);
		}
		if (profile_area <= 0.0) continue;
		const R area_scale = piece.area / profile_area;
		const WakeGeometry geo = wake_geometry(piece, ss, w, ax, source);
		const R inner_radius = w.rs * (1.0 - ss.edge_fraction), outer_radius = w.rs * (1.0 + ss.edge_fraction);
		const R inner2 = inner_radius * inner_radius, outer2 = outer_radius * outer_radius;
		const Tail &tail = piece.vertical ? m.vertical : m.horizontal;
		for (std::size_t i = 0; i < piece.profile.size(); i += 4) {
			const R start = piece.profile[i], end = piece.profile[i + 1];
			std::array<R, 8> splits{start, end};
			std::size_t count = 2;
			wake_insert_circle_roots(splits, count, geo.along, geo.d2, inner2, start, end);
			wake_insert_circle_roots(splits, count, geo.along, geo.d2, outer2, start, end);
			wake_insert_circle_roots(splits, count, geo.along, geo.d2, w.core * w.core, start, end);
			std::sort(splits.begin(), splits.begin() + static_cast<std::ptrdiff_t>(count), [](R a, R b) { return a.v < b.v; });
			for (std::size_t j = 0; j + 1 < count; ++j) {
				const R lo = splits[j], hi = splits[j + 1];
				if (hi - lo <= 1.0e-14) continue;
				const Loads interval = wake_swirl_interval(state, v, d, m, piece, tail, geo, w, ax, inner2, outer2,
					area_scale, start, end, piece.profile[i + 2], piece.profile[i + 3], lo, hi, rho, wing_cl, sampler);
				for (int c = 0; c < 6; ++c) piece_result[c] += interval[c];
			}
		}
		for (int c = 0; c < 6; ++c) result[c] += piece_result[c];
	}
	for (int c = 0; c < 6; ++c) result[c] *= fade;
	return result;
}

// Slipstream.stage_loads. The caller supplies actual same-stage thrust/torque;
// lagged is either null or contains one value per piece. source_delta is an
// optional hub ambient delta (without rotation). The point sampler is queried
// only at tail force locations and remains native throughout this evaluation.
inline Loads wake_loads(const R *state, const Air &air, const Deflections &d, const AeroModel &m,
		const PropModel &prop, const WakeModel &ss, R rpm, R rho, R thrust, R torque, R downwash = kNan,
		const R *lagged = nullptr, const R *source_delta = nullptr, const WakePointSampler *sampler = nullptr) {
	if ((rpm < kStoppedRpm && lagged == nullptr) || !ss.enabled) return Loads{};
	R source[3] = {air.v[0], air.v[1], air.v[2]};
	for (int i = 0; i < 3; ++i) {
		if (!is_finite(source[i])) return wake_invalid();
		if (source_delta != nullptr) {
			if (!is_finite(source_delta[i])) return wake_invalid();
			if (source_delta[i] != 0.0) source[i] += source_delta[i];
			if (!is_finite(source[i])) return wake_invalid();
		}
	}
	if (sampler != nullptr && sampler->sample == nullptr) return wake_invalid();
	R fade = ss.smooth ? wake_reverse_weight(source, rpm, prop, ss) : R(1.0);
	if (lagged != nullptr && rpm < kStoppedRpm) fade = source[0] >= 0.0 ? R(1.0) : R(0.0);
	if (fade == 0.0) return Loads{};
	const WakeState w = wake_state(source, thrust, torque, prop, ss, rho);
	const auto axis = wake_axis(prop);
	const R *ax = axis.data();
	R wash[3] = {ax[0] * w.dv, ax[1] * w.dv, ax[2] * w.dv};
	const R swirl_strength = ss.smooth ? R(0.0) : w.swirl;
	R wing_cl = 0.0;
	if (m.horizontal.present && m.horizontal.free) {
		const std::vector<R> no_ground;
		wing_cl = is_nan(downwash) ? wing_lift_coefficient_with(state, air, d, m, no_ground, true) : downwash;
	}
	Loads out{};
	std::array<R, 3> crossflow{};
	if (ss.segmented) crossflow = wake_sidewash(source, rpm, prop, w, ax, rho, ss.sidewash_gain);
	for (std::size_t i = 0; i < ss.pieces.size(); ++i) {
		const WakePiece &piece = ss.pieces[i];
		if (lagged != nullptr) {
			wash[0] = ax[0] * lagged[i]; wash[1] = ax[1] * lagged[i]; wash[2] = ax[2] * lagged[i];
		}
		const WakeGeometry geo = wake_geometry(piece, ss, w, ax, source);
		R immersed, full, eta;
		if (ss.smooth) {
			const auto moments = wake_profile_moments(piece.profile, geo.along, geo.d2, w.rs, ss.edge_fraction);
			immersed = moments[0];
			if (immersed <= 0.0) continue;
			full = piece.area;
			eta = moments[1] / immersed;
		} else {
			if (geo.d2 >= w.rs * w.rs) continue;
			const R half = sqrt_(w.rs * w.rs - geo.d2);
			const R a = clampf(-geo.along - half, 0.0, piece.span);
			const R b = clampf(-geo.along + half, 0.0, piece.span);
			if (b <= a) continue;
			const R c0 = piece.chords[0], slope = (piece.chords[1] - c0) / piece.span;
			if (ss.segmented) {
				const R combined_wash[3] = {wash[0] + crossflow[0], wash[1] + crossflow[1], wash[2] + crossflow[2]};
				const Tail &tail = piece.vertical ? m.vertical : m.horizontal;
				const Loads segment = wake_segmented_increment(piece, tail, a, b, c0, slope, geo, ax,
					w.core, swirl_strength, combined_wash, state, air.v, d, m, rho, wing_cl, sampler);
				for (int c = 0; c < 6; ++c) out[c] += segment[c];
				continue;
			}
			const R area_b = c0 * b + 0.5 * slope * b * b;
			const R area_a = c0 * a + 0.5 * slope * a * a;
			immersed = area_b - area_a;
			full = c0 * piece.span + 0.5 * slope * piece.span * piece.span;
			if (immersed <= 0.0) continue;
			const R moment_b = 0.5 * c0 * b * b + slope * b * b * b / 3.0;
			const R moment_a = 0.5 * c0 * a * a + slope * a * a * a / 3.0;
			eta = (moment_b - moment_a) / immersed;
		}
		const R point0 = piece.root[0] + piece.span_dir[0] * eta;
		const R point1 = piece.root[1] + piece.span_dir[1] * eta;
		const R point2 = piece.root[2] + piece.span_dir[2] * eta;
		const Tail &tail = piece.vertical ? m.vertical : m.horizontal;
		const R shift1 = point1 - tail.position[1];
		R shift2 = -(point2 - tail.position[2]);
		if (ss.smooth && !piece.vertical) shift2 = 0.0;
		R rb0 = -(point0 - geo.centre[0]), rb1 = point1 - geo.centre[1], rb2 = -(point2 - geo.centre[2]);
		const R axial_projection = rb0 * ax[0] + rb1 * ax[1] + rb2 * ax[2];
		rb0 -= ax[0] * axial_projection; rb1 -= ax[1] * axial_projection; rb2 -= ax[2] * axial_projection;
		const R radius = maxf(sqrt_(rb0 * rb0 + rb1 * rb1 + rb2 * rb2), w.core);
		const R swirl_scale = swirl_strength / (radius * radius);
		const R swirl0 = (ax[1] * rb2 - ax[2] * rb1) * swirl_scale;
		const R swirl1 = (ax[2] * rb0 - ax[0] * rb2) * swirl_scale;
		const R swirl2 = (ax[0] * rb1 - ax[1] * rb0) * swirl_scale;
		const R area = piece.area * immersed / full;
		if (area <= 0.0) continue;
		const R arm[3] = {-(tail.position[0] - m.cg[0]) + 0.0,
			tail.position[1] - m.cg[1] + shift1, -(tail.position[2] - m.cg[2]) + shift2};
		const R rate0 = state[11] * arm[2] - state[12] * arm[1];
		const R rate1 = state[12] * arm[0] - state[10] * arm[2];
		const R rate2 = state[10] * arm[1] - state[11] * arm[0];
		R local_v[3];
		if (!wake_point_air(air.v, sampler, arm, local_v)) return wake_invalid();
		const R free_flow[3] = {(local_v[0] + 0.0) + rate0, (local_v[1] + 0.0) + rate1, (local_v[2] + 0.0) + rate2};
		const R washed_flow[3] = {(local_v[0] + (wash[0] - swirl0)) + rate0,
			(local_v[1] + (wash[1] - swirl1)) + rate1, (local_v[2] + (wash[2] - swirl2)) + rate2};
		const Loads free = tail_surface_from_flow(free_flow, arm, d, tail, m, area, piece.vertical, rho, wing_cl);
		const Loads washed = tail_surface_from_flow(washed_flow, arm, d, tail, m, area, piece.vertical, rho, wing_cl);
		for (int c = 0; c < 6; ++c) out[c] += washed[c] - free[c];
	}
	if (ss.smooth) {
		for (int c = 0; c < 6; ++c) out[c] *= fade;
		if (w.swirl != 0.0) {
			// Deliberately uses equilibrium wake.dv even with transported_dv: this is the current reference law.
			const Loads correction = wake_swirl_correction(state, air.v, d, m, ss, w, ax, source, fade, rho, wing_cl, sampler);
			for (int c = 0; c < 6; ++c) out[c] += correction[c];
		}
	}
	return out;
}

} // namespace nk
