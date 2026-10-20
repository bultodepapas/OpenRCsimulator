## LU-25-R2: original caller methods; unchanged helpers inherited from production.
extends "res://physics/ground_terrain.gd"


static func sample(north: float, east: float, surfaces: PackedFloat64Array, lake: Dictionary = {}) -> PackedFloat64Array:
	if not is_finite(north) or not is_finite(east) or not is_valid_surface_table(surfaces) \
		or (not lake.is_empty() and not LakeSurface.is_valid_definition(lake)):
		return PackedFloat64Array([NAN, NAN, NAN])
	return sample_validated(north, east, surfaces, lake)


static func sample_validated(north: float, east: float, surfaces: PackedFloat64Array,
		lake: Dictionary = {}) -> PackedFloat64Array:
	if not is_finite(north) or not is_finite(east):
		return PackedFloat64Array([NAN, NAN, NAN])
	var base: PackedFloat64Array = _sample_microrelief_validated(north, east, surfaces)
	if lake.is_empty():
		return base
	# `lake` is immutable normalized output from LakeLoader. Keep this hot path validation-free; the
	# public `sample` entry point checks untrusted lake dictionaries before calling here.
	var basin: Dictionary = LakeSurface.sample_terrain_validated(lake, north, east)
	if not bool(basin.get("covered", false)):
		return base # outside the bounded bank, preserve the existing field sample exactly
	var blend: float = float(basin.blend_fraction)
	var blend_north: float = float(basin.blend_slope_north)
	var blend_east: float = float(basin.blend_slope_east)
	var down: float = float(basin.ground_down_m)
	var down_north: float = float(basin.slope_north)
	var down_east: float = float(basin.slope_east)
	if not is_finite(blend) or not is_finite(blend_north) or not is_finite(blend_east) \
		or not is_finite(down) or not is_finite(down_north) or not is_finite(down_east):
		return PackedFloat64Array([NAN, NAN, NAN])
	# The lake is NED positive-down. The authored microrelief is faded across the bank so the
	# composite joins the unchanged field at blend=0 and the surveyed bed at blend=1.
	return PackedFloat64Array([
		base[0] * (1.0 - blend) - down,
		base[1] * (1.0 - blend) - base[0] * blend_north - down_north,
		base[2] * (1.0 - blend) - base[0] * blend_east - down_east,
	])
