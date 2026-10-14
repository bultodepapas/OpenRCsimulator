extends SceneTree
const Life=preload("res://physics/rotorcraft/lifecycle.gd")
const Data=preload("res://physics/rotorcraft_data.gd")
var checks:=0
var failures:=0
func check(label: String,ok: bool) -> void:
	checks+=1
	if not ok: failures+=1; print("FAIL ",label)
func _initialize() -> void:
	var aircraft: Dictionary=Data.load_file("res://data/aircraft/xcell_60_research.json",1.225)
	check("accepted aircraft",aircraft.ok)
	var model: Dictionary=aircraft.context.electronics_model
	var pickup: Dictionary=Life.collective_for_pitch(model,"normal",0.0)
	check("normal zero pitch derives signed -2/3",pickup.ok and absf(pickup.stick+2.0/3.0)<1e-14)
	check("rate gamepad startup is one sixth collective",absf(pickup.collective-1.0/6.0)<1e-14)
	check("idle-up zero pitch is center",Life.collective_for_pitch(model,"idle_up",0.0).collective==.5)
	check("absent mode refused",not Life.collective_for_pitch(model,"missing",0.0).ok)
	check("unreachable physical pitch refused",not Life.collective_for_pitch(model,"normal",PI).ok)
	var edited: Dictionary=model.duplicate(true)
	edited.curves_by_mode.normal.pitch=[-1.0,0.0,0.0,.5,1.0]
	check("ambiguous plateau refused",not Life.collective_for_pitch(edited,"normal",0.0).ok)
	edited.curves_by_mode.normal.pitch=[-1.0,.5,-.5,.5,1.0]
	check("multiple roots refused",not Life.collective_for_pitch(edited,"normal",0.0).ok)
	var power: Dictionary=Life.initial(false)
	check("cold ground start is disarmed",not power.armed and Life.valid(power,0.0))
	check("disarmed removes all output regardless of time",Life.scale(power,false,100.0)==0.0)
	power.armed=true
	check("hold overrides arm",Life.scale(power,true,100.0)==0.0)
	check("no impulse at soft-start entry",Life.scale(power,false,0.0)==0.0)
	check("smoothstep midpoint",Life.scale(power,false,Life.SOFT_START_S*.5)==.5)
	check("bounded output after ramp",Life.scale(power,false,100.0)==1.0)
	check("airborne fixture retains full output",Life.scale(Life.initial(true),false,0.0)==1.0)
	check("phase requires speed as well as elapsed ramp",Life.phase(power,false,Life.SOFT_START_S+1.0,0.0,167.0)=="SPOOLING")
	check("governed phase reports target speed",Life.phase(power,false,Life.SOFT_START_S+1.0,167.0,167.0)=="GOVERNED")
	check("future spool epoch refused",not Life.valid({armed=true,spool_start_s=1.0},0.0))
	check("malformed arm refused",not Life.valid({armed=1,spool_start_s=0.0},0.0))
	print("HELI-07b lifecycle: %d checks, %d failed"%[checks,failures])
	quit(1 if failures else 0)
