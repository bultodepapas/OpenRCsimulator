## LU-25-R2: original full terrain query; unchanged geometry helpers inherited.
extends "res://physics/lake_surface.gd"


static func sample_terrain_validated(lake: Dictionary, north: float, east: float) -> Dictionary:
	if not is_finite(north) or not is_finite(east):
		return _invalid_sample()
	# Keep the four finite-difference neighbors, but resolve each point's shoreline/bank distances once.
	# The older nested helpers repeated the same polygon scans for contains, blend, depth and height.
	var center: PackedFloat64Array = _terrain_point_state(lake, north, east)
	var inside_bank: bool = center[1] > 0.5
	var inside_water: bool = center[0] > 0.5
	var signed_shore_distance: float = center[2] if inside_water else -center[2]
	var signed_bank_distance: float = center[3] if inside_bank else -center[3]
	if not inside_bank and _outside_expanded_polygon_aabb(lake.bank_ne_m, north, east, SAMPLE_EPSILON_M):
		return {
			"covered": false,
			"region": "outside",
			"ground_down_m": 0.0,
			"slope_north": 0.0,
			"slope_east": 0.0,
			"blend_fraction": 0.0,
			"blend_slope_north": 0.0,
			"blend_slope_east": 0.0,
			"bed_depth_m": 0.0,
			"bed_depth_slope_north": 0.0,
			"bed_depth_slope_east": 0.0,
			"signed_shore_distance_m": signed_shore_distance,
			"signed_bank_distance_m": signed_bank_distance,
			"water_down_m": float(lake.water_level_down_m),
			"depth_m": 0.0,
		}
	var north_plus: PackedFloat64Array = _terrain_point_state(lake, north + SAMPLE_EPSILON_M, east)
	var north_minus: PackedFloat64Array = _terrain_point_state(lake, north - SAMPLE_EPSILON_M, east)
	var east_plus: PackedFloat64Array = _terrain_point_state(lake, north, east + SAMPLE_EPSILON_M)
	var east_minus: PackedFloat64Array = _terrain_point_state(lake, north, east - SAMPLE_EPSILON_M)
	var blend_fraction: float = center[4]
	var bed_depth: float = center[5]
	var blend_north: float = (north_plus[4] - north_minus[4]) / (2.0 * SAMPLE_EPSILON_M)
	var blend_east: float = (east_plus[4] - east_minus[4]) / (2.0 * SAMPLE_EPSILON_M)
	var depth_north: float = (north_plus[5] - north_minus[5]) / (2.0 * SAMPLE_EPSILON_M)
	var depth_east: float = (east_plus[5] - east_minus[5]) / (2.0 * SAMPLE_EPSILON_M)
	if not inside_bank:
		return {
			"covered": false,
			"region": "outside",
			"ground_down_m": 0.0,
			"slope_north": 0.0,
			"slope_east": 0.0,
			"blend_fraction": 0.0,
			"blend_slope_north": blend_north,
			"blend_slope_east": blend_east,
			"bed_depth_m": 0.0,
			"bed_depth_slope_north": depth_north,
			"bed_depth_slope_east": depth_east,
			"signed_shore_distance_m": signed_shore_distance,
			"signed_bank_distance_m": signed_bank_distance,
			"water_down_m": float(lake.water_level_down_m),
			"depth_m": 0.0,
		}
	var region: String = "bed" if inside_water else "bank"
	var height_down: float = center[6]
	var north_slope: float = (north_plus[6] - north_minus[6]) / (2.0 * SAMPLE_EPSILON_M)
	var east_slope: float = (east_plus[6] - east_minus[6]) / (2.0 * SAMPLE_EPSILON_M)
	return {
		"covered": true,
		"region": region,
		"ground_down_m": height_down,
		"slope_north": north_slope,
		"slope_east": east_slope,
		"blend_fraction": blend_fraction,
		"blend_slope_north": blend_north,
		"blend_slope_east": blend_east,
		"bed_depth_m": bed_depth,
		"bed_depth_slope_north": depth_north,
		"bed_depth_slope_east": depth_east,
		"signed_shore_distance_m": signed_shore_distance,
		"signed_bank_distance_m": signed_bank_distance,
		"water_down_m": float(lake.water_level_down_m),
		"depth_m": bed_depth,
	}
