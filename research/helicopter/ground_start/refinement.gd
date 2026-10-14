# HELI-20: five-second smooth startup, common endpoint at three physics cadences.
# This checks integration refinement, not aircraft identification or aerobatic flight.
extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Field=preload("res://data/field_loader.gd")
const Wind=preload("res://physics/wind_config.gd")
const M=preload("res://physics/math3d.gd")
var rows: Array=[]
var failures: Array=[]
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var output: String="user://heli-refinement.json"
 for arg: String in OS.get_cmdline_user_args():
  if arg.begins_with("--out="): output=arg.trim_prefix("--out=")
 for scenario: String in ["calm","steady","gusts"]:
  var endpoints: Array=[]
  for hz: int in [240,480,960]:
   Engine.physics_ticks_per_second=hz
   var weather: Dictionary=Wind.defaults()
   if scenario!="calm": weather.speed_mps=3.0; weather.from_deg=90.0
   if scenario=="gusts": weather.gust_mps=1.0; weather.gust_up_mps=.2; weather.gust_duration_s=4.0; weather.gust_period_s=12.0; weather.gust_delay_s=2.0
   var session: Node=Session.new()
   session.physics_enabled=false; session.input_enabled=false; root.add_child(session)
   var ok: bool=session.setup() and session.set_field(Field.load_from(Field.DEFAULT_PATH).field) and session.setup_weather(weather) and session.set_start_choice("ground") and session.reset()
   if ok: ok=session.toggle_motor_arm() and session.set_drive_hold(false)
   for tick: int in 5*hz:
    if not ok: break
    var before: int=session.sim.tick
    session.sim.step()
    ok=session.sim.tick==before+1 and session.is_flyable()
   if not ok: failures.append("%s/%d: %s"%[scenario,hz,session.start_error+session.pause_reason])
   endpoints.append({hz=hz,ok=ok,body=Array(session.sim.state),continuous=Array(session.sim.continuous),phase=Array(session.shaft_phase)})
   session.free()
  var reference: Dictionary=endpoints[2]
  for endpoint: Dictionary in endpoints:
   if not endpoint.ok or not reference.ok: continue
   var b: PackedFloat64Array=PackedFloat64Array(endpoint.body)
   var r: PackedFloat64Array=PackedFloat64Array(reference.body)
   var qdot: float=0.0
   for i: int in 4: qdot+=b[6+i]*r[6+i]
   var error: Dictionary={position_m=M.norm(M.sub(b.slice(0,3),r.slice(0,3))),attitude_deg=2*acos(clampf(absf(qdot),0,1))*180/PI,body_rate_rad_s=M.norm(M.sub(b.slice(10,13),r.slice(10,13))),shaft_rad_s=absf(endpoint.continuous[0]-reference.continuous[0])}
   endpoint.error_vs_960=error
   # Plan engineering gates; body-rate bound 0.01 rad/s is tighter than 1% of trainer rate scale.
   endpoint.within_gate=error.position_m<=.01 and error.attitude_deg<=.1 and error.body_rate_rad_s<=.01 and error.shaft_rad_s<=.005*167.0
   if not endpoint.within_gate: failures.append("%s/%d: refinement gate"%[scenario,endpoint.hz])
  rows.append({case=scenario,endpoints=endpoints})
 var data: Dictionary={format="openrc-heli-startup-refinement v1",duration_s=5.0,reference_hz=960,ok=failures.is_empty(),failures=failures,scenarios=rows,godot=Engine.get_version_info().string}
 var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
 if file==null: failures.append("write evidence failed")
 else: file.store_string(JSON.stringify(data,"\t",true,true)); file.close()
 print("HELI-20 startup refinement: ","PASS" if failures.is_empty() else failures)
 quit(0 if failures.is_empty() else 1)
