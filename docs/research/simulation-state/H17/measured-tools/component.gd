extends SceneTree
const AD = preload("res://physics/aircraft_data.gd")
const Air = preload("res://physics/air_data.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const Before = preload("res://physics/slipstream.gd")
const After = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/perf-pass4-20261019/candidate/physics/slipstream.gd")

func _initialize() -> void:
	var loaded: Dictionary = AD.load_file("res://data/aircraft/p51d_mustang_120.json")
	if not loaded.ok:
		quit(1)
		return
	var model: Dictionary = loaded.model
	var report := {complete = true, iterations = 2000, repeats = 10, cases = [], scope = "Direct Slipstream.loads CPU only"}
	var controls := {elevator = -0.02, aileron_right = 0.01, aileron_left = -0.01, rudder = 0.03}
	for item: Array in [["powered", PackedFloat64Array([28.0, 1.2, 1.5]), 5200.0],
			["static", PackedFloat64Array([0.0, 0.0, 0.0]), 5200.0],
			["wide sideslip", PackedFloat64Array([18.0, 12.0, 3.0]), 5200.0],
			["stopped", PackedFloat64Array([28.0, 1.2, 1.5]), 0.0]]:
		var state := RB.make_state(M.v3(0, 0, -100), item[1], M.q_identity(), M.v3(0.1, 0.05, 0.08))
		var air := Air.compute(state, M.v3(0, 0, 0), 1.225)
		var old: PackedFloat64Array = Before.loads(state, air, controls, model, item[2], 1.225, 1.5)
		var new: PackedFloat64Array = After.loads(state, air, controls, model, item[2], 1.225, 1.5)
		if old.to_byte_array() != new.to_byte_array():
			quit(1)
			return
		for warmup in 100:
			Before.loads(state, air, controls, model, item[2], 1.225, 1.5)
			After.loads(state, air, controls, model, item[2], 1.225, 1.5)
		var times: Array = [[], []]
		for pair in 10:
			for mode: int in ([0, 1] if pair % 2 == 0 else [1, 0]):
				var begin: int = Time.get_ticks_usec()
				if mode == 0:
					for index in 2000:
						Before.loads(state, air, controls, model, item[2], 1.225, 1.5)
				else:
					for index in 2000:
						After.loads(state, air, controls, model, item[2], 1.225, 1.5)
				times[mode].append(Time.get_ticks_usec() - begin)
		report.cases.append({label = item[0], before_usec = times[0], after_usec = times[1]})
	var output: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	print("component parity and benchmark PASS")
	quit(0)
