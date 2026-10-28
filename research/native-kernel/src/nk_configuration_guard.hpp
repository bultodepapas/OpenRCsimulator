// NK-3 fixed-wing configuration ownership guard. Constructed from the identity
// produced alongside the exact native stage configuration. Every watch is
// allocated at preparation; tick checks neither rebuild data nor call physics.
// The installed stage callback is checked separately by NativeStage.owns_stage.
#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstddef>
#include <cstring>
#include <initializer_list>
#include <utility>
#include <vector>

namespace nk {

class ConfigurationGuard {
	using Variant = godot::Variant;
	using Object = godot::Object;
	using Dictionary = godot::Dictionary;
	using Array = godot::Array;
	using StringName = godot::StringName;

	enum class Parent { SessionProperty, SimulationProperty, OwnedProperty, DictionaryEntry, ArrayEntry };
	struct Watch {
		Parent source = Parent::SessionProperty;
		Variant parent;
		StringName property;
		Variant key;
		int64_t index = 0;
		Variant expected;
		int64_t container_size = -1;
	};
	static constexpr std::size_t kMaxWatches = 65536;
	static constexpr int kMaxDepth = 32;

	bool ready_ = false;
	bool helicopter_ = false;
	uint64_t session_id_ = 0;
	uint64_t sim_id_ = 0;
	Variant session_script_;
	Variant sim_script_;
	Variant environment_;
	Variant environment_script_;
	Variant vehicle_;
	Variant vehicle_script_;
	int64_t input_size_ = 0;
	int64_t aux_size_ = 0;
	int64_t continuous_size_ = 0;
	int64_t modes_size_ = 0;
	std::vector<Watch> watches_;

	StringName p_sim_ = "sim";
	StringName p_model_ = "model";
	StringName p_environment_ = "environment";
	StringName p_stage_ = "stage";
	StringName p_inputs_ = "inputs";
	StringName p_aux_ = "aux";
	StringName p_continuous_ = "continuous";
	StringName p_modes_ = "modes";

	static bool same_bits(double a, double b) { return std::memcmp(&a, &b, sizeof(double)) == 0; }

	template <typename P, typename T>
	static bool same_packed(const Variant &a, const Variant &b) {
		const P left = a;
		const P right = b;
		return left.size() == right.size() && (left.size() == 0 ||
				std::memcmp(left.ptr(), right.ptr(), static_cast<std::size_t>(left.size()) * sizeof(T)) == 0);
	}

	static bool same_scalar(const Variant &a, const Variant &b) {
		if (a.get_type() != b.get_type()) return false;
		switch (a.get_type()) {
			case Variant::NIL:
			case Variant::BOOL:
			case Variant::INT:
			case Variant::STRING:
			case Variant::STRING_NAME:
			case Variant::PACKED_STRING_ARRAY:
				return a == b;
			case Variant::CALLABLE:
				return godot::UtilityFunctions::is_same(a, b);
			case Variant::FLOAT:
				return same_bits(static_cast<double>(a), static_cast<double>(b));
			case Variant::PACKED_FLOAT64_ARRAY:
				return same_packed<godot::PackedFloat64Array, double>(a, b);
			case Variant::PACKED_FLOAT32_ARRAY:
				return same_packed<godot::PackedFloat32Array, float>(a, b);
			case Variant::PACKED_INT64_ARRAY:
				return same_packed<godot::PackedInt64Array, int64_t>(a, b);
			case Variant::PACKED_INT32_ARRAY:
				return same_packed<godot::PackedInt32Array, int32_t>(a, b);
			case Variant::PACKED_BYTE_ARRAY:
				return same_packed<godot::PackedByteArray, uint8_t>(a, b);
			default:
				return false; // No arbitrary Object or unsupported variant in a stage snapshot.
		}
	}

	static Variant detached_scalar(const Variant &value) {
		switch (value.get_type()) {
			case Variant::PACKED_FLOAT64_ARRAY: return godot::PackedFloat64Array(value).duplicate();
			case Variant::PACKED_FLOAT32_ARRAY: return godot::PackedFloat32Array(value).duplicate();
			case Variant::PACKED_INT64_ARRAY: return godot::PackedInt64Array(value).duplicate();
			case Variant::PACKED_INT32_ARRAY: return godot::PackedInt32Array(value).duplicate();
			case Variant::PACKED_BYTE_ARRAY: return godot::PackedByteArray(value).duplicate();
			case Variant::PACKED_STRING_ARRAY: return godot::PackedStringArray(value).duplicate();
			default: return value;
		}
	}

	static bool container(const Variant &value) {
		return value.get_type() == Variant::DICTIONARY || value.get_type() == Variant::ARRAY;
	}

	static int64_t container_size(const Variant &value) {
		if (value.get_type() == Variant::DICTIONARY) return Dictionary(value).size();
		if (value.get_type() == Variant::ARRAY) return Array(value).size();
		return -1;
	}

