// NK-3 research GDExtension: prepared fixed-wing stage-evaluator components (terrain + lake, GP-02 wheels, aero).
// Not installed into app/; the oracle loads it at run time. Inputs are decoded once by prepare_ground/prepare_aero
// (D6: unknown keys or unsupported laws are refused so callers keep the GDScript reference); per-call methods take
// packed float64 arrays and never touch the source dictionaries. Simulation values are double scalars only.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <chrono>
#include <initializer_list>
#include <string>
#include <vector>

#include "nk_aero.hpp"
#include "nk_wheels.hpp"

namespace {

using godot::Array;
using godot::Dictionary;
using godot::PackedFloat64Array;
using godot::PackedStringArray;
using godot::String;
using godot::Variant;

constexpr int kStateSize = 13;
constexpr const char *kBackend = "openrc-native-kernel-nk3-research";
constexpr int kAbi = 1;
// Law identities the port mirrors; the oracle compares them with the loaded GDScript constants.
constexpr const char *kAeroLaw = "section-plane-source-weighted-wake-velocity-v2";
constexpr const char *kRollingLaw = "wheel-positive-terrain-excess-v2";

struct Decoder {
	std::string error;

	bool fail(const std::string &message) {
		if (error.empty()) {
			error = message;
		}
		return false;
	}

	bool number(const Dictionary &d, const char *key, nk::R &out, bool required, double fallback = 0.0) {
		if (!d.has(key)) {
			if (required) {
				return fail(std::string("missing ") + key);
			}
			out = fallback;
			return true;
		}
		const Variant value = d[key];
		if (value.get_type() == Variant::FLOAT) {
			out = static_cast<double>(value);
			return true;
		}
		if (value.get_type() == Variant::INT) {
			out = static_cast<double>(static_cast<int64_t>(value));
			return true;
		}
		return fail(std::string("non-numeric ") + key);
	}

	template <typename T>
	bool vec(const Dictionary &d, const char *key, std::vector<T> &out, bool required, int size = -1) {
		out.clear();
		if (!d.has(key)) {
			return required ? fail(std::string("missing ") + key) : true;
		}
		const Variant value = d[key];
		if (value.get_type() != Variant::PACKED_FLOAT64_ARRAY) {
			return fail(std::string("expected PackedFloat64Array ") + key);
		}
		const PackedFloat64Array packed = value;
		if (size >= 0 && packed.size() != size) {
			return fail(std::string("unexpected size ") + key);
		}
		out.assign(packed.ptr(), packed.ptr() + packed.size());
		return true;
	}

	bool dict(const Dictionary &d, const char *key, Dictionary &out, bool required) {
		if (!d.has(key)) {
			out = Dictionary();
			return required ? fail(std::string("missing ") + key) : true;
		}
		const Variant value = d[key];
		if (value.get_type() != Variant::DICTIONARY) {
			return fail(std::string("expected Dictionary ") + key);
		}
		out = value;
		return true;
	}

