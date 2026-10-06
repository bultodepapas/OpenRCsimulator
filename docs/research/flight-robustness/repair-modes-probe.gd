# Extract trim and linearized matrices for the post-repair modal check.
# Run from the repo root:
#   FLIGHT_REPAIR_MODES_OUT="$PWD/docs/research/flight-robustness/repair-modes-input.json" \
#     $(app/get-godot.sh) --headless --path app --script "$PWD/docs/research/flight-robustness/repair-modes-probe.gd"
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const FM := preload("res://physics/flight_modes.gd")
const L := preload("res://physics/linearize.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")

const SPEEDS := [10.0, 15.0, 20.0, 25.0]


func _initialize() -> void:
	var result := AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	if not result.ok:
		printerr("Aircraft load failed: %s" % result.errors)
		quit(2)
		return
	var model: Dictionary = result.model
	var rows: Array[Dictionary] = []
	for speed in SPEEDS:
		var mode: Dictionary = FM.analyze(model, speed)
		if not mode.ok:
			rows.append({"V_mps": speed, "ok": false, "message": mode.message})
			continue
		var trim: Dictionary = mode.trim
		var d := {elevator = trim.elevator, aileron_right = trim.aileron,
			aileron_left = -trim.aileron, rudder = trim.rudder}
		var air := Air.compute(trim.state, PackedFloat64Array([0.0, 0.0, 0.0]))
		rows.append({
			"V_mps": speed,
			"ok": true,
			"alpha_deg": rad_to_deg(trim.alpha),
			"beta_deg": rad_to_deg(trim.beta),
			"elevator_deg": rad_to_deg(trim.elevator),
			"aileron_deg": rad_to_deg(trim.aileron),
			"rudder_deg": rad_to_deg(trim.rudder),
			"rpm": trim.rpm,
			"local_flow_weight_at_trim": Aero.local_flow_weight(trim.state, air, d, model),
			"projected_spiral_tau_s": mode.spiral_tau,
			"projected_lateral_jacobian": mode.projected_jacobians.lateral,
			"projected_lateral_eigenvalues": _lateral_eigenvalues(mode.projected_jacobians.lateral),
			"full_jacobian": mode.full_jacobian,
			"rotor_momentum_body": Dynamics.rotor_momentum(model, trim.rpm),
		})
	var report := {
		"format": "openrc-flight-repair-modal-input v1",
		"godot": Engine.get_version_info(),
		"aircraft": model.id,
		"aircraft_json_sha256": FileAccess.get_sha256(ProjectSettings.globalize_path("res://data/aircraft/jensen_ugly_stik_60.json")),
		"aero_script_sha256": FileAccess.get_sha256(ProjectSettings.globalize_path("res://physics/aero.gd")),
		"flight_modes_script_sha256": FileAccess.get_sha256(ProjectSettings.globalize_path("res://physics/flight_modes.gd")),
		"Cnb_1_per_rad": model.aero.Cnb,
		"attached_oracle_limit_deg": rad_to_deg(model.surfaces.attached_limit),
		"wing_positive_stall_start_deg": rad_to_deg(model.envelope.a1),
		"wing_negative_stall_start_magnitude_deg": rad_to_deg(model.envelope.n1),
		"state_order": ["u_mps", "v_mps", "w_mps", "p_rad_s", "q_rad_s", "r_rad_s", "phi_rad", "theta_rad"],
		"linearization": "Dynamics.evaluate at level trim, frozen control angles; full 8-state Jacobian, with derived propeller rotor momentum",
		"rows": rows,
	}
	var serialized := JSON.stringify(report, "\t", true, true) + "\n"
	var out_path := OS.get_environment("FLIGHT_REPAIR_MODES_OUT")
	if out_path.is_empty():
		print(serialized)
	else:
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			printerr("Could not write %s (error %d)" % [out_path, FileAccess.get_open_error()])
			quit(3)
			return
		file.store_string(serialized)
		print("wrote %s" % out_path)
	quit()


func _lateral_eigenvalues(matrix: Array) -> Array:
	return L.eigenvalues(matrix)
