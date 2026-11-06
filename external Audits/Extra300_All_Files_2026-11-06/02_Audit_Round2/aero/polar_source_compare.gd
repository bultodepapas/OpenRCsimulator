extends SceneTree
const AD=preload("res://physics/aircraft_data.gd")
const Air=preload("res://physics/air_data.gd")
const Aero=preload("res://physics/aero.gd")
const Alt=preload("res://physics/aero_polar_probe.gd")
const M=preload("res://physics/math3d.gd")
const RB=preload("res://physics/rigid_body.gd")
const D={elevator=0.0,aileron_left=0.0,aileron_right=0.0,rudder=0.0}
func _initialize():
    var o=AD.load_file("res://data/aircraft/gp_extra_300s_60.json")
    if not o.ok:
        print(o.errors)
        quit(1)
        return
    var model=o.model
    var rows=[]
    for alpha in [-25.0,-20.0,-17.0,-15.0,-10.0,0.0,10.0,15.0,17.0,20.0,25.0]:
        for p in [-1.0,0.0,1.0]:
            var a=deg_to_rad(alpha)
            var s=RB.make_state(M.v3(0,0,-100),M.v3(20*cos(a),0,20*sin(a)),M.q_identity(),M.v3(p,0,0))
            var air=Air.compute(s,M.v3(0,0,0),1.225)
            var base=Aero.loads(s,air,D,model,1.225)
            var alt=Alt.loads(s,air,D,model,1.225)
            var delta=[]
            for i in 6:
                delta.append(alt[i]-base[i])
            var base_wake=Aero.wing_wake_velocity(s,air,D,model)
            var alt_wake=Alt.wing_wake_velocity(s,air,D,model)
            var baseflow=Aero._wing_flow(s,air,D,model)
            var altflow=Alt._wing_flow(s,air,D,model)
            var no_polar=model.duplicate(true)
            no_polar.envelope.erase("wing_polar")
            var nocontrol=var_to_bytes(Aero.loads(s,air,D,no_polar,1.225))==var_to_bytes(Alt.loads(s,air,D,no_polar,1.225))
            rows.append({"alpha":alpha,"p":p,"baseline":Array(base),"candidate":Array(alt),"delta":delta,"baseline_wake":base_wake,"candidate_wake":alt_wake,"baseline_sources":Array(baseflow.sources),"candidate_sources":Array(altflow.sources),"no_polar_byte_control":nocontrol})
    print(JSON.stringify(rows))
    print("POLAR_COMPARISON_COMPLETE")
    quit()
