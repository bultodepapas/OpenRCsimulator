# CAM-01: camera math (render/camera/camera_math.gd). Known values, exact frame-rate independence of the filters,
# FOV conversions, headings and a look basis that stays finite when looking straight up or down.
# Run: godot --headless --path . --script res://tests/test_camera_math.gd
extends SceneTree

const CameraMath := preload("res://render/camera/camera_math.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## Runs a filter from t = 0 to `duration` at `fps` and returns its final value.
func _run_damp(fps: float, duration: float, half_life: float) -> float:
	var x := 0.0
	var dt := 1.0 / fps
	for i in roundi(duration * fps):
		x = CameraMath.damp(x, 1.0, dt, half_life)
	return x


func _run_spring(fps: float, duration: float, half_life: float) -> Array:
	var x := Vector3.ZERO
	var v := Vector3.ZERO
	var dt := 1.0 / fps
	var monotonic := true
	for i in roundi(duration * fps):
		var moved: Array = CameraMath.spring(x, v, Vector3(1.0, -2.0, 0.5), dt, half_life)
		if (moved[0] as Vector3).x < x.x - 1e-12:
			monotonic = false
		x = moved[0]
		v = moved[1]
	return [x, v, monotonic]


func _initialize() -> void:
	_check("damper covers half the distance in one half-life", is_equal_approx(CameraMath.damp_factor(0.2, 0.2), 0.5))
	_check("damper with no half-life snaps", CameraMath.damp_factor(0.016, 0.0) == 1.0)
	var d30 := _run_damp(30.0, 1.0, 0.25)
	var d60 := _run_damp(60.0, 1.0, 0.25)
	var d144 := _run_damp(144.0, 1.0, 0.25)
	_check("damper: same value at 1 s for 30/60/144 fps", absf(d30 - d60) < 1e-12 and absf(d60 - d144) < 1e-12, "%.15f %.15f %.15f" % [d30, d60, d144])
	_check("damper: 4 half-lives leave 1/16", absf(d60 - (1.0 - 1.0 / 16.0)) < 1e-12, "%.15f" % d60)
	var s30 := _run_spring(30.0, 1.5, 0.25)
	var s60 := _run_spring(60.0, 1.5, 0.25)
	var s144 := _run_spring(144.0, 1.5, 0.25)
	# Vector3 is 32-bit: equal to float32 rounding (the 64-bit damper above is equal to 1e-12).
	_check("spring: same position at 1.5 s for 30/60/144 fps", (s30[0] as Vector3).distance_to(s60[0]) < 1e-5 and (s60[0] as Vector3).distance_to(s144[0]) < 1e-5,
		"%s %s %s" % [s30[0], s60[0], s144[0]])
	_check("spring: same velocity at 1.5 s for 30/60/144 fps", (s30[1] as Vector3).distance_to(s60[1]) < 1e-5 and (s60[1] as Vector3).distance_to(s144[1]) < 1e-5)
	_check("spring: critically damped step never overshoots", bool(s30[2]) and bool(s60[2]) and bool(s144[2]))
	_check("spring: settles on the goal", (s60[0] as Vector3).distance_to(Vector3(1.0, -2.0, 0.5)) < 0.01, str(s60[0]))
	var spring_snap: Array = CameraMath.spring(Vector3.ZERO, Vector3.ONE, Vector3.ONE, 0.016, 0.0)
	_check("spring with no half-life snaps and stops", spring_snap[0] == Vector3.ONE and spring_snap[1] == Vector3.ZERO)
	# Angles take the short way through ±180°.
	var a := CameraMath.damp_angle(deg_to_rad(170.0), deg_to_rad(-170.0), 0.2, 0.2)
	_check("angle damper goes through 180°, not through 0°", absf(rad_to_deg(a)) > 175.0, "%.3f°" % rad_to_deg(a))
	# FOV conversions.
	_check("zoom factor 1 keeps the FOV", absf(CameraMath.zoomed_fov(50.0, 1.0) - 50.0) < 1e-9)
	var half := CameraMath.zoomed_fov(50.0, 0.5)
	_check("zoom factor 0.5 halves tan(fov/2): 50° → 26.25°", absf(half - rad_to_deg(2.0 * atan(0.5 * tan(deg_to_rad(25.0))))) < 1e-9 and absf(half - 26.25) < 0.01, "%.4f" % half)
	_check("ln(tan) round trip", absf(CameraMath.from_log_tan(CameraMath.log_tan(37.5)) - 37.5) < 1e-9)
	var h := CameraMath.horizontal_fov(50.0, 16.0 / 9.0)
	_check("50° vertical is ≈ 79.3° horizontal at 16:9", absf(h - 79.32) < 0.01, "%.3f" % h)
	_check("horizontal ↔ vertical round trip", absf(CameraMath.vertical_fov(h, 16.0 / 9.0) - 50.0) < 1e-9)
	# Headings: 0 = north (−z), 90° = east (+x).
	_check("north heading is 0", absf(CameraMath.heading_of(Vector3(0, 0, -1))) < 1e-12)
	_check("east heading is +90°", absf(CameraMath.heading_of(Vector3(1, 0, 0)) - PI / 2.0) < 1e-12)
	var round_ok := true
	for deg in range(-180, 181, 15):
		var back := CameraMath.heading_of(CameraMath.dir_of_heading(deg_to_rad(deg)))
		round_ok = round_ok and absf(angle_difference(back, deg_to_rad(deg))) < 1e-6 # through a 32-bit Vector3
	_check("heading ↔ direction round trip every 15°", round_ok)
	_check("horizontal direction of a vertical vector is undefined", CameraMath.horizontal_dir(Vector3(0, 5, 0)) == Vector3.ZERO)
	# Look basis.
	var level := CameraMath.look_basis(Vector3.ZERO, Vector3(10, 0, 0))
	_check("look basis: forward points at the target", (-level.z).distance_to(Vector3(1, 0, 0)) < 1e-6 and level.y.distance_to(Vector3.UP) < 1e-6)
	var finite := true
	for target: Vector3 in [Vector3(0, 10, 0), Vector3(0, -10, 0), Vector3(1e-7, 10, 0)]:
		var b := CameraMath.look_basis(Vector3.ZERO, target)
		finite = finite and b.is_finite() and absf(b.determinant() - 1.0) < 1e-5 and (-b.z).dot(target.normalized()) > 0.9999
	_check("look basis straight up/down: finite, orthonormal, aimed", finite)
	print("all %d camera math checks passed" % _count if _failures == 0 else "%d of %d failed" % [_failures, _count])
	quit(1 if _failures > 0 else 0)
