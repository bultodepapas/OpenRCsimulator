# HELI-09c: isolated tail stage diagnostic. Run timings alone.
extends SceneTree

const Tail = preload("res://physics/rotorcraft/tail_rotor.gd")
const Fixture = preload("res://tests/test_heli_tail_rotor.gd")
const M = preload("res://physics/math3d.gd")
const BATCHES: int = 20
const CALLS_PER_BATCH: int = 500
var sink: float = 0.0


func _initialize() -> void:
	var model: Dictionary = Tail.prepare(Fixture.PARAMS).model
	var zero: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var rows: Array = []
	for fixture: Array in [["hover", M.v3(0.0, 0.0, 0.0), 0.1],
		["forward_wake", M.v3(15.0, 0.0, 0.0), 0.1],
		["reverse", M.v3(-10.0, 0.0, 0.0), 0.1],
		["capped", M.v3(0.0, 0.0, 0.0), 1.0]]:
		for _warm: int in range(100):
			sink += Tail.evaluate(model, 167.0, 4.2, fixture[1], zero, fixture[2], false).thrust_n
		var batch_us: PackedFloat64Array = PackedFloat64Array()
		for _batch: int in range(BATCHES):
			var start: int = Time.get_ticks_usec()
			for _call: int in range(CALLS_PER_BATCH):
				var result: Dictionary = Tail.evaluate(model, 167.0, 4.2, fixture[1], zero, fixture[2], false)
				if not result.ok:
					push_error("tail benchmark refused valid fixture")
					quit(1)
					return
				sink += result.thrust_n
			batch_us.append(float(Time.get_ticks_usec() - start) / float(CALLS_PER_BATCH))
		batch_us.sort()
		rows.append({"regime": fixture[0], "median_us_per_call": (batch_us[9] + batch_us[10]) / 2.0,
			"p95_batch_mean_us": batch_us[18], "batches": BATCHES, "calls_per_batch": CALLS_PER_BATCH})
	print(JSON.stringify({"format": "openrc-heli-tail-bench-v1", "godot": Engine.get_version_info().string,
		"os": OS.get_name(), "cpu": OS.get_processor_name(), "rows": rows, "sink": sink,
		"scope": "tail only; batch means, not individual ticks, complete-load budget or H15 acceptance"}))
	quit(0)
