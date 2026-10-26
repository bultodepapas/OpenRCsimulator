from pathlib import Path
import json
home=Path(__file__).resolve().parent
source=(home/'flight_session.before.gd').read_text()
old='''	_shaft_explicit = true
	if mode == _shaft_integrator:
		shaft_error = ""
		return true
	resetting.emit()
	_shaft_integrator = mode
	_shaft_pending_reset = sim != null
	if sim != null:
		_configure_continuous_callbacks()
		sim.set_paused(true)
	shaft_error = ""
	return true'''
new='''	if mode == _shaft_integrator:
		_shaft_explicit = true
		shaft_error = ""
		return true
	if sim == null:
		_shaft_explicit = true
		_shaft_integrator = mode
		_shaft_pending_reset = false
		shaft_error = ""
		return true
	var transaction := _begin_start_transaction()
	# Capture the old recorder boundary before selecting the new layout. Reading
	# that checkpoint may invoke a model validator, so preparation is guarded too.
	var intact: bool = sim._endpoint_guard_matches(transaction.kernel)
	for field: String in _START_OWNER_FIELDS:
		intact = intact and Sim._guard_values_equal(get(field), transaction.owner[field])
	if _reset_transaction_reentry or not intact:
		_refuse_start_transaction(transaction, "shaft preparation changed the installed owner")
		shaft_error = "shaft preparation changed the installed owner"
		return false
	_shaft_explicit = true
	_shaft_integrator = mode
	_shaft_pending_reset = true
	var callbacks: Dictionary = PropulsionRuntime.prepare_callbacks(self)
	if not callbacks.ok:
		_refuse_start_transaction(transaction, "shaft callback preparation failed")
		shaft_error = "shaft callback preparation failed: " + str(callbacks.get("errors", []))
		return false
	_install_continuous_callbacks(callbacks)
	shaft_error = ""
	# Pending selection is accepted now. The explicit reset still constructs the
	# physical layout and owns statistics credit; no sample is published here.
	transaction.committed = true
	_reset_physical_committed = true
	sim.reset_observer_fault = ""
	sim._publish_committed_boundary(func() -> void:
		_reset_publication_active = true
		_reset_closing_context = transaction.closing
		resetting.emit()
		_reset_closing_context = {}
		_reset_publication_active = false, false, "shaft configuration", true)
	_end_start_transaction(transaction)
	if not sim.reset_observer_fault.is_empty():
		shaft_error = sim.reset_observer_fault
		pause_reason = "simulation fault: " + shaft_error
	return true'''
assert source.count(old)==1
source=source.replace(old,new)
needle='''	for field: String in PropulsionRuntime.CALLBACK_FIELDS:
		sim.model.set(field, prepared[field])'''
replacement='''	_install_continuous_callbacks(prepared)


## Install only an already prepared callback set; this does not advance state.
func _install_continuous_callbacks(prepared: Dictionary) -> void:
	for field: String in PropulsionRuntime.CALLBACK_FIELDS:
		sim.model.set(field, prepared[field])'''
assert source.count(needle)==1
source=source.replace(needle,replacement)
(home/'flight_session.gd').write_text(source,newline='\n')
header=(home/'fixture.gd').read_text()
test=header+'''var output:=""
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
	var expected:Dictionary=BASELINE_HASHES
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
'''
baseline=json.loads((home/'baseline.json').read_text());baseline.pop('observer_defect')
test=test.replace('BASELINE_HASHES',json.dumps(baseline))
(home/'test_shaft_publication.gd').write_text(test,newline='\n')
(home/'test_draft.gd').write_text(test.replace('res://sim/flight_session.gd','res://../tmp/gp-shaft-publication/flight_session.gd'),newline='\n')
print('Prepared production-target test and draft')
