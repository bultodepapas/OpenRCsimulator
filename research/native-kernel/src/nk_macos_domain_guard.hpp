// DT-MAC automatic-domain guard: immutable container topology plus detached
// snapshots of packed numeric leaves. Prepared outside the tick; no physics.
#pragma once

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <utility>
#include <vector>

namespace nk {

class MacosDomainGuard {
	using Variant = godot::Variant;
	using Dictionary = godot::Dictionary;
	using Array = godot::Array;

	// Experimental retained-leaf candidate: only real-engine mutation and resize
	// controls can establish that this reference follows every live packed edit.
	struct Watch {
		Variant live;
		Variant::Type type = Variant::NIL;
		std::vector<uint8_t> bytes;
	};

	// Preparation must remain bounded even for an unexpected graph or cycle.
	static constexpr int kMaxDepth = 32;
	static constexpr std::size_t kMaxNodes = 2000000;
	static constexpr std::size_t kMaxPackedLeaves = 262144;
	static constexpr std::size_t kMaxPackedBytes = 64 * 1024 * 1024;

	bool ready_ = false;
	Variant world_;
	Variant field_;
	std::size_t nodes_ = 0;
	std::size_t packed_bytes_ = 0;
	std::vector<Watch> watches_;

	static bool scalar_key(const Variant &value) {
		switch (value.get_type()) {
			case Variant::NIL:
			case Variant::BOOL:
			case Variant::INT:
			case Variant::FLOAT:
			case Variant::STRING:
			case Variant::STRING_NAME: return true;
			default: return false;
		}
	}

	template <typename P, typename E>
	bool capture_packed(const Variant &value, Watch &watch) {
		const P packed = value;
		if (packed.size() < 0 || static_cast<std::size_t>(packed.size()) >
				(kMaxPackedBytes - packed_bytes_) / sizeof(E)) return false;
		const std::size_t size = static_cast<std::size_t>(packed.size()) * sizeof(E);
		watch.bytes.resize(size);
		if (size != 0) std::memcpy(watch.bytes.data(), packed.ptr(), size);
		packed_bytes_ += size;
		return true;
	}

	template <typename P, typename E>
	static bool packed_matches(const Variant &value, const Watch &watch) {
		const P packed = value;
		if (packed.size() < 0 || static_cast<std::size_t>(packed.size()) != watch.bytes.size() / sizeof(E)) return false;
		return watch.bytes.empty() || std::memcmp(packed.ptr(), watch.bytes.data(), watch.bytes.size()) == 0;
	}

	bool visit(const Variant &value, int depth) {
		if (depth > kMaxDepth || ++nodes_ > kMaxNodes) return false;
		if (value.get_type() == Variant::DICTIONARY) {
			const Dictionary dict = value;
			if (!dict.is_read_only()) return false;
			if (dict.size() < 0 || static_cast<std::size_t>(dict.size()) > kMaxNodes - nodes_) return false;
			const Array keys = dict.keys(); // Only during preparation.
			for (int64_t i = 0; i < keys.size(); ++i) {
				const Variant child_key = keys[i];
				if (!scalar_key(child_key) || !visit(dict[child_key], depth + 1)) return false;
			}
			return true;
		}
		if (value.get_type() == Variant::ARRAY) {
			const Array array = value;
			if (!array.is_read_only()) return false;
			if (array.size() < 0 || static_cast<std::size_t>(array.size()) > kMaxNodes - nodes_) return false;
			for (int64_t i = 0; i < array.size(); ++i) {
				if (!visit(array[i], depth + 1)) return false;
			}
			return true;
		}
		if (scalar_key(value)) return true;
		if (watches_.size() >= kMaxPackedLeaves) return false;
		Watch watch;
		watch.live = value;
		watch.type = value.get_type();
		bool ok = false;
		switch (watch.type) {
			case Variant::PACKED_BYTE_ARRAY: ok = capture_packed<godot::PackedByteArray, uint8_t>(value, watch); break;
			case Variant::PACKED_INT32_ARRAY: ok = capture_packed<godot::PackedInt32Array, int32_t>(value, watch); break;
			case Variant::PACKED_INT64_ARRAY: ok = capture_packed<godot::PackedInt64Array, int64_t>(value, watch); break;
			case Variant::PACKED_FLOAT32_ARRAY: ok = capture_packed<godot::PackedFloat32Array, float>(value, watch); break;
			case Variant::PACKED_FLOAT64_ARRAY: ok = capture_packed<godot::PackedFloat64Array, double>(value, watch); break;
			default: return false; // Objects, unsupported packed types, etc. never qualify.
		}
		if (!ok) return false;
		watches_.push_back(std::move(watch));
		return true;
	}

	static bool watch_matches(const Watch &watch) {
		const Variant &current = watch.live;
		if (current.get_type() != watch.type) return false;
		switch (watch.type) {
			case Variant::PACKED_BYTE_ARRAY: return packed_matches<godot::PackedByteArray, uint8_t>(current, watch);
			case Variant::PACKED_INT32_ARRAY: return packed_matches<godot::PackedInt32Array, int32_t>(current, watch);
			case Variant::PACKED_INT64_ARRAY: return packed_matches<godot::PackedInt64Array, int64_t>(current, watch);
			case Variant::PACKED_FLOAT32_ARRAY: return packed_matches<godot::PackedFloat32Array, float>(current, watch);
			case Variant::PACKED_FLOAT64_ARRAY: return packed_matches<godot::PackedFloat64Array, double>(current, watch);
			default: return false;
		}
	}

public:
	Dictionary prepare(const Dictionary &world, const Dictionary &field) {
		ready_ = false;
		watches_.clear();
		MacosDomainGuard candidate;
		candidate.world_ = world;
		candidate.field_ = field;
		Dictionary result;
		if (!candidate.visit(candidate.world_, 0) || !candidate.visit(candidate.field_, 0)) {
			result["ok"] = false;
			result["reason"] = "domain context is mutable, unsupported, cyclic or exceeds guard limits";
			return result;
		}
		candidate.ready_ = true;
		*this = std::move(candidate);
		result["ok"] = true;
		result["reason"] = "";
		result["nodes"] = static_cast<int64_t>(nodes_);
		result["packed_leaves"] = static_cast<int64_t>(watches_.size());
		result["packed_bytes"] = static_cast<int64_t>(packed_bytes_);
		return result;
	}

	bool matches(const Dictionary &world, const Dictionary &field) const {
		if (!ready_ || !godot::UtilityFunctions::is_same(world_, Variant(world)) ||
				!godot::UtilityFunctions::is_same(field_, Variant(field))) return false;
		for (const Watch &watch : watches_) if (!watch_matches(watch)) return false;
		return true;
	}
};

} // namespace nk
