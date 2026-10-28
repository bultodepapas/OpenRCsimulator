// NK-3 weather provider ownership guard. The stage uses no reference callbacks;
// this guard only checks that its once-validated source objects and inputs still
// match. prepare_weather_guard builds all watch records; weather_guard_matches
// performs no configuration construction, decoding, hashing, serialization or
// weather evaluation. The session and simulation Nodes are held by ObjectID,
// so their native stage owner cannot create a reference cycle.
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
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cmath>
#include <cstddef>
#include <cstring>
#include <initializer_list>
#include <string>
#include <utility>
#include <vector>

namespace nk {

class WeatherGuard {
	using Variant = godot::Variant;
	using Object = godot::Object;
	using Dictionary = godot::Dictionary;
	using Array = godot::Array;
	using StringName = godot::StringName;

	// Property, dictionary entry, and array entry point to an already-owned
	// parent. A container record also pins identity and its initial size.
	enum class Parent { Property, DictionaryEntry, ArrayEntry };
	struct Watch {
		Parent source = Parent::Property;
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
	Variant model_;
	Variant model_script_;
	Variant environment_;
	Variant environment_script_;
	Variant field_;
	Variant field_script_;
	Variant spatial_;
	Variant spatial_script_;
	Variant thermal_;
	Variant thermal_script_;
	Variant turbulence_;
	double fixed_dt_ = 0.0;
	double dt_ = 0.0;
	int64_t physics_rate_ = 0;
	uint64_t engine_id_ = 0;
	int64_t aux_size_ = 0;
	int64_t turbulence_aux_index_ = -1;
	std::vector<Watch> watches_;

	// Interned once with the guard, never manufactured during the tick check.
	StringName p_session_ = "session";
	StringName p_sim_ = "sim";
	StringName p_model_ = "model";
	StringName p_environment_ = "environment";
	StringName p_weather_ = "weather";
	StringName p_spatial_ = "_spatial";
	StringName p_thermal_ = "_thermal_field";
	StringName p_turbulence_ = "turbulence";
	StringName p_fixed_dt_ = "_fixed_dt";
	StringName p_physics_rate_ = "physics_ticks_per_second";
	StringName p_aux_ = "aux";
	StringName p_turbulence_index_ = "_turbulence_aux_index";
	StringName p_pending_ = "_weather_pending_reset";
	StringName p_ready_to_fly_ = "_ready_to_fly";

	static bool same_bits(double a, double b) { return std::memcmp(&a, &b, sizeof(double)) == 0; }

	template <typename P, typename T>
	static bool same_packed(const Variant &a, const Variant &b) {
		const P left = a;
		const P right = b;
		return left.size() == right.size() && (left.size() == 0 ||
				std::memcmp(left.ptr(), right.ptr(), static_cast<std::size_t>(left.size()) * sizeof(T)) == 0);
	}

	// Types are checked before values, and signed zero/NaN payloads remain
	// significant. Configurations have bounded trees of only these types.
	static bool same_scalar(const Variant &a, const Variant &b) {
		if (a.get_type() != b.get_type()) return false;
		switch (a.get_type()) {
			case Variant::NIL:
			case Variant::BOOL:
			case Variant::INT:
			case Variant::STRING:
			case Variant::STRING_NAME:
				return a == b;
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
			case Variant::PACKED_STRING_ARRAY:
				return a == b;
			default:
				return false;
		}
	}

