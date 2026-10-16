# HELI-20: controller semantic actions reach the real motor lifecycle guards.
extends SceneTree
const Flight=preload("res://helicopter_main.gd")
const Session=preload("res://sim/helicopter_flight_session.gd")
const Field=preload("res://data/field_loader.gd")
const Profile=preload("res://input/controller_profile.gd")
const Actions=preload("res://input/controller_actions.gd")
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
 var defaults: Dictionary=Actions.effective_bindings(Profile.defaults(),flight.controller_capabilities())
 check("helicopter arm defaults to A/Cross",defaults.helicopter_arm=={type="button",button=JOY_BUTTON_A})
 check("helicopter hold defaults to B/Circle",defaults.helicopter_hold=={type="button",button=JOY_BUTTON_B})
 check("mode and trainer have automatic controls",defaults.helicopter_mode.button==JOY_BUTTON_RIGHT_SHOULDER and defaults.helicopter_trainer.button==JOY_BUTTON_LEFT_STICK)
 check("fixed-wing equipment is not inferred for helicopter",defaults.flaps_cycle.type=="unbound" and defaults.gear_toggle.type=="unbound" and defaults.smoke_toggle.type=="unbound")
 check("helicopter defaults have no collisions",Actions.validate(defaults).ok)
 check("fixed-wing presets do not gain helicopter functions",Actions.effective_bindings(Profile.defaults()).helicopter_arm.type=="unbound")
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
 session.set_controller_cut(true)
 flight.controller_action("helicopter_hold")
 check("held cut prevents another button from releasing rotor hold",session.zero_drive_hold)
 session.set_controller_cut(false)
 check("standard cut release cannot restart",session.zero_drive_hold)
 flight.controller_action("helicopter_hold")
 check("new explicit hold release works after cut release",not session.zero_drive_hold)
 session.commands.throttle=.5
 flight.controller_action("helicopter_mode")
 check("first mode action only previews pitch jump",session.flight_mode=="normal" and session.pending_mode=="idle_up")
 flight.controller_action("helicopter_mode")
 check("second mode action changes curve without stick move",session.flight_mode=="idle_up" and session.commands.throttle==.5)
 var trainer: bool=session.trainer_enabled
 flight.controller_action("helicopter_trainer")
 check("trainer action changes assistance",session.trainer_enabled!=trainer)
 session.sim.set_paused(true)
 var paused_mode: String=session.flight_mode
 var paused_trainer: bool=session.trainer_enabled
 flight.controller_action("helicopter_mode")
 flight.controller_action("helicopter_trainer")
 check("paused semantic mode and trainer do not queue",session.flight_mode==paused_mode and session.pending_mode.is_empty() and session.trainer_enabled==paused_trainer)
 flight.controller_action("helicopter_arm")
 check("disarm always latches hold",not session.power.armed and session.zero_drive_hold)
 session.sim.set_paused(false)
 session.radio.connect_device(42,{"known":true,"name":"Synthetic gamepad"},Profile.defaults())
 session.radio.armed=false
 flight.controller_action("helicopter_arm")
 check("unarmed selected controller cannot arm rotor",not session.power.armed)
 session.radio.profile.actions={helicopter_arm={type="button",button=25},helicopter_trainer={type="unbound"}}
 var custom: Dictionary=Actions.effective_bindings(session.radio.profile,flight.controller_capabilities())
 check("helicopter remaps and Clear beat defaults",custom.helicopter_arm.button==25 and custom.helicopter_trainer.type=="unbound")
 check("controller guide follows remapped arm and cleared trainer",flight.controller_controls_text().contains("25") and flight.controller_controls_text().contains(tr("Unbound")))
 flight.free(); session.free()
 print("HELI-20 controller actions: %d checks, %d failed"%[checks,failures])
 quit(0 if failures==0 else 1)
