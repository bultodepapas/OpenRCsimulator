extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const AD := preload("res://physics/aircraft_data.gd")
const P := preload("res://physics/propulsion.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const PATH := "res://r6_custom_trim.json"
var failures := 0
func check(label: String, ok: bool) -> void:
 print("%s %s" % ["PASS" if ok else "FAIL", label])
 if not ok: failures += 1
func _initialize() -> void:
 _run.call_deferred()
func _run() -> void:
 var loaded: Dictionary = AD.load_file(PATH)
 check("custom aircraft passes file and v2 admission",loaded.ok)
 var stock: Dictionary = AD.load_file("res://data/aircraft/turbo_lumber_evolution.json")
 check("unaltered stock aircraft passes v2 admission",stock.ok)
 var f: Node = Flight.new()
 check("reference backend explicitly selected",f.setup_stage_backend("gdscript_reference"))
 f.setup(PATH,"turbo-lumber-evolution")
 f.input_enabled = false
 check("custom aircraft obtains normal reference trim and setup",f.is_flyable())
 check("reference backend is active",f.stage_backend_identity().get("backend") == "gdscript_reference")
 if not f.is_flyable():
  print("DETAIL ",str(f.start_error));f.free();quit(1);return
 var prop: Dictionary = f.aircraft.model.propulsion
 var state: PackedFloat64Array = f.sim.state
 var rpm: float = f.sim.continuous[f._rotor_index()]
 var rho: float = f.air_density(state)
 var air: Dictionary = f.air_data(state,0.0)
 var local: Dictionary = P.stage_air_velocity(state,air,prop)
 var tq: PackedFloat64Array = P.thrust_torque(local.velocity_body,rpm,prop,rho)
 var speed: float = M.dot(P.axis(prop),local.velocity_body)
 var shaft: float = tq[1]*rpm*TAU/60.0
 var work: float = tq[0]*speed
 var area: float = PI*float(prop.diameter)*float(prop.diameter)/4.0
 var disk: float = tq[0]*(speed+sqrt(speed*speed+2.0*tq[0]/(rho*area)))/2.0
 var stage: Dictionary = f._coupled_response(state,f.sim.continuous,0.0)
 check("normal starting stage evaluates",stage.ok)
 check("normal starting stage creates excessive propeller work",tq[0]>0 and tq[1]>0 and work>shaft)
 var before: int = f.sim.tick
 f.sim.step()
 check("normal reference session advances an accepted tick",f.sim.tick == before+1 and f.sim.fault_reason.is_empty())
 print("R6_NATURAL_TRIM ",JSON.stringify({rpm=rpm,rho=rho,j=tq[2],speed_mps=speed,diameter=prop.diameter,thrust_n=tq[0],torque_nm=tq[1],shaft_power_w=shaft,thrust_work_w=work,ideal_disk_w=disk,rate_radps=Array(state.slice(RB.RATE,RB.RATE+3)),air_mps=Array(local.velocity_body),initial_tick=before,final_tick=f.sim.tick,fault=f.sim.fault_reason,backend=f.stage_backend_identity(),custom_identity=loaded.input_identity,stock_identity=stock.input_identity}))
 f.free()
 print("R6 natural trim power witness: %d failures" % failures)
 quit(1 if failures else 0)