	// D6: a key the port does not know may carry a law the native code would silently ignore.
	bool only(const Dictionary &d, const char *where, std::initializer_list<const char *> allowed) {
		const Array keys = d.keys();
		for (int64_t i = 0; i < keys.size(); ++i) {
			const String key = keys[i];
			bool known = false;
			for (const char *name : allowed) {
				if (key == String(name)) {
					known = true;
					break;
				}
			}
			if (!known) {
				return fail(std::string("unsupported key ") + where + "." + key.utf8().get_data());
			}
		}
		return true;
	}
};

bool read_state(const PackedFloat64Array &s) { return s.size() == kStateSize; }

// Packed float64 input -> left-first scalars (bit copy).
template <int N>
void load(const PackedFloat64Array &in, nk::R (&out)[N]) {
	const double *src = in.ptr();
	for (int i = 0; i < N; ++i) {
		out[i] = src[i];
	}
}

PackedFloat64Array pack(const nk::R *values, int count) {
	PackedFloat64Array out;
	out.resize(count);
	double *dst = out.ptrw();
	for (int i = 0; i < count; ++i) {
		dst[i] = values[i].v;
	}
	return out;
}

PackedFloat64Array pack(const std::vector<nk::R> &values) {
	return pack(values.data(), static_cast<int>(values.size()));
}

bool decode_tail(Decoder &dec, const Dictionary &tail, nk::Tail &out, bool vertical) {
	out = nk::Tail();
	out.present = true;
	if (vertical) {
		if (!dec.only(tail, "surfaces.vertical", {"area", "position", "lift_slope", "control_effectiveness", "incidence"})) {
			return false;
		}
	} else if (!dec.only(tail, "surfaces.horizontal", {"area", "position", "lift_slope", "control_effectiveness",
			"incidence", "downwash_gradient", "free_slope", "elevator_tau", "downwash_per_cl", "free_incidence",
			"wing_cl0", "downwash_lag_length"})) {
		return false;
	}
	std::vector<nk::R> position;
	if (!dec.number(tail, "area", out.area, true) || !dec.vec(tail, "position", position, true, 3)) {
		return false;
	}
	for (int i = 0; i < 3; ++i) {
		out.position[i] = position[i];
	}
	out.free = !vertical && tail.has("free_slope");
	if (out.free) {
		return dec.number(tail, "free_slope", out.free_slope, true) &&
			dec.number(tail, "elevator_tau", out.elevator_tau, true) &&
			dec.number(tail, "downwash_per_cl", out.downwash_per_cl, true) &&
			dec.number(tail, "free_incidence", out.free_incidence, true);
	}
	return dec.number(tail, "lift_slope", out.lift_slope, true) &&
		dec.number(tail, "control_effectiveness", out.control_effectiveness, true) &&
		dec.number(tail, "incidence", out.incidence, true);
}

bool decode_aero(Decoder &dec, const Dictionary &model, nk::AeroModel &m) {
	m = nk::AeroModel();
	// Flaps.enabled(model): the flap law is not ported.
	Dictionary capabilities;
	if (!dec.dict(model, "capabilities", capabilities, false)) {
		return false;
	}
	if (capabilities.has("flaps") && String(capabilities["flaps"]) == String("simulated") && model.has("flaps") &&
			model["flaps"].get_type() == Variant::DICTIONARY && !Dictionary(model["flaps"]).is_empty()) {
		return dec.fail("flaps law not ported");
	}
	Dictionary reference, aero, envelope, surfaces, ground_effect;
	if (!dec.dict(model, "reference", reference, true) || !dec.dict(model, "aero", aero, true) ||
			!dec.dict(model, "envelope", envelope, true) || !dec.dict(model, "surfaces", surfaces, true)) {
		return false;
	}
	if (envelope.is_empty()) {
		return dec.fail("pure-oracle model (empty envelope) not ported");
	}
	if (!dec.only(reference, "reference", {"S", "b", "c", "geometric_chord", "arp_le", "planform", "chords"}) ||
			!dec.only(envelope, "envelope", {"a1", "a2", "n1", "n2", "b1", "b2", "CD90", "CL_max", "CL_min",
				"station_ys", "strip_slope", "strip_cl0", "induced_map", "strip_alpha_zero", "strip_row_sum",
				"station_chords", "ground_effect"}) ||
			!dec.only(surfaces, "surfaces", {"wing_aileron_effectiveness", "attached_limit", "tail_local_limit",
				"tail_stall_end", "tail_CD0", "tail_k", "tail_CD90", "body_cn_beta", "wing_body_cl_beta", "body_cy_beta",
				"body_crossflow_area", "wing_cm_ac", "station_incidence", "horizontal", "vertical"}) ||
			!dec.only(aero, "aero", {"CL0", "CLa", "CLadot", "CLq", "CLde", "CLda_each", "CD0", "CL_minD", "k_induced",
				"CDda_each", "CDdr", "CDde", "CYb", "CYp", "CYr", "CYdr", "Clb", "Clp", "Clr", "Clda_right", "Clda_left",
				"Cldr", "Cm0", "Cma", "Cmq", "Cmde", "Cmda_each", "Cnb", "Cnp", "Cnr", "Cnda_right", "Cnda_left",
				"Cndr"})) {
		return false;
	}
	std::vector<nk::R> arp, cg;
	if (!dec.number(reference, "S", m.S, true) || !dec.number(reference, "b", m.b, true) ||
			!dec.number(reference, "c", m.c, true) || !dec.vec(reference, "arp_le", arp, true, 3) ||
			!dec.vec(model, "cg_le", cg, true, 3)) {
		return false;
	}
	for (int i = 0; i < 3; ++i) {
		m.arp[i] = arp[i];
		m.cg[i] = cg[i];
	}
	struct Named {
		const char *key;
		nk::R *slot;
	};
	const Named coefficients[] = {{"CL0", &m.CL0}, {"CLa", &m.CLa}, {"CLq", &m.CLq}, {"CLde", &m.CLde},
		{"CLda_each", &m.CLda_each}, {"CD0", &m.CD0}, {"CL_minD", &m.CL_minD}, {"k_induced", &m.k_induced},
		{"CDda_each", &m.CDda_each}, {"CDdr", &m.CDdr}, {"CDde", &m.CDde}, {"CYb", &m.CYb}, {"CYp", &m.CYp},
		{"CYr", &m.CYr}, {"CYdr", &m.CYdr}, {"Clb", &m.Clb}, {"Clp", &m.Clp}, {"Clr", &m.Clr},
		{"Clda_right", &m.Clda_right}, {"Clda_left", &m.Clda_left}, {"Cldr", &m.Cldr}, {"Cm0", &m.Cm0},
		{"Cma", &m.Cma}, {"Cmq", &m.Cmq}, {"Cmde", &m.Cmde}, {"Cmda_each", &m.Cmda_each}, {"Cnb", &m.Cnb},
		{"Cnp", &m.Cnp}, {"Cnr", &m.Cnr}, {"Cnda_right", &m.Cnda_right}, {"Cnda_left", &m.Cnda_left},
		{"Cndr", &m.Cndr}};
	for (const Named &entry : coefficients) {
		if (!dec.number(aero, entry.key, *entry.slot, true)) {
			return false;
		}
	}
	const Named env_numbers[] = {{"a1", &m.a1}, {"a2", &m.a2}, {"n1", &m.n1}, {"n2", &m.n2}, {"b1", &m.b1},
		{"b2", &m.b2}, {"CD90", &m.CD90}};
	for (const Named &entry : env_numbers) {
		if (!dec.number(envelope, entry.key, *entry.slot, true)) {
			return false;
		}
	}
	if (!dec.vec(envelope, "station_ys", m.ys, true) || !dec.number(envelope, "strip_slope", m.strip_slope, false, m.CLa) ||
			!dec.vec(envelope, "strip_cl0", m.strip_cl0, false) || !dec.vec(envelope, "induced_map", m.induced_map, false) ||
			!dec.vec(envelope, "strip_row_sum", m.strip_row_sum, false) ||
			!dec.vec(envelope, "station_chords", m.station_chords, false)) {
		return false;
	}
	const int stations = static_cast<int>(m.ys.size());
	if (stations < 1 || stations > 16) {
		return dec.fail("station count outside 1..16");
	}
	m.has_strip_alpha_zero = envelope.has("strip_alpha_zero");
	if (!dec.number(envelope, "strip_alpha_zero", m.strip_alpha_zero, false, 0.0)) {
		return false;
	}
	if (static_cast<int>(m.induced_map.size()) == stations * stations && static_cast<int>(m.strip_cl0.size()) != stations) {
		return dec.fail("coupled induced map without one strip_cl0 per station");
	}
	if (!dec.dict(envelope, "ground_effect", ground_effect, false)) {
		return false;
	}
	m.ground_effect = envelope.has("ground_effect");
	if (m.ground_effect) {
		if (!dec.only(ground_effect, "envelope.ground_effect", {"induced_coefficient", "induced_exponent",
					"downwash_coefficient", "downwash_exponent"}) ||
				!dec.number(ground_effect, "induced_coefficient", m.ge_induced_coefficient, true) ||
				!dec.number(ground_effect, "induced_exponent", m.ge_induced_exponent, true) ||
				!dec.number(ground_effect, "downwash_coefficient", m.ge_downwash_coefficient, true) ||
				!dec.number(ground_effect, "downwash_exponent", m.ge_downwash_exponent, true)) {
			return false;
		}
		if (!m.has_strip_alpha_zero || static_cast<int>(m.strip_row_sum.size()) != stations || !envelope.has("strip_slope")) {
			return dec.fail("ground effect without strip_slope, strip_alpha_zero and strip_row_sum");
		}
	}
	const Named surface_numbers[] = {{"wing_aileron_effectiveness", &m.wing_aileron_effectiveness},
		{"attached_limit", &m.attached_limit}, {"tail_local_limit", &m.tail_local_limit},
		{"tail_stall_end", &m.tail_stall_end}, {"tail_CD0", &m.tail_CD0}, {"tail_k", &m.tail_k},
		{"tail_CD90", &m.tail_CD90}};
	for (const Named &entry : surface_numbers) {
		if (!dec.number(surfaces, entry.key, *entry.slot, true)) {
			return false;
		}
	}
	if (!dec.number(surfaces, "body_cn_beta", m.body_cn_beta, false, 0.0) ||
			!dec.number(surfaces, "wing_body_cl_beta", m.wing_body_cl_beta, false, 0.0) ||
			!dec.number(surfaces, "body_cy_beta", m.body_cy_beta, false, 0.0) ||
			!dec.number(surfaces, "body_crossflow_area", m.body_crossflow_area, false, 0.0) ||
			!dec.number(surfaces, "wing_cm_ac", m.wing_cm_ac, false, 0.0) ||
			!dec.vec(surfaces, "station_incidence", m.station_incidence, false)) {
		return false;
	}
	if (!m.station_incidence.empty() && static_cast<int>(m.station_incidence.size()) != stations) {
		return dec.fail("station_incidence size");
	}
	if (m.wing_cm_ac.v != 0.0 && static_cast<int>(m.station_chords.size()) != stations) {
		return dec.fail("wing_cm_ac without one station chord per station");
	}
	Dictionary vertical, horizontal;
	if (!dec.dict(surfaces, "vertical", vertical, true) || !decode_tail(dec, vertical, m.vertical, true)) {
		return false;
	}
	if (surfaces.has("horizontal")) {
		if (!dec.dict(surfaces, "horizontal", horizontal, true) || !decode_tail(dec, horizontal, m.horizontal, false)) {
			return false;
		}
	}
	if (m.ground_effect && !(m.horizontal.present && m.horizontal.free)) {
		return dec.fail("ground effect requires the E0a2 horizontal tail");
	}
	return true;
}

bool decode_gear(Decoder &dec, const Dictionary &gear, nk::PreparedGear &out) {
	out = nk::PreparedGear();
	if (gear.is_empty()) {
		out.empty = true;
		return true;
	}
	out.empty = false;
	if (!dec.only(gear, "landing_gear", {"contacts", "reach", "heave_omega", "static_sag", "rolling_resistance",
				"side_friction", "tan_peak_slip", "substeps", "breakaway_factor", "rolling_reference_radius",
				"rolling_reference_radius_provenance"}) ||
			!dec.number(gear, "reach", out.reach, true) ||
			!dec.number(gear, "side_friction", out.side_friction, false, 0.0) ||
			!dec.number(gear, "rolling_resistance", out.rolling_resistance, false, 0.0) ||
			!dec.number(gear, "tan_peak_slip", out.tan_peak_slip, false, 1.0) ||
			!dec.number(gear, "breakaway_factor", out.breakaway_factor, false, 1.0) ||
			!dec.number(gear, "rolling_reference_radius", out.rolling_reference_radius, false, nk::kReferenceRadius)) {
		return false;
	}
	if (!gear.has("contacts") || gear["contacts"].get_type() != Variant::ARRAY) {
		return dec.fail("missing contacts array");
	}
	const Array contacts = gear["contacts"];
	for (int64_t i = 0; i < contacts.size(); ++i) {
		if (contacts[i].get_type() != Variant::DICTIONARY) {
			return dec.fail("contact is not a Dictionary");
		}
		const Dictionary c = contacts[i];
		nk::WheelContact w;
		std::vector<nk::R> position;
		if (!dec.only(c, "landing_gear.contacts[]", {"name", "position", "stiffness", "damping", "max_compression",
					"max_steering", "damping_onset", "anchor_stiffness", "anchor_damping", "id", "wheel_radius",
					"wheel_inertia", "spin_relaxation", "brake_torque", "brake_availability", "wheel_provenance"}) ||
				!dec.vec(c, "position", position, true, 3) || !dec.number(c, "stiffness", w.stiffness, true) ||
				!dec.number(c, "damping", w.damping, true) ||
				!dec.number(c, "damping_onset", w.damping_onset, false, 0.0) ||
				!dec.number(c, "max_steering", w.max_steering, false, 0.0) ||
				!dec.number(c, "anchor_stiffness", w.anchor_stiffness, true) ||
				!dec.number(c, "anchor_damping", w.anchor_damping, true) ||
				!dec.number(c, "wheel_radius", w.wheel_radius, false, nk::kReferenceRadius) ||
				!dec.number(c, "wheel_inertia", w.wheel_inertia, false, 0.00003) ||
				!dec.number(c, "spin_relaxation", w.spin_relaxation, false, 0.03) ||
				!dec.number(c, "brake_torque", w.brake_torque, false, 0.0)) {
			return false;
		}
		for (int k = 0; k < 3; ++k) {
			w.position[k] = position[k];
		}
		out.contacts.push_back(w);
	}
	return true;
}

bool decode_lake(Decoder &dec, const Dictionary &lake, nk::LakeTerrain &out) {
	out = nk::LakeTerrain();
	if (lake.is_empty()) {
		return true;
	}
	out.present = true;
	if (!dec.vec(lake, "shoreline_ne_m", out.shoreline, true) || !dec.vec(lake, "bank_ne_m", out.bank, true) ||
			!dec.number(lake, "water_level_down_m", out.water_level_down, true)) {
		return false;
	}
	if (out.shoreline.size() < 6 || out.shoreline.size() % 2 != 0 || out.bank.size() < 6 || out.bank.size() % 2 != 0) {
		return dec.fail("lake polygons");
	}
	if (!lake.has("bed_profile") || lake["bed_profile"].get_type() != Variant::ARRAY) {
		return dec.fail("lake bed_profile");
	}
	const Array profile = lake["bed_profile"];
	if (profile.is_empty()) {
		return dec.fail("empty lake bed_profile");
	}
	for (int64_t i = 0; i < profile.size(); ++i) {
		if (profile[i].get_type() != Variant::DICTIONARY) {
			return dec.fail("lake bed_profile row");
		}
		const Dictionary row = profile[i];
		nk::R inset = 0.0, depth = 0.0;
		if (!dec.number(row, "inset_m", inset, true) || !dec.number(row, "depth_m", depth, true)) {
			return false;
		}
		out.profile_inset.push_back(inset);
		out.profile_depth.push_back(depth);
	}
	// lake_surface.gd _polygon_aabb of the bank.
	double north_min = nk::kInf, north_max = -nk::kInf, east_min = nk::kInf, east_max = -nk::kInf;
	for (size_t index = 0; index < out.bank.size(); index += 2) {
		north_min = nk::minf(north_min, out.bank[index]).v;
		north_max = nk::maxf(north_max, out.bank[index]).v;
		east_min = nk::minf(east_min, out.bank[index + 1]).v;
		east_max = nk::maxf(east_max, out.bank[index + 1]).v;
	}
	out.bank_aabb[0] = north_min;
	out.bank_aabb[1] = north_max;
	out.bank_aabb[2] = east_min;
	out.bank_aabb[3] = east_max;
	return true;
}

bool read_deflections(const PackedFloat64Array &d, nk::Deflections &out) {
	if (d.size() != 4 && d.size() != 5) {
		return false;
	}
	out.elevator = d[0];
	out.aileron_right = d[1];
	out.aileron_left = d[2];
	out.rudder = d[3];
	return true;
}

} // namespace

