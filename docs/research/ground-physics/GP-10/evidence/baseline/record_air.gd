## GP-10 focused baseline: reuse existing flight-log tests for Stik and P-51 only.
extends "res://tests/test_flight_log.gd"

func _run() -> void:
	for path: String in ["res://data/aircraft/jensen_ugly_stik_60.json", "res://data/aircraft/p51d_mustang_120.json"]:
		_flight(path)
	var file := FileAccess.open(destination.path_join("verification.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({checks = checks, failures = failures, measurements = measurements}, "\t", true, true))
	file.close()
	print("GP-10 focused air logs: %d checks, %d failures; %s" % [checks, failures, destination])
	quit(1 if failures else 0)
