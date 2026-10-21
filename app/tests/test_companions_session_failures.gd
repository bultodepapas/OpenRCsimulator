# AFC-01: real seeded failure onset through the controllerless session seam.
# Ordinary/manual and external sessions receive the same trim-relative commands.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RB := preload("res://physics/rigid_body.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail: Variant = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s: %s" % [label, str(detail)])


func _new_session(external: bool) -> Session:
	var session := Session.new()
	session.input_enabled = false
	session.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	_check("failure fixture is flyable", session.is_flyable())
	if external:
		_check("failure fixture accepts external driver at tick zero", session.configure_external_driver())
	var initial: PackedFloat64Array = session.sim.state.duplicate()
	initial[RB.POS + 2] = -1000.0
	_check("failure fixture starts clear of ground", session.sim.reset(initial) and session._failure_airborne())
	_check("failure fixture resolves the same seeded plan", session.setup_failures({
		probability_percent = 100, include_catastrophic = false, notify = true,
	}, 1751), session.failure_error)
	return session


func _packet(session: Session, roll: float = 0.0) -> Dictionary:
	return {roll = roll, pitch = 0.0, yaw = 0.0, throttle = float(session.start.throttle)}


func _step(session: Session, packet: Dictionary) -> bool:
	if session.external_driver_enabled:
		var staged: Dictionary = session.prepare_external_tick(packet)
		return bool(staged.get("ok", false)) and session.step_external_tick()
	session.commands = packet.duplicate(true)
	session.raw = packet.duplicate(true)
	session.sim.inputs = session._inputs()
	var tick: int = session.sim.tick
	if session._session_after_input():
		session.sim.step()
	return session.sim.tick == tick + 1 and session.sim.fault_reason.is_empty()


func _same_tick(left: Session, right: Session) -> bool:
	for field: String in ["state", "previous", "continuous", "aux", "inputs", "last_loads"]:
		var lhs: PackedFloat64Array = left.sim.get(field)
		var rhs: PackedFloat64Array = right.sim.get(field)
		if lhs.to_byte_array() != rhs.to_byte_array():
			return false
	return left.sim.tick == right.sim.tick and left.sim.time() == right.sim.time() \
		and left.sim.modes == right.sim.modes and left.commands == right.commands and left.raw == right.raw \
		and left._failures.snapshot() == right._failures.snapshot() \
		and var_to_bytes(left.contact_events()) == var_to_bytes(right.contact_events())


func _committed_bytes(sim: Object) -> PackedByteArray:
	# Faulted kernels deliberately refuse checkpoint production; compare retained fields directly.
	var values: Array = []
	for field: String in ["state", "previous", "continuous", "aux", "inputs", "modes", "last_loads",
		"tick", "stop_at_tick", "mass", "gravity", "inertia", "_inertia_inv", "_inertia_cache",
		"_last_valid_state", "_last_valid_previous", "_last_valid_continuous", "_last_valid_aux",
		"_last_valid_inputs", "_last_valid_modes", "_last_valid_loads", "_last_valid_tick",
		"_last_valid_stop", "_last_valid_mass", "_last_valid_gravity", "_last_valid_inertia"]:
		values.append(sim.get(field))
	return var_to_bytes(values)


