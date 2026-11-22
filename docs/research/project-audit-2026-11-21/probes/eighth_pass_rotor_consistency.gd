extends SceneTree
const Data = preload("res://physics/rotorcraft_data.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const Stage = preload("res://physics/rotorcraft/aerodynamic_stage.gd")
const Tail = preload("res://physics/rotorcraft/tail_rotor.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const Session = preload("res://sim/helicopter_flight_session.gd")
const Skids = preload("res://physics/rotorcraft/skid_contact.gd")
const Lifecycle = preload("res://physics/rotorcraft/lifecycle.gd")
var checks: int = 0
var failures: int = 0
func ck(label: String, value: bool) -> void:
 checks += 1
 if not value:
  failures += 1
  print("FAIL ", label)
func close(label: String, a: float, b: float, tol: float = 1e-9) -> void:
 ck(label, is_finite(a) and is_finite(b) and absf(a-b) <= tol * maxf(1.0, absf(b)))
func main_state(u: float, a1: float, vi: float) -> PackedFloat64Array:
 var s: PackedFloat64Array = RB.make_state(M.v3(0.0,0.0,-20.0), M.v3(u,0.0,0.0), PackedFloat64Array([1.0,0.0,0.0,0.0]), M.v3(0.0,0.0,0.0))
 s.append_array(PackedFloat64Array([167.0,a1,0.0,vi,0.0,0.0]))
 return s
func ev(ctx: Dictionary, state: PackedFloat64Array, bias: float) -> Dictionary:
 return Flight.evaluate(state,ctx,PackedFloat64Array([0.0,0.0,0.0,-0.19]),"normal",false,false,M.v3(0.0,0.0,0.0),true,PackedFloat64Array(),{"cyclic_forward_bias_rad":bias},-1.0)
func steady_ev(ctx: Dictionary, u: float, a1: float, vi: float) -> Dictionary:
 var state: PackedFloat64Array = main_state(u,a1,vi)
 var first: Dictionary = ev(ctx,state,0.0)
 if not first.get("ok",false): return first
 var tau: float = first.aero.main_rotor.effective_flap_time_constant_s
 var bias: float = first.aero.derivative[0]*tau/ctx.main_model.cyclic_longitudinal_gain_nominal_rad_per_rad
 var final: Dictionary = ev(ctx,state,bias)
 final["probe_bias"] = bias
 return final
func shaft_rate(ctx: Dictionary, state: PackedFloat64Array, out: Dictionary) -> float:
 var spin: float = ctx.spin_inertia_kg_m2 * out.state_derivative[Flight.OMEGA]
 var b: PackedFloat64Array = ctx.b_body_frd_kg_m2
 for j: int in range(3): spin += b[j] * out.state_derivative[RB.RATE+j]
 return state[Flight.OMEGA]*spin
func kinetic_rate(ctx: Dictionary, state: PackedFloat64Array, out: Dictionary) -> float:
 var translation: float = 0.0
 for j: int in range(3): translation += ctx.mass_kg*state[RB.VEL+j]*out.state_derivative[RB.VEL+j]
 return translation + shaft_rate(ctx,state,out)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
 var loaded: Dictionary = Data.load_file("res://data/aircraft/xcell_60_research.json")
 ck("stock X-Cell loader",loaded.get("ok",false))
 if not loaded.get("ok",false): print("loader ",loaded); quit(1); return
 var ctx: Dictionary = loaded.context
 var tip: float = 167.0*ctx.tail_model.tail_to_main_speed_ratio*ctx.tail_model.tail_rotor_radius_m
 var normal_speed: float = -5.0
 var theta: float = -0.75*normal_speed/tip
 var rotor_state: PackedFloat64Array = PackedFloat64Array([0.0,0.0,4.2])
 var vel: PackedFloat64Array = M.v3(0.0,normal_speed,0.0)
 var zero: PackedFloat64Array = M.v3(0.0,0.0,0.0)
 var s: Dictionary = Stage.evaluate(ctx.main_model,ctx.tail_model,ctx.airframe_model,rotor_state,167.0,vel,zero,0.10,0.0,0.0,theta,ctx.flow_floor_m_s,0.2,-1.0,1.0,0.0,true)
 var no: Dictionary = Stage.evaluate(ctx.main_model,ctx.tail_model,ctx.airframe_model,rotor_state,167.0,vel,zero,0.10,0.0,0.0,theta,ctx.flow_floor_m_s,0.0,-1.0,1.0,0.0,true)
 var mirror: Dictionary = Stage.evaluate(ctx.main_model,ctx.tail_model,ctx.airframe_model,rotor_state,167.0,M.v3(0.0,5.0,0.0),zero,0.10,0.0,0.0,-theta,ctx.flow_floor_m_s,0.2,-1.0,1.0,0.0,true)
 var calm: Dictionary = Tail.evaluate(ctx.tail_model,167.0,4.2,zero,zero,0.0,true,167.0)
 ck("tail and controls accepted",s.get("ok",false) and no.get("ok",false) and mirror.get("ok",false) and calm.get("ok",false))
 if not s.get("ok",false): print("tail stage ",s); quit(1); return
 var tr: Dictionary=s.tail_rotor
 var lam: float=tr.induced_velocity_m_s/tip
 var muz: float=normal_speed/tip
 var residual: float=tr.thrust_coefficient-2.0*ctx.tail_model.wake_efficiency*lam*sqrt(tr.advance_ratio*tr.advance_ratio+(lam-muz)*(lam-muz))
 close("zero coefficient",tr.thrust_coefficient,0.0)
 close("negative wake",tr.induced_velocity_m_s,-2.5)
 ck("no tail cap",not tr.thrust_limited)
 close("tail in-plane zero",tr.advance_ratio,0.0)
 close("no force control wake zero",calm.induced_velocity_m_s,0.0)
 close("signed reflection",mirror.tail_rotor.induced_velocity_m_s,-tr.induced_velocity_m_s)
 close("zero-fraction control leaves tail unchanged",no.tail_rotor.induced_velocity_m_s,tr.induced_velocity_m_s)
 close("fin wake is 20 percent",s.vertical_fin_wake_velocity_body_frd_m_s[1],-0.5)
 close("fin side velocity",s.airframe.vertical_fin_relative_air_m_s[1],-4.5)
 close("no-wake fin side velocity",no.airframe.vertical_fin_relative_air_m_s[1],-5.0)
 ck("induced not zero-flow branch",absf(lam)>1e-6 and absf(lam-muz)>1e-6)
 ck("nonzero momentum closure residual",absf(residual)>1e-4)
 print("TAIL ",JSON.stringify({"tip":tip,"theta":theta,"ct":tr.thrust_coefficient,"trim_ct":tr.trim_ct,"thrust_n":tr.thrust_n,"vi":tr.induced_velocity_m_s,"momentum_residual":residual,"equivalent_unblocked_residual_n":residual*ctx.tail_model.rho_kg_m3*PI*ctx.tail_model.tail_rotor_radius_m*ctx.tail_model.tail_rotor_radius_m*tip*tip,"tail_torque_nm":tr.torque_nm,"tail_power_w":tr.torque_nm*tr.tail_omega_rad_s,"fin_with_wake":s.airframe.vertical_fin_loads,"fin_no_wake":no.airframe.vertical_fin_loads,"fin_relative_power":s.airframe.vertical_fin_relative_power_w,"fin_wake_power":s.airframe.vertical_fin_wake_power_w}))
 var main: Dictionary=ctx.main_model
 var radius: float=main.rotor_radius_m
 var mt: float=167.0*radius
 var area: float=PI*radius*radius
 var probe_state: PackedFloat64Array=main_state(15.0,0.0,3.0)
 var sample: Dictionary=ev(ctx,probe_state,0.0)
 ck("power sample accepted",sample.get("ok",false))
 var pitch: float=sample.controls.collective_75_rad
 var lo: float=0.0
 var hi: float=10.0
 var mu: float=15.0/mt
 for i: int in range(100):
  var v: float=(lo+hi)*0.5
  var ct: float=clampf(0.5*main.blade_lift_curve_slope_per_rad*main.solidity*(pitch*(1.0/3.0+mu*mu/2.0)-v/(2.0*mt)),-main.thrust_coefficient_max,main.thrust_coefficient_max)
  var thrust: float=main.rho_kg_m3*area*mt*mt*ct
  if 2.0*main.rho_kg_m3*area*v*sqrt(15.0*15.0+v*v)>thrust: hi=v
  else: lo=v
 var vi: float=(lo+hi)*0.5
 var flat: Dictionary=steady_ev(ctx,15.0,0.0,vi)
 var forward: Dictionary=steady_ev(ctx,15.0,-0.12,vi)
 var aft: Dictionary=steady_ev(ctx,15.0,0.12,vi)
 ck("steady flap cases accepted",flat.get("ok",false) and forward.get("ok",false) and aft.get("ok",false))
 for item: Dictionary in [flat,forward,aft]:
  ck("inside reported indicators",item.aero.main_rotor.within_identified_advance_ratio and item.aero.main_rotor.within_small_flap_angle_range)
  close("zero flap derivative",item.aero.derivative[0],0.0)
  close("steady main wake",item.aero.derivative[2],0.0,1e-8)
  ck("constructed cyclic bias magnitude below 0.06 rad",absf(item.probe_bias)<0.06)
  close("shared shaft row",shaft_rate(ctx,probe_state,item),167.0*(item.drive.net_main_torque_nm-item.aero.main_rotor.torque_nm-ctx.tail_model.tail_to_main_speed_ratio*item.aero.tail_rotor.torque_nm),1e-10)
 close("main Q flat vs tilted",forward.aero.main_rotor.torque_nm,flat.aero.main_rotor.torque_nm)
 close("main thrust flat vs tilted",forward.aero.main_rotor.thrust_n,flat.aero.main_rotor.thrust_n)
 close("tail Q unaffected",forward.aero.tail_rotor.torque_nm,flat.aero.tail_rotor.torque_nm)
 close("drive unaffected",forward.drive.net_main_torque_nm,flat.drive.net_main_torque_nm)
 var work: float=15.0*forward.aero.main_rotor.loads[0]
 close("forward rotor work",work,15.0*forward.aero.main_rotor.thrust_n*sin(0.12))
 close("negative tilt symmetry",15.0*aft.aero.main_rotor.loads[0],-work)
 close("total derivative energy delta matches body work",kinetic_rate(ctx,probe_state,forward)-kinetic_rate(ctx,probe_state,flat),work,1e-9)
 for record: Array in [["flat",flat,0.0],["tilted",forward,-0.12],["aft",aft,0.12]]:
  var label: String=record[0]
  var item: Dictionary=record[1]
  var alpha: float=record[2]
  print("ENERGY_LEDGER ",JSON.stringify({"label":label,"mass":ctx.mass_kg,"gravity":ctx.gravity_m_s2,"inertia":ctx.inertia_kg_m2,"b":ctx.b_body_frd_kg_m2,"ispin":ctx.spin_inertia_kg_m2,"state":main_state(15.0,alpha,vi),"derivative":item.state_derivative,"loads":item.loads,"aero_loads":item.aerodynamic_loads,"main_rotor":item.aero.main_rotor,"tail_rotor":item.aero.tail_rotor,"airframe":item.aero.airframe,"drive":item.drive,"controls":item.controls,"coupling":item.coupling,"inflow":item.aero.inflow,"tail_ratio":ctx.tail_model.tail_to_main_speed_ratio,"wind_ned":[0.0,0.0,0.0],"height_over_radius":-1.0}))
 print("MAIN ",JSON.stringify({"u":15.0,"mu":mu,"pitch":pitch,"vi":vi,"tilt":-0.12,"thrust_n":forward.aero.main_rotor.thrust_n,"main_q_nm":forward.aero.main_rotor.torque_nm,"main_shaft_power_w":167.0*forward.aero.main_rotor.torque_nm,"tail_shaft_power_w":167.0*ctx.tail_model.tail_to_main_speed_ratio*forward.aero.tail_rotor.torque_nm,"drive_main_power_w":167.0*forward.drive.net_main_torque_nm,"forward_work_w":work,"opposite_work_w":15.0*aft.aero.main_rotor.loads[0],"kinetic_flat_w":kinetic_rate(ctx,probe_state,flat),"kinetic_tilt_w":kinetic_rate(ctx,probe_state,forward),"wake_derivative":forward.aero.derivative[2],"cyclic_bias_flat":flat.probe_bias,"cyclic_bias_forward":forward.probe_bias}))
 var session: Node=Session.new()
 session.input_enabled=false
 session.physics_enabled=false
 root.add_child(session)
 var setup_ok: bool=session.setup() and session.reset()
 ck("session starts",setup_ok)
 if setup_ok:
  var body: PackedFloat64Array=session.sim.state.duplicate()
  var session_normal: float = -19.3
  var session_theta: float = -0.75 * session_normal / tip
  body[3]=0.0; body[4]=session_normal; body[5]=0.0
  body[6]=1.0; body[7]=0.0; body[8]=0.0; body[9]=0.0
  body[10]=0.0; body[11]=0.0; body[12]=0.0
  var continuous: PackedFloat64Array=PackedFloat64Array([167.0,0.0,0.0,4.2,0.0,-0.15])
  var full: PackedFloat64Array=body.duplicate(); full.append_array(continuous)
  session.trainer_enabled=false
  var wind: PackedFloat64Array=session.wind_at(session.sim.time(),body)
  var height: float=session._height_over_radius(full)
  var contact: Dictionary=Skids.evaluate(body,session.aircraft.skids,session.ground_surfaces,false,PackedFloat64Array(),session.environment.lake)
  ck("constructed airborne contact valid",contact.get("ok",false) and contact.max_depth_m==0.0)
  var drive_scale: float=Lifecycle.scale(session.power,session.zero_drive_hold,session.sim.time())
  var held: bool=session.zero_drive_hold or not session.power.armed
  var base: Dictionary=Flight.evaluate(full,ctx,PackedFloat64Array([0.0,0.0,0.0,0.0]),session.flight_mode,false,held,wind,true,contact.loads,session._trim,height,drive_scale)
  ck("session base evaluation accepted",base.get("ok",false))
  if not base.get("ok",false): quit(1); return
  var yaw: float=(session_theta-base.controls.tail_collective_rad)/0.075
  ck("constructed session yaw within stick range",absf(yaw)<=1.0)
  if absf(yaw)<=1.0:
   var session_eval: Dictionary=Flight.evaluate(full,ctx,PackedFloat64Array([0.0,0.0,yaw,0.0]),session.flight_mode,false,held,wind,true,contact.loads,session._trim,height,drive_scale)
   ck("session matched evaluation accepted",session_eval.get("ok",false))
   if not session_eval.get("ok",false): quit(1); return
   close("session matched tail thrust near zero",session_eval.aero.tail_rotor.thrust_n,0.0)
   close("session matched tail wake half normal speed",session_eval.aero.tail_rotor.induced_velocity_m_s,session_normal*0.5)
   session.sim.inputs=PackedFloat64Array([0.0,0.0,yaw,0.5])
   session.commands={roll=0.0,pitch=0.0,yaw=yaw,throttle=0.5}
   session.sim.continuous=continuous
   session.sim.aux=PackedFloat64Array([167.0*60.0/(2.0*PI)])
   var prepared: Dictionary=session.sim.prepare_reset(body)
   if not prepared.get("ok",false): print("SESSION RESET REFUSAL ",prepared)
   var committed: bool=prepared.get("ok",false) and session.sim.commit_prepared_reset(prepared)
   ck("constructed reference snapshot reset",committed)
   if committed:
    var actual_stage: Dictionary=session._stage(session.sim.state,session.sim.continuous,session.sim.time())
    var same_stage: bool=not actual_stage.is_empty()
    if same_stage:
     for i: int in RB.SIZE: same_stage=same_stage and absf(actual_stage.body_derivative[i]-session_eval.body_derivative[i])<1e-12
     for i: int in 6: same_stage=same_stage and absf(actual_stage.derivative[i]-session_eval.derivative[i])<1e-12
    ck("session stage matches diagnostic full state derivative",same_stage)
    print("SESSION PRE ",JSON.stringify({"normal":session_normal,"mu_main":absf(session_normal)/mt,"base_theta":base.controls.tail_collective_rad,"theta":session_theta,"required_yaw":yaw,"trim":session._trim,"inflow":session_eval.aero.tail_rotor.induced_velocity_m_s,"thrust":session_eval.aero.tail_rotor.thrust_n,"fin_load":session_eval.aero.airframe.vertical_fin_loads,"state":full,"wind_ned":wind,"height_over_radius":height,"weather":session.weather_configuration(),"backend":session.stage_backend_identity(),"aircraft_sha256":session.aircraft.input_identity.sha256,"inputs":session.sim.inputs,"hold":held,"drive_scale":drive_scale,"contact_loads":contact.loads,"matched_stage":same_stage,"reset_accepted":committed,"diagnostic_derivative":session_eval.state_derivative,"body_derivative":actual_stage.get("body_derivative",PackedFloat64Array()),"continuous_derivative":actual_stage.get("derivative",PackedFloat64Array())}))
    session.sim.step()
    ck("constructed reference tick accepted",session.sim.tick==1 and session.is_flyable() and session.sim.fault_reason.is_empty() and session.crash.is_empty())
    print("SESSION POST ",JSON.stringify({"tick":session.sim.tick,"flyable":session.is_flyable(),"fault":session.sim.fault_reason,"crash":session.crash,"yaw":yaw,"body":session.sim.state,"continuous":session.sim.continuous}))
  else: print("SESSION untested: required yaw outside sticks")
 session.queue_free()
 print("R8 ROTOR LEDGER: %d checks, %d failed" % [checks,failures])
 quit(1 if failures else 0)
