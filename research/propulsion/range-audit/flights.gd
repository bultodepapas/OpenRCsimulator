# G1b1: real session/recorder flights and direct propulsion-query oracle.
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Recorder = preload("res://sim/recorder.gd")
const Prop = preload("res://physics/propulsion.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")


func _initialize() -> void:
	var output: String = OS.get_environment("OPENRC_RANGE_OUTPUT")
	if output.is_empty():
		printerr("FAIL OPENRC_RANGE_OUTPUT required")
		quit(1)
		return
	var cases: Array = [
		["stik_trim", "jensen_ugly_stik_60", 240],
		["stik_dive_idle", "jensen_ugly_stik_60", 480],
		["stik_full_power", "jensen_ugly_stik_60", 240],
		["stik_stopped", "jensen_ugly_stik_60", 240],
		["extra_trim", "gp_extra_300s_60", 240],
		["p51_trim", "p51d_mustang_120", 240],
	]
	var results: Array = []
	for item in cases:
		var session: Node = Session.new()
		session.input_enabled = false
		session.physics_enabled = false
		session.setup("res://data/aircraft/%s.json" % item[1])
		if session.aircraft.model.is_empty() or not session.sim.fault_reason.is_empty():
			printerr("FAIL setup ", item[0])
			quit(1)
			return
		var prop: Dictionary = session.aircraft.model.propulsion
		if item[0] == "stik_stopped":
			if not session.trim_at(15.0, "glide").ok:
				quit(1)
				return
			session.reset()
		elif item[0] == "stik_dive_idle":
			session.commands.throttle = 0.0
			session.sim.inputs = session._inputs() # Synchronous sim.step does not poll session commands.
			session.sim.aux[0] = prop.idle_rpm
			var state: PackedFloat64Array = session.sim.state.duplicate()
			state[RB.VEL] = 40.0
			state[RB.VEL + 1] = 0.0
			state[RB.VEL + 2] = 0.0
			state[RB.POS + 2] = -1000.0
			var attitude: PackedFloat64Array = M.q_from_euler(0.0, deg_to_rad(-30.0), 0.0)
			for k in 4:
				state[RB.ATT + k] = attitude[k]
			if not session.sim.reset(state):
				quit(1)
				return
		elif item[0] == "stik_full_power":
			session.commands.throttle = 1.0
			session.sim.inputs = session._inputs()
			session.sim.aux[0] = prop.max_rpm
			if not session.sim.reset(session.sim.state):
				quit(1)
				return
		var recorder: RefCounted = Recorder.new(session.sim)
		var metadata: Dictionary = session.trace_meta()
		metadata.configuration = "G1b1 verification fixture: %s; fixed sampled commands; calm air. Dive overrides trim with 40 m/s body-axis speed, -30 deg pitch, 1000 m altitude and idle RPM; full-power overrides throttle/RPM; other starts use session trim." % item[0]
		recorder.start(metadata)
		var queries: Array = []
		for tick in int(item[2]):
			var previous: PackedFloat64Array = session.sim.state.duplicate()
			session.sim.step()
			if session.sim.tick != tick + 1 or not session.sim.fault_reason.is_empty() or not session.crash.is_empty():
				printerr("FAIL incomplete flight ", item[0], " ", tick)
				quit(1)
				return
			var velocity: PackedFloat64Array = previous.slice(RB.VEL, RB.VEL + 3)
			var rpm: float = session.sim.aux[0]
			var tq: PackedFloat64Array = Prop.thrust_torque(velocity, rpm, prop, 1.225)
			queries.append({tick = session.sim.tick, J = tq[2], rpm = rpm,
				axial_mps = M.dot(velocity, Prop.axis(prop)), stopped = rpm < Prop.STOPPED_RPM})
		if recorder.stop(output.path_join(item[0] + ".csv")) != OK:
			quit(1)
			return
		results.append({name = item[0], aircraft_file = item[1], ticks = item[2], queries = queries})
		recorder.detach()
		session.free()
	var file: FileAccess = FileAccess.open(output.path_join("oracle.json"), FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(results, "\t", true, true) + "\n")
	file.close()
	print("G1b1: six complete session flights and direct propulsion query oracles")
	quit(0)
