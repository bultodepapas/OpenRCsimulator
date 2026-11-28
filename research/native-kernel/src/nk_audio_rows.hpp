// NK-7f: flight audio's per-frame rows from the accepted rigid-body state, exact: ground_audio_model.gd
// _unloaded_rows (the airborne contact rows) and the source kinematics of flight_audio.gd snapshot. Doubles follow
// math3d.gd's operation order; Frames.ned_to_render narrows to real_t at the render boundary, as GDScript does.
// Presentation only: nothing here reaches the simulation.
#pragma once

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include "nk_math.hpp"
#include "nk_terrain.hpp"
#include "nk_wheels.hpp"

namespace nk {
namespace sound {

struct V3d {
	R x = 0.0, y = 0.0, z = 0.0;
};

inline V3d v3_add(const V3d &a, const V3d &b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
inline V3d v3_scale(const V3d &a, R k) { return {a.x * k, a.y * k, a.z * k}; }
inline R v3_dot(const V3d &a, const V3d &b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline V3d v3_cross(const V3d &a, const V3d &b) {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
// math3d.gd q_rotate, q = [w, x, y, z].
inline V3d q_rotate_gd(const R q[4], const V3d &v) {
	const R tx = (q[2] * v.z - q[3] * v.y) * R(2.0);
	const R ty = (q[3] * v.x - q[1] * v.z) * R(2.0);
	const R tz = (q[1] * v.y - q[2] * v.x) * R(2.0);
	return {(v.x + tx * q[0]) + (q[2] * tz - q[3] * ty), (v.y + ty * q[0]) + (q[3] * tx - q[1] * tz),
		(v.z + tz * q[0]) + (q[1] * ty - q[2] * tx)};
}
// Frames.ned_to_render: Vector3(ned[1], -ned[2], -ned[0]).
inline godot::Vector3 ned_to_render(const V3d &n) {
	return godot::Vector3(static_cast<float>(n.y.v), static_cast<float>(-n.z.v), static_cast<float>(-n.x.v));
}

// The row keys, owned by the kernel instance that builds rows (StringNames must not outlive the engine).
struct RowKeys {
	godot::StringName id{"id"}, position{"position"}, velocity{"velocity_mps"}, force{"force_n"},
		normal{"surface_normal"}, normal_force{"normal_force_n"}, reference{"reference_load_n"},
		compression{"compression_m"}, approach{"approach_speed_mps"}, rolling{"rolling_speed_mps"}, rim{"rim_speed_mps"},
		surface{"surface"}, material{"material_id"}, resolved{"material_resolved"}, fallback{"surface_audio_fallback"},
		region{"surface_region_id"}, grounded{"grounded"}, roll{"roll_enabled"};
	// NK-7j: the loaded rows' region keys and string values; ground_audio_model.gd MATERIAL_ROLL_FAMILIES.
	godot::StringName region_id{"region_id"}, material_id{"material_id"};
	godot::String hard{"hard"}, grass{"grass"}, gravel{"gravel"}, unspecified{"unspecified"};
	godot::String grass_materials[3] = {"maintained_turf", "mown_grass", "long_grass"};
	godot::String hard_materials[3] = {"dry_pavement", "asphalt", "concrete"};
};

// NK-7j: GroundSupport.sample's LEGACY law as Environment.sample_support evaluates it (no road or track overlay; the
// stage's validated table and lake): the surface row of a successful sample (-1 where it fails) and whether the lake
// covers the point. Doubles follow ground_support.gd's operation order; only finiteness reaches the answer besides.
struct SupportAnswer {
	int64_t row = -1;
	bool covered = false;
};

inline SupportAnswer support_sample(const V3d &p, const V3d &v, double time_s, const SurfaceTable &table,
		const LakeTerrain &lake) {
	SupportAnswer out;
	if (!is_finite(p.x) || !is_finite(p.y) || !is_finite(p.z) || !is_finite(v.x) || !is_finite(v.y) || !is_finite(v.z) ||
			!std::isfinite(time_s) || time_s < 0.0) {
		return out;
	}
	const Vec3 height = terrain_sample_validated(p.x, p.y, table, lake);
	if (!is_finite(height[0]) || !is_finite(height[1]) || !is_finite(height[2])) return out;
	Vec3 normal;
	if (!normal_from_up_slopes(height[1], height[2], normal)) return out;
	int64_t row = 0;
	const std::vector<double> &s = table.values;
	if (!s.empty()) {
		std::size_t offset = 0;
		while (offset + kSurfaceStride < s.size()) {
			if (p.x.v >= s[offset] && p.x.v <= s[offset + 1] && p.y.v >= s[offset + 2] && p.y.v <= s[offset + 3]) break;
			offset += kSurfaceStride;
		}
		row = static_cast<int64_t>(offset / kSurfaceStride);
	}
	const R gap = -p.z - height[0];
	const R gradient[3] = {-height[1], -height[2], R(-1.0)};
	const R gap_rate = gradient[0] * v.x + gradient[1] * v.y + gradient[2] * v.z;
	const R normal_speed = normal[0] * v.x + normal[1] * v.y + normal[2] * v.z;
	if (!is_finite(gap) || !is_finite(gap_rate) || !is_finite(normal_speed)) return out;
	out.row = row;
	out.covered = lake.present && lake_sample_covered(lake, p.x, p.y).covered;
	return out;
}

// ground_audio_model.gd MATERIAL_ROLL_FAMILIES' family for a resolved material, or empty.
inline godot::String roll_family(const RowKeys &k, const godot::String &material) {
	for (const godot::String &name : k.grass_materials) {
		if (material == name) return k.grass;
	}
	for (const godot::String &name : k.hard_materials) {
		if (material == name) return k.hard;
	}
	return material == k.gravel ? k.gravel : godot::String();
}

// One contact's values for a snapshot_contacts row: its frame (position, normal, compression, long speed), the force
// and the rim speed. The point velocity, approach speed, normal force, rolling speed and support follow from them.
struct RowInput {
	V3d position;
	V3d normal;
	R compression = 0.0;
	R long_speed = 0.0;
	V3d force;
	double rim = 0.0;
};

// The point velocity of the contact at `arm` (snapshot_contacts' kinematics), q = [w, x, y, z].
inline V3d point_velocity(const double *s, const R q[4], const V3d &arm) {
	return q_rotate_gd(q, v3_add(V3d{s[3], s[4], s[5]}, v3_cross(V3d{s[10], s[11], s[12]}, arm)));
}

// snapshot_contacts' row for one contact, appended to `rows`: the approach speed, normal force and rolling speed in its
// operation order, and surface_observation over the environment's prepared support, whose `regions` name each surface
// row (a lake-covered point has no measured material). False for a region entry the reference would not read as
// strings.
inline bool append_row(godot::Array &rows, const RowKeys &k, const godot::String &id, const RowInput &in,
		const V3d &velocity, double reference_load, double time_s, const SurfaceTable &table, const LakeTerrain &lake,
		const godot::Array &regions) {
	const R zero = 0.0;
	const R approach = maxf(zero, -v3_dot(velocity, in.normal));
	const R normal_force = maxf(zero, v3_dot(in.force, in.normal));
	const R rolling = maxf(R(godot::UtilityFunctions::absf(in.long_speed.v)), R(godot::UtilityFunctions::absf(in.rim)));
	const SupportAnswer support = support_sample(in.position, velocity, time_s, table, lake);
	godot::String region_id, material = k.unspecified, surface = k.hard;
	bool resolved = false, fallback = true;
	if (support.row >= 0) {
		if (support.row >= regions.size() || regions[support.row].get_type() != godot::Variant::DICTIONARY) return false;
		const godot::Dictionary region = regions[support.row];
		const godot::Variant id_value = region.get(k.region_id, godot::Variant());
		const godot::Variant material_value = region.get(k.material_id, godot::Variant());
		if (id_value.get_type() != godot::Variant::STRING || material_value.get_type() != godot::Variant::STRING) {
			return false;
		}
		region_id = id_value;
		if (!support.covered) material = material_value;
		resolved = material != k.unspecified;
		const godot::String family = resolved ? roll_family(k, material) : godot::String();
		if (!family.is_empty()) {
			surface = family;
			fallback = false;
		}
	}
	godot::Dictionary row;
	row[k.id] = id;
	row[k.position] = ned_to_render(in.position);
	row[k.velocity] = ned_to_render(velocity);
	row[k.force] = ned_to_render(in.force);
	row[k.normal] = ned_to_render(in.normal);
	row[k.normal_force] = normal_force.v;
	row[k.reference] = reference_load;
	row[k.compression] = in.compression.v;
	row[k.approach] = approach.v;
	row[k.rolling] = rolling.v;
	row[k.rim] = in.rim;
	row[k.surface] = surface;
	row[k.material] = material;
	row[k.resolved] = resolved;
	row[k.fallback] = fallback;
	row[k.region] = region_id;
	row[k.grounded] = normal_force.v > 0.0;
	row[k.roll] = true;
	rows.push_back(row);
	return true;
}

// NK-7j: snapshot_contacts' loaded rows from the native wheel rows of the published endpoint (NK-6o): _row_kinematics,
// the force and load arithmetic, and the support. wheel_rows: kWheelRowSize values per contact, in contact order; arms
// and ids: every contact's position and identity. Empty for malformed input or an unreadable region entry.
inline godot::Array loaded_rows(const RowKeys &k, const godot::PackedFloat64Array &state, const double *wheel_rows,
		int64_t count, const godot::PackedFloat64Array &arms, const godot::PackedStringArray &ids, double reference_load,
		double time_s, const SurfaceTable &table, const LakeTerrain &lake, const godot::Array &regions) {
	godot::Array rows;
	if (state.size() < 13 || wheel_rows == nullptr || count <= 0 || count != ids.size() || arms.size() != count * 3 ||
			table.values.empty()) {
		return rows;
	}
	const double *s = state.ptr();
	const R q[4] = {s[6], s[7], s[8], s[9]};
	const R zero = 0.0;
	for (int64_t i = 0; i < count; ++i) {
		const double *w = wheel_rows + i * kWheelRowSize;
		RowInput in;
		in.position = V3d{w[5], w[6], w[7]};
		in.normal = V3d{w[8], w[9], w[10]};
		in.compression = w[4];
		in.long_speed = w[17];
		const V3d heading{w[11], w[12], w[13]};
		const V3d side{w[14], w[15], w[16]};
		const R normal_load = maxf(zero, R(w[0]));
		in.force = v3_add(v3_scale(in.normal, normal_load), v3_add(v3_scale(heading, R(w[1])), v3_scale(side, R(w[2]))));
		in.rim = w[3];
		const V3d velocity = point_velocity(s, q, V3d{arms[i * 3], arms[i * 3 + 1], arms[i * 3 + 2]});
		if (!append_row(rows, k, ids[i], in, velocity, reference_load, time_s, table, lake, regions)) return godot::Array();
	}
	return rows;
}

// NK-7k: snapshot_contacts' rows where every wheel is beyond the terrain's reach but not clear of the ground (the
// native wheel rows' [0]): Wheels.frame for each contact (`frames`, the stage's own law), no wheel diagnostics, and
// Ground.loads answering no loads beyond that same reach bound, so the force stays [0, 0, 0] and the rim speed 0.
// Empty for malformed input or an unreadable region entry.
inline godot::Array band_rows(const RowKeys &k, const godot::PackedFloat64Array &state,
		const std::vector<WheelFrame> &frames, const godot::PackedFloat64Array &arms, const godot::PackedStringArray &ids,
		double reference_load, double time_s, const SurfaceTable &table, const LakeTerrain &lake,
		const godot::Array &regions) {
	godot::Array rows;
	const int64_t count = static_cast<int64_t>(frames.size());
	if (state.size() < 13 || count <= 0 || count != ids.size() || arms.size() != count * 3 || table.values.empty()) {
		return rows;
	}
	const double *s = state.ptr();
	const R q[4] = {s[6], s[7], s[8], s[9]};
	for (int64_t i = 0; i < count; ++i) {
		const WheelFrame &f = frames[static_cast<size_t>(i)];
		RowInput in;
		in.position = V3d{f.position[0], f.position[1], f.position[2]};
		in.normal = V3d{f.normal[0], f.normal[1], f.normal[2]};
		in.compression = f.compression;
		in.long_speed = f.long_speed;
		in.force = V3d{0.0, 0.0, 0.0};
		const V3d velocity = point_velocity(s, q, V3d{arms[i * 3], arms[i * 3 + 1], arms[i * 3 + 2]});
		if (!append_row(rows, k, ids[i], in, velocity, reference_load, time_s, table, lake, regions)) return godot::Array();
	}
	return rows;
}

// NK-7k: GroundAudioModel.approach_speeds' values: each contact's approach speed against its Wheels.frame normal
// (`frames`), in contact order. Empty for malformed input.
inline godot::PackedFloat64Array approach_speeds(const godot::PackedFloat64Array &state,
		const std::vector<WheelFrame> &frames, const godot::PackedFloat64Array &arms) {
	godot::PackedFloat64Array out;
	const int64_t count = static_cast<int64_t>(frames.size());
	if (state.size() < 13 || count <= 0 || arms.size() != count * 3) return out;
	const double *s = state.ptr();
	const R q[4] = {s[6], s[7], s[8], s[9]};
	out.resize(count);
	for (int64_t i = 0; i < count; ++i) {
		const WheelFrame &f = frames[static_cast<size_t>(i)];
		const V3d velocity = point_velocity(s, q, V3d{arms[i * 3], arms[i * 3 + 1], arms[i * 3 + 2]});
		out[i] = maxf(R(0.0), -v3_dot(velocity, V3d{f.normal[0], f.normal[1], f.normal[2]})).v;
	}
	return out;
}

// _unloaded_rows. state: the 13 rigid-body values; arms: 3 per row (contacts with a position, in order); ids: their
// identities. Returns the rows as GDScript builds them, or an empty array for malformed input.
inline godot::Array unloaded_rows(const RowKeys &k, const godot::PackedFloat64Array &state,
		const godot::PackedFloat64Array &arms, const godot::PackedStringArray &ids, double reference_load) {
	godot::Array rows;
	if (state.size() < 13 || arms.size() != ids.size() * 3) return rows;
	const double *s = state.ptr();
	const R q[4] = {s[6], s[7], s[8], s[9]};
	const V3d origin{s[0], s[1], s[2]};
	const V3d base_velocity{s[3], s[4], s[5]};
	const V3d body_rate{s[10], s[11], s[12]};
	const V3d zero{0.0, 0.0, 0.0};
	const V3d up{0.0, 0.0, -1.0};
	for (int64_t i = 0; i < ids.size(); ++i) {
		const V3d arm{arms[i * 3], arms[i * 3 + 1], arms[i * 3 + 2]};
		const V3d point_velocity = q_rotate_gd(q, v3_add(base_velocity, v3_cross(body_rate, arm)));
		const V3d position_ned = v3_add(origin, q_rotate_gd(q, arm));
		godot::Dictionary row;
		row[k.id] = ids[i];
		row[k.position] = ned_to_render(position_ned);
		row[k.velocity] = ned_to_render(point_velocity);
		row[k.force] = ned_to_render(zero);
		row[k.normal] = ned_to_render(up);
		row[k.normal_force] = 0.0;
		row[k.reference] = reference_load;
		row[k.compression] = position_ned.z.v;
		row[k.approach] = maxf(0.0, point_velocity.z).v;
		row[k.rolling] = 0.0;
		row[k.rim] = 0.0;
		row[k.surface] = godot::String("hard");
		row[k.material] = godot::String("unspecified");
		row[k.resolved] = false;
		row[k.fallback] = true;
		row[k.region] = godot::String();
		row[k.grounded] = false;
		row[k.roll] = true;
		rows.push_back(row);
	}
	return rows;
}

// flight_audio.gd snapshot's source kinematics: [source xyz, source velocity xyz, exhaust xyz] in render axes
// (real_t values). offset: the propulsion offset; axis: the thrust axis, or empty for no exhaust (zero).
inline godot::PackedFloat64Array source_kinematics(const godot::PackedFloat64Array &state,
		const godot::PackedFloat64Array &offset, const godot::PackedFloat64Array &axis) {
	godot::PackedFloat64Array out;
	if (state.size() < 13 || offset.size() < 3 || (!axis.is_empty() && axis.size() < 3)) return out;
	const double *s = state.ptr();
	const R q[4] = {s[6], s[7], s[8], s[9]};
	const godot::Vector3 velocity = ned_to_render(q_rotate_gd(q, V3d{s[3], s[4], s[5]}));
	const V3d arm{-offset[0], offset[1], -offset[2]};
	const V3d source_ned = v3_add(V3d{s[0], s[1], s[2]}, q_rotate_gd(q, arm));
	const godot::Vector3 source_velocity =
		velocity + ned_to_render(q_rotate_gd(q, v3_cross(V3d{s[10], s[11], s[12]}, arm)));
	const godot::Vector3 source = ned_to_render(source_ned);
	godot::Vector3 exhaust;
	if (!axis.is_empty()) exhaust = ned_to_render(q_rotate_gd(q, V3d{-axis[0], -axis[1], -axis[2]}));
	out.resize(9);
	const godot::Vector3 values[3] = {source, source_velocity, exhaust};
	for (int k = 0; k < 3; ++k) {
		out[k * 3] = values[k].x;
		out[k * 3 + 1] = values[k].y;
		out[k * 3 + 2] = values[k].z;
	}
	return out;
}

} // namespace sound
} // namespace nk
