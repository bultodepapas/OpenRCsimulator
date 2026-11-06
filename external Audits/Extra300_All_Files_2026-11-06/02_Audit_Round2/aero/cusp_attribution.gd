extends SceneTree
const AD=preload("res://physics/aircraft_data.gd")
const Air=preload("res://physics/air_data.gd")
const Aero=preload("res://physics/aero.gd")
const Alt=preload("res://physics/aero_fixed_normalizer_probe.gd")
const M=preload("res://physics/math3d.gd")
const RB=preload("res://physics/rigid_body.gd")
const D={elevator=0.0,aileron_left=0.0,aileron_right=0.0,rudder=0.0}
func value(model:Dictionary, alpha_deg:float, p:float) -> Dictionary:
    var a=deg_to_rad(alpha_deg)
    var s=RB.make_state(M.v3(0,0,-100),M.v3(20*cos(a),0,20*sin(a)),M.q_identity(),M.v3(p,0,0))
    var air=Air.compute(s,M.v3(0,0,0),1.225)
    return {"base":Array(Aero.loads(s,air,D,model,1.225)),"alt":Array(Alt.loads(s,air,D,model,1.225)),"blend":Aero.local_flow_weight(s,air,D,model)}
func _initialize():
    var o=AD.load_file("res://data/aircraft/gp_extra_300s_60.json")
    if not o.ok: print(o.errors); quit(1); return
    var out=[]
    for alpha in [14.0,20.0]:
        var z=value(o.model,alpha,0.0)
        for h in [0.01,0.001,0.0001,0.00001]:
            var l=value(o.model,alpha,-h)
            var r=value(o.model,alpha,h)
            out.append({"alpha":alpha,"h":h,"base_left":(z.base[2]-l.base[2])/h,"base_right":(r.base[2]-z.base[2])/h,"alt_left":(z.alt[2]-l.alt[2])/h,"alt_right":(r.alt[2]-z.alt[2])/h,"zero_diff":z.base[2]-z.alt[2],"blend":z.blend})
    print(JSON.stringify(out))
    print("CUSP_ATTRIBUTION_COMPLETE")
    quit()
