# AV-17: retain the production crash-pose assertions and expose numerical deltas.
extends "res://tests/test_crash_pose.gd"


func _pose_equal(a: Dictionary, b: Dictionary) -> bool:
	var equal: bool = a.pos == b.pos and a.basis == b.basis
	if not equal:
		var basis_error := 0.0
		for axis in 3:
			basis_error = maxf(basis_error, (a.basis[axis] - b.basis[axis]).length())
		print("AV17_POSE_DELTA " + JSON.stringify({position_m = a.pos.distance_to(b.pos), basis_axis = basis_error}, "", true, true))
	return equal
