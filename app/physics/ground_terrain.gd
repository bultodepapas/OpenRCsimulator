# GP-01: deterministic, analytic micro-relief over the validated field surface rectangles.
# Inputs use local NED north/east coordinates; output height and slope are positive upward.
# The surface table is the six-float GroundSurfaces rectangle format. Keep this module independent
# of Ground/ground_contact so it can be called by physics and rendering without a dependency cycle.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")

const SURFACE_STRIDE := 6
const ROLLING_RUNWAY := 2.5
const ROLLING_ROTORPAD := 0.5
const ROLLING_MOWN := 5.0
const ROLLING_ROUGH := 7.5

# Estimated GP-00 engineering envelope, not measured RC turf. It represents load-bearing soil relief,
# not blade height: 1 mm runway, 4 mm mown, 7 mm rough; smooth amplitude transitions span 0.5 m.
const RELIEF_RUNWAY_M := 0.001
const RELIEF_ROTORPAD_M := 0.0
const RELIEF_MOWN_M := 0.004
const RELIEF_ROUGH_M := 0.007
const EDGE_BLEND_M := 0.5

# [weight, wavelength m, north direction, east direction, phase rad]. Weights sum to one, so the
# absolute terrain height is bounded by its surface amplitude. Wavelengths and directions are
# deterministic estimates (0.41–1.2 m), not a surveyed field profile.
const WAVES := [
	[0.45, 1.2, 0.8, 0.6, 0.17],
	[0.35, 0.73, -0.35, 0.9367496998, 2.11],
	[0.20, 0.41, 0.6, -0.8, 4.73],
]
const TAU := 6.2831853071795864769


## Returns [height_up_m, dh/dnorth, dh/deast]. An empty table is the explicit flat fixture;
## malformed inputs fail closed with NANs so a broken surface table cannot silently fly flat.
static func sample(north: float, east: float, surfaces: PackedFloat64Array, lake: Dictionary = {}) -> PackedFloat64Array:
	if not is_finite(north) or not is_finite(east) or not is_valid_surface_table(surfaces) \
		or (not lake.is_empty() and not LakeSurface.is_valid_definition(lake)):
		return PackedFloat64Array([NAN, NAN, NAN])
	return sample_validated(north, east, surfaces, lake)


## Fast path for trusted callers that validate the immutable surface table once before evaluating multiple wheels.
## Still rejects non-finite coordinates. Empty input remains the flat fixture.
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


## Original GP-01 sampler. Keep its operation order intact so the no-lake path remains bit-identical.
static func _sample_microrelief_validated(north: float, east: float,
		surfaces: PackedFloat64Array) -> PackedFloat64Array:
	if surfaces.is_empty():
		return PackedFloat64Array([0.0, 0.0, 0.0])
	var rows: int = surfaces.size() / SURFACE_STRIDE
	var last: int = (rows - 1) * SURFACE_STRIDE
	var amplitude: float = amplitude_for_rolling_factor(surfaces[last + 5])
	var amplitude_north := 0.0
	var amplitude_east := 0.0
	# The packed table is highest-precedence first; compose catchall toward runway.
	for row in range(rows - 2, -1, -1):
		var i: int = row * SURFACE_STRIDE
		var north_min: float = surfaces[i]
		var north_max: float = surfaces[i + 1]
		var east_min: float = surfaces[i + 2]
		var east_max: float = surfaces[i + 3]
		var north_low_value: float = north - north_min
		var north_high_value: float = north_max - north
		var east_low_value: float = east - east_min
		var east_high_value: float = east_max - east
		# Evaluate each edge's value and slope together. Keep the original
		# arithmetic order (including signed zero) while avoiding eight script
		# calls and repeated transition divisions for every surface/query.
		var north_low := 0.0
		var north_low_slope := 0.0
		if north_low_value >= EDGE_BLEND_M:
			north_low = 1.0
		elif north_low_value > 0.0:
			var t := north_low_value / EDGE_BLEND_M
			north_low = t * t * (3.0 - 2.0 * t)
			north_low_slope = 6.0 * t * (1.0 - t) / EDGE_BLEND_M
		var north_high := 0.0
		var north_high_slope := 0.0
		if north_high_value >= EDGE_BLEND_M:
			north_high = 1.0
		elif north_high_value > 0.0:
			var t := north_high_value / EDGE_BLEND_M
			north_high = t * t * (3.0 - 2.0 * t)
			north_high_slope = 6.0 * t * (1.0 - t) / EDGE_BLEND_M
		var east_low := 0.0
		var east_low_slope := 0.0
		if east_low_value >= EDGE_BLEND_M:
			east_low = 1.0
		elif east_low_value > 0.0:
			var t := east_low_value / EDGE_BLEND_M
			east_low = t * t * (3.0 - 2.0 * t)
			east_low_slope = 6.0 * t * (1.0 - t) / EDGE_BLEND_M
		var east_high := 0.0
		var east_high_slope := 0.0
		if east_high_value >= EDGE_BLEND_M:
			east_high = 1.0
		elif east_high_value > 0.0:
			var t := east_high_value / EDGE_BLEND_M
			east_high = t * t * (3.0 - 2.0 * t)
			east_high_slope = 6.0 * t * (1.0 - t) / EDGE_BLEND_M
		var mask_north: float = north_low * north_high
		var mask_east: float = east_low * east_high
		var mask: float = mask_north * mask_east
		var mask_gradient_north: float = (north_low_slope * north_high
			- north_low * north_high_slope) * mask_east
		var mask_gradient_east: float = (east_low_slope * east_high
			- east_low * east_high_slope) * mask_north
		var target: float = amplitude_for_rolling_factor(surfaces[i + 5])
		var difference: float = target - amplitude
		amplitude_north = amplitude_north * (1.0 - mask) + difference * mask_gradient_north
		amplitude_east = amplitude_east * (1.0 - mask) + difference * mask_gradient_east
		amplitude += difference * mask
	var wave := 0.0
	var wave_north := 0.0
	var wave_east := 0.0
	for term: Array in WAVES:
		var weight: float = term[0]
		var wavelength: float = term[1]
		var direction_north: float = term[2]
		var direction_east: float = term[3]
		var phase: float = TAU * (direction_north * north + direction_east * east) / wavelength + float(term[4])
		wave += weight * M.sin_(phase)
		var slope_scale: float = weight * TAU / wavelength * M.cos_(phase)
		wave_north += slope_scale * direction_north
		wave_east += slope_scale * direction_east
	var height: float = amplitude * wave
	return PackedFloat64Array([
		height,
		amplitude_north * wave + amplitude * wave_north,
		amplitude_east * wave + amplitude * wave_east,
	])


