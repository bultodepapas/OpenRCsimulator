extends "res://tests/avanti_rudder_base.gd"
const AD := preload("res://physics/aircraft_data.gd")
const Trim := preload("res://physics/trim.gd")
var checks := 0
var failures := 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	var loaded:=AD.load_file(data_path)
	check("aircraft loads",loaded.ok)
	var model:Dictionary=loaded.model
	var fin:Dictionary=model.surfaces.vertical
	var b:float=model.reference.b
	var S:float=model.reference.S
	var lv:float=fin.position[0]-model.cg_le[0]
	var zv:float=fin.position[2]-model.cg_le[2]
	var cyb:float=-fin.lift_slope*fin.area/S
	var cl_ref:float=model.mass_kg*9.80665/(0.5*1.225*model.start_speed*model.start_speed*S)
	var targets := [-cl_ref/8.0-2.0*lv*zv/(b*b)*cyb, -0.005+2.0*pow(lv/b,2)*cyb-0.02]
	var state:=Trim.state_for(45.0,0.0,0.0,0.0,M.v3(0,0,-500))
	var air:=Air.compute(state,M.v3(0,0,0),1.225)
	var d:Dictionary={aileron_right=0.0,aileron_left=0.0,elevator=0.0,rudder=0.0}
	for index in 2:
		var slot:int=10 if index==0 else 12
		state[slot]=0.01
		var plus:=Aero._global_loads(state,air,d,model,1.225)
		state[slot]=-0.01
		var minus:=Aero._global_loads(state,air,d,model,1.225)
		state[slot]=0.0
		var actual:float=(plus[5]-minus[5])/0.02*2.0*air.V/(air.qbar*S*b*b)
		check("yaw rate moment about CG matches its physical build-up %d"%index,absf(actual-targets[index])<1e-6)
	for pair in [[29.0,0.5],[45.0,0.5],[60.0,0.5],[45.0,-0.5],[45.0,1.0]]:
		var result:=run_case(pair[0],pair[1])
		check("complete finite yaw pulse/release",result.completed)
		check("no counter-command or servo reversal on release",result.command_opposite<1e-12 and result.rudder_opposite<1e-8)
		check("pitch and roll channels remain neutral",result.unwanted_command==0.0)
		check("release rebound is bounded",absf(result.return_yaw_rate)<(14.0 if absf(pair[1])==0.5 else 38.0))
		check("sideslip oscillation decays",result.late_beta<0.5)
	print("AV-17-R3 yaw flight: %d checks, %d failed"%[checks,failures])
	quit(0 if failures==0 else 1)
