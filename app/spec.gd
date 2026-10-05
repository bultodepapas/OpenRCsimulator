# Scene and control defaults from prototypes/stage0/SPEC.md.
# Current visual geometry: aircraft/ugly_stik_geometry.gd (generated from assets/).
extends RefCounted

const G := 9.80665

const CIRCLE := {
	center_north = 60.0, center_east = 0.0, altitude = 20.0,
	radius = 40.0, speed = 15.0, prop_rev_per_sec = 10.0,
}

const RED := Color("#c8102e")
const WHITE := Color("#f2f2f2")
const DARK := Color("#222222")
const DARK_GREY := Color("#333333")
const BLACK := Color("#111111")
const GRASS := Color("#4a7a32")
const RUNWAY_COLOR := Color("#6f9a4a")
const SKY := Color("#9cc9ef")

# Aircraft geometry is generated from assets/aircraft/ugly-stik-60/geometry.json.

const GROUND_SIZE := 2000.0
const RUNWAY := { length_east_west = 100.0, width_north_south = 12.0, center_north = 15.0 }

## Atmosphere (LANDSCAPE-PLAN L1a; one source for sky, light and, from L2, haze). Zenith and horizon from Hosek-Wilkie
## at a 45° sun with a pow(1 − y, 2.6) fit (investigation 02, computed); the real sun's 0.53° disc (investigation 01);
## below the horizon a muted green-grey (estimated, mostly hidden by the ground).
const ATMOSPHERE := {
	sun_azimuth_deg = 225.0, sun_elevation_deg = 45.0,
	zenith = Color("#4e6893"), horizon = Color("#c9e3ed"), below_horizon = Color("#8a9a80"),
	gradient_curve = 2.6, sun_diameter_deg = 0.53,
	exposure = 0.6, white = 1.0, # L1b: ACES tonemap, from a measured sweep against the readability thresholds
}

const CAMERA := { eye_height = 1.7, fov_deg = 50.0, near = 0.1, far = 3000.0 }
# Close-up camera, fixed to the airplane: model offset (left, above, behind).
const INSPECT_OFFSET := Vector3(-1.2, 0.9, 2.0)

# Keyboard virtual-stick profile (input device behaviour, not aircraft physics). Surface throws are aircraft
# data: controls.max_throw in app/data/aircraft/.
const CONTROLS := {
	rate = 4.0, # per second: full deflection or centering in 0.25 s
	throttle_rate = 0.5, # per second
	throttle_start = 0.5,
}

const CAPTURE := { time = 3.0, width = 1280, height = 720 }

# Pilot aids (D7). Estimated values, to be judged at Gate 2.
## Ground shadow: height above ground (m, against z-fighting), opacity low down → high up, fade height (m).
const SHADOW := { height = 0.05, fade_height = 80.0, alpha_low = 0.6, alpha_high = 0.18 }
## Grass texture: tile size (m) and brightness variation (±).
const GROUND := { tile_m = 6.0, contrast = 0.14 }
## Auto-zoom: the pilot camera narrows its vertical FOV so the airplane's span covers at least target_px of the
## viewport height (a 720p screen at 50° resolves ~4× worse than the eye); never below min_fov_deg.
const AUTO_ZOOM := { target_px = 30.0, min_fov_deg = 6.0 }
