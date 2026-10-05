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
	# r = M * r_ned * M^T
	var r := []
	for i in 3:
		var row := []
		for j in 3:
			var s := 0.0
			for k in 3:
				for l in 3:
					s += M[i][k] * r_ned[k][l] * M[j][l]
			row.append(s)
		r.append(row)
	# Basis takes columns.
	return Basis(
		Vector3(r[0][0], r[1][0], r[2][0]),
		Vector3(r[0][1], r[1][1], r[2][1]),
		Vector3(r[0][2], r[1][2], r[2][2]),
	)
