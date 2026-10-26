## Common Session start preparation, reload receipts and old recorder preservation.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Field := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Weather := preload("res://physics/wind_config.gd")
var checks := 0
var failed := 0
var field: Dictionary
var spot: Dictionary
var output := ""

class CandidateFlight extends "res://sim/flight_session.gd":
	var refuse_load_once := false
	var arm_reload := false
	var refit_reentry := false
	func _wheel_evaluate(s: PackedFloat64Array, x: PackedFloat64Array, t: float) -> Dictionary:
		if refuse_load_once:
			refuse_load_once = false
			return {}
		return super._wheel_evaluate(s, x, t)
	func _refit_selected_trim() -> Dictionary:
		if refit_reentry:
			refit_reentry = false
			reset()
		return super._refit_selected_trim()
	func _commit_aircraft(prepared: Dictionary) -> void:
		super._commit_aircraft(prepared)
		if arm_reload:
			arm_reload = false
			refuse_load_once = true

func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failed += 1
		printerr("FAIL ", label, " ", detail)

func _initialize() -> void: call_deferred("_run")

func session(ticks := 3, path := "res://data/aircraft/jensen_ugly_stik_60.json") -> Node:
	var f := CandidateFlight.new()
	f.input_enabled = false
	f.crash_auto_restart = false
	f.setup(path)
	check("actual field installs", f.set_field(field))
	for i: int in ticks: f.sim.step()
	check("actual fixture checkpoint", not f.checkpoint().is_empty())
	return f

func state(f: Node) -> PackedByteArray:
	# Rejection diagnostics are allowed to change; physical/provenance/input state is not.
	return var_to_bytes([f.checkpoint(), f.aircraft, f.start, f.trims, f.commands, f.raw,
		f.sim.paused, f.pause_reason, f._launch_metadata, f.holds, f.failure_status(),
		f._weather_pending_reset, f._shaft_pending_reset])

func begin(f: Node, name: String) -> Dictionary:
	var writer := Log.new(f)
	var path := output.path_join(name + ".orfl")
	check(name + " actual writer opens", writer.start(path) == OK)
	var signals := [0, 0, 0, 0]
	f.resetting.connect(func(): signals[0] += 1)
	f.sim.stepped.connect(func(_k, _t, _s, _l, _i, _a): signals[1] += 1)
	f.sim.faulted.connect(func(_why): signals[2] += 1)
	f.statistics_lifecycle.connect(func(_r): signals[3] += 1)
	return {writer = writer, path = path, before = state(f), checkpoint = f.checkpoint(),
		model = f.sim.model, generation = f.statistics_generation, signals = signals}

func refused(f: Node, b: Dictionary, label: String) -> void:
	check(label + " complete old state retained", state(f) == b.before)
	check(label + " old model object retained", f.sim.model == b.model)
	check(label + " no publication/fault/generation/close", b.signals == [0, 0, 0, 0]
		and f.statistics_generation == b.generation and b.writer.recording and f.sim.fault_reason.is_empty())
	check(label + " context flags cleared", not f._reset_transaction_active and f.reset_closing_context().is_empty())
	b.writer.stop("rejection fixture cleanup")

