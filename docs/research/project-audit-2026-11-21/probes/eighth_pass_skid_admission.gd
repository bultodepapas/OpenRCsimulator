extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Field=preload("res://data/field_loader.gd")
const Weather=preload("res://physics/wind_config.gd")
const M=preload("res://physics/math3d.gd")
const Skids=preload("res://physics/rotorcraft/skid_contact.gd")
const Adapter=preload("res://physics/rotorcraft/simulation_step_adapter.gd")
const Data=preload("res://physics/rotorcraft_data.gd")
var checks: int=0
var failures: int=0
var active: Node
var min_normal: float=INF
var max_normal: float=0.0
var max_traction_fraction: float=0.0
var stage_calls: int=0
var stage_bad: bool=false
var max_rotor_speed: float=0.0

func check(label: String,condition: bool) -> void:
	checks+=1
	if not condition:
		failures+=1
		print("FAIL ",label)

func _initialize() -> void:
	Engine.physics_ticks_per_second=240
	_run.call_deferred()

func _derivative(state: PackedFloat64Array,t: float) -> PackedFloat64Array:
	stage_calls+=1
	max_rotor_speed=maxf(max_rotor_speed,absf(state[13]))
	var contact: Dictionary=Skids.evaluate(state.slice(0,13),active.aircraft.skids,active.ground_surfaces,true,state.slice(19),active.environment.lake)
	if not contact.get("ok",false):
		stage_bad=true
		return PackedFloat64Array()
	for i: int in 4:
		var normal: float=contact.normal_forces_n[i]
		min_normal=minf(min_normal,normal)
		max_normal=maxf(max_normal,normal)
		var tangent: float=sqrt(pow(contact.bristle_force_world_n[2*i],2)+pow(contact.bristle_force_world_n[2*i+1],2))
		if normal>0.0: max_traction_fraction=maxf(max_traction_fraction,tangent/(0.35*normal))
	var result: Dictionary=active._stage(state.slice(0,13),state.slice(13),t)
	if result.is_empty():
		stage_bad=true
		return PackedFloat64Array()
	var out: PackedFloat64Array=result.body_derivative.duplicate()
	out.append_array(result.derivative)
	return out

func _refine(initial: PackedFloat64Array,n: int) -> Dictionary:
	min_normal=INF
	max_normal=0.0
	max_traction_fraction=0.0
	stage_calls=0
	stage_bad=false
	max_rotor_speed=0.0
	var state: PackedFloat64Array=initial.duplicate()
	var h: float=1.0/(240.0*float(n))
	var events: Array=[]
	for i: int in n:
		var t: float=float(i)*h
		var first: PackedFloat64Array=_derivative(state,t)
		var result: Variant=Adapter.step(state,t,h,_derivative,first)
		if not result is Dictionary: return {ok=false,stage_failure=active._stage_failure}
		state=result.state
		events.append_array(result.events)
	return {ok=not stage_bad,state=Array(state),min_normal=min_normal,max_normal=max_normal,max_traction_fraction=max_traction_fraction,stage_calls=stage_calls,events=events,max_rotor_speed=max_rotor_speed,roll=M.q_to_euler(state.slice(6,10))[2]}

func _setup(path: String,speed: float) -> bool:
	active=Session.new()
	active.physics_enabled=false
	active.input_enabled=false
	root.add_child(active)
	var field: Dictionary=Field.load_from(Field.DEFAULT_PATH)
	var weather: Dictionary=Weather.defaults()
	weather.speed_mps=speed
	weather.from_deg=45.0
	return active.setup(path) and active.set_field(field.field) and active.setup_weather(weather) and active.set_start_choice("ground") and active.reset()

func _full() -> PackedFloat64Array:
	var state: PackedFloat64Array=active.sim.state.duplicate()
	state.append_array(active.sim.continuous)
	return state

func _record(kind: String,path: String,initial: PackedFloat64Array) -> Dictionary:
	var cfg: Dictionary=active.aircraft.skids
	var mass: float=active.aircraft.context.mass_kg
	return {kind=kind,path=path,aircraft_sha256=active.aircraft.input_identity.sha256,
		backend=active.stage_backend_identity(),dt_s=active.sim.dt(),weather=active.weather_configuration(),
		initial=Array(initial),commands=Array(active.sim.inputs),refinements=[],
		geometry={points=Array(cfg.points_body_frd_m),reach_m=cfg.reach_m,actual_envelope_m=active._ground_start.actual_envelope_radius_m,authored_envelope_m=active._ground_start.authored_envelope_radius_m},
		constants={mass=mass,inertia=Array(active.aircraft.context.inertia_kg_m2),gravity=active.aircraft.context.gravity_m_s2,k=cfg.spring_n_m,c=cfg.damping_n_s_m,friction=cfg.friction},
		admission_ratios=[sqrt(4.0*cfg.spring_n_m/mass)/240.0,4.0*cfg.damping_n_s_m/(mass*240.0)]}

func _actual_tick(record: Dictionary) -> void:
	var tick: int=active.sim.tick
	active.sim.step()
	var accepted: bool=active.sim.tick==tick+1 and active.is_flyable() and active.sim.fault_reason.is_empty() and active.crash.is_empty()
	check(record.kind+" actual tick accepted",accepted)
	check(record.kind+" stopped held rotor preserved",active.sim.continuous[0]==0.0 and active.zero_drive_hold and not active.power.armed)
	record["accepted_tick"]=active.sim.tick
	record["actual_body"]=Array(active.sim.state)
	record["actual_continuous"]=Array(active.sim.continuous)
	record["fault"]=active.sim.fault_reason
	record["crash"]=active.crash
	var unsplit: Array=record.refinements[0].result.state
	var full: PackedFloat64Array=_full()
	var max_difference: float=0.0
	for i: int in full.size():
		# The actual owner reconciles stopped-rotor heading memory at the endpoint.
		# It has no rotor-force effect in this held Omega=0 contact experiment.
		if i in [17,18]: continue
		max_difference=maxf(max_difference,absf(full[i]-float(unsplit[i])))
	record["unsplit_vs_actual_max_difference_excluding_heading_memory"]=max_difference
	check(record.kind+" unsplit body/contact equals actual policy",max_difference<1e-13)

