extends SceneTree
const AD=preload("res://physics/aircraft_data.gd")
const Air=preload("res://physics/air_data.gd")
const Aero=preload("res://physics/aero.gd")
const M=preload("res://physics/math3d.gd")
const RB=preload("res://physics/rigid_body.gd")
const D={elevator=0.0,aileron_left=0.0,aileron_right=0.0,rudder=0.0}
func _initialize():
    var o=AD.load_file("res://data/aircraft/gp_extra_300s_60.json")
    if not o.ok: print(o.errors); quit(1); return
    var model=o.model
    var out=[]
    for alpha in [0.0,14.0,20.0]:
        for lateral in [-10.0,-5.0,0.0,2.0,5.0,10.0]:
            var a=deg_to_rad(alpha)
            var s=RB.make_state(M.v3(0,0,-100),M.v3(20*cos(a),lateral,20*sin(a)),M.q_identity(),M.v3(0,0,0))
            var air=Air.compute(s,M.v3(0,0,0),1.225)
            var f=Aero._wing_flow(s,air,D,model)
            var rows=Aero.wing_strip_loads(s,air,D,model,1.225)
            var wing=PackedFloat64Array([0,0,0,0,0,0])
            for row in rows:
                for i in 3:
                    wing[i]+=row.force_body_n[i]
                    wing[3+i]+=row.moment_body_nm[i]
            out.append({"alpha":alpha,"lateral":lateral,"sources":Array(f.sources),"plane_speeds":Array(f.speeds),"angles":Array(f.angles),"wing":Array(wing),"max_speed":f.reference_speed,"blend":Aero.local_flow_weight(s,air,D,model)})
    print(JSON.stringify(out))
    print("SPANFLOW_SCAN_COMPLETE")
    quit()
