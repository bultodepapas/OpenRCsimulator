# Focused step ownership and pending-reply boundaries, without a running app or socket.
extends SceneTree

const Bridge := preload("res://debug/debug_bridge.gd")

var checks := 0
var failures := 0


class FakeSim extends Node:
	var paused := true
	var tick := 0
	var fault_reason := ""
	var stop_at_tick := -1
	var state := PackedFloat64Array([0, 0, -10, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])
	func dt() -> float:
		return 1.0 / 240.0
	func time() -> float:
		return tick * dt()
	func set_paused(value: bool) -> void:
		if not value and not fault_reason.is_empty():
			return
		paused = value


class FakeSession extends Node:
	signal resetting
	var sim: Node = FakeSim.new()
	var holds := {}
	var crash := {}
	var pause_reason := ""
	var commands := {}
	var raw := {}
	var checkpoint_calls := 0
	func _init() -> void:
		add_child(sim)
	func checkpoint() -> Dictionary:
		checkpoint_calls += 1
		return {simulation = {tick = sim.tick, stop_at_tick = sim.stop_at_tick}}
	func checkpoint_json() -> String:
		checkpoint_calls += 1
		return "{}"


class FakeFlight extends Node:
	var session: Node = FakeSession.new()
	var aircraft_id := "fake-plane"
	func _init() -> void:
		add_child(session)


class FakeApp extends Node:
	var flight: Node = FakeFlight.new()
	var ground_vehicle: Node
	var home: Node
	var screens: Node
	func _init() -> void:
		add_child(flight)


func _check(label: String, ok: bool, detail: Variant = null) -> void:
	checks += 1
	if ok:
		print("ok ", label)
	else:
		failures += 1
		print("FAIL ", label, " ", detail)


