# CR-01b: same read-only harness against baseline and candidate projects.
# Run with --path <snapshot>/app --script <absolute path to this file>.
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const COUNT: int = 240
const REPEATS: int = 5

func _initialize() -> void:
	var results: Dictionary = {flight_tick_us = {}, snapshot_with_previous_us = {}}
	var impact: GDScript = load("res://physics/impact_snapshot.gd") if FileAccess.file_exists("res://physics/impact_snapshot.gd") else null
	for entry: Dictionary in Catalog.ENTRIES:
		var session: Node = Session.new()
		session.setup(entry.data)
		root.add_child(session)
		session.input_enabled = false
		var regimes: Dictionary = {}
		for regime: String in ["trim", "stall"]:
			var samples: Array[float] = []
			for trial: int in REPEATS:
				session.reset()
				if regime == "stall":
					var speed: float = M.norm(RB._slice3(session.sim.state, RB.VEL))
					session.sim.state[RB.VEL] = speed*cos(deg_to_rad(15))
					session.sim.state[RB.VEL+2] = speed*sin(deg_to_rad(15))
				var began: int = Time.get_ticks_usec()
				for i: int in COUNT:
					session._physics_process(session.sim.dt())
					session.sim.step()
				samples.append(float(Time.get_ticks_usec()-began)/COUNT)
				if not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
					printerr("unexpected crash/fault in benchmark")
					quit(1)
					return
			regimes[regime] = samples
		results.flight_tick_us[entry.id] = regimes
		if impact != null:
			var s: PackedFloat64Array = RB.make_state(M.v3(0, 0, 0), M.v3(3, 4, 2), M.q_identity(), M.v3(2, 0, 0))
			var previous: PackedFloat64Array = s.duplicate()
			previous[RB.POS+2] = -2.0
			var supports_crossing: bool = FileAccess.file_exists("res://physics/hull_crossing.gd")
			if supports_crossing:
				var probe: RefCounted = impact.hull_contact(s, 42, session.aircraft.model.crash_hull, previous)
				if probe.crossing == null or not probe.crossing.available:
					printerr("benchmark did not reconstruct a crossing")
					quit(1)
					return
			var samples: Array[float] = []
			for trial: int in REPEATS:
				var began: int = Time.get_ticks_usec()
				for i: int in 1000:
					if supports_crossing:
						impact.hull_contact(s, 42, session.aircraft.model.crash_hull, previous)
					else:
						impact.hull_contact(s, 42, session.aircraft.model.crash_hull)
				samples.append(float(Time.get_ticks_usec()-began)/1000)
			results.snapshot_with_previous_us[entry.id] = samples
		session.free()
	print("CR01B_JSON=" + JSON.stringify(results, "", true, true))
	quit()
