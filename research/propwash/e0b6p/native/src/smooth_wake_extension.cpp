#include "smooth_wake_kernel.hpp"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <vector>

namespace {

using namespace openrc::smooth_wake;

constexpr double kPi = 3.141592653589793238462643383279502884;
constexpr double kSwirlSpeedFloor = 1.0;
constexpr double kRootTolerance = 1.0e-14;
constexpr double kGodotEpsilon = 1.0e-5;

// The fixed nodes and weights match PROFILE_X/PROFILE_W and GAUSS_X/GAUSS_W
// in app/physics/slipstream.gd and app/physics/swirl_loads.gd.
constexpr std::array<double, 5> kProfileX{
		-0.906179845938664, -0.538469310105683, 0.0, 0.538469310105683, 0.906179845938664};
constexpr std::array<double, 5> kProfileW{
		0.236926885056189, 0.478628670499366, 0.568888888888889, 0.478628670499366, 0.236926885056189};
constexpr std::array<double, 5> kGaussX{
		-0.9061798459386640, -0.5384693101056831, 0.0, 0.5384693101056831, 0.9061798459386640};
constexpr std::array<double, 5> kGaussW{
		0.2369268850561891, 0.4786286704993665, 0.5688888888888889, 0.4786286704993665, 0.2369268850561891};

using Loads6 = openrc::smooth_wake::Loads6;
using Vec3 = openrc::smooth_wake::Vec3;

bool is_finite(double value) {
	return std::isfinite(value);
}

bool is_finite(const Vec3 &value) {
	return is_finite(value[0]) && is_finite(value[1]) && is_finite(value[2]);
}

bool is_finite(const Pair &value) {
	return is_finite(value[0]) && is_finite(value[1]);
}

bool is_finite(const Loads6 &value) {
	for (double component : value) {
		if (!is_finite(component)) {
			return false;
		}
	}
	return true;
}

double clampf(double value, double low, double high) {
	return value < low ? low : (value > high ? high : value);
}

double maxf(double first, double second) {
	return first > second ? first : second;
}

double minf(double first, double second) {
	return first < second ? first : second;
}

double wrapf(double value, double low, double high) {
	// Match Godot 4.7's double wrapf calculation and CMP_EPSILON boundary check.
	const double range = high - low;
	if (std::abs(range) < kGodotEpsilon) {
		return low;
	}
	const double result = value - (range * std::floor((value - low) / range));
	double tolerance = kGodotEpsilon * std::abs(result);
	if (tolerance < kGodotEpsilon) {
		tolerance = kGodotEpsilon;
	}
	if (std::abs(result - high) < tolerance) {
		return low;
	}
	return result;
}

double smoothstep(double value) {
	if (value <= 0.0) {
		return 0.0;
	}
	if (value >= 1.0) {
		return 1.0;
	}
	return value * value * (3.0 - 2.0 * value);
}

double dot(const Vec3 &a, const Vec3 &b) {
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

Vec3 cross(const Vec3 &a, const Vec3 &b) {
	return Vec3{
		a[1] * b[2] - a[2] * b[1],
		a[2] * b[0] - a[0] * b[2],
		a[0] * b[1] - a[1] * b[0],
	};
}

struct Wake {
	double u = 0.0;
	double w = 0.0;
	double vs = 0.0;
	double dv = 0.0;
	double rs = 0.0;
	double swirl = 0.0;
	double core = 0.0;
};

struct Moments {
	double area = 0.0;
	double first = 0.0;
};

struct ProfileRoots {
	std::array<double, 2> values{};
	std::size_t count = 0;
};

bool compute_wake(const Vec3 &velocity, const Pair &thrust_torque, const Model &model,
		double rho, Wake &wake) {
	const double propeller_radius = 0.5 * model.propeller_diameter;
	const double disc_area = kPi * propeller_radius * propeller_radius;
	wake.u = dot(velocity, model.shaft_axis);
	const double vs = std::sqrt(maxf(wake.u * wake.u + 2.0 * thrust_torque[0] / (rho * disc_area), 0.0));
	wake.w = 0.5 * (vs - wake.u);
	const double ratio = clampf((wake.u + wake.w) / maxf(wake.u + 2.0 * wake.w, 1.0e-6), 0.25, 1.5 * 1.5);
	const double mass_flow_ratio = wake.w > 0.0 ? wake.u / maxf(wake.u + wake.w, 1.0e-6) : 1.0;
	const double wash_mix = clampf(mass_flow_ratio / 0.75, 0.0, 1.0);
	const double wash = model.wash_factor[0] + (model.wash_factor[1] - model.wash_factor[0]) * wash_mix;
	wake.vs = wake.u + 2.0 * wake.w;
	wake.dv = wash * wake.w;
	wake.rs = propeller_radius * std::sqrt(ratio);
	wake.swirl = model.swirl_factor * 0.5 * wash * thrust_torque[1] /
			(rho * disc_area * maxf(wake.u + wake.w, kSwirlSpeedFloor));
	wake.core = 0.3 * propeller_radius;
	return is_finite(wake.u) && is_finite(wake.w) && is_finite(wake.vs) && is_finite(wake.dv) &&
			is_finite(wake.rs) && is_finite(wake.swirl) && is_finite(wake.core);
}

Moments profile_moments(const Piece &piece, double along, double d2, double rs, double edge) {
	const double inner2 = rs * rs * (1.0 - edge) * (1.0 - edge);
	const double outer2 = rs * rs * (1.0 + edge) * (1.0 + edge);
	Moments result;
	if (d2 >= outer2) {
		return result;
	}
	const double outer = std::sqrt(outer2 - d2);
	const double inner = std::sqrt(maxf(inner2 - d2, 0.0));
	for (std::size_t i = 0; i < piece.profile_count; ++i) {
		const ProfileInterval &segment = piece.profile[i];
		const double start = segment.start;
		const double end = segment.end;
		const double a = maxf(start, -along - outer);
		const double b = minf(end, -along + outer);
		if (b <= a) {
			continue;
		}
		const double slope = (segment.chord_end - segment.chord_start) / (end - start);
		for (int zone = 0; zone < 3; ++zone) {
			double lo = a;
			double hi = b;
			if (zone == 0) {
				hi = minf(b, -along - inner);
			} else if (zone == 1) {
				lo = maxf(a, -along - inner);
				hi = minf(b, -along + inner);
			} else {
				lo = maxf(a, -along + inner);
			}
			if (hi <= lo) {
				continue;
			}
			const double middle = 0.5 * (lo + hi);
			const double half = 0.5 * (hi - lo);
			const double chord = segment.chord_start + slope * (middle - start);
			if (zone == 1) {
				const double strip = 2.0 * half * chord;
				result.area += strip;
				result.first += middle * strip + slope * 2.0 * half * half * half / 3.0;
			} else {
				for (std::size_t k = 0; k < kProfileX.size(); ++k) {
					const double offset = half * kProfileX[k];
					const double eta = middle + offset;
					const double radial = eta + along;
					const double t = clampf((d2 + radial * radial - inner2) / (outer2 - inner2), 0.0, 1.0);
					const double strip = half * kProfileW[k] * (chord + slope * offset) *
							(1.0 - t * t * (3.0 - 2.0 * t));
					result.area += strip;
					result.first += eta * strip;
				}
			}
		}
	}
	return result;
}

bool wake_centre(const Piece &piece, const Model &model, const Wake &wake, const Vec3 &velocity,
		double speed, Vec3 &centre, double &along, double &d2) {
	const Vec3 &axis = model.shaft_axis;
	const double ax_le_0 = -axis[0];
	const double ax_le_1 = axis[1];
	const double ax_le_2 = -axis[2];
	const double distance = piece.root[0] - model.hub[0];
	const double shaft_scale = distance / ax_le_0;
	centre[0] = model.hub[0] + ax_le_0 * shaft_scale;
	centre[1] = model.hub[1] + ax_le_1 * shaft_scale;
	centre[2] = model.hub[2] + ax_le_2 * shaft_scale;
	if (speed > 1.0e-6 && wake.vs > 1.0e-6) {
		const double lean = minf(speed / (wake.u + wake.w), 1.0) * distance / speed;
		centre[1] -= velocity[1] * lean;
		centre[2] += velocity[2] * lean * model.vertical_drift;
	}
	const Vec3 &e = piece.span_dir;
	const double rel_0 = piece.root[0] - centre[0];
	const double rel_1 = piece.root[1] - centre[1];
	const double rel_2 = piece.root[2] - centre[2];
	along = rel_0 * e[0] + rel_1 * e[1] + rel_2 * e[2];
	const double perp_0 = rel_0 - e[0] * along;
	const double perp_1 = rel_1 - e[1] * along;
	const double perp_2 = rel_2 - e[2] * along;
	d2 = perp_0 * perp_0 + perp_1 * perp_1 + perp_2 * perp_2;
	return is_finite(centre) && is_finite(along) && is_finite(d2);
}

Loads6 surface_with_flow(const Vec3 &flow, const Vec3 &arm, double area, double cl, double cd,
		bool vertical, double lift_q, double drag_q) {
	const double flow_speed = std::sqrt(flow[0] * flow[0] + flow[1] * flow[1] + flow[2] * flow[2]);
	double fx = 0.0;
	double fy = 0.0;
	double fz = 0.0;
	double mx = 0.0;
	double my = 0.0;
	double mz = 0.0;
	if (!(flow_speed < 1.0e-10)) {
		const double normal = vertical ? flow[1] : flow[2];
		const double plane_speed = std::sqrt(flow[0] * flow[0] + normal * normal);
		const double force_scale = drag_q * flow_speed * area * cd;
		fx = flow[0] * force_scale;
		fy = flow[1] * force_scale;
		fz = flow[2] * force_scale;
		if (plane_speed > 1.0e-10) {
			const double lift = lift_q * plane_speed * plane_speed * area * cl;
			fx += lift * normal / plane_speed;
			if (vertical) {
				fy -= lift * flow[0] / plane_speed;
			} else {
				fz -= lift * flow[0] / plane_speed;
			}
		}
		mx = arm[1] * fz - arm[2] * fy;
		my = arm[2] * fx - arm[0] * fz;
		mz = arm[0] * fy - arm[1] * fx;
	}
	return Loads6{fx, fy, fz, mx, my, mz};
}

Loads6 tail_load(const Vec3 &flow, const Vec3 &arm, double control, const TailSurface &tail,
		const Model &model, double area, bool vertical, double wing_cl,
		double lift_q, double drag_q) {
	const double normal = vertical ? flow[1] : flow[2];
	const bool has_downwash = !vertical && tail.has_free_slope;
	double effective = 0.0;
	double lift_slope = tail.lift_slope;
	if (has_downwash) {
		effective = wrapf(std::atan2(normal, flow[0]) - tail.downwash_per_cl * wing_cl +
				tail.elevator_tau * control + tail.free_incidence, -kPi, kPi);
		lift_slope = tail.free_slope;
	} else {
		effective = wrapf(std::atan2(normal, flow[0]) + tail.control_effectiveness * control + tail.incidence,
				-kPi, kPi);
	}
	const double blend = smoothstep((std::abs(effective) - model.tail_local_limit) /
			(model.tail_stall_end - model.tail_local_limit));
	const double cl = (1.0 - blend) * lift_slope * effective +
			blend * 0.5 * model.tail_cd90 * std::sin(2.0 * effective);
	const double sine = std::sin(effective);
	const double cd = model.tail_cd0 + model.tail_k * cl * cl + model.tail_cd90 * std::pow(sine, 2.0);
	return surface_with_flow(flow, arm, area, cl, cd, vertical, lift_q, drag_q);
}

bool profile_centroid_loads(const State13 &state, const Vec3 &velocity, const Pair &deflections,
		const Model &model, const Wake &wake, double rho, double fade, double wing_cl,
		const std::vector<double> &transported_dv, Loads6 &output) {
	const double v0 = velocity[0];
	const double v1 = velocity[1];
	const double v2 = velocity[2];
	const double p = state[10];
	const double q = state[11];
	const double r = state[12];
	const Vec3 &axis = model.shaft_axis;
	const double speed = std::sqrt(v0 * v0 + v1 * v1 + v2 * v2);
	if (!is_finite(speed)) {
		return false;
	}
	const double ax_le_0 = -axis[0];
	const double ax_le_1 = axis[1];
	const double ax_le_2 = -axis[2];
	const bool drifts = speed > 1.0e-6 && wake.vs > 1.0e-6;
	const double lean_ratio = drifts ? minf(speed / (wake.u + wake.w), 1.0) : 0.0;
	const double lift_q = 0.5 * rho;
	const double drag_q = -0.5 * rho;
	for (std::size_t i = 0; i < model.piece_count; ++i) {
		const Piece &piece = model.pieces[i];
		Vec3 centre{};
		const double distance = piece.root[0] - model.hub[0];
		const double shaft_scale = distance / ax_le_0;
		centre[0] = model.hub[0] + ax_le_0 * shaft_scale;
		centre[1] = model.hub[1] + ax_le_1 * shaft_scale;
		centre[2] = model.hub[2] + ax_le_2 * shaft_scale;
		if (drifts) {
			const double lean = lean_ratio * distance / speed;
			centre[1] -= v1 * lean;
			centre[2] += v2 * lean * model.vertical_drift;
		}
		const Vec3 &e = piece.span_dir;
		const double rel_0 = piece.root[0] - centre[0];
		const double rel_1 = piece.root[1] - centre[1];
		const double rel_2 = piece.root[2] - centre[2];
		const double along = rel_0 * e[0] + rel_1 * e[1] + rel_2 * e[2];
		const double perp_0 = rel_0 - e[0] * along;
		const double perp_1 = rel_1 - e[1] * along;
		const double perp_2 = rel_2 - e[2] * along;
		const double d2 = perp_0 * perp_0 + perp_1 * perp_1 + perp_2 * perp_2;
		const Moments moments = profile_moments(piece, along, d2, wake.rs, model.edge_fraction);
		const double immersed = moments.area;
		if (immersed <= 0.0) {
			continue;
		}
		const double full = piece.area;
		const double eta = moments.first / immersed;
		const double point_0 = piece.root[0] + e[0] * eta;
		const double point_1 = piece.root[1] + e[1] * eta;
		const double point_2 = piece.root[2] + e[2] * eta;
		const TailSurface &tail = model.tails[piece.surface];
		const double shift_1 = point_1 - tail.position[1];
		double shift_2 = -(point_2 - tail.position[2]);
		const bool vertical = piece.surface == 1;
		if (!vertical) {
			shift_2 = 0.0;
		}
		const double radial_body_0 = -(point_0 - centre[0]);
		const double radial_body_1 = point_1 - centre[1];
		const double radial_body_2 = -(point_2 - centre[2]);
		const double axial_projection = radial_body_0 * axis[0] + radial_body_1 * axis[1] + radial_body_2 * axis[2];
		const double radial_perp_0 = radial_body_0 - axis[0] * axial_projection;
		const double radial_perp_1 = radial_body_1 - axis[1] * axial_projection;
		const double radial_perp_2 = radial_body_2 - axis[2] * axial_projection;
		const double radius = maxf(std::sqrt(radial_perp_0 * radial_perp_0 + radial_perp_1 * radial_perp_1 +
				radial_perp_2 * radial_perp_2), wake.core);
		const double swirl_scale = 0.0 / (radius * radius);
		const double swirl_0 = (axis[1] * radial_perp_2 - axis[2] * radial_perp_1) * swirl_scale;
		const double swirl_1 = (axis[2] * radial_perp_0 - axis[0] * radial_perp_2) * swirl_scale;
		const double swirl_2 = (axis[0] * radial_perp_1 - axis[1] * radial_perp_0) * swirl_scale;
		const double piece_area = piece.area;
		const double area = piece_area * immersed / full;
		if (area <= 0.0) {
			continue;
		}
		const double arm_0 = -(tail.position[0] - model.cg_le[0]) + 0.0;
		const double arm_1 = tail.position[1] - model.cg_le[1] + shift_1;
		const double arm_2 = -(tail.position[2] - model.cg_le[2]) + shift_2;
		const double rate_arm_0 = q * arm_2 - r * arm_1;
		const double rate_arm_1 = r * arm_0 - p * arm_2;
		const double rate_arm_2 = p * arm_1 - q * arm_0;
		const double control = vertical ? -deflections[1] : deflections[0];
		const Vec3 free_flow{
				(v0 + 0.0) + rate_arm_0,
				(v1 + 0.0) + rate_arm_1,
				(v2 + 0.0) + rate_arm_2,
		};
		const Vec3 wash{
				axis[0] * (transported_dv.empty() ? wake.dv : transported_dv[i]),
				axis[1] * (transported_dv.empty() ? wake.dv : transported_dv[i]),
				axis[2] * (transported_dv.empty() ? wake.dv : transported_dv[i]),
		};
		const Vec3 washed_flow{
				(v0 + (wash[0] - swirl_0)) + rate_arm_0,
				(v1 + (wash[1] - swirl_1)) + rate_arm_1,
				(v2 + (wash[2] - swirl_2)) + rate_arm_2,
		};
		const Loads6 free_load = tail_load(free_flow, Vec3{arm_0, arm_1, arm_2}, control, tail,
				model, area, vertical, wing_cl, lift_q, drag_q);
		const Loads6 washed_load = tail_load(washed_flow, Vec3{arm_0, arm_1, arm_2}, control, tail,
				model, area, vertical, wing_cl, lift_q, drag_q);
		for (std::size_t component = 0; component < output.size(); ++component) {
			output[component] += washed_load[component] - free_load[component];
		}
	}
	for (double &component : output) {
		component *= fade;
	}
	return is_finite(output);
}

ProfileRoots circle_intersections(double along, double d2, double radius2) {
	ProfileRoots result;
	const double radial2 = radius2 - d2;
	if (radial2 < 0.0) {
		return result;
	}
	const double half = std::sqrt(radial2);
	result.values[result.count++] = -along - half;
	if (half > kRootTolerance) {
		result.values[result.count++] = -along + half;
	}
	return result;
}

void add_interior_roots(std::array<double, 8> &splits, std::size_t &split_count,
		const ProfileRoots &roots, double start, double end) {
	for (std::size_t i = 0; i < roots.count; ++i) {
		const double root = roots.values[i];
		if (root > start && root < end) {
			splits[split_count++] = root;
		}
	}
}

double occupancy(double eta, double along, double d2, double inner2, double outer2) {
	const double radial = eta + along;
	const double radius2 = d2 + radial * radial;
	if (radius2 <= inner2) {
		return 1.0;
	}
	if (radius2 >= outer2) {
		return 0.0;
	}
	const double t = clampf((radius2 - inner2) / (outer2 - inner2), 0.0, 1.0);
	return 1.0 - t * t * (3.0 - 2.0 * t);
}

void integrate_interval(const Vec3 &velocity, const Vec3 &rates, const Piece &piece, const Model &model,
		const Wake &wake, const TailSurface &tail,
		double centre_0, double centre_1, double centre_2, double along, double d2,
		double wash_0, double wash_1, double wash_2, double inner2, double outer2, double area_scale,
		const ProfileInterval &segment, double lo, double hi, double arm_base_0, double arm_base_1,
		double arm_base_2, bool horizontal, bool vertical, double control_angle, double incidence,
		double downwash_product, double elevator_tau_control, double free_incidence,
		double lift_slope, double tail_limit, double tail_span, double tail_cd0, double tail_k,
		double tail_cd90, double rho, Loads6 &result) {
	const double middle = 0.5 * (lo + hi);
	const double half = 0.5 * (hi - lo);
	const double chord_slope = (segment.chord_end - segment.chord_start) / (segment.end - segment.start);
	const double v0 = velocity[0];
	const double v1 = velocity[1];
	const double v2 = velocity[2];
	const double p = rates[0];
	const double q = rates[1];
	const double r = rates[2];
	const double axis_0 = model.shaft_axis[0];
	const double axis_1 = model.shaft_axis[1];
	const double axis_2 = model.shaft_axis[2];
	const double root_0 = piece.root[0];
	const double root_1 = piece.root[1];
	const double root_2 = piece.root[2];
	const double e_0 = piece.span_dir[0];
	const double e_1 = piece.span_dir[1];
	const double e_2 = piece.span_dir[2];
	Loads6 interval_result{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	for (std::size_t node = 0; node < kGaussX.size(); ++node) {
		const double eta = middle + half * kGaussX[node];
		const double sample_occupancy = occupancy(eta, along, d2, inner2, outer2);
		if (sample_occupancy <= 0.0) {
			continue;
		}
		const double chord = segment.chord_start + chord_slope * (eta - segment.start);
		const double sample_area = area_scale * half * kGaussW[node] * chord * sample_occupancy;
		if (sample_area <= 0.0) {
			continue;
		}
		const double point_0 = root_0 + e_0 * eta;
		const double point_1 = root_1 + e_1 * eta;
		const double point_2 = root_2 + e_2 * eta;
		const double shift_1 = point_1 - tail.position[1];
		const double shift_2 = horizontal ? 0.0 : -(point_2 - tail.position[2]);
		const double arm_0 = arm_base_0 + 0.0;
		const double arm_1 = arm_base_1 + shift_1;
		const double arm_2 = arm_base_2 + shift_2;
		const double rate_arm_0 = q * arm_2 - r * arm_1;
		const double rate_arm_1 = r * arm_0 - p * arm_2;
		const double rate_arm_2 = p * arm_1 - q * arm_0;
		double radial_body_0 = -(point_0 - centre_0);
		double radial_body_1 = point_1 - centre_1;
		double radial_body_2 = -(point_2 - centre_2);
		const double axial_projection = radial_body_0 * axis_0 + radial_body_1 * axis_1 + radial_body_2 * axis_2;
		radial_body_0 -= axis_0 * axial_projection;
		radial_body_1 -= axis_1 * axial_projection;
		radial_body_2 -= axis_2 * axial_projection;
		const double radius = maxf(std::sqrt(radial_body_0 * radial_body_0 + radial_body_1 * radial_body_1 +
				radial_body_2 * radial_body_2), wake.core);
		const double swirl_scale = wake.swirl / (radius * radius);
		const double swirl_0 = (axis_1 * radial_body_2 - axis_2 * radial_body_1) * swirl_scale;
		const double swirl_1 = (axis_2 * radial_body_0 - axis_0 * radial_body_2) * swirl_scale;
		const double swirl_2 = (axis_0 * radial_body_1 - axis_1 * radial_body_0) * swirl_scale;

		const double axial_flow_0 = (v0 + wash_0) + rate_arm_0;
		const double axial_flow_1 = (v1 + wash_1) + rate_arm_1;
		const double axial_flow_2 = (v2 + wash_2) + rate_arm_2;
		const double axial_normal = vertical ? axial_flow_1 : axial_flow_2;
		double axial_effective = 0.0;
		if (!vertical && tail.has_free_slope) {
			axial_effective = wrapf(std::atan2(axial_flow_2, axial_flow_0) - downwash_product +
					elevator_tau_control + free_incidence, -kPi, kPi);
		} else {
			axial_effective = wrapf(std::atan2(axial_normal, axial_flow_0) + control_angle + incidence,
					-kPi, kPi);
		}
		const double axial_blend_input = (std::abs(axial_effective) - tail_limit) / tail_span;
		const double axial_blend = smoothstep(axial_blend_input);
		const double axial_cl = (1.0 - axial_blend) * lift_slope * axial_effective +
				axial_blend * 0.5 * tail_cd90 * std::sin(2.0 * axial_effective);
		const double axial_sine = std::sin(axial_effective);
		const double axial_cd = tail_cd0 + tail_k * axial_cl * axial_cl + tail_cd90 * std::pow(axial_sine, 2.0);
		const double axial_flow_speed = std::sqrt(axial_flow_0 * axial_flow_0 + axial_flow_1 * axial_flow_1 +
				axial_flow_2 * axial_flow_2);
		double axial_fx = 0.0;
		double axial_fy = 0.0;
		double axial_fz = 0.0;
		double axial_mx = 0.0;
		double axial_my = 0.0;
		double axial_mz = 0.0;
		if (!(axial_flow_speed < 1.0e-10)) {
			const double axial_plane_speed = std::sqrt(axial_flow_0 * axial_flow_0 + axial_normal * axial_normal);
			const double axial_force_scale = -0.5 * rho * axial_flow_speed * sample_area * axial_cd;
			axial_fx = axial_flow_0 * axial_force_scale;
			axial_fy = axial_flow_1 * axial_force_scale;
			axial_fz = axial_flow_2 * axial_force_scale;
			if (axial_plane_speed > 1.0e-10) {
				const double axial_lift = 0.5 * rho * axial_plane_speed * axial_plane_speed * sample_area * axial_cl;
				axial_fx += axial_lift * axial_normal / axial_plane_speed;
				if (vertical) {
					axial_fy -= axial_lift * axial_flow_0 / axial_plane_speed;
				} else {
					axial_fz -= axial_lift * axial_flow_0 / axial_plane_speed;
				}
			}
			axial_mx = arm_1 * axial_fz - arm_2 * axial_fy;
			axial_my = arm_2 * axial_fx - arm_0 * axial_fz;
			axial_mz = arm_0 * axial_fy - arm_1 * axial_fx;
		}

		const double swirl_extra_0 = wash_0 - swirl_0;
		const double swirl_extra_1 = wash_1 - swirl_1;
		const double swirl_extra_2 = wash_2 - swirl_2;
		const double swirl_flow_0 = (v0 + swirl_extra_0) + rate_arm_0;
		const double swirl_flow_1 = (v1 + swirl_extra_1) + rate_arm_1;
		const double swirl_flow_2 = (v2 + swirl_extra_2) + rate_arm_2;
		const double swirl_normal = vertical ? swirl_flow_1 : swirl_flow_2;
		double swirl_effective = 0.0;
		if (!vertical && tail.has_free_slope) {
			swirl_effective = wrapf(std::atan2(swirl_flow_2, swirl_flow_0) - downwash_product +
					elevator_tau_control + free_incidence, -kPi, kPi);
		} else {
			swirl_effective = wrapf(std::atan2(swirl_normal, swirl_flow_0) + control_angle + incidence,
					-kPi, kPi);
		}
		const double swirl_blend_input = (std::abs(swirl_effective) - tail_limit) / tail_span;
		const double swirl_blend = smoothstep(swirl_blend_input);
		const double swirl_cl = (1.0 - swirl_blend) * lift_slope * swirl_effective +
				swirl_blend * 0.5 * tail_cd90 * std::sin(2.0 * swirl_effective);
		const double swirl_sine = std::sin(swirl_effective);
		const double swirl_cd = tail_cd0 + tail_k * swirl_cl * swirl_cl + tail_cd90 * std::pow(swirl_sine, 2.0);
		const double swirl_flow_speed = std::sqrt(swirl_flow_0 * swirl_flow_0 + swirl_flow_1 * swirl_flow_1 +
				swirl_flow_2 * swirl_flow_2);
		double swirl_fx = 0.0;
		double swirl_fy = 0.0;
		double swirl_fz = 0.0;
		double swirl_mx = 0.0;
		double swirl_my = 0.0;
		double swirl_mz = 0.0;
		if (!(swirl_flow_speed < 1.0e-10)) {
			const double swirl_plane_speed = std::sqrt(swirl_flow_0 * swirl_flow_0 + swirl_normal * swirl_normal);
			const double swirl_force_scale = -0.5 * rho * swirl_flow_speed * sample_area * swirl_cd;
			swirl_fx = swirl_flow_0 * swirl_force_scale;
			swirl_fy = swirl_flow_1 * swirl_force_scale;
			swirl_fz = swirl_flow_2 * swirl_force_scale;
			if (swirl_plane_speed > 1.0e-10) {
				const double swirl_lift = 0.5 * rho * swirl_plane_speed * swirl_plane_speed * sample_area * swirl_cl;
				swirl_fx += swirl_lift * swirl_normal / swirl_plane_speed;
				if (vertical) {
					swirl_fy -= swirl_lift * swirl_flow_0 / swirl_plane_speed;
				} else {
					swirl_fz -= swirl_lift * swirl_flow_0 / swirl_plane_speed;
				}
			}
			swirl_mx = arm_1 * swirl_fz - arm_2 * swirl_fy;
			swirl_my = arm_2 * swirl_fx - arm_0 * swirl_fz;
			swirl_mz = arm_0 * swirl_fy - arm_1 * swirl_fx;
		}
		interval_result[0] += swirl_fx - axial_fx;
		interval_result[1] += swirl_fy - axial_fy;
		interval_result[2] += swirl_fz - axial_fz;
		interval_result[3] += swirl_mx - axial_mx;
		interval_result[4] += swirl_my - axial_my;
		interval_result[5] += swirl_mz - axial_mz;
	}
	for (std::size_t component = 0; component < result.size(); ++component) {
		result[component] += interval_result[component];
	}
}

bool swirl_correction(const State13 &state, const Vec3 &velocity, const Pair &deflections,
		const Model &model, const Wake &wake, double fade, double rho, double wing_cl, Loads6 &result) {
	result = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	if (fade == 0.0 || wake.swirl == 0.0) {
		return true;
	}
	const Vec3 rates{state[10], state[11], state[12]};
	const Vec3 axis = model.shaft_axis;
	const Vec3 wash{
			axis[0] * wake.dv,
			axis[1] * wake.dv,
			axis[2] * wake.dv,
	};
	const double speed = std::sqrt(velocity[0] * velocity[0] + velocity[1] * velocity[1] + velocity[2] * velocity[2]);
	if (!is_finite(speed)) {
		return false;
	}
	for (std::size_t i = 0; i < model.piece_count; ++i) {
		const Piece &piece = model.pieces[i];
		Loads6 piece_result{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
		double profile_area = 0.0;
		for (std::size_t j = 0; j < piece.profile_count; ++j) {
			const ProfileInterval &segment = piece.profile[j];
			profile_area += 0.5 * (segment.chord_start + segment.chord_end) * (segment.end - segment.start);
		}
		if (profile_area <= 0.0) {
			continue;
		}
		const double area_scale = piece.area / profile_area;
		Vec3 centre{};
		double along = 0.0;
		double d2 = 0.0;
		if (!wake_centre(piece, model, wake, velocity, speed, centre, along, d2)) {
			return false;
		}
		const double inner_radius = wake.rs * (1.0 - model.edge_fraction);
		const double outer_radius = wake.rs * (1.0 + model.edge_fraction);
		const double inner2 = inner_radius * inner_radius;
		const double outer2 = outer_radius * outer_radius;
		const ProfileRoots core_roots = circle_intersections(along, d2, wake.core * wake.core);
		const ProfileRoots inner_roots = circle_intersections(along, d2, inner2);
		const ProfileRoots outer_roots = circle_intersections(along, d2, outer2);
		const TailSurface &tail = model.tails[piece.surface];
		const double arm_base_0 = -(tail.position[0] - model.cg_le[0]) + 0.0;
		const double arm_base_1 = tail.position[1] - model.cg_le[1];
		const double arm_base_2 = -(tail.position[2] - model.cg_le[2]);
		const bool horizontal = piece.surface == 0;
		const bool vertical = piece.surface == 1;
		const bool has_downwash = !vertical && tail.has_free_slope;
		const double control = vertical ? -deflections[1] : deflections[0];
		const double control_angle = tail.control_effectiveness * control;
		const double incidence = tail.incidence;
		const double downwash_product = tail.downwash_per_cl * wing_cl;
		const double elevator_tau_control = tail.elevator_tau * control;
		const double free_incidence = tail.free_incidence;
		const double lift_slope = has_downwash ? tail.free_slope : tail.lift_slope;
		const double tail_limit = model.tail_local_limit;
		const double tail_span = model.tail_stall_end - tail_limit;
		for (std::size_t profile_index = 0; profile_index < piece.profile_count; ++profile_index) {
			const ProfileInterval &segment = piece.profile[profile_index];
			std::array<double, 8> splits{};
			splits[0] = segment.start;
			splits[1] = segment.end;
			std::size_t split_count = 2;
			add_interior_roots(splits, split_count, inner_roots, segment.start, segment.end);
			add_interior_roots(splits, split_count, outer_roots, segment.start, segment.end);
			add_interior_roots(splits, split_count, core_roots, segment.start, segment.end);
			std::sort(splits.begin(), splits.begin() + static_cast<std::ptrdiff_t>(split_count));
			for (std::size_t interval = 0; interval + 1 < split_count; ++interval) {
				const double lo = splits[interval];
				const double hi = splits[interval + 1];
				if (hi - lo <= kRootTolerance) {
					continue;
				}
		integrate_interval(velocity, rates, piece, model, wake, tail,
						centre[0], centre[1], centre[2], along, d2,
						wash[0], wash[1], wash[2], inner2, outer2, area_scale, segment, lo, hi,
						arm_base_0, arm_base_1, arm_base_2, horizontal, vertical, control_angle, incidence,
						downwash_product, elevator_tau_control, free_incidence, lift_slope,
						tail_limit, tail_span, model.tail_cd0, model.tail_k, model.tail_cd90, rho, piece_result);
			}
		}
		for (std::size_t component = 0; component < result.size(); ++component) {
			result[component] += piece_result[component];
		}
	}
	for (double &component : result) {
		component *= fade;
	}
	return is_finite(result);
}

bool validate(const State13 &state, const Vec3 &velocity, const Pair &deflections, const Model &model,
		const Pair &thrust_torque, double rho, double fade, double downwash_cl,
		const std::vector<double> &transported_dv) {
	for (double value : state) {
		if (!is_finite(value)) {
			return false;
		}
	}
	if (!is_finite(velocity) || !is_finite(deflections) || !is_finite(thrust_torque) ||
			!is_finite(model.shaft_axis) || !is_finite(model.hub) || !is_finite(model.wash_factor) ||
			!is_finite(model.cg_le) || !is_finite(rho) || rho <= 0.0 || !is_finite(fade) || fade < 0.0 || fade > 1.0 ||
			!is_finite(model.propeller_diameter) || model.propeller_diameter <= 0.0 ||
			model.shaft_axis[0] != 1.0 || model.shaft_axis[1] != 0.0 || model.shaft_axis[2] != 0.0 ||
			!is_finite(model.swirl_factor) || !is_finite(model.vertical_drift) ||
			model.wash_factor[0] < 0.0 || model.wash_factor[0] > 2.0 ||
			model.wash_factor[1] < 0.0 || model.wash_factor[1] > 2.0 ||
			model.swirl_factor < 0.0 || model.swirl_factor > 1.0 ||
			model.vertical_drift < 0.0 || model.vertical_drift > 1.0 ||
			!is_finite(model.edge_fraction) || model.edge_fraction < 0.01 || model.edge_fraction > 0.5 ||
			!is_finite(model.tail_local_limit) || !is_finite(model.tail_stall_end) ||
			model.tail_stall_end <= model.tail_local_limit || !is_finite(model.tail_cd0) ||
			!is_finite(model.tail_k) || !is_finite(model.tail_cd90) || model.piece_count == 0 ||
			model.piece_count > 8 || (!transported_dv.empty() && transported_dv.size() != model.piece_count)) {
		return false;
	}
	if (!std::isfinite(downwash_cl)) {
		if (!std::isnan(downwash_cl) || model.tails[0].has_free_slope) {
			return false;
		}
	}
	for (double value : transported_dv) {
		if (!is_finite(value)) {
			return false;
		}
	}
	for (const TailSurface &tail : model.tails) {
		if (!is_finite(tail.position) || !is_finite(tail.lift_slope) || !is_finite(tail.free_slope) ||
				!is_finite(tail.control_effectiveness) || !is_finite(tail.incidence) ||
				!is_finite(tail.downwash_per_cl) || !is_finite(tail.elevator_tau) || !is_finite(tail.free_incidence)) {
			return false;
		}
	}
	for (std::size_t i = 0; i < model.piece_count; ++i) {
		const Piece &piece = model.pieces[i];
		if (piece.surface > 1 || !is_finite(piece.area) || piece.area < 0.001 || piece.area > 1.0 ||
				!is_finite(piece.span) || piece.span < 0.01 || piece.span > 2.0 ||
				!is_finite(piece.root) || !is_finite(piece.span_dir) || piece.profile_count == 0 ||
				piece.profile_count > kMaxProfileIntervals || piece.root[0] <= model.hub[0]) {
			return false;
		}
		const double span_dir_length = std::sqrt(piece.span_dir[0] * piece.span_dir[0] +
				piece.span_dir[1] * piece.span_dir[1] + piece.span_dir[2] * piece.span_dir[2]);
		if (!is_finite(span_dir_length) || std::abs(span_dir_length - 1.0) > 1.0e-6) {
			return false;
		}
		if (piece.span_dir[0] != 0.0 || (piece.surface == 0 ? piece.span_dir[2] != 0.0 : piece.span_dir[1] != 0.0)) {
			return false;
		}
		double previous = 0.0;
		double profile_area = 0.0;
		for (std::size_t j = 0; j < piece.profile_count; ++j) {
			const ProfileInterval &segment = piece.profile[j];
			if (!is_finite(segment.start) || !is_finite(segment.end) || !is_finite(segment.chord_start) ||
					!is_finite(segment.chord_end) || segment.start < previous || segment.start < 0.0 ||
					segment.end <= segment.start || segment.end > 3.0 || segment.end > piece.span + 1.0e-10 ||
					segment.chord_start < 0.0 || segment.chord_start > 3.0 || segment.chord_end < 0.0 ||
					segment.chord_end > 3.0 ||
					segment.chord_start + segment.chord_end <= 0.0) {
				return false;
			}
			profile_area += 0.5 * (segment.chord_start + segment.chord_end) * (segment.end - segment.start);
			previous = segment.end;
		}
		if (!is_finite(profile_area) || std::abs(profile_area - piece.area) > 1.0e-8) {
			return false;
		}
	}
	return true;
}

bool read_number(const godot::Variant &value, double &out) {
	const godot::Variant::Type type = value.get_type();
	if (type != godot::Variant::FLOAT && type != godot::Variant::INT) {
		return false;
	}
	out = static_cast<double>(value);
	return is_finite(out);
}

bool read_number(const godot::Dictionary &dictionary, const char *key, double &out) {
	return dictionary.has(key) && read_number(dictionary.get(key, godot::Variant()), out);
}

bool read_optional_number(const godot::Dictionary &dictionary, const char *key, double &out) {
	if (!dictionary.has(key)) {
		out = 0.0;
		return true;
	}
	return read_number(dictionary.get(key, godot::Variant()), out);
}

bool read_dictionary(const godot::Variant &value, godot::Dictionary &out) {
	if (value.get_type() != godot::Variant::DICTIONARY) {
		return false;
	}
	out = static_cast<godot::Dictionary>(value);
	return true;
}

bool read_array(const godot::Variant &value, godot::Array &out) {
	if (value.get_type() != godot::Variant::ARRAY) {
		return false;
	}
	out = static_cast<godot::Array>(value);
	return true;
}

bool read_packed(const godot::Variant &value, double *out, std::size_t expected) {
	if (value.get_type() != godot::Variant::PACKED_FLOAT64_ARRAY) {
		return false;
	}
	const godot::PackedFloat64Array array = static_cast<godot::PackedFloat64Array>(value);
	if (static_cast<std::size_t>(array.size()) != expected) {
		return false;
	}
	for (std::size_t i = 0; i < expected; ++i) {
		out[i] = array[static_cast<int64_t>(i)];
		if (!is_finite(out[i])) {
			return false;
		}
	}
	return true;
}

bool read_vec3(const godot::Dictionary &dictionary, const char *key, Vec3 &out) {
	return dictionary.has(key) && read_packed(dictionary.get(key, godot::Variant()), out.data(), out.size());
}

bool read_pair(const godot::Dictionary &dictionary, const char *key, Pair &out) {
	return dictionary.has(key) && read_packed(dictionary.get(key, godot::Variant()), out.data(), out.size());
}

bool read_profile(const godot::Dictionary &piece_value, Piece &piece) {
	const godot::Variant profile_value = piece_value.get("profile", godot::Variant());
	if (profile_value.get_type() != godot::Variant::PACKED_FLOAT64_ARRAY) {
		return false;
	}
	const godot::PackedFloat64Array profile = static_cast<godot::PackedFloat64Array>(profile_value);
	if (profile.is_empty() || profile.size() % 4 != 0 ||
			static_cast<std::size_t>(profile.size() / 4) > kMaxProfileIntervals) {
		return false;
	}
	piece.profile_count = static_cast<std::size_t>(profile.size() / 4);
	for (std::size_t i = 0; i < piece.profile_count; ++i) {
		const int64_t offset = static_cast<int64_t>(i * 4);
		piece.profile[i] = ProfileInterval{profile[offset], profile[offset + 1], profile[offset + 2], profile[offset + 3]};
	}
	return true;
}

bool read_model(const godot::Dictionary &model_value, Model &model) {
	godot::Dictionary propulsion;
	godot::Dictionary slipstream;
	godot::Dictionary surfaces;
	if (!read_dictionary(model_value.get("propulsion", godot::Variant()), propulsion) ||
			!read_dictionary(propulsion.get("slipstream", godot::Variant()), slipstream) ||
			!read_dictionary(model_value.get("surfaces", godot::Variant()), surfaces)) {
		return false;
	}
	if (!read_number(propulsion, "diameter", model.propeller_diameter) ||
			!read_vec3(slipstream, "hub", model.hub) || !read_pair(slipstream, "wash_factor", model.wash_factor) ||
			!read_number(slipstream, "swirl_factor", model.swirl_factor) ||
			!read_number(slipstream, "vertical_drift", model.vertical_drift) ||
			!read_number(slipstream, "edge_fraction", model.edge_fraction) ||
			!read_vec3(model_value, "cg_le", model.cg_le)) {
		return false;
	}
	if (propulsion.has("axis")) {
		if (!read_packed(propulsion.get("axis", godot::Variant()), model.shaft_axis.data(), model.shaft_axis.size())) {
			return false;
		}
	} else {
		model.shaft_axis = Vec3{1.0, 0.0, 0.0};
	}
	if (!read_number(surfaces, "tail_local_limit", model.tail_local_limit) ||
			!read_number(surfaces, "tail_stall_end", model.tail_stall_end) ||
			!read_number(surfaces, "tail_CD0", model.tail_cd0) || !read_number(surfaces, "tail_k", model.tail_k) ||
			!read_number(surfaces, "tail_CD90", model.tail_cd90)) {
		return false;
	}
	const char *tail_names[2] = {"horizontal", "vertical"};
	for (std::size_t i = 0; i < 2; ++i) {
		godot::Dictionary tail_value;
		TailSurface &tail = model.tails[i];
		if (!read_dictionary(surfaces.get(tail_names[i], godot::Variant()), tail_value) ||
				!read_vec3(tail_value, "position", tail.position) ||
				!read_number(tail_value, "lift_slope", tail.lift_slope) ||
				!read_number(tail_value, "control_effectiveness", tail.control_effectiveness) ||
				!read_number(tail_value, "incidence", tail.incidence)) {
			return false;
		}
		tail.has_free_slope = tail_value.has("free_slope");
		if (tail.has_free_slope && !read_number(tail_value, "free_slope", tail.free_slope)) {
			return false;
		}
		if (!read_optional_number(tail_value, "downwash_per_cl", tail.downwash_per_cl) ||
				!read_optional_number(tail_value, "elevator_tau", tail.elevator_tau) ||
				!read_optional_number(tail_value, "free_incidence", tail.free_incidence)) {
			return false;
		}
	}
	godot::Array pieces;
	if (!read_array(slipstream.get("pieces", godot::Variant()), pieces) || pieces.is_empty() ||
			static_cast<std::size_t>(pieces.size()) > kMaxPieces) {
		return false;
	}
	model.piece_count = static_cast<std::size_t>(pieces.size());
	for (std::size_t i = 0; i < model.piece_count; ++i) {
		godot::Dictionary piece_value;
		if (!read_dictionary(pieces[static_cast<int64_t>(i)], piece_value)) {
			return false;
		}
		const godot::Variant surface_value = piece_value.get("surface", godot::Variant());
		if (surface_value.get_type() != godot::Variant::STRING) {
			return false;
		}
		const godot::String surface_name = static_cast<godot::String>(surface_value);
		Piece &piece = model.pieces[i];
		if (surface_name == godot::String("horizontal")) {
			piece.surface = 0;
		} else if (surface_name == godot::String("vertical")) {
			piece.surface = 1;
		} else {
			return false;
		}
		if (!read_number(piece_value, "area", piece.area) || !read_number(piece_value, "span", piece.span) ||
				!read_vec3(piece_value, "root", piece.root) || !read_vec3(piece_value, "span_dir", piece.span_dir) ||
				!read_profile(piece_value, piece)) {
			return false;
		}
	}
	return true;
}

} // namespace

namespace openrc::smooth_wake {

bool loads(const State13 &state, const Vec3 &velocity, const Pair &deflections, const Model &model,
		const Pair &thrust_torque, double rho, double fade, double downwash_cl,
		const std::vector<double> &transported_dv, Loads6 &output) {
	output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	if (!validate(state, velocity, deflections, model, thrust_torque, rho, fade, downwash_cl, transported_dv)) {
		return false;
	}
	if (fade == 0.0) {
		return true;
	}
	Wake wake;
	if (!compute_wake(velocity, thrust_torque, model, rho, wake)) {
		return false;
	}
	const double wing_cl = model.tails[0].has_free_slope ? downwash_cl : 0.0;
	if (!profile_centroid_loads(state, velocity, deflections, model, wake, rho, fade, wing_cl,
			transported_dv, output)) {
		output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
		return false;
	}
	Loads6 correction{};
	if (!swirl_correction(state, velocity, deflections, model, wake, fade, rho, wing_cl, correction)) {
		output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
		return false;
	}
	for (std::size_t component = 0; component < output.size(); ++component) {
		output[component] += correction[component];
	}
	if (!is_finite(output)) {
		output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
		return false;
	}
	return true;
}

} // namespace openrc::smooth_wake

class OpenRCSmoothWake final : public godot::RefCounted {
	GDCLASS(OpenRCSmoothWake, godot::RefCounted)

protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("loads", "state", "velocity", "deflections", "model",
				"thrust_torque", "rho", "fade", "downwash_cl", "transported_dv"), &OpenRCSmoothWake::loads);
	}

public:
	godot::PackedFloat64Array loads(const godot::PackedFloat64Array &state_value,
		const godot::PackedFloat64Array &velocity_value, const godot::Dictionary &deflections_value,
			const godot::Dictionary &model_value, const godot::PackedFloat64Array &thrust_torque_value,
			double rho, double fade, double downwash_cl, const godot::PackedFloat64Array &transported_dv_value) {
		if (state_value.size() != 13 || velocity_value.size() != 3 || thrust_torque_value.size() != 2) {
			return godot::PackedFloat64Array();
		}
		State13 state{};
		Vec3 velocity{};
		Pair thrust_torque{};
		for (int64_t i = 0; i < state_value.size(); ++i) {
			state[static_cast<std::size_t>(i)] = state_value[i];
		}
		for (int64_t i = 0; i < velocity_value.size(); ++i) {
			velocity[static_cast<std::size_t>(i)] = velocity_value[i];
		}
		for (int64_t i = 0; i < thrust_torque_value.size(); ++i) {
			thrust_torque[static_cast<std::size_t>(i)] = thrust_torque_value[i];
		}
		Pair deflections{};
		if (!read_number(deflections_value, "elevator", deflections[0]) ||
				!read_number(deflections_value, "rudder", deflections[1])) {
			return godot::PackedFloat64Array();
		}
		Model model;
		if (!read_model(model_value, model)) {
			return godot::PackedFloat64Array();
		}
		if (!transported_dv_value.is_empty() &&
				static_cast<std::size_t>(transported_dv_value.size()) != model.piece_count) {
			return godot::PackedFloat64Array();
		}
		std::vector<double> transported_dv;
		transported_dv.reserve(static_cast<std::size_t>(transported_dv_value.size()));
		for (int64_t i = 0; i < transported_dv_value.size(); ++i) {
			transported_dv.push_back(transported_dv_value[i]);
		}
		Loads6 result{};
		if (!openrc::smooth_wake::loads(state, velocity, deflections, model, thrust_torque, rho, fade,
				downwash_cl, transported_dv, result)) {
			return godot::PackedFloat64Array();
		}
		godot::PackedFloat64Array packed_result;
		packed_result.resize(6);
		for (std::size_t i = 0; i < result.size(); ++i) {
			packed_result[static_cast<int64_t>(i)] = result[i];
		}
		return packed_result;
	}
};

void initialize_openrc_smooth_wake(godot::ModuleInitializationLevel level) {
	if (level == godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
		godot::ClassDB::register_class<OpenRCSmoothWake>();
	}
}

void uninitialize_openrc_smooth_wake(godot::ModuleInitializationLevel) {}

extern "C" GDExtensionBool GDE_EXPORT openrc_smooth_wake_library_init(
		GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library,
		GDExtensionInitialization *initialization) {
	godot::GDExtensionBinding::InitObject init_object(get_proc_address, library, initialization);
	init_object.register_initializer(initialize_openrc_smooth_wake);
	init_object.register_terminator(uninitialize_openrc_smooth_wake);
	init_object.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_object.init();
}
