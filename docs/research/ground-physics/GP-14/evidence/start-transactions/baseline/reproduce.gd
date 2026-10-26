## Read-only audit of current remaining reset routes; fault injections only in disposable subclasses/callbacks.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Field := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Weather := preload("res://physics/wind_config.gd")
var checks := 0
var failed := 0
var folder := ""
var field: Dictionary
var spot: Dictionary
var receipts: Array = []

class FaultFlight extends "res://sim/flight_session.gd":
	var refuse_evaluator := false
	var refuse_trim := false
	var reject_reload_candidate := false
	var reload_commits := 0
	func _wheel_evaluate(s: PackedFloat64Array, x: PackedFloat64Array, t: float) -> Dictionary:
		return {} if refuse_evaluator else super._wheel_evaluate(s, x, t)
	func _refit_selected_trim() -> Dictionary:
		return {ok = false, message = "audit injected detached trim refusal"} if refuse_trim else super._refit_selected_trim()
	func _commit_aircraft(prepared: Dictionary) -> void:
		super._commit_aircraft(prepared)
		if reject_reload_candidate:
			reload_commits += 1
			refuse_evaluator = reload_commits == 1 # Restored old callbacks evaluate normally.

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failed += 1
		printerr("FAIL ", label)

func _initialize() -> void: call_deferred("_run")

func session(ticks := 3) -> Node:
	var f := FaultFlight.new()
	f.input_enabled = false
	f.crash_auto_restart = false
	f.setup()
	check("actual field installs", f.set_field(field))
	for i: int in ticks: f.sim.step()
	check("actual initial checkpoint", not f.checkpoint().is_empty())
	return f

func view(f: Node) -> PackedByteArray:
	return var_to_bytes([f.checkpoint(), f.aircraft, f.start, f.trims, f.commands, f.raw,
		f.sim.paused, f.pause_reason, f.start_error, f._launch_metadata, f.holds,
		f._weather_pending_reset, f._shaft_pending_reset, f._gear_requested_down, f._flap_requested])

func begin(f: Node, name: String) -> Dictionary:
	var writer := Log.new(f)
	check(name + " actual recorder starts", writer.start(folder.path_join(name + ".orfl")) == OK)
	var signals := [0, 0, 0, 0]
	f.resetting.connect(func(): signals[0] += 1)
	f.sim.stepped.connect(func(_k, _t, _s, _l, _i, _a): signals[1] += 1)
	f.sim.faulted.connect(func(_why): signals[2] += 1)
	f.statistics_lifecycle.connect(func(_r): signals[3] += 1)
	return {writer = writer, signals = signals, before = view(f), checkpoint = f.checkpoint(),
		tick = f.sim.tick, generation = f.statistics_generation, aircraft_bytes = var_to_bytes(f.aircraft),
		commands = var_to_bytes(f.commands), model = f.sim.model}

func record(f: Node, setup: Dictionary, name: String, result: Variant) -> Dictionary:
	var r := {case = name, result = result, signals = setup.signals.duplicate(),
		old_tick = setup.tick, tick = f.sim.tick, generation_delta = f.statistics_generation - setup.generation,
		old_full_view_retained = setup.before == view(f), old_checkpoint_retained = var_to_bytes(setup.checkpoint) == var_to_bytes(f.checkpoint()),
		checkpoint_available = not f.checkpoint().is_empty(), recording = setup.writer.recording,
		aircraft_retained = setup.aircraft_bytes == var_to_bytes(f.aircraft), commands_retained = setup.commands == var_to_bytes(f.commands),
		model_reference_retained = setup.model == f.sim.model, fault = f.sim.fault_reason,
		start_error = f.start_error, paused = f.sim.paused, mass = f.sim.mass,
		launch_choice = f._launch_metadata.get("launch_choice"), launch_kind = f._launch_metadata.get("launch_kind"),
		weather_pending = f._weather_pending_reset, shaft_pending = f._shaft_pending_reset}
	print("RESET_FOLLOWUP ", JSON.stringify(r))
	receipts.append(r)
	setup.writer.stop("audit cleanup")
	return r