func _initialize() -> void:
	var ordinary := _new_session(false)
	var external := _new_session(true)
	var plan: Dictionary = ordinary._failures.plan()
	var onset: int = int(plan.get("onset_airborne_ticks", -1))
	_check("roll-jam fixture retains its real twenty-second onset", str(plan.get("id", "")) == "roll_jam"
		and onset == 4800 and external._failures.plan() == plan, plan)
	if onset != 4800:
		ordinary.free()
		external.free()
		_finish()
		return
	var notices := [0, 0]
	ordinary.failure_changed.connect(func() -> void: notices[0] += 1)
	external.failure_changed.connect(func() -> void: notices[1] += 1)
	var first_mismatch := -1
	var reached := true
	for tick in range(1, onset):
		var normal_step := _step(ordinary, _packet(ordinary))
		var external_step := _step(external, _packet(external))
		if not normal_step or not external_step:
			reached = false
			break
		if first_mismatch < 0 and not _same_tick(ordinary, external):
			first_mismatch = tick
	_check("every pre-onset physical/control/failure/contact frame matches", reached
		and first_mismatch == -1 and ordinary.sim.tick == onset - 1 and external.sim.tick == onset - 1,
		{first_mismatch = first_mismatch, ordinary_tick = ordinary.sim.tick, external_tick = external.sim.tick})
	_check("no early activation or notice", not ordinary.failure_status().get("active", true)
		and not external.failure_status().get("active", true) and notices == [0, 0])
	var before_onset: Dictionary = external.checkpoint()
	_check("external pre-onset checkpoint is complete", not before_onset.is_empty()
		and before_onset.get("failure_state", {}).get("airborne_ticks", -1) == onset - 1)
	var ordinary_onset := _step(ordinary, _packet(ordinary))
	var external_onset := _step(external, _packet(external))
	_check("external seam commits the same accepted onset", ordinary_onset and external_onset
		and _same_tick(ordinary, external) and external.failure_status().get("active", false)
		and external.failure_status().get("activation_tick", -1) == onset)
	_check("accepted onset emits exactly one notice per session", notices == [1, 1])
	var onset_checkpoint: Dictionary = external.checkpoint()
	var jam: float = float(external._failures.snapshot().jam_positions[0])
	var opposite: float = -0.8 if jam > -0.75 else 0.8
	var normal_jam := _step(ordinary, _packet(ordinary, opposite))
	var external_jam := _step(external, _packet(external, opposite))
	_check("opposing command is recorded while the actual servo remains jammed", normal_jam and external_jam
		and _same_tick(ordinary, external) and external.commands.roll == opposite
		and absf(external.sim.inputs[0] - jam) > 0.5
		and external.sim.aux[Session.AUX_SERVO] == jam and notices == [1, 1])

	# A rejected accepted-step candidate must not commit the staged failure or consume a second packet.
	var rollback := _new_session(true)
	var rollback_notices := [0]
	rollback.failure_changed.connect(func() -> void: rollback_notices[0] += 1)
	var restored: bool = rollback.restore_checkpoint(before_onset)
	_check("external session restores the pre-onset boundary", restored)
	if restored:
		_check("restored external flight stays paused until explicit resume", rollback.sim.paused
			and not _step(rollback, _packet(rollback)) and rollback.sim.tick == onset - 1
			and not rollback._external_packet_ready and not rollback.failure_status().get("active", true))
		rollback.resume()
		var committed_before: PackedByteArray = _committed_bytes(rollback.sim)
		var failure_before: Dictionary = rollback._failures.snapshot()
		var contact_before: PackedByteArray = var_to_bytes(rollback.contact_events())
		var original_post_tick: Callable = rollback.sim.model.post_tick
		rollback.sim.model.post_tick = func(previous: PackedFloat64Array, candidate: PackedFloat64Array, tick: int) -> PackedFloat64Array:
			if original_post_tick.is_valid():
				original_post_tick.call(previous, candidate, tick)
			return PackedFloat64Array([NAN])
		var rejected: bool = _step(rollback, _packet(rollback))
		_check("rejected external onset leaves all committed state and observers unchanged", not rejected
			and rollback.sim.tick == onset - 1
			and rollback.sim.fault_reason == "step rejected: post-step contact filter returned a malformed body state"
			and _committed_bytes(rollback.sim) == committed_before
			and rollback._failures.snapshot() == failure_before
			and var_to_bytes(rollback.contact_events()) == contact_before and rollback_notices[0] == 0)
		_check("rejected packet is consumed exactly once", not rollback._external_packet_ready
			and not rollback.step_external_tick() and rollback.sim.tick == onset - 1)
		rollback.sim.model.post_tick = original_post_tick
		_check("explicit restore recovers the external onset fixture", rollback.restore_checkpoint(before_onset))
		rollback.resume()
		var recovery: bool = _step(rollback, _packet(rollback))
		_check("fresh packet after restore commits byte-exact onset once", recovery
			and var_to_bytes(rollback.checkpoint()) == var_to_bytes(onset_checkpoint)
			and rollback_notices[0] == 1)
	for session: Session in [ordinary, external, rollback]:
		session.free()
	_finish()


func _finish() -> void:
	print("companion session failures: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
