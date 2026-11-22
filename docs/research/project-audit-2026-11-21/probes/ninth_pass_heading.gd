extends SceneTree
## Public make_state with stock Bisonte on isotropic flat ground, at rest but
## 10 micrometres below static support. Only yaw changes between each pair.
## No external force or direct state mutation is used. This tests a component;
## ninth_pass_session.gd separately tests validated custom-course preparation.
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const M := preload("res://physics/math3d.gd")
const NEUTRAL := {"throttle":0.0, "steering":0.0, "brake":0.0, "reverse":false}
var checks := 0
var failures := 0

func check(label: String, passed: bool) -> void:
    checks += 1
    if not passed: failures += 1
    print(("PASS " if passed else "FAIL ") + label)

func road(mu: float) -> Callable:
    return func(_n: float, _e: float) -> Dictionary:
        return {"height_m":0.0, "normal_ned":PackedFloat64Array([0.0,0.0,-1.0]), "mu":mu, "rolling":0.0, "surface_id":"audit"}

func slip_rates(state: PackedFloat64Array, model: Dictionary, acceleration: PackedFloat64Array) -> PackedFloat64Array:
    var epsilon := 0.000001
    var velocity := PackedFloat64Array([epsilon * acceleration[0], epsilon * acceleration[1], epsilon * acceleration[2]])
    var omega := PackedFloat64Array([epsilon * acceleration[3], epsilon * acceleration[4], epsilon * acceleration[5]])
    var radius := float(model.tire_radius_m)
    var arm := float(model.arm_length_m)
    var result := PackedFloat64Array()
    for corner in 4:
        var travel := state[Vehicle.TRAVEL + corner]
        var side := signf(model.corner_y_m[corner])
        var horizontal_arm := sqrt(arm * arm - travel * travel)
        var hub := PackedFloat64Array([model.corner_x_m[corner], model.corner_y_m[corner] + side * (horizontal_arm - arm),
            float(model.cg_height_above_chassis_datum_m) + float(model.wheel_center_rest_below_chassis_datum_m) - travel])
        var hub_prime := PackedFloat64Array([0.0, -side * travel / horizontal_arm, -1.0])
        var hub_vel := M.add(velocity, M.add(M.cross(omega, hub), M.scale(hub_prime, epsilon * acceleration[6 + corner])))
        var wheel_omega := M.add(omega, PackedFloat64Array([0.0, -epsilon * acceleration[10 + corner], 0.0]))
        var patch_vel := M.add(hub_vel, M.cross(wheel_omega, PackedFloat64Array([0.0, 0.0, radius])))
        result.append(patch_vel[0] / epsilon)
        result.append(patch_vel[1] / epsilon)
    return result


