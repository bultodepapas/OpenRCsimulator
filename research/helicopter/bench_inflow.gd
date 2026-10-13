# HELI-09a diagnostic: batch-average target-law cost, not a whole rotorcraft tick.
# Run alone, using --path app --script ../research/helicopter/bench_inflow.gd.
extends SceneTree

const Inflow = preload("res://physics/rotorcraft/inflow.gd")
const CALLS_PER_BATCH: int = 500
const BATCHES: int = 20
var sink: float = 0.0


func _initialize() -> void:
	var rows: Array = []
	# Crossflow normalized by a convenient v_h=4 m/s, T/(2rhoA)=16.
	for fixture: Array in [["hover", 0.0, 0.0], ["forward_hover", 0.0, 2.0],
		["vrs_crossflow", -0.8, 0.5], ["windmill", -3.0, 0.2]]:
		for _warm: int in range(100):
			sink += Inflow.target(32.0 * PI, 1.0, 1.0, fixture[1] * 4.0, fixture[2] * 4.0).velocity
		var batch_us := PackedFloat64Array()
		for _batch: int in range(BATCHES):
			var begin: int = Time.get_ticks_usec()
			for _call: int in range(CALLS_PER_BATCH):
				var r: Dictionary = Inflow.target(32.0 * PI, 1.0, 1.0, fixture[1] * 4.0, fixture[2] * 4.0)
				if not r.ok:
					push_error("benchmark target refused valid fixture")
					quit(1)
					return
				sink += r.velocity
			batch_us.append(float(Time.get_ticks_usec() - begin) / float(CALLS_PER_BATCH))
		batch_us.sort()
		rows.append({"regime": fixture[0], "median_us_per_call": 0.5 * (batch_us[9] + batch_us[10]),
			"p95_batch_mean_us": batch_us[18], "samples": BATCHES, "calls_per_batch": CALLS_PER_BATCH})
	var result: Dictionary = {"format": "openrc-heli-inflow-bench-v1", "godot": Engine.get_version_info().string,
		"os": OS.get_name(), "cpu": OS.get_processor_name(), "rows": rows, "sink": sink,
		"scope": "isolated equilibrium target; batch averages, not individual-tick latency or HELI-09 acceptance"}
	print(JSON.stringify(result))
	quit(0)
