extends SceneTree
const I:=preload("res://physics/aircraft_ground_impulse.gd")
const R:=preload("res://physics/contact_assembly_resolution.gd")
var checks:=0
var failures:=0
func check(label:String,value:bool,detail:Variant="")->void:
	checks+=1
	if not value:
		failures+=1
		printerr("FAIL ",label," ",detail)
func _initialize()->void:

	var golden_path:="res://tests/fixtures/ground_contact_default_outputs.bin"
	check("frozen result bytes retain exact identity",FileAccess.get_sha256(golden_path)=="85df6ec77ea772eb55a5d1b9942e4d828ea78fae25fd833b93d6a6af1ece5133")
	var golden_file:=FileAccess.open(golden_path,FileAccess.READ)
	var golden:Dictionary=bytes_to_var(golden_file.get_buffer(golden_file.get_length())).cases
	golden_file.close()
	var paths:PackedStringArray=["res://tests/fixtures/ground_contact_rest_nonzero.bin",
		"res://tests/fixtures/ground_contact_rest_proposal.bin","res://tests/fixtures/ground_contact_rest_range.bin",
		"res://tests/fixtures/ground_contact_rest_slip.bin","res://tests/fixtures/ground_contact_rest_work.bin"]
	for path in paths:
		var file:=FileAccess.open(path,FileAccess.READ)
		var d:Dictionary=bytes_to_var(file.get_buffer(file.get_length()))
		file.close()
		var frozen:=var_to_bytes(d)
		var old:Dictionary=golden[path.get_file()].candidate
		var actual:=I.apply(d.stage,d.mass_kg,d.velocity_cm_body,d.jacobian,d.prescribed_slip_bias,d.limits,d.groups,1024,{},3.125e-13)
		check("retained case accepts before/after local reuse "+path,old.ok and actual.ok,actual)
		check("all public mathematical/state/certificate bytes equal "+path,var_to_bytes(old)==var_to_bytes(actual))
		check("complete strict-default bytes equal "+path,var_to_bytes(golden[path.get_file()].strict)
			==var_to_bytes(I.apply(d.stage,d.mass_kg,d.velocity_cm_body,d.jacobian,d.prescribed_slip_bias,d.limits,d.groups)))
		check("captured inputs remain detached "+path,var_to_bytes(d)==frozen)
		check("fixture byte identity "+path,FileAccess.get_sha256(path)==golden[path.get_file()].input_sha256)
		if actual.ok:check("total proposal sweeps honor caller budget "+path,actual.qp.get("iterations",0)<=1024)
		if path==paths[-1]:
			var memo:Dictionary={}
			var first:=R._memo_bounds(memo,d.mobility,d.free_slip,d.full_mass,d.jacobian,d.z,d.prescribed_slip_bias,d.flat_responses)
			var second:=R._memo_bounds(memo,d.mobility,d.free_slip,d.full_mass,d.jacobian,d.z,d.prescribed_slip_bias,d.flat_responses)
			check("same exact local operands reuse one verified build",first.ok and var_to_bytes(first)==var_to_bytes(second) and memo.builds==1)
			var changed:PackedFloat64Array=d.jacobian.duplicate()
			changed[0]+=1e-6
			var third:=R._memo_bounds(memo,d.mobility,d.free_slip,d.full_mass,changed,d.z,d.prescribed_slip_bias,d.flat_responses)
			check("changed operands never reuse old witness",memo.builds==2 and not third.ok)
			check("memo retains one operand set only",memo.size()==3)
			if actual.ok:print("REUSE_WORK ",actual.qp.numerical_work)
	print("Contact assembly strategy: %d checks, %d failed"%[checks,failures])
	quit(1 if failures else 0)
