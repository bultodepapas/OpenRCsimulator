# HELI-33: accepted-state regression tape; helicopter recorder uses CSV, not ORFL.
extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Field=preload("res://data/field_loader.gd")
const CollisionSetup=preload("res://scenery/collision_setup.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var out: String="user://heli-crash-healthy.json"
 for arg: String in OS.get_cmdline_user_args():
  if arg.begins_with("--out="): out=arg.trim_prefix("--out=")
 var result: Dictionary={format="HELI-33 healthy accepted-state tape v1",cases={}}
 var ok: bool=true
 for mode: String in ["ground","hover","controls"]:
  var session=Session.new()
  session.physics_enabled=false; session.input_enabled=false
  root.add_child(session)
  var field: Dictionary=Field.load_from(Field.DEFAULT_PATH).field
  var world: Dictionary=CollisionSetup.build(field)
  ok=session.setup() and session.set_field(field) and world.ok and session.set_collision_world(world.world) and session.set_start_choice("ground" if mode=="ground" else "airborne") and session.reset() and ok
  var hashes: Array=[]
  for tick: int in 720:
   if mode=="controls":
    session.sim.inputs[0]=.04*sin(tick*.017)
    session.sim.inputs[1]=.03*cos(tick*.011)
    session.sim.inputs[2]=.02*sin(tick*.013)
   session.sim.step()
   hashes.append(var_to_bytes([session.sim.state,session.sim.continuous,session.sim.aux,session.sim.inputs,session.shaft_phase]).hex_encode().sha256_text())
   if not session.is_flyable(): ok=false; break
  result.cases[mode]={ticks=session.sim.tick,hashes=hashes,final_body=Array(session.sim.state),crash=session.crash}
  session.free()
 result.ok=ok
 var file=FileAccess.open(out,FileAccess.WRITE)
 if file==null: quit(1); return
 file.store_string(JSON.stringify(result,"\t",true,true)); file.close()
 print("HELI-33 healthy tape: ",ok," ",out)
 quit(0 if ok else 1)
