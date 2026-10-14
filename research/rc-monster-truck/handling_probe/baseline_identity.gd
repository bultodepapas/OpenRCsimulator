extends SceneTree

func _initialize() -> void:
	var solver_path := ProjectSettings.globalize_path("res://../research/rc-monster-truck/handling_probe/baseline_sources/app/physics/ground_vehicle/vehicle_dynamics.gd")
	var solver_script: Script = load(solver_path)
	if solver_script == null:
		push_error("Could not load frozen baseline solver from " + solver_path)
		quit(1)
		return
	var identity: Dictionary = solver_script.backend_identity()
	print(JSON.stringify(identity))
	quit(0)
