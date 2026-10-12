## Negative control: a finite but incomplete case must make the inherited probe fail.
extends "ground_probe.gd"


func _run_case(label: String, initial: PackedFloat64Array, rpm: float, engine_running: bool, seconds: float, pilot: Callable) -> Dictionary:
	var result := super._run_case(label, initial, rpm, engine_running, seconds, pilot)
	if label == "parked_engine_off" and result.get("complete", false):
		result.crashed = "injected finite-crash acceptance control"
		result.complete = false
	return result
