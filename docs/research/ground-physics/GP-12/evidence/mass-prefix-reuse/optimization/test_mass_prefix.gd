extends SceneTree
const Before:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/contact_assembly_resolution.gd")
const Candidate:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/contact_assembly_resolution.gd")
const GC:=preload("res://physics/generalized_coordinates.gd")
var checks:=0
var failed:=0
func check(label:String,condition:bool)->void:
	checks+=1
	if not condition:failed+=1;printerr("FAIL ",label)
func _operands(matrix:PackedFloat64Array,w:int)->Dictionary:
	var n:=3
	var z:=PackedFloat64Array();z.resize(w)
	var j:=PackedFloat64Array();j.resize(n*w)
	var bias:=PackedFloat64Array([.25,-.5,.75])
	for i in w:z[i]=.125*(i-1)
	for r in n:
		for k in w:j[r*w+k]=.25*(1+((r+2*k)%5))
	var factor:=GC.cholesky_factor(matrix,w)
	var responses:=PackedFloat64Array()
	for r in n:responses.append_array(GC.solve_cholesky(factor.lower,j.slice(r*w,(r+1)*w),w))
	var a:=PackedFloat64Array();a.resize(n*n)
	var v:=bias.duplicate()
	for r in n:
		for k in w:v[r]+=j[r*w+k]*z[k]
		for c in n:
			for k in w:a[r*n+c]+=j[r*w+k]*responses[c*w+k]
	return {a=a,v=v,mass_matrix=matrix,jacobian=j,z=z,bias=bias,responses=responses}
func _old(q:Dictionary)->Dictionary:return Before.bounds(q.a,q.v,q.mass_matrix,q.jacobian,q.z,q.bias,q.responses)
func _new(q:Dictionary,proof:RefCounted)->Dictionary:return Candidate._bounds_mass(q.a,q.v,q.mass_matrix,q.jacobian,q.z,q.bias,q.responses,proof)
func _case(matrix:PackedFloat64Array,w:int)->void:
	var q:=_operands(matrix,w)
	var before:=var_to_bytes(q)
	var prepared:=Candidate.prepare_mass(matrix,w)
	check("SPD preparation succeeds",prepared.ok)
	if not prepared.ok:return
	var baseline:=_old(q)
	check("synthetic assembly qualifies",baseline.ok)
	check("prepared complete bound output bytes equal",var_to_bytes(baseline)==var_to_bytes(_new(q,prepared.proof)))
	check("default complete bound output bytes equal",var_to_bytes(baseline)==var_to_bytes(_new(q,null)))
	check("arbitrary object is not proof authority",var_to_bytes(baseline)==var_to_bytes(_new(q,RefCounted.new())))
	check("unprepared typed object is not proof authority",var_to_bytes(baseline)==var_to_bytes(_new(q,Candidate.FixedMassProof.new())))
	check("complete operands unchanged",before==var_to_bytes(q))
	var original:PackedFloat64Array=matrix.duplicate()
	matrix[0]*=1.01
	check("changed caller matrix misses prepared key",not prepared.proof.matches(matrix,w))
	var changed:=_operands(matrix,w)
	check("changed matrix safely falls back with exact bytes",var_to_bytes(_old(changed))==var_to_bytes(_new(changed,prepared.proof)))
	matrix[0]=original[0]
	check("preparation detached original matrix",prepared.proof.matches(matrix,w))
	var other:=PackedFloat64Array();other.resize((w+1)*(w+1))
	for i in w+1:other[i*(w+1)+i]=2.0+i
	var wider:=_operands(other,w+1)
	check("changed width misses old proof",not prepared.proof.matches(other,w+1))
	check("changed width safely falls back with exact bytes",var_to_bytes(_old(wider))==var_to_bytes(_new(wider,prepared.proof)))
	var altered:=_new(q,prepared.proof)
	altered.operands.mass_matrix[0]=999.0
	check("output mutation cannot change prepared proof",var_to_bytes(baseline)==var_to_bytes(_new(q,prepared.proof)))
	q.a[0]*=1.01
	check("prepared mass never bypasses changed mobility refusal",not _new(q,prepared.proof).ok and var_to_bytes(_old(q))==var_to_bytes(_new(q,prepared.proof)))
func _initialize()->void:
	_case(PackedFloat64Array([2.0,.25,.25,3.0]),2)
	_case(PackedFloat64Array([3.0,.125,0.0,.125,4.0,.25,0.0,.25,5.0]),3)
	var zero:=PackedFloat64Array([2.0,0.0,0.0,3.0])
	var prepared:=Candidate.prepare_mass(zero,2)
	var negative_zero:=PackedByteArray([0,0,0,0,0,0,0,128]).to_float64_array()[0]
	zero[1]=negative_zero;zero[2]=negative_zero
	check("signed-zero matrix bytes require a fresh prefix",not prepared.proof.matches(zero,2))
	var q:=_operands(zero,2)
	check("signed-zero mismatch still preserves exact full bounds",var_to_bytes(_old(q))==var_to_bytes(_new(q,prepared.proof)))
	for matrix:PackedFloat64Array in [PackedFloat64Array([1.0,2.0,2.0,1.0]),PackedFloat64Array([1.0,0.0,.1,1.0]),PackedFloat64Array([NAN,0.0,0.0,1.0]),PackedFloat64Array([INF,0.0,0.0,1.0])]:
		check("invalid prepared matrix refuses",not Candidate.prepare_mass(matrix,2).ok)
	for w:int in [-1,0,71]:check("unsupported prepared width refuses",not Candidate.prepare_mass(PackedFloat64Array(),w).ok)
	var dir:=DirAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-drop-diagnosis")
	for name:String in dir.get_files():
		if not name.begins_with("qp-") or not name.ends_with(".bin"):continue
		var f:=FileAccess.open(dir.get_current_dir()+"/"+name,FileAccess.READ)
		var actual:Dictionary=bytes_to_var(f.get_buffer(f.get_length()));f.close()
		var proof:=Candidate.prepare_mass(actual.mass_matrix,actual.z.size())
		check("actual retained QP fixed matrix prepares",proof.ok)
		if proof.ok:
			check("actual retained QP complete bounds bytes equal",var_to_bytes(_old(actual))==var_to_bytes(_new(actual,proof.proof)))
	print("Prepared mass prefix: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
