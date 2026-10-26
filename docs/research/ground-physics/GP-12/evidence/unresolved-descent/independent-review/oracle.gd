extends SceneTree
const Old:=preload("res://physics/ground_traction.gd")
const OldStrategy:=preload("res://physics/contact_assembly_strategy.gd")
const QP:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-gentle-qp-review/source/traction_null.gd")
const Strategy:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-gentle-qp-review/source/strategy_null.gd")
const AR:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-gentle-qp-review/source/resolution_null.gd")
const Impulse:=preload("res://physics/aircraft_ground_impulse.gd")
var checks:=0
var failed:=0
var measured:Array=[]
func check(label:String,yes:bool)->void:
	checks+=1
	if not yes:failed+=1;printerr("FAIL ",label)
func objective(a:PackedFloat64Array,b:PackedFloat64Array,y:PackedFloat64Array)->float:
	var n:=y.size();var sum:=0.0
	for i in n:
		sum+=b[i]*y[i]
		for j in n:sum+=.5*y[i]*a[i*n+j]*y[j]
	return sum
func next_up(value:float)->float:
	var bytes:=PackedByteArray();bytes.resize(8);bytes.encode_double(0,value)
	bytes.encode_u64(0,bytes.decode_u64(0)+1)
	return bytes.decode_double(0)
func scalar_certificate(cap:float,impulse:float)->Dictionary:
	var one:=PackedFloat64Array([1.0]);var zero:=PackedFloat64Array([0.0])
	var assembly:=AR.bounds(one,one,one,one,one,zero,one)
	return AR.certificate(one,one,PackedFloat64Array([cap]),[PackedInt32Array([0])],PackedFloat64Array([impulse]),assembly)
func weak(curvature:float,drive:float,disk:bool)->void:
	var a:=PackedFloat64Array([1.0,1.0-curvature,1.0-curvature,1.0])
	var b:=PackedFloat64Array([-drive,drive])
	var y:=PackedFloat64Array([0.0,0.0]);var limits:=PackedFloat64Array([1.0,1.0])
	var groups:Array=[PackedInt32Array([0,1])] if disk else [PackedInt32Array([0]),PackedInt32Array([1])]
	var before:=var_to_bytes([a,b,y,limits,groups])
	var work:={calls=0,accepted=0}
	var proposal:=QP._interior_face(a,b,y,limits,groups,0.0,true,work,true)
	check("weak-mode trial is invoked and descends",work.calls==1 and work.accepted==1 and objective(a,b,proposal)<objective(a,b,y))
	check("trial inputs preserve exact original curvature and capacities",before==var_to_bytes([a,b,y,limits,groups]))
	check("deterministic repeated first-cap proposal bytes",var_to_bytes(proposal)==var_to_bytes(QP._interior_face(a,b,y,limits,groups,0.0,true,{calls=0,accepted=0},true)))
	if curvature>0.0 and drive/curvature<.5:
		var exact:=drive/curvature
		check("genuine weak positive curvature keeps interior optimum",absf(proposal[0]-exact)<1e-12 and absf(proposal[1]+exact)<1e-12)
		check("positive curvature never treated as a linear boundary drive",absf(proposal[0])<.5 and absf(proposal[1])<.5)
	elif disk:
		var length:=proposal[0]*proposal[0]+proposal[1]*proposal[1]
		check("disk first cap reached within float arithmetic",absf(length-1.0)<1e-14)
	else:
		check("first scalar cap reached without exceeding either cap",maxf(absf(proposal[0]),absf(proposal[1]))==1.0 and absf(proposal[0])<=1.0 and absf(proposal[1])<=1.0)
	measured.append({curvature=curvature,drive=drive,disk=disk,proposal=proposal,original_objective=objective(a,b,proposal),calls=work.calls,accepted=work.accepted})
