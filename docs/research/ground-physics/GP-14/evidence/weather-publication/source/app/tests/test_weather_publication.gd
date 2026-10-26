## Accepted pending weather selection closes old observers under the common guard.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Weather := preload("res://physics/wind_config.gd")
const Field := preload("res://data/field_loader.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
var checks := 0
var failed := 0
var output := ""
func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed: failed += 1; printerr("FAIL ",label)
func _initialize() -> void: call_deferred("_run")
func flight() -> Node:
	var f := Flight.new()
	f.input_enabled = false
	f.crash_auto_restart = false
	f.setup()
	check("authored field installs", f.set_field(Field.load_from().field))
	return f
func tracked(f: Node, name: String) -> Dictionary:
	var writer := Log.new(f)
	var path := output.path_join(name+".orfl")
	check("old recording opens", writer.start(path) == OK)
	var counts := [0,0,0,0]
	f.resetting.connect(func(): counts[0] += 1)
	f.sim.paused_changed.connect(func(_p): counts[1] += 1)
	f.sim.stepped.connect(func(_k,_t,_s,_l,_i,_a): counts[2] += 1)
	f.statistics_lifecycle.connect(func(_r): counts[3] += 1)
	return {writer=writer,path=path,counts=counts,checkpoint=f.checkpoint(),model=f.sim.model,
		generation=f.statistics_generation,weather=f.weather_configuration(),mass=f.sim.mass}
func _run() -> void:
	Engine.physics_ticks_per_second = 240
	output = ProjectSettings.globalize_path("res://../tmp/weather-publication-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output)
	_parity()
	_refusals()
	_pending()
	_pending_manual_step()
	_faults()
	_preparation()
	print("Weather publication: %d checks, %d failed; %s" % [checks,failed,output])
	quit(1 if failed else 0)
func _parity() -> void:
	# Complete 25-endpoint traces captured before GP-14h; see its evidence cohort.
	var expected: Dictionary = {"calm": "e28993adf8aeae616a072f7698fc86d40adaa19961b821cb8254417662df0bab", "cool-dense": "96471c89616b64a915298690f87a938d1891fc55e743419261742457732ef442", "gusty": "3c04da05216e7f9541e005cfb39223a33a30262da8966b6a1c70b25cea8ee4d3", "turbulent": "718475cbac36aab485517d82e6fb948f95a70f5bf961d527acb814cc6991f6eb"}
	for name: String in ["calm","gusty","turbulent","cool-dense"]:
		var f := flight()
		check("valid weather selected",f.setup_weather(Weather.defaults() if name=="calm" else Weather.preset(name)))
		f.reset()
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		for i: int in 25:
			check("complete accepted weather checkpoint",not f.checkpoint().is_empty())
			hash.update(var_to_bytes(f.checkpoint()))
			if i < 24: f.sim.step()
		check("frozen complete 25-endpoint weather trace "+name,hash.finish().hex_encode()==expected[name])
		f.free()
func _refusals() -> void:
	for live: bool in [false,true]:
		var f := flight()
		if live: f.sim.step()
		var b := tracked(f,"refusal-"+str(live))
		var old := var_to_bytes([f.checkpoint(),f.weather_configuration(),f.sim.paused])
		check("bad weather refuses quietly",not f.setup_weather([]) and old==var_to_bytes([f.checkpoint(),f.weather_configuration(),f.sim.paused]))
		if live: check("live valid selection refuses",not f.setup_weather(Weather.preset("gusty")))
		check("refusal preserves recording/model/generation",b.writer.recording and b.counts==[0,0,0,0]
			and b.model==f.sim.model and b.generation==f.statistics_generation)
		b.writer.stop("test cleanup"); f.free()
func _pending() -> void:
	var f := flight()
	var b := tracked(f,"accepted-pending")
	var config := Weather.preset("cool-dense")
	var closing := {}
	var observed := [false]
	f.resetting.connect(func():
		closing.assign(f.reset_closing_context())
		observed[0] = f.weather_configuration()==config and f._weather_pending_reset and not f.is_flyable()
		f.hold("presentation"))
	check("pending configuration accepts",f.setup_weather(config))
	check("notification observes accepted pending owner",observed[0] and f.weather_configuration()==config and f._weather_pending_reset)
	check("configuration publishes no tick or generation",b.counts==[1,1,0,0] and b.generation==f.statistics_generation and f.sim.tick==0 and f.sim.paused)
	check("configuration keeps old physical frame and model",var_to_bytes(f.sim.checkpoint())==var_to_bytes(b.checkpoint.simulation) and b.model==f.sim.model)
	var record: Dictionary = Reader.inspect(b.path)
	check("old recorder closes with exact old checkpoint",record.ok and not b.writer.recording
		and var_to_bytes(record.footer.checkpoint)==var_to_bytes(b.checkpoint) and var_to_bytes(closing.checkpoint)==var_to_bytes(b.checkpoint))
	check("pending config cannot serialize a ready flight",f.checkpoint().is_empty() and not f.is_flyable()
		and f.reset_closing_context().is_empty() and not f._reset_transaction_active and f.holds.has("presentation"))
	f.reset()
	check("explicit reset is the physical readiness/credit boundary",f.is_flyable() and f.statistics_generation==b.generation+1 and not f._weather_pending_reset)
	f.free()
	var pre := Flight.new()
	var notifications := [0]
	pre.resetting.connect(func(): notifications[0] += 1)
	check("pre-setup selection has no installed-flight notification",pre.setup_weather(config) and notifications[0]==0 and pre.weather_configuration()==config)
	pre.free()
func _pending_manual_step() -> void:
	var f := flight()
	var old_state: PackedFloat64Array = f.sim.state.duplicate()
	var generation: int = f.statistics_generation
	var count := [0]
	f.sim.stepped.connect(func(_k,_t,_s,_l,_i,_a): count[0] += 1)
	check("manual-step pending weather selection",f.setup_weather(Weather.preset("turbulent")))
	f.sim.step()
	check("manual stepping cannot advance a pending old layout",f.sim.tick==0 and f.sim.state==old_state and count[0]==0
		and not f.sim.fault_reason.is_empty() and f._weather_pending_reset and f.statistics_generation==generation)
	f.reset()
	check("explicit reset recovers selected weather after pending-step refusal",f.is_flyable() and f.sim.fault_reason.is_empty()
		and not f._weather_pending_reset and f.statistics_generation==generation+1 and count[0]==1)
	f.sim.step()
	check("recovered selected-weather flight advances",f.sim.tick==1 and count[0]==2 and not f.checkpoint().is_empty())
	f.free()
func _faults() -> void:
	for kind: String in ["mass","model","state","step","reset","restore","weather","shaft","pause-step","pause-resume","fault-mutation"]:
		var f := flight()
		var b := tracked(f,"observer-"+kind)
		var expected_state: PackedFloat64Array = f.sim.state.duplicate()
		var config := Weather.preset("gusty")
		if kind=="pause-step": f.sim.paused_changed.connect(func(_p): f.sim.step())
		elif kind=="pause-resume": f.sim.paused_changed.connect(func(p):
			if p: f.sim.set_paused(false))
		else: f.resetting.connect(func():
			if kind in ["mass", "fault-mutation"]: f.sim.mass=0.0
			elif kind=="model": f.sim.model.input_size=999
			elif kind=="state": f.sim.state[2]=999.0
			elif kind=="step": f.sim.step()
			elif kind=="reset": f.reset()
			elif kind=="restore": f.restore_checkpoint(b.checkpoint)
			elif kind=="weather": f.setup_weather(Weather.defaults())
			elif kind=="shaft": f.setup_shaft_integrator("split"))
		if kind=="fault-mutation": f.sim.faulted.connect(func(_r): f.sim.state[2]=888.0; f.sim.mass=0.0)
		check("observer fault cannot veto accepted config "+kind,f.setup_weather(config))
		check("fault retains accepted weather and old physical frame "+kind,f.weather_configuration()==config and f._weather_pending_reset
			and f.sim.mass==b.mass and f.sim.state==expected_state and f.sim.tick==0 and f.sim.model==b.model and f.sim.model.input_size==b.checkpoint.simulation.inputs.size())
		check("fault pauses with no tick or credited restart "+kind,f.sim.paused and not f.sim.fault_reason.is_empty()
			and not f.weather_error.is_empty() and not b.writer.recording and b.counts[0]==1 and b.counts[2]==0 and b.counts[3]==0 and f.statistics_generation==b.generation)
		f.free()
func _preparation() -> void:
	var f := flight()
	f.sim.model.aux_size=f.sim.aux.size()
	f.sim.model.continuous_size=f.sim.continuous.size()
	f.sim.model.modes_size=f.sim.modes.size()
	f.sim.model.state_layout_identity="weather-publication-preparation-v1"
	check("endpoint fixture starts",f.sim.reset(f.sim.state.duplicate()))
	var b := tracked(f,"validator-reentry")
	var validator := func(_frame:Dictionary,_context:Dictionary)->bool:
		f.setup_weather(Weather.preset("gusty"))
		return true
	f.sim.model.state_validator=validator
	check("checkpoint preparation reentry refuses selection",not f.setup_weather(Weather.preset("cool-dense")))
	check("preparation refusal restores old owner and recorder",f.weather_configuration()==b.weather and not f._weather_pending_reset
		and b.writer.recording and b.counts==[0,0,0,0] and f.sim.model.state_validator==validator and f.sim.mass==b.mass)
	f.sim.model.state_validator=Callable()
	b.writer.stop("test cleanup"); f.free()
