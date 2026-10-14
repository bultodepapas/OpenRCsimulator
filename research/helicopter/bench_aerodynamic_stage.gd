# HELI-09d: joint aerodynamic stage diagnostic, excluding drive/body/control.
extends SceneTree

const Stage = preload("res://physics/rotorcraft/aerodynamic_stage.gd")
const Main = preload("res://physics/rotorcraft/main_rotor.gd")
const Tail = preload("res://physics/rotorcraft/tail_rotor.gd")
const Airframe = preload("res://physics/rotorcraft/airframe.gd")
const MainFixture = preload("res://tests/test_heli_main_rotor.gd")
const TailFixture = preload("res://tests/test_heli_tail_rotor.gd")
const AirframeFixture = preload("res://tests/test_heli_airframe.gd")
const M = preload("res://physics/math3d.gd")
const BATCHES: int = 20
const CALLS_PER_BATCH: int = 500
var sink: float = 0.0


func _initialize() -> void:
	var main_model: Dictionary = Main.prepare(MainFixture.PARAMS).model
	var tail_model: Dictionary = Tail.prepare(TailFixture.PARAMS).model
	var airframe_model: Dictionary = Airframe.prepare(AirframeFixture.PARAMS).model
	var state: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 4.2])
	var zero: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var max_thrust: float = main_model.thrust_coefficient_max * main_model.rho_kg_m3 * PI * 0.775 * 0.775 * (167.0 * 0.775) * (167.0 * 0.775)
	var vh: float = M.sqrt_(max_thrust / (2.0 * main_model.rho_kg_m3 * PI * 0.775 * 0.775))
	var rows: Array = []
	for fixture: Array in [["hover", M.v3(0.0, 0.0, 0.0)], ["forward", M.v3(15.0, 0.0, 0.0)],
		["vrs_crossflow", M.v3(0.5 * vh, 0.0, 1.3 * vh)], ["windmill", M.v3(0.2 * vh, 0.0, 3.0 * vh)]]:
		for _warm: int in range(100):
			sink += Stage.evaluate(main_model, tail_model, airframe_model, state, 167.0, fixture[1], zero, 0.1, 0.0, 0.0, 0.1, 0.1, 0.2).main_rotor.thrust_n
		var batch_us: PackedFloat64Array = PackedFloat64Array()
		for _batch: int in range(BATCHES):
			var start: int = Time.get_ticks_usec()
			for _call: int in range(CALLS_PER_BATCH):
				var response: Dictionary = Stage.evaluate(main_model, tail_model, airframe_model, state, 167.0, fixture[1], zero, 0.1, 0.0, 0.0, 0.1, 0.1, 0.2)
				if not response.ok:
					push_error("aerodynamic stage benchmark refused valid fixture")
					quit(1)
					return
				sink += response.main_rotor.thrust_n
			batch_us.append(float(Time.get_ticks_usec() - start) / float(CALLS_PER_BATCH))
		batch_us.sort()
		rows.append({"regime": fixture[0], "median_us_per_call": 0.5 * (batch_us[9] + batch_us[10]),
			"p95_batch_mean_us": batch_us[18], "batches": BATCHES, "calls_per_batch": CALLS_PER_BATCH})
	print(JSON.stringify({"format": "openrc-heli-aerodynamic-stage-bench-v1", "godot": Engine.get_version_info().string,
		"os": OS.get_name(), "cpu": OS.get_processor_name(), "rows": rows, "sink": sink,
		"scope": "joint aerodynamics only; batch means, no drive/body/control/event localization; not HELI-09 acceptance"}))
	quit(0)
