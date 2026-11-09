extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const Weather := preload("res://physics/wind_config.gd")
const RB := preload("res://physics/rigid_body.gd")
const AVANTI_ID := "sebart-avanti-s-a200-p100rx"
const P51_PATH := "res://data/aircraft/p51d_mustang_120.json"

var checks := 0
var failures := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_test_paused_and_guarded_inputs()
	_test_precommit_fault_observers()
	_test_fault_restores_kernel_last_valid_inputs()
	_test_postcommit_fault_observers()
	_test_terminal_guard_and_countdown()
	_test_external_tick_reentry()
	_test_observer_reset_during_tick()
	_test_transition_receipts()
	_test_transition_spawn_reload_and_observer_fault()
	_test_shaft_receipt()
	print("companion external rejection: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _check(label: String, ok: bool, detail: Variant = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", str(detail))


func _new_avanti() -> Session:
	var session := Session.new()
	session.input_enabled = false
	session.setup(str(Catalog.entry(AVANTI_ID).get("data", "")), AVANTI_ID)
	_check("real Avanti fixture starts and configures external driver", session.is_flyable()
		and session.gear_is_retractable() and session.wheel_brake_available() and session.flaps_available()
		and session.sim.inputs.size() == 7 and session.configure_external_driver())
	return session


func _packet_a() -> Dictionary:
	return {roll = 0.1, pitch = -0.1, yaw = 0.05, throttle = 0.6, gear_down = true, flaps = 0.7, brake = 0.25}


func _packet_b() -> Dictionary:
	return {roll = -0.6, pitch = 0.4, yaw = -0.3, throttle = 0.3, gear_down = false, flaps = 0.1, brake = 0.75}


func _packet_c() -> Dictionary:
	return {roll = 0.25, pitch = 0.15, yaw = -0.12, throttle = 0.65, gear_down = false, flaps = 0.35, brake = 0.5}


func _step(session: Session, packet: Dictionary) -> bool:
	var staged: Dictionary = session.prepare_external_tick(packet)
	return staged.get("ok", false) and session.step_external_tick()


func _controls(session: Session) -> Dictionary:
	return {commands = session.commands.duplicate(true), raw = session.raw.duplicate(true),
		gear = session._gear_requested_down, flaps = session._flap_requested, brake = session._wheel_brake_demand,
		inputs = session.sim.inputs.duplicate(), tick = session.sim.tick}


func _matches_packet(session: Session, packet: Dictionary) -> bool:
	return session.commands == {roll = packet.roll, pitch = packet.pitch, yaw = packet.yaw, throttle = packet.throttle} \
		and session.raw == session.commands and session._gear_requested_down == packet.gear_down \
		and session._flap_requested == packet.flaps and session._wheel_brake_demand == packet.brake \
		and session.sim.inputs[4] == (1.0 if packet.gear_down else 0.0) \
		and session.sim.inputs[5] == packet.brake and session.sim.inputs[6] == packet.flaps


func _test_paused_and_guarded_inputs() -> void:
	var session := _new_avanti()
	_check("packet A commits all seven controls", _step(session, _packet_a()) and _matches_packet(session, _packet_a()))
	var accepted: Dictionary = _controls(session)
	var checkpoint: Dictionary = session.checkpoint()
	_check("accepted packet checkpoint contains seven inputs", not checkpoint.is_empty() and checkpoint.simulation.inputs.size() == 7)
	session.sim.set_paused(true)
	_check("ordinary pause refuses B and preserves accepted owner and kernel", not _step(session, _packet_b())
		and _controls(session) == accepted and not session._external_packet_ready)
	_check("ordinary paused rejection preserves the serialized checkpoint", var_to_bytes(session.checkpoint()) == var_to_bytes(checkpoint))
	session.resume()
	session.hold("test")
	_check("held guard refuses B without altering accepted controls", not _step(session, _packet_b()) and _controls(session) == accepted)
	session.release("test")
	session.resume()
	session.sim.stop_at_tick = session.sim.tick
	_check("stop-at-tick guard refuses B without altering accepted controls", not _step(session, _packet_b()) and _controls(session) == accepted)
	session.sim.stop_at_tick = -1
	_check("fresh C resumes with its own seven controls", _step(session, _packet_c()) and _matches_packet(session, _packet_c())
		and session.sim.tick == int(accepted.tick) + 1)
	session.free()


