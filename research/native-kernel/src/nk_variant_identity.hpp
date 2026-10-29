// Preparation-only memoization for pairs of Godot containers.
#pragma once

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstddef>
#include <unordered_map>
#include <utility>

namespace nk {

struct VariantPairKey {
	const void *live_slot = nullptr;
	const void *expected_slot = nullptr;
	int type = 0;
	int depth = 0;
	bool operator==(const VariantPairKey &other) const {
		return live_slot == other.live_slot && expected_slot == other.expected_slot &&
			type == other.type && depth == other.depth;
	}
};

struct VariantPairHash {
	std::size_t operator()(const VariantPairKey &key) const {
		std::size_t h = std::hash<const void *>{}(key.live_slot);
		h ^= std::hash<const void *>{}(key.expected_slot) + 0x9e3779b9U + (h << 6) + (h >> 2);
		h ^= std::hash<int>{}(key.type) + 0x9e3779b9U + (h << 6) + (h >> 2);
		h ^= std::hash<int>{}(key.depth) + 0x9e3779b9U + (h << 6) + (h >> 2);
		return h;
	}
};

using CompletedVariantPairs = std::unordered_multimap<VariantPairKey,
	std::pair<godot::Variant, godot::Variant>, VariantPairHash>;

// Only call for nonempty, equally sized Array/Dictionary pairs. The address is
// of an element stored inside the container, never the address of a godot-cpp
// wrapper. Parents and the prepared identity must retain both containers and
// neither may mutate while the preparation runs. Empty containers need no
// content traversal and therefore no memo entry.
inline bool variant_pair_key(const godot::Variant &live, const godot::Variant &expected, int depth,
		VariantPairKey &out) {
	using godot::Variant;
	if (live.get_type() != expected.get_type()) return false;
	out.type = static_cast<int>(live.get_type());
	out.depth = depth;
	if (live.get_type() == Variant::ARRAY) {
		const godot::Array current = live, saved = expected;
		if (current.is_empty() || current.size() != saved.size()) return false;
		out.live_slot = &current[0];
		out.expected_slot = &saved[0];
		return true;
	}
	if (live.get_type() == Variant::DICTIONARY) {
		const godot::Dictionary current = live, saved = expected;
		if (current.is_empty() || current.size() != saved.size()) return false;
		const godot::Array keys = saved.keys();
		const Variant first_key = keys[0];
		if (!current.has(first_key)) return false;
		out.live_slot = &current[first_key];
		out.expected_slot = &saved[first_key];
		return true;
	}
	return false;
}

// A key narrows candidates only; is_same verifies both actual container
// identities. Callers insert only after all descendants have been checked.
inline bool variant_pair_completed(const CompletedVariantPairs &completed, const VariantPairKey &key,
		const godot::Variant &live, const godot::Variant &expected) {
	const auto range = completed.equal_range(key);
	for (auto it = range.first; it != range.second; ++it) {
		if (godot::UtilityFunctions::is_same(it->second.first, live) &&
				godot::UtilityFunctions::is_same(it->second.second, expected)) return true;
	}
	return false;
}

} // namespace nk