class OpenRCNativeKernel : public godot::RefCounted {
	GDCLASS(OpenRCNativeKernel, godot::RefCounted)

	nk::GroundContext ground_;
	bool ground_ready_ = false;
	nk::AeroModel aero_;
	bool aero_ready_ = false;
	nk::LakeTerrain no_lake_; // Environment.terrain (the ground-effect height) samples without the lake

protected:
	static void _bind_methods() {
		using godot::D_METHOD;
		godot::ClassDB::bind_method(D_METHOD("backend_identity"), &OpenRCNativeKernel::backend_identity);
		godot::ClassDB::bind_method(D_METHOD("prepare_ground", "gear", "surfaces", "lake", "lake_valid"),
			&OpenRCNativeKernel::prepare_ground);
		godot::ClassDB::bind_method(D_METHOD("terrain_sample", "north", "east", "with_lake"), &OpenRCNativeKernel::terrain_sample);
		godot::ClassDB::bind_method(D_METHOD("surface_table_is_valid", "surfaces"), &OpenRCNativeKernel::surface_table_is_valid);
		godot::ClassDB::bind_method(D_METHOD("wheels_evaluate", "s", "steer", "anchors", "speeds", "brake"),
			&OpenRCNativeKernel::wheels_evaluate);
		godot::ClassDB::bind_method(D_METHOD("wheels_compressions", "s"), &OpenRCNativeKernel::wheels_compressions);
		godot::ClassDB::bind_method(D_METHOD("prepare_aero", "model"), &OpenRCNativeKernel::prepare_aero);
		godot::ClassDB::bind_method(D_METHOD("aero_component", "which", "s", "wind", "rho", "d", "downwash_cl", "ground_up"),
			&OpenRCNativeKernel::aero_component);
		godot::ClassDB::bind_method(D_METHOD("aero_loads", "s", "wind", "rho", "d", "downwash_cl", "ground_up"),
			&OpenRCNativeKernel::aero_loads);
		godot::ClassDB::bind_method(D_METHOD("math_probe", "fn", "a", "b", "c"), &OpenRCNativeKernel::math_probe);
		godot::ClassDB::bind_method(D_METHOD("literal_table"), &OpenRCNativeKernel::literal_table);
		godot::ClassDB::bind_method(D_METHOD("bench_wheels", "s", "steer", "anchors", "speeds", "brake", "iterations"),
			&OpenRCNativeKernel::bench_wheels);
		godot::ClassDB::bind_method(D_METHOD("bench_aero", "s", "wind", "rho", "d", "downwash_cl", "ground_up", "iterations"),
			&OpenRCNativeKernel::bench_aero);
	}

public:
	Dictionary backend_identity() const {
		Dictionary out;
		out["backend"] = kBackend;
		out["abi"] = kAbi;
		out["aero_law"] = kAeroLaw;
		out["rolling_law"] = kRollingLaw;
		out["state_size"] = kStateSize;
		return out;
	}

