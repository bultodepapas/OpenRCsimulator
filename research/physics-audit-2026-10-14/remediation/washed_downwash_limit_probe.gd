## Read-only adversarial probe of P51-22's proposed free-speed downwash denominator.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

func _initialize() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if output.is_empty():
		quit(2)
		return
	var loaded: Dictionary = AD.load_file("res://data/aircraft/p51d_mustang_120.json")
	if not loaded.ok:
		printerr(loaded.errors)
		quit(2)
		return
	var model: Dictionary = loaded.model
	var tail: Dictionary = model.surfaces.horizontal
	var arm := Aero._arm(tail.position, model.cg_le)
	var d := {elevator = 0.0, aileron_left = 0.0, aileron_right = 0.0, rudder = 0.0}
	var washed_zero := M.v3(20.0, 0.0, 0.0)
	var zero_load := Aero._tail_surface_from_flow(washed_zero, arm, d, tail, model.surfaces,
		float(tail.area), false, 1.225, 0.0)
	var rows: Array = []
	for angle in [-5.0, 0.0, 5.0]:
		var alpha := deg_to_rad(angle)
		for speed in [1.0, 0.1, 0.01, 0.001, 0.0001, 0.000001, 0.00000001]:
			var flow := M.v3(speed * cos(alpha), 0.0, speed * sin(alpha))
			var state := RB.make_state(M.v3(0.0, 0.0, -500.0), flow, M.q_identity(), M.v3(0.0, 0.0, 0.0))
			var air := Air.compute(state, M.v3(0.0, 0.0, 0.0), 1.225)
			var wake := Aero.wing_wake_velocity(state, air, d, model)
			var washed_flow := M.add(flow, washed_zero)
			var current := Aero._tail_surface_from_flow(washed_flow, arm, d, tail, model.surfaces,
				float(tail.area), false, 1.225, wake)
			var free_plane := sqrt(flow[0] * flow[0] + flow[2] * flow[2])
			var held_angle := Aero.downwash_angle(wake, float(tail.downwash_per_cl), free_plane)
			# Compose the proposed effective angle explicitly; no production patch or frozen oracle is edited.
			var effective := wrapf(atan2(washed_flow[2], washed_flow[0]) - held_angle + float(tail.free_incidence), -PI, PI)
			var cl := Aero._tail_curve(effective, float(tail.free_slope), model.surfaces)
			var cd: float = model.surfaces.tail_CD0 + model.surfaces.tail_k * cl * cl \
				+ model.surfaces.tail_CD90 * sin(effective) * sin(effective)
			var proposed := Aero._surface_with_flow(washed_flow, arm, float(tail.area), cl, cd, false, 1.225)
			rows.append({speed_mps = speed, approach_alpha_deg = angle, wake_mps = wake,
				free_angle_rad = held_angle, current_loads = Array(current), proposed_loads = Array(proposed),
				current_force_delta_n = M.norm(M.sub(current, zero_load)),
				proposed_force_delta_n = M.norm(M.sub(proposed, zero_load)),
				current_pitch_delta_nm = current[4] - zero_load[4], proposed_pitch_delta_nm = proposed[4] - zero_load[4]})
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify({aircraft_id = model.id, wash_mps = 20.0, rho_kg_m3 = 1.225,
		purpose = "Counterexample to proposed free-speed angle; does not validate the current wing/propeller interaction",
		zero_flow_tail_loads = Array(zero_load), tail_area_m2 = tail.area, rows = rows}, "  ", true, true) + "\n")
	file.close()
	print("Recorded ", rows.size(), " approach states; no production source changed")
	quit()
