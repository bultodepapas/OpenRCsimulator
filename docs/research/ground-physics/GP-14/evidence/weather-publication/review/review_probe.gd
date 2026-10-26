extends "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp-weather-publication/test_weather_publication.gd"

func _initialize()->void:call_deferred("_run_review")

func _run_review()->void:
	Engine.physics_ticks_per_second=240
	output=ProjectSettings.globalize_path("res://../tmp/gp-weather-independent-review/recordings-%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output)
	var f:=flight()
	var b:=tracked(f,"two-pending-selections")
	var contexts:Array=[]
	f.resetting.connect(func():contexts.append(f.reset_closing_context()))
	check("first pending weather selection accepts",f.setup_weather(Weather.preset("gusty")))
	var bytes_after_first:=var_to_bytes(f.sim.checkpoint())
	check("second pending selection at same physical clock accepts",f.setup_weather(Weather.preset("turbulent")))
	check("repeated pending selection preserves physical frame/model/generation",bytes_after_first==var_to_bytes(f.sim.checkpoint())
		and f.sim.model==b.model and f.statistics_generation==b.generation and f.sim.tick==0 and f.sim.paused)
	check("old context exact then unavailable pending context explicit",contexts.size()==2 and contexts[0].checkpoint_available
		and var_to_bytes(contexts[0].checkpoint)==var_to_bytes(b.checkpoint) and not contexts[1].checkpoint_available and contexts[1].checkpoint.is_empty())
	check("latest pending configuration cannot masquerade as ready",f.weather_configuration()==Weather.preset("turbulent")
		and f.checkpoint().is_empty() and not f.is_flyable())
	var record:Dictionary=Reader.inspect(b.path)
	check("second selection does not replace already closed old recorder footer",record.ok and var_to_bytes(record.footer.checkpoint)==var_to_bytes(b.checkpoint))
	f.reset()
	check("one explicit reset credits one actual flight from latest selection",f.is_flyable() and f.statistics_generation==b.generation+1
		and f.weather_configuration()==Weather.preset("turbulent"))
	f.free()
	f=flight()
	b=tracked(f,"detached-closing-context")
	var observed:={}
	f.resetting.connect(func():
		var detached:Dictionary=f.reset_closing_context()
		detached.checkpoint.simulation.mass=0.0
		detached.checkpoint.simulation.state[2]=999.0
		var cfg:Dictionary=f.weather_configuration()
		cfg["independent_probe_mutation"]=true)
	f.resetting.connect(func():observed.assign(f.reset_closing_context()))
	check("ordinary read-only consumers can mutate detached copies safely",f.setup_weather(Weather.preset("cool-dense")))
	check("second observer and recorder retain exact old context",var_to_bytes(observed.checkpoint)==var_to_bytes(b.checkpoint)
		and var_to_bytes(Reader.inspect(b.path).footer.checkpoint)==var_to_bytes(b.checkpoint))
	check("configuration accessor copy does not mutate accepted weather",not f.weather_configuration().has("independent_probe_mutation")
		and f.weather_configuration()==Weather.preset("cool-dense"))
	f.free()
	f=flight()
	b=tracked(f,"pause-observer-weather-reentry")
	var attempt:=[true]
	f.sim.paused_changed.connect(func(p:bool):
		if p:attempt[0]=f.setup_weather(Weather.defaults()))
	check("accepted config survives pause-observer Session weather reentry",f.setup_weather(Weather.preset("gusty")))
	check("pause-side reentry is refused without replacing pending weather",not attempt[0] and f.weather_configuration()==Weather.preset("gusty")
		and f._weather_pending_reset and f.sim.paused and not f.sim.fault_reason.is_empty())
	check("pause-side reentry publishes no tick or credited flight",f.sim.tick==0 and f.statistics_generation==b.generation
		and b.counts[2]==0 and b.counts[3]==0 and not b.writer.recording)
	f.free()
	print("Independent weather publication review: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