func _run() -> void:
	Engine.physics_ticks_per_second = 240
	output = ProjectSettings.globalize_path("res://../tmp/common-reset-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output)
	field = Field.load_from().field
	spot = GroundStart.threshold(field)
	_refusals()
	_reentry()
	_failure_rng()
	_reload()
	_observer_faults()
	_fallback()
	_boolean_probe_compatibility()
	_hand_launch_and_initial_failure()
	_exact_continuation()
	print("Common flight reset: %d checks, %d failed; %s" % [checks, failed, output])
	quit(1 if failed else 0)

func _refusals() -> void:
	for kind: String in ["airborne-load", "airborne-trim", "runway-trim"]:
		var f := session()
		if kind == "runway-trim": f.start_choice = Flight.START_RUNWAY
		if kind.ends_with("trim"): f.trim_throttle = 0.0
		var b := begin(f, kind)
		f.refuse_load_once = kind == "airborne-load"
		f.reset()
		check(kind + " explicit rejection reason", not f.start_error.is_empty())
		refused(f, b, kind)
		f.free()

func _reload() -> void:
	for runway: bool in [false, true]:
		var f := session()
		if runway: f.start_choice = Flight.START_RUNWAY
		f.commands.roll = 0.2
		f.engine_running = false
		var b := begin(f, "reload-refusal-" + str(runway))
		f.arm_reload = true
		var message: String = f.reload()
		check("refused reload never claims success " + str(runway), message.begins_with("reload failed; previous aircraft"), message)
		refused(f, b, "reload " + str(runway))
		f.free()
		f = session()
		if runway: f.start_choice = Flight.START_RUNWAY
		b = begin(f, "reload-success-" + str(runway))
		message = f.reload()
		check("accepted reload commits once " + str(runway), message.begins_with("aircraft reloaded:") and b.signals == [1, 1, 0, 1]
			and f.statistics_generation == b.generation + 1 and f.sim.tick == 0 and not b.writer.recording)
		var read: Dictionary = Reader.inspect(b.path)
		check("reload old footer exact " + str(runway), read.ok and var_to_bytes(read.footer.checkpoint) == var_to_bytes(b.checkpoint))
		f.free()

func _reentry() -> void:
	for route: String in ["refit", "airborne-prepare", "airborne-commit", "reload-preparation"]:
		var f := session()
		var calls := [0]
		if route != "refit":
			f.sim.model.aux_size = f.sim.aux.size()
			f.sim.model.continuous_size = f.sim.continuous.size()
			f.sim.model.modes_size = f.sim.modes.size()
			f.sim.model.state_layout_identity = "common-reset-reentry-fixture-v1"
			check("endpoint fixture reset", f.sim.reset(f.sim.state.duplicate()))
			for i: int in 3: f.sim.step()
		var b := begin(f, "reentry-" + route)
		var armed := [true]
		if route == "refit": f.refit_reentry = true
		else:
			f.sim.model.state_validator = func(_frame: Dictionary, context: Dictionary) -> bool:
				var target_tick: int = 3 if route == "reload-preparation" else 0
				if armed[0] and context.tick == target_tick:
					calls[0] += 1
					if route != "airborne-commit" or calls[0] == 2:
						armed[0] = false
						if route == "reload-preparation": f.reload()
						else: f.reset()
				return true
		if route == "reload-preparation":
			check("reload preflight refuses reentry", f.reload().begins_with("reload failed; previous aircraft"))
		else: f.reset()
		refused(f, b, route)
		if route == "airborne-commit": check("final airborne validator specifically exercised", calls[0] == 2)
		f.free()

func _failure_rng() -> void:
	var f := session(0)
	check("turbulent fixture selection", f.setup_weather(Weather.preset("turbulent")))
	f.reset()
	check("failure episode selection", f.setup_failures({probability_percent = 100, include_catastrophic = false, notify = false}, 20261026))
	for i: int in 12: f.sim.step()
	var original_failure: RefCounted = f._failures
	var b := begin(f, "failure-rng-refusal")
	f.refuse_load_once = true
	f.reset()
	refused(f, b, "failure and RNG")
	check("failed restart keeps original failure resource", f._failures == original_failure)
	f.free()

func _observer_faults() -> void:
	for route: String in ["airborne", "reload-airborne", "reload-runway", "fallback-airborne"]:
		var f := session()
		if route == "reload-runway": f.start_choice = Flight.START_RUNWAY
		var b := begin(f, "observer-fault-" + route)
		f.resetting.connect(func(): f.sim.mass = 0.0, CONNECT_ONE_SHOT)
		var message := ""
		if route.begins_with("reload"): message = f.reload()
		elif route.begins_with("fallback"): f.reset_on_runway(NAN, spot.east, spot.heading)
		else: f.reset()
		check("accepted observer fault is final " + route, b.signals == [1, 1, 1, 1] and f.sim.tick == 0
			and f.statistics_generation == b.generation + 1 and f.sim.mass > 0.0 and f.sim.paused and not f.sim.fault_reason.is_empty())
		check("observer fault cannot claim old flight retained " + route, not f.start_error.is_empty()
			and not b.writer.recording and f._launch_metadata.launch_choice != "failed"
			and (not route.begins_with("reload") or message.begins_with("aircraft reloaded: observer fault")), message)
		if route.begins_with("fallback"):
			check("accepted fallback fault reports physical acceptance and nonreadiness", f.runway_start_outcome.committed
				and not f.runway_start_outcome.ready and f.runway_start_outcome.fallback_status == "observer_fault"
				and f.start_error.contains("observer fault"))
		f.free()

func _boolean_probe_compatibility() -> void:
	var f := session()
	var b := begin(f, "boolean-probe")
	f.refuse_load_once = true
	var result: Variant = f._reset_airborne_start()
	check("existing technical helper keeps false Boolean on refusal", typeof(result) == TYPE_BOOL and not result)
	refused(f, b, "boolean probe")
	result = f._reset_airborne_start()
	check("existing technical helper keeps true Boolean on accepted reset", typeof(result) == TYPE_BOOL and result
		and f.sim.tick == 0 and not f.checkpoint().is_empty())
	f.free()

func _fallback() -> void:
	for refusal: bool in [false, true]:
		var f := session()
		var b := begin(f, "fallback-" + str(refusal))
		f.refuse_load_once = refusal
		var accepted_runway: bool = f.reset_on_runway(NAN, spot.east, spot.heading)
		check("legacy requested runway result remains false", not accepted_runway)
		if refusal:
			check("failed fallback remains explicit", f.runway_start_outcome.fallback == "failed")
			refused(f, b, "fallback")
		else:
			check("explicit successful fallback is one accepted replacement", f.runway_start_outcome.fallback == "trimmed_airborne"
				and b.signals == [1, 1, 0, 1] and f.statistics_generation == b.generation + 1 and not b.writer.recording
				and not f.checkpoint().is_empty() and f._launch_metadata.launch_kind == "airborne_fallback")
		f.free()

func _hand_launch_and_initial_failure() -> void:
	var f := session(0, "res://data/aircraft/skywalker_x8.json")
	f.start_choice = Flight.START_HAND_LAUNCH
	var b := begin(f, "hand-launch")
	f.reset()
	check("actual gearless hand launch uses common publication", b.signals == [1, 1, 0, 1]
		and f.statistics_generation == b.generation + 1 and f._launch_metadata.launch_kind == "hand_launch_release"
		and not f.checkpoint().is_empty())
	f.free()
	f = CandidateFlight.new()
	f.trim_throttle = 0.0
	f.input_enabled = false
	f.setup()
	check("initial invalid selection still parks an inert fault", f.sim.state.size() == 13 and f.sim.paused
		and not f.sim.fault_reason.is_empty() and not f.is_flyable() and f.statistics_generation == 0)
	f.free()

func _exact_continuation() -> void:
	var f := session()
	var reference := session()
	var b := begin(f, "exact-continuation")
	f.reset()
	reference.reset()
	var equal := var_to_bytes(f.checkpoint()) == var_to_bytes(reference.checkpoint())
	for i: int in 32:
		f.sim.step()
		reference.sim.step()
		equal = equal and var_to_bytes(f.checkpoint()) == var_to_bytes(reference.checkpoint())
	check("actual common reset and observed continuation byte exact", equal)
	f.free()
	reference.free()
