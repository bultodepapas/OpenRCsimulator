extends SceneTree
## Read-only diagnostic probes against the actual generated research trainer.
const Data = preload("res://physics/rotorcraft_data.gd")
const Hover = preload("res://physics/rotorcraft/trim.gd")
const Electronics = preload("res://physics/rotorcraft/electronics.gd")
const Drive = preload("res://physics/rotorcraft/drive.gd")
const M = preload("res://physics/math3d.gd")

func _initialize() -> void:
 var loaded: Dictionary = Data.load_file("res://data/aircraft/xcell_60_research.json")
 if not loaded.ok:
  push_error(str(loaded)); quit(1); return
 var context: Dictionary = loaded.context
 var hover: Dictionary = Hover.solve_hover(context, 0.0, M.v3(12,4,-3), M.v3(0,0,0), {"ground_height_up_m":0.0})
 if not hover.ok:
  push_error(str(hover)); quit(1); return
 var report: Dictionary = {"scope":"single evaluations, actual preset; no physical validation", "engine":Engine.get_version_info(), "heading_vertical_crossing":[], "flight_mode_switch":[], "drive_at_zero_speed":[]}
 var state: PackedFloat64Array = hover.state.duplicate()
 var sticks: PackedFloat64Array = hover.sticks.duplicate()
 report["hover"] = {"collective_stick":sticks[3], "shaft_rad_s":state[13], "state":Array(state)}
 for pitch_degrees: float in [89.9,90.0,90.1]:
  var q: PackedFloat64Array = M.q_from_euler(0.0,pitch_degrees*PI/180.0,0.0)
  for i: int in 4: state[6+i] = q[i]
  for i: int in [10,11,12,17,18]: state[i] = 0.0
  var controls: Dictionary = Electronics.fast_evaluate(context.electronics_model,state,sticks,"idle_up",false)
  if not controls.ok:
   push_error(str(controls)); quit(1); return
  report.heading_vertical_crossing.append({"pitch_degrees":pitch_degrees,"heading_error_rad":controls.heading_error_rad,"target_yaw_rate_rad_s":controls.target_yaw_rate_rad_s,"tail_collective_rad":controls.tail_collective_rad})
 state = hover.state.duplicate()
 for mode: String in ["normal","idle_up"]:
  var controls: Dictionary = Electronics.fast_evaluate(context.electronics_model,state,sticks,mode,true,hover.trim)
  if not controls.ok:
   push_error(str(controls)); quit(1); return
  report.flight_mode_switch.append({"mode":mode,"same_stick":sticks[3],"collective_rad":controls.collective_75_rad,"drive_fraction":controls.drive_fraction})
 for hold: bool in [false,true]:
  var result: Dictionary = Drive.evaluate(context.drive_model,0.0,0.0,true,hold)
  if not result.ok:
   push_error(str(result)); quit(1); return
  report.drive_at_zero_speed.append({"hold":hold,"drive_fraction":0.0,"engine_torque_nm":result.engine_torque_nm,"net_main_torque_nm":result.net_main_torque_nm})
 report["derived_reference"] = {"weight_n":context.mass_kg*context.gravity_m_s2,"disc_area_m2":PI*pow(context.main_model.rotor_radius_m,2),"hover_ideal_vi_m_s":sqrt(context.mass_kg*context.gravity_m_s2/(2*context.main_model.rho_kg_m3*PI*pow(context.main_model.rotor_radius_m,2))),"skid_equal_load_compression_m":context.mass_kg*context.gravity_m_s2/(4*loaded.skids.spring_n_m)}
 print(JSON.stringify(report,"  "))
 quit(0)
