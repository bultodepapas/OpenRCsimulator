extends SceneTree
const Session := preload("res://sim/airship/session.gd")
const Log := preload("res://sim/airship/flight_log.gd")
var failures:=0
func check(label:String, condition:bool) -> void:
 print(("ok " if condition else "FAIL ")+label)
 if not condition: failures+=1
func _initialize() -> void:
 var s:=Session.new(); root.add_child(s)
 check("prepare terrain-only session",s.prepare({}, {altitude_m=20.0}))
 var sticks:=PackedFloat64Array([0,0,0,0]); check("resume",s.resume(sticks))
 for i in 3: check("warmup tick",s.tick_once(sticks))
 var path:="user://r3_restore_probe.orfl"; if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 var log:=Log.new(s); check("record starts",log.start({},path)==OK)
 for i in 2: check("recorded tick",s.tick_once(sticks))
 var resets:=[0]; var faults:=[0]
 s.resetting.connect(func():resets[0]+=1)
 s.faulted.connect(func(_reason):faults[0]+=1)
 var old_body=s.sim.state.to_byte_array(); var old_cont=s.sim.continuous.to_byte_array(); var old_input=s.sim.inputs.to_byte_array(); var old_tape=s.tape.to_byte_array(); var old_tick=s.sim.tick
 var cont:PackedFloat64Array=s.continuous_snapshot(); var invalid:PackedFloat64Array=s.state_snapshot(); invalid[0]=NAN
 var zeroq:PackedFloat64Array=s.state_snapshot(); for i in 4: zeroq[6+i]=0.0
 var nancont:PackedFloat64Array=cont.duplicate(); nancont[0]=NAN
 check("nan body refused",not s.restore_checkpoint(invalid,cont))
 check("degenerate quaternion refused",not s.restore_checkpoint(zeroq,cont))
 check("nan continuous refused",not s.restore_checkpoint(s.state_snapshot(),nancont))
 check("rejection preserves state, inputs, tape and tick",s.sim.state.to_byte_array()==old_body and s.sim.continuous.to_byte_array()==old_cont and s.sim.inputs.to_byte_array()==old_input and s.tape.to_byte_array()==old_tape and s.sim.tick==old_tick)
 check("rejection preserves recorder, signals and pause",log.recording and resets[0]==0 and faults[0]==0 and not s.paused and not s.sim.paused)
 check("flight and recorder continue",s.tick_once(sticks) and log.recording)
 check("valid restore accepted",s.restore_checkpoint(s.state_snapshot(),s.continuous_snapshot()))
 var result:Dictionary=Log.inspect(path)
 check("accepted restore closes complete recorder once",resets[0]==1 and faults[0]==0 and not log.recording and result.ok and result.complete and result.ticks.size()==3)
 print("RESTORE_PROBE_COMPLETE failures=%d" % failures)
 quit(1 if failures else 0)
