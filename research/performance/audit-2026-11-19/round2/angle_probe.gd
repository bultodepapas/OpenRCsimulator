extends SceneTree
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const FC = preload("res://physics/multirotor/flight_controller.gd")
const Rates = preload("res://physics/multirotor/rates.gd")
const Allocator = preload("res://physics/multirotor/allocator.gd")
const Actuator = preload("res://physics/multirotor/actuator_map.gd")

func _initialize() -> void:
 var half := 0.0537
 var rotors := [
  {hub_frd=PackedFloat64Array([-half,half,0]),spin=-1},
  {hub_frd=PackedFloat64Array([half,half,0]),spin=1},
  {hub_frd=PackedFloat64Array([-half,-half,0]),spin=1},
  {hub_frd=PackedFloat64Array([half,-half,0]),spin=-1}]
 var thrust_max := 8.25
 var allocator := Allocator.prepare(rotors,PackedFloat64Array([0.016,0.016,0.016,0.016]),PackedFloat64Array([4*thrust_max,2*thrust_max*half,2*thrust_max*half,2*thrust_max*0.016]),PackedFloat64Array([1,20,20,5]))
 var actuator := Actuator.prepare({law="first-order-lab-v1",full_command_speed_rad_s=3140.0,idle_command=0.055,max_command=1.0},{thrust_coefficient_n_s2=8.25/(3140.0*3140.0),torque_coefficient_n_m_s2=0.016*8.25/(3140.0*3140.0)})
 var prepared_rates := Rates.prepare(Rates.default_profile())
 var controller := {sample_hz=240,kp=PackedFloat64Array([0.08,0.085,0.09]),ki=PackedFloat64Array([0.1,0.11,0.2]),kd=PackedFloat64Array([0.002,0.0021,0.0]),i_max=PackedFloat64Array([0.08,0.08,0.06]),kaw=PackedFloat64Array([20,20,20]),tau_limit=PackedFloat64Array([0.9,0.9,0.35]),gyro_lpf_hz=90.0,dterm_lpf_hz=60.0,kff=PackedFloat64Array([0.00118,0.00126,0]),setpoint_lpf_hz=80.0,angle_max_tilt_rad=deg_to_rad(55),angle_gain_per_s=6.0,angle_rate_limit_rad_s=deg_to_rad(400),arm_low_throttle=0.05,throttle_rate_per_s=0.8}
 var result := FC.prepare(controller,prepared_rates.prepared,allocator,actuator.map,FC.THROTTLE_ABSOLUTE)
 if not (allocator.ok and actuator.ok and prepared_rates.ok and result.ok):
  print("PREP_FAILED ",allocator," ",actuator," ",prepared_rates," ",result)
  quit(1); return
 var config: Dictionary=result.config
 var pitch_threshold := acos(0.2)
 var input := FC.neutral_input()
 input[FC.IN_MODE]=1
 input[FC.IN_ARM]=1
 input[FC.IN_THROTTLE]=0.5
 var cases := []
 for pitch_sign in [1.0,-1.0]:
  for roll in [0.0,0.3,2.0]:
   var observations := []
   var attitudes := []
   for direction in [-1.0,1.0]:
    var pitch: float = float(pitch_sign) * (pitch_threshold + float(direction) * 1e-8)
    var q := M.q_from_euler(0.0,pitch,roll)
    attitudes.append(q)
    var body := RB.make_state(M.v3(0,0,-20),M.v3(0,0,0),q,M.v3(0,0,0))
    var modes := FC.initial_modes()
    modes[FC.MODE_MOTOR]=FC.MOTOR_ARMED
    modes[FC.MODE_FLIGHT]=FC.FLIGHT_ANGLE
    modes[FC.MODE_PREVIOUS_ARM]=1
    modes[FC.MODE_OFF_OBSERVED]=1
    var initial_aux := FC.initial_aux(body)
    var frame := {body=body,aux=initial_aux,modes=modes}
    var raw_target := FC._angle_rate_target(config,body,0,0)
    var sample := FC.sample(config,frame,input,{dt=1.0/240.0},0.0)
    observations.append({pitch=pitch,nose_horizontal=absf(cos(pitch)),heading=FC.heading(q),body=Array(body),initial_aux=Array(initial_aux),initial_modes=Array(modes),raw_target=Array(raw_target),sampled_setpoint=Array(sample.aux.slice(FC.AUX_SETPOINT,FC.AUX_SETPOINT+3)),torque_request=Array(sample.aux.slice(FC.AUX_TAU_REQUEST,FC.AUX_TAU_REQUEST+3)),torque_allocated=Array(sample.aux.slice(FC.AUX_TAU_ALLOCATED,FC.AUX_TAU_ALLOCATED+3)),motor_commands=Array(sample.aux.slice(FC.AUX_COMMAND,FC.AUX_COMMAND+4))})
   var dq := M.q_mul(M.q_conj(attitudes[0]),attitudes[1])
   var angle_distance := 2.0*atan2(sqrt(dq[1]*dq[1]+dq[2]*dq[2]+dq[3]*dq[3]),absf(dq[0]))
   cases.append({pitch_sign=pitch_sign,roll=roll,orientation_distance_rad=angle_distance,observations=observations,raw_roll_jump=absf(observations[0].raw_target[0]-observations[1].raw_target[0]),filtered_roll_jump=absf(observations[0].sampled_setpoint[0]-observations[1].sampled_setpoint[0]),roll_torque_jump=absf(observations[0].torque_request[0]-observations[1].torque_request[0])})
 var report := {description="Angle-mode heading boundary, actual production GDScript; controlled component fixture, not full flight",source_locations=["app/physics/multirotor/flight_controller.gd:330-342","app/physics/multirotor/flight_controller.gd:365-394","app/physics/multirotor/flight_controller.gd:447-475","app/physics/multirotor/controlled_plant.gd:288-304","app/physics/multirotor/controlled_plant.gd:324-325","app/sim/multirotor/session.gd:278"],controller_input={pilot=Array(input),dt_s=1.0/240.0,supply_voltage=0.0,controller_config=_jsonable(config),rates_profile=_jsonable(Rates.default_profile()),rotors=_jsonable(rotors),actuator=_jsonable(actuator.map),rotor_thrust_max=thrust_max,initial_body_velocity=[0.0,0.0,0.0],initial_angular_rate=[0.0,0.0,0.0]},cases=cases}
 var path := "user://angle_evidence.json"
 var f := FileAccess.open(path,FileAccess.WRITE)
 if f==null:
  print("could not write evidence")
  quit(1); return
 f.store_string(JSON.stringify(report,"  "))
 f.close()
 for c in cases:
  print("ANGLE_CASE sign=%.0f roll=%.3f distance=%.12f raw_jump=%.12f filtered_jump=%.12f torque_jump=%.12f" % [c.pitch_sign,c.roll,c.orientation_distance_rad,c.raw_roll_jump,c.filtered_roll_jump,c.roll_torque_jump])
 if cases[0].raw_roll_jump<1e-6 and cases[1].raw_roll_jump>1.0 and cases[2].raw_roll_jump>5.0 and cases[3].raw_roll_jump<1e-6 and cases[4].raw_roll_jump>1.0 and cases[5].raw_roll_jump>5.0:
  print("angle discontinuity reproduced")
  quit(0)
 else:
  print("angle discontinuity conditions changed")
  quit(1)

func _jsonable(value: Variant) -> Variant:
 match typeof(value):
  TYPE_DICTIONARY:
   var out := {}
   for key in value: out[key]=_jsonable(value[key])
   return out
  TYPE_ARRAY:
   var out := []
   for item in value: out.append(_jsonable(item))
   return out
  TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
   return Array(value)
 return value
