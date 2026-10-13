# CAM-01: camera math (docs/plans/camera-views.md). Presentation only, render space (Y-up, metres); never used by
# app/sim or app/physics. Every filter is an exact discretization, so the same motion sampled at 30, 60 or 144 fps
# gives the same camera at matched times (a constant target is reached identically for any frame split).
extends RefCounted


## Share of the remaining distance an exponential damper covers in dt (half-life in s; ≤ 0 means "snap").
static func damp_factor(dt: float, half_life: float) -> float:
	if half_life <= 0.0:
		return 1.0
	return 1.0 - pow(2.0, -maxf(dt, 0.0) / half_life)


static func damp(x: float, target: float, dt: float, half_life: float) -> float:
	return lerpf(x, target, damp_factor(dt, half_life))


static func damp_v3(x: Vector3, target: Vector3, dt: float, half_life: float) -> Vector3:
	return x.lerp(target, damp_factor(dt, half_life))


## Shortest-way angle damper (radians); the result is wrapped to [−π, π].
static func damp_angle(a: float, target: float, dt: float, half_life: float) -> float:
	return wrapf(a + angle_difference(a, target) * damp_factor(dt, half_life), -PI, PI)


## Critically damped spring toward a goal, exact for a constant goal (D. Holden, "Spring-It-On"): the half-life is
## the time to cover half of a step. Returns [position, velocity].
static func spring(x: Vector3, v: Vector3, goal: Vector3, dt: float, half_life: float) -> Array:
	if half_life <= 0.0:
		return [goal, Vector3.ZERO]
	var y := 2.0 * log(2.0) / half_life # half the damping 4·ln2/half_life
	var j0 := x - goal
	var j1 := v + j0 * y
	var e := exp(-y * maxf(dt, 0.0))
	return [goal + (j0 + j1 * dt) * e, (v - j1 * y * dt) * e]


## Vertical FOV ↔ ln(tan(fov/2)): the space where zoom factors add and jumps can be blended evenly.
static func log_tan(fov_deg: float) -> float:
	return log(tan(deg_to_rad(clampf(fov_deg, 0.01, 179.0)) * 0.5))


static func from_log_tan(value: float) -> float:
	return rad_to_deg(2.0 * atan(exp(value)))


## A FOV narrowed (factor < 1) or widened (factor > 1) like a zoom lens: tan(fov/2) scales by the factor.
static func zoomed_fov(fov_deg: float, factor: float) -> float:
	return from_log_tan(log_tan(fov_deg) + log(maxf(factor, 1e-6)))


## Horizontal FOV for a vertical FOV at an aspect ratio (width / height), and back.
static func horizontal_fov(vertical_deg: float, aspect: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(vertical_deg) * 0.5) * aspect))


static func vertical_fov(horizontal_deg: float, aspect: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal_deg) * 0.5) / maxf(aspect, 1e-6)))


## Unit horizontal direction of v, or ZERO when v is (nearly) vertical or still.
static func horizontal_dir(v: Vector3, min_length := 1e-4) -> Vector3:
	var h := Vector3(v.x, 0.0, v.z)
	return h / h.length() if h.length() > min_length else Vector3.ZERO


## Render heading (radians) of a horizontal direction: 0 = north (−z), +π/2 = east (+x).
static func heading_of(dir: Vector3) -> float:
	return atan2(dir.x, -dir.z)


static func dir_of_heading(heading: float) -> Vector3:
	return Vector3(sin(heading), 0.0, -cos(heading))


## A camera basis looking from `eye` at `target` with world up; a nearly vertical view keeps `fallback_up` on screen.
static func look_basis(eye: Vector3, target: Vector3, fallback_up := Vector3.FORWARD) -> Basis:
	var forward := target - eye
	if forward.length() < 1e-6:
		return Basis.IDENTITY
	forward = forward.normalized()
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.999 else fallback_up
	return Basis.looking_at(forward, up)