func _initialize()->void:
	var eps:=pow(2.0,-42.0)
	weak(eps,.25*eps,false)
	weak(eps,2.0*eps,false)
	weak(eps,2.0*eps,true)
	weak(0.0,1.0,false)
	for cap:float in [AR.ETA,1e-200,.1,1.0]:
		for sign_value:float in [-1.0,1.0]:
			var equality:=scalar_certificate(cap,sign_value*cap)
			check("exact scalar equality never falsely called infeasible",not equality.get("reason","").contains("capacity"))
			var outside:=scalar_certificate(cap,sign_value*next_up(cap))
			check("oneULP scalar overshoot still refuses original set",not outside.ok and outside.get("reason","").contains("capacity"))
	check("zero scalar cap accepts exact zero",scalar_certificate(0.0,0.0).ok)
	check("zero scalar cap refuses smallest positive impulse",not scalar_certificate(0.0,AR.ETA).ok)
	var identity:=PackedFloat64Array([1.0,0.0,0.0,1.0]);var zeros:=PackedFloat64Array([0.0,0.0]);var ones:=PackedFloat64Array([1.0,1.0])
	var pair_assembly:=AR.bounds(identity,ones,identity,identity,ones,zeros,identity)
	var pair_outside:=AR.certificate(identity,ones,ones,[PackedInt32Array([0,1])],PackedFloat64Array([next_up(1.0),0.0]),pair_assembly)
	check("two-row outside disk is still rejected by original outward norm",not pair_outside.ok and pair_outside.get("reason","").contains("capacity"))
	for groups:Array in [[PackedInt32Array([0]),PackedInt32Array([1])],[PackedInt32Array([0,1])]]:
		for velocity:PackedFloat64Array in [PackedFloat64Array([0.0,0.0]),PackedFloat64Array([.1,-.2]),PackedFloat64Array([2.0,-3.0])]:
			var a:=PackedFloat64Array([1.0,.25,.25,2.0]);var d:=PackedFloat64Array([1.0,1.0])
			check("pure default strict complete outputs preserved",var_to_bytes(Old.solve(a,velocity,d,groups,1024))==var_to_bytes(QP.solve(a,velocity,d,groups,1024)))
			var m:=PackedFloat64Array([1.0,0.0,0.0,1.0]);var j:=PackedFloat64Array([1.0,0.0,0.0,1.0])
			# For this early strict-success case assembly operands are deliberately
			# inconsistent. Their proof is never called or needed for strict KKT.
			var memo:Dictionary={}
			var early:=Strategy._solve_local(a,velocity,d,groups,m,j,velocity,PackedFloat64Array([0.0,0.0]),j,1e-12,8,memo)
			var original:=OldStrategy.solve(a,velocity,d,groups,m,j,velocity,PackedFloat64Array([0.0,0.0]),j,1e-12,8)
			check("early strict result complete bytes unchanged",var_to_bytes(early)==var_to_bytes(original))
			check("strict successes do not eagerly build assembly bounds",not memo.has("builds") and not memo.has("source"))
	var f:=FileAccess.open("res://tests/fixtures/ground_contact_default_outputs.bin",FileAccess.READ)
	var golden:Dictionary=bytes_to_var(f.get_buffer(f.get_length())).cases;f.close()
	for name:String in ["ground_contact_rest_nonzero.bin","ground_contact_rest_proposal.bin","ground_contact_rest_range.bin","ground_contact_rest_slip.bin","ground_contact_rest_work.bin"]:
		f=FileAccess.open("res://tests/fixtures/"+name,FileAccess.READ);var raw:Dictionary=bytes_to_var(f.get_buffer(f.get_length()));f.close()
		var z:PackedFloat64Array=raw.velocity_cm_body.duplicate();z.append_array(raw.stage.velocity)
		var width:=z.size();var mass:=PackedFloat64Array();mass.resize(width*width)
		for i in 3:mass[i*width+i]=raw.mass_kg
		for i in width-3:
			for j in width-3:mass[(3+i)*width+3+j]=raw.stage.matrix[i*(width-3)+j]
		var valid:=Impulse._stage(raw.stage)
		var responses:=PackedFloat64Array()
		for row in raw.free_slip.size():responses.append_array(Impulse._response(valid.factor,raw.stage.axial.size(),raw.mass_kg,raw.jacobian.slice(row*width,(row+1)*width)))
		var now:=Strategy.solve(raw.mobility,raw.free_slip,raw.limits,raw.groups,mass,raw.jacobian,z,raw.prescribed_slip_bias,responses,3.125e-13,1024)
		var old:=OldStrategy.solve(raw.mobility,raw.free_slip,raw.limits,raw.groups,mass,raw.jacobian,z,raw.prescribed_slip_bias,responses,3.125e-13,1024)
		check("previous accepted near-rest complete strategy output preserved",var_to_bytes(now)==var_to_bytes(old))
		check("existing input fixture identity retained",FileAccess.get_sha256("res://tests/fixtures/"+name)==golden[name].input_sha256)
	f=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-gentle-qp-review/oracle-results.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({checks=checks,failed=failed,weak_modes=measured},"\t",true,true));f.close()
	print("Independent weak-mode oracle: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
