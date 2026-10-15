# SF-03: the RC ground vehicle runs on the shared Simulation kernel through its VehicleModel.
# Structure and transaction checks only; byte identity with the pre-SF-03 integrator is proven by
# tests/fingerprint_vehicles.gd against a HEAD copy (docs/research/simulation-foundation/SF-03).
extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const Sim := preload("res://sim/simulation.gd")
const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")

var _count := 0
var _failures := 0
var session: Node
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


## A paused session resumes only after it has seen a neutral, armed sample (held keys cannot carry over).
func _arm_and_resume() -> bool:
	return session.tick_once(NEUTRAL) and session.resume()


func _drive(ticks: int, sample: Dictionary) -> bool:
	for _i in ticks:
		if not session.tick_once(sample):
			return false
	return true


func _run() -> void:
	session = Session.new()
	root.add_child(session)
	_check("default session prepares", session.prepare_default(), session.load_error)
	var sim: Node = session.sim
	_check("the session owns a Simulation kernel", sim is Sim and sim.get_parent() == session)
	_check("the kernel never steps from the engine loop", sim.process_mode == Node.PROCESS_MODE_DISABLED)
	_check("ground-vehicle model installed with the declared layout", sim.model.identity.get("vehicle") == "ground-vehicle"
		and sim.model.input_size == 4 and sim.model.continuous_size == Session.STATE_SIZE - 13
		and sim.model.aux_size == 0 and sim.model.modes_size == 0)
	_check("kernel body and coupled block compose the 31-value state", session.state_snapshot() == _combined(sim)
		and session.state_snapshot().size() == Session.STATE_SIZE)
	_check("tick is the kernel's clock", session.tick == 0 and sim.tick == 0)
	_check("arming tick and resume", _arm_and_resume())
	var throttle: Dictionary = NEUTRAL.duplicate()
	throttle.throttle = 0.6
	_check("240 driven ticks advance the kernel clock", _drive(240, throttle) and session.tick == 240 and sim.tick == 240, session.fault_reason)
	_check("the vehicle moved", session.state_snapshot()[0] != _combined(sim)[0] or absf(session.state_snapshot()[3]) > 0.01)
	_check("kernel state equals the session state after driving", session.state_snapshot() == _combined(sim))
	# Session checkpoint (JSON v3, unchanged format) restores through the kernel and replays exactly.
	var saved: Dictionary = session.checkpoint()
	_check("session checkpoint exists at tick 240", not saved.is_empty() and int(saved.tick) == 240)
	_check("100 more ticks", _drive(100, throttle))
	var ahead: PackedByteArray = session.state_snapshot().to_byte_array()
	_check("restore moves the kernel clock back", session.restore_checkpoint(saved) and sim.tick == 240 and session.tick == 240)
	_check("restored kernel state matches the checkpoint", session.state_snapshot().to_byte_array() == session._decode_float64_blob(saved.state_f64_base64, Session.STATE_SIZE).to_byte_array())
	_check("exact replay after restore", _arm_and_resume() and _drive(100, throttle) and session.state_snapshot().to_byte_array() == ahead)
	# Manual recovery replaces the state at the current tick without emitting a tick.
	var before_recovery: int = session.tick
	_check("manual recovery keeps the kernel clock", session.manual_recovery() and sim.tick == before_recovery and session.tick == before_recovery)
	_check("recovery state is a spawn pose at rest", absf(session.state_snapshot()[3]) < 1e-12 and absf(session.state_snapshot()[4]) < 1e-12)
	# The standalone evaluator and the kernel path integrate the same plan: one tick, same bytes.
	_check("resume after recovery", _arm_and_resume())
	var state_before: PackedFloat64Array = session.state_snapshot()
	var oracle: PackedFloat64Array = VehicleDynamics.step(state_before, session._model, session._damage.effective_controls(session._parse_controls(throttle, true).controls), Session.DT, session._road)
	_check("one kernel tick", session.tick_once(throttle))
	_check("kernel tick is byte-identical to VehicleDynamics.step", oracle.to_byte_array() == session.state_snapshot().to_byte_array())
	# A kernel fault reaches the session as its own fault and rolls the state back.
	var state_at_fault: PackedByteArray = session.state_snapshot().to_byte_array()
	sim.model.input_size = 5 # illegal mid-run change: the kernel's input guard must refuse the next tick
	_check("kernel refusal faults the session", not session.tick_once(throttle) and session.fault_reason.begins_with("ground-vehicle kernel") and session.paused, session.fault_reason)
	_check("faulted tick leaves the committed state", session.state_snapshot().to_byte_array() == state_at_fault)
	sim.model.input_size = 4
	_check("reset clears the fault through a fresh kernel reset", session.reset() and session.fault_reason.is_empty() and sim.tick == 0 and sim.fault_reason.is_empty())
	session.free()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _combined(sim: Node) -> PackedFloat64Array:
	var out: PackedFloat64Array = sim.state.duplicate()
	out.append_array(sim.continuous)
	return out
