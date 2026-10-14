# HELI-09: paired fixed-state comparison of the safe and prepared aero paths.
# Timing uses one Godot process and the same hover-stage payload for both paths.
extends SceneTree

const Stage = preload("res://physics/rotorcraft/aerodynamic_stage.gd")
const MainStage = preload("res://physics/rotorcraft/main_rotor_stage.gd")
const Main = preload("res://physics/rotorcraft/main_rotor.gd")
const Tail = preload("res://physics/rotorcraft/tail_rotor.gd")
const Airframe = preload("res://physics/rotorcraft/airframe.gd")
const MainFixture = preload("res://tests/test_heli_main_rotor.gd")
const TailFixture = preload("res://tests/test_heli_tail_rotor.gd")
const AirframeFixture = preload("res://tests/test_heli_airframe.gd")
var state: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 1.0])
var air: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var rates: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
const OMEGA: float = 167.0
const COLLECTIVE: float = 0.09624751257538011
const FLOW_FLOOR: float = 0.1
const FIN_WAKE_FRACTION: float = 0.2
const ROUNDS: int = 9
const ITERATIONS: int = 2000

var main_model: Dictionary
var tail_model: Dictionary
var airframe_model: Dictionary
var context: Dictionary
var safe_samples: Array[float] = []
var fast_samples: Array[float] = []
var main_safe_samples: Array[float] = []
var main_fast_samples: Array[float] = []
var tail_safe_samples: Array[float] = []
var tail_fast_samples: Array[float] = []
var airframe_safe_samples: Array[float] = []
var airframe_fast_samples: Array[float] = []
var safe_checksum: float = 0.0
var fast_checksum: float = 0.0
var failed: bool = false


func _initialize() -> void:
	main_model = Main.prepare(MainFixture.PARAMS).model
	tail_model = Tail.prepare(TailFixture.PARAMS).model
	airframe_model = Airframe.prepare(AirframeFixture.PARAMS).model
	var prepared: Dictionary = Stage.prepare(main_model, tail_model, airframe_model,
		FLOW_FLOOR, FIN_WAKE_FRACTION, -1.0, 1.0, 0.0)
	if not prepared.ok:
		push_error("HELI-09 benchmark could not prepare its fixed model")
		quit(1)
	context = prepared.context
	# Warm both APIs before the first timed pair.
	for index: int in range(400):
		var safe: Dictionary = _safe()
		var fast: Dictionary = _fast()
		if not safe.ok or not fast.ok or safe != fast:
			push_error("HELI-09 benchmark warmup parity failed")
			quit(1)
	for round_index: int in range(ROUNDS):
		if round_index % 2 == 0:
			safe_samples.append(_time_safe())
			fast_samples.append(_time_fast())
			main_safe_samples.append(_time_main(false))
			main_fast_samples.append(_time_main(true))
			tail_safe_samples.append(_time_tail(false))
			tail_fast_samples.append(_time_tail(true))
			airframe_safe_samples.append(_time_airframe(false))
			airframe_fast_samples.append(_time_airframe(true))
		else:
			fast_samples.append(_time_fast())
			safe_samples.append(_time_safe())
			main_fast_samples.append(_time_main(true))
			main_safe_samples.append(_time_main(false))
			tail_fast_samples.append(_time_tail(true))
			tail_safe_samples.append(_time_tail(false))
			airframe_fast_samples.append(_time_airframe(true))
			airframe_safe_samples.append(_time_airframe(false))
	if failed:
		quit(1)
	safe_samples.sort()
	fast_samples.sort()
	main_safe_samples.sort()
	main_fast_samples.sort()
	tail_safe_samples.sort()
	tail_fast_samples.sort()
	airframe_safe_samples.sort()
	airframe_fast_samples.sort()
	var middle: int = int(safe_samples.size() / 2)
	var safe_median: float = safe_samples[middle]
	var fast_median: float = fast_samples[middle]
	var report: Dictionary = {
		"format": "openrc-heli-aero-performance-v1",
		"godot": Engine.get_version_info().string,
		"os": OS.get_name(),
		"processor": OS.get_processor_name(),
		"scenario": "hover compact payload",
		"diagnostics": false,
		"rounds": ROUNDS,
		"evaluations_per_round": ITERATIONS,
		"safe_samples_us_per_evaluation": safe_samples,
		"fast_samples_us_per_evaluation": fast_samples,
		"safe_median_us_per_evaluation": safe_median,
		"fast_median_us_per_evaluation": fast_median,
		"speedup": safe_median / fast_median if fast_median > 0.0 else 0.0,
		"component_medians_us_per_evaluation": {
			"main_stage_safe": main_safe_samples[middle],
			"main_stage_prepared": main_fast_samples[middle],
			"tail_safe": tail_safe_samples[middle],
			"tail_prepared": tail_fast_samples[middle],
			"airframe_safe": airframe_safe_samples[middle],
			"airframe_prepared": airframe_fast_samples[middle],
		},
		"safe_checksum": safe_checksum,
		"fast_checksum": fast_checksum,
	}
	var json: String = JSON.stringify(report, "\t") + "\n"
	var output_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_path = arg.substr(9)
	if not output_path.is_empty():
		var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			push_error("HELI-09 benchmark cannot write %s" % output_path)
			quit(1)
		file.store_string(json)
	print(json)
	quit(0)


