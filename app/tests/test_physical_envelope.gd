# D9-R1/R2: independent total-power and reverse-flow seam regression.
# Neutral fixed surfaces, no wind/propulsion: F dot v + M dot omega must not be positive.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const ZERO := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}

func evaluate(model: Dictionary, alpha_deg: float, p: float, r: float) -> Dictionary:
	var a := deg_to_rad(alpha_deg)
	var state := RB.make_state(M.v3(0, 0, -100), M.v3(15*cos(a), 0, 15*sin(a)), M.q_identity(), M.v3(p, 0, r))
	var air := Air.compute(state, M.v3(0, 0, 0))
	var c := Aero.coefficients(air, M.v3(p, 0, r), ZERO, model.aero, model.envelope)
	var loads := Aero.loads(state, air, ZERO, model, Air.RHO_SEA_LEVEL)
	var power := loads[0]*state[3] + loads[2]*state[5] + loads[3]*p + loads[5]*r
	return {alpha_deg = alpha_deg, p_rad_s = p, r_rad_s = r, CD = c.CD, aero_power_W = power, loads = Array(loads)}

func _initialize() -> void:
	var model: Dictionary = AD.load_file(Scenarios.AIRCRAFT).model
	var min_drag := {CD = 1e30}
	var max_power := {aero_power_W = -1e30}
	var count := 0
	var negative_drag := 0
	var positive_power := 0
	var positive_forward := []
	for alpha in range(-180, 181, 10):
		for p in [-10.0, -5.0, 0.0, 5.0, 10.0]:
			for r in [-10.0, -5.0, 0.0, 5.0, 10.0]:
				var result := evaluate(model, alpha, p, r)
				count += 1
				if result.CD < min_drag.CD:
					min_drag = result
				if result.aero_power_W > max_power.aero_power_W:
					max_power = result
				negative_drag += int(result.CD < 0.0)
				positive_power += int(result.aero_power_W > 1e-6)
				if abs(alpha) <= 30 and result.aero_power_W > 1e-6:
					positive_forward.append(result)
	var isolated := []
	for conditions in [[150, -10, -5], [150, -10, 0], [150, 0, -5], [150, 0, 0], [-179.999, 0, 0], [179.999, 0, 0], [-179.999, 5, 0], [179.999, 5, 0]]:
		isolated.append(evaluate(model, conditions[0], conditions[1], conditions[2]))
	var seam := []
	for epsilon in [0.1, 0.01, 0.001]:
		var left := evaluate(model, -180.0 + epsilon, 5.0, 0.0)
		var right := evaluate(model, 180.0 - epsilon, 5.0, 0.0)
		seam.append({epsilon_deg = epsilon, delta_Fz_N = right.loads[2] - left.loads[2]})
	var result := {count = count, negative_drag_count = negative_drag, positive_power_count = positive_power, positive_forward = positive_forward, min_drag = min_drag, max_power = max_power, isolated = isolated, reverse_flow_seam = seam}
	print("passive neutral aero: %d / %d states add energy; worst %.3f W" % [positive_power, count, max_power.aero_power_W])
	var seam_ok := absf(seam[-1].delta_Fz_N) < 0.1 and absf(seam[-1].delta_Fz_N) < 0.02 * absf(seam[0].delta_Fz_N)
	print("continuity across reversed flow: ", "PASS" if seam_ok else "FAIL")
	# Independent seeded sphere and transition samples: asymmetric controls and nonzero q
	# catch failures hidden by the original alpha/p/r-only probe. Fixed surfaces, no propeller.
	var rng := RandomNumberGenerator.new()
	rng.seed = 60106
	var fuzz_positive := 0
	var finite := true
	for i in 5000:
		var v := rng.randf_range(0.0, 40.0) if i % 11 != 0 else 0.0
		var a := rng.randf_range(-PI, PI) if i % 2 == 0 else deg_to_rad(rng.randf_range(-15, 15))
		var b := rng.randf_range(-PI/2, PI/2) if i % 2 == 0 else deg_to_rad(rng.randf_range(-15, 15))
		var rates := M.v3(rng.randf_range(-25, 25), rng.randf_range(-25, 25), rng.randf_range(-25, 25))
		var state := RB.make_state(M.v3(0,0,-100), M.v3(v*cos(a)*cos(b), v*sin(b), v*sin(a)*cos(b)), M.q_identity(), rates)
		var d := {elevator=rng.randf_range(-1,1)*model.controls.throw_rad.elevator,
			aileron_right=rng.randf_range(-1,1)*model.controls.throw_rad.aileron,
			aileron_left=rng.randf_range(-1,1)*model.controls.throw_rad.aileron,
			rudder=rng.randf_range(-1,1)*model.controls.throw_rad.rudder}
		var loads := Aero.loads(state, Air.compute(state, M.v3(0,0,0)), d, model, Air.RHO_SEA_LEVEL)
		var power := 0.0
		for k in 3:
			power += loads[k]*state[3+k] + loads[3+k]*rates[k]
		for value in loads:
			finite = finite and is_finite(value)
		fuzz_positive += int(power > 1e-7)
	print("seeded fixed-control envelope: %d/5000 positive power; finite=%s" % [fuzz_positive, finite])
	# Isolate the rudder force by differencing opposite deflections at a stalled-wing state.
	# Both evaluations use the local regime; unchanged wing/horizontal-tail loads cancel.
	var state := RB.make_state(M.v3(0,0,-100), M.v3(12,0,7), M.q_identity(), M.v3(0,0,0))
	var right := ZERO.duplicate()
	var left := ZERO.duplicate()
	right.rudder = -0.1
	left.rudder = 0.1
	var air := Air.compute(state, M.v3(0,0,0))
	var a := Aero.loads(state, air, right, model, Air.RHO_SEA_LEVEL)
	var b := Aero.loads(state, air, left, model, Air.RHO_SEA_LEVEL)
	var fy := a[1]-b[1]
	var fin: Dictionary = model.surfaces.vertical
	var lever_ok := absf(fy) > 0.01 		and absf((a[5]-b[5])/fy + fin.position[0]-model.cg_le[0]) < 1e-10 		and absf((a[3]-b[3])/fy - fin.position[2]+model.cg_le[2]) < 1e-10
	print("rudder force and moments share the declared physical lever: ", lever_ok)
	var out := OS.get_environment("FLIGHT_AUDIT_OUT")
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		var file := FileAccess.open(out.path_join("envelope.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t") + "\n")
	quit(1 if positive_power > 0 or fuzz_positive > 0 or not finite or not seam_ok or not lever_ok else 0)
