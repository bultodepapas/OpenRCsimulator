# SF-07: the environment contract every vehicle session consumes. Pure, deterministic queries sampled at a stage
# position and time; the providers are the existing physical weather field (wind, atmosphere column), the owner's
# turbulence sample (sampled state, interpolated by the session), the field's flat surface table with the terrain
# sampler, the lake, and a ground-vehicle course. Rendering, lighting and visual time are not part of it.
# Sessions keep their checkpoint identities; identity() summarizes the installed providers for diagnostics.
# 64-bit floats only; no Vector3/Basis/Quaternion/Transform3D.
extends RefCounted

const WeatherField := preload("res://physics/wind_field.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const Course := preload("res://physics/ground_vehicle/course.gd")
const AirfieldCourse := preload("res://physics/ground_vehicle/airfield_course.gd")

## Physical wind and atmosphere (physics/wind_field.gd). Sessions configure it at launch boundaries.
var weather: WeatherField = WeatherField.new()
## turbulence(time_s) -> float64[3] NED noise interpolated from the owner's sampled state, or an empty array when the
## owner has no turbulence this run (then nothing is added, so calm wind keeps its exact bytes); unset = none.
var turbulence: Callable
## The field's flat surface table (physics/ground_surfaces.gd); empty = dry pavement everywhere at height 0.
var surfaces: PackedFloat64Array = PackedFloat64Array()
## Normalized lake (physics/lake_surface.gd); empty = no water.
var lake: Dictionary = {}
## Ground-vehicle course sampler (north, east) -> Dictionary with height, normal, surface, walls and wet zone;
## unset = no course.
var road: Callable
var gravity: float = 9.80665


## Wind in NED at `time_s`, with the owner's turbulence added when supplied.
func wind(time_s: float) -> PackedFloat64Array:
	var out: PackedFloat64Array = weather.sample(time_s)
	if turbulence.is_valid():
		var noise: PackedFloat64Array = turbulence.call(time_s)
		if noise.size() == 3:
			for axis: int in 3:
				out[axis] += noise[axis]
	return out


## Atmosphere at `down_m` (NED down of the datum): {ok, rho_kgm3, engine_charge_ratio, ...} per the weather law.
func air(down_m: float = 0.0) -> Dictionary:
	return weather.atmosphere(down_m)


func air_density(down_m: float = 0.0) -> float:
	return weather.air_density(down_m)


func engine_charge_ratio(down_m: float = 0.0) -> float:
	return weather.engine_charge_ratio(down_m)


## Dry terrain sample [height_up, ...] from the surface table alone (physics/ground_terrain.gd).
func terrain(north: float, east: float) -> PackedFloat64Array:
	return Terrain.sample_validated(north, east, surfaces)


## Terrain sample with the lake applied, as the contact laws see it.
func ground(north: float, east: float) -> PackedFloat64Array:
	return Terrain.sample_validated(north, east, surfaces, lake)


func ground_max_height() -> float:
	return Terrain.max_height_validated(surfaces)


## Lake terrain sample at a point, or {} without a lake.
func water(north: float, east: float) -> Dictionary:
	return LakeSurface.sample_terrain_validated(lake, north, east) if not lake.is_empty() else {}


## Ground-vehicle course sample, or {} without a course.
func course(north: float, east: float) -> Dictionary:
	return road.call(north, east) if road.is_valid() else {}


## The course sampler a ground-vehicle session installs as `road` (moved from the session, unchanged).
static func course_road(course_value: Dictionary) -> Callable:
	if str(course_value.get("sampler", "")) == AirfieldCourse.FORMAT:
		return func(north_m: float, east_m: float) -> Dictionary:
			return AirfieldCourse.sample(course_value, north_m, east_m)
	return func(north_m: float, east_m: float) -> Dictionary:
		return Course.sample(course_value, north_m, east_m)


## Diagnostic summary of the installed providers (not a checkpoint format).
func identity() -> Dictionary:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not surfaces.is_empty():
		ctx.update(surfaces.to_byte_array())
	return {
		weather = weather.configuration(),
		turbulence = turbulence.is_valid(),
		surfaces_sha256 = ctx.finish().hex_encode(),
		lake = str(lake.get("identity", "")),
		course = road.is_valid(),
		gravity = gravity,
	}