func _safe() -> Dictionary:
	return Stage.evaluate(main_model, tail_model, airframe_model, state, OMEGA, air, rates,
		COLLECTIVE, 0.01, -0.01, 0.1, FLOW_FLOOR, FIN_WAKE_FRACTION, -1.0, 1.0, 0.0, false)


func _fast() -> Dictionary:
	return Stage.fast_evaluate(context, state, OMEGA, air, rates,
		COLLECTIVE, 0.01, -0.01, 0.1, false)


func _time_safe() -> float:
	var checksum: float = 0.0
	var started: int = Time.get_ticks_usec()
	for index: int in range(ITERATIONS):
		var result: Dictionary = _safe()
		if not result.ok:
			failed = true
			break
		checksum += result.loads[2]
	safe_checksum += checksum
	return float(Time.get_ticks_usec() - started) / float(ITERATIONS)


func _time_fast() -> float:
	var checksum: float = 0.0
	var started: int = Time.get_ticks_usec()
	for index: int in range(ITERATIONS):
		var result: Dictionary = _fast()
		if not result.ok:
			failed = true
			break
		checksum += result.loads[2]
	fast_checksum += checksum
	return float(Time.get_ticks_usec() - started) / float(ITERATIONS)


func _time_main(prepared: bool) -> float:
	var checksum: float = 0.0
	var started: int = Time.get_ticks_usec()
	for index: int in range(ITERATIONS):
		var result: Dictionary = MainStage._evaluate_prepared(main_model, state, OMEGA, air, rates,
			COLLECTIVE, 0.01, -0.01, FLOW_FLOOR, -1.0, 1.0, 0.0, false) if prepared else MainStage.evaluate(
			main_model, state, OMEGA, air, rates, COLLECTIVE, 0.01, -0.01, FLOW_FLOOR, -1.0, 1.0, 0.0, false)
		if not result.ok:
			failed = true
			break
		checksum += result.loads[2]
	return float(Time.get_ticks_usec() - started) / float(ITERATIONS)


func _time_tail(prepared: bool) -> float:
	var checksum: float = 0.0
	var started: int = Time.get_ticks_usec()
	for index: int in range(ITERATIONS):
		var result: Dictionary = Tail._evaluate_prepared(tail_model, OMEGA, state[2], air, rates, 0.1, false) if prepared else Tail.evaluate(
			tail_model, OMEGA, state[2], air, rates, 0.1, false)
		if not result.ok:
			failed = true
			break
		checksum += result.loads[1]
	return float(Time.get_ticks_usec() - started) / float(ITERATIONS)


func _time_airframe(prepared: bool) -> float:
	var checksum: float = 0.0
	var fuselage_wake := PackedFloat64Array([0.0, 0.0, 1.0])
	var fin_wake := PackedFloat64Array([0.0, 0.2, 0.0])
	var tail_wake := PackedFloat64Array([0.0, 0.0, 0.0])
	var started: int = Time.get_ticks_usec()
	for index: int in range(ITERATIONS):
		var result: Dictionary = Airframe._evaluate_compact_stage_prepared(airframe_model, air, rates,
			fuselage_wake, fin_wake, tail_wake) if prepared else Airframe.evaluate(
			airframe_model, air, rates, fuselage_wake, fin_wake, tail_wake, false)
		if not result.ok:
			failed = true
			break
		checksum += result.loads[2]
	return float(Time.get_ticks_usec() - started) / float(ITERATIONS)