	Dictionary prepare_ground(const Dictionary &gear, const PackedFloat64Array &surfaces, const Dictionary &lake,
			bool lake_valid) {
		Decoder dec;
		nk::GroundContext candidate;
		Dictionary out;
		candidate.surfaces.values.assign(surfaces.ptr(), surfaces.ptr() + surfaces.size());
		candidate.surfaces.valid = nk::surface_table_is_valid(candidate.surfaces.values);
		candidate.lake_valid = lake_valid;
		const bool ok = decode_gear(dec, gear, candidate.gear) && (!lake_valid || decode_lake(dec, lake, candidate.lake));
		ground_ready_ = ok;
		if (ok) {
			ground_ = candidate;
		}
		out["ok"] = ok;
		out["error"] = String(dec.error.c_str());
		out["surfaces_valid"] = candidate.surfaces.valid;
		out["contacts"] = static_cast<int64_t>(candidate.gear.contacts.size());
		return out;
	}

	bool surface_table_is_valid(const PackedFloat64Array &surfaces) const {
		std::vector<double> values(surfaces.ptr(), surfaces.ptr() + surfaces.size());
		return nk::surface_table_is_valid(values);
	}

	PackedFloat64Array terrain_sample(double north, double east, bool with_lake) const {
		if (!ground_ready_) {
			return PackedFloat64Array();
		}
		const nk::Vec3 out = nk::terrain_sample_validated(north, east, ground_.surfaces, with_lake ? ground_.lake : no_lake_);
		return pack(out.data(), 3);
	}

