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


## Position-aware wind contract. The weather provider keeps its uniform legacy law here;
## owner-sampled turbulence is added once and malformed samples fail closed.
func wind_world(position_ned: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
	if not _valid_ned_vector(position_ned) or not is_finite(time_s):
		return _invalid_world_wind()
	var out: PackedFloat64Array = weather.sample_world(position_ned, time_s)
	if not _valid_ned_vector(out):
		return _invalid_world_wind()
	if not turbulence.is_valid():
		return out
	var noise_value: Variant = turbulence.call(time_s)
	if typeof(noise_value) != TYPE_PACKED_FLOAT64_ARRAY:
		return _invalid_world_wind()
	if noise_value.is_empty():
		return out
	if not _valid_ned_vector(noise_value):
		return _invalid_world_wind()
	for axis: int in 3:
		var combined: float = out[axis] + float(noise_value[axis])
		if not is_finite(combined):
			return _invalid_world_wind()
		out[axis] = combined
	return out


## Atmosphere at `down_m` (NED down of the datum): {ok, rho_kgm3, engine_charge_ratio, ...} per the weather law.
func air(down_m: float = 0.0) -> Dictionary:
	return weather.atmosphere(down_m)


## Atmosphere at a world NED position, preserving the provider's validated result shape.
func air_world(position_ned: PackedFloat64Array) -> Dictionary:
	if not _valid_ned_vector(position_ned):
		return _air_world_failure("world position must contain three finite NED coordinates")
	var out: Dictionary = weather.atmosphere(position_ned[2])
	if typeof(out.get("ok", null)) != TYPE_BOOL:
		return _air_world_failure("weather atmosphere result is malformed")
	if not bool(out.ok):
		return out
	for key: String in [
		"pressure_pa", "temperature_k", "vapor_pressure_pa", "rho_kgm3",
		"dry_air_density_kgm3", "sigma", "engine_charge_ratio", "density_altitude_m",
	]:
		var value: Variant = out.get(key, null)
		if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or not is_finite(float(value)):
			return _air_world_failure("weather atmosphere result has invalid %s" % key)
	return out


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


func _valid_ned_vector(value: PackedFloat64Array) -> bool:
	if value.size() != 3:
		return false
	for component: float in value:
		if not is_finite(component):
			return false
	return true


static func _invalid_world_wind() -> PackedFloat64Array:
	return PackedFloat64Array([NAN, NAN, NAN])


static func _air_world_failure(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message])}
