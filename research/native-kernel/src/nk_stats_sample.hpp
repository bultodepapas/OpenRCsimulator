// NK-9b: app/statistics/fixed_wing_adapter.gd sample(true) for a published endpoint, exact: the accepted-tick
// statistics sample from the state, the native stage's endpoint facts (NK-5i), the session's contact events and the
// validated accident observation. The adapter keeps the packet checks, the gear extension read and the damage
// observation; profiles with an authored hull support keep the GDScript. Arithmetic follows math3d.gd's order with
// nk::R left-first operations; atan2, pow, sqrt, absf and deg_to_rad are the engine's own, as GDScript calls them. The
// result has the GDScript literal's StringName keys, order and value types.
#pragma once

#include <cstdint>
#include <vector>

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>

#include "nk_audio_rows.hpp"
#include "nk_math.hpp"

namespace nk {
namespace stats {

class FixedWingSample {
public:
	// {landing_available, main_indices, stop_indices, rest_pitch_rad, rest_height_m, clearance_m} as the adapter reads
	// them from its profile (bool, the index collections, floats).
	bool bind(const godot::Dictionary &plan) {
		ready_ = false;
		if (plan.size() != 6 || plan.get("landing_available", godot::Variant()).get_type() != godot::Variant::BOOL) return false;
		landing_available_ = bool(plan["landing_available"]);
		if (!indices(plan.get("main_indices", godot::Variant()), main_) || !indices(plan.get("stop_indices", godot::Variant()), stop_)) {
			return false;
		}
		for (const char *key : {"rest_pitch_rad", "rest_height_m", "clearance_m"}) {
			if (plan.get(key, godot::Variant()).get_type() != godot::Variant::FLOAT) return false;
		}
		rest_pitch_ = double(plan["rest_pitch_rad"]);
		rest_height_ = double(plan["rest_height_m"]);
		clearance_ = double(plan["clearance_m"]);
		ready_ = true;
		return true;
	}

	// The sample, or {} when the inputs are not the published form this mirrors (the adapter then evaluates GDScript).
	godot::Dictionary build(const godot::PackedFloat64Array &s, const godot::PackedFloat64Array &facts, bool deployed,
			int64_t tick, double dt, bool fault_empty, bool crashed, const godot::Dictionary &contacts,
			const godot::Dictionary &observation) {
		godot::Dictionary out;
		if (!ready_ || s.size() != 13 || facts.size() < 5) return out;
		const double *v = s.ptr();
		const R q[4] = {v[6], v[7], v[8], v[9]};
		const sound::V3d velocity = sound::q_rotate_gd(q, sound::V3d{v[3], v[4], v[5]});
		const double speed = sqrt_(pow2(velocity.x.v) + pow2(velocity.y.v) + pow2(velocity.z.v));
		const double angular = sqrt_(pow2(v[10]) + pow2(v[11]) + pow2(v[12]));
		const double tas = facts[0];
		const double terrain[3] = {facts[1], facts[2], facts[3]};
		const R conj[4] = {q[0], -q[1], -q[2], -q[3]};
		const sound::V3d body_normal = sound::q_rotate_gd(conj, sound::V3d{-terrain[1], -terrain[2], -1.0});
		const double bank = godot::UtilityFunctions::atan2(body_normal.y.v, -body_normal.z.v);
		const double pitch = godot::UtilityFunctions::atan2(body_normal.x.v, sqrt_(pow2(body_normal.y.v) + pow2(body_normal.z.v)));
		bool physical = false, intended = false, stop = landing_available_;
		for (int64_t i = 0; i < facts.size() - 5; ++i) {
			const bool contact = facts[5 + i] > 0.00001;
			physical = physical || contact;
			if (has(main_, i)) intended = intended || contact;
			if (has(stop_, i) && !contact) stop = false;
		}
		// The contact events and the observation, as the adapter reads them (non-hull profile).
		bool gear_up = bool(observation.get(k_.gear_up_contact, false));
		bool incident = gear_up;
		if (!incident) {
			const godot::Variant strike = contacts.get(k_.prop_strike, godot::Dictionary());
			int empty = is_empty(strike);
			if (empty < 0) return godot::Dictionary();
			incident = empty == 0;
		}
		const int hulls_empty = is_empty(contacts.get(k_.active_hull_ids, godot::Array()));
		if (hulls_empty < 0) return godot::Dictionary();
		bool ground_contact = physical || hulls_empty == 0;
		const godot::Variant events_value = contacts.get(k_.events, godot::Array());
		if (events_value.get_type() != godot::Variant::ARRAY) return godot::Dictionary();
		const godot::Array events = events_value;
		const bool observed_intended = bool(observation.get(k_.intended_support, false));
		for (int64_t i = 0; i < events.size(); ++i) {
			if (events[i].get_type() != godot::Variant::DICTIONARY) return godot::Dictionary();
			const godot::Dictionary event = events[i];
			if (equals(event.get(k_.format, godot::Variant()), k_.support_format)) continue;
			if (!equals(event.get(k_.lifecycle, godot::Variant()), k_.ended)) {
				const godot::Variant source = event.get(k_.source, godot::Variant());
				incident = incident || equals(source, k_.scenery) || equals(source, k_.lake) || equals(source, k_.propeller) ||
					(equals(source, k_.hull) && !observed_intended) ||
					equals(event.get(k_.response, godot::Variant()), k_.terminal_text);
				if (equals(source, k_.hull) || equals(source, k_.gear) || equals(source, k_.lake)) ground_contact = true;
			}
		}
		ground_contact = ground_contact || bool(observation.get(k_.ground_contact, false));
		physical = physical || ground_contact;
		intended = intended || observed_intended;
		const bool collapsed = facts[4] != 0.0;
		const bool controlled = godot::UtilityFunctions::absf(bank) <= godot::UtilityFunctions::deg_to_rad(15.0) &&
			godot::UtilityFunctions::absf(pitch - rest_pitch_) <= godot::UtilityFunctions::deg_to_rad(20.0) &&
			angular <= 1.0 && deployed && !collapsed;
		const double reference_height = terrain[0];
		const bool valid = std::isfinite(terrain[0]) && std::isfinite(tas) && fault_empty;
		out[k_.tick] = tick;
		out[k_.dt] = dt;
		out[k_.valid] = valid;
		out[k_.supported] = physical;
		out[k_.intended_support] = intended && landing_available_;
		out[k_.stop_support] = stop;
		out[k_.clearance_ok] = !physical && (-v[2]) - reference_height >= rest_height_ + clearance_;
		out[k_.controlled] = controlled;
		out[k_.ground_speed_3d] = speed;
		out[k_.angular_speed] = angular;
		out[k_.tas] = tas;
		out[k_.groundspeed] = sqrt_(pow2(velocity.x.v) + pow2(velocity.y.v));
		godot::PackedFloat64Array position;
		position.resize(3);
		position.set(0, v[0]);
		position.set(1, v[1]);
		position.set(2, v[2]);
		out[k_.position] = position;
		godot::PackedFloat64Array velocity_ned;
		velocity_ned.resize(3);
		velocity_ned.set(0, velocity.x.v);
		velocity_ned.set(1, velocity.y.v);
		velocity_ned.set(2, velocity.z.v);
		out[k_.velocity_ned] = velocity_ned;
		out[k_.incident] = incident;
		out[k_.gear_up_contact] = gear_up;
		out[k_.terminal] = crashed || bool(observation.get(k_.terminal, false));
		out[k_.ground_contact] = ground_contact;
		return out;
	}

private:
	static double pow2(double x) { return godot::UtilityFunctions::pow(x, 2.0); }
	static double sqrt_(double x) { return godot::UtilityFunctions::sqrt(x); }

