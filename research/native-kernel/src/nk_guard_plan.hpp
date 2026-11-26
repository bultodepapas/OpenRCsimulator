// NK-5h: the per-tick plan rules shared by the configuration and weather guards.
//
// Engine Dictionary/Array equality (recursive_equal through Variant::hash_compare) is type-strict and independent of
// key order. It compares sizes, strings, ints, bools and packed bytes exactly, and floats with ==. For the guards' bit
// equality that leaves two gaps: the sign of zero (+0 == -0), and NaN, which no plan ever holds (a NaN keeps the full
// leaf walk). A leaf whose engine equality is weaker than the guard's keeps its own watch: a ±0 float, a packed float
// array with a ±0 element, and a Callable (compared by identity). Every container holding such a leaf keeps its
// identity watch too, whichever path reaches it, so the retained leaf watch reads the live container at that path
// instead of a container replaced by an equal copy. Every other nested container is settled by content.
#pragma once

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>
#include <cstring>

namespace nk {
namespace guard_plan {

enum class Leaf { Exact, Retained, Refuse };

inline bool zero_bits64(uint64_t bits) { return (bits & ~(uint64_t(1) << 63)) == 0; }
inline bool nan_bits64(uint64_t bits) {
	return (bits & 0x7ff0000000000000ULL) == 0x7ff0000000000000ULL && (bits & 0x000fffffffffffffULL) != 0;
}
inline bool zero_bits32(uint32_t bits) { return (bits & ~(uint32_t(1) << 31)) == 0; }
inline bool nan_bits32(uint32_t bits) { return (bits & 0x7f800000U) == 0x7f800000U && (bits & 0x007fffffU) != 0; }

// How engine equality settles a non-container value against the guards' comparison.
inline Leaf classify_scalar(const godot::Variant &value) {
	switch (value.get_type()) {
		case godot::Variant::FLOAT: {
			const double number = static_cast<double>(value);
			uint64_t bits = 0;
			std::memcpy(&bits, &number, sizeof(bits));
			if (nan_bits64(bits)) return Leaf::Refuse;
			return zero_bits64(bits) ? Leaf::Retained : Leaf::Exact;
		}
		case godot::Variant::PACKED_FLOAT64_ARRAY: {
			const godot::PackedFloat64Array packed = value;
			const double *data = packed.ptr();
			bool zero = false;
			for (int64_t i = 0; i < packed.size(); ++i) {
				uint64_t bits = 0;
				std::memcpy(&bits, &data[i], sizeof(bits));
				if (nan_bits64(bits)) return Leaf::Refuse;
				zero = zero || zero_bits64(bits);
			}
			return zero ? Leaf::Retained : Leaf::Exact;
		}
		case godot::Variant::PACKED_FLOAT32_ARRAY: {
			const godot::PackedFloat32Array packed = value;
			const float *data = packed.ptr();
			bool zero = false;
			for (int64_t i = 0; i < packed.size(); ++i) {
				uint32_t bits = 0;
				std::memcpy(&bits, &data[i], sizeof(bits));
				if (nan_bits32(bits)) return Leaf::Refuse;
				zero = zero || zero_bits32(bits);
			}
			return zero ? Leaf::Retained : Leaf::Exact;
		}
		case godot::Variant::CALLABLE:
			return Leaf::Retained;
		case godot::Variant::NIL:
		case godot::Variant::BOOL:
		case godot::Variant::INT:
		case godot::Variant::STRING:
		case godot::Variant::STRING_NAME:
		case godot::Variant::PACKED_STRING_ARRAY:
		case godot::Variant::PACKED_INT64_ARRAY:
		case godot::Variant::PACKED_INT32_ARRAY:
		case godot::Variant::PACKED_BYTE_ARRAY:
			return Leaf::Exact;
		default:
			return Leaf::Refuse;
	}
}

// Whether a value holds a Retained leaf anywhere below it. `refuse` reports a NaN, an unsupported value or excess
// depth anywhere in it (the whole tree is scanned).
inline bool holds_retained(const godot::Variant &value, int depth, int max_depth, bool &refuse) {
	if (depth > max_depth) {
		refuse = true;
		return false;
	}
	bool found = false;
	if (value.get_type() == godot::Variant::DICTIONARY) {
		const godot::Dictionary dictionary = value;
		const godot::Array values = dictionary.values();
		for (int64_t i = 0; i < values.size(); ++i) found = holds_retained(values[i], depth + 1, max_depth, refuse) || found;
		return found;
	}
	if (value.get_type() == godot::Variant::ARRAY) {
		const godot::Array array = value;
		for (int64_t i = 0; i < array.size(); ++i) found = holds_retained(array[i], depth + 1, max_depth, refuse) || found;
		return found;
	}
	const Leaf leaf = classify_scalar(value);
	if (leaf == Leaf::Refuse) refuse = true;
	return leaf == Leaf::Retained;
}

} // namespace guard_plan
} // namespace nk
