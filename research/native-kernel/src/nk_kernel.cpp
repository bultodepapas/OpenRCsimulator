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
#include <godot_cpp/variant/string_name.hpp>

#include <chrono>
#include <initializer_list>
#include <string>
#include <vector>

#include "nk_aero.hpp"
#include "nk_stage.hpp"
#include "nk_wheels.hpp"
#include "nk_weather_binding.hpp"
#include "nk_electric_binding.hpp"
#include "nk_wake_binding.hpp"
#include "nk_wake_spatial_binding.hpp"
#include "nk_glow_binding.hpp"
#include "nk_helicopter_binding.hpp"
#include "nk_liquid_binding.hpp"
#include "nk_gear_binding.hpp"
#include "nk_weather_guard.hpp"

namespace {

using godot::Array;
using godot::Dictionary;
using godot::PackedFloat64Array;
using godot::PackedStringArray;
using godot::String;
using godot::Variant;

constexpr int kStateSize = 13;
constexpr int kMaxContinuousSize = 64;
constexpr const char *kBackend = "native";
// Bump on any change to the stage contract (inputs, layout, outputs); the app loader and receipt must agree.
constexpr const char *kBackendVersion = "openrc-native-kernel-stage-v1";
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
	Dictionary capabilities;
	if (!dec.dict(model, "capabilities", capabilities, false)) {
		return false;
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
				"station_chords", "ground_effect", "wing_polar"}) ||
			!dec.only(surfaces, "surfaces", {"wing_aileron_effectiveness", "attached_limit", "tail_local_limit",
				"tail_stall_end", "tail_CD0", "tail_k", "tail_CD90", "body_cn_beta", "wing_body_cl_beta", "body_cy_beta",
				"body_crossflow_area", "wing_cm_ac", "station_incidence", "horizontal", "vertical", "tailless"}) ||
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
	// Prepared tables are copied verbatim. Recomputing tangents or geometry here would change rounding.
	if (envelope.has("wing_polar")) {
		Dictionary polar;
		if (!dec.dict(envelope, "wing_polar", polar, true) ||
				!dec.only(polar, "wing_polar", {"positive", "negative", "cd0", "cd90", "slope", "offset",
					"spanwise_progression", "strip_factor"}) ||
				!dec.number(polar, "cd0", m.polar.cd0, true) || !dec.number(polar, "cd90", m.polar.cd90, true) ||
				!dec.number(polar, "slope", m.polar.slope, true) || !dec.number(polar, "offset", m.polar.offset, true) ||
				!dec.vec(polar, "strip_factor", m.polar.strip_factor, false)) {
			return false;
		}
		if (!m.polar.strip_factor.empty() && static_cast<int>(m.polar.strip_factor.size()) != stations) {
			return dec.fail("wing polar strip_factor size");
		}
		for (const char *side : {"positive", "negative"}) {
			Dictionary branch;
			nk::WingPolarBranch &b = std::string(side) == "positive" ? m.polar.positive : m.polar.negative;
			if (!dec.dict(polar, side, branch, true) || !dec.only(branch, "wing_polar branch", {"angles", "values", "tangents"}) ||
					!dec.vec(branch, "angles", b.angles, true) || !dec.vec(branch, "values", b.values, true) ||
					!dec.vec(branch, "tangents", b.tangents, true)) {
				return false;
			}
			if (b.angles.size() < 4 || b.angles.size() > 64 || b.values.size() != b.angles.size() * 3 ||
					b.tangents.size() != b.values.size()) {
				return dec.fail("wing polar branch dimensions");
			}
			for (size_t i = 0; i < b.angles.size(); ++i) {
				if (!nk::is_finite(b.angles[i]) || (i > 0 && b.angles[i] <= b.angles[i - 1])) {
					return dec.fail("wing polar angles must be finite and increasing");
				}
			}
			for (size_t i = 0; i < b.values.size(); ++i) {
				if (!nk::is_finite(b.values[i]) || !nk::is_finite(b.tangents[i])) {
					return dec.fail("nonfinite wing polar table");
				}
			}
		}
		m.polar.enabled = true;
	}
	if (capabilities.has("flaps") && String(capabilities["flaps"]) == String("simulated")) {
		Dictionary flap;
		if (!dec.dict(model, "flaps", flap, true) || !dec.only(flap, "flaps", {"max_angle_deg", "takeoff_angle_deg",
				"takeoff_fraction", "inner_span_m", "outer_span_m", "hinge_fraction", "chord_fraction", "lift_effectiveness",
				"thin_airfoil_moment_per_cl", "extension_time", "retraction_time", "max_speed_mps",
				"elevator_mix_per_flap_fraction", "effective_angle_limit_deg", "profile_drag_coefficient",
				"aerodynamic_gain", "station_coverage", "stall_shift_fraction", "lift_reference_offset_m"}) ||
				!dec.vec(flap, "station_coverage", m.flaps.station_coverage, true, stations)) {
			return false;
		}
		const Named flap_numbers[] = {{"hinge_fraction", &m.flaps.hinge_fraction}, {"chord_fraction", &m.flaps.chord_fraction},
			{"lift_effectiveness", &m.flaps.lift_effectiveness}, {"thin_airfoil_moment_per_cl", &m.flaps.thin_airfoil_moment_per_cl},
			{"effective_angle_limit_deg", &m.flaps.effective_angle_limit_deg}, {"profile_drag_coefficient", &m.flaps.profile_drag_coefficient}};
		for (const Named &entry : flap_numbers) {
			if (!dec.number(flap, entry.key, *entry.slot, true) || !nk::is_finite(*entry.slot)) {
				return dec.fail("invalid flap scalar");
			}
		}
		if (!dec.number(flap, "aerodynamic_gain", m.flaps.aerodynamic_gain, false, 1.0) ||
				!dec.number(flap, "stall_shift_fraction", m.flaps.stall_shift_fraction, false) ||
				!dec.number(flap, "lift_reference_offset_m", m.flaps.lift_reference_offset_m, false)) {
			return false;
		}
		m.flaps.has_stall_shift_fraction = flap.has("stall_shift_fraction");
		m.flaps.has_lift_reference_offset_m = flap.has("lift_reference_offset_m");
		m.flaps.enabled = true;
	}
	if (surfaces.has("tailless")) {
		Dictionary tailless;
		if (!dec.dict(surfaces, "tailless", tailless, true) || !dec.only(tailless, "surfaces.tailless",
				{"station_x_authored", "elevon_coverage", "elevon_chord_fraction", "station_x", "station_shift",
					"tau", "thin_airfoil_tau", "moment_per_rad"}) ||
				!dec.vec(tailless, "station_x", m.tailless.station_x, true, stations) ||
				!dec.vec(tailless, "elevon_coverage", m.tailless.elevon_coverage, true, stations) ||
				!dec.number(tailless, "tau", m.tailless.tau, true) ||
				!dec.number(tailless, "moment_per_rad", m.tailless.moment_per_rad, true)) {
			return false;
		}
		if (surfaces.has("horizontal") || static_cast<int>(m.station_chords.size()) != stations) {
			return dec.fail("tailless model needs station chords and no horizontal tail");
		}
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

// Preparation-only projection. Moving geometry remains validated by GearBinding.
Dictionary fixed_gear_source(const Dictionary &gear) {
	Dictionary base = gear.duplicate(true);
	base.erase("retraction");
	if (base.has("contacts") && base["contacts"].get_type() == Variant::ARRAY) {
		Array contacts = base["contacts"];
		for (int64_t i = 0; i < contacts.size(); ++i) {
			if (contacts[i].get_type() == Variant::DICTIONARY) {
				Dictionary contact = contacts[i];
				contact.erase("retraction_path");
			}
		}
	}
	return base;
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

bool decode_prop(Decoder &dec, const Dictionary &prop, nk::PropModel &out) {
	out = nk::PropModel();
	// Geometry-only decoder. Source, wake and shaft admission belongs to the complete stage decoder.
	if (!dec.only(prop, "propulsion", {"max_rpm", "idle_rpm", "lag", "diameter", "offset", "ct", "cp", "rotor_inertia",
				"id", "cp_min", "axis", "normal_force", "pfactor_moment"})) {
		return false;
	}
	std::vector<nk::R> offset;
	if (!dec.number(prop, "diameter", out.diameter, true) || !dec.vec(prop, "offset", offset, true, 3) ||
			!dec.vec(prop, "ct", out.ct, true) || !dec.vec(prop, "cp", out.cp, true) ||
			!dec.number(prop, "rotor_inertia", out.rotor_inertia, true) || !dec.number(prop, "cp_min", out.cp_min, false, 0.0)) {
		return false;
	}
	if (out.ct.size() < 4 || out.ct.size() % 2 != 0 || out.cp.size() < 4 || out.cp.size() % 2 != 0) {
		return dec.fail("propeller ct/cp tables need at least two [J, value] rows");
	}
	for (int i = 0; i < 3; ++i) {
		out.offset[i] = offset[i];
	}
	out.has_axis = prop.has("axis");
	if (out.has_axis) {
		std::vector<nk::R> axis;
		if (!dec.vec(prop, "axis", axis, true, 3)) {
			return false;
		}
		for (int i = 0; i < 3; ++i) {
			if (!nk::is_finite(axis[i])) {
				return dec.fail("nonfinite propeller axis");
			}
			out.axis[i] = axis[i];
		}
	}
	if (!dec.vec(prop, "normal_force", out.normal_force, false) ||
			!dec.vec(prop, "pfactor_moment", out.pfactor_moment, false)) {
		return false;
	}
	for (const auto *table : {&out.normal_force, &out.pfactor_moment}) {
		if (!table->empty() && (table->size() < 4 || table->size() % 2 != 0)) {
			return dec.fail("propeller crossflow table dimensions");
		}
	}
	return true;
}

bool decode_hull(Decoder &dec, const Dictionary &prepared, nk::HullPrepared &out, bool geometry_only = false) {
	out = nk::HullPrepared();
	if (prepared.is_empty()) {
		return true;
	}
	if (!dec.only(prepared, "hull", {"points", "stiffness", "damping", "reach", "mass", "inertia", "surfaces", "lake",
				"lake_bounds_ne_m", "terminal_j_per_kg", "crash_depth_m", "geometry_only"})) {
		return false;
	}
	if (prepared.has("geometry_only") && (prepared["geometry_only"].get_type() != Variant::BOOL ||
			!geometry_only || !static_cast<bool>(prepared["geometry_only"]))) return dec.fail("unexpected geometry-only hull");
	if (geometry_only && !prepared.has("geometry_only")) return dec.fail("missing geometry-only hull marker");
	out.present = true;
	if (!dec.vec(prepared, "points", out.points, true) || !dec.vec(prepared, "stiffness", out.stiffness, !geometry_only) ||
			!dec.vec(prepared, "damping", out.damping, !geometry_only) || !dec.number(prepared, "reach", out.reach, true) ||
			!dec.vec(prepared, "surfaces", out.surfaces, false)) {
		return false;
	}
	const size_t count = out.points.size() / 3;
	if (out.points.empty() || out.points.size() % 3 != 0 || (!geometry_only && (out.stiffness.size() != count || out.damping.size() != count))) {
		return dec.fail("hull points/stiffness/damping sizes");
	}
	if (!out.surfaces.empty() && out.surfaces.size() % nk::kAirframeStride != 0) {
		return dec.fail("airframe friction table stride");
	}
	Dictionary lake;
	if (!dec.dict(prepared, "lake", lake, false) || !decode_lake(dec, lake, out.lake)) {
		return false;
	}
	if (prepared.has("lake_bounds_ne_m")) {
		std::vector<double> bounds;
		if (!dec.vec(prepared, "lake_bounds_ne_m", bounds, true)) {
			return false;
		}
		out.has_bounds = bounds.size() == 4;
		for (size_t i = 0; i < 4 && out.has_bounds; ++i) {
			out.bounds[i] = bounds[i];
		}
	}
	return true;
}

bool layout_int(Decoder &dec, const Dictionary &layout, const char *key, int &out) {
	if (!layout.has(key) || layout[key].get_type() != Variant::INT) {
		return dec.fail(std::string("layout.") + key + " must be an int");
	}
	const int64_t value = layout[key];
	if (value < -1 || value > 4096) return dec.fail(std::string("layout index out of range: ") + key);
	out = static_cast<int>(value);
	return true;
}

bool decode_stage(Decoder &dec, const Dictionary &config, nk::StageModel &m) {
	m = nk::StageModel();
	const bool electric_requested = config.has("electric");
	// Session capabilities whose laws are not ported: the caller keeps the GDScript stage (D6).
	for (const char *flag : {"retractable", "glow", "coupled", "turbine", "liquid", "finite_fuel", "flaps",
				"spatial_weather", "turbulence", "vertical_atmosphere", "weather_pending_reset", "not_calm",
				"slipstream", "rotor_dynamics"}) {
		if (!config.has(flag) || config[flag].get_type() != Variant::BOOL) {
			return dec.fail(std::string("capability flag missing: ") + flag);
		}
		const bool weather_flag = std::string(flag) == "turbulence" || std::string(flag) == "vertical_atmosphere" ||
			std::string(flag) == "not_calm" || std::string(flag) == "spatial_weather";
		const bool electric_flag = electric_requested && (std::string(flag) == "coupled" || std::string(flag) == "rotor_dynamics");
		if (static_cast<bool>(config[flag]) && !(weather_flag && config.has("weather")) && !electric_flag &&
				std::string(flag) != "slipstream" && std::string(flag) != "flaps" && std::string(flag) != "retractable") {
			return dec.fail(std::string("unsupported session capability: ") + flag);
		}
	}
	Dictionary model, gear, lake, hull, layout, propulsion;
	if (!dec.dict(config, "model", model, true) || !dec.dict(config, "gear", gear, true) ||
			!dec.dict(config, "lake", lake, true) || !dec.dict(config, "hull", hull, true) ||
			!dec.dict(config, "layout", layout, true) || !dec.dict(model, "propulsion", propulsion, true)) {
		return false;
	}
	Dictionary prop_geometry = propulsion.duplicate();
	prop_geometry.erase("slipstream");
	if (electric_requested) {
		if (!propulsion.has("kind") || String(propulsion["kind"]) != "electric_prop" ||
				!static_cast<bool>(config["coupled"]) || !static_cast<bool>(config["rotor_dynamics"]) || !config.has("weather")) {
			return dec.fail("electric stage requires a coupled electric model and prepared weather");
		}
		for (const char *key : {"kind", "motor", "battery", "esc"}) prop_geometry.erase(key);
		Dictionary snapshot;
		if (!dec.dict(config, "electric", snapshot, true)) return false;
		for (const char *part : {"motor", "battery", "esc"}) {
			Dictionary supplied, actual;
			if (!dec.dict(snapshot, part, supplied, true) || !dec.dict(propulsion, part, actual, true)) return false;
			const Array keys = supplied.keys();
			for (int64_t i = 0; i < keys.size(); ++i) {
				if (!actual.has(keys[i]) || supplied[keys[i]] != actual[keys[i]]) return dec.fail("electric snapshot differs from the committed model");
			}
		}
		nk::ElectricBinding electric_candidate;
		const Dictionary prepared = electric_candidate.prepare_electric(snapshot);
		if (!static_cast<bool>(prepared["ok"])) return dec.fail("invalid prepared electric source");
		m.electric = true;
		m.electric_source = electric_candidate.model();
		std::vector<nk::R> inertia, inverse;
		if (!dec.vec(config, "inertia", inertia, true, 6) || !dec.vec(config, "inverse", inverse, true, 6)) return false;
		for (int i = 0; i < 6; ++i) {
			if (!nk::is_finite(inertia[i]) || !nk::is_finite(inverse[i])) return dec.fail("nonfinite fixed electric inertia");
			m.inertia[i] = inertia[i]; m.inverse[i] = inverse[i];
		}
		if (!model.has("inertia") || config["inertia"] != model["inertia"]) return dec.fail("electric inertia differs from the committed model");
		const auto expected_inverse = nk::liquid_inertia_inverse(m.inertia);
		for (int i = 0; i < 6; ++i) {
			if (m.inverse[i] != expected_inverse[i]) return dec.fail("electric inverse inertia differs from the reference tensor");
		}
	}
	if (!decode_aero(dec, model, m.aero) || !decode_prop(dec, prop_geometry, m.prop) || !decode_gear(dec, static_cast<bool>(config["retractable"]) ? fixed_gear_source(gear) : gear, m.ground.gear)) {
		return false;
	}
	if (m.aero.flaps.enabled != static_cast<bool>(config["flaps"])) return dec.fail("flap capability and model differ");
	Dictionary slipstream;
	if (!dec.dict(propulsion, "slipstream", slipstream, false)) return false;
	nk::WakeBinding wake_candidate;
	const Dictionary wake_result = wake_candidate.prepare_wake(slipstream, m.aero, m.prop);
	if (!static_cast<bool>(wake_result["ok"]) || (!slipstream.is_empty()) != static_cast<bool>(config["slipstream"])) {
		return dec.fail("invalid wake model or capability flag");
	}
	m.wake = wake_candidate.model();
	if (!config.has("surfaces") || config["surfaces"].get_type() != Variant::PACKED_FLOAT64_ARRAY ||
			!config.has("lake_valid") || config["lake_valid"].get_type() != Variant::BOOL ||
			!config.has("soft_hull") || config["soft_hull"].get_type() != Variant::BOOL) {
		return dec.fail("surfaces, lake_valid and soft_hull are required");
	}
	const PackedFloat64Array surfaces = config["surfaces"];
	m.ground.surfaces.values.assign(surfaces.ptr(), surfaces.ptr() + surfaces.size());
	m.ground.surfaces.valid = nk::surface_table_is_valid(m.ground.surfaces.values);
	m.ground.lake_valid = static_cast<bool>(config["lake_valid"]);
	if (m.ground.lake_valid && !decode_lake(dec, lake, m.ground.lake)) {
		return false;
	}
	if (static_cast<bool>(config["retractable"])) {
		nk::GearBinding retraction;
		const Dictionary result = retraction.prepare_retractable(gear, m.ground);
		if (!static_cast<bool>(result["ok"])) return dec.fail("invalid retractable gear");
		m.retraction = retraction.model();
	}
	m.soft_hull = static_cast<bool>(config["soft_hull"]);
	if (m.soft_hull && !decode_hull(dec, hull, m.hull)) {
		return false;
	}
	if (!dec.number(config, "density", m.density, true) ||
			!dec.number(config, "ground_effect_reach", m.ground_effect_reach, true)) {
		return false;
	}
	nk::StageLayout &L = m.layout;
	if (!layout_int(dec, layout, "aux_size", L.aux_size) || !layout_int(dec, layout, "rpm", L.rpm) ||
			!layout_int(dec, layout, "servo", L.servo) || !layout_int(dec, layout, "anchors", L.anchors) ||
			!layout_int(dec, layout, "anchor_count", L.anchor_count) || !layout_int(dec, layout, "downwash", L.downwash) ||
			!layout_int(dec, layout, "wheel_count", L.wheel_count) || !layout_int(dec, layout, "rotor_index", L.rotor_index) ||
			!layout_int(dec, layout, "wheel_index", L.wheel_index) || !layout_int(dec, layout, "brake_input", L.brake_input) ||
			!layout_int(dec, layout, "input_count", L.input_count)) {
		return false;
	}
	if (m.retraction.enabled && (!layout_int(dec, layout, "gear_aux", L.gear_aux) ||
			L.gear_aux < 0 || L.gear_aux + 1 >= L.aux_size)) return dec.fail("invalid retractable actuator layout");
	const int wash_count = m.wake.transport ? static_cast<int>(m.wake.pieces.size()) : 0;
	L.battery_size = m.electric_source.kind == nk::ElectricBatteryKind::PackEcm ? 9 + 2 * m.electric_source.pack.branches :
		(m.electric_source.kind == nk::ElectricBatteryKind::OcvResistance ? 3 : 0);
	const int source_count = m.electric ? 1 + L.battery_size : 0;
	if (L.rotor_index != wash_count || L.wheel_index != wash_count + source_count) {
		return dec.fail("continuous wash layout differs from prepared wake pieces");
	}
	if (L.wheel_count < 0 || L.wheel_count > 16 || (L.wheel_count == 0 && !m.ground.gear.empty) ||
			L.wheel_count != static_cast<int>(m.ground.gear.contacts.size()) ||
			L.anchor_count != L.wheel_count || L.anchors + L.anchor_count * 3 > L.aux_size || L.servo + 2 >= L.aux_size ||
			L.rpm < 0 || L.rpm >= L.aux_size || L.downwash >= L.aux_size || L.servo < 0 || L.anchors < 0 ||
			L.wheel_index + L.wheel_count > kMaxContinuousSize) {
		return dec.fail("unsupported or inconsistent layout");
	}
	if (config.has("weather")) {
		Dictionary snapshot;
		if (!dec.dict(config, "weather", snapshot, true) || !dec.number(config, "dt", m.dt, true) ||
				!nk::is_finite(m.dt) || m.dt <= 0.0 || !layout_int(dec, layout, "turbulence", L.turbulence)) {
			return dec.fail("weather needs a finite positive tick dt and turbulence layout");
		}
		if (m.electric && m.electric_source.kind == nk::ElectricBatteryKind::PackEcm && !snapshot.has("temperature_k")) {
			return dec.fail("pack stage requires the actual prepared atmosphere temperature");
		}
		nk::WeatherBinding candidate;
		const Dictionary prepared = candidate.prepare_weather(snapshot);
		if (!static_cast<bool>(prepared["ok"]) || candidate.is_spatial() != static_cast<bool>(config["spatial_weather"])) {
			return dec.fail("joint weather stage needs a matching valid snapshot");
		}
		m.weather = candidate.uniform_model();
		m.spatial_weather = candidate.is_spatial();
		m.spatial = candidate.spatial_model();
		if (m.weather.has_turbulence != static_cast<bool>(config["turbulence"]) ||
				m.weather.vertical_atmosphere != static_cast<bool>(config["vertical_atmosphere"]) ||
				(!m.spatial_weather && m.weather.calm == static_cast<bool>(config["not_calm"])) ||
				(m.weather.has_turbulence && (L.turbulence < 4 || L.turbulence + 7 != L.aux_size)) ||
				(!m.weather.has_turbulence && L.turbulence != -1)) {
			return dec.fail("weather snapshot and session capabilities/layout differ");
		}
		if (m.spatial_weather && m.aero.ys.size() != 6) return dec.fail("spatial stage requires six wing stations");
		m.has_weather = true;
	}
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
	out.flap = d.size() == 5 ? d[4] : 0.0;
	return true;
}

} // namespace

class OpenRCNativeKernel : public godot::RefCounted {
	GDCLASS(OpenRCNativeKernel, godot::RefCounted)

	nk::GroundContext ground_;
	bool ground_ready_ = false;
	nk::AeroModel aero_;
	bool aero_ready_ = false;
	nk::PropModel prop_;
	bool prop_ready_ = false;
	nk::WeatherBinding weather_;
	nk::ElectricBinding electric_;
	nk::WakeBinding wake_;
	nk::GlowBinding glow_;
	nk::HelicopterBinding helicopter_;
	nk::LiquidBinding liquid_;
	nk::GearBinding gear_;
	nk::LiveHullBinding live_hull_;
	nk::WeatherGuard weather_guard_;
	nk::LakeTerrain no_lake_; // Environment.terrain (the ground-effect height) samples without the lake
	nk::StageModel stage_;
	bool stage_ready_ = false;
	nk::TickContext tick_;
	int64_t stage_calls_ = 0;
	bool stage_timing_ = false;
	double stage_ns_ = 0.0;
	int64_t context_calls_ = 0;

protected:
	static void _bind_methods() {
		using godot::D_METHOD;
		godot::ClassDB::bind_method(D_METHOD("prepare_weather_guard", "session", "identity"), &OpenRCNativeKernel::prepare_weather_guard);
		godot::ClassDB::bind_method(D_METHOD("weather_guard_matches", "session"), &OpenRCNativeKernel::weather_guard_matches);
		godot::ClassDB::bind_method(D_METHOD("prepare_liquid", "snapshot"), &OpenRCNativeKernel::prepare_liquid);
		godot::ClassDB::bind_method(D_METHOD("liquid_mass_component", "usable"), &OpenRCNativeKernel::liquid_mass_component);
		godot::ClassDB::bind_method(D_METHOD("liquid_gas_laws_component", "rpm", "throttle", "axial", "rho", "charge", "shaft_power", "running"), &OpenRCNativeKernel::liquid_gas_laws_component);
		godot::ClassDB::bind_method(D_METHOD("liquid_gas_component", "body", "external", "prop_air", "datum_air", "explicit_air", "stage", "running", "gravity"), &OpenRCNativeKernel::liquid_gas_component);
		godot::ClassDB::bind_method(D_METHOD("liquid_turbine_component", "body", "datum_air", "explicit_air", "stage", "running"), &OpenRCNativeKernel::liquid_turbine_component);
		godot::ClassDB::bind_method(D_METHOD("prepare_retractable", "source"), &OpenRCNativeKernel::prepare_retractable);
		godot::ClassDB::bind_method(D_METHOD("gear_component", "part", "body", "air", "extension", "density", "ambient_delta", "target", "dt"), &OpenRCNativeKernel::gear_component);
		godot::ClassDB::bind_method(D_METHOD("gear_wheels_component", "body", "extension", "steer", "anchors", "speeds", "brake"), &OpenRCNativeKernel::gear_wheels_component);
		godot::ClassDB::bind_method(D_METHOD("prepare_live_hull", "source"), &OpenRCNativeKernel::prepare_live_hull);
		godot::ClassDB::bind_method(D_METHOD("live_hull_component", "body", "properties"), &OpenRCNativeKernel::live_hull_component);

		godot::ClassDB::bind_method(D_METHOD("backend_identity"), &OpenRCNativeKernel::backend_identity);
		godot::ClassDB::bind_method(D_METHOD("prepare_ground", "gear", "surfaces", "lake", "lake_valid"),
			&OpenRCNativeKernel::prepare_ground);
		godot::ClassDB::bind_method(D_METHOD("terrain_sample", "north", "east", "with_lake"), &OpenRCNativeKernel::terrain_sample);
		godot::ClassDB::bind_method(D_METHOD("surface_table_is_valid", "surfaces"), &OpenRCNativeKernel::surface_table_is_valid);
		godot::ClassDB::bind_method(D_METHOD("wheels_evaluate", "s", "steer", "anchors", "speeds", "brake"),
			&OpenRCNativeKernel::wheels_evaluate);
		godot::ClassDB::bind_method(D_METHOD("wheels_compressions", "s"), &OpenRCNativeKernel::wheels_compressions);
		godot::ClassDB::bind_method(D_METHOD("prepare_aero", "model"), &OpenRCNativeKernel::prepare_aero);
		godot::ClassDB::bind_method(D_METHOD("prepare_propeller", "model"), &OpenRCNativeKernel::prepare_propeller);
		godot::ClassDB::bind_method(D_METHOD("prepare_weather", "config"), &OpenRCNativeKernel::prepare_weather);
		godot::ClassDB::bind_method(D_METHOD("weather_component", "position", "time", "aux", "turbulence_index", "dt"),
			&OpenRCNativeKernel::weather_component);
		godot::ClassDB::bind_method(D_METHOD("air_component", "down"), &OpenRCNativeKernel::air_component);
		godot::ClassDB::bind_method(D_METHOD("temperature_component", "down"), &OpenRCNativeKernel::temperature_component);
		godot::ClassDB::bind_method(D_METHOD("prepare_electric", "snapshot"), &OpenRCNativeKernel::prepare_electric);
		godot::ClassDB::bind_method(D_METHOD("electric_component", "rpm", "duty", "block", "enabled", "ambient_k", "cooling_mps"),
			&OpenRCNativeKernel::electric_component);
		godot::ClassDB::bind_method(D_METHOD("electric_coupling_component", "body", "stage", "block", "inertia", "inverse", "external", "enabled"),
			&OpenRCNativeKernel::electric_coupling_component);
		godot::ClassDB::bind_method(D_METHOD("prepare_wake", "slipstream"), &OpenRCNativeKernel::prepare_wake);
		godot::ClassDB::bind_method(D_METHOD("wake_component", "part", "body", "wind", "rho", "deflections", "rpm",
			"thrust_torque", "downwash", "lagged", "source_delta"), &OpenRCNativeKernel::wake_component);
		godot::ClassDB::bind_method(D_METHOD("spatial_aero_component", "body", "wind", "rho", "controls", "deltas",
			"downwash", "ground_up", "continuation"), &OpenRCNativeKernel::spatial_aero_component);
		godot::ClassDB::bind_method(D_METHOD("spatial_flow_component", "body", "time", "rho", "aux", "turbulence_index", "dt"),
			&OpenRCNativeKernel::spatial_flow_component);
		godot::ClassDB::bind_method(D_METHOD("spatial_wake_component", "body", "time", "rho", "controls", "rpm", "tq", "downwash",
			"lagged", "aux", "turbulence_index", "dt"), &OpenRCNativeKernel::spatial_wake_component);
		godot::ClassDB::bind_method(D_METHOD("prepare_glow", "snapshot"), &OpenRCNativeKernel::prepare_glow);
		godot::ClassDB::bind_method(D_METHOD("glow_source_component", "rpm", "admission", "mixture", "dry_density", "running", "firing"),
			&OpenRCNativeKernel::glow_source_component);
		godot::ClassDB::bind_method(D_METHOD("glow_blade_component", "rpm", "axial_speed", "density"), &OpenRCNativeKernel::glow_blade_component);
		godot::ClassDB::bind_method(D_METHOD("glow_mass_component", "amounts"), &OpenRCNativeKernel::glow_mass_component);
		godot::ClassDB::bind_method(D_METHOD("glow_body_component", "body", "amounts", "force", "moment", "gravity", "rotor"),
			&OpenRCNativeKernel::glow_body_component);
		godot::ClassDB::bind_method(D_METHOD("glow_feed_component", "remaining", "capacity", "unusable", "admission", "rpm",
			"force", "mass", "arm", "alpha", "omega"), &OpenRCNativeKernel::glow_feed_component);
		godot::ClassDB::bind_method(D_METHOD("prepare_helicopter", "snapshot"), &OpenRCNativeKernel::prepare_helicopter);
		godot::ClassDB::bind_method(D_METHOD("heli_component", "body", "continuous", "time", "tick", "wind"),
			&OpenRCNativeKernel::heli_component);
		godot::ClassDB::bind_method(D_METHOD("propeller_component", "s", "air", "rho", "rpm", "local_hub", "explicit_air"),
			&OpenRCNativeKernel::propeller_component);
		godot::ClassDB::bind_method(D_METHOD("aero_component", "which", "s", "wind", "rho", "d", "downwash_cl", "ground_up"),
			&OpenRCNativeKernel::aero_component);
		godot::ClassDB::bind_method(D_METHOD("aero_loads", "s", "wind", "rho", "d", "downwash_cl", "ground_up"),
			&OpenRCNativeKernel::aero_loads);
		godot::ClassDB::bind_method(D_METHOD("math_probe", "fn", "a", "b", "c"), &OpenRCNativeKernel::math_probe);
		godot::ClassDB::bind_method(D_METHOD("literal_table"), &OpenRCNativeKernel::literal_table);
		godot::ClassDB::bind_method(D_METHOD("bench_wheels", "s", "steer", "anchors", "speeds", "brake", "iterations"),
			&OpenRCNativeKernel::bench_wheels);
		godot::ClassDB::bind_method(D_METHOD("prepare_stage", "config"), &OpenRCNativeKernel::prepare_stage);
		godot::ClassDB::bind_method(D_METHOD("set_tick_context", "aux", "inputs", "deflections", "time_now"),
			&OpenRCNativeKernel::set_tick_context);
		godot::ClassDB::bind_method(D_METHOD("set_power_context", "throttle", "enabled"), &OpenRCNativeKernel::set_power_context);
		godot::ClassDB::bind_method(D_METHOD("stage", "body", "continuous", "t"), &OpenRCNativeKernel::stage);
		godot::ClassDB::bind_method(D_METHOD("stage_stats"), &OpenRCNativeKernel::stage_stats);
		godot::ClassDB::bind_method(D_METHOD("reset_stage_stats", "timing"), &OpenRCNativeKernel::reset_stage_stats);
		godot::ClassDB::bind_method(D_METHOD("prop_component", "s", "wind", "rho", "rpm"), &OpenRCNativeKernel::prop_component);
		godot::ClassDB::bind_method(D_METHOD("hull_component", "s"), &OpenRCNativeKernel::hull_component);
		godot::ClassDB::bind_method(D_METHOD("ground_component", "s", "values"), &OpenRCNativeKernel::ground_component);
		godot::ClassDB::bind_method(D_METHOD("ground_up_component", "s"), &OpenRCNativeKernel::ground_up_component);
		godot::ClassDB::bind_method(D_METHOD("bench_aero", "s", "wind", "rho", "d", "downwash_cl", "ground_up", "iterations"),
			&OpenRCNativeKernel::bench_aero);
	}

public:
	Dictionary backend_identity() const {
		Dictionary out;
		out["backend"] = kBackend;
		out["backend_version"] = kBackendVersion;
		out["abi_version"] = kAbi;
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
		const bool ok = decode_gear(dec, fixed_gear_source(gear), candidate.gear) && (!lake_valid || decode_lake(dec, lake, candidate.lake));
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

	Dictionary prepare_propeller(const Dictionary &model) {
		Decoder dec;
		nk::PropModel candidate;
		prop_ready_ = decode_prop(dec, model, candidate);
		if (prop_ready_) {
			prop_ = std::move(candidate);
		}
		Dictionary out;
		out["ok"] = prop_ready_;
		out["error"] = String(dec.error.c_str());
		return out;
	}

	Dictionary prepare_weather(const Dictionary &config) { return weather_.prepare_weather(config); }
	PackedFloat64Array weather_component(const PackedFloat64Array &position, double time, const PackedFloat64Array &aux,
			int64_t turbulence_index, double dt) const {
		return weather_.weather_component(position, time, aux, turbulence_index, dt);
	}
	PackedFloat64Array air_component(double down) const { return weather_.air_component(down); }
	double temperature_component(double down) const { return weather_.temperature_component(down); }
	Dictionary prepare_electric(const Dictionary &snapshot) { return electric_.prepare_electric(snapshot); }
	Dictionary electric_component(double rpm, double duty, const PackedFloat64Array &block, bool enabled,
			double ambient_k, double cooling_mps) const {
		return electric_.electric_component(rpm, duty, block, enabled, ambient_k, cooling_mps);
	}
	Dictionary electric_coupling_component(const PackedFloat64Array &body, const PackedFloat64Array &stage,
			const PackedFloat64Array &block, const PackedFloat64Array &inertia, const PackedFloat64Array &inverse,
			const PackedFloat64Array &external, bool enabled) const {
		if (!prop_ready_) { Dictionary out; out["ok"] = false; return out; }
		return electric_.electric_coupling_component(prop_, body, stage, block, inertia, inverse, external, enabled);
	}
	Dictionary prepare_wake(const Dictionary &slipstream) {
		if (!aero_ready_ || !prop_ready_) {
			wake_ = nk::WakeBinding();
			Dictionary out;
			out["ok"] = false;
			out["error"] = "prepare aerodynamic and propeller models before the wake";
			return out;
		}
		return wake_.prepare_wake(slipstream, aero_, prop_);
	}
	PackedFloat64Array wake_component(int64_t part, const PackedFloat64Array &body, const PackedFloat64Array &wind,
			double rho, const PackedFloat64Array &deflections, double rpm, const PackedFloat64Array &thrust_torque,
			double downwash, const PackedFloat64Array &lagged, const PackedFloat64Array &source_delta) const {
		return wake_.wake_component(part, body, wind, rho, deflections, rpm, thrust_torque, downwash, lagged, source_delta);
	}
	Dictionary spatial_aero_component(const PackedFloat64Array &body, const PackedFloat64Array &wind, double rho,
			const PackedFloat64Array &controls, const PackedFloat64Array &deltas, double downwash, double ground_up, bool continuation) const {
		if (!aero_ready_) return nk::spatial_binding_failure("aero not prepared");
		return nk::spatial_aero_component(aero_, body, wind, rho, controls, deltas, downwash, ground_up, continuation);
	}
	Dictionary spatial_flow_component(const PackedFloat64Array &body, double time, double rho, const PackedFloat64Array &aux,
			int64_t turbulence_index, double dt) const {
		if (!aero_ready_ || !prop_ready_ || !weather_.ready()) return nk::spatial_binding_failure("spatial models not prepared");
		return nk::spatial_flow_component(aero_, prop_.offset, weather_, body, time, rho, aux, turbulence_index, dt);
	}
	Dictionary spatial_wake_component(const PackedFloat64Array &body, double time, double rho, const PackedFloat64Array &controls,
			double rpm, const PackedFloat64Array &tq, double downwash, const PackedFloat64Array &lagged, const PackedFloat64Array &aux,
			int64_t turbulence_index, double dt) const {
		if (!aero_ready_ || !prop_ready_ || !wake_.ready() || !weather_.ready()) return nk::spatial_binding_failure("spatial models not prepared");
		return nk::spatial_wake_component(aero_, prop_, wake_.model(), weather_, body, time, rho, controls, rpm, tq, downwash, lagged,
			aux, turbulence_index, dt);
	}
	Dictionary prepare_glow(const Dictionary &snapshot) { return glow_.prepare_glow(snapshot); }
	Dictionary glow_source_component(double rpm, double admission, double mixture, double dry_density, bool running, double firing) const {
		return glow_.glow_source_component(rpm, admission, mixture, dry_density, running, firing);
	}
	Dictionary glow_blade_component(double rpm, double axial_speed, double density) const {
		return glow_.glow_blade_component(rpm, axial_speed, density);
	}
	Dictionary glow_mass_component(const PackedFloat64Array &amounts) const { return glow_.glow_mass_component(amounts); }
	Dictionary glow_body_component(const PackedFloat64Array &body, const PackedFloat64Array &amounts, const PackedFloat64Array &force,
			const PackedFloat64Array &moment, double gravity, const PackedFloat64Array &rotor) const {
		return glow_.glow_body_component(body, amounts, force, moment, gravity, rotor);
	}
	Dictionary glow_feed_component(double remaining, double capacity, double unusable, double admission, double rpm,
			const PackedFloat64Array &force, double mass, const PackedFloat64Array &arm, const PackedFloat64Array &alpha,
			const PackedFloat64Array &omega) const {
		return glow_.glow_feed_component(remaining, capacity, unusable, admission, rpm, force, mass, arm, alpha, omega);
	}

	Dictionary prepare_weather_guard(godot::Object *session, godot::Object *identity) { return weather_guard_.prepare_weather_guard(session, identity); }
	bool weather_guard_matches(godot::Object *session) const { return weather_guard_.weather_guard_matches(session); }
	Dictionary prepare_liquid(const Dictionary &snapshot) { return liquid_.prepare_liquid(snapshot); }
	Dictionary liquid_mass_component(double usable) const { return liquid_.liquid_mass_component(usable); }
	Dictionary liquid_gas_laws_component(double rpm, double throttle, double axial, double rho, double charge, double shaft_power, bool running) const {
		if (!prop_ready_) return nk::spatial_binding_failure("propeller not prepared");
		return liquid_.liquid_gas_laws_component(prop_, rpm, throttle, axial, rho, charge, shaft_power, running);
	}
	Dictionary liquid_gas_component(const PackedFloat64Array &body, const PackedFloat64Array &external,
			const PackedFloat64Array &prop_air, const PackedFloat64Array &datum_air, bool explicit_air,
			const PackedFloat64Array &stage, bool running, double gravity) const {
		if (!prop_ready_) return nk::spatial_binding_failure("propeller not prepared");
		return liquid_.liquid_gas_component(prop_, body, external, prop_air, datum_air, explicit_air, stage, running, gravity);
	}
	Dictionary liquid_turbine_component(const PackedFloat64Array &body, const PackedFloat64Array &datum_air,
			const PackedFloat64Array &explicit_air, const PackedFloat64Array &stage, bool running) const {
		return liquid_.liquid_turbine_component(body, datum_air, explicit_air, stage, running);
	}
	Dictionary prepare_retractable(const Dictionary &source) {
		if (!ground_ready_) return nk::spatial_binding_failure("ground not prepared");
		return gear_.prepare_retractable(source, ground_);
	}
	PackedFloat64Array gear_component(int64_t part, const PackedFloat64Array &body, const PackedFloat64Array &air,
			double extension, double density, const PackedFloat64Array &ambient_delta, double target, double dt) const {
		return gear_.gear_component(part, body, air, extension, density, ambient_delta, target, dt);
	}
	Dictionary gear_wheels_component(const PackedFloat64Array &body, double extension, double steer,
			const PackedFloat64Array &anchors, const PackedFloat64Array &speeds, double brake) const {
		return gear_.gear_wheels_component(body, extension, steer, anchors, speeds, brake);
	}
	Dictionary prepare_live_hull(const Dictionary &source) {
		Decoder dec;
		nk::HullPrepared prepared;
		live_hull_ = nk::LiveHullBinding();
		if (!decode_hull(dec, source, prepared, true)) return nk::spatial_binding_failure(dec.error.c_str());
		return live_hull_.prepare_live_hull(source, prepared);
	}
	Dictionary live_hull_component(const PackedFloat64Array &body, const Dictionary &properties) const {
		return live_hull_.live_hull_component(body, properties);
	}

	Dictionary prepare_helicopter(const Dictionary &snapshot) { return helicopter_.prepare_helicopter(snapshot); }
	Dictionary heli_component(const PackedFloat64Array &body, const PackedFloat64Array &continuous, double time,
			const Dictionary &tick, const PackedFloat64Array &wind) const {
		return helicopter_.heli_component(body, continuous, time, tick, wind);
	}

	Dictionary propeller_component(const PackedFloat64Array &s, const PackedFloat64Array &air, double rho,
			double rpm, bool local_hub, const PackedFloat64Array &explicit_air) const {
		Dictionary out;
		out["ok"] = false;
		if (!prop_ready_ || !read_state(s) || air.size() != 3 || (explicit_air.size() != 0 && explicit_air.size() != 3)) {
			return out;
		}
		nk::R state[kStateSize], datum[3], local[3];
		load(s, state);
		load(air, datum);
		if (!explicit_air.is_empty()) {
			load(explicit_air, local);
		}
		const auto flow = nk::prop_stage_air_velocity(state, datum, prop_, local_hub, explicit_air.is_empty() ? nullptr : local);
		if (!flow.ok) {
			return out;
		}
		const auto tq = nk::prop_thrust_torque(flow.velocity.data(), rpm, prop_, rho);
		const auto loads = nk::prop_loads(flow.velocity.data(), rpm, prop_, rho);
		const auto rotor = nk::prop_rotor_momentum(prop_, rpm);
		const auto normal = nk::prop_normal_force(flow.velocity.data(), rpm, prop_, rho);
		const auto pfactor = nk::prop_pfactor_moment(flow.velocity.data(), rpm, prop_, rho);
		out["ok"] = true;
		out["velocity"] = pack(flow.velocity.data(), 3);
		out["thrust_torque"] = pack(tq.data(), 3);
		out["loads"] = pack(loads.data(), 6);
		out["rotor_momentum"] = pack(rotor.data(), 3);
		out["normal_force"] = pack(normal.data(), 3);
		out["pfactor_moment"] = pack(pfactor.data(), 3);
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
			{"TAU", nk::kTauConstant}, {"-0.1", nk::kCtFloor}, {"60.0", nk::kHullOmega}, {"0.004", nk::kHullDampingOnset},
			{"0.4", nk::kHullFrictionMu}, {"120.0", nk::kHullFrictionRateMax}, {"0.001", 0.001}, {"4.0", 4.0},
			{"2.0", nk::kGroundEffectFade},
			{"180.0", 180.0}, {"1e-11", 1e-11}, {"0.5", 0.5}, {"10.0", 10.0},
			{"100.0", 100.0}, {"3600.0", 3600.0},
			{"101325.0", nk::kWeatherSeaPressure}, {"288.15", nk::kWeatherSeaTemperature},
			{"1.225", nk::kWeatherSeaDensity}, {"9.80665", nk::kWeatherGravity},
			{"0.0065", nk::kWeatherLapse}, {"287.05287", nk::kWeatherDryGas},
			{"6356766.0", nk::kWeatherEarthRadius}, {"6.283185307179586476925286766559", nk::kSpatialWeatherTau},
			{"3.1415926535897932384626433832795", nk::kSpatialThermalPi},
			// Additional spellings used by the broader prepared component laws.
			{"0.0", 0.0}, {"0.00001", 0.00001}, {"0.005", 0.005}, {"0.03794", 0.03794},
			{"0.05", 0.05}, {"0.08", 0.08}, {"0.15", 0.15}, {"0.2", 0.2},
			{"0.236926885056189", 0.236926885056189}, {"0.2369268850561891", 0.2369268850561891}, {"0.3", 0.3}, {"0.478628670499366", 0.478628670499366},
			{"0.4786286704993665", 0.4786286704993665}, {"0.525", 0.525}, {"0.5282817877171742", 0.5282817877171742}, {"0.538469310105683", 0.538469310105683},
			{"0.5384693101056831", 0.5384693101056831}, {"0.5688888888888889", 0.5688888888888889}, {"0.568888888888889", 0.568888888888889}, {"0.6847314563772704", 0.6847314563772704},
			{"0.7", 0.7}, {"0.7071", 0.7071}, {"0.75", 0.75}, {"0.849", 0.849},
			{"0.85", 0.85}, {"0.906179845938664", 0.906179845938664}, {"0.9061798459386640", 0.9061798459386640}, {"0.95", 0.95},
			{"0.975", 0.975}, {"0.9926", 0.9926}, {"1.0", 1.0}, {"1.0e-10", 1.0e-10},
			{"1.0e-12", 1.0e-12}, {"1.0e-14", 1.0e-14}, {"1.0e-24", 1.0e-24}, {"1.0e-8", 1.0e-8},
			{"1.0e12", 1.0e12}, {"1.0e6", 1.0e6}, {"1.25", 1.25}, {"1.4", 1.4},
			{"1.5", 1.5}, {"1000.0", 1000.0}, {"10000.0", 10000.0}, {"11000.0", 11000.0},
			{"12.0", 12.0}, {"1200.0", 1200.0}, {"125000000.0", 125000000.0}, {"15.0", 15.0},
			{"1500.0", 1500.0}, {"16.0", 16.0}, {"1e-10", 1e-10}, {"1e-12", 1e-12},
			{"1e-13", 1e-13}, {"1e-15", 1e-15}, {"1e-24", nk::kGd1eMinus24}, {"1e-8", 1e-8},
			{"1e6", 1e6}, {"2.1", 2.1}, {"20.0", 20.0}, {"200.0", 200.0},
			{"270.0", 270.0}, {"287.05", 287.05}, {"3.0", 3.0}, {"3.1415926535897932384626433833", 3.1415926535897932384626433833},
			{"30.0", 30.0}, {"360.0", 360.0}, {"3600000.0", 3600000.0}, {"4000.0", 4000.0},
			{"5.0", 5.0}, {"50.0", 50.0}, {"500.0", 500.0}, {"6.0", 6.0},
			{"6.2831853071795864769252867666", 6.2831853071795864769252867666}, {"64.0", 64.0}, {"7.0", 7.0}, {"720.0", 720.0},
			{"8.0", 8.0}, {"80.0", 80.0}, {"86400.0", 86400.0}, {"90.0", 90.0},
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

	Dictionary prepare_stage(const Dictionary &config) {
		Decoder dec;
		nk::StageModel candidate;
		const bool ok = decode_stage(dec, config, candidate);
		stage_ready_ = ok;
		tick_ = nk::TickContext();
		if (ok) {
			stage_ = candidate;
		}
		Dictionary out;
		out["ok"] = ok;
		out["error"] = String(dec.error.c_str());
		out["law"] = "flight_session._wheel_evaluate/legacy-prop/soft-hull/gp02-wheels";
		return out;
	}

	// Once per tick, from the wrapped pre_tick: the aux the kernel installs, the inputs, the session's own
	// _deflections(aux) [elevator, aileron_right, aileron_left, rudder] and sim.time().
	bool set_tick_context(const PackedFloat64Array &aux, const PackedFloat64Array &inputs,
			const PackedFloat64Array &deflections, double time_now) {
		++context_calls_;
		tick_.ready = false;
		tick_.power_ready = false;
		if (!stage_ready_ || aux.size() != stage_.layout.aux_size || !read_deflections(deflections, tick_.deflections)) {
			return false;
		}
		tick_.aux.assign(aux.ptr(), aux.ptr() + aux.size());
		const int brake = stage_.layout.brake_input;
		tick_.brake = brake >= 0 && brake < inputs.size() ? inputs[brake] : 0.0;
		if (stage_.retraction.enabled) {
			const int index = stage_.layout.gear_aux;
			if (inputs.size() != stage_.layout.input_count || !nk::retractable_valid_fraction(tick_.aux[index]) ||
					(tick_.aux[index + 1] != 0.0 && tick_.aux[index + 1] != 1.0)) return false;
			tick_.posed_ground = stage_.ground;
			if (!nk::retractable_pose(stage_.ground.gear, stage_.retraction, tick_.aux[index], tick_.posed_ground.gear)) return false;
		}
		tick_.time_now = time_now;
		tick_.ready = true;
		return true;
	}
	bool set_power_context(double throttle, bool enabled) {
		tick_.power_ready = false;
		if (!stage_ready_ || !tick_.ready || !stage_.electric) return false;
		tick_.throttle = throttle;
		tick_.power_enabled = enabled;
		tick_.power_ready = true;
		return true;
	}

	Dictionary stage(const PackedFloat64Array &body, const PackedFloat64Array &continuous, double t) {
		++stage_calls_;
		const auto start = stage_timing_ ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point();
		Dictionary out;
		if (stage_ready_ && read_state(body) && continuous.size() <= kMaxContinuousSize) {
			nk::R state[kStateSize];
			nk::R values[kMaxContinuousSize];
			load(body, state);
			for (int64_t i = 0; i < continuous.size(); ++i) {
				values[i] = continuous[i];
			}
			const nk::StageResult result = nk::stage_evaluate(state, values, static_cast<int>(continuous.size()), t,
				stage_, tick_);
			if (result.shaped) {
				// GDScript's {loads = ...} literal keys are StringNames; keep the reference's exact dictionary bytes.
				static const godot::StringName kLoads("loads"), kDerivative("derivative"), kRotor("rotor_momentum");
				out[kLoads] = pack(result.loads.data(), 6);
				out[kDerivative] = pack(result.derivative);
				out[kRotor] = pack(result.rotor.data(), 3);
			}
		}
		if (stage_timing_) {
			stage_ns_ += std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - start).count();
		}
		return out;
	}

	Dictionary stage_stats() const {
		Dictionary out;
		out["stage_calls"] = stage_calls_;
		out["context_calls"] = context_calls_;
		out["stage_ns"] = stage_ns_;
		out["timing"] = stage_timing_;
		return out;
	}

	void reset_stage_stats(bool timing) {
		stage_calls_ = 0;
		context_calls_ = 0;
		stage_ns_ = 0.0;
		stage_timing_ = timing;
	}

	// Dynamics.loads_from_air's propeller part: Propulsion.stage_air_velocity (datum inflow) then Propulsion.loads.
	PackedFloat64Array prop_component(const PackedFloat64Array &s, const PackedFloat64Array &wind, double rho, double rpm) const {
		if (!stage_ready_ || !read_state(s) || wind.size() != 3) {
			return PackedFloat64Array();
		}
		nk::R state[kStateSize];
		nk::R wind_ned[3];
		load(s, state);
		load(wind, wind_ned);
		const nk::Air air = nk::air_compute(state, wind_ned, rho);
		if (!nk::is_finite(air.v[0]) || !nk::is_finite(air.v[1]) || !nk::is_finite(air.v[2])) {
			const nk::R invalid[6] = {nk::kNan, nk::kNan, nk::kNan, nk::kNan, nk::kNan, nk::kNan};
			return pack(invalid, 6);
		}
		const std::array<nk::R, 6> loads = nk::prop_loads(air.v, rpm, stage_.prop, rho);
		return pack(loads.data(), 6);
	}

	PackedFloat64Array hull_component(const PackedFloat64Array &s) const {
		if (!stage_ready_ || !read_state(s)) {
			return PackedFloat64Array();
		}
		nk::R state[kStateSize];
		load(s, state);
		std::array<nk::R, 6> loads;
		if (!nk::hull_loads(state, stage_.hull, loads)) {
			return PackedFloat64Array();
		}
		return pack(loads.data(), 6);
	}

	// FlightSession._ground_evaluation with the current tick context's aux.
	Dictionary ground_component(const PackedFloat64Array &s, const PackedFloat64Array &values) const {
		Dictionary out;
		if (!stage_ready_ || !tick_.ready || !read_state(s) || values.size() > kMaxContinuousSize) {
			out["ok"] = false;
			return out;
		}
		nk::R state[kStateSize];
		nk::R continuous[kMaxContinuousSize];
		load(s, state);
		for (int64_t i = 0; i < values.size(); ++i) {
			continuous[i] = values[i];
		}
		std::array<nk::R, 6> loads{};
		bool has_loads = false;
		std::vector<nk::R> rates;
		const bool ok = nk::stage_ground(state, stage_, tick_, continuous, static_cast<int>(values.size()), loads, has_loads, rates);
		out["ok"] = ok;
		if (ok) {
			out["loads"] = has_loads ? pack(loads.data(), 6) : PackedFloat64Array();
			out["derivative"] = pack(rates);
		}
		return out;
	}

	double ground_up_component(const PackedFloat64Array &s) const {
		if (!stage_ready_ || !read_state(s)) {
			return nk::kNan;
		}
		nk::R state[kStateSize];
		load(s, state);
		return nk::stage_ground_up(state, stage_).v;
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
