extends SceneTree
const Reader:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp20-brake-input/reader/flight_log_cli.gd")
var returned:=0
var checks:=0
var failed:=0
func check(label:String,ok:bool)->void:
	checks+=1
	if not ok:failed+=1;printerr("FAIL ",label)
func _initialize()->void:
	for width in [5,6]:
		for value:Variant in [null,false,true,[],{},0,1.0,&"fixed-gear-shared-wheel-brake-input-v1"]:
			call_deferred("_case",value,width)
	call_deferred("_done")
func _case(value:Variant,width:int)->void:
	var names:='["roll","pitch","yaw","throttle","wheel_brake"]' if width==5 else '["roll","pitch","yaw","throttle","wheel_brake","flaps"]'
	var layout:={inputs=width,aux=4,continuous=0,modes=1}
	var metadata:={fixed_brake_input_law=value,wheel_brake_input_index=4,input_layout=names}
	var before:=var_to_bytes([layout,metadata])
	var result:=Reader.input_names(layout,metadata)
	returned+=1
	check("unsupported selector type refuses",typeof(result.get("ok"))==TYPE_BOOL and not result.ok)
	check("bad metadata cannot emit mislabeled columns",Reader.columns(layout,metadata).is_empty())
	check("read-only contract inputs",before==var_to_bytes([layout,metadata]))
func _done()->void:
	print("Hostile CLI law probe complete: ",returned," calls returned, ",checks," checks, ",failed," failed")
	quit(1 if failed else 0)
