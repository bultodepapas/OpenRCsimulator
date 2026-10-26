## Accepted restore publication; existing parser, paused replay and old-writer boundaries.
extends SceneTree
const Sim := preload("res://sim/simulation.gd")
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Statistics := preload("res://statistics/service.gd")
const Weather := preload("res://physics/wind_config.gd")
const Field := preload("res://data/field_loader.gd")
# Captured with the pre-promotion direct restore at checks/default-before.
const LEGACY_RESTORE_SHA256 := "02734db2f127b76f3220938e693b4a3ab92f25d25975c679064fa1360fd68032"
var checks := 0
var failed := 0
var output := ""

func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed: failed += 1; printerr("FAIL ", label, " ", detail)

func _initialize() -> void: call_deferred("_run")

func body(x := 0.0) -> PackedFloat64Array:
	return PackedFloat64Array([x, 0.0, -30.0, 10.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

func kernel(script: Script = Sim) -> Node:
	var sim: Node = script.new()
	check("generic initial frame", sim.reset(body()))
	return sim

func flight(endpoint := false) -> Node:
	var f := Flight.new()
	f.input_enabled = false
	f.crash_auto_restart = false
	f.setup()
	check("actual field installs", f.set_field(Field.load_from().field))
	if endpoint:
		f.sim.model.aux_size = f.sim.aux.size()
		f.sim.model.continuous_size = f.sim.continuous.size()
		f.sim.model.modes_size = f.sim.modes.size()
		f.sim.model.state_layout_identity = "restore-publication-fixture-v1"
		check("actual endpoint fixture", f.sim.reset(f.sim.state.duplicate()))
	return f

func raw(f: Node) -> PackedByteArray:
	return var_to_bytes([f.checkpoint(), f.commands, f.raw, f.holds, f.sim.paused,
		f.pause_reason, f.start_error, f._launch_metadata, f.input_enabled, f.weather_configuration(),
		f.fuel_start_fill, f.failure_status()])

func begin(f: Node, name: String) -> Dictionary:
	var writer := Log.new(f)
	var path := output.path_join(name + ".orfl")
	check(name + " writer starts", writer.start(path) == OK)
	var signals := [0, 0, 0, 0]
	f.resetting.connect(func(): signals[0] += 1)
	f.sim.paused_changed.connect(func(_p): signals[1] += 1)
	f.sim.stepped.connect(func(_k, _t, _s, _l, _i, _a): signals[2] += 1)
	f.statistics_lifecycle.connect(func(_r): signals[3] += 1)
	return {writer = writer, path = path, signals = signals, before = raw(f), model = f.sim.model,
		checkpoint = f.checkpoint(), generation = f.statistics_generation}

func _run() -> void:
	Engine.physics_ticks_per_second = 240
	output = ProjectSettings.globalize_path("res://../tmp/restore-publication-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output)
	_kernel()
	_refusals()
	_validation_reentry()
	_old_writer()
	_observer_faults()
	_weather_failure_continuation()
	_noncredit_branch()
	print("Restore publication: %d checks, %d failed; %s" % [checks, failed, output])
	quit(1 if failed else 0)

func _kernel() -> void:
	var current := kernel()
	var target: Dictionary = current.checkpoint()
	var after_order := []
	current.paused_changed.connect(func(_p): after_order.append(current.tick))
	for i: int in 3: current.step()
	check("empty restore hook retains legacy acceptance", current.restore_checkpoint(target))
	check("empty hook retains explicit legacy pause order", after_order == [0] and current.paused)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(current.checkpoint()))
	check("empty restore hook frozen legacy checkpoint bytes", digest.finish().hex_encode() == LEGACY_RESTORE_SHA256)
	current.free()
	var freed := Node.new()
	var freed_call := Callable(freed, "get_instance_id")
	freed.free()
	for callback: Callable in [Callable(self, "missing_hook"), freed_call, func(_required): pass]:
		current = kernel()
		target = current.checkpoint()
		current.step()
		var before := var_to_bytes([current.checkpoint(), current.paused])
		check("invalid hook refuses before state/pause publication", not current.restore_checkpoint(target, callback)
			and before == var_to_bytes([current.checkpoint(), current.paused]))
		current.free()
	current = kernel()
	target = current.checkpoint()
	current.step()
	var order := []
	current.paused_changed.connect(func(_p): order.append("pause"))
	current.stepped.connect(func(_k, _t, _s, _l, _i, _a): order.append("sample"))
	var core := current
	check("generic committed restore hook", current.restore_checkpoint(target, func():
		check("restore frame installed before hook", core.tick == 0 and core.state[0] == 0.0)
		order.append("hook")))
	check("hook before automatic pause with no stepped", order == ["hook", "pause"] and current.paused)
	current.free()
	for kind: String in ["mass", "model", "array", "step", "reset", "restore", "pause-reentry", "pause-unpause", "fault-reentry", "fault-mutation"]:
		current = kernel()
		target = current.checkpoint()
		current.step()
		core = current
		var samples := [0]
		current.stepped.connect(func(_k, _t, _s, _l, _i, _a): samples[0] += 1)
		if kind == "pause-reentry": current.paused_changed.connect(func(_p): core.step())
		if kind == "pause-unpause": current.paused_changed.connect(func(p):
			if p: core.set_paused(false))
		if kind == "fault-reentry": current.faulted.connect(func(_why): core.reset(body(999.0)))
		var faults := [0]
		current.faulted.connect(func(_why): faults[0] += 1)
		if kind == "fault-mutation": current.faulted.connect(func(_why):
			core.mass = 0.0
			core.model.input_size = 8
			core.state[0] = 999.0)
		var callback := func():
			match kind:
				"mass", "fault-reentry", "fault-mutation": core.mass = 0.0
				"model": core.model.input_size = 8
				"array": core.state[0] = 999.0
				"step": core.step()
				"reset": core.reset(body(999.0))
				"restore": core.restore_checkpoint(target)
		check("observer violation keeps restore acceptance " + kind, current.restore_checkpoint(target, callback))
		check("restored protected frame stays paused/faulted " + kind, current.tick == 0 and current.state[0] == 0.0
			and current.mass == 1.0 and current.model.input_size == 4 and current.paused and not current.fault_reason.is_empty() and samples[0] == 0
			and faults[0] == 1)
		current.free()

func _refusals() -> void:
	for kind: String in ["format", "mass", "contact"]:
		var f := flight()
		var target: Dictionary = f.checkpoint()
		for i: int in 3: f.sim.step()
		var b := begin(f, "refusal-" + kind)
		var bad: Dictionary = target.duplicate(true)
		match kind:
			"format": bad.format = "unsupported-checkpoint"
			"mass": bad.simulation.mass = NAN
			"contact": bad.contact_state.tick = 99
		check("candidate refuses " + kind, not f.restore_checkpoint(bad))
		check("candidate keeps exact old owner/model/writer " + kind, raw(f) == b.before and f.sim.model == b.model
			and b.signals == [0, 0, 0, 0] and b.writer.recording and f.statistics_generation == b.generation)
		check("refusal clears transaction context " + kind, not f._reset_transaction_active and f.reset_closing_context().is_empty())
		b.writer.stop("refusal cleanup")
		f.free()
	for selector: Variant in [null, true, 1, 1.5, [], {}, &"openrc-flight-checkpoint v1"]:
		var f := flight()
		var target: Dictionary = f.checkpoint()
		for i: int in 3: f.sim.step()
		var b := begin(f, "format-type-" + str(typeof(selector)))
		target.format = selector
		check("primitive/Array/Dictionary/StringName format refuses quietly", not f.restore_checkpoint(target))
		check("malformed format retains complete old boundary", raw(f) == b.before and b.writer.recording and b.signals == [0, 0, 0, 0]
			and f.statistics_generation == b.generation and f.sim.model == b.model)
		b.writer.stop("malformed selector cleanup")
		f.free()

func _validation_reentry() -> void:
	for kind: String in ["closing", "preflight", "final"]:
		var f := flight(true)
		var target: Dictionary = f.checkpoint()
		for i: int in 3: f.sim.step()
		var b := begin(f, "reentry-" + kind)
		var armed := [true]
		var calls := [0]
		f.sim.model.state_validator = func(_frame, context) -> bool:
			if armed[0] and context.tick == (3 if kind == "closing" else 0):
				calls[0] += 1
				if kind != "final" or calls[0] == 2:
					armed[0] = false
					f.hold("validator-must-not-leak")
			return true
		check("validator owner reentry refuses " + kind, not f.restore_checkpoint(target))
		check("validator keeps old full owner and recording " + kind, raw(f) == b.before and b.writer.recording
			and f.sim.model == b.model and b.signals == [0, 0, 0, 0] and f.statistics_generation == b.generation)
		if kind == "final": check("final restore validation armed after preflight", calls[0] == 2)
		b.writer.stop("validator cleanup")
		f.free()

func _old_writer() -> void:
	var f := flight()
	var target: Dictionary = f.checkpoint()
	for i: int in 3: f.sim.step()
	f.input_enabled = true
	var closing := {}
	f.resetting.connect(func():
		closing.merge(f.reset_closing_context(), true)
		f.hold("presentation-hold")) # Before the writer callback, on purpose.
	var b := begin(f, "old-writer")
	var wrong_pause := [false]
	f.sim.paused_changed.connect(func(_p):
		if b.writer.recording and f.sim.tick != b.checkpoint.simulation.tick and f.reset_closing_context().is_empty(): wrong_pause[0] = true)
	check("actual restore accepts with legitimate hold", f.restore_checkpoint(target))
	check("restore publication has no stepped and one branch receipt", b.signals == [1, 1, 0, 1] and f.statistics_generation == b.generation + 1)
	check("accepted paused replay owner semantics", f.sim.paused and not f.input_enabled and f._launch_metadata.launch_kind == "checkpoint_restore"
		and f._launch_metadata.launch_choice == "unknown" and f.sim.tick == 0 and f.sim.model == b.model)
	var read: Dictionary = Reader.inspect(b.path)
	check("old actual footer uses exact old full checkpoint", read.ok and not b.writer.recording
		and var_to_bytes(read.footer.checkpoint) == var_to_bytes(b.checkpoint) and var_to_bytes(closing.checkpoint) == var_to_bytes(b.checkpoint))
	var event_ticks := true
	for event: Dictionary in read.get("events", []): event_ticks = event_ticks and event.tick == b.checkpoint.simulation.tick
	check("old pause event never uses new clock", event_ticks and not wrong_pause[0])
	check("accepted context absent after notification", f.reset_closing_context().is_empty() and not f._reset_transaction_active)
	f.free()

func _observer_faults() -> void:
	for kind: String in ["mass", "restore", "pause-step"]:
		var f := flight()
		var target: Dictionary = f.checkpoint()
		for i: int in 3: f.sim.step()
		var b := begin(f, "observer-" + kind)
		if kind == "pause-step": f.sim.paused_changed.connect(func(_p): f.sim.step())
		else:
			f.resetting.connect(func():
				if kind == "mass": f.sim.mass = 0.0
				else: f.restore_checkpoint(target))
		check("faulted publication is accepted restore " + kind, f.restore_checkpoint(target))
		check("observer fault cannot roll back restored frame " + kind, f.sim.tick == 0 and f.sim.mass > 0.0 and f.sim.paused
			and not f.sim.fault_reason.is_empty() and not f.start_error.is_empty() and not b.writer.recording
			and b.signals[0] == 1 and b.signals[2] == 0 and b.signals[3] == 1 and f.statistics_generation == b.generation + 1)
		f.free()

func _weather_failure_continuation() -> void:
	var source := flight()
	check("turbulence selection", source.setup_weather(Weather.preset("turbulent")))
	source.reset()
	check("detached failure fixture selection", source.setup_failures({probability_percent = 100, include_catastrophic = false, notify = false}, 20261026))
	for i: int in 12: source.sim.step()
	var target: Dictionary = source.checkpoint()
	var old_failure: RefCounted = source._failures
	for i: int in 12: source.sim.step()
	var old_failure_snapshot := var_to_bytes(old_failure.snapshot())
	check("failure restore accepted", source.restore_checkpoint(target))
	check("old FailureRuntime never mutated by restore", source._failures != old_failure and var_to_bytes(old_failure.snapshot()) == old_failure_snapshot)
	check("restored weather/failure full checkpoint exact", var_to_bytes(source.checkpoint()) == var_to_bytes(target))
	var receiver := flight()
	check("fresh receiver adopts existing parsed weather/failure snapshot", receiver.restore_checkpoint(target))
	var exact := var_to_bytes(source.checkpoint()) == var_to_bytes(receiver.checkpoint())
	for i: int in 32:
		source.sim.step()
		receiver.sim.step()
		exact = exact and var_to_bytes(source.checkpoint()) == var_to_bytes(receiver.checkpoint())
	check("restored physical continuation exactly matches parsed source", exact)
	source.free()
	receiver.free()

func _noncredit_branch() -> void:
	var f := flight()
	var target: Dictionary = f.checkpoint()
	var service := Statistics.new()
	check("in-memory statistics", service.setup("", false))
	service.begin_activity(f, "jensen-das-ugly-stik-60", "restore fixture")
	for i: int in 300: f.sim.step()
	check("active flight established before restore", service.query().started == 1)
	var restarts: int = service.query().restarts
	check("active restore accepted", f.restore_checkpoint(target))
	var totals: Dictionary = service.query()
	f.resume()
	for i: int in 300: f.sim.step()
	var replayed: Dictionary = service.query()
	check("restore branch credits no flight/restart/M7/replayed time", replayed.started == totals.started and replayed.restarts == restarts
		and replayed.crashes == totals.crashes and replayed.airborne_seconds == totals.airborne_seconds)
	service.close()
	service.free()
	f.free()
