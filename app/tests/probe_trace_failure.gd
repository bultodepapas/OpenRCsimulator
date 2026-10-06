# C7-R1: inject failures at the real synchronous trace boundary, never in production options.
extends SceneTree

class FaultFlight extends "res://main.gd":
	func _write_trace_and_quit(ticks: int, path: String) -> void:
		var mode: String = OS.get_environment("OPENRC_TRACE_FAILURE")
		if mode == "initial":
			session.sim.fault_reason = "injected invalid start"
		elif mode == "missing_sample":
			session.sim.stepped.disconnect(recorder._on_stepped)
		else:
			var failing_tick: int = ticks - 1 if mode == "last_tick" else 0
			var original: Callable = session.sim.pre_step
			session.sim.pre_step = func(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> PackedFloat64Array:
				if session.sim.tick == failing_tick:
					return PackedFloat64Array([NAN])
				return original.call(aux, inputs, dt)
		super._write_trace_and_quit(ticks, path)


func _initialize() -> void:
	root.add_child.call_deferred(FaultFlight.new())
