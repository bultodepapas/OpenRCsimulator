extends SceneTree
const H:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-hull-lake/draft/hull_contact.gd")
const Old:=preload("res://physics/hull_contact.gd")
const RB:=preload("res://physics/rigid_body.gd")
const M:=preload("res://physics/math3d.gd")
const Lake:=preload("res://data/lake_loader.gd")
var checks:=0
var failed:=0
func check(label:String,ok:bool)->void:
	checks+=1
	if not ok:failed+=1;printerr("FAIL ",label)
func _initialize()->void:
	var loaded:=Lake.load_from()
	check("real configured lake loads",loaded.ok)
	if not loaded.ok:quit(1);return
	var inertia:=PackedFloat64Array([1.0,1.2,1.4,.01,.02,-.01])
	var props:={mass_kg=2.0,cg_body_m=M.v3(.12,-.04,.02),inertia=inertia,inverse=RB.inertia_inverse(inertia)}
	var state:=RB.make_state(M.v3(0,0,.01),M.v3(5,0,0),M.q_identity(),M.v3(0,0,0))
	var hulls:Array=[PackedFloat64Array([0,0,0]),PackedFloat64Array([110,125,0]),PackedFloat64Array([0,0,0,110,125,0]),PackedFloat64Array([110,125,0,0,0,0])]
	for index in hulls.size():
		var hull:PackedFloat64Array=hulls[index]
		var prepared:=H.prepare(hull,2.0,inertia,loaded.lake)
		var old:=Old.prepare(hull,2.0,inertia,loaded.lake)
		var diagnostics:={stale=true}
		var force:=H.loads(state,prepared,[],diagnostics)
		check("constant default force exact",var_to_bytes(force)==var_to_bytes(Old.loads(state,old)) and var_to_bytes(force)==var_to_bytes(H.loads(state,prepared)))
		check("outside-only qualifies otherwise batch atomically unavailable",diagnostics.available==(index==0) and (diagnostics.rows.size()==1 if index==0 else diagnostics.rows.is_empty()))
		if index>0:check("covered reason retained",diagnostics.reason=="covered_lake_branch_unqualified")
		var array:Array=[{stale=true}]
		H.loads(state,prepared,[],array)
		check("historical Array lake collector unchanged",array.is_empty())
		var geometry:=H.prepare_geometry(hull,loaded.lake)
		var dynamic:={}
		var result:=H.loads_at_properties(state,geometry,props,dynamic)
		var reference:=Old.loads_at_properties(state,Old.prepare_geometry(hull,loaded.lake),props)
		check("live-mass complete force result exact",var_to_bytes(result)==var_to_bytes(reference))
		check("dynamic reason survives active and no-active routes",dynamic.available==(index==0) and (dynamic.reason=="" if index==0 else dynamic.reason=="covered_lake_branch_unqualified"))
		state[RB.POS+2]=-1.0
		H.loads_at_properties(state,geometry,props,dynamic)
		check("proven high noforce route yields available empty rows",dynamic.available and dynamic.rows.is_empty())
		state[RB.POS+2]=.01
	print("Independent dry lake collector: ",checks," checks, ",failed," failed")
	quit(1 if failed else 0)
