# Audit observation probe; run with the repository checked launcher on the pinned build.
# This is a narrowly initialized final-lap *state*, with a disarmed moving vehicle, NOT a reachable pilot tape.
# It tests one real Session.tick_once -> kernel RK4 -> plant endpoint -> race wrapper/director tick.
# It performs no result-file writes. A passing OBSERVED check is the baseline defect and must change after repair.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Track := preload("res://sim/race/track.gd")
const Gates := preload("res://sim/race/gate_crossing.gd")
const Director := preload("res://sim/race/race_director.gd")
const RaceModel := preload("res://sim/race/race_model.gd")
const TRACK := "res://data/race/tracks/openrc-practice-oval-1.json"
const DT := 1.0 / 240.0

func _initialize() -> void:
	_run.call_deferred()

func _world_velocity(body: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_rotate(M.quat(body[RB.ATT], body[RB.ATT + 1], body[RB.ATT + 2], body[RB.ATT + 3]),
		M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2]))

func _run() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	var s := Session.new()
	root.add_child(s)
	if not loaded.ok or not s.prepare(loaded.get("field", {}), {race_track = TRACK}):
		print("INCONCLUSIVE: fixture preparation ", s.load_error)
		quit(2)
		return
	var gate: Dictionary = s.course.gates.back()
	var radius: float = float(s._body_radius)
	var across: float = float(gate.w) - (radius - 0.0006)
	var envelope: Dictionary = s.checkpoint()
	if envelope.is_empty():
		print("INCONCLUSIVE: no initial envelope")
		quit(2)
		return
	var body: PackedFloat64Array = envelope.kernel.state.duplicate()
	for i in 3:
		body[RB.POS + i] = float(gate.c[i]) - 0.04 * float(gate.n[i]) + across * float(gate.u[i])
		body[RB.VEL + i] = 24.0 * float(gate.n[i])
		body[RB.RATE + i] = 0.0
	body[RB.ATT] = 1.0
	for i in range(1, 4):
		body[RB.ATT + i] = 0.0
	envelope.kernel.state = body.duplicate()
	envelope.kernel.previous = body.duplicate()
	envelope.kernel.tick = 1200
	var aux: PackedFloat64Array = envelope.kernel.aux.duplicate()
	aux[RaceModel.AUX_GO_TIME] = 1.0
	aux[RaceModel.AUX_LAP_START] = 4.0
	aux[RaceModel.AUX_LAP_DURATION] = 1.0
	aux[RaceModel.AUX_LAP_DURATION + 1] = 2.0
	aux[RaceModel.AUX_LAST_GATE_TIME] = 4.0
	aux[RaceModel.AUX_ATTEMPT_START] = 1.0
	envelope.kernel.aux = aux
	var modes: PackedInt64Array = envelope.kernel.modes.duplicate()
	modes[RaceModel.MODE_PHASE] = Director.PHASE_RACING
	modes[RaceModel.MODE_ATTEMPT] = 1
	modes[RaceModel.MODE_VALID_LAPS] = 2
	modes[RaceModel.MODE_NEXT_GATE] = int(s.course.gate_count) - 1
	modes[RaceModel.MODE_GATES_TOTAL] = 3 * int(s.course.gate_count) - 1
	envelope.kernel.modes = modes
	if not s.restore_checkpoint(envelope) or not s.resume():
		print("INCONCLUSIVE: initialized state refused: ", s.load_error)
		quit(2)
		return
	var before: PackedFloat64Array = s.frame().body.duplicate()
	var p0: PackedFloat64Array = before.slice(RB.POS, RB.POS + 3)
	var clear_before: float = s.plant.obstacle.call(p0[0], p0[1], p0[2])
	if not s.tick_once(FC.neutral_input()):
		print("INCONCLUSIVE: real physics tick refused: ", s.fault_reason)
		quit(2)
		return
	var after: PackedFloat64Array = s.frame().body.duplicate()
	var p1: PackedFloat64Array = after.slice(RB.POS, RB.POS + 3)
	var rules: Dictionary = Track.ruleset()
	var crossing: Dictionary = Gates.crossing(gate, p0, 5.0, p1, 5.0 + DT,
		Gates.chord_bound_m(float(rules.acceleration_envelope_mps2), DT))
	if not crossing.crossed or not crossing.direction_ok:
		print("INCONCLUSIVE: actual chord missed final forward crossing: ", crossing)
		quit(2)
		return
	var lambda_probe: float = 0.15 * float(crossing.lambda)
	var probe := PackedFloat64Array()
	for i in 3:
		probe.append(lerpf(p0[i], p1[i], lambda_probe))
	var clear_probe: float = s.plant.obstacle.call(probe[0], probe[1], probe[2])
	var dv: PackedFloat64Array = M.sub(_world_velocity(after), _world_velocity(before))
	var accel: float = M.norm(dv) / DT
	var names := PackedStringArray()
	for event: Dictionary in s.sim.last_events:
		names.append(str(event.get("type", "")))
	var result: Dictionary = s.results[0] if s.results.size() == 1 else {}
	var observed: bool = clear_before > radius and clear_probe <= radius \
		and lambda_probe < float(crossing.lambda) and crossing.status == Gates.STATUS_INSIDE \
		and accel <= float(rules.acceleration_envelope_mps2) \
		and str(s.crash.get("reason", "")) == "Obstacle strike" \
		and ",".join(names) == "race_gate,race_lap,race_finish,crash" \
		and bool(result.get("valid", false)) and str(result.get("phase", "")) == "FINISHED"
	print("%s real wrapped tick from initialized final-lap state; NOT a flown tape" % ("OBSERVED" if observed else "NOT OBSERVED"))
	print("radius=%.9f clear_before=%.9f clear_before_plane=%.9f crossing_lambda=%.9f accel=%.4f events=%s" %
		[radius, clear_before, clear_probe, float(crossing.lambda), accel, ",".join(names)])
	print("tick=%d motor_before=%d crash=%s result_valid=%s" % [s.sim.tick, int(envelope.kernel.modes[FC.MODE_MOTOR]),
		str(s.crash), str(result.get("valid", false))])
	s.queue_free()
	quit(0 if observed else 1)
