extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const AD := preload("res://physics/aircraft_data.gd")
const P := preload("res://physics/propulsion.gd")
const D := preload("res://physics/dynamics.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const CUSTOM := "res://r6_custom_power.json"
const STOCK := "res://data/aircraft/turbo_lumber_evolution.json"
var failures := 0
func check(label: String, ok: bool) -> void:
 print("%s %s" % ["PASS" if ok else "FAIL", label])
 if not ok: failures += 1
func _initialize() -> void:
 _run.call_deferred()
func _run() -> void:
 var custom: Dictionary = AD.load_file(CUSTOM)
 var stock: Dictionary = AD.load_file(STOCK)
 check("complete custom aircraft loads through production v2 loader", custom.ok)
 check("complete stock aircraft loads", stock.ok)
 if not custom.ok or not stock.ok:
  print("ERROR_DETAIL ", str(custom.get("errors", [])), str(stock.get("errors", [])))
  quit(1)
  return
 var prop: Dictionary = custom.model.propulsion
 var other: Dictionary = stock.model.propulsion
 var rpm := 6000.0
 var j := 0.655
 var speed: float = j * (rpm / 60.0) * float(prop.diameter)
 var v: PackedFloat64Array = M.scale(P.axis(prop), speed)
 var tq: PackedFloat64Array = P.thrust_torque(v, rpm, prop, 1.225)
 var stock_tq: PackedFloat64Array = P.thrust_torque(v, rpm, other, 1.225)
 var p_shaft: float = tq[1] * rpm * TAU / 60.0
 var p_stock: float = stock_tq[1] * rpm * TAU / 60.0
 var p_body: float = tq[0] * speed
 var disc_area: float = PI * float(prop.diameter) * float(prop.diameter) / 4.0
 var ideal: float = tq[0] * (speed + sqrt(speed*speed + 2.0*tq[0]/(1.225*disc_area))) / 2.0
 check("custom propeller returns positive thrust and positive shaft load", tq[0] > 0 and tq[1] > 0)
 check("custom propeller work exceeds shaft supply", p_body > p_shaft)
 check("unaltered stock table has shaft supply above ideal disk bound", p_stock > ideal)
 print("R6_COMPONENT ", JSON.stringify({speed_mps=speed,rpm=rpm,j=tq[2],rho=1.225,diameter=prop.diameter,thrust_n=tq[0],torque_nm=tq[1],shaft_power_w=p_shaft,body_force_work_w=p_body,ideal_disk_w=ideal,stock_shaft_power_w=p_stock}))
 var f: Node = Flight.new()
 check("reference backend explicitly selected", f.setup_stage_backend("gdscript_reference"))
 f.setup(CUSTOM, "turbo-lumber-evolution")
 f.input_enabled = false
 check("custom aircraft passes full reference session setup", f.is_flyable())
 check("reference backend is active", f.stage_backend_identity().get("backend") == "gdscript_reference")
 if not f.is_flyable():
  print("SETUP_REFUSAL ", str(f.start_error))
  f.free()
  quit(1)
  return
 var initial_prop_air: Dictionary = P.stage_air_velocity(f.sim.state, f.air_data(f.sim.state, 0.0), prop)
 var initial_rpm: float = f.sim.continuous[f._rotor_index()]
 var initial_tq: PackedFloat64Array = P.thrust_torque(initial_prop_air.velocity_body, initial_rpm, prop, f.air_density())
 print("R6_TRIM ", JSON.stringify({rpm=initial_rpm,j=initial_tq[2],velocity=Array(initial_prop_air.velocity_body),thrust=initial_tq[0],torque=initial_tq[1]}))
 var state: PackedFloat64Array = f.sim.state.duplicate()
 state[RB.POS+2] = -50.0
 for k in 3:
  state[RB.VEL+k]=v[k]
  state[RB.RATE+k]=0.0
 state[RB.ATT]=1.0
 for k in range(1,4):state[RB.ATT+k]=0.0
 var continuous: PackedFloat64Array = f.sim.continuous.duplicate()
 var idx: int = f._rotor_index()
 continuous[idx]=rpm
 var actual_rho: float = f.air_density(state)
 var air: Dictionary = f.air_data(state, 0.0)
 var hub: Dictionary = P.stage_air_velocity(state, air, prop)
 var stage: Dictionary = f._coupled_response(state, continuous, 0.0)
 var local_tq: PackedFloat64Array = P.thrust_torque(hub.velocity_body, rpm, prop, actual_rho)
 var local_p: float = local_tq[1] * rpm * TAU / 60.0
 var local_work: float = local_tq[0] * M.dot(hub.velocity_body, P.axis(prop))
 check("production coupled stage evaluates constructed no-rate witness", stage.ok)
 check("stage inflow preserves exact advance ratio and deficit", absf(local_tq[2]-j)<1e-8 and local_work > local_p)
 f.sim.state = state
 f.sim.previous = state.duplicate()
 f.sim.continuous = continuous
 f.sim.aux[f.AUX_RPM] = rpm
 var saved: Dictionary = f.checkpoint()
 var restored: Node = Flight.new()
 check("restore backend explicitly selected", restored.setup_stage_backend("gdscript_reference"))
 restored.setup(CUSTOM, "turbo-lumber-evolution")
 restored.input_enabled = false
 var accepted: bool = restored.restore_checkpoint(bytes_to_var(var_to_bytes(saved)))
 check("constructed witness accepted by session checkpoint restore", accepted)
 if accepted:
  var before: int = restored.sim.tick
  restored.sim.step()
  check("constructed state advances one accepted reference tick", restored.sim.tick == before + 1 and restored.sim.fault_reason.is_empty())
  print("R6_SESSION ", JSON.stringify({rho=actual_rho,j=local_tq[2],thrust_n=local_tq[0],shaft_power_w=local_p,body_force_work_w=local_work,stage_ok=stage.ok,checkpoint_accepted=accepted,initial_tick=before,final_tick=restored.sim.tick,fault=restored.sim.fault_reason,backend=restored.stage_backend_identity(),custom_identity=custom.input_identity,stock_identity=stock.input_identity}))
 f.free()
 restored.free()
 print("R6 propeller power witness: %d failures" % failures)
 quit(1 if failures else 0)
