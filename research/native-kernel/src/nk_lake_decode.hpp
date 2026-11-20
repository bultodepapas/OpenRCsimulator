// Shared prepared-lake decoder, moved verbatim from nk_kernel.cpp decode_lake so the fixed-wing stage and the
// helicopter stage decode the same lake identically (lake_surface.gd _polygon_aabb of the bank). Dec supplies
// number(d, key, R&, required), vec<T>(d, key, std::vector<T>&, required) and fail(message) with the kernel
// Decoder's semantics. Structural checks only; LakeSurface.is_valid_definition is established by the GDScript owner.
#pragma once

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <string>
#include <vector>

#include "nk_terrain.hpp"

namespace nk {

template <typename Dec>
bool decode_lake_prepared(Dec &dec, const godot::Dictionary &lake, LakeTerrain &out) {
	out = LakeTerrain();
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
	if (!lake.has("bed_profile") || lake["bed_profile"].get_type() != godot::Variant::ARRAY) {
		return dec.fail("lake bed_profile");
	}
	const godot::Array profile = lake["bed_profile"];
	if (profile.is_empty()) {
		return dec.fail("empty lake bed_profile");
	}
	for (int64_t i = 0; i < profile.size(); ++i) {
		if (profile[i].get_type() != godot::Variant::DICTIONARY) {
			return dec.fail("lake bed_profile row");
		}
		const godot::Dictionary row = profile[i];
		R inset = 0.0, depth = 0.0;
		if (!dec.number(row, "inset_m", inset, true) || !dec.number(row, "depth_m", depth, true)) {
			return false;
		}
		out.profile_inset.push_back(inset);
		out.profile_depth.push_back(depth);
	}
	// lake_surface.gd _polygon_aabb of the bank.
	double north_min = kInf, north_max = -kInf, east_min = kInf, east_max = -kInf;
	for (size_t index = 0; index < out.bank.size(); index += 2) {
		north_min = minf(north_min, out.bank[index]).v;
		north_max = maxf(north_max, out.bank[index]).v;
		east_min = minf(east_min, out.bank[index + 1]).v;
		east_max = maxf(east_max, out.bank[index + 1]).v;
	}
	out.bank_aabb[0] = north_min;
	out.bank_aabb[1] = north_max;
	out.bank_aabb[2] = east_min;
	out.bank_aabb[3] = east_max;
	return true;
}

// The kernel Decoder's number/vec semantics (nk_kernel.cpp) over another decoder's error channel, so a lake
// decoded for the helicopter is byte-identical to the fixed-wing decode (no extra finiteness or length rule).
template <typename Fail>
struct KernelLakeDecoder {
	Fail &failer;

	bool fail(const std::string &message) { return failer.fail(message); }

	bool number(const godot::Dictionary &d, const char *key, R &out, bool required, double fallback = 0.0) {
		if (!d.has(key)) {
			if (required) {
				return fail(std::string("missing ") + key);
			}
			out = fallback;
			return true;
		}
		const godot::Variant value = d[key];
		if (value.get_type() == godot::Variant::FLOAT) {
			out = static_cast<double>(value);
			return true;
		}
		if (value.get_type() == godot::Variant::INT) {
			out = static_cast<double>(static_cast<int64_t>(value));
			return true;
		}
		return fail(std::string("non-numeric ") + key);
	}

	template <typename T>
	bool vec(const godot::Dictionary &d, const char *key, std::vector<T> &out, bool required, int size = -1) {
		out.clear();
		if (!d.has(key)) {
			return required ? fail(std::string("missing ") + key) : true;
		}
		const godot::Variant value = d[key];
		if (value.get_type() != godot::Variant::PACKED_FLOAT64_ARRAY) {
			return fail(std::string("expected PackedFloat64Array ") + key);
		}
		const godot::PackedFloat64Array packed = value;
		if (size >= 0 && packed.size() != size) {
			return fail(std::string("unexpected size ") + key);
		}
		if (!packed.is_empty()) out.assign(packed.ptr(), packed.ptr() + packed.size());
		return true;
	}
};

} // namespace nk
