extends SceneTree
const Before:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-stage-factor/baseline.gd")
const Candidate:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-stage-factor/candidate.gd")
const M:=preload("res://physics/math3d.gd")
const RB:=preload("res://physics/rigid_body.gd")
var checks:=0
var failed:=0
func check(label:String,yes:bool)->void:
	checks+=1
	if not yes:failed+=1;printerr("FAIL ",label)
func _initialize()->void:
	for count in [0,64]:
		var axial:=PackedFloat64Array();var transverse:=PackedFloat64Array();var spin:=PackedFloat64Array()
		var axes:=PackedFloat64Array();var rates:=PackedFloat64Array();var accels:=PackedFloat64Array()
		var external:=PackedFloat64Array();var internal:=PackedFloat64Array()
		for i in count:
			axial.append(.01+.0002*i);transverse.append(.006+.0001*i);spin.append(i*.1)
			var a:=M.v3(1.0+i%3,2.0,i%2);axes.append_array(M.scale(a,1.0/M.norm(a)))
			rates.append_array(M.v3(.01,-.02,.03));accels.append_array(M.v3(.03,.02,-.01))
			external.append_array(M.v3(.01,.02,.03));internal.append(-.01*i)
		var inertia:=PackedFloat64Array([1.2,1.5,1.8,.02,-.03,.04])
		var omega:=M.v3(.1,-.3,.2);var moment:=M.v3(.3,-.2,.1)
		var args:Array=[inertia,axial,transverse,omega,spin,axes,rates,accels,moment,external,internal,[]]
		var frozen:=var_to_bytes(args)
		var old:Dictionary=Before._evaluate_carrier.callv(args)
		var candidate:Dictionary=Candidate._evaluate_carrier.callv(args)
		check("body-only and maximum rotor count stay admitted",old.ok and candidate.ok)
		check("entire supported edge return bytes identical",var_to_bytes(old)==var_to_bytes(candidate))
		check("factor reuse cannot mutate input operands",frozen==var_to_bytes(args))
		if count==0:
			var expected:=RB.inertia_mul(RB.inertia_inverse(inertia),M.sub(moment,M.cross(omega,RB.inertia_mul(inertia,omega))))
			check("body-only acceleration agrees with independent Euler equation",M.norm(M.sub(expected,candidate.angular_acceleration))<1e-14)
	print("Independent stage-local factor review: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
