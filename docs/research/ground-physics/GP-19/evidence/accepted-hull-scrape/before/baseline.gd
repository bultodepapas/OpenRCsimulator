## Pure existing-law audit, not an acoustic or accepted-interval work measurement.
extends SceneTree
const Hull := preload("res://physics/hull_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
var checks:=0
var failed:=0
func check(label:String,passed:bool)->void:
	checks+=1
	if not passed:failed+=1;printerr("FAIL ",label)
func _initialize()->void:
	var prepared:=Hull.prepare(PackedFloat64Array([0.0,0.0,0.0]),1.0,PackedFloat64Array([1.0,1.0,1.0,0.0,0.0,0.0]))
	check("single COM point prepares under current law",not prepared.is_empty())
	var rows:=[]
	for state_case:Array in [["loaded_slide",10.0,0.0],["unloaded_opening_slide",10.0,-1.0],["loaded_stationary",0.0,0.0]]:
		var state:=RB.make_state(M.v3(0.0,0.0,0.002),M.v3(state_case[1],0.0,state_case[2]),M.q_identity(),M.v3(0.0,0.0,0.0))
		var contacts:=Hull.contacts(state,state,prepared)
		var force:=Hull.loads(state,prepared)
		var power: float=0.0 if force.is_empty() else -force[0]*state_case[1]
		check("geometric contact exists "+str(state_case[0]),contacts.size()==1 and contacts[0].depth_m>0.0)
		if state_case[0]=="loaded_slide":check("existing force gives independent 28.8 W tangent loss",not force.is_empty() and absf(power-28.8)<1e-12)
		elif state_case[0]=="unloaded_opening_slide":check("speed-only scrape can occur with zero physical friction",contacts[0].slide_speed_mps==10.0 and force.is_empty() and power==0.0)
		else:check("loaded zero slip gives zero friction power",not force.is_empty() and power==0.0)
		check("legacy contact record has no force/work evidence",not contacts[0].has("normal_force_n") and not contacts[0].has("friction_power_w") and not contacts[0].has("friction_work_j"))
		rows.append({scenario=state_case[0],contacts=contacts,loads=Array(force),instantaneous_tangent_power_w=power})
	var output:=ProjectSettings.globalize_path("res://../tmp/gp19-hull-scrape/observations.json")
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(rows,"\t",true,true));file.close()
	print("Hull scrape audit: %d checks, %d failed"%[checks,failed]);quit(1 if failed else 0)