func max_difference(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
    var biggest := 0.0
    for i in a.size():
        biggest = maxf(biggest, absf(a[i] - b[i]))
    return biggest

func report(label: String, state: PackedFloat64Array, model: Dictionary, result: Dictionary) -> void:
    if not bool(result.get("ok", false)):
        print("FAIL ", label, " ", result)
        return
    print("RESULT ", label, " ", JSON.stringify({"sweeps":result.friction_sweeps_used,
        "tire_load_n":result.wheel_load_n, "tire_long_n":result.wheel_longitudinal_force_n,
        "tire_lat_n":result.wheel_lateral_force_n, "slip_accel":slip_rates(state,model,result.generalized_acceleration),
        "generalized_accel":result.generalized_acceleration, "attitude":state.slice(6,10),
        "travel":state.slice(13,17), "position_down":state[2]}))

func pair(label: String, model: Dictionary, altitude: float, mu: float) -> Dictionary:
    var ground := road(mu)
    var forward := Vehicle.make_state(model,{"id":"witness", "north_m":0.0, "east_m":0.0, "heading_rad":0.0, "vehicle_up_m":altitude},ground)
    var rotated := Vehicle.make_state(model,{"id":"witness", "north_m":0.0, "east_m":0.0, "heading_rad":PI / 2.0, "vehicle_up_m":altitude},ground)
    if forward.size() != Vehicle.STATE_SIZE or rotated.size() != Vehicle.STATE_SIZE:
        print("FAIL state construction ", label)
        return {"ok":false}
    var a: Dictionary = Vehicle._evaluate_active(forward, model, NEUTRAL, ground, false)
    var b: Dictionary = Vehicle._evaluate_active(rotated, model, NEUTRAL, ground, false)
    report(label + "_heading_0", forward, model, a)
    report(label + "_heading_90", rotated, model, b)
    if not a.ok or not b.ok:
        return {"ok":false}
    return {"ok":true, "a":a, "b":b, "difference":max_difference(a.generalized_acceleration,b.generalized_acceleration),
        "tire_difference":max_difference(a.wheel_lateral_force_n,b.wheel_lateral_force_n)}

func _initialize() -> void:
    if not Vehicle.set_backend_override_for_tests(Vehicle.BACKEND_GDSCRIPT_REFERENCE):
        print("FAIL reference")
        quit(1)
        return
    var data := Data.load_default()
    if not data.ok:
        print("FAIL data ", data)
        quit(1)
        return
    var model: Dictionary = data.model
    var initial := Vehicle.initialize(model, road(0.8))
    if not initial.ok:
        print("FAIL init ", initial)
        quit(1)
        return
    var up := -float(initial.state[Vehicle.POS + 2])
    var perturb := pair("lowered10um_mu08",model,up-0.00001,0.8)
    var frictionless := pair("lowered10um_mu0",model,up-0.00001,0.0)
    var equilibrium := pair("equilibrium_mu08",model,up,0.8)
    if not perturb.ok or not frictionless.ok or not equilibrium.ok:
        print("FAIL eval")
        quit(1)
        return
    print("COMPARE ", JSON.stringify({"lowered_mu08_generalized_difference":perturb.difference,
        "lowered_mu08_lateral_force_difference":perturb.tire_difference,
        "lowered_mu0_generalized_difference":frictionless.difference,
        "equilibrium_mu08_generalized_difference":equilibrium.difference}))
    check("lowered matched headings differ in generalized acceleration", perturb.difference > 0.01)
    check("lowered matched headings differ in lateral tyre force", perturb.tire_difference > 0.1)
    check("zero-grip matched headings agree", frictionless.difference < 1.0e-9)
    check("true-equilibrium matched headings agree", equilibrium.difference < 1.0e-8)
    check("zero heading suppresses rows while rotated case solves them", int(perturb.a.friction_sweeps_used) == 0
        and int(perturb.b.friction_sweeps_used) > 0 and int(perturb.b.friction_sweeps_used) < Vehicle.FRICTION_SWEEPS)
    var patch: PackedFloat64Array = slip_rates(Vehicle.make_state(model, {"id":"check", "north_m":0.0,
        "east_m":0.0, "heading_rad":PI/2.0, "vehicle_up_m":up-0.00001}, road(0.8)), model, perturb.b.generalized_acceleration)
    var residual := 0.0
    var capacity_ok := true
    for value in patch: residual = maxf(residual, absf(value))
    for corner in 4:
        var longitudinal := float(perturb.b.wheel_longitudinal_force_n[corner])
        var lateral := float(perturb.b.wheel_lateral_force_n[corner])
        var capacity := 0.8 * float(model.tire_friction_scale) * float(perturb.b.wheel_load_n[corner])
        capacity_ok = capacity_ok and sqrt(longitudinal*longitudinal+lateral*lateral) < 0.1*capacity
    check("rotated residual is below one micrometre per second squared", residual < 1.0e-6)
    check("rotated forces use less than ten percent of available grip", capacity_ok)
    print("R9 HEADING: %d checks, %d failed" % [checks, failures])
    quit(0 if failures == 0 else 1)
