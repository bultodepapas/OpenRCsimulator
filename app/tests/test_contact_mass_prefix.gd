## Fixed-M prefix reuse is a computational optimization, with no new law.
## Hashes bind complete original pre-extraction bounds; comparisons therefore
## do not reduce to testing the candidate against itself. Existing raw contact
## captures supply the physical assembly and full Impulse receipt regressions.
extends "res://tests/test_aircraft_ground_step.gd"
const Candidate:=preload("res://physics/contact_assembly_resolution.gd")
const GC:=preload("res://physics/generalized_coordinates.gd")
const BASELINE_STEP_SHA256:Dictionary={
  "fixed-hub-half-impulse-rk4-normal-half-impulse-v1": "c7947513f02059f604a3c5f4c8495f3e41e6260a5569ab4cc1940c5368ecf1e6",
  "fixed-hub-rk4-normal-endpoint-impulse-lie-v1": "243f6c851503981f0e0b4b150f2a7886ddf9c9728f24071e68e25e3e38564474"
}
const BASELINE_BOUNDS_SHA256:Dictionary={
  "ground_contact_rest_nonzero.bin": "4e6058052843f2e2cbfcf08160b699a615de60f53d155b055b8cc422e18c21bf",
  "ground_contact_rest_proposal.bin": "cf3aebf160130b1099c6ba35df76d43426e55e649fc3c2e829ca6a10736027e4",
  "ground_contact_rest_range.bin": "7d8a3f7bc29e1199a1426e0033308722ef471bfeecb177c7d6cb7802ea0f8a54",
  "ground_contact_rest_slip.bin": "9f8d431738f2bf8038a0e436966d608e7fef309b6ded8e4c6435dcdd37651145",
  "ground_contact_rest_work.bin": "889f0ab9b847c6eef4852b78e73a10ec59f7bd7d5f4d73779b81c3762200c377",
  "signed_zero": "e7f9300b44e1779426bd63dad74a279d6c618aaefcc435149072392d677710b2",
  "three.base": "d5ec51ad45d12d4662593e94820114dbedb29787edd4b940e8fb2fdb3da8d0c8",
  "three.changed": "caca24f613d03ff729d51009c251304848aeb5f6c327029e4243c97619541d82",
  "three.invalid_mobility": "7778ec18f1bd55413c0b95a400100dfdfc1bb1f3c2ddadd5f4e00c262282532d",
  "three.wider": "68d47b2cbc922a577f695c9a3c5d56d01ed3012349c9bc63dbc7b1f0394d4390",
  "two.base": "89903fcbc7a36589c26e9f4e5d0107688b1528829a0e9f593e70ec45e187a30c",
  "two.changed": "851f242847c0e1f8fd06fb2cb056075ba06a68b7e8fde8b334f9bda99f2edb48",
  "two.invalid_mobility": "7778ec18f1bd55413c0b95a400100dfdfc1bb1f3c2ddadd5f4e00c262282532d",
  "two.wider": "ae0fc13d36b03af57d94a16773ccac867fb9f2472df2afe1cd200b3918fabc96",
  "zero_mass": "378cc67252f84710d8aedae8a98fd620ccf7a418db2a3a93808e0b1fca1111dd"
}
const FIXTURES:PackedStringArray=["ground_contact_rest_nonzero.bin","ground_contact_rest_proposal.bin",
	"ground_contact_rest_range.bin","ground_contact_rest_slip.bin","ground_contact_rest_work.bin"]
var checks:=0
var failed:=0
func check(label:String,condition:bool)->void:
	checks+=1
	if not condition:failed+=1;printerr("FAIL ",label)
func _digest(value:Variant)->String:
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()
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
func _expected_bounds(id:String,q:Dictionary)->Dictionary:
	var result:=Candidate.bounds(q.a,q.v,q.mass_matrix,q.jacobian,q.z,q.bias,q.responses)
	check("complete original bound return bytes "+id,BASELINE_BOUNDS_SHA256.has(id) and _digest(result)==BASELINE_BOUNDS_SHA256[id])
	return result
func _new(q:Dictionary,proof:RefCounted)->Dictionary:
	return Candidate._bounds_mass(q.a,q.v,q.mass_matrix,q.jacobian,q.z,q.bias,q.responses,proof)
