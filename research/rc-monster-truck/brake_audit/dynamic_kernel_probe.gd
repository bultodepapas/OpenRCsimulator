extends SceneTree

const SOURCE_PATH := "C:/DEVELOPMENT/OpenRCsimulator/app/physics/ground_vehicle/vehicle_dynamics.gd"
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")

func _initialize() -> void:
	var source := FileAccess.get_file_as_string(SOURCE_PATH)
	print("SOURCE_LEN ", source.length())
	var script := GDScript.new()
	script.source_code = source.replace("const FRICTION_SWEEPS := 6", "const FRICTION_SWEEPS := 12")
	var error := script.reload()
	print("RELOAD ", error, " RESOURCE_HAS_STEP ", script.has_method("step"))
	var instance: Object = script.new()
	print("INSTANCE_HAS_STEP ", instance.has_method("step"), " INSTANCE_HAS_EVALUATE ", instance.has_method("_evaluate"))
	print("RESOURCE_METHODS ", JSON.stringify(script.get_method_list().map(func(m): return m.name).filter(func(n): return "step" in n or "evaluate" in n)))
	print("INSTANCE_METHODS ", JSON.stringify(instance.get_method_list().map(func(m): return m.name).filter(func(n): return "step" in n or "evaluate" in n)))
	var loaded: Dictionary = Data.load_default()
	if bool(loaded.get("ok", false)):
		var initial: Dictionary = script.call("initialize", loaded.model, _road, 0.0, 0.0)
		print("DYNAMIC_INIT ", bool(initial.get("ok", false)), " ", str(initial.get("error", "")))
		if bool(initial.get("ok", false)):
			var advanced: PackedFloat64Array = script.call("step", initial.state, loaded.model,
				{"throttle": 1.0, "steering": 0.0, "brake": 0.0, "reverse": false}, 1.0 / 240.0, _road)
			print("DYNAMIC_STEP ", advanced.size(), " U=", advanced[3] if advanced.size() > 3 else -1.0)
	quit(0)

func _road(_n: float, _e: float) -> Dictionary:
	return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85, "rolling": 1.0, "surface_id": "dynamic_probe"}