func _prepare(sim: Node, tick: int) -> void:
	sim.fault_reason = ""
	sim.stop_at_tick = -1
	sim.tick = tick
	sim.paused = true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var bridge: Node = Bridge.new()
	var app := FakeApp.new()
	bridge.app = app
	var flight: Node = app.flight
	var session: Node = flight.session
	var sim: Node = session.sim

	_prepare(sim, 10)
	var full: Dictionary = bridge._cmd_step({ticks = 3})
	_check("step starts with the requested owned stop", full.has("pending") and not sim.paused and sim.stop_at_tick == 13)
	sim.tick = 12
	_check("step is pending before target", full.pending.call() == null)
	sim.tick = 13
	var full_result: Dictionary = full.pending.call()
	_check("step succeeds at the exact target and pauses", full_result.ok and full_result.result.tick == 13
		and sim.paused and sim.stop_at_tick == -1 and bridge._step_target == -1)
	_check("completed step disconnects reset listener", session.get_signal_connection_list("resetting").is_empty())

	_prepare(sim, 20)
	sim.fault_reason = "entry fault"
	var entry_fault: Dictionary = bridge._cmd_step({ticks = 4})
	_check("faulted start is refused unchanged", not entry_fault.ok and sim.tick == 20 and sim.paused and sim.stop_at_tick == -1)
	_prepare(sim, 30)
	var fault_job: Dictionary = bridge._cmd_step({ticks = 4})
	sim.tick = 31
	sim.fault_reason = "mid-step fault"
	var fault_result: Dictionary = fault_job.pending.call()
	_check("mid-step fault fails with actual progress", not fault_result.ok and fault_result.progress.tick == 31
		and sim.paused and sim.stop_at_tick == -1)

	_prepare(sim, 40)
	var early_job: Dictionary = bridge._cmd_step({ticks = 4})
	sim.tick = 41
	sim.paused = true
	var early_result: Dictionary = early_job.pending.call()
	_check("early pause fails instead of claiming completion", not early_result.ok and early_result.progress.tick == 41
		and sim.paused and sim.stop_at_tick == -1)
	_prepare(sim, 50)
	var overrun_job: Dictionary = bridge._cmd_step({ticks = 4})
	sim.tick = 55
	var overrun_result: Dictionary = overrun_job.pending.call()
	_check("passed target fails rather than reporting exact completion", not overrun_result.ok and overrun_result.progress.tick == 55
		and sim.paused and sim.stop_at_tick == -1)

	_prepare(sim, 60)
	var timeout_job: Dictionary = bridge._cmd_step({ticks = 4})
	sim.tick = 61
	var timeout_result: Dictionary = timeout_job.on_timeout.call()
	_check("timeout pauses and releases its boundary", not timeout_result.ok and timeout_result.progress.tick == 61
		and sim.paused and sim.stop_at_tick == -1 and session.get_signal_connection_list("resetting").is_empty())
	_prepare(sim, 70)
	bridge._handle(1001, 11, {cmd = "step", ticks = 4})
	_check("disconnect fixture owns one pending step", bridge._pending.size() == 1 and sim.stop_at_tick == 74)
	bridge._forget_peer(1001)
	_check("disconnect cancels pending step and cleans ownership", bridge._pending.is_empty() and sim.paused
		and sim.stop_at_tick == -1 and session.get_signal_connection_list("resetting").is_empty())
	_prepare(sim, 75)
	bridge._handle(1002, 12, {cmd = "step", ticks = 4, timeout_s = 0})
	bridge._run_pending()
	var timeout_reply: Variant = JSON.parse_string(bridge._outbox[-1].bytes.get_string_from_utf8())
	_check("pending deadline sends a failure and cleans ownership", bridge._pending.is_empty() and timeout_reply is Dictionary
		and not timeout_reply.ok and timeout_reply.id == 12 and sim.paused and sim.stop_at_tick == -1
		and session.get_signal_connection_list("resetting").is_empty())
	bridge._outbox.clear()

	_prepare(sim, 80)
	var first: Dictionary = bridge._cmd_step({ticks = 2})
	sim.tick = 82
	bridge._finish_step()
	var second: Dictionary = bridge._cmd_step({ticks = 3})
	var first_result: Dictionary = first.pending.call()
	var first_timeout: Dictionary = first.on_timeout.call()
	_check("old completed reply cannot cancel a newer step", first_result.ok and first_result.result.tick == 82
		and first_timeout.ok and second.pending.call() == null and sim.stop_at_tick == 85 and not sim.paused)
	sim.tick = 85
	var second_result: Dictionary = second.pending.call()
	_check("newer step retains its own result", second_result.ok and second_result.result.tick == 85 and sim.paused)

	_prepare(sim, 90)
	sim.stop_at_tick = 93
	var bounded: Dictionary = bridge._cmd_step({ticks = 5})
	_check("an existing simulation stop is not overwritten", not bounded.ok and sim.tick == 90
		and sim.paused and sim.stop_at_tick == 93)
	_prepare(sim, 9223372036854775806)
	var overflow: Dictionary = bridge._cmd_step({ticks = 2})
	_check("unrepresentable target is refused without mutation", not overflow.ok and sim.paused and sim.stop_at_tick == -1)
	_prepare(sim, 100)
	var replaced_bound: Dictionary = bridge._cmd_step({ticks = 5})
	sim.tick = 102
	sim.stop_at_tick = 103
	var replaced_result: Dictionary = replaced_bound.pending.call()
	_check("replaced stop fails promptly and is preserved", not replaced_result.ok and sim.stop_at_tick == 103
		and bridge._step_target == -1)

	_prepare(sim, 110)
	var reset_job: Dictionary = bridge._cmd_step({ticks = 5})
	sim.tick = 0
	sim.stop_at_tick = -1
	sim.paused = false
	session.resetting.emit()
	var reset_result: Dictionary = reset_job.pending.call()
	_check("accepted reset cancels without pausing the new unowned run", not reset_result.ok and sim.tick == 0
		and not sim.paused and sim.stop_at_tick == -1 and session.get_signal_connection_list("resetting").is_empty())

	_prepare(sim, 120)
	var wrong_session_job: Dictionary = bridge._cmd_step({ticks = 5})
	var replacement_session := FakeSession.new()
	flight.add_child(replacement_session)
	flight.session = replacement_session
	var wrong_session: Dictionary = wrong_session_job.pending.call()
	_check("replacing the flight session fails and releases old stop", not wrong_session.ok
		and sim.paused and sim.stop_at_tick == -1)
	flight.session = session
	replacement_session.free()

	_prepare(sim, 130)
	var wrong_sim_job: Dictionary = bridge._cmd_step({ticks = 5})
	var replacement_sim := FakeSim.new()
	replacement_sim.paused = false
	replacement_sim.stop_at_tick = 777
	session.add_child(replacement_sim)
	session.sim = replacement_sim
	var wrong_sim: Dictionary = wrong_sim_job.pending.call()
	_check("replacing the simulation fails without touching its replacement", not wrong_sim.ok
		and sim.paused and sim.stop_at_tick == -1 and not replacement_sim.paused and replacement_sim.stop_at_tick == 777)
	session.sim = sim
	replacement_sim.free()

	_prepare(sim, 140)
	var lost_sim_job: Dictionary = bridge._cmd_step({ticks = 5})
	sim.free()
	var lost_result: Dictionary = lost_sim_job.pending.call()
	_check("freed simulation has unavailable progress", not lost_result.ok and lost_result.progress.tick == null)
	var fresh_sim := FakeSim.new()
	session.add_child(fresh_sim)
	session.sim = fresh_sim
	sim = fresh_sim

	_prepare(sim, 150)
	bridge._rewind.arm(1, 8)
	var bounded_capture: Dictionary = bridge._cmd_step({ticks = 5})
	bridge._physics_process(0.0)
	_check("rewind does not capture a temporary step stop", bridge._rewind.size() == 0 and session.checkpoint_calls == 0)
	var path := OS.get_user_data_dir().path_join("openrc-step-checkpoint-test.json")
	var saved: Dictionary = bridge._cmd_checkpoint({action = "save", path = path})
	_check("checkpoint save refuses while a step is active", not saved.ok and str(saved.error).contains("step")
		and session.checkpoint_calls == 0)
	bounded_capture.on_timeout.call()
	sim.paused = false
	bridge._physics_process(0.0)
	_check("rewind capture resumes after step cleanup", bridge._rewind.size() == 1 and session.checkpoint_calls == 1)
	bridge._rewind.disarm()

	bridge.app = null
	app.free()
	OS.remove_logger(bridge.debug_log)
	bridge.free()
	print("DEBUG_STEP %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
