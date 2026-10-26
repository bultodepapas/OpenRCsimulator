extends SceneTree
const Audio:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-scrape-independent-review/postfix/crash_audio.gd")
class Spy extends Audio:
	var plans:Array=[]
	func _play(_sample:String,point:Vector3,gain:float,pitch:float,_scrape:=false)->void:
		plans.append({point=point,gain=gain,pitch=pitch,old_tag_stopped=_voices[0].stream==null and _scrape_tags[0]==0})
var checks:=0
var failed:=0
func check(label:String,yes:bool)->void:
	checks+=1
	if not yes:failed+=1;printerr("FAIL ",label)
func packet(tick:int,point:float=2.0,paused:bool=false)->Dictionary:
	return {observation={schema="openrc-hull-friction-observation",version=1,tick=tick,generation=1,law_identity="probe",available=true,sampling="accepted_endpoint_instantaneous_power",contacts=[{contact_id="hull",material_id="",point_ned=PackedFloat64Array([point,0.0,0.0]),normal_force_n=7.2,tangent_force_ned_n=PackedFloat64Array([-2.88,0.0,0.0]),relative_tangent_velocity_ned_mps=PackedFloat64Array([10.0,0.0,0.0]),friction_power_w=28.8}],reason=""},tick_rate=240.0,paused=paused,terminal=false}
func tag(a:Spy)->void:
	a._scrape_tags[0]=1;a._voices[0].stream=a._streams.scrape;a._voice_gain[0]=.2
func _initialize()->void:call_deferred("_run")
func _run()->void:
	var bus_count:=AudioServer.bus_count
	var a:=Spy.new();root.add_child(a);a.setup();a.set_accepted_hull_observation(true)
	var rng_state:=a._rng.state
	a.observe_accepted(packet(0))
	check("first consecutive positive sample queues",a.observe_accepted(packet(1)) and a.hull_scrape_diagnostics().queued==1)
	tag(a)
	var tagged_gain:float=a._voice_gain[0]
	check("pause capture clears stale queue",a.observe_accepted(packet(2,2.0,true)) and a.hull_scrape_diagnostics().queued==0)
	check("capture cannot stop or alter native tagged slot",a._voices[0].stream!=null and a._voice_gain[0]==tagged_gain and a._scrape_tags[0]==1)
	check("capture never changes audio RNG or pool/bus count",a._rng.state==rng_state and a.voice_count()==8 and AudioServer.bus_count==bus_count+1)
	a.observe_accepted(packet(3))
	a.update(1.0/60.0,false,0.0)
	check("deferred stop happens before newly accepted grain",a.plans.size()==1 and a.plans[0].old_tag_stopped)
	var original:=packet(4)
	var frozen:=var_to_bytes(original)
	check("capture preserves caller packet",a.observe_accepted(original) and frozen==var_to_bytes(original))
	tag(a)
	var wrong:=packet(5);wrong.observation.contacts[0].friction_power_w=999.0
	check("invalid packet refuses and clears pending cues",not a.observe_accepted(wrong) and a.hull_scrape_diagnostics().queued==0)
	check("invalid capture also defers tagged-player stop",a._voices[0].stream!=null and a._scrape_tags[0]==1)
	var old_plans:=a.plans.size();a.update(1.0/60.0,false,0.0)
	check("render invalidation stops old slot without stale playback",a._voices[0].stream==null and a._scrape_tags[0]==0 and a.plans.size()==old_plans)
	check("finite float64 outside render domain refuses cleanly",not a.observe_accepted(packet(5,1e50)) and a.hull_scrape_diagnostics().queued==0)
	a.reset();a.observe_accepted(packet(0))
	check("large supported position remains available",a.observe_accepted(packet(1,1e30)))
	a.update(1.0/60.0,false,0.0)
	check("supported large position converts to finite render point",a.plans[-1].point.is_finite() and is_finite(a.plans[-1].gain) and is_finite(a.plans[-1].pitch))
	tag(a);a.observe_accepted(packet(2));a.observe_accepted(packet(0));a.observe_accepted(packet(1))
	old_plans=a.plans.size();a.update(1.0/60.0,false,0.0)
	check("rewind cancellation retains only legitimate new branch grain",a.plans.size()==old_plans+1 and a.plans[-1].old_tag_stopped)
	a.free()
	check("review releases all bus/player resources",AudioServer.bus_count==bus_count)
	print("Independent scrape review: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
