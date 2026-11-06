# Bounded observation: stock whole-polar progression versus no-progression diagnostic.
# This records the current law and a geometric flat-plate limit; it is not a repair regression.
extends SceneTree
const AD = preload("res://physics/aircraft_data.gd")
const Air = preload("res://physics/air_data.gd")
const Aero = preload("res://physics/aero.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const ZERO = {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
const RHO = 1.225
var checks := 0
var failures := 0

func check(label: String, ok: bool) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAIL: ", label)

func state(v: PackedFloat64Array, p: float) -> PackedFloat64Array:
    return RB.make_state(M.v3(0,0,-100),v,M.q_identity(),M.v3(p,0,0))

func case(model: Dictionary, baseline: Dictionary, v: PackedFloat64Array, p: float) -> Dictionary:
    var s=state(v,p)
    var air=Air.compute(s,M.v3(0,0,0),RHO)
    var current=Aero.loads(s,air,ZERO,model,RHO)
    var diagnostic=Aero.loads(s,air,ZERO,baseline,RHO)
    var rows=Aero.wing_strip_loads(s,air,ZERO,model,RHO)
    var ref_rows=Aero.wing_strip_loads(s,air,ZERO,baseline,RHO)
    var wing_yaw=0.0
    var reference_yaw=0.0
    for i in rows.size():
        wing_yaw += float(rows[i].moment_body_nm[2])
        reference_yaw += float(ref_rows[i].moment_body_nm[2])
    return {current=current, diagnostic=diagnostic, rows=rows, reference_rows=ref_rows,
        selector=Aero.local_flow_weight(s,air,ZERO,model), wing_yaw=wing_yaw, reference_yaw=reference_yaw,
        wake=Aero.wing_wake_velocity(s,air,ZERO,model), reference_wake=Aero.wing_wake_velocity(s,air,ZERO,baseline)}

func _initialize() -> void:
    var loaded=AD.load_file("res://data/aircraft/gp_extra_300s_60.json")
    check("Extra data loaded", bool(loaded.get("ok",false)))
    if not loaded.get("ok",false):
        printerr(str(loaded.get("errors",[])))
        quit(1)
        return
    var model: Dictionary=loaded.model
    var baseline: Dictionary=model.duplicate(true)
    baseline.envelope.wing_polar.erase("strip_factor")
    var factors: PackedFloat64Array=model.envelope.wing_polar.strip_factor
    check("stock six progression factors enabled", factors.size()==6 and factors[0]>1.0 and factors[2]<1.0)
    var zero=case(model,baseline,M.v3(0,0,20),0.0)
    var pos=case(model,baseline,M.v3(0,0,20),2.0)
    var neg=case(model,baseline,M.v3(0,0,20),-2.0)
    var minus_alpha=case(model,baseline,M.v3(0,0,-20),0.0)
    check("positive and negative 90-degree cases are local", zero.selector==1.0 and minus_alpha.selector==1.0)
    var cl_expected := PackedFloat64Array([-0.0219318219950382,-0.0460464259468821,0.0694833627756922,0.0694833627756922,-0.0460464259468821,-0.0219318219950382])
    var all_geo := true
    var exact_zero_diagnostic := true
    var actual_character := true
    for i in factors.size():
        var row: Dictionary=zero.rows[i]
        var ref: Dictionary=zero.reference_rows[i]
        all_geo = all_geo and absf(float(row.alpha_geometric_rad)-PI/2.0)<1e-14 and absf(float(row.stall_weight)-1.0)<1e-14
        exact_zero_diagnostic = exact_zero_diagnostic and absf(float(ref.cl))<1e-12 \
            and absf(float(ref.cd)-(float(model.envelope.wing_polar.cd0)+float(model.envelope.wing_polar.cd90)))<1e-12
        actual_character = actual_character and absf(float(row.cl)-cl_expected[i])<1e-9 and absf(float(row.cl))>0.015
    check("all six stock stations have geometric 90-degree incidence and zero attached fraction", all_geo)
    check("geometric flat-plate diagnostic gives zero CL and exact CD90 endpoint", exact_zero_diagnostic)
    check("stock factors yield nonzero, signed per-station CL at 90 degrees", actual_character)
    var reverse_signs := true
    for i in factors.size():
        reverse_signs = reverse_signs and signf(float(minus_alpha.rows[i].cl)) == -signf(float(zero.rows[i].cl))
    check("negative incidence reverses every 90-degree station CL sign", reverse_signs)
    var delta_pos=float(pos.current[5])-float(pos.diagnostic[5])
    var delta_neg=float(neg.current[5])-float(neg.diagnostic[5])
    check("symmetric p produces opposite total-yaw differences", absf(delta_pos+delta_neg)<1e-11)
    check("nonzero roll exposes about 0.107 N m yaw difference", absf(delta_pos-0.1069608902928)<1e-8)
    check("wing-only yaw difference accounts for total difference at positive roll", absf(delta_pos-(pos.wing_yaw-pos.reference_yaw))<1e-10)
    check("wing-only yaw difference accounts for total difference at negative roll", absf(delta_neg-(neg.wing_yaw-neg.reference_yaw))<1e-10)
    check("zero-roll case has no artificial net wing yaw", absf(zero.wing_yaw)<1e-10 and absf(zero.reference_yaw)<1e-10)
    check("opposite p gives odd yaw with neutral surfaces", absf(float(pos.current[5])+float(neg.current[5]))<1e-10)
    var att_pos=case(model,baseline,M.v3(20,0,0),2.0)
    var att_neg=case(model,baseline,M.v3(20,0,0),-2.0)
    check("forward level +p full loads byte identical", att_pos.current==att_pos.diagnostic)
    check("forward level -p full loads byte identical", att_neg.current==att_neg.diagnostic)
    check("loaded source model was not changed by diagnostic", model.envelope.wing_polar.has("strip_factor") and not baseline.envelope.wing_polar.has("strip_factor"))
    print(JSON.stringify({source_model="gp_extra_300s_60", speed_mps=20.0, density=RHO,
        factors=Array(factors), alpha90_zero_actual=Array(zero.current), alpha90_zero_diagnostic=Array(zero.diagnostic),
        alpha90_p2_actual=Array(pos.current), alpha90_p2_diagnostic=Array(pos.diagnostic),
        alpha90_m2_actual=Array(neg.current), alpha90_m2_diagnostic=Array(neg.diagnostic),
        p2_wing_yaw=pos.wing_yaw, p2_diagnostic_wing_yaw=pos.reference_yaw,
        wake=zero.wake, diagnostic_wake=zero.reference_wake,
        checks=checks, failures=failures}))
    print("PROGRESSION_OBSERVATION_COMPLETE: %d checks, %d failed" % [checks,failures])
    quit(1 if failures else 0)
