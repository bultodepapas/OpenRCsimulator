extends SceneTree
const S:=preload("res://physics/contact_assembly_strategy.gd")
const I:=preload("res://physics/aircraft_ground_impulse.gd")
const QP:=preload("res://physics/ground_traction.gd")
const AR:=preload("res://physics/contact_assembly_resolution.gd")
var checks:=0
var failed:=0
var controls:Dictionary
const INPUT_SHA:={"ground_contact_unresolved_16.bin":"9d066b9e540d817e9a3d5d9770f46fe9d2b4f17da31d72a575629f50009e7e1f","ground_contact_unresolved_8.bin":"b565d3edd1b997704b75369e6e7f8c8e50b08ed63f8c3a268df9443cf0536bc6","ground_contact_unresolved_defaults.bin":"e9573e09f971d5d4dcc285e8038b034c3015c9bca57d5f9719ffd9acab759b52"}
func check(label:String,condition:bool,detail:Variant="")->void:
	checks+=1
	if not condition:failed+=1;print("FAIL ",label," ",detail)
func _initialize()->void:
	var frozen:=FileAccess.open("res://tests/fixtures/ground_contact_unresolved_defaults.bin",FileAccess.READ)
	var frozen_bytes:=frozen.get_buffer(frozen.get_length());frozen.close()
	check("frozen default controls retain exact bytes",_digest(frozen_bytes)==INPUT_SHA["ground_contact_unresolved_defaults.bin"])
	controls=bytes_to_var(frozen_bytes)
	_scalar_cases()
	var ordinary:Dictionary=controls.ordinary
	check("ordinary <=8 default complete bytes frozen",var_to_bytes(QP.solve(ordinary.a,ordinary.v,ordinary.d,ordinary.groups))==var_to_bytes(ordinary.result))
	# Independent symmetry oracle: two tire disks with a weak coupled lateral
	# direction. Its positive curvature is kept, not regularized or made zero.
	var c:=1.0-2e-13
	var a:=PackedFloat64Array([1,0,0,0,0,1,0,c,0,0,1,0,0,c,0,1])
	var b:=PackedFloat64Array([.2,1e-7,.2,-1e-7])
	var d:=PackedFloat64Array([1,1,1,1])
	var groups:=[PackedInt32Array([0,1]),PackedInt32Array([2,3])]
	var result:=QP._solve_for_assembly(a,b,d,groups,1024,true)
	check("coupled disks recover original strict KKT",result.ok,str(result))
	if result.ok:
		var lo:=0.0;var hi:=1.0
		for iteration in 80:
			var mid:=.5*(lo+hi)
			var norm:float=pow(.2/(1.0+mid),2)+pow(1e-7/(1.0-c+mid),2)
			if norm>1.0:lo=mid
			else:hi=mid
		var lambda:=.5*(lo+hi)
		var x:float=-.2/(1.0+lambda)
		var y:float=-1e-7/(1.0-c+lambda)
		check("independent constrained optimum x agrees",absf(result.impulse[0]-x)<1e-8 and absf(result.impulse[2]-x)<1e-8)
		check("independent constrained optimum y agrees",absf(result.impulse[1]-y)<1e-8 and absf(result.impulse[3]+y)<1e-8)
	# A tiny but POSITIVE unresolved curvature has an interior line minimizer.
	var weak:float=1.0-c
	var toy:=PackedFloat64Array([1,c,c,1])
	var linear:=PackedFloat64Array([weak*.25,-weak*.25])
	var proposal:=QP._interior_face(toy,linear,PackedFloat64Array([0,0]),PackedFloat64Array([1,1]),[PackedInt32Array([0]),PackedInt32Array([1])],0.0,true,{},true)
	check("positive weak curvature prevents a cap-only move",proposal.size()==2 and absf(proposal[0]+.25)<1e-6 and absf(proposal[1]-.25)<1e-6,str(proposal))
	check("original full objective descends",QP._objective(toy,linear,proposal)<0.0)
	var root:="res://tests/fixtures/"
	var outputs:Array=[]
	for name:String in DirAccess.get_files_at(root):
		if not name.begins_with("ground_contact_unresolved_") or name=="ground_contact_unresolved_defaults.bin" or not name.ends_with(".bin"):continue
		var f:=FileAccess.open(root+name,FileAccess.READ)
		var bytes:=f.get_buffer(f.get_length());f.close()
		check("lossless captured QP fixture exact bytes",_digest(bytes)==INPUT_SHA[name])
		var q:Dictionary=bytes_to_var(bytes)
		var input_before:=var_to_bytes(q)
		var solve:=S.solve(q.a,q.v,q.limits,q.groups,q.mass_matrix,q.jacobian,q.z,q.bias,q.responses,q.ceiling,1024)
		check("captured case strict acceptance after bounded fallback",solve.ok and not solve.has("assembly_resolution"),str(solve))
		check("old and new pure strict defaults are byte-identical",var_to_bytes(controls.pure_results[name])==var_to_bytes(QP.solve(q.a,q.v,q.limits,q.groups,1024)))
		for budget in [1,8,16,24,25]:
			var bounded:=S.solve(q.a,q.v,q.limits,q.groups,q.mass_matrix,q.jacobian,q.z,q.bias,q.responses,q.ceiling,budget)
			check("total proposal sweeps respect caller budget",bounded.iterations<=budget and bounded.numerical_work.started_sweeps<=budget)
		var applied:=I.apply(q.stage,q.mass_matrix[0],q.z.slice(0,3),q.jacobian,q.bias,q.limits,q.groups,1024,{},q.ceiling)
		check("actual common mass/slip/work impulse accepts",applied.ok,str(applied))
		if applied.ok:
			check("actual mass equation retains original target",applied.mass_solve_relative_residual<=I.RESIDUAL_RELATIVE_TOLERANCE)
			check("actual slip retains original target",applied.slip_relative_residual<=I.RESIDUAL_RELATIVE_TOLERANCE)
			check("actual independent impulse work closes",absf(applied.energy_balance_residual)<1e-12)
		check("input arrays and frozen stage remain detached",input_before==var_to_bytes(q))
		outputs.append({input=name,solve=solve,applied=applied})
	# Zero preference must run BEFORE enabling the new unresolved trial.
	var identity:=PackedFloat64Array([1,0,0,1])
	var j:=PackedFloat64Array([1,0,c,sqrt(1-c*c)])
	var gram:=PackedFloat64Array([1,c,c,c*c+(1-c*c)])
	var zero:=PackedFloat64Array([0,0]);var tiny:=PackedFloat64Array([1e-25,-1e-25])
	var responses:=PackedFloat64Array([1,0,c,sqrt(1-c*c)])
	var scalar_groups:=[PackedInt32Array([0]),PackedInt32Array([1])]
	var old_zero:Dictionary=controls.zero_result
	var new_zero:=S.solve(gram,tiny,PackedFloat64Array([1,1]),scalar_groups,identity,j,zero,tiny,responses,1e-10,1024)
	check("zero-optimal probe preserves complete result bytes",var_to_bytes(old_zero)==var_to_bytes(new_zero),str(new_zero))
	print("Contact unresolved descent: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)

func _next(value:float)->float:
	var bytes:=PackedByteArray();bytes.resize(8);bytes.encode_double(0,value)
	bytes.encode_u64(0,bytes.decode_u64(0)+1)
	return bytes.decode_double(0)
func _certificate(d:float,p:float)->Dictionary:
	var a:=PackedFloat64Array([1.0]);var v:=PackedFloat64Array([1.0]);var z:=PackedFloat64Array([1.0]);var zero:=PackedFloat64Array([0.0])
	var assembly:=AR.bounds(a,v,a,a,z,zero,a)
	return AR.certificate(a,v,PackedFloat64Array([d]),[PackedInt32Array([0])],PackedFloat64Array([p]),assembly)

func _scalar_cases()->void:
	for d:float in [AR.ETA,1e-200,.1,1.0]:
		for sign_value:float in [-1.0,1.0]:
			var equality:=_certificate(d,sign_value*d)
			check("exact scalar equality not called infeasible",not equality.get("reason","").contains("capacity"),str(equality))
			var outside:=_certificate(d,sign_value*_next(d))
			check("oneULP outside exact scalar interval refuses",not outside.ok and outside.get("reason","").contains("capacity"),str(outside))
	for p:float in [0.0,-0.0]:
		check("signed zero obeys zero capacity",_certificate(0.0,p).ok)
	check("subnormal nonzero cannot bypass zero cap",not _certificate(0.0,AR.ETA).ok)
	check("infinite capacity refuses supported finite domain",not _certificate(INF,0.0).ok)
	check("infinite impulse refuses supported finite domain",not _certificate(1.0,INF).ok)
	check("finite energy overflow refuses",not _certificate(1.7e308,1.7e308).ok)

func _digest(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
