extends SceneTree

const Session = preload("res://sim/helicopter_flight_session.gd")
const Field = preload("res://data/field_loader.gd")
const Wind = preload("res://physics/wind_config.gd")
const Rotor = preload("res://physics/rotorcraft/main_rotor.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const DOMAIN_REASON = "main-rotor advance ratio exceeds the kernel domain at this speed"

var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _session() -> Node:
	var result: Node = Session.new()
	result.physics_enabled = false
	result.input_enabled = false
	root.add_child(result)
	return result


func _frame(session: Node) -> PackedByteArray:
	return var_to_bytes([session.sim.tick, session.sim.state, session.sim.continuous,
		session.sim.aux, session.sim.inputs, session.sim.last_loads, session.shaft_phase])


func _unpublished_candidates() -> void:
	var session: Node = _session()
	var ready: bool = session.setup() and session.reset()
	check("airborne reference session starts", ready and session.stage_domain_diagnostics().is_empty())
	if not ready:
		session.free()
		return
	var prior: PackedByteArray = var_to_bytes(session.checkpoint())
	var candidate: PackedFloat64Array = session.sim.state.duplicate()
	candidate[RB.VEL] = 500.0
	var refused: Dictionary = session.sim.prepare_reset(candidate)
	check("detached rotor-domain reset preparation refuses", not refused.get("ok", false))
	check("rejected preparation leaves live checkpoint unchanged", prior == var_to_bytes(session.checkpoint()))
	check("rejected preparation publishes no fault receipt", session.stage_domain_diagnostics().is_empty())
	session.sim.inputs[0] = NAN
	session.sim.step()
	check("unrelated input fault excludes stale rotor cause", session.sim.fault_reason.contains("input or auxiliary")
		and not session.pause_reason.contains(DOMAIN_REASON) and session.stage_domain_diagnostics().is_empty())
	check("reset recovers after unrelated input fault", session.reset() and session.is_flyable())

	refused = session.sim.prepare_reset(candidate)
	var accepted: Dictionary = session.sim.prepare_reset(session.sim.state.duplicate())
	check("valid detached preparation follows refusal without publication", not refused.get("ok", false)
		and accepted.get("ok", false) and session.stage_domain_diagnostics().is_empty())
	session.sim.step()
	check("valid tick after detached refusal has no rotor receipt", session.is_flyable()
		and session.sim.tick == 1 and session.stage_domain_diagnostics().is_empty())

	refused = session.sim.prepare_reset(candidate)
	var original_stage: Callable = session.sim.model.stage
	session.sim.model.stage = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array, _time: float) -> Dictionary: return {}
	session.sim.step()
	check("different stage refusal cannot claim earlier candidate", not refused.get("ok", false)
		and session.sim.fault_reason.contains("joint stage") and not session.pause_reason.contains(DOMAIN_REASON)
		and session.stage_domain_diagnostics().is_empty())
	session.sim.model.stage = original_stage
	check("reset recovers after unrelated joint-stage failure", session.reset() and session.is_flyable())
	session.free()


