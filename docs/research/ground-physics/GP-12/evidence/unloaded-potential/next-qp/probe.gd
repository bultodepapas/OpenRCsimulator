extends "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-unloaded-policy/self_contained_test.gd"
const CaptureStep:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-drop-diagnosis/step.gd")
func _initialize()->void:
	_fixture();_prepare_composition();_prepare_quality()
	var cases:Array=[]
	for speed:float in [.25,1.2]:
		var f:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-unloaded-policy/drop-"+str(speed)+".bin",FileAccess.READ)
		var raw:Dictionary=bytes_to_var(f.get_buffer(f.get_length()));f.close()
		lift_start=raw.lift_start;lift_duration=raw.lift_duration;lift_ratio=raw.lift_ratio;brake_start=raw.brake_start
		_bind()
		var paths:Array=[]
		for count in [1,2,4,8,16]:
			var result:=CaptureStep._attempt(raw.state,raw.time_s,raw.dt,_derivative,PackedFloat64Array(),_sample_policy,_certificate,_sample_policy(raw.state,raw.time_s),count,CaptureStep._settings(raw.options),_policy,{})
			paths.append({count=count,result=result})
			print("COUNT_OUTCOME speed=",speed," count=",count," ok=",result.ok," status=",result.get("status","")," reason=",result.get("reason",""))
		var gate:Dictionary={}
		if paths[3].result.ok and paths[4].result.ok:
			gate=Quality.diagnose(quality,paths[3].result.state,paths[4].result.state,paths[3].result.integration_receipt,paths[4].result.integration_receipt,raw.dt)
		cases.append({speed=speed,tick=raw.accepted_ticks,paths=paths,raw8_16=gate})
	var f:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-drop-diagnosis/count-results.bin",FileAccess.WRITE)
	f.store_buffer(var_to_bytes(cases));f.close()
	f=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-drop-diagnosis/count-results.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(cases,"\t",true,true));f.close()
	print("Drop count diagnosis: complete")
	quit(0)
