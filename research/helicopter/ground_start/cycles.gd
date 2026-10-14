# HELI-20e: deterministic test pilot; never attached to the production flight.
# Exercise repeated motor starts without resetting/reloading the scene or body.
extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Field=preload("res://data/field_loader.gd")
const Wind=preload("res://physics/wind_config.gd")
const Skids=preload("res://physics/rotorcraft/skid_contact.gd")
const M=preload("res://physics/math3d.gd")
var session: Node
var samples: Array=[]
var reports: Array=[]
var scenario: String="calm"
var out: String="user://heli-cycles.json"
var count: int=1
var failure: String=""
var hz: int=240
func _initialize() -> void: run.call_deferred()
func run() -> void:
 for arg: String in OS.get_cmdline_user_args():
  var pair: PackedStringArray=arg.trim_prefix("--").split("=",true,1)
  if pair.size()!=2: continue
  match pair[0]:
   "case": scenario=pair[1]
   "cycles": count=int(pair[1])
   "out": out=pair[1]
   "hz": hz=int(pair[1])
 if scenario not in ["calm","steady","gusts"] or count<1 or count>10 or hz not in [240,480,960]: quit(1); return
 Engine.physics_ticks_per_second=hz
 var weather: Dictionary=Wind.defaults()
 if scenario!="calm": weather.speed_mps=3.0; weather.from_deg=90.0
 if scenario=="gusts": weather.gust_mps=1.0; weather.gust_up_mps=.2; weather.gust_duration_s=4.0; weather.gust_period_s=12.0; weather.gust_delay_s=2.0
 session=Session.new(); session.physics_enabled=false; session.input_enabled=false; root.add_child(session)
 if not (session.setup() and session.set_field(Field.load_from(Field.DEFAULT_PATH).field) and session.setup_weather(weather) and session.set_start_choice("ground") and session.reset()):
  failure="setup: "+session.start_error+session.weather_error
 else:
  for cycle: int in count:
   var report: Dictionary=run_cycle(cycle)
   reports.append(report)
   print("CYCLE_RESULT ",JSON.stringify(report))
   if not failure.is_empty(): break
 var data: Dictionary={format="openrc-heli-ground-cycles v1",case=scenario,hz=hz,requested_cycles=count,completed_cycles=reports.size(),ok=failure.is_empty() and reports.size()==count,failure=failure,weather=weather,control_reference=session._trim,cycles=reports,sample_layout="t,cycle,phase,body13,rotor_contact14,inputs4,power_phase",samples=samples,godot=Engine.get_version_info().string,final_checkpoint_sha256=var_to_bytes(session.checkpoint()).hex_encode().sha256_text()}
 var file: FileAccess=FileAccess.open(out,FileAccess.WRITE)
 if file==null: failure="cannot write evidence"
 else: file.store_string(JSON.stringify(data,"\t",true,true)); file.close()
 session.free()
 if not failure.is_empty(): print("CYCLE_FAILURE ",failure)
 quit(0 if failure.is_empty() else 1)
