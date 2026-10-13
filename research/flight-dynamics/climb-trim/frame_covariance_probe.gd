extends SceneTree

# Randomized 6-DoF body-coordinate covariance and angular power identity probe.
# Run from the repository root with: Godot --headless --path app --script <absolute path to this file>
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")


func _dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


func _jv(j: PackedFloat64Array, v: PackedFloat64Array) -> PackedFloat64Array:
	return M.v3(j[0] * v[0] + j[3] * v[1] + j[4] * v[2],
		j[3] * v[0] + j[1] * v[1] + j[5] * v[2],
		j[4] * v[0] + j[5] * v[1] + j[2] * v[2])


func _rotate_into(q: PackedFloat64Array, v: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_rotate(M.q_conj(q), v)


func _inertia_in_rotated_axes(j: PackedFloat64Array, q: PackedFloat64Array) -> PackedFloat64Array:
	var cols: Array[PackedFloat64Array] = [
		M.q_rotate(q, M.v3(1.0, 0.0, 0.0)),
		M.q_rotate(q, M.v3(0.0, 1.0, 0.0)),
		M.q_rotate(q, M.v3(0.0, 0.0, 1.0)),
	]
	var out := PackedFloat64Array()
	for i in 3:
		for k in 3:
			var value := _dot(cols[i], _jv(j, cols[k]))
			if i <= k:
				out.append(value)
	return PackedFloat64Array([out[0], out[3], out[5], out[1], out[2], out[4]])


func _max_diff(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, absf(a[i] - b[i]))
	return worst


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2601301
	var max_covariance_error := 0.0
	var max_power_error := 0.0
	for _case in 1000:
		var j := PackedFloat64Array([0.4, 0.7, 0.9, 0.08, -0.06, 0.05])
		var j_inv := RB.inertia_inverse(j)
		var q_body := M.q_from_euler(rng.randf_range(-PI, PI), rng.randf_range(-1.3, 1.3), rng.randf_range(-PI, PI))
		var q_world := M.q_from_euler(rng.randf_range(-PI, PI), rng.randf_range(-1.3, 1.3), rng.randf_range(-PI, PI))
		var velocity := M.v3(rng.randf_range(-30.0, 30.0), rng.randf_range(-15.0, 15.0), rng.randf_range(-15.0, 15.0))
		var omega := M.v3(rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0))
		var force := M.v3(rng.randf_range(-100.0, 100.0), rng.randf_range(-100.0, 100.0), rng.randf_range(-100.0, 100.0))
		var moment := M.v3(rng.randf_range(-5.0, 5.0), rng.randf_range(-5.0, 5.0), rng.randf_range(-5.0, 5.0))
		var h := M.v3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
		var pos := M.v3(1.0, -2.0, -20.0)
		var old_state := RB.make_state(pos, velocity, q_world, omega)
		var old_dot: PackedFloat64Array = RB.derivative(old_state, 2.7, j, j_inv, force, moment, 9.80665, h)
		var j_new := _inertia_in_rotated_axes(j, q_body)
		var q_body_inv: PackedFloat64Array = M.q_conj(q_body)
		var new_state := RB.make_state(pos, _rotate_into(q_body, velocity), M.q_mul(q_world, q_body), _rotate_into(q_body, omega))
		var new_dot: PackedFloat64Array = RB.derivative(new_state, 2.7, j_new, RB.inertia_inverse(j_new),
			_rotate_into(q_body, force), _rotate_into(q_body, moment), 9.80665, _rotate_into(q_body, h))
		var expected := PackedFloat64Array()
		expected.append_array(old_dot.slice(RB.POS, RB.POS + 3))
		expected.append_array(_rotate_into(q_body, old_dot.slice(RB.VEL, RB.VEL + 3)))
		var qd_old := M.quat(old_dot[RB.ATT], old_dot[RB.ATT + 1], old_dot[RB.ATT + 2], old_dot[RB.ATT + 3])
		expected.append_array(M.q_mul(qd_old, q_body))
		expected.append_array(_rotate_into(q_body, old_dot.slice(RB.RATE, RB.RATE + 3)))
		max_covariance_error = maxf(max_covariance_error, _max_diff(new_dot, expected))
		var angular_power_error := absf(M.dot(omega, _jv(j, old_dot.slice(RB.RATE, RB.RATE + 3))) - M.dot(omega, moment))
		max_power_error = maxf(max_power_error, angular_power_error)
	print(JSON.stringify({cases = 1000, max_frame_covariance_error = max_covariance_error, max_torque_power_identity_error = max_power_error}))
	quit()
