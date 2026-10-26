extends SceneTree
const Reader:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp20-brake-input/reader/flight_log_cli.gd")
var returned:=0
func _initialize()->void:
	for value:Variant in [null,false,true,[],{},0,1.0,&"fixed-gear-shared-wheel-brake-input-v1"]:
		call_deferred("_case",value)
	call_deferred("_done")
func _case(value:Variant)->void:
	var result:=Reader.input_names({inputs=5},{fixed_brake_input_law=value,wheel_brake_input_index=4,input_layout='["roll","pitch","yaw","throttle","wheel_brake"]'})
	returned+=1
	print("SELECTOR type=",typeof(value)," returned_ok=",result.ok)
func _done()->void:
	print("Hostile CLI law probe complete: ",returned," calls returned")
	quit()
