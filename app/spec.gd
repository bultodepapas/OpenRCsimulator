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

const SUN := { azimuth_from_north_deg = 225.0, elevation_deg = 45.0 } # south-west

const CAMERA := { eye_height = 1.7, fov_deg = 50.0, near = 0.1, far = 3000.0 }
# Close-up camera, fixed to the airplane: model offset (left, above, behind).
const INSPECT_OFFSET := Vector3(-1.2, 0.9, 2.0)

# Stage 1 controls. Throws are estimates (evidence kind: estimated), not from the plans.
const CONTROLS := {
	rate = 4.0, # per second: full deflection or centering in 0.25 s
	throttle_rate = 0.5, # per second
	throttle_start = 0.5,
	max_throw_deg = { aileron = 20.0, elevator = 20.0, rudder = 25.0 },
}

const CAPTURE := { time = 3.0, width = 1280, height = 720 }
