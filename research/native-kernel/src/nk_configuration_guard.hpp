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

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <string>
#include <utility>
#include <vector>

#include "nk_guard_plan.hpp"
#include "nk_variant_identity.hpp"

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
		// NK-5c: per-tick fast paths captured at preparation. The parent is the same
		// container instance, and the primed value repeats same_scalar's comparison.
		Dictionary parent_dictionary;
		Array parent_array;
		Variant::Type expected_type = Variant::NIL;
		int64_t expected_int = 0;
		uint64_t expected_bits = 0;
		std::vector<uint8_t> expected_bytes;
	};
	// Validated schemas have bounded nesting; flat model size is owned by the source validator.
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
	// NK-5h per-tick plan (build_plan): root watches and the nested watches engine equality cannot settle, then one
	// engine deep equality per root container against its preparation snapshot. Not ready: the full leaf walk.
	bool plan_ready_ = false;
	std::vector<std::size_t> plan_watches_;
	std::vector<std::pair<std::size_t, Variant>> plan_snapshots_;
	int64_t plan_frozen_roots_ = 0; // NK-6p: root containers the plan proves by identity alone

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

	template <typename P, typename T>
	static void prime_bytes(Watch &watch) {
		const P packed = watch.expected;
		const int64_t size = packed.size();
		watch.expected_bytes.clear();
		if (size > 0) {
			const uint8_t *data = reinterpret_cast<const uint8_t *>(packed.ptr());
			watch.expected_bytes.assign(data, data + static_cast<std::size_t>(size) * sizeof(T));
		}
	}

	// NK-5c: capture the expected scalar once; same_primed then repeats same_scalar per tick.
	static void prime_scalar(Watch &watch) {
		watch.expected_type = watch.expected.get_type();
		switch (watch.expected_type) {
			case Variant::BOOL: watch.expected_int = static_cast<bool>(watch.expected) ? 1 : 0; break;
			case Variant::INT: watch.expected_int = static_cast<int64_t>(watch.expected); break;
			case Variant::FLOAT: {
				const double value = static_cast<double>(watch.expected);
				std::memcpy(&watch.expected_bits, &value, sizeof(double));
				break;
			}
			case Variant::PACKED_FLOAT64_ARRAY: prime_bytes<godot::PackedFloat64Array, double>(watch); break;
			case Variant::PACKED_FLOAT32_ARRAY: prime_bytes<godot::PackedFloat32Array, float>(watch); break;
			case Variant::PACKED_INT64_ARRAY: prime_bytes<godot::PackedInt64Array, int64_t>(watch); break;
			case Variant::PACKED_INT32_ARRAY: prime_bytes<godot::PackedInt32Array, int32_t>(watch); break;
			case Variant::PACKED_BYTE_ARRAY: prime_bytes<godot::PackedByteArray, uint8_t>(watch); break;
			default: break;
		}
	}

	template <typename P, typename T>
	static bool same_bytes(const Variant &current, const std::vector<uint8_t> &expected) {
		const P packed = current;
		const int64_t size = packed.size();
		if (size < 0 || static_cast<std::size_t>(size) * sizeof(T) != expected.size()) return false;
		return size == 0 || std::memcmp(packed.ptr(), expected.data(), expected.size()) == 0;
	}

	// The result of same_scalar(current, watch.expected) for a current value of the expected type.
	static bool same_primed(const Variant &current, Variant::Type type, const Watch &watch) {
		switch (type) {
			case Variant::NIL: return true;
			case Variant::BOOL: return (static_cast<bool>(current) ? 1 : 0) == watch.expected_int;
			case Variant::INT: return static_cast<int64_t>(current) == watch.expected_int;
			case Variant::FLOAT: {
				const double value = static_cast<double>(current);
				uint64_t bits = 0;
				std::memcpy(&bits, &value, sizeof(double));
				return bits == watch.expected_bits;
			}
			case Variant::STRING:
			case Variant::STRING_NAME:
			case Variant::PACKED_STRING_ARRAY:
				return current == watch.expected;
			case Variant::CALLABLE:
				return godot::UtilityFunctions::is_same(current, watch.expected);
			case Variant::PACKED_FLOAT64_ARRAY: return same_bytes<godot::PackedFloat64Array, double>(current, watch.expected_bytes);
			case Variant::PACKED_FLOAT32_ARRAY: return same_bytes<godot::PackedFloat32Array, float>(current, watch.expected_bytes);
			case Variant::PACKED_INT64_ARRAY: return same_bytes<godot::PackedInt64Array, int64_t>(current, watch.expected_bytes);
			case Variant::PACKED_INT32_ARRAY: return same_bytes<godot::PackedInt32Array, int32_t>(current, watch.expected_bytes);
			case Variant::PACKED_BYTE_ARRAY: return same_bytes<godot::PackedByteArray, uint8_t>(current, watch.expected_bytes);
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

	bool append_watch(Watch watch, const Variant &live, const Variant &expected, int depth, CompletedVariantPairs &completed) {
		if (depth > kMaxDepth || watches_.size() == watches_.max_size() || live.get_type() != expected.get_type()) return false;
		if (!container(live)) {
			if (!same_scalar(live, expected)) return false;
			watch.expected = detached_scalar(expected);
			prime_scalar(watch);
			watches_.push_back(std::move(watch));
			return true;
		}
		const int64_t size = container_size(live);
		if (size < 0 || size != container_size(expected)) return false;
		watch.expected = live;
		watch.expected_type = live.get_type();
		watch.container_size = size;
		watches_.push_back(std::move(watch));
		if (size == 0) return true;
		VariantPairKey key;
		if (!variant_pair_key(live, expected, depth, key)) return false;
		if (variant_pair_completed(completed, key, live, expected)) return true;
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
				child.parent_dictionary = current;
				// An untyped dictionary treats a String key and the equal StringName as one key, and the
				// StringName carries its hash, so the per-tick lookup does not rehash the text. Keep it only
				// where this dictionary resolves it (an empty StringName does not hash like the empty String).
				child.key = key;
				if (key.get_type() == Variant::STRING && !current.is_typed_key()) {
					const Variant interned = StringName(godot::String(key));
					if (current.has(interned)) child.key = interned;
				}
				if (!append_watch(std::move(child), current[key], saved[key], depth + 1, completed)) return false;
			}
		} else {
			const Array current = live;
			const Array saved = expected;
			for (int64_t i = 0; i < size; ++i) {
				Watch child;
				child.source = Parent::ArrayEntry;
				child.parent = live;
				child.parent_array = current;
				child.index = i;
				if (!append_watch(std::move(child), current[i], saved[i], depth + 1, completed)) return false;
			}
		}
		// Only completed pairs are memoized: a cycle must still hit kMaxDepth.
		completed.emplace(key, std::make_pair(live, expected));
		return true;
	}

	bool append_fields(Object *object, const Variant &retained, Parent kind, const Variant &values,
			CompletedVariantPairs &completed, std::initializer_list<const char *> names) {
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
			if (!append_watch(std::move(watch), object->get(StringName(name)), saved[key], 0, completed)) return false;
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
				current = watch.parent_dictionary.get(watch.key, Variant());
				if (current.get_type() == Variant::NIL && !watch.parent_dictionary.has(watch.key)) return false;
				break;
			}
			case Parent::ArrayEntry: {
				if (watch.index < 0 || watch.index >= watch.parent_array.size()) return false;
				current = watch.parent_array[watch.index];
				break;
			}
		}
		const Variant::Type type = current.get_type();
		if (type != watch.expected_type) return false;
		if (watch.container_size >= 0) {
			return godot::UtilityFunctions::is_same(current, watch.expected) &&
					(type == Variant::DICTIONARY ? Dictionary(current).size() : Array(current).size()) == watch.container_size;
		}
		return same_primed(current, type, watch);
	}

	// NK-5h: the per-tick plan (rules in nk_guard_plan.hpp). Root watches stay; each root container is compared once
	// with the engine against a deep snapshot; nested watches stay only for leaves engine equality settles less
	// strictly (±0, Callables) and for every container holding one. A NaN, an unsupported value or a snapshot the
	// engine does not accept keeps the full leaf walk.
	// NK-6p: a root container that is read-only all the way down needs no snapshot, and an entry of a read-only
	// container no watch: neither can be replaced while the root watch proves the same instance. A packed array
	// keeps its bitwise watch: its elements stay writable in place under a read-only parent.
	bool build_plan() {
		plan_ready_ = false;
		plan_watches_.clear();
		plan_snapshots_.clear();
		plan_frozen_roots_ = 0;
		const auto refuse = [this] {
			plan_watches_.clear();
			plan_snapshots_.clear();
			return false;
		};
		// Every root container must fit the plan's path budget (nk_guard_plan.hpp kPlanPathBudget): a deeply aliased
		// configuration keeps the full watch walk, which shares each container once.
		for (const Watch &watch : watches_) {
			if (watch.source == Parent::DictionaryEntry || watch.source == Parent::ArrayEntry || watch.container_size < 0) continue;
			int64_t remaining = guard_plan::kPlanPathBudget;
			if (!guard_plan::within_budget(watch.expected, remaining, 0, kMaxDepth)) return refuse();
		}
		for (std::size_t i = 0; i < watches_.size(); ++i) {
			const Watch &watch = watches_[i];
			if (watch.source != Parent::DictionaryEntry && watch.source != Parent::ArrayEntry) {
				plan_watches_.push_back(i);
				if (watch.container_size >= 0 && guard_plan::frozen(watch.expected, 0, kMaxDepth)) {
					++plan_frozen_roots_;
					continue;
				}
				if (watch.container_size >= 0) {
					// A deep copy (nested containers and packed buffers of its own); the engine must accept it.
					const Variant snapshot = watch.expected.duplicate(true);
					if (snapshot.get_type() != watch.expected_type || godot::UtilityFunctions::is_same(snapshot, watch.expected) ||
							!(snapshot == watch.expected)) {
						return refuse();
					}
					plan_snapshots_.emplace_back(i, snapshot);
				}
				continue;
			}
			if ((watch.source == Parent::DictionaryEntry && watch.parent_dictionary.is_read_only()) ||
					(watch.source == Parent::ArrayEntry && watch.parent_array.is_read_only())) {
				// NK-6p: a read-only parent keeps this entry, but not a packed array's elements.
				if (guard_plan::packed(watch.expected)) plan_watches_.push_back(i);
				continue;
			}
			if (watch.container_size >= 0) {
				bool refused = false;
				if (guard_plan::holds_retained(watch.expected, 0, kMaxDepth, refused)) plan_watches_.push_back(i);
				if (refused) return refuse();
				continue;
			}
			switch (guard_plan::classify_scalar(watch.expected)) {
				case guard_plan::Leaf::Retained: plan_watches_.push_back(i); break;
				case guard_plan::Leaf::Refuse: return refuse();
				case guard_plan::Leaf::Exact: break;
			}
		}
		plan_ready_ = true;
		return true;
	}

	bool watches_match(Object *session, Object *sim, bool use_plan) const {
		if (use_plan && plan_ready_) {
			for (const std::size_t i : plan_watches_) if (!watch_matches(watches_[i], session, sim)) return false;
			// Each root watch above proved the live root is its prepared instance (`expected`) of the same size.
			for (const auto &root : plan_snapshots_) if (!(root.second == watches_[root.first].expected)) return false;
			return true;
		}
		for (const Watch &watch : watches_) if (!watch_matches(watch, session, sim)) return false;
		return true;
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
		return out >= 0;
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
		CompletedVariantPairs completed; // preparation only; no cache or allocation per tick
		const bool session_fields_ok = helicopter_ ?
				append_fields(owner, Variant(), Parent::SessionProperty, identity->get("session_values"), completed,
						{"aircraft", "_trim", "start_choice", "_ready_to_fly"}) :
				append_fields(owner, Variant(), Parent::SessionProperty, identity->get("session_values"), completed, {
						"aircraft", "_hull_contact", "_airframe_surfaces", "_ground_effect_reach", "soft_hull_contacts",
						"_shaft_integrator", "_shaft_explicit", "_shaft_pending_reset"});
		if (!session_fields_ok ||
				!append_fields(environment, environment_, Parent::OwnedProperty, identity->get("environment_values"), completed, {"surfaces", "lake"}) ||
				!append_fields(sim, Variant(), Parent::SimulationProperty, identity->get("sim_values"), completed, {"mass", "inertia", "gravity"}) ||
				!append_fields(vehicle, vehicle_, Parent::OwnedProperty, identity->get("vehicle_values"), completed, {
				"input_size", "aux_size", "modes_size", "continuous_size", "identity", "state_layout_identity", "loads",
				"block_loads", "block_derivative", "stage_rotor_momentum", "rotor_momentum", "pre_tick", "post_tick",
				"post_tick_joint", "block_aux", "step_policy", "events", "substeps", "substeps_joint", "endpoint_transition", "state_validator"})) return false;
		build_plan(); // a refused plan keeps the full leaf walk
		return matches(session, false) && configuration_guard_matches(session);
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

	// NK-5h research diagnostic: per-category cost of the per-tick watch loop and of its access pieces.
	Dictionary profile(Object *session, int64_t iterations) const {
		Dictionary out;
		if (!ready_ || !session || iterations < 1) return out;
		Object *sim = godot::ObjectDB::get_instance(sim_id_);
		if (!sim) return out;
		static const char *kSources[] = {"session", "sim", "owned", "dict", "array"};
		std::vector<std::pair<std::string, std::vector<const Watch *>>> groups;
		for (const Watch &watch : watches_) {
			std::string name = std::string(kSources[static_cast<int>(watch.source)]) + ":" +
					godot::String(Variant::get_type_name(watch.expected_type)).utf8().get_data();
			if (watch.source == Parent::DictionaryEntry) name += watch.key.get_type() == Variant::STRING_NAME ? "[sn]" : "[str]";
			bool found = false;
			for (auto &group : groups) {
				if (group.first == name) { group.second.push_back(&watch); found = true; break; }
			}
			if (!found) groups.push_back({name, {&watch}});
		}
		auto timed = [&](auto &&body) {
			const auto start = std::chrono::steady_clock::now();
			for (int64_t k = 0; k < iterations; ++k) body();
			return std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - start).count() / iterations;
		};
		bool sink = true;
		for (const auto &group : groups) {
			const double n = static_cast<double>(group.second.size());
			Dictionary row;
			row["count"] = static_cast<int64_t>(group.second.size());
			row["match_ns"] = timed([&] { for (const Watch *w : group.second) sink = watch_matches(*w, session, sim) && sink; }) / n;
			if (group.second.front()->source == Parent::DictionaryEntry) {
				row["get_ns"] = timed([&] { for (const Watch *w : group.second) sink = w->parent_dictionary.get(w->key, Variant()).get_type() != Variant::OBJECT && sink; }) / n;
				row["has_ns"] = timed([&] { for (const Watch *w : group.second) sink = w->parent_dictionary.has(w->key) && sink; }) / n;
			}
			if (group.second.front()->source == Parent::ArrayEntry) {
				row["index_ns"] = timed([&] { for (const Watch *w : group.second) sink = (&w->parent_array[w->index] != nullptr) && sink; }) / n;
			}
			row["type_ns"] = timed([&] { for (const Watch *w : group.second) sink = w->expected.get_type() != Variant::OBJECT && sink; }) / n;
			out[godot::String(group.first.c_str())] = row;
		}
		out["whole_ns"] = timed([&] { sink = configuration_guard_matches(session) && sink; });
		out["full_ns"] = timed([&] { sink = matches(session, false) && sink; });
		out["plan_ready"] = plan_ready_;
		out["plan_watches"] = static_cast<int64_t>(plan_watches_.size());
		out["plan_snapshots"] = static_cast<int64_t>(plan_snapshots_.size());
		out["plan_frozen_roots"] = plan_frozen_roots_;
		for (const auto &root : plan_snapshots_) {
			const Watch &watch = watches_[root.first];
			const godot::String name = godot::String("root ") + godot::String(watch.property);
			Dictionary row;
			row["equal_ns"] = timed([&] { sink = (root.second == watch.expected) && sink; });
			row["size"] = watch.container_size;
			out[name] = row;
		}
		out["sink"] = sink;
		out["watches"] = static_cast<int64_t>(watches_.size());
		return out;
	}

	bool configuration_guard_matches(Object *session) const { return matches(session, true); }

	bool plan_ready() const { return plan_ready_; }

private:
	bool matches(Object *session, bool use_plan) const {
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
		return watches_match(session, sim, use_plan);
	}
};

} // namespace nk
