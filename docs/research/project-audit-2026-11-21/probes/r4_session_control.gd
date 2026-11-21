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
	var path := "res://r4_no_wake.json"
	var data: Dictionary = Data.load_file(path)
	var pre: Dictionary = flight._prepare_aircraft_before_trim(data)
	print("R4_NO_WAKE_PREFLIGHT ", JSON.stringify({loader_ok=data.get("ok",false), preflight_ok=pre.get("ok",false), message=pre.get("message",""), input_identity=data.get("input_identity",{}),
		backend_selected=backend_selected, stage_backend_identity=flight.stage_backend_identity()}))
	flight.setup(path, "r4-tailless-tractor-control")
	flight.input_enabled = false
	var before: int = flight.sim.tick
	var was_flyable: bool = flight.is_flyable()
	if was_flyable:
		flight.sim.step()
	var accepted: bool = was_flyable and flight.sim.tick == before + 1 and flight.sim.fault_reason.is_empty() \
		and flight.stage_backend_identity().get("backend", "") == "gdscript_reference"
	print("R4_NO_WAKE_SESSION ", JSON.stringify({flyable=was_flyable, start=flight.start, start_error=flight.start_error, initial_tick=before,
		final_tick=flight.sim.tick, fault=flight.sim.fault_reason, accepted=accepted,
		stage_backend_identity=flight.stage_backend_identity()}))
	flight.free()
	print("R4_NO_WAKE_SESSION_COMPLETE ", "PASS" if accepted else "FAIL")
	quit(0 if accepted else 1)
