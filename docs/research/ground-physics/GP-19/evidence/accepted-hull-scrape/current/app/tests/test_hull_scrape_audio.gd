extends SceneTree
const A = preload("res://render/crash/crash_audio.gd")
class Spy extends A:
	var plans: Array = []
	func _play(sample_name: String, position: Vector3, gain: float, pitch: float, hull_scrape := false) -> void:
		plans.append({sample=sample_name,point=position,gain=gain,tag=hull_scrape})
		super._play(sample_name,position,gain,pitch,hull_scrape)
var checks := 0
var failed := 0
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failed += 1; printerr("FAIL ",label)
func _initialize() -> void: call_deferred("_run")
func packet(tick: int, power := 28.8, paused := false, generation := 3, rate := 240.0) -> Dictionary:
	var contacts: Array = []
	if power >= 0.0:
		contacts.append({contact_id="hull:belly",point_ned=PackedFloat64Array([2.,3.,.002]),normal_force_n=7.2,
			tangent_force_ned_n=PackedFloat64Array([-power/10.,0.,0.]),
			relative_tangent_velocity_ned_mps=PackedFloat64Array([10.,0.,0.]),friction_power_w=power,material_id="maintained_turf"})
	return {observation={schema="openrc-hull-friction-observation",version=1,tick=tick,generation=generation,
		law_identity="fixture-flat-solid",available=true,sampling="accepted_endpoint_instantaneous_power",contacts=contacts,reason=""},
		tick_rate=rate,paused=paused,terminal=false}
func make() -> Spy:
	var audio := Spy.new()
	root.add_child(audio)
	audio.setup()
	audio.set_accepted_hull_observation(true)
	return audio
