extends SceneTree
const AD=preload("res://physics/aircraft_data.gd")
const Air=preload("res://physics/air_data.gd")
const Aero=preload("res://physics/aero.gd")
const M=preload("res://physics/math3d.gd")
const RB=preload("res://physics/rigid_body.gd")
const D={elevator=0.0,aileron_left=0.0,aileron_right=0.0,rudder=0.0}
func getrow(model:Dictionary,angle:float,p:float) -> Dictionary:
    var alpha=deg_to_rad(angle)
    var s=RB.make_state(M.v3(0,0,-100),M.v3(20*cos(alpha),0,20*sin(alpha)),M.q_identity(),M.v3(p,0,0))
    var air=Air.compute(s,M.v3(0,0,0))
    var flow=Aero._wing_flow(s,air,D,model)
    return {"loads":Array(Aero.loads(s,air,D,model,1.225)),"weights":Array(flow.sources),"max_speed":flow.reference_speed,"blend":Aero.local_flow_weight(s,air,D,model)}
func _initialize():
    var o=AD.load_file("res://data/aircraft/gp_extra_300s_60.json")
    if not o.ok:
        print(o.errors)
        quit(1)
        return
    var m=o.model
    var out=[]
    for alpha in [-19.0,-17.0,-15.0,-12.0,10.0,13.5,14.0,15.0,16.0,17.0,18.0,20.0]:
        var row={"alpha":alpha,"zero":getrow(m,alpha,0.0),"samples":[]}
        for h in [0.1,0.01,0.001,0.0001,0.00001,0.000001]:
            var neg=getrow(m,alpha,-h)
            var pos=getrow(m,alpha,h)
            row.samples.append({"h":h,"dFz_minus":(row.zero.loads[2]-neg.loads[2])/h,"dFz_plus":(pos.loads[2]-row.zero.loads[2])/h,"dMy_minus":(row.zero.loads[4]-neg.loads[4])/h,"dMy_plus":(pos.loads[4]-row.zero.loads[4])/h,"neg_blend":neg.blend,"pos_blend":pos.blend})
        out.append(row)
    print(JSON.stringify(out))
    print("CUSP_SCAN_COMPLETE")
    quit()
