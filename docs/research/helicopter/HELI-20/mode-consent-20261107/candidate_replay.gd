extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Activity=preload("res://helicopter_main.gd")
const Field=preload("res://data/field_loader.gd")
const OUT="C:/DEVELOPMENT/OpenRCsimulator/tmp/audit4-20261107-heli-mode"
func _initialize() -> void:
 Engine.physics_ticks_per_second=240
 _run.call_deferred()
func _run() -> void:
 var f: FileAccess=FileAccess.open(OUT.path_join("baseline.tape"),FileAccess.READ)
 var tape: Dictionary=f.get_var()
 f.close()
 var s=Session.new(); s.physics_enabled=false; s.input_enabled=false; root.add_child(s)
 var a=Activity.new(); a.session=s
 var ok: bool=s.setup() and s.set_field(Field.load_from().field) and s.set_start_choice("ground") and s.reset()
 ok=s.restore_checkpoint(tape.initial).get("ok",false) and ok
 s.resume()
 var first: Dictionary={}
 var second: Dictionary={}
 var equal:=true
 var completed:=0
 for i: int in tape.inputs.size():
  var input: PackedFloat64Array=tape.inputs[i]
  s.commands={roll=input[0],pitch=input[1],yaw=input[2],throttle=input[3]}
  s.sim.inputs=input.duplicate()
  s.sim.step()
  var digest: String=var_to_bytes([s.sim.state,s.sim.continuous,s.sim.aux,s.sim.inputs,s.shaft_phase,s.flight_mode]).hex_encode().sha256_text()
  equal=equal and digest==tape.hashes[i]
  if not s.is_flyable(): break
  completed+=1
  if completed==tape.first_tick:
   a.controller_action("helicopter_mode")
   first={tick=s.sim.tick,mode=s.flight_mode,pending=s.pending_mode,message=s.pause_reason}
  if completed==tape.second_tick:
   a.controller_action("helicopter_mode")
   second={tick=s.sim.tick,mode=s.flight_mode,pending=s.pending_mode,message=s.pause_reason}
 var refreshed: bool=first.mode=="normal" and first.pending=="idle_up" and second.mode=="normal" and second.pending=="idle_up" and first.message!=second.message
 a.controller_action("helicopter_mode")
 var confirmed: bool=s.flight_mode=="idle_up" and s.pending_mode.is_empty()
 ok=ok and equal and completed==tape.inputs.size() and refreshed and confirmed
 var report: Dictionary={format="helicopter-mode candidate baseline-input replay v1",ok=ok,input_sha256=FileAccess.get_sha256(OUT.path_join("baseline.tape")),candidate_session_sha256=FileAccess.get_sha256("res://sim/helicopter_flight_session.gd"),engine=Engine.get_version_info().string,ticks=completed,accepted_physics_bytes_identical_before_switch=equal,first=first,second=second,third_confirmed=confirmed}
 var out: FileAccess=FileAccess.open(OUT.path_join("candidate.json"),FileAccess.WRITE)
 out.store_string(JSON.stringify(report,"\t",true,true)); out.close()
 print("H04 CANDIDATE completed=",completed," unchanged physics=",equal," stale refresh=",refreshed," third confirmed=",confirmed)
 a.free(); s.free(); quit(0 if ok else 1)
