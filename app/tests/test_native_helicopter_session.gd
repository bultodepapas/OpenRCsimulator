## NK-3 helicopter native session ownership, reset, restore and guard checks.
## The reference-only branch runs without an installed native library.
extends SceneTree

const Session := preload("res://sim/helicopter_flight_session.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Weather := preload("res://physics/wind_config.gd")

var checks := 0
var failures := 0
var field := {}
var native_available := false
var _finished := false
var _native_exercised := false
var _native_tapes := 0


## This exercises the production owner's installed-stage lifecycle without
## claiming C++ execution or substituting for the verified-library tests.
class MockNativeStage:
	extends RefCounted
	var context_calls := 0
	var last_context := {}
	var identity_root: Dictionary
	var events_root: Array[Dictionary]
	var trim_root: Dictionary
	var identity_values: Dictionary
	var events_values: Array[Dictionary]
	var trim_values: Dictionary

	func owns_stage(session: Node) -> bool:
		return session.sim.model.stage == Callable(self, "stage")

	func configuration_matches(session: Node) -> bool:
		return owns_stage(session) and session._ready_to_fly \
			and is_same(identity_root, session.sim.model.identity) and is_same(events_root, session.sim.model.events) \
			and is_same(trim_root, session._trim)

	func backend_identity() -> Dictionary:
		return {backend = NativeStage.BACKEND_NATIVE, backend_version = "mock", abi_version = 0,
			binary_sha256 = "a".repeat(64), source_sha256 = "b".repeat(64), lock_sha256 = "c".repeat(64)}

	func restore_configuration_guard(session: Node) -> bool:
		if not owns_stage(session) or session.sim.model.identity != identity_values \
				or session.sim.model.events != events_values or session._trim != trim_values: return false
		identity_root = session.sim.model.identity
		events_root = session.sim.model.events
		trim_root = session._trim
		return configuration_matches(session)

	func tick_context(session: Node, aux: PackedFloat64Array, inputs: PackedFloat64Array, time: float) -> bool:
		context_calls += 1
		last_context = {aux = aux.duplicate(), inputs = inputs.duplicate(), time = time,
			mode = session.flight_mode, trainer = session.trainer_enabled,
			hold = session.zero_drive_hold, power = session.power.duplicate()}
		return true

	func stage(body: PackedFloat64Array, continuous: PackedFloat64Array, time: float) -> Dictionary:
		return _owner._stage(body, continuous, time)

	var _owner: Node

	func restore_reference_callback(session: Node) -> void:
		if owns_stage(session): session.sim.model.stage = Callable(session, "_stage")

	func last_failure() -> String:
		return ""


func _attach_mock_stage(session: Node) -> MockNativeStage:
	session._detach_stage_backend()
	var helper := MockNativeStage.new()
	helper._owner = session
	helper.identity_root = session.sim.model.identity
	helper.events_root = session.sim.model.events
	helper.trim_root = session._trim
	helper.identity_values = session.sim.model.identity.duplicate(true)
	helper.events_values = session.sim.model.events.duplicate(true)
	helper.trim_values = session._trim.duplicate(true)
	session._native_previous_pre_tick = session.sim.model.pre_tick
	session._native_stage = helper
	session.sim.model.pre_tick = Callable(session, "_kernel_pre_step")
	session.sim.model.stage = Callable(helper, "stage")
	return helper


func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _session(mode: String, start := "airborne") -> Node:
	var session: Node = Session.new()
	session.input_enabled = false
	session.physics_enabled = false
	check("backend selection " + mode, session.setup_stage_backend(mode))
	check("helicopter setup " + mode, session.setup())
	check("helicopter field " + mode, session.set_field(field))
	check("helicopter start " + mode, session.set_start_choice(start))
	check("helicopter reset " + mode, session.reset(), session.start_error)
	return session


func _physical(session: Node) -> PackedByteArray:
	var sim: Node = session.sim
	return var_to_bytes([sim.tick, sim.state, sim.previous, sim.aux, sim.continuous, sim.inputs,
		sim.last_loads, sim.modes, sim.last_events, session.shaft_phase])


func _steps(native: Node, reference: Node, count: int, label: String) -> void:
	var same := true
	var covered := true
	var ran := 0
	var previous: Dictionary = native._native_stage.stage_stats()
	for i: int in count:
		var input := PackedFloat64Array([0.01 if i % 4 < 2 else -0.01, 0.005 if i % 6 < 3 else -0.005,
			0.0, float(reference.commands.throttle)])
		for session: Node in [native, reference]:
			for axis: int in 4: session.commands[["roll", "pitch", "yaw", "throttle"][axis]] = input[axis]
			session.sim.inputs = input.duplicate()
			session.sim.step()
		if native.sim.tick != reference.sim.tick or not native.sim.fault_reason.is_empty() or not reference.sim.fault_reason.is_empty():
			break
		if native._native_stage == null:
			covered = false
			break
		var stats: Dictionary = native._native_stage.stage_stats()
		covered = covered and int(stats.get("stage_calls", 0)) - int(previous.get("stage_calls", 0)) >= 4 \
			and int(stats.get("context_calls", 0)) - int(previous.get("context_calls", 0)) >= 1
		previous = stats
		ran += 1
		same = same and _physical(native) == _physical(reference)
	var complete: bool = ran == count and same and covered
	check(label + " complete and identical with native calls", complete,
		"%d/%d; %s / %s" % [ran, count, native.sim.fault_reason, reference.sim.fault_reason])
	if complete: _native_tapes += 1


func _selection() -> void:
	var session: Node = Session.new()
	check("default is explicit reference", session.stage_backend_status().requested == NativeStage.BACKEND_REFERENCE \
		and session.stage_backend_identity() == NativeStage.reference_identity())
	check("unknown backend rejected", not session.setup_stage_backend("future"))
	check("valid backend before setup", session.setup_stage_backend(NativeStage.BACKEND_NATIVE))
	check("setup accepts aircraft", session.setup())
	check("choice locked after setup", not session.setup_stage_backend(NativeStage.BACKEND_REFERENCE) \
		and session.stage_backend_status().requested == NativeStage.BACKEND_NATIVE)
	session.free()


func _checkpoint_restore(native: Node, reference: Node, start: String) -> void:
	_steps(native, reference, 12, start + " initial tape")
	var native_checkpoint: Dictionary = native.checkpoint()
	var reference_checkpoint: Dictionary = reference.checkpoint()
	check(start + " reference checkpoint is historical v4", reference_checkpoint.get("format") == Session.CHECKPOINT_FORMAT \
		and not reference_checkpoint.has("stage_backend"))
	check(start + " native checkpoint identifies backend", native_checkpoint.get("format") == Session.NATIVE_CHECKPOINT_FORMAT \
		and native_checkpoint.get("stage_backend") == native.stage_backend_identity() \
		and native.trace_meta().get("stage_backend") == native.stage_backend_identity())
	var normalized: Dictionary = native_checkpoint.duplicate(true)
	normalized.erase("stage_backend")
	normalized.format = Session.CHECKPOINT_FORMAT
	check(start + " checkpoint physical bytes match", var_to_bytes(normalized) == var_to_bytes(reference_checkpoint))
	var before_native := _physical(native)
	var before_reference := _physical(reference)
	var helper: RefCounted = native._native_stage
	var malformed: Dictionary = native_checkpoint.duplicate(true)
	malformed.stage_backend.binary_sha256 = "0".repeat(64) if native_checkpoint.stage_backend.binary_sha256 != "0".repeat(64) else "1".repeat(64)
	check(start + " foreign native receipt refuses atomically", not native.restore_checkpoint(malformed).get("ok", false) \
		and _physical(native) == before_native and native._native_stage == helper and helper.owns_stage(native))
	check(start + " reference checkpoint refuses in native session", not native.restore_checkpoint(reference_checkpoint).get("ok", false) \
		and _physical(native) == before_native and native._native_stage == helper)
	check(start + " native checkpoint refuses in reference session", not reference.restore_checkpoint(native_checkpoint).get("ok", false) \
		and _physical(reference) == before_reference and reference.stage_backend_identity() == NativeStage.reference_identity())
	_steps(native, reference, 8, start + " pre-restore tape")
	check(start + " matching checkpoints restore", native.restore_checkpoint(native_checkpoint).get("ok", false) \
		and reference.restore_checkpoint(reference_checkpoint).get("ok", false))
	check(start + " restored physical bytes and owner match", _physical(native) == before_native \
		and _physical(reference) == before_reference and native._native_stage == helper and helper.owns_stage(native))
	native.sim.set_paused(false)
	reference.sim.set_paused(false)
	_steps(native, reference, 16, start + " resumed tape")


func _native_lifecycle(start: String) -> void:
	var native := _session(NativeStage.BACKEND_NATIVE, start)
	var reference := _session(NativeStage.BACKEND_REFERENCE, start)
	check(start + " native stage installed", native.stage_backend_identity().get("backend") == NativeStage.BACKEND_NATIVE \
		and native._native_stage != null and native._native_stage.owns_stage(native), str(native.stage_backend_status()))
	if native._native_stage == null:
		native.free()
		reference.free()
		return
	check(start + " initial physics matches", _physical(native) == _physical(reference))
	_checkpoint_restore(native, reference, start)
	var helper: RefCounted = native._native_stage
	native.reset()
	reference.reset()
	check(start + " reset replaces native context", native._native_stage != null and native._native_stage != helper \
		and native._native_stage.owns_stage(native) and native.sim.tick == 0 and _physical(native) == _physical(reference), str(native.stage_backend_status()))
	_steps(native, reference, 8, start + " post-reset tape")
	native.free()
	reference.free()


func _transitions() -> void:
	var session := _session(NativeStage.BACKEND_NATIVE)
	if session._native_stage == null:
		session.free()
		return
	var helper: RefCounted = session._native_stage
	var before := _physical(session)
	check("unsupported weather preserves native helper", not session.setup_weather(Weather.preset("spatial-gusty-v1")) \
		and session._native_stage == helper and helper.owns_stage(session) and _physical(session) == before)
	check("accepted weather detaches pending native stage", session.setup_weather(Weather.preset("steady")) \
		and session._native_stage == null and not session.is_flyable() and not session.stage_backend_error.is_empty())
	check("weather reset reprepares native", session.reset() and session._native_stage != null \
		and session.stage_backend_identity().backend == NativeStage.BACKEND_NATIVE, str(session.stage_backend_status()))
	helper = session._native_stage
	check("reapplying collision world invalidates the ready native stage", session.set_collision_world(session.collision_world()) \
		and session._native_stage == null and not session.is_flyable())
	check("collision world reset reprepares native", session.reset() and session._native_stage != null \
		and session._native_stage != helper and session.stage_backend_identity().backend == NativeStage.BACKEND_NATIVE, str(session.stage_backend_status()))
	helper = session._native_stage
	check("ground start change detaches pending stage", session.set_start_choice("ground") \
		and session._native_stage == null and not session.is_flyable())
	check("ground reset uses a new native fourteen-state stage", session.reset() and session._native_stage != null \
		and session._native_stage != helper and session.sim.continuous.size() == 14, str(session.stage_backend_status()))
	session.free()


func _guard() -> void:
	var session := _session(NativeStage.BACKEND_NATIVE)
	if session._native_stage == null:
		session.free()
		return
	var modified: PackedFloat64Array = session.ground_surfaces.duplicate()
	if modified.is_empty():
		check("field table guard fixture present", false)
		session.free()
		return
	modified[0] += 0.01
	session.ground_surfaces = modified
	var before_body: PackedFloat64Array = session.sim.state.duplicate()
	var before_continuous: PackedFloat64Array = session.sim.continuous.duplicate()
	session.sim.step()
	check("changed prepared surface refuses tick without advancing", session.sim.tick == 0 \
		and not session.sim.fault_reason.is_empty() and not session.stage_backend_error.is_empty() \
		and session.checkpoint().is_empty() and session.sim.state.to_byte_array() == before_body.to_byte_array() \
		and session.sim.continuous.to_byte_array() == before_continuous.to_byte_array())
	# Explicit body/continuous comparison avoids relying on the reason text or a recovered prefix.
	check("changed surface refuses with an owned native stage", session._native_stage != null \
		and session._native_stage.owns_stage(session) and session.sim.paused)
	session.free()


func _reset_rollback() -> void:
	var session := _session(NativeStage.BACKEND_NATIVE)
	var model: RefCounted = session.sim.model
	model.aux_size = session.sim.aux.size()
	model.continuous_size = session.sim.continuous.size()
	model.modes_size = session.sim.modes.size()
	model.state_layout_identity = "helicopter-native-reset-fixture-v1"
	var reject := [false]
	var attempted := [0]
	model.state_validator = func(_frame: Dictionary, context: Dictionary) -> bool:
		if reject[0] and context.tick == 0:
			attempted[0] += 1
			return false
		return true
	check("transaction fixture resets", session.reset(), session.start_error)
	if native_available:
		check("transaction fixture retains a real native stage", session._native_stage != null \
			and session._native_stage.owns_stage(session), str(session.stage_backend_status()))
	else:
		_attach_mock_stage(session)
	for _i: int in 4: session.sim.step()
	var before := _physical(session)
	var checkpoint: Dictionary = session.checkpoint()
	check("transaction fixture produces a checkpoint", not checkpoint.is_empty())
	var saved := var_to_bytes(checkpoint)
	var helper: RefCounted = session._native_stage
	var old_stage: Callable = model.stage
	var resetting_count := [0]
	session.resetting.connect(func() -> void: resetting_count[0] += 1)
	reject[0] = true
	var accepted: bool = session.reset()
	reject[0] = false
	check("rejected reset actually exercised validation", not accepted and attempted[0] > 0 and not session.start_error.is_empty())
	var physical_ok: bool = _physical(session) == before
	var model_ok: bool = session.sim.model == model
	var stage_ok: bool = model.stage == old_stage
	var helper_ok: bool = session._native_stage == helper
	var checkpoint_ok: bool = var_to_bytes(session.checkpoint()) == saved
	check("rejected reset restores owner, kernel, helper and callback", physical_ok \
		and model_ok and stage_ok and helper_ok and resetting_count[0] == 0 and checkpoint_ok,
		"physical=%s model=%s stage=%s helper=%s signals=%d checkpoint=%s backend=%s" % \
		[physical_ok, model_ok, stage_ok, helper_ok, resetting_count[0], checkpoint_ok, str(session.stage_backend_status())])
	if helper != null:
		check("old native helper remains owned after rejected reset", helper.owns_stage(session))
	var old_tick: int = session.sim.tick
	session.sim.step()
	check("flight continues after reset rollback", session.sim.tick == old_tick + 1 and session.sim.fault_reason.is_empty(),
		"before=%d after=%d fault=%s backend=%s" % [old_tick, session.sim.tick, session.sim.fault_reason, str(session.stage_backend_status())])
	session.free()


func _reset_observer_reentry() -> void:
	var session := _session(NativeStage.BACKEND_NATIVE)
	var attempted := [false]
	var accepted := [true]
	session.resetting.connect(func() -> void:
		attempted[0] = true
		accepted[0] = session.set_start_choice("ground"), CONNECT_ONE_SHOT)
	var reset_ok: bool = session.reset()
	check("reset observer cannot reenter the start transition", attempted[0] and not accepted[0] \
		and not reset_ok and session.start_choice == "airborne" and not session.is_flyable() \
		and session.sim.paused and not session.sim.reset_observer_fault.is_empty() \
		and not session.start_error.is_empty())
	var tick: int = session.sim.tick
	session.sim.step()
	check("reset observer fault prevents a subsequent tick", session.sim.tick == tick)
	session.free()
	for action: String in ["toggle_motor_arm", "set_drive_hold", "set_controller_cut", "request_flight_mode",
			"cancel_calibration", "start_calibration", "advance_calibration", "apply_controller_selection",
			"controller_disconnected", "controller_focus_lost"]:
		var controls := _session(NativeStage.BACKEND_NATIVE)
		controls.resetting.connect(func() -> void:
			if action == "set_drive_hold" or action == "set_controller_cut":
				controls.call(action, true)
			elif action == "apply_controller_selection":
				controls.call(action, -1, {}, {})
			else:
				controls.call(action), CONNECT_ONE_SHOT)
		var control_reset_ok: bool = controls.reset()
		check("reset observer cannot call " + action, not control_reset_ok \
			and controls.power.armed and not controls.zero_drive_hold and not controls._controller_cut_held \
			and controls.flight_mode == "normal" and not controls.is_flyable() \
			and controls.sim.paused and not controls.sim.reset_observer_fault.is_empty())
		controls.free()
	var direct := _session(NativeStage.BACKEND_NATIVE)
	direct.resetting.connect(func() -> void: direct.commands.roll = 0.3, CONNECT_ONE_SHOT)
	check("reset observer cannot mutate committed commands directly", not direct.reset() \
		and direct.commands.roll == 0.0 and not direct.is_flyable() and direct.sim.paused \
		and not direct.sim.reset_observer_fault.is_empty())
	direct.free()
	var weather := _session(NativeStage.BACKEND_NATIVE)
	var prior_wind: PackedFloat64Array = weather._weather._mean_ned.duplicate()
	weather.resetting.connect(func() -> void:
		var changed: PackedFloat64Array = weather._weather._mean_ned.duplicate()
		changed[0] += 1.0
		weather._weather._mean_ned = changed, CONNECT_ONE_SHOT)
	check("reset observer cannot mutate the committed weather provider", not weather.reset() \
		and weather._weather._mean_ned.to_byte_array() == prior_wind.to_byte_array() \
		and not weather.is_flyable() and weather.sim.paused and not weather.sim.reset_observer_fault.is_empty())
	weather.free()


func _restore_observer_reentry() -> void:
	for mutation: String in ["reset", "toggle_motor_arm", "direct_commands"]:
		var session := _session(NativeStage.BACKEND_NATIVE)
		var checkpoint: Dictionary = session.checkpoint()
		check("restore observer fixture has a checkpoint " + mutation, not checkpoint.is_empty())
		for _i: int in 3: session.sim.step()
		session.resetting.connect(func() -> void:
			if mutation == "direct_commands": session.commands.roll = 0.3
			else: session.call(mutation), CONNECT_ONE_SHOT)
		var result: Dictionary = session.restore_checkpoint(checkpoint)
		check("restore observer cannot reenter or mutate " + mutation, not result.get("ok", false) \
			and session.commands.roll == checkpoint.commands.roll and session.power == checkpoint.power \
			and session.sim.tick == checkpoint.simulation.tick and session.sim.paused \
			and not session.is_flyable() and not session.sim.reset_observer_fault.is_empty())
		session.free()


func _mock_native_publication() -> void:
	for mutation: String in ["set_drive_hold", "direct_commands"]:
		var session := _session(NativeStage.BACKEND_NATIVE)
		var helper := _attach_mock_stage(session)
		var saved: Dictionary = session.checkpoint()
		check("mock native owner has a v5 checkpoint", saved.get("format") == Session.NATIVE_CHECKPOINT_FORMAT \
			and saved.get("stage_backend") == helper.backend_identity() and helper.owns_stage(session))
		for _i: int in 3: session.sim.step()
		var prior_contexts: int = helper.context_calls
		session.resetting.connect(func() -> void:
			if mutation == "direct_commands": session.commands.roll = 0.3
			else: session.set_drive_hold(true), CONNECT_ONE_SHOT)
		var restored: Dictionary = session.restore_checkpoint(saved)
		check("mock native restore preflights context and guards " + mutation, not restored.get("ok", false) \
			and helper.context_calls > prior_contexts and session._native_stage == helper and helper.owns_stage(session) \
			and session.commands.roll == saved.commands.roll and session.power == saved.power \
			and session.sim.tick == saved.simulation.tick and session.sim.paused \
			and not session.is_flyable() and not session.sim.reset_observer_fault.is_empty())
		session.free()


func _publication_hold() -> void:
	for transition: String in ["reset", "restore"]:
		var session := _session(NativeStage.BACKEND_NATIVE)
		var saved: Dictionary = session.checkpoint()
		session.resetting.connect(func() -> void: session.hold("presentation"), CONNECT_ONE_SHOT)
		var accepted: bool
		if transition == "reset": accepted = session.reset()
		else: accepted = session.restore_checkpoint(saved).get("ok", false)
		check("publication permits a presentation hold during " + transition, accepted and session.is_flyable() \
			and session.holds.has("presentation") and session.sim.paused and session.sim.reset_observer_fault.is_empty())
		session.free()


func _mock_native_restore_rollback() -> void:
	var session := _session(NativeStage.BACKEND_NATIVE)
	var model: RefCounted = session.sim.model
	model.aux_size = session.sim.aux.size()
	model.continuous_size = session.sim.continuous.size()
	model.modes_size = session.sim.modes.size()
	model.state_layout_identity = "helicopter-native-restore-fixture-v1"
	var rejecting := [false]
	var calls := [0]
	model.state_validator = func(_frame: Dictionary, context: Dictionary) -> bool:
		if rejecting[0] and context.tick == 0:
			calls[0] += 1
			return calls[0] < 2
		return true
	check("restore rollback fixture resets", session.reset(), session.start_error)
	var helper := _attach_mock_stage(session)
	var target: Dictionary = session.checkpoint()
	check("restore rollback fixture captures native checkpoint", not target.is_empty())
	for _i: int in 4: session.sim.step()
	var before := _physical(session)
	var prior_checkpoint := var_to_bytes(session.checkpoint())
	var prior_contexts := helper.context_calls
	rejecting[0] = true
	var result: Dictionary = session.restore_checkpoint(target)
	rejecting[0] = false
	check("restore revalidation actually rejects after native context preflight", not result.get("ok", false) \
		and calls[0] >= 2 and helper.context_calls >= prior_contexts + 2)
	check("rejected restore rolls back mock native owner, state and context", _physical(session) == before \
		and var_to_bytes(session.checkpoint()) == prior_checkpoint and session._native_stage == helper \
		and helper.owns_stage(session) and helper.last_context.aux == session.sim.aux \
		and helper.last_context.inputs == session.sim.inputs and helper.last_context.time == session.sim.time() \
		and helper.last_context.power == session.power and not session.sim.paused)
	var old_tick: int = session.sim.tick
	session.sim.step()
	check("mock native session advances after rejected restore", session.sim.tick == old_tick + 1 \
		and session.sim.fault_reason.is_empty() and helper.owns_stage(session))
	session.free()


func _restore_validator_mutation() -> void:
	var session := _session(NativeStage.BACKEND_NATIVE)
	var model: RefCounted = session.sim.model
	model.aux_size = session.sim.aux.size()
	model.continuous_size = session.sim.continuous.size()
	model.modes_size = session.sim.modes.size()
	model.state_layout_identity = "helicopter-native-restore-mutation-v1"
	var rejecting := [false]
	var attempts := [0]
	model.state_validator = func(_frame: Dictionary, context: Dictionary) -> bool:
		if rejecting[0] and context.tick == 0:
			attempts[0] += 1
			session.sim.mass += 1.0
			return false
		return true
	check("restore mutation fixture resets", session.reset(), session.start_error)
	if not native_available: _attach_mock_stage(session)
	var helper: RefCounted = session._native_stage
	check("restore mutation fixture owns its evaluator", helper != null and helper.owns_stage(session) \
		and helper.configuration_matches(session), str(session.stage_backend_status()))
	if helper == null:
		session.free()
		return
	var target: Dictionary = session.checkpoint()
	check("restore mutation fixture has a checkpoint", not target.is_empty())
	for _i: int in 4: session.sim.step()
	var before := _physical(session)
	var old_checkpoint := var_to_bytes(session.checkpoint())
	var old_mass: float = session.sim.mass
	var prior_stats: Dictionary = helper.stage_stats() if native_available and helper != null else {}
	var signals := [0]
	session.resetting.connect(func() -> void: signals[0] += 1)
	rejecting[0] = true
	var result: Dictionary = session.restore_checkpoint(target)
	rejecting[0] = false
	check("mutating restore validator was rejected without publication", not result.get("ok", false) \
		and attempts[0] > 0 and signals[0] == 0 and session.sim.mass == old_mass)
	check("mutating restore rolls back state and native guard", _physical(session) == before \
		and var_to_bytes(session.checkpoint()) == old_checkpoint and session._native_stage == helper \
		and helper != null and helper.owns_stage(session) and helper.configuration_matches(session),
		str(session.stage_backend_status()))
	var old_tick: int = session.sim.tick
	session.sim.step()
	var covered := true
	if native_available and helper != null:
		var stats: Dictionary = helper.stage_stats()
		covered = int(stats.get("stage_calls", 0)) - int(prior_stats.get("stage_calls", 0)) >= 4 \
			and int(stats.get("context_calls", 0)) - int(prior_stats.get("context_calls", 0)) >= 1
	check("native-owned flight continues after mutating restore refusal", session.sim.tick == old_tick + 1 \
		and session.sim.fault_reason.is_empty() and helper.owns_stage(session) and covered,
		str(session.stage_backend_status()))
	session.free()


func _run() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	check("field fixture", loaded.get("ok", false))
	if not loaded.get("ok", false):
		_finished = true
		quit(1)
		return
	field = loaded.field
	var status: Dictionary = NativeStage.library_status()
	native_available = status.get("ok", false)
	_selection()
	_reset_rollback()
	_reset_observer_reentry()
	_restore_observer_reentry()
	_mock_native_publication()
	_publication_hold()
	_mock_native_restore_rollback()
	_restore_validator_mutation()
	if native_available:
		_native_lifecycle("airborne")
		_native_lifecycle("ground")
		_transitions()
		_guard()
	else:
		var fallback := _session(NativeStage.BACKEND_NATIVE)
		check("unavailable native library falls back explicitly", fallback.stage_backend_identity() == NativeStage.reference_identity() \
			and not fallback.stage_backend_error.is_empty() and fallback.is_flyable(), str(status))
		fallback.free()
	_native_exercised = native_available and _native_tapes == 8 and failures == 0 and checks > 0
	if _native_exercised: print("NK3_NATIVE_HELICOPTER_NATIVE verdict=pass")
	_finished = true
	print("NK-3 helicopter native session: %d checks, %d failures, native exercised=%s" % [checks, failures, _native_exercised])
	quit(1 if failures else 0)
