# H9-R1: malformed records and live-state faults must never certify a golden replay.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Golden := preload("res://tests/golden_flights.gd")
const RB := preload("res://physics/rigid_body.gd")
var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func rejected_before_reset(flight: Node, record: Dictionary, label: String) -> void:
	var before: Dictionary = flight.sim.checkpoint()
	var input_enabled: bool = flight.input_enabled
	var resets: Array[int] = [0]
	var on_reset: Callable = func() -> void: resets[0] += 1
	flight.resetting.connect(on_reset)
	var result: Dictionary = Golden.replay(flight, record)
	flight.resetting.disconnect(on_reset)
	check(label + " rejected", not result.ok)
	check(label + " preserves session", resets[0] == 0 and flight.sim.checkpoint() == before and flight.input_enabled == input_enabled)


func _initialize() -> void:
	var flight: Node = Flight.new()
	flight.setup()
	root.add_child(flight)
	var recorded: Dictionary = Golden.record(flight, "roll_15")
	var g: Dictionary = JSON.parse_string(JSON.stringify(recorded, "", false, true))
	# Keep three real checkpoints, including an interior one, with genuine per-tick inputs.
	g.ticks = 120
	for key in ["inputs", "checkpoints", "aux_checkpoints", "mode_checkpoints"]:
		while g[key][-1][0] > g.ticks:
			g[key].pop_back()
	check("valid stamped JSON round trip", Golden.replay(flight, g).ok)
	for key in ["aux_checkpoints", "mode_checkpoints"]:
		var bad: Dictionary = g.duplicate(true)
		bad[key].remove_at(1)
		rejected_before_reset(flight, bad, key + " missing interior sample")
		bad = g.duplicate(true)
		bad[key][1][0] += 1
		rejected_before_reset(flight, bad, key + " shifted interior sample")
	var bad: Dictionary = g.duplicate(true)
	bad.aux_checkpoints[1].append(0.0)
	rejected_before_reset(flight, bad, "changing auxiliary layout")
	for value in [9007199254740992, 9223372036854775807, 1e30, INF, NAN, -1, 1.5, true, "120"]:
		bad = g.duplicate(true)
		bad.ticks = value
		# Keep endpoints aligned: otherwise the old reader also rejects an oversized clock.
		for key in ["checkpoints", "aux_checkpoints", "mode_checkpoints"]:
			bad[key][-1][0] = value
		rejected_before_reset(flight, bad, "invalid clock " + str(value))
	for key in ["inputs", "checkpoints", "aux_checkpoints", "mode_checkpoints"]:
		for value in [NAN, INF, -INF, true, "0"]:
			bad = g.duplicate(true)
			bad[key][0][1] = value
			rejected_before_reset(flight, bad, key + " invalid value " + str(value))
	# A valid record need not use the recorder's default sampling interval.
	var sparse: Dictionary = g.duplicate(true)
	for key in ["checkpoints", "aux_checkpoints", "mode_checkpoints"]:
		sparse[key].remove_at(1)
	check("aligned sparse checkpoints accepted", Golden.replay(flight, sparse).ok)
	var legacy: Dictionary = g.duplicate(true)
	for key in ["policy", "stamp", "aux_checkpoints", "mode_checkpoints"]:
		legacy.erase(key)
	check("legacy body-only record accepted", Golden.replay(flight, legacy).ok)
	# Fault injection after the final committed tick isolates the replay reader: no next step can catch it.
	for source in [g, legacy]:
		for value in [NAN, INF, -INF]:
			for index in RB.SIZE:
				var corrupt: Callable = func(tick: int, _t: float, _s: PackedFloat64Array, _l: PackedFloat64Array, _i: PackedFloat64Array, _a: PackedFloat64Array) -> void:
					if tick == int(source.ticks):
						flight.sim.state[index] = value
				flight.sim.stepped.connect(corrupt)
				var result: Dictionary = Golden.replay(flight, source)
				flight.sim.stepped.disconnect(corrupt)
				check("nonfinite live body %s[%d] rejected" % [str(value), index], not result.ok and result.message.contains("invalid replay body"))
	for size in [0, RB.SIZE - 1, RB.SIZE + 1]:
		var corrupt: Callable = func(tick: int, _t: float, _s: PackedFloat64Array, _l: PackedFloat64Array, _i: PackedFloat64Array, _a: PackedFloat64Array) -> void:
			if tick == int(g.ticks):
				flight.sim.state.resize(size)
		flight.sim.stepped.connect(corrupt)
		var result: Dictionary = Golden.replay(flight, g)
		flight.sim.stepped.disconnect(corrupt)
		check("malformed live body size %d rejected" % size, not result.ok and result.message.contains("invalid replay body"))
	check("valid replay recovers after rejected live faults", Golden.replay(flight, g).ok)
	print("H9-R1 replay integrity: %d checks, %d failed" % [checks, failures])
	flight.free()
	quit(1 if failures else 0)
