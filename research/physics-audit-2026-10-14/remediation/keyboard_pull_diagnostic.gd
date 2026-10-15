## R11 diagnostic: existing AV-17 input fixture, explicit hold durations and rate.
extends "res://tests/avanti_pullup_base.gd"

func _initialize() -> void:
	var holds := PackedFloat64Array([2.0])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
		if arg.begins_with("--holds="):
			holds.clear()
			for item in arg.trim_prefix("--holds=").split(","):
				holds.append(float(item))
	if output.is_empty() or hz not in [240, 480] or holds.is_empty():
		quit(2)
		return
	Engine.physics_ticks_per_second = hz
	var cases: Array = []
	var complete := true
	for hold in holds:
		var result := run_case(45.0, hold)
		cases.append(result)
		complete = complete and result.completed
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify({hz = hz, cases = cases, complete = complete,
		sample_columns = ["t_s", "tas_mps", "alpha_deg", "gamma_deg", "body_normal_g",
			"virtual_pitch_stick", "elevator_deg", "max_strip_separation", "altitude_m"]}, "  ") + "\n")
	file.close()
	quit(0 if complete else 1)
