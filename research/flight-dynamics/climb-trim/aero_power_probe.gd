extends SceneTree

const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const Air = preload("res://physics/air_data.gd")
const Aero = preload("res://physics/aero.gd")
const AD = preload("res://physics/aircraft_data.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")

func _initialize() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 20261013
    var local_pos := 0.0
    var local_max := 0.0
    var local_count := 0
    var global_pos := 0.0
    var global_max := 0.0
    var global_count := 0
    var local_worst := ""
    var global_worst := ""
    for id in Catalog.flyable_ids():
        var result := AD.load_file(Catalog.entry(id).data)
        if not result.ok:
            printerr("load failed ", id, " ", result.errors)
            continue
        var model: Dictionary = result.model.duplicate(true)
        # Exclude an explicitly modeled airfoil pitching couple; test flow work of force-only strip/tail loads.
        model.surfaces.wing_cm_ac = 0.0
        var d := {aileron_right=0.0, aileron_left=0.0, elevator=0.0, rudder=0.0}
        for sample in 4000:
            var vel := M.v3(rng.randf_range(-40.0, 40.0), rng.randf_range(-12.0, 12.0), rng.randf_range(-25.0, 25.0))
            var rates := M.v3(rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0))
            var s := RB.make_state(M.v3(0.0,0.0,-20.0), vel, M.q_identity(), rates)
            var air := Air.compute(s, M.v3(0.0,0.0,0.0))
            var f := Aero._local_loads(s, air, d, model, Air.RHO_SEA_LEVEL)
            var power := f[0]*vel[0]+f[1]*vel[1]+f[2]*vel[2]+f[3]*rates[0]+f[4]*rates[1]+f[5]*rates[2]
            local_count += 1
            if power > local_max:
                local_max = power
                local_worst = "%s sample=%d v=%s omega=%s loads=%s" % [id,sample,vel,rates,f]
            if power > 1e-8:
                local_pos += 1

            # Isolate global coefficient rate derivatives by subtracting zero-rate loads at identical air data.
            var s0 := RB.make_state(M.v3(0.0,0.0,-20.0), vel, M.q_identity(), M.v3(0.0,0.0,0.0))
            var air0 := Air.compute(s0, M.v3(0.0,0.0,0.0))
            var fr := Aero._global_loads(s, air, d, model, Air.RHO_SEA_LEVEL)
            var f0 := Aero._global_loads(s0, air0, d, model, Air.RHO_SEA_LEVEL)
            var delta_power := (fr[0]-f0[0])*vel[0]+(fr[1]-f0[1])*vel[1]+(fr[2]-f0[2])*vel[2] \
                +(fr[3]-f0[3])*rates[0]+(fr[4]-f0[4])*rates[1]+(fr[5]-f0[5])*rates[2]
            global_count += 1
            if delta_power > global_max:
                global_max = delta_power
                global_worst = "%s sample=%d v=%s omega=%s dF=%s,%s,%s dM=%s,%s,%s" % [id,sample,vel,rates,fr[0]-f0[0],fr[1]-f0[1],fr[2]-f0[2],fr[3]-f0[3],fr[4]-f0[4],fr[5]-f0[5]]
            if delta_power > 1e-8:
                global_pos += 1
    print("LOCAL_FORCE_POWER positive=%d/%d max=%.12f worst=%s" % [local_pos,local_count,local_max,local_worst])
    print("GLOBAL_RATE_INCREMENT_POWER positive=%d/%d max=%.12f worst=%s" % [global_pos,global_count,global_max,global_worst])
    quit(0)
