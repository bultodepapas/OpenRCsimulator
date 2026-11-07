extends SceneTree

const Ring := preload("res://debug/rewind_ring.gd")
const Gizmos := preload("res://debug/flight_gizmos.gd")
const DebugLog := preload("res://debug/debug_log.gd")

var failures := 0
var checks := 0

class FakeSim extends Node:
	var tick := 0
	var paused := false
	var mass := 2.0
	var gravity := 9.81
	var last_loads := PackedFloat64Array([0, 0, -19.62, 0, 0, 0])
	var state := PackedFloat64Array([0, 0, -10, 20, 0, 0, 1, 0, 0, 0, 0, 0, 0])
	func dt() -> float:
		return 1.0 / 240.0
	func time() -> float:
		return tick * dt()

class FakeSession extends Node:
	signal resetting
	var sim := FakeSim.new()
	var refusal := false
	var wind := PackedFloat64Array([0, 0, 0])
	var air_override := {}
	func _init() -> void:
		add_child(sim)
	func checkpoint() -> Dictionary:
		return {simulation = {tick = sim.tick, state = sim.state.duplicate()}}
	func restore_checkpoint(snapshot: Dictionary) -> bool:
		if refusal:
			return false
		sim.tick = int(snapshot.simulation.tick)
		sim.state = snapshot.simulation.state.duplicate()
		resetting.emit()
		return true
	func accepted_boundary(tick: int, marker: float) -> void:
		sim.tick = tick
		sim.state[0] = marker
		resetting.emit()
	func air_data(_state: PackedFloat64Array) -> Dictionary:
		if not air_override.is_empty():
			return air_override
		return {v_air = PackedFloat64Array([20, 0, 0]), V = 20.0, alpha = 0.0, beta = 0.0}
	func wind_at(_time: float, _state: PackedFloat64Array) -> PackedFloat64Array:
		return wind

