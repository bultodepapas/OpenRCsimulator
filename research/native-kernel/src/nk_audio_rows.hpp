// NK-7f: flight audio's per-frame rows from the accepted rigid-body state, exact: ground_audio_model.gd
// _unloaded_rows (the airborne contact rows) and the source kinematics of flight_audio.gd snapshot. Doubles follow
// math3d.gd's operation order; Frames.ned_to_render narrows to real_t at the render boundary, as GDScript does.
// Presentation only: nothing here reaches the simulation.
#pragma once

#include <cstdint>

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include "nk_math.hpp"

namespace nk {
namespace sound {

struct V3d {
	R x = 0.0, y = 0.0, z = 0.0;
};

inline V3d v3_add(const V3d &a, const V3d &b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
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
};

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