func _inject_pre_tick_fault(session: Session) -> Callable:
	var original: Callable = session.sim.model.pre_tick
	session.sim.model.pre_tick = func(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> PackedFloat64Array:
		if original.is_valid():
			original.call(aux, inputs, dt)
		return PackedFloat64Array([NAN])
	return original


func _test_precommit_fault_observers() -> void:
	var session := _new_avanti()
	_check("precommit fixture accepts A", _step(session, _packet_a()))
	var accepted: Dictionary = _controls(session)
	var checkpoint: Dictionary = session.checkpoint()
	var pause_seen: Array[Dictionary] = []
	var fault_seen: Array[Dictionary] = []
	var attempt_seen: Array[Dictionary] = []
	session.sim.paused_changed.connect(func(paused: bool) -> void:
		if paused: pause_seen.append(_controls(session)))
	session.sim.faulted.connect(func(_reason: String) -> void: fault_seen.append(_controls(session)))
	session.sim.before_step.connect(func(_tick: int) -> void: attempt_seen.append(_controls(session)))
	var original := _inject_pre_tick_fault(session)
	_check("actual pre-tick kernel rejection consumes B", not _step(session, _packet_b())
		and not session._external_packet_ready and not session.sim.fault_reason.is_empty())
	_check("before_step sees the attempted B", attempt_seen.size() == 1 and attempt_seen[0].commands.roll == _packet_b().roll,
		{attempt = attempt_seen, reason = session.sim.fault_reason})
	_check("precommit fault returns all accepted owner and kernel inputs", _controls(session) == accepted)
	_check("pause and fault observers see accepted A with restored kernel inputs", pause_seen.size() == 1 and fault_seen.size() == 1
		and pause_seen[0] == accepted and fault_seen[0] == accepted, {pause = pause_seen, fault = fault_seen, accepted = accepted})
	session.sim.model.pre_tick = original
	_check("real A checkpoint restores after kernel rejection", session.restore_checkpoint(checkpoint))
	session.resume()
	_check("fresh C commits after checkpoint recovery", _step(session, _packet_c()) and _matches_packet(session, _packet_c()))
	session.free()


func _test_fault_restores_kernel_last_valid_inputs() -> void:
	var session := _new_avanti()
	_check("invalid-prior-input fixture accepts A", _step(session, _packet_a()))
	var accepted: Dictionary = _controls(session)
	session.sim.inputs[0] = NAN
	var original := _inject_pre_tick_fault(session)
	_check("kernel fault restores last valid inputs instead of invalid pre-call values", not _step(session, _packet_b())
		and _controls(session) == accepted and is_finite(session.sim.inputs[0]))
	session.sim.model.pre_tick = original
	session.free()


func _test_postcommit_fault_observers() -> void:
	var session := _new_avanti()
	_check("postcommit fixture accepts A", _step(session, _packet_a()))
	var tick_before: int = session.sim.tick
	var pause_seen: Array[Dictionary] = []
	var fault_seen: Array[Dictionary] = []
	session.sim.paused_changed.connect(func(paused: bool) -> void:
		if paused: pause_seen.append(_controls(session)))
	session.sim.faulted.connect(func(_reason: String) -> void: fault_seen.append(_controls(session)))
	session.sim.stepped.connect(func(tick: int, _time: float, _state: PackedFloat64Array, _loads: PackedFloat64Array,
			_inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
		if tick == tick_before + 1: session.sim._fail_safe("injected postcommit observer fault"), CONNECT_ONE_SHOT)
	_check("postcommit observer fault returns false after advancing", not _step(session, _packet_b())
		and session.sim.tick == tick_before + 1 and not session.sim.fault_reason.is_empty())
	_check("accepted B remains visible after postcommit fault", _matches_packet(session, _packet_b()))
	var current: Dictionary = _controls(session)
	_check("postcommit pause and fault observers see accepted B", pause_seen.size() == 1 and fault_seen.size() == 1
		and pause_seen[0] == current and fault_seen[0] == current)
	session.free()


func _test_terminal_guard_and_countdown() -> void:
	var terminal := _new_avanti()
	_check("terminal fixture accepts A", _step(terminal, _packet_a()))
	var accepted: Dictionary = _controls(terminal)
	var ground: PackedFloat64Array = terminal.sim.state.duplicate()
	ground[RB.POS + 2] = 100.0
	terminal.sim.state = ground
	terminal.sim.previous = ground.duplicate()
	var pause_seen: Array[Dictionary] = []
	var guard_preparations: Array[Dictionary] = []
	terminal.sim.paused_changed.connect(func(paused: bool) -> void:
		if paused:
			pause_seen.append(_controls(terminal))
			guard_preparations.append(terminal.prepare_external_tick(_packet_c())))
	_check("terminal guard refuses B and commits crash effects", not _step(terminal, _packet_b())
		and not terminal.crash.is_empty() and terminal.sim.paused and _controls(terminal) == accepted)
	_check("terminal pause observes accepted A", pause_seen.size() == 1 and pause_seen[0] == accepted)
	_check("terminal guard rejects reentrant packet preparation", guard_preparations.size() == 1
		and not guard_preparations[0].ok and not terminal._external_packet_ready)
	terminal.free()

	var crashed := _new_avanti()
	_check("countdown fixture accepts A", _step(crashed, _packet_a()))
	var before: Dictionary = _controls(crashed)
	var generation: int = int(crashed.last_transition().generation)
	crashed.crash = {ticks_left = 2, why = "countdown fixture"}
	crashed.sim.set_paused(true)
	_check("first crash packet advances countdown without exposing B", not _step(crashed, _packet_b())
		and crashed.crash.ticks_left == 1 and _controls(crashed) == before)
	_check("second crash packet preserves auto-restart controls", not _step(crashed, _packet_b())
		and crashed.crash.is_empty() and crashed.sim.tick == 0 and not crashed.sim.paused
		and crashed.commands.roll == 0.0 and crashed.commands.throttle == crashed.start.throttle
		and not crashed._gear_requested_down and crashed._flap_requested == 0.0 and crashed._wheel_brake_demand == 0.0
		and crashed.last_transition().generation == generation + 1 and crashed.last_transition().kind == Session.TRANSITION_START)
	crashed.free()


func _test_external_tick_reentry() -> void:
	var session := _new_avanti()
	_check("reentry fixture accepts A", _step(session, _packet_a()))
	var observations: Array[Dictionary] = []
	session.sim.before_step.connect(func(_tick: int) -> void:
		var before: Dictionary = session._external_pending_packet.duplicate(true)
		var prepared: Dictionary = session.prepare_external_tick(_packet_c())
		var nested: bool = session.step_external_tick()
		observations.append({before = before, after = session._external_pending_packet.duplicate(true),
			prepared = prepared, nested = nested}), CONNECT_ONE_SHOT)
	_check("outer B still commits during a nested attempt", _step(session, _packet_b()) and _matches_packet(session, _packet_b()))
	_check("nested prepare and step refuse without replacing staged B", observations.size() == 1
		and not observations[0].prepared.ok and not observations[0].nested
		and observations[0].before == _packet_b() and observations[0].after == observations[0].before
		and not session._external_packet_ready)
	session.free()


func _test_observer_reset_during_tick() -> void:
	var session := _new_avanti()
	_check("reset observer fixture accepts A", _step(session, _packet_a()))
	var before: Dictionary = session.last_transition()
	var previous_tick: int = session.sim.tick
	session.sim.stepped.connect(func(tick: int, _time: float, _state: PackedFloat64Array, _loads: PackedFloat64Array,
			_inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
		if tick == previous_tick + 1: session.reset(), CONNECT_ONE_SHOT)
	_check("observer reset wins over the old attempted packet", not _step(session, _packet_b()) and session.sim.tick == 0
		and session.last_transition().generation == before.generation + 1 and session.last_transition().kind == Session.TRANSITION_START
		and session.commands.roll == 0.0 and session.commands.throttle == session.start.throttle
		and not session._gear_requested_down and session._flap_requested == 0.0 and session._wheel_brake_demand == 0.0)
	session.free()


func _test_transition_receipts() -> void:
	var pre := Session.new()
	_check("fresh session has no accepted transition receipt", pre.last_transition().is_empty())
	_check("pre-setup weather selection has no publication receipt", pre.setup_weather(Weather.preset("cool-dense"))
		and pre.last_transition().is_empty())
	pre.free()
	var session := Session.new()
	session.input_enabled = false
	var seen: Array[Dictionary] = []
	session.resetting.connect(func() -> void: seen.append(session.last_transition()))
	session.setup(str(Catalog.entry(AVANTI_ID).get("data", "")), AVANTI_ID)
	_check("first start receipt is visible during publication", session.last_transition() == {generation = 1, kind = Session.TRANSITION_START}
		and seen.size() == 1 and seen[0] == session.last_transition())
	var copy: Dictionary = session.last_transition()
	copy.generation = 99
	copy.kind = "mutated"
	_check("receipt is detached from owner metadata", session.last_transition() == {generation = 1, kind = Session.TRANSITION_START})
	var receipt_before: Dictionary = session.last_transition()
	var checkpoint_before: Dictionary = session.checkpoint()
	_check("invalid restore does not publish or change receipt", not session.restore_checkpoint({})
		and session.last_transition() == receipt_before and seen.size() == 1)
	_check("receipt access leaves physical checkpoint unchanged", var_to_bytes(checkpoint_before) == var_to_bytes(session.checkpoint()))
	var trim_before: float = session.trim_throttle
	session.trim_throttle = 0.0
	session.reset()
	_check("refused reset preparation does not publish", session.last_transition() == receipt_before
		and seen.size() == 1 and not session.start_error.is_empty())
	session.trim_throttle = trim_before
	_check("invalid weather leaves receipt unchanged", not session.setup_weather({bad = true})
		and session.last_transition() == receipt_before and seen.size() == 1)
	_check("accepted weather publishes its distinct receipt", session.setup_weather(Weather.preset("cool-dense"))
		and session.last_transition() == {generation = 2, kind = Session.TRANSITION_WEATHER}
		and seen.back() == session.last_transition())
	session.reset()
	_check("reset after weather publishes start receipt", session.last_transition() == {generation = 3, kind = Session.TRANSITION_START}
		and seen.back() == session.last_transition())
	var checkpoint: Dictionary = session.checkpoint()
	_check("valid restore publishes restore receipt", not checkpoint.is_empty() and session.restore_checkpoint(checkpoint)
		and session.last_transition() == {generation = 4, kind = Session.TRANSITION_RESTORE}
		and seen.back() == session.last_transition())
	_check("receipt stays outside checkpoint schema", not session.checkpoint().has("last_transition")
		and not session.checkpoint().has("transition_generation"))
	var before_spawn: Dictionary = session.last_transition()
	_check("invalid spawn does not publish", not session.external_spawn_airborne(INF, 0.0, 100.0, 0.0)
		and session.last_transition() == before_spawn)
	session.free()


func _test_transition_spawn_reload_and_observer_fault() -> void:
	var spawn := _new_avanti()
	var initial: Dictionary = spawn.last_transition()
	var spawn_seen: Array[Dictionary] = []
	spawn.resetting.connect(func() -> void: spawn_seen.append(spawn.last_transition()))
	_check("accepted external spawn publishes start", spawn.external_spawn_airborne(10.0, 20.0, 100.0, 0.2)
		and spawn.last_transition() == {generation = int(initial.generation) + 1, kind = Session.TRANSITION_START}
		and spawn_seen.size() == 1 and spawn_seen[0] == spawn.last_transition())
	spawn.free()
	var reload := Session.new()
	reload.input_enabled = false
	reload.setup(str(Catalog.entry(AVANTI_ID).get("data", "")), AVANTI_ID)
	var before_reload: Dictionary = reload.last_transition()
	var message: String = reload.reload()
	_check("accepted reload publishes start", message.begins_with("aircraft reloaded")
		and reload.last_transition() == {generation = int(before_reload.generation) + 1, kind = Session.TRANSITION_START}, message)
	reload.free()
	var fault := Session.new()
	fault.input_enabled = false
	fault.setup(str(Catalog.entry(AVANTI_ID).get("data", "")), AVANTI_ID)
	var before_fault: Dictionary = fault.last_transition()
	var observed: Array[Dictionary] = []
	fault.resetting.connect(func() -> void:
		observed.append(fault.last_transition())
		fault.sim.mass = 0.0, CONNECT_ONE_SHOT)
	fault.reset()
	_check("accepted reset observer fault still publishes its committed receipt", not fault.sim.reset_observer_fault.is_empty()
		and fault.last_transition() == {generation = int(before_fault.generation) + 1, kind = Session.TRANSITION_START}
		and observed.size() == 1 and observed[0] == fault.last_transition() and fault.sim.paused)
	fault.free()


func _test_shaft_receipt() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(P51_PATH))
	raw.propulsion.erase("fuel_consumption")
	raw.capabilities.energy = "prescribed_fuel"
	var checked: Dictionary = AircraftData.validate_and_derive(raw)
	var profiled: Dictionary = WheelProfiles.apply_to_model(checked.model)
	checked.model = profiled.model
	checked.wheel_profile_identity = profiled.identity
	var session := Session.new()
	session.input_enabled = false
	session.setup(P51_PATH)
	_check("shaft fixture applies real legacy propulsion model", checked.ok and profiled.ok and session._apply(checked))
	_check("shaft fixture selects split mode", session.setup_shaft_integrator("split"))
	session.reset()
	var seen: Array[Dictionary] = []
	session.resetting.connect(func() -> void: seen.append(session.last_transition()))
	var before: Dictionary = session.last_transition()
	_check("invalid shaft selection does not publish", not session.setup_shaft_integrator("unknown")
		and session.last_transition() == before and seen.is_empty())
	_check("shaft selection publishes distinct receipt", session.setup_shaft_integrator("coupled-rk4")
		and session.last_transition() == {generation = int(before.generation) + 1, kind = Session.TRANSITION_SHAFT}
		and seen.size() == 1 and seen[0] == session.last_transition())
	var selected: Dictionary = session.last_transition()
	_check("reselecting same shaft emits no receipt", session.setup_shaft_integrator("coupled-rk4")
		and session.last_transition() == selected and seen.size() == 1)
	session.reset()
	_check("reset after shaft selection publishes start", session.last_transition() == {generation = int(selected.generation) + 1, kind = Session.TRANSITION_START}
		and seen.back() == session.last_transition())
	session.free()
