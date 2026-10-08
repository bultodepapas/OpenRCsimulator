extends SceneTree
const Flight = preload("res://sim/flight_session.gd")
const Golden = preload("res://tests/golden_flights.gd")
func _initialize() -> void:
	var flight: Node = Flight.new()
	flight.setup()
	root.add_child(flight)
	var g: Dictionary = Golden.record(flight, "roll_15")
	var boundary: Callable = func(tick: int, _t: float, _s: PackedFloat64Array, _l: PackedFloat64Array, _i: PackedFloat64Array, _a: PackedFloat64Array) -> void:
		if tick == int(g.ticks):
			flight.sim.state[0] = NAN
	flight.sim.stepped.connect(boundary)
	print("nonfinite final actual state accepted: ", Golden.replay(flight, g))
	flight.sim.stepped.disconnect(boundary)
	g.aux_checkpoints.remove_at(1)
	print("missing interior auxiliary checkpoint accepted: ", Golden.replay(flight, g).ok)
	g.mode_checkpoints.remove_at(1)
	print("missing interior auxiliary and mode checkpoints accepted: ", Golden.replay(flight, g).ok)
	var overflow: Dictionary = Golden.record(flight, "roll_15")
	overflow.ticks = 9223372036854775807
	for key in ["checkpoints", "aux_checkpoints", "mode_checkpoints"]:
		overflow[key][-1][0] = overflow.ticks
	print("overflow clock accepted: ", Golden.replay(flight, overflow), "; actual tick: ", flight.sim.tick)
	flight.free()
	quit()
