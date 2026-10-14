## AV-17-R2: fixed-input matrix. Run --headless --path app --script <absolute path> -- --out=<file>.
extends "res://tests/avanti_gamepad_base.gd"

func _initialize() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
		if arg == "--baseline": baseline = true
		if arg == "--physics-only": physics_only = true
		if arg == "--full": full_rates = true
	if output.is_empty() or hz not in [240, 480]:
		quit(2)
		return
	Engine.physics_ticks_per_second = hz
	var results: Array = []
	var complete := true
	for speed in [29.0, 45.0, 60.0]:
		for pitch in [-0.75, -0.5, 0.25, 0.5, 0.75, 1.0]:
			var row := run_case(speed, pitch)
			results.append(row)
			complete = complete and row.completed
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({hz = hz, baseline = baseline, physics_only = physics_only, full_rates = full_rates,
		completed = complete,
		sample_columns = ["t_s", "tas_mps", "alpha_deg", "beta_deg", "p_degps", "q_degps", "r_degps",
			"max_strip_separation", "roll_command", "pitch_command", "yaw_command", "elevator_deg", "throttle", "normal_g", "altitude_m"],
		cases = results}, "  ") + "\n")
	file.close()
	quit(0 if complete else 1)
