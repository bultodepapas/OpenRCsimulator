extends SceneTree
const Data := preload("res://physics/aircraft_data.gd")
const Modules := preload("res://physics/aircraft_modules.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var passed := true
	for name: String in ["r4_no_wake.json", "r4_candidate.json", "r4_electric_wake.json"]:
		var path := "res://" + name
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not raw is Dictionary:
			print("R4_JSON_FAILURE ", name)
			passed = false
			continue
		var classification: Dictionary = Modules.classify(raw)
		var result: Dictionary = Data.load_file(path)
		var expected: bool = name != "r4_electric_wake.json"
		print("R4_ADMISSION ", JSON.stringify({file = name, expected = expected, classified = classification.get("ok", false),
			classification_errors = classification.get("errors", []), ok = result.get("ok", false), errors = result.get("errors", []),
			warnings = result.get("warnings", []), surface_keys = result.get("model", {}).get("surfaces", {}).keys(),
			wake_pieces = result.get("model", {}).get("propulsion", {}).get("slipstream", {}).get("pieces", [])}))
		if bool(result.get("ok", false)) != expected:
			passed = false
	print("R4_ADMISSION_COMPLETE ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)