	static Variant detached_scalar(const Variant &value) {
		switch (value.get_type()) {
			case Variant::PACKED_FLOAT64_ARRAY: return godot::PackedFloat64Array(value).duplicate();
			case Variant::PACKED_FLOAT32_ARRAY: return godot::PackedFloat32Array(value).duplicate();
			case Variant::PACKED_INT64_ARRAY: return godot::PackedInt64Array(value).duplicate();
			case Variant::PACKED_INT32_ARRAY: return godot::PackedInt32Array(value).duplicate();
			case Variant::PACKED_BYTE_ARRAY: return godot::PackedByteArray(value).duplicate();
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

	// Construct watchers from the real live object and detached GDScript
	// baseline. Reject any mismatch at preparation, including malformed types,
	// omitted keys, and differing signed zeros. No live container is frozen.
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
		watch.expected = live; // exact live reference, not the detached content
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

	bool append_fields(const Variant &provider, const Variant &values,
			std::initializer_list<const char *> names) {
		if (provider.get_type() != Variant::OBJECT || values.get_type() != Variant::DICTIONARY) return false;
		Object *object = provider;
		const Dictionary saved = values;
		if (!object || saved.size() != static_cast<int64_t>(names.size())) return false;
		for (const char *name : names) {
			const godot::String key(name);
			if (!saved.has(key)) return false;
			Watch watch;
			watch.source = Parent::Property;
			watch.parent = provider; // Variant keeps RefCounted provider alive
			watch.property = StringName(name);
			if (!append_watch(std::move(watch), object->get(StringName(name)), saved[key], 0)) return false;
		}
		return true;
	}

	bool watch_matches(const Watch &watch) const {
		Variant current;
		switch (watch.source) {
			case Parent::Property: {
				Object *provider = watch.parent;
				if (!provider) return false;
				current = provider->get(watch.property);
				break;
			}
			case Parent::DictionaryEntry: {
				const Dictionary parent = watch.parent;
				// Dictionary::get does not construct a keys array. The missing-key
				// ambiguity matters only when the retrieved value is NIL.
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

	static Dictionary failure(const char *message) {
		Dictionary out;
		out["ok"] = false;
		out["reason"] = godot::String(message);
		return out;
	}

	static bool object_variant(const Variant &value) {
		return value.get_type() == Variant::OBJECT && static_cast<Object *>(value) != nullptr;
	}

	static bool instance_matches(const Variant &current, const Variant &expected) {
		return current.get_type() == expected.get_type() && godot::UtilityFunctions::is_same(current, expected);
	}

	bool capture(Object *session, Object *identity) {
		if (!session || !identity) return false;
		const Variant identity_session = identity->get(p_session_);
		const Variant identity_sim = identity->get(p_sim_);
		if (!object_variant(identity_session) || !object_variant(identity_sim)) return false;
		Object *owner = identity_session;
		Object *sim = identity_sim;
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
		model_ = identity->get("model");
		model_script_ = identity->get("model_script");
		environment_ = identity->get("environment");
		environment_script_ = identity->get("environment_script");
		field_ = identity->get("field");
		field_script_ = identity->get("field_script");
		spatial_ = identity->get("spatial");
		spatial_script_ = identity->get("spatial_script");
		thermal_ = identity->get("thermal");
		thermal_script_ = identity->get("thermal_script");
		turbulence_ = identity->get("turbulence");
		if (!instance_matches(owner->get_script(), session_script_) ||
				static_cast<Object *>(owner->get(p_sim_)) != sim || !instance_matches(sim->get_script(), sim_script_) ||
				!instance_matches(sim->get(p_model_), model_) || !object_variant(model_)) return false;
		Object *model = model_;
		if (!instance_matches(model->get_script(), model_script_)) return false;
		const Variant expected_dt = identity->get("dt");
		const Variant expected_aux_size = identity->get("aux_size");
		const Variant expected_index = identity->get("turbulence_aux_index");
		const Variant fixed_dt = sim->get(p_fixed_dt_);
		if (!object_variant(model_) || !object_variant(environment_) || !object_variant(field_) ||
				turbulence_.get_type() != Variant::CALLABLE || expected_dt.get_type() != Variant::FLOAT ||
				expected_aux_size.get_type() != Variant::INT || expected_index.get_type() != Variant::INT ||
				fixed_dt.get_type() != Variant::FLOAT) return false;
		dt_ = static_cast<double>(expected_dt);
		fixed_dt_ = static_cast<double>(fixed_dt);
		aux_size_ = static_cast<int64_t>(expected_aux_size);
		turbulence_aux_index_ = static_cast<int64_t>(expected_index);
		if (!std::isfinite(dt_) || dt_ <= 0.0 || !std::isfinite(fixed_dt_) || aux_size_ < 0) return false;
		if (fixed_dt_ <= 0.0) {
			const StringName engine_name("Engine");
			auto raw_engine = godot::gdextension_interface::global_get_singleton(engine_name._native_ptr());
			Object *engine = raw_engine ? godot::internal::get_object_instance_binding(raw_engine) : nullptr;
			if (!engine) return false;
			engine_id_ = engine->get_instance_id();
			const Variant rate = engine->get(p_physics_rate_);
			if (rate.get_type() != Variant::INT || static_cast<int64_t>(rate) <= 0) return false;
			physics_rate_ = static_cast<int64_t>(rate);
			if (!same_bits(dt_, 1.0 / static_cast<double>(physics_rate_))) return false;
		} else if (!same_bits(dt_, fixed_dt_)) {
			return false;
		}
		// Validate every owner and script before touching provider properties.
		// Script fields are plain variables only on the admitted built-in scripts.
		ready_ = true;
		if (!weather_guard_matches(session)) return false;
		if (!append_fields(field_, identity->get("field_values"), {
				"_config", "_atmosphere", "_atmosphere_active", "_vertical_air", "_rho", "_engine_charge",
				"_mean_ned", "_gust_ned", "_gust_duration_s", "_gust_period_s", "_gust_delay_s", "_has_gust",
				"_calm", "_turbulent", "_turbulence_rms", "_turbulence_tau", "_turbulence_seed"})) return false;
		if (object_variant(spatial_)) {
			if (!append_fields(spatial_, identity->get("spatial_values"), {
					"_config", "_reference_speed", "_roughness_length", "_displacement_height", "_wall_height", "_surface_top",
					"_free_air_join_height", "_direction_cosine", "_direction_sine", "_log_denominator", "_wall_scale",
					"_wall_scale_slope", "_gust_transition_height", "_gust_values", "_gust_max_duration", "_turbulence_rms", "_modes"})) return false;
			if (object_variant(thermal_)) {
				if (!append_fields(thermal_, identity->get("thermal_values"), {"_config"})) return false;
			} else if (thermal_.get_type() != Variant::NIL) return false;
		} else if (spatial_.get_type() != Variant::NIL || thermal_.get_type() != Variant::NIL) return false;
		ready_ = true;
		return weather_guard_matches(session);
	}

public:
	// An unsuccessful preparation disarms the previous guard. identity is the
	// result of NativeWeather.prepare, already validated against the reference.
	Dictionary prepare_weather_guard(Object *session, Object *identity) {
		ready_ = false;
		watches_.clear();
		WeatherGuard candidate;
		if (!candidate.capture(session, identity)) return failure("weather guard source differs from its validated identity");
		*this = std::move(candidate);
		Dictionary out;
		out["ok"] = true;
		out["reason"] = "";
		return out;
	}

	bool weather_guard_matches(Object *session) const {
		if (!ready_ || !session || godot::ObjectDB::get_instance(session_id_) != session) return false;
		Object *sim = godot::ObjectDB::get_instance(sim_id_);
		if (!sim || !instance_matches(session->get_script(), session_script_) ||
				static_cast<Object *>(session->get(p_sim_)) != sim || !instance_matches(sim->get_script(), sim_script_) ||
				!instance_matches(sim->get(p_model_), model_)) return false;
		Object *model = model_;
		if (!model || !instance_matches(model->get_script(), model_script_)) return false;
		const Variant pending = session->get(helicopter_ ? p_ready_to_fly_ : p_pending_);
		const Variant fixed = sim->get(p_fixed_dt_);
		const Variant aux = sim->get(p_aux_);
		if (pending.get_type() != Variant::BOOL || static_cast<bool>(pending) != helicopter_ || fixed.get_type() != Variant::FLOAT ||
				aux.get_type() != Variant::PACKED_FLOAT64_ARRAY ||
				godot::PackedFloat64Array(aux).size() != aux_size_) return false;
		const double live_fixed_dt = static_cast<double>(fixed);
		// First reset commits the same effective fallback dt into the simulation.
		// This is the only permitted change to a captured unset raw clock.
		const bool captured_raw_clock = same_bits(live_fixed_dt, fixed_dt_);
		if (!captured_raw_clock && !(engine_id_ != 0 && same_bits(live_fixed_dt, dt_))) return false;
		if (!helicopter_) {
			const Variant index = session->get(p_turbulence_index_);
			if (index.get_type() != Variant::INT || static_cast<int64_t>(index) != turbulence_aux_index_) return false;
		}
		if (engine_id_ != 0 && captured_raw_clock) {
			Object *engine = godot::ObjectDB::get_instance(engine_id_);
			if (!engine) return false;
			const Variant rate = engine->get(p_physics_rate_);
			if (rate.get_type() != Variant::INT || static_cast<int64_t>(rate) != physics_rate_) return false;
		}
		if (!instance_matches(session->get(p_environment_), environment_)) return false;
		Object *environment = environment_;
		if (!environment || !instance_matches(environment->get_script(), environment_script_) ||
				!instance_matches(environment->get(p_weather_), field_) ||
				!instance_matches(environment->get(p_turbulence_), turbulence_)) return false;
		Object *field = field_;
		if (!field || !instance_matches(field->get_script(), field_script_) ||
				!instance_matches(field->get(p_spatial_), spatial_)) return false;
		if (object_variant(spatial_)) {
			Object *spatial = spatial_;
			if (!instance_matches(spatial->get_script(), spatial_script_) ||
					!instance_matches(spatial->get(p_thermal_), thermal_)) return false;
			if (object_variant(thermal_)) {
				Object *thermal = thermal_;
				if (!instance_matches(thermal->get_script(), thermal_script_)) return false;
			}
		}
		for (const Watch &watch : watches_) if (!watch_matches(watch)) return false;
		return true;
	}
};

} // namespace nk
