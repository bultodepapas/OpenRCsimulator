extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Field=preload("res://data/field_loader.gd")
const CollisionSetup=preload("res://scenery/collision_setup.gd")
const Fixtures=preload("fixtures.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var s=Session.new()
 s.input_enabled=false; s.physics_enabled=false
 root.add_child(s)
 var field: Dictionary=Field.load_from(Field.DEFAULT_PATH).field
 var world: Dictionary=CollisionSetup.build(field)
 var ok: bool=s.setup() and s.set_field(field) and world.ok and s.set_collision_world(world.world) and s.reset()
 var expected: Dictionary={main="main_rotor",tail="tail_rotor",hard="skid_1",nose="fuselage"}
 for scenario: String in ["main","tail","hard","nose","fence"]:
  var hit: bool=Fixtures.trigger(s,scenario)
  print("HELI-33 SESSION ",scenario," hit=",hit," ",JSON.stringify(s.crash))
  ok=ok and hit and s.sim.paused and not s.power.armed and s.zero_drive_hold and not s.can_resume()
  if expected.has(scenario): ok=ok and s.crash.get("component","")==expected[scenario]
  else: ok=ok and s.crash.get("obstacle_kind","")=="fence"
  ok=ok and s.checkpoint().is_empty()
  var snapshot: PackedByteArray=var_to_bytes([s.sim.state,s.sim.continuous,s.sim.tick,s.crash])
  s.sim._physics_process(s.sim.dt())
  ok=ok and snapshot==var_to_bytes([s.sim.state,s.sim.continuous,s.sim.tick,s.crash])
  ok=ok and s.reset() and s.is_flyable()
 s.free()
 print("HELI-33 SESSION PASS ",ok)
 quit(0 if ok else 1)
