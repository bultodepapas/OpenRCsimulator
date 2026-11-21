extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Data := preload("res://physics/aircraft_data.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var flight: Node = Flight.new()
	var backend_selected: bool = flight.setup_stage_backend("gdscript_reference")
	if not backend_selected:
		printerr("R4_REFERENCE_BACKEND_SELECTION_FAILED ", flight.stage_backend_error)
		flight.free()
		quit(1)
		return
	var path := "res://r4_candidate.json"
	var data: Dictionary = Data.load_file(path)
	var pre: Dictionary = flight._prepare_aircraft_before_trim(data)
	print("R4_WAKE_PREFLIGHT ", JSON.stringify({loader_ok=data.get("ok",false), preflight_ok=pre.get("ok",false), message=pre.get("message",""), input_identity=data.get("input_identity",{}),
		backend_selected=backend_selected, stage_backend_identity=flight.stage_backend_identity()}))
	print("R4_WAKE_SETUP_BEGIN")
	flight.setup(path, "r4-tailless-tractor-test")
	print("R4_WAKE_SETUP_RETURN ", JSON.stringify({flyable=flight.is_flyable(), start=flight.start,
		start_error=flight.start_error, tick=flight.sim.tick, fault=flight.sim.fault_reason,
		stage_backend_identity=flight.stage_backend_identity()}))
	flight.free()
	print("R4_WAKE_SESSION_COMPLETE")
	quit(0)