class SignalLessSession extends Node:
	var sim := FakeSim.new()
	func _init() -> void:
		add_child(sim)
	func checkpoint() -> Dictionary:
		return {simulation = {tick = sim.tick, state = sim.state.duplicate()}}
	func air_data(_state: PackedFloat64Array) -> Dictionary:
		return {v_air = PackedFloat64Array([20, 0, 0]), V = 20.0, alpha = 0.0, beta = 0.0}
	func wind_at(_time: float, _state: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array([0, 0, 0])

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)
	else:
		print("ok ", label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var session := FakeSession.new()
	root.add_child(session)
	var ring := Ring.new()
	ring.arm(1, 8)
	ring.capture(session)
	_check("initial capture", ring.size() == 1 and ring.attempt() == 0)
	session.accepted_boundary(0, 42.0)
	ring.capture(session)
	var current: Dictionary = ring.find({tick = 0}, 0, session.sim.dt())
	_check("same-tick accepted restart opens a new attempt", ring.attempt() == 1 and ring.size() == 2
		and not current.has("error") and current.snapshot.simulation.state[0] == 42.0)
	var prev: Dictionary = ring.find({tick = 0, attempt = "previous"}, 0, session.sim.dt())
	_check("previous attempt retains pre-restart state", not prev.has("error") and prev.snapshot.simulation.state[0] == 0.0)
	session.accepted_boundary(0, 43.0)
	session.accepted_boundary(0, 44.0)
	_check("unobserved successive boundaries do not manufacture attempts", ring.attempt() == 2)
	ring.capture(session)
	_check("latest successive-boundary state captured", ring.find({tick = 0}, 0, session.sim.dt()).snapshot.simulation.state[0] == 44.0)

	var forward := Ring.new()
	forward.arm(1, 8)
	session.sim.tick = 0
	forward.capture(session)
	session.sim.tick = 20
	forward.capture(session)
	session.accepted_boundary(40, 40.0)
	forward.capture(session)
	var gap: Dictionary = forward.find({tick = 30}, 40, session.sim.dt())
	_check("forward checkpoint boundary rejects lookup across discontinuity", forward.attempt() == 1 and gap.has("error"))

	var branch := Ring.new()
	branch.arm(1, 8)
	session.sim.tick = 0
	branch.capture(session)
	session.sim.tick = 1
	branch.capture(session)
	session.sim.tick = 2
	branch.capture(session)
	var first: Dictionary = branch.find({tick = 0}, 2, session.sim.dt())
	session.refusal = true
	_check("refused restore preserves timeline", not branch.restore(session, first) and branch.size() == 3 and branch.attempt() == 0)
	session.refusal = false
	_check("owned restore cuts timeline without a second attempt", branch.restore(session, first) and branch.size() == 1 and branch.attempt() == 0)

	var old_connections := session.get_signal_connection_list("resetting").size()
	var replacement := FakeSession.new()
	root.add_child(replacement)
	_check("restore refuses a different session", not branch.restore(replacement, first) and branch.size() == 1)
	branch.capture(replacement)
	_check("session replacement disconnects prior boundary", session.get_signal_connection_list("resetting").size() == old_connections - 1
		and replacement.get_signal_connection_list("resetting").size() == 1 and branch.size() == 1)
	branch.disarm()
	_check("disarm disconnects boundary", replacement.get_signal_connection_list("resetting").is_empty() and branch.size() == 0)
	branch.capture_usec = 123.0
	branch.disarm()
	_check("disarm clears prior capture-cost diagnostic", branch.capture_usec == 0.0)

	var gizmos := Gizmos.new()
	root.add_child(gizmos)
	gizmos.configure(["trail"])
	replacement.sim.tick = 0
	gizmos.update_from(replacement, {pos = Vector3.ZERO, basis = Basis.IDENTITY})
	replacement.sim.tick = 12
	gizmos.update_from(replacement, {pos = Vector3(1, 0, 0), basis = Basis.IDENTITY})
	_check("trail accumulates distinct ticks", gizmos._trail.size() == 2)
	replacement.accepted_boundary(12, 5.0)
	gizmos.update_from(replacement, {pos = Vector3(50, 0, 0), basis = Basis.IDENTITY})
	_check("same-tick boundary starts a fresh trail", gizmos._trail.size() == 1 and gizmos._trail[0] == Vector3(50, 0, 0))
	replacement.sim.tick = 24
	gizmos.update_from(replacement, {pos = Vector3(51, 0, 0), basis = Basis.IDENTITY})
	replacement.accepted_boundary(60, 6.0)
	gizmos.update_from(replacement, {pos = Vector3(70, 0, 0), basis = Basis.IDENTITY})
	_check("forward checkpoint boundary starts a fresh trail", gizmos._trail.size() == 1 and gizmos._trail[0] == Vector3(70, 0, 0))
	gizmos.update_from(replacement, {})
	_check("missing pose clears stale gizmo values", gizmos.last.is_empty() and gizmos._lines.get_surface_count() == 0)
	gizmos.configure(["wind"])
	replacement.wind = PackedFloat64Array([0, 3, 0])
	gizmos.update_from(replacement, {pos = Vector3.ZERO, basis = Basis.IDENTITY})
	_check("finite wind reports speed and draws an arrow", gizmos.last.wind_mps == 3.0 and gizmos._lines.get_surface_count() == 1)
	replacement.wind = PackedFloat64Array([NAN, NAN, NAN])
	gizmos.update_from(replacement, {pos = Vector3.ZERO, basis = Basis.IDENTITY})
	_check("unavailable wind is not reported as calm", gizmos.last.wind_mps == null and gizmos._lines.get_surface_count() == 0)
	replacement.wind = PackedFloat64Array()
	gizmos.update_from(replacement, {pos = Vector3.ZERO, basis = Basis.IDENTITY})
	_check("missing wind is not reported as calm", gizmos.last.wind_mps == null)
	replacement.wind = PackedFloat64Array([0, 0, 0])
	gizmos.update_from(replacement, {pos = Vector3.ZERO, basis = Basis.IDENTITY})
	_check("actual calm remains a valid zero", gizmos.last.wind_mps == 0.0)
	replacement.wind = PackedFloat64Array([NAN, NAN, NAN])
	replacement.air_override = {v_air = PackedFloat64Array([NAN, NAN, NAN]), V = NAN, alpha = NAN, beta = NAN}
	gizmos.configure(["air", "forces", "label"])
	gizmos.update_from(replacement, {pos = Vector3.ZERO, basis = Basis.IDENTITY})
	var finite_vertices := true
	for vertex: Vector3 in gizmos._lines.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		finite_vertices = finite_vertices and vertex.is_finite()
	_check("unavailable air never enters rendered geometry", finite_vertices)
	_check("unavailable air is not attributed a flight-path force", gizmos.last.airspeed_mps == null
		and gizmos.last.alpha_deg == null and gizmos.last.beta_deg == null
		and gizmos.last.along_path_n == null and gizmos.last.across_path_n == null)
	_check("label explains unavailable air data", gizmos._label.text.contains("unavailable"))
	replacement.air_override = {v_air = PackedFloat64Array([20, 0, 0]), V = 20.0, alpha = NAN, beta = 0.0}
	gizmos.update_from(replacement, {pos = Vector3.ZERO, basis = Basis.IDENTITY})
	_check("partially invalid air sample is unavailable", gizmos.last.airspeed_mps == null
		and gizmos.last.along_path_n == null and gizmos.last.across_path_n == null)
	replacement.air_override.clear()
	replacement.wind = PackedFloat64Array([0, 0, 0])
	replacement.sim.last_loads = PackedFloat64Array([-2, 0, -30, 0, 0, 0])
	gizmos.update_from(replacement, {pos = Vector3.ZERO, basis = Basis.IDENTITY})
	_check("valid air retains force and load-factor values", is_equal_approx(gizmos.last.airspeed_mps, 20.0)
		and is_equal_approx(gizmos.last.along_path_n, -2.0) and is_equal_approx(gizmos.last.across_path_n, 30.0)
		and is_equal_approx(gizmos.last.load_factor, 30.0 / 19.62))
	replacement.air_override = {v_air = PackedFloat64Array([0, 0, 0]), V = 0.0, alpha = 0.0, beta = 0.0}
	gizmos.configure(["air"])
	gizmos.update_from(replacement, {pos = Vector3.ZERO, basis = Basis.IDENTITY})
	_check("zero airspeed draws no empty mesh", gizmos._lines.get_surface_count() == 0)
	gizmos.configure(["axes"])
	gizmos.axis_m = 0.0
	gizmos.update_from(replacement, {pos = Vector3.ZERO, basis = Basis.IDENTITY})
	_check("zero axis length draws no empty mesh", gizmos._lines.get_surface_count() == 0)
	gizmos.axis_m = 0.6
	gizmos.update_from(replacement, {pos = Vector3.ZERO, basis = Basis.IDENTITY})
	_check("nonzero body axes retain all arrows", gizmos._lines.get_surface_count() == 1
		and gizmos._lines.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 18)
	gizmos.configure(["velocity"])
	gizmos.velocity_m_per_mps = 0.0
	gizmos.update_from(replacement, {pos = Vector3.ZERO, basis = Basis.IDENTITY})
	_check("zero velocity scale draws no empty mesh", gizmos._lines.get_surface_count() == 0)
	gizmos.configure(["forces", "moments"])
	gizmos.force_m_per_g = 0.0
	gizmos.moment_gain = 0.0
	gizmos.update_from(replacement, {pos = Vector3.ZERO, basis = Basis.IDENTITY})
	_check("zero force and moment scales draw no empty mesh", gizmos._lines.get_surface_count() == 0)

	var older := SignalLessSession.new()
	root.add_child(older)
	branch.arm(1, 8)
	older.sim.tick = 10
	branch.capture(older)
	older.sim.tick = 0
	branch.capture(older)
	_check("signal-less session retains backward-tick fallback", branch.attempt() == 1 and branch.size() == 2)
	gizmos.update_from(older, {pos = Vector3.ZERO, basis = Basis.IDENTITY})
	gizmos.configure([])
	branch.disarm()
	older.free()

	var logger := DebugLog.new()
	_check("empty log has no records", logger.since(0, 10).is_empty() and logger.last_seq() == 0)
	logger._log_message("first\n", false)
	logger._log_message("error\n", true)
	_check("log preserves filtered sequence order", logger.since(0, 10, PackedStringArray(["stderr"]))[0].text == "error")
	_check("maximum future cursor returns no old records", logger.since(9223372036854775807, 10).is_empty())
	var profile := "FRAME: total: 0.004 script: 0.003/75 %\n0:res://sim/a.gd::10::step\n\ttotal: 0.003/75 % self: 0.001/25 % tcalls: 240"
	logger._log_message(profile, false)
	_check("multiline profile message remains intact", logger.profile_since(0) == PackedStringArray([profile]))
	for i in DebugLog.CAPACITY + 1:
		logger._log_message("ring %d" % i, false)
	var retained: Array[Dictionary] = logger.since(0, DebugLog.CAPACITY + 10)
	_check("log ring retains newest records in sequence", retained.size() == DebugLog.CAPACITY
		and retained[0].seq == logger.last_seq() - DebugLog.CAPACITY + 1
		and retained[-1].seq == logger.last_seq() and logger.dropped == 3)
	gizmos.free()
	ring.disarm()
	forward.disarm()
	session.free()
	replacement.free()
	print("DEBUG_OBSERVERS %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
