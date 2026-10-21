extends SceneTree

const Candidate := preload("res://../research/ai-companions/sorties/circuit_pilot_candidate.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	var driver_script: Script = load("res://../research/ai-companions/sorties/external_sortie_driver.gd")
	_check(driver_script != null, "external sortie driver with the opt-in weather seam loads")
	var east: float = PI / 2.0
	var west: float = -PI / 2.0
	var candidate: RefCounted = Candidate.new({}, true, {})
	var calm: Dictionary = Candidate.wind_correction(east, PackedFloat64Array([0.0, 0.0, 0.0]), 12.0)
	_check(calm.get("ok", false) and absf(float(calm.get("correction_rad", INF))) <= 1.0e-12,
		"calm wind leaves the desired eastbound track unchanged", JSON.stringify(calm))
	var headwind: Dictionary = Candidate.wind_correction(east, PackedFloat64Array([0.0, -3.0, 0.0]), 12.0)
	_check(headwind.get("ok", false) and absf(float(headwind.get("correction_rad", INF))) <= 1.0e-12,
		"runway-aligned headwind does not induce a crab angle", JSON.stringify(headwind))
	var north_crosswind: Dictionary = Candidate.wind_correction(east, PackedFloat64Array([-2.0, 0.0, 0.0]), 12.0)
	_check(north_crosswind.get("ok", false) and float(north_crosswind.get("correction_rad", 0.0)) < 0.0,
		"southbound crosswind on an eastbound track commands a crab into the wind", JSON.stringify(north_crosswind))
	var mirrored_crosswind: Dictionary = Candidate.wind_correction(west, PackedFloat64Array([-2.0, 0.0, 0.0]), 12.0)
	_check(mirrored_crosswind.get("ok", false) and float(mirrored_crosswind.get("correction_rad", 0.0)) > 0.0,
		"the mirrored westbound track reverses the crab sign", JSON.stringify(mirrored_crosswind))
	var untrackable: Dictionary = Candidate.wind_correction(east, PackedFloat64Array([-13.0, 0.0, 0.0]), 12.0)
	_check(not untrackable.get("ok", false) and str(untrackable.get("reason", "")).contains("not trackable"),
		"crosswind at or above true airspeed is refused rather than emitting a false heading", JSON.stringify(untrackable))
	var malformed: Dictionary = Candidate.wind_correction(east, PackedFloat64Array([NAN, 0.0, 0.0]), 12.0)
	_check(not malformed.get("ok", false), "nonfinite wind is refused", JSON.stringify(malformed))
	_check(float(candidate._cross_track_error("final_turn", -200.0, 12.0)) == -12.0,
		"final-turn guidance retains a centerline-closing correction", str(candidate._cross_track_error("final_turn", -200.0, 12.0)))
	var calm_gate: Dictionary = Candidate.approach_gate_for_weather(50.0, 1.0, PackedFloat64Array([0.0, 0.0, 0.0]))
	_check(calm_gate.get("ok", false) and absf(float(calm_gate.gate_before_threshold_m) - 85.0) <= 1.0e-9,
		"calm approach gate preserves the measured C4 entry-distance neighborhood", JSON.stringify(calm_gate))
	var east_headwind_gate: Dictionary = Candidate.approach_gate_for_weather(50.0, 1.0, PackedFloat64Array([0.0, -2.0, 0.0]))
	var west_headwind_gate: Dictionary = Candidate.approach_gate_for_weather(50.0, -1.0, PackedFloat64Array([0.0, 2.0, 0.0]))
	_check(east_headwind_gate.get("ok", false) and west_headwind_gate.get("ok", false)
		and absf(float(east_headwind_gate.ground_speed_mps) - 10.0) <= 1.0e-9
		and absf(float(east_headwind_gate.gate_before_threshold_m) - 70.0) <= 1.0e-9
		and absf(float(west_headwind_gate.gate_before_threshold_m) - float(east_headwind_gate.gate_before_threshold_m)) <= 1.0e-9,
		"opposed runway directions receive the same ground-speed-aware entry distance into a headwind",
		JSON.stringify([east_headwind_gate, west_headwind_gate]))
	var crosswind_gate: Dictionary = Candidate.approach_gate_for_weather(50.0, 1.0, PackedFloat64Array([-2.0, 0.0, 0.0]))
	_check(crosswind_gate.get("ok", false) and float(crosswind_gate.gate_before_threshold_m) < 85.0
		and float(crosswind_gate.gate_before_threshold_m) > 83.0,
		"crosswind crab reduces along-runway groundspeed in the predicted glide distance", JSON.stringify(crosswind_gate))
	print("AFC-09 weather-control candidate: %d checks, %d failed" % [checks, failures.size()])
	for failure: String in failures:
		printerr("FAIL " + failure)
	quit(1 if not failures.is_empty() else 0)


func _check(condition: bool, label: String, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures.append(label + (" -- " + detail if not detail.is_empty() else ""))