## Conservative positive height envelope for gear reach and visual placement.
static func max_height(surfaces: PackedFloat64Array) -> float:
	if not is_valid_surface_table(surfaces):
		return NAN
	return max_height_validated(surfaces)


## Conservative bound for trusted tables. Every accepted rolling factor maps to ≤ 7 mm by clamped profile.
static func max_height_validated(surfaces: PackedFloat64Array) -> float:
	if surfaces.is_empty():
		return 0.0
	return RELIEF_ROUGH_M


## Validate the local six-float contract without depending on GroundSurfaces (which depends on contact code).
## Production tables are already validated upstream; this guard also protects test tools and future callers.
static func is_valid_surface_table(surfaces: PackedFloat64Array) -> bool:
	if surfaces.is_empty():
		return true
	if surfaces.size() % SURFACE_STRIDE != 0:
		return false
	var rows: int = surfaces.size() / SURFACE_STRIDE
	var outside: int = (rows - 1) * SURFACE_STRIDE
	if surfaces[outside] != -INF or surfaces[outside + 1] != INF \
		or surfaces[outside + 2] != -INF or surfaces[outside + 3] != INF:
		return false
	for row in rows:
		var i: int = row * SURFACE_STRIDE
		var friction: float = surfaces[i + 4]
		var rolling: float = surfaces[i + 5]
		if not is_finite(friction) or friction < 0.05 or friction > 1.0 \
			or not is_finite(rolling) or rolling < 0.5 or rolling > 20.0:
			return false
		if row == rows - 1:
			continue
		if not is_finite(surfaces[i]) or not is_finite(surfaces[i + 1]) \
			or not is_finite(surfaces[i + 2]) or not is_finite(surfaces[i + 3]) \
			or surfaces[i + 1] <= surfaces[i] or surfaces[i + 3] <= surfaces[i + 2]:
			return false
	return true


## Temporary profile proxy: the existing stride-6 surface table has friction and rolling multipliers but no
## material/type ID, so terrain amplitude follows its current rolling factors: 2.5 runway, 5 mown, 7.5 rough.
## This is not a physical dependency between C_rr and soil height. If those factors are tuned independently,
## add a surface-class channel at the GroundSurfaces boundary before changing this mapping.
## Linear interpolation preserves a useful intermediate if a field uses another validated factor.
static func amplitude_for_rolling_factor(factor: float) -> float:
	if factor == ROLLING_ROTORPAD:
		return RELIEF_ROTORPAD_M
	var t: float = clampf((factor - ROLLING_RUNWAY) / (ROLLING_ROUGH - ROLLING_RUNWAY), 0.0, 1.0)
	return lerpf(RELIEF_RUNWAY_M, RELIEF_ROUGH_M, t)


## Values used by the ground shader. They match amplitude_for_rolling_factor at the current
## runway/mown/rough factors; categories and boundaries come from the same field surface data.
static func renderer_profile() -> Dictionary:
	return {
		"runway_amplitude_m": amplitude_for_rolling_factor(ROLLING_RUNWAY),
		"rotorpad_amplitude_m": amplitude_for_rolling_factor(ROLLING_ROTORPAD),
		"mown_amplitude_m": amplitude_for_rolling_factor(ROLLING_MOWN),
		"rough_amplitude_m": amplitude_for_rolling_factor(ROLLING_ROUGH),
		"edge_blend_m": EDGE_BLEND_M,
		# Renderer-only anti-aliasing: fade relief from 20–80 m, then skip waves; suppress when
		# a pixel spans the 0.41 m shortest feature. Physics remains the full spatial field.
		"visibility_start_m": 20.0,
		"visibility_end_m": 80.0,
		"footprint_start_m": 0.08,
		"footprint_end_m": 0.41,
	}


## Smoothstep(value / blend). Zero slope at both feather endpoints gives C1 seams.
static func _smooth_edge_value(value: float) -> float:
	if value <= 0.0:
		return 0.0
	if value >= EDGE_BLEND_M:
		return 1.0
	var t: float = value / EDGE_BLEND_M
	return t * t * (3.0 - 2.0 * t)


## Derivative of _smooth_edge_value, per metre.
static func _smooth_edge_slope(value: float) -> float:
	if value <= 0.0 or value >= EDGE_BLEND_M:
		return 0.0
	var t: float = value / EDGE_BLEND_M
	return 6.0 * t * (1.0 - t) / EDGE_BLEND_M
