extends "res://tests/avanti_rudder_base.gd"

func _initialize() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output=arg.trim_prefix("--out=")
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
		if arg.begins_with("--aircraft="): data_path=arg.trim_prefix("--aircraft=")
	if output.is_empty() or hz not in [240,480]:
		quit(2)
		return
	Engine.physics_ticks_per_second=hz
	var results := []
	var complete := true
	for speed in [29.0,45.0,60.0]:
		for yaw in [-1.0,-0.5,-0.25,0.25,0.5,1.0]:
			var row:=run_case(speed,yaw)
			results.append(row)
			complete=complete and row.completed
	var f:=FileAccess.open(output,FileAccess.WRITE)
	f.store_string(JSON.stringify({hz=hz,data_sha256=FileAccess.get_sha256(data_path),completed=complete,
		sample_columns=["t_s","V_mps","alpha_deg","beta_deg","p_degps","r_degps","heading_deg","track_deg",
		"conditioned_yaw","filtered_yaw","rudder_deg","throttle"],cases=results},"  ")+"\n")
	f.close()
	quit(0 if complete else 1)