	Dictionary wheels_evaluate(const PackedFloat64Array &s, double steer, const PackedFloat64Array &anchors,
			const PackedFloat64Array &speeds, double brake) const {
		Dictionary out;
		if (!ground_ready_ || !read_state(s)) {
			out["ok"] = false;
			out["error"] = ground_ready_ ? "state size" : "ground not prepared";
			return out;
		}
		nk::R state[kStateSize];
		load(s, state);
		std::vector<nk::R> loads, rates;
		nk::wheels_evaluate(state, ground_, steer, anchors.ptr(), static_cast<int>(anchors.size()), speeds.ptr(),
			static_cast<int>(speeds.size()), brake, loads, rates);
		out["ok"] = true;
		out["loads"] = pack(loads);
		out["derivative"] = pack(rates);
		return out;
	}

	PackedFloat64Array wheels_compressions(const PackedFloat64Array &s) const {
		if (!ground_ready_ || !read_state(s)) {
			return PackedFloat64Array();
		}
		nk::R state[kStateSize];
		load(s, state);
		std::vector<nk::R> out;
		nk::wheels_compressions(state, ground_, out);
		return pack(out);
	}

	Dictionary prepare_aero(const Dictionary &model) {
		Decoder dec;
		nk::AeroModel candidate;
		const bool ok = decode_aero(dec, model, candidate);
		aero_ready_ = ok;
		if (ok) {
			aero_ = candidate;
		}
		Dictionary out;
		out["ok"] = ok;
		out["error"] = String(dec.error.c_str());
		out["law"] = kAeroLaw;
		return out;
	}

