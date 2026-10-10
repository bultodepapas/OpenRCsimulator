## TOD-03: one scene-local snapshot. Curves are SDR appearance estimates, not measured lux.
## Sources, domain and numerical anchors: docs/research/time-of-day-investigations/TOD-03/README.md.
extends RefCounted

const Spec = preload("res://spec.gd")
const Solar = preload("res://environment/solar_position.gd")
const PROFILE: String = "openrc-lighting-curves v1"
## Geometric solar elevation, zenith/horizon/cloud sRGB appearance. Twilight bounds: USNO.
const ANCHORS: Array = [
	[-18.0, Color("#010205"), Color("#020305"), Color("#010203")],
	[-12.0, Color("#071024"), Color("#263247"), Color("#111b2c")],
	[-6.0, Color("#1d3255"), Color("#706d7b"), Color("#4e4c5c")],
	[-0.8333, Color("#344e7c"), Color("#cf9f85"), Color("#d5ac96")],
	[6.0, Color("#416294"), Color("#cbd7dc"), Color("#eee2d3")],
	[45.0, Color("#4e6893"), Color("#c9e3ed"), Color("#f2f4f7")],
	[90.0, Color("#43668f"), Color("#c9e3ed"), Color("#f2f4f7")],
]


## Input is validated by the UI/CLI boundary. Legacy returns the original parameters exactly.
static func snapshot(config: Dictionary) -> Dictionary:
	var result: Dictionary = Spec.ATMOSPHERE.duplicate(true)
	if config.get("mode", "legacy") == "legacy":
		return result
	var solar: Dictionary = Solar.evaluate(config)
	var elevation: float = solar.elevation_deg
	var colours: Array[Color] = colours_at(elevation)
	result.zenith = colours[0]
	result.haze = colours[1]
	result.cloud_color = colours[2]
	result.sun_azimuth_deg = solar.azimuth_deg
	# Mean 34 arcminute horizon refraction (USNO), smoothly removed by 5 degrees.
	# A bounded visual approximation, independent of the physical atmosphere settings.
	var apparent: float = elevation + (34.0 / 60.0) * (1.0 - smoothstep(0.0, 5.0, elevation))
	result.disc_elevation_deg = apparent
	result.sun_elevation_deg = maxf(apparent, 0.05)
	result.sun_energy = smoothstep(-0.8333, 6.0, elevation) * lerpf(0.7, 1.15, smoothstep(6.0, 80.0, elevation))
	result.sun_color = Color("#ff975a").lerp(Spec.ATMOSPHERE.sun_color, smoothstep(0.0, 25.0, elevation))
	result.sun_scatter = Spec.ATMOSPHERE.sun_scatter
	result.cloud_silver_strength = Spec.ATMOSPHERE.cloud_silver_strength * smoothstep(-0.8333, 6.0, elevation)
	result.shadow_strength = smoothstep(0.0, 6.0, apparent) * minf(result.sun_energy, 1.0)
	result.disc_cloud_occlusion = true
	result.solar = solar
	return result


## Interpolate in linear light; retain endpoint colours for deterministic plateau cases.
static func colours_at(elevation_deg: float) -> Array[Color]:
	var lower: Array = ANCHORS[0]
	var upper: Array = ANCHORS[0]
	for row: Array in ANCHORS:
		upper = row
		if elevation_deg <= float(row[0]):
			break
		lower = row
	var weight: float = 0.0 if lower[0] == upper[0] else smoothstep(float(lower[0]), float(upper[0]), elevation_deg)
	var result: Array[Color] = []
	for column: int in range(1, 4):
		var a: Color = lower[column]
		var b: Color = upper[column]
		result.append(a.srgb_to_linear().lerp(b.srgb_to_linear(), weight).linear_to_srgb())
	return result


static func context(config: Dictionary, lighting: Dictionary) -> Dictionary:
	var encoded: String = JSON.stringify(config, "", true, true)
	return {
		format = "openrc-visual-context v1", mode = "fixed", config = config.duplicate(true),
		config_sha256 = encoded.sha256_text(), profile = "legacy-spec" if config.mode == "legacy" else PROFILE,
		solar = lighting.get("solar", {}).duplicate(true),
		exposure = lighting.exposure, moon = "not-modelled", illumination_kind = "estimated",
	}
