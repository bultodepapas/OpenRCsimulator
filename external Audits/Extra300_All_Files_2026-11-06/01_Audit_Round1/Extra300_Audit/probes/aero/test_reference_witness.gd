extends SceneTree
const AD = preload("res://physics/aircraft_data.gd")
const Air = preload("res://physics/air_data.gd")
const Aero = preload("res://physics/aero.gd")
const Dynamics = preload("res://physics/dynamics.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const D0 = {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
const DCTRL = {elevator = 0.02, aileron_right = -0.02, aileron_left = 0.02, rudder = 0.02}
const RHO = 1.225
const V = 20.0
var checks = 0
var failures = 0
func check(label:String, condition:bool, detail:String = ""):
    checks += 1
    print(("ok   " if condition else "FAIL ") + label + " " + detail)
    if not condition:
        failures += 1
func state(beta_deg:float, rates:PackedFloat64Array) -> PackedFloat64Array:
    var b = deg_to_rad(beta_deg)
    return RB.make_state(M.v3(0,0,-300), M.v3(V*cos(b),V*sin(b),0), M.q_identity(), rates)
func evaluate(model:Dictionary,s:PackedFloat64Array,d:Dictionary) -> Dictionary:
    var air = Air.compute(s,M.v3(0,0,0),RHO)
    var wake = Aero.wing_wake_velocity(s,air,d,model)
    var result = Dynamics._components_from_air(s,model,d,12000.0,RHO,air,wake,PackedFloat64Array())
    return {"aero":result.aero_loads,"total":result.loads,"prop":result.propulsion_loads,"blend":Aero.local_flow_weight(s,air,d,model,wake)}
func static_aero(model:Dictionary,rate_index:int,rate:float) -> Dictionary:
    var rates = M.v3(0,0,0)
    rates[rate_index] = rate
    var s = state(0.0,rates)
    var air = Air.compute(s,M.v3(0,0,0),RHO)
    return {"loads":Aero.loads(s,air,D0,model,RHO),"blend":Aero.local_flow_weight(s,air,D0,model)}
func _initialize():
    var obj = AD.load_file("res://data/aircraft/gp_extra_300s_60.json")
    check("stock Extra and wheel profile load",obj.ok,str(obj.get("errors",[])))
    if not obj.ok:
        quit(1)
        return
    var model:Dictionary = obj.model
    var S:float = model.reference.S
    var span:float = model.reference.b
    var chord:float = model.reference.c
    var x_arm:float = -(float(model.reference.arp_le[0])-float(model.cg_le[0]))
    var z_arm:float = -(float(model.reference.arp_le[2])-float(model.cg_le[2]))
    var fin_cyb:float = -float(model.surfaces.vertical.lift_slope)*float(model.surfaces.vertical.area)/S
    var fin_z:float = model.surfaces.vertical.position[2]
    var cg_z:float = model.cg_le[2]
    var arp_z:float = model.reference.arp_le[2]
    var excess:float = -z_arm/span*fin_cyb
    var generated_fin:float = fin_cyb*(fin_z-cg_z)/span
    var arp_fin:float = fin_cyb*(fin_z-arp_z)/span
    check("generated CG-arm fin Clbeta minus ARP-arm fin Clbeta matches transfer",absf((generated_fin-arp_fin)-excess)<1e-14)
    check("stock Extra identifies expected duplicated fin term",absf(excess-0.00620923294282455)<1e-13,"excess Clbeta %.12f"%excess)
    var diagnostic = model.duplicate(true)
    diagnostic.aero.Clb -= excess
    var zrates = M.v3(0,0,0)
    for controls in [D0,DCTRL]:
        var s = state(0.0,zrates)
        var orig = evaluate(model,s,controls)
        var alt = evaluate(diagnostic,s,controls)
        check("zero beta selector stays attached",orig.blend==0.0 and alt.blend==0.0)
        check("zero beta: neutral or moved controls preserve every load exactly",orig.aero==alt.aero and orig.total==alt.total and orig.prop==alt.prop)
    var positive_delta = 0.0
    var negative_delta = 0.0
    for beta in [-5.0,5.0]:
        var s = state(beta,zrates)
        var orig = evaluate(model,s,D0)
        var alt = evaluate(diagnostic,s,D0)
        var delta:float = alt.total[3]-orig.total[3]
        if beta<0: negative_delta=delta
        else: positive_delta=delta
        var expected:float = -0.5*RHO*V*V*S*span*excess*deg_to_rad(beta)
        check("both sides stay on the attached oracle",orig.blend==0.0 and alt.blend==0.0,"beta %.1f"%beta)
        check("combined roll changes by the independently calculated fin transfer",absf(delta-expected)<1e-11,"beta %.1f delta %.12f expected %.12f"%[beta,delta,expected])
        var nonroll = true
        var other_sources = true
        for i in 6:
            if i != 3 and orig.total[i]!=alt.total[i]: nonroll=false
            if absf((alt.total[i]-alt.aero[i])-(orig.total[i]-orig.aero[i]))>1e-12: other_sources=false
        check("no change to the other five combined loads or propeller/wake contribution",nonroll and other_sources and orig.prop==alt.prop)
        check("roll delta belongs entirely to aerodynamic load",absf(delta-(alt.aero[3]-orig.aero[3]))<1e-13)
        print("ROLL_WITNESS beta=%s aero=%s diagnostic_aero=%s combined=%s diagnostic_combined=%s"%[beta,orig.aero[3],alt.aero[3],orig.total[3],alt.total[3]])
    check("roll deltas reverse exactly with sideslip",absf(positive_delta+negative_delta)<1e-13)
    # Datum-only diagnostic: the actual fuel/session path needs a separate accepted-stage test.
    # Keep alpha, beta, rates, coefficients and flow fixed; only the moment reference moves.
    var s_ref = state(5.0,zrates)
    var air_ref = Air.compute(s_ref,M.v3(0,0,0),RHO)
    var load_ref = Aero.loads(s_ref,air_ref,D0,model,RHO)
    var fixed_delta = Aero.loads(s_ref,air_ref,D0,diagnostic,RHO)[3]-load_ref[3]
    for direction in [-1.0,1.0]:
        var dx = 0.03*direction
        var dz = 0.02*direction
        var shifted = model.duplicate(true)
        shifted.cg_le[0] += dx
        shifted.cg_le[2] += dz
        var shifted_diagnostic = diagnostic.duplicate(true)
        shifted_diagnostic.cg_le[0] += dx
        shifted_diagnostic.cg_le[2] += dz
        var now = Aero.loads(s_ref,air_ref,D0,shifted,RHO)
        var amended = Aero.loads(s_ref,air_ref,D0,shifted_diagnostic,RHO)
        var cg_displacement = M.v3(-dx,0.0,-dz)
        var transfer = M.cross(cg_displacement,M.v3(load_ref[0],load_ref[1],load_ref[2]))
        var coherent = true
        for i in 3:
            if absf(now[i]-load_ref[i])>1e-12 or absf(now[i+3]-(load_ref[i+3]-transfer[i]))>1e-12:
                coherent=false
        check("changed moment datum transforms the same force exactly",coherent,"direction %s"%direction)
        check("fin correction stays fixed while the datum moves",absf((amended[3]-now[3])-fixed_delta)<1e-12,"direction %s"%direction)
    var step = 1e-5
    for i in 3:
        var minus = static_aero(model,i,-step)
        var zero = static_aero(model,i,0.0)
        var plus = static_aero(model,i,step)
        check("positive and negative rate samples stay in the attached oracle",minus.blend==0.0 and zero.blend==0.0 and plus.blend==0.0,"axis %d"%i)
        var c:float = chord if i==1 else span
        var nondim_scale:float = 0.25*RHO*V*S*c*c
        var measured:float = (plus.loads[3+i]-minus.loads[3+i])/(2.0*step)/nondim_scale
        var expected:float = 0.0
        if i==0: expected=model.aero.Clp-z_arm/span*model.aero.CYp
        if i==1: expected=model.aero.Cmq+x_arm/chord*model.aero.CLq
        if i==2: expected=model.aero.Cnr+x_arm/span*model.aero.CYr
        check("rate derivative equals ARP coefficient plus force transfer",absf(measured-expected)<1e-8,"axis %d measured %.12f expected %.12f"%[i,measured,expected])
        check("signed rates are symmetric around zero-rate moment",absf(plus.loads[3+i]+minus.loads[3+i]-2.0*zero.loads[3+i])<1e-12,"axis %d"%i)
    print("%d checks, %d failed"%[checks,failures])
    if failures==0: print("REFERENCE_WITNESS_COMPLETE")
    quit(1 if failures else 0)
