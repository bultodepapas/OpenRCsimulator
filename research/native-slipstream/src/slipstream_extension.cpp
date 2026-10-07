#include "slipstream_kernel.hpp"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cmath>
#include <cstddef>

namespace {

using namespace openrc::slipstream;

constexpr double kPi = 3.141592653589793238462643383279502884;
constexpr double kSwirlSpeedFloor = 1.0;
constexpr double kRadiusMin = 0.7071;
constexpr double kRadiusMax = 1.5;
constexpr double kEpsilon = 1.0e-5; // Godot 4.7 CMP_EPSILON.

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
	// Godot's CLAMP comparisons preserve the input when it is already in range.
	return value < low ? low : (value > high ? high : value);
}

double maxf(double first, double second) {
	return first > second ? first : second;
}

double minf(double first, double second) {
	return first < second ? first : second;
}

double wrapf(double value, double low, double high) {
	const double range = high - low;
	if (std::abs(range) < kEpsilon) {
		return low;
	}
	const double result = value - (range * std::floor((value - low) / range));
	double tolerance = kEpsilon * std::abs(result);
	if (tolerance < kEpsilon) {
		tolerance = kEpsilon;
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
	double radius = 0.0;
	double swirl = 0.0;
	double core = 0.0;
};

struct Immersion {
	double area = 0.0;
	Vec3 shift{};
	Vec3 swirl{};
};

bool compute_wake(const Vec3 &velocity, const Pair &thrust_torque, const Model &model,
		double rho, Wake &wake) {
	const double propeller_radius = 0.5 * model.propeller_diameter;
	const double disc_area = kPi * propeller_radius * propeller_radius;
	wake.u = maxf(dot(velocity, model.shaft_axis), 0.0);
	const double vs_squared = wake.u * wake.u + 2.0 * thrust_torque[0] / (rho * disc_area);
	const double vs = std::sqrt(maxf(vs_squared, 0.0));
	wake.w = 0.5 * (vs - wake.u);
	const double radius_ratio = clampf((wake.u + wake.w) / maxf(wake.u + 2.0 * wake.w, 1.0e-6),
			kRadiusMin * kRadiusMin, kRadiusMax * kRadiusMax);
	const double mass_flow_ratio = wake.w > 0.0 ? wake.u / maxf(wake.u + wake.w, 1.0e-6) : 1.0;
	const double wash_mix = clampf(mass_flow_ratio / 0.75, 0.0, 1.0);
	const double wash = model.wash_factor[0] + (model.wash_factor[1] - model.wash_factor[0]) * wash_mix;
	wake.vs = wake.u + 2.0 * wake.w;
	wake.dv = wash * wake.w;
	wake.radius = propeller_radius * std::sqrt(radius_ratio);
	wake.swirl = model.swirl_factor * 0.5 * wash * thrust_torque[1] /
			(rho * disc_area * maxf(wake.u + wake.w, kSwirlSpeedFloor));
	wake.core = 0.3 * propeller_radius;
	return is_finite(wake.u) && is_finite(wake.w) && is_finite(wake.vs) && is_finite(wake.dv) &&
			is_finite(wake.radius) && is_finite(wake.swirl) && is_finite(wake.core);
}

bool compute_immersion(const Piece &piece, const Wake &wake, const Model &model,
		const Vec3 &velocity, double speed, Immersion &immersion) {
	const Vec3 &axis = model.shaft_axis;
	const double axis_le_0 = -axis[0];
	const double axis_le_1 = axis[1];
	const double axis_le_2 = -axis[2];
	const double distance = piece.root[0] - model.hub[0];
	if (std::abs(axis_le_0) <= 1.0e-12) {
		return false;
	}
	const double shaft_scale = distance / axis_le_0;
	double centre_0 = model.hub[0] + axis_le_0 * shaft_scale;
	double centre_1 = model.hub[1] + axis_le_1 * shaft_scale;
	double centre_2 = model.hub[2] + axis_le_2 * shaft_scale;
	if (speed > 1.0e-6 && wake.vs > 1.0e-6) {
		const double lean = minf(speed / (wake.u + wake.w), 1.0) * distance / speed;
		centre_1 -= velocity[1] * lean;
		centre_2 += velocity[2] * lean * model.vertical_drift;
	}
	const Vec3 &span_dir = piece.span_dir;
	const double rel_0 = piece.root[0] - centre_0;
	const double rel_1 = piece.root[1] - centre_1;
	const double rel_2 = piece.root[2] - centre_2;
	const double along = rel_0 * span_dir[0] + rel_1 * span_dir[1] + rel_2 * span_dir[2];
	const double perp_0 = rel_0 - span_dir[0] * along;
	const double perp_1 = rel_1 - span_dir[1] * along;
	const double perp_2 = rel_2 - span_dir[2] * along;
	const double distance_squared = perp_0 * perp_0 + perp_1 * perp_1 + perp_2 * perp_2;
	const double radius_squared = wake.radius * wake.radius;
	if (!is_finite(distance_squared) || !is_finite(radius_squared)) {
		return false;
	}
	if (distance_squared >= radius_squared) {
		return true;
	}
	const double half_length = std::sqrt(radius_squared - distance_squared);
	const double a = clampf(-along - half_length, 0.0, piece.span);
	const double b = clampf(-along + half_length, 0.0, piece.span);
	if (b <= a) {
		return true;
	}
	const double chord_root = piece.chords[0];
	const double chord_slope = (piece.chords[1] - chord_root) / piece.span;
	const double area_b = chord_root * b + 0.5 * chord_slope * b * b;
	const double area_a = chord_root * a + 0.5 * chord_slope * a * a;
	const double immersed_area = area_b - area_a;
	const double full_area = chord_root * piece.span + 0.5 * chord_slope * piece.span * piece.span;
	if (!is_finite(immersed_area) || !is_finite(full_area) || full_area <= 0.0) {
		return false;
	}
	if (immersed_area <= 0.0) {
		return true;
	}
	const double moment_b = 0.5 * chord_root * b * b + chord_slope * b * b * b / 3.0;
	const double moment_a = 0.5 * chord_root * a * a + chord_slope * a * a * a / 3.0;
	const double eta = (moment_b - moment_a) / immersed_area;
	const double point_0 = piece.root[0] + span_dir[0] * eta;
	const double point_1 = piece.root[1] + span_dir[1] * eta;
	const double point_2 = piece.root[2] + span_dir[2] * eta;
	const Vec3 &tail_position = model.tails[piece.surface].position;
	immersion.area = piece.area * immersed_area / full_area;
	immersion.shift = Vec3{0.0, point_1 - tail_position[1], -(point_2 - tail_position[2])};
	const double radial_0 = point_0 - centre_0;
	const double radial_1 = point_1 - centre_1;
	const double radial_2 = point_2 - centre_2;
	const double radial_body_0 = -radial_0;
	const double radial_body_1 = radial_1;
	const double radial_body_2 = -radial_2;
	const double axial_projection = radial_body_0 * axis[0] + radial_body_1 * axis[1] + radial_body_2 * axis[2];
	Vec3 radial_perpendicular{
		radial_body_0 - axis[0] * axial_projection,
		radial_body_1 - axis[1] * axial_projection,
		radial_body_2 - axis[2] * axial_projection,
	};
	const double radial_length = std::sqrt(radial_perpendicular[0] * radial_perpendicular[0] +
			radial_perpendicular[1] * radial_perpendicular[1] + radial_perpendicular[2] * radial_perpendicular[2]);
	const double swirl_radius = maxf(radial_length, wake.core);
	const double swirl_scale = wake.swirl / (swirl_radius * swirl_radius);
	const Vec3 swirl_cross = cross(axis, radial_perpendicular);
	immersion.swirl = Vec3{
		swirl_cross[0] * swirl_scale,
		swirl_cross[1] * swirl_scale,
		swirl_cross[2] * swirl_scale,
	};
	return is_finite(immersion.area) && is_finite(immersion.shift) && is_finite(immersion.swirl);
}

double tail_curve(double alpha, double slope, const Model &model) {
	const double blend = smoothstep((std::abs(alpha) - model.tail_local_limit) /
			(model.tail_stall_end - model.tail_local_limit));
	return (1.0 - blend) * slope * alpha + blend * 0.5 * model.tail_cd90 * std::sin(2.0 * alpha);
}

Loads6 surface_with_flow(const Vec3 &flow, const Vec3 &arm, double area, double cl, double cd,
		bool vertical, double rho) {
	const double speed = std::sqrt(dot(flow, flow));
	if (speed < 1.0e-10) {
		return Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	}
	const std::size_t side = vertical ? 1 : 2;
	const double plane_speed = std::sqrt(flow[0] * flow[0] + flow[side] * flow[side]);
	const double force_scale = -0.5 * rho * speed * area * cd;
	double fx = flow[0] * force_scale;
	double fy = flow[1] * force_scale;
	double fz = flow[2] * force_scale;
	if (plane_speed > 1.0e-10) {
		const double lift = 0.5 * rho * plane_speed * plane_speed * area * cl;
		fx += lift * flow[side] / plane_speed;
		if (vertical) {
			fy -= lift * flow[0] / plane_speed;
		} else {
			fz -= lift * flow[0] / plane_speed;
		}
	}
	const double mx = arm[1] * fz - arm[2] * fy;
	const double my = arm[2] * fx - arm[0] * fz;
	const double mz = arm[0] * fy - arm[1] * fx;
	return Loads6{fx, fy, fz, mx, my, mz};
}

Loads6 tail_from_flow(const Vec3 &flow, const Vec3 &arm, double control, const TailSurface &tail,
		const Model &model, double area, bool vertical, double rho) {
	const std::size_t side = vertical ? 1 : 2;
	const double effective = wrapf(std::atan2(flow[side], flow[0]) + tail.control_effectiveness * control +
			tail.incidence, -kPi, kPi);
	const double cl = tail_curve(effective, tail.lift_slope, model);
	const double sin_alpha = std::sin(effective);
	const double cd = model.tail_cd0 + model.tail_k * cl * cl +
			model.tail_cd90 * std::pow(sin_alpha, 2.0);
	return surface_with_flow(flow, arm, area, cl, cd, vertical, rho);
}

bool validate(const State13 &state, const Vec3 &velocity, const Pair &deflections, const Model &model,
		const Pair &thrust_torque, double rho) {
	for (double value : state) {
		if (!is_finite(value)) {
			return false;
		}
	}
	if (!is_finite(velocity) || !is_finite(deflections) || !is_finite(thrust_torque) || !is_finite(model.shaft_axis) ||
			!is_finite(model.hub) || !is_finite(model.wash_factor) || !is_finite(model.cg_le) || !is_finite(rho) || rho <= 0.0 ||
			!is_finite(model.propeller_diameter) || model.propeller_diameter <= 0.0 || std::abs(model.shaft_axis[0]) <= 1.0e-12 ||
			!is_finite(model.swirl_factor) || !is_finite(model.vertical_drift) || !is_finite(model.tail_local_limit) ||
			!is_finite(model.tail_stall_end) || model.tail_stall_end <= model.tail_local_limit || !is_finite(model.tail_cd0) ||
			!is_finite(model.tail_k) || !is_finite(model.tail_cd90) || model.piece_count > kMaxPieces) {
		return false;
	}
	for (const TailSurface &tail : model.tails) {
		if (!is_finite(tail.position) || !is_finite(tail.lift_slope) || !is_finite(tail.control_effectiveness) || !is_finite(tail.incidence)) {
			return false;
		}
	}
	for (std::size_t i = 0; i < model.piece_count; ++i) {
		const Piece &piece = model.pieces[i];
		if (piece.surface > 1 || !is_finite(piece.area) || piece.area <= 0.0 || !is_finite(piece.root) ||
				!is_finite(piece.span_dir) || !is_finite(piece.span) || piece.span <= 0.0 || !is_finite(piece.chords) ||
				piece.chords[0] <= 0.0 || piece.chords[1] <= 0.0 || !is_finite(piece.chords[1] - piece.chords[0])) {
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

bool read_dictionary(const godot::Variant &value, godot::Dictionary &out) {
	if (value.get_type() != godot::Variant::DICTIONARY) {
		return false;
	}
	out = static_cast<godot::Dictionary>(value);
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
		if (!read_dictionary(surfaces.get(tail_names[i], godot::Variant()), tail_value) ||
				!read_vec3(tail_value, "position", model.tails[i].position) ||
				!read_number(tail_value, "lift_slope", model.tails[i].lift_slope) ||
				!read_number(tail_value, "control_effectiveness", model.tails[i].control_effectiveness) ||
				!read_number(tail_value, "incidence", model.tails[i].incidence)) {
			return false;
		}
	}
	const godot::Variant pieces_value = slipstream.get("pieces", godot::Variant());
	if (pieces_value.get_type() != godot::Variant::ARRAY) {
		return false;
	}
	const godot::Array pieces = static_cast<godot::Array>(pieces_value);
	if (pieces.size() <= 0 || static_cast<std::size_t>(pieces.size()) > kMaxPieces) {
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
		if (surface_name == godot::String("horizontal")) {
			model.pieces[i].surface = 0;
		} else if (surface_name == godot::String("vertical")) {
			model.pieces[i].surface = 1;
		} else {
			return false;
		}
		if (!read_number(piece_value, "area", model.pieces[i].area) ||
				!read_vec3(piece_value, "root", model.pieces[i].root) ||
				!read_vec3(piece_value, "span_dir", model.pieces[i].span_dir) ||
				!read_number(piece_value, "span", model.pieces[i].span) ||
				!read_pair(piece_value, "chords", model.pieces[i].chords)) {
			return false;
		}
	}
	return true;
}

} // namespace

namespace openrc::slipstream {

bool tail_loads(const State13 &state, const Vec3 &velocity, const Pair &deflections,
		const Model &model, const Pair &thrust_torque, double rho, Loads6 &output) {
	output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	if (!validate(state, velocity, deflections, model, thrust_torque, rho)) {
		return false;
	}
	Wake wake;
	if (!compute_wake(velocity, thrust_torque, model, rho, wake)) {
		return false;
	}
	const Vec3 rates{state[10], state[11], state[12]};
	const double speed = std::sqrt(dot(velocity, velocity));
	if (!is_finite(speed)) {
		return false;
	}
	const Vec3 wash_velocity{
		model.shaft_axis[0] * wake.dv,
		model.shaft_axis[1] * wake.dv,
		model.shaft_axis[2] * wake.dv,
	};
	for (std::size_t i = 0; i < model.piece_count; ++i) {
		Immersion immersion;
		if (!compute_immersion(model.pieces[i], wake, model, velocity, speed, immersion)) {
			return false;
		}
		if (immersion.area <= 0.0) {
			continue;
		}
		const Vec3 extra{
			wash_velocity[0] - immersion.swirl[0],
			wash_velocity[1] - immersion.swirl[1],
			wash_velocity[2] - immersion.swirl[2],
		};
		const Piece &piece = model.pieces[i];
		const TailSurface &tail = model.tails[piece.surface];
		const Vec3 arm{
			-(tail.position[0] - model.cg_le[0]) + immersion.shift[0],
			tail.position[1] - model.cg_le[1] + immersion.shift[1],
			-(tail.position[2] - model.cg_le[2]) + immersion.shift[2],
		};
		const Vec3 rate_arm = cross(rates, arm);
		const Vec3 free_velocity{
			velocity[0] + 0.0,
			velocity[1] + 0.0,
			velocity[2] + 0.0,
		};
		const Vec3 free_flow{
			free_velocity[0] + rate_arm[0],
			free_velocity[1] + rate_arm[1],
			free_velocity[2] + rate_arm[2],
		};
		const Vec3 washed_velocity{
			velocity[0] + extra[0],
			velocity[1] + extra[1],
			velocity[2] + extra[2],
		};
		const Vec3 washed_flow{
			washed_velocity[0] + rate_arm[0],
			washed_velocity[1] + rate_arm[1],
			washed_velocity[2] + rate_arm[2],
		};
		const bool vertical = piece.surface == 1;
		const double control = vertical ? -deflections[1] : deflections[0];
		const Loads6 free_load = tail_from_flow(free_flow, arm, control, tail, model, immersion.area, vertical, rho);
		Loads6 washed_load = tail_from_flow(washed_flow, arm, control, tail, model, immersion.area, vertical, rho);
		for (std::size_t k = 0; k < output.size(); ++k) {
			washed_load[k] -= free_load[k];
			output[k] += washed_load[k];
		}
		if (!is_finite(output)) {
			output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
			return false;
		}
	}
	return is_finite(output);
}

} // namespace openrc::slipstream

class OpenRCNativeSlipstream final : public godot::RefCounted {
	GDCLASS(OpenRCNativeSlipstream, godot::RefCounted)

protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("tail_loads", "state", "velocity", "deflections", "model",
				"thrust_torque", "rho"), &OpenRCNativeSlipstream::tail_loads);
	}

public:
	godot::PackedFloat64Array tail_loads(const godot::PackedFloat64Array &state_value,
			const godot::PackedFloat64Array &velocity_value, const godot::Dictionary &deflections_value,
			const godot::Dictionary &model_value, const godot::PackedFloat64Array &thrust_torque_value, double rho) {
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
		Loads6 loads{};
		if (!openrc::slipstream::tail_loads(state, velocity, deflections, model, thrust_torque, rho, loads)) {
			return godot::PackedFloat64Array();
		}
		godot::PackedFloat64Array result;
		result.resize(6);
		for (std::size_t i = 0; i < loads.size(); ++i) {
			result[static_cast<int64_t>(i)] = loads[i];
		}
		return result;
	}
};

void initialize_openrc_slipstream(godot::ModuleInitializationLevel level) {
	if (level == godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
		godot::ClassDB::register_class<OpenRCNativeSlipstream>();
	}
}

void uninitialize_openrc_slipstream(godot::ModuleInitializationLevel) {}

extern "C" GDExtensionBool GDE_EXPORT openrc_slipstream_library_init(
		GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library,
		GDExtensionInitialization *initialization) {
	godot::GDExtensionBinding::InitObject init_object(get_proc_address, library, initialization);
	init_object.register_initializer(initialize_openrc_slipstream);
	init_object.register_terminator(uninitialize_openrc_slipstream);
	init_object.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_object.init();
}
