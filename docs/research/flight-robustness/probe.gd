# Diagnostic probes only. Production model and files stay unchanged.
# $(app/get-godot.sh) --headless --path app --script "$PWD/docs/research/flight-robustness/probe.gd"
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
	var result := {count = count, negative_drag_count = negative_drag, positive_power_count = positive_power, positive_forward = positive_forward, min_drag = min_drag, max_power = max_power, isolated = isolated}
	print("ENVELOPE_PROBE ", JSON.stringify(result))
	var out := OS.get_environment("FLIGHT_AUDIT_OUT")
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		var file := FileAccess.open(out.path_join("envelope.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t") + "\n")
	quit(1 if positive_power > 0 else 0)
