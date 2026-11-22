extends SceneTree
const Data := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Wake := preload("res://physics/slipstream.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var result: Dictionary = Data.load_file("res://r4_candidate.json")
	if not result.ok:
		print("R4_TRIGGER_UNREACHABLE ", result.errors)
		quit(1)
		return
	var model: Dictionary = result.model
	var s := PackedFloat64Array([0.0, 0.0, -20.0, 12.0, 0.5, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var air: Dictionary = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), 1.225)
	var d := {elevator=0.0, aileron_left=0.0, aileron_right=0.0, rudder=0.0}
	print("R4_TRIGGER_ADMITTED horizontal=", model.surfaces.has("horizontal"), " vertical=", model.surfaces.has("vertical"), " rpm=5000")
	var observed: Variant = Wake.stage_loads(s, air, d, model, 5000.0, 1.225, NAN, PackedFloat64Array(), 1, PackedFloat64Array())
	print("R4_TRIGGER_RETURN ", observed)
	print("R4_TRIGGER_COMPLETE")
	quit(0)