func _case(id:String,matrix:PackedFloat64Array,w:int)->void:
	var q:=_operands(matrix,w)
	var before:=var_to_bytes(q)
	var prepared:=Candidate.prepare_mass(matrix,w)
	check("SPD preparation succeeds",prepared.ok)
	if not prepared.ok:return
	var baseline:=_expected_bounds(id+".base",q)
	check("synthetic assembly qualifies",baseline.ok)
	for proof:RefCounted in [prepared.proof,null,RefCounted.new(),Candidate.FixedMassProof.new()]:
		check("prepared/null/arbitrary/unprepared fallback complete bytes equal",var_to_bytes(baseline)==var_to_bytes(_new(q,proof)))
	check("complete operands unchanged",before==var_to_bytes(q))
	var original:PackedFloat64Array=matrix.duplicate()
	matrix[0]*=1.01
	check("changed caller matrix misses prepared key",not prepared.proof.matches(matrix,w))
	var changed:=_operands(matrix,w)
	check("changed matrix fallback original return bytes",var_to_bytes(_expected_bounds(id+".changed",changed))==var_to_bytes(_new(changed,prepared.proof)))
	matrix[0]=original[0]
	check("preparation detached original matrix",prepared.proof.matches(matrix,w))
	var other:=PackedFloat64Array();other.resize((w+1)*(w+1))
	for i in w+1:other[i*(w+1)+i]=2.0+i
	var wider:=_operands(other,w+1)
	check("changed width misses old proof",not prepared.proof.matches(other,w+1))
	check("changed width fallback original return bytes",var_to_bytes(_expected_bounds(id+".wider",wider))==var_to_bytes(_new(wider,prepared.proof)))
	var altered:=_new(q,prepared.proof)
	altered.operands.mass_matrix[0]=999.0
	check("output mutation cannot change prepared proof",var_to_bytes(baseline)==var_to_bytes(_new(q,prepared.proof)))
	q.a[0]*=1.01
	var invalid:=_expected_bounds(id+".invalid_mobility",q)
	check("prepared mass never bypasses changed mobility refusal",not invalid.ok and var_to_bytes(invalid)==var_to_bytes(_new(q,prepared.proof)))
func _read(path:String)->Dictionary:
	var file:=FileAccess.open("res://tests/fixtures/"+path,FileAccess.READ)
	check("existing fixture opens "+path,file!=null)
	if file==null:return {}
	var result:Dictionary=bytes_to_var(file.get_buffer(file.get_length()));file.close()
	return result
func _fixture_case(name:String,golden:Dictionary)->void:
	var raw:=_read(name)
	if raw.is_empty():return
	check("fixture original byte identity "+name,FileAccess.get_sha256("res://tests/fixtures/"+name)==golden[name].input_sha256)
	var w:int=6+raw.stage.axial.size()
	var z:PackedFloat64Array=raw.velocity_cm_body.duplicate();z.append_array(raw.stage.velocity)
	var matrix:=PackedFloat64Array();matrix.resize(w*w)
	for i in 3:matrix[i*w+i]=raw.mass_kg
	for i in w-3:
		for j in w-3:matrix[(3+i)*w+3+j]=raw.stage.matrix[i*(w-3)+j]
	var valid:=Impulse._stage(raw.stage)
	check("retained common rotor stage validates",valid.ok)
	if not valid.ok:return
	var responses:=PackedFloat64Array()
	for row in raw.free_slip.size():responses.append_array(Impulse._response(valid.factor,raw.stage.axial.size(),raw.mass_kg,raw.jacobian.slice(row*w,(row+1)*w)))
	var q:={a=raw.mobility,v=raw.free_slip,mass_matrix=matrix,jacobian=raw.jacobian,z=z,bias=raw.prescribed_slip_bias,responses=responses}
	var frozen:=var_to_bytes([raw,q])
	var prepared:=Candidate.prepare_mass(matrix,w)
	check("actual retained matrix prepares",prepared.ok)
	if not prepared.ok:return
	var baseline:=_expected_bounds(name,q)
	check("actual retained bounds qualify",baseline.ok)
	check("actual complete prepared bounds equal original bytes",var_to_bytes(baseline)==var_to_bytes(_new(q,prepared.proof)))
	var ordinary:=Impulse.apply(raw.stage,raw.mass_kg,raw.velocity_cm_body,raw.jacobian,raw.prescribed_slip_bias,raw.limits,raw.groups,1024,{},3.125e-13)
	var reused:=Impulse.apply(raw.stage,raw.mass_kg,raw.velocity_cm_body,raw.jacobian,raw.prescribed_slip_bias,raw.limits,raw.groups,1024,{},3.125e-13,prepared.proof)
	check("actual original and prepared impulse both accept",ordinary.ok and reused.ok)
	check("entire actual impulse/objective/work/receipt bytes equal",var_to_bytes(ordinary)==var_to_bytes(reused))
	check("retained inputs unchanged",frozen==var_to_bytes([raw,q]))
