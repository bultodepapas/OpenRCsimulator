# HELI-16: real AppRoot rotorcraft route and keyboard sampling at three render cadences.
extends SceneTree
const TICKS: int=480
const SCHEDULE: Dictionary={119:[[KEY_RIGHT,true],[KEY_W,true]],239:[[KEY_RIGHT,false],[KEY_W,false],[KEY_DOWN,true]],359:[[KEY_DOWN,false],[KEY_A,true]]}
var app: Node
var frames: int=0
var done: Dictionary={}
var hover_throttle: float=0.0
func _initialize() -> void:
 app=load("res://app_root.tscn").instantiate()
 app.user_args=PackedStringArray(["--aircraft=xcell-60-research","--start=airborne"])
 root.add_child(app)
func key(code: Key,pressed: bool) -> void:
 var event: InputEventKey=InputEventKey.new()
 event.keycode=code
 event.physical_keycode=code
 event.pressed=pressed
 Input.parse_input_event(event)
func _process(_delta: float) -> bool:
 frames+=1
 if app.flight==null or not app.flight.startup_error.is_empty():
  printerr("ERROR: helicopter direct route did not start")
  quit(1)
  return true
 var session: Node=app.flight.session
 if frames==1: hover_throttle=session.commands.throttle
 var sim: Node=session.sim
 sim.stop_at_tick=TICKS
 if not session.is_flyable():
  printerr("ERROR: ",session.pause_reason)
  quit(1)
  return true
 for tick: int in SCHEDULE:
  if done.has(tick) or sim.tick<tick: continue
  if sim.tick!=tick:
   printerr("ERROR: frame passed scheduled input tick ",tick," at ",sim.tick)
   quit(1)
   return true
  done[tick]=true
  for command: Array in SCHEDULE[tick]: key(command[0],command[1])
 if sim.tick<TICKS: return false
 if session.commands.throttle<=hover_throttle:
  printerr("ERROR: real keyboard input did not change collective")
  quit(1)
  return true
 var hash: HashingContext=HashingContext.new()
 hash.start(HashingContext.HASH_SHA256)
 hash.update(var_to_bytes(session.checkpoint()))
 print("HELI-16 ticks=%d frames=%d flight_sha256=%s"%[sim.tick,frames,hash.finish().hex_encode()])
 return true