func _run() -> void:
	var buses := AudioServer.bus_count
	var a := make()
	check("bounded existing8 voices and one bus",a.voice_count()==8 and AudioServer.bus_count==buses+1)
	check("attach primes no grain",a.observe_accepted(packet(0,-1.0)) and a.hull_scrape_diagnostics().queued==0)
	check("short first loaded sample queues immediately",a.observe_accepted(packet(1)) and a.hull_scrape_diagnostics().queued==1)
	check("stopping before render preserves brief grain",a.observe_accepted(packet(2,-1.0)) and a.hull_scrape_diagnostics().queued==1)
	a.update(1./60.,false,0.)
	check("brief brush plays one tagged generic scrape with correct render point",a.plans.size()==1 and a.plans[0].sample=="scrape" and a.plans[0].tag and a.plans[0].point==Vector3(3,-.002,-2))
	a.update(1./144.,false,0.)
	check("render repeat cannot duplicate",a.plans.size()==1)
	a.observe_accepted(packet(2))
	check("duplicate accepted tick cannot queue",a.hull_scrape_diagnostics().queued==0)
	a.observe_accepted(packet(3,0.0))
	check("zero loaded friction makes zero grain",a.hull_scrape_diagnostics().queued==0)
	a.observe_accepted(packet(4))
	var original_tick: int = a.hull_scrape_diagnostics().tick
	var wrong := packet(5)
	wrong.observation.contacts[0].friction_power_w=1.0
	check("invalid power fails quiet without accepting clock",not a.observe_accepted(wrong) and a.hull_scrape_diagnostics().queued==0 and a.hull_scrape_diagnostics().cancellation_pending and a.hull_scrape_diagnostics().tick==original_tick)
	for bad in [null,true,3,1.5,[],{},&"bad"]:
		wrong=packet(5);wrong.observation.schema=bad
		check("malformed primitive schema rejected without engine errors",not a.observe_accepted(wrong))
	wrong=packet(5);wrong.observation.tick=5.5
	check("fractional clock rejected",not a.observe_accepted(wrong))
	wrong=packet(5);wrong.observation.contacts.append(wrong.observation.contacts[0].duplicate(true))
	check("duplicate physical ID rejected",not a.observe_accepted(wrong))
	wrong=packet(5);wrong.observation.contacts[0].normal_force_n=0.0
	check("zero-normal alleged friction rejected",not a.observe_accepted(wrong))
	wrong=packet(5);wrong.observation.contacts[0].point_ned[0]=INF
	check("nonfinite SI rejected",not a.observe_accepted(wrong))
	wrong=packet(5);wrong.observation.contacts[0].point_ned[0]=1e308;wrong.observation.contacts[0].friction_power_w=1e308;wrong.observation.contacts[0].tangent_force_ned_n[0]=-1e307
	check("finite inputs with overflowing aggregation rejected",not a.observe_accepted(wrong))
	a.observe_accepted(packet(5,28.8,true))
	check("pause discards pending before render",a.hull_scrape_diagnostics().queued==0)
	a.observe_accepted(packet(6,28.8,true));a.observe_accepted(packet(6,28.8,false))
	check("paused manual step does not replay on resume",a.hull_scrape_diagnostics().queued==0)
	a.observe_accepted(packet(7));a.observe_accepted(packet(7,28.8,false,3,480.))
	check("same-tick rate replacement primes/discards",a.hull_scrape_diagnostics().queued==0)
	a.observe_accepted(packet(8,28.8,false,3,480.));a.observe_accepted(packet(9,28.8,false,4,480.))
	check("generation replacement clears old queue",a.hull_scrape_diagnostics().queued==0)
	a.observe_accepted(packet(10,28.8,false,4,480.));a.observe_accepted(packet(12,28.8,false,4,480.))
	check("gap primes",a.hull_scrape_diagnostics().queued==0)
	a.observe_accepted(packet(13,28.8,false,4,480.));a.observe_accepted(packet(1))
	check("rewind primes",a.hull_scrape_diagnostics().queued==0)
	a.observe_accepted(packet(2))
	wrong=packet(3);wrong.terminal=true
	a.observe_accepted(wrong)
	check("terminal capture cancels queued live grains",a.hull_scrape_diagnostics().queued==0)
	a.observe_accepted(packet(4))
	a.impact(Vector3.ZERO,{"valid":true,"class":1,"severity":.2},false)
	check("primary handoff cancels live grains before exclusive aftermath layers",a.hull_scrape_diagnostics().queued==0 and a._primary_played)
	a.reset()
	# Emulate an already assigned native slot without playing on Dummy.
	a._scrape_tags[0]=1;a._voices[0].stream=a._streams.scrape;a._voice_gain[0]=.2
	a.cancel_hull_scrape()
	check("cancel stops tagged pool slot without growing or replacing pool",a._voices[0].stream==null and a._voice_gain[0]==0.0 and a.voice_count()==8)
	var totals: Array = []
	for fps in [30,60,144]:
		var b := make()
		b.observe_accepted(packet(0,-1.0))
		var next_render := 1.0/float(fps)
		for tick in range(1,481):
			var power := 28.8 if tick%40<20 else -1.0
			b.observe_accepted(packet(tick,power))
			if tick/240.0 >= next_render:
				b.update(1./float(fps),false,0.);next_render+=1./float(fps)
		b.update(1./float(fps),false,0.)
		totals.append(b.hull_scrape_diagnostics().emitted)
		check("cadence queue has no age/overflow loss",b.hull_scrape_diagnostics().overflow==0 and b.hull_scrape_diagnostics().stale==0)
		b.free()
	check("same accepted tape30/60/144Hz emits identical finite grains",totals[0]>0 and totals[0]==totals[1] and totals[1]==totals[2])
	var b := make()
	b.observe_accepted(packet(0,-1.0))
	for tick in range(1,201): b.observe_accepted(packet(tick,28.8 if tick%2 else -1.0))
	check("queue bound64 drops oldest explicitly",b.hull_scrape_diagnostics().queued==64 and b.hull_scrape_diagnostics().overflow==36)
	b.update(1./60.,false,0.)
	check("old cues respect250ms presentation-latency bound",b.hull_scrape_diagnostics().stale>0 and b.hull_scrape_diagnostics().queued==0)
	b.free()
	a.reset()
	a.observe_accepted(packet(0,-1.0))
	a._scrape_tags[0]=1;a._voices[0].stream=a._streams.scrape;a._voice_gain[0]=.2
	a.observe_accepted(packet(1,28.8,true))
	check("accepted pause only requests stop without touching tagged player",a._scrape_tags[0]==1 and a._voices[0].stream!=null and absf(a._voice_gain[0]-.2)<1e-7 and a.hull_scrape_diagnostics().cancellation_pending)
	a.observe_accepted(packet(2))
	check("resume may queue fresh grain behind pending cancellation",a.hull_scrape_diagnostics().queued==1)
	a.update(1./60.,false,0.)
	check("render stops old tagged slot before fresh grain drains",a._scrape_tags[0]==0 and a._voices[0].stream==null and not a.hull_scrape_diagnostics().cancellation_pending and a.hull_scrape_diagnostics().queued==0)
	a.observe_accepted(packet(3,-1.0));a.observe_accepted(packet(4))
	a._scrape_tags[0]=1;a._voices[0].stream=a._streams.scrape
	wrong=packet(5);wrong.observation.contacts[0].friction_power_w=-1.0
	check("invalid packet requests deferred stop and drops stale queue",not a.observe_accepted(wrong) and a.hull_scrape_diagnostics().queued==0 and a._voices[0].stream!=null)
	a.update(1./60.,false,0.)
	check("invalid packet cannot leave tagged scrape playing after render",a._voices[0].stream==null and a.hull_scrape_diagnostics().queued==0)
	a.reset();a.observe_accepted(packet(0,-1.0))
	a.observe_accepted(packet(1))
	wrong=packet(2);wrong.observation.contacts[0].point_ned[0]=1e50
	check("finite float64 position outside render numeric domain fails quiet",not a.observe_accepted(wrong) and a.hull_scrape_diagnostics().queued==0)
	wrong=packet(2);wrong.observation.contacts[0].point_ned[0]=1e30
	check("large renderable SI position remains supported without location guess",a.observe_accepted(wrong) and a.hull_scrape_diagnostics().queued==1)
	a.update(1./60.,false,0.)
	check("all supported planned scrape render positions remain finite",a.plans.back().point.is_finite())
	a.set_accepted_hull_observation(false)
	check("legacy mode restored without changing voice/bus allocation",not a.accepted_hull_observation_enabled() and a.voice_count()==8)
	var bus_name := a.output_bus()
	a.free()
	check("free releases isolated bus and all players",AudioServer.get_bus_index(bus_name)==-1 and AudioServer.bus_count==buses)
	print("Hull scrape audio: %d checks, %d failed"%[checks,failed])
	print("Hull scrape audio complete")
	quit(1 if failed else 0)