func _step_api_case()->void:
	_fixture()
	check("existing one-wheel/shaft stage fixture prepares",_failed==0)
	if _failed:return
	var state:=_initial(-.08,_p([3,0,.3]))
	var frozen:=var_to_bytes(state)
	var point:=_evaluate(state,0.0)
	var w:int=6+point.rotor_stage.axial.size()
	var matrix:=PackedFloat64Array();matrix.resize(w*w)
	for i in 3:matrix[i*w+i]=point.mass_kg
	for i in w-3:
		for j in w-3:matrix[(3+i)*w+3+j]=point.rotor_stage.matrix[i*(w-3)+j]
	var prepared:=Candidate.prepare_mass(matrix,w)
	check("public Step owner mass proof prepares",prepared.ok)
	if not prepared.ok:return
	for law:String in [Step.LAW,Step.TWO_SIDED_LAW]:
		var options:={operator_law=law,maximum_assembly_resolution_j=3.125e-13}
		var ordinary:=Step.advance(state,0.0,.01,_derivative,PackedFloat64Array(),_evaluate,_certificate,options)
		var reused:=Step.advance(state,0.0,.01,_derivative,PackedFloat64Array(),_evaluate,_certificate,options,Callable(),Callable(),prepared.proof)
		check("original whole Step output bytes "+law,BASELINE_STEP_SHA256.has(law) and _digest(ordinary)==BASELINE_STEP_SHA256[law])
		check("both original and prepared Step paths accept",ordinary.ok and reused.ok)
		check("entire accepted state/objective/receipt bytes equal",var_to_bytes(ordinary)==var_to_bytes(reused))
	check("public Step input state unchanged",frozen==var_to_bytes(state))
func _initialize()->void:
	_case("two",PackedFloat64Array([2.0,.25,.25,3.0]),2)
	_case("three",PackedFloat64Array([3.0,.125,0.0,.125,4.0,.25,0.0,.25,5.0]),3)
	var zero:=PackedFloat64Array([2.0,0.0,0.0,3.0])
	var prepared:=Candidate.prepare_mass(zero,2)
	var negative_zero:=PackedByteArray([0,0,0,0,0,0,0,128]).to_float64_array()[0]
	zero[1]=negative_zero;zero[2]=negative_zero
	check("signed-zero bytes require a fresh prefix",not prepared.proof.matches(zero,2))
	var q:=_operands(zero,2)
	check("signed-zero fallback original complete bounds",var_to_bytes(_expected_bounds("signed_zero",q))==var_to_bytes(_new(q,prepared.proof)))
	q.mass_matrix=PackedFloat64Array([0.0,0.0,0.0,0.0])
	var invalid:=_expected_bounds("zero_mass",q)
	check("zero matrix never receives old proof authority",not invalid.ok and var_to_bytes(invalid)==var_to_bytes(_new(q,prepared.proof)))
	for matrix:PackedFloat64Array in [PackedFloat64Array([0.0,0.0,0.0,0.0]),PackedFloat64Array([1.0,2.0,2.0,1.0]),PackedFloat64Array([1.0,0.0,.1,1.0]),PackedFloat64Array([NAN,0.0,0.0,1.0]),PackedFloat64Array([INF,0.0,0.0,1.0])]:
		check("invalid prepared matrix refuses",not Candidate.prepare_mass(matrix,2).ok)
	for w:int in [-1,0,71]:check("unsupported prepared width refuses",not Candidate.prepare_mass(PackedFloat64Array(),w).ok)
	check("frozen fixture return register identity",FileAccess.get_sha256("res://tests/fixtures/ground_contact_default_outputs.bin")=="85df6ec77ea772eb55a5d1b9942e4d828ea78fae25fd833b93d6a6af1ece5133")
	var golden:Dictionary=_read("ground_contact_default_outputs.bin").cases
	for name:String in FIXTURES:_fixture_case(name,golden)
	_step_api_case()
	print("Prepared contact mass prefix: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
