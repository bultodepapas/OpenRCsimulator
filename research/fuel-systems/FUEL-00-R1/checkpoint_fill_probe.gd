extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const GLOW := "res://data/aircraft/stik_glow_61fx_2t.json"
func _initialize() -> void:
	var source: Node = Flight.new()
	source.input_enabled = false
	source.setup(GLOW)
	source.set_fuel_start_fill(0.5)
	source.reset()
	var saved: Dictionary = source.checkpoint()
	print("source_fill=", source.fuel_start_fill, " source_fuel_kg=", source.sim.continuous[1])
	var destination: Node = Flight.new()
	destination.input_enabled = false
	destination.setup(GLOW)
	print("destination_before_restore_fill=", destination.fuel_start_fill)
	var accepted: bool = destination.restore_checkpoint(saved)
	print("restore_accepted=", accepted, " restored_fuel_kg=", destination.sim.continuous[1], " destination_fill=", destination.fuel_start_fill,
		" trace_meta_fill=", destination.trace_meta().get("fuel_start_fill", "<absent>"))
	destination.reset()
	print("after_reset_fuel_kg=", destination.sim.continuous[1], " destination_fill=", destination.fuel_start_fill)
	source.free()
	destination.free()
	quit(0)
