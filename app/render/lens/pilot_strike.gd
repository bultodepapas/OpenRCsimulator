## LENS-05 (docs/plans/lens-screen-effects.md §5.4): presentation-only detection of the aircraft striking the pilot
## (the player). The player has no collision body, so the simulation is unchanged and the aircraft passes through;
## this only tells the lens that the pilot was struck. float64 NED throughout (north, east, down).
##
## The pilot is a vertical capsule at the station with the flight-line pilot's radius (prefabs.gd person_pilot,
## 0.335 m), from the feet to just above the eyes. Each observation sweeps every hull point from its previous
## position, so a fast pass between two frames cannot tunnel through the capsule.
extends RefCounted

const M := preload("res://physics/math3d.gd")

const RADIUS_M := 0.335
const HEAD_CLEARANCE_M := 0.12
## After a strike, the detector re-arms once every hull point is this far from the capsule axis.
const REARM_DISTANCE_M := 3.0

var _previous := PackedFloat64Array()
var _armed := true


func reset() -> void:
	_previous = PackedFloat64Array()
	_armed = true


## Drops the previous sample: the aircraft left the watch radius, far beyond REARM_DISTANCE_M, so it also re-arms.
func forget() -> void:
	_previous = PackedFloat64Array()
	_armed = true


## Hull points (body FRD triples about the CG) placed in the world for a position (NED) and attitude quaternion.
static func hull_world(position_ned: PackedFloat64Array, attitude: PackedFloat64Array, hull: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if position_ned.size() != 3 or attitude.size() != 4 or hull.size() % 3 != 0:
		return out
	out.resize(hull.size())
	for i in range(0, hull.size(), 3):
		var world: PackedFloat64Array = M.add(position_ned, M.q_rotate(attitude, hull.slice(i, i + 3)))
		out[i] = world[0]
		out[i + 1] = world[1]
		out[i + 2] = world[2]
	return out


## Observes one presentation sample. `station` = [north, east, ground down]; returns {} or
## {hit = true, speed_mps, point_ned} on the first crossing since the detector was armed.
func observe(points_ned: PackedFloat64Array, station: PackedFloat64Array, eye_height_m: float, dt_s: float) -> Dictionary:
	if points_ned.is_empty() or points_ned.size() % 3 != 0 or station.size() != 3 or not (dt_s > 0.0):
		_previous = points_ned.duplicate()
		return {}
	var axis_low := PackedFloat64Array([station[0], station[1], station[2] - RADIUS_M])
	var axis_high := PackedFloat64Array([station[0], station[1], station[2] - eye_height_m - HEAD_CLEARANCE_M + RADIUS_M])
	var result := {}
	var nearest := INF
	var swept := _previous.size() == points_ned.size()
	for i in range(0, points_ned.size(), 3):
		var now := points_ned.slice(i, i + 3)
		var before := _previous.slice(i, i + 3) if swept else now
		var distance := segment_distance(before, now, axis_low, axis_high)
		nearest = minf(nearest, distance)
		if _armed and result.is_empty() and distance <= RADIUS_M:
			var travel := sqrt(_square(now[0] - before[0]) + _square(now[1] - before[1]) + _square(now[2] - before[2]))
			result = {"hit": true, "speed_mps": travel / dt_s, "point_ned": now}
	_previous = points_ned.duplicate()
	if not result.is_empty():
		_armed = false
	elif not _armed and nearest > REARM_DISTANCE_M:
		_armed = true
	return result


## Shortest distance between segments PQ and AB (Ericson, Real-Time Collision Detection §5.1.9).
static func segment_distance(p: PackedFloat64Array, q: PackedFloat64Array, a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var d1 := [q[0] - p[0], q[1] - p[1], q[2] - p[2]]
	var d2 := [b[0] - a[0], b[1] - a[1], b[2] - a[2]]
	var r := [p[0] - a[0], p[1] - a[1], p[2] - a[2]]
	var aa := _dot(d1, d1)
	var ee := _dot(d2, d2)
	var f := _dot(d2, r)
	var s := 0.0
	var t := 0.0
	if aa <= 1e-12 and ee <= 1e-12:
		return sqrt(_dot(r, r))
	if aa <= 1e-12:
		t = clampf(f / ee, 0.0, 1.0)
	else:
		var c := _dot(d1, r)
		if ee <= 1e-12:
			s = clampf(-c / aa, 0.0, 1.0)
		else:
			var bb := _dot(d1, d2)
			var denominator := aa * ee - bb * bb
			s = clampf((bb * f - c * ee) / denominator, 0.0, 1.0) if denominator > 1e-12 else 0.0
			t = (bb * s + f) / ee
			if t < 0.0:
				t = 0.0
				s = clampf(-c / aa, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((bb - c) / aa, 0.0, 1.0)
	var dx: float = (p[0] + d1[0] * s) - (a[0] + d2[0] * t)
	var dy: float = (p[1] + d1[1] * s) - (a[1] + d2[1] * t)
	var dz: float = (p[2] + d1[2] * s) - (a[2] + d2[2] * t)
	return sqrt(dx * dx + dy * dy + dz * dz)


static func _dot(u: Array, v: Array) -> float:
	return float(u[0]) * float(v[0]) + float(u[1]) * float(v[1]) + float(u[2]) * float(v[2])


static func _square(x: float) -> float:
	return x * x
