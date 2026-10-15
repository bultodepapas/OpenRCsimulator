extends SceneTree

const Session = preload("res://sim/ground_vehicle/session.gd")
var checks := 0
var failures := 0


## SF-03: the session reads its state from the shared kernel, so a test places state through the kernel
## (combined index: 13-value body first, then the coupled block).
func _poke(session: Node, index: int, value: float) -> void:
	if index < 13:
		session.sim.state[index] = value
	else:
		session.sim.continuous[index - 13] = value

func _initialize() -> void:
	call_deferred("_run")

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("FAIL: " + label)

func _neutral() -> Dictionary:
	return {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}

func _run() -> void:
	var session = Session.new()
	_check("nitro prepares", session.prepare_default({}, "monster-car-2"))
	var bad_telemetry: Dictionary = session.telemetry_snapshot().nitro.duplicate(true)
	bad_telemetry.fuel_flow_kg_per_s = NAN
	_check("non-finite fuel diagnostics rejected before recording", not session._nitro_telemetry_is_valid(bad_telemetry))
	var before: PackedFloat64Array = session.state_snapshot()
	var damage: PackedFloat64Array = session.damage_snapshot()
	_check("refuelling running engine refused", not session.service_nitro("refuel"))
	_check("unknown service refused", not session.service_nitro("oil"))
	_check("rejected service atomic", before.to_byte_array() == session.state_snapshot().to_byte_array()
		and session.recovery_actions_snapshot().is_empty())
	_check("stop succeeds", session.service_nitro("stop"))
	_check("stop changes engine only", session.state_snapshot()[31] == 0.0
		and session.state_snapshot()[32] == before[32]
		and session.state_snapshot().slice(0, 31).to_byte_array() == before.slice(0, 31).to_byte_array())
	_check("stopped telemetry", not session.telemetry_snapshot().nitro.engine_running)
	_check("repeated stop refused", not session.service_nitro("stop"))
	_check("refuel succeeds", session.service_nitro("refuel"))
	_check("start succeeds", session.service_nitro("start"))
	_check("service retains body and damage", before.to_byte_array() == session.state_snapshot().to_byte_array()
		and damage.to_byte_array() == session.damage_snapshot().to_byte_array() and session.tick == 0)
	var saved: Dictionary = session.checkpoint()
	var json_save: Variant = JSON.parse_string(JSON.stringify(saved, "", true, true))
	_check("service checkpoint JSON restores", session.can_restore_checkpoint(json_save)
		and session.restore_checkpoint(json_save))
	var malformed: Array = session.recovery_actions_snapshot()
	malformed.reverse()
	_check("same-tick service ordering validated", not session._recovery_history_is_consistent(
		malformed, session.event_tape_snapshot()))
	_check("no spontaneous resume after service", session.paused and not session.resume())
	_check("arm and resume", session.tick_once(_neutral()) and session.resume())
	_check("running session cannot service", not session.service_nitro("stop"))
	var ok := true
	for _i in 480: ok = session.tick_once(_neutral()) and ok
	session.pause()
	_check("idle consumes fuel", ok and session.state_snapshot()[32] < before[32])
	_check("stationary stop mid-tape", session.service_nitro("stop"))
	var fuel_after: float = session.state_snapshot()[32]
	_check("refuel mid-tape", session.service_nitro("refuel") and session.state_snapshot()[32] > fuel_after)
	_check("restart mid-tape", session.service_nitro("start"))
	_check("rearm after service", session.tick_once(_neutral()) and session.resume())
	for _i in 24: ok = session.tick_once(_neutral()) and ok
	session.pause()
	var final_state: PackedFloat64Array = session.state_snapshot()
	var tape: PackedFloat64Array = session.control_tape_snapshot()
	var actions: Array = session.recovery_actions_snapshot()
	var events: Array = session.event_tape_snapshot()
	_check("service replay completes", ok and session.replay(tape, actions) and session.tick == 504)
	_check("service replay is byte exact", session.state_snapshot().to_byte_array() == final_state.to_byte_array())
	_check("service action order retained", JSON.stringify(session.recovery_actions_snapshot(), "", true, true) == JSON.stringify(actions, "", true, true)
		and JSON.stringify(session.event_tape_snapshot(), "", true, true) == JSON.stringify(events, "", true, true))
	_check("new checkpoint valid", session.can_restore_checkpoint(session.checkpoint()))
	var invalid_actions: Array = actions.duplicate(true)
	invalid_actions[0].action = "unknown"
	_check("malformed replay rejects atomically", not session.replay(tape, invalid_actions)
		and session.state_snapshot().to_byte_array() == final_state.to_byte_array())
	_check("recording starts", session.start_recording())
	_check("active recording blocks service", not session.service_nitro("stop"))
	_check("recording stops", session.stop_recording())
	_check("unsaved recording blocks service", not session.service_nitro("stop"))
	session.free()
	var moving = Session.new()
	_check("moving session prepares", moving.prepare_default({}, "monster-car-2"))
	_poke(moving, 3, 2.0)
	var moving_before: PackedFloat64Array = moving.state_snapshot()
	_check("paused moving vehicle refuses refuel/stop", not moving.service_nitro("stop")
		and moving.state_snapshot().to_byte_array() == moving_before.to_byte_array())
	_poke(moving, 3, 0.0)
	_poke(moving, 21, 2.0)
	_check("spinning wheel refuses service", not moving.service_nitro("stop"))
	_poke(moving, 21, 0.0)
	_poke(moving, 32, 0.0)
	_poke(moving, 31, 0.0)
	_check("empty tank cannot start", not moving.service_nitro("start"))
	_check("empty tank can refuel then start", moving.service_nitro("refuel") and moving.service_nitro("start"))
	moving.free()
	var electric = Session.new()
	_check("electric prepares", electric.prepare_default())
	_check("nitro service unavailable on electric", not electric.service_nitro("stop"))
	electric.free()
	print("RCV Nitro service: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)
