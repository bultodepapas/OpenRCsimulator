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
# Landscape improvement phase 1 (report 01): measured lawn colour. #4a7a32 rendered hue 104-110 deg, sat 0.69-0.74 ("billiard
# table"); #657545 renders hue 77-79 deg, sat 0.48-0.52, inside the owner's photo window, same linear luminance (0.159).
const GRASS := Color("#657545")
# Mown runway turf: the grass hue, saturation -0.08, value +18 % (report 04: same hue as the grass +-5 deg, a little paler).
const RUNWAY_COLOR := Color("#7b8a5c")
const SKY := Color("#9cc9ef")

# Aircraft geometry is generated from assets/aircraft/ugly-stik-60/geometry.json.

## Ground plane edge length (m): half-size 20 km (L2). At 23 km visibility the haze leaves 3 % contrast there, so the
## rim fade (ATMOSPHERE.rim_*) only removes the last few levels. A 6 km ground left 36 % contrast, ~21 levels in 3
## screen rows seen from 100 m up (L2 log). One quad either way; float32 is ~2 mm at 20 km.
const GROUND_SIZE := 40000.0
const RUNWAY := { length_east_west = 100.0, width_north_south = 12.0, center_north = 15.0 }

## Atmosphere (LANDSCAPE-PLAN L1a; one source for sky, light and, from L2, haze). Zenith and horizon from Hosek-Wilkie
## at a 45° sun with a pow(1 − y, 2.6) fit (investigation 02, computed); the real sun's 0.53° disc (investigation 01);
## below the horizon a muted green-grey (estimated, mostly hidden by the ground).
const ATMOSPHERE := {
	sun_azimuth_deg = 225.0, sun_elevation_deg = 45.0,
	zenith = Color("#4e6893"), gradient_curve = 2.6, sun_diameter_deg = 0.53,
	exposure = 0.6, white = 1.0, # L1b: ACES tonemap, the best readability in a measured sweep (atmosphere.gd)
	# L2 haze (investigation 02). Koschmieder: distant objects tend to the horizon sky, so haze = the Hosek anti-sun
	# horizon. Visibility 23 km = MODTRAN rural "clear". sun_scatter fitted (estimated) so the horizon toward the sun
	# is ~1.2× the anti-sun horizon (Hosek T = 2.5). Rim fade over the outer 20 % of the ground (estimated).
	haze = Color("#c9e3ed"), haze_energy = 1.0, visibility_m = 23000.0, sun_scatter = 0.785,
	# L3 sun: colour 5200 K at a 45° sun (Godot's formula, investigation 09). Optional engine PSSM shadows to 300 m
	# (estimated): Compatibility blends shadowed lights in sRGB after tonemapping (Godot #90259, PR #98656 unmerged),
	# +14 % on the sunlit wing; shadow_energy_compat (measured: grass and wing within ±4 %) scales the light then, and
	# the fog scatter is divided by it so the haze stays the same. Whites still clip, so engine shadows are off.
	sun_color = Color("#ffe9d7"), sun_energy = 1.0, shadow_energy_compat = 0.85, shadow_max_distance_m = 300.0,
	rim_start_m = 16000.0, rim_end_m = 20000.0,
	# L4 clouds (estimated, fair-weather cumulus): coverage, deck scale, seed, colour, drift (noise cells per second,
	# from the wind aloft once wind exists), updated at most once per second of simulation (each update re-renders
	# the sky radiance).
	cloud_coverage = 0.35, cloud_scale = 6.0, cloud_seed = 1253, cloud_color = Color("#f2f4f7"),
	cloud_drift_cells_per_s = Vector2(0.004, 0.0015), cloud_update_s = 1.0,
}

const CAMERA := { eye_height = 1.7, fov_deg = 50.0, near = 0.1, far = 21000.0 } # far ≥ 1.05 × the ground's rim (L2)
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