	// `i in collection` for the profile's index collections: numeric elements compared as GDScript does.
	static bool indices(const godot::Variant &value, std::vector<double> &out) {
		out.clear();
		switch (value.get_type()) {
			case godot::Variant::PACKED_INT32_ARRAY: {
				const godot::PackedInt32Array a = value;
				for (int64_t i = 0; i < a.size(); ++i) out.push_back(static_cast<double>(a[i]));
				return true;
			}
			case godot::Variant::PACKED_INT64_ARRAY: {
				const godot::PackedInt64Array a = value;
				for (int64_t i = 0; i < a.size(); ++i) out.push_back(static_cast<double>(a[i]));
				return true;
			}
			default:
				return false; // other collections keep the GDScript membership test
		}
	}

	static bool has(const std::vector<double> &collection, int64_t i) {
		for (double x : collection) {
			if (x == static_cast<double>(i)) return true;
		}
		return false;
	}

	// GDScript `.is_empty()` on a contact field: 1 empty, 0 not, -1 for a type this does not mirror.
	static int is_empty(const godot::Variant &value) {
		switch (value.get_type()) {
			case godot::Variant::DICTIONARY: return godot::Dictionary(value).is_empty() ? 1 : 0;
			case godot::Variant::ARRAY: return godot::Array(value).is_empty() ? 1 : 0;
			case godot::Variant::PACKED_STRING_ARRAY: return godot::PackedStringArray(value).is_empty() ? 1 : 0;
			default: return -1;
		}
	}

	// Variant equality with a String, as GDScript compares a String or StringName field with a String literal.
	static bool equals(const godot::Variant &value, const godot::String &text) {
		const godot::Variant::Type type = value.get_type();
		if (type != godot::Variant::STRING && type != godot::Variant::STRING_NAME) return false;
		return godot::String(value) == text;
	}

	struct Keys {
		godot::StringName tick{"tick"}, dt{"dt"}, valid{"valid"}, supported{"supported"},
			intended_support{"intended_support"}, stop_support{"stop_support"}, clearance_ok{"clearance_ok"},
			controlled{"controlled"}, ground_speed_3d{"ground_speed_3d"}, angular_speed{"angular_speed"}, tas{"tas"},
			groundspeed{"groundspeed"}, position{"position"}, velocity_ned{"velocity_ned"}, incident{"incident"},
			gear_up_contact{"gear_up_contact"}, terminal{"terminal"}, ground_contact{"ground_contact"};
		godot::String prop_strike{"prop_strike"}, active_hull_ids{"active_hull_ids"}, events{"events"}, format{"format"},
			lifecycle{"lifecycle"}, source{"source"}, response{"response"}, support_format{"openrc-aircraft-support-events v2"},
			ended{"ended"}, scenery{"scenery"}, lake{"lake"}, propeller{"propeller"}, hull{"hull"}, gear{"gear"},
			terminal_text{"terminal"};
	};

	bool ready_ = false;
	bool landing_available_ = false;
	std::vector<double> main_, stop_;
	double rest_pitch_ = 0.0, rest_height_ = 0.0, clearance_ = 0.0;
	Keys k_; // per instance: never function-local statics
};

} // namespace stats
} // namespace nk