func _run() -> void:
	Engine.physics_ticks_per_second = 240
	folder = ProjectSettings.globalize_path("res://../tmp/gp-reset-followup/artifacts-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	field = Field.load_from().field
	spot = GroundStart.threshold(field)
	_airborne()
	_reload()
	_restore()
	_config()
	_runway_refit_prefix()
	_fallback()
	var report := FileAccess.open(folder.path_join("observations.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({scope = "Observed current behavior; passing assertions reproduce known defects and controls, not corrected production acceptance", checks = checks, failed = failed, observations = receipts}, "\t", true, true))
	report.close()
	print("Remaining reset audit: %d checks, %d failed; %s" % [checks, failed, folder])
	quit(1 if failed else 0)

func _airborne() -> void:
	for failure: String in ["trim", "evaluator"]:
		var f := session()
		var b := begin(f, "airborne-" + failure)
		f.refuse_trim = failure == "trim"
		f.refuse_evaluator = failure == "evaluator"
		f.reset()
		var r := record(f, b, "airborne-" + failure, "reset() returns void")
		check("airborne refusal closes before failure " + failure, r.signals[0] == 1 and not r.recording and not r.old_checkpoint_retained
			and not r.checkpoint_available and r.generation_delta == 0 and not r.fault.is_empty())
		f.free()

func _reload() -> void:
	var f := session()
	f.commands.roll = 0.2
	f.engine_running = false
	var b := begin(f, "reload-late-refusal")
	f.reject_reload_candidate = true
	var result: String = f.reload()
	var r := record(f, b, "reload-late-refusal", result)
	check("late failed reload restores physical/commands but closes recorder", result.begins_with("reload failed; previous aircraft")
		and r.old_checkpoint_retained and r.aircraft_retained and r.commands_retained and r.signals[0] == 1 and not r.recording and r.generation_delta == 0)
	f.free()
	f = session()
	f.start_choice = Flight.START_RUNWAY
	b = begin(f, "reload-runway-refused-candidate")
	f.reject_reload_candidate = true
	result = f.reload()
	r = record(f, b, "reload-runway-refused-candidate", result)
	check("reload calls a refused runway candidate success without physical commit", result.begins_with("aircraft reloaded:")
		and r.signals == [0, 0, 0, 1] and r.recording and r.generation_delta == 1 and not r.start_error.is_empty())
	f.free()
	f = session()
	f.start_choice = Flight.START_RUNWAY
	b = begin(f, "reload-committed-observer-fault")
	f.resetting.connect(func(): f.sim.mass = 0.0, CONNECT_ONE_SHOT)
	result = f.reload()
	r = record(f, b, "reload-committed-observer-fault", result)
	check("reload rolls back after already published physical runway commit", result.begins_with("reload failed; previous aircraft")
		and r.old_checkpoint_retained and r.signals[0] == 1 and r.signals[1] == 1 and not r.recording and r.generation_delta == 0)
	f.free()

func _restore() -> void:
	var f := session(0)
	var target: Dictionary = f.checkpoint()
	for i: int in 3: f.sim.step()
	var b := begin(f, "restore-listener-refusal")
	f.resetting.connect(func(): f.sim.mass = 0.0, CONNECT_ONE_SHOT)
	var result: bool = f.restore_checkpoint(target)
	var r := record(f, b, "restore-listener-refusal", result)
	check("restore refusal after publication loses recorder/valid configuration", not result and r.tick == b.tick and r.signals[0] == 1
		and not r.recording and not r.checkpoint_available and r.mass == 0.0)
	f.free()

func _config() -> void:
	var f := session(0)
	var b := begin(f, "weather-listener-mutation")
	f.resetting.connect(func(): f.sim.mass = 0.0, CONNECT_ONE_SHOT)
	var result: bool = f.setup_weather(Weather.preset("gentle-practice"))
	var r := record(f, b, "weather-listener-mutation", result)
	check("accepted weather config has unguarded observer mutation", result and not r.recording and r.mass == 0.0 and r.fault.is_empty() and r.weather_pending)
	f.free()
	f = session(0)
	b = begin(f, "config-rejection-control")
	result = f.setup_weather({})
	r = record(f, b, "config-rejection-control", result)
	check("malformed config refuses before publication", not result and r.old_checkpoint_retained and r.recording and r.signals == [0, 0, 0, 0])
	f.free()
	f = session(0)
	b = begin(f, "shaft-listener-mutation")
	f.resetting.connect(func(): f.sim.mass = 0.0, CONNECT_ONE_SHOT)
	result = f.setup_shaft_integrator("coupled-rk4")
	r = record(f, b, "shaft-listener-mutation", result)
	check("stock no-shaft configuration refusal stays before publication", not result and r.recording and r.old_checkpoint_retained and r.signals == [0, 0, 0, 0])
	f.free()

func _runway_refit_prefix() -> void:
	var f := session()
	f.start_choice = Flight.START_RUNWAY
	f.trim_throttle = 0.0 # Invalid candidate selection; the previously accepted flight remains valid before reset.
	var b := begin(f, "runway-refit-prefix")
	f.reset()
	var r := record(f, b, "runway-refit-prefix", "reset() returns void")
	check("runway rejected trim prefix invalidates accepted start without publication", r.signals == [0, 0, 0, 0]
		and r.tick == b.tick and r.recording and not r.checkpoint_available and r.fault.is_empty() and not f.start.ok)
	f.free()

func _fallback() -> void:
	for refuse: bool in [false, true]:
		var f := session()
		var b := begin(f, "fallback-" + str(refuse))
		f.refuse_evaluator = refuse
		var result: bool = f.reset_on_runway(NAN, spot.east, spot.heading)
		var r := record(f, b, "fallback-" + str(refuse), result)
		if not refuse:
			check("intentional successful airborne fallback remains a physical commit", not result and f.runway_start_outcome.fallback == "trimmed_airborne"
				and r.signals[0] == 1 and r.signals[1] == 1 and r.generation_delta == 1 and r.checkpoint_available)
		else:
			check("refused fallback still closes old recorder", not result and f.runway_start_outcome.fallback == "failed"
				and r.signals[0] == 1 and not r.recording and not r.checkpoint_available and r.generation_delta == 0)
		f.free()