	// which: 0 loads, 1 air [u, v, w, V, alpha, beta, qbar], 2 ground-effect factors, 3 local_flow_weight,
	// 4 _global_loads, 5 _local_loads, 6 wing wake velocity (dimensional, with the stage's factors).
	PackedFloat64Array aero_component(int which, const PackedFloat64Array &s, const PackedFloat64Array &wind, double rho,
			const PackedFloat64Array &d, double downwash_cl, double ground_up) const {
		nk::Deflections deflections;
		if (!aero_ready_ || !read_state(s) || wind.size() != 3 || !read_deflections(d, deflections)) {
			return PackedFloat64Array();
		}
		nk::R state[kStateSize];
		nk::R wind_ned[3];
		load(s, state);
		load(wind, wind_ned);
		const nk::R *sp = state;
		const nk::Air air = nk::air_compute(sp, wind_ned, rho);
		std::vector<nk::R> ge;
		switch (which) {
			case 0: {
				const nk::Loads loads = nk::aero_loads(sp, air, deflections, aero_, rho, downwash_cl, ground_up);
				return pack(loads.data(), 6);
			}
			case 1: {
				const nk::R values[7] = {air.v[0], air.v[1], air.v[2], air.V, air.alpha, air.beta, air.qbar};
				return pack(values, 7);
			}
			case 2:
				nk::ge_factors(sp, aero_, ground_up, ge);
				return pack(ge);
			case 3: {
				nk::ge_factors(sp, aero_, ground_up, ge);
				const nk::R w = nk::local_flow_weight(sp, air, deflections, aero_, downwash_cl, ge);
				return pack(&w, 1);
			}
			case 4: {
				nk::ge_factors(sp, aero_, ground_up, ge);
				const nk::Loads loads = nk::global_loads(sp, air, deflections, aero_, rho, downwash_cl, ge);
				return pack(loads.data(), 6);
			}
			case 5: {
				nk::ge_factors(sp, aero_, ground_up, ge);
				const nk::Loads loads = nk::local_loads(sp, air, deflections, aero_, rho, downwash_cl, ge);
				return pack(loads.data(), 6);
			}
			case 6: {
				nk::ge_factors(sp, aero_, ground_up, ge);
				const nk::R w = nk::wing_lift_coefficient_with(sp, air, deflections, aero_, ge, true);
				return pack(&w, 1);
			}
			default:
				return PackedFloat64Array();
		}
	}