	bool append_watch(Watch watch, const Variant &live, const Variant &expected, int depth) {
		if (depth > kMaxDepth || watches_.size() >= kMaxWatches || live.get_type() != expected.get_type()) return false;
		if (!container(live)) {
			if (!same_scalar(live, expected)) return false;
			watch.expected = detached_scalar(expected);
			watches_.push_back(std::move(watch));
			return true;
		}
		const int64_t size = container_size(live);
		if (size < 0 || size != container_size(expected) || static_cast<std::size_t>(size) > kMaxWatches) return false;
		watch.expected = live;
		watch.container_size = size;
		watches_.push_back(std::move(watch));
		if (live.get_type() == Variant::DICTIONARY) {
			const Dictionary current = live;
			const Dictionary saved = expected;
			const Array keys = saved.keys(); // preparation only
			for (int64_t i = 0; i < keys.size(); ++i) {
				const Variant key = keys[i];
				if (!current.has(key)) return false;
				Watch child;
				child.source = Parent::DictionaryEntry;
				child.parent = live;
				child.key = key;
				if (!append_watch(std::move(child), current[key], saved[key], depth + 1)) return false;
			}
		} else {
			const Array current = live;
			const Array saved = expected;
			for (int64_t i = 0; i < size; ++i) {
				Watch child;
				child.source = Parent::ArrayEntry;
				child.parent = live;
				child.index = i;
				if (!append_watch(std::move(child), current[i], saved[i], depth + 1)) return false;
			}
		}
		return true;
	}

	bool append_fields(Object *object, const Variant &retained, Parent kind, const Variant &values,
			std::initializer_list<const char *> names) {
		if (!object || values.get_type() != Variant::DICTIONARY) return false;
		const Dictionary saved = values;
		if (saved.size() != static_cast<int64_t>(names.size())) return false;
		for (const char *name : names) {
			const godot::String key(name);
			if (!saved.has(key)) return false;
			Watch watch;
			watch.source = kind;
			watch.parent = retained; // only RefCounted owners are retained
			watch.property = StringName(name);
			if (!append_watch(std::move(watch), object->get(StringName(name)), saved[key], 0)) return false;
		}
		return true;
	}

	bool watch_matches(const Watch &watch, Object *session, Object *sim) const {
		Variant current;
		switch (watch.source) {
			case Parent::SessionProperty: current = session->get(watch.property); break;
			case Parent::SimulationProperty: current = sim->get(watch.property); break;
			case Parent::OwnedProperty: {
				Object *owner = watch.parent;
				if (!owner) return false;
				current = owner->get(watch.property);
				break;
			}
			case Parent::DictionaryEntry: {
				const Dictionary parent = watch.parent;
				current = parent.get(watch.key, Variant());
				if (current.get_type() == Variant::NIL && !parent.has(watch.key)) return false;
				break;
			}
			case Parent::ArrayEntry: {
				const Array parent = watch.parent;
				if (watch.index < 0 || watch.index >= parent.size()) return false;
				current = parent[watch.index];
				break;
			}
		}
		if (watch.container_size >= 0) {
			return current.get_type() == watch.expected.get_type() &&
					godot::UtilityFunctions::is_same(current, watch.expected) && container_size(current) == watch.container_size;
		}
		return same_scalar(current, watch.expected);
	}

	static bool object_variant(const Variant &value) {
		return value.get_type() == Variant::OBJECT && static_cast<Object *>(value) != nullptr;
	}
	static bool instance_matches(const Variant &current, const Variant &expected) {
		return current.get_type() == expected.get_type() && godot::UtilityFunctions::is_same(current, expected);
	}
	static bool read_int(const Variant &value, int64_t &out) {
		if (value.get_type() != Variant::INT) return false;
		out = static_cast<int64_t>(value);
		return out >= 0 && out <= 65536;
	}
	static Dictionary failure(const char *message) {
		Dictionary out;
		out["ok"] = false;
		out["reason"] = godot::String(message);
		return out;
	}

