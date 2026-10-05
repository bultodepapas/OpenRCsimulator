# C1: known-answer and property checks for the float64 math helpers.
# Run: godot --headless --path . --script res://tests/test_math3d.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const Frames := preload("res://render/frames.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _close_v(label: String, got: PackedFloat64Array, want: PackedFloat64Array, eps := 1e-12) -> void:
	var ok := got.size() == want.size()
	for i in mini(got.size(), want.size()):
		ok = ok and absf(got[i] - want[i]) <= eps
	_check(label, ok, "got %s want %s" % [got, want])


func _initialize() -> void:
	var north := M.v3(1, 0, 0)
	var east := M.v3(0, 1, 0)
	var down := M.v3(0, 0, 1)

	# Known answers
	_close_v("x cross y = z (right-handed)", M.cross(north, east), down)
	_close_v("yaw 90: body forward -> east", M.q_rotate(M.q_from_euler(PI / 2, 0, 0), north), east)
	_close_v("pitch 90: body forward -> up", M.q_rotate(M.q_from_euler(0, PI / 2, 0), north), M.v3(0, 0, -1))
	_close_v("roll 90: body right -> down", M.q_rotate(M.q_from_euler(0, 0, PI / 2), east), down)
	_close_v("axis-angle = euler for yaw", M.q_from_axis_angle(down, 0.7), M.q_from_euler(0.7, 0, 0))

	# Properties over a deterministic random sample
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261005
	var worst_len := 0.0
	var worst_euler := 0.0
	var worst_comp := 0.0
	var worst_frames := 0.0
	for i in 500:
		var yaw := rng.randf_range(-PI, PI)
		var pitch := rng.randf_range(-1.5, 1.5) # away from the ±90° singularity
		var roll := rng.randf_range(-PI, PI)
		var q := M.q_from_euler(yaw, pitch, roll)
		var v := M.v3(rng.randf_range(-100, 100), rng.randf_range(-100, 100), rng.randf_range(-100, 100))

		worst_len = maxf(worst_len, absf(M.norm(M.q_rotate(q, v)) - M.norm(v)) / M.norm(v))

		var e := M.q_to_euler(q)
		worst_euler = maxf(worst_euler, maxf(absf(e[0] - yaw), maxf(absf(e[1] - pitch), absf(e[2] - roll))))

		var q2 := M.q_from_euler(rng.randf_range(-PI, PI), rng.randf_range(-1.5, 1.5), rng.randf_range(-PI, PI))
		var a := M.q_rotate(M.q_mul(q, q2), v)
		var b := M.q_rotate(q, M.q_rotate(q2, v))
		worst_comp = maxf(worst_comp, M.norm(M.sub(a, b)) / M.norm(v))

		# Cross-check against the independent render conversion (32-bit Basis, so 1e-6).
		var r := M.q_rotate(q, north)
		var nose: Vector3 = Frames.attitude_to_render(yaw, pitch, roll) * Vector3(0, 0, -1)
		var want := Frames.ned_to_render([r[0], r[1], r[2]])
		worst_frames = maxf(worst_frames, (nose - want).length())
	_check("rotation preserves length (500 samples)", worst_len < 1e-14, str(worst_len))
	_check("euler round trip (500 samples)", worst_euler < 1e-12, str(worst_euler))
	_check("composition q1*q2 = rotate q2 then q1", worst_comp < 1e-14, str(worst_comp))
	_check("agrees with render/frames.gd", worst_frames < 1e-5, str(worst_frames))

	# Why 64-bit: a 1e-4 m/s² acceleration for 60 s at 240 Hz (see research/float32_vs_float64_integration.mjs).
	var dt := 1.0 / 240.0
	var v64 := M.v3(20, 0, 0)
	var v32 := Vector3(20, 0, 0)
	for i in 240 * 60:
		v64 = M.add(v64, M.v3(1e-4 * dt, 0, 0))
		v32 += Vector3(1e-4 * dt, 0, 0)
	_check("float64 keeps a 1e-4 m/s² acceleration", absf((v64[0] - 20.0) - 0.006) < 1e-9, str(v64[0] - 20.0))
	_check("(contrast) Vector3 loses it entirely", absf(v32.x - 20.0) < 1e-12, str(v32.x - 20.0))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
