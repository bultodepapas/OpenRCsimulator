// NK-3: ground terrain sampler (app/physics/ground_terrain.gd sample_validated / _sample_microrelief_validated /
// _compose_lake) and the lake terrain it composes (app/physics/lake_surface.gd sample_covered_terrain_validated,
// sample_terrain_validated, _terrain_point_state, _polygon_state, _bed_depth). Operation order follows the
// current GDScript line by line; tables and the lake are decoded once (prepared), never per query.
#pragma once

#include <array>
#include <vector>

#include "nk_math.hpp"

namespace nk {

using Vec3 = std::array<R, 3>;

constexpr int kSurfaceStride = 6;
constexpr double kRollingRunway = 2.5;
constexpr double kRollingRotorpad = 0.5;
constexpr double kRollingRough = 7.5;
constexpr double kReliefRunway = 0.001;
constexpr double kReliefRotorpad = 0.0;
constexpr double kReliefRough = 0.007;
constexpr double kEdgeBlend = 0.5;
constexpr double kTau = 6.2831853071795864769;
// [weight, wavelength m, north direction, east direction, phase rad] (ground_terrain.gd WAVES).
constexpr double kWaves[3][5] = {
	{0.45, 1.2, 0.8, 0.6, 0.17},
	{0.35, 0.73, -0.35, 0.9367496998, 2.11},
	{0.20, 0.41, 0.6, -0.8, 4.73},
};
constexpr double kLakeSampleEpsilon = 0.025;
constexpr double kLakeEdgeEpsilon = 0.00000001;

struct SurfaceTable {
	std::vector<double> values;
	bool valid = true;
};

struct LakeTerrain {
	bool present = false;
	std::vector<double> shoreline;
	std::vector<double> bank;
	std::vector<R> profile_inset;
	std::vector<R> profile_depth;
	R water_level_down = 0.0;
	double bank_aabb[4] = {kInf, -kInf, kInf, -kInf};
};

// ground_terrain.gd _surface_table_is_valid.
inline bool surface_table_is_valid(const std::vector<double> &surfaces) {
	if (surfaces.empty()) {
		return true;
	}
	if (surfaces.size() % kSurfaceStride != 0) {
		return false;
	}
	const int rows = static_cast<int>(surfaces.size()) / kSurfaceStride;
	const int outside = (rows - 1) * kSurfaceStride;
	if (surfaces[outside] != -kInf || surfaces[outside + 1] != kInf || surfaces[outside + 2] != -kInf ||
			surfaces[outside + 3] != kInf) {
		return false;
	}
	for (int row = 0; row < rows; ++row) {
		const int i = row * kSurfaceStride;
		const double friction = surfaces[i + 4];
		const double rolling = surfaces[i + 5];
		if (!is_finite(friction) || friction < 0.05 || friction > 1.0 || !is_finite(rolling) || rolling < 0.5 ||
				rolling > 20.0) {
			return false;
		}
		if (row == rows - 1) {
			continue;
		}
		if (!is_finite(surfaces[i]) || !is_finite(surfaces[i + 1]) || !is_finite(surfaces[i + 2]) ||
				!is_finite(surfaces[i + 3]) || surfaces[i + 1] <= surfaces[i] || surfaces[i + 3] <= surfaces[i + 2]) {
			return false;
		}
	}
	return true;
}

inline R max_height_validated(const SurfaceTable &table) {
	return table.values.empty() ? 0.0 : kReliefRough;
}

inline R amplitude_for_rolling_factor(R factor) {
	if (factor.v == kRollingRotorpad) {
		return kReliefRotorpad;
	}
	const R t = clampf((factor - kRollingRunway) / (kRollingRough - kRollingRunway), 0.0, 1.0);
	return lerpf(kReliefRunway, kReliefRough, t);
}

// One smoothstep edge value and slope, exactly as the four unrolled blocks of _sample_microrelief_validated.
inline void edge_value_slope(R value, R &out, R &slope) {
	out = 0.0;
	slope = 0.0;
	if (value.v >= kEdgeBlend) {
		out = 1.0;
	} else if (value.v > 0.0) {
		const R t = value / kEdgeBlend;
		out = t * t * (3.0 - 2.0 * t);
		slope = 6.0 * t * (1.0 - t) / kEdgeBlend;
	}
}

inline Vec3 sample_microrelief_validated(R north, R east, const std::vector<double> &surfaces) {
	if (surfaces.empty()) {
		return {0.0, 0.0, 0.0};
	}
	const int rows = static_cast<int>(surfaces.size()) / kSurfaceStride;
	const int last = (rows - 1) * kSurfaceStride;
	R amplitude = amplitude_for_rolling_factor(surfaces[last + 5]);
	R amplitude_north = 0.0;
	R amplitude_east = 0.0;
	for (int row = rows - 2; row > -1; --row) {
		const int i = row * kSurfaceStride;
		const R north_low_value = north - surfaces[i];
		const R north_high_value = surfaces[i + 1] - north;
		const R east_low_value = east - surfaces[i + 2];
		const R east_high_value = surfaces[i + 3] - east;
		R north_low, north_low_slope, north_high, north_high_slope;
		R east_low, east_low_slope, east_high, east_high_slope;
		edge_value_slope(north_low_value, north_low, north_low_slope);
		edge_value_slope(north_high_value, north_high, north_high_slope);
		edge_value_slope(east_low_value, east_low, east_low_slope);
		edge_value_slope(east_high_value, east_high, east_high_slope);
		const R mask_north = north_low * north_high;
		const R mask_east = east_low * east_high;
		const R mask = mask_north * mask_east;
		const R mask_gradient_north = (north_low_slope * north_high - north_low * north_high_slope) * mask_east;
		const R mask_gradient_east = (east_low_slope * east_high - east_low * east_high_slope) * mask_north;
		const R target = amplitude_for_rolling_factor(surfaces[i + 5]);
		const R difference = target - amplitude;
		amplitude_north = amplitude_north * (1.0 - mask) + difference * mask_gradient_north;
		amplitude_east = amplitude_east * (1.0 - mask) + difference * mask_gradient_east;
		amplitude += difference * mask;
	}
	R wave = 0.0;
	R wave_north = 0.0;
	R wave_east = 0.0;
	for (const auto &term : kWaves) {
		const R weight = term[0];
		const R wavelength = term[1];
		const R direction_north = term[2];
		const R direction_east = term[3];
#ifdef NK_MUTATION
		const R phase = kTau / wavelength * (direction_north * north + direction_east * east) + term[4]; // negative control
#else
		const R phase = kTau * (direction_north * north + direction_east * east) / wavelength + term[4];
#endif
		wave += weight * sin_(phase);
		const R slope_scale = weight * kTau / wavelength * cos_(phase);
		wave_north += slope_scale * direction_north;
		wave_east += slope_scale * direction_east;
	}
	const R height = amplitude * wave;
	return {height, amplitude_north * wave + amplitude * wave_north, amplitude_east * wave + amplitude * wave_east};
}

// ---- lake_surface.gd ----

inline R lake_smoothstep(R t_value) {
	const R t = clampf(t_value, 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

inline R lake_polygon_state(const std::vector<double> &polygon, R north, R east) {
	bool inside = false;
	bool on_boundary = false;
	R minimum_sq = kInf;
	const int count = static_cast<int>(polygon.size()) / 2;
	for (int index = 0; index < count; ++index) {
		const int next = index + 1 < count ? index + 1 : 0;
		const R n1 = polygon[index * 2];
		const R e1 = polygon[index * 2 + 1];
		const R n2 = polygon[next * 2];
		const R e2 = polygon[next * 2 + 1];
		const R dn = n2 - n1;
		const R de = e2 - e1;
		const R length_sq = dn * dn + de * de;
		R distance_sq;
		if (length_sq <= 0.0) {
			distance_sq = (north - n1) * (north - n1) + (east - e1) * (east - e1);
		} else {
			const R t = clampf(((north - n1) * dn + (east - e1) * de) / length_sq, 0.0, 1.0);
			const R gap_north = north - (n1 + t * dn);
			const R gap_east = east - (e1 + t * de);
			distance_sq = gap_north * gap_north + gap_east * gap_east;
		}
		minimum_sq = minf(minimum_sq, distance_sq);
		if (distance_sq <= kLakeEdgeEpsilon * kLakeEdgeEpsilon) {
			on_boundary = true;
		}
		if ((n1 > north) != (n2 > north)) {
			const R crossing_east = (e2 - e1) * (north - n1) / (n2 - n1) + e1;
			if (east < crossing_east) {
				inside = !inside;
			}
		}
	}
	const R distance = sqrt_(minimum_sq);
	return on_boundary || inside ? distance : -distance;
}

inline R lake_bed_depth(const LakeTerrain &lake, R inset) {
	const int size = static_cast<int>(lake.profile_inset.size());
	if (size == 0) {
		return kNan;
	}
	for (int index = 0; index < size - 1; ++index) {
		const R first_inset = lake.profile_inset[index];
		const R second_inset = lake.profile_inset[index + 1];
		if (inset <= second_inset) {
			const R t = clampf((inset - first_inset) / (second_inset - first_inset), 0.0, 1.0);
			return lerpf(lake.profile_depth[index], lake.profile_depth[index + 1], lake_smoothstep(t));
		}
	}
	return lake.profile_depth[size - 1];
}

// [in_water, in_bank, shore_distance, bank_distance, blend, depth, ground_down].
struct LakePoint {
	R v[7];
};

inline LakePoint lake_terrain_point_state(const LakeTerrain &lake, R north, R east) {
	const R shore_signed = lake_polygon_state(lake.shoreline, north, east);
	const R bank_signed = lake_polygon_state(lake.bank, north, east);
	const R shore_distance = absf(shore_signed);
	const R bank_distance = absf(bank_signed);
	const bool inside_shoreline = shore_signed >= 0.0;
	const bool inside_bank = bank_signed >= 0.0;
	const bool inside_water = inside_bank && inside_shoreline;
	R blend = 1.0;
	if (!inside_shoreline) {
		if (!inside_bank) {
			blend = 0.0;
		} else {
			const R span = shore_distance + bank_distance;
			blend = span <= 0.0 ? R(1.0) : lake_smoothstep(bank_distance / span);
		}
	}
	const R depth = inside_shoreline ? lake_bed_depth(lake, shore_distance) : R(0.0);
	const R ground_down = inside_shoreline ? lake.water_level_down + depth : lake.water_level_down * blend;
	return {{inside_water ? 1.0 : 0.0, inside_bank ? 1.0 : 0.0, shore_distance, bank_distance, blend, depth,
			ground_down}};
}

inline bool lake_outside_expanded_aabb(const LakeTerrain &lake, R north, R east, double margin) {
	const double *b = lake.bank_aabb;
	return north < b[0] - margin || north > b[1] + margin || east < b[2] - margin || east > b[3] + margin;
}

// The six fields _compose_lake reads, from sample_covered_terrain_validated (finite north/east only).
struct LakeCover {
	bool covered = false;
	R blend = 0.0, blend_north = 0.0, blend_east = 0.0;
	R down = 0.0, down_north = 0.0, down_east = 0.0;
};

inline LakeCover lake_sample_covered(const LakeTerrain &lake, R north, R east) {
	LakeCover out;
	if (lake_outside_expanded_aabb(lake, north, east, kLakeSampleEpsilon)) {
		return out;
	}
	const LakePoint center = lake_terrain_point_state(lake, north, east);
	const bool inside_bank = center.v[1] > 0.5;
	const bool inside_water = center.v[0] > 0.5;
	const R last_inset = lake.profile_inset.back();
	if (inside_water && center.v[2] > last_inset + kLakeSampleEpsilon && center.v[3] > kLakeSampleEpsilon) {
		out.covered = true;
		out.down = center.v[6];
		out.down_north = 0.0;
		out.down_east = 0.0;
		out.blend = center.v[4];
		out.blend_north = 0.0;
		out.blend_east = 0.0;
		return out;
	}
	if (!inside_bank && lake_outside_expanded_aabb(lake, north, east, kLakeSampleEpsilon)) {
		return out;
	}
	if (!inside_bank) {
		return out; // covered = false: _compose_lake ignores the neighbour stencil
	}
	const LakePoint north_plus = lake_terrain_point_state(lake, north + kLakeSampleEpsilon, east);
	const LakePoint north_minus = lake_terrain_point_state(lake, north - kLakeSampleEpsilon, east);
	const LakePoint east_plus = lake_terrain_point_state(lake, north, east + kLakeSampleEpsilon);
	const LakePoint east_minus = lake_terrain_point_state(lake, north, east - kLakeSampleEpsilon);
	out.covered = true;
	out.blend = center.v[4];
	out.blend_north = (north_plus.v[4] - north_minus.v[4]) / (2.0 * kLakeSampleEpsilon);
	out.blend_east = (east_plus.v[4] - east_minus.v[4]) / (2.0 * kLakeSampleEpsilon);
	out.down = center.v[6];
	out.down_north = (north_plus.v[6] - north_minus.v[6]) / (2.0 * kLakeSampleEpsilon);
	out.down_east = (east_plus.v[6] - east_minus.v[6]) / (2.0 * kLakeSampleEpsilon);
	return out;
}

inline Vec3 compose_lake(const Vec3 &base, R north, R east, const LakeTerrain &lake) {
	if (!lake.present) {
		return base;
	}
	const LakeCover basin = lake_sample_covered(lake, north, east);
	if (!basin.covered) {
		return base;
	}
	if (!is_finite(basin.blend) || !is_finite(basin.blend_north) || !is_finite(basin.blend_east) ||
			!is_finite(basin.down) || !is_finite(basin.down_north) || !is_finite(basin.down_east)) {
		return {kNan, kNan, kNan};
	}
	return {
		base[0] * (1.0 - basin.blend) - basin.down,
		base[1] * (1.0 - basin.blend) - base[0] * basin.blend_north - basin.down_north,
		base[2] * (1.0 - basin.blend) - base[0] * basin.blend_east - basin.down_east,
	};
}

// ground_terrain.gd sample_validated (trusted table; the lake is the prepared LakeLoader output or absent).
inline Vec3 terrain_sample_validated(R north, R east, const SurfaceTable &table, const LakeTerrain &lake) {
	if (!is_finite(north) || !is_finite(east)) {
		return {kNan, kNan, kNan};
	}
	const Vec3 base = sample_microrelief_validated(north, east, table.values);
	return compose_lake(base, north, east, lake);
}

// ground_terrain.gd normal_from_up_slopes; returns false for the empty (invalid) result.
inline bool normal_from_up_slopes(R slope_north, R slope_east, Vec3 &normal) {
	if (!is_finite(slope_north) || !is_finite(slope_east)) {
		return false;
	}
	const R length = sqrt_(1.0 + slope_north * slope_north + slope_east * slope_east);
	if (!is_finite(length)) {
		return false;
	}
	normal = {-slope_north / length, -slope_east / length, -1.0 / length};
	return true;
}

} // namespace nk
