extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const AD := preload("res://physics/aircraft_data.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const P51_PATH := "res://data/aircraft/p51d_mustang_120.json"
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Weather := preload("res://physics/wind_config.gd")
var checks := 0
var failed := 0
func check(label:String, passed:bool)->void:
	checks+=1
	if not passed: failed+=1; printerr("FAIL ",label)
func _initialize()->void: call_deferred("_run")
func flight(mode: String = "auto") -> Node:
	var raw_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(P51_PATH))
	if not raw_value is Dictionary:
		return null
	var raw: Dictionary = raw_value
	raw.propulsion.erase("fuel_consumption")
	raw.capabilities.energy = "prescribed_fuel"
	var checked: Dictionary = AD.validate_and_derive(raw)
	if not checked.get("ok", false):
		return null
	var profiled: Dictionary = WheelProfiles.apply_to_model(checked.model)
	if not profiled.get("ok", false):
		return null
	checked.model = profiled.model
	checked.wheel_profile_identity = profiled.identity
	var flight: Node = Flight.new()
	# setup() creates the simulation before _apply() refits the in-memory legacy contract.
	flight.setup(P51_PATH)
	if not flight._apply(checked):
		flight.free()
		return null
	if mode != "auto" and not flight.setup_shaft_integrator(mode):
		flight.free()
		return null
	flight.input_enabled = false
	flight.reset()
	return flight


var output:=""
func tracked(f:Node,name:String)->Dictionary:
	var writer:=Log.new(f)
	var path:=output.path_join(name+".orfl")
	check("old recording opens",writer.start(path)==OK)
	var counts:=[0,0,0,0]
	f.resetting.connect(func():counts[0]+=1)
	f.sim.paused_changed.connect(func(_p):counts[1]+=1)
	f.sim.stepped.connect(func(_k,_t,_s,_l,_i,_a):counts[2]+=1)
	f.statistics_lifecycle.connect(func(_r):counts[3]+=1)
	return {writer=writer,path=path,counts=counts,checkpoint=f.checkpoint(),model=f.sim.model,
		generation=f.statistics_generation,mode=f.shaft_integrator(),mass=f.sim.mass}
