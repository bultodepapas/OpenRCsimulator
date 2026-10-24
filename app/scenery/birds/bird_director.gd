## SC-BIRD-08 (first part): which share of each species is out, from the committed lighting and the scene detail.
## Pure functions of their inputs, so a lighting snapshot always gives the same birds. Inputs: the true solar elevation
## (time-of-day snapshots clamp `sun_elevation_deg` for the sky), morning or afternoon (an evening species only
## flies in the afternoon), cloud cover (thermal soarers fade under an overcast sky) and the scenery quality tier.
## Seasons wait for owner decision D9; rain and storms for a weather input the scenery does not receive yet.
extends RefCounted

const Atmosphere = preload("res://render/atmosphere.gd")

# Scene detail (VQ-06b scenery tier) -> share of each flock that is drawn [est].
const DENSITY := {low = 0.5, balanced = 0.75, high = 1.0}
const EDGE_DEG := 4.0 # sun-elevation half width of every threshold's smooth step
const CLOUD_EDGE := 0.25


## {sun_deg, afternoon, clouds, density} from a lighting snapshot ({} = the flow state or the legacy default).
static func conditions(lighting: Dictionary, quality: String = "high") -> Dictionary:
	var source: Dictionary = lighting
	if lighting.is_empty() and not Atmosphere.state.is_empty():
		source = Atmosphere.state
	elif lighting.is_empty():
		source = Atmosphere.parameters(lighting)
	return {sun_deg = sun_elevation_deg(lighting), afternoon = afternoon(source),
		clouds = clampf(float(source.get("cloud_coverage", 0.0)), 0.0, 1.0), density = float(DENSITY.get(quality, 1.0))}


## The true solar elevation (deg).
static func sun_elevation_deg(lighting: Dictionary) -> float:
	var solar: Variant = lighting.get("solar", null)
	if solar is Dictionary and (solar as Dictionary).has("elevation_deg"):
		return float(solar.elevation_deg)
	if lighting.is_empty() and not Atmosphere.state.is_empty():
		return float(Atmosphere.state.get("sun_elevation_deg", 45.0))
	return float(Atmosphere.parameters(lighting).get("sun_elevation_deg", 45.0))


## Afternoon from the solar hour angle; without one, the sun in the west (azimuth 180-360 deg, northern sites).
static func afternoon(source: Dictionary) -> bool:
	var solar: Variant = source.get("solar", null)
	if solar is Dictionary and (solar as Dictionary).has("hour_angle_deg"):
		return float(solar.hour_angle_deg) > 0.0
	return fposmod(float(source.get("sun_azimuth_deg", 225.0)), 360.0) > 180.0


## Share of a species out in [0, 1]: Wildlife.activity()'s day curve (birds call when they fly), the species' sun
## window, its period, cloud cover for soarers and the detail density.
static func activity(species: Dictionary, c: Dictionary) -> float:
	var a: Dictionary = species.activity
	var sun: float = c.sun_deg
	var share: float = smoothstep(-5.0, 4.0, sun) * smoothstep(float(a.sun_min) - EDGE_DEG, float(a.sun_min) + EDGE_DEG, sun)
	if float(a.sun_max) < 90.0:
		share *= 1.0 - smoothstep(float(a.sun_max) - EDGE_DEG, float(a.sun_max) + EDGE_DEG, sun)
	if str(a.period) == "evening" and not bool(c.afternoon):
		share = 0.0
	if float(a.clouds_max) < 1.0:
		share *= 1.0 - smoothstep(float(a.clouds_max) - CLOUD_EDGE, float(a.clouds_max), float(c.clouds))
	return clampf(share * float(c.density), 0.0, 1.0)
