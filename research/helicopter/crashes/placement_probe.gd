extends SceneTree
const Main=preload("res://helicopter_main.gd")
const Fixtures=preload("fixtures.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var flight=Main.new()
 flight.interactive_start=true; flight.external_controller_selection=true
 flight.set_user_args(PackedStringArray(["--start=airborne"]))
 root.add_child(flight); flight.set_process(false)
 flight.session.physics_enabled=false; flight.session.input_enabled=false
 for scenario: String in ["main","tail","hard","nose","fence"]:
  if DisplayServer.get_name()!="headless":
   await RenderingServer.frame_post_draw
   await RenderingServer.frame_post_draw
  Fixtures.trigger(flight.session,scenario)
  flight._present(0.0,1.0)
  print("POSE ",scenario," report=",flight.session.crash.body.slice(0,3)," ground=",flight._crash_presentation.wreck._ground_point," initial=",flight._crash_presentation.wreck._core_body.global_position)
  for frame: int in 480:
   await physics_frame
   flight._present(.0041666667,1.0)
   if frame in [0,3,9,59,100,479]: print("AFTER ",frame," ",flight._crash_presentation.wreck._core_body.global_position)
   if frame==59:
    var key:=InputEventKey.new(); key.physical_keycode=KEY_P; key.pressed=true
    flight._unhandled_input(key); flight._present(0.0,1.0)
    for paused_frame: int in 8:
     await physics_frame
     flight._present(.0041666667,1.0)
    flight._unhandled_input(key); flight._present(0.0,1.0)
  flight.session.reset(); flight._present(0.0,1.0)
 flight.free(); quit()