func _run()->void:
	Engine.physics_ticks_per_second=240
	output=ProjectSettings.globalize_path("res://../tmp/shaft-publication-%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output)
	_parity()
	_refusals()
	_pending()
	_reselection()
	_faults()
	_preparation()
	print("Shaft publication: %d checks, %d failed; %s"%[checks,failed,output]);quit(1 if failed else 0)
func _parity()->void:
	var expected:Dictionary={"coupled-rk4": "5245d739cbb0288f4ea8b1f19007bd9d1da2a58bf2f65950a9af5661fc0e28af", "split": "2bf9090ccabc380fb7c2c1e07a7d68095b82ac5794f01037ed92a83737a99904"}
	for initial:String in ["split","coupled-rk4"]:
		var f:=flight(initial)
		check("legacy fixture starts",f!=null)
		if f==null:continue
		var target:="split" if initial=="coupled-rk4" else "coupled-rk4"
		check("opposite mode accepts",f.setup_shaft_integrator(target))
		f.reset()
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
		for tick:int in 25:
			check("complete checkpoint",not f.checkpoint().is_empty())
			hash.update(var_to_bytes(f.checkpoint()))
			if tick<24:f.sim.step()
		check("frozen full 25-endpoint shaft trace "+target,hash.finish().hex_encode()==expected[target])
		f.free()
func _refusals()->void:
	for live:bool in [false,true]:
		var f:=flight("split")
		if live:f.sim.step()
		var b:=tracked(f,"refusal-"+str(live))
		var old:=var_to_bytes([f.checkpoint(),f.sim.paused,f._shaft_explicit])
		for bad:Variant in [null,[],{},true,1,"bad"]:
			check("malformed mode refuses",not f.setup_shaft_integrator(bad))
		if live:check("live change refuses",not f.setup_shaft_integrator("coupled-rk4"))
		else:check("same selection is silent",f.setup_shaft_integrator("split"))
		check("refusal preserves owner and recording",b.writer.recording and b.counts==[0,0,0,0]
			and b.generation==f.statistics_generation and old==var_to_bytes([f.checkpoint(),f.sim.paused,f._shaft_explicit]))
		b.writer.stop("test cleanup");f.free()
	var finite:=Flight.new();finite.input_enabled=false;finite.setup(P51_PATH)
	var b:=tracked(finite,"finite-refusal")
	check("finite source still rejects split",not finite.setup_shaft_integrator("split") and b.writer.recording
		and b.counts==[0,0,0,0] and var_to_bytes(b.checkpoint)==var_to_bytes(finite.checkpoint()))
	b.writer.stop("test cleanup");finite.free()
func _pending()->void:
	for initial:String in ["split","coupled-rk4"]:
		var f:=flight(initial)
		var b:=tracked(f,"pending-"+initial)
		var target:="split" if initial=="coupled-rk4" else "coupled-rk4"
		var closing:={};var seen:=[false]
		f.resetting.connect(func():
			closing.assign(f.reset_closing_context())
			seen[0]=f.shaft_integrator()==target and f._shaft_pending_reset and not f.is_flyable()
			f.hold("presentation"))
		check("pending mode accepts",f.setup_shaft_integrator(target))
		check("observer sees accepted pending owner",seen[0] and f.shaft_integrator()==target)
		check("pending publishes no tick or credit",b.counts==[1,1,0,0] and b.generation==f.statistics_generation and f.sim.tick==0 and f.sim.paused)
		check("pending retains old physical arrays",f.sim.state==b.checkpoint.simulation.state and f.sim.continuous==b.checkpoint.simulation.continuous and f.sim.model==b.model)
		check("pending callbacks match selected mode",f.sim.model.stage.get_method()==("_coupled_evaluate" if target=="coupled-rk4" else "_wheel_evaluate"))
		var record:Dictionary=Reader.inspect(b.path)
		check("recording closes with old exact footer",record.ok and not b.writer.recording
			and var_to_bytes(record.footer.checkpoint)==var_to_bytes(b.checkpoint) and var_to_bytes(closing.checkpoint)==var_to_bytes(b.checkpoint))
		check("pending cannot serialize ready state",f.checkpoint().is_empty() and not f.is_flyable() and not f._reset_transaction_active and f.reset_closing_context().is_empty())
		f.sim.step()
		check("manual step cannot advance pending layout",f.sim.tick==0 and not f.sim.fault_reason.is_empty() and b.counts[2]==0)
		f.reset()
		check("explicit reset restores readiness and credits once",f.is_flyable() and not f._shaft_pending_reset and f.statistics_generation==b.generation+1)
		f.sim.step()
		check("reset selected layout advances",f.sim.tick==1 and f.sim.fault_reason.is_empty())
		f.free()
	var pre:=Flight.new();var counts:=[0]
	pre.resetting.connect(func():counts[0]+=1)
	check("pre-setup mode has no installed-flight notification",pre.setup_shaft_integrator("coupled-rk4") and counts[0]==0 and not pre._shaft_pending_reset)
	pre.free()
func _reselection()->void:
	var f:=flight("split")
	var b:=tracked(f,"reselection")
	var closings:Array=[]
	f.resetting.connect(func():closings.append(f.reset_closing_context()))
	check("first pending choice accepts",f.setup_shaft_integrator("coupled-rk4"))
	var footer:=FileAccess.get_file_as_bytes(b.path)
	check("same pending choice emits nothing",f.setup_shaft_integrator("coupled-rk4") and b.counts[0]==1)
	check("second pending choice accepts",f.setup_shaft_integrator("split"))
	check("second closing context explicitly unavailable",closings.size()==2 and closings[0].checkpoint_available
		and not closings[1].checkpoint_available and closings[1].checkpoint.is_empty())
	check("old footer stays intact",footer==FileAccess.get_file_as_bytes(b.path) and not b.writer.recording)
	check("both pending choices require one physical reset",f._shaft_pending_reset and not f.is_flyable()
		and f.statistics_generation==b.generation and b.counts[2]==0 and b.counts[3]==0)
	f.reset()
	check("final reset alone credits and advances",f.is_flyable() and f.statistics_generation==b.generation+1 and b.counts[3]==1)
	f.free()
func _faults()->void:
	for kind:String in ["mass","model","state","step","reset","restore","weather","shaft","pause-step","pause-resume","fault-mutation"]:
		var f:=flight("split")
		var b:=tracked(f,"observer-"+kind)
		if kind=="pause-step":f.sim.paused_changed.connect(func(_p):f.sim.step())
		elif kind=="pause-resume":f.sim.paused_changed.connect(func(p):
			if p:f.sim.set_paused(false))
		else:f.resetting.connect(func():
			if kind in ["mass","fault-mutation"]:f.sim.mass=0.0
			elif kind=="model":f.sim.model.input_size=999
			elif kind=="state":f.sim.state[2]=999.0
			elif kind=="step":f.sim.step()
			elif kind=="reset":f.reset()
			elif kind=="restore":f.restore_checkpoint(b.checkpoint)
			elif kind=="weather":f.setup_weather(Weather.defaults())
			elif kind=="shaft":f.setup_shaft_integrator("split"))
		if kind=="fault-mutation":f.sim.faulted.connect(func(_r):f.sim.state[2]=888.0;f.sim.mass=0.0)
		check("observer cannot veto accepted mode "+kind,f.setup_shaft_integrator("coupled-rk4"))
		check("observer cannot corrupt accepted pending frame "+kind,f.shaft_integrator()=="coupled-rk4" and f._shaft_pending_reset
			and f.sim.mass==b.mass and f.sim.state==b.checkpoint.simulation.state and f.sim.model==b.model and f.sim.model.input_size==b.checkpoint.simulation.inputs.size()
			and f.sim.model.stage.get_method()=="_coupled_evaluate")
		check("fault pauses without tick or credit "+kind,f.sim.paused and not f.sim.fault_reason.is_empty() and not f.shaft_error.is_empty()
			and not b.writer.recording and b.counts[0]==1 and b.counts[2]==0 and b.counts[3]==0 and f.statistics_generation==b.generation)
		f.free()
func _preparation()->void:
	var f:=flight("split")
	f.sim.model.aux_size=f.sim.aux.size();f.sim.model.continuous_size=f.sim.continuous.size();f.sim.model.modes_size=f.sim.modes.size()
	f.sim.model.state_layout_identity="shaft-publication-preparation-v1"
	check("validator fixture starts",f.sim.reset(f.sim.state.duplicate()))
	var b:=tracked(f,"preparation")
	var validator:=func(_frame:Dictionary,_context:Dictionary)->bool:
		f.setup_shaft_integrator("coupled-rk4")
		return true
	f.sim.model.state_validator=validator
	check("validator reentry refuses before selection",not f.setup_shaft_integrator("coupled-rk4"))
	check("preparation restores owner and writer",f.shaft_integrator()=="split" and not f._shaft_pending_reset and b.writer.recording and b.counts==[0,0,0,0]
		and f.sim.model.state_validator==validator and f.sim.model.stage.get_method()=="_wheel_evaluate")
	f.sim.model.state_validator=Callable();b.writer.stop("test cleanup");f.free()
