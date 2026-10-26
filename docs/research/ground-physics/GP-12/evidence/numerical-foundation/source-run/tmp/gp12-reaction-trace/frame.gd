extends RefCounted
const M:=preload("res://physics/math3d.gd")
const RB:=preload("res://physics/rigid_body.gd")
static func wrench(state:PackedFloat64Array,sample:Dictionary)->PackedFloat64Array:
	var q:=M.q_normalized(state.slice(RB.ATT,RB.ATT+4))
	var loads:PackedFloat64Array=sample.physical.loads
	var force:=loads.slice(0,3)
	var moment:=M.sub(loads.slice(3),M.cross(sample.cg_body_m,force))
	var result:=M.q_rotate(q,force)
	result.append_array(M.q_rotate(q,moment))
	return result
static func impulse(state:PackedFloat64Array,g:PackedFloat64Array)->PackedFloat64Array:
	var q:=M.q_normalized(state.slice(RB.ATT,RB.ATT+4))
	var result:=M.q_rotate(q,g.slice(0,3))
	result.append_array(M.q_rotate(q,g.slice(3,6)))
	return result
