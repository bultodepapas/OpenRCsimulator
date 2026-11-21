extends SceneTree
const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const GE := preload("res://physics/ground_effect.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RHO := 1.225
func _initialize() -> void:
    var info := AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
    print("ADMISSION ",info.ok," errors ",info.errors)
    if not info.ok:
        quit(1)
        return
    var model: Dictionary = info.model
    print("DATA span=",model.reference.b," area=",model.reference.S," effect=",model.surfaces.wing_aileron_effectiveness," input=",info.input_identity)
    print("STATION ",model.envelope.station_ys," rows ",model.envelope.strip_row_sum," slope ",model.envelope.strip_slope)
    print("MAP ",model.envelope.induced_map)
    print("ARM ",Aero._arm(model.reference.arp_le, model.cg_le)," throws ",model.controls.throw_deg)
    for alpha_deg: float in [0.0, 3.0, 6.0]:
        var alpha := deg_to_rad(alpha_deg)
        var state := RB.make_state(M.v3(0,0,-0.4), M.v3(15.0*cos(alpha),0,15.0*sin(alpha)), M.q_identity(), M.v3(0,0,0))
        var air := Air.compute(state, M.v3(0,0,0), RHO)
        var factors := GE.factors(state, model, 0.0)
        print("CASE alpha=",alpha_deg," factors=",factors)
        for da_deg: float in [-2.0,0.0,2.0]:
            var da := deg_to_rad(da_deg)
            var d := {elevator=0.0,rudder=0.0,aileron_right=da,aileron_left=-da}
            var blend_ge := Aero.local_flow_weight(state,air,d,model,NAN,factors)
            var blend_free := Aero.local_flow_weight(state,air,d,model)
            var global_free := Aero._global_loads(state,air,d,model,RHO)
            var global_ge := Aero._global_loads(state,air,d,model,RHO,NAN,factors)
            var local_free := Aero._local_loads(state,air,d,model,RHO)
            var local_ge := Aero._local_loads(state,air,d,model,RHO,NAN,null,factors)
            var public_free := Aero.loads(state,air,d,model,RHO)
            var public_ge := Aero.loads(state,air,d,model,RHO,NAN,0.0)
            print("  d=",da_deg," blend=",blend_free,",",blend_ge," GF=",global_free[3]," GG=",global_ge[3]," LF=",local_free[3]," LG=",local_ge[3]," PF=",public_free[3]," PG=",public_ge[3])
    print("PROBE_COMPLETE")
    quit(0)
