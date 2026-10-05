# B4: known-answer checks for the NED/FRD -> render conversion and the scripted pose.
# Run: godot --headless --path . --script res://tests/test_frames.gd
extends SceneTree

const Frames := preload("res://render/frames.gd")
const Scripted := preload("res://sim/scripted.gd")
const M3 := preload("res://physics/math3d.gd")

const NOSE := Vector3(0, 0, -1) # model forward
const RIGHT_WING := Vector3(1, 0, 0) # model right
const EPS := 1e-6 # Vector3/Basis are 32-bit floats

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _close(label: String, got: Vector3, want: Vector3) -> void:
	_check(label, got.is_equal_approx(want) or (got - want).length() < EPS, "got %s want %s" % [got, want])


func _initialize() -> void:
	_close("north -> -z", Frames.ned_to_render([1.0, 0.0, 0.0]), Vector3(0, 0, -1))
	_close("east -> +x", Frames.ned_to_render([0.0, 1.0, 0.0]), Vector3(1, 0, 0))
	_close("down -> -y", Frames.ned_to_render([0.0, 0.0, 1.0]), Vector3(0, -1, 0))

	_close("heading 0: nose north", Frames.attitude_to_render(0, 0, 0) * NOSE, Vector3(0, 0, -1))
	_close("heading 90: nose east", Frames.attitude_to_render(deg_to_rad(90), 0, 0) * NOSE, Vector3(1, 0, 0))
	var p30 := deg_to_rad(30)
	_close("pitch up 30: nose rises", Frames.attitude_to_render(0, p30, 0) * NOSE, Vector3(0, sin(p30), -cos(p30)))
	_close("bank right 30: right wing down", Frames.attitude_to_render(0, 0, p30) * RIGHT_WING, Vector3(cos(p30), -sin(p30), 0))
	_check("proper rotation", absf(Frames.attitude_to_render(1.1, -0.4, 2.3).determinant() - 1.0) < EPS)

	# Quaternion path agrees with the Euler path (C6 renders the simulation's quaternion).
	var worst := 0.0
	for e in [[0.0, 0.0, 0.0], [1.2, 0.3, -0.7], [-2.5, -1.1, 2.9], [PI / 2, 0.0, PI / 2]]:
		var from_q := Frames.quat_to_render(M3.q_from_euler(e[0], e[1], e[2]))
		var from_e := Frames.attitude_to_render(e[0], e[1], e[2])
		for c in 3:
			worst = maxf(worst, (from_q[c] - from_e[c]).length())
	_check("quat_to_render = attitude_to_render", worst < 1e-6, str(worst))

	# D1: the visual model is placed so its CG point lands exactly on the simulated (CG) position.
	var cg_model := Frames.cg_in_model_frame(PackedFloat64Array([0.1209, 0.0, 0.0]), -0.115, -0.005)
	_close("cg in model frame", cg_model, Vector3(0, -0.005, 0.0059))
	var cg_basis := Frames.quat_to_render(M3.q_from_euler(0.7, -0.3, 1.1))
	var cg_pos := Vector3(12, 30, -60)
	_close("model CG lands on the sim position", Frames.root_transform(cg_basis, cg_pos, cg_model) * cg_model, cg_pos)

	var pose := Scripted.pose_at(0.0)
	_check("t=0 north 100", absf(pose.ned[0] - 100.0) < 1e-12)
	_check("t=0 up 20", absf(pose.ned[2] + 20.0) < 1e-12)
	_check("t=0 heading east", absf(pose.yaw - PI / 2.0) < 1e-12)
	_check("bank 29.84 deg", absf(rad_to_deg(pose.roll) - 29.84) < 0.005, str(rad_to_deg(pose.roll)))
	var lap := TAU * 40.0 / 15.0
	var a := Scripted.pose_at(1.3)
	var b := Scripted.pose_at(1.3 + lap)
	for i in 3:
		_check("lap repeats [%d]" % i, absf(a.ned[i] - b.ned[i]) < 1e-9)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
