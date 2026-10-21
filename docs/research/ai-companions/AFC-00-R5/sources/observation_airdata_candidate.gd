## Research candidate for Agent.observation(); preserves airspeed_m_s without building Air.compute's full result.
extends RefCounted

const Math3D := preload("res://physics/math3d.gd")
const RigidBody := preload("res://physics/rigid_body.gd")


static func airspeed_m_s(state: PackedFloat64Array, wind_ned: PackedFloat64Array) -> float:
	# Keep Air.compute's scalar rotation and arithmetic grouping exactly: only V is consumed by the pilot.
	var qw: float = state[RigidBody.ATT]
	var ux: float = -state[RigidBody.ATT + 1]
	var uy: float = -state[RigidBody.ATT + 2]
	var uz: float = -state[RigidBody.ATT + 3]
	var wx: float = wind_ned[0]
	var wy: float = wind_ned[1]
	var wz: float = wind_ned[2]
	var tx: float = (uy * wz - uz * wy) * 2.0
	var ty: float = (uz * wx - ux * wz) * 2.0
	var tz: float = (ux * wy - uy * wx) * 2.0
	var u: float = state[RigidBody.VEL] - ((wx + tx * qw) + (uy * tz - uz * ty))
	var v: float = state[RigidBody.VEL + 1] - ((wy + ty * qw) + (uz * tx - ux * tz))
	var w: float = state[RigidBody.VEL + 2] - ((wz + tz * qw) + (ux * ty - uy * tx))
	return Math3D.sqrt_(u * u + v * v + w * w)
