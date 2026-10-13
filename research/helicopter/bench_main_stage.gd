# HELI-09b: standalone main-disc/wake stage cost. Run timings alone.
extends SceneTree

const Stage = preload("res://physics/rotorcraft/main_rotor_stage.gd")
const Rotor = preload("res://physics/rotorcraft/main_rotor.gd")
const Fixture = preload("res://tests/test_heli_main_rotor.gd")
const M = preload("res://physics/math3d.gd")
const CALLS_PER_BATCH: int = 500
const BATCHES: int = 20
var sink: float = 0.0


func _initialize() -> void:
	var model: Dictionary = Rotor.prepare(Fixture.PARAMS).model
	var state: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 4.2])
	var zero: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var maximum_thrust: float = model.thrust_coefficient_max * model.rho_kg_m3 * PI * 0.775 * 0.775 * (167.0 * 0.775) * (167.0 * 0.775)
	var vh: float = M.sqrt_(maximum_thrust / (2.0 * model.rho_kg_m3 * PI * 0.775 * 0.775))
	var rows: Array = []
	for fixture: Array in [["hover", M.v3(0.0, 0.0, 0.0)], ["forward", M.v3(15.0, 0.0, 0.0)],
		["vrs_crossflow", M.v3(0.5 * vh, 0.0, 1.3 * vh)], ["windmill", M.v3(0.2 * vh, 0.0, 3.0 * vh)]]:
		for _warm: int in range(100):
			sink += Stage.evaluate(model, state, 167.0, fixture[1], zero, 0.1, 0.0, 0.0, 0.1).rotor.thrust_n
		var batch_us := PackedFloat64Array()
		for _batch: int in range(BATCHES):
			var begin: int = Time.get_ticks_usec()
			for _call: int in range(CALLS_PER_BATCH):
				var response: Dictionary = Stage.evaluate(model, state, 167.0, fixture[1], zero, 0.1, 0.0, 0.0, 0.1)
				if not response.ok:
					push_error("benchmark stage refused valid fixture")
					quit(1)
					return
				sink += response.rotor.thrust_n
			batch_us.append(float(Time.get_ticks_usec() - begin) / float(CALLS_PER_BATCH))
		batch_us.sort()
		rows.append({"regime": fixture[0], "median_us_per_call": 0.5 * (batch_us[9] + batch_us[10]),
			"p95_batch_mean_us": batch_us[18], "samples": BATCHES, "calls_per_batch": CALLS_PER_BATCH})
	print(JSON.stringify({"format": "openrc-heli-main-stage-bench-v1", "godot": Engine.get_version_info().string,
		"os": OS.get_name(), "cpu": OS.get_processor_name(), "rows": rows, "sink": sink,
		"scope": "main-disc/wake only; batch averages, no drive/tail/airframe/body or event localization; not HELI-09 acceptance"}))
	quit(0)