	PackedFloat64Array aero_loads(const PackedFloat64Array &s, const PackedFloat64Array &wind, double rho,
			const PackedFloat64Array &d, double downwash_cl, double ground_up) const {
		return aero_component(0, s, wind, rho, d, downwash_cl, ground_up);
	}

	// Element-wise shim probe for the oracle's semantic checks (NaN signs, signed zeros, clamps, wrapf seams).
	PackedFloat64Array math_probe(int fn, const PackedFloat64Array &a, const PackedFloat64Array &b,
			const PackedFloat64Array &c) const {
		const int64_t n = a.size();
		PackedFloat64Array out;
		out.resize(n);
		double *dst = out.ptrw();
		for (int64_t i = 0; i < n; ++i) {
			const nk::R x = a[i];
			const nk::R y = i < b.size() ? b[i] : 0.0;
			const nk::R z = i < c.size() ? c[i] : 0.0;
			nk::R r = nk::kNan;
			switch (fn) {
				case 0: r = nk::wrapf(x, y, z); break;
				case 1: r = nk::clampf(x, y, z); break;
				case 2: r = nk::maxf(x, y); break;
				case 3: r = nk::minf(x, y); break;
				case 4: r = nk::absf(x); break;
				case 5: r = nk::lerpf(x, y, z); break;
				case 6: r = nk::pow_(x, y); break;
				case 7: r = nk::atan2_(x, y); break;
				case 8: r = nk::sin_(x); break;
				case 9: r = nk::cos_(x); break;
				case 10: r = nk::sqrt_(x); break;
				case 11: r = nk::aero_smoothstep(x); break;
				case 12: r = nk::lake_smoothstep(x); break;
				case 13: r = nk::pow_(x, 2.0); break; // literal exponent through the shim (folding hazard)
				default: break;
			}
			dst[i] = r.v;
		}
		return out;
	}