func _refinements(record: Dictionary,initial: PackedFloat64Array) -> void:
	for n: int in [1,8,16,32,64]:
		var result: Dictionary=_refine(initial,n)
		check(record.kind+" refinement "+str(n)+" finite",result.get("ok",false))
		check(record.kind+" refinement "+str(n)+" stays in loaded unsaturated branch",result.ok and result.min_normal>0.0 and result.max_traction_fraction<1.0 and result.max_rotor_speed==0.0 and result.events.is_empty())
		record.refinements.append({pieces=n,result=result})

func _run() -> void:
	for path: String in ["res://data/aircraft/xcell_60_research.json","res://r8_skid_0.5.json"]:
		var loaded: Dictionary=Data.load_file(path)
		check("strict loader "+path,loaded.ok)
		var ready: bool=loaded.ok and _setup(path,3.0)
		check("normal pad setup "+path,ready)
		if not ready:
			print("SETUP REFUSED ",active.start_error)
			quit(1)
			return
		var initial: PackedFloat64Array=_full()
		var record: Dictionary=_record("wind_first_tick",path,initial)
		check("unchanged mass-only guard passes",record.admission_ratios[0]<0.5 and record.admission_ratios[1]<1.0)
		_refinements(record,initial)
		_actual_tick(record)
		print("R8_SKID ",JSON.stringify(record))
		var trace: Array=[]
		var all_accepted: bool=true
		for i: int in 47:
			var before: int=active.sim.tick
			active.sim.step()
			if active.sim.tick!=before+1 or not active.is_flyable() or not active.sim.fault_reason.is_empty() or not active.crash.is_empty():
				all_accepted=false
				break
			var contact: Dictionary=Skids.evaluate(active.sim.state,active.aircraft.skids,active.ground_surfaces,true,active.sim.continuous.slice(6),active.environment.lake)
			trace.append({tick=active.sim.tick,body=Array(active.sim.state),normal=Array(contact.normal_forces_n),max_depth=contact.max_depth_m,rotor_speed=active.sim.continuous[0]})
		check("48 held wind ticks accepted "+path,all_accepted and active.sim.tick==48 and active.zero_drive_hold and not active.power.armed)
		print("R8_SKID_TRACE ",JSON.stringify({path=path,weather=active.weather_configuration(),accepted=all_accepted,rows=trace,fault=active.sim.fault_reason,crash=active.crash}))
		active.free()
	for config: Dictionary in [{path="res://r8_skid_0.5.json",lambda=-1055.7470419248,b=-0.119792158362,v=10.5491916329,eps=1e-8},{path="res://r8_skid_1.0.json",lambda=-4220.96938650,b=-0.112233668388,v=10.2724397625,eps=1e-10}]:
		check("calm mode pad setup",_setup(config.path,0.0))
		var body: PackedFloat64Array=active.sim.state.duplicate()
		# Separate constructed local-mode witness: yaw is zero, so the common
		# body-lateral mode aligns with world east. Normal pad traces above keep
		# their authored 90-degree heading and receive no state perturbation.
		var q: PackedFloat64Array=M.q_from_euler(0.0,0.0,config.eps)
		for i: int in 4: body[6+i]=q[i]
		body[4]=config.v*config.eps
		body[10]=config.lambda*config.eps
		var continuous: PackedFloat64Array=active.sim.continuous.duplicate()
		continuous[4]=0.0
		for i: int in 4: continuous[6+2*i+1]=config.b*config.eps
		active.sim.continuous=continuous
		var reset_accepted: bool=active.sim.reset(body)
		check("constructed local mode reset accepted",reset_accepted)
		var initial: PackedFloat64Array=_full()
		var record: Dictionary=_record("calm_constructed_mode",config.path,initial)
		record["config"]=config
		record["reset_accepted"]=reset_accepted
		_refinements(record,initial)
		_actual_tick(record)
		var actual_roll: float=M.q_to_euler(active.sim.state.slice(6,10))[2]
		check("production local mode grows",absf(actual_roll)>7.0*config.eps)
		check("fine local equation decays",absf(record.refinements[-1].result.roll)<0.02*config.eps)
		print("R8_SKID ",JSON.stringify(record))
		active.free()
	check("custom calm pad setup",_setup("res://r8_skid_1.0.json",0.0))
	var calm_initial: PackedFloat64Array=_full()
	var calm_accepted: bool=true
	for i: int in 48:
		var before: int=active.sim.tick
		active.sim.step()
		if active.sim.tick!=before+1 or not active.is_flyable(): calm_accepted=false; break
	check("unforced exact rest remains at rest",calm_accepted and active.sim.tick==48 and absf(active.sim.state[10])<1e-12 and absf(M.q_to_euler(active.sim.state.slice(6,10))[2])<1e-12)
	print("R8_SKID_CALM ",JSON.stringify({initial=Array(calm_initial),final=Array(_full()),accepted=calm_accepted,tick=active.sim.tick,fault=active.sim.fault_reason,crash=active.crash}))
	active.free()
	print("R8 skid admission: %d checks, %d failed"%[checks,failures])
	quit(1 if failures else 0)