func run_cycle(cycle: int) -> Dictionary:
 var start: float=session.sim.time()
 var initial: PackedFloat64Array=session.sim.state.duplicate()
 var phase: String="spool"
 var phase_start: float=start
 var landing_collective: float=0.0
 var iz: float=0.0
 var inorth: float=0.0
 var ieast: float=0.0
 var peak_height: float=0.0
 var peak_radius: float=0.0
 var spool_displacement: float=0.0
 var spool_yaw: float=0.0
 var touchdown_down_speed: float=0.0
 var hover_error: float=0.0
 var left_ground: bool=false
 var grounded_previous: bool=true
 var shutdown_on_ground: bool=false
 var stop_time: float=-1.0
 session.commands={roll=0.0,pitch=0.0,yaw=0.0,throttle=session.startup_collective}
 session.sim.inputs=PackedFloat64Array([0,0,0,session.startup_collective])
 if not session.toggle_motor_arm() or not session.set_drive_hold(false):
  failure="arm/hold refused: "+session.pause_reason
  return {cycle=cycle,ok=false,failure=failure}
 for tick: int in 120*hz:
  var t: float=session.sim.time()-start
  var state: PackedFloat64Array=session.sim.state
  var velocity: PackedFloat64Array=M.q_rotate(state.slice(6,10),state.slice(3,6))
  var h: float=-state[2]
  var contact: Dictionary=Skids.evaluate(state,session.aircraft.skids,session.ground_surfaces)
  var grounded: bool=contact.ok and contact.max_depth_m>0.0
  if not grounded and h>.2: left_ground=true
  if grounded and not grounded_previous and left_ground: touchdown_down_speed=maxf(touchdown_down_speed,velocity[2])
  grounded_previous=grounded
  peak_height=maxf(peak_height,h)
  peak_radius=maxf(peak_radius,sqrt((state[0]-6.0)**2+state[1]**2))
  if phase=="spool":
   spool_displacement=maxf(spool_displacement,M.norm(M.sub(state.slice(0,3),initial.slice(0,3))))
   var yaw0: float=M.q_to_euler(initial.slice(6,10))[0]
   var yaw: float=M.q_to_euler(state.slice(6,10))[0]
   spool_yaw=maxf(spool_yaw,absf(wrapf(yaw-yaw0,-PI,PI)))
   if h>.16: failure="automatic liftoff during zero-pitch spool"; break
   if t>=14.0:
    if session.power_phase()!="GOVERNED": failure="spool never governed"; break
    phase="flight"; phase_start=session.sim.time()
  if phase=="flight":
   var flight_t: float=session.sim.time()-phase_start
   var target: float=.11+minf(flight_t*.18,1.09) if flight_t<16 else maxf(.06,1.2-(flight_t-16)*.12)
   var down_target: float=clampf((h-target)*.8,-.25,.2)
   var ev: float=down_target-velocity[2]
   iz=clampf(iz+.03*ev*session.sim.dt(),-.15,.3)
   var throttle: float=clampf(.49-.07*ev-iz,.16,.7)
   inorth=clampf(inorth+.12*(6-state[0])*session.sim.dt(),-.8,.8)
   ieast=clampf(ieast+.12*(-state[1])*session.sim.dt(),-.8,.8)
   var an: float=.7*(6-state[0])-1.4*velocity[0]+inorth
   var ae: float=.7*(-state[1])-1.4*velocity[1]+ieast
   var yaw: float=M.q_to_euler(state.slice(6,10))[0]
   var ax: float=cos(yaw)*an+sin(yaw)*ae
   var ay: float=-sin(yaw)*an+cos(yaw)*ae
   var roll: float=clampf(ay/9.80665/session.aircraft.context.electronics_model.trainer_max_tilt_rad,-.4,.4)
   var pitch: float=clampf(-ax/9.80665/session.aircraft.context.electronics_model.trainer_max_tilt_rad,-.4,.4)
   session.commands={roll=roll,pitch=pitch,yaw=0.0,throttle=throttle}
   session.sim.inputs=PackedFloat64Array([roll,pitch,0,throttle])
   if flight_t>=12.0 and flight_t<=16.0: hover_error=maxf(hover_error,absf(h-1.2))
   if flight_t>26 and grounded and h<.14 and M.norm(velocity)<.1:
    phase="lower_collective"; phase_start=session.sim.time(); landing_collective=throttle; shutdown_on_ground=true
   elif flight_t>65: failure="test pilot did not finish landing"; break
  elif phase=="lower_collective":
   var u: float=clampf((session.sim.time()-phase_start)/2.0,0.0,1.0)
   var throttle: float=lerpf(landing_collective,session.startup_collective,u)
   session.commands={roll=0.0,pitch=0.0,yaw=0.0,throttle=throttle}
   session.sim.inputs=PackedFloat64Array([0,0,0,throttle])
   if u==1.0: session.set_drive_hold(true); phase="coast"; phase_start=session.sim.time()
  elif phase=="coast":
   if session.sim.continuous[0]==0.0:
    if stop_time<0.0: stop_time=session.sim.time()
    if session.sim.time()-stop_time>=1.0:
     if not session.toggle_motor_arm(): failure="disarm refused"
     break
  var before: int=session.sim.tick
  session.sim.step()
  if not session.is_flyable() or session.sim.tick!=before+1:
   failure="tick failed: "+session.pause_reason; break
  if session.sim.tick%hz==0: samples.append([session.sim.time(),cycle,phase,Array(session.sim.state),Array(session.sim.continuous),Array(session.sim.inputs),session.power_phase()])
 var ok: bool=failure.is_empty() and left_ground and peak_height>.9 and peak_height<1.5 and peak_radius<2.5 and hover_error<.15 and shutdown_on_ground and touchdown_down_speed<.35 and session.sim.continuous[0]==0.0 and not session.power.armed and session.zero_drive_hold
 if not ok and failure.is_empty(): failure="cycle acceptance metric failed"
 return {cycle=cycle,ok=ok,failure=failure,seconds=session.sim.time()-start,spool_displacement_m=spool_displacement,spool_yaw_deg=spool_yaw*180.0/PI,peak_height_m=peak_height,peak_radius_m=peak_radius,hover_height_error_m=hover_error,touchdown_down_speed_m_s=touchdown_down_speed,shutdown_on_ground=shutdown_on_ground,final_body=Array(session.sim.state),final_omega=session.sim.continuous[0]}
