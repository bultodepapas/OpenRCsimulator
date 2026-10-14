# HELI-20: controller semantic actions reach the real motor lifecycle guards.
extends SceneTree
const Flight=preload("res://helicopter_main.gd")
const Session=preload("res://sim/helicopter_flight_session.gd")
const Field=preload("res://data/field_loader.gd")
const Profile=preload("res://input/controller_profile.gd")
var checks: int=0
var failures: int=0
func check(label: String,value: bool) -> void:
 checks+=1
 if not value: failures+=1; printerr("FAIL ",label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var session: Node=Session.new()
 session.physics_enabled=false; session.input_enabled=false; root.add_child(session)
 var flight: Node=Flight.new()
 flight.session=session
 check("ground lifecycle ready",session.setup() and session.set_field(Field.load_from(Field.DEFAULT_PATH).field) and session.set_start_choice("ground") and session.reset())
 check("unknown action refused",not flight.controller_action("unknown"))
 flight.controller_action("helicopter_hold")
 check("disarmed hold release refused",session.zero_drive_hold and not session.power.armed)
 session.sim.set_paused(true)
 flight.controller_action("helicopter_arm")
 check("paused arm refused",not session.power.armed)
 session.sim.set_paused(false)
 session.commands.roll=.2
 flight.controller_action("helicopter_arm")
 check("displaced cyclic refuses motor arm",not session.power.armed)
 session.commands.roll=0.0
 session.commands.throttle=.8
 flight.controller_action("helicopter_arm")
 check("high collective refuses motor arm",not session.power.armed)
 session.commands.throttle=session.startup_collective
 session._controller_lost=true
 flight.controller_action("helicopter_arm")
 check("lost device refuses motor arm",not session.power.armed)
 session._controller_lost=false
 check("arm action recognized",flight.controller_action("helicopter_arm"))
 check("arm retains hold",session.power.armed and session.zero_drive_hold)
 session.sim.set_paused(true)
 flight.controller_action("helicopter_hold")
 check("paused hold release refused",session.zero_drive_hold)
 session.sim.set_paused(false)
 flight.controller_action("helicopter_hold")
 check("explicit hold release enters spool",not session.zero_drive_hold and session.power_phase()=="SPOOLING")
 session.set_controller_cut(true); session.set_controller_cut(false)
 check("standard cut release cannot restart",session.zero_drive_hold)
 session.commands.throttle=.5
 flight.controller_action("helicopter_mode")
 check("first mode action only previews pitch jump",session.flight_mode=="normal" and session.pending_mode=="idle_up")
 flight.controller_action("helicopter_mode")
 check("second mode action changes curve without stick move",session.flight_mode=="idle_up" and session.commands.throttle==.5)
 var trainer: bool=session.trainer_enabled
 flight.controller_action("helicopter_trainer")
 check("trainer action changes assistance",session.trainer_enabled!=trainer)
 session.sim.set_paused(true)
 flight.controller_action("helicopter_arm")
 check("disarm always latches hold",not session.power.armed and session.zero_drive_hold)
 session.sim.set_paused(false)
 session.radio.connect_device(42,{"known":true,"name":"Synthetic gamepad"},Profile.defaults())
 session.radio.armed=false
 flight.controller_action("helicopter_arm")
 check("unarmed selected controller cannot arm rotor",not session.power.armed)
 flight.free(); session.free()
 print("HELI-20 controller actions: %d checks, %d failed"%[checks,failures])
 quit(0 if failures==0 else 1)
