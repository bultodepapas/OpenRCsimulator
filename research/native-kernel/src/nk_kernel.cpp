// NK-3 research GDExtension: prepared fixed-wing stage-evaluator components (terrain + lake, GP-02 wheels, aero).
// Not installed into app/; the oracle loads it at run time. Inputs are decoded once by prepare_ground/prepare_aero
// (D6: unknown keys or unsupported laws are refused so callers keep the GDScript reference); per-call methods take
// packed float64 arrays and never touch the source dictionaries. Simulation values are double scalars only.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>

#include <chrono>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <memory>
#include <initializer_list>
#include <limits>
#include <string>
#include <utility>
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
#include "nk_prescribed_binding.hpp"
#include "nk_gear_binding.hpp"
#include "nk_weather_guard.hpp"
#include "nk_point_sampler.hpp"
#include "nk_configuration_guard.hpp"
#include "nk_soundscape.hpp"
#include "nk_soundscape_core.hpp"
#include "nk_ground_audio_core.hpp"
#include "nk_mechanical_audio_core.hpp"
#include "nk_audio_rows.hpp"
#include "nk_macos_domain_guard.hpp"
#include "nk_stage_snapshot.hpp"
#include "nk_contact_reach.hpp"
#include "nk_pre_step.hpp"
#include "nk_tick.hpp"
#include "nk_glow_voice.hpp"
#include "nk_glow_finish.hpp"
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/ref.hpp>

namespace {

using godot::Array;
using godot::Dictionary;
using godot::PackedFloat64Array;
using godot::PackedStringArray;
using godot::String;
using godot::Variant;

constexpr int kStateSize = 13;
// Refusal diagnostics deliberately retain bounded copies; execution is sized
// to the validated layout and is not subject to this diagnostic limit.
constexpr int kMaxDiagnosticContinuousSize = 64;
constexpr int kMaxDiagnosticAuxSize = 4096;
constexpr int kMaxDiagnosticInputSize = 256;
constexpr const char *kBackend = "native";
// Bump on any change to the stage contract (inputs, layout, outputs); the app loader and receipt must agree.
constexpr const char *kBackendVersion = "openrc-native-kernel-stage-v2";
constexpr int kAbi = 2;
// Law identities the port mirrors; the oracle compares them with the loaded GDScript constants.
constexpr const char *kAeroLaw = "section-plane-source-weighted-wake-velocity-v4";
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
		if (!packed.is_empty()) out.assign(packed.ptr(), packed.ptr() + packed.size());
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
				"body_crossflow_area", "wing_cm_ac", "wing_separated_force_offset", "station_incidence", "horizontal", "vertical", "tailless"}) ||
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
		for (nk::R factor : m.polar.strip_factor) {
			if (!nk::is_finite(factor) || factor <= 0.0) return dec.fail("wing polar strip_factor must be finite and positive");
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
			!dec.number(surfaces, "wing_separated_force_offset", m.wing_separated_force_offset, false, 0.0) ||
			!dec.vec(surfaces, "station_incidence", m.station_incidence, false)) {
		return false;
	}
	if (!nk::is_finite(m.wing_separated_force_offset) || m.wing_separated_force_offset < 0.0 || m.wing_separated_force_offset > 0.25) {
		return dec.fail("wing_separated_force_offset range");
	}
	if (!m.station_incidence.empty() && static_cast<int>(m.station_incidence.size()) != stations) {
		return dec.fail("station_incidence size");
	}
	if (m.wing_cm_ac.v != 0.0 && static_cast<int>(m.station_chords.size()) != stations) {
		return dec.fail("wing_cm_ac without one station chord per station");
	}
	if (surfaces.has("wing_separated_force_offset") && (m.flaps.enabled || !m.tailless.station_x.empty())) {
		return dec.fail("wing_separated_force_offset requires a conventional wing without flaps");
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
				!dec.number(c, "anchor_stiffness", w.anchor_stiffness, false, 0.0) ||
				!dec.number(c, "anchor_damping", w.anchor_damping, false, 0.0) ||
				!dec.number(c, "wheel_radius", w.wheel_radius, false, nk::kReferenceRadius) ||
				!dec.number(c, "wheel_inertia", w.wheel_inertia, false, 0.00003) ||
				!dec.number(c, "spin_relaxation", w.spin_relaxation, false, 0.03) ||
				!dec.number(c, "brake_torque", w.brake_torque, false, 0.0)) {
			return false;
		}
		for (int k = 0; k < 3; ++k) {
			w.position[k] = position[k];
		}
		// NK-5i: Ground.collapsed's travel limit, read without new refusals: a missing or non-numeric value stays NAN
		// and only the endpoint facts that would compare it refuse.
		if (c.has("max_compression")) {
			const Variant limit = c["max_compression"];
			if (limit.get_type() == Variant::FLOAT) {
				w.max_compression = static_cast<double>(limit);
			} else if (limit.get_type() == Variant::INT) {
				w.max_compression = static_cast<double>(static_cast<int64_t>(limit));
			}
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
	if (value < -1 || value > std::numeric_limits<int>::max()) return dec.fail(std::string("layout index out of range: ") + key);
	out = static_cast<int>(value);
	return true;
}

