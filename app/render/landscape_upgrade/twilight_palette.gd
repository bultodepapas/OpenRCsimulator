## LU-13: artistic diffuse-light chromaticity for the simplified FW atmosphere table.
## The table omits multiple scattering. Keep warm direct sunlight and the sunward lobe,
## but avoid making the entire sky hemisphere and every shadow saturated orange.
## Original MIT; colors/weights are art estimates, not a physical atmosphere model.
extends RefCounted

const ZENITH_TINT := Vector3(0.20, 0.36, 0.72)
const HAZE_TINT := Vector3(0.62, 0.65, 0.74)
const CLOUD_TINT := Vector3(0.80, 0.83, 0.90)


static func weight(elevation_deg: float) -> float:
	return smoothstep(-10.0, -4.0, elevation_deg) * (1.0 - smoothstep(4.0, 12.0, elevation_deg))


static func luminance(rgb: Vector3) -> float:
	return rgb.dot(Vector3(0.2126, 0.7152, 0.0722))


## Preserve the scalar irradiance used for adaptation; adjust only chromaticity.
## Exact early-out outside twilight keeps daylight and deep-night values untouched.
static func diffuse(rgb: Vector3, elevation_deg: float, tint: Vector3, strength: float) -> Vector3:
	var blend := weight(elevation_deg) * clampf(strength, 0.0, 1.0)
	if blend <= 0.0:
		return rgb
	var y := luminance(rgb)
	var target := tint * (y / maxf(luminance(tint), 1e-20))
	return rgb.lerp(target, blend)