	// Float literals as spelled in the mirrored GDScript, with the value this binary compiled for each.
	// The oracle compiles the same spellings in GDScript and compares bits (engine literal parser identity).
	Dictionary literal_table() const {
		Dictionary out;
		const struct {
			const char *spelling;
			double value;
		} table[] = {
			{"6.2831853071795864769", nk::kTau}, {"0.45", nk::kWaves[0][0]}, {"1.2", nk::kWaves[0][1]},
			{"0.8", nk::kWaves[0][2]}, {"0.6", nk::kWaves[0][3]}, {"0.17", nk::kWaves[0][4]},
			{"0.35", nk::kWaves[1][0]}, {"0.73", nk::kWaves[1][1]}, {"-0.35", nk::kWaves[1][2]},
			{"0.9367496998", nk::kWaves[1][3]}, {"2.11", nk::kWaves[1][4]}, {"0.20", nk::kWaves[2][0]},
			{"0.41", nk::kWaves[2][1]}, {"-0.8", nk::kWaves[2][3]}, {"4.73", nk::kWaves[2][4]},
			{"2.5", nk::kRollingRunway}, {"7.5", nk::kRollingRough}, {"0.001", nk::kReliefRunway},
			{"0.004", 0.004}, {"0.007", nk::kReliefRough}, {"0.025", nk::kLakeSampleEpsilon},
			{"0.00000001", nk::kLakeEdgeEpsilon}, {"0.0381", nk::kReferenceRadius}, {"0.02", nk::kStickSpeed},
			{"0.00003", 0.00003}, {"0.03", 0.03}, {"1e-6", 1e-6}, {"0.01", 0.01}, {"0.1", 0.1}, {"0.25", 0.25},
			{"1e-5", 1e-5}, {"PI", nk::kPi},
		};
		for (const auto &entry : table) {
			out[entry.spelling] = entry.value;
		}
		return out;
	}

	double bench_wheels(const PackedFloat64Array &s, double steer, const PackedFloat64Array &anchors,
			const PackedFloat64Array &speeds, double brake, int iterations) const {
		if (!ground_ready_ || !read_state(s) || iterations < 1) {
			return nk::kNan;
		}
		std::vector<nk::R> loads, rates;
		double sink = 0.0;
		const auto start = std::chrono::steady_clock::now();
		for (int i = 0; i < iterations; ++i) {
			nk::R state[kStateSize];
			load(s, state);
			nk::wheels_evaluate(state, ground_, steer, anchors.ptr(), static_cast<int>(anchors.size()), speeds.ptr(),
				static_cast<int>(speeds.size()), brake, loads, rates);
			sink += loads.empty() ? 0.0 : loads[0].v;
		}
		const auto end = std::chrono::steady_clock::now();
		volatile double keep = sink;
		(void)keep;
		return std::chrono::duration<double, std::nano>(end - start).count() / iterations;
	}

	double bench_aero(const PackedFloat64Array &s, const PackedFloat64Array &wind, double rho, const PackedFloat64Array &d,
			double downwash_cl, double ground_up, int iterations) const {
		nk::Deflections deflections;
		if (!aero_ready_ || !read_state(s) || wind.size() != 3 || !read_deflections(d, deflections) || iterations < 1) {
			return nk::kNan;
		}
		double sink = 0.0;
		const auto start = std::chrono::steady_clock::now();
		for (int i = 0; i < iterations; ++i) {
			nk::R state[kStateSize];
			nk::R wind_ned[3];
			load(s, state);
			load(wind, wind_ned);
			const nk::Air air = nk::air_compute(state, wind_ned, rho);
			const nk::Loads loads = nk::aero_loads(state, air, deflections, aero_, rho, downwash_cl, ground_up);
			sink += loads[0].v;
		}
		const auto end = std::chrono::steady_clock::now();
		volatile double keep = sink;
		(void)keep;
		return std::chrono::duration<double, std::nano>(end - start).count() / iterations;
	}
};

void initialize_openrc_native_kernel(godot::ModuleInitializationLevel level) {
	if (level == godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
		godot::ClassDB::register_class<OpenRCNativeKernel>();
	}
}

void uninitialize_openrc_native_kernel(godot::ModuleInitializationLevel) {}

extern "C" GDExtensionBool GDE_EXPORT openrc_native_kernel_library_init(
		GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library,
		GDExtensionInitialization *initialization) {
	godot::GDExtensionBinding::InitObject init_object(get_proc_address, library, initialization);
	init_object.register_initializer(initialize_openrc_native_kernel);
	init_object.register_terminator(uninitialize_openrc_native_kernel);
	init_object.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_object.init();
}
