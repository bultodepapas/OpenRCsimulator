# The one place where world NED / body FRD meet the Y-up render frame.
# Render axes: x = east, y = -down, z = -north. M maps (N, E, D) to (x, y, z).
extends RefCounted

const M := [[0.0, 1.0, 0.0], [0.0, 0.0, -1.0], [-1.0, 0.0, 0.0]]


static func ned_to_render(ned: Array) -> Vector3:
	return Vector3(ned[1], -ned[2], -ned[0])


## Body-to-NED rotation from ZYX Euler angles, expressed in render axes.
static func attitude_to_render(yaw: float, pitch: float, roll: float) -> Basis:
	var cy := cos(yaw)
	var sy := sin(yaw)
	var cp := cos(pitch)
	var sp := sin(pitch)
	var cr := cos(roll)
	var sr := sin(roll)
	var r_ned := [
		[cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr],
		[sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr],
		[-sp, cp * sr, cp * cr],
	]
	return _ned_matrix_to_basis(r_ned)


## Body-to-NED attitude quaternion [w, x, y, z] (64-bit) → render Basis. Same mapping as attitude_to_render.
static func quat_to_render(q: PackedFloat64Array) -> Basis:
	var w := q[0]
	var x := q[1]
	var y := q[2]
	var z := q[3]
	var r_ned := [
		[1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
		[2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
		[2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)],
	]
	return _ned_matrix_to_basis(r_ned)


## r_render = M · r_ned · Mᵀ, returned as a Basis (columns).
static func _ned_matrix_to_basis(r_ned: Array) -> Basis:
	var r := []
	for i in 3:
		var row := []
		for j in 3:
			var acc := 0.0
			for k in 3:
				for l in 3:
					acc += M[i][k] * r_ned[k][l] * M[j][l]
			row.append(acc)
		r.append(row)
	return Basis(
		Vector3(r[0][0], r[1][0], r[2][0]),
		Vector3(r[0][1], r[1][1], r[2][1]),
		Vector3(r[0][2], r[1][2], r[2][2]),
	)