	bool capture(Object *session, Object *identity) {
		if (!session || !identity) return false;
		const Variant owner_value = identity->get("session");
		const Variant sim_value = identity->get("sim");
		if (!object_variant(owner_value) || !object_variant(sim_value)) return false;
		Object *owner = owner_value;
		Object *sim = sim_value;
		if (owner != session || godot::ObjectDB::get_instance(owner->get_instance_id()) != owner ||
				godot::ObjectDB::get_instance(sim->get_instance_id()) != sim) return false;
		session_id_ = owner->get_instance_id();
		sim_id_ = sim->get_instance_id();
		const Variant kind = identity->get("owner_kind");
		if (kind.get_type() != Variant::STRING) return false;
		const godot::String owner_kind = kind;
		if (owner_kind == godot::String("helicopter")) helicopter_ = true;
		else if (owner_kind != godot::String("fixed_wing")) return false;
		session_script_ = identity->get("session_script");
		sim_script_ = identity->get("sim_script");
		environment_ = identity->get("environment");
		environment_script_ = identity->get("environment_script");
		vehicle_ = identity->get("vehicle");
		vehicle_script_ = identity->get("vehicle_script");
		const Variant reference_stage = identity->get("reference_stage");
		if (!object_variant(environment_) || !object_variant(vehicle_) || reference_stage.get_type() != Variant::CALLABLE ||
				!instance_matches(owner->get_script(), session_script_) ||
				static_cast<Object *>(owner->get(p_sim_)) != sim || !instance_matches(sim->get_script(), sim_script_) ||
				!instance_matches(sim->get(p_model_), vehicle_) || !instance_matches(owner->get(p_environment_), environment_)) return false;
		Object *environment = environment_;
		Object *vehicle = vehicle_;
		if (!instance_matches(environment->get_script(), environment_script_) ||
				!instance_matches(vehicle->get_script(), vehicle_script_) ||
				!instance_matches(vehicle->get(p_stage_), reference_stage)) return false;
		if (!read_int(identity->get("input_size"), input_size_) || !read_int(identity->get("aux_size"), aux_size_) ||
				!read_int(identity->get("continuous_size"), continuous_size_) || !read_int(identity->get("modes_size"), modes_size_)) return false;
		ready_ = true;
		if (!configuration_guard_matches(session)) return false;
		const bool session_fields_ok = helicopter_ ?
				append_fields(owner, Variant(), Parent::SessionProperty, identity->get("session_values"),
						{"aircraft", "_trim", "start_choice", "_ready_to_fly"}) :
				append_fields(owner, Variant(), Parent::SessionProperty, identity->get("session_values"), {
						"aircraft", "_hull_contact", "_airframe_surfaces", "_ground_effect_reach", "soft_hull_contacts",
						"_shaft_integrator", "_shaft_explicit", "_shaft_pending_reset"});
		if (!session_fields_ok ||
				!append_fields(environment, environment_, Parent::OwnedProperty, identity->get("environment_values"), {"surfaces", "lake"}) ||
				!append_fields(sim, Variant(), Parent::SimulationProperty, identity->get("sim_values"), {"mass", "inertia", "gravity"}) ||
				!append_fields(vehicle, vehicle_, Parent::OwnedProperty, identity->get("vehicle_values"), {
				"input_size", "aux_size", "modes_size", "continuous_size", "identity", "state_layout_identity", "loads",
				"block_loads", "block_derivative", "stage_rotor_momentum", "rotor_momentum", "pre_tick", "post_tick",
				"post_tick_joint", "block_aux", "step_policy", "events", "substeps", "substeps_joint", "endpoint_transition", "state_validator"})) return false;
		return configuration_guard_matches(session);
	}

public:
	Dictionary prepare_configuration_guard(Object *session, Object *identity) {
		ready_ = false;
		watches_.clear();
		ConfigurationGuard candidate;
		if (!candidate.capture(session, identity)) return failure("configuration guard source differs from its prepared identity");
		*this = std::move(candidate);
		Dictionary out;
		out["ok"] = true;
		out["reason"] = "";
		return out;
	}

	bool configuration_guard_matches(Object *session) const {
		if (!ready_ || !session || godot::ObjectDB::get_instance(session_id_) != session) return false;
		Object *sim = godot::ObjectDB::get_instance(sim_id_);
		if (!sim || !instance_matches(session->get_script(), session_script_) ||
				static_cast<Object *>(session->get(p_sim_)) != sim || !instance_matches(sim->get_script(), sim_script_) ||
				!instance_matches(session->get(p_environment_), environment_) || !instance_matches(sim->get(p_model_), vehicle_)) return false;
		Object *environment = environment_;
		Object *vehicle = vehicle_;
		if (!environment || !vehicle || !instance_matches(environment->get_script(), environment_script_) ||
				!instance_matches(vehicle->get_script(), vehicle_script_)) return false;
		const Variant inputs = sim->get(p_inputs_);
		const Variant aux = sim->get(p_aux_);
		const Variant continuous = sim->get(p_continuous_);
		const Variant modes = sim->get(p_modes_);
		if (inputs.get_type() != Variant::PACKED_FLOAT64_ARRAY || godot::PackedFloat64Array(inputs).size() != input_size_ ||
				aux.get_type() != Variant::PACKED_FLOAT64_ARRAY || godot::PackedFloat64Array(aux).size() != aux_size_ ||
				continuous.get_type() != Variant::PACKED_FLOAT64_ARRAY || godot::PackedFloat64Array(continuous).size() != continuous_size_ ||
				modes.get_type() != Variant::PACKED_INT64_ARRAY || godot::PackedInt64Array(modes).size() != modes_size_) return false;
		for (const Watch &watch : watches_) if (!watch_matches(watch, session, sim)) return false;
		return true;
	}
};

} // namespace nk
