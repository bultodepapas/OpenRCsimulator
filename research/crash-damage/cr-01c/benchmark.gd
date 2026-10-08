# Selector cost only, without drawing; shared-host batch means, not frame-time acceptance.
extends SceneTree
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
var _results: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for entry: Dictionary in Catalog.ENTRIES:
		var flight: Node = load("res://main.tscn").instantiate()
		flight.aircraft_id = entry.id
		root.add_child(flight)
		flight.set_process(false)
		flight.session.set_physics_process(false)
		flight.session.sim.set_physics_process(false)
		flight.session.input_enabled = false
		var regimes: Dictionary = {}
		for regime in ["flight","crash"]:
			if regime == "crash":
				flight.session.sim.previous = RB.make_state(M.v3(0,-15,-5),M.v3(10,0,3),M.q_identity(),M.v3(0,0,0))
				flight.session.sim.state = flight.session.sim.previous.duplicate()
				flight.session.sim.state[RB.POS+2] = .2
				flight.session._physics_process(flight.session.sim.dt())
				if flight.session.crash.is_empty() or not flight.session.crash.impact.crossing.available:
					printerr("benchmark has no crossing")
					quit(1)
					return
			var batches: Array[float] = []
			for trial in 5:
				var began: int = Time.get_ticks_usec()
				for iteration in 1000:
					flight._current_pose()
				batches.append(float(Time.get_ticks_usec()-began)/1000)
			regimes[regime] = batches
		_results[entry.id] = regimes
		flight.queue_free()
		await process_frame
	print("CR01C_JSON="+JSON.stringify(_results,"",true,true))
	quit()
