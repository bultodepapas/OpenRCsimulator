# H15 scratch profiler: where does a Simulation.step tick go outside the aircraft loads? Not a test.
extends SceneTree
const FlightSession := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Commands := preload("res://input/commands.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const BATCHES := 16
const TICKS := 120

func _initialize() -> void:
	for id in Catalog.ids():
		var session: Node = FlightSession.new()
		session.setup(Catalog.entry(id).data)
		root.add_child(session)
		for regime in ["trim", "stall"]:
			_fixture(session, regime)
			var acc := {"loads": 0.0, "loads_calls": 0, "pre": 0.0, "rotor": 0.0}
			var orig_loads: Callable = session.sim.loads
			var orig_pre: Callable = session.sim.pre_step
			var orig_rotor: Callable = session.sim.rotor_momentum
			session.sim.loads = func(s: PackedFloat64Array, t: float) -> PackedFloat64Array:
				var t0 := Time.get_ticks_usec()
				var r: PackedFloat64Array = orig_loads.call(s, t)
				acc.loads += Time.get_ticks_usec() - t0
				acc.loads_calls += 1
				return r
			session.sim.pre_step = func(a: PackedFloat64Array, i: PackedFloat64Array, dt: float) -> PackedFloat64Array:
				var t0 := Time.get_ticks_usec()
				var r: PackedFloat64Array = orig_pre.call(a, i, dt)
				acc.pre += Time.get_ticks_usec() - t0
				return r
			session.sim.rotor_momentum = func(a: PackedFloat64Array) -> PackedFloat64Array:
				var t0 := Time.get_ticks_usec()
				var r: PackedFloat64Array = orig_rotor.call(a)
				acc.rotor += Time.get_ticks_usec() - t0
				return r
			var start: Dictionary = {"state": session.sim.state.duplicate(), "aux": session.sim.aux.duplicate(), "inputs": session.sim.inputs.duplicate()}
			var total := 0.0
			var ticks := 0
			for b in BATCHES:
				session.sim.inputs = start.inputs.duplicate()
				session.sim.aux = start.aux.duplicate()
				session.sim.reset(start.state)
				var t0 := Time.get_ticks_usec()
				for k in TICKS:
					session.sim.step()
				total += Time.get_ticks_usec() - t0
				ticks += TICKS
			# Wrapper overhead: an empty wrapped call costs about as much as one Callable layer; report it.
			var probe := func() -> void: pass
			var t1 := Time.get_ticks_usec()
			for k in 10000:
				probe.call()
			var call_cost := float(Time.get_ticks_usec() - t1) / 10000.0
			var per_tick := total / ticks
			var loads := float(acc.loads) / ticks
			var pre := float(acc.pre) / ticks
			var rotor := float(acc.rotor) / ticks
			print("%-28s %-5s tick %6.1f | loads %6.1f (%d calls/tick, %5.1f each) pre_step %5.1f rotor %4.1f | rest %6.1f us (wrapper ~%.1f/call)" % [
				id, regime, per_tick, loads, acc.loads_calls / ticks, loads / (acc.loads_calls / ticks), pre, rotor,
				per_tick - loads - pre - rotor, call_cost])
			session.sim.loads = orig_loads
			session.sim.pre_step = orig_pre
			session.sim.rotor_momentum = orig_rotor
		session.free()
	quit(0)

func _fixture(session: Node, regime: String) -> void:
	session.commands = Commands.neutral_commands()
	session.reset()
	if regime == "stall":
		var s: PackedFloat64Array = session.start.state.duplicate()
		var speed := sqrt(s[RB.VEL] * s[RB.VEL] + s[RB.VEL + 1] * s[RB.VEL + 1] + s[RB.VEL + 2] * s[RB.VEL + 2])
		var alpha := deg_to_rad(15.0)
		s[RB.VEL] = speed * M.cos_(alpha)
		s[RB.VEL + 1] = 0.0
		s[RB.VEL + 2] = speed * M.sin_(alpha)
		s[RB.POS + 2] = -150.0
		session.sim.reset(s)
