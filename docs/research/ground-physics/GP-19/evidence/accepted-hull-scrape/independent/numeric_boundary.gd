extends SceneTree
const Audio:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-scrape-independent-review/crash_audio_snapshot.gd")
class Spy extends Audio:
	var points:Array=[]
	func _play(_sample:String,point:Vector3,_gain:float,_pitch:float,_scrape:=false)->void:
		points.append(point)
func packet(tick:int,power:float=28.8)->Dictionary:
	return {observation={schema="openrc-hull-friction-observation",version=1,tick=tick,generation=1,law_identity="probe",available=true,sampling="accepted_endpoint_instantaneous_power",contacts=[{contact_id="hull",material_id="",point_ned=PackedFloat64Array([1e50,0.0,0.0]),normal_force_n=7.2,tangent_force_ned_n=PackedFloat64Array([-power/10.0,0.0,0.0]),relative_tangent_velocity_ned_mps=PackedFloat64Array([10.0,0.0,0.0]),friction_power_w=power}],reason=""},tick_rate=240.0,paused=false,terminal=false}
func _initialize()->void:call_deferred("_run")
func _run()->void:
	var a:=Spy.new();root.add_child(a);a.setup();a.set_accepted_hull_observation(true)
	a.observe_accepted(packet(0))
	var accepted:=a.observe_accepted(packet(1))
	a.update(1.0/60.0,false,0.0)
	var result:={accepted_finite_float64_point=accepted,planned_grains=a.points.size(),nonfinite_render_point=a.points.size()>0 and not a.points[0].is_finite()}
	a.free()
	print("SCRAPE_NUMERIC_BOUNDARY ",JSON.stringify(result))
	var f:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-scrape-independent-review/numeric-boundary.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t",true,true));f.close()
	print("Scrape numeric boundary probe complete")
	quit()
