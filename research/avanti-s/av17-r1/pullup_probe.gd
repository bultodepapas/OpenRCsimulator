## AV-17-R1: reproducible real-keyboard dive-recovery measurements.
extends "res://tests/avanti_pullup_base.gd"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
		if arg.begins_with("--pitch-rate="): candidate_rate = float(arg.trim_prefix("--pitch-rate="))
		if arg == "--legacy-keyboard": legacy_keyboard = true
	if output.is_empty() or hz not in [240, 480]:
		quit(2)
		return
	Engine.physics_ticks_per_second = hz
	var recovery_only := "--recovery-only" in OS.get_cmdline_user_args()
	var results: Array = []
	for speed in [29.0, 45.0, 60.0]:
		for hold in ([-1.0] if recovery_only else [0.20, 0.35, 0.5, 0.75, 1.0, 2.0, -1.0]):
			results.append(run_case(speed, hold))
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({hz = hz, experimental_pitch_rate = candidate_rate, legacy_keyboard = legacy_keyboard,
		sample_columns = ["t_s","tas_mps","alpha_deg","gamma_deg","body_normal_g","virtual_pitch_stick","elevator_deg","max_strip_separation","altitude_m"],
		cases = results}, "  ") + "\n")
	file.close()
	quit()