func _actual_gust() -> void:
	var session: Node = _session()
	var weather: Dictionary = Wind.defaults()
	weather.speed_mps = 15.0
	weather.from_deg = 0.0
	weather.gust_mps = 8.0
	weather.gust_duration_s = 12.0
	weather.gust_period_s = 120.0
	weather.gust_delay_s = 0.0
	var ready: bool = session.setup() and session.set_field(Field.load_from().field) and session.setup_weather(weather) and session.set_start_choice("ground") and session.reset()
	check("admitted gust ground start succeeds with no diagnostic", ready and session.stage_domain_diagnostics().is_empty())
	if not ready:
		session.free()
		return
	check("stopped start has zero head speed", session.sim.continuous[0] == 0.0)
	check("normal ground lifecycle arms and releases hold", session.toggle_motor_arm() and session.set_drive_hold(false))
	var original_stage: Callable = session.sim.model.stage
	var failed_trial := {}
	session.sim.model.stage = func(body: PackedFloat64Array, continuous: PackedFloat64Array, time: float) -> Dictionary:
		var result: Dictionary = original_stage.call(body, continuous, time)
		if result.is_empty() and session._stage_failure == DOMAIN_REASON:
			failed_trial.body = body.duplicate()
			failed_trial.continuous = continuous.duplicate()
			failed_trial.time = time
			failed_trial.wind = session.wind_at(time, body)
		return result
	var observed := {}
	session.sim.faulted.connect(func(_reason: String) -> void:
		observed.frame = _frame(session)
		observed.receipt = session.stage_domain_diagnostics())
	var saved: Dictionary = {}
	var hashes: Array = []
	var before_fault: PackedByteArray = PackedByteArray()
	for i: int in 1000:
		var before: PackedByteArray = _frame(session)
		session.sim.step()
		if not session.is_flyable():
			before_fault = before
			break
		hashes.append(_frame(session).hex_encode().sha256_text())
		if session.sim.tick == 360:
			saved = session.checkpoint()
	check("gust fails at the known intermediate startup stage", session.sim.tick == 740
		and session.sim.fault_reason.contains("RK joint stage") and not failed_trial.is_empty())
	check("refused tick rolls back before fault publication", before_fault == _frame(session)
		and observed.get("frame", PackedByteArray()) == before_fault)
	var diagnostic: Dictionary = session.stage_domain_diagnostics()
	check("fault observer receives a detached diagnostic", diagnostic.get("ok", false)
		and observed.get("receipt", {}) == diagnostic)
	if diagnostic.get("ok", false) and not failed_trial.is_empty():
		var body: PackedFloat64Array = failed_trial.body
		var q: PackedFloat64Array = M.q_normalized(body.slice(RB.ATT, RB.ATT + 4))
		var velocity_ned: PackedFloat64Array = M.q_rotate(q, body.slice(RB.VEL, RB.VEL + 3))
		var cg_air: PackedFloat64Array = M.q_rotate(M.q_conj(q), M.sub(velocity_ned, failed_trial.wind))
		var rates: PackedFloat64Array = body.slice(RB.RATE, RB.RATE + 3)
		var model: Dictionary = session.aircraft.context.main_model
		var hub: PackedFloat64Array = M.add(cg_air, M.cross(rates, M.v3(model.hub_x_m, model.hub_y_m, model.hub_z_m)))
		var expected: Dictionary = Rotor.domain_diagnostics(model, failed_trial.continuous[0], hub)
		check("reported hub uses trial wind, attitude and rate cross hub arm", var_to_bytes(expected) == var_to_bytes(diagnostic))
		check("failed trial differs from restored head speed", diagnostic.head_speed_rad_s != session.sim.continuous[0]
			and diagnostic.head_speed_rad_s == failed_trial.continuous[0])
		check("nonzero body rates actually alter hub air velocity", M.norm(rates) > 0.0 and hub.to_byte_array() != cg_air.to_byte_array())
		check("refusal identifies required invalid algebraic member", diagnostic.standard_member_required
			and diagnostic.standard_algebraic_mu_valid == false and diagnostic.mu_squared >= 2.0
			and diagnostic.pole_factor <= 0.0)
		check("reported signed hub velocity matches the refused trial", session.pause_reason.contains(str(hub)))
		check("report labels signed flow, ratios, boundaries and limit provenance", session.pause_reason.contains("air-relative FRD")
			and session.pause_reason.contains("mu_x") and session.pause_reason.contains("mu_y")
			and session.pause_reason.contains("standard member required") and session.pause_reason.contains("valid false")
			and session.pause_reason.contains("pole factor") and session.pause_reason.contains("not a validated aircraft limit"))
		var original_regime: String = diagnostic.regime
		diagnostic.regime = "caller mutation"
		check("published diagnostic cannot be mutated by a caller", session.stage_domain_diagnostics().regime == original_regime)
		diagnostic = session.stage_domain_diagnostics()

	check("mid-spool checkpoint exists", not saved.is_empty())
	var expected_tail: Array = hashes.slice(360)
	check("restore after fault succeeds and clears terminal receipt", session.restore_checkpoint(saved).get("ok", false)
		and session.stage_domain_diagnostics().is_empty())
	session.resume()
	var replay: Array = []
	for i: int in expected_tail.size():
		session.sim.step()
		if not session.is_flyable(): break
		replay.append(_frame(session).hex_encode().sha256_text())
	check("restored startup continuation replays accepted states exactly", replay == expected_tail)
	session.sim.step()
	var old_receipt: Dictionary = session.stage_domain_diagnostics()
	check("replay reaches same failed trial and receipt", not session.is_flyable() and old_receipt == diagnostic)

	var old_body: PackedByteArray = session.sim.state.to_byte_array()
	var old_continuous: PackedByteArray = session.sim.continuous.to_byte_array()
	var old_phase: PackedByteArray = session.shaft_phase.to_byte_array()
	var old_tick: int = session.sim.tick
	var notifications := {count=0}
	session.resetting.connect(func() -> void: notifications.count += 1)
	session.sim.model.stage = func(body: PackedFloat64Array, continuous: PackedFloat64Array, time: float) -> Dictionary:
		var bad_body: PackedFloat64Array = body.duplicate()
		bad_body[RB.VEL] = 1.0e200
		var bad_continuous: PackedFloat64Array = continuous.duplicate()
		bad_continuous[0] = 17.0
		return original_stage.call(bad_body, bad_continuous, time)
	var reset_ok: bool = session.reset()
	check("refused start reports unavailable diagnostic without invented values", not reset_ok
		and session.start_error.contains(DOMAIN_REASON) and session.start_error.contains("diagnostic unavailable"))
	check("refused start neither commits nor notifies", notifications.count == 0 and session.sim.tick == old_tick
		and session.sim.state.to_byte_array() == old_body and session.sim.continuous.to_byte_array() == old_continuous
		and session.shaft_phase.to_byte_array() == old_phase)
	check("refused start retains prior terminal diagnostic", session.stage_domain_diagnostics() == old_receipt)
	session.sim.model.stage = original_stage
	check("accepted reset clears terminal diagnostic", session.reset() and session.is_flyable()
		and session.stage_domain_diagnostics().is_empty())
	session.free()


