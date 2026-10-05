# Every number from ../SPEC.md lives here, once.
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

# Das Ugly Stik 60. Model axes: +x right, +y up, -z forward. Origin near the CG.
const BOXES := [
	{ name = "fuselage", size = Vector3(0.11, 0.15, 1.14), center = Vector3(0, 0, 0.13), color = RED },
	{ name = "cowl", size = Vector3(0.1, 0.13, 0.08), center = Vector3(0, 0, -0.48), color = DARK_GREY },
	{ name = "stab", size = Vector3(0.56, 0.02, 0.13), center = Vector3(0, 0, 0.635), color = RED },
	{ name = "fin", size = Vector3(0.02, 0.17, 0.14), center = Vector3(0, 0.155, 0.63), color = WHITE },
	{ name = "propeller", size = Vector3(0.305, 0.025, 0.01), center = Vector3(0, 0, -0.54), color = BLACK },
]

# Wing panels have a dark underside, for orientation.
const WINGS := [
	{ name = "wing_center", size = Vector3(1.124, 0.035, 0.226), center = Vector3(0, 0.03, 0.023), top = RED, bottom = DARK },
	{ name = "wing_tip_left", size = Vector3(0.2, 0.035, 0.226), center = Vector3(-0.662, 0.03, 0.023), top = WHITE, bottom = DARK },
	{ name = "wing_tip_right", size = Vector3(0.2, 0.035, 0.226), center = Vector3(0.662, 0.03, 0.023), top = WHITE, bottom = DARK },
]

# Control surfaces pivot on their leading edge (hinge line).
const SURFACES := [
	{ name = "aileron_left", size = Vector3(0.62, 0.02, 0.08), center = Vector3(-0.39, 0.03, 0.176), color = RED },
	{ name = "aileron_right", size = Vector3(0.62, 0.02, 0.08), center = Vector3(0.39, 0.03, 0.176), color = RED },
	{ name = "elevator", size = Vector3(0.56, 0.02, 0.07), center = Vector3(0, 0, 0.735), color = RED },
	{ name = "rudder", size = Vector3(0.02, 0.19, 0.07), center = Vector3(0, 0.165, 0.735), color = WHITE },
]

const WHEELS := [
	{ name = "nosewheel", diameter = 0.07, width = 0.025, center = Vector3(0, -0.19, -0.4), color = BLACK },
	{ name = "gear_left", diameter = 0.076, width = 0.028, center = Vector3(-0.17, -0.19, 0.05), color = BLACK },
	{ name = "gear_right", diameter = 0.076, width = 0.028, center = Vector3(0.17, -0.19, 0.05), color = BLACK },
]

const GROUND_SIZE := 2000.0
const RUNWAY := { length_east_west = 100.0, width_north_south = 12.0, center_north = 15.0 }

const SUN := { azimuth_from_north_deg = 225.0, elevation_deg = 45.0 } # south-west

const CAMERA := { eye_height = 1.7, fov_deg = 50.0, near = 0.1, far = 3000.0 }

const CAPTURE := { time = 3.0, width = 1280, height = 720 }