bool decode_stage(Decoder &dec, const Dictionary &config, nk::StageModel &m) {
	m = nk::StageModel();
	const bool electric_requested = config.has("electric");
	const bool liquid_requested = config.has("liquid_source");
	const bool glow_requested = config.has("glow_snapshot");
	const bool prescribed_requested = config.has("prescribed");
	if (int(electric_requested) + int(liquid_requested) + int(glow_requested) + int(prescribed_requested) > 1) return dec.fail("multiple stage source families");
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
		const bool liquid_flag = liquid_requested && (std::string(flag) == "coupled" || std::string(flag) == "rotor_dynamics" ||
			std::string(flag) == "liquid" || std::string(flag) == "finite_fuel" || std::string(flag) == "turbine");
		const bool glow_flag = glow_requested && (std::string(flag) == "coupled" || std::string(flag) == "rotor_dynamics" ||
			std::string(flag) == "glow" || std::string(flag) == "finite_fuel");
		const bool prescribed_flag = prescribed_requested && (std::string(flag) == "coupled" ||
			std::string(flag) == "rotor_dynamics" || std::string(flag) == "turbine");
		if (static_cast<bool>(config[flag]) && !glow_flag && !liquid_flag && !prescribed_flag && !(weather_flag && config.has("weather")) && !electric_flag &&
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
		if (!dec.dict(config, "electric", snapshot, true) || !nk::stage_snapshot_electric(model, snapshot, dec.error)) return false;
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
		if (!model.has("inertia") || !nk::stage_snapshot_exact(config["inertia"], model["inertia"])) return dec.fail("electric inertia differs from the committed model");
		const auto expected_inverse = nk::liquid_inertia_inverse(m.inertia);
		for (int i = 0; i < 6; ++i) {
			if (nk::bits(m.inverse[i].v) != nk::bits(expected_inverse[i].v)) return dec.fail("electric inverse inertia differs from the reference tensor");
		}
	}
	if (glow_requested) {
		Dictionary snapshot;
		if (!static_cast<bool>(config["glow"]) || !static_cast<bool>(config["coupled"]) ||
				!static_cast<bool>(config["finite_fuel"]) || !config.has("weather") ||
				!dec.dict(config, "glow_snapshot", snapshot, true) || !dec.number(config, "gravity", m.gravity, true) ||
				!nk::is_finite(m.gravity)) return dec.fail("invalid glow stage prerequisites");
		if (!nk::stage_snapshot_glow(model, snapshot, dec.error)) return false;
		nk::GlowBinding candidate;
		const Dictionary prepared = candidate.prepare_glow(snapshot);
		if (!static_cast<bool>(prepared["ok"]) || !candidate.stage_model().ready) return dec.fail("invalid prepared glow lifecycle");
		m.glow = candidate.stage_model();
		Dictionary selected;
		for (const char *key : {"diameter", "offset", "ct", "cp", "rotor_inertia", "cp_min", "axis", "normal_force", "pfactor_moment"}) {
			if (propulsion.has(key)) selected[key] = propulsion[key];
		}
		prop_geometry = selected;
	}
	if (liquid_requested) {
		Dictionary snapshot;
		if (!static_cast<bool>(config["liquid"]) || !static_cast<bool>(config["finite_fuel"]) ||
				!config.has("weather") || !dec.dict(config, "liquid_source", snapshot, true) ||
				!dec.number(config, "gravity", m.gravity, true) || !nk::is_finite(m.gravity)) return dec.fail("invalid liquid stage prerequisites");
		if (!nk::stage_snapshot_liquid(model, snapshot, dec.error)) return false;
		nk::LiquidBinding candidate;
		const Dictionary prepared = candidate.prepare_liquid(snapshot);
		if (!static_cast<bool>(prepared["ok"])) return dec.fail("invalid prepared liquid source");
		m.liquid = candidate.stage_model();
		if (static_cast<bool>(config["turbine"]) == m.liquid.gas) return dec.fail("liquid source family mismatch");
		if (m.liquid.gas) {
			Dictionary selected;
			for (const char *key : {"diameter", "offset", "ct", "cp", "rotor_inertia", "cp_min", "axis", "normal_force", "pfactor_moment"}) {
				if (propulsion.has(key)) selected[key] = propulsion[key];
			}
			prop_geometry = selected;
		} else {
			for (int i = 0; i < 3; ++i) m.prop.offset[i] = m.liquid.turbine.intake_offset[i];
		}
	}
	if (prescribed_requested) {
		Dictionary snapshot;
		if (!config.has("weather") || static_cast<bool>(config["liquid"]) || static_cast<bool>(config["glow"]) ||
				static_cast<bool>(config["finite_fuel"]) || !dec.dict(config, "prescribed", snapshot, true)) return dec.fail("invalid prescribed stage prerequisites");
		nk::PrescribedBinding candidate;
		const Dictionary prepared = candidate.prepare_prescribed(snapshot, model);
		if (!static_cast<bool>(prepared["ok"])) return dec.fail(String(prepared["error"]).utf8().get_data());
		m.prescribed = candidate.model();
		if (static_cast<bool>(config["turbine"]) != m.prescribed.is_turbine() ||
				static_cast<bool>(config["coupled"]) != m.prescribed.coupled() ||
				static_cast<bool>(config["rotor_dynamics"]) != (m.prescribed.gas() || m.prescribed.continuous_turbine())) return dec.fail("prescribed source capability mismatch");
		if (m.prescribed.gas()) {
			Dictionary selected;
			for (const char *key : {"diameter", "offset", "ct", "cp", "rotor_inertia", "cp_min", "axis", "normal_force", "pfactor_moment"}) {
				if (propulsion.has(key)) selected[key] = propulsion[key];
			}
			prop_geometry = selected;
		} else {
			for (int i = 0; i < 3; ++i) m.prop.offset[i] = m.prescribed.turbine.intake_offset[i];
		}
		if (m.prescribed.coupled()) {
			std::vector<nk::R> inertia, inverse;
			if (!dec.vec(config, "inertia", inertia, true, 6) || !dec.vec(config, "inverse", inverse, true, 6)) return false;
			for (int i = 0; i < 6; ++i) {
				if (!nk::is_finite(inertia[i]) || !nk::is_finite(inverse[i])) return dec.fail("nonfinite prescribed inertia");
				m.inertia[i] = inertia[i]; m.inverse[i] = inverse[i];
			}
			if (!model.has("inertia") || !nk::stage_snapshot_exact(config["inertia"], model["inertia"])) return dec.fail("prescribed inertia differs from committed model");
			const auto expected_inverse = nk::liquid_inertia_inverse(m.inertia);
			for (int i = 0; i < 6; ++i) if (nk::bits(m.inverse[i].v) != nk::bits(expected_inverse[i].v)) return dec.fail("prescribed inverse inertia differs from reference");
		}
	}
	if (!decode_aero(dec, model, m.aero) || ((!m.liquid.ready || m.liquid.gas) && !m.prescribed.is_turbine() && !decode_prop(dec, prop_geometry, m.prop)) || !decode_gear(dec, static_cast<bool>(config["retractable"]) ? fixed_gear_source(gear) : gear, m.ground.gear)) {
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
	if (!surfaces.is_empty()) m.ground.surfaces.values.assign(surfaces.ptr(), surfaces.ptr() + surfaces.size());
	m.ground.surfaces.valid = nk::surface_table_is_valid(m.ground.surfaces.values);
	m.ground.lake_valid = static_cast<bool>(config["lake_valid"]);
	if (!m.ground.lake_valid) m.ground.lake.present = !lake.is_empty();
	if (m.ground.lake_valid && !decode_lake(dec, lake, m.ground.lake)) {
		return false;
	}
	if (static_cast<bool>(config["retractable"])) {
		if (!model.has("landing_gear") || !nk::stage_snapshot_exact(gear, model["landing_gear"])) return dec.fail("retractable snapshot differs from committed model");
		nk::GearBinding retraction;
		const Dictionary result = retraction.prepare_retractable(gear, m.ground);
		if (!static_cast<bool>(result["ok"])) return dec.fail("invalid retractable gear");
		m.retraction = retraction.model();
	}
	m.soft_hull = static_cast<bool>(config["soft_hull"]);
	if (m.soft_hull && !decode_hull(dec, hull, m.hull, m.liquid.ready || m.glow.ready)) {
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
			L.gear_aux < 0 || int64_t(L.gear_aux) + 1 >= L.aux_size)) return dec.fail("invalid retractable actuator layout");
	const int wash_count = m.wake.transport ? static_cast<int>(m.wake.pieces.size()) : 0;
	L.battery_size = m.electric_source.kind == nk::ElectricBatteryKind::PackEcm ? 9 + 2 * m.electric_source.pack.branches :
		(m.electric_source.kind == nk::ElectricBatteryKind::OcvResistance ? 3 : 0);
	const int source_count = m.electric ? 1 + L.battery_size : (m.liquid.ready ? 1 : (m.glow.ready ? 19 :
		(m.prescribed.coupled() || m.prescribed.continuous_turbine() ? 1 : 0)));
	if (m.glow.ready && m.wake.transport) return dec.fail("glow stage does not transport continuous wake pieces");
	if (L.rotor_index != wash_count || L.wheel_index != wash_count + source_count) {
		return dec.fail("continuous wash layout differs from prepared wake pieces");
	}
	const int64_t ground_value_count = int64_t(L.wheel_index) + L.wheel_count;
	const int64_t continuous_count = ground_value_count + (m.liquid.ready ? 2 : 0);
	if (m.liquid.ready && (!layout_int(dec, layout, "liquid_index", L.liquid_index) ||
			int64_t(L.liquid_index) != ground_value_count)) {
		return dec.fail("invalid liquid inventory layout");
	}
	if (m.ground.gear.contacts.size() > static_cast<size_t>(std::numeric_limits<int>::max())) {
		return dec.fail("gear contact count exceeds index range");
	}
	const int gear_count = static_cast<int>(m.ground.gear.contacts.size());
	if (L.wheel_count < 0 || L.anchor_count < 0 ||
			(L.wheel_count != 0 && L.wheel_count != gear_count) ||
			(L.anchor_count != 0 && L.anchor_count != gear_count) ||
			int64_t(L.anchor_count) * 3 > std::numeric_limits<int>::max() ||
			int64_t(L.anchors) + int64_t(L.anchor_count) * 3 > L.aux_size || int64_t(L.servo) + 2 >= L.aux_size ||
			L.rpm < 0 || L.rpm >= L.aux_size || L.downwash >= L.aux_size || L.servo < 0 || L.anchors < 0 ||
			ground_value_count < 0 || continuous_count > std::numeric_limits<int>::max()) {
		return dec.fail("unsupported or inconsistent layout");
	}
	if (config.has("weather")) {
		Dictionary snapshot;
		if (!dec.dict(config, "weather", snapshot, true) || !dec.number(config, "dt", m.dt, true) ||
				!nk::is_finite(m.dt) || m.dt <= 0.0 || !layout_int(dec, layout, "turbulence", L.turbulence)) {
			return dec.fail("weather needs a finite positive tick dt and turbulence layout");
		}
		if ((m.glow.ready || (m.electric && m.electric_source.kind == nk::ElectricBatteryKind::PackEcm)) && !snapshot.has("temperature_k")) {
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
		if (m.spatial_weather) m.spatial_identity = std::make_shared<const nk::SpatialWeather>(m.spatial);
		if (m.weather.has_turbulence != static_cast<bool>(config["turbulence"]) ||
				m.weather.vertical_atmosphere != static_cast<bool>(config["vertical_atmosphere"]) ||
				(!m.spatial_weather && m.weather.calm == static_cast<bool>(config["not_calm"])) ||
				(m.weather.has_turbulence && (L.turbulence < 4 || int64_t(L.turbulence) + 7 != L.aux_size)) ||
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

// NK-5g: GDScript exp/log/sin/cos are these engine utility functions; calling them keeps the pre-step's results
// the engine's own, bit for bit, whatever libm this library links.
double engine_exp(double x) { return godot::UtilityFunctions::exp(x); }
double engine_log(double x) { return godot::UtilityFunctions::log(x); }
double engine_sin(double x) { return godot::UtilityFunctions::sin(x); }
double engine_cos(double x) { return godot::UtilityFunctions::cos(x); }

bool config_bool(Decoder &dec, const Dictionary &d, const char *key, bool &out) {
	if (!d.has(key) || d[key].get_type() != Variant::BOOL) return dec.fail(std::string(key) + " must be a bool");
	out = static_cast<bool>(d[key]);
	return true;
}

bool config_int(Decoder &dec, const Dictionary &d, const char *key, int64_t &out) {
	if (!d.has(key) || d[key].get_type() != Variant::INT) return dec.fail(std::string(key) + " must be an int");
	out = static_cast<int64_t>(d[key]);
	return true;
}

// NK-5g: StageConfig.pre_step_config_for(session), checked against the prepared stage it extends.
bool decode_pre_step(Decoder &dec, const Dictionary &config, const nk::StageModel &m, nk::PreStepModel &p) {
	p = nk::PreStepModel();
	int64_t flap_aux = -1, flap_input = -1, input_count = 0, turbulence_index = -1, turbulence_seed = 0;
	if (!dec.only(config, "pre_step", {"servo_rate", "rpm_passthrough", "rpm_turbine", "rpm_shaft", "idle_rpm",
				"max_rpm", "rpm_lag", "flaps", "flap_extension_time", "flap_retraction_time", "flap_elevator_mix",
				"flap_aux", "flap_input", "retractable", "input_count", "lake_present", "downwash_length",
				"turbulence", "turbulence_index", "turbulence_sigma", "turbulence_tau", "turbulence_seed",
				"weight_on_wheels_threshold", "turbulence_uniform_denominator", "turbulence_max_uniform"}) ||
			!dec.number(config, "servo_rate", p.servo_rate, true) ||
			!config_bool(dec, config, "rpm_passthrough", p.rpm_passthrough) ||
			!config_bool(dec, config, "rpm_turbine", p.rpm_turbine) || !config_bool(dec, config, "rpm_shaft", p.rpm_shaft) ||
			!config_bool(dec, config, "flaps", p.flaps) || !config_bool(dec, config, "retractable", p.retractable) ||
			!config_bool(dec, config, "lake_present", p.lake_present) || !config_bool(dec, config, "turbulence", p.turbulence) ||
			!config_int(dec, config, "flap_aux", flap_aux) || !config_int(dec, config, "flap_input", flap_input) ||
			!config_int(dec, config, "input_count", input_count) ||
			!config_int(dec, config, "turbulence_index", turbulence_index) ||
			!config_int(dec, config, "turbulence_seed", turbulence_seed) ||
			!dec.number(config, "downwash_length", p.downwash_length, true) ||
			!dec.number(config, "weight_on_wheels_threshold", p.weight_on_wheels_threshold, true)) {
		return false;
	}
	// Propulsion.rpm_step reads prop.idle_rpm, max_rpm and lag; only that branch needs them.
	p.rpm_lag_ready = config.has("idle_rpm") && config.has("max_rpm") && config.has("rpm_lag");
	if (p.rpm_lag_ready && (!dec.number(config, "idle_rpm", p.idle_rpm, true) ||
			!dec.number(config, "max_rpm", p.max_rpm, true) || !dec.number(config, "rpm_lag", p.rpm_lag, true))) {
		return false;
	}
	if (p.flaps && (!dec.number(config, "flap_extension_time", p.flap_extension_time, true) ||
			!dec.number(config, "flap_retraction_time", p.flap_retraction_time, true) ||
			!dec.number(config, "flap_elevator_mix", p.flap_elevator_mix, true))) {
		return false;
	}
	const nk::StageLayout &L = m.layout;
	if (input_count != L.input_count || p.retractable != m.retraction.enabled || (p.retractable && L.gear_aux < 0) ||
			p.flaps != m.aero.flaps.enabled || flap_aux < -1 || flap_aux >= L.aux_size || flap_input < -1 ||
			flap_input >= input_count || (p.flaps && (flap_aux < 0 || flap_input < 0))) {
		return dec.fail("pre-step layout differs from the prepared stage");
	}
	p.flap_aux = static_cast<int>(flap_aux);
	p.flap_input = static_cast<int>(flap_input);
	p.input_count = static_cast<int>(input_count);
	if (p.turbulence) {
		std::vector<nk::R> sigma;
		if (turbulence_index != L.turbulence || turbulence_index < 0 || turbulence_index + 7 != L.aux_size ||
				!dec.vec(config, "turbulence_sigma", sigma, true, 3) || !dec.number(config, "turbulence_tau", p.turbulence_tau, true) ||
				!dec.number(config, "turbulence_uniform_denominator", p.turbulence_uniform_denominator, true) ||
				!dec.number(config, "turbulence_max_uniform", p.turbulence_max_uniform, true)) {
			return dec.fail("pre-step turbulence differs from the prepared weather layout");
		}
		for (int i = 0; i < 3; ++i) {
			if (!nk::is_finite(sigma[i]) || sigma[i].v < 0.0) return dec.fail("turbulence sigma must be finite and nonnegative");
			p.turbulence_sigma[i] = sigma[i];
		}
		// WindTurbulence.step's own refusals: a positive finite tau and a seed in [0, 4294967295].
		if (!nk::is_finite(p.turbulence_tau) || p.turbulence_tau.v <= 0.0 || turbulence_seed < 0 ||
				turbulence_seed > 4294967295LL) {
			return dec.fail("turbulence tau or seed is out of range");
		}
		p.turbulence_index = static_cast<int>(turbulence_index);
		p.turbulence_seed = turbulence_seed;
	}
	p.ready = true;
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
	nk::ConfigurationGuard configuration_guard_;
	std::unique_ptr<nk::sound::Core> sound_core_; // NK-7b: this instance's soundscape core, made on first bind
	std::unique_ptr<nk::sound::GroundCore> ground_core_; // NK-7d: this instance's ground audio core, made on first slot
	std::unique_ptr<nk::sound::MechanicalCore> mechanical_core_; // NK-7e: this instance's mechanical audio core
	std::unique_ptr<nk::sound::RowKeys> row_keys_; // NK-7f: made on the first rows
	nk::MacosDomainGuard macos_domain_guard_;
	bool heli_stage_ready_ = false;
	nk::LakeTerrain no_lake_; // Environment.terrain (the ground-effect height) samples without the lake
	nk::StageModel stage_;
	std::vector<nk::R> wing_wake_ge_; // NK-5a scratch: no allocation per tick
	nk::ContactReach contact_reach_; // NK-5d: proxy bounds of the session's collision world
	std::vector<nk::R> compressions_scratch_; // NK-5e: endpoint compressions without a per-tick allocation
	std::vector<nk::R> facts_aux_;            // NK-5i: the endpoint aux for its air sample
	std::vector<nk::R> facts_scratch_;        // NK-5i: the endpoint facts answer
	nk::PreStepModel pre_model_; // NK-5g: the prepared stage's pre-step (FlightSession._pre_step)
	nk::PreStepScratch pre_scratch_;
	std::vector<double> pre_out_;
	int64_t pre_rng_state_ = 0;
	int64_t pre_step_calls_ = 0, pre_step_answers_ = 0;
	bool stage_ready_ = false;
	nk::TickContext tick_;
	// The binding converts Godot arrays once per call, into storage sized at
	// preparation. The same non-reentrant session owner uses both entry points.
	mutable std::vector<nk::R> continuous_scratch_;
	int64_t stage_calls_ = 0;
	bool stage_timing_ = false;
	double stage_ns_ = 0.0;
	int64_t context_calls_ = 0;
	// NK-6a: the tick integrator's counters and scratch (one non-reentrant tick owner).
	int64_t tick_calls_ = 0, tick_answers_ = 0, tick_faults_ = 0;
	int64_t glow_firing_calls_ = 0, glow_firing_answers_ = 0; // NK-6b
	// NK-6e: the glow installation's bounds for GlowFlight.valid and mass_context.
	struct GlowValidity {
		bool ready = false;
		nk::R max_rpm = 0.0, total_capacity = 0.0, capacity = 0.0, line_capacity = 0.0, unusable = 0.0, cycle = 0.0;
		bool has_line = false, family_ok = false;
	};
	GlowValidity glow_validity_;
	int64_t glow_mass_calls_ = 0;
	std::vector<nk::R> terminal_amounts_;
	std::vector<nk::R> wheel_rows_;
	std::vector<nk::R> wheel_rows_loads_;
	std::vector<nk::R> wheel_rows_rates_;
	int64_t wheel_rows_answers_ = 0;
	bool hull_guard_ready_ = false;
	double hull_guard_crash_depth_ = 0.0;
	std::vector<nk::R> glow_finish_out_;
	int64_t glow_finish_answers_ = 0;
	bool prop_strike_ready_ = false;
	nk::R prop_hub_[3] = {0.0, 0.0, 0.0};
	nk::R prop_axis_[3] = {0.0, 0.0, 0.0};
	double prop_radius_ = 0.0;
	bool liquid_terminal_ready_ = false;
	bool glow_terminal_ready_ = false;
	double glow_terminal_crash_depth_ = 0.0;
	std::vector<double> glow_terminal_stores_;
	double liquid_terminal_crash_depth_ = 0.0;
	int64_t terminal_calls_ = 0;
	int64_t terminal_quiet_ = 0;
	int64_t hull_rows_calls_ = 0;
	int64_t hull_rows_answers_ = 0;
	nk::HullDiagnostics hull_diagnostics_;
	std::vector<nk::R> hull_rows_scratch_;
	nk::R tick_mass_ = 0.0, tick_gravity_ = 0.0;
	nk::R tick_inertia_[6] = {}, tick_inertia_inv_[6] = {};
	nk::StageResult tick_stage_result_;
	nk::TickRk4Scratch tick_rk4_;
	std::vector<nk::R> tick_combined_, tick_first_, tick_next_, tick_event_times_;
	bool rejection_diagnostics_enabled_ = false;
	bool rejection_valid_ = false;
	bool diagnostic_context_ready_ = false;
	nk::GlowStageRejection rejection_;
	// These two COW references pin the exact tick handoff without copying its
	// arrays on every diagnostic tick; detached copies are made only on refusal.
	PackedFloat64Array diagnostic_context_inputs_, diagnostic_context_deflections_;
	PackedFloat64Array rejection_body_, rejection_continuous_, rejection_aux_, rejection_inputs_, rejection_deflections_;
	double rejection_stage_time_ = 0.0, rejection_tick_time_ = 0.0, rejection_brake_ = 0.0, rejection_throttle_ = 0.0;
	bool rejection_engine_running_ = false, rejection_injected_cut_ = false;
	int64_t rejection_stage_call_ = 0, rejection_context_call_ = 0;

	void clear_stage_rejection() {
		if (rejection_valid_) {
			rejection_body_ = PackedFloat64Array();
			rejection_continuous_ = PackedFloat64Array();
			rejection_aux_ = PackedFloat64Array();
			rejection_inputs_ = PackedFloat64Array();
			rejection_deflections_ = PackedFloat64Array();
		}
		rejection_valid_ = false;
		rejection_.code = nk::GlowRejectionCode::None;
	}

	void clear_diagnostic_context() {
		diagnostic_context_ready_ = false;
		diagnostic_context_inputs_ = PackedFloat64Array();
		diagnostic_context_deflections_ = PackedFloat64Array();
	}

	bool rejection_trial_is_valid(const PackedFloat64Array &body, const PackedFloat64Array &continuous, double t) const {
		if (!diagnostic_context_ready_ || !stage_ready_ || !stage_.glow.ready || !tick_.ready || !tick_.power_ready ||
				rejection_.code != nk::GlowRejectionCode::StoppedReverseDrive ||
				(rejection_.origin != nk::GlowRejectionOrigin::Direct && rejection_.origin != nk::GlowRejectionOrigin::FeedEndpoint) ||
				!std::isfinite(rejection_.rpm) || rejection_.rpm != 0.0 ||
				!std::isfinite(rejection_.demand_nm) || !std::isfinite(rejection_.friction_nm) || rejection_.friction_nm < 0.0 ||
				!(rejection_.demand_nm < -rejection_.friction_nm) || !std::isfinite(rejection_.prop_load_torque_nm) ||
				!std::isfinite(rejection_.axial_acceleration_rad_s2) || !std::isfinite(rejection_.rotor_inertia_kg_m2) ||
				rejection_.rotor_inertia_kg_m2 <= 0.0 ||
				(rejection_.origin == nk::GlowRejectionOrigin::FeedEndpoint &&
						(!std::isfinite(rejection_.feed_factor) || (rejection_.feed_factor != 0.0 && rejection_.feed_factor != 2.0))) ||
				body.size() != kStateSize || continuous.size() > kMaxDiagnosticContinuousSize ||
				continuous.size() != stage_.layout.wheel_index + stage_.layout.wheel_count ||
				stage_.layout.rotor_index < 0 || stage_.layout.rotor_index >= continuous.size() ||
				continuous[stage_.layout.rotor_index] != 0.0 || !std::isfinite(t) || t < 0.0 ||
				static_cast<int64_t>(tick_.aux.size()) != stage_.layout.aux_size ||
				tick_.aux.size() > static_cast<size_t>(kMaxDiagnosticAuxSize) || diagnostic_context_inputs_.size() != stage_.layout.input_count ||
				diagnostic_context_inputs_.size() > kMaxDiagnosticInputSize ||
				(diagnostic_context_deflections_.size() != 4 && diagnostic_context_deflections_.size() != 5) ||
				!nk::is_finite(tick_.time_now) || tick_.time_now.v < 0.0 || !nk::is_finite(tick_.brake) ||
				!nk::is_finite(tick_.throttle) || tick_.throttle.v < 0.0 || tick_.throttle.v > 1.0) return false;
		for (int64_t i = 0; i < body.size(); ++i) if (!std::isfinite(body[i])) return false;
		for (int64_t i = 0; i < continuous.size(); ++i) if (!std::isfinite(continuous[i])) return false;
		for (nk::R value : tick_.aux) if (!nk::is_finite(value)) return false;
		for (int64_t i = 0; i < diagnostic_context_inputs_.size(); ++i) if (!std::isfinite(diagnostic_context_inputs_[i])) return false;
		for (int64_t i = 0; i < diagnostic_context_deflections_.size(); ++i) if (!std::isfinite(diagnostic_context_deflections_[i])) return false;
		const double qnorm = body[6] * body[6] + body[7] * body[7] + body[8] * body[8] + body[9] * body[9];
		return std::isfinite(qnorm) && qnorm > nk::kGd1eMinus24;
	}

	void capture_stage_rejection(const PackedFloat64Array &body, const PackedFloat64Array &continuous, double t) {
		rejection_body_ = body.duplicate();
		rejection_continuous_ = continuous.duplicate();
		rejection_aux_ = pack(tick_.aux);
		rejection_inputs_ = diagnostic_context_inputs_.duplicate();
		rejection_deflections_ = diagnostic_context_deflections_.duplicate();
		rejection_stage_time_ = t;
		rejection_tick_time_ = tick_.time_now.v;
		rejection_brake_ = tick_.brake.v;
		rejection_throttle_ = tick_.throttle.v;
		rejection_engine_running_ = tick_.power_enabled;
		rejection_injected_cut_ = tick_.injected_cut;
		rejection_stage_call_ = stage_calls_;
		rejection_context_call_ = context_calls_;
		rejection_valid_ = true;
	}

protected:
	static void _bind_methods() {
		using godot::D_METHOD;
		godot::ClassDB::bind_method(D_METHOD("prepare_configuration_guard", "session", "identity"), &OpenRCNativeKernel::prepare_configuration_guard);
		godot::ClassDB::bind_method(D_METHOD("configuration_guard_matches", "session"), &OpenRCNativeKernel::configuration_guard_matches);
		godot::ClassDB::bind_method(D_METHOD("configuration_guard_profile", "session", "iterations"), &OpenRCNativeKernel::configuration_guard_profile);
		godot::ClassDB::bind_method(D_METHOD("configuration_guard_plan_ready"), &OpenRCNativeKernel::configuration_guard_plan_ready);
		godot::ClassDB::bind_method(D_METHOD("weather_guard_plan_ready"), &OpenRCNativeKernel::weather_guard_plan_ready);
		godot::ClassDB::bind_method(D_METHOD("prepare_macos_domain_guard", "world", "field"), &OpenRCNativeKernel::prepare_macos_domain_guard);
		godot::ClassDB::bind_method(D_METHOD("macos_domain_guard_matches", "world", "field"), &OpenRCNativeKernel::macos_domain_guard_matches);
		godot::ClassDB::bind_method(D_METHOD("prepare_heli_stage", "snapshot", "weather"), &OpenRCNativeKernel::prepare_heli_stage);
		godot::ClassDB::bind_method(D_METHOD("set_heli_tick_context", "tick"), &OpenRCNativeKernel::set_heli_tick_context);
		godot::ClassDB::bind_method(D_METHOD("heli_last_failure"), &OpenRCNativeKernel::heli_last_failure);
		godot::ClassDB::bind_method(D_METHOD("set_glow_context", "throttle", "engine_running", "injected_cut"), &OpenRCNativeKernel::set_glow_context);
		godot::ClassDB::bind_method(D_METHOD("set_stage_rejection_diagnostics", "enabled"), &OpenRCNativeKernel::set_stage_rejection_diagnostics);
		godot::ClassDB::bind_method(D_METHOD("stage_rejection_diagnostic"), &OpenRCNativeKernel::stage_rejection_diagnostic);
		godot::ClassDB::bind_method(D_METHOD("set_preview_context", "body", "continuous", "capture"), &OpenRCNativeKernel::set_preview_context);
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
		godot::ClassDB::bind_method(D_METHOD("stage_wing_wake", "s", "air", "d", "ground_up"),
			&OpenRCNativeKernel::stage_wing_wake);
		godot::ClassDB::bind_method(D_METHOD("prepare_reach_world", "proxies"), &OpenRCNativeKernel::prepare_reach_world);
		godot::ClassDB::bind_method(D_METHOD("clear_reach_world"), &OpenRCNativeKernel::clear_reach_world);
		godot::ClassDB::bind_method(D_METHOD("stage_compressions", "s", "aux"), &OpenRCNativeKernel::stage_compressions);
		godot::ClassDB::bind_method(D_METHOD("stage_wheel_rows", "s", "aux", "steer", "anchors", "speeds", "brake"),
			&OpenRCNativeKernel::stage_wheel_rows);
		godot::ClassDB::bind_method(D_METHOD("wheel_rows_answers"), &OpenRCNativeKernel::wheel_rows_answers);
		godot::ClassDB::bind_method(D_METHOD("state_valid", "s"), &OpenRCNativeKernel::state_valid);
		godot::ClassDB::bind_method(D_METHOD("sound_doppler", "source", "listener", "source_velocity", "listener_velocity",
			"sound_speed"), &OpenRCNativeKernel::sound_doppler);
		godot::ClassDB::bind_method(D_METHOD("sound_targets", "values", "exhaust", "listener", "source"),
			&OpenRCNativeKernel::sound_targets);
		godot::ClassDB::bind_method(D_METHOD("sound_humidity", "relative_humidity_pct", "temperature_k", "pressure_pa"),
			&OpenRCNativeKernel::sound_humidity);
		godot::ClassDB::bind_method(D_METHOD("sound_absorption_cutoff", "path_m", "temperature_k", "pressure_pa", "humidity_pct"),
			&OpenRCNativeKernel::sound_absorption_cutoff);
		godot::ClassDB::bind_method(D_METHOD("sound_screening", "source", "listener", "boxes"), &OpenRCNativeKernel::sound_screening);
		godot::ClassDB::bind_method(D_METHOD("sound_activity", "sun_elevation", "wind_speed", "temperature_c"),
			&OpenRCNativeKernel::sound_activity);
		godot::ClassDB::bind_method(D_METHOD("sound_distance_gain", "distance_m"), &OpenRCNativeKernel::sound_distance_gain);
		godot::ClassDB::bind_method(D_METHOD("sound_core_bind", "voices", "glow_player", "absorption_filter", "screen_filter",
			"trees", "canopies", "kind", "state"), &OpenRCNativeKernel::sound_core_bind);
		godot::ClassDB::bind_method(D_METHOD("sound_core_bind_bank", "players", "layers", "family", "profile_max_rpm", "trim_db",
			"state"), &OpenRCNativeKernel::sound_core_bind_bank);
		godot::ClassDB::bind_method(D_METHOD("sound_core_frame", "snapshot", "delta", "flags"),
			&OpenRCNativeKernel::sound_core_frame);
		godot::ClassDB::bind_method(D_METHOD("sound_core_events", "species_levels"), &OpenRCNativeKernel::sound_core_events);
		godot::ClassDB::bind_method(D_METHOD("sound_core_heard", "snapshot"), &OpenRCNativeKernel::sound_core_heard);
		godot::ClassDB::bind_method(D_METHOD("sound_core_reset", "absorption"), &OpenRCNativeKernel::sound_core_reset);
		godot::ClassDB::bind_method(D_METHOD("sound_core_state"), &OpenRCNativeKernel::sound_core_state);
		godot::ClassDB::bind_method(D_METHOD("sound_core_history_size"), &OpenRCNativeKernel::sound_core_history_size);
		godot::ClassDB::bind_method(D_METHOD("ground_core_open"), &OpenRCNativeKernel::ground_core_open);
		godot::ClassDB::bind_method(D_METHOD("ground_core_bind_slot", "id", "roll", "impact", "roll_offset", "stream_lengths"),
			&OpenRCNativeKernel::ground_core_bind_slot);
		godot::ClassDB::bind_method(D_METHOD("ground_core_observe", "snapshot"), &OpenRCNativeKernel::ground_core_observe);
		godot::ClassDB::bind_method(D_METHOD("ground_core_touchdown_possible"), &OpenRCNativeKernel::ground_core_touchdown_possible);
		godot::ClassDB::bind_method(D_METHOD("ground_core_touchdown_possible_at", "identities", "compressions"),
			&OpenRCNativeKernel::ground_core_touchdown_possible_at);
		godot::ClassDB::bind_method(D_METHOD("ground_core_note_skipped_tick", "tick", "identities", "approaches"),
			&OpenRCNativeKernel::ground_core_note_skipped_tick);
		godot::ClassDB::bind_method(D_METHOD("ground_core_pending_slots", "tick", "paused"),
			&OpenRCNativeKernel::ground_core_pending_slots);
		godot::ClassDB::bind_method(D_METHOD("ground_core_frame", "tick", "paused", "engine_power", "delta", "listener",
			"tick_rate_hz", "seed"), &OpenRCNativeKernel::ground_core_frame);
		godot::ClassDB::bind_method(D_METHOD("ground_core_stop"), &OpenRCNativeKernel::ground_core_stop);
		godot::ClassDB::bind_method(D_METHOD("ground_core_reset"), &OpenRCNativeKernel::ground_core_reset);
		godot::ClassDB::bind_method(D_METHOD("ground_core_release_buses"), &OpenRCNativeKernel::ground_core_release_buses);
		godot::ClassDB::bind_method(D_METHOD("ground_core_accepted_tick"), &OpenRCNativeKernel::ground_core_accepted_tick);
		godot::ClassDB::bind_method(D_METHOD("ground_core_diagnostics"), &OpenRCNativeKernel::ground_core_diagnostics);
		godot::ClassDB::bind_method(D_METHOD("ground_core_state"), &OpenRCNativeKernel::ground_core_state);
		godot::ClassDB::bind_method(D_METHOD("mechanical_core_bind", "event_players", "servo_loop", "servo_loop_length",
			"gear_loop", "gear_loop_length", "takes", "servo_level", "profile_pitch", "counters"),
			&OpenRCNativeKernel::mechanical_core_bind);
		godot::ClassDB::bind_method(D_METHOD("mechanical_core_bind_motion_player", "key", "player"),
			&OpenRCNativeKernel::mechanical_core_bind_motion_player);
		godot::ClassDB::bind_method(D_METHOD("mechanical_core_observe", "snapshot"), &OpenRCNativeKernel::mechanical_core_observe);
		godot::ClassDB::bind_method(D_METHOD("mechanical_core_prepare", "snapshot", "delta"),
			&OpenRCNativeKernel::mechanical_core_prepare);
		godot::ClassDB::bind_method(D_METHOD("mechanical_core_failed"), &OpenRCNativeKernel::mechanical_core_failed);
		godot::ClassDB::bind_method(D_METHOD("mechanical_core_finish"), &OpenRCNativeKernel::mechanical_core_finish);
		godot::ClassDB::bind_method(D_METHOD("mechanical_core_reset"), &OpenRCNativeKernel::mechanical_core_reset);
		godot::ClassDB::bind_method(D_METHOD("mechanical_core_diagnostics"), &OpenRCNativeKernel::mechanical_core_diagnostics);
		godot::ClassDB::bind_method(D_METHOD("mechanical_core_state"), &OpenRCNativeKernel::mechanical_core_state);
		godot::ClassDB::bind_method(D_METHOD("mechanical_core_accepted_events"),
			&OpenRCNativeKernel::mechanical_core_accepted_events);
		godot::ClassDB::bind_method(D_METHOD("audio_unloaded_rows", "state", "arms", "ids", "reference_load"),
			&OpenRCNativeKernel::audio_unloaded_rows);
		godot::ClassDB::bind_method(D_METHOD("audio_source_kinematics", "state", "offset", "axis"),
			&OpenRCNativeKernel::audio_source_kinematics);
		godot::ClassDB::bind_method(D_METHOD("glow_vibration", "geometry", "crank_phase", "omega", "alpha", "firing"),
			&OpenRCNativeKernel::glow_vibration);
		godot::ClassDB::bind_method(D_METHOD("retarded_emission", "times", "positions", "listener", "now", "sound_speed",
			"min_index"), &OpenRCNativeKernel::retarded_emission);
		godot::ClassDB::bind_method(D_METHOD("stage_glow_blade_torques", "rpm", "axial_speed", "density"),
			&OpenRCNativeKernel::stage_glow_blade_torques);
		godot::ClassDB::bind_method(D_METHOD("scenery_state_valid", "s"), &OpenRCNativeKernel::scenery_state_valid);
		godot::ClassDB::bind_method(D_METHOD("arrays_finite", "inputs", "input_size", "aux", "aux_size", "continuous",
			"continuous_size"), &OpenRCNativeKernel::arrays_finite);
		godot::ClassDB::bind_method(D_METHOD("inertia_cached", "inertia", "cache", "inverse"),
			&OpenRCNativeKernel::inertia_cached);
		godot::ClassDB::bind_method(D_METHOD("glow_steady_finish_component", "start", "end", "dt", "terms", "firing"),
			&OpenRCNativeKernel::glow_steady_finish_component);
		godot::ClassDB::bind_method(D_METHOD("glow_finish_answers"), &OpenRCNativeKernel::glow_finish_answers);
		godot::ClassDB::bind_method(D_METHOD("glow_voice_block", "parameters", "harmonics", "state", "frames"),
			&OpenRCNativeKernel::glow_voice_block);
		godot::ClassDB::bind_method(D_METHOD("prepare_hull_guard", "crash_depth"), &OpenRCNativeKernel::prepare_hull_guard);
		godot::ClassDB::bind_method(D_METHOD("stage_hull_guard", "previous", "s"), &OpenRCNativeKernel::stage_hull_guard);
		godot::ClassDB::bind_method(D_METHOD("prepare_prop_strike", "hub", "axis", "radius"),
			&OpenRCNativeKernel::prepare_prop_strike);
		godot::ClassDB::bind_method(D_METHOD("stage_prop_strike_clear", "s"), &OpenRCNativeKernel::stage_prop_strike_clear);
		godot::ClassDB::bind_method(D_METHOD("stage_guard_collapsed", "s", "aux"),
			&OpenRCNativeKernel::stage_guard_collapsed);
		godot::ClassDB::bind_method(D_METHOD("stage_endpoint_facts", "s", "aux", "time_s"),
			&OpenRCNativeKernel::stage_endpoint_facts);
		godot::ClassDB::bind_method(D_METHOD("prepare_pre_step", "config"), &OpenRCNativeKernel::prepare_pre_step);
		godot::ClassDB::bind_method(D_METHOD("pre_step", "aux", "inputs", "dt", "state", "continuous", "time_now",
			"engine_running", "flap_mix_simulator", "deflections", "rng_state"), &OpenRCNativeKernel::pre_step);
		godot::ClassDB::bind_method(D_METHOD("pre_step_rng_state"), &OpenRCNativeKernel::pre_step_rng_state);
		godot::ClassDB::bind_method(D_METHOD("pre_step_stats"), &OpenRCNativeKernel::pre_step_stats);
		godot::ClassDB::bind_method(D_METHOD("pre_step_rng_probe", "state", "count"), &OpenRCNativeKernel::pre_step_rng_probe);
		godot::ClassDB::bind_method(D_METHOD("contact_reach", "previous", "candidate", "hull", "extra_reach", "lake_threshold", "lake_bank"),
			&OpenRCNativeKernel::contact_reach);
		godot::ClassDB::bind_method(D_METHOD("math_probe", "fn", "a", "b", "c"), &OpenRCNativeKernel::math_probe);
		godot::ClassDB::bind_method(D_METHOD("float64_transport", "scalar", "values"), &OpenRCNativeKernel::float64_transport);
		godot::ClassDB::bind_method(D_METHOD("math_control_state"), &OpenRCNativeKernel::math_control_state);
		godot::ClassDB::bind_method(D_METHOD("literal_table"), &OpenRCNativeKernel::literal_table);
		godot::ClassDB::bind_method(D_METHOD("bench_wheels", "s", "steer", "anchors", "speeds", "brake", "iterations"),
			&OpenRCNativeKernel::bench_wheels);
		godot::ClassDB::bind_method(D_METHOD("prepare_stage", "config"), &OpenRCNativeKernel::prepare_stage);
		godot::ClassDB::bind_method(D_METHOD("set_tick_context", "aux", "inputs", "deflections", "time_now"),
			&OpenRCNativeKernel::set_tick_context);
		godot::ClassDB::bind_method(D_METHOD("set_power_context", "throttle", "enabled"), &OpenRCNativeKernel::set_power_context);
		godot::ClassDB::bind_method(D_METHOD("stage", "body", "continuous", "t"), &OpenRCNativeKernel::stage);
		godot::ClassDB::bind_method(D_METHOD("integrate_tick", "model", "state", "continuous", "aux", "t", "dt", "tick",
			"mass", "gravity", "inertia", "inertia_inv"), &OpenRCNativeKernel::integrate_tick);
		godot::ClassDB::bind_method(D_METHOD("tick_stats"), &OpenRCNativeKernel::tick_stats);
		godot::ClassDB::bind_method(D_METHOD("stage_glow_firing", "body", "values", "time_s"),
			&OpenRCNativeKernel::stage_glow_firing);
		godot::ClassDB::bind_method(D_METHOD("prepare_glow_validity", "bounds"), &OpenRCNativeKernel::prepare_glow_validity);
		godot::ClassDB::bind_method(D_METHOD("stage_glow_mass_check", "values", "with_mass"),
			&OpenRCNativeKernel::stage_glow_mass_check);
		godot::ClassDB::bind_method(D_METHOD("stage_hull_scrape_rows", "s", "properties"),
			&OpenRCNativeKernel::stage_hull_scrape_rows);
		godot::ClassDB::bind_method(D_METHOD("prepare_liquid_terminal", "crash_depth", "sample_static_ok"),
			&OpenRCNativeKernel::prepare_liquid_terminal);
		godot::ClassDB::bind_method(D_METHOD("stage_liquid_terminal_quiet", "previous", "s", "usable_before"),
			&OpenRCNativeKernel::stage_liquid_terminal_quiet);
		godot::ClassDB::bind_method(D_METHOD("prepare_glow_terminal", "crash_depth", "stores", "sample_static_ok"),
			&OpenRCNativeKernel::prepare_glow_terminal);
		godot::ClassDB::bind_method(D_METHOD("stage_glow_terminal_quiet", "previous", "s", "total", "line"),
			&OpenRCNativeKernel::stage_glow_terminal_quiet);
		godot::ClassDB::bind_method(D_METHOD("body_loads", "body", "time"), &OpenRCNativeKernel::body_loads);
		godot::ClassDB::bind_method(D_METHOD("body_rotor", "aux"), &OpenRCNativeKernel::body_rotor);
		godot::ClassDB::bind_method(D_METHOD("stage_stats"), &OpenRCNativeKernel::stage_stats);
		godot::ClassDB::bind_method(D_METHOD("reset_stage_stats", "timing"), &OpenRCNativeKernel::reset_stage_stats);
		godot::ClassDB::bind_method(D_METHOD("prop_component", "s", "wind", "rho", "rpm"), &OpenRCNativeKernel::prop_component);
		godot::ClassDB::bind_method(D_METHOD("hull_component", "s"), &OpenRCNativeKernel::hull_component);
		godot::ClassDB::bind_method(D_METHOD("ground_component", "s", "values"), &OpenRCNativeKernel::ground_component);
		godot::ClassDB::bind_method(D_METHOD("legacy_ground_component", "body", "steer", "anchors"), &OpenRCNativeKernel::legacy_ground_component);
		godot::ClassDB::bind_method(D_METHOD("ground_up_component", "s"), &OpenRCNativeKernel::ground_up_component);
		godot::ClassDB::bind_method(D_METHOD("bench_aero", "s", "wind", "rho", "d", "downwash_cl", "ground_up", "iterations"),
			&OpenRCNativeKernel::bench_aero);
	}

public:
	// Diagnostics are explicitly armed before a tick handoff. They do not
	// alter the stage result, evaluator counters or source/solver policy.
	void set_stage_rejection_diagnostics(bool enabled) {
		clear_stage_rejection();
		clear_diagnostic_context();
		rejection_diagnostics_enabled_ = enabled;
	}

	Dictionary stage_rejection_diagnostic() const {
		Dictionary out;
		if (!rejection_diagnostics_enabled_ || !rejection_valid_ ||
				rejection_.code != nk::GlowRejectionCode::StoppedReverseDrive) return out;
		out["code"] = "glow_stopped_reverse_drive";
		out["origin"] = rejection_.origin == nk::GlowRejectionOrigin::FeedEndpoint ? "feed_endpoint" : "direct";
		out["body"] = rejection_body_.duplicate();
		out["continuous"] = rejection_continuous_.duplicate();
		out["stage_time"] = rejection_stage_time_;
		out["aux"] = rejection_aux_.duplicate();
		out["inputs"] = rejection_inputs_.duplicate();
		out["deflections"] = rejection_deflections_.duplicate();
		out["tick_time"] = rejection_tick_time_;
		out["brake"] = rejection_brake_;
		out["throttle"] = rejection_throttle_;
		out["engine_running"] = rejection_engine_running_;
		out["injected_cut"] = rejection_injected_cut_;
		out["stage_call"] = rejection_stage_call_;
		out["context_call"] = rejection_context_call_;
		out["rpm"] = rejection_.rpm;
		out["demand_nm"] = rejection_.demand_nm;
		out["friction_nm"] = rejection_.friction_nm;
		out["prop_load_torque_nm"] = rejection_.prop_load_torque_nm;
		out["axial_acceleration_rad_s2"] = rejection_.axial_acceleration_rad_s2;
		out["rotor_inertia_kg_m2"] = rejection_.rotor_inertia_kg_m2;
		if (rejection_.origin == nk::GlowRejectionOrigin::FeedEndpoint) out["feed_factor"] = rejection_.feed_factor;
		return out;
	}

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
		if (!surfaces.is_empty()) candidate.surfaces.values.assign(surfaces.ptr(), surfaces.ptr() + surfaces.size());
		candidate.surfaces.valid = nk::surface_table_is_valid(candidate.surfaces.values);
		candidate.lake_valid = lake_valid;
		if (!lake_valid) candidate.lake.present = !lake.is_empty();
		const bool ok = decode_gear(dec, fixed_gear_source(gear), candidate.gear) && (!lake_valid || decode_lake(dec, lake, candidate.lake));
		gear_ = nk::GearBinding();
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
		std::vector<double> values;
		if (!surfaces.is_empty()) values.assign(surfaces.ptr(), surfaces.ptr() + surfaces.size());
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

	PackedFloat64Array legacy_ground_component(const PackedFloat64Array &body, double steer, const PackedFloat64Array &anchors) const {
		if (!ground_ready_ || !read_state(body)) return PackedFloat64Array();
		nk::R state[kStateSize];
		load(body, state);
		std::vector<nk::R> values;
		nk::legacy_ground_loads(state, ground_, steer, anchors.ptr(), static_cast<int>(anchors.size()), values);
		return pack(values);
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
		wake_ = nk::WakeBinding();
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
		wake_ = nk::WakeBinding();
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

	Dictionary prepare_configuration_guard(godot::Object *session, godot::Object *identity) { return configuration_guard_.prepare_configuration_guard(session, identity); }
	bool configuration_guard_matches(godot::Object *session) const { return configuration_guard_.configuration_guard_matches(session); }
	Dictionary configuration_guard_profile(godot::Object *session, int64_t iterations) const { return configuration_guard_.profile(session, iterations); }
	bool configuration_guard_plan_ready() const { return configuration_guard_.plan_ready(); }
	Dictionary prepare_macos_domain_guard(const Dictionary &world, const Dictionary &field) { return macos_domain_guard_.prepare(world, field); }
	bool macos_domain_guard_matches(const Dictionary &world, const Dictionary &field) const { return macos_domain_guard_.matches(world, field); }
	Dictionary prepare_heli_stage(const Dictionary &snapshot, const Dictionary &weather) {
		if (rejection_diagnostics_enabled_) {
			clear_stage_rejection();
			clear_diagnostic_context();
		}
		heli_stage_ready_ = false;
		stage_ready_ = false;
		tick_.ready = false;
		const Dictionary result = helicopter_.prepare_heli_stage(snapshot, weather);
		heli_stage_ready_ = helicopter_.stage_ready();
		return result;
	}
	bool set_heli_tick_context(const Dictionary &tick) {
		if (rejection_diagnostics_enabled_) {
			clear_stage_rejection();
			clear_diagnostic_context();
		}
		++context_calls_;
		return heli_stage_ready_ && helicopter_.set_heli_tick_context(tick);
	}
	String heli_last_failure() const { return helicopter_.heli_last_failure(); }
	Dictionary prepare_weather_guard(godot::Object *session, godot::Object *identity) { return weather_guard_.prepare_weather_guard(session, identity); }
	bool weather_guard_matches(godot::Object *session) const { return weather_guard_.weather_guard_matches(session); }
	bool weather_guard_plan_ready() const { return weather_guard_.plan_ready(); }
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
		if (!ground_ready_) {
			gear_ = nk::GearBinding();
			return nk::spatial_binding_failure("ground not prepared");
		}
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

	// NK-5a: aero.gd wing_wake_velocity for flight_session.gd _pre_step's downwash lag, with the prepared stage's
	// AeroModel (decode_aero, as the component oracle's), the caller's own air_data(s) values [v_air x, y, z, V, alpha,
	// beta, qbar] (datum or spatial; the reference reads only v_air) and _deflections(aux). Same arithmetic as
	// aero_component case 6. NaN when the stage or an input is unusable: the caller then evaluates the reference.
	// NK-5d: copy the bounds of the session's collision-world proxies (six numbers each) for contact_reach.
	// Anything other than numeric bounds refuses and clears, so contact_reach then proves nothing for scenery.
	bool prepare_reach_world(const godot::Array &proxies) {
		static const godot::StringName keys[6] = {"bounds_north_min", "bounds_north_max", "bounds_east_min",
			"bounds_east_max", "bounds_down_min", "bounds_down_max"};
		contact_reach_.clear();
		const int64_t count = proxies.size();
		if (count <= 0 || count > nk::ContactReach::kMaxProxies) return false;
		std::vector<double> bounds;
		bounds.reserve(static_cast<size_t>(count) * 6);
		for (int64_t i = 0; i < count; ++i) {
			const godot::Variant item = proxies[i];
			if (item.get_type() != godot::Variant::DICTIONARY) return false;
			const godot::Dictionary proxy = item;
			for (const godot::StringName &key : keys) {
				const godot::Variant value = proxy.get(key, godot::Variant());
				if (value.get_type() != godot::Variant::FLOAT && value.get_type() != godot::Variant::INT) return false;
				bounds.push_back(static_cast<double>(value));
			}
		}
		return contact_reach_.prepare(bounds);
	}

	void clear_reach_world() { contact_reach_.clear(); }

	// NK-5d: bit 1 = no collision proxy can be reached this tick, bit 2 = the lake cannot be reached. 0 = no proof.
	int64_t contact_reach(const PackedFloat64Array &previous, const PackedFloat64Array &candidate,
			const PackedFloat64Array &hull, double extra_reach, double lake_threshold, const PackedFloat64Array &lake_bank) const {
		if (previous.size() != kStateSize || candidate.size() != kStateSize || hull.is_empty()) return 0;
		if (!lake_bank.is_empty() && lake_bank.size() != 4) return 0;
		return contact_reach_.reach_clear(previous.ptr(), candidate.ptr(), hull.ptr(), hull.size(), extra_reach, lake_threshold,
			lake_bank.is_empty() ? nullptr : lake_bank.ptr());
	}

	// NK-5g: prepare FlightSession._pre_step over the prepared stage (StageConfig.pre_step_config_for). A refusal
	// leaves the pre-step unprepared and the session evaluates the reference.
	Dictionary prepare_pre_step(const Dictionary &config) {
		Decoder dec;
		nk::PreStepModel candidate;
		const bool ok = stage_ready_ && decode_pre_step(dec, config, stage_, candidate);
		pre_model_ = ok ? candidate : nk::PreStepModel();
		if (ok) {
			pre_scratch_.aux.reserve(static_cast<size_t>(stage_.layout.aux_size));
			pre_scratch_.anchors.reserve(static_cast<size_t>(stage_.layout.anchor_count) * 3);
			pre_scratch_.compressions.reserve(stage_.ground.gear.contacts.size());
			pre_out_.reserve(static_cast<size_t>(stage_.layout.aux_size));
		}
		Dictionary out;
		out["ok"] = ok;
		out["error"] = stage_ready_ ? String(dec.error.c_str()) : String("no prepared stage");
		return out;
	}

	// NK-5g: FlightSession._pre_step(aux, inputs, dt) from the committed sim.state, sim.continuous and sim.time(),
	// engine_running, the manual flap mix owner, _deflections(aux) (empty without a downwash lag) and sim.modes[1].
	// Empty refuses: the session evaluates the reference. After an answer, pre_step_rng_state() is sim.modes[1].
	PackedFloat64Array pre_step(const PackedFloat64Array &aux, const PackedFloat64Array &inputs, double dt,
			const PackedFloat64Array &state, const PackedFloat64Array &continuous, double time_now, bool engine_running,
			bool flap_mix_simulator, const PackedFloat64Array &deflections, int64_t rng_state) {
		++pre_step_calls_;
		if (!stage_ready_ || !pre_model_.ready || !read_state(state)) return PackedFloat64Array();
		nk::PreStepInput in;
		in.aux = aux.ptr();
		in.aux_size = static_cast<int>(aux.size());
		in.inputs = inputs.ptr();
		in.input_size = static_cast<int>(inputs.size());
		in.dt = dt;
		in.state = state.ptr();
		in.state_size = static_cast<int>(state.size());
		in.continuous = continuous.ptr();
		in.continuous_size = static_cast<int>(continuous.size());
		in.time_now = time_now;
		in.engine_running = engine_running;
		in.flap_mix_simulator = flap_mix_simulator;
		in.rng_state = rng_state;
		if (!deflections.is_empty()) {
			if (!read_deflections(deflections, in.deflections)) return PackedFloat64Array();
			in.has_deflections = true;
		}
		static const nk::PreStepEngine engine{engine_exp, engine_log, engine_sin, engine_cos};
		int64_t next_state = rng_state;
		if (!nk::pre_step(stage_, pre_model_, in, engine, pre_scratch_, pre_out_, next_state)) return PackedFloat64Array();
		pre_rng_state_ = next_state;
		++pre_step_answers_;
		PackedFloat64Array out;
		out.resize(static_cast<int64_t>(pre_out_.size()));
		double *dst = out.ptrw();
		for (size_t i = 0; i < pre_out_.size(); ++i) dst[i] = pre_out_[i];
		return out;
	}

	int64_t pre_step_rng_state() const { return pre_rng_state_; }

	Dictionary pre_step_stats() const {
		Dictionary out;
		out["ready"] = pre_model_.ready;
		out["calls"] = pre_step_calls_;
		out["answers"] = pre_step_answers_;
		return out;
	}

	// NK-5g test probe: `count` WindTurbulence randi() draws from a RandomNumberGenerator restored to the raw `state`
	// (any seed: the seed only fixes the default stream), then the raw state read back.
	godot::PackedInt64Array pre_step_rng_probe(int64_t state, int64_t count) const {
		godot::PackedInt64Array out;
		if (count < 0 || count > 1000000) return out;
		nk::PreStepPcg32 rng(state);
		for (int64_t i = 0; i < count; ++i) out.push_back(rng.randi());
		out.push_back(rng.raw_state());
		return out;
	}

	// NK-5e: flight_session.gd gear_compressions(s) at the accepted endpoint, for its contact observer: the stage's
	// ground (posed by this tick's context when retractable) through nk::wheels_compressions, as the component
	// oracle's. Empty when the stage, tick context, state (Simulation.state_is_valid), endpoint gear aux or ground
	// (empty or invalid table, invalid lake) cannot reproduce the reference's terrain branch: the caller then
	// evaluates the reference.
	// The ground context of the accepted endpoint s with its aux (NK-5e): a finite state with a usable quaternion, the
	// tick context's retraction pose when both gear values carry its bits, and a non-empty valid table and lake.
	// nullptr refuses.
	const nk::GroundContext *endpoint_ground(const PackedFloat64Array &s, const PackedFloat64Array &aux) const {
		if (!stage_ready_ || !tick_.ready || !read_state(s) || stage_.layout.wheel_count <= 0) return nullptr;
		const double *body = s.ptr();
		for (int i = 0; i < kStateSize; ++i) {
			if (!std::isfinite(body[i])) return nullptr;
		}
		const double norm_sq = body[6] * body[6] + body[7] * body[7] + body[8] * body[8] + body[9] * body[9];
		if (!std::isfinite(norm_sq) || !(norm_sq > nk::kGd1eMinus24)) return nullptr; // GDScript 1e-24
		const nk::GroundContext *ground = &stage_.ground;
		if (stage_.retraction.enabled) {
			// The endpoint pose is the tick context's only when both gear values carry the same bits it validated.
			const int64_t index = stage_.layout.gear_aux;
			if (aux.size() != static_cast<int64_t>(tick_.aux.size()) || index < 0 || index + 1 >= aux.size()) {
				return nullptr;
			}
			for (int64_t i = index; i <= index + 1; ++i) {
				const double expected = tick_.aux[static_cast<size_t>(i)].v;
				if (std::memcmp(&aux.ptr()[i], &expected, sizeof(double)) != 0) return nullptr;
			}
			ground = &tick_.posed_ground;
		}
		// An empty table (valid here) may send the reference to its flat-ground formula, whose -0.0 can differ.
		if (ground->gear.empty || ground->surfaces.values.empty() || !ground->surfaces.valid || !ground->lake_valid) {
			return nullptr;
		}
		return ground;
	}

	PackedFloat64Array stage_compressions(const PackedFloat64Array &s, const PackedFloat64Array &aux) {
		const nk::GroundContext *ground = endpoint_ground(s, aux);
		if (ground == nullptr) return PackedFloat64Array();
		nk::R state[kStateSize];
		load(s, state);
		if (!nk::wheels_compressions(state, *ground, compressions_scratch_)) return PackedFloat64Array();
		return pack(compressions_scratch_);
	}

	// NK-6m: the glow voice's per-sample loop (nk_glow_voice.hpp), audio only. parameters in GlowVoiceParameter order,
	// harmonics as the angles then the weights, state in GlowVoiceState order. Returns [PCM, state + scheduled_any (1/0)],
	// or [] for malformed input.
	Array glow_voice_block(const PackedFloat64Array &parameters, const PackedFloat64Array &harmonics,
			const PackedFloat64Array &state, int64_t frames) const {
		Array out;
		if (parameters.size() != nk::kGvParameterCount || harmonics.size() % 2 != 0 || harmonics.size() > 64 ||
				state.size() != nk::kGvStateCount || frames < 0 || frames > (int64_t(1) << 20)) return out;
		godot::PackedVector2Array pcm;
		pcm.resize(frames);
		double next[nk::kGvStateCount];
		for (int i = 0; i < nk::kGvStateCount; ++i) next[i] = state[i];
		const int64_t count = harmonics.size() / 2;
		const bool any = nk::glow_voice_block(parameters.ptr(), harmonics.ptr(), harmonics.ptr() + count, count, next, frames,
			frames > 0 ? reinterpret_cast<float *>(pcm.ptrw()) : nullptr);
		PackedFloat64Array next_state;
		next_state.resize(nk::kGvStateCount + 1);
		for (int i = 0; i < nk::kGvStateCount; ++i) next_state[i] = next[i];
		next_state[nk::kGvStateCount] = any ? 1.0 : 0.0;
		out.append(pcm);
		out.append(next_state);
		return out;
	}

	// NK-6k: FlightSession._prop_disc (HullContact.prop_disc of the model's propulsion): hub and unit axis in body FRD
	// and radius. Each installation prepares its own.
	bool prepare_prop_strike(const PackedFloat64Array &hub, const PackedFloat64Array &axis, double radius) {
		prop_strike_ready_ = stage_ready_ && !heli_stage_ready_ && hub.size() == 3 && axis.size() == 3 &&
			std::isfinite(radius) && radius > 0.0;
		for (int i = 0; prop_strike_ready_ && i < 3; ++i) {
			if (!std::isfinite(hub[i]) || !std::isfinite(axis[i])) prop_strike_ready_ = false;
			prop_hub_[i] = hub[i];
			prop_axis_[i] = axis[i];
		}
		prop_radius_ = radius;
		return prop_strike_ready_;
	}

	// NK-6k: 1 when HullContact.prop_disc_depth(s, disc, the stage's lake, any finite time).depth <= 0, so
	// FlightSession._check_prop_strike finds no strike: the lake is absent, or valid with the disc's lowest point outside
	// the bank bounds expanded by sample_covered_terrain_validated's margin and the disc, padded as _disc_near_lake pads
	// it, horizontally clear of them. The reference then keeps its flat-datum depth, computed here in its order.
	// -1 for the reference otherwise, strikes included.
	int64_t stage_prop_strike_clear(const PackedFloat64Array &s) {
		if (!prop_strike_ready_ || heli_stage_ready_ || !stage_ready_ || !read_state(s) || !stage_.ground.lake_valid) return -1;
		const double *v = s.ptr();
		for (int i = 0; i < 10; ++i) {
			if (!std::isfinite(v[i])) return -1;
		}
		const nk::R q[4] = {v[6], v[7], v[8], v[9]};
		const nk::R w = q[0], x = q[1], y = q[2], z = q[3];
		// hull_contact.gd _down_row, then prop_disc_depth's lowest rim point.
		const nk::R down[3] = {2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)};
		const nk::R *a = prop_axis_;
		const nk::R along = down[0] * a[0] + down[1] * a[1] + down[2] * a[2];
		const nk::R p[3] = {down[0] - along * a[0], down[1] - along * a[1], down[2] - along * a[2]};
		const nk::R p_len = nk::sqrt_(p[0] * p[0] + p[1] * p[1] + p[2] * p[2]);
		nk::R lowest[3] = {prop_hub_[0], prop_hub_[1], prop_hub_[2]};
		if (p_len.v > 1.0e-9) {
			const nk::R k = nk::R(prop_radius_) / p_len;
			for (int i = 0; i < 3; ++i) lowest[i] = lowest[i] + p[i] * k;
		}
		const nk::R depth = nk::R(v[2]) + down[0] * lowest[0] + down[1] * lowest[1] + down[2] * lowest[2];
		if (!(depth.v <= 0.0)) return -1;
		const nk::LakeTerrain &lake = stage_.ground.lake;
		if (!lake.present) return 1;
		const double *b = lake.bank_aabb;
		const double margin = 0.025; // LakeSurface.SAMPLE_EPSILON_M
		const std::array<nk::R, 3> point = nk::q_rotate3(q, lowest);
		const nk::R north = nk::R(v[0]) + point[0];
		const nk::R east = nk::R(v[1]) + point[1];
		if (!(north.v < b[0] - margin || north.v > b[1] + margin || east.v < b[2] - margin || east.v > b[3] + margin)) {
			return -1;
		}
		const std::array<nk::R, 3> hub = nk::q_rotate3(q, prop_hub_);
		const nk::R hub_north = nk::R(v[0]) + hub[0];
		const nk::R hub_east = nk::R(v[1]) + hub[1];
		const nk::R qq = w * w + x * x + y * y + z * z;
		const nk::R pad = nk::R(prop_radius_) * (1.0 + 4.0 * qq) + 0.001;
		const bool clear = (hub_north + pad).v < b[0] || (hub_north - pad).v > b[1] || (hub_east + pad).v < b[2] ||
			(hub_east - pad).v > b[3];
		return clear ? 1 : -1;
	}

	// NK-6j: FlightSession.gear_collapsed(s) for the pre-tick guard, from the endpoint compressions of the tick context
	// the guarded pre-step installed (stage_compressions refuses whatever it cannot answer exactly): 1 collapsed, 0 not,
	// -1 for the reference.
	int64_t stage_guard_collapsed(const PackedFloat64Array &s, const PackedFloat64Array &aux) {
		const PackedFloat64Array compressions = stage_compressions(s, aux);
		if (compressions.is_empty()) return -1;
		const nk::GroundContext &ground = stage_.retraction.enabled ? tick_.posed_ground : stage_.ground;
		if (static_cast<int64_t>(ground.gear.contacts.size()) != compressions.size()) return -1;
		for (int64_t i = 0; i < compressions.size(); ++i) {
			const double limit = ground.gear.contacts[static_cast<size_t>(i)].max_compression.v;
			if (std::isnan(limit)) return -1;
			if (compressions[i] > limit) return 1;
		}
		return 0;
	}

	// NK-6o: Wheels.evaluate(s, posed gear, steer, surfaces, anchors, speeds, brake, diagnostics, lake)'s diagnostics and
	// frames for GroundAudioModel.snapshot_contacts, at the endpoint whose ground endpoint_ground accepts: [1, n, n rows
	// of nk::kWheelRowSize], [0] where every wheel is beyond the terrain's height bound (no diagnostics), or [] for the
	// reference (another wheel count, a nonfinite input, the reference's failure shape).
	PackedFloat64Array stage_wheel_rows(const PackedFloat64Array &s, const PackedFloat64Array &aux, double steer,
			const PackedFloat64Array &anchors, const PackedFloat64Array &speeds, double brake) {
		const nk::GroundContext *ground = endpoint_ground(s, aux);
		if (ground == nullptr || speeds.size() != static_cast<int64_t>(ground->gear.contacts.size()) ||
				!std::isfinite(steer) || !std::isfinite(brake)) return PackedFloat64Array();
		for (int64_t i = 0; i < anchors.size(); ++i) {
			if (!std::isfinite(anchors[i])) return PackedFloat64Array();
		}
		for (int64_t i = 0; i < speeds.size(); ++i) {
			if (!std::isfinite(speeds[i])) return PackedFloat64Array();
		}
		nk::R state[kStateSize];
		load(s, state);
		if (!nk::wheels_evaluate(state, *ground, steer, anchors.ptr(), static_cast<int>(anchors.size()), speeds.ptr(),
				static_cast<int>(speeds.size()), brake, wheel_rows_loads_, wheel_rows_rates_, &wheel_rows_)) {
			return PackedFloat64Array();
		}
		++wheel_rows_answers_;
		if (wheel_rows_.empty()) return PackedFloat64Array({0.0});
		const int64_t count = static_cast<int64_t>(wheel_rows_.size()) / nk::kWheelRowSize;
		if (count != speeds.size()) return PackedFloat64Array();
		PackedFloat64Array out;
		out.resize(2 + static_cast<int64_t>(wheel_rows_.size()));
		double *o = out.ptrw();
		o[0] = 1.0;
		o[1] = static_cast<double>(count);
		for (size_t i = 0; i < wheel_rows_.size(); ++i) o[2 + i] = wheel_rows_[i].v;
		return out;
	}

	int64_t wheel_rows_answers() const { return wheel_rows_answers_; }

	// F5b: glow/propeller.gd's torque at (rpm, axial speed) and at (rpm, 0) from the prepared glow stage's blade model,
	// for flight audio's shaft load (Propulsion.thrust_torque()[1] and prop_torque()); NaN where the evaluator refuses
	// the query, empty without a glow stage. A pure function of the prepared installation and its arguments.
	PackedFloat64Array stage_glow_blade_torques(double rpm, double axial_speed, double density) const {
		if (heli_stage_ready_ || !stage_ready_ || !stage_.glow.ready) return PackedFloat64Array();
		const nk::GlowBladePoint moving = nk::glow_blade_evaluate(stage_.glow.blade, rpm, axial_speed, density);
		const nk::GlowBladePoint still = nk::glow_blade_evaluate(stage_.glow.blade, rpm, 0.0, density);
		PackedFloat64Array out;
		out.resize(2);
		out[0] = moving.ok ? moving.torque_nm.v : nk::kNan;
		out[1] = still.ok ? still.torque_nm.v : nk::kNan;
		return out;
	}

	// NK-7a: the soundscape model's pure functions (nk_soundscape.hpp), for flight audio and their parity tests.
	double sound_doppler(const godot::Vector3 &source, const godot::Vector3 &listener, const godot::Vector3 &source_velocity,
			const godot::Vector3 &listener_velocity, double sound_speed) const {
		return nk::sound::doppler(source, listener, source_velocity, listener_velocity, sound_speed).v;
	}

	// values: [rpm, max_rpm, load, throttle, airspeed, wind_speed, running (1/0), blades, sun_elevation, kind
	// (TargetKind), jet_velocity, jet_velocity_max] -> [motor_gain, prop_gain, motor_pitch, prop_pitch, air_gain, wind_low,
	// wind_high, foliage, bird_activity, exhaust_angle_deg]; empty for a malformed request.
	PackedFloat64Array sound_targets(const PackedFloat64Array &values, const godot::Vector3 &exhaust,
			const godot::Vector3 &listener, const godot::Vector3 &source) const {
		PackedFloat64Array out;
		if (values.size() != 12) return out;
		const double *v = values.ptr();
		const nk::sound::Targets t = nk::sound::targets(v[0], v[1], v[2], v[3], v[4], v[5], v[6] != 0.0, v[7], v[8],
			static_cast<int>(v[9]), v[1], v[10], v[11], exhaust, listener, source);
		out.resize(10);
		out[0] = t.motor_gain.v; out[1] = t.prop_gain.v; out[2] = t.motor_pitch.v; out[3] = t.prop_pitch.v;
		out[4] = t.air_gain.v; out[5] = t.wind_low.v; out[6] = t.wind_high.v; out[7] = t.foliage.v;
		out[8] = t.bird_activity.v; out[9] = t.exhaust_angle_deg.v;
		return out;
	}

	double sound_humidity(double relative_humidity_pct, double temperature_k, double pressure_pa) const {
		return nk::sound::humidity_molar_pct(relative_humidity_pct, temperature_k, pressure_pa).v;
	}

	double sound_absorption_cutoff(double path_m, double temperature_k, double pressure_pa, double humidity_pct) const {
		return nk::sound::absorption_cutoff_hz(path_m, temperature_k, pressure_pa, humidity_pct).v;
	}

	double sound_screening(const godot::Vector3 &source, const godot::Vector3 &listener, const godot::PackedFloat32Array &boxes) const {
		return nk::sound::screening(source, listener, boxes.ptr(), boxes.size() / 6).v;
	}

	PackedFloat64Array sound_activity(double sun_elevation, double wind_speed, double temperature_c) const {
		nk::R values[5];
		nk::sound::wildlife_activity(sun_elevation, wind_speed, temperature_c, values);
		PackedFloat64Array out;
		out.resize(5);
		for (int i = 0; i < 5; ++i) out[i] = values[i].v;
		return out;
	}

	double sound_distance_gain(double distance_m) const { return nk::sound::distance_gain(distance_m).v; }

	// NK-7b: audio/soundscape.gd update_sound (nk_soundscape_core.hpp). bind takes the soundscape's fourteen voices, its
	// glow player (or null), both bus filters, trees, canopy boxes [px, py, pz, sx, sy, sz], the targets kind and the
	// mix state (sound_core_state's layout); false leaves the core unbound. frame and events return empty when they
	// refuse; nothing changes then.
	bool sound_core_bind(const godot::Array &voices, const godot::Variant &glow_player, const godot::Variant &absorption_filter,
			const godot::Variant &screen_filter, const godot::PackedVector3Array &trees, const godot::PackedFloat32Array &canopies,
			int64_t kind, const PackedFloat64Array &state) {
		if (!sound_core_) sound_core_ = std::make_unique<nk::sound::Core>();
		return sound_core_->bind(voices, glow_player, absorption_filter, screen_filter, trees, canopies, kind, state);
	}

	// NK-7c: the recorded powertrain bank (nk_soundscape_core.hpp Core::bind_bank), after sound_core_bind.
	bool sound_core_bind_bank(const godot::Array &players, const PackedFloat64Array &layers, int64_t family,
			double profile_max_rpm, double trim_db, const PackedFloat64Array &state) {
		return sound_core_ && sound_core_->bind_bank(players, layers, family, profile_max_rpm, trim_db, state);
	}

	PackedFloat64Array sound_core_frame(const godot::Dictionary &snapshot, double delta, int64_t flags) {
		return sound_core_ ? sound_core_->frame(snapshot, delta, flags) : PackedFloat64Array();
	}

	PackedFloat64Array sound_core_events(const PackedFloat64Array &species_levels) {
		return sound_core_ ? sound_core_->events(species_levels) : PackedFloat64Array();
	}

	godot::Dictionary sound_core_heard(const godot::Dictionary &snapshot) const {
		return sound_core_ ? sound_core_->heard(snapshot) : snapshot;
	}

	void sound_core_reset(bool absorption) {
		if (sound_core_) sound_core_->reset(absorption);
	}

	PackedFloat64Array sound_core_state() const {
		return sound_core_ ? sound_core_->state() : PackedFloat64Array();
	}

	int64_t sound_core_history_size() const { return sound_core_ ? sound_core_->history_size() : 0; }

	// NK-7d: audio/ground_audio.gd in accepted-tick mode (nk_ground_audio_core.hpp). open makes a fresh core and
	// answers whether the engine binds it needs exist; slots then bind in _slot_for's order.
	bool ground_core_open() {
		ground_core_ = std::make_unique<nk::sound::GroundCore>();
		return nk::sound::engine_binds().ok;
	}
	bool ground_core_bind_slot(const godot::String &id, const godot::Array &roll, const godot::Variant &impact, double roll_offset,
			const PackedFloat64Array &stream_lengths) {
		return ground_core_ && ground_core_->bind_slot(id, roll, impact, roll_offset, stream_lengths);
	}
	bool ground_core_observe(const godot::Dictionary &snapshot) { return ground_core_ && ground_core_->observe(snapshot); }
	bool ground_core_touchdown_possible() const { return !ground_core_ || ground_core_->touchdown_possible(); }
	bool ground_core_touchdown_possible_at(const PackedStringArray &identities, const PackedFloat64Array &compressions) const {
		return !ground_core_ || ground_core_->touchdown_possible_at(identities, compressions);
	}
	void ground_core_note_skipped_tick(int64_t tick, const PackedStringArray &identities, const PackedFloat64Array &approaches) {
		if (ground_core_) ground_core_->note_skipped_tick(tick, identities, approaches);
	}
	godot::Array ground_core_pending_slots(int64_t tick, bool paused) const {
		return ground_core_ ? ground_core_->pending_slots(tick, paused) : godot::Array();
	}
	PackedFloat64Array ground_core_frame(int64_t tick, bool paused, double engine_power, double delta,
			const godot::Vector3 &listener, double tick_rate_hz, bool seed) {
		return ground_core_ ? ground_core_->frame(tick, paused, engine_power, delta, listener, tick_rate_hz, seed)
			: PackedFloat64Array();
	}
	void ground_core_stop() { if (ground_core_) ground_core_->stop(); }
	void ground_core_reset() { if (ground_core_) ground_core_->reset(); }
	void ground_core_release_buses() { if (ground_core_) ground_core_->release_buses(); }
	int64_t ground_core_accepted_tick() const { return ground_core_ ? ground_core_->accepted_tick() : -1; }
	godot::Dictionary ground_core_diagnostics() const { return ground_core_ ? ground_core_->diagnostics() : godot::Dictionary(); }
	godot::Array ground_core_state() const { return ground_core_ ? ground_core_->state() : godot::Array(); }

	// NK-7e: audio/mechanical_audio.gd in accepted-tick mode (nk_mechanical_audio_core.hpp). bind makes a fresh core.
	bool mechanical_core_bind(const godot::Array &event_players, const godot::Variant &servo_loop, double servo_loop_length,
			const godot::Variant &gear_loop, double gear_loop_length, const godot::Array &takes, double servo_level,
			double profile_pitch, const godot::PackedInt64Array &counters) {
		mechanical_core_ = std::make_unique<nk::sound::MechanicalCore>();
		return mechanical_core_->bind(event_players, servo_loop, servo_loop_length, gear_loop, gear_loop_length, takes,
			servo_level, profile_pitch, counters);
	}
	bool mechanical_core_bind_motion_player(const godot::String &key, const godot::Variant &player) {
		return mechanical_core_ && mechanical_core_->bind_motion_player(key, player);
	}
	bool mechanical_core_observe(const godot::Dictionary &snapshot) {
		return mechanical_core_ && mechanical_core_->observe(snapshot);
	}
	godot::Array mechanical_core_prepare(const godot::Dictionary &snapshot, double delta) {
		return mechanical_core_ ? mechanical_core_->prepare(snapshot, delta) : godot::Array();
	}
	bool mechanical_core_failed() const { return !mechanical_core_ || mechanical_core_->failed(); }
	bool mechanical_core_finish() { return mechanical_core_ && mechanical_core_->finish(); }
	void mechanical_core_reset() { if (mechanical_core_) mechanical_core_->reset(); }
	godot::Dictionary mechanical_core_diagnostics() const {
		return mechanical_core_ ? mechanical_core_->diagnostics() : godot::Dictionary();
	}
	godot::Array mechanical_core_state() const { return mechanical_core_ ? mechanical_core_->state() : godot::Array(); }
	// NK-7f: ground_audio_model.gd _unloaded_rows and flight_audio.gd snapshot's source kinematics (nk_audio_rows.hpp).
	godot::Array audio_unloaded_rows(const PackedFloat64Array &state, const PackedFloat64Array &arms, const PackedStringArray &ids,
			double reference_load) {
		if (!row_keys_) row_keys_ = std::make_unique<nk::sound::RowKeys>();
		return nk::sound::unloaded_rows(*row_keys_, state, arms, ids, reference_load);
	}
	PackedFloat64Array audio_source_kinematics(const PackedFloat64Array &state, const PackedFloat64Array &offset,
			const PackedFloat64Array &axis) const {
		return nk::sound::source_kinematics(state, offset, axis);
	}

	godot::Array mechanical_core_accepted_events() const {
		return mechanical_core_ ? mechanical_core_->accepted_events() : godot::Array();
	}

	// NK-6s: physics/glow/vibration.gd evaluate's numbers for a validated geometry [crank radius, rod, reciprocating
	// mass, cosine 1x, cosine 2x, cycle revolutions]: [ok (1/0), phase, source force, 1x cosine, 1x sine, 2x cosine,
	// 2x sine, 1x peak, 2x peak, opportunity Hz, mean fire rate Hz], in its operation order. 0 wherever evaluate fails
	// (the caller then runs it for the exact failure). Presentation only (flight audio's glow voice).
	PackedFloat64Array glow_vibration(const PackedFloat64Array &geometry, double crank_phase, double omega, double alpha,
			double firing) const {
		PackedFloat64Array out;
		out.resize(11);
		out.fill(0.0);
		if (geometry.size() != 6) return out;
		if (!std::isfinite(crank_phase) || !std::isfinite(omega) || !std::isfinite(alpha) || !std::isfinite(firing)) return out;
		if (omega < 0.0 || firing < 0.0 || firing > 1.0) return out;
		const nk::R tau = 6.28318530717958647692;
		const nk::R phase = nk::gv_fposmod(nk::R(crank_phase), tau);
		if (!nk::is_finite(phase)) return out;
		const nk::R radius = geometry[0], rod = geometry[1], mass = geometry[2];
		const nk::R c1 = geometry[3], c2 = geometry[4];
		const int64_t cycle = static_cast<int64_t>(geometry[5]);
		const nk::R w = omega, a = alpha;
		const nk::R sine = nk::sin_(phase);
		const nk::R cosine = nk::cos_(phase);
		const nk::R root_argument = rod * rod - radius * radius * sine * sine;
		if (!nk::is_finite(root_argument) || !(root_argument.v > 0.0)) return out;
		const nk::R r = nk::sqrt_(root_argument);
		const nk::R position_derivative = radius * sine + radius * radius * sine * cosine / r;
		const nk::R position_second_derivative = radius * cosine + radius * radius * ((cosine * cosine - sine * sine) / r +
			radius * radius * sine * sine * cosine * cosine / (r * r * r));
		const nk::R piston_acceleration = position_second_derivative * w * w + position_derivative * a;
		const nk::R source_force = -mass * piston_acceleration;
		const nk::R c1_cos = mass * c1 * w * w;
		const nk::R c1_sin = mass * c1 * a;
		const nk::R c2_cos = mass * nk::R(4.0) * c2 * w * w;
		const nk::R c2_sin = mass * nk::R(2.0) * c2 * a;
		const nk::R order_1x = nk::sqrt_(c1_cos * c1_cos + c1_sin * c1_sin);
		const nk::R order_2x = nk::sqrt_(c2_cos * c2_cos + c2_sin * c2_sin);
		const nk::R opportunity = w / tau / nk::R(static_cast<double>(cycle));
		const nk::R mean = opportunity * nk::R(firing);
		const nk::R values[9] = {source_force, order_1x, order_2x, c1_cos, c1_sin, c2_cos, c2_sin, opportunity, mean};
		for (const nk::R &value : values) {
			if (!nk::is_finite(value)) return out;
		}
		out[0] = 1.0; out[1] = phase.v; out[2] = source_force.v; out[3] = c1_cos.v; out[4] = c1_sin.v; out[5] = c2_cos.v;
		out[6] = c2_sin.v; out[7] = order_1x.v; out[8] = order_2x.v; out[9] = opportunity.v; out[10] = mean.v;
		return out;
	}

	// NK-6r: audio/soundscape_model.gd retarded_emission, exact (nk_soundscape.hpp): [index, alpha, delay, truncated
	// (1/0)]. Presentation only.
	PackedFloat64Array retarded_emission(const PackedFloat64Array &times, const godot::PackedVector3Array &positions,
			const godot::Vector3 &listener, double now, double sound_speed, int64_t min_index) const {
		const int64_t count = std::min(times.size(), positions.size());
		const nk::sound::Emission e = nk::sound::retarded_emission(times.ptr(), positions.ptr(), count, listener, now,
			sound_speed, min_index);
		PackedFloat64Array out;
		out.resize(4);
		out[0] = double(e.index); out[1] = e.alpha; out[2] = e.delay; out[3] = e.truncated ? 1.0 : 0.0;
		return out;
	}

	// NK-6q: Simulation.step's own checks and the session's state checks, exact; the reference runs them in GDScript.
	// Pure functions of their arguments: no prepared stage is needed.
	// simulation.gd state_is_valid: 13 finite values and a quaternion norm above MIN_QUATERNION_NORM_SQ.
	bool state_valid(const PackedFloat64Array &s) const {
		if (s.size() != nk::kTickBody) return false;
		const double *v = s.ptr();
		nk::R body[nk::kTickBody];
		for (int i = 0; i < nk::kTickBody; ++i) body[i] = v[i];
		return nk::tick_body_valid(body);
	}

	// scenery_collision.gd _state_is_valid: 13 finite values and |_dot4(q, q) - 1| <= 1.0e-9.
	bool scenery_state_valid(const PackedFloat64Array &s) const {
		if (s.size() != nk::kTickBody) return false;
		const double *v = s.ptr();
		for (int i = 0; i < nk::kTickBody; ++i) {
			if (!std::isfinite(v[i])) return false;
		}
		const int a = nk::kTickAtt;
		nk::R q_norm = 0.0; // _dot4: out := 0.0, then out += a[axis] * b[axis]
		for (int axis = 0; axis < 4; ++axis) q_norm = q_norm + nk::R(v[a + axis]) * nk::R(v[a + axis]);
		return nk::is_finite(q_norm) && std::fabs((q_norm - nk::R(1.0)).v) <= 1.0e-9;
	}

	// simulation.gd _array_is_finite(candidate, expected_size) for inputs, aux and continuous.
	static bool finite_sized(const PackedFloat64Array &values, int64_t expected_size) {
		if (expected_size >= 0 && values.size() != expected_size) return false;
		const double *v = values.ptr();
		for (int64_t i = 0; i < values.size(); ++i) {
			if (!std::isfinite(v[i])) return false;
		}
		return true;
	}

	bool arrays_finite(const PackedFloat64Array &inputs, int64_t input_size, const PackedFloat64Array &aux, int64_t aux_size,
			const PackedFloat64Array &continuous, int64_t continuous_size) const {
		return finite_sized(inputs, input_size) && finite_sized(aux, aux_size) && finite_sized(continuous, continuous_size);
	}

	// simulation.gd _refresh_inertia_inverse's cache test: _same_array(inertia, cache) (`!=` per entry, so a NaN never
	// matches) and _array_is_finite(inverse, 6).
	bool inertia_cached(const PackedFloat64Array &inertia, const PackedFloat64Array &cache, const PackedFloat64Array &inverse) const {
		if (inertia.size() != cache.size()) return false;
		const double *a = inertia.ptr();
		const double *b = cache.ptr();
		for (int64_t i = 0; i < inertia.size(); ++i) {
			if (a[i] != b[i]) return false;
		}
		return finite_sized(inverse, 6);
	}

	// NK-5i: the statistics sampler's evaluations of the accepted endpoint (statistics/fixed_wing_adapter.gd sample)
	// in one answer: [V, terrain height, slope north, slope east, collapsed (1/0), c_0 .. c_{n-1}], as
	// FlightSession.air_data(s, t).V (pre_step_air with the endpoint aux), Environment.ground(north, east) without an
	// RC track (the stage's surface table and lake), gear_compressions(s) (stage_compressions) and Ground.collapsed's
	// comparison of each compression with its posed contact's max_compression give them. Empty refuses, the caller
	// then evaluates the reference: every stage_compressions refusal, an aux of another layout or a nonfinite time,
	// a refused air sample or a contact without a numeric travel limit.
	PackedFloat64Array stage_endpoint_facts(const PackedFloat64Array &s, const PackedFloat64Array &aux, double time_s) {
		const PackedFloat64Array compressions = stage_compressions(s, aux);
		if (compressions.is_empty() || !std::isfinite(time_s) || aux.size() != static_cast<int64_t>(stage_.layout.aux_size)) {
			return PackedFloat64Array();
		}
		const nk::GroundContext &ground = stage_.retraction.enabled ? tick_.posed_ground : stage_.ground;
		if (static_cast<int64_t>(ground.gear.contacts.size()) != compressions.size()) return PackedFloat64Array();
		facts_aux_.resize(static_cast<size_t>(aux.size()));
		for (int64_t i = 0; i < aux.size(); ++i) {
			facts_aux_[static_cast<size_t>(i)] = aux[i];
		}
		nk::R state[kStateSize];
		load(s, state);
		nk::Air air;
		if (!nk::pre_step_air(state, nk::R(time_s), facts_aux_, stage_, air)) return PackedFloat64Array();
		const nk::Vec3 terrain = nk::terrain_sample_validated(state[0], state[1], ground.surfaces, ground.lake);
		bool collapsed = false;
		for (int64_t i = 0; i < compressions.size(); ++i) {
			const double limit = ground.gear.contacts[static_cast<size_t>(i)].max_compression.v;
			if (std::isnan(limit)) return PackedFloat64Array();
			if (compressions[i] > limit) collapsed = true;
		}
		facts_scratch_.resize(5 + static_cast<size_t>(compressions.size()));
		facts_scratch_[0] = air.V;
		facts_scratch_[1] = terrain[0];
		facts_scratch_[2] = terrain[1];
		facts_scratch_[3] = terrain[2];
		facts_scratch_[4] = collapsed ? 1.0 : 0.0;
		for (int64_t i = 0; i < compressions.size(); ++i) {
			facts_scratch_[5 + static_cast<size_t>(i)] = compressions[i];
		}
		return pack(facts_scratch_);
	}

	double stage_wing_wake(const PackedFloat64Array &s, const PackedFloat64Array &air, const PackedFloat64Array &d,
			double ground_up) {
		nk::Deflections deflections;
		if (!stage_ready_ || !read_state(s) || air.size() != 7 || !read_deflections(d, deflections)) {
			return std::numeric_limits<double>::quiet_NaN();
		}
		nk::R state[kStateSize];
		nk::R values[7];
		load(s, state);
		load(air, values);
		nk::Air a;
		a.v[0] = values[0];
		a.v[1] = values[1];
		a.v[2] = values[2];
		a.V = values[3];
		a.alpha = values[4];
		a.beta = values[5];
		a.qbar = values[6];
		nk::ge_factors(state, stage_.aero, ground_up, wing_wake_ge_);
		return nk::wing_lift_coefficient_with(state, a, deflections, stage_.aero, wing_wake_ge_, true).v;
	}

	// Diagnostic boundary witnesses only: no arithmetic, global FP changes, or retained caller storage.
	Dictionary float64_transport(double scalar, const PackedFloat64Array &values) const {
		Dictionary out;
		out["scalar"] = scalar;
		out["values"] = values.duplicate();
		return out;
	}

	Dictionary math_control_state() const {
		Dictionary out;
#if defined(NK_MATH_APPLE_ARM64)
		std::uint64_t fpcr = 0;
		__asm__ __volatile__("mrs %0, fpcr" : "=r"(fpcr) : : "memory");
		out["available"] = true;
		out["fpcr"] = static_cast<std::int64_t>(fpcr);
#else
		out["available"] = false;
#endif
		return out;
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
			{"100000.0", 100000.0},
			{"1e-30", nk::kGd1eMinus30}, {"1.0e-30", 1.0e-30},
			// NK-6q: scenery_collision.gd _state_is_valid.
			{"1.0e-9", 1.0e-9},
			// NK-7a: audio/soundscape_model.gd, wildlife.gd and powertrain_audio.gd (nk_soundscape.hpp).
			{"300.0", 300.0}, {"380.0", 380.0}, {"0.65", 0.65}, {"293.15", 293.15}, {"273.16", 273.16},
			{"101325.0", 101325.0}, {"16000.0", 16000.0}, {"6.8346", 6.8346}, {"1.261", 1.261}, {"4.6151", 4.6151},
			{"100.0", 100.0}, {"180.0", 180.0}, {"330.0", 330.0}, {"120000.0", 120000.0}, {"24.0", 24.0},
			{"4.04e4", 4.04e4}, {"0.02", 0.02}, {"0.391", 0.391}, {"9.0", 9.0}, {"280.0", 280.0}, {"4.170", 4.170},
			{"8.686", 8.686}, {"1.84e-11", 1.84e-11}, {"2.5", 2.5}, {"0.01275", 0.01275}, {"2239.1", 2239.1},
			{"0.1068", 0.1068}, {"3352.0", 3352.0}, {"1e-300", 1e-300}, {"1e-12", 1e-12}, {"0.16", 0.16},
			{"0.38", 0.38}, {"0.35", 0.35}, {"0.07", 0.07}, {"0.32", 0.32}, {"0.55", 0.55}, {"0.45", 0.45},
			{"6000.0", 6000.0}, {"0.12", 0.12}, {"3.5", 3.5}, {"0.18", 0.18}, {"55.0", 55.0}, {"0.20", 0.20},
			{"18.0", 18.0}, {"1.1", 1.1}, {"0.10", 0.10}, {"1.7", 1.7}, {"0.008", 0.008}, {"0.23", 0.23},
			{"14.0", 14.0}, {"45.0", 45.0}, {"1200.0", 1200.0}, {"35.0", 35.0}, {"12000.0", 12000.0}, {"1.4", 1.4},
			{"0.4", 0.4}, {"82320.0", 82320.0}, {"1.40", 1.40}, {"0.98", 0.98}, {"2.28", 2.28}, {"1.2", 1.2},
			{"0.46", 0.46}, {"1e-6", 1e-6}, {"4.0", 4.0}, {"60.0", 60.0}, {"120.0", 120.0}, {"10.0", 10.0},
			{"2.0", 2.0}, {"0.6", 0.6}, {"22.0", 22.0}, {"25.0", 25.0}, {"1500.0", 1500.0}, {"0.0", 0.0},
			// NK-7b: audio/soundscape.gd update_sound (nk_soundscape_core.hpp); -12.0 there is 0.5 * SCREEN_SHELF_DB.
			{"-24.0", -24.0}, {"-7.0", -7.0}, {"0.0001", 0.0001}, {"0.04", 0.04}, {"0.09", 0.09}, {"0.11", 0.11},
			{"0.21", 0.21}, {"0.22", 0.22}, {"0.26", 0.26}, {"0.30", 0.30}, {"0.31", 0.31}, {"0.78", 0.78},
			{"150.0", 150.0}, {"2.2", 2.2}, {"273.15", 273.15}, {"343.0", 343.0}, {"5.5", 5.5}, {"6500.0", 6500.0},
			// NK-7c: audio/powertrain_audio.gd update_sound and band_weights.
			{"0.055", 0.055}, {"1.3", 1.3}, {"450.0", 450.0}, {"18000.0", 18000.0}, {"0.24", 0.24}, {"0.76", 0.76},
			{"0.28", 0.28}, {"0.42", 0.42}, {"1.25", 1.25}, {"0.40", 0.40}, {"0.015", 0.015}, {"0.985", 0.985},
			{"2.6", 2.6}, {"0.7", 0.7}, {"0.035", 0.035}, {"0.00001", 0.00001}, {"0.173", 0.173}, {"2.5", 2.5},
			// NK-7d: audio/ground_audio.gd and ground_audio_motion.gd.
			{"0.035", 0.035}, {"0.018", 0.018}, {"0.14", 0.14}, {"0.65", 0.65}, {"0.42", 0.42}, {"0.9", 0.9},
			{"0.94", 0.94}, {"1.12", 1.12}, {"1.18", 1.18}, {"0.85", 0.85}, {"0.025", 0.025}, {"1.35", 1.35},
			{"0.86", 0.86}, {"0.34", 0.34}, {"0.18", 0.18}, {"0.0001", 0.0001}, {"1e-6", 1e-6},
			{"10000.0", 10000.0},
			// NK-7e: audio/mechanical_audio.gd and mechanical_motion.gd.
			{"60.0", 60.0}, {"39.0", 39.0}, {"0.085", 0.085}, {"0.16", 0.16}, {"0.48", 0.48}, {"0.78", 0.78},
			{"0.82", 0.82}, {"0.36", 0.36}, {"0.75", 0.75}, {"0.25", 0.25}, {"0.98", 0.98}, {"0.04", 0.04},
			{"997.0", 997.0}, {"1000.0", 1000.0}, {"0.999", 0.999}, {"0.000001", 0.000001}, {"240.0", 240.0},
			{"0.0002", 0.0002}, {"0.08", 0.08}, {"0.55", 0.55}, {"1.5", 1.5}, {"0.7", 0.7},
			// NK-6a: simulation.gd EVENT_TIME_SLACK_S and event_step.gd VALUE_TOL.
			{"1e-9", nk::kTickEventTimeSlack}, {"1e-7", nk::kEventValueTol},
			// NK-6c: electric_contact_step.gd FLOAT64_EPSILON.
			{"2.220446049250313e-16", nk::kFloat64Epsilon},
			// NK-6e: glow/flight.gd valid()'s mixture bound.
			{"2.8", 2.8},
			{"9223372036854775808.0", 9223372036854775808.0},
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
		if (rejection_diagnostics_enabled_) {
			clear_stage_rejection();
			clear_diagnostic_context();
		}
		heli_stage_ready_ = false;
		liquid_terminal_ready_ = false; // NK-6h: each installation prepares its own terminal bounds
		prop_strike_ready_ = false; // NK-6k: and its own propeller disc
		hull_guard_ready_ = false; // NK-6l: and its own guard crash depth
		glow_terminal_ready_ = false;
		pre_model_ = nk::PreStepModel(); // a new stage needs its own pre-step preparation
		Decoder dec;
		nk::StageModel candidate;
		const bool ok = decode_stage(dec, config, candidate);
		stage_ready_ = ok;
		tick_ = nk::TickContext();
		if (ok) {
			stage_ = std::move(candidate);
			const nk::StageLayout &layout = stage_.layout;
			continuous_scratch_.resize(static_cast<size_t>(layout.wheel_index) + layout.wheel_count + (stage_.liquid.ready ? 2 : 0));
			tick_.ground_anchors.resize(static_cast<size_t>(layout.anchor_count) * 3);
			tick_.wheel_speeds.resize(static_cast<size_t>(layout.wheel_count));
			tick_.preview_values.reserve(continuous_scratch_.size());
		} else {
			continuous_scratch_.clear();
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
		if (rejection_diagnostics_enabled_) {
			clear_stage_rejection();
			clear_diagnostic_context();
		}
		++context_calls_;
		tick_.ready = false;
		tick_.power_ready = false;
		tick_.capture_preview = false;
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
		if (rejection_diagnostics_enabled_) {
			diagnostic_context_inputs_ = inputs;
			diagnostic_context_deflections_ = deflections;
			diagnostic_context_ready_ = true;
		}
		return true;
	}
	bool set_preview_context(const PackedFloat64Array &body, const PackedFloat64Array &continuous, bool capture) {
		if (rejection_diagnostics_enabled_) clear_stage_rejection();
		tick_.capture_preview = false;
		if (!stage_ready_ || !tick_.ready) return false;
		if (!capture) {
			tick_.preview_values.clear();
			return true; // initial setup can have no committed body yet
		}
		if (!read_state(body) || continuous.size() != static_cast<int64_t>(continuous_scratch_.size())) return false;
		for (int i = 0; i < kStateSize; ++i) tick_.preview_body[i] = body[i];
		if (continuous.is_empty()) tick_.preview_values.clear();
		else tick_.preview_values.assign(continuous.ptr(), continuous.ptr() + continuous.size());
		tick_.capture_preview = capture;
		return true;
	}
	bool set_glow_context(double throttle, bool engine_running, bool injected_cut) {
		if (rejection_diagnostics_enabled_) clear_stage_rejection();
		tick_.power_ready = false;
		if (!stage_ready_ || !tick_.ready || !stage_.glow.ready) return false;
		tick_.throttle = throttle;
		tick_.power_enabled = engine_running;
		tick_.injected_cut = injected_cut;
		tick_.power_ready = true;
		return true;
	}
	bool set_power_context(double throttle, bool enabled) {
		if (rejection_diagnostics_enabled_) clear_stage_rejection();
		tick_.power_ready = false;
		if (!stage_ready_ || !tick_.ready || (!stage_.electric && !stage_.liquid.ready && !stage_.prescribed.ready())) return false;
		tick_.throttle = throttle;
		tick_.power_enabled = enabled;
		tick_.power_ready = true;
		return true;
	}

	PackedFloat64Array body_loads(const PackedFloat64Array &body, double t) {
		if (rejection_diagnostics_enabled_) clear_stage_rejection();
		++stage_calls_;
		const auto start = stage_timing_ ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point();
		PackedFloat64Array out;
		if (stage_ready_ && tick_.ready && read_state(body) && stage_.layout.wheel_index == 0 && stage_.layout.wheel_count == 0) {
			nk::R state[kStateSize], empty[1];
			load(body, state);
			const auto result = nk::stage_evaluate(state, empty, 0, t, stage_, tick_);
			if (result.shaped) out = pack(result.loads.data(), 6);
		}
		if (stage_timing_) stage_ns_ += std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - start).count();
		return out;
	}

	PackedFloat64Array body_rotor(const PackedFloat64Array &aux) const {
		if (!stage_ready_ || stage_.layout.rpm < 0 || stage_.layout.rpm >= aux.size()) return PackedFloat64Array();
		const nk::R rpm = aux[stage_.layout.rpm];
		const auto rotor = stage_.prescribed.is_turbine() ? nk::liquid_turbine_rotor_momentum(rpm, stage_.prescribed.turbine) :
			nk::prop_rotor_momentum(stage_.prop, rpm);
		return pack(rotor.data(), 3);
	}

	Dictionary stage(const PackedFloat64Array &body, const PackedFloat64Array &continuous, double t) {
		if (rejection_diagnostics_enabled_) clear_stage_rejection();
		++stage_calls_;
		const auto start = stage_timing_ ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point();
		Dictionary out;
		if (heli_stage_ready_) out = helicopter_.heli_stage(body, continuous, t);
		else if (stage_ready_ && read_state(body) && continuous.size() == static_cast<int64_t>(continuous_scratch_.size())) {
			nk::R state[kStateSize];
			load(body, state);
			for (int64_t i = 0; i < continuous.size(); ++i) {
				continuous_scratch_[static_cast<size_t>(i)] = continuous[i];
			}
			const nk::StageResult result = nk::stage_evaluate(state, continuous_scratch_.data(), static_cast<int>(continuous.size()), t,
				stage_, tick_, rejection_diagnostics_enabled_ ? &rejection_ : nullptr);
			if (result.shaped) {
				out = stage_dictionary(result, body);
			} else if (rejection_diagnostics_enabled_ && rejection_.code == nk::GlowRejectionCode::StoppedReverseDrive &&
					rejection_trial_is_valid(body, continuous, t)) {
				capture_stage_rejection(body, continuous, t);
			}
		}
		if (stage_timing_) {
			stage_ns_ += std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - start).count();
		}
		return out;
	}

	// The joint-stage dictionary of a shaped result, as `stage` returns it (NK-6a builds it only where a callback reads it).
	Dictionary stage_dictionary(const nk::StageResult &result, const PackedFloat64Array &body) const {
		Dictionary out;
		{
			{
				// GDScript's {loads = ...} literal keys are StringNames; keep the reference's exact dictionary bytes.
				static const godot::StringName kLoads("loads"), kDerivative("derivative"), kRotor("rotor_momentum");
				// NK-5c: build every result key once, not on each RK stage.
				static const godot::StringName k_body_derivative("body_derivative");
				static const godot::StringName k_v_air("v_air");
				static const godot::StringName k_V("V");
				static const godot::StringName k_alpha("alpha");
				static const godot::StringName k_beta("beta");
				static const godot::StringName k_qbar("qbar");
				static const godot::StringName k_spatial_air_law("spatial_air_law");
				static const godot::StringName k_spatial_aero_law("spatial_aero_law");
				static const godot::StringName k_spatial_state("spatial_state");
				static const godot::StringName k_spatial_time_s("spatial_time_s");
				static const godot::StringName k_spatial_rho("spatial_rho");
				static const godot::StringName k_aero_station_delta_body("aero_station_delta_body");
				static const godot::StringName k_spatial_sampler("spatial_sampler");
				static const godot::StringName k_ambient_delta_body_at("ambient_delta_body_at");
				static const godot::StringName k_propulsion_air_body("propulsion_air_body");
				static const godot::StringName k_wake_source_delta_body("wake_source_delta_body");
				static const godot::StringName k_air("air");
				static const godot::StringName k_pre_reaction_loads("pre_reaction_loads");
				static const godot::StringName k_wheel_derivative("wheel_derivative");
				static const godot::StringName k_source_off_rpm_rate("source_off_rpm_rate");
				static const godot::StringName k_stage_context("stage_context");
				out[kLoads] = pack(result.loads.data(), 6);
				out[kDerivative] = pack(result.derivative);
				out[kRotor] = pack(result.rotor.data(), 3);
				if (result.has_body_derivative) out[k_body_derivative] = pack(result.body_derivative.data(), 13);
				if (result.has_preview) {
					Dictionary air;
					const nk::Air &a = result.preview_air;
					air[k_v_air] = pack(a.v, 3);
					air[k_V] = a.V.v;
					air[k_alpha] = a.alpha.v;
					air[k_beta] = a.beta.v;
					air[k_qbar] = a.qbar.v;
					if (result.preview_spatial) {
						godot::Ref<OpenRCNativePointSampler> sampler;
						sampler.instantiate();
						sampler->prepare(stage_.spatial_identity, result.preview_point);
						air[k_spatial_air_law] = "m5-w05c-r2-point-air-v1";
						air[k_spatial_aero_law] = "matched-unwashed-full-angle-section-delta-v1";
						air[k_spatial_state] = body;
						air[k_spatial_time_s] = result.preview_time.v;
						air[k_spatial_rho] = result.preview_rho.v;
						air[k_aero_station_delta_body] = pack(result.preview_flow.aero_deltas.data(), 24);
						air[k_spatial_sampler] = sampler;
						air[k_ambient_delta_body_at] = godot::Callable(sampler.ptr(), "delta_at");
						air[k_propulsion_air_body] = pack(result.preview_flow.propulsion_air.data(), 3);
						air[k_wake_source_delta_body] = pack(result.preview_flow.wake_source_delta.data(), 3);
					}
					Dictionary context;
					context[k_air] = air;
					context[k_pre_reaction_loads] = pack(result.pre_reaction.data(), 6);
					context[k_wheel_derivative] = pack(result.preview_wheel_rates);
					// NK-5b: same key, order and value as LiquidFlight.evaluate; only a finite rate is published.
					if (result.has_preview_source_off) {
						context[k_source_off_rpm_rate] = result.preview_source_off_rpm_rate.v;
					}
					out[k_stage_context] = context;
				}
			}
		}
		return out;
	}

	// NK-6a: one counted fixed-wing stage evaluation from left-first scalars, with `stage`'s counters, timing and
	// rejection diagnostics. The caller has checked that the stage is prepared for this continuous size.
	void tick_stage(const nk::R *s, int size, double t, nk::StageResult &result) {
		if (rejection_diagnostics_enabled_) clear_stage_rejection();
		++stage_calls_;
		const auto start = stage_timing_ ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point();
		result = nk::stage_evaluate(s, s + kStateSize, size - kStateSize, t, stage_, tick_,
			rejection_diagnostics_enabled_ ? &rejection_ : nullptr);
		if (!result.shaped && rejection_diagnostics_enabled_ && rejection_.code == nk::GlowRejectionCode::StoppedReverseDrive) {
			const PackedFloat64Array body = pack(s, kStateSize);
			const PackedFloat64Array values = pack(s + kStateSize, size - kStateSize);
			if (rejection_trial_is_valid(body, values, t)) capture_stage_rejection(body, values, t);
		}
		if (stage_timing_) {
			stage_ns_ += std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - start).count();
		}
	}

	// Simulation `_joint_stage_is_valid` for the dictionary `stage` would build from this result.
	static bool tick_joint_valid(const nk::StageResult &r, int extra) {
		if (!r.shaped) return false;
		if (r.has_body_derivative && !nk::tick_finite(r.body_derivative.data(), kStateSize)) return false;
		return nk::tick_finite(r.loads.data(), 6) && static_cast<int>(r.derivative.size()) == extra &&
			nk::tick_finite(r.derivative.data(), extra) && nk::tick_finite(r.rotor.data(), 3);
	}

	// Simulation `derive` for a valid joint stage: its body derivative or rigid_body.gd's with the stage's rotor
	// momentum, then its continuous derivative.
	bool tick_derive(const nk::R *s, const nk::StageResult &joint, nk::R *out, const char *&error) const {
		if (joint.has_body_derivative) {
			for (int i = 0; i < kStateSize; ++i) out[i] = joint.body_derivative[static_cast<size_t>(i)];
		} else {
			nk::tick_rb_derivative(s, tick_mass_, tick_inertia_, tick_inertia_inv_, joint.loads.data(), tick_gravity_,
				joint.rotor.data(), out);
		}
		if (!nk::tick_finite(out, kStateSize)) {
			error = "RK stage derivative is nonfinite or malformed";
			return false;
		}
		for (size_t i = 0; i < joint.derivative.size(); ++i) out[kStateSize + i] = joint.derivative[i];
		return true;
	}

	static PackedFloat64Array tick_slice(const std::vector<nk::R> &values, int from, int to) {
		return pack(values.data() + from, to - from);
	}

	static bool tick_packed_finite(const Variant &value, int64_t expected) {
		if (value.get_type() != Variant::PACKED_FLOAT64_ARRAY) return false;
		const PackedFloat64Array values = value;
		if (expected >= 0 && values.size() != expected) return false;
		const double *data = values.ptr();
		for (int64_t i = 0; i < values.size(); ++i) {
			if (!std::isfinite(data[i])) return false;
		}
		return true;
	}

	static bool tick_state_valid(const Variant &value) {
		if (!tick_packed_finite(value, kStateSize)) return false;
		const PackedFloat64Array values = value;
		nk::R s[kStateSize];
		load(values, s);
		return nk::tick_body_valid(s);
	}

	// NK-6d: the glow plan's recording events, checked as ResourceStep.advance checks its definitions; only the stock
	// surfaces (rotor stop, main tank unusable, feed line empty) are admitted, so a pickup event keeps the reference.
	static bool decode_glow_plan(const Dictionary &plan, std::vector<nk::ResourceEvent> &events,
			std::vector<godot::Callable> &transitions, nk::ResourceGlowLayout &layout) {
		static const godot::StringName k_events("events"), k_transitions("transitions"), k_unusable("unusable_fuel_kg"),
			k_id("id"), k_type("type"), k_surface("surface"), k_transition("transition"), k_sense("sense"),
			k_unit("surface_unit"), k_enabled("enabled"), k_priority("priority"), k_tolerance("surface_tolerance");
		const Variant events_value = plan.get(k_events, Variant());
		const Variant unusable = plan.get(k_unusable, Variant());
		if (events_value.get_type() != Variant::ARRAY || plan.get(k_transitions, Variant()).get_type() != Variant::ARRAY ||
				unusable.get_type() != Variant::FLOAT || !std::isfinite(double(unusable))) return false;
		layout.unusable_fuel_kg = double(unusable);
		const Array list = events_value;
		if (list.is_empty()) return false;
		for (int64_t i = 0; i < list.size(); ++i) {
			if (list[i].get_type() != Variant::DICTIONARY) return false;
			const Dictionary event = list[i];
			const Variant id = event.get(k_id, Variant());
			const Variant type = event.get(k_type, Variant());
			const Variant unit = event.get(k_unit, Variant());
			const Variant sense = event.get(k_sense, Variant());
			const Variant surface = event.get(k_surface, Variant());
			const Variant transition = event.get(k_transition, Variant());
			if (id.get_type() != Variant::STRING || String(id).strip_edges().is_empty() || type.get_type() != Variant::STRING ||
					String(type).strip_edges().is_empty() || unit.get_type() != Variant::STRING ||
					String(unit).strip_edges().is_empty() || surface.get_type() != Variant::CALLABLE ||
					transition.get_type() != Variant::CALLABLE || !godot::Callable(surface).is_valid() ||
					!godot::Callable(transition).is_valid()) return false;
			nk::ResourceEvent decoded;
			const String sense_name = sense.get_type() == Variant::STRING ? String(sense) : String();
			if (sense_name == String("falling")) decoded.sense = nk::ResourceSense::Falling;
			else if (sense_name == String("rising")) decoded.sense = nk::ResourceSense::Rising;
			else if (sense_name == String("either")) decoded.sense = nk::ResourceSense::Either;
			else return false;
			decoded.has_enabled = event.has(k_enabled);
			if (decoded.has_enabled && (event.get(k_enabled, Variant()).get_type() != Variant::CALLABLE ||
					!godot::Callable(event.get(k_enabled, Variant())).is_valid())) return false;
			const Variant priority = event.get(k_priority, int64_t(100));
			if (priority.get_type() != Variant::INT) return false;
			decoded.priority = static_cast<int>(int64_t(priority));
			if (event.has(k_tolerance)) {
				const Variant tolerance = event.get(k_tolerance, Variant());
				if ((tolerance.get_type() != Variant::FLOAT && tolerance.get_type() != Variant::INT) ||
						!std::isfinite(double(tolerance)) || double(tolerance) <= 0.0) return false;
				decoded.tolerance = double(tolerance);
			}
			const godot::CharString id_utf8 = String(id).utf8();
			decoded.id = std::string(id_utf8.get_data());
			for (const nk::ResourceEvent &other : events) if (other.id == decoded.id) return false;
			if (decoded.id == "rotor_stop" && !decoded.has_enabled) decoded.surface = nk::ResourceSurface::RotorStop;
			else if (decoded.id == "main_tank_unusable" && decoded.has_enabled) decoded.surface = nk::ResourceSurface::MainTankUnusable;
			else if (decoded.id == "feed_line_empty" && decoded.has_enabled) decoded.surface = nk::ResourceSurface::FeedLineEmpty;
			else return false; // a pickup or other event: its surface stays with the reference
			decoded.type = std::string(String(type).utf8().get_data());
			decoded.unit = std::string(String(unit).utf8().get_data());
			decoded.index = static_cast<int>(i);
			events.push_back(decoded);
			transitions.push_back(godot::Callable(transition));
		}
		return true;
	}

	// Simulation._unpack_policy_result for a policy's Dictionary: {} with `events` and `next` filled, or {fault}.
	Dictionary unpack_policy_result(const Dictionary &result, double t, double dt, Array &events, std::vector<nk::R> &next) {
		static const godot::StringName k_failure("failure"), k_state("state"), k_receipt("integration_receipt"),
			k_events("events"), k_type("type"), k_time("time_s");
		if (result.has(k_failure)) {
			const Variant failure = result.get(k_failure, Variant());
			if (result.size() == 1 && failure.get_type() == Variant::STRING && !String(failure).is_empty() &&
					String(failure).length() <= 256) return tick_fault(String("step rejected: ") + String(failure));
			return tick_fault("step rejected: malformed step-policy failure receipt");
		}
		if (result.get(k_state, Variant()).get_type() != Variant::PACKED_FLOAT64_ARRAY) {
			return tick_fault("step rejected: step policy returned no state");
		}
		if (result.has(k_receipt)) {
			return tick_fault("step rejected: integration receipt requires an opt-in endpoint owner and bounded finite payload");
		}
		const Variant raw = result.get(k_events, Array());
		if (raw.get_type() != Variant::ARRAY) return tick_fault("step rejected: step policy returned malformed events");
		const nk::R earliest = nk::R(t) - nk::R(nk::kTickEventTimeSlack);
		const nk::R latest = nk::R(t) + nk::R(dt) + nk::R(nk::kTickEventTimeSlack);
		const Array items = raw;
		for (int64_t i = 0; i < items.size(); ++i) {
			const Variant item = items[i];
			if (item.get_type() != Variant::DICTIONARY) return tick_fault("step rejected: step policy returned malformed events");
			const Dictionary event = item;
			const Variant type = event.get(k_type, Variant());
			const Variant time = event.get(k_time, Variant());
			if (type.get_type() != Variant::STRING || String(type).is_empty() ||
					(time.get_type() != Variant::FLOAT && time.get_type() != Variant::INT) || !std::isfinite(double(time)) ||
					double(time) < earliest.v || double(time) > latest.v) {
				return tick_fault("step rejected: step policy returned malformed events");
			}
			events.append(event.duplicate(true));
		}
		const PackedFloat64Array state = result.get(k_state, Variant());
		next.resize(static_cast<size_t>(state.size()));
		for (int64_t i = 0; i < state.size(); ++i) next[static_cast<size_t>(i)] = state[i];
		return Dictionary();
	}

	Dictionary tick_fault(const String &reason) {
		++tick_faults_;
		Dictionary out;
		out["fault"] = reason;
		return out;
	}

	// NK-6a: Simulation.step's legacy joint tick from the tick's first stage to its accepted endpoint, after the
	// reference pre_tick installed `aux` (simulation.gd). The model's callbacks (rotor momentum, substeps, event
	// transition, post-step filter, auxiliary projection) are called where and with what the reference calls them.
	// {} refuses before any evaluation, leaving the tick to the reference; {fault} carries the reference's refusal;
	// otherwise {state, continuous, aux, loads, events} is the endpoint the reference would commit.
	Dictionary integrate_tick(godot::Object *model, const PackedFloat64Array &state, const PackedFloat64Array &continuous,
			const PackedFloat64Array &aux, double t, double dt, int64_t tick, double mass, double gravity,
			const PackedFloat64Array &inertia, const PackedFloat64Array &inertia_inv) {
		static const godot::StringName k_rotor_momentum("rotor_momentum"), k_substeps_joint("substeps_joint"),
			k_substeps("substeps"), k_events("events"), k_post_tick("post_tick"), k_post_tick_joint("post_tick_joint"),
			k_block_aux("block_aux"), k_transition("transition"), k_index("index"), k_type("type"), k_fault("fault"),
			k_state("state"), k_continuous("continuous"), k_aux("aux"), k_loads("loads"), k_events_out("events");
		if (model == nullptr || heli_stage_ready_ || !stage_ready_ || !tick_.ready || state.size() != kStateSize ||
				continuous.is_empty() || continuous.size() != static_cast<int64_t>(continuous_scratch_.size()) ||
				inertia.size() != 6 || inertia_inv.size() != 6) {
			return Dictionary();
		}
		// NK-6c: a model stepped by the session's finite-pack policy (_electric_step) first gives the policy's plan:
		// [dynamic, contact pieces, combined rotor index, pack supervision], computed as the policy computes it (pure).
		static const godot::StringName k_step_policy("step_policy"), k_electric_step("_electric_step"),
			k_electric_plan("native_electric_step_plan"), k_supervise_pack("_supervise_pack"),
			k_project_stop("_project_electric_stop");
		const godot::Callable policy = model->get(k_step_policy);
		godot::Object *policy_owner = nullptr;
		godot::PackedInt64Array plan;
		// NK-6d: GlowFlight.step (a static policy bound to its session) gives its recording resource events.
		static const godot::StringName k_glow_step("step"), k_glow_plan("native_glow_step_plan"), k_glow_finish("finish");
		godot::Object *glow_owner = nullptr;
		godot::Object *glow_script = nullptr;
		Dictionary glow_plan;
		std::vector<nk::ResourceEvent> glow_events;
		std::vector<godot::Callable> glow_transitions;
		nk::ResourceGlowLayout glow_layout;
		if (policy.is_valid() && policy.get_method() == k_glow_step) {
			const Array bound = policy.get_bound_arguments();
			if (bound.size() != 1 || bound[0].get_type() != Variant::OBJECT) return Dictionary();
			glow_owner = bound[0];
			glow_script = policy.get_object();
			if (glow_owner == nullptr || glow_script == nullptr || !glow_owner->has_method(k_glow_plan)) return Dictionary();
			glow_plan = glow_owner->call(k_glow_plan);
			if (glow_plan.is_empty() || !decode_glow_plan(glow_plan, glow_events, glow_transitions, glow_layout)) {
				return Dictionary();
			}
		} else if (policy.is_valid()) {
			policy_owner = policy.get_object();
			if (policy_owner == nullptr || policy.get_method() != k_electric_step || !policy_owner->has_method(k_electric_plan)) {
				return Dictionary();
			}
			PackedFloat64Array planned_state = state.duplicate();
			planned_state.append_array(continuous);
			const Variant planned = policy_owner->call(k_electric_plan, planned_state, dt);
			if (planned.get_type() != Variant::PACKED_INT64_ARRAY) return Dictionary();
			plan = planned;
			if (plan.size() != 4 || plan[2] < kStateSize || plan[2] + 1 >= kStateSize + continuous.size()) return Dictionary();
		}
		const bool step_policy = policy_owner != nullptr || glow_script != nullptr;
		++tick_calls_;
		const int extra = static_cast<int>(continuous.size());
		const int size = kStateSize + extra;
		tick_combined_.resize(static_cast<size_t>(size));
		for (int i = 0; i < kStateSize; ++i) tick_combined_[static_cast<size_t>(i)] = state[i];
		for (int i = 0; i < extra; ++i) tick_combined_[static_cast<size_t>(kStateSize + i)] = continuous[i];
		tick_mass_ = mass;
		tick_gravity_ = gravity;
		for (int i = 0; i < 6; ++i) {
			tick_inertia_[i] = inertia[i];
			tick_inertia_inv_[i] = inertia_inv[i];
		}
		tick_rk4_.size(size);
		const nk::R *combined = tick_combined_.data();

		// The tick's own joint stage (H2: stage 1 reuses it).
		nk::StageResult current;
		tick_stage(combined, size, t, current);
		if (!tick_joint_valid(current, extra)) return tick_fault("step rejected: joint stage evaluation is nonfinite or malformed");
		const Variant rotor = godot::Callable(model->get(k_rotor_momentum)).call(aux);
		if (!tick_packed_finite(rotor, -1) || (PackedFloat64Array(rotor).size() != 0 && PackedFloat64Array(rotor).size() != 3)) {
			return tick_fault("step rejected: rotor momentum is nonfinite or malformed");
		}
		const char *stage_error = nullptr;
		tick_first_.resize(static_cast<size_t>(size));
		tick_derive(combined, current, tick_first_.data(), stage_error);

		// Substeps: the joint callback reads the tick's stage dictionary.
		Variant declared = int64_t(1);
		const godot::Callable substeps_joint = model->get(k_substeps_joint);
		const godot::Callable substeps = model->get(k_substeps);
		if (substeps_joint.is_valid()) {
			const PackedFloat64Array body = tick_slice(tick_combined_, 0, kStateSize);
			declared = substeps_joint.call(body, tick_slice(tick_combined_, kStateSize, size), t, stage_dictionary(current, body));
		} else if (substeps.is_valid()) {
			declared = substeps.call(tick_slice(tick_combined_, 0, kStateSize), tick_slice(tick_combined_, kStateSize, size), t);
		}
		if (declared.get_type() != Variant::INT || int64_t(declared) < 1 || int64_t(declared) > nk::kTickMaxSubsteps) {
			return tick_fault("step rejected: substep count is not an integer within 1..16");
		}
		const int pieces = static_cast<int>(int64_t(declared));
		if (step_policy && pieces > 1) {
			return tick_fault(String("step rejected: the step policy owns the tick and cannot honour ") +
				String::num_int64(pieces) + String(" contact substeps"));
		}
		if (stage_error != nullptr) return tick_fault(String("step rejected: ") + stage_error);

		// The RK stage derivative `f`.
		auto f = [&](const nk::R *s, nk::R stage_t, nk::R *out) -> bool {
			if (!nk::tick_finite(s, size) || !nk::tick_body_valid(s)) {
				stage_error = "RK stage state is nonfinite, malformed, or has a degenerate quaternion";
				return false;
			}
			tick_stage(s, size, stage_t.v, tick_stage_result_);
			if (!tick_joint_valid(tick_stage_result_, extra)) {
				stage_error = "RK joint stage evaluation is nonfinite or malformed";
				return false;
			}
			return tick_derive(s, tick_stage_result_, out, stage_error);
		};
		tick_next_.resize(static_cast<size_t>(size));
		tick_event_times_.clear();
		nk::TickStatus status = nk::TickStatus::Ok;
		bool located = true;
		String event_type;
		const Array events = model->get(k_events);
		bool policy_ok = true;
		std::vector<nk::TickPolicyEvent> policy_events;
		Variant glow_result;
		if (glow_script != nullptr) {
			// GlowFlight.step: ResourceStep.advance over the recording events, then GlowFlight.finish.
			std::vector<Variant> glow_details;
			auto transition = [&](const nk::ResourceEvent &event, const std::vector<nk::R> &in, nk::R at,
					std::vector<nk::R> &out, int &details) -> bool {
				const Variant transitioned = glow_transitions[static_cast<size_t>(event.index)].call(pack(in), at.v);
				if (transitioned.get_type() != Variant::DICTIONARY) return false;
				const Dictionary result = transitioned;
				static const godot::StringName k_ok("ok"), k_state_key("state"), k_event_key("event");
				if (!bool(result.get(k_ok, false)) || result.get(k_state_key, Variant()).get_type() != Variant::PACKED_FLOAT64_ARRAY) {
					return false;
				}
				const PackedFloat64Array values = result.get(k_state_key, Variant());
				out.resize(static_cast<size_t>(values.size()));
				for (int64_t i = 0; i < values.size(); ++i) out[static_cast<size_t>(i)] = values[i];
				details = static_cast<int>(glow_details.size());
				glow_details.push_back(result.get(k_event_key, Dictionary()));
				return true;
			};
			std::vector<nk::ResourceReport> reports;
			bool glow_ok = false;
			status = nk::resource_advance(combined, size, t, dt, f, tick_first_.data(), glow_events, glow_layout, transition,
				glow_ok, tick_next_, reports, tick_rk4_);
			policy_ok = false;
			static const godot::StringName k_steady_key("steady"), k_plan_transitions_key("transitions");
			const Variant steady = glow_plan.get(k_steady_key, Variant());
			if (status == nk::TickStatus::Ok && glow_ok && stage_error == nullptr && reports.empty() &&
					steady.get_type() == Variant::PACKED_FLOAT64_ARRAY && PackedFloat64Array(steady).size() == nk::kGfTermCount &&
					glow_plan.get(k_plan_transitions_key, Variant()).get_type() == Variant::ARRAY &&
					Array(glow_plan.get(k_plan_transitions_key, Variant())).is_empty()) {
				// NK-6n: a steady tick's finish without its GDScript call; any refusal leaves it to finish below.
				const PackedFloat64Array terms = steady;
				const double firing = glow_firing_at(tick_next_.data(), tick_next_.data() + kStateSize,
					static_cast<int64_t>(tick_next_.size()) - kStateSize, (nk::R(t) + nk::R(dt)).v);
				if (std::isfinite(firing) &&
						nk::glow_steady_finish(tick_combined_, tick_next_, kStateSize, dt, terms.ptr(), firing, glow_finish_out_)) {
					static const godot::StringName k_steady_state("state"), k_steady_events("events");
					Dictionary finished;
					finished[k_steady_state] = pack(glow_finish_out_.data(), static_cast<int>(glow_finish_out_.size()));
					finished[k_steady_events] = Array();
					glow_result = finished;
					policy_ok = true;
					++glow_finish_answers_;
				}
			}
			if (!policy_ok && status == nk::TickStatus::Ok && glow_ok && stage_error == nullptr) {
				static const godot::StringName k_ok("ok"), k_state_key("state"), k_events_key("events"),
					k_type_key("type"), k_time_key("time_s"), k_id_key("id"), k_residual_key("surface_residual"),
					k_unit_key("surface_unit"), k_error_key("time_error_bound_s"), k_transitions_key("transitions");
				Array reported;
				for (const nk::ResourceReport &report : reports) {
					Dictionary entry;
					entry[k_type_key] = String::utf8(report.event->type.c_str());
					entry[k_time_key] = report.time_s.v;
					entry[k_id_key] = String::utf8(report.event->id.c_str());
					entry[k_residual_key] = report.residual.v;
					entry[k_unit_key] = String::utf8(report.event->unit.c_str());
					entry[k_error_key] = report.time_error.v;
					const Variant details = report.details >= 0 ? glow_details[static_cast<size_t>(report.details)] : Variant();
					if (details.get_type() == Variant::DICTIONARY) entry.merge(Dictionary(details), true);
					reported.append(entry);
				}
				Dictionary bounded;
				bounded[k_ok] = true;
				bounded[k_state_key] = pack(tick_next_);
				bounded[k_events_key] = reported;
				glow_result = glow_script->call(k_glow_finish, pack(tick_combined_), t, dt, glow_owner, bounded,
					glow_plan.get(k_transitions_key, Variant()));
				policy_ok = true;
			}
		} else if (policy_owner != nullptr) {
			// FlightSession._electric_step: battery step (one piece) or contact pieces, then pack supervision; a fixed
			// source keeps the rotor-stop event step. Any failure makes the policy return [NAN].
			const bool dynamic = plan[0] != 0;
			const int64_t count = plan[1];
			const int rotor = static_cast<int>(plan[2]);
			const bool supervised = plan[3] != 0;
			const godot::Callable project_stop(policy_owner, k_project_stop);
			auto project = [&](const nk::R *in, int count_in, int at, std::vector<nk::R> &out) -> bool {
				const Variant projected = project_stop.call(pack(in, count_in), at);
				if (projected.get_type() != Variant::PACKED_FLOAT64_ARRAY) return false;
				const PackedFloat64Array values = projected;
				out.resize(static_cast<size_t>(values.size()));
				for (int64_t i = 0; i < values.size(); ++i) out[static_cast<size_t>(i)] = values[i];
				return true;
			};
			policy_ok = false;
			if (dynamic) {
				if (count >= 1 && count <= nk::kTickMaxSubsteps) {
					status = count == 1 ?
						nk::tick_battery_advance(combined, size, t, dt, f, tick_first_.data(), rotor, rotor + 1, project,
							policy_ok, tick_next_, policy_events, tick_rk4_) :
						nk::tick_contact_advance(combined, size, t, dt, f, tick_first_.data(), rotor, rotor + 1, project,
							static_cast<int>(count), policy_ok, tick_next_, policy_events, tick_rk4_);
					if (status == nk::TickStatus::Ok && policy_ok && supervised) {
						const PackedFloat64Array supervised_state = policy_owner->call(k_supervise_pack, pack(tick_next_), dt);
						tick_next_.resize(static_cast<size_t>(supervised_state.size()));
						for (int64_t i = 0; i < supervised_state.size(); ++i) tick_next_[static_cast<size_t>(i)] = supervised_state[i];
					}
				}
			} else {
				status = nk::tick_event_advance(combined, size, t, dt, f, tick_first_.data(), rotor, project,
					project_stop.is_valid(), policy_ok, tick_next_, tick_event_times_, tick_rk4_);
				for (const nk::R at : tick_event_times_) {
					nk::TickPolicyEvent rotor_event;
					rotor_event.time_s = at;
					policy_events.push_back(rotor_event);
				}
			}
		} else if (!events.is_empty()) {
			const Dictionary event = events[0];
			const godot::Callable transition = event.get(k_transition, Variant());
			const int index = static_cast<int>(int64_t(event.get(k_index, Variant())));
			event_type = String(event.get(k_type, Variant()));
			auto project = [&](const nk::R *in, int count, int at, std::vector<nk::R> &out) -> bool {
				const Variant projected = transition.call(pack(in, count), at);
				if (projected.get_type() != Variant::PACKED_FLOAT64_ARRAY) return false;
				const PackedFloat64Array values = projected;
				out.resize(static_cast<size_t>(values.size()));
				for (int64_t i = 0; i < values.size(); ++i) out[static_cast<size_t>(i)] = values[i];
				return true;
			};
			status = nk::tick_locate_substeps(combined, size, t, dt, f, tick_first_.data(), index, project,
				transition.is_valid(), pieces, located, tick_next_, tick_event_times_, tick_rk4_);
		} else if (pieces == 1) {
			status = nk::tick_rk4_step_at(combined, size, t, dt, f, tick_first_.data(), tick_next_.data(), tick_rk4_);
		} else {
			status = nk::tick_rk4_substeps(combined, size, t, dt, f, tick_first_.data(), pieces, tick_next_, tick_rk4_);
		}
		if (status == nk::TickStatus::Abort || stage_error != nullptr) {
			return tick_fault(String("step rejected: ") + (stage_error != nullptr ? stage_error : ""));
		}
		if (!located) return tick_fault("step rejected: the event locator could not bound the tick");
		Array tick_events;
		if (glow_script != nullptr) {
			if (!policy_ok) {
				tick_next_.assign(1, nk::R(nk::kNan)); // ResourceStep failed: the policy returned [NAN]
			} else if (glow_result.get_type() == Variant::DICTIONARY) {
				const Dictionary unpacked_fault = unpack_policy_result(glow_result, t, dt, tick_events, tick_next_);
				if (!unpacked_fault.is_empty()) return unpacked_fault;
			} else if (glow_result.get_type() == Variant::PACKED_FLOAT64_ARRAY) {
				const PackedFloat64Array values = glow_result;
				tick_next_.resize(static_cast<size_t>(values.size()));
				for (int64_t i = 0; i < values.size(); ++i) tick_next_[static_cast<size_t>(i)] = values[i];
			} else {
				return tick_fault(glow_result.get_type() == Variant::NIL ?
					"step rejected: the event locator could not bound the tick" :
					"step rejected: step policy returned a malformed result");
			}
		} else if (policy_owner != nullptr && !policy_ok) {
			// The policy returned [NAN]: Simulation finds no events and refuses the integrated state.
			tick_next_.assign(1, nk::R(nk::kNan));
		} else if (policy_owner != nullptr) {
			const nk::R earliest = nk::R(t) - nk::R(nk::kTickEventTimeSlack);
			const nk::R latest = nk::R(t) + nk::R(dt) + nk::R(nk::kTickEventTimeSlack);
			for (const nk::TickPolicyEvent &policy_event : policy_events) {
				if (!nk::is_finite(policy_event.time_s) || policy_event.time_s.v < earliest.v || policy_event.time_s.v > latest.v) {
					return tick_fault("step rejected: step policy returned malformed events");
				}
				Dictionary event;
				event[String("type")] = String(policy_event.battery ? "battery_exhausted" : "rotor_stop");
				event[String("time_s")] = policy_event.time_s.v;
				if (policy_event.battery) {
					event[String("charge_residual_c")] = policy_event.residual_c.v;
					event[String("time_error_bound_s")] = policy_event.time_error_s.v;
				}
				tick_events.append(event);
			}
		} else if (!events.is_empty()) {
			const nk::R earliest = nk::R(t) - nk::R(nk::kTickEventTimeSlack);
			const nk::R latest = nk::R(t) + nk::R(dt) + nk::R(nk::kTickEventTimeSlack);
			for (const nk::R time_s : tick_event_times_) {
				if (event_type.is_empty() || !nk::is_finite(time_s) || time_s.v < earliest.v || time_s.v > latest.v) {
					return tick_fault("step rejected: step policy returned malformed events");
				}
				Dictionary event;
				event[String("type")] = event_type;
				event[String("time_s")] = time_s.v;
				tick_events.append(event);
			}
		}
		if (static_cast<int>(tick_next_.size()) != size || !nk::tick_finite(tick_next_.data(), size) ||
				!nk::tick_body_valid(tick_next_.data())) {
			return tick_fault("step rejected: integrated state is nonfinite, malformed, or has a degenerate quaternion");
		}

		// The post-step body filter owns only the rigid body.
		PackedFloat64Array accepted_body = tick_slice(tick_next_, 0, kStateSize);
		const godot::Callable post_tick = model->get(k_post_tick);
		const godot::Callable post_tick_joint = model->get(k_post_tick_joint);
		if (post_tick.is_valid() || post_tick_joint.is_valid()) {
			Array arguments;
			arguments.append(state.duplicate());
			arguments.append(accepted_body.duplicate());
			arguments.append(tick + 1);
			if (post_tick_joint.is_valid()) {
				arguments.append(continuous.duplicate());
				arguments.append(tick_slice(tick_next_, kStateSize, size));
			}
			const Variant filtered = (post_tick_joint.is_valid() ? post_tick_joint : post_tick).callv(arguments);
			if (!tick_state_valid(filtered)) {
				return tick_fault("step rejected: post-step contact filter returned a malformed body state");
			}
			accepted_body = PackedFloat64Array(filtered).duplicate();
		}
		const PackedFloat64Array accepted_continuous = tick_slice(tick_next_, kStateSize, size);
		PackedFloat64Array accepted_aux = aux;
		const godot::Callable block_aux = model->get(k_block_aux);
		if (block_aux.is_valid()) {
			const Variant projected = block_aux.call(accepted_continuous, accepted_aux.duplicate());
			if (!tick_packed_finite(projected, aux.size())) {
				return tick_fault("step rejected: continuous auxiliary projection is nonfinite or malformed");
			}
			accepted_aux = projected;
		}
		++tick_answers_;
		Dictionary out;
		out[k_state] = accepted_body;
		out[k_continuous] = accepted_continuous;
		out[k_aux] = accepted_aux;
		out[k_loads] = pack(current.loads.data(), 6);
		out[k_events_out] = tick_events;
		return out;
	}

	// NK-6b: GlowFlight.point(owner, body, values, time_s).firing_fraction from the prepared glow stage and the tick
	// context of the guarded pre-step: the same point evaluation the stage composes. NaN refuses (no glow stage or
	// context, another layout, a refused stage); the caller then evaluates point(). Not counted as an RK stage.
	double stage_glow_firing(const PackedFloat64Array &body, const PackedFloat64Array &values, double time_s) {
		if (!read_state(body)) {
			++glow_firing_calls_;
			return nk::kNan;
		}
		nk::R state[kStateSize];
		load(body, state);
		std::vector<nk::R> values_in(static_cast<size_t>(values.size()));
		for (int64_t i = 0; i < values.size(); ++i) values_in[static_cast<size_t>(i)] = values[i];
		return glow_firing_at(state, values_in.data(), values.size(), time_s);
	}

	// stage_glow_firing on raw arrays (NK-6n reads the bounded end state in place).
	double glow_firing_at(const nk::R *body, const nk::R *values, int64_t count, double time_s) {
		++glow_firing_calls_;
		if (heli_stage_ready_ || !stage_ready_ || !stage_.glow.ready || !tick_.ready ||
				count != static_cast<int64_t>(continuous_scratch_.size()) || !std::isfinite(time_s)) {
			return nk::kNan;
		}
		nk::R state[kStateSize];
		for (int i = 0; i < kStateSize; ++i) state[i] = body[i];
		std::vector<nk::R> &scratch = continuous_scratch_;
		for (int64_t i = 0; i < count; ++i) scratch[static_cast<size_t>(i)] = values[i];
		const nk::StageResult result = nk::stage_evaluate(state, scratch.data(), static_cast<int>(count), time_s,
			stage_, tick_, nullptr);
		if (!result.shaped || !nk::is_finite(result.glow_firing_fraction)) return nk::kNan;
		++glow_firing_answers_;
		return result.glow_firing_fraction.v;
	}

	// NK-6n: GlowFlight.finish's steady-tick answer (nk_glow_finish.hpp) for given states, terms and endpoint firing
	// fraction; empty where finish must run. For equivalence tests; the tick calls the same function.
	PackedFloat64Array glow_steady_finish_component(const PackedFloat64Array &start, const PackedFloat64Array &end,
			double dt, const PackedFloat64Array &terms, double firing) const {
		if (terms.size() != nk::kGfTermCount || start.size() != end.size()) return PackedFloat64Array();
		std::vector<nk::R> a(static_cast<size_t>(start.size())), b(static_cast<size_t>(end.size())), out;
		for (int64_t i = 0; i < start.size(); ++i) a[static_cast<size_t>(i)] = start[i];
		for (int64_t i = 0; i < end.size(); ++i) b[static_cast<size_t>(i)] = end[i];
		if (!nk::glow_steady_finish(a, b, kStateSize, dt, terms.ptr(), firing, out)) return PackedFloat64Array();
		return pack(out.data(), static_cast<int>(out.size()));
	}

	int64_t glow_finish_answers() const { return glow_finish_answers_; }

	// NK-6e: GlowFlight.valid(values, install) and GlowFlight.mass_context(owner, values).ok for the prepared glow stage.
	// The installation's own bounds arrive once from the session (prepare_glow_validity); the configuration guard keeps
	// them. -1 refuses (not prepared); otherwise 1 valid or 0 invalid, as the reference decides.
	bool prepare_glow_validity(const Dictionary &bounds) {
		glow_validity_ = GlowValidity();
		const char *names[] = {"max_rpm", "total_capacity_kg", "capacity_fuel_kg", "line_capacity_kg", "unusable_fuel_kg",
				"cycle_revolutions"};
		double read[6];
		for (int i = 0; i < 6; ++i) {
			const Variant value = bounds.get(String(names[i]), Variant());
			if ((value.get_type() != Variant::FLOAT && value.get_type() != Variant::INT) || !std::isfinite(double(value))) return false;
			read[i] = double(value);
		}
		const Variant has_line = bounds.get("has_line", Variant());
		const Variant family_ok = bounds.get("family_ok", Variant());
		if (has_line.get_type() != Variant::BOOL || family_ok.get_type() != Variant::BOOL) return false;
		glow_validity_.max_rpm = read[0];
		glow_validity_.total_capacity = read[1];
		glow_validity_.capacity = read[2];
		glow_validity_.line_capacity = read[3];
		glow_validity_.unusable = read[4];
		glow_validity_.cycle = read[5];
		glow_validity_.has_line = bool(has_line);
		glow_validity_.family_ok = bool(family_ok);
		glow_validity_.ready = true;
		return true;
	}

	// GlowFlight.valid: unpack's checks, Life._state_error(state, true), then valid's own bounds, in their order.
	static bool glow_values_valid(const double *v, int64_t n, const GlowValidity &g) {
		if (n < 19) return false;
		for (int64_t i = 0; i < n; ++i) {
			if (!std::isfinite(v[i])) return false;
		}
		if (!(v[7] == 0.0 || v[7] == 1.0) || v[8] != std::floor(v[8]) || v[8] < 0.0 || v[8] >= 7.0) return false;
		if (!g.family_ok) return false;
		const int64_t opportunities = static_cast<int64_t>(v[9]);
		const int64_t fires = static_cast<int64_t>(v[10]);
		if (opportunities < 0 || fires < 0 || fires > opportunities) return false;
		if (v[11] < 0.0 || v[11] >= 1.0) return false;
		if (v[2] <= 0.0 || v[6] < 0.0) return false;
		if (v[1] < 0.0 || v[5] < 0.0 || v[3] < 0.0 || v[3] > 1.0 || v[4] < 0.0 || v[4] > 1.0) return false;
		if (v[0] < 0.0 || v[0] > g.max_rpm.v || v[1] > g.total_capacity.v || v[12] < 0.0 || v[12] > 2.8) return false;
		const nk::R line = v[17];
		const nk::R main = nk::R(v[1]) - line;
		const nk::R line_capacity = g.has_line ? g.line_capacity : nk::R(0.0);
		if (!nk::is_finite(line) || line.v < 0.0 || line.v > line_capacity.v || main.v < 0.0 || main.v > g.capacity.v ||
				v[18] != std::floor(v[18]) || v[18] < 0.0 || v[18] > 2.0) return false;
		const nk::R residue = g.has_line ?
			nk::R(4.0) * nk::R(nk::kFloat64Epsilon) * nk::maxf(nk::absf(nk::R(v[1])), nk::absf(line)) : nk::R(0.0);
		if (main.v < g.unusable.v && (g.unusable - main).v > residue.v) return false;
		if (!g.has_line && (line.v != 0.0 || v[18] == 2.0)) return false;
		if (v[18] == 2.0 && line.v <= 0.0) return false;
		const int64_t mode = static_cast<int64_t>(v[18]);
		if (mode == 1 && main.v <= g.unusable.v) return false;
		if (mode == 0 && v[7] == 1.0) return false;
		if (v[6] < 0.0 || v[6] >= g.cycle.v || v[9] != std::floor(v[9]) || v[10] != std::floor(v[10])) return false;
		return true;
	}

	int64_t stage_glow_mass_check(const PackedFloat64Array &values, bool with_mass) {
		++glow_mass_calls_;
		if (heli_stage_ready_ || !stage_ready_ || !stage_.glow.ready || !glow_validity_.ready) return -1;
		const double *v = values.ptr();
		const int64_t n = values.size();
		if (n < 19) return 0;
		if (!with_mass) return glow_values_valid(v, n, glow_validity_) ? 1 : 0;
		// GlowFlight.mass_context: valid, the store bounds, then properties(total, line).ok.
		const nk::R total = v[1];
		const nk::R line = v[17];
		const nk::R main = total - line;
		const nk::R line_capacity = glow_validity_.has_line ? glow_validity_.line_capacity : nk::R(0.0);
		if (!glow_values_valid(v, n, glow_validity_) || !nk::is_finite(total) || !nk::is_finite(line) || total.v < 0.0 ||
				line.v < 0.0 || line.v > line_capacity.v || main.v < 0.0 || main.v > glow_validity_.capacity.v ||
				total.v > glow_validity_.total_capacity.v || (!glow_validity_.has_line && line.v != 0.0)) return 0;
		return nk::glow_raw_mass(stage_.glow, total, line).ok ? 1 : 0;
	}

	Dictionary tick_stats() const {
		Dictionary out;
		out["calls"] = tick_calls_;
		out["glow_mass_calls"] = glow_mass_calls_;
		out["terminal_calls"] = terminal_calls_;
		out["terminal_quiet"] = terminal_quiet_;
		out["hull_rows_calls"] = hull_rows_calls_;
		out["hull_rows_answers"] = hull_rows_answers_;
		out["answers"] = tick_answers_;
		out["faults"] = tick_faults_;
		out["glow_firing_calls"] = glow_firing_calls_;
		out["glow_firing_answers"] = glow_firing_answers_;
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
		if (rejection_diagnostics_enabled_) clear_stage_rejection();
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

	// NK-6h/6i: the geometry half of a quiet HullContact.terminal_at_properties: both states pass its input and
	// attitude checks, and every hull point is out of reach, above ground or already touching before the tick, with
	// none lake-covered or past the crash depth. The caller has checked the properties.
	int64_t terminal_geometry_quiet(const PackedFloat64Array &previous, const PackedFloat64Array &s, double crash_depth) {
		// terminal_at_properties' input checks.
		nk::R before[kStateSize];
		nk::R now[kStateSize];
		load(previous, before);
		load(s, now);
		for (int i = 0; i < kStateSize; ++i) if (!nk::is_finite(before[i]) || !nk::is_finite(now[i])) return 0;
		const nk::R q_norm = before[6] * before[6] + before[7] * before[7] + before[8] * before[8] + before[9] * before[9];
		if (!nk::is_finite(q_norm) || nk::absf(q_norm - 1.0).v > 1.0e-9) return 0;
		const nk::HullPrepared &hull = stage_.hull;
		if ((-now[2]).v > hull.reach.v) {
			++terminal_quiet_;
			return 1;
		}
		const nk::R dn[3] = {2.0 * (now[7] * now[9] - now[6] * now[8]), 2.0 * (now[8] * now[9] + now[6] * now[7]),
			1.0 - 2.0 * (now[7] * now[7] + now[8] * now[8])};
		const nk::R db[3] = {2.0 * (before[7] * before[9] - before[6] * before[8]), 2.0 * (before[8] * before[9] + before[6] * before[7]),
			1.0 - 2.0 * (before[7] * before[7] + before[8] * before[8])};
		const bool lake_sampled = hull.lake.present && !nk::hull_clear_of_lake(now, hull);
		const int count = static_cast<int>(hull.points.size() / 3);
		for (int i = 0; i < count; ++i) {
			const nk::R *r = &hull.points[static_cast<size_t>(i) * 3];
			if (lake_sampled) {
				const std::array<nk::R, 3> rotated = nk::q_rotate3(now + 6, r);
				const std::array<nk::R, 3> point = {now[0] + rotated[0], now[1] + rotated[1], now[2] + rotated[2]};
				if (nk::hull_lake_sample(hull, point).covered) return 0; // the lake's own terminal candidate
			}
			const nk::R depth = now[2] + dn[0] * r[0] + dn[1] * r[1] + dn[2] * r[2];
			if (depth.v <= 0.0) continue;
			if (depth.v > crash_depth) return 0;
			const nk::R depth_before = before[2] + db[0] * r[0] + db[1] * r[1] + db[2] * r[2];
			if (depth_before.v > 0.0) continue;
			return 0; // a new penetration: the reference grades its impact energy
		}
		++terminal_quiet_;
		return 1;
	}

	// NK-6l: the crash depth of the session's hull (HullContact.crash_depth of FlightSession._hull_contact) for the
	// pre-tick guard's hull checks. Each installation prepares its own.
	bool prepare_hull_guard(double crash_depth) {
		hull_guard_ready_ = stage_ready_ && !heli_stage_ready_ && stage_.hull.present && std::isfinite(crash_depth);
		hull_guard_crash_depth_ = crash_depth;
		return hull_guard_ready_;
	}

	// NK-6l: the pre-tick guard's hull checks on the stage's hull. Bit 1: HullContact.terminal(previous, s, hull) must
	// return no event (terminal_geometry_quiet: no point newly penetrates, lies deeper than the crash depth or meets
	// the lake). Bit 2: HullContact.contacts(previous, s, hull) must return no contact (above the reach, or the lake
	// out of reach and every point at or above the datum). 0: the reference answers both.
	int64_t stage_hull_guard(const PackedFloat64Array &previous, const PackedFloat64Array &s) {
		if (!hull_guard_ready_ || heli_stage_ready_ || !stage_ready_ || !stage_.hull.present || !read_state(previous) ||
				!read_state(s)) return 0;
		int64_t bits = terminal_geometry_quiet(previous, s, hull_guard_crash_depth_) == 1 ? 1 : 0;
		nk::R now[kStateSize];
		load(s, now);
		for (int i = 0; i < 10; ++i) {
			if (!nk::is_finite(now[i])) return bits;
		}
		const nk::HullPrepared &hull = stage_.hull;
		if ((-now[2]).v > hull.reach.v) return bits | 2;
		if (hull.lake.present && !nk::hull_clear_of_lake(now, hull)) return bits;
		const nk::R dn[3] = {2.0 * (now[7] * now[9] - now[6] * now[8]), 2.0 * (now[8] * now[9] + now[6] * now[7]),
			1.0 - 2.0 * (now[7] * now[7] + now[8] * now[8])};
		const int count = static_cast<int>(hull.points.size() / 3);
		for (int i = 0; i < count; ++i) {
			const nk::R *r = &hull.points[static_cast<size_t>(i) * 3];
			const nk::R depth = now[2] + dn[0] * r[0] + dn[1] * r[1] + dn[2] * r[2];
			if (!(depth.v <= 0.0)) return bits;
		}
		return bits | 2;
	}

	// NK-6h: the session's hull crash depth (HullContact.crash_depth of its live geometry) and whether its fuel
	// sample (FuelSample.build) accepts every in-range liquid amount, from the installation. The configuration guard
	// refuses a tick after a later change.
	bool prepare_liquid_terminal(double crash_depth, bool sample_static_ok) {
		liquid_terminal_ready_ = stage_ready_ && !heli_stage_ready_ && stage_.liquid.ready && stage_.hull.present &&
			stage_.hull.stiffness.empty() && std::isfinite(crash_depth) && sample_static_ok;
		liquid_terminal_crash_depth_ = crash_depth;
		return liquid_terminal_ready_;
	}

	// NK-6h: 1 when HullContact.terminal_at_properties(previous, s, live hull, the liquid contact sample at fraction 0)
	// must answer {ok, no event}: the sample's properties are valid (the stage's own live mass for that store), the
	// inputs pass its checks, and no hull point newly penetrates, lies deeper than the crash depth or meets the lake.
	// 0 where the reference must evaluate. usable_before is the start store's usable fuel coordinate.
	int64_t stage_liquid_terminal_quiet(const PackedFloat64Array &previous, const PackedFloat64Array &s, double usable_before) {
		++terminal_calls_;
		if (!liquid_terminal_ready_ || heli_stage_ready_ || !stage_ready_ || !stage_.liquid.ready || !stage_.hull.present ||
				!stage_.hull.stiffness.empty() || !read_state(previous) || !read_state(s)) return 0;
		const nk::LiquidStageModel &liquid = stage_.liquid;
		const nk::R usable = usable_before;
		if (!nk::is_finite(usable) || usable.v < 0.0 || usable.v > (liquid.capacity_kg - liquid.unusable_kg).v) return 0;
		// LiquidFlight.contact_sampler at fraction 0: Liquid.properties of the clamped onboard store, as the stage does.
		const nk::R onboard = nk::liquid_trial_onboard_mass(usable, liquid.unusable_kg, liquid.capacity_kg);
		const nk::R inventory_usable = nk::liquid_inventory_usable_mass(onboard, liquid.unusable_kg, liquid.capacity_kg);
		const size_t resource_count = liquid.mass.resources.size();
		if (resource_count == 0 || static_cast<size_t>(liquid.bound_index) >= resource_count) return 0;
		terminal_amounts_.resize(resource_count);
		for (size_t i = 0; i < resource_count; ++i) terminal_amounts_[i] = liquid.mass.resources[i].reference_kg;
		terminal_amounts_[static_cast<size_t>(liquid.bound_index)] = inventory_usable;
		const nk::LiquidMassProperties p = nk::liquid_mass_evaluate(liquid.mass, terminal_amounts_.data(), static_cast<int>(resource_count));
		if (!p.ok || nk::live_hull_properties_error(p)[0] != '\0') return 0;
		return terminal_geometry_quiet(previous, s, liquid_terminal_crash_depth_);
	}

	// NK-6i: the glow counterpart of prepare_liquid_terminal. stores: [capacity_kg, unusable_kg] of the contact sample's
	// tanks in its order (the main tank, then the feed line when installed); sample_static_ok: FuelSample.build accepts
	// those tanks at both ends of each store's range.
	bool prepare_glow_terminal(double crash_depth, const PackedFloat64Array &stores, bool sample_static_ok) {
		glow_terminal_ready_ = stage_ready_ && !heli_stage_ready_ && stage_.glow.ready && stage_.hull.present &&
			stage_.hull.stiffness.empty() && std::isfinite(crash_depth) && sample_static_ok &&
			(stores.size() == 2 || stores.size() == 4);
		glow_terminal_crash_depth_ = crash_depth;
		glow_terminal_stores_.clear();
		for (int64_t i = 0; glow_terminal_ready_ && i < stores.size(); ++i) {
			if (!std::isfinite(stores[i])) glow_terminal_ready_ = false;
			glow_terminal_stores_.push_back(stores[i]);
		}
		return glow_terminal_ready_;
	}

	// NK-6i: 1 when HullContact.terminal_at_properties for the glow contact sample at fraction 0 must answer
	// {ok, no event}: GlowFlight.properties(total, line) from the prepared glow mass is valid, FuelSample.build accepts
	// the main (total - line) and line amounts, and the geometry is quiet. 0 where the reference must evaluate.
	int64_t stage_glow_terminal_quiet(const PackedFloat64Array &previous, const PackedFloat64Array &s, double total,
			double line) {
		++terminal_calls_;
		if (!glow_terminal_ready_ || heli_stage_ready_ || !stage_ready_ || !stage_.glow.ready || !stage_.hull.present ||
				!stage_.hull.stiffness.empty() || !read_state(previous) || !read_state(s)) return 0;
		const nk::R total_r = total;
		const nk::R line_r = line;
		if (!nk::is_finite(total_r) || !nk::is_finite(line_r)) return 0;
		// FuelSample.build's amount checks for {main: total - line, line: line}.
		const nk::R amounts[2] = {total_r - line_r, line_r};
		const int stores = static_cast<int>(glow_terminal_stores_.size() / 2);
		if (stores == 1 && line_r.v != 0.0) return 0; // no feed line store: the sample records the main tank only
		for (int k = 0; k < stores; ++k) {
			const double capacity = glow_terminal_stores_[static_cast<size_t>(2 * k)];
			const double unusable = glow_terminal_stores_[static_cast<size_t>(2 * k + 1)];
			const double amount = amounts[k].v;
			const double tolerance = capacity * 1.0e-9;
			if (!std::isfinite(amount) || amount < 0.0 || capacity - amount < -tolerance || amount - unusable < -tolerance) {
				return 0;
			}
		}
		const nk::LiquidMassProperties p = nk::glow_raw_mass(stage_.glow, total_r, line_r);
		if (!p.ok || nk::live_hull_properties_error(p)[0] != '\0') return 0;
		return terminal_geometry_quiet(previous, s, glow_terminal_crash_depth_);
	}

	// NK-6f: the GP-19 endpoint diagnostics of HullContact.loads (properties empty: the prepared hull) or
	// loads_at_properties (properties = [ok, mass, cg x3, inertia x6, inverse x6]: the geometry-only live hull) for the
	// session's hull-scrape observation. Returns [1, n, then n x (index, f_up, f_n, f_e, vn, ve)], the reference's own
	// values, or [0] where the reference must answer: a lake-covered sample (its structured diagnostics are
	// unavailable), a refused live sample, or a hull of the other kind.
	PackedFloat64Array stage_hull_scrape_rows(const PackedFloat64Array &s, const PackedFloat64Array &properties) {
		++hull_rows_calls_;
		PackedFloat64Array refuse;
		refuse.push_back(0.0);
		if (heli_stage_ready_ || !stage_ready_ || !read_state(s) || !stage_.hull.present) return refuse;
		const bool live = !properties.is_empty();
		if (live != stage_.hull.stiffness.empty() || (live && properties.size() != 17)) return refuse;
		nk::R state[kStateSize];
		load(s, state);
		hull_diagnostics_.rows.clear();
		hull_diagnostics_.covered = false;
		if (live) {
			const double *v = properties.ptr();
			nk::LiquidMassProperties p;
			p.ok = v[0] != 0.0;
			p.mass_kg = v[1];
			for (int i = 0; i < 3; ++i) p.cg[static_cast<size_t>(i)] = v[2 + i];
			for (int i = 0; i < 6; ++i) {
				p.inertia[static_cast<size_t>(i)] = v[5 + i];
				p.inverse[static_cast<size_t>(i)] = v[11 + i];
			}
			if (!nk::hull_loads_at_properties(state, stage_.hull, p, &hull_diagnostics_).ok) return refuse;
		} else {
			std::array<nk::R, 6> loads;
			nk::hull_loads(state, stage_.hull, loads, &hull_diagnostics_);
		}
		if (hull_diagnostics_.covered) return refuse;
		hull_rows_scratch_.clear();
		hull_rows_scratch_.push_back(1.0);
		hull_rows_scratch_.push_back(static_cast<double>(hull_diagnostics_.rows.size()));
		for (const nk::HullRow &row : hull_diagnostics_.rows) {
			hull_rows_scratch_.push_back(static_cast<double>(row.index));
			hull_rows_scratch_.push_back(row.f_up);
			hull_rows_scratch_.push_back(row.f_n);
			hull_rows_scratch_.push_back(row.f_e);
			hull_rows_scratch_.push_back(row.vn);
			hull_rows_scratch_.push_back(row.ve);
		}
		++hull_rows_answers_;
		return pack(hull_rows_scratch_);
	}

	// FlightSession._ground_evaluation with the current tick context's aux.
	Dictionary ground_component(const PackedFloat64Array &s, const PackedFloat64Array &values) const {
		Dictionary out;
		if (!stage_ready_ || !tick_.ready || !read_state(s) ||
				values.size() != int64_t(stage_.layout.wheel_index) + stage_.layout.wheel_count) {
			out["ok"] = false;
			return out;
		}
		nk::R state[kStateSize];
		load(s, state);
		for (int64_t i = 0; i < values.size(); ++i) {
			continuous_scratch_[static_cast<size_t>(i)] = values[i];
		}
		std::array<nk::R, 6> loads{};
		bool has_loads = false;
		std::vector<nk::R> rates;
		const bool ok = nk::stage_ground(state, stage_, tick_, continuous_scratch_.data(), static_cast<int>(values.size()), loads, has_loads, rates);
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
		godot::ClassDB::register_class<OpenRCNativePointSampler>();
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
