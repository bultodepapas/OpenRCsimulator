extends SceneTree
const AD=preload("res://physics/aircraft_data.gd")
const OP=preload("res://physics/glow/operating_point.gd")
var checks:=0
var failures:=0
func check(label: String,value: bool):
	checks+=1
	if not value: failures+=1;print("FAIL ",label)
func _initialize():
	for id in ["55ax_2t","fs64v_4t","55ax_2t_apc_13x6","fs64v_4t_apc_13x6"]:
		var loaded: Dictionary=AD.load_file("res://data/aircraft/stik_glow_"+id+".json")
		check(id+" loads",loaded.ok)
		if not loaded.ok: continue
		var prop: Dictionary=loaded.model.propulsion
		for throttle in [0.,.25,.5,.75,1.]:
			for u in [0.,15.,20.]:
				var solved: Dictionary=OP.solve(prop,throttle,u,1.225,1.225)
				check(id+" supported root",solved.ok)
				if not solved.ok: continue
				check(id+" torque balance",absf(OP.residual(prop,solved.rpm,throttle,u,1.225,1.225))<=1e-10)
				check(id+" restoring branch",OP.residual(prop,solved.rpm-.001,throttle,u,1.225,1.225)>0. and OP.residual(prop,solved.rpm+.001,throttle,u,1.225,1.225)<0.)
		var synthetic: Dictionary=prop.duplicate(true)
		synthetic.glow.profile.parameters.indicated_efficiency=PackedFloat64Array([0.,0.,5000.1,0.,5000.15,.9,5000.2,0.,8000.1,0.,8000.15,.9,8000.2,0.,synthetic.glow.profile.operation.max_rpm,0.])
		var peaks: Dictionary=OP.solve(synthetic,1.,0.,1.225,1.225)
		check(id+" narrow two-branch table",peaks.ok and peaks.roots.size()==2 and peaks.rpm>8000.15 and peaks.rpm<8000.2)
		synthetic.glow.profile.parameters.indicated_efficiency=PackedFloat64Array([0.,0.,synthetic.glow.profile.operation.max_rpm,0.])
		check(id+" absent root is refused",not OP.solve(synthetic,1.,0.,1.225,1.225).ok)
		check(id+" invalid throttle is refused",not OP.solve(prop,1.1,0.,1.225,1.225).ok)
	print("Glow equilibria: ",checks," checks, ",failures," failed")
	quit(1 if failures else 0)