func _publication_guard() -> void:
	var session: Node = _session()
	var ready: bool = session.setup() and session.reset()
	check("observer mutation fixture starts", ready)
	if not ready:
		session.free()
		return
	var observed := {}
	session.resetting.connect(func() -> void:
		session._stage_domain_diagnostics = {"ok": true, "origin": "observer"}
		session._fault_domain_diagnostics = {"ok": true, "origin": "observer"}
		observed.receipt = session.stage_domain_diagnostics())
	var accepted: bool = session.reset()
	check("reset observer cannot publish a fabricated terminal receipt", observed.get("receipt", {}).is_empty())
	check("reset observer mutation is detected", not accepted and not session.sim.reset_observer_fault.is_empty())
	check("reset observer cannot retain altered diagnostic owner", session._stage_domain_diagnostics.is_empty()
		and session._fault_domain_diagnostics.is_empty() and session.stage_domain_diagnostics().is_empty())
	session.free()

	var restored: Node = _session()
	ready = restored.setup() and restored.reset()
	check("restore observer fixture starts", ready)
	if not ready:
		restored.free()
		return
	var saved: Dictionary = restored.checkpoint()
	var seen := {}
	restored.resetting.connect(func() -> void:
		restored._stage_domain_diagnostics = {"ok": true, "origin": "restore observer"}
		restored._fault_domain_diagnostics = {"ok": true, "origin": "restore observer"}
		seen.receipt = restored.stage_domain_diagnostics())
	var outcome: Dictionary = restored.restore_checkpoint(saved)
	check("restore observer cannot publish without a terminal fault", outcome.get("ok", false)
		and seen.get("receipt", {}).is_empty() and restored.stage_domain_diagnostics().is_empty())
	restored.sim.inputs[0] = NAN
	restored.sim.step()
	check("pre-stage fault after restore discards fabricated receipt", restored.sim.fault_reason.contains("input or auxiliary")
		and restored.stage_domain_diagnostics().is_empty() and not restored.pause_reason.contains(DOMAIN_REASON))
	restored.free()


func _run() -> void:
	_unpublished_candidates()
	_actual_gust()
	_publication_guard()
	print("HELI A20 runtime rotor refusal: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
